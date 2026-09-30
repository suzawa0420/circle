"""Exercise the production guard using a loopback-only, synthetic Nginx server."""
import http.client
import json
import pathlib
import re
import socket
import subprocess
import tempfile
import time

root = pathlib.Path(__file__).resolve().parents[2]
guard = root / 'ops/al2023/origin-guard.conf'
rails_ranges = set(re.findall(r'[0-9a-f:.]+/\d+', (root / 'lib/cloudflare_proxy.rb').read_text()))
nginx_ranges = set(re.findall(r'^    ([0-9a-f:.]+/\d+) 1;', guard.read_text(), re.M))
assert nginx_ranges - {'172.26.0.0/16', '127.0.0.1/32', '::1/128'} == rails_ranges

cases = [
    ('local', '127.0.0.1', '/', 'GET', None, 'circle-book.com', 200),
    ('direct', '203.0.113.2', '/', 'GET', None, 'circle-book.com', 403),
    ('direct_spoof', '203.0.113.2', '/', 'GET', '173.245.48.5', 'circle-book.com', 403),
    ('private_without_cf', '172.26.10.40', '/', 'GET', None, 'circle-book.com', 403),
    ('cf_ipv4', '172.26.10.40', '/', 'GET', '203.0.113.2, 173.245.48.5', 'circle-book.com', 200),
    ('cf_ipv6', '172.26.10.40', '/', 'GET', '203.0.113.2, 2606:4700::1', 'www.circle-book.com', 200),
    ('spoofed_first_hop', '172.26.10.40', '/', 'GET', '173.245.48.5, 203.0.113.2', 'circle-book.com', 403),
    ('wrong_host', '172.26.10.40', '/', 'GET', '173.245.48.5', 'attacker.example', 403),
    ('lb_health', '172.26.10.40', '/health', 'GET', None, '172.26.15.224', 200),
    ('lb_head', '172.26.10.40', '/health', 'HEAD', None, '172.26.15.224', 200),
    ('health_post', '172.26.10.40', '/health', 'POST', None, 'circle-book.com', 403),
    ('health_query', '172.26.10.40', '/health?x=1', 'GET', None, 'circle-book.com', 403),
    ('health_from_public', '203.0.113.2', '/health', 'GET', None, 'circle-book.com', 403),
    ('health_with_spoof', '172.26.10.40', '/health', 'GET', '203.0.113.2', 'circle-book.com', 403),
]
with tempfile.TemporaryDirectory(prefix='circle-nginx-test-') as directory:
    d = pathlib.Path(directory)
    config = d / 'nginx.conf'
    production = (root / 'ops/al2023/nginx.conf').read_text()
    log_format = production.split('    log_format circle escape=json', 1)[1].split(';', 1)[0]
    log_format = 'log_format circle escape=json' + log_format + ';'
    config.write_text(f'''pid {d}/nginx.pid;
error_log {d}/error.log;
events {{ worker_connections 32; }}
http {{
 {log_format}
 access_log {d}/access.log circle;
 map $circle_cf_allowed $circle_log_cf_client {{ default ""; 1 $http_cf_connecting_ip; }}
 client_body_temp_path {d}/client_body;
 proxy_temp_path {d}/proxy;
 fastcgi_temp_path {d}/fastcgi;
 uwsgi_temp_path {d}/uwsgi;
 scgi_temp_path {d}/scgi;
 include {guard};
 server {{
  listen 127.0.0.1:35441;
  set_real_ip_from 127.0.0.1;
  real_ip_header X-Circle-Test-Peer;
  location / {{ if ($circle_origin_deny) {{ return 403; }} return 200; }}
 }}
}}
''')
    command = ['nginx', '-e', str(d / 'error.log'), '-p', str(d), '-c', str(config)]
    result = subprocess.run(command + ['-t'], capture_output=True)
    assert result.returncode == 0, result.stderr.decode()
    process = subprocess.Popen(command + ['-g', 'daemon off;'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        for _ in range(30):
            assert process.poll() is None, (d / 'error.log').read_text()
            try:
                with socket.create_connection(('127.0.0.1', 35441), timeout=.2):
                    break
            except OSError:
                pass
            time.sleep(.1)
        for name, peer, path, method, xff, host, expected in cases:
            headers = {'Host': host, 'X-Circle-Test-Peer': peer, 'User-Agent': 'Google-Display-Ads-Bot \"test\"', 'CF-Ray': 'synthetic-ray', 'CF-Connecting-IP': '203.0.113.2'}
            if xff is not None:
                headers['X-Forwarded-For'] = xff
            connection = http.client.HTTPConnection('127.0.0.1', 35441, timeout=3)
            connection.request(method, path, headers=headers)
            response = connection.getresponse()
            assert response.status == expected, f'{name}: {response.status} != {expected}'
            response.read()
            connection.close()
        records = [json.loads(line) for line in (d / 'access.log').read_text().splitlines()]
        assert len(records) == len(cases)
        for record, case in zip(records, cases):
            assert record['status'] == case[-1]
            assert record['path'] == case[2].split('?')[0]
            assert record['origin_deny'] == ('1' if case[-1] == 403 else '0')
            assert record['ua'] == 'Google-Display-Ads-Bot "test"'
            assert record['cf_ray'] == 'synthetic-ray'
            assert record['time']
            assert 'x=1' not in json.dumps(record)
            assert record['cf_client'] == ('203.0.113.2' if record['private_peer'] == '1' and record['cf_hop'] == '1' and record['host_ok'] == '1' else '')
        print(f'ORIGIN_GUARD_TESTS_OK cases={len(cases)}')
    finally:
        process.terminate()
        process.wait(timeout=5)

"""Exercise the production guard using a loopback-only, synthetic Nginx server."""
import http.client
import pathlib
import re
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
    config.write_text(f'''pid {d}/nginx.pid;
error_log {d}/error.log;
events {{ worker_connections 32; }}
http {{
 access_log off;
 include {guard};
 server {{
  listen 127.0.0.1:35441;
  set_real_ip_from 127.0.0.1;
  real_ip_header X-Circle-Test-Peer;
  location / {{ if ($circle_origin_deny) {{ return 403; }} return 200; }}
 }}
}}
''')
    subprocess.run(['nginx', '-t', '-p', str(d), '-c', str(config)], check=True, capture_output=True)
    process = subprocess.Popen(['nginx', '-p', str(d), '-c', str(config), '-g', 'daemon off;'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        for _ in range(30):
            if (d / 'nginx.pid').exists():
                break
            time.sleep(.1)
        for name, peer, path, method, xff, host, expected in cases:
            headers = {'Host': host, 'X-Circle-Test-Peer': peer}
            if xff is not None:
                headers['X-Forwarded-For'] = xff
            connection = http.client.HTTPConnection('127.0.0.1', 35441, timeout=3)
            connection.request(method, path, headers=headers)
            response = connection.getresponse()
            assert response.status == expected, f'{name}: {response.status} != {expected}'
            response.read()
            connection.close()
        print(f'ORIGIN_GUARD_TESTS_OK cases={len(cases)}')
    finally:
        process.terminate()
        process.wait(timeout=5)

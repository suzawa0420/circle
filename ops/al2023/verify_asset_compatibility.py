#!/usr/bin/env python3
"""Read-only cross-target asset checks, run from a trusted private instance.

Example: --target old=172.26.10.40 --target new=172.26.15.224
Outputs aggregate statuses only; does not print response bodies or visitor data.
"""
import argparse
from collections import Counter
import html.parser
import http.client
import ipaddress
import json
import re
import urllib.parse


class Assets(html.parser.HTMLParser):
    def __init__(self, host):
        super().__init__()
        self.host = host
        self.paths = set()

    def handle_starttag(self, tag, attributes):
        a = dict(attributes)
        url = a.get('src') if tag == 'script' else a.get('href') if tag == 'link' and a.get('rel') == 'stylesheet' else None
        if url:
            path = local_asset(url, '/', self.host)
            if path:
                self.paths.add(path)


def local_asset(url, base, host):
    p = urllib.parse.urlsplit(urllib.parse.urljoin('https://' + host + base, url))
    if p.netloc in [host, 'www.' + host] and p.path.startswith('/assets/'):
        return p.path
    return None


def fetch(ip, path, host):
    c = http.client.HTTPConnection(ip, timeout=30)
    try:
        c.request('GET', path, headers={'Host': host, 'X-Forwarded-For': '198.51.100.7, 173.245.48.1', 'X-Forwarded-Proto': 'https'})
        r = c.getresponse()
        body = r.read(16 * 1024 * 1024 + 1)
        if len(body) > 16 * 1024 * 1024:
            raise ValueError('response too large')
        return r.status, body
    finally:
        c.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--target', action='append', required=True)
    parser.add_argument('--host', default='circle-book.com')
    args = parser.parse_args()
    targets = {}
    for item in args.target:
        label, ip = item.split('=', 1)
        if not re.fullmatch(r'[a-zA-Z0-9_-]+', label) or not ipaddress.ip_address(ip).is_private:
            parser.error('use a simple label and a private IP')
        targets[label] = ip
    paths = ['/', '/circles', '/admin_users/sign_in', '/members/sign_in', '/admin_users/sign_up', '/members/sign_up']
    failed = False
    for source, ip in targets.items():
        assets = set()
        for path in paths:
            status, body = fetch(ip, path, args.host)
            if status != 200:
                failed = True
            page = Assets(args.host)
            page.feed(body.decode('utf-8', 'replace'))
            assets.update(page.paths)
        pending = list(assets)
        checked_css = set()
        while pending:
            path = pending.pop()
            if not path.endswith('.css') or path in checked_css:
                continue
            checked_css.add(path)
            status, body = fetch(ip, path, args.host)
            if status != 200:
                failed = True
                continue
            for url in re.findall(r'url\(\s*[\'"]?([^\)\'"\s]+)', body.decode('utf-8', 'replace')):
                dependency = local_asset(url, path, args.host)
                if dependency and dependency not in assets:
                    assets.add(dependency)
                    pending.append(dependency)
            if len(assets) > 1000:
                raise ValueError('asset limit exceeded')
        if not assets:
            failed = True
        for target, address in targets.items():
            counts = Counter(str(fetch(address, path, args.host)[0]) for path in sorted(assets))
            failed |= any(status != '200' for status in counts)
            print(json.dumps({'source': source, 'target': target, 'assets': len(assets), 'statuses': dict(counts)}), flush=True)
    return int(failed)


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (OSError, ValueError, http.client.HTTPException):
        raise SystemExit('Compatibility check failed; response contents were not printed.')

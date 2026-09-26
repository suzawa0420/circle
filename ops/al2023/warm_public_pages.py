#!/usr/bin/env python3
"""Bounded GET-only warm-up, without response bodies, cookies or tokens in logs."""
import collections
import json
import subprocess
import time

paths = ["/health", "/", "/circles", "/events/badminton", "/places",
         "/admin_users/sign_in", "/admin_users/sign_up", "/members/sign_up",
         "/exhibition_groups/sign_up"]
counts = collections.Counter()
for iteration in range(8):
    for path in paths:
        for attempt in range(10):
            result = subprocess.run([
                "curl", "--unix-socket", "/var/www/circle/tmp/sockets/unicorn.sock",
                "-sS", "--max-time", "20", "-o", "/dev/null", "-w", "%{http_code}",
                "-H", "Host: circle-book.com", "-H", "X-Forwarded-Proto: https",
                "http://localhost" + path,
            ], capture_output=True, text=True)
            if result.returncode == 0:
                break
            # Only tolerate the initial boot/socket delay, not later failures.
            if iteration != 0 or path != "/health":
                raise SystemExit("Warm-up connection failed")
            time.sleep(1)
        if result.returncode or result.stdout != "200":
            raise SystemExit("Warm-up failed for " + path + ": " + result.stdout)
        counts[result.stdout] += 1
print(json.dumps({"warmup_status_counts": dict(counts)}))

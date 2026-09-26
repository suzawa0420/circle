# AL2023 runtime migration

## Current production topology (2026-09-26)

LoadBalancer-1 now serves **server4 + server5**. Both AL2023 targets pass
`/health`. Server2 and server3 were permanently deleted on 2026-09-26 after
explicit action-time approval, including server2 automatic snapshots. Existing
manual snapshots, transferred static IPs, the external DB and S3 were retained.

| Instance | Zone | Static public IP | Private IP | Application |
| --- | --- | --- | --- | --- |
| circle-book-web-server4 | Tokyo A | 18.176.169.209 | 172.26.15.224 | circle-puma + nginx |
| circle-book-web-server5 | Tokyo C | 54.95.19.169 | 172.26.21.101 | circle-puma + nginx |

Both retain the approved 8 GB / 2 vCPU / 160 GB plan. The existing static IPs
were transferred from server3/server2 with explicit user approval. Cloudflare
still points to the load balancer. Public HTTP IPv4/IPv6 is closed on both
instances; the private LB/Cloudflare origin guard remains enabled. HTTPS requests
directly to the LB, including spoofed forwarding headers, return 403.

### Performance and data checks

CarrierWave 3 Fog `empty?` performs an S3 HEAD request. Image URL generation and
stored-image presence checks now avoid it, while local/cached upload validation
retains its prior behavior. The regression suite has 9 tests / 17 assertions.
Each new server passed 64 GET checks; the last eight averaged 0.126 s on server4
and 0.110 s on server5. These bounded measurements are not a capacity guarantee.
The final master deployment (f3fcb7485, Actions run 36237085166) passed all jobs.
The following 901-second observation covered 5,786 requests with zero 5xx errors,
90 successful health checks and zero unexpected service restarts. Request p95
was 0.635 s on server4 and 0.748 s on server5. After deleting the old instances,
public home/health returned 200 and direct LB HTTPS returned 403.

Before deletion, `public/uploads` and `storage` contained the same 281 files on all four instances
(combined SHA256 cdf34902bb454f9098cb2c8b59b5eb02e20a03d5e9ecbedde8fe0fc379aad045).
The DB is outside the retiring instances and uploaded images use S3.
No production test writes, outbound test mail or DB migration were performed.

### Scheduled work

`circle-sitemap.service` completed successfully on server4. Only server4 has
`circle-sitemap.timer` enabled, daily at 15:00 UTC (00:00 JST). Both old sitemap
cron entries were disabled after saving a private crontab backup on each old
instance. Do not enable the timer on server5. The old Unicorn log-maintenance
cron is unnecessary for Puma, which logs via journald.

### Deployment and recovery

The updated `deploy_prod.yml` targets only the two static IPs above, with pinned
SSH host fingerprints. Existing GitHub deployment credentials are reused.
Runtime tests must pass; both instances prepare the exact tested commit and
retain old asset digests before one-at-a-time Puma hot restarts and public GET /
Turnstile readiness checks. Missing DB migrations stop deployment rather than
running automatically. Existing private production/Turnstile configuration is
preserved and is not copied into workflow logs.

Manual `check-al2023` verifies SSH and service state without changing production.
Manual `all` performs the complete verified deployment. Pushes to master use
the same path. Do not dispatch an older workflow
revision that still targets server2/server3.

For an application regression, revert the offending change with a new commit
and deploy it through the same checks; do not reset production Git history or
clobber assets. If one instance fails, detach that instance and keep the healthy
one serving while fixing it. The approved server4 snapshot used to create
server5 predates later application fixes; restoration requires applying the
current tested Git revision and rechecking configuration, origin guard, assets,
health and the singleton sitemap timer before attachment.

The remaining sections are **historical migration notes**. Earlier topology,
rollback state and approval requests are superseded by this section and live AWS
state. Never start the obsolete `circle-unicorn` service on the new runtime.

## Versions and compatibility

- Ruby 3.3.12 (security-supported 3.3 series; plan its next update before March 2027).
- Rails 8.1.4, Bundler 2.5.23.
- Node.js 24.21.0 LTS, npm 11.
- Keep `config.load_defaults 6.0` for existing cookie, serialization and DB compatibility during the cutover. New framework defaults are a separate migration.
- Preserve the database schema. This change does not add a data migration.
- Keep Sprockets and Bootstrap 3; use Rails-supplied Trix instead of a duplicate legacy gem.
- Replace removed ActiveModel error APIs and CarrierWave extension/filename APIs; explicitly allow only public Ransack fields.
- Drop unused Paperclip and the all-services AWS SDK dependency. Keep S3 and the official `aws-actionmailer-ses` adapter; configure `ses_settings` instead of the removed AWS Rails helper. Replace old Heroku middleware gems with Rails logging/static-file settings and Rack::Deflater.
- Explicit model annotations: `bundle exec annotaterb models` (no automatic source rewrites during migrations).

## New server preparation (completed 2026-09-26)

`circle-book-web-server4`, Tokyo zone A, AL2023, same 8 GB / 2 vCPU / 160 GB plan, 44 USD/month base price. Public HTTP IPv4/IPv6 is closed; SSH is retained. Not attached to the production load balancer.

Installed from Amazon Linux repositories: GCC/C++, make, OpenSSL/libyaml/readline/zlib/libffi/gdbm/ncurses development packages, Git, Nginx, ImageMagick, tar/gzip/xz.

Installed and version-verified:

- `/opt/circle/ruby-3.3.12`
- `/opt/circle/node-v24.21.0-linux-x64`
- Bundler 2.5.23

Official download SHA256 values verified before extraction:

- Ruby tar.gz: `b06d63beae271933033e27f0a389bc582a009e7845357d44365c39de525a051b`
- Node Linux x64 tar.xz: `fd8e59d5a511510f6a298afb548f18c7d2b1be404d8b4a27d94fbe49f56cb2d6`

## Verification and cutover gates

Production configuration was transferred directly from server3 to server4 into
`/home/ec2-user/circle-production-config`, with byte integrity and private file
permissions verified. The source-IP-limited, forced-command SSH grant was removed;
an authentication attempt after removal was rejected. A separate probe loaded these
settings and verified Rails boot, signing configuration, Turnstile configuration,
and a read-only production DB connection. No production traffic has been moved.

The templates in this directory are for server4 only:

- `nginx.conf`: port 80, 20 MB uploads, Unix socket upstream, health routed to Rails.
- `origin-guard.conf`: private LB + final Cloudflare XFF hop + exact site hostname;
  exact GET/HEAD `/health` without XFF is allowed for private LB health probes.
- `circle-unicorn.service`: the installed Ruby/Node paths, graceful stop, nginx group socket access.
- `test_origin_guard.py`: real Nginx, loopback-only synthetic listener, 14 request
  cases covering spoofed headers, host checks, IPv4/IPv6 and health exceptions.
  Its test-only real-IP header is never part of the production template.

Keep the existing master deployment workflow unchanged during preparation: it
still targets AL2. Do not merge this branch until its targets and the remaining
AL2 server are reconciled. Existing scheduled tasks stay on the old server until
their role is reviewed, preventing duplicate execution on server4.

Prepared on server4 (services are still stopped):

- Application: `/var/www/circle`; the previous check directory is a symlink here.
- Eight configuration links point to the private transferred files, outside Git.
- `/etc/nginx/nginx.conf` and `/etc/nginx/circle-origin-guard.conf` installed;
  the packaged default is backed up as `/etc/nginx/nginx.conf.before-circle`.
- `/etc/systemd/system/circle-unicorn.service` installed and unit syntax checked.
- Nginx syntax and the 14 guard cases pass. All nine read-only production page
  probes return 200. S3 HeadBucket and SES GetSendQuota succeed; no image or email
  was submitted by these checks.

### Proposed activation (requires specific production approval)

Use the exact reviewed commit on `codex/al2023-runtime-upgrade`, on server4 only.
Compile and verify production assets as `ec2-user` with group `nginx` and umask
0007. Keep asset directories group-readable. Do not run a database migration.
Start `circle-unicorn` and Nginx; require local HTTP checks, a healthy private
`/health`, working static assets, and rejection of untrusted forwarded headers.
Only after these checks attach server4 to `LoadBalancer-1`. Keep server2 and
server3 attached while observing errors and latency for at least 15 minutes.
Detach server3 only after this canary check succeeds. Its scheduled jobs and
instance remain running until separately reviewed; server2 remains unchanged.

Rollback on health failure, repeated new 5xx responses, broken account pages,
or failed origin protection: detach server4, reattach server3 if necessary,
verify both old targets healthy, and stop the new services. The database schema
and existing targets are unchanged, so rollback does not require data restoration.
Do not move the static IP, change DNS, merge master, or delete any old instance
as part of this activation.

The runtime workflow uses disposable PostgreSQL 17 and synthetic accounts; it never connects to production. It checks eager loading, permissions, public pages, password login/logout, date validation, image processing and extension rejection, spam/Turnstile regressions, assets and the Unicorn readiness script.

Before production traffic:

1. Reconcile any subsequent master changes; rerun CI on the exact commit.
2. Confirm real DB server location/version, backups, upload storage and scheduled jobs. The old server's `psql 12.18` identifies the client only.
3. Have the operator provision production environment variables and Rails/Turnstile configuration directly on the new server without exposing secret values to Codex or chat. Preserve the existing signing keys during parallel operation. Do not create a new production database or run migrations implicitly.
4. Apply and verify the existing Nginx origin guard and private `/health` exception. Confirm direct LB traffic is rejected, Cloudflare traffic works, and the private health check succeeds.
5. Build assets and run the app on the new server before attaching it to the load balancer. Exercise login, image upload, registration/Turnstile, reviews and mail using agreed test accounts.
6. Update deployment to target the exact new runtime paths; the existing `~/.rbenv` commands target the old installation.
7. Attach the tested server, verify LB health and real routes, then retire one old server at a time. Keep the old servers and DB schema unchanged for rollback. Route traffic back to old servers if checks fail.
8. Stop duplicate scheduled jobs before enabling their replacements. Delete old instances only after explicit approval; stopping alone does not remove their charges.

## Sources

- https://www.ruby-lang.org/en/news/2026/07/16/ruby-3-3-12-released/
- https://guides.rubyonrails.org/maintenance_policy.html
- https://nodejs.org/en/about/previous-releases

### 2026-09-26 canary rollback: mixed-version assets

Commit `f3ef41ffd` was started on server4 and briefly attached to LoadBalancer-1.
Health, principal pages, local assets, origin rejection and both CI runs passed.
The canary was rolled back before retiring server3: the old page referenced five
local assets; server4 returned 301 for three and 404 for two. Conversely, all five
new page assets returned 404 on server3. Per-server smoke checks alone do not
establish compatibility when the load balancer can send HTML and assets to
different runtime versions. A 301 is not accepted as proof of a valid static asset.

Before another canary, distribute the union of fingerprinted public assets from
all participating versions to **server2, server3 and server4**. This is an
additional production scope beyond the prior server4-only approval. It changes
only public compiled files, not application code, manifests, secrets, database,
cron, origin guards, or old-server services. No new paid service is needed.

1. Create private staging directories containing only each server's public
   fingerprinted assets. Transfer these via an operator-approved existing secure
   channel. Never expose a temporary HTTP file server or include app configuration.
2. Run `python3 sync_assets.py STAGED_ASSETS /var/www/circle/public/assets` on each
   destination. This previews additions and fails before writing if a digest path
   exists with different contents or any symlink/unfingerprinted file is present.
3. Once the added scope is approved, repeat with `--apply` for each staged version
   on each server. Existing bytes and each server's Sprockets manifest stay intact.
   New files publish atomically and can be served without restarting old services.
   Verify nginx traversal/read access if staging created new directories.
4. While server4 is still detached, run `verify_asset_compatibility.py` on a
   private instance with all three `--target LABEL=PRIVATE_IP` arguments. It checks
   six pages and same-origin CSS/JS plus CSS dependencies against every target.
   Require **every asset to return 200**, and verify representative public pages.
5. Repeat health/origin checks, then attach server4. Observe at least 15 minutes;
   detach server3 only if all compatibility and runtime checks stay healthy.
   On failure detach server4 and keep server2/server3 serving; the extra immutable
   files can remain for cached pages, so no destructive cleanup is required.

`test_sync_assets.py` verifies dry-run behavior, idempotency, manifest preservation,
collision refusal before any write, symlink refusal, and non-asset rejection.
Do not run assets:clobber, cleanup old digests, overwrite a manifest, or merge this
branch into the existing AL2 deployment workflow during this transition.

### 2026-09-26 second canary: Rack 3 HTTP headers

Public assets were synchronized at `b12008232`: 285 new files on each old
server and 665 old files on server4. Existing bytes and manifests were preserved.
All 171 cross-server asset probes returned 200. The old servers' 53 different
gzip encodings were checked to decompress identically.

After adding server4, the live monitor detected two HTTP 500 responses within
210 seconds. The first corresponds to Unicorn 6.1.0 applying `=~` to an Array
header value; Rack 3 uses arrays for multiple response headers (including cookies).
Another NoMethodError came from an unknown event slug in TagsController.
The canary was rolled back before detaching server3. No DB changes were made.

The next candidate uses the already locked **Puma 7.2.1** on server4 only:

- `puma.rb`: eight workers, one application thread per worker, matching the
  existing concurrency without newly introducing concurrent application threads.
  It preloads the app and reconnects Active Record in each worker.
- Keep the existing private `tmp/sockets/unicorn.sock` name for Nginx compatibility,
  with explicit `umask=0007`; no new TCP listener or public firewall opening.
- `circle-puma.service`: the same ec2-user/nginx identity and runtime paths,
  foreground operation, graceful SIGTERM, and restart-on-failure.
- Invalid tag event/prefecture/city lookups return 404 rather than dereferencing
  nil. Existing redirects for mismatched prefectures return immediately.
- `test/runtime/puma_http_test.rb` exercises real local HTTP responses with
  multiple cookies and redirects, plus the production configuration. Rails
  integration tests cover unknown tag slugs. Both run in CI.

#### Next deployment (new production approval required)

Use the newly reviewed exact commit on `codex/al2023-runtime-upgrade`.
Keep server2/server3 attached and serving throughout preparation; server4 must
remain detached. Do not merge master or run a database migration.

1. Pull the approved commit on server4, retain its private config links and all
   existing compiled assets. No asset source or dependency change is needed for
   this fix; verify the current manifest/assets without rebuilding them.
2. With Unicorn and Nginx stopped, install `circle-puma.service`, daemon-reload,
   disable `circle-unicorn`, and enable/start `circle-puma` and Nginx. Never run
   both app servers on the shared socket. Verify service state, socket ownership
   and permissions, health, account pages and the origin guard.
3. Run the real HTTP cookie regression using synthetic data and no production
   Rails boot; verify all-server asset compatibility again. No test accounts,
   posts or email should be created in production.
4. Attach server4 only after these checks pass. Start a fresh monitor of
   `circle-puma` + `nginx`, counting 5xx, asset failures and health failures.
   Observe at least 15 minutes after AWS marks server4 healthy. Inspect any 403
   to distinguish origin rejection from failed legitimate asset requests.
5. Detach server3 only after a successful canary. Preserve its instance/cron and
   keep server2 attached. No DNS or plan changes and no planned site downtime.

Rollback: detach server4, keep or reattach server3, require server2/server3 health
and public-page success, then stop Puma/Nginx on server4. No DB restore is needed.
Never restart the incompatible Unicorn service with the new Rails runtime.

References: [Rack 3 header changes](https://github.com/rack/rack/blob/main/UPGRADE-GUIDE.md),
[Puma deployment](https://github.com/puma/puma/blob/main/docs/deployment.md).

### Live-data edge cases found in the Puma canary

The `b17799b5c` Puma canary passed its initial checks but the saved 40-minute
monitor reported five HTTP 500 responses. After a usage-limit interruption,
server4 was detached again rather than retiring server3. The later Puma journal
identified null recruitment text in listings, anonymous visits to management
pages, invalid city/prefecture URLs, and an existing typo in schedule deletion.

The follow-up patch makes legacy nullable listing text safe, requires admin
sign-in before management callbacks (and owner checks before schedule writes),
handles missing region records before rendering, and saves the actual User after
schedule deletion. Synthetic integration tests cover all four cases without
using production accounts or modifying production data. Redeploy on detached
server4, rerun private page/origin/asset checks, and restart the full 15-minute
canary before removing server3. The user authorized subsequent deploy/fix/rollback
steps for this chat on 2026-09-26; no repeated deploy approval is required.

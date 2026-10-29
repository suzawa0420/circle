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

The Ruby update section records the completed 2026-10-11 deployment. Sections explicitly marked
historical describe the earlier migration; their topology, rollback state and
approval requests are superseded by current production state. Never start the
obsolete `circle-unicorn` service on the new runtime.

## Schedule submission deduplication (2026-10-26)

Schedule creation forms retain a UUID through validation errors and resubmissions.
Creation holds the circle's row lock and returns the existing schedule when that
form was already saved, including requests reaching different app servers.
Separate forms can still create separate activities with identical contents.

Deployment applies additive migration `20261026000000` on server4 before either
Puma restarts. It adds a nullable UUID column and a partial unique index created
concurrently, with a five-second lock timeout. Existing schedules are unchanged.
Rollback uses a normal application revert while retaining the additive schema;
do not remove existing schedules or roll back the column during recovery.

## Official facility discovery (2026-10-25)

Facility discovery starts with the Setagaya Sports Promotion Foundation's official
facility directory. Verified, unambiguous facilities may be registered automatically,
up to five per run. Missing facts, possible duplicates and closure notices stay in
the webmaster review inbox. See [facility import operations](place-imports.md).

Deployment applies additive migration `20261025010000` before either Puma restarts.
It adds candidate and execution-history tables, without changing existing facility
content. Server4 receives the import service/timer units; the timer is enabled
separately after the initial production preview and registration check. Server5
must not run this timer. Daily execution is scheduled at 05:20 JST plus up to
15 minutes of jitter. To roll back, disable the timer, then deploy a normal revert
while keeping the additive schema and registered facilities.

## Delivery-service promotion moderation (2026-10-21)

Profiles containing euphemistic phrases such as `高品質なデリバリーサービス`,
`高級なデリバリーサービス` or `厳選されたデリバリーサービス` are held for
review and excluded from public detail pages, listings and sitemap discovery.
Ordinary delivery or reservation terms alone do not trigger this rule.

Deployment explicitly applies data migration `20261021000000` before either
Puma restarts. It holds matching existing clear profiles and records the reason
and check time without changing content or existing review/blocked decisions.
There is no schema change. Both servers then perform the normal rolling hot
restart and server4 refreshes the sitemap. Revert the application through the
normal workflow if needed; do not automatically republish held profiles or
reverse later human moderation decisions.

## Editorial articles and affiliate links (2026-10-21)

The webmaster dashboard's **紹介記事・コラム** opens `/columns`. The editor at
`/columns/new` supports draft/publish, a Trix body, a cover image, participant or
organizer targeting, an optional sport and up to twelve product cards. Each card
accepts an official Amazon affiliate URL. The editor includes
starter outlines for a first-visit checklist and an organizer equipment guide.
Use **下書き保存**, then **保存済みの記事をプレビュー** to review saved content;
**公開する** makes it public. Saving a published article as a draft unpublishes
it after confirmation. New articles default to drafts. Existing columns keep
their public URLs and publication state after migration.

Product cards automatically enable advertising disclosure; Amazon links also
enable the Amazon Associates statement. Rich body markup is sanitized, and
external links in affiliate articles are marked `sponsored nofollow noopener`.
Only generated HTTPS shop links on the supported domains are accepted in cards.
No product images, prices, stock data or affiliate identifiers are fetched or
generated. Paste the actual links from the respective affiliate accounts.

Published guides appear on matching event pages for participants and in the
organizer dashboard for organizers, including all-sports/all-audience guides.
The left-thumbnail cards also appear below circle details and genre listings.
The organizer dashboard and post-creation prompt prioritize sport-specific
guides, then fill the remaining slots with shared guides (up to three total),
so equipment, teamwear and camp articles can be discovered together. Participant
My Pages show up to three published participant guides matching registered
interests. Unrelated sports and organizer-only guides are excluded there.
Drafts are excluded from these placements, public articles and the sitemap.
`config/sitemap.rb` automatically includes every published column with its last
update time. The master deployment regenerates the sitemap on server4 after
both application servers are ready; article-only publication is also picked
up by the daily timer or the `refresh_sitemap.yml` workflow.
Product-link clicks are atomically counted per shop and shown in the editor
and management list. Webmaster previews do not count. These are click counts,
not purchases or revenue; affiliate reports remain the source for those.

Deployment requires `20261021010000` **before restarting either application
server**, followed by normal asset compilation and rolling Puma restarts. It
adds columns and the `column_products` table, without changing circle blogs.
Rollback the application through the normal revert workflow while retaining
the additive schema and article data. Do not run the migration's destructive
`down` against production as a routine application rollback.

## LanCul affiliate placements (2026-10-21)

Campaigns are configured in `config/affiliate_ads.yml` and rendered by the shared
`layouts/ads/affiliate` partial. Follow [affiliate card operations](../../docs/affiliate-ads.md)
for approval, copy/image changes, targeting, compact design and verification.
Cards use natural height on desktop; ads never stretch neighboring circle cards.
Public search cards omit webmaster edit/delete buttons; management pages remain
available for those operations.

The approved LanCul A8 creatives for the registered Circlebook site appear
only on English (`english`) discovery pages: as the third card after two circle
results (or last result on a shorter page), matching empty searches, English blog discovery
lists, and English circle blog archives/details. Participant home pages show it
below recommended circles only when English is a saved interest. Generic lists,
other genres, public participant profiles and conversations do not show it.
English lists use one LanCul card in normal desktop grid flow, without the
full-width in-list AdSense rows; the footer ad is retained. The official A8
300x250 creative (013) is linked with its supplied tracking pixel, without
cropping or editing. Fragment cache keys include the English placement flag.
PR/disclosure, the supplied A8 links and their tracking pixels are shared by all placements. No price or time-limited offer is copied.

No new migration is required. Deploy master through the normal runtime checks,
asset compilation and rolling Puma hot restart on server4/server5. Existing
migration tasks remain idempotent. Revert this change and deploy normally to
remove placements; no database rollback or affiliate-account change is needed.

## Circle detail read-more controls (2026-10-20)

Long circle introductions, reviews, questions, blogs and organizer profiles share
an on-page expand/collapse control with a fading preview. Controls appear only
when rendered content exceeds the section's preview height; short content and
pages without JavaScript remain fully readable. Private organizer profiles stay
hidden. Blog and review archive links remain available, and existing item limits
and structured data are preserved. No new database migration is required.

The public detail CSS includes the shared controls and their dynamic states.
Deploy through the normal asset preparation and rolling Puma restart workflow;
an application revert restores the previous display without a database rollback.

## Circle introduction videos (2026-10-20)

Each circle can save one optional YouTube URL in its basic-information form.
Normal, shared, Shorts, embed and live video URLs are parsed locally; non-YouTube
hosts, channel/playlist links and malformed video IDs fail server-side validation.
The public detail page shows a thumbnail below its introduction and opens the
player on demand. Closing the dialog removes the iframe and stops playback.

Deployment explicitly applies `20261020010000` before either Puma restarts.
This adds a nullable `users.youtube_url` string without a backfill or new index.
Asset preparation retains video styles in the public detail CSS. Roll back the
application with a revert deployment; keep the additive column and its data.

## Event OGP renderer (2026-10-19)

Public schedule detail pages generate 1200 × 630 PNGs with a square image,
up to three title lines and one public `venue` line. Member-only venue names,
addresses and map fields are never selected by the image endpoint.
`install_ogp_renderer.sh` installs `librsvg2-tools` on each server during verified
deployment preparation. The existing Japanese fonts and ImageMagick handle
text fallback and photo composition. No database migration is added. Generated
PNGs are cached under `tmp/cache/schedule-ogp`; changed schedules or circle
images receive a new versioned URL. A normal revert deployment restores the
previous application; the additional renderer package may safely remain.

## Retiring secondary sports (2026-10-17)

Secondary activities were already hidden from the edit form, but stored values
still affected search, profile links and sitemap discovery. All discovery now
uses `users.event_id` exclusively.

The rollout requires two separate successful deployments:

1. Activate `c2ca5047b` on **both** servers. This removes all live references and
   adds `User.ignored_columns` for `secondary_event_ids`, while leaving the data
   in place. Wait for the deployment workflow to succeed before step 2.
2. Deploy the subsequent column-removal commit. Migration `20261017030000` drops
   `users.secondary_event_ids` and its GIN index. A five-second lock timeout
   prevents waiting indefinitely for the table lock. The normal workflow checks
   and activates both servers in sequence and republishes the sitemap.

Do not skip step 1 on any existing server. Removing the column discards its
stored assignments permanently; the primary sport and `sport_details` remain.
After step 2, use `c2ca5047b` as the application recovery baseline, never an older
revision that references the deleted column. Do not run `db:rollback`: the drop
is explicitly irreversible. Keep the ignored-column declaration for safe Rails
schema caching. Historical migrations retain their original column creation;
the reviewed classification migration also tolerates the retired column being
absent when exercised against a current schema.

## Ruby 3.4.11 update (deployed 2026-10-11)

Both production servers now run Ruby 3.4.11. Deployment of `cd2f2fc7f` succeeded
on server4 and server5, including runtime checks, preparation, activation,
running-interpreter verification, public-page warm-up and registration-form
readiness. Server4's sitemap and chat-maintenance units use the new runtime.
Public home, health and admin sign-in returned HTTP 200 after the rollout.

Deployment record: https://github.com/suzawa0420/circle/actions/runs/38098057486

The historical installation records below still describe Ruby 3.3.12. The old
runtime and gems were retained for rollback. Rails remains 8.1.4 and
`config.load_defaults` remains 6.0.

Pushes to `master` trigger deployment. The workflow runs tests first, then
installs Ruby alongside the existing runtime on both servers before preparing
and activating the tested revision. Activation performs a full Puma restart
only when the running interpreter differs from the target version, and verifies
the running interpreter afterward. Server4's scheduler service units are updated
as well. Ruby 3.3 and its gems remain available for rollback.

The workflow restarts servers one at a time, but does not detach them from the
load balancer. A runtime restart can briefly cause failed requests on that
server until it boots or the load balancer detects it. If uninterrupted traffic
is required, drain each server before activation through a separately approved
load-balancer operation.

For a manually drained cutover, use these steps before automatic activation:

1. Run `bash ops/al2023/install_ruby.sh` on each AL2023 server to install Ruby
   3.4.11 alongside 3.3.12 at `/opt/circle/ruby-3.4.11`. The script verifies the
   official archive SHA256 and installs Bundler 2.5.23. Rebuild the locked
   gems for Ruby 3.4 (`vendor/bundle/ruby/3.4.0`). Keep the old Ruby and gems for
   rollback. Do not reuse Ruby 3.3 native extensions.
2. Run the runtime checks with synthetic test settings, including PostgreSQL,
   uploads, authentication, asset compilation and production-mode boot.
3. Drain one server from the load balancer, install the updated `circle-puma`
   systemd unit, run `systemctl daemon-reload`, and restart Puma with the new
   Ruby. A USR2 hot restart alone keeps the old Ruby interpreter and does not
   perform this runtime upgrade. Verify health and Ruby version before restoring
   traffic; repeat on the second server.
4. On server4 only, update both sitemap and chat-maintenance service units,
   reload systemd and verify the singleton timers. Keep server5 timers disabled.
5. Deploy the matching tested revision. Existing deployment scripts include
   database migrations and asset compilation; their execution needs to be
   included in the production approval. This Ruby update adds no migration.

For rollback, drain the affected server, restore the previous tested revision
and the Ruby 3.3.12 service units, reload systemd, restart, verify health and
restore traffic. Restore scheduler units on server4 as well. Retain both sets
of compiled gems and assets until the cutover is verified.

Local validation (2026-10-11): Ruby 3.4.11 / Rails 8.1.4, isolated PostgreSQL,
155 tests / 1,955 assertions passed. Zeitwerk, production-mode boot with stubbed
SES, asset precompilation and brand asset verification passed. The lockfile
changes only the Ruby version; all gem versions and Bundler 2.5.23 are retained.

Local macOS build note: on machines whose Command Line Tools do not find C++
standard headers, install gems with `MAKEFLAGS='-j4 CXX=clang++'` and
`CPATH="$(xcrun --show-sdk-path)/usr/include/c++/v1"`. These are local compiler
settings; the Linux runtime uses its system compiler normally.

Source: https://www.ruby-lang.org/en/downloads/
Ruby 3.4.11 tar.gz SHA256:
`5c22be44524312b3d433d68739bcc530633b1da5ef8ba0afa0a37680da17d3de`

## Versions and compatibility (historical 3.3 migration)

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

### AdSense review diagnostics (2026-10-01)

Access logs now use escaped JSON and retain the timestamp, path (without query),
Host, status, upstream status, duration, User-Agent, CF-Ray, trusted CF client IP,
and the origin guard decisions. Client IP is retained only for a request which
passed the private-LB + Cloudflare-hop + Host checks. A User-Agent alone does not
prove a Google crawler; verify crawler addresses by Google's reverse/forward DNS
procedure or published crawler IP ranges. Do not paste full logs into tickets.

The application returns 404 for unknown event/category/prefecture records and
invalid calendar dates. Missing question owners were already changed to 404 in
`80e7db99c`; the public page regression tests cover this as well.

Nginx configuration is installed separately from the application deploy. On each
server, after the tested revision has been deployed, back up `/etc/nginx/nginx.conf`,
install `ops/al2023/nginx.conf` with root ownership and mode 0644, run `nginx -t`,
and reload only if that check passes. Keep the origin guard include unchanged.
If the check or reload fails, restore the backup and validate before reloading.
The application can be reverted with a revert commit and the normal rolling
workflow; do not undo the existing DB moderation migrations.

On or after 2026-10-07, confirm the review restriction has expired and that the
public homepage, robots.txt and AdSense snippet remain reachable, then request
review once. Record its time in JST and UTC. Correlate both servers' JSON logs
for `Google-Display-Ads-Bot` and `Mediapartners-Google`, paying attention to 403,
5xx, origin_deny, upstream_status, and CF-Ray. Match failures to Cloudflare events
and Puma's journal in the same time range. Existing logs without timestamps or
User-Agent cannot identify the crawler retrospectively. A successful local UA
probe is insufficient to establish Google's actual access.

## Participant withdrawal guidance (2026-10-29)

The participant My Page, login settings, member menu and help article
`/help/withdraw-member` link to `/unsubscribe/member`. Anonymous visitors use
participant login and return to the confirmation page. Deletion always targets
`current_member`; an explicit confirmation checkbox is required server-side.
The alternate Devise deletion endpoint redirects to the same confirmation page.
Existing dependent-deletion behavior is retained, followed by participant sign-out.
Database constraints or aborted deletions roll back and show a support link;
legacy `applications` records are retained and can prevent withdrawal. Their
retention policy is not changed by this release. Support must review such cases
rather than deleting those records as an automatic workaround.

No migration is added. Deploy master through the normal checks, retained asset
compilation and rolling Puma hot restarts on server4/server5. Roll back with an
application revert; no database rollback is needed. Never validate withdrawal
using a real production participant, organizer or webmaster account.

## Circle names within one organizer account (2026-10-29)

New circles, renamed circles and ownership changes reject a name already used
by that organizer account. Comparison ignores surrounding Unicode whitespace;
internal whitespace, case and character width remain distinct and display names
are preserved. Different organizer accounts may use the same name. Existing
duplicates are retained and remain editable when their name/account is unchanged.
No automatic deletion, merging or renaming is performed.

The model validates names and rechecks before saving while holding the account
row's PostgreSQL `FOR NO KEY UPDATE` lock until the save transaction commits.
This serializes concurrent creates/renames across application servers without
adding a unique index that would reject existing duplicates. Normal writes must
use model save/update methods; bulk SQL and update_columns bypass callbacks and
must not be used for new circles, names or ownership changes. No migration is
added. Deploy master through existing checks, asset preparation and sequential
Puma hot restarts on server4/server5. Roll back with a normal application revert;
no database rollback or existing-data cleanup is required.

## Contextual adult dispatch promotion review (2026-10-29)

Profiles combining a dispatch-service offer, delivery/dispatch of women to a
private home or hotel, private companionship or selection language, and an
external destination are held for webmaster review. The check spans editable
profile fields and ignores markup, Unicode spacing/punctuation and character
width variations. Premium travel, women-led mobile lessons and hotel activities
alone do not match. A stated hobby/category does not bypass the combined rule.

Both initial registration and later edits use the existing review/visibility
pipeline. Recorded reasons carry a content fingerprint: approval requires the
content the webmaster viewed, and changes to accepted matching content require
fresh review. Concurrent blocks remain in force. The webmaster-only control on
a circle detail page can move that single circle into review and record current
reasons; it does not suspend the owner, affect sibling circles or send mail.

No migration or bulk reclassification is included. Only the specifically reported
circle 81256 is to be held through the existing moderation action after deployment.
Other existing posts must not be updated in a batch without separate approval.
Deploy master normally with retained assets and sequential Puma hot restarts on
server4/server5. Roll back using an application revert; retain the human review
status and data. Do not automatically republish held content during recovery.

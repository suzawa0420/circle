# AL2023 runtime migration

This branch is based on production commit `72e201611` and must **not** be pushed to master until the new server is ready. The existing master workflow deploys to AL2 servers that still run Ruby 2.7.

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

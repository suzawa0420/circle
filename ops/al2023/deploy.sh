#!/usr/bin/env bash
set -euo pipefail
export PATH=/opt/circle/ruby-3.3.12/bin:/opt/circle/node-v24.21.0-linux-x64/bin:/usr/local/bin:/usr/bin:/bin
export RAILS_ENV=production BUNDLE_PATH=/var/www/circle/vendor/bundle AWS_EC2_METADATA_DISABLED=true
cd /var/www/circle
umask 0007
mode=${1:?prepare or activate required}
revision=${2:?exact commit required}
[[ "$revision" =~ ^[a-f0-9]{40}$ ]] || exit 2

case "$mode" in
  prepare)
    previous=$(git rev-parse HEAD)
    git cat-file -e "$revision^{commit}"
    git merge --ff-only "$revision"
    bundle check || bundle install --jobs 1 --retry 2
    if ! git diff --quiet "$previous" "$revision" -- package-lock.json package.json; then
      npm ci --ignore-scripts --no-audit --no-fund
    fi
    # Retain older digested assets throughout rolling deployments. Never clobber.
    if ! git diff --quiet "$previous" "$revision" -- app/assets vendor/assets config/initializers/assets.rb Gemfile.lock package-lock.json; then
      bundle exec rails assets:precompile
    fi
    bundle exec ruby bin/verify_brand_assets
    bundle exec rails db:abort_if_pending_migrations
    sudo -n nginx -t
    ;;
  activate)
    test "$(git rev-parse HEAD)" = "$revision"
    # Puma hot restart retains the listening socket and drains active requests.
    sudo -n systemctl kill --kill-whom=main --signal=USR2 circle-puma
    python3 ops/al2023/warm_public_pages.py
    CIRCLE_PUMA_SOCKET=/var/www/circle/tmp/sockets/unicorn.sock bundle exec ruby bin/verify_turnstile_readiness
    systemctl is-active circle-puma nginx
    ;;
  *) exit 2 ;;
esac

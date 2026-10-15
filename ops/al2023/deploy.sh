#!/usr/bin/env bash
set -euo pipefail
export PATH=/opt/circle/ruby-3.4.11/bin:/opt/circle/node-v24.21.0-linux-x64/bin:/usr/local/bin:/usr/bin:/bin
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
    # Older servers may have hand-edited error pages. Preserve only pages that
    # this revision replaces, without exposing their contents in Actions logs.
    dirty_pages=()
    for page in public/404.html public/422.html public/500.html; do
      if ! git diff --quiet "$previous" "$revision" -- "$page"; then
        if ! git diff --quiet -- "$page" || ! git diff --cached --quiet -- "$page"; then
          dirty_pages+=("$page")
        fi
      fi
    done
    if ((${#dirty_pages[@]})); then
      backup_dir=$(mktemp -d "tmp/deploy-local-pages.${revision:0:12}.XXXXXX")
      git diff --binary HEAD -- "${dirty_pages[@]}" > "$backup_dir/worktree.patch"
      git diff --cached --binary HEAD -- "${dirty_pages[@]}" > "$backup_dir/index.patch"
      for page in "${dirty_pages[@]}"; do
        mkdir -p "$backup_dir/$(dirname "$page")"
        cp -p -- "$page" "$backup_dir/$page"
      done
      git restore --source=HEAD --staged --worktree -- "${dirty_pages[@]}"
      printf 'Preserved local error-page edits in %s\n' "$backup_dir"
    fi
    git merge --ff-only "$revision"
    bundle check || bundle install --jobs 1 --retry 2
    if ! git diff --quiet "$previous" "$revision" -- package-lock.json package.json; then
      npm ci --ignore-scripts --no-audit --no-fund
    fi
    # Retain older digested assets throughout rolling deployments. Never clobber.
    if ! git diff --quiet "$previous" "$revision" -- app/assets lib/assets vendor/assets app/views app/helpers lib/public_listing_styles.rb config/initializers/assets.rb config/initializers/public_listing_styles.rb Gemfile.lock package-lock.json; then
      bundle exec rails assets:precompile
    fi
    bundle exec ruby bin/verify_brand_assets
    # Apply moderation backfills before either server restarts.
    bundle exec rails db:migrate:up VERSION=20260926010000
    bundle exec rails db:migrate:up VERSION=20260927000000
    bundle exec rails db:migrate:up VERSION=20260927010000
    bundle exec rails db:migrate:up VERSION=20260927120000
    bundle exec rails db:migrate:up VERSION=20261002000000
    # Additive chat/account migrations; deliberately enumerate approved versions.
    for version in 20261001000000 20261001010000 20261001020000 20261001030000 20261001040000 20261001050000 20261002010000 20261002020000; do
      bundle exec rails db:migrate:up VERSION="$version"
    done
    # Circle levels: additive fingerprint history and concurrent ranking index.
    for version in 20261002030000 20261002040000; do
      bundle exec rails db:migrate:up VERSION="$version"
    done
    # Recalculate affected stored levels without legacy inquiry penalties.
    bundle exec rails db:migrate:up VERSION=20261003000000
    # Help center: additive private requests and anonymous search/answer counters.
    bundle exec rails db:migrate:up VERSION=20261005000000
    bundle exec rails db:migrate:up VERSION=20261007000000
    bundle exec rails db:migrate:up VERSION=20261008000000
    bundle exec rails db:migrate:up VERSION=20261009000000
    # Preserve publication policy while avoiding repeated profile-HTML scans.
    bundle exec rails db:migrate:up VERSION=20261010000000
    # Align stored scores with delivered, reported first inquiries only.
    bundle exec rails db:migrate:up VERSION=20261010010000
    # Public keyword searches: avoid profile-HTML checks in ordered scans.
    bundle exec rails db:migrate:up VERSION=20261013020000
    bundle exec rails db:migrate:up VERSION=20261013030000
    bundle exec ruby bin/verify_public_level_index
    # Backlink reward requests must exist before activating the new scoring code.
    bundle exec rails db:migrate:up VERSION=20261013100000
    # Circle-to-circle chat: nullable participant and an additive sender-circle reference.
    bundle exec rails db:migrate:up VERSION=20261014000000
    # Anonymous facility correction requests and private webmaster inbox.
    bundle exec rails db:migrate:up VERSION=20261014010000
    # Add sport taxonomy and optional owner-entered discovery details.
    bundle exec rails db:migrate:up VERSION=20261015000000
    bundle exec rails db:migrate:up VERSION=20261015010000
    bundle exec rails db:migrate:up VERSION=20261015020000
    bundle exec rails db:abort_if_pending_migrations
    sudo -n nginx -t
    ;;
  activate)
    test "$(git rev-parse HEAD)" = "$revision"
    puma_pid=$(systemctl show circle-puma --property MainPID --value)
    current_ruby=$(sudo -n runuser -u ec2-user -g nginx -- readlink -f "/proc/$puma_pid/exe")
    expected_ruby=$(readlink -f /opt/circle/ruby-3.4.11/bin/ruby)
    if [[ "$current_ruby" != "$expected_ruby" ]]; then
      # USR2 re-execs the old interpreter. A runtime change needs the new unit
      # and a full restart; the workflow activates only one server at a time.
      sudo -n install -m 0644 ops/al2023/circle-puma.service /etc/systemd/system/circle-puma.service
      sudo -n systemctl daemon-reload
      sudo -n systemctl restart circle-puma
    else
      # Ordinary application deployments retain the listening socket.
      sudo -n systemctl kill --kill-whom=main --signal=USR2 circle-puma
    fi
    python3 ops/al2023/warm_public_pages.py
    CIRCLE_PUMA_SOCKET=/var/www/circle/tmp/sockets/unicorn.sock bundle exec ruby bin/verify_turnstile_readiness
    # A single scheduler serves the shared DB. Never install it on server5.
    if [[ "${3:-}" == server4 ]]; then
      sudo -n install -m 0644 ops/al2023/circle-sitemap.service /etc/systemd/system/circle-sitemap.service
      sudo -n install -m 0644 ops/al2023/circle-chat-maintenance.service /etc/systemd/system/circle-chat-maintenance.service
      sudo -n install -m 0644 ops/al2023/circle-chat-maintenance.timer /etc/systemd/system/circle-chat-maintenance.timer
      sudo -n systemctl daemon-reload
      sudo -n systemctl enable --now circle-chat-maintenance.timer
      systemctl is-active circle-chat-maintenance.timer
    fi
    systemctl is-active circle-puma nginx
    puma_pid=$(systemctl show circle-puma --property MainPID --value)
    test "$(sudo -n runuser -u ec2-user -g nginx -- readlink -f "/proc/$puma_pid/exe")" = "$expected_ruby"
    "$expected_ruby" --version
    ;;
  *) exit 2 ;;
esac

#!/usr/bin/env bash
# Install alongside the old runtime; never restart services here.
set -euo pipefail
version=3.4.13
prefix="/opt/circle/ruby-${version}"
sha256=d0d3bf3dd8c224a3c3b7ecd816a0f1b2cbcf4f87b5afcbdbe91d3fef177f351a
[[ "$(uname -s)" == Linux ]] || { echo 'AL2023 Linux is required' >&2; exit 1; }

if ! [[ -x "$prefix/bin/ruby" ]] || ! "$prefix/bin/ruby" -ropenssl -rpsych -e 'abort unless RUBY_VERSION == "3.4.13"'; then
  build_dir=$(mktemp -d /tmp/circle-ruby-3.4.13.XXXXXX)
  trap 'rm -rf -- "$build_dir"' EXIT
  cd "$build_dir"
  curl -q --fail --silent --show-error --location \
    "https://cache.ruby-lang.org/pub/ruby/3.4/ruby-${version}.tar.gz" -o ruby.tar.gz
  printf '%s  ruby.tar.gz\n' "$sha256" | sha256sum --check --status
  tar -xzf ruby.tar.gz
  cd "ruby-${version}"
  ./configure --prefix="$prefix" --disable-install-doc
  nice -n 10 make -j2
  sudo -n make install
fi

if ! "$prefix/bin/ruby" -rrubygems -e 'gem "bundler", "2.5.23"' 2>/dev/null; then
  sudo -n env GEMRC=/dev/null "$prefix/bin/gem" install bundler --version 2.5.23 --no-document --source https://rubygems.org
fi
"$prefix/bin/ruby" -ropenssl -rpsych -e 'abort unless RUBY_VERSION == "3.4.13"; puts RUBY_DESCRIPTION'
"$prefix/bin/bundle" _2.5.23_ --version

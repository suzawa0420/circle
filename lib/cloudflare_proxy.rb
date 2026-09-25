# frozen_string_literal: true

require 'ipaddr'

module CloudflareProxy
  # Public reverse-proxy ranges, verified 2026-09-25 against
  # https://www.cloudflare.com/ips/ . Review when Cloudflare updates its list.
  # Never trust CF-Connecting-IP supplied directly by a visitor.
  NETWORKS = %w[
    103.21.244.0/22 103.22.200.0/22 103.31.4.0/22
    104.16.0.0/13 104.24.0.0/14 108.162.192.0/18
    131.0.72.0/22 141.101.64.0/18 162.158.0.0/15
    172.64.0.0/13 173.245.48.0/20 188.114.96.0/20
    190.93.240.0/20 197.234.240.0/22 198.41.128.0/17
    2400:cb00::/32 2606:4700::/32 2803:f800::/32
    2405:b500::/32 2405:8100::/32 2a06:98c0::/29 2c0f:f248::/32
  ].map { |cidr| IPAddr.new(cidr).freeze }.freeze
end

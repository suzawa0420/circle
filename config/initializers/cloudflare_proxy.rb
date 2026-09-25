require Rails.root.join('lib/cloudflare_proxy')

# Preserve Rails' internal proxy ranges for Lightsail LB -> Nginx -> Unicorn.
# The ingress must append its actual peer to X-Forwarded-For. Rails then walks
# from the nearest proxy to the visitor, ignoring a forged left-hand prefix.
existing = Rails.application.config.action_dispatch.trusted_proxies
Rails.application.config.action_dispatch.trusted_proxies =
  Array(existing || ActionDispatch::RemoteIp::TRUSTED_PROXIES) + CloudflareProxy::NETWORKS

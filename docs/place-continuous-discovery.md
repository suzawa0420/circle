# Continuous official facility discovery (2026-11-13)

## What changes

The existing server4-only 30-minute `places:nationwide` job can now run one bounded
prefectural discovery batch first (`OFFICIAL_DISCOVERY=1`). The 47 official origins
are reviewed in `place_import_official_directories.json`; least-recently checked
origins rotate fairly, with lower existing facility counts first for ties.

Each batch reads robots and at most three pages. It follows declared same-host
sitemaps and sports-related HTML links, including configured entrypoints. Stored
frontier/seen URLs are capped at 2,000 per source. A completed cycle restarts after
seven days; truncated cycles remain visibly flagged. Retrieval gets two attempts.
Private/reserved IP ranges, redirects, off-host URLs, query URLs and unsupported
content types are refused. TLS remains verified. No cookies, credentials, paid
API, remote JavaScript or generated page claims are used.

New discoveries are deduplicated into the existing **確認待ち** queue. They contain
only title, URL and prefecture; they do NOT bypass the facility Registrar. Existing
reviewed adapters continue automatic registration of sufficiently supported facts.
Unknown sources need a reviewed adapter and evidence for identity/address/sports,
fees/hours/parking/closures before publication. No existing facility is edited.

## Coverage limitations

This is continuous discovery from 47 prefectural official websites, **not complete
coverage of every municipality or every facility**. Numeric sitemap URLs without
sports labels can be missed. Off-host municipality/operator links require a new
reviewed source, and robots/format restrictions are not bypassed. Search-result
noise may enter the review queue but cannot be published from discovery metadata.
Live source permission/format checks are not yet verified for every origin.

## Verification / observability

`places:official_discovery_status` is read-only. It returns checked/configured source
counts, pending discoveries and per-source latest status. `robots_unavailable`,
`robots_disallowed`, `fetch_failed` and `capacity_reached` differ from a healthy
crawl. `places:nationwide_status` remains the publication queue status. Do not report
scheduler success as a facility addition. Monitor both pending growth and actual
registered counts.

Local tests cover cursor continuation, robots, encoded paths, XML NONET, exact
hosts, bounded retries, capped frontier continuation, nav links, entrypoints,
private-address rejection, persistent rotation and duplicate-safe pending writes.

## Production rollout (requires action-specific approval)

1. Normal review/CI on this branch, then master deployment to server4 + server5.
2. Additive migration `20261113000000` creates `place_discovery_sources` only;
   no existing customer/facility data changes or backfill. CI uses updated schema.
   Existing deploy refuses pending migrations; use the established approved
   migration procedure before the rolling deployment, not an ad-hoc DB write.
3. Normal asset compilation and sequential Puma hot restarts; no planned full
   outage. Install updated nationwide unit on server4 only, daemon-reload, retain
   the existing timer interval. Do not enable a second runner on server5.
4. Check public /health and exact deployment SHA, first discovery summary,
   source state advancement and pending queue. Observe a subsequent timer run.
5. No manual bulk facility insertion. Any new public count comes from the existing
   verified registration gate and must be independently checked.

Rollback: remove the server4 OFFICIAL_DISCOVERY flag, daemon-reload and revert the
application commit through the normal deployment. Keep the additive table and
review candidates; no destructive down migration or customer data deletion.

# Owner dashboard level-up celebration

On the first dashboard visit after rollout, the circle's current integer level
becomes its baseline without showing a historical celebration. Later owner
visits show a single dialog when the calculated level has increased, including
reviews received while away and increases spanning several levels. Decreases
update the baseline quietly. The level remains capped at 100.

The nullable `users.last_seen_circle_level` column is shared across devices.
Reading and advancing it happens under a row lock, so concurrent dashboard
requests cannot consume the same increase twice. Only the circle's owner
consumes it; public pages, other owners and webmaster-only visits do not.
The notification is consumed when the dashboard response is prepared, rather
than requiring an additional write request when the dialog is dismissed.

The responsive dialog prioritizes new schedule registration, aligns the old and
new level text on their baseline, and plays one short, silent green/gold
confetti burst. Native dialog focus handling, Escape/close controls, scroll
restoration, reduced-motion preferences and Turbolinks cache cleanup are
supported. Decorative particles never intercept clicks. Preview replay
controls and the preview-only motion override are not part of production.

## Rollout and recovery

Deploy `master` through `deploy_prod.yml`. Preparation on both AL2023 servers
adds column `20261017040000`, compiles changed assets while retaining old
digests, then activates Puma one instance at a time. There is no data backfill
or change to ranking calculations. Schema changes have a five-second lock
timeout. The existing workflow also refreshes the sitemap after activation.

For a regression, revert this application change in a new commit and redeploy.
Leave the nullable column in place; no DB rollback or history reset is needed.

## Verification

- Notification integration tests: initial baseline, fractional increases,
  schedule creation crossing a level, aggregated reviews, repeat visits and
  another device, decreases, cap and owner permissions.
- Existing level card/ranking, legacy score, owner permissions and site design.
- JavaScript lifecycle tests cover duplicate load events, immediate close,
  Turbolinks restoration, focus/scroll restoration and reduced motion.
- Actual Rails partial and compiled styles checked in Chrome at 320/390/1440px,
  including confetti, text alignment, focus, Escape and the schedule destination.
- The production workflow runs the new tests before preparing either server.

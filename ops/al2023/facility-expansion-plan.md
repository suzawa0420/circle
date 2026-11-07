# Nationwide facility expansion plan

## Baseline and goal

Snapshot: 2026-11-07 16:46 JST. The existing database contains 2,296 facilities across all 47 prefectures.
These are existing registrations, not a claim that every historical detail has been reverified.
The goal is to add missing verified facilities and expand repeatable official-source coverage across all prefectures.

## Current delivery stages

- Mizuno: permitted individual-facility related links rotate in bounded batches. The restricted nationwide directory remains excluded.
- Sapporo: municipal gym/tennis listing discovery and reviewed tennis parsing deployed in 7020b13d5. First timed apply on 2026-11-07 registered Hiragishi tennis courts (public ID2402); 18 candidates yielded 1 registration, 8 duplicates, 1 pending, and 8 queued at that checkpoint. Public page and key fields were verified.
- Sendai: deployed in 16bdc1b7c. The existing timer registered Ideka Gym (public ID2403) on 2026-11-07 at 17:32 JST; public page and all six detail fields verified. Its single seed does not imply city coverage.
- Hiroshima: association HTTPS is unavailable. Other city-designated operator pages have unresolved access/sport/notice evidence; do not publish incomplete records.

## Repeatable expansion process

1. Select genuinely missing venues using current existing records, not counts alone. Combine low-count regions, source reliability, and reusable layouts.
2. Establish municipality/operator provenance and inspect robots, HTTPS availability, current notices, and actual fee versions.
3. Confirm address, supported sports, indoor/outdoor identity, written access, parking, hours, closure/season, scale, and qualified actual fees.
4. Build a narrow reviewed adapter with minimal real fixtures. Fail closed on changed identity, missing terms, ambiguous facilities, and source restrictions.
5. Test extraction, duplicate identity, concurrency, interrupted runs, notices, tariff spans, and malformed URLs before release.
6. Release a small reviewed batch, observe the existing scheduler, and verify public records and counts after actual application.
7. Record newly published, discovered, duplicate, pending, and unavailable-source outcomes separately. Never label queue exhaustion as complete national coverage.

Prioritize operator/layout families that cover multiple venues and prefectures. Do not create a timer for every city.
The current scheduler remains one invocation every 30 minutes, selecting one reviewed source, up to 10 candidates total.
Before enabling many sources, measure queue age and source refresh intervals and review throughput; avoid silently starving active backfills.

## Sustained operation and actual limits

The application does not research arbitrary new websites or generate new adapters. It only fetches reviewed hosts, paths and layouts.
Mizuno discovers bounded related links; Sapporo discovers reviewed gym/tennis listing categories; Sendai currently has one reviewed seed.
A running timer with zero additions can therefore be healthy but have no sufficiently evidenced new venue. It must not be described as full national coverage.

`places:nationwide_status` remains read-only and reports `coverage_scope: reviewed_sources_only`, the latest apply run ID/time/status,
latest candidate discovery, latest actual publication, and oldest unprocessed candidate per source. Preview runs do not mask a missing apply run.
Use these signals alongside systemd timer/service status to distinguish a stopped scheduler, a growing queue, and exhausted sources.
No new timer, paid service, automatic retry of pending records, or external notification is introduced by the status report.

Operational review should check scheduler health daily and the source-expansion backlog at least weekly. When sources have no new candidates,
review another small batch of official sources rather than repeatedly accessing prohibited directories or weakening publication requirements.
New domains and layouts need implementation review; source restrictions and ambiguous facts remain blockers. Preserve pending evidence for later targeted review.
This research/release work is separate from the 30-minute importer and must be scheduled by the operator; the application does not silently claim to perform it.

## Reviewed next batch, 2026-11-07

- Kochi: East Sports Ground tennis courts are absent from existing registrations. Current linked fee PDF, its full applicable qualifications,
  parent-park access, facility-specific address and outdoor identity have been reviewed. Implementation verifies the current official link and exact PDF digest;
  changed bytes/link fail closed. Shared reservation contact requires an explicit venue-identity review, not a general phone-deduplication exemption.
- Tottori: Yonago Yodoe/Kamo gym pages are absent but lack verified written access/current parking. Yodoe also has unresolved partial spectator-seat restrictions.
- Miyazaki: Hinata Tennis Park has mixed indoor/outdoor courts; retain for review rather than assign one inaccurate category.
- Yamanashi: Kofu's Midorigaoka courts lack written access/parking in the reviewed sources. Higashishimojo is soft-tennis-only and must not become standard tennis.
- Ehime: Matsuyama Central Park's primary detail page returned 403. Do not use indexed content or another route to bypass that response.
- Nagasaki: Kakidomari courts have current fee/access evidence, but the park's official address variants and outdoor identity still need resolution.
- Tokushima: reviewed sports center is already registered. Nishinomaru courts have conflicting official addresses/hours; Jonai courts link an inapplicable fee PDF.
- Iwate: Mori-no-Arena is already registered. Iwate Town tennis courts lack verified written access; an additional source returned robots 403 and was not fetched.
- Okayama: Shigeto Arena is existing ID1844 under the former Zip Arena name; do not add it again. Current September fees differ from an old linked subarena PDF.

These holds are not pending permission requests and not automatic retry candidates. Resolve the identified evidence gap before enabling a source.

## Further research priorities

- Tokushima city sports operator: reusable details plus municipal counterpart; current linked PDF fees need qualified table/version review.
- Iwate town municipality and sports association: structured fees and facilities; written access and current operational notices still need verification.
- Okayama official operators: source health and recent fee revisions must be resolved before using indexed details.
- Temporary failures should receive bounded later health checks, not repeated immediate requests or alternate routes around restrictions.

## Prefecture baseline

| Prefecture | Existing registrations | Verified importer additions before Sapporo release |
| --- | ---: | ---: |
| 北海道 | 50 | 0 |
| 青森県 | 26 | 0 |
| 岩手県 | 10 | 0 |
| 宮城県 | 21 | 0 |
| 秋田県 | 19 | 1 |
| 山形県 | 23 | 0 |
| 福島県 | 31 | 0 |
| 茨城県 | 40 | 0 |
| 栃木県 | 48 | 0 |
| 群馬県 | 77 | 0 |
| 埼玉県 | 212 | 0 |
| 千葉県 | 145 | 0 |
| 東京都 | 219 | 2 |
| 神奈川県 | 175 | 0 |
| 新潟県 | 19 | 0 |
| 富山県 | 17 | 0 |
| 石川県 | 23 | 0 |
| 福井県 | 22 | 0 |
| 山梨県 | 11 | 0 |
| 長野県 | 28 | 1 |
| 岐阜県 | 18 | 0 |
| 静岡県 | 33 | 0 |
| 愛知県 | 87 | 0 |
| 三重県 | 51 | 0 |
| 滋賀県 | 31 | 1 |
| 京都府 | 88 | 0 |
| 大阪府 | 103 | 1 |
| 兵庫県 | 98 | 1 |
| 奈良県 | 40 | 0 |
| 和歌山県 | 14 | 0 |
| 鳥取県 | 7 | 1 |
| 島根県 | 50 | 1 |
| 岡山県 | 10 | 0 |
| 広島県 | 30 | 0 |
| 山口県 | 38 | 0 |
| 徳島県 | 9 | 0 |
| 香川県 | 53 | 0 |
| 愛媛県 | 13 | 0 |
| 高知県 | 12 | 0 |
| 福岡県 | 120 | 0 |
| 佐賀県 | 45 | 0 |
| 長崎県 | 13 | 0 |
| 熊本県 | 21 | 0 |
| 大分県 | 24 | 0 |
| 宮崎県 | 8 | 0 |
| 鹿児島県 | 29 | 0 |
| 沖縄県 | 35 | 0 |

# Kochi reviewed seed fixtures

Captured and manually reviewed on 2026-11-07. HTML fixtures retain the original
main content and structure, with scripts, styles, social widgets, and embedded
frames removed. No external content is executable by the importer.

- `tobu.html`: https://www.kc-sports.or.jp/facilities/f300/f305/
- `tobu-access.html`: https://www.kc-sports.or.jp/facilities/f300/
- `costs.html`: https://www.kc-sports.or.jp/facilities/costs/
- `fee-notice.html`: https://www.kc-sports.or.jp/i0002025006/
- `index.html`: https://www.kc-sports.or.jp/
- `s300fee20261001.pdf`: https://www.kc-sports.or.jp/uploads/s300fee20261001.pdf

The PDF is the unmodified official binary, SHA256
`33d9dc7e34d86b579d30c235bf368c4994ddd2556ea09630f3f9a065c7c68309`.
A visual review of its tennis rows, equipment rows, tax/scope footnotes and date
supports the scoped tariff in `KochiSource::TARIFF`. The filename does not replace
the document's own date (令和8年4月1日時点). Rates apply to applications from
2026-04-01, per the separate official fee-change notice.

Outdoor classification was visually reviewed using the exact official photo:
https://kc-sports.or.jp/uploads/5a0249179c877292721cf38b7f67ba91.jpg
The importer does not fetch or execute the photo. Its reviewed identity depends
on the unchanged venue name, address, 16-court layout, and linked photo URL.

The tennis venue is at 介良1221-1, not the parent office's 五台山 address.
The number 088-878-1150 is explicitly the shared くろしおアリーナ事務所.
Access directions refer to the parent sports park, not the tennis entrance.
This single seed does not establish exhaustive coverage of Kochi city.

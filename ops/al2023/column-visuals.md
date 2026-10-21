# Article covers and product images

Article covers use `ColumnImageUploader`: JPEG/PNG up to 20MB, resized to a
1600px maximum edge. The shared 400px uploader is unchanged. Covers appear in
the article header, directory and social preview metadata. The editor previews
a selected cover before saving it.

Product cards accept an optional Amazon-provided `image_url`. Only HTTPS URLs
on `m.media-amazon.com/images/I/` for JPEG, PNG or WebP are accepted; credentials,
nonstandard ports, queries and fragments are rejected. Images are displayed
directly from Amazon, never downloaded to this server. No scraper, remote URL
fetcher or new credentials are introduced. Editors must select a relevant image
for search-result destinations and follow Amazon's current content-use rules.
Image and button links preserve the original affiliate destination and tracking.

Deployment adds nullable `column_products.image_url` via `20261021020000` before
either Puma process is activated. This is additive, without a content backfill.
Deploy assets and hot-restart server4/server5 one at a time through the existing
master workflow. Revert this commit through the same workflow for an application
rollback, retaining the nullable column and article data. Existing covers and
product cards continue to work without images.

New product rows use numeric nested-attribute keys so Rails strong parameters
retains them on save.

## Inline products and compact disclosures

A standalone body paragraph `[商品:1]` renders the first ordered product at that
position. The editor's product button inserts this marker at the current writing
position. Numbering follows product display order; check markers after reordering
or deleting products. Repeated markers render the product once, unused products
remain in the end section, and unresolved numbers prevent publication. Rendering
only uses products belonging to the current article. The editor retains the raw
markers and never saves generated card HTML back into the body.

The article header carries a compact advertising disclosure and a link to the
public `/advertising` explanation. Amazon's statement stays readable at the end
of applicable articles and also appears on that explanation page, linked from
the shared footer. No database migration is added. Deploy the application before
updating the six articles using the normal webmaster editor. Reviewed sources
and content rollback instructions are in `content/columns/2026-10-product-guides`.

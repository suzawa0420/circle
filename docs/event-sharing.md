# Event sharing

Successful schedule creation redirects to the new public detail page. A
record-specific flash value opens the organizer's share panel once. The same
panel remains available as a disclosure on ordinary detail visits, with wording
for organizers or visitors. The publication prompt is removed from Turbolinks
snapshots so returning to a cached page does not repeat it.

The editable draft uses only the public title, date, time and `venue`. Public
URLs always use `https://circle-book.com/users/:user_id/schedules/:id`, without
request query strings or the member-only URL. Member-only venue names,
addresses, map fields and rich-text notes are not included. Hidden circles do
not offer sharing. Editing a draft only changes the local page; it is not saved
to the event or sent to an SNS until the user chooses a sharing action.

X and Threads links pass the edited draft as `text` and the public detail URL
as `url`. The destination handles sign-in and the user's final posting action.
The app does not publish on the user's behalf. Copying a post appends the public
URL; copying a URL copies only that URL. Clipboard failures fall back to browser
selection copy, then a visible manual-selection field. Native sharing is offered
only when available over a secure context. Cancelling native sharing does not
copy anything or report a completed post.

Sources checked on 2026-10-19:

- [Threads Web Intents](https://developers.facebook.com/documentation/threads/threads-web-intents): official current post endpoint is `https://www.threads.com/intent/post`; `text` and `url` are supported and must be URL encoded. Verified in the browser because the document fetch endpoint was rate limited.
- [X Web Intent](https://x.com/intent/tweet): the official logged-out flow preserves the supplied intent parameters in the login return URL. Existing `twitter.com/intent/tweet` links are retained.
- [Web Share API](https://developer.mozilla.org/en-US/docs/Web/API/Navigator/share): requires HTTPS and a user gesture, with platform-specific support; completion does not consistently prove a published post.

Validation:

```sh
bundle exec rails test test/integration/schedule_sharing_test.rb test/integration/schedule_copy_test.rb test/integration/schedule_detail_design_test.rb test/integration/circle_level_notification_test.rb test/integration/schedule_ogp_images_test.rb
node test/security/schedule_share_js_test.js
```

No migration or new dependency is required. Deploy through the normal verified
master workflow. Rollback uses a revert commit and the same rolling deployment.

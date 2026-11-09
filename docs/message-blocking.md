# Conversation message blocking

Either participant can use **相手をブロック** below the conversation's two profile
cards, then confirm the action. **自分のブロックを解除** clears only that person's
flag. If both people block, both must independently unblock before sending resumes.
This applies to the selected conversation, including practice-match conversations;
it does not suspend accounts or block unrelated circles/participants.

The existing unique conversation pair is reused by new inquiry submissions, so
resubmitting the inquiry cannot create a second thread to evade the block.
The server derives the role from authenticated membership, never form parameters.
Each change is an idempotent desired state under the conversation row lock.

While either flag is set, neither side can send text/photos/reactions, edit message
content, or release a held message through moderation. Deleting one's own recent
message remains possible. Existing history, reports and review rights are retained.
The block itself sends no email. Pending message/review notification deadlines are
cleared and are not revived merely by unblocking. Mail already delivered before the
block cannot be recalled. Polling hides/disables the composer without deleting its
draft and provides a refresh link when the state changes. A stale form is rejected
server-side regardless of polling or JavaScript.

No schema changes or production test records are required. Deploy through the
normal master workflow; rollback with a revert commit, retaining stored block flags.

## Checks

- `bundle exec rails test test/integration/conversation_blocking_test.rb test/integration/conversation_concurrency_test.rb`
- Existing conversation, message revision, moderation, image, reaction, review,
  practice-match and help suites.
- `node test/security/conversation_receipts_js_test.js`
- `node test/security/chat_message_editor_js_test.js`
- `bundle exec rails zeitwerk:check assets:precompile` and the production CI suite.

Use isolated local test data only. Check the profile-card placement, confirmation
cancel/accept, own unblock, double block, preserved draft and mobile width.
Production verification is limited to the exact deployed commit, CI/service status
and public GET health checks; never use real participants for block testing.

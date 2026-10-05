// Exercise receipt polling without a browser, network, or real user data.
const assert = require('assert');
const fs = require('fs');
const vm = require('vm');
const source = fs.readFileSync(__dirname + '/../../app/assets/javascripts/conversations.js', 'utf8');

async function checkPolling({ hidden = false, focused = false, latestId = 10 } = {}) {
  const events = {};
  let scheduled, requests = 0, replacements = 0;
  const receipt = { dataset: { messageId: '10' }, textContent: '未読' };
  const container = {
    dataset: { pollUrl: '/conversations/example/messages', latestId: '10', accepted: 'true' },
    querySelectorAll: () => [receipt],
    querySelector: () => null,
    contains: () => focused,
    set innerHTML(value) { replacements++; }
  };
  const document = {
    hidden, activeElement: {},
    body: { contains: () => true },
    querySelector: () => null,
    getElementById: id => id === 'chat-messages' ? container : null,
    addEventListener: (name, callback) => { events[name] = callback; }
  };
  const window = { clearTimeout() {}, setTimeout(fn) { scheduled = fn; }, location: { hash: '' } };
  vm.runInNewContext(source, { window, document, fetch: async () => {
    requests++;
    return { ok: true, redirected: false, json: async () => ({ latest_id: latestId, recipient_read_id: 10, html: 'new messages', accepted: true }) };
  } });
  events.DOMContentLoaded();
  scheduled();
  await new Promise(resolve => setImmediate(resolve));
  return { receipt, requests, replacements };
}
(async () => {
  const sameMessage = await checkPolling();
  assert.equal(sameMessage.receipt.textContent, '既読', 'receipt updates without a new message');
  assert.equal(sameMessage.replacements, 0, 'existing content is preserved');
  const composingReport = await checkPolling({ focused: true, latestId: 11 });
  assert.equal(composingReport.receipt.textContent, '既読');
  assert.equal(composingReport.replacements, 0, 'report input is preserved when receipt changes');
  const background = await checkPolling({ hidden: true });
  assert.equal(background.requests, 0, 'background tabs do not mark new messages as read');
  console.log('Conversation receipt polling: 5 assertions passed');
})().catch(error => { console.error(error); process.exitCode = 1; });

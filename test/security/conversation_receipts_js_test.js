// Exercise receipt polling without a browser, network, or real user data.
const assert = require('assert');
const fs = require('fs');
const vm = require('vm');
const source = fs.readFileSync(__dirname + '/../../app/assets/javascripts/conversations.js', 'utf8');

async function checkPolling({ hidden = false, focused = false, latestId = 10, receiptText = '既読', historyVersion = 'initial' } = {}) {
  const events = {};
  let scheduled, requests = 0, replacements = 0;
  const receipt = { dataset: { messageId: '10' }, textContent: '未読' };
  const container = {
    dataset: { pollUrl: '/conversations/example/messages', latestId: '10', historyVersion: 'initial', accepted: 'true' },
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
    return { ok: true, redirected: false, json: async () => ({ latest_id: latestId, recipient_read_id: 10, receipts: { 10: receiptText }, history_version: historyVersion, html: 'new messages', accepted: true }) };
  } });
  events.DOMContentLoaded();
  scheduled();
  await new Promise(resolve => setImmediate(resolve));
  return { receipt, requests, replacements };
}
function checkInitialJump({ readyState = 'complete', hash = '', event, cancel = false, alignment = 'start' } = {}) {
  const events = {}, windowEvents = {}, frames = new Map();
  const calls = [];
  let frameId = 0;
  const target = { scrollIntoView: options => calls.push(options) };
  const thread = { dataset: { chatJumpTarget: 'chat-message-10', chatJumpAlignment: alignment }, querySelectorAll: () => [] };
  const document = {
    readyState, body: { contains: () => true },
    querySelector: selector => selector === '[data-chat-jump-target]' ? thread : null,
    getElementById: id => id === 'chat-message-10' ? target : null,
    addEventListener: (name, callback) => { events[name] = callback; }
  };
  const window = {
    location: { hash }, clearTimeout() {},
    requestAnimationFrame(callback) { frames.set(++frameId, callback); return frameId; },
    cancelAnimationFrame(id) { frames.delete(id); },
    addEventListener: (name, callback) => { windowEvents[name] = callback; },
    removeEventListener: name => { delete windowEvents[name]; }
  };
  vm.runInNewContext(source, { window, document });
  if (event) events[event]();
  if (cancel) windowEvents.touchstart();
  frames.forEach(callback => callback());
  return calls;
}
(async () => {
  const sameMessage = await checkPolling();
  assert.equal(sameMessage.receipt.textContent, '既読', 'receipt updates without a new message');
  assert.equal(sameMessage.replacements, 0, 'existing content is preserved');
  const composingReport = await checkPolling({ focused: true, latestId: 11, historyVersion: 'changed' });
  assert.equal(composingReport.receipt.textContent, '既読');
  assert.equal(composingReport.replacements, 0, 'report input is preserved when receipt changes');
  const background = await checkPolling({ hidden: true });
  assert.equal(background.requests, 0, 'background tabs do not mark new messages as read');
  const released = await checkPolling({ receiptText: '未読', historyVersion: 'released' });
  assert.equal(released.receipt.textContent, '未読', 'old released message is not read just because its ID precedes the cursor');
  assert.equal(released.replacements, 1, 'moderation change refreshes history even when latest ID stays the same');
  const held = await checkPolling({ receiptText: '運営確認中' });
  assert.equal(held.receipt.textContent, '運営確認中', 'held status is preserved when polling');
  assert.equal(checkInitialJump().length, 1, 'a bundle loaded after DOMContentLoaded still initializes the master jump');
  assert.equal(checkInitialJump({ readyState: 'loading' }).length, 0, 'wait for the DOM while it is loading');
  assert.equal(checkInitialJump({ readyState: 'loading', event: 'DOMContentLoaded', alignment: 'end' })[0].block, 'end', 'all-read conversations align the latest message');
  assert.equal(checkInitialJump({ hash: '#evaluation' }).length, 0, 'explicit anchor links take priority');
  assert.equal(checkInitialJump({ cancel: true }).length, 0, 'user scrolling cancels pending automatic movement');
  console.log('Conversation receipt polling and initial jump: 13 assertions passed');
})().catch(error => { console.error(error); process.exitCode = 1; });

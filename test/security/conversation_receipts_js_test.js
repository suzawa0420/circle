// Exercise receipt polling without a browser, network, or real user data.
const assert = require('assert');
const fs = require('fs');
const vm = require('vm');
const source = fs.readFileSync(__dirname + '/../../app/assets/javascripts/conversations.js', 'utf8');

async function checkPolling({ hidden = false, focused = false, latestId = 10, receiptText = '既読', historyVersion = 'initial', noticeHtml, noticeFocused = false, noticeInitial = '' } = {}) {
  const events = {};
  let scheduled, requests = 0, replacements = 0;
  const reviewPrompt = { innerHTML: noticeInitial, contains: () => noticeFocused };
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
    getElementById: id => id === 'chat-messages' ? container : (id === 'chat-review-prompt' ? reviewPrompt : null),
    addEventListener: (name, callback) => { events[name] = callback; }
  };
  const window = { clearTimeout() {}, setTimeout(fn) { scheduled = fn; }, location: { hash: '' } };
  vm.runInNewContext(source, { window, document, fetch: async () => {
    requests++;
    return { ok: true, redirected: false, json: async () => ({ latest_id: latestId, recipient_read_id: 10, receipts: { 10: receiptText }, history_version: historyVersion, html: 'new messages', accepted: true, review_prompt_html: noticeHtml }) };
  } });
  events.DOMContentLoaded();
  scheduled();
  await new Promise(resolve => setImmediate(resolve));
  return { receipt, requests, replacements, reviewPrompt };
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
function checkReplyShortcuts() {
  const events = {}, clicks = new Map();
  const links = [{}, {}]; // Header link and fixed reply shortcut.
  const photo = { name: 'draft.jpg' };
  const input = { value: '消えてはいけない返信の下書き', selectionStart: 5, selectionEnd: 5,
    style: {}, scrollHeight: 120, addEventListener() {}, removeEventListener() {},
    focus() { this.focused = true; }
  };
  let scrolls = 0;
  const composer = { querySelector: () => input,
    scrollIntoView() { scrolls++; }, photo, editing: true
  };
  links.forEach(link => {
    link.addEventListener = (name, callback) => clicks.set(link, callback);
    link.removeEventListener = () => clicks.delete(link);
  });
  const document = {
    readyState: 'loading', querySelector: selector => selector === '.chat-composer' ? composer : null,
    querySelectorAll: selector => selector === 'a[href="#chat-reply"]' ? links : [],
    getElementById: () => null, addEventListener: (name, callback) => { events[name] = callback; }
  };
  const location = Object.freeze({hash: '#chat-reply'});
  const window = { location, clearTimeout() {}, addEventListener() {}, removeEventListener() {} };
  vm.runInNewContext(source, {window, document});
  events.DOMContentLoaded();
  // Click both shortcuts repeatedly after reaching the same anchor, including editing.
  links.forEach(link => {
    for (let i = 0; i < 3; i++) {
      let prevented = false;
      clicks.get(link)({preventDefault() { prevented = true; }});
      assert(prevented, 'anchor navigation is stopped before Turbolinks can reload');
      assert.equal(input.value, '消えてはいけない返信の下書き');
      assert.equal(input.selectionStart, 5, 'cursor position is preserved');
      assert.equal(composer.photo, photo, 'selected photo is preserved');
      assert.equal(composer.editing, true, 'editing mode is preserved');
    }
  });
  assert.equal(scrolls, 6);
  assert.equal(input.focused, true);
  events['turbolinks:before-cache']();
  assert.equal(clicks.size, 0, 'navigation cleans up shortcut listeners');
  events['turbolinks:load']();
  assert.equal(clicks.size, 2, 'returning to the conversation rebinds shortcuts');
}
(async () => {
  const peerNotice = await checkPolling({ noticeHtml: '<aside>口コミが届いています</aside>' });
  assert.equal(peerNotice.reviewPrompt.innerHTML, '<aside>口コミが届いています</aside>', 'peer notice appears without a new chat message');
  const published = await checkPolling({ noticeHtml: '', noticeInitial: 'old invitation' });
  assert.equal(published.reviewPrompt.innerHTML, '', 'invitation disappears once reviews are public');
  const focusedNotice = await checkPolling({ noticeHtml: 'new invitation', noticeInitial: 'current invitation', noticeFocused: true });
  assert.equal(focusedNotice.reviewPrompt.innerHTML, 'current invitation', 'focused invitation controls are preserved');
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
  checkReplyShortcuts();
  console.log('Conversation receipt polling, initial jump and draft-safe reply shortcuts: passed');
})().catch(error => { console.error(error); process.exitCode = 1; });

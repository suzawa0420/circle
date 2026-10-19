const assert = require('assert');
const fs = require('fs');
const vm = require('vm');
const source = fs.readFileSync('app/assets/javascripts/conversation_notes.js', 'utf8');
function element(values = {}) {
  return Object.assign({ events: {}, dataset: {}, addEventListener(name, fn) { this.events[name] = fn; }, removeEventListener(name) { delete this.events[name]; } }, values);
}
function setup() {
  const timers = new Map(), calls = [], visits = [];
  let serial = 0;
  const input = element({ value: '' });
  const status = element({ textContent: '' });
  const retry = element({ hidden: true });
  const form = element({ action: '/conversations/private/messages-note', querySelector: selector => selector.includes('__input') ? input : selector.includes('__state') ? status : selector.includes('__retry') ? retry : { value: 'synthetic-csrf' } });
  const document = element({ readyState: 'loading', querySelectorAll: () => [form] });
  const window = element({ setTimeout(fn) { const id = ++serial; timers.set(id, fn); return id; }, clearTimeout(id) { timers.delete(id); }, Turbolinks: { visit(url) { visits.push(url); } } });
  vm.runInNewContext(source, { document, window, fetch(url, options) {
    return new Promise(resolve => calls.push({ url, options, resolve }));
  } });
  document.events.DOMContentLoaded();
  return { input, status, retry, form, document, window, calls, timers, visits,
    type(value) { input.value = value; input.events.input(); },
    tick() { const tasks = Array.from(timers.values()); timers.clear(); tasks.forEach(fn => fn()); },
    finish(index, good = true, redirected = false) { calls[index].resolve({ ok: good, redirected, json: async () => ({ saved: true }) }); }
  };
}
const settle = () => new Promise(resolve => setImmediate(resolve));
(async () => {
  const c = setup();
  c.input.events.compositionstart();
  c.type('10月'); c.tick();
  assert.equal(c.calls.length, 0, 'IME composition must not save partial input');
  c.input.events.compositionend(); c.tick();
  assert.equal(c.calls.length, 1);
  assert.equal(c.calls[0].options.method, 'PATCH');
  assert.equal(c.calls[0].options.headers['X-CSRF-Token'], 'synthetic-csrf');
  assert.equal(c.status.textContent, '保存中…');
  c.type('10月24日、参加予定'); c.tick();
  assert.equal(c.calls.length, 1, 'serialize writes to avoid stale data winning');
  c.finish(0); await settle();
  assert.equal(c.calls.length, 2);
  assert.equal(JSON.parse(c.calls[1].options.body).note.body, '10月24日、参加予定');
  c.finish(1); await settle();
  assert.equal(c.status.textContent, '保存済み');
  c.type('変更'); c.tick(); c.finish(2, false); await settle();
  assert.equal(c.status.textContent, '保存できませんでした');
  assert.equal(c.retry.hidden, false);
  assert.equal(c.input.value, '変更');
  c.retry.events.click(); c.finish(3); await settle();
  assert.equal(c.status.dataset.saved, 'true');
  c.type(''); c.input.events.blur();
  assert.equal(JSON.parse(c.calls[4].options.body).note.body, '');
  let prevented = false;
  c.document.events['turbolinks:before-visit']({ preventDefault() { prevented = true; }, data: { url: '/next' } });
  assert(prevented);
  assert.equal(c.visits.length, 0);
  c.finish(4); await settle();
  assert.deepEqual(c.visits, ['/next']);
  const auth = setup();
  auth.type('秘密のメモ'); auth.tick(); auth.finish(0, true, true); await settle();
  assert.equal(auth.status.textContent, '保存できませんでした', 'login redirects must not look like saved notes');
  const close = setup();
  close.type('未保存');
  let warned = false;
  close.window.events.beforeunload({ preventDefault() { warned = true; } });
  assert(warned);
  assert.equal(close.calls.length, 1);
  assert.equal(close.calls[0].options.keepalive, true);
  const revert = setup();
  revert.type('一時的な変更'); revert.tick(); revert.type('');
  let waitsForRevert = false;
  revert.document.events['turbolinks:before-visit']({ preventDefault() { waitsForRevert = true; }, data: { url: '/after-revert' } });
  assert(waitsForRevert, 'returning to the saved text must still wait for an older in-flight write');
  revert.finish(0); await settle();
  assert.equal(JSON.parse(revert.calls[1].options.body).note.body, '');
  assert.equal(revert.visits.length, 0);
  revert.finish(1); await settle();
  assert.deepEqual(revert.visits, ['/after-revert']);
  console.log('Private note autosave: IME, serialization, retry, clearing, navigation and session expiry passed.');
})().catch(error => { console.error(error); process.exitCode = 1; });

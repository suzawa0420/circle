const assert = require('assert');
const fs = require('fs');
const vm = require('vm');
const source = fs.readFileSync('app/assets/javascripts/schedule_share.js', 'utf8');

function setup({ clipboard = 'ok', fallback = true, native = 'ok', secure = true } = {}) {
  const copied = [], shared = [], listeners = {}, removed = [];
  const field = { value: '編集した投稿 & #日本語\n改行も保持', matches: () => true, closest: () => panel };
  const status = { textContent: '' }, manual = { hidden: true, focus() {}, select() { this.selected = true; } };
  const heading = { textContent: 'イベントを公開しました！' }, summary = { focus() { this.focused = true; } };
  const later = { hidden: false }, nativeButton = { hidden: true };
  const links = ['x', 'threads'].map(destination => ({ dataset: { shareDestination: destination } }));
  const elements = { '[data-share-text]': field, '[data-share-status]': status, '[data-share-manual]': manual,
    '[data-share-heading]': heading, '[data-share-dismiss]': later, '[data-share-native]': nativeButton, summary };
  const panel = { open: true, dataset: { shareUrl: 'https://circle-book.com/users/123/schedules/456',
    shareTitle: '公開タイトル', shareHeading: 'このイベントをSNSで知らせる', shareCreated: 'true' },
    querySelector: selector => elements[selector], querySelectorAll: () => links,
    scrollIntoView() { this.scrolled = true; } };
  const document = { readyState: 'complete', activeElement: { focus() {} },
    addEventListener(name, fn) { assert(!listeners[name], 'register delegated listeners once'); listeners[name] = fn; },
    querySelectorAll: () => [panel], querySelector: () => panel,
    body: { appendChild() {} },
    createElement() { return { style: {}, setAttribute() {}, focus() {}, select() {}, remove() { removed.push(true); } }; },
    execCommand(command) { assert.equal(command, 'copy'); return fallback; } };
  const navigator = {};
  if (clipboard !== 'missing') navigator.clipboard = { async writeText(value) {
    if (clipboard === 'denied') throw new Error('Permission denied');
    copied.push(value);
  } };
  if (native !== 'missing') navigator.share = async value => {
    if (native === 'cancel') throw Object.assign(new Error('Cancelled'), { name: 'AbortError' });
    if (native === 'error') throw Object.assign(new Error('Unavailable'), { name: 'NotAllowedError' });
    shared.push(value);
  };
  const window = { isSecureContext: secure };
  const context = vm.createContext({ document, window, navigator, encodeURIComponent });
  vm.runInContext(source, context);
  vm.runInContext(source, context);
  async function click(attribute, value) {
    const button = { dataset: { shareCopy: value }, hasAttribute: name => name === attribute, closest: () => panel };
    let prevented = false;
    await listeners.click({ target: { closest: () => button }, preventDefault() { prevented = true; } });
    return prevented;
  }
  return { panel, field, status, manual, heading, summary, later, links, nativeButton, copied, shared, removed, listeners, click };
}

(async () => {
  const c = setup();
  c.links.forEach(link => {
    const url = new URL(link.href);
    assert.equal(url.searchParams.get('text'), c.field.value);
    assert.equal(url.searchParams.get('url'), c.panel.dataset.shareUrl);
  });
  assert.equal(new URL(c.links[0].href).origin, 'https://twitter.com');
  assert.equal(new URL(c.links[1].href).origin, 'https://www.threads.com');
  c.field.value = '変更した告知 & #更新\nもう一行';
  c.listeners.input({ target: c.field });
  assert.equal(new URL(c.links[1].href).searchParams.get('text'), c.field.value);
  await c.click('data-share-copy', 'post');
  assert.equal(c.copied[0], c.field.value + '\n' + c.panel.dataset.shareUrl);
  assert.equal(c.status.textContent, '投稿文と公開URLをコピーしました。');
  await c.click('data-share-copy', 'url');
  assert.equal(c.copied[1], c.panel.dataset.shareUrl);
  await c.click('data-share-native');
  assert.equal(c.shared[0].text, c.field.value);
  assert.equal(c.shared[0].url, c.panel.dataset.shareUrl);
  assert(!c.status.textContent.includes('投稿しました'), 'opening a target does not prove publication');
  await c.click('data-share-dismiss');
  assert.equal(c.panel.open, false);
  assert.equal(c.heading.textContent, c.panel.dataset.shareHeading);
  assert(c.summary.focused);
  assert(await c.click('data-schedule-share-reopen'));
  assert(c.panel.open && c.panel.scrolled);

  const legacy = setup({ clipboard: 'missing', native: 'missing', secure: false });
  assert.equal(legacy.nativeButton.hidden, true);
  await legacy.click('data-share-copy', 'post');
  assert.equal(legacy.removed.length, 1);
  assert.equal(legacy.manual.hidden, true);
  assert.equal(legacy.status.textContent, '投稿文と公開URLをコピーしました。');

  const manual = setup({ clipboard: 'denied', fallback: false });
  await manual.click('data-share-copy', 'post');
  assert.equal(manual.manual.hidden, false);
  assert.equal(manual.manual.value, manual.field.value + '\n' + manual.panel.dataset.shareUrl);
  assert(manual.manual.selected);
  assert.equal(manual.status.textContent, '内容を選択しました。端末のコピー操作でコピーしてください。');

  const cancelled = setup({ native: 'cancel' });
  await cancelled.click('data-share-native');
  assert.equal(cancelled.copied.length, 0, 'cancelling share must not overwrite the clipboard');
  const failed = setup({ native: 'error' });
  await failed.click('data-share-native');
  assert.equal(failed.copied.length, 1);

  const cached = setup();
  cached.listeners['turbolinks:before-cache']();
  assert.equal(cached.panel.open, false);
  assert.equal(cached.panel.dataset.shareCreated, 'false');
  cached.listeners['turbolinks:load']();
  assert.equal(cached.heading.textContent, 'このイベントをSNSで知らせる');
  console.log('Schedule sharing: edited intents, public URL copying, clipboard fallback, native share, cancellation and Turbolinks passed.');
})().catch(error => { console.error(error); process.exitCode = 1; });

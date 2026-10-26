const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const code = fs.readFileSync('app/assets/javascripts/event_management.js', 'utf8');

async function copyScenario({ secure, clipboardFails, fallbackWorks }) {
  const listeners = {};
  const copied = [];
  let selected = false;
  let restored = false;
  const source = { value: 'メンバー向けの限定URL', focus() {}, select() { selected = true; } };
  const status = { textContent: '' };
  const panel = { querySelector(selector) { return selector === '.em-copy-source' ? source : status; } };
  const button = { closest(selector) { assert.equal(selector, '[data-management-copy]'); return panel; } };
  const document = {
    activeElement: { focus() { restored = true; } },
    addEventListener(name, fn) { listeners[name] = fn; },
    execCommand(command) { assert.equal(command, 'copy'); return fallbackWorks; }
  };
  const context = { window: { isSecureContext: secure }, document,
    navigator: { clipboard: { async writeText(text) { if (clipboardFails) throw new Error('denied'); copied.push(text); } } } };
  vm.runInNewContext(code, context);
  await listeners.click({ target: { closest(selector) { assert.equal(selector, '[data-management-copy-button]'); return button; } } });
  assert.equal(status.textContent, secure && !clipboardFails || fallbackWorks ? 'コピーしました。' : '内容を選択しました。端末のコピー操作でコピーしてください。');
  if (secure && !clipboardFails) {
    assert.deepEqual(copied, [source.value]);
    assert.equal(selected, false);
  } else {
    assert.equal(selected, true);
    assert.equal(restored, fallbackWorks);
  }
  // Turbolinks visits must not attach a second global handler.
  const handler = listeners.click;
  vm.runInNewContext(code, context);
  assert.equal(listeners.click, handler);
}

function imageScenario() {
  const listeners = {};
  const status = { textContent: '' };
  const preview = { replaceChildren(image) { this.image = image; } };
  const image = {};
  const revoked = [];
  const form = { querySelector(selector) { return selector === '.em-image-preview' ? preview : status; } };
  const context = {
    window: {},
    document: { addEventListener(name, fn) { listeners[name] = fn; }, createElement(tag) { assert.equal(tag, 'img'); return image; } },
    URL: { createObjectURL(file) { assert.equal(file.name, 'replacement.png'); return 'blob:local-preview'; }, revokeObjectURL(url) { revoked.push(url); } }
  };
  vm.runInNewContext(code, context);
  listeners.change({ target: {
    matches(selector) { assert.equal(selector, '[data-event-image-input]'); return true; },
    closest() { return form; }, files: [{ name: 'replacement.png', type: 'image/png' }]
  } });
  assert.equal(preview.image.src, 'blob:local-preview');
  assert.match(status.textContent, /replacement.png/);
  assert.match(status.textContent, /保存ボタン/);
  image.onload();
  assert.deepEqual(revoked, ['blob:local-preview']);
}

(async () => {
  await copyScenario({ secure: true, clipboardFails: false, fallbackWorks: false });
  await copyScenario({ secure: true, clipboardFails: true, fallbackWorks: true });
  await copyScenario({ secure: false, clipboardFails: false, fallbackWorks: false });
  imageScenario();
  console.log('Event management clipboard and replacement image preview: 4 scenarios passed');
})().catch(error => { console.error(error); process.exitCode = 1; });

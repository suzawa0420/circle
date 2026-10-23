const assert = require('assert');
const fs = require('fs');
const vm = require('vm');
function element(values = {}) {
  return Object.assign({ events: {}, dataset: {}, hidden: false,
    addEventListener(name, fn) { this.events[name] = fn; },
    removeEventListener(name) { delete this.events[name]; },
    dispatchEvent(event) { if (this.events[event.type]) this.events[event.type](event); },
    focus() { this.focused = true; }
  }, values);
}
const text = element({ value: '返信の下書き', setSelectionRange() {} });
const submit = element({ value: '送信', dataset: { disableWith: '送信中…' } });
const picker = element({ files: [{name: 'draft.jpg'}], disabled: false });
const label = element();
const preview = element();
const error = element();
const status = element({hidden: true});
const cancel = element();
const title = element({textContent: 'メッセージを返信'});
let method;
const token = element({value: 'reply-token'});
const controls = { '.chat-compose-input': text, '[type="submit"]': submit,
  '.chat-image-input': picker, '.chat-image-picker': label, '.chat-upload-preview': preview,
  '[data-upload-error]': error, '.chat-edit-status': status, '.chat-edit-cancel': cancel };
const form = element({action: '/messages', dataset: {editing: 'false'},
  querySelector(selector) { return selector === 'input[name="_method"]' ? method : (selector === 'input[name="authenticity_token"]' ? token : controls[selector]); },
  appendChild(child) { method = child; }
});
const composer = element({ querySelector: selector => selector === '.chat-compose-form' ? form : title,
  scrollIntoView() { this.scrolled = true; }
});
const document = element({querySelector: () => composer, createElement: () => element(), body: {contains: () => true}});
vm.runInNewContext(fs.readFileSync(__dirname + '/../../app/assets/javascripts/chat_message_editor.js', 'utf8'), {
  document, Event: function(type) { this.type = type; }
});
document.events.DOMContentLoaded();
const link = element({dataset: {editToken: 'patch-token-12', editUrl: '/messages/12', editBody: '元の本文\n2行目', editImage: 'true'}});
function edit(target = link) {
  let prevented = false;
  document.events.click({target: {closest: () => target}, preventDefault() { prevented = true; }});
  assert(prevented);
}
edit();
assert.equal(text.value, '元の本文\n2行目');
assert.equal(form.action, '/messages/12');
assert.equal(method.value, 'patch');
assert.equal(token.value, 'patch-token-12');
assert.equal(method.disabled, false);
assert.equal(form.dataset.editImage, 'true');
assert.equal(picker.disabled, true);
assert.equal(label.hidden, true);
assert.equal(preview.hidden, true);
assert.equal(status.hidden, false);
assert.equal(submit.value, '変更を保存');
assert.equal(submit.dataset.disableWith, '更新中…');
assert.equal(title.textContent, 'メッセージを編集');
assert(composer.scrolled && text.focused);
// Switching between messages must preserve the original reply draft.
edit(element({dataset: {editToken: 'patch-token-13', editUrl: '/messages/13', editBody: '別の本文', editImage: 'false'}}));
assert.equal(text.value, '別の本文');
assert.equal(form.action, '/messages/13');
cancel.events.click({preventDefault() {}});
assert.equal(text.value, '返信の下書き');
assert.equal(token.value, 'reply-token');
assert.equal(form.action, '/messages');
assert.equal(method.disabled, true);
assert.equal(form.dataset.editing, 'false');
assert.equal(picker.disabled, false);
assert.equal(picker.files[0].name, 'draft.jpg');
assert.equal(label.hidden, false);
assert.equal(preview.hidden, false);
assert.equal(status.hidden, true);
assert.equal(submit.value, '送信');
assert.equal(submit.dataset.disableWith, '送信中…');
// Turbolinks must not cache an editing action with a reply draft.
edit();
document.events['turbolinks:before-cache']();
assert.equal(text.value, '返信の下書き');
assert.equal(token.value, 'reply-token');
assert.equal(form.action, '/messages');
assert.equal(document.events.click, undefined);
console.log('Message composer editing, switching, draft/photo restoration and navigation: passed');

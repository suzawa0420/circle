const assert = require('assert');
const fs = require('fs');
const vm = require('vm');
function element(values = {}) {
  return Object.assign({ events: {}, hidden: false,
    addEventListener(name, callback) { this.events[name] = callback; },
    removeEventListener(name) { delete this.events[name]; },
    removeAttribute(name) { delete this[name]; },
    focus() { this.focused = true; }
  }, values);
}
const photo = element();
const name = element();
const preview = element({hidden: true, querySelector: selector => selector === 'img' ? photo : name});
const error = element({hidden: true});
const remove = element();
const picker = element({files: [], value: ''});
const text = element({value: ''});
const controls = {'.chat-image-input':picker, '.chat-compose-input':text, '.chat-upload-preview':preview, '[data-upload-error]':error, '.chat-upload-remove':remove};
const form = element({querySelector: selector => controls[selector]});
const expanded = element();
const close = element();
const viewer = element({open: false, querySelector: selector => selector === 'img' ? expanded : close,
  showModal() { this.open = true; }, close() { this.open = false; if (this.events.close) this.events.close(); }
});
const document = element({querySelector: selector => selector === '.chat-compose-form' ? form : viewer, body: {contains: () => true}});
const revoked = [];
vm.runInNewContext(fs.readFileSync(__dirname + '/../../app/assets/javascripts/chat_images.js','utf8'), {
  document, window: {dispatchEvent() {}}, Event: function() {},
  URL: {createObjectURL: () => 'blob:test', revokeObjectURL: value => revoked.push(value)}
});
document.events.DOMContentLoaded();
picker.files = [{name:'test.png', size:1024}];
picker.events.change();
assert.equal(preview.hidden, false);
assert.equal(photo.src, 'blob:test');
assert.equal(name.textContent, 'test.png');
let blocked = false;
form.events.submit({preventDefault(){blocked=true;}});
assert.equal(blocked, false, 'a photo can be sent without text');
remove.events.click();
assert.equal(preview.hidden, true);
assert.equal(picker.value, '');
assert.deepEqual(revoked, ['blob:test']);
picker.files = [];
form.events.submit({preventDefault(){blocked=true;}});
assert.equal(blocked, true, 'empty messages are stopped');
picker.files = [{name:'too-large.png',size:11*1024*1024}];
picker.events.change();
assert.equal(error.hidden, false);
assert.equal(preview.hidden, true);
const link = element({href:'/conversations/test/images/1'});
document.events.click({target:{closest:()=>link},preventDefault(){}});
assert.equal(viewer.open, true);
assert.equal(expanded.src, link.href);
close.events.click();
assert.equal(viewer.open, false);
assert.equal(link.focused, true);
assert.equal(expanded.src, undefined);
document.events['turbolinks:before-cache']();
assert.equal(document.events.click, undefined, 'navigation removes gallery listeners');
console.log('Chat image selection, validation, preview and dialog: 16 assertions passed');

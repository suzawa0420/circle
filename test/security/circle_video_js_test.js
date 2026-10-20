const assert = require('assert');
const fs = require('fs');
const vm = require('vm');
const events = {};
const player = { textContent: '', replaceChildren(frame) { this.frame = frame; this.textContent = 'playing'; } };
const dialog = {
  open: false,
  getAttribute() { return 'Abcde_123-4'; },
  querySelector() { return player; },
  showModal() { this.open = true; },
  close() { this.open = false; },
  getBoundingClientRect() { return { left: 20, right: 620, top: 20, bottom: 400 }; },
  closest() { return null; }
};
const document = {
  documentElement: { style: { overflow: 'auto' } },
  getElementById() { return dialog; },
  createElement(tag) { assert.equal(tag, 'iframe'); return {}; },
  addEventListener(name, fn) { events[name] = fn; }
};
vm.runInNewContext(fs.readFileSync('app/assets/javascripts/circle_video.js', 'utf8'), { document });
const trigger = { getAttribute() { return 'circle-video-dialog'; } };
function open() {
  let prevented = false;
  events.click({ target: { closest(selector) { return selector === '[data-circle-video-open]' ? trigger : null; } }, preventDefault() { prevented = true; } });
  return prevented;
}
function flushClose() { events.close({ target: dialog }); }
assert.equal(player.textContent, '');
assert(open());
assert(dialog.open);
assert.equal(document.documentElement.style.overflow, 'hidden');
assert.equal(player.frame.src, 'https://www.youtube-nocookie.com/embed/Abcde_123-4?autoplay=1&rel=0');
assert(player.frame.allowFullscreen);
// The close button immediately removes playback and unlocks the page.
events.click({ target: { closest(selector) { return selector === '[data-circle-video-close]' ? {} : null; } } });
assert(!dialog.open);
assert.equal(player.textContent, '');
assert.equal(document.documentElement.style.overflow, 'auto');
flushClose();
// Escape is handled by the native dialog, followed by its close event.
open();
dialog.close();
flushClose();
assert.equal(player.textContent, '');
assert.equal(document.documentElement.style.overflow, 'auto');
// Clicking inside the dialog does not dismiss it; the backdrop does.
open();
events.click({ target: dialog, clientX: 30, clientY: 30 });
assert(dialog.open);
events.click({ target: dialog, clientX: 0, clientY: 0 });
assert(!dialog.open);
assert.equal(player.textContent, '');
flushClose();
// Turbolinks must never cache an active iframe.
open();
events['turbolinks:before-cache']();
assert(!dialog.open);
assert.equal(player.textContent, '');
assert.equal(document.documentElement.style.overflow, 'auto');
flushClose();
// A delayed close event after reopening must not lose the next Escape cleanup.
open();
events.click({ target: { closest(selector) { return selector === '[data-circle-video-close]' ? {} : null; } } });
open();
flushClose();
assert(dialog.open);
assert.equal(player.textContent, 'playing');
dialog.close();
flushClose();
assert.equal(player.textContent, '');
// Browsers without dialog support keep the regular YouTube link.
dialog.showModal = undefined;
assert(!open());
assert.equal(player.textContent, '');
console.log('YouTube dialog checks passed');

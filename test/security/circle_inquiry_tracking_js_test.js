const assert = require('assert');
const fs = require('fs');
const vm = require('vm');
const source = fs.readFileSync('app/assets/javascripts/circle_inquiry_tracking.js', 'utf8');
const listeners = [];
const context = {
  window: { dataLayer: [{ event: 'gtm.js' }] },
  document: { addEventListener(name, callback) { assert.equal(name, 'click'); listeners.push(callback); } }
};
vm.runInNewContext(source, context);
vm.runInNewContext(source, context);
assert.equal(listeners.length, 1, 'bundle reloads must not duplicate clicks');
function click(matches, extra = {}) {
  listeners[0]({ target: { closest(selector) {
    assert.equal(selector, 'a[data-circle-inquiry-click]');
    return matches ? {} : null;
  } }, preventDefault() { throw new Error('tracking must not interfere with navigation or warnings'); }, ...extra });
}
click(true); // Includes a nested icon/text target resolved by closest.
click(false); // Other links, submit buttons, and warning continue links.
click(true, { defaultPrevented: true }); // Opening a warning still counts as an entry click.
listeners[0]({ target: {} });
assert.equal(context.window.dataLayer.length, 3);
assert.deepEqual(JSON.parse(JSON.stringify(context.window.dataLayer.slice(1))),
  [{ event: 'circle_inquiry_click' }, { event: 'circle_inquiry_click' }],
  'send only the event, without account/contact details or monetary values');
delete context.window.dataLayer;
click(true);
assert.equal(context.window.dataLayer[0].event, 'circle_inquiry_click', 'queue while GTM is loading');
console.log('Inquiry tracking: single binding, entry-only clicks, warning behavior and minimal payload passed');

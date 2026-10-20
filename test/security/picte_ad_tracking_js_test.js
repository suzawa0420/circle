const assert = require('assert');
const fs = require('fs');
const vm = require('vm');
const listeners = {};
const beacons = [];
const fetches = [];
let accepted = true;
let token = { content: 'synthetic-csrf-token' };
const context = {
  window: { fetch(url, options) { fetches.push({ url, options }); return Promise.resolve(); } },
  document: {
    addEventListener(name, fn) { assert(!listeners[name], 'bound twice'); listeners[name] = fn; },
    querySelector() { return token; }
  },
  navigator: { sendBeacon(url, body) { beacons.push({ url, body }); return accepted; } },
  FormData: class { constructor() { this.values = {}; } append(key, value) { this.values[key] = value; } }
};
const source = fs.readFileSync('app/assets/javascripts/picte_ad_tracking.js', 'utf8');
vm.runInNewContext(source, context);
vm.runInNewContext(source, context);
function click(placement, extra = {}, url = '/picte-ad-clicks') {
  const event = Object.assign({ type: 'click', button: 0, target: { closest() { return { dataset: { picteAdClick: placement, picteClickUrl: url } }; } } }, extra);
  listeners[event.type](event);
}
click('search');
assert.equal(beacons.length, 1);
assert.equal(fetches.length, 0);
assert.deepStrictEqual(beacons[0].body.values, { placement: 'search', authenticity_token: 'synthetic-csrf-token' });
accepted = false;
click('mypage');
assert.equal(fetches.length, 1);
assert.equal(fetches[0].options.keepalive, true);
assert.equal(fetches[0].options.credentials, 'same-origin');
click('search', { type: 'auxclick', button: 1 });
assert.equal(beacons.length, 3, 'middle click counted once');
click('search', { type: 'auxclick', button: 2 });
click('search', { defaultPrevented: true });
click('unknown');
click('search', {}, 'https://unrelated.example');
token = null;
click('search');
assert.equal(beacons.length, 3, 'invalid, cancelled and right clicks ignored');
assert.equal(context.window.dataLayer.length, 3);
assert.deepStrictEqual(Object.keys(context.window.dataLayer[0]).sort(), ['event', 'placement']);
console.log('PICTE clicks: duplicate binding, single-send beacon/fallback, middle click, minimal payload and invalid input checks passed');

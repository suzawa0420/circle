const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const script = fs.readFileSync('app/assets/javascripts/page_navigation_scroll.js', 'utf8');
const source = 'https://example.test/users/10/schedules';
const target = source + '/42';

function browser(href, initialMarker, type) {
  const documentHandlers = {};
  const windowHandlers = {};
  const scrolls = [];
  const location = new URL(href);
  const storage = { marker: initialMarker };
  const sessionStorage = {
    getItem() { return storage.marker || null; },
    setItem(_key, value) { storage.marker = value; },
    removeItem() { delete storage.marker; }
  };
  const document = { documentElement: { hasAttribute: () => false }, addEventListener(name, fn) { documentHandlers[name] = fn; } };
  const performance = { getEntriesByType: () => [{ type }] };
  const window = { performance, requestAnimationFrame(fn) { fn(); }, addEventListener(name, fn) { windowHandlers[name] = fn; }, scrollTo(...xy) { scrolls.push(xy); } };
  vm.runInNewContext(script, { window, document, sessionStorage, performance, URL, location });
  return { location, storage, documentHandlers, windowHandlers, scrolls };
}

function propose(b, url) {
  b.documentHandlers['turbolinks:before-visit']({ data: { url } });
}
function visit(b, url) {
  b.location.href = url;
  b.documentHandlers['turbolinks:visit']({ data: { url } });
}
function arrival(href, state, type, persisted = false) {
  const b = browser(href, state, type);
  b.windowHandlers.pageshow({ persisted });
  return b;
}

async function run() {
  const b = browser(source, null, 'navigate');
  propose(b, target);
  visit(b, target);
  assert.equal(JSON.parse(b.storage.marker).url, target);
  const fresh = arrival(target, b.storage.marker, 'reload');
  assert.deepEqual(fresh.scrolls, [[0, 0]]);
  assert.equal(fresh.storage.marker, undefined);
  fresh.windowHandlers.pageshow({ persisted: false });
  assert.equal(fresh.scrolls.length, 1);

  for (const [type, persisted] of [['navigate', false], ['reload', true], ['back_forward', false]]) {
    assert.deepEqual(arrival(target, b.storage.marker, type, persisted).scrolls, []);
  }
  assert.deepEqual(arrival(target, null, 'reload').scrolls, []);
  assert.deepEqual(arrival(source, b.storage.marker, 'reload').scrolls, []);
  const hash = target + '#schedule';
  assert.deepEqual(arrival(hash, JSON.stringify({ url: hash, at: Date.now() }), 'reload').scrolls, []);

  b.documentHandlers['turbolinks:render']();
  assert.equal(b.storage.marker, undefined);
  for (const href of [source + '?date=fixture', target + '#schedule', 'https://other.test/users/10']) {
    const other = browser(source, undefined, 'navigate');
    propose(other, href);
    visit(other, href);
    assert.equal(other.storage.marker, undefined);
  }

  const racing = browser(source, undefined, 'navigate');
  propose(racing, target);
  visit(racing, target);
  const otherTarget = source + '/43';
  propose(racing, otherTarget);
  visit(racing, otherTarget);
  assert.deepEqual(arrival(target, racing.storage.marker, 'reload').scrolls, []);
  assert.deepEqual(arrival(otherTarget, racing.storage.marker, 'reload').scrolls, [[0, 0]]);
  const samePath = otherTarget + '?page=2';
  propose(racing, samePath);
  visit(racing, samePath);
  assert.equal(racing.storage.marker, undefined);
  assert.deepEqual(arrival(target, JSON.stringify({ url: target, at: Date.now() - 31000 }), 'reload').scrolls, []);
  assert.deepEqual(arrival(target, null, 'reload').scrolls, []);
  const back = browser(source, undefined, 'back_forward');
  visit(back, target); // history restoration has no before-visit.
  assert.equal(back.storage.marker, undefined);
  const canceled = browser(source, undefined, 'navigate');
  propose(canceled, target);
  await Promise.resolve();
  visit(canceled, target);
  assert.equal(canceled.storage.marker, undefined);
}
void run().catch(error => { console.error(error); process.exitCode = 1; });

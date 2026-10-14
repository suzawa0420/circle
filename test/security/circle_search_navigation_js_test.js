const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync('app/assets/javascripts/circle_search_navigation.js', 'utf8');
const store = new Map();
function page({ url, referrer = '', listing = false, blocked = false }) {
  const events = {};
  const add = (name, callback) => (events[name] ||= []).push(callback);
  const backEvents = {};
  const back = { dataset: { circleSearchBack: '123' }, href: '/circles', addEventListener(name, cb) { backEvents[name] = cb; } };
  const scrolls = [];
  const context = {
    URL, Date, location: new URL(url), requestAnimationFrame: cb => cb(),
    sessionStorage: { getItem(k) { if (blocked) throw Error(); return store.get(k) || null; }, setItem(k, v) { if (blocked) throw Error(); store.set(k, v); } },
    window: { scrollY: 1450, addEventListener: add, scrollTo: (x, y) => scrolls.push(y) },
    document: { referrer, readyState: 'complete', body: { dataset: { circleSearchList: String(listing) } },
      addEventListener: add, querySelectorAll: () => listing ? [] : [back] }
  };
  vm.runInNewContext(source, context);
  vm.runInNewContext(source, context);
  assert.equal(events.click.length, 1);
  return { back, backEvents, scrolls, click(href) { events.click[0]({ target: { closest: () => ({ href }) } }); } };
}
const search = 'https://circle.example/circles/search?detailed=1&q=tokyo&sort=2&page=3';
page({ url: search, listing: true }).click('https://circle.example/circles/123');
let detail = page({ url: 'https://circle.example/circles/123', referrer: search });
assert.equal(detail.back.href, search);
detail.back.onclick();
assert.deepEqual(page({ url: search, referrer: 'https://circle.example/circles/123', listing: true }).scrolls, [1450]);
assert.deepEqual(page({ url: search, listing: true }).scrolls, [], 'consume explicit restoration once');
assert.equal(page({ url: 'https://circle.example/circles/123' }).back.href, '/circles', 'direct visits keep fallback');
assert.equal(page({ url: 'https://circle.example/circles/123', referrer: 'https://external.example/' }).back.href, '/circles');
page({ url: search, listing: true, blocked: true }).click('https://circle.example/circles/123');
assert.equal(page({ url: 'https://circle.example/circles/123', referrer: search, blocked: true }).back.href, '/circles');
for (const url of ['https://evil.example/', 'javascript:alert(1)', '//evil.example/', 'https://user:pass@circle.example/']) {
  store.set('circle-search-v1:circle:123', JSON.stringify({ url, at: Date.now(), y: 1 }));
  assert.equal(page({ url: 'https://circle.example/circles/123', referrer: search }).back.href, '/circles');
}
store.set('circle-search-v1:circle:123', JSON.stringify({ url: search, at: Date.now() - 31 * 60 * 1000, y: 1 }));
assert.equal(page({ url: 'https://circle.example/circles/123', referrer: search }).back.href, '/circles');
console.log('Search return: filters/page/scroll, once-only restore, direct/external visits, blocked storage, expiry and unsafe URL checks passed');

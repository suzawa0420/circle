const assert = require('assert');
const fs = require('fs');
const vm = require('vm');
const events = {}, windowEvents = {}, observers = [];
function section(height) {
  const classes = new Set(), attrs = {}, linkAttrs = {};
  const link = {
    getAttribute: key => linkAttrs[key] ?? null,
    setAttribute: (key, value) => { linkAttrs[key] = value; },
    removeAttribute: key => { delete linkAttrs[key]; },
    getBoundingClientRect: () => ({ bottom: 800 })
  };
  const text = {};
  const content = { style: {}, getBoundingClientRect: () => ({ top: 0 }) };
  const body = { height, getBoundingClientRect() { return { height: this.height }; }, querySelectorAll: () => [link], contains: target => target === link };
  const button = { hidden: true, getAttribute: key => key === 'data-readmore-label' ? '紹介文' : attrs[key],
    setAttribute: (key, value) => { attrs[key] = value; }, querySelector: () => text,
    closest: () => wrapper };
  const wrapper = { classList: { toggle(name, on) { if (on) classes.add(name); else classes.delete(name); }, remove(name) { classes.delete(name); } },
    querySelector: selector => ({ '.circle-readmore__content': content, '.circle-readmore__body': body, '.circle-readmore__button': button })[selector],
    getBoundingClientRect: () => ({ top: 0 }), scrollIntoView() { this.scrolled = true; } };
  return { wrapper, body, button, content, text, attrs, link, linkAttrs, classes };
}
const long = section(900), short = section(160);
const document = { readyState: 'complete', querySelectorAll: () => [long.wrapper, short.wrapper],
  getElementById: id => id === 'review-1' ? long.link : null,
  addEventListener: (name, fn) => { events[name] = fn; } };
const window = { location: { hash: '' }, getComputedStyle: () => ({ getPropertyValue: () => '320px' }),
  matchMedia: () => ({ matches: true }), ResizeObserver: true,
  addEventListener: (name, fn) => { windowEvents[name] = fn; } };
class ResizeObserver {
  constructor(fn) { this.fn = fn; observers.push(this); }
  observe() {}
  disconnect() { this.disconnected = true; }
}
long.link.scrollIntoView = function () { this.scrolled = true; };
vm.runInNewContext(fs.readFileSync('app/assets/javascripts/circle_readmore.js', 'utf8'), { document, window, ResizeObserver, Map });
function toggle(state) { events.click({ target: { closest: () => state.button } }); }
assert.equal(long.content.style.maxHeight, '320px');
assert(long.classes.has('is-collapsed'));
assert.equal(long.linkAttrs.tabindex, '-1');
assert.equal(short.button.hidden, true);
assert.equal(short.content.style.maxHeight, '');
toggle(long);
assert.equal(long.attrs['aria-expanded'], 'true');
assert.equal(long.text.textContent, '閉じる');
assert.equal(long.content.style.maxHeight, '900px');
assert(!('tabindex' in long.linkAttrs));
assert.equal(short.button.hidden, true);
toggle(long);
assert.equal(long.attrs['aria-expanded'], 'false');
assert.equal(long.text.textContent, 'もっと見る');
// Re-measure after a responsive layout change or an image/FAQ changes height.
long.body.height = 200;
observers[0].fn();
assert(long.button.hidden);
assert.equal(long.content.style.maxHeight, '');
assert(!('tabindex' in long.linkAttrs));
long.body.height = 1000;
windowEvents.resize();
assert(!long.button.hidden);
assert.equal(long.content.style.maxHeight, '320px');
// Incoming review links expand the matching section before scrolling.
window.location.hash = '#review-1';
windowEvents.hashchange();
assert.equal(long.attrs['aria-expanded'], 'true');
assert.equal(long.link.scrolled, true);
assert.equal(long.content.style.maxHeight, '1000px');
// Turbolinks snapshots never retain clipped content or disabled links.
events['turbolinks:before-cache']();
assert(observers.every(observer => observer.disconnected));
assert.equal(long.content.style.maxHeight, '');
assert(long.button.hidden);
assert(!long.classes.has('is-collapsed'));
assert(!('tabindex' in long.linkAttrs));
window.location.hash = '';
events['turbolinks:load']();
assert.equal(long.attrs['aria-expanded'], 'false');
assert.equal(long.content.style.maxHeight, '320px');
console.log('Read-more collapse, resize, focus, anchors and Turbolinks checks passed');

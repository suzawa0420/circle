const assert = require('assert');
const fs = require('fs');
const vm = require('vm');
const source = fs.readFileSync('app/assets/javascripts/circle_level_up.js', 'utf8');

function setup(reduced = false, hidden = false, supported = true) {
  const events = {}, frames = [], animations = [], timers = new Map();
  var timerId = 0;
  const layer = { textContent: '', appendChild() {} };
  const focus = { isConnected: true, focus() { this.restored = true; } };
  const animate = function () {
    let reject;
    const animation = { finished: new Promise((_, no) => { reject = no; }), cancel() { this.cancelled = true; reject(new Error('cancelled')); } };
    animations.push(animation);
    return animation;
  };
  const dialog = { dataset: {}, open: false, showModal() { this.open = true; }, close() { this.open = false; },
    addEventListener() {}, removeAttribute() { this.open = false; },
    getBoundingClientRect() { return {top:100,left:16,right:374,bottom:650,height:550}; },
    querySelector(selector) { return selector.includes('confetti') ? layer : { animate }; } };
  const mode = { matches: reduced, addEventListener(_, fn) { this.changed = fn; } };
  const document = { activeElement: focus, visibilityState: hidden ? 'hidden' : 'visible', documentElement: { clientWidth:390, style: {overflow:'auto'} },
    querySelector() { return dialog; }, createElement() { return {style:{},animate}; },
    addEventListener(type, fn) { (events[type] ||= []).push(fn); } };
  vm.runInNewContext(source, { document, window: { matchMedia() { return mode; },innerHeight:844,
    setTimeout(fn) { timers.set(++timerId,fn); return timerId; }, clearTimeout(id) { timers.delete(id); } },
    Element: {prototype:supported ? {animate} : {}}, Promise, Math, requestAnimationFrame(fn) {frames.push(fn);} });
  const emit = (type, event = {}) => (events[type] || []).forEach(fn => fn(event));
  const tick = () => { Array.from(timers.values()).forEach(fn=>fn());timers.clear();while (frames.length) frames.shift()(); };
  const click = selector => emit('click',{target:{closest(query) {return query === selector;}}});
  return { dialog, mode, animations, document, focus, emit, tick, click, timers };
}

(async () => {
  let app = setup();
  app.emit('DOMContentLoaded');
  assert(app.dialog.open, 'opens on the dashboard');
  assert.equal(app.document.documentElement.style.overflow, 'hidden');
  app.emit('turbolinks:load'); app.tick();
  assert.equal(app.animations.length,65,'one number bounce and one burst, even with both load events');
  app.click('[data-level-up-close], .circle-level-up__primary');
  assert.equal(app.dialog.open,false,'can close immediately during motion');
  assert(app.animations.every(a => a.cancelled),'closing cancels every animation');
  assert.equal(app.document.documentElement.style.overflow,'auto');
  assert(app.focus.restored);
  app.emit('turbolinks:load'); app.tick();
  assert.equal(app.dialog.open,false,'cached page never celebrates twice');

  app = setup(true); app.emit('turbolinks:load'); app.tick();
  assert(app.dialog.open,'reduced motion still shows the notification');
  assert.equal(app.animations.length,0,'reduced motion suppresses all effects');
  app.emit('turbolinks:before-cache');
  app = setup(false,true); app.emit('DOMContentLoaded'); app.tick();
  assert.equal(app.animations.length,0,'never spends the short burst while the page is hidden');
  app.document.visibilityState='visible'; app.emit('visibilitychange'); app.tick();
  assert.equal(app.animations.length,65,'starts after the page becomes visible');
  app.emit('turbolinks:before-cache');
  app = setup(); app.emit('DOMContentLoaded');
  app.click('[data-level-up-close], .circle-level-up__primary'); app.tick();
  assert.equal(app.animations.length,0,'closing before the delay cancels the scheduled burst');
  app = setup(false,false,false); app.emit('DOMContentLoaded'); app.tick();
  assert.equal(app.animations.length,0);
  assert(app.dialog.open,'unsupported effects do not hide the notification');
  app.emit('turbolinks:before-cache');
  assert.equal(app.dialog.open,false);
  assert.equal(app.document.documentElement.style.overflow,'auto');

  app = setup(); app.emit('turbolinks:load'); app.tick();
  app.mode.matches = true; app.mode.changed();
  assert(app.animations.every(a => a.cancelled),'motion preference changes stop an in-flight burst');
  assert(app.dialog.open);
  app.emit('turbolinks:before-cache');
  app = setup(); app.document.querySelector = () => null;
  app.emit('DOMContentLoaded'); app.tick();
  assert.equal(app.animations.length,0,'pages without an actual notification do not animate');
  await new Promise(resolve => setImmediate(resolve));
  assert(!source.includes('data-level-up-replay') && !source.includes('data-level-up-preview'),'manual effect controls are removed');
  console.log('Level-up dialog: automatic visible startup, reduced motion, one-time lifecycle, no manual controls, cleanup, focus and scroll restoration passed');
})().catch(error => {console.error(error);process.exit(1);});

const assert = require('assert');
const fs = require('fs');
const vm = require('vm');
const source = fs.readFileSync('app/assets/javascripts/circle_level_up.js', 'utf8');

function setup(reduced = false, hidden = false, supported = true, previewOnly = false) {
  const events = {}, frames = [], animations = [], timers = new Map();
  var timerId = 0;
  const layer = { textContent: '', appendChild() {} };
  const replay = { hidden: true, textContent: '' };
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
    querySelector(selector) { return selector.includes('confetti') ? layer : selector.includes('replay') ? replay : { animate }; } };
  const mode = { matches: reduced, addEventListener(_, fn) { this.changed = fn; } };
  const document = { activeElement: focus, visibilityState: hidden ? 'hidden' : 'visible', documentElement: { clientWidth:390, style: {overflow:'auto'} },
    querySelector() { return previewOnly ? null : dialog; }, getElementById() { return dialog; }, createElement() { return {style:{},animate}; },
    addEventListener(type, fn) { (events[type] ||= []).push(fn); } };
  vm.runInNewContext(source, { document, window: { matchMedia() { return mode; },innerHeight:844,
    setTimeout(fn) { timers.set(++timerId,fn); return timerId; }, clearTimeout(id) { timers.delete(id); } },
    Element: {prototype:supported ? {animate} : {}}, Promise, Math, requestAnimationFrame(fn) {frames.push(fn);} });
  const emit = (type, event = {}) => (events[type] || []).forEach(fn => fn(event));
  const tick = () => { Array.from(timers.values()).forEach(fn=>fn());timers.clear();while (frames.length) frames.shift()(); };
  const click = selector => emit('click',{target:{closest(query) {return query === selector;}}});
  return { dialog, mode, animations, document, focus, replay, emit, tick, click, timers };
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
  assert.ok(app.replay.textContent.includes('動きあり'),'explicit motion opt-in label');
  app.click('[data-level-up-replay]');
  assert.equal(app.animations.length,65,'explicit labelled tap replays on a reduced-motion device');
  assert.equal(app.dialog.dataset.motionConsented,'true');
  app.emit('turbolinks:before-cache');
  app = setup(false,true); app.emit('DOMContentLoaded'); app.tick();
  assert.equal(app.animations.length,0,'never spends the short burst while the page is hidden');
  app.document.visibilityState='visible'; app.emit('visibilitychange'); app.tick();
  assert.equal(app.animations.length,65,'starts after the page becomes visible');
  app.click('[data-level-up-replay]'); app.tick();
  assert.equal(app.animations.length,130,'manual replay does not race with pending auto play');
  assert(app.animations.slice(0,65).every(a=>a.cancelled));
  app.emit('turbolinks:before-cache');
  app = setup(); app.emit('DOMContentLoaded');
  app.click('[data-level-up-close], .circle-level-up__primary'); app.tick();
  assert.equal(app.animations.length,0,'closing before the delay cancels the scheduled burst');
  app = setup(false,false,false); app.emit('DOMContentLoaded'); app.tick();
  assert.equal(app.replay.hidden,true);
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
  app = setup(false,false,true,true); app.emit('DOMContentLoaded'); app.tick();
  assert.equal(app.dialog.open,false,'preview never opens automatically');
  const trigger={getAttribute() {return 'circle-level-preview';}};
  app.emit('click',{target:{closest(query) {return query==='[data-level-up-preview]' ? trigger : null;}}});
  app.tick();
  assert(app.dialog.open,'owner can test the effect after a previous notification was consumed');
  assert.equal(app.animations.length,65);
  app.emit('turbolinks:before-cache');
  await new Promise(resolve => setImmediate(resolve));
  console.log('Level-up dialog: delayed visible startup, replay, explicit reduced-motion opt-in, unsupported fallback, one-time lifecycle, cleanup, focus and scroll restoration passed');
})().catch(error => {console.error(error);process.exit(1);});

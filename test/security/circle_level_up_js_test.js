const assert = require('assert');
const fs = require('fs');
const vm = require('vm');
const source = fs.readFileSync('app/assets/javascripts/circle_level_up.js', 'utf8');

function setup(reduced = false) {
  const events = {}, frames = [], animations = [];
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
  const document = { activeElement: focus, documentElement: { clientWidth:390, style: {overflow:'auto'} },
    querySelector() { return dialog; }, createElement() { return {style:{},animate}; },
    addEventListener(type, fn) { (events[type] ||= []).push(fn); } };
  vm.runInNewContext(source, { document, window: { matchMedia() { return mode; },innerHeight:844 },
    Element: {prototype:{animate}}, Promise, Math, requestAnimationFrame(fn) {frames.push(fn);} });
  const emit = (type, event = {}) => (events[type] || []).forEach(fn => fn(event));
  const tick = () => { while (frames.length) frames.shift()(); };
  return { dialog, mode, animations, document, focus, emit, tick };
}

(async () => {
  let app = setup();
  app.emit('DOMContentLoaded');
  assert(app.dialog.open, 'opens on the dashboard');
  assert.equal(app.document.documentElement.style.overflow, 'hidden');
  app.emit('turbolinks:load'); app.tick();
  assert.equal(app.animations.length,65,'one number bounce and one burst, even with both load events');
  app.emit('click',{target:{closest() {return true;}}});
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
  assert.equal(app.dialog.open,false);
  assert.equal(app.document.documentElement.style.overflow,'auto');

  app = setup(); app.emit('turbolinks:load'); app.tick();
  app.mode.matches = true; app.mode.changed();
  assert(app.animations.every(a => a.cancelled),'motion preference changes stop an in-flight burst');
  assert(app.dialog.open);
  app.emit('turbolinks:before-cache');
  await new Promise(resolve => setImmediate(resolve));
  console.log('Level-up dialog: one-time lifecycle, motion preference, close during confetti, focus and scroll restoration passed');
})().catch(error => {console.error(error);process.exit(1);});

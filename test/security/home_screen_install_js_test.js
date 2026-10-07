const assert = require('assert');
const fs = require('fs');
const vm = require('vm');
const source = fs.readFileSync('app/assets/javascripts/home_screen_install.js', 'utf8');

function setup(options = {}) {
  const events = {};
  const buttons = [{ hidden: true, focus() { this.focused = true; }, closest() { return null; } }];
  const sections = ['ios', 'android', 'other'].map(kind => ({ hidden: true, getAttribute() { return kind; } }));
  const note = { hidden: true }, error = { hidden: true };
  const panel = { open: false, showModal() { this.open = true; }, close() { this.open = false; },
    querySelectorAll() { return sections; },
    querySelector(selector) { return selector === '[data-install-error]' ? error : note; } };
  const mode = { matches: !!options.standalone, addEventListener(name, fn) { this.change = fn; } };
  const document = { body: { contains() { return true; } },
    querySelectorAll() { return buttons; }, querySelector() { return buttons[0]; },
    getElementById() { return panel; },
    addEventListener(name, fn) { (events[name] ||= []).push(fn); },
    dispatchEvent(event) { (events[event.type] || []).forEach(fn => fn(event)); } };
  const window = { matchMedia() { return mode; }, addEventListener: document.addEventListener };
  const context = { document, window, navigator: { userAgent: options.ua || 'Android Chrome',
    platform: options.platform || '', maxTouchPoints: options.touch || 0, standalone: options.appleStandalone },
    Event: function(type) { this.type = type; }, Promise };
  vm.runInNewContext(source, context);
  function emit(type, values = {}) { document.dispatchEvent({ type, ...values }); }
  function click() { emit('click', { target: { closest(selector) { return selector === '[data-home-screen-install]' ? buttons[0] : null; } } }); }
  return { buttons, sections, panel, note, error, mode, events, context, emit, click };
}

(async function () {
  let app = setup({ ua: 'iPhone Version/26 Safari' });
  assert.equal(app.buttons[0].hidden, false);
  app.click();
  assert.equal(app.panel.open, true);
  assert.equal(app.sections[0].hidden, false);
  assert.equal(app.sections[1].hidden, true);
  assert.equal(app.note.hidden, true);
  let prevented = false;
  app.emit('cancel', { target: app.panel, preventDefault() { prevented = true; } });
  assert(prevented);
  assert.equal(app.panel.open, false);
  assert(app.buttons[0].focused);
  app = setup({ ua: 'iPhone CriOS Safari' }); app.click(); assert.equal(app.note.hidden, false);
  app = setup({ ua: 'Macintosh Safari', platform: 'MacIntel', touch: 5 });
  app.click(); assert.equal(app.sections[0].hidden, false, 'iPad desktop user agent');
  app = setup(); app.click(); assert.equal(app.sections[1].hidden, false, 'Android manual fallback');
  app.emit('turbolinks:before-cache'); assert.equal(app.panel.open, false);
  app = setup({ standalone: true }); assert.equal(app.buttons[0].hidden, true);
  app = setup({ appleStandalone: true, ua: 'iPhone Safari' }); assert.equal(app.buttons[0].hidden, true);
  app = setup(); let calls = 0;
  const prompt = { preventDefault() { this.prevented = true; },
    prompt() { calls++; return Promise.resolve(); }, userChoice: Promise.resolve({ outcome: 'dismissed' }) };
  app.emit('beforeinstallprompt', prompt); app.click();
  assert.equal(calls, 1, 'native prompt runs synchronously in the tap');
  assert.equal(app.panel.open, false);
  await new Promise(resolve => setImmediate(resolve));
  app.click(); assert.equal(calls, 1, 'prompt is never reused after dismissal');
  assert.equal(app.panel.open, true, 'manual fallback after dismissal');
  app.emit('appinstalled'); assert.equal(app.buttons[0].hidden, true); assert.equal(app.panel.open, false);
  app = setup();
  app.emit('beforeinstallprompt', { preventDefault() {}, prompt() {}, userChoice: Promise.resolve({ outcome: 'accepted' }) });
  app.click(); await new Promise(resolve => setImmediate(resolve));
  assert.equal(app.buttons[0].hidden, true, 'accepted installation hides the action');
  app = setup();
  app.emit('beforeinstallprompt', { preventDefault() {}, prompt() { throw new Error('unavailable'); } });
  app.click(); assert.equal(app.error.hidden, false, 'synchronous prompt failure has manual guidance');
  app = setup();
  app.emit('beforeinstallprompt', { preventDefault() {}, prompt() { return Promise.reject(new Error('unavailable')); } });
  app.click(); await new Promise(resolve => setImmediate(resolve));
  assert.equal(app.error.hidden, false); assert.equal(app.panel.open, true);
  app = setup(); app.buttons[0].closest = () => ({ open: true });
  let closedMenu = false; app.events['circle:close-mobile-menu'] = [() => { closedMenu = true; }];
  app.click(); assert(closedMenu, 'existing mobile menu closes before instruction dialog');
  const listenerCount = app.events.click.length;
  vm.runInNewContext(source, app.context);
  assert.equal(app.events.click.length, listenerCount, 'bundles do not duplicate listeners');
  app = setup({ ua: 'Desktop Chrome' }); assert.equal(app.buttons[0].hidden, true);
  app.emit('beforeinstallprompt', { preventDefault() {} }); assert.equal(app.buttons[0].hidden, false);
  app.mode.matches = true; app.mode.change(); assert.equal(app.buttons[0].hidden, true);
  const manifest = JSON.parse(fs.readFileSync('public/manifest.webmanifest'));
  assert.equal(manifest.display, 'standalone'); assert.equal(manifest.start_url, '/');
  for (const icon of manifest.icons) {
    const png = fs.readFileSync('public' + icon.src);
    assert.equal(`${png.readUInt32BE(16)}x${png.readUInt32BE(20)}`, icon.sizes);
  }
  console.log('Home screen install: device guidance, prompt lifecycle, navigation and manifest passed');
})().catch(error => { console.error(error); process.exit(1); });

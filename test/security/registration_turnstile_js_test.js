// Node-only lifecycle test. No browser, network, real credentials or packages.
const assert = require('assert');
const fs = require('fs');
const vm = require('vm');
const source = fs.readFileSync(__dirname + '/../../app/assets/javascripts/registration_turnstile.js', 'utf8');

function harness() {
  const events = {};
  const scripts = [];
  const widgets = [];
  const removed = [];
  let elements = [];
  const window = {};
  const document = {
    querySelector: () => elements[0] || null,
    querySelectorAll: () => elements,
    addEventListener: (name, callback) => { events[name] = callback; },
    createElement: () => ({ remove() { this.removed = true; } }),
    head: { appendChild: script => scripts.push(script) }
  };
  vm.runInNewContext(source, { window, document });
  return {
    events, scripts, widgets, removed, window,
    addForm() {
      const attrs = { 'data-sitekey': 'dummy-public-site-key' };
      const node = {
        nextElementSibling: { textContent: '' },
        hasAttribute: key => key in attrs,
        getAttribute: key => attrs[key],
        setAttribute: (key, value) => { attrs[key] = value; },
        removeAttribute: key => { delete attrs[key]; }
      };
      elements = [node];
      return node;
    },
    ready() {
      window.turnstile = {
        render(node, options) { widgets.push({ node, options }); return String(widgets.length); },
        remove(id) { removed.push(id); }
      };
      window.circleRegistrationTurnstileReady();
    }
  };
}

const page = harness();
page.events['DOMContentLoaded']();
assert.equal(page.scripts.length, 0, 'ordinary pages must not load Cloudflare');
const node = page.addForm();
page.events['turbolinks:load']();
page.events['DOMContentLoaded']();
assert.equal(page.scripts.length, 1, 'one loader across duplicate events');
assert.equal(page.scripts[0].src, 'https://challenges.cloudflare.com/turnstile/v0/api.js?onload=circleRegistrationTurnstileReady&render=explicit');
page.ready();
page.events['turbolinks:load']();
assert.equal(page.widgets.length, 1, 'one widget per form');
const options = page.widgets[0].options;
assert.equal(options.sitekey, 'dummy-public-site-key');
assert.equal(options.action, 'registration');
assert.equal(options['refresh-expired'], 'auto');
options.callback();
assert.match(node.nextElementSibling.textContent, /認証が完了/);
options['expired-callback']();
assert.match(node.nextElementSibling.textContent, /有効期限/);
options['error-callback']();
assert.match(node.nextElementSibling.textContent, /再読み込み/);
page.events['turbolinks:before-cache']();
assert.deepEqual(page.removed, ['1']);
assert.equal(node.hasAttribute('data-widget-id'), false);
page.events['turbolinks:load']();
assert.equal(page.widgets.length, 2, 'back navigation renders a fresh challenge');
assert.equal(page.scripts.length, 1);

const failure = harness();
const failedNode = failure.addForm();
failure.events['DOMContentLoaded']();
failure.scripts[0].onerror();
assert.match(failedNode.nextElementSibling.textContent, /通信状態/);
assert.equal(failure.scripts[0].removed, true);
failure.events['turbolinks:load']();
assert.equal(failure.scripts.length, 2, 'failed loader can be retried');
console.log('Turnstile JavaScript lifecycle checks passed');

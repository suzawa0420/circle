const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const report = { open: true };
const events = {};
const document = {
  readyState: 'loading',
  getElementById(id) { return id === 'chat-profile-report' ? report : null; },
  querySelector() { return null; },
  addEventListener(name, fn) { events[name] = fn; }
};
vm.runInNewContext(fs.readFileSync('app/assets/javascripts/conversations.js', 'utf8'), {
  document, window: { clearTimeout() {} }
});
for (const event of ['DOMContentLoaded', 'turbolinks:before-cache', 'turbolinks:load']) {
  report.open = true;
  events[event]();
  assert.equal(report.open, false, `${event} must reset report disclosure`);
}
console.log('chat report: initial load, cache storage and navigation restore close disclosure');

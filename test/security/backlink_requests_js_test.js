const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const model = fs.readFileSync('app/models/backlink_request.rb', 'utf8');
const domains = model.match(/SNS_DOMAINS = %w\[([^\]]+)\]/)[1].split(/\s+/);
const message = model.match(/SNS_URL_ERROR = '([^']+)'/)[1];
const handlers = {};
const error = {};
const field = {
  value: '', dataset: {backlinkSnsDomains: JSON.stringify(domains), backlinkSnsError: message},
  matches: selector => selector === '[data-backlink-sns-domains]',
  setCustomValidity(value) { this.validationMessage = value; },
  setAttribute(key, value) { this[key] = value; },
  reportValidity() { this.reported = true; }
};
const document = {
  addEventListener(type, callback) { (handlers[type] ||= []).push(callback); },
  getElementById: () => error,
  querySelectorAll: () => [field]
};
vm.runInNewContext(fs.readFileSync('app/assets/javascripts/backlink_requests.js', 'utf8'), {document, URL});
function dispatch(type, target) { handlers[type].forEach(callback => callback({target})); }
for (const domain of domains) {
  for (const url of [`https://${domain}/a`, ` HTTPS://M.${domain.toUpperCase()}./a `]) {
    field.value = url;
    dispatch('input', field);
    assert.equal(field.validationMessage, message, url);
    assert.equal(error.hidden, false);
    assert.equal(field['aria-invalid'], 'true');
  }
}
for (const url of ['https://example.com/note', 'https://notfacebook.com/', 'https://instagram.com.example.org/', 'not a URL', 'https://example.com/?next=https://x.com']) {
  field.value = url;
  dispatch('change', field);
  assert.equal(field.validationMessage, '', url);
  assert.equal(error.hidden, true);
}
field.value = 'https://%69nstagram.com/a';
dispatch('turbolinks:load', document);
assert.equal(field.validationMessage, message);
let prevented = false, stopped = false;
handlers.submit[0]({target: {querySelector: () => field}, preventDefault() {prevented = true;}, stopImmediatePropagation() {stopped = true;}});
assert.ok(prevented && stopped && field.reported);
field.value = 'https://example.com/';
dispatch('input', field);
assert.equal(field.validationMessage, '');
assert.equal(field['aria-invalid'], 'false');
console.log('SNS client validation: all domains, host boundaries, correction, restore and submit prevention passed');

const assert = require('assert');
const fs = require('fs');
const vm = require('vm');
const events = {};
function input(attributes, value) {
  return { checked: false, value, getAttribute: key => attributes[key] || null,
    hasAttribute: key => Object.prototype.hasOwnProperty.call(attributes, key) };
}
const items = [input({ form: 'first', 'data-bulk-owner': true }, '1'),
  input({ form: 'first', 'data-bulk-owner': true }, '1'),
  input({ form: 'first', 'data-bulk-owner': true }, '2'),
  input({ form: 'second', 'data-bulk-owner': true }, '3')];
const all = input({ 'data-bulk-select-all': 'first' });
const count = {};
const document = {
  addEventListener: (name, handler) => { events[name] = handler; },
  querySelectorAll: selector => selector === 'input[data-bulk-owner]' ? items : [all],
  querySelector: selector => selector.startsWith('[data-bulk-count=') ? count : all
};
vm.runInNewContext(fs.readFileSync('app/assets/javascripts/webmaster_bulk_selection.js', 'utf8'), { document });
all.checked = true;
events.change({ target: all });
assert.deepEqual(items.map(item => item.checked), [true, true, true, false]);
assert.equal(count.textContent, '2主催者選択');
items[0].checked = false;
events.change({ target: items[0] });
assert.equal(all.checked, false);
assert.equal(all.indeterminate, true);
assert.equal(count.textContent, '2主催者選択');
all.checked = false;
events.change({ target: all });
assert(items.every(item => !item.checked));
assert.equal(count.textContent, '0主催者選択');
items[2].checked = true;
events['turbolinks:load']();
assert.equal(count.textContent, '1主催者選択');
assert.equal(all.indeterminate, true);
console.log('Bulk selection: scope, unique counts, deselection and navigation passed');

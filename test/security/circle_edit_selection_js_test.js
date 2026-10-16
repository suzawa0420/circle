const assert = require('assert');
const fs = require('fs');
const vm = require('vm');
const events = {};
function group(states) {
  const all = { checked: false, indeterminate: false };
  const cities = states.map(checked => ({ checked }));
  const result = { all, cities,
    querySelector: () => all,
    querySelectorAll: () => cities };
  [all, ...cities].forEach(item => {
    item.matches = () => true;
    item.closest = () => result;
    item.hasAttribute = () => item === all;
  });
  return result;
}
const main = group([true, false, false]);
const sub = group([true, true]);
const empty = group([]);
vm.runInNewContext(fs.readFileSync('app/assets/javascripts/circle_edit_selection.js', 'utf8'), {
  document: { addEventListener: (name, handler) => { events[name] = handler; },
    querySelectorAll: () => [main, sub, empty] }
});
events['turbolinks:load']();
assert(main.all.indeterminate);
assert(!main.all.checked);
assert(sub.all.checked);
assert(!empty.all.checked);
main.all.checked = true;
events.change({ target: main.all });
assert(main.cities.every(city => city.checked));
assert(main.all.checked && !main.all.indeterminate);
main.cities[0].checked = false;
events.change({ target: main.cities[0] });
assert(!main.all.checked && main.all.indeterminate);
main.all.checked = false;
events.change({ target: main.all });
assert(main.cities.every(city => !city.checked));
assert(!main.all.indeterminate);
assert(sub.cities.every(city => city.checked));
main.cities.forEach(city => { city.checked = true; });
events.change({ target: main.cities[2] });
assert(main.all.checked && !main.all.indeterminate);
main.cities[0].checked = false;
events['DOMContentLoaded']();
assert(main.all.indeterminate);
events.change({ target: { matches: () => false } });
events.change({ target: { matches: () => true, closest: () => null } });
console.log('Circle edit: select all, clear all, mixed state, prefecture isolation and navigation passed');

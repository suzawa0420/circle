const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync('app/assets/javascripts/circle_city_search.js', 'utf8');
const events = {};
const requests = [];
const prefecture = { value: '13' };
const city = {
  dataset: { prefectureId: '13', citiesUrl: '/circles/search/cities' },
  value: '101', disabled: false, options: [],
  replaceChildren(option) { this.options = [option]; this.value = option.value; },
  add(option) { this.options.push(option); }
};
const status = {};
const form = { querySelector(selector) {
  return selector === '[name="prefecture_id"]' ? prefecture : selector === '[name="city_id"]' ? city : status;
} };
const add = (name, callback) => { (events[name] ||= []).push(callback); };
const context = {
  URL, location: { origin: 'https://circle.example' },
  Option: function (text, value) { this.text = text; this.value = String(value); },
  window: { addEventListener: add },
  document: { readyState: 'complete', addEventListener: add, querySelectorAll: () => [form] },
  fetch: (url, options) => new Promise((resolve, reject) => requests.push({ url, options, resolve, reject }))
};
vm.runInNewContext(source, context);
vm.runInNewContext(source, context);
assert.equal(events.pageshow.length, 1);
assert.equal(requests.length, 0, 'server-rendered selected city is retained');
assert.equal(city.value, '101');

(async () => {
  prefecture.value = '14';
  const first = prefecture.onchange();
  assert.equal(city.disabled, true);
  assert.equal(city.value, '', 'changing prefecture clears city immediately, before submit');
  assert.equal(requests[0].url.searchParams.get('prefecture_id'), '14');
  assert.equal(requests[0].url.origin, 'https://circle.example');
  prefecture.value = '27';
  const second = prefecture.onchange();
  requests[1].resolve({ ok: true, json: async () => [{ id: 271, name: '大阪市' }] });
  await second;
  assert.equal(city.disabled, false);
  assert.equal(city.options[1].text, '大阪市');
  requests[0].resolve({ ok: true, json: async () => [{ id: 141, name: '横浜市' }] });
  await first;
  assert.equal(city.options[1].text, '大阪市', 'stale responses cannot replace current options');
  prefecture.value = '';
  await prefecture.onchange();
  assert.equal(city.disabled, true);
  assert.equal(city.options[0].text, '都道府県を選択してください');
  prefecture.value = '13';
  const failure = prefecture.onchange();
  requests[2].reject(new Error('offline'));
  await failure;
  assert.equal(city.disabled, true);
  assert.match(status.textContent, /選び直す/);
  const retry = prefecture.onchange();
  requests[3].resolve({ ok: true, json: async () => [{ id: 131, name: '渋谷区' }] });
  await retry;
  assert.equal(city.options[1].text, '渋谷区');
  assert.equal(city.disabled, false);
  // A restored/cached form whose prefecture changed gets fresh city options.
  prefecture.value = '14';
  events.pageshow[0]();
  assert.equal(city.disabled, true);
  requests[4].resolve({ ok: true, json: async () => [] });
  await new Promise(resolve => setImmediate(resolve));
  assert.match(status.textContent, /ありません/);
  // Restoring while a request was in flight must not strand a disabled select,
  // and a response from the previous ready() handler must not win the race.
  prefecture.value = '27';
  const interrupted = prefecture.onchange();
  events.pageshow[0]();
  assert.equal(requests.length, 7);
  requests[6].resolve({ ok: true, json: async () => [{ id: 272, name: '堺市' }] });
  await new Promise(resolve => setImmediate(resolve));
  requests[5].resolve({ ok: true, json: async () => [{ id: 271, name: '大阪市' }] });
  await interrupted;
  assert.equal(city.options[1].text, '堺市');
  assert.equal(city.disabled, false);
  context.window.history = { state: { turbolinks: 'keep' }, replaceState(state) { this.state = state; } };
  city.value = '272';
  city.onchange();
  assert.equal(context.window.history.state.turbolinks, 'keep');
  assert.equal(context.window.history.state.circleCitySearch.city, '272');
  form.onsubmit();
  // A history traversal can rebuild the original server form before dynamically
  // loaded options are restored. Restore only a city present in the new response.
  prefecture.value = '';
  city.dataset.prefectureId = '';
  city.disabled = true;
  events.pageshow[0]();
  assert.equal(prefecture.value, '27');
  requests[7].resolve({ ok: true, json: async () => [{ id: 272, name: '堺市' }] });
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(city.value, '272');
  context.window.history.state.circleCitySearch.city = '999';
  city.dataset.prefectureId = '';
  events.pageshow[0]();
  requests[8].resolve({ ok: true, json: async () => [{ id: 272, name: '堺市' }] });
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(city.value, '', 'stale city cannot be resurrected from history');
  context.window.history.replaceState = () => { throw new Error('blocked'); };
  assert.doesNotThrow(() => city.onchange());
  console.log('Municipality select: reset, races, failure/retry, restored in-flight forms, history selection, stale-city validation and blocked history passed');
})().catch(error => { console.error(error); process.exitCode = 1; });

(function () {
  if (window.circleCitySearchInstalled) return;
  window.circleCitySearchInstalled = true;

  function ready() {
    document.querySelectorAll('.cb-circle-search-form').forEach(function (form) {
      var prefecture = form.querySelector('[name="prefecture_id"]');
      var city = form.querySelector('[name="city_id"]');
      if (!prefecture || !city) return;
      var status = form.querySelector('[data-city-status]');
      function remember() {
        try {
          if (!window.history) return;
          var state = Object.assign({}, window.history.state || {});
          state.circleCitySearch = { prefecture: prefecture.value, city: city.value };
          window.history.replaceState(state, '');
        } catch (_) { /* Browsing remains available when history access is blocked. */ }
      }
      function reset(label) {
        city.replaceChildren(new Option(label, ''));
        city.disabled = true;
      }
      async function update(selectedCity) {
        var current = city.circleCityRequest = (city.circleCityRequest || 0) + 1;
        city.dataset.prefectureId = prefecture.value;
        reset(prefecture.value ? '読み込み中…' : '都道府県を選択してください');
        status.textContent = prefecture.value ? '市区町村を読み込んでいます。' : '市区町村は1つ選択できます。';
        if (!prefecture.value) return;
        try {
          var url = new URL(city.dataset.citiesUrl, location.origin);
          url.searchParams.set('prefecture_id', prefecture.value);
          var response = await fetch(url, { headers: { Accept: 'application/json' }, credentials: 'same-origin' });
          if (!response.ok) throw new Error('City options unavailable');
          var cities = await response.json();
          if (current !== city.circleCityRequest) return;
          city.replaceChildren(new Option('指定なし（都道府県全域）', ''));
          cities.forEach(function (item) { city.add(new Option(item.name, item.id)); });
          if (selectedCity && cities.some(function (item) { return String(item.id) === selectedCity; })) city.value = selectedCity;
          city.disabled = false;
          status.textContent = cities.length ? '市区町村を選んで、そのまま検索できます。' : '選択できる市区町村がありません。都道府県全域で検索できます。';
        } catch (_) {
          if (current !== city.circleCityRequest) return;
          reset('市区町村を読み込めませんでした');
          status.textContent = '都道府県を選び直すと再読み込みできます。市区町村を指定せずに検索することもできます。';
        }
      }
      // Property assignment also works after Turbolinks restores a cached form.
      prefecture.onchange = function () { var result = update(); remember(); return result; };
      city.onchange = remember;
      form.onsubmit = remember;
      var saved;
      try { saved = window.history && window.history.state && window.history.state.circleCitySearch; } catch (_) {}
      if (saved && typeof saved.prefecture === 'string' && typeof saved.city === 'string') prefecture.value = saved.prefecture;
      if ((city.dataset.prefectureId || '') !== prefecture.value || (city.disabled && prefecture.value)) update(saved && saved.city);
      else if (saved && Array.from(city.options).some(function (option) { return option.value === saved.city; })) city.value = saved.city;
    });
  }
  document.addEventListener('turbolinks:load', ready);
  window.addEventListener('pageshow', ready);
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', ready, { once: true });
  else ready();
}());

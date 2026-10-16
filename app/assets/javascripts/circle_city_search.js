(function () {
  if (window.circleCitySearchInstalled) return;
  window.circleCitySearchInstalled = true;

  function ready() {
    document.querySelectorAll('.cb-circle-search-form').forEach(function (form) {
      var prefecture = form.querySelector('[name="prefecture_id"]');
      var city = form.querySelector('[name="city_id"]');
      if (!prefecture || !city) return;
      var status = form.querySelector('[data-city-status]');
      var request = 0;
      function reset(label) {
        city.replaceChildren(new Option(label, ''));
        city.disabled = true;
      }
      async function update() {
        var current = ++request;
        city.dataset.prefectureId = prefecture.value;
        reset(prefecture.value ? '読み込み中…' : '都道府県を選択してください');
        status.textContent = '市区町村は1つ選択できます。';
        if (!prefecture.value) return;
        try {
          var url = new URL(city.dataset.citiesUrl, location.origin);
          url.searchParams.set('prefecture_id', prefecture.value);
          var response = await fetch(url, { headers: { Accept: 'application/json' }, credentials: 'same-origin' });
          if (!response.ok) throw new Error('City options unavailable');
          var cities = await response.json();
          if (current !== request) return;
          city.replaceChildren(new Option('指定なし（都道府県全域）', ''));
          cities.forEach(function (item) { city.add(new Option(item.name, item.id)); });
          city.disabled = false;
        } catch (_) {
          if (current !== request) return;
          reset('市区町村を読み込めませんでした');
          status.textContent = '都道府県を選び直すと再読み込みできます。市区町村を指定せずに検索することもできます。';
        }
      }
      // Property assignment also works after Turbolinks restores a cached form.
      prefecture.onchange = update;
      if ((city.dataset.prefectureId || '') !== prefecture.value) update();
    });
  }
  document.addEventListener('turbolinks:load', ready);
  window.addEventListener('pageshow', ready);
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', ready, { once: true });
  else ready();
}());

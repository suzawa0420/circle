(function () {
  'use strict';

  function sync(group) {
    var all = group.querySelector('[data-city-select-all]');
    var cities = Array.from(group.querySelectorAll('.city-selection-options input[type="checkbox"]'));
    var selected = cities.filter(function (city) { return city.checked; }).length;
    all.checked = cities.length > 0 && selected === cities.length;
    all.indeterminate = selected > 0 && selected < cities.length;
  }

  function initialize() {
    document.querySelectorAll('[data-city-selection]').forEach(sync);
  }

  document.addEventListener('change', function (event) {
    var input = event.target;
    if (!input.matches('input[type="checkbox"]')) return;
    var group = input.closest('[data-city-selection]');
    if (!group) return;
    if (input.hasAttribute('data-city-select-all')) {
      group.querySelectorAll('.city-selection-options input[type="checkbox"]').forEach(function (city) {
        city.checked = input.checked;
      });
    }
    sync(group);
  });

  document.addEventListener('DOMContentLoaded', initialize);
  document.addEventListener('turbolinks:load', initialize);
})();

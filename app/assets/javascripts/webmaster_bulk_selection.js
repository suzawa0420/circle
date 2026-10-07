(function () {
  function boxes(formId) {
    return Array.prototype.slice.call(document.querySelectorAll('input[data-bulk-owner]')).filter(function (box) {
      return box.getAttribute('form') === formId;
    });
  }
  function update(formId) {
    var items = boxes(formId);
    var selected = items.filter(function (box) { return box.checked; });
    var all = document.querySelector('[data-bulk-select-all="' + formId + '"]');
    var count = document.querySelector('[data-bulk-count="' + formId + '"]');
    if (all) {
      all.checked = items.length > 0 && selected.length === items.length;
      all.indeterminate = selected.length > 0 && selected.length < items.length;
    }
    if (count) count.textContent = new Set(selected.map(function (box) { return box.value; })).size + '主催者選択';
  }
  document.addEventListener('change', function (event) {
    var target = event.target;
    var formId = target.getAttribute('data-bulk-select-all');
    if (formId) {
      boxes(formId).forEach(function (box) { box.checked = target.checked; });
      update(formId);
    } else if (target.hasAttribute('data-bulk-owner')) {
      update(target.getAttribute('form'));
    }
  });
  document.addEventListener('turbolinks:load', function () {
    document.querySelectorAll('[data-bulk-select-all]').forEach(function (all) { update(all.getAttribute('data-bulk-select-all')); });
  });
}());

(function () {
  if (window.circleMemberCompositionBound) return;
  window.circleMemberCompositionBound = true;

  function ageStatus(group) {
    var values = Array.from(group.querySelectorAll('[data-composition-age]')).map(function (field) { return field.value; });
    var sum = values.reduce(function (total, value) { return total + Number(value); }, 0);
    var status = group.querySelector('[data-composition-age-total]');
    var configured = values.some(function (value) { return value !== ''; });
    status.dataset.totalState = !configured ? 'empty' : sum === 100 ? 'complete' : sum > 100 ? 'excess' : 'remaining';
    status.textContent = !configured ? '未入力。年齢の割合は公開されません。' :
      '合計 ' + sum + '%' + (sum === 100 ? '。' : sum > 100 ? '（' + (sum - 100) + '%超過）' : '（残り ' + (100 - sum) + '%）');
  }

  function syncGender(group, changed) {
    var male = group.querySelector('[data-composition-male]');
    var female = group.querySelector('[data-composition-female]');
    var status = group.querySelector('[data-composition-gender-status]');
    if (changed === female) male.value = female.value === '' ? '' : String(100 - Number(female.value));
    female.value = male.value === '' ? '' : String(100 - Number(male.value));
    status.textContent = male.value === '' ? '未入力。男女比は公開されません。' : '男性 ' + male.value + '%・女性 ' + female.value + '%';
  }

  function refresh() {
    document.querySelectorAll('[data-member-composition]').forEach(function (group) {
      group.querySelectorAll('[data-composition-female-field], [data-composition-clear-ages], [data-composition-clear-gender]')
        .forEach(function (element) { element.hidden = false; });
      ageStatus(group);
      syncGender(group);
    });
  }
  document.addEventListener('DOMContentLoaded', refresh);
  document.addEventListener('turbolinks:load', refresh);
  document.addEventListener('change', function (event) {
    var group = event.target.closest('[data-member-composition]');
    if (!group) return;
    if (event.target.matches('[data-composition-age]')) ageStatus(group);
    if (event.target.matches('[data-composition-male], [data-composition-female]')) syncGender(group, event.target);
  });
  document.addEventListener('click', function (event) {
    var group = event.target.closest('[data-member-composition]');
    if (!group) return;
    if (event.target.closest('[data-composition-clear-ages]')) {
      group.querySelectorAll('[data-composition-age]').forEach(function (field) { field.value = ''; });
      ageStatus(group);
    }
    if (event.target.closest('[data-composition-clear-gender]')) {
      group.querySelector('[data-composition-male]').value = '';
      syncGender(group);
    }
  });
})();

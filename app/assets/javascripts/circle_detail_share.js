(function () {
  document.addEventListener('click', async function (event) {
    var trigger = event.target.closest('[data-circle-share-open]');
    if (trigger) {
      var dialog = document.getElementById(trigger.getAttribute('aria-controls'));
      if (dialog && !dialog.open && typeof dialog.showModal === 'function') {
        dialog.querySelector('[data-circle-share-status]').textContent = '';
        dialog.showModal();
      } else if (dialog && typeof dialog.showModal !== 'function') {
        dialog.setAttribute('open', '');
      }
      return;
    }

    var panel = event.target.closest('[data-circle-share-dialog]');
    if (!panel) return;
    if (event.target === panel && typeof panel.close === 'function') {
      var box = panel.getBoundingClientRect();
      if (event.clientX < box.left || event.clientX > box.right ||
          event.clientY < box.top || event.clientY > box.bottom) panel.close();
    }
    if (!event.target.closest('[data-circle-share-copy]')) return;
    var field = panel.querySelector('.cb-circle-share__url');
    var status = panel.querySelector('[data-circle-share-status]');
    try {
      await navigator.clipboard.writeText(field.value);
      status.textContent = 'URLをコピーしました。';
    } catch (_) {
      field.focus();
      field.select();
      field.setSelectionRange(0, field.value.length);
      status.textContent = 'URLを選択しました。端末のコピー操作でコピーしてください。';
    }
  });

  document.addEventListener('turbolinks:before-cache', function () {
    var dialog = document.querySelector('[data-circle-share-dialog][open]');
    if (dialog) {
      if (typeof dialog.close === 'function') dialog.close();
      else dialog.removeAttribute('open');
    }
  });
})();

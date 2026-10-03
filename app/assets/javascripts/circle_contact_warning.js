(function () {
  function closeWarning() {
    var dialog = document.getElementById('circle-contact-warning');
    if (dialog && dialog.open) dialog.close();
  }

  document.addEventListener('click', function (event) {
    var trigger = event.target.closest('a[data-circle-contact-warning]');
    var dialog = document.getElementById('circle-contact-warning');
    if (!dialog) return;
    if (trigger && typeof dialog.showModal === 'function') {
      event.preventDefault();
      dialog.querySelector('[data-contact-warning-continue]').href = trigger.href;
      if (!dialog.open) dialog.showModal();
    } else if (event.target.closest('[data-contact-warning-close], [data-contact-warning-continue]')) {
      closeWarning();
    }
  });

  document.addEventListener('turbolinks:before-cache', closeWarning);
})();

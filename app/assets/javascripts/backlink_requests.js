document.addEventListener('click', function (event) {
  var button = event.target.closest('[data-backlink-copy]');
  if (!button) return;
  var field = document.getElementById(button.getAttribute('data-backlink-copy'));
  var status = document.getElementById('backlink-copy-status');
  if (!field || !status) return;
  function fallback() {
    field.focus();
    field.select();
    status.textContent = '文字を選択しました。お使いの端末のコピー操作でコピーしてください。';
  }
  if (navigator.clipboard && window.isSecureContext) {
    navigator.clipboard.writeText(field.value).then(function () {
      status.textContent = 'コピーしました。';
    }).catch(fallback);
  } else {
    fallback();
  }
});

(function () {
  function validate(field) {
    var blocked = false;
    try {
      var url = new URL(field.value.trim());
      var host = url.hostname.toLowerCase().replace(/\.+$/, '');
      blocked = /^https?:$/.test(url.protocol) && JSON.parse(field.dataset.backlinkSnsDomains).some(function (domain) {
        return host === domain || host.endsWith('.' + domain);
      });
    } catch (_) { /* Leave malformed URLs to the existing URL validation. */ }
    var message = blocked ? field.dataset.backlinkSnsError : '';
    field.setCustomValidity(message);
    field.setAttribute('aria-invalid', blocked ? 'true' : 'false');
    var error = document.getElementById('backlink-placement-error');
    if (error) {
      error.textContent = message;
      error.hidden = !blocked;
    }
    return !blocked;
  }
  function fieldEvent(event) {
    if (event.target.matches('[data-backlink-sns-domains]')) validate(event.target);
  }
  document.addEventListener('input', fieldEvent);
  document.addEventListener('change', fieldEvent);
  // Capture before Rails UJS can disable the submit button or send the form.
  document.addEventListener('submit', function (event) {
    var field = event.target.querySelector('[data-backlink-sns-domains]');
    if (field && !validate(field)) {
      event.preventDefault();
      event.stopImmediatePropagation();
      field.reportValidity();
    }
  }, true);
  function initialize() {
    document.querySelectorAll('[data-backlink-sns-domains]').forEach(validate);
  }
  document.addEventListener('DOMContentLoaded', initialize);
  document.addEventListener('turbolinks:load', initialize);
})();

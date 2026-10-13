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

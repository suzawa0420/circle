(function () {
  function updatePreview(input) {
    var form = input.closest('form');
    var preview = form && form.querySelector('[data-inquiry-body-preview]');
    if (preview) preview.textContent = input.value.trim() || 'ここに入力したお問い合わせ内容が表示されます。';
  }
  document.addEventListener('input', function (event) {
    if (event.target.matches('[data-inquiry-preview-input]')) updatePreview(event.target);
  });
  function initialize() {
    document.querySelectorAll('[data-inquiry-preview-input]').forEach(updatePreview);
  }
  document.addEventListener('DOMContentLoaded', initialize);
  document.addEventListener('turbolinks:load', initialize);
})();

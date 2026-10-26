(function () {
  if (window.eventManagementBound) return;
  window.eventManagementBound = true;

  document.addEventListener('click', async function (event) {
    var button = event.target.closest('[data-management-copy-button]');
    if (!button) return;
    var panel = button.closest('[data-management-copy]');
    var source = panel.querySelector('.em-copy-source');
    var status = panel.querySelector('[data-management-copy-status]');
    var copied = false;
    try {
      if (navigator.clipboard && window.isSecureContext) {
        await navigator.clipboard.writeText(source.value);
        copied = true;
      }
    } catch (_) { /* Fall back to a selectable source field. */ }
    if (!copied) {
      var previous = document.activeElement;
      source.focus();
      source.select();
      try { copied = document.execCommand('copy'); } catch (_) { copied = false; }
      if (copied && previous && previous.focus) previous.focus();
    }
    status.textContent = copied ? 'コピーしました。' : '内容を選択しました。端末のコピー操作でコピーしてください。';
  });

  document.addEventListener('change', function (event) {
    if (event.target.id !== 'file_header' || !event.target.closest('.em-event-form')) return;
    var preview = event.target.closest('form').querySelector('.em-image-preview');
    var file = event.target.files[0];
    if (!file || !['image/jpeg', 'image/png'].includes(file.type)) return;
    var image = document.createElement('img');
    var url = URL.createObjectURL(file);
    image.alt = '選択したトップ画像';
    image.onload = function () { URL.revokeObjectURL(url); };
    image.onerror = function () { URL.revokeObjectURL(url); };
    image.src = url;
    preview.replaceChildren(image);
  });
})();

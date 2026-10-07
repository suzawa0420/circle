(function () {
  var cleanup = function () {};
  function start() {
    cleanup();
    var form = document.querySelector('.chat-compose-form');
    var picker = form && form.querySelector('.chat-image-input');
    var text = form && form.querySelector('.chat-compose-input');
    var preview = form && form.querySelector('.chat-upload-preview');
    var error = form && form.querySelector('[data-upload-error]');
    var remove = form && form.querySelector('.chat-upload-remove');
    var viewer = document.querySelector('.chat-image-viewer');
    var close = viewer && viewer.querySelector('.chat-image-viewer__close');
    var objectUrl, opener;
    function resize() { window.dispatchEvent(new Event('resize')); }
    function clearPreview() {
      if (objectUrl) URL.revokeObjectURL(objectUrl);
      objectUrl = null;
      if (preview) { preview.hidden = true; preview.querySelector('img').removeAttribute('src'); }
    }
    function select() {
      clearPreview();
      error.hidden = true;
      var file = picker.files[0];
      if (!file) { resize(); return; }
      if (picker.files.length !== 1 || file.size > 10 * 1024 * 1024) {
        error.textContent = '写真は1枚10MBまで選択できます。';
        error.hidden = false;
        picker.value = '';
        resize();
        return;
      }
      objectUrl = URL.createObjectURL(file);
      var image = preview.querySelector('img');
      image.hidden = false;
      image.onerror = function () { image.hidden = true; resize(); };
      image.src = objectUrl;
      preview.querySelector('.chat-upload-name').textContent = file.name;
      preview.hidden = false;
      resize();
    }
    function discard() { picker.value = ''; clearPreview(); error.hidden = true; resize(); }
    function submit(event) {
      if (!text.value.trim() && !picker.files.length) {
        event.preventDefault();
        error.textContent = 'メッセージを入力するか、写真を1枚選択してください。';
        error.hidden = false;
        text.focus();
        resize();
      }
    }
    function hide() { viewer.close(); }
    function closed() {
      viewer.querySelector('img').removeAttribute('src');
      if (opener && document.body.contains(opener)) opener.focus();
    }
    function open(event) {
      var link = event.target.closest('[data-chat-image]');
      if (!link || !viewer || typeof viewer.showModal !== 'function') return;
      event.preventDefault();
      opener = link;
      viewer.querySelector('img').src = link.href;
      viewer.showModal();
      close.focus();
    }
    if (picker) {
      picker.addEventListener('change', select);
      remove.addEventListener('click', discard);
      form.addEventListener('submit', submit);
    }
    if (viewer) {
      document.addEventListener('click', open);
      close.addEventListener('click', hide);
      viewer.addEventListener('close', closed);
    }
    cleanup = function () {
      clearPreview();
      if (picker) { picker.removeEventListener('change', select); remove.removeEventListener('click', discard); form.removeEventListener('submit', submit); }
      if (viewer) {
        if (viewer.open) viewer.close();
        document.removeEventListener('click', open);
        close.removeEventListener('click', hide);
        viewer.removeEventListener('close', closed);
        viewer.querySelector('img').removeAttribute('src');
      }
    };
  }
  document.addEventListener('DOMContentLoaded', start);
  document.addEventListener('turbolinks:load', start);
  document.addEventListener('turbolinks:before-cache', function () { cleanup(); });
})();

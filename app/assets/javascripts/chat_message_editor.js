(function () {
  var cleanup = function () {};
  function start() {
    cleanup();
    var composer = document.querySelector('#chat-reply');
    var form = composer && composer.querySelector('.chat-compose-form');
    if (!form) return;
    var text = form.querySelector('.chat-compose-input');
    var submit = form.querySelector('[type="submit"]');
    var picker = form.querySelector('.chat-image-input');
    var photoLabel = form.querySelector('.chat-image-picker');
    var preview = form.querySelector('.chat-upload-preview');
    var error = form.querySelector('[data-upload-error]');
    var status = form.querySelector('.chat-edit-status');
    var cancel = form.querySelector('.chat-edit-cancel');
    var title = composer.querySelector('#chat-reply-title');
    var token = form.querySelector('input[name="authenticity_token"]');
    var method = form.querySelector('input[name="_method"]');
    var draft, opener;
    function resize() { text.dispatchEvent(new Event('input', { bubbles: true })); }
    function restore() {
      if (!draft) return;
      form.action = draft.action;
      form.dataset.editing = 'false';
      form.dataset.editImage = '';
      method.disabled = true;
      if (token) token.value = draft.token;
      text.value = draft.body;
      submit.value = draft.submit;
      submit.dataset.disableWith = draft.disableWith;
      title.textContent = draft.title;
      picker.disabled = false;
      photoLabel.hidden = false;
      preview.hidden = draft.previewHidden;
      status.hidden = true;
      error.hidden = true;
      draft = null;
      resize();
    }
    function edit(event) {
      var link = event.target.closest('[data-chat-edit]');
      if (!link || event.defaultPrevented || event.button > 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
      event.preventDefault();
      if (!draft && form.dataset.editing !== 'true') {
        draft = { action: form.action, body: text.value, submit: submit.value,
          token: token && token.value, disableWith: submit.dataset.disableWith, title: title.textContent, previewHidden: preview.hidden };
      }
      if (!method) {
        method = document.createElement('input');
        method.type = 'hidden';
        method.name = '_method';
        form.appendChild(method);
      }
      method.value = 'patch';
      method.disabled = false;
      form.action = link.dataset.editUrl;
      if (token) token.value = link.dataset.editToken;
      form.dataset.editing = 'true';
      form.dataset.editImage = link.dataset.editImage;
      text.value = link.dataset.editBody;
      submit.value = '変更を保存';
      submit.dataset.disableWith = '更新中…';
      title.textContent = 'メッセージを編集';
      picker.disabled = true;
      photoLabel.hidden = true;
      preview.hidden = true;
      error.hidden = true;
      status.hidden = false;
      opener = link;
      resize();
      composer.scrollIntoView({ block: 'start' });
      text.focus({ preventScroll: true });
      text.setSelectionRange(text.value.length, text.value.length);
    }
    function cancelEdit(event) {
      if (!draft) return; // Server-rendered editing returns via the normal link.
      event.preventDefault();
      restore();
      if (opener && document.body.contains(opener)) opener.focus({ preventScroll: true });
    }
    document.addEventListener('click', edit);
    cancel.addEventListener('click', cancelEdit);
    cleanup = function () {
      restore();
      document.removeEventListener('click', edit);
      cancel.removeEventListener('click', cancelEdit);
    };
  }
  document.addEventListener('DOMContentLoaded', start);
  document.addEventListener('turbolinks:load', start);
  document.addEventListener('turbolinks:before-cache', function () { cleanup(); });
})();

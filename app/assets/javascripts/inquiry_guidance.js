(function () {
  document.addEventListener('click', function (event) {
    var button = event.target.closest('[data-inquiry-template-copy]');
    if (!button) return;
    var input = document.getElementById('message_body');
    if (!input) return;
    var status = document.getElementById('inquiry-template-status');
    var template = button.getAttribute('data-inquiry-template-copy').replace(/\r\n?/g, '\n');
    if (status) status.textContent = '';
    if (input.value.indexOf(template) < 0) {
      var draft = input.value + (input.value.trim() ? '\n\n' : '') + template;
      if (input.maxLength >= 0 && draft.length > input.maxLength) {
        if (status) status.textContent = '文字数の上限を超えるため追加できません。必要な部分だけ入力してください。';
        return;
      }
      input.value = draft;
    }
    input.dispatchEvent(new Event('input', { bubbles: true }));
    input.focus();
  });
})();

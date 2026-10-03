(function () {
  document.addEventListener('click', function (event) {
    var button = event.target.closest('[data-inquiry-template-copy]');
    if (!button) return;
    var input = document.getElementById('message_body');
    if (!input) return;
    var template = button.getAttribute('data-inquiry-template-copy');
    if (input.value.indexOf(template) < 0) input.value += (input.value.trim() ? '\n\n' : '') + template;
    input.dispatchEvent(new Event('input', { bubbles: true }));
    input.focus();
  });
})();

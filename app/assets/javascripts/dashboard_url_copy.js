(function () {
  document.addEventListener('click', async function (event) {
    var button = event.target.closest('.dashboard-url-copy');
    if (!button) return;
    var target = button.closest('.dashboard-circle__url').querySelector('.dashboard-circle__url-value');
    var label = button.querySelector('span');
    try {
      if (navigator.clipboard && window.isSecureContext) {
        await navigator.clipboard.writeText(target.textContent.trim());
      } else {
        var selection = window.getSelection();
        var range = document.createRange();
        range.selectNodeContents(target);
        selection.removeAllRanges();
        selection.addRange(range);
        var copied = document.execCommand('copy');
        selection.removeAllRanges();
        if (!copied) throw new Error('Copy unavailable');
      }
      label.textContent = 'コピーしました';
    } catch (error) {
      label.textContent = 'URLを選択してコピー';
    }
  });
})();

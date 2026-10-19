(function () {
  if (window.scheduleShareBound) return;
  window.scheduleShareBound = true;

  function body(panel) { return panel.querySelector('[data-share-text]').value.trim(); }
  function post(panel) { return [body(panel), panel.dataset.shareUrl].filter(Boolean).join('\n'); }
  function updateLinks(panel) {
    panel.querySelectorAll('[data-share-destination]').forEach(function (link) {
      var base = link.dataset.shareDestination === 'threads' ? 'https://www.threads.com/intent/post' : 'https://twitter.com/intent/tweet';
      link.href = base + '?text=' + encodeURIComponent(body(panel)) + '&url=' + encodeURIComponent(panel.dataset.shareUrl);
    });
  }
  function ordinaryHeading(panel) {
    panel.querySelector('[data-share-heading]').textContent = panel.dataset.shareHeading;
    panel.dataset.shareCreated = 'false';
    var later = panel.querySelector('[data-share-dismiss]');
    if (later) later.hidden = true;
  }
  function initialize() {
    document.querySelectorAll('[data-schedule-share]').forEach(function (panel) {
      updateLinks(panel);
      panel.querySelector('[data-share-native]').hidden = !(navigator.share && window.isSecureContext);
    });
  }
  function fallbackCopy(value) {
    var temporary = document.createElement('textarea');
    temporary.value = value;
    temporary.setAttribute('readonly', '');
    temporary.style.position = 'fixed';
    temporary.style.left = '-9999px';
    temporary.style.fontSize = '16px';
    var previous = document.activeElement;
    document.body.appendChild(temporary);
    try {
      temporary.focus();
      temporary.select();
      return document.execCommand('copy');
    } finally {
      temporary.remove();
      if (previous && previous.focus) previous.focus();
    }
  }
  async function copy(panel, value, message) {
    var copied = false;
    try {
      if (navigator.clipboard && window.isSecureContext) {
        await navigator.clipboard.writeText(value);
        copied = true;
      }
    } catch (_) { /* Try the browser's selection copy below. */ }
    if (!copied) {
      try { copied = fallbackCopy(value); } catch (_) { copied = false; }
    }
    var status = panel.querySelector('[data-share-status]');
    var manual = panel.querySelector('[data-share-manual]');
    manual.hidden = copied;
    if (copied) {
      status.textContent = message;
    } else {
      manual.value = value;
      manual.hidden = false;
      manual.focus();
      manual.select();
      status.textContent = '内容を選択しました。端末のコピー操作でコピーしてください。';
    }
  }
  document.addEventListener('input', function (event) {
    if (!event.target.matches('[data-share-text]')) return;
    var panel = event.target.closest('[data-schedule-share]');
    updateLinks(panel);
    panel.querySelector('[data-share-status]').textContent = '';
    panel.querySelector('[data-share-manual]').hidden = true;
  });
  document.addEventListener('click', async function (event) {
    var target = event.target.closest('[data-share-copy], [data-share-dismiss], [data-share-native], [data-schedule-share-reopen]');
    if (!target) return;
    var panel = target.hasAttribute('data-schedule-share-reopen') ? document.querySelector('[data-schedule-share]') : target.closest('[data-schedule-share]');
    if (!panel) return;
    if (target.hasAttribute('data-schedule-share-reopen')) {
      event.preventDefault();
      panel.open = true;
      panel.scrollIntoView({ behavior: 'smooth', block: 'start' });
    } else if (target.hasAttribute('data-share-dismiss')) {
      panel.open = false;
      ordinaryHeading(panel);
      panel.querySelector('summary').focus();
    } else if (target.hasAttribute('data-share-copy')) {
      var onlyUrl = target.dataset.shareCopy === 'url';
      await copy(panel, onlyUrl ? panel.dataset.shareUrl : post(panel), onlyUrl ? '公開URLをコピーしました。' : '投稿文と公開URLをコピーしました。');
    } else if (navigator.share) {
      try {
        await navigator.share({ title: panel.dataset.shareTitle, text: body(panel), url: panel.dataset.shareUrl });
        panel.querySelector('[data-share-status]').textContent = '投稿内容は共有先のアプリで確認してください。';
      } catch (error) {
        if (error.name !== 'AbortError') await copy(panel, post(panel), '投稿文と公開URLをコピーしました。共有先に貼り付けてください。');
      }
    }
  });
  document.addEventListener('turbolinks:before-cache', function () {
    document.querySelectorAll('[data-schedule-share]').forEach(function (panel) {
      if (panel.dataset.shareCreated === 'true') {
        panel.open = false;
        ordinaryHeading(panel);
      }
      panel.querySelector('[data-share-status]').textContent = '';
      panel.querySelector('[data-share-manual]').hidden = true;
    });
  });
  document.addEventListener('DOMContentLoaded', initialize);
  document.addEventListener('turbolinks:load', initialize);
  if (document.readyState !== 'loading') initialize();
})();

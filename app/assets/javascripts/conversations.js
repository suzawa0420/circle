(function () {
  var timer, cleanup = function () {};
  function stop() { window.clearTimeout(timer); cleanup(); cleanup = function () {}; }
  function setupComposer() {
    var composer = document.querySelector('.chat-composer');
    if (!composer) return;
    var input = composer.querySelector('.chat-compose-input');
    var root = document.documentElement;
    var viewport = window.visualViewport;
    function resize() {
      if (input) {
        input.style.height = 'auto';
        input.style.height = Math.min(input.scrollHeight, 144) + 'px';
      }
      root.style.setProperty('--chat-composer-height', composer.offsetHeight + 'px');
      var offset = viewport ? Math.max(0, window.innerHeight - viewport.height - viewport.offsetTop) : 0;
      root.style.setProperty('--chat-keyboard-offset', offset + 'px');
    }
    function openEvaluation() {
      if (window.location.hash === '#evaluation') {
        var evaluation = document.getElementById('evaluation');
        if (evaluation) evaluation.open = true;
      }
    }
    var evaluationLinks = document.querySelectorAll('[data-open-evaluation]');
    function revealEvaluation() {
      var evaluation = document.getElementById('evaluation');
      if (evaluation) evaluation.open = true;
    }
    evaluationLinks.forEach(function (link) { link.addEventListener('click', revealEvaluation); });
    if (input) input.addEventListener('input', resize);
    window.addEventListener('resize', resize);
    window.addEventListener('hashchange', openEvaluation);
    if (viewport) { viewport.addEventListener('resize', resize); viewport.addEventListener('scroll', resize); }
    resize();
    openEvaluation();
    cleanup = function () {
      evaluationLinks.forEach(function (link) { link.removeEventListener('click', revealEvaluation); });
      if (input) input.removeEventListener('input', resize);
      window.removeEventListener('resize', resize);
      window.removeEventListener('hashchange', openEvaluation);
      if (viewport) { viewport.removeEventListener('resize', resize); viewport.removeEventListener('scroll', resize); }
      root.style.removeProperty('--chat-keyboard-offset');
      root.style.removeProperty('--chat-composer-height');
    };
  }
  function start() {
    stop();
    setupComposer();
    var container = document.getElementById('chat-messages');
    if (!container || !container.dataset.pollUrl) return;
    var latest = document.getElementById('chat-latest');
    if (!window.location.hash && latest) latest.scrollIntoView({ block: 'end' });
    function poll() {
      if (document.hidden || !document.body.contains(container)) {
        if (document.body.contains(container)) timer = window.setTimeout(poll, 15000);
        return;
      }
      fetch(container.dataset.pollUrl, { credentials: 'same-origin', headers: { 'Accept': 'application/json' }, cache: 'no-store' })
        .then(function (response) { if (!response.ok || response.redirected) throw new Error('Session unavailable'); return response.json(); })
        .then(function (data) {
          if (!document.body.contains(container)) return;
          container.querySelectorAll('.chat-read-receipt').forEach(function (receipt) {
            if (data.receipts && data.receipts[receipt.dataset.messageId]) receipt.textContent = data.receipts[receipt.dataset.messageId];
          });
          if (data.history_version !== container.dataset.historyVersion) {
            // Preserve any report the user is currently composing.
            if (!container.contains(document.activeElement) && !container.querySelector('details[open]')) {
              var atBottom = latest && latest.getBoundingClientRect().top <= window.innerHeight && latest.getBoundingClientRect().top >= 0;
              container.innerHTML = data.html;
              if (atBottom && latest) latest.scrollIntoView({ block: 'end' });
              container.dataset.latestId = String(data.latest_id);
              container.dataset.historyVersion = data.history_version;
            }
          }
          if (data.accepted && container.dataset.accepted !== 'true') {
            var notice = document.getElementById('chat-acceptance-notice');
            if (notice) notice.hidden = false;
            var status = document.getElementById('chat-acceptance-status');
            if (status) status.textContent = '受付済み';
            var noReply = document.getElementById('chat-no-reply');
            if (noReply) noReply.hidden = true;
          }
          timer = window.setTimeout(poll, 15000);
        }).catch(function () { if (document.body.contains(container)) timer = window.setTimeout(poll, 30000); });
    }
    timer = window.setTimeout(poll, 15000);
  }
  document.addEventListener('turbolinks:load', start);
  document.addEventListener('turbolinks:before-cache', stop);
  document.addEventListener('DOMContentLoaded', start);
})();

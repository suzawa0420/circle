(function () {
  var timer, cleanup = function () {};
  function stop() { window.clearTimeout(timer); cleanup(); cleanup = function () {}; }
  function setupComposer() {
    var composer = document.querySelector('.chat-composer');
    if (!composer) return;
    var input = composer.querySelector('.chat-compose-input');
    function resize() {
      if (input) {
        input.style.height = 'auto';
        input.style.height = Math.min(input.scrollHeight, 320) + 'px';
      }
    }
    function openEvaluation() {
      if (window.location.hash === '#evaluation') {
        var evaluation = document.getElementById('evaluation');
        if (evaluation) evaluation.open = true;
      }
    }
    var replyLinks = document.querySelectorAll('a[href="#chat-reply"]');
    function revealComposer(event) {
      // Repeated anchor visits can trigger a Turbolinks reload and discard drafts.
      event.preventDefault();
      composer.scrollIntoView({ block: 'start' });
      (input || composer).focus({ preventScroll: true });
    }
    replyLinks.forEach(function (link) { link.addEventListener('click', revealComposer); });
    var evaluationLinks = document.querySelectorAll('[data-open-evaluation]');
    function revealEvaluation() {
      var evaluation = document.getElementById('evaluation');
      if (evaluation) evaluation.open = true;
    }
    evaluationLinks.forEach(function (link) { link.addEventListener('click', revealEvaluation); });
    var reviewPrompt = document.getElementById('chat-review-prompt');
    function revealPromptEvaluation(event) {
      if (event.target.closest('[data-open-evaluation]')) revealEvaluation();
    }
    if (reviewPrompt) reviewPrompt.addEventListener('click', revealPromptEvaluation);
    if (input) input.addEventListener('input', resize);
    window.addEventListener('resize', resize);
    window.addEventListener('hashchange', openEvaluation);
    resize();
    openEvaluation();
    cleanup = function () {
      replyLinks.forEach(function (link) { link.removeEventListener('click', revealComposer); });
      evaluationLinks.forEach(function (link) { link.removeEventListener('click', revealEvaluation); });
      if (reviewPrompt) reviewPrompt.removeEventListener('click', revealPromptEvaluation);
      if (input) input.removeEventListener('input', resize);
      window.removeEventListener('resize', resize);
      window.removeEventListener('hashchange', openEvaluation);
    };
  }
  function setupInitialJump() {
    var thread = document.querySelector('[data-chat-jump-target]');
    if (!thread || !thread.dataset.chatJumpTarget || window.location.hash || thread.dataset.chatJumpFinished) return function () {};
    var target = document.getElementById(thread.dataset.chatJumpTarget);
    if (!target) return function () {};
    var cancelled = false;
    function jump() {
      if (!cancelled && document.body.contains(target) && !window.location.hash) {
        target.scrollIntoView({ block: thread.dataset.chatJumpAlignment || 'start', behavior: 'auto' });
      }
    }
    function cancel() { cancelled = true; thread.dataset.chatJumpFinished = 'true'; }
    var images = thread.querySelectorAll('img');
    var events = ['wheel', 'touchstart', 'pointerdown', 'keydown'];
    images.forEach(function (img) { if (!img.complete) img.addEventListener('load', jump); });
    events.forEach(function (event) { window.addEventListener(event, cancel, { passive: true }); });
    window.addEventListener('load', jump);
    var frame = window.requestAnimationFrame(jump);
    var composerCleanup = cleanup;
    cleanup = function () {
      composerCleanup();
      window.cancelAnimationFrame(frame);
      window.removeEventListener('load', jump);
      images.forEach(function (img) { img.removeEventListener('load', jump); });
      events.forEach(function (event) { window.removeEventListener(event, cancel); });
    };
  }
  function start() {
    stop();
    setupComposer();
    setupInitialJump();
    var container = document.getElementById('chat-messages');
    if (!container || !container.dataset.pollUrl) return;
    var latest = document.getElementById('chat-latest');
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
          var reviewPrompt = document.getElementById('chat-review-prompt');
          if (reviewPrompt && typeof data.review_prompt_html === 'string' &&
              !reviewPrompt.contains(document.activeElement) && reviewPrompt.innerHTML !== data.review_prompt_html) {
            reviewPrompt.innerHTML = data.review_prompt_html;
          }
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
  // A deferred bundle added during navigation may run after the load events.
  if (document.readyState !== 'loading') start();
})();

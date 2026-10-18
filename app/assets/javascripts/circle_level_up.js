(function () {
  var activeDialog = null;
  var running = [];
  var previousOverflow = null;
  var previousFocus = null;
  var openingTimer = null;
  var autoPlayed = false;
  var boundDialogs = new WeakSet();
  var motionPreference = window.matchMedia('(prefers-reduced-motion: reduce)');

  function stopConfetti() {
    running.forEach(function (animation) { animation.cancel(); });
    running = [];
    if (activeDialog) activeDialog.querySelector('.circle-level-up__confetti').textContent = '';
  }

  function restorePage() {
    cancelOpening();
    stopConfetti();
    if (previousOverflow !== null) document.documentElement.style.overflow = previousOverflow;
    previousOverflow = null;
    activeDialog = null;
    if (previousFocus && previousFocus.isConnected) previousFocus.focus({ preventScroll: true });
    previousFocus = null;
  }

  function close() {
    if (!activeDialog) return;
    var dialog = activeDialog;
    if (typeof dialog.close === 'function' && dialog.open) dialog.close();
    else dialog.removeAttribute('open');
    restorePage();
  }

  function celebrate(dialog) {
    stopConfetti();
    if (motionPreference.matches || typeof Element.prototype.animate !== 'function') return;
    var layer = dialog.querySelector('.circle-level-up__confetti');
    var width = document.documentElement.clientWidth;
    var height = window.innerHeight;
    var bounds = dialog.getBoundingClientRect();
    var originY = Math.min(height * .7, bounds.top + bounds.height * .55);
    var batch = [];
    running = batch;
    batch.push(dialog.querySelector('.circle-level-up__new').animate([
      { transform: 'scale(1) translateY(0)', offset: 0 },
      { transform: 'scale(1.14) translateY(-5px)', offset: .4 },
      { transform: 'scale(.98) translateY(1px)', offset: .72 },
      { transform: 'scale(1) translateY(0)', offset: 1 }
    ], { duration: 540, delay: 120, easing: 'ease-out' }));
    for (var i = 0; i < 64; i++) {
      var paper = document.createElement('span');
      paper.className = 'circle-level-up__paper';
      paper.style.left = (i % 2 === 0 ? Math.max(12, bounds.left) : Math.min(width - 12, bounds.right)) + 'px';
      paper.style.top = (originY + Math.random() * 30) + 'px';
      layer.appendChild(paper);
      var flight = 1.4 + Math.random() * .35;
      var vx = (i % 2 === 0 ? 1 : -1) * Math.min(width, 600) * (.18 + Math.random() * .38);
      var vy = -(230 + Math.random() * 140);
      var spin = (Math.random() - .5) * 1100;
      var frames = [];
      for (var step = 0; step <= 24; step++) {
        var progress = step / 24;
        var time = progress * flight;
        var x = vx * time + Math.sin(progress * 8) * progress * 14;
        var y = vy * time + 240 * time * time;
        frames.push({ offset: progress,
          transform: 'translate(' + x + 'px,' + y + 'px) rotate(' + (spin * progress) + 'deg) scaleX(' + (.3 + Math.abs(Math.cos(progress * 11)) * .7) + ')',
          opacity: progress < .72 ? 1 : Math.max(0, (1 - progress) / .28) });
      }
      batch.push(paper.animate(frames, { duration: flight * 1000, delay: Math.random() * 120, easing: 'linear', fill: 'both' }));
    }
    Promise.allSettled(batch.map(function (animation) { return animation.finished; })).then(function () {
      if (running === batch) stopConfetti();
    });
  }

  function cancelOpening() {
    if (openingTimer !== null) window.clearTimeout(openingTimer);
    openingTimer = null;
  }

  function scheduleOpening() {
    if (!activeDialog || autoPlayed || openingTimer !== null || document.visibilityState === 'hidden') return;
    var dialog = activeDialog;
    // Give the newly opened page time to become visible before the short burst.
    openingTimer = window.setTimeout(function () {
      openingTimer = null;
      requestAnimationFrame(function () {
        if (activeDialog !== dialog || !dialog.open || autoPlayed || document.visibilityState === 'hidden') return;
        autoPlayed = true;
        celebrate(dialog);
      });
    }, 300);
  }

  function openDialog(dialog) {
    if (activeDialog === dialog && dialog.open) return;
    if (activeDialog) close();
    dialog.dataset.levelUpShown = 'true';
    activeDialog = dialog;
    autoPlayed = false;
    previousFocus = document.activeElement;
    previousOverflow = document.documentElement.style.overflow;
    document.documentElement.style.overflow = 'hidden';
    if (!boundDialogs.has(dialog)) {
      boundDialogs.add(dialog);
      dialog.addEventListener('close', function () { if (activeDialog === dialog && !dialog.open) restorePage(); });
      dialog.addEventListener('cancel', function (event) { event.preventDefault(); close(); });
    }
    if (typeof dialog.showModal === 'function') dialog.showModal();
    else dialog.setAttribute('open', '');
    scheduleOpening();
  }

  function start() {
    var dialog = document.querySelector('[data-circle-level-up="true"]');
    if (!dialog || dialog.dataset.levelUpShown === 'true') return;
    openDialog(dialog);
  }

  document.addEventListener('click', function (event) {
    if (!activeDialog) return;
    if (event.target.closest('[data-level-up-close], .circle-level-up__primary')) close();
    else if (event.target === activeDialog) {
      var bounds = activeDialog.getBoundingClientRect();
      if (event.clientX < bounds.left || event.clientX > bounds.right || event.clientY < bounds.top || event.clientY > bounds.bottom) close();
    }
  });
  function motionChanged() {
    if (!activeDialog) return;
    if (motionPreference.matches) stopConfetti();
  }
  if (motionPreference.addEventListener) motionPreference.addEventListener('change', motionChanged);
  else if (motionPreference.addListener) motionPreference.addListener(motionChanged);
  document.addEventListener('DOMContentLoaded', start);
  document.addEventListener('turbolinks:load', start);
  document.addEventListener('turbolinks:before-cache', close);
  document.addEventListener('visibilitychange', function () {
    if (document.visibilityState === 'hidden') {
      cancelOpening();
      stopConfetti();
    } else scheduleOpening();
  });
})();

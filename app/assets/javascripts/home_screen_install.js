(function () {
  // Both bundles can load during Turbolinks navigation. Keep one prompt/listener.
  if (window.circleHomeScreenInstall) return;
  window.circleHomeScreenInstall = true;
  var deferredPrompt;
  var installed = false;
  var opener;
  var displayMode = window.matchMedia('(display-mode: standalone)');
  var ios = /iPad|iPhone|iPod/.test(navigator.userAgent) ||
    (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
  var android = /Android/.test(navigator.userAgent);

  function standalone() { return installed || displayMode.matches || navigator.standalone === true; }
  function update() {
    document.querySelectorAll('[data-home-screen-install]').forEach(function (button) {
      button.hidden = standalone() || !(ios || android || deferredPrompt);
    });
  }
  function dialog() { return document.getElementById('home-screen-install-dialog'); }
  function close() {
    var panel = dialog();
    if (panel && panel.open) panel.close();
    if (opener && document.body.contains(opener)) opener.focus();
  }
  function showInstructions(failed) {
    var panel = dialog();
    if (!panel) return;
    var kind = ios ? 'ios' : android ? 'android' : 'other';
    panel.querySelectorAll('[data-install-instructions]').forEach(function (section) {
      section.hidden = section.getAttribute('data-install-instructions') !== kind;
    });
    panel.querySelector('[data-install-browser-note]').hidden = !ios ||
      (/Safari/.test(navigator.userAgent) && !/CriOS|FxiOS|EdgiOS|OPiOS|GSA|Line|FBAN|FBAV|Instagram/i.test(navigator.userAgent));
    panel.querySelector('[data-install-error]').hidden = !failed;
    if (!panel.open) panel.showModal();
  }
  window.addEventListener('beforeinstallprompt', function (event) {
    event.preventDefault();
    deferredPrompt = event;
    update();
  });
  window.addEventListener('appinstalled', function () {
    installed = true;
    deferredPrompt = null;
    close();
    update();
  });
  if (displayMode.addEventListener) displayMode.addEventListener('change', update);
  document.addEventListener('click', function (event) {
    var button = event.target.closest('[data-home-screen-install]');
    if (button) {
      if (standalone()) return;
      opener = button;
      // Let mobile_navigation restore scrolling before opening another dialog.
      var menu = button.closest('dialog');
      if (menu && menu.open) {
        document.dispatchEvent(new Event('circle:close-mobile-menu'));
        opener = document.querySelector('.mobile-menu-trigger') || button;
      }
      if (deferredPrompt && !ios) {
        var prompt = deferredPrompt;
        deferredPrompt = null;
        // Must run synchronously inside the tap handler to keep user activation.
        try {
          Promise.resolve(prompt.prompt()).then(function () { return prompt.userChoice; }).then(function (choice) {
            if (choice.outcome === 'accepted') installed = true;
            update();
          }).catch(function () { showInstructions(true); });
        } catch (error) { showInstructions(true); }
      } else {
        showInstructions(false);
      }
    } else if (event.target.closest('[data-install-close]')) {
      close();
    } else if (event.target === dialog()) {
      var bounds = event.target.getBoundingClientRect();
      if (event.clientX < bounds.left || event.clientX > bounds.right ||
          event.clientY < bounds.top || event.clientY > bounds.bottom) close();
    }
  });
  document.addEventListener('DOMContentLoaded', update);
  document.addEventListener('cancel', function (event) {
    if (event.target === dialog()) {
      event.preventDefault();
      close();
    }
  }, true);
  document.addEventListener('turbolinks:load', update);
  document.addEventListener('turbolinks:before-cache', close);
  update();
}());

(function () {
  var closingTimer;
  var opener;
  var scrollY = 0;

  function restorePage() {
    document.body.classList.remove('mobile-menu-open');
    document.body.style.top = '';
    window.scrollTo(0, scrollY);
    if (opener) opener.setAttribute('aria-expanded', 'false');
  }

  function closeMenu(immediate) {
    var dialog = document.getElementById('mobile-menu-dialog');
    if (!dialog || !dialog.open) return;
    clearTimeout(closingTimer);
    dialog.classList.remove('is-open');
    function finish() {
      dialog.close();
      restorePage();
    }
    if (immediate || window.matchMedia('(prefers-reduced-motion: reduce)').matches) finish();
    else closingTimer = setTimeout(finish, 180);
  }

  document.addEventListener('click', function (event) {
    document.querySelectorAll('.circle-desktop-menu[open]').forEach(function (menu) {
      if (!menu.contains(event.target)) menu.open = false;
    });
    var trigger = event.target.closest('.mobile-menu-trigger');
    var dialog = document.getElementById('mobile-menu-dialog');
    if (!dialog) return;
    if (trigger) {
      if (dialog.open) return;
      opener = trigger;
      scrollY = window.scrollY;
      document.body.style.top = -scrollY + 'px';
      document.body.classList.add('mobile-menu-open');
      dialog.showModal();
      trigger.setAttribute('aria-expanded', 'true');
      requestAnimationFrame(function () { dialog.classList.add('is-open'); });
    } else if (event.target.closest('.mobile-menu-close')) {
      closeMenu(false);
    } else if (event.target === dialog) {
      var bounds = dialog.getBoundingClientRect();
      if (event.clientX < bounds.left || event.clientX > bounds.right ||
          event.clientY < bounds.top || event.clientY > bounds.bottom) closeMenu(false);
    } else if (dialog.open && event.target.closest('#mobile-menu-dialog a')) {
      closeMenu(true);
    }
  });

  document.addEventListener('keydown', function (event) {
    if (event.key === 'Escape') document.querySelectorAll('.circle-desktop-menu[open]').forEach(function (menu) {
      menu.open = false;
      menu.querySelector('summary').focus();
    });
  });

  // Keep Escape, page navigation and desktop resizing consistent with the close button.
  document.addEventListener('cancel', function (event) {
    if (event.target.id === 'mobile-menu-dialog') {
      event.preventDefault();
      closeMenu(false);
    }
  }, true);
  document.addEventListener('turbolinks:before-cache', function () { closeMenu(true); });
  window.addEventListener('resize', function () {
    if (window.innerWidth >= 768) closeMenu(true);
  });
})();

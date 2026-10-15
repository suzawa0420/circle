(function () {
  var cleanup;

  function ready() {
    if (cleanup) cleanup();
    var body = document.body;
    var sentinel = body.querySelector('.circle-header-sentinel');
    if (!body.classList.contains('circle-scroll-header') || !sentinel) return;
    var headers = body.querySelectorAll('.circle-desktop-toolbar, .mobile-site-heading');
    var frame;
    var scrolled;

    function update() {
      frame = null;
      // Opening the bottom menu temporarily fixes the body in place.
      if (body.classList.contains('mobile-menu-open')) return;
      var next = sentinel.getBoundingClientRect().top <= 0;
      if (next === scrolled) return;
      scrolled = next;
      body.classList.toggle('circle-header-scrolled', next);
      headers.forEach(function (header) {
        header.inert = next;
        if (next) header.querySelectorAll('details[open]').forEach(function (menu) { menu.open = false; });
      });
    }

    function schedule() {
      if (frame == null) frame = window.requestAnimationFrame(update);
    }

    body.classList.add('circle-header-enhanced');
    update();
    window.addEventListener('scroll', schedule, { passive: true });
    window.addEventListener('resize', schedule);
    window.addEventListener('pageshow', schedule);
    cleanup = function () {
      window.cancelAnimationFrame(frame);
      window.removeEventListener('scroll', schedule);
      window.removeEventListener('resize', schedule);
      window.removeEventListener('pageshow', schedule);
      body.classList.remove('circle-header-enhanced', 'circle-header-scrolled');
      headers.forEach(function (header) { header.inert = false; });
      cleanup = null;
    };
  }

  document.addEventListener('turbolinks:load', ready);
  document.addEventListener('turbolinks:before-cache', function () { if (cleanup) cleanup(); });
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', ready, { once: true });
  else ready();
}());

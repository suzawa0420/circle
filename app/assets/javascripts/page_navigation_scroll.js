(function () {
  if (window.circlePageNavigationScrollInstalled) return;
  window.circlePageNavigationScrollInstalled = true;

  var marker = 'circle:fresh-page-visit';
  var proposedVisit;
  var markedVisit;

  function storeMarker(value, source) {
    try {
      if (value) sessionStorage.setItem(marker, JSON.stringify({ url: value, source: source, at: Date.now() }));
      else sessionStorage.removeItem(marker);
    } catch (_) {
      // In restricted browser contexts, leave native restoration alone.
    }
  }

  function readMarker() {
    try {
      return JSON.parse(sessionStorage.getItem(marker));
    } catch (_) {
      return null;
    }
  }

  // Lightweight pages (including the event calendars) navigate natively.
  // Record ordinary link visits without changing the browser's history behavior.
  document.addEventListener('click', function (event) {
    if (event.defaultPrevented || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
    var link = event.target && event.target.closest && event.target.closest('a[href]');
    if (!link || link.hasAttribute('download') || (link.target && link.target.toLowerCase() !== '_self')) return;
    // Rails UJS links can represent a mutation or an Ajax action, not a visit.
    if (link.hasAttribute('data-method') || link.hasAttribute('data-remote')) return;
    if (link.hasAttribute('data-circle-search-back')) return; // Restores its own listing position.
    var base = document.querySelector('base[target]');
    if (!link.target && base && base.target.toLowerCase() !== '_self') return;
    var target = new URL(link.href, location.href);
    if (target.origin !== location.origin || target.hash || target.pathname === location.pathname) return;
    storeMarker(target.href, location.href);
    // A later delegated handler may cancel this click.
    Promise.resolve().then(function () {
      var marker = readMarker();
      if (event.defaultPrevented && marker && marker.url === target.href && marker.source === location.href) storeMarker(null);
    });
  });

  document.addEventListener('turbolinks:before-visit', function (event) {
    var target = new URL(event.data.url, location.href);
    proposedVisit = target.origin === location.origin && target.pathname !== location.pathname && !target.hash ? target.href : null;
    // The corresponding visit begins synchronously. Do not retain a
    // prevented proposal for a later browser Back or Forward restoration.
    Promise.resolve().then(function () { proposedVisit = null; });
  });

  document.addEventListener('turbolinks:visit', function (event) {
    if (markedVisit) storeMarker(null);
    markedVisit = proposedVisit === event.data.url && proposedVisit === location.href ? proposedVisit : null;
    if (markedVisit) storeMarker(markedVisit);
  });

  document.addEventListener('turbolinks:render', function () {
    if (!markedVisit || markedVisit !== location.href || document.documentElement.hasAttribute('data-turbolinks-preview')) return;
    // Normal soft navigation already scrolls to the start; no reload needed.
    markedVisit = null;
    storeMarker(null);
  });

  window.addEventListener('pageshow', function (event) {
    var arrival = readMarker();
    if (!arrival) return;
    storeMarker(null);
    if (arrival.url !== location.href || Date.now() - arrival.at > 30000) return;
    var navigation = window.performance && performance.getEntriesByType && performance.getEntriesByType('navigation')[0];
    // Never reset a history traversal, BFCache resume or explicit anchor.
    if (event.persisted || !navigation || location.hash) return;
    if (arrival.source) {
      if (navigation.type !== 'navigate' || document.referrer !== arrival.source.split('#')[0]) return;
    } else if (navigation.type !== 'reload') {
      // Turbolinks can turn a visit into a reload after changing the URL.
      return;
    }
    // WebKit can defer animation frames on the newly shown document. Reset
    // immediately, and also catch any restoration applied just after pageshow.
    var shownAt = Date.now();
    var retry = true;
    var intentEvents = ['wheel', 'touchstart', 'touchmove', 'pointerdown', 'keydown', 'focusin'];
    function cancelRetry() {
      retry = false;
      intentEvents.forEach(function (type) { window.removeEventListener(type, cancelRetry, true); });
    }

    window.scrollTo(0, 0);
    intentEvents.forEach(function (type) {
      window.addEventListener(type, cancelRetry, { capture: true, passive: true });
    });
    var timeout = window.setTimeout(cancelRetry, 250);
    window.requestAnimationFrame(function () {
      if (retry && Date.now() - shownAt < 250 && location.href === arrival.url && window.scrollY > 0) window.scrollTo(0, 0);
      window.clearTimeout(timeout);
      cancelRetry();
    });
  });
}());

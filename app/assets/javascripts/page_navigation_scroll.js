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

  function withoutHash(url) { return url.split('#')[0]; }

  function freshDestination(url) {
    return url.origin === location.origin && !url.hash && url.href !== withoutHash(location.href);
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
    if (!freshDestination(target)) return;
    storeMarker(target.href, location.href);
    // A later delegated handler may cancel this click.
    Promise.resolve().then(function () {
      var marker = readMarker();
      if (event.defaultPrevented && marker && marker.url === target.href && marker.source === location.href) storeMarker(null);
    });
  });

  document.addEventListener('turbolinks:before-visit', function (event) {
    var target = new URL(event.data.url, location.href);
    proposedVisit = freshDestination(target) ? target.href : null;
    // The corresponding visit begins synchronously. Do not retain a
    // prevented proposal for a later browser Back or Forward restoration.
    Promise.resolve().then(function () { proposedVisit = null; });
  });

  document.addEventListener('turbolinks:visit', function (event) {
    if (stopReset) stopReset();
    if (markedVisit) storeMarker(null);
    markedVisit = proposedVisit === event.data.url && proposedVisit === location.href ? proposedVisit : null;
    if (markedVisit) storeMarker(markedVisit);
  });

  var stopReset;

  function resetOnArrival(url) {
    if (stopReset) stopReset();
    var frame;
    var timeout;
    var active = true;
    var started = Date.now();
    var settleFor = 650;
    var intentEvents = ['wheel', 'touchstart', 'touchmove', 'pointerdown', 'keydown', 'focusin', 'pagehide'];
    function stop() {
      active = false;
      intentEvents.forEach(function (type) { window.removeEventListener(type, stop, true); });
      window.removeEventListener('scroll', settle);
      window.clearTimeout(timeout);
      if (frame !== undefined) window.cancelAnimationFrame(frame);
      stopReset = null;
    }
    function settle() {
      // A browser scroll applied after the first paint can otherwise survive
      // the reset. Never fight a real gesture, focus change or later visit.
      if (!active) return;
      if (Date.now() - started >= settleFor || location.href !== url) {
        stop();
        return;
      }
      if (window.scrollY !== 0) window.scrollTo(0, 0);
    }

    stopReset = stop;
    window.scrollTo(0, 0);
    intentEvents.forEach(function (type) {
      window.addEventListener(type, stop, { capture: true, passive: true });
    });
    // A hidden or newly active WebKit view can defer animation frames.
    // Observe the scroll itself as well as the first frame.
    window.addEventListener('scroll', settle, { passive: true });
    timeout = window.setTimeout(function () {
      if (active && location.href === url && window.scrollY !== 0) window.scrollTo(0, 0);
      stop();
    }, settleFor);
    frame = window.requestAnimationFrame(settle);
  }

  document.addEventListener('turbolinks:load', function () {
    if (!markedVisit || markedVisit !== location.href || document.documentElement.hasAttribute('data-turbolinks-preview')) return;
    markedVisit = null;
    storeMarker(null);
    resetOnArrival(location.href);
  });

  function navigationType() {
    var perf = window.performance;
    var entry = perf && perf.getEntriesByType && perf.getEntriesByType('navigation')[0];
    if (entry) return entry.type;
    // Older WebKit may provide only the legacy navigation timing interface.
    return perf && perf.navigation && ['navigate', 'reload', 'back_forward'][perf.navigation.type];
  }

  window.addEventListener('pageshow', function (event) {
    var arrival = readMarker();
    if (!arrival) return;
    storeMarker(null);
    if (arrival.url !== location.href || Date.now() - arrival.at > 30000) return;
    // Never reset a history traversal, BFCache resume or explicit anchor.
    var type = navigationType();
    if (event.persisted || location.hash) return;
    if (arrival.source) {
      if (type !== 'navigate') return;
      // The short-lived marker was written by a same-tab, same-origin link.
      // Accept a stripped referrer, but reject a contradictory full referrer.
      var referrer = document.referrer;
      if (referrer && referrer !== location.origin + '/' && withoutHash(referrer) !== withoutHash(arrival.source)) return;
    } else if (type !== 'reload') {
      // Turbolinks can turn a visit into a reload after changing the URL.
      return;
    }
    resetOnArrival(location.href);
  });
}());

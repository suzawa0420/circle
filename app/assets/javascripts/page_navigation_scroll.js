(function () {
  if (window.circlePageNavigationScrollInstalled) return;
  window.circlePageNavigationScrollInstalled = true;

  var marker = 'circle:fresh-page-visit';
  var proposedVisit;
  var markedVisit;

  function storeMarker(value) {
    try {
      if (value) sessionStorage.setItem(marker, JSON.stringify({ url: value, at: Date.now() }));
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
    // Public pages and changed bundles may require a full reload after
    // Turbolinks changes the URL, causing scroll from the previous document
    // to be restored against the destination. Correct that reload only.
    if (event.persisted || !navigation || navigation.type !== 'reload' || location.hash) return;
    // The browser can restore the reload position just after pageshow.
    window.requestAnimationFrame(function () {
      if (location.href === arrival.url) window.scrollTo(0, 0);
    });
  });
}());

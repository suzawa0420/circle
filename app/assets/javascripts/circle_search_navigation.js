// Per-tab state only: never prefetch a result or send search history to a server.
(function () {
  if (window.circleSearchNavigationInstalled) return;
  window.circleSearchNavigationInstalled = true;
  var prefix = 'circle-search-v1:';
  var ttl = 30 * 60 * 1000;
  function read(key) {
    try { return JSON.parse(sessionStorage.getItem(prefix + key)); } catch (_) { return null; }
  }
  function write(key, value) {
    try { sessionStorage.setItem(prefix + key, JSON.stringify(value)); } catch (_) { /* Storage may be disabled. */ }
  }
  function localUrl(value) {
    try {
      var url = new URL(value, location.origin);
      return url.origin === location.origin && !url.username && !url.password ? url : null;
    } catch (_) { return null; }
  }
  function listing() { return document.body.dataset.circleSearchList === 'true'; }
  function position() { return { url: location.href, y: window.scrollY, at: Date.now() }; }
  function ready() {
    document.querySelectorAll('[data-circle-search-back]').forEach(function (link) {
      var saved = read('circle:' + link.dataset.circleSearchBack);
      if (!saved || Date.now() - saved.at > ttl || !localUrl(saved.url) || !localUrl(document.referrer) || !document.referrer) return;
      link.href = saved.url;
      // Reassign after Turbolinks restores a cloned page; listeners are not cloned.
      link.onclick = function () { write('restore', saved); };
    });
    var restore = read('restore');
    if (listing() && restore && restore.url === location.href && Date.now() - restore.at < ttl) {
      write('restore', null);
      // Wait for layout; image slots reserve their dimensions in the listing.
      var scroll = function () { window.scrollTo(0, restore.y); };
      requestAnimationFrame(function () { requestAnimationFrame(scroll); });
      if (document.readyState !== 'complete') window.addEventListener('load', scroll, { once: true });
    }
  }
  document.addEventListener('click', function (event) {
    if (!listing()) return;
    var link = event.target.closest('a[href]');
    var url = link && localUrl(link.href);
    var match = url && url.pathname.match(/^\/circles\/(\d+)\/?$/);
    if (match) write('circle:' + match[1], position());
  });
  document.addEventListener('turbolinks:load', ready);
  window.addEventListener('pageshow', ready);
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', ready, { once: true });
  else ready();
}());

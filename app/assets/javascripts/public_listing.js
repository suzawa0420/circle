// Public collection pages need navigation and Rails link behavior, not the editor,
// gallery, datepicker, jQuery, or Bootstrap JavaScript bundles.
//= require rails-ujs
//= require mobile_navigation

(function () {
  function ready() {
    // Analytics stays early. Start automatic ads once the leading photograph
    // has loaded and painted, avoiding competition for its network bandwidth.
    var adsense = document.querySelector('meta[name="listing-adsense"]');
    if (adsense) {
      var adsStarted = false;
      function startAds() {
        if (adsStarted) return;
        adsStarted = true;
        var script = document.createElement('script');
        script.src = adsense.content;
        script.async = true;
        script.crossOrigin = 'anonymous';
        document.head.appendChild(script);
      }
      function afterImage() {
        window.requestAnimationFrame(function () {
          window.requestAnimationFrame(function () {
            if ('requestIdleCallback' in window) {
              window.requestIdleCallback(startAds, { timeout: 1000 });
            } else {
              startAds();
            }
          });
        });
      }
      var leadingImage = document.querySelector('img.header_imege_user_list[fetchpriority="high"]');
      if (leadingImage && !leadingImage.complete) {
        leadingImage.addEventListener('load', afterImage, { once: true });
        leadingImage.addEventListener('error', afterImage, { once: true });
      } else {
        afterImage();
      }
      // Slow/failed images and background tabs still receive their ad request.
      window.setTimeout(startAds, 4000);
    }
    var placement = document.querySelector('[data-deferred-listing-ad]');
    if (placement) {
      var loaded = false;
      function loadAd() {
        if (loaded) return;
        loaded = true;
        var slot = placement.querySelector('[data-admax-id]');
        (window.admaxads = window.admaxads || []).push({ admax_id: slot.dataset.admaxId, type: 'switch' });
        var script = document.createElement('script');
        script.src = 'https://adm.shinobi.jp/st/t.js';
        script.async = true;
        script.charset = 'utf-8';
        placement.appendChild(script);
      }
      if ('IntersectionObserver' in window) {
        var observer = new IntersectionObserver(function (entries) {
          if (entries.some(function (entry) { return entry.isIntersecting; })) {
            observer.disconnect();
            loadAd();
          }
        }, { rootMargin: '600px' });
        observer.observe(placement);
      } else {
        loadAd();
      }
    }
    document.querySelectorAll('.time-limit').forEach(function (element) {
      window.setTimeout(function () { element.hidden = true; }, 1000);
    });
  }
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', ready, { once: true });
  } else {
    ready();
  }
}());

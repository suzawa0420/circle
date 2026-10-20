(function () {
  if (window.picteAdTrackingBound) return;
  window.picteAdTrackingBound = true;

  function track(event) {
    if (event.defaultPrevented || (event.type === 'auxclick' && event.button !== 1)) return;
    var target = event.target;
    var link = target && target.closest && target.closest('a[data-picte-ad-click]');
    if (!link || !/^(search|mypage)$/.test(link.dataset.picteAdClick)) return;
    var token = document.querySelector('meta[name="csrf-token"]');
    if (!token) return;
    var url = link.dataset.picteClickUrl;
    if (url !== '/picte-ad-clicks') return;

    var payload = new FormData();
    payload.append('placement', link.dataset.picteAdClick);
    payload.append('authenticity_token', token.content);
    // Do not retry an accepted beacon: the same click must count only once.
    if (!navigator.sendBeacon || !navigator.sendBeacon(url, payload)) {
      window.fetch(url, { method: 'POST', body: payload, credentials: 'same-origin', keepalive: true }).catch(function () {});
    }
    window.dataLayer = window.dataLayer || [];
    window.dataLayer.push({ event: 'picte_ad_click', placement: link.dataset.picteAdClick });
  }
  document.addEventListener('click', track);
  document.addEventListener('auxclick', track);
})();

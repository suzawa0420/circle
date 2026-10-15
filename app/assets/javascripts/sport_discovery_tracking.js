(function () {
  if (window.sportDiscoveryTrackingBound) return;
  window.sportDiscoveryTrackingBound = true;
  function track(name, sport) {
    if (!sport || !/^[a-z0-9-]+$/.test(sport)) return;
    window.dataLayer = window.dataLayer || [];
    window.dataLayer.push({ event: name, sport: sport });
  }
  document.addEventListener('click', function (event) {
    var target = event.target;
    if (!target || !target.closest) return;
    var listing = target.closest('a[data-sport-listing-click]');
    if (listing) track('sport_listing_click', listing.dataset.sportListingClick);
  });
  function completed() {
    document.querySelectorAll('[data-sport-inquiry-delivered]').forEach(function (node) {
      track('sport_inquiry_delivered', node.dataset.sportInquiryDelivered);
      node.remove();
    });
  }
  document.addEventListener('DOMContentLoaded', completed);
  document.addEventListener('turbolinks:load', completed);
})();

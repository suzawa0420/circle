(function () {
  // Both bundles and Turbolinks visits may load this file. Bind only once.
  if (window.circleInquiryTrackingBound) return;
  window.circleInquiryTrackingBound = true;

  document.addEventListener('click', function (event) {
    var target = event.target;
    if (!target || typeof target.closest !== 'function') return;
    if (!target.closest('a[data-circle-inquiry-click]')) return;

    // Measure the entry click, including clicks that open the warning dialog.
    // Do not collect message text, account details, or a monetary value.
    // Leave navigation and the contact warning's cancellation behavior intact.
    window.dataLayer = window.dataLayer || [];
    window.dataLayer.push({ event: 'circle_inquiry_click' });
  });
})();

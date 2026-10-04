// Public collection pages need navigation and Rails link behavior, not the editor,
// gallery, datepicker, jQuery, or Bootstrap JavaScript bundles.
//= require rails-ujs
//= require mobile_navigation

(function () {
  function ready() {
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

// Native loading and CSS popups; Swiper remains for multi-photo related posts.
//= require public_listing
//= require circle_contact_warning
//= require swiper.min

(function () {
  function ready() {
    if (document.body.dataset.publicCircleDetail !== 'true') return;
    document.querySelectorAll('.swiper-container').forEach(function (element) {
      if (!element.swiper) new Swiper(element, {
        slidesPerView: 1, spaceBetween: 30, loop: true,
        pagination: { el: element.querySelector('.swiper-pagination'), clickable: true }
      });
    });
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', ready, { once: true });
  else ready();
}());

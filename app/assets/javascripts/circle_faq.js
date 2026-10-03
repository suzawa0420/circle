(function () {
  var animations = new WeakMap();
  document.addEventListener('click', function (event) {
    var summary = event.target.closest('.circle-faq__question');
    if (!summary || !Element.prototype.animate || window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;
    event.preventDefault();
    var details = summary.parentElement;
    var previous = animations.get(details);
    var expand = previous ? !previous.expand : !details.open;
    var start = details.getBoundingClientRect().height;
    if (previous) previous.animation.cancel();
    details.open = true;
    var end = expand ? summary.getBoundingClientRect().height + details.querySelector('.circle-faq__answer').getBoundingClientRect().height + 2 : summary.getBoundingClientRect().height + 2;
    var animation = details.animate({ height: [start + 'px', end + 'px'] }, { duration: 180, easing: 'ease-out' });
    animations.set(details, { animation: animation, expand: expand });
    animation.onfinish = function () { details.open = expand; animations.delete(details); };
  });
}());

(function () {
  var states = new Map();
  var focusSelector = 'a[href], button, input, select, textarea, summary, [tabindex]';

  function syncFocus(state) {
    var boundary = state.content.getBoundingClientRect().top + state.limit - 48;
    state.body.querySelectorAll(focusSelector).forEach(function (element) {
      var clipped = !state.expanded && state.long && element.getBoundingClientRect().bottom > boundary;
      if (clipped && !state.tabs.has(element)) {
        state.tabs.set(element, element.getAttribute('tabindex'));
        element.setAttribute('tabindex', '-1');
      } else if (!clipped && state.tabs.has(element)) {
        var original = state.tabs.get(element);
        if (original === null) element.removeAttribute('tabindex');
        else element.setAttribute('tabindex', original);
        state.tabs.delete(element);
      }
    });
  }

  function measure(state) {
    state.limit = parseFloat(window.getComputedStyle(state.section).getPropertyValue('--circle-readmore-height')) || 320;
    var height = Math.ceil(state.body.getBoundingClientRect().height);
    state.long = height > state.limit + 48;
    state.button.hidden = !state.long;
    state.section.classList.toggle('is-collapsed', state.long && !state.expanded);
    state.content.style.maxHeight = state.long ? (state.expanded ? height : state.limit) + 'px' : '';
    state.button.setAttribute('aria-expanded', String(state.expanded));
    state.button.querySelector('[data-readmore-text]').textContent = state.expanded ? '閉じる' : 'もっと見る';
    state.button.setAttribute('aria-label', state.button.getAttribute('data-readmore-label') + (state.expanded ? 'を閉じる' : 'をもっと見る'));
    syncFocus(state);
  }

  function revealHash() {
    var id;
    try { id = decodeURIComponent(window.location.hash.slice(1)); } catch (_) { return; }
    var target = id && document.getElementById(id);
    if (!target) return;
    states.forEach(function (state) {
      if (state.body.contains(target)) {
        state.expanded = true;
        measure(state);
        target.scrollIntoView({ block: 'start' });
      }
    });
  }

  function init() {
    document.querySelectorAll('[data-circle-readmore]').forEach(function (section) {
      if (states.has(section)) return;
      var state = { section: section, content: section.querySelector('.circle-readmore__content'),
        body: section.querySelector('.circle-readmore__body'), button: section.querySelector('.circle-readmore__button'),
        expanded: false, tabs: new Map() };
      if (!state.content || !state.body || !state.button) return;
      states.set(section, state);
      measure(state);
      if (window.ResizeObserver) {
        state.observer = new ResizeObserver(function () { measure(state); });
        state.observer.observe(state.body);
      }
    });
    revealHash();
  }

  document.addEventListener('click', function (event) {
    var button = event.target.closest('.circle-readmore__button');
    if (!button) return;
    var state = states.get(button.closest('[data-circle-readmore]'));
    if (!state) return;
    state.expanded = !state.expanded;
    measure(state);
    if (!state.expanded && state.section.getBoundingClientRect().top < 0) {
      state.section.scrollIntoView({ block: 'start', behavior: window.matchMedia('(prefers-reduced-motion: reduce)').matches ? 'auto' : 'smooth' });
    }
  });
  document.addEventListener('toggle', function (event) {
    var section = event.target.closest('[data-circle-readmore]');
    if (states.has(section)) measure(states.get(section));
  }, true);
  window.addEventListener('resize', function () { states.forEach(measure); });
  window.addEventListener('hashchange', revealHash);
  document.addEventListener('turbolinks:before-cache', function () {
    states.forEach(function (state) {
      if (state.observer) state.observer.disconnect();
      state.expanded = true;
      syncFocus(state);
      state.section.classList.remove('is-collapsed');
      state.content.style.maxHeight = '';
      state.button.hidden = true;
    });
    states.clear();
  });
  document.addEventListener('DOMContentLoaded', init);
  document.addEventListener('turbolinks:load', init);
  if (document.readyState !== 'loading') init();
})();

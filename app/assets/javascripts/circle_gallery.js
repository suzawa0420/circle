(function () {
  var active = null;

  function display(index, autoplay) {
    var gallery = active;
    if (!gallery) return;
    gallery.index = (index + gallery.slides.length) % gallery.slides.length;
    var slide = gallery.slides[gallery.index];
    var title = slide.dataset.circleGalleryTitle;
    var media;
    var isVideo = slide.dataset.circleGalleryKind === 'video';

    if (isVideo) {
      var videoId = slide.dataset.circleGalleryVideoId;
      if (!/^[A-Za-z0-9_-]{11}$/.test(videoId || '')) return;
      media = document.createElement('iframe');
      media.title = title;
      media.src = 'https://www.youtube-nocookie.com/embed/' + videoId + '?rel=0&autoplay=' + (autoplay ? '1' : '0');
      media.allow = 'autoplay; encrypted-media; picture-in-picture; fullscreen';
      media.allowFullscreen = true;
      media.referrerPolicy = 'strict-origin-when-cross-origin';
    } else {
      media = document.createElement('img');
      media.src = slide.href;
      media.alt = title;
      media.decoding = 'async';
    }

    // Removing the old iframe on every change also stops its audio.
    gallery.media.replaceChildren(media);
    gallery.fallback.hidden = !isVideo;
    if (isVideo) gallery.fallback.href = slide.href;
    else gallery.fallback.removeAttribute('href');
    gallery.status.textContent = (gallery.index + 1) + ' / ' + gallery.slides.length + ' ・ ' + title;
  }

  function closeGallery(restoreFocus) {
    if (!active) return;
    var gallery = active;
    active = null;
    gallery.media.replaceChildren();
    gallery.status.textContent = '';
    gallery.fallback.hidden = true;
    gallery.fallback.removeAttribute('href');
    document.documentElement.style.overflow = gallery.previousOverflow;
    if (gallery.dialog.open) gallery.dialog.close();
    if (restoreFocus && gallery.trigger.isConnected) gallery.trigger.focus({ preventScroll: true });
  }

  document.addEventListener('click', function (event) {
    var trigger = event.target.closest('[data-circle-gallery-open]');
    if (trigger) {
      if (event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
      var container = trigger.closest('[data-circle-gallery]');
      if (!container) return;
      var dialog = container.querySelector('[data-circle-gallery-dialog]');
      if (!dialog || typeof dialog.showModal !== 'function') return;
      var slides = Array.from(container.querySelectorAll('[data-circle-gallery-open]'));
      if (active) closeGallery(false);

      // Leave ordinary links usable when native modal dialogs are unavailable.
      dialog.showModal();
      event.preventDefault();
      active = {
        dialog: dialog,
        slides: slides,
        trigger: trigger,
        media: dialog.querySelector('[data-circle-gallery-media]'),
        status: dialog.querySelector('[data-circle-gallery-status]'),
        fallback: dialog.querySelector('[data-circle-gallery-fallback]'),
        previousOverflow: document.documentElement.style.overflow
      };
      document.documentElement.style.overflow = 'hidden';
      display(slides.indexOf(trigger), trigger.dataset.circleGalleryKind === 'video');
      return;
    }

    if (!active) return;
    var control = event.target.closest('[data-circle-gallery-move]');
    if (control && active.dialog.contains(control)) {
      display(active.index + Number(control.dataset.circleGalleryMove), false);
    } else if (event.target.closest('[data-circle-gallery-close]')) {
      closeGallery(true);
    } else if (event.target === active.dialog) {
      var bounds = active.dialog.getBoundingClientRect();
      if (event.clientX < bounds.left || event.clientX > bounds.right ||
          event.clientY < bounds.top || event.clientY > bounds.bottom) closeGallery(true);
    }
  });

  document.addEventListener('keydown', function (event) {
    if (!active || active.slides.length < 2 || event.altKey || event.ctrlKey || event.metaKey || event.shiftKey) return;
    if (event.key !== 'ArrowLeft' && event.key !== 'ArrowRight') return;
    event.preventDefault();
    display(active.index + (event.key === 'ArrowRight' ? 1 : -1), false);
  });

  document.addEventListener('cancel', function (event) {
    if (!active || event.target !== active.dialog) return;
    event.preventDefault();
    closeGallery(true);
  }, true);

  document.addEventListener('close', function (event) {
    if (active && event.target === active.dialog && !active.dialog.open) closeGallery(true);
  }, true);

  document.addEventListener('turbolinks:before-cache', function () { closeGallery(false); });
  window.addEventListener('pagehide', function () { closeGallery(false); });
})();

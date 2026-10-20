(function () {
  var activeDialog = null;
  var previousOverflow = null;

  function stopVideo() {
    if (!activeDialog) return;
    activeDialog.querySelector('[data-circle-video-player]').textContent = '';
    document.documentElement.style.overflow = previousOverflow;
    activeDialog = null;
    previousOverflow = null;
  }

  function closeVideo() {
    if (!activeDialog) return;
    activeDialog.close();
    stopVideo();
  }

  document.addEventListener('click', function (event) {
    var trigger = event.target.closest('[data-circle-video-open]');
    if (trigger) {
      var dialog = document.getElementById(trigger.getAttribute('aria-controls'));
      if (!dialog || typeof dialog.showModal !== 'function') return;
      var videoId = dialog.getAttribute('data-video-id');
      if (!/^[A-Za-z0-9_-]{11}$/.test(videoId)) return;
      event.preventDefault();
      if (activeDialog) closeVideo();
      dialog.showModal();
      activeDialog = dialog;
      previousOverflow = document.documentElement.style.overflow;
      document.documentElement.style.overflow = 'hidden';
      var iframe = document.createElement('iframe');
      iframe.title = 'サークルのYouTube紹介動画';
      iframe.src = 'https://www.youtube-nocookie.com/embed/' + videoId + '?autoplay=1&rel=0';
      iframe.allow = 'autoplay; encrypted-media; picture-in-picture; fullscreen';
      iframe.allowFullscreen = true;
      iframe.referrerPolicy = 'strict-origin-when-cross-origin';
      dialog.querySelector('[data-circle-video-player]').replaceChildren(iframe);
      return;
    }
    if (!activeDialog) return;
    if (event.target.closest('[data-circle-video-close]')) closeVideo();
    else if (event.target === activeDialog) {
      var bounds = activeDialog.getBoundingClientRect();
      if (event.clientX < bounds.left || event.clientX > bounds.right ||
          event.clientY < bounds.top || event.clientY > bounds.bottom) closeVideo();
    }
  });

  document.addEventListener('close', function (event) {
    if (event.target === activeDialog && !activeDialog.open) stopVideo();
  }, true);

  document.addEventListener('turbolinks:before-cache', function () {
    closeVideo();
  });
})();

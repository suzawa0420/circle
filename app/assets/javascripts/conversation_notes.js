(function () {
  var controllers = [], leaving = false;
  function bind(form) {
    var input = form.querySelector('.chat-private-note__input');
    var status = form.querySelector('.chat-private-note__state');
    var retry = form.querySelector('.chat-private-note__retry');
    var saved = input.value, timer, pending = null, composing = false;
    var item = form.closest('.chat-talk-item');
    function activityValue(value) { return Date.parse(String(value).replace(/(\.\d{3})\d+/, '$1')); }
    function reorder() {
      if (!item || document.activeElement === input) return;
      var list = item.parentNode;
      var siblings = Array.from(list.children);
      var target = siblings.find(function (row) { return row !== item && activityValue(row.dataset.inboxUpdatedAt) < activityValue(item.dataset.inboxUpdatedAt); });
      if (target) list.insertBefore(item, target);
    }
    function updateActivity(timestamp) {
      if (!item || !timestamp || !Number.isFinite(activityValue(timestamp))) return;
      if (activityValue(timestamp) > activityValue(item.dataset.inboxUpdatedAt)) item.dataset.inboxUpdatedAt = timestamp;
      var time = item.querySelector('time');
      if (time) {
        var updated = new Date(activityValue(item.dataset.inboxUpdatedAt));
        var today = new Date();
        time.dateTime = item.dataset.inboxUpdatedAt;
        var localDate = function (date) { return new Intl.DateTimeFormat('ja-JP', { timeZone: 'Asia/Tokyo', month: 'numeric', day: 'numeric' }).format(date); };
        time.textContent = localDate(updated) === localDate(today) ? new Intl.DateTimeFormat('ja-JP', { timeZone: 'Asia/Tokyo', hour: '2-digit', minute: '2-digit', hourCycle: 'h23' }).format(updated) : localDate(updated);
      }
      reorder();
    }
    function dirty() { return pending !== null || input.value !== saved; }
    function message(text, success) { status.textContent = text; status.dataset.saved = String(!!success); }
    function save() {
      window.clearTimeout(timer);
      if (pending) return pending;
      if (!dirty() || composing) return Promise.resolve(!dirty());
      var value = input.value;
      var token = form.querySelector('input[name="authenticity_token"]');
      message('保存中…');
      retry.hidden = true;
      pending = fetch(form.action, {
        method: 'PATCH', credentials: 'same-origin', cache: 'no-store', keepalive: true,
        headers: { 'Accept': 'application/json', 'Content-Type': 'application/json', 'X-CSRF-Token': token ? token.value : '' },
        body: JSON.stringify({ note: { body: value } })
      }).then(function (response) {
        if (!response.ok || response.redirected) throw new Error('Save failed');
        return response.json();
      }).then(function (data) {
        if (data.saved !== true) throw new Error('Save failed');
        saved = value;
        updateActivity(data.updated_at);
        pending = null;
        if (dirty()) return save();
        message('保存済み', true);
        return true;
      }).catch(function () {
        pending = null;
        message('保存できませんでした');
        retry.hidden = false;
        return false;
      });
      return pending;
    }
    function changed() {
      window.clearTimeout(timer);
      message(dirty() ? '未保存' : '保存済み', !dirty());
      if (!composing && dirty()) timer = window.setTimeout(save, 700);
    }
    function compositionStart() { composing = true; window.clearTimeout(timer); }
    function compositionEnd() { composing = false; changed(); }
    function blur() { save().then(reorder); }
    function submit(event) { event.preventDefault(); save(); }
    input.addEventListener('input', changed);
    input.addEventListener('blur', blur);
    input.addEventListener('compositionstart', compositionStart);
    input.addEventListener('compositionend', compositionEnd);
    form.addEventListener('submit', submit);
    retry.addEventListener('click', save);
    return { dirty: dirty, save: save, cleanup: function () {
      window.clearTimeout(timer);
      input.removeEventListener('input', changed);
      input.removeEventListener('blur', blur);
      input.removeEventListener('compositionstart', compositionStart);
      input.removeEventListener('compositionend', compositionEnd);
      form.removeEventListener('submit', submit);
      retry.removeEventListener('click', save);
    } };
  }
  function stop() { controllers.forEach(function (controller) { controller.cleanup(); }); controllers = []; }
  function start() {
    stop();
    leaving = false;
    document.querySelectorAll('[data-private-note]').forEach(function (form) { controllers.push(bind(form)); });
  }
  document.addEventListener('DOMContentLoaded', start);
  document.addEventListener('turbolinks:load', start);
  document.addEventListener('turbolinks:before-cache', stop);
  document.addEventListener('turbolinks:before-visit', function (event) {
    if (leaving || !controllers.some(function (controller) { return controller.dirty(); })) return;
    event.preventDefault();
    Promise.all(controllers.map(function (controller) { return controller.save(); })).then(function (results) {
      if (results.every(Boolean) && !controllers.some(function (controller) { return controller.dirty(); })) {
        leaving = true;
        window.Turbolinks.visit(event.data.url);
      }
    });
  });
  window.addEventListener('beforeunload', function (event) {
    if (!controllers.some(function (controller) { return controller.dirty(); })) return;
    controllers.forEach(function (controller) { controller.save(); });
    event.preventDefault();
    event.returnValue = '';
  });
  window.addEventListener('online', function () { controllers.forEach(function (controller) { if (controller.dirty()) controller.save(); }); });
  if (document.readyState !== 'loading') start();
})();

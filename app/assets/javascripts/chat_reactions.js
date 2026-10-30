(function () {
  var cleanup = function () {};
  function start() {
    cleanup();
    var thread = document.getElementById('chat-messages');
    if (!thread) return;
    var opened, watcher, pending = {};
    function closeReports(except) {
      thread.querySelectorAll('.chat-message__report[open]').forEach(function (report) {
        if (report !== except) report.open = false;
      });
    }
    function closePicker(restoreFocus) {
      if (!opened) return;
      var summary = opened.querySelector('summary');
      opened.open = false;
      opened = null;
      if (watcher) { watcher.destroy(); watcher = null; }
      if (restoreFocus && summary && document.body.contains(summary)) summary.focus({ preventScroll: true });
    }
    function click(event) {
      var summary = event.target.closest('.chat-reactions__picker > summary');
      if (summary && thread.contains(summary)) {
        event.preventDefault();
        if (summary.parentElement === opened) return closePicker(false);
        closePicker(false);
        closeReports();
        opened = summary.parentElement;
        opened.open = true;
        // Native close requests (including supported mobile Back buttons) do
        // not add history entries or trigger Turbolinks page restoration.
        if (window.CloseWatcher) {
          watcher = new window.CloseWatcher();
          watcher.addEventListener('close', function () { closePicker(true); });
        }
      } else if (event.target.closest('[data-chat-reaction-close]')) {
        closePicker(true);
      } else if (opened && !opened.contains(event.target)) {
        closePicker(false);
      }
      var reportSummary = event.target.closest('.chat-message__report > summary');
      if (reportSummary && thread.contains(reportSummary)) closeReports(reportSummary.parentElement);
      else thread.querySelectorAll('.chat-message__report[open]').forEach(function (report) {
        if (!report.contains(event.target)) report.open = false;
      });
    }
    function keydown(event) {
      if (event.key === 'Escape' && opened) {
        event.preventDefault();
        closePicker(true);
      }
      if (event.key === 'Escape') closeReports();
    }
    function submit(event) {
      var form = event.target.closest('[data-chat-reaction-form]');
      if (!form || !thread.contains(form)) return;
      var choice = event.submitter;
      // Keep the ordinary form fallback when a browser lacks submitter support.
      if (!choice) return;
      event.preventDefault();
      var wrapper = form.closest('[data-chat-reactions]'), id = wrapper.id;
      if (pending[id]) return;
      pending[id] = true;
      closePicker(false);
      wrapper.setAttribute('aria-busy', 'true');
      form.querySelectorAll('button').forEach(function (button) { button.disabled = true; });
      var status = wrapper.querySelector('[role="status"]');
      status.removeAttribute('data-error');
      status.textContent = '保存中…';
      fetch(form.action, { method: 'PUT', credentials: 'same-origin', cache: 'no-store',
        headers: { 'Accept': 'application/json', 'Content-Type': 'application/json', 'X-CSRF-Token': form.querySelector('[name="authenticity_token"]').value },
        body: JSON.stringify({ reaction: { key: choice.value } })
      }).then(function (response) {
        if (response.redirected) throw new Error('ログイン状態を確認して、ページを再読み込みしてください。');
        if (!response.ok && response.status !== 422) throw new Error('保存できませんでした。ページを再読み込みしてからお試しください。');
        return response.json();
      }).then(function (data) {
        if (data.error) throw new Error(data.error);
        if (typeof data.html !== 'string') throw new Error('保存結果を確認できませんでした。ページを再読み込みしてください。');
        if (!document.body.contains(wrapper)) return;
        wrapper.outerHTML = data.html;
        var updated = document.getElementById(id);
        if (updated) {
          updated.querySelector('[role="status"]').textContent = choice.value ? 'リアクションを保存しました。' : 'リアクションを取り消しました。';
          var summary = updated.querySelector('summary');
          if (summary) summary.focus({ preventScroll: true });
        }
      }).catch(function (error) {
        if (document.body.contains(wrapper)) {
          status.textContent = error.message || '保存できませんでした。もう一度お試しください。';
          status.setAttribute('data-error', 'true');
        }
      }).then(function () {
        delete pending[id];
        if (document.body.contains(wrapper)) {
          wrapper.removeAttribute('aria-busy');
          form.querySelectorAll('button').forEach(function (button) { button.disabled = false; });
        }
      });
    }
    document.addEventListener('click', click);
    document.addEventListener('keydown', keydown);
    thread.addEventListener('submit', submit);
    cleanup = function () {
      closePicker(false);
      document.removeEventListener('click', click);
      document.removeEventListener('keydown', keydown);
      thread.removeEventListener('submit', submit);
    };
  }
  document.addEventListener('DOMContentLoaded', start);
  document.addEventListener('turbolinks:load', start);
  document.addEventListener('turbolinks:before-cache', function () { cleanup(); cleanup = function () {}; });
  if (document.readyState !== 'loading') start();
})();

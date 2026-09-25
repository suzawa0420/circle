(function () {
  'use strict';
  var loader;
  var nodes = [];

  function message(node, text) {
    var status = node.nextElementSibling;
    if (status) status.textContent = text;
  }

  function renderWidgets() {
    if (!window.turnstile) return;
    document.querySelectorAll('.registration-turnstile').forEach(function (node) {
      if (node.hasAttribute('data-widget-id')) return;
      var id = window.turnstile.render(node, {
        sitekey: node.getAttribute('data-sitekey'),
        action: 'registration',
        language: 'ja',
        'refresh-expired': 'auto',
        callback: function () { message(node, '認証が完了しました。'); },
        'expired-callback': function () { message(node, '認証の有効期限が切れました。再認証をお待ちください。'); },
        'error-callback': function () {
          message(node, '認証を読み込めませんでした。通信状態を確認し、ページを再読み込みしてください。');
        }
      });
      node.setAttribute('data-widget-id', id);
      nodes.push(node);
    });
  }

  window.circleRegistrationTurnstileReady = renderWidgets;

  function loadWidgets() {
    if (!document.querySelector('.registration-turnstile')) return;
    if (window.turnstile) { renderWidgets(); return; }
    if (loader) return;
    loader = document.createElement('script');
    loader.src = 'https://challenges.cloudflare.com/turnstile/v0/api.js?onload=circleRegistrationTurnstileReady&render=explicit';
    loader.async = true;
    loader.defer = true;
    loader.onerror = function () {
      document.querySelectorAll('.registration-turnstile').forEach(function (node) {
        message(node, '認証を読み込めませんでした。通信状態を確認し、ページを再読み込みしてください。');
      });
      loader.remove();
      loader = null;
    };
    document.head.appendChild(loader);
  }

  document.addEventListener('DOMContentLoaded', loadWidgets);
  document.addEventListener('turbolinks:load', loadWidgets);
  document.addEventListener('turbolinks:before-cache', function () {
    nodes.forEach(function (node) {
      if (window.turnstile) window.turnstile.remove(node.getAttribute('data-widget-id'));
      node.removeAttribute('data-widget-id');
      node.textContent = '';
      message(node, '登録前に認証を行います。');
    });
    nodes = [];
  });
})();

(function () {
  if (window.columnEditorBound) return;
  window.columnEditorBound = true;
  var productSequence = 0;

  document.addEventListener('trix-file-accept', function (event) {
    if (event.target.closest('[data-column-editor]')) event.preventDefault();
  });
  document.addEventListener('click', function (event) {
    var insert = event.target.closest('[data-column-insert-product]');
    if (insert) {
      var insertForm = insert.closest('form');
      var insertEditor = insertForm.querySelector('trix-editor');
      if (!insertEditor.editor) return;
      var rows = Array.prototype.slice.call(insertForm.querySelectorAll('[data-column-products] .column-product-fields'));
      rows = rows.filter(function (row) { return !row.querySelector('input[type="checkbox"][name$="[_destroy]"]').checked; });
      rows.sort(function (a, b) { return Number(a.querySelector('input[type="number"]').value) - Number(b.querySelector('input[type="number"]').value); });
      var number = rows.indexOf(insert.closest('.column-product-fields')) + 1;
      if (!number) {
        insertForm.querySelector('[data-column-editor-status]').textContent = '削除予定の商品は挿入できません。';
        return;
      }
      insertEditor.editor.insertDocument(window.Trix.Document.fromString('[商品:' + number + ']'));
      insertEditor.focus();
      insertForm.querySelector('[data-column-editor-status]').textContent = '商品カードを挿入しました。保存してプレビューを確認してください。';
    }
    var add = event.target.closest('[data-column-add-product]');
    if (add) {
      var form = add.closest('form');
      var list = form.querySelector('[data-column-products]');
      var fields = list.querySelectorAll('.column-product-fields');
      if (fields.length >= 12) {
        form.querySelector('[data-column-editor-status]').textContent = '紹介商品は最大12件です。不要な商品を削除して保存してください。';
        return;
      }
      // Rails strong parameters recognizes numeric keys as nested collections.
      var key = String(Date.now()) + String(productSequence++);
      list.insertAdjacentHTML('beforeend', form.querySelector('[data-column-product-template]').innerHTML.replace(/NEW_PRODUCT/g, key));
      var inserted = list.lastElementChild;
      inserted.querySelector('input[type="number"]').value = fields.length;
      inserted.querySelector('input[type="text"]').focus();
    }
    var button = event.target.closest('[data-column-template]');
    if (button) {
      var editor = button.closest('form').querySelector('trix-editor');
      if (!editor.editor) return;
      var status = button.closest('form').querySelector('[data-column-editor-status]');
      if (editor.editor.getDocument().toString().trim()) {
        status.textContent = '本文が入力済みのため、構成は挿入していません。';
        return;
      }
      var template = document.getElementById('column-template-' + button.dataset.columnTemplate);
      if (template) {
        editor.editor.loadHTML(template.innerHTML);
        status.textContent = '構成を挿入しました。内容を書き換えて下書き保存してください。';
      }
    }
    var link = event.target.closest('a[data-column-shop]');
    if (!link || event.defaultPrevented || event.button > 0) return;
    recordClick(link);
  });
  document.addEventListener('change', function (event) {
    if (!event.target.matches('[data-column-cover-input]')) return;
    var preview = event.target.closest('form').querySelector('[data-column-cover-preview]');
    if (!preview) return;
    if (preview.dataset.objectUrl) URL.revokeObjectURL(preview.dataset.objectUrl);
    var file = event.target.files[0];
    if (!file || !/^image\/(jpeg|png)$/.test(file.type)) {
      preview.hidden = true;
      return;
    }
    preview.src = URL.createObjectURL(file);
    preview.dataset.objectUrl = preview.src;
    preview.hidden = false;
  });
  document.addEventListener('auxclick', function (event) {
    var link = event.target.closest('a[data-column-shop]');
    if (link && !event.defaultPrevented && event.button === 1) recordClick(link);
  });
  function recordClick(link) {
    var url = link.dataset.columnClickUrl;
    var shop = link.dataset.columnShop;
    var token = document.querySelector('meta[name="csrf-token"]');
    if (!token || !/^\/columns\/\d+\/products\/\d+\/click$/.test(url) || shop !== 'amazon') return;
    var payload = new FormData();
    payload.append('shop', shop);
    payload.append('authenticity_token', token.content);
    if (!navigator.sendBeacon || !navigator.sendBeacon(url, payload)) {
      if (window.fetch) window.fetch(url, { method: 'POST', body: payload, credentials: 'same-origin', keepalive: true }).catch(function () {});
    }
  }
})();

(function () {
  if (window.circleTrixTextOnly) return;
  window.circleTrixTextOnly = true;

  var controls = '[data-trix-button-group="file-tools"], [data-trix-action="attachFiles"]';
  var initialized = new WeakSet();
  var trix = window.Trix;
  if (trix && trix.config && trix.config.toolbar) {
    var originalToolbar = trix.config.toolbar.getDefaultHTML;
    trix.config.toolbar.getDefaultHTML = function () {
      var template = document.createElement('template');
      template.innerHTML = originalToolbar.apply(this, arguments);
      template.content.querySelectorAll(controls).forEach(function (node) { node.remove(); });
      return template.innerHTML;
    };
  }

  function editorFor(event) {
    return event.target.closest && event.target.closest('trix-editor');
  }

  document.addEventListener('trix-initialize', function (event) {
    var editor = editorFor(event);
    if (!editor) return;
    initialized.add(editor);
    // Toolbars created before this script loaded, including external event toolbars.
    if (editor.toolbarElement) {
      editor.toolbarElement.querySelectorAll(controls).forEach(function (node) { node.remove(); });
    }
  });
  document.addEventListener('trix-file-accept', function (event) {
    if (editorFor(event)) event.preventDefault();
  });
  document.addEventListener('drop', function (event) {
    if (editorFor(event) && event.dataTransfer && Array.from(event.dataTransfer.types).includes('Files')) {
      event.preventDefault();
      event.stopImmediatePropagation();
    }
  }, true);
  document.addEventListener('trix-before-paste', function (event) {
    if (!editorFor(event) || !event.paste || !event.paste.html) return;
    var template = document.createElement('template');
    template.innerHTML = event.paste.html;
    template.content.querySelectorAll('img, picture, video, audio, source, object, embed, iframe, action-text-attachment, [data-trix-attachment]').forEach(function (node) {
      node.remove();
    });
    event.paste.html = template.innerHTML;
  });
  document.addEventListener('trix-attachment-add', function (event) {
    var editor = editorFor(event);
    // Do not change historical content merely by loading it into an edit form.
    if (editor && initialized.has(editor) && event.attachment) event.attachment.remove();
  });
})();

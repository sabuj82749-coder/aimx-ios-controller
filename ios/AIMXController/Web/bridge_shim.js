// AIM-X Controller iOS bridge shim.
// Maps the Android `window.AndroidBridge.*` API used by controller.html onto
// WKWebView message handlers. controller.html itself is never modified.
(function () {
  'use strict';
  if (window.AndroidBridge) {
    return;
  }
  function post(name, body) {
    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers[name]) {
      window.webkit.messageHandlers[name].postMessage(body || {});
    }
  }
  window.AndroidBridge = {
    sendStateToPC: function (stateJson) {
      post('sendStateToPC', { state: String(stateJson || '') });
    },
    onControlAction: function (action, value) {
      post('onControlAction', { action: String(action || ''), value: String(value || '') });
    },
    sendBypassRequest: function () {
      post('sendBypassRequest', {});
    },
    onPageLoaded: function () {
      post('onPageLoaded', {});
    }
  };
})();
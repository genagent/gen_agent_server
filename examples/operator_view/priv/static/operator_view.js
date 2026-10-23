// Connects the observer page's LiveView socket. Served as a file so the
// page's content security policy needs no inline script.
(function () {
  var meta = document.querySelector("meta[name='csrf-token']");
  var csrfToken = meta ? meta.getAttribute("content") : "";
  var liveSocket = new window.LiveView.LiveSocket("/live", window.Phoenix.Socket, {
    params: { _csrf_token: csrfToken }
  });
  liveSocket.connect();
  window.liveSocket = liveSocket;
})();

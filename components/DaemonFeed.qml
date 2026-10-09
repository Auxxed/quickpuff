import QtQuick
import Quickshell
import Quickshell.Io

// The daemon's event socket, read as newline-delimited JSON with a ceiling:
// bytes are counted as they arrive, before any line is assembled, and a line
// past maxLine drops the connection (the owner may reconnect) instead of
// buffering on. Only status events are passed on.
Socket {
  id: feed

  property int maxLine: 262144
  property string _buf: ""
  property bool _dropping: false

  signal status(var data)

  // QUICKPUFF_SOCKET when it's an absolute path, else quickpuff.sock in the
  // runtime dir. Without a runtime dir there's nothing to connect to; no
  // guessing at a shared path.
  readonly property string socketPath: {
    var override = Quickshell.env("QUICKPUFF_SOCKET") || ""
    if (override !== "") return override.charAt(0) === "/" ? override : ""
    var run = Quickshell.env("XDG_RUNTIME_DIR") || ""
    return run.charAt(0) === "/" ? run + "/quickpuff.sock" : ""
  }

  path: socketPath
  onConnectedChanged: {
    _buf = ""
    _dropping = false
  }

  // Dropped after the read that found it, not from inside it.
  function drop() {
    _buf = ""
    _dropping = true
    Qt.callLater(function() { feed.connected = false })
  }

  parser: SplitParser {
    splitMarker: ""
    onRead: function(chunk) {
      if (feed._dropping) return
      var buf = feed._buf + chunk
      for (var nl = buf.indexOf("\n"); nl >= 0; nl = buf.indexOf("\n")) {
        var line = buf.slice(0, nl)
        buf = buf.slice(nl + 1)
        if (line.length > feed.maxLine) {
          feed.drop()
          return
        }
        if (line.indexOf('"status"') < 0) continue
        var msg = null
        try { msg = JSON.parse(line) } catch (e) {}
        if (msg && msg.event === "status" && msg.data && typeof msg.data === "object") feed.status(msg.data)
      }
      if (buf.length > feed.maxLine) {
        feed.drop()
        return
      }
      feed._buf = buf
    }
  }
}

import QtQuick
import Quickshell
import Quickshell.Io

// A Process whose output can't grow without bound. stdout and stderr arrive
// as raw chunks (no line assembly) and are counted as they come in; past
// maxBytes, or past timeoutMs, the process is stopped (TERM, then KILL two
// seconds on) and the run reported as failed. stderr keeps only its last
// maxErrBytes, so chatty logging doesn't fail a command that worked. The
// quickpuff CLI prints ASCII JSON, so string length is the byte count.
Process {
  id: proc

  property int maxBytes: 262144
  property int maxErrBytes: 4096
  property int timeoutMs: 10000

  // ok: exited 0 inside every bound. code: the exit code; 127 when the
  // program couldn't be started at all (QuickPuff isn't installed); -1 when
  // it was stopped for a bound or died from a signal. out is empty unless
  // the process exited by itself. Emitted while `running` is still true, so
  // start the next run from onRunningChanged or Qt.callLater.
  signal done(bool ok, int code, string out, string err)

  property string _out: ""
  property string _err: ""
  property bool _launched: false
  property bool _started: false
  property bool _stopped: false

  // Starts argv unless a run is still going; false when it didn't start.
  function launch(argv) {
    if (running || _launched) return false
    command = argv
    _out = ""
    _err = ""
    _started = false
    _stopped = false
    _launched = true
    running = true
    return true
  }

  function stop() {
    if (!running || _stopped) return
    _stopped = true
    _out = ""
    signal(15)
    killTimer.restart()
  }

  stdout: SplitParser {
    splitMarker: ""
    onRead: function(chunk) {
      if (proc._stopped) return
      if (proc._out.length + chunk.length > proc.maxBytes) {
        proc.stop()
        return
      }
      proc._out += chunk
    }
  }

  stderr: SplitParser {
    splitMarker: ""
    onRead: function(chunk) {
      var tail = proc._err + chunk
      proc._err = tail.length > proc.maxErrBytes ? tail.slice(tail.length - proc.maxErrBytes) : tail
    }
  }

  onStarted: {
    _started = true
    deadline.restart()
  }

  onExited: function(exitCode, exitStatus) {
    deadline.stop()
    killTimer.stop()
    var failed = _stopped || exitStatus !== 0
    var out = failed ? "" : _out
    var err = _err
    _out = ""
    _err = ""
    _launched = false
    done(!failed && exitCode === 0, failed ? -1 : exitCode, out, err)
  }

  // A program that isn't there never starts, and then no exited comes.
  onRunningChanged: {
    if (running || !_launched || _started) return
    _launched = false
    done(false, 127, "", "")
  }

  property Timer deadline: Timer {
    interval: proc.timeoutMs
    onTriggered: proc.stop()
  }

  // Kept running after TERM, so a process that ignores it still goes.
  property Timer killTimer: Timer {
    interval: 2000
    onTriggered: if (proc.running) proc.signal(9)
  }

  Component.onDestruction: if (running) signal(9)
}

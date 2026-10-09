import QtQuick
import Quickshell

// How the plugin runs the quickpuff CLI: the Python environment install.sh
// made, running this checkout's src. No login shell and no PATH lookup, and
// Python starts isolated (-I), so PYTHONPATH and the like can't put other
// code first. The boot line is a constant; the src path and every argument
// travel in argv. --no-start: the shell never starts the daemon itself; the
// systemd unit install.sh set up runs it.
QtObject {
  readonly property string python: {
    var data = Quickshell.env("XDG_DATA_HOME") || ""
    if (data.charAt(0) !== "/") data = Quickshell.env("HOME") + "/.local/share"
    return data + "/quickpuff/venv/bin/python"
  }
  readonly property string src: decodeURIComponent(String(Qt.resolvedUrl("../src")).replace(/^file:\/\//, ""))
  readonly property string boot: "import sys; sys.path.insert(0, sys.argv.pop(1)); from quickpuff.cli import main; main()"

  function argv(args) {
    return [python, "-I", "-c", boot, src, "--no-start"].concat(args.map(String))
  }

  // Fire-and-forget, for the controls: nothing is read back, and a call that
  // hangs is stopped after a minute (TERM, then KILL).
  function fire(args) {
    Quickshell.execDetached(["/usr/bin/timeout", "-k", "2", "60"].concat(argv(args)))
  }
}

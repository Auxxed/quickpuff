#!/usr/bin/bash
# Removes QuickPuff: the daemon and its unit, the `quickpuff` command, the
# Python environment and the plugin. Your dab history and saved lights
# (~/.local/share/quickpuff) and settings (~/.config/quickpuff) are kept;
# delete those folders too for a clean removal.
set -euo pipefail

BIN_DIR="${XDG_BIN_HOME:-$HOME/.local/bin}"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
DATA_DIR="$DATA_HOME/quickpuff"
UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
PLUGIN_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins"
PLUGIN_ID="auxxed.quickpuff"
UNIT="$UNIT_DIR/quickpuff-daemon.service"
COMMAND="$BIN_DIR/quickpuff"
VENV="$DATA_DIR/venv"

# Only what install.sh made is deleted, and only once it's known to be that:
# a plain file carrying install.sh's `-m quickpuff` line, or a real directory
# with a venv's pyvenv.cfg. Anything else at those paths (a symlink, a file
# of yours) is left where it is, with a note.
ours() { [[ -f $1 && ! -L $1 ]] && grep -q -- '-m quickpuff' "$1"; }

systemctl --user disable --now quickpuff-daemon.service >/dev/null 2>&1 || true
if ours "$UNIT"; then
  rm -f -- "$UNIT"
elif [[ -e $UNIT || -L $UNIT ]]; then
  echo "Left $UNIT alone: it isn't the unit install.sh wrote."
fi
systemctl --user daemon-reload >/dev/null 2>&1 || true

if ours "$COMMAND"; then
  rm -f -- "$COMMAND"
elif [[ -e $COMMAND || -L $COMMAND ]]; then
  echo "Left $COMMAND alone: it isn't the command install.sh wrote."
fi

if [[ -d $VENV && ! -L $VENV && -f $VENV/pyvenv.cfg && ! -L $VENV/pyvenv.cfg ]]; then
  rm -rf -- "$VENV"
elif [[ -e $VENV || -L $VENV ]]; then
  echo "Left $VENV alone: it isn't the Python environment install.sh made."
fi

echo "QuickPuff removed. Dab history ($DATA_DIR) and settings (~/.config/quickpuff) were kept."

target="$PLUGIN_DIR/$PLUGIN_ID"
if [[ -L $target ]]; then
  command -v omarchy >/dev/null && omarchy plugin disable "$PLUGIN_ID" >/dev/null 2>&1 || true
  rm -f -- "$target"
  command -v omarchy-shell >/dev/null && omarchy-shell -q shell rescanPlugins
elif [[ -d $target ]] && command -v omarchy >/dev/null; then
  # Last, because this deletes the folder this script runs from.
  exec omarchy plugin remove "$PLUGIN_ID" --yes
fi

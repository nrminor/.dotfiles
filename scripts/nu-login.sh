#!/bin/sh
# GUI terminal servers do not inherit the interactive shell's XDG environment.
set -eu
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
mise_data="${MISE_DATA_DIR:-$HOME/.local/share/mise}"
exec "$mise_data/shims/nu" --login "$@"

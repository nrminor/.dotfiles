#!/bin/sh
# Follow Rex.app's selected server release without pinning a versioned binary.
set -eu
rex="$HOME/Library/Application Support/com.superlogical.rex/RexServer/Versions/Current/Rex Server.app/Contents/MacOS/rex"
if [ ! -x "$rex" ]; then
	printf '%s\n' 'Open Rex Beta once to install its server and CLI.' >&2
	exit 127
fi
exec "$rex" "$@"

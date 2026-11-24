#!/bin/sh
# Initial installation only. Rex owns subsequent application/server updates.
set -eu
[ "$(uname -s)" = Darwin ] || exit 0
for app in "/Applications/Rex Beta.app" "/Applications/Rex.app" \
	"$HOME/Applications/Rex Beta.app" "$HOME/Applications/Rex.app"; do
	if [ -d "$app" ]; then
		printf 'Keeping installed application: %s\n' "$app"
		exit 0
	fi
done

[ "$(uname -m)" = arm64 ] || {
	printf '%s\n' 'This Rex preview bootstrap supports Apple Silicon only.' >&2
	exit 1
}
work=$(mktemp -d "${TMPDIR:-/tmp}/rex-install.XXXXXX")
mounted=false
staging=
cleanup() {
	if [ -n "$staging" ]; then rm -rf "$staging"; fi
	if [ "$mounted" = true ]; then
		hdiutil detach "$work/mount" >/dev/null || return
	fi
	rm -rf "$work"
}
trap cleanup EXIT
curl --fail --location --proto '=https' --proto-redir '=https' \
	'https://blob.superlogical.com/download/rex-app/preview/latest.dmg' -o "$work/rex.dmg"
mkdir "$work/mount"
hdiutil attach "$work/rex.dmg" -readonly -nobrowse -mountpoint "$work/mount" >/dev/null
mounted=true
bundle="$work/mount/Rex Beta.app"
# Verify both integrity and the publisher, not just the presence of a signature.
codesign --verify --deep --strict -R \
	'anchor apple generic and identifier "com.superlogical.rex" and certificate leaf[subject.OU] = "AG92C3PT77"' "$bundle"
spctl --assess --type execute "$bundle"
mkdir -p "$HOME/Applications"
destination="$HOME/Applications/Rex Beta.app"
if [ -e "$destination" ] || [ -L "$destination" ]; then
	printf 'Refusing to overwrite %s\n' "$destination" >&2
	exit 1
fi
staging=$(mktemp -d "$HOME/Applications/.rex-install.XXXXXX")
ditto "$bundle" "$staging/Rex Beta.app"
mv -n "$staging/Rex Beta.app" "$HOME/Applications/"
if [ -d "$staging/Rex Beta.app" ]; then
	printf 'Another installation appeared at %s; left it untouched.\n' "$destination" >&2
	exit 1
fi
printf 'Installed %s. Open it once, then run mise run rex:setup.\n' "$destination"

# ============================================================================
# Login shell initialization
# Runs once at login, before .zshrc
# ============================================================================

# Display system info on login
# if command -v fastfetch >/dev/null 2>&1; then
# 	echo ""
# 	fastfetch
# 	echo ""
# fi

# Check if nix-darwin flake needs updating (once per login)
if command -v nix >/dev/null 2>&1; then
	FLAKE_DIR="$XDG_CONFIG_HOME/nix-darwin"
	if [ -f "$FLAKE_DIR/flake.lock" ]; then
		# Check if flake.lock is older than 7 days (follow symlinks with -L)
		if [ -n "$(find -L "$FLAKE_DIR/flake.lock" -mtime +7 2>/dev/null)" ]; then
			# Get the real path by resolving the flake.nix symlink
			FLAKE_PATH="$(readlink "$FLAKE_DIR/flake.nix" 2>/dev/null)"
			if [ -n "$FLAKE_PATH" ]; then
				REAL_FLAKE_DIR="$(dirname "$FLAKE_PATH")"
			else
				REAL_FLAKE_DIR="$FLAKE_DIR"
			fi
			echo "💡 Tip: Your nix-darwin flake hasn't been updated in over a week."
			echo "   Run: cd $REAL_FLAKE_DIR && nix flake update && darwin-rebuild switch --flake ."
		fi
	fi
fi

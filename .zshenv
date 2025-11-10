# ============================================================================
# Environment variables for all zsh shells (login, interactive, scripts)
# Sourced first, before .zprofile and .zshrc
# ============================================================================

# Enable automatic PATH deduplication (zsh built-in magic!)
typeset -U PATH path
typeset -U LIBRARY_PATH library_path
typeset -U PKG_CONFIG_PATH pkg_config_path

# CORE EDITOR CONFIGURATION
# ---------------------------------------------------------------------------
export VISUAL=hx
export EDITOR="$VISUAL"
export GIT_EDITOR=hx

# LOCALE SETTINGS
# ---------------------------------------------------------------------------
export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8

# XDG BASE DIRECTORY
# ---------------------------------------------------------------------------
export XDG_CONFIG_HOME="$HOME/.config"

# HOMEBREW CONFIGURATION
# ---------------------------------------------------------------------------
export BREW_PREFIX=/opt/homebrew # Hard-code for performance (avoid calling brew --prefix)
export HOMEBREW_NO_AUTO_UPDATE=1

# PATH CONSTRUCTION
# ---------------------------------------------------------------------------
# Build PATH with priority order (highest priority first)
path=(
	# User binaries (highest priority)
	/usr/local/bin
	$HOME/.cargo/bin # Rust
	$HOME/.pixi/bin  # Pixi (Python)

	# Homebrew
	$BREW_PREFIX/bin
	$BREW_PREFIX/sbin
	$BREW_PREFIX/lib

	# Runtime environments
	$HOME/.deno/bin  # Deno
	$HOME/.bun/bin   # Bun
	$HOME/go/bin     # Go
	$HOME/.local/bin # Local scripts

	# Nix (if present)
	$HOME/.nix-profile/bin
	/run/current-system/sw/bin
	/nix/var/nix/profiles/default/bin

	# System paths (lowest priority)
	$path # Preserve existing system paths
)

# LIBRARY AND COMPILER PATHS
# ---------------------------------------------------------------------------
library_path=(
	$BREW_PREFIX/lib
	/opt/homebrew/opt/libiconv/lib
	$BREW_PREFIX/opt/libiconv/lib
	$BREW_PREFIX/opt/zlib/lib
	$library_path
)

export LDFLAGS="-L/opt/homebrew/opt/libiconv/lib -L$BREW_PREFIX/opt/zlib/lib"
export CPPFLAGS="-I/opt/homebrew/opt/libiconv/include
-I$BREW_PREFIX/opt/zlib/include"

pkg_config_path=(
	$BREW_PREFIX/opt/zlib/lib/pkgconfig
	$pkg_config_path
)

# LANGUAGE-SPECIFIC ENVIRONMENTS
# ---------------------------------------------------------------------------
# Go
export GOPATH="$HOME/go"
export GOBIN="$GOPATH/bin"

# Node.js / NVM
export NVM_DIR="$HOME/.config/nvm"

# nu / nushell
export TOPIARY_CONFIG_FILE=$XDG_CONFIG_HOME/topiary/languages.ncl
export TOPIARY_LANGUAGE_DIR=$XDG_CONFIG_HOME/topiary/languages

# TOOL CONFIGURATION
# ---------------------------------------------------------------------------
export BAT_THEME="OneHalfDark"
export CARAPACE_BRIDGES='zsh,bash,clap,click'

# Disable compfix warnings
export ZSH_DISABLE_COMPFIX=true

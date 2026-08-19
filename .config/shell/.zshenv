# ============================================================================
# Environment variables for all zsh shells (login, interactive, scripts)
# Sourced first, before .zprofile and .zshrc
# ============================================================================

# Enable automatic PATH deduplication (zsh built-in magic!)
typeset -U PATH path
typeset -TU LIBRARY_PATH library_path
typeset -TU PKG_CONFIG_PATH pkg_config_path

# CORE EDITOR CONFIGURATION
# ---------------------------------------------------------------------------
export VISUAL=nvim
export EDITOR="$VISUAL"
export GIT_EDITOR=nvim

# LOCALE SETTINGS
# ---------------------------------------------------------------------------
if [[ -z "${LANG:-}" ]]; then
	if [[ "$OSTYPE" == darwin* ]]; then
		export LANG=en_US.UTF-8
	else
		export LANG=C.UTF-8
	fi
fi

# XDG BASE DIRECTORY
# ---------------------------------------------------------------------------
export XDG_CONFIG_HOME="$HOME/.config"

# MACOS FORMULA PREFIX
# ---------------------------------------------------------------------------
if [[ "$OSTYPE" == darwin* ]]; then
	export BREW_PREFIX=/opt/homebrew
fi

# PATH CONSTRUCTION
# ---------------------------------------------------------------------------
# Build PATH with priority order (highest priority first)
# path=(
# 	# User binaries (highest priority)
# 	/usr/local/bin
# 	$HOME/.cargo/bin # Rust
# 	$HOME/.pixi/bin  # Pixi (Python)
#
# 	# Formulae installed directly by mise
# 	$BREW_PREFIX/bin
# 	$BREW_PREFIX/sbin
#
# 	# Runtime environments
# 	$HOME/go/bin     # Go
# 	$HOME/.local/bin # Local scripts
#
# 	# System paths (lowest priority)
# 	$path # Preserve existing system paths
# )

# LIBRARY AND COMPILER PATHS
# ---------------------------------------------------------------------------
# library_path=(
# 	$BREW_PREFIX/lib
# 	/opt/homebrew/opt/libiconv/lib
# 	$BREW_PREFIX/opt/libiconv/lib
# 	$BREW_PREFIX/opt/zlib/lib
# 	$library_path
# )
# export LIBRARY_PATH

# export LDFLAGS="-L/opt/homebrew/opt/libiconv/lib -L$BREW_PREFIX/opt/zlib/lib"
# export CPPFLAGS="-I/opt/homebrew/opt/libiconv/include
# -I$BREW_PREFIX/opt/zlib/include"

# pkg_config_path=(
# 	$BREW_PREFIX/opt/zlib/lib/pkgconfig
# 	$pkg_config_path
# )
# export PKG_CONFIG_PATH

# LANGUAGE-SPECIFIC ENVIRONMENTS
# ---------------------------------------------------------------------------
# Go
export GOPATH="$HOME/go"
export GOBIN="$GOPATH/bin"

# nu / nushell
export TOPIARY_CONFIG_FILE=$XDG_CONFIG_HOME/topiary/languages.ncl
export TOPIARY_LANGUAGE_DIR=$XDG_CONFIG_HOME/topiary/languages

# TOOL CONFIGURATION
# ---------------------------------------------------------------------------
export BAT_THEME="Catppuccin Macchiato"
export CARAPACE_BRIDGES='zsh,bash,clap,click'

# Disable compfix warnings
export ZSH_DISABLE_COMPFIX=true

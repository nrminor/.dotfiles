# env.nu
#
# Environment configuration for Nushell
# Migrated from zsh .zshenv
# This file is loaded before config.nu and login.nu
#
# See https://www.nushell.sh/book/configuration.html

# ============================================================================
# CORE EDITOR CONFIGURATION
# ============================================================================
$env.VISUAL = "hx"
$env.EDITOR = $env.VISUAL
$env.GIT_EDITOR = "hx"

# ============================================================================
# LOCALE SETTINGS
# ============================================================================
$env.LC_ALL = "en_US.UTF-8"
$env.LANG = "en_US.UTF-8"

# ============================================================================
# XDG BASE DIRECTORY
# ============================================================================
$env.XDG_CONFIG_HOME = ($env.HOME | path join ".config")

# ============================================================================
# HOMEBREW CONFIGURATION
# ============================================================================
$env.BREW_PREFIX = "/opt/homebrew"
$env.HOMEBREW_NO_AUTO_UPDATE = "1"

# ============================================================================
# PATH CONSTRUCTION
# ============================================================================
# In nushell, PATH is a list that gets automatically deduplicated
# Priority order: first items have highest priority
# Using 'prepend' adds to the front (highest priority)

$env.PATH = (
  $env.PATH
  | split row (char esep) # Split existing PATH by OS-appropriate separator
  | prepend [
    # User binaries (highest priority)
    "/usr/local/bin"
    ($env.HOME | path join ".cargo" "bin") # Rust
    ($env.HOME | path join ".pixi" "bin") # Pixi (Python)

    # Homebrew
    ($env.BREW_PREFIX | path join "bin")
    ($env.BREW_PREFIX | path join "sbin")

    # Runtime environments
    ($env.HOME | path join ".deno" "bin") # Deno
    ($env.HOME | path join ".bun" "bin") # Bun
    ($env.HOME | path join "go" "bin") # Go
    ($env.HOME | path join ".local" "bin") # Local scripts

    # Nix (if present)
    ($env.HOME | path join ".nix-profile" "bin")
    "/run/current-system/sw/bin"
    "/nix/var/nix/profiles/default/bin"
  ]
  | uniq # Remove duplicates while preserving order
)

# ============================================================================
# LIBRARY AND COMPILER PATHS
# ============================================================================
# These are used by compilers and linkers (must be colon-separated strings)

$env.LIBRARY_PATH = (
  [
    ($env.BREW_PREFIX | path join "lib")
    "/opt/homebrew/opt/libiconv/lib"
    ($env.BREW_PREFIX | path join "opt" "libiconv" "lib")
    ($env.BREW_PREFIX | path join "opt" "zlib" "lib")
  ] | str join ":"
)

$env.LDFLAGS = $"-L/opt/homebrew/opt/libiconv/lib -L($env.BREW_PREFIX)/opt/zlib/lib"

$env.CPPFLAGS = $"-I/opt/homebrew/opt/libiconv/include -I($env.BREW_PREFIX)/opt/zlib/include"

$env.PKG_CONFIG_PATH = (
  [
    ($env.BREW_PREFIX | path join "opt" "zlib" "lib" "pkgconfig")
  ] | str join ":"
)

# ============================================================================
# LANGUAGE-SPECIFIC ENVIRONMENTS
# ============================================================================

# Go
$env.GOPATH = ($env.HOME | path join "go")
$env.GOBIN = ($env.GOPATH | path join "bin")

# Node.js / NVM
$env.NVM_DIR = ($env.HOME | path join ".config" "nvm")

# ============================================================================
# TOOL CONFIGURATION
# ============================================================================
$env.BAT_THEME = "Catppuccin Macchiato"
$env.CARAPACE_BRIDGES = 'zsh,fish,bash,inshellisense,clap'
$env.TOPIARY_CONFIG_FILE = ($env.XDG_CONFIG_HOME | path join "topiary" "languages.ncl")
$env.TOPIARY_LANGUAGE_DIR = ($env.XDG_CONFIG_HOME | path join "topiary" "languages")

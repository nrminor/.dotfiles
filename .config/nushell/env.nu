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
$env.VISUAL = "nvim"
$env.EDITOR = $env.VISUAL
$env.GIT_EDITOR = "nvim"

# ============================================================================
# LOCALE SETTINGS
# ============================================================================
let is_macos = $nu.os-info.name == "macos"

if (($env.LANG? | default "") | is-empty) {
  $env.LANG = if $is_macos { "en_US.UTF-8" } else { "C.UTF-8" }
}

# ============================================================================
# XDG BASE DIRECTORY
# ============================================================================
$env.XDG_CONFIG_HOME = ($env.HOME | path join ".config")

# ============================================================================
# MACOS FORMULA PREFIX
# ============================================================================
if $is_macos {
  $env.BREW_PREFIX = "/opt/homebrew"
}

# ============================================================================
# PATH CONSTRUCTION
# ============================================================================
# In nushell, PATH is a list that gets automatically deduplicated
# Priority order: first items have highest priority
# Using 'prepend' adds to the front (highest priority)

let platform_paths = if $is_macos {
  [
    ($env.BREW_PREFIX | path join "bin")
    ($env.BREW_PREFIX | path join "sbin")
    "/run/current-system/sw/bin"
  ] | where {|path| $path | path exists }
} else {
  []
}

let user_paths = [
  "/usr/local/bin"
  ($env.HOME | path join ".cargo" "bin") # Rust
  ($env.HOME | path join ".pixi" "bin") # Pixi (Python)
  ($env.HOME | path join "go" "bin") # Go
  ($env.HOME | path join ".local" "bin") # Local scripts
]

$env.PATH = (
  $env.PATH
  | split row (char esep) # Split existing PATH by OS-appropriate separator
  | prepend ($user_paths | append $platform_paths)
  | uniq # Remove duplicates while preserving order
)

# ============================================================================
# ENVIRONMENT VARIABLE CONVERSIONS
# ============================================================================
# Define how environment variables should be converted between string and structured types
# This is essential for PATH and other colon-separated variables to work correctly
# with overlays, direnv, and external tools

$env.ENV_CONVERSIONS = {
  PATH: {
    from_string: {|s| $s | split row (char esep) }
    to_string: {|v| $v | str join (char esep) }
  }
}

# ============================================================================
# LANGUAGE-SPECIFIC ENVIRONMENTS
# ============================================================================

# Go
$env.GOPATH = ($env.HOME | path join "go")
$env.GOBIN = ($env.GOPATH | path join "bin")

# ============================================================================
# TOOL CONFIGURATION
# ============================================================================
$env.BAT_THEME = (^nu ($env.XDG_CONFIG_HOME | path join "nushell" "theme.nu") get bat | str trim)
$env.CARAPACE_BRIDGES = 'zsh,fish,bash,inshellisense,clap'
$env.TOPIARY_CONFIG_FILE = ($env.XDG_CONFIG_HOME | path join "topiary" "languages.ncl")
$env.TOPIARY_LANGUAGE_DIR = ($env.XDG_CONFIG_HOME | path join "topiary" "languages")

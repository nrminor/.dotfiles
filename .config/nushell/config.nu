# ============================================================================
# Interactive shell configuration
# For config settings, custom commands, aliases, and tool initialization
# ============================================================================

# INTERACTIVE SHELL INITIALIZATION
# -------------------------------------------------------------------------------------
# Display system info on startup
print ""
fastfetch
print ""

# Nix-Darwin Flake Update Reminder
if (which nix | is-not-empty) {
  let flake_dir = ($env.XDG_CONFIG_HOME | path join "nix-darwin")
  let flake_lock = ($flake_dir | path join "flake.lock")

  if ($flake_lock | path exists) {
    # Follow symlink to get the real file's modification time
    let real_lock = ($flake_lock | path expand)
    let lock_info = (ls -l $real_lock | first)
    let lock_age = ($lock_info.modified | into int) / 1_000_000_000 # Convert to seconds
    let now = (date now | into int) / 1_000_000_000
    let age_days = (($now - $lock_age) / 86400 | math floor)

    if $age_days > 7 {
      print $"💡 Tip: Your nix-darwin flake hasn't been updated in ($age_days) days."
      print $"   Run: sysupdate"
    }
  }
}

# Nushell config settings

$env.config = {
  buffer_editor: "hx"
  show_banner: false
  # edit_mode: "vi"

  hooks: {
    pre_prompt: [
      {||
        # Direnv integration
        if (which direnv | is-empty) {
          return
        }

        let direnv_data = (direnv export json | from json | default {})

        # Handle PATH separately to keep it as a list
        if 'PATH' in $direnv_data {
          $env.PATH = ($direnv_data.PATH | split row (char esep))
          let other_vars = ($direnv_data | reject PATH)
          load-env $other_vars
        } else {
          load-env $direnv_data
        }
      }
    ]
  }
}
# -------------------------------------------------------------------------------------

# EXTERNAL TOOL INITIALIZATION
# -------------------------------------------------------------------------------------
# Only initialize these for interactive shells

# Shell history
source ~/.config/atuin/init.nu

# Fast directory jumping
source ~/.zoxide.nu

# Completions (carapace for external commands)
# This file is managed by dotter and symlinked to the cache directory.
# See .config/nushell/carapace.nu in the dotfiles repo for the customized version
# that properly defers to Nushell's internal completer for built-in commands.
source $"($nu.cache-dir)/carapace.nu"

# Prompt (Starship)
# One-time setup (if needed):
# mkdir ($nu.data-dir | path join "vendor/autoload")
# starship init nu | save -f ($nu.data-dir | path join "vendor/autoload/starship.nu")
# Starship is auto-loaded from vendor/autoload directory
# -------------------------------------------------------------------------------------

# CONDITIONAL TOOL INITIALIZATION
# -------------------------------------------------------------------------------------
# Local overrides
if ("~/.config/nushell/local.nu" | path exists) {
  overlay use "~/.config/nushell/local.nu"
}
# -------------------------------------------------------------------------------------

# Managing Node/NVM with fnm
# -------------------------------------------------------------------------------------
if not (which fnm | is-empty) {
  ^fnm env --log-level=error --json | from json | load-env

  $env.PATH = $env.PATH | prepend ($env.FNM_MULTISHELL_PATH | path join (if $nu.os-info.name == 'windows' { '' } else { 'bin' }))
  $env.config.hooks.env_change.PWD = (
    $env.config.hooks.env_change.PWD? | append {
      condition: {|| ['.nvmrc' '.node-version' 'package.json'] | any {|el| $el | path exists } }
      code: {|| ^fnm use --install-if-missing --silent-if-unchanged --log-level=error }
    }
  )
}
# -------------------------------------------------------------------------------------

# LOAD CUSTOM MODULES
# -------------------------------------------------------------------------------------
# Import custom commands and aliases. We do this at the end of the config because some
# commands and aliases depend on all the above having happened first.
use commands.nu *
use aliases.nu *
# -------------------------------------------------------------------------------------

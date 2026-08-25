# ============================================================================
# Interactive shell configuration
# For config settings, custom commands, aliases, and tool initialization
# ============================================================================

# NUSHELL CONFIG SETTINGS
# -------------------------------------------------------------------------------------
$env.config.buffer_editor = "nvim"
$env.config.show_banner = false

let direnv_hook = {||
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

# EXTERNAL TOOL INITIALIZATION
# -------------------------------------------------------------------------------------
# Only initialize these for interactive shells

# Shell history
source ~/.config/atuin/init.nu

# Tool versions and project environments
use ($nu.default-config-dir | path join mise.nu)

# Fast directory jumping
source ~/.zoxide.nu

# Completions (carapace for external commands)
# This file is managed by mise and symlinked to the cache directory.
# See .config/nushell/carapace.nu in the dotfiles repo for the customized version
# that properly defers to Nushell's internal completer for built-in commands.
source $"($nu.cache-dir)/carapace.nu"

# Let project-local Direnv state override mise's environment updates.
$env.config.hooks.pre_prompt ++= [$direnv_hook]

# Prompt (Starship)
# One-time setup (if needed):
# mkdir ($nu.data-dir | path join "vendor/autoload")
# starship init nu | save -f ($nu.data-dir | path join "vendor/autoload/starship.nu")
# Starship is auto-loaded from vendor/autoload directory
# -------------------------------------------------------------------------------------

# CONDITIONAL TOOL INITIALIZATION
# -------------------------------------------------------------------------------------
# Local overrides
const local_module = if ("~/.config/nushell/local.nu" | path exists) {
  "~/.config/nushell/local.nu"
} else {
  null
}
overlay use $local_module

# ocaml & opam setup
if ("~/.opam" | path exists) {
  # launch the ocaml/opam environment using this trick:
  # https://stackoverflow.com/questions/79760891/how-do-i-use-eval-opam-env-with-nushell
  opam env --shell=powershell | parse "$env:{key} = '{val}'" | transpose -rd | load-env
}
# -------------------------------------------------------------------------------------

# LOAD CUSTOM MODULES
# -------------------------------------------------------------------------------------
# Import custom commands and aliases. We do this at the end of the config because some
# commands and aliases depend on all the above having happened first.
#
# NOTE: We use `overlay use ... as` instead of `use` to work around a nushell bug (#15859)
# where loading modules through managed symlinks corrupts PWD tracking
# for built-in completions.
overlay use commands.nu as commands
overlay use aliases.nu as aliases
overlay use plugins.nu as plugins
# -------------------------------------------------------------------------------------

# INTERACTIVE SHELL INITIALIZATION
# -------------------------------------------------------------------------------------
# Display system info on startup
print ""
fastfetch
print ""

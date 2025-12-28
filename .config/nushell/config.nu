# ============================================================================
# Interactive shell configuration
# For config settings, custom commands, aliases, and tool initialization
# ============================================================================

# CUSTOM COMMANDS MODULE
# -------------------------------------------------------------------------------------
# Import custom commands from commands.nu
use commands.nu *

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

# PYTHON VENV HELPERS
# -------------------------------------------------------------------------------------
# Python virtual environment activation requires overlay commands
# These aliases provide shorter syntax
alias a = overlay use .venv/bin/activate.nu
alias d = overlay hide activate
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

# ALIASES
# -------------------------------------------------------------------------------------
alias b = btop
alias cd = z
alias cat = bat -p --pager never
alias lg = lazygit
alias gu = gitui
alias lj = lazyjj
alias gst = git status
alias curll = curl -L
alias h = hx
alias h. = hx .
alias g. = hx .
alias x = hx
alias z. = zed .
alias o. = ^open . # open the current directory in Finder on MacOS
alias dots = dotter deploy -f -v -y
alias la = ls --all
alias less = less -R
alias cat = bat -p --pager never
alias py = RUST_LOG=warn uvx --with polars --with biopython --with pysam --with polars-bio python # run a uv-managed version of the python repl with some of my go to libs
alias u = utop
alias db = duckdb
alias hq = harlequin
alias tw = tw --theme catppuccin
alias tab = tw
alias ff = fastfetch
alias y = yazi
alias zj = zellij
alias zjs = zellij ls
alias zjls = zellij ls
alias zja = zellij a
alias zjd = zellij d
alias f = fzf
alias fhis = fh
alias fhist = fh
alias fop = fopen
alias fzopen = fopen
alias fzop = fopen
alias fk = fkill
alias fkl = fkill
alias fzgb = fgb
alias fbranches = fgb
alias fzbranches = fgb
alias gitcc = gitcd
alias fzeq = fseq
alias fzrm = frm
# alias z- = z -
alias uvs = uv sync --all-extras
# alias uvv = uv sync --all-extras and source .venv/bin/activate
# alias a = source .venv/bin/activate
alias sq = seqkit
alias mm = minimap2
alias bt = bedtools
alias st = samtools
alias bcf = bcftools
alias nf = nextflow
alias k = clear
# alias zr = source $HOME/.zshenv && source $HOME/.zshrc
# alias zrl = source $HOME/.zshenv && source $HOME/.zshrc
# alias zshrc = source $HOME/.zshenv && source $HOME/.zshrc
if $nu.os-info.name == "macos" {
  alias bfx = z ~/Documents/bioinformatics/
  alias books = z ~/Documents/books/
  alias dholk = z ~/Documents/dholk_experiments/
} else {
  alias bfx = z ~/bioinformatics/
  alias books = z ~/books/
  alias dholk = z ~/dholk_experiments/
}
alias l = ls
alias s = ls
alias ks = ls
alias cld = claude
alias cl = claude
alias oc = opencode
alias code = opencode
alias chtc = ssh nrminor@oconnor-ap.chtc.wisc.edu

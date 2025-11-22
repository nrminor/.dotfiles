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
    # Get the modification time of flake.lock
    let lock_info = (ls -l $flake_lock | first)
    let lock_age = ($lock_info.modified | into int) / 1_000_000_000 # Convert to seconds
    let now = (date now | into int) / 1_000_000_000
    let age_days = (($now - $lock_age) / 86400 | math floor)

    if $age_days > 7 {
      # Resolve the real path by following the flake.nix symlink
      let flake_nix = ($flake_dir | path join "flake.nix")
      let real_flake_dir = if ($flake_nix | path type) == "symlink" {
        let flake_target = (ls -l $flake_nix | first | get target)
        ($flake_target | path dirname)
      } else {
        $flake_dir
      }

      print $"💡 Tip: Your nix-darwin flake hasn't been updated in ($age_days) days."
      print $"   Run: cd ($real_flake_dir) && nix flake update && darwin-rebuild switch --flake ."
    }
  }
}

# Nushell config settings
$env.config = {
  buffer_editor: "hx"
  show_banner: false

  hooks: {
    pre_prompt: [
      {||
        # Direnv integration
        if (which direnv | is-empty) {
          return
        }

        direnv export json | from json | default {} | load-env
        if 'ENV_CONVERSIONS' in $env and 'PATH' in $env.ENV_CONVERSIONS {
          $env.PATH = do $env.ENV_CONVERSIONS.PATH.from_string $env.PATH
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

# Completions (nicer tab completions)
# One-time setup (if needed):
# mkdir $"($nu.cache-dir)"
# carapace _carapace nushell | save --force $"($nu.cache-dir)/carapace.nu"
source $"($nu.cache-dir)/carapace.nu"

# Prompt (Starship)
# One-time setup (if needed):
# mkdir ($nu.data-dir | path join "vendor/autoload")
# starship init nu | save -f ($nu.data-dir | path join "vendor/autoload/starship.nu")
# Starship is auto-loaded from vendor/autoload directory
# -------------------------------------------------------------------------------------

# CONDITIONAL TOOL INITIALIZATION
# -------------------------------------------------------------------------------------
# Load these only if they exist

# OCaml/OPAM initialization
# if ("/Users/nickminor/.opam/opam-init/init.nu" | path exists) {
#   source ~/.opam/opam-init/init.nu
# }

# Local overrides
# if ("~/.config.nu.local" | path exists) {
#   source ~/.config.nu.local
# }

# Bun completions
# if ("~/.bun/_bun.nu" | path exists) {
#   source ~/.bun/_bun.nu
# }
# -------------------------------------------------------------------------------------

# PYTHON VENV HELPERS
# -------------------------------------------------------------------------------------
# Python virtual environment activation requires overlay commands
# These aliases provide shorter syntax
alias a = overlay use .venv/bin/activate.nu
# alias d = deactivate

# NVM Lazy Loading
# -------------------------------------------------------------------------------------
# Note: NVM lazy loading in nushell works differently than in zsh.
# These are placeholder implementations. For full NVM support in nushell,
# consider using nushell's built-in virtual environment or a different Node version manager.

# TODO: Implement NVM lazy loading for nushell
# The zsh approach of function overriding doesn't translate directly to nushell.
# Consider alternatives like:
# - Using a nushell plugin for NVM
# - Direct sourcing of NVM in env.nu
# - Using a different version manager (e.g., fnm which has better nushell support)

# -------------------------------------------------------------------------------------

# ALIASES
# -------------------------------------------------------------------------------------
alias b = btop
alias cd = z
alias cat = bat -p --pager never
alias lg = lazygit
alias lj = lazyjj
alias gst = git status
alias curll = curl -L
alias h = hx
alias h. = hx .
alias x = hx
alias z. = zed .
alias o. = open . # open the current directory in Finder on MacOS
alias dots = dotter deploy -f -v -y
alias la = ls --all
alias less = less -R
alias cat = bat -p --pager never
alias py = RUST_LOG=warn uvx --with polars --with biopython --with pysam --with polars-bio python # run a uv-managed version of the python repl with some of my go to libs
alias u = utop
alias db = duckdb
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
alias gitcd = gitcc
alias fzeq = fseq
alias fzrm = frm
# alias z- = z -
alias uvs = uv sync --all-extras
# alias uvv = uv sync --all-extras and source .venv/bin/activate
# alias a = source .venv/bin/activate
alias d = deactivate
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

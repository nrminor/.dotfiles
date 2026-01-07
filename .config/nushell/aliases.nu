# aliases.nu
#
# Exported aliases for nushell
# Organized by category for maintainability

# ============================================================================
# PYTHON VENV
# ============================================================================
export alias a = overlay use .venv/bin/activate.nu
export alias d = overlay hide activate

# ============================================================================
# NAVIGATION & SHELL
# ============================================================================
export alias cd = z
export alias k = clear
export alias s = ls
export alias ks = ls
export alias la = ls --all
export alias l = la

# Change to bioinformatics directory (OS-aware)
export def --env bfx [] {
  let bfx_dir = if $nu.os-info.name == "macos" {
    $env.HOME | path join "Documents" "bioinformatics"
  } else {
    $env.HOME | path join "bioinformatics"
  }
  z $bfx_dir
}

# Change to books directory (OS-aware)
export def --env books [] {
  let books_dir = if $nu.os-info.name == "macos" {
    $env.HOME | path join "Documents" "books"
  } else {
    $env.HOME | path join "books"
  }
  z $books_dir
}

# ============================================================================
# FILE VIEWING
# ============================================================================
export alias cat = bat -p --pager never
export alias less = less -R

# ============================================================================
# EDITORS
# ============================================================================
export alias h = hx
export alias h. = hx .
export alias g. = hx .
export alias x = hx
export alias z. = zed .

# ============================================================================
# SYSTEM TOOLS
# ============================================================================
export alias b = btop
export alias ff = fastfetch
export alias y = yazi
export alias o. = ^open . # open the current directory in Finder on macOS

# ============================================================================
# GIT & VERSION CONTROL
# ============================================================================
export alias lg = lazygit
export alias gu = gitui
export alias lj = lazyjj
export alias gst = git status
export alias gitcc = gitcd
export alias jja = jj abandon
export alias jjs = jj status
export alias jju = jj undo
export alias jje = jj edit
export alias j = jj
export alias kk = jj
export alias hh = jj

# ============================================================================
# ZELLIJ (Terminal Multiplexer)
# ============================================================================
export alias zj = zellij
export alias zjs = zellij ls
export alias zjls = zellij ls
export alias zja = zellij a
export alias zjd = zellij d

# ============================================================================
# FZF & FUZZY COMMANDS
# ============================================================================
export alias f = fzf
export alias fhis = fh
export alias fhist = fh
export alias fop = fopen
export alias fzopen = fopen
export alias fzop = fopen
export alias fk = fkill
export alias fkl = fkill
export alias fzgb = fgb
export alias fbranches = fgb
export alias fzbranches = fgb
export alias fzeq = fseq
export alias fzrm = frm

# ============================================================================
# DATABASE & DATA TOOLS
# ============================================================================
export alias db = duckdb
export alias hq = harlequin
export alias tw = tw --theme catppuccin
export alias tab = tw

# ============================================================================
# NETWORK & REMOTE
# ============================================================================
export alias curll = curl -L
export alias chtc = ssh nrminor@oconnor-ap.chtc.wisc.edu

# ============================================================================
# PYTHON & UV
# ============================================================================
# Run a uv-managed Python REPL with common data science libraries
export alias py = uvx --with polars --with biopython --with pysam --with polars-bio python3.13

# ============================================================================
# OCAML
# ============================================================================
export alias u = utop

# ============================================================================
# BIOINFORMATICS
# ============================================================================
export alias sq = seqkit
export alias mm = minimap2
export alias bt = bedtools
export alias st = samtools
export alias bcf = bcftools
export alias nf = nextflow

# ============================================================================
# DOTFILES & SYSTEM
# ============================================================================
export alias dots = dotter deploy -f -v -y

# ============================================================================
# AI ASSISTANTS
# ============================================================================
export alias cld = claude
export alias cl = claude
export alias vscode = ^code
export alias code = opencode
export alias oc = opencode
export alias agent = opencode

# ============================================================================
# "CUTE STUFF"
# ============================================================================
export alias noise = ^relax-player

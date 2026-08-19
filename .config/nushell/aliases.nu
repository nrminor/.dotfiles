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
export alias h, = hx .
export alias g. = hx .
export alias x = hx
export alias z. = zed .
export alias vi = nvim
export alias vim = nvim
export alias v = nvim
export alias nv = nvim
export alias nvi = nvim
export alias v. = nvim .
export alias n. = nvim .

# ============================================================================
# SYSTEM TOOLS
# ============================================================================
export alias b = btop-themed
export alias ff = fastfetch
export alias y = yazi-themed
export alias sg = ast-grep

# ============================================================================
# GIT/JUJUTSU & VERSION CONTROL
# ============================================================================
export alias lg = lazygit
export alias lj = lazyjj
export alias mj = majjit
export alias gst = git status
export alias gitcc = gitcd
export alias jja = jj abandon
export alias jjs = jj status
export alias js = jj status
export alias jju = jj undo
export alias jje = jj edit
export alias j = jj
export alias jjj = jj
export alias kk = jj
export alias hh = jj
export alias "jj push" = jj git push
export alias "jj ::@" = jj -r '::@'
export alias "jj@" = jj -r '::@'
export alias "j@" = jj -r '::@'
export alias jjr = jj -r
export alias "jj w up" = jj workspace update-stale
export alias "jj ws up" = jj workspace update-stale
export alias "jj ws upd" = jj workspace update-stale
export alias jjwu = jj workspace update-stale
export alias lu = lumen diff --wrap
export alias lud = lumen diff --wrap
export alias cr = tuicr
export alias "jj watch" = watchexec --quiet --interactive jj
export alias "jjw" = watchexec --quiet --interactive jj

# ============================================================================
# herdr
# ============================================================================
export alias hrdr = herdr
export alias hdr = herdr
export alias hd = herdr
export alias hdr = herdr
export alias herd = herdr

# ============================================================================
# FUZZY-FINDING COMMANDS
# ============================================================================
export alias f = sk
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
export alias fmake = fzf-make
export alias fzmake = fzf-make

# ============================================================================
# DATABASE & DATA TOOLS
# ============================================================================
export alias db = duckdb
export alias tw = tw --theme catppuccin
export alias tab = tw
export alias pl = polars # https://www.nushell.sh/blog/2026-02-28-nushell_v0_111_0.html#type-polars-less-now

# ============================================================================
# NETWORK & REMOTE
# ============================================================================
export alias curll = curl -L

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
# DOTFILES & SYSTEM
# ============================================================================

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

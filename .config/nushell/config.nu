# config.nu
#
# Installed by:
# version = "0.103.0"
#
# This file is used to override default Nushell settings, define
# (or import) custom commands, or run any other startup tasks.
# See https://www.nushell.sh/book/configuration.html
#
# This file is loaded after env.nu and before login.nu
#
# You can open this file in your default editor using:
# config nu
#
# See `help config nu` for more options
#
# You can remove these comments if you want or leave
# them for future reference.

# cut startup printout
echo ""
fastfetch
echo ""

# evironment variables!
$env.config.buffer_editor = "hx"
$env.config.show_banner = false
$env.CARAPACE_BRIDGES = 'zsh,fish,bash,inshellisense,clap'
$env.TOPIARY_CONFIG_FILE = ($env.XDG_CONFIG_HOME | path join topiary languages.ncl)
$env.TOPIARY_LANGUAGE_DIR = ($env.XDG_CONFIG_HOME | path join topiary languages)

# atuin setup
source ~/.config/atuin/init.nu

# zoxide setup
source ~/.zoxide.nu

# one time starship setup
# mkdir ($nu.data-dir | path join "vendor/autoload")
# starship init nu | save -f ($nu.data-dir | path join "vendor/autoload/starship.nu")

# (partially) one time carapace setup
# mkdir $"($nu.cache-dir)"
# carapace _carapace nushell | save --force $"($nu.cache-dir)/carapace.nu"
source $"($nu.cache-dir)/carapace.nu"

# aliases
alias b = btop
alias cd = z
alias cat = bat -pP
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
def ll [path = "."] { ls --all --long $path | sort-by type }
alias la = ls --all
alias less = less -R
alias cat = bat -pP
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

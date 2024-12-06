# EXPORTS
# -------------------------------------------------------------------------------------
export EDITOR=hx
export ZSH="$HOME/.oh-my-zsh"
export JAVA_HOME=$(/usr/libexec/java_home)
export PATH=/usr/local/bin:/Users/nickminor/.pixi/bin:/opt/homebrew/opt/libiconv/bin:$(brew --prefix)/lib:/opt/homebrew/opt/libiconv/lib:$PATH:$HOME/.nextflow-lsp
export LIBRARY_PATH=$LIBRARY_PATH:$(brew --prefix)/lib:$(brew --prefix)/opt/libiconv/lib
export LDFLAGS="-L/opt/homebrew/opt/libiconv/lib"
export CPPFLAGS="-I/opt/homebrew/opt/libiconv/include"
export JULIA_DEPOT_PATH="~/.config/julia"


# ENVIRONMENT VARIABLES
# -------------------------------------------------------------------------------------
ZSH_THEME="robbyrussell"
plugins=(
    colorize
    dotenv
    eza
    fzf
    git
    rsync
)


# CUSTOM FUNCTIONS
# -------------------------------------------------------------------------------------
function yy() {
	local tmp="$(mktemp -t "yazi-cwd.XXXXXX")"
	yazi "$@" --cwd-file="$tmp"
	if cwd="$(cat -- "$tmp")" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
		cd -- "$cwd"
	fi
	rm -f -- "$tmp"
}
function fcd() {
  local dir
  dir=$(find "${1:-.}" -type d 2> /dev/null | fzf --preview='tree -C {} | head -200') && cd "$dir"
}
function fh() {
  history | fzf --height 40% --reverse --tiebreak=index | sed 's/ *[0-9]* *//'
}
function fkill() {
  ps -ef | sed 1d | fzf --height 40% --reverse --preview 'echo {}' | awk '{print $2}' | xargs -r kill -9
}
function fgb() {
  git branch --all | grep -v HEAD | sed 's/remotes\/origin\///' | sort -u | fzf --height 40% --reverse | xargs git checkout
}
function fco() {
  git log --pretty=oneline --abbrev-commit | fzf --height 40% --reverse | cut -d ' ' -f 1 | xargs git checkout
}


# SOURCES
# -------------------------------------------------------------------------------------
. "$HOME/.cargo/env"
# source $ZSH/oh-my-zsh.sh # loading this is quite slow
eval "$(zoxide init zsh)"
source <(fzf --zsh)


# ALIASES
# -------------------------------------------------------------------------------------
alias b="btop"
alias cd="z"
alias cat="bat -pP"
alias lg="lazygit"
alias gst="git status"
alias curll='curl -L' # curl but follow redirects
alias h="hx"
alias h.="hx ."
alias z.="zed ."
alias dots="dotter deploy -f -v -y"
alias bfx="z ~/Documents/bioinformatics"
alias ls="eza -1a"
alias ll="eza -la --group-directories-first --icons"
alias cat="bat -pP"
alias py="python3"
alias jl="julia"
alias db="duckdb"
alias ff="fastfetch"
alias y="yazi"
alias zj="zellij"
alias zjs="zellij ls"
alias zjls="zellij ls"
alias zja="zellij a"
alias zjd="zellij d"
alias f="fzf"
alias fzo='hx $(fzf -m --preview="bat -P {} --color=always")' # fuzzy-find then open multiple files in helix
alias fh=fh # fuzzy-find through command history
alias fkill=fkill # fuzzy-find through processes to kill one
alias fgb=fgb # fuzzy-find through git branches
alias fco=fco # fuzzy-find through git commits
alias uvv='uv sync && source .venv/bin/activate'
alias uvs='uv sync'
alias d='deactivate'
alias sq='seqkit'
alias mm='minimap2'
alias bt='bedtools'
alias st='samtools'
alias bcf='bcftools'
alias nf='nextflow'



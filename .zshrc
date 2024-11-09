# EXPORTS
# -------------------------------------------------------------------------------------
export ZSH="$HOME/.oh-my-zsh"
path=('$HOME/.juliaup/bin' $path)
export JAVA_HOME=$(/usr/libexec/java_home)
export PATH=$PATH:/Users/nickminor/.pixi/bin


# ENVIRONMENT VARIABLES
# -------------------------------------------------------------------------------------
ZSH_THEME="robbyrussell"


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


# OTHER
# -------------------------------------------------------------------------------------
. "$HOME/.cargo/env"
# source $ZSH/oh-my-zsh.sh
plugins=(
    colorize
    dotenv
    eza
    fzf
    git
    rsync
)
eval "$(zoxide init zsh)"


# ALIASES
# -------------------------------------------------------------------------------------
alias b="btop"
alias cd="z"
alias cat="bat -pP"
alias lg="lazygit"
alias gst="git status"
alias h="hx"
alias h.="hx ."
alias z.="zed ."
alias dots="dotter deploy -f -v -y"
alias bfx="z ~/Documents/bioinformatics"
alias ls="eza -1a"
alias cat="bat -pP"
alias py="python3"
alias jl="julia"
alias db="duckdb"
alias ff="fastfetch"
alias y="yazi"


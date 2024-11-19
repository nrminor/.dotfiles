# EXPORTS
# -------------------------------------------------------------------------------------
export EDITOR=hx
export ZSH="$HOME/.oh-my-zsh"
export JAVA_HOME=$(/usr/libexec/java_home)
export PATH=/usr/local/bin:/Users/nickminor/.pixi/bin:/opt/homebrew/opt/libiconv/bin:$(brew --prefix)/lib:/opt/homebrew/opt/libiconv/lib:$PATH
export LIBRARY_PATH=$LIBRARY_PATH:$(brew --prefix)/lib:$(brew --prefix)/opt/libiconv/lib
export LDFLAGS="-L/opt/homebrew/opt/libiconv/lib"
export CPPFLAGS="-I/opt/homebrew/opt/libiconv/include"
export JULIA_DEPOT_PATH="~/.config/julia"


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


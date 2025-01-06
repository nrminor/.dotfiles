# ENVIRONMENT VARIABLES
# -------------------------------------------------------------------------------------
export PATH=/usr/local/bin:/Users/nickminor/.pixi/bin:/opt/homebrew/opt/libiconv/bin:$(brew --prefix)/lib:/opt/homebrew/opt/libiconv/lib:$PATH:$HOME/.moon/bin
export LIBRARY_PATH=$LIBRARY_PATH:$(brew --prefix)/lib:$(brew --prefix)/opt/libiconv/lib
export LDFLAGS="-L/opt/homebrew/opt/libiconv/lib"
export CPPFLAGS="-I/opt/homebrew/opt/libiconv/include"
export XDG_CONFIG_HOME="$HOME/.config"
export CARAPACE_BRIDGES='zsh,fish,bash,inshellisense'
# -------------------------------------------------------------------------------------


# CUSTOM FUNCTIONS
# -------------------------------------------------------------------------------------
function mkcd() {
  mkdir -p "$1" && cd "$1"
}

function gitcc() {
  if [[ -z "$1" ]]; then
    echo "Usage: ghcc <Git repository URL>"
    return 1
  fi

  local url="$1"
  # Extract the last path component, e.g. "myrepo.git" or "myrepo"
  local base
  base=$(basename "$url")

  # Remove a trailing ".git" if present
  local repo
  repo=${base%.git}

  # Clone and change into the repo directory if successful
  git clone "$url" && cd "$repo"
}

function trash() {
  if [[ "$(uname -s)" == "Darwin" ]]; then
    # On macOS, move to user's Trash folder
    mv "$@" "$HOME/.Trash/"
  else
    # On Linux (or other OS), permanently remove
    rm "$@"
  fi
}

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
  dir=$(find "${1:-.}" -type d 2> /dev/null | fzf --height 70% --preview='tree -C {} | head -200') && cd "$dir"
}

function fopen() {
  local items
  items=$(find "${1:-.}" 2> /dev/null | fzf -m --height 70% --reverse \
    --preview='[ -d {} ] && tree -C {} || bat -pP {} --color=always')
  if [[ -n "$items" ]]; then
    while IFS= read -r line; do
      open "$line"
    done <<< "$items"
  fi
}

function fh() {
  history | fzf --height 70% --reverse --tiebreak=index | sed 's/ *[0-9]* *//'
}

function fkill() {
  ps -ef | sed 1d | fzf -m --height 70% --reverse --preview 'echo {}' | awk '{print $2}' | xargs -r kill -9
}

function fgb() {
  git branch --all | grep -v HEAD | sed 's/remotes\/origin\///' | sort -u | fzf --height 70% --reverse | xargs git checkout
}

function fco() {
  git log --pretty=oneline --abbrev-commit | fzf --height 70% --reverse | cut -d ' ' -f 1 | xargs git checkout
}

function fzo() {
  local files
  files=$(find "${1:-.}" 2> /dev/null | fzf --height 70% -m \
    --preview='[ -d {} ] && tree -C {} || bat -pP {} --color=always') || return

  # If no selection was made, return with exit code 0
  [[ -z "$files" ]] && return 0

  hx $files
}

function hxs() {
	RG_PREFIX="rg -i --files-with-matches"
	local files
	files="$(
		FZF_DEFAULT_COMMAND_DEFAULT_COMMAND="$RG_PREFIX '$1'" \
			fzf --multi 3 --print0 --sort --preview="[[ ! -z {} ]] && rg --pretty --ignore-case --context 5 {q} {}" \
				--phony -i -q "$1" \
				--bind "change:reload:$RG_PREFIX {q}" \
				--preview-window="70%:wrap" \
				--bind 'ctrl-a:select-all'
	)"
	[[ "$files" ]] && hx --vsplit $(echo $files | tr \\0 " ")
}

function fseq() {

  local infile="$1"
  local outfile="$2"

  if [[ -z "$infile" ]]; then
    echo "Usage: fseq <file.fasta|file.fastq> [output_file]"
    return 1
  fi

  # Get the list of IDs and allow fuzzy selection of multiple IDs
  local ids
  ids=$(seqkit seq -i -n "$infile" | fzf --height 70% --multi \
    --preview="seqkit grep -p {} '$infile' | bat --wrap=auto --style=numbers,grid --color=always --theme=ansi") || return

  # If no IDs were selected, just return
  if [[ -z "$ids" ]]; then
    return 0
  fi

  # Create a comma-delimited list of chosen IDs
  local comma_list
  comma_list=$(echo "$ids" | paste -sd ',' -)

  # If outfile is given, write to it, otherwise print to stdout
  if [[ -n "$outfile" ]]; then
    seqkit grep -p "$comma_list" "$infile" -o "$outfile"
  else
    seqkit grep -p "$comma_list" "$infile"
  fi
  
}

function frm() {
  # Use find to list files (and directories if you want) from the given path or current dir
  # Adjust find arguments to suit your needs (e.g., just files, recursive, etc.)
  local files
  files=$(find "${1:-.}" -mindepth 1 -maxdepth 1 2>/dev/null | fzf --multi --height 75% \
    --preview='[ -d {} ] && tree -C {} || bat -pP {} --color=always') || return

  # If no selection was made, exit
  [[ -z "$files" ]] && return 0

  # Move each selected file to the trash
  while IFS= read -r file; do
    trash "$file"
  done <<< "$files"
}
# -------------------------------------------------------------------------------------


# SOURCES AND EVALS
# -------------------------------------------------------------------------------------
. "$HOME/.cargo/env"
eval "$(zoxide init zsh)"
source <(fzf --zsh)
eval "$(starship init zsh)"
eval "$(atuin init zsh)"
autoload -Uz compinit
compinit
zstyle ':completion:*' format $'\e[2;37mCompleting %d\e[m'
source <(carapace _carapace)
eval $(opam env)
# -------------------------------------------------------------------------------------


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
alias o.="open ." # open the current directory in Finder on MacOS
alias dots="dotter deploy -f -v -y"
alias ls="eza -1a"
alias ll="eza -la --group-directories-first --icons"
alias cat="bat -pP"
alias py="python3"
alias db="duckdb"
alias ff="fastfetch"
alias y="yazi"
alias zj="zellij"
alias zjs="zellij ls"
alias zjls="zellij ls"
alias zja="zellij a"
alias zjd="zellij d"
alias f="fzf"
alias fzo=fzo # fuzzy-find then open multiple files in helix
alias fh=fh # fuzzy-find through command history
alias fhis=fh
alias fhist=fh
alias fopen=fopen # fuzzy find files and directories, select them, and open them with MacOS's `open`
alias fop=fopen
alias fzopen=fopen
alias fzop=fopen
alias fkill=fkill # fuzzy-find through processes to kill one
alias fk=fkill
alias fkl=fkill
alias fgb=fgb # fuzzy-find through git branches
alias fzgb=fgb
alias fbranches=fgb
alias fzbranches=fgb
alias fco=fco # fuzzy-find through git commits
alias mkcd=mkcd # make a directory and change into it
alias gitcc=gitcc # git clone a repository and cd into it
alias hxs=hxs
alias fseq=fseq # query a FASTA or FASTQ for specific IDs
alias fzeq=fseq
alias frm=frm # fuzzy find and move files into trash
alias fzrm=frm
alias z-="z -"
alias uvv='uv sync && source .venv/bin/activate'
alias uvs='uv sync'
alias a='source .venv/bin/activate'
alias d='deactivate'
alias sq='seqkit'
alias mm='minimap2'
alias bt='bedtools'
alias st='samtools'
alias bcf='bcftools'
alias nf='nextflow'
alias k="clear"
alias zr="source $HOME/.zshrc"
alias zrl="source $HOME/.zshrc"
alias zshrc="source $HOME/.zshrc"
if [[ "$(uname -s)" == "Darwin" ]]; then
  alias bfx="z $HOME/Documents/bioinformatics"
  alias books="z $HOME/Documents/books"
  alias dholk="z $HOME/Documents/dholk_experiments"
else
  alias bfx="z $HOME/bioinformatics"
  alias books="z $HOME/books"
  alias dholk="z $HOME/dholk_experiments"

fi
# -------------------------------------------------------------------------------------


# ENVIRONMENT VARIABLES
# -------------------------------------------------------------------------------------
export PATH=/usr/local/bin:/Users/nickminor/.pixi/bin:/opt/homebrew/opt/libiconv/bin:$(brew --prefix)/lib:/opt/homebrew/opt/libiconv/lib:$PATH:$HOME/.nextflow-lsp
export LIBRARY_PATH=$LIBRARY_PATH:$(brew --prefix)/lib:$(brew --prefix)/opt/libiconv/lib
export LDFLAGS="-L/opt/homebrew/opt/libiconv/lib"
export CPPFLAGS="-I/opt/homebrew/opt/libiconv/include"
export XDG_CONFIG_HOME="$HOME/.config"
export JAVA_HOME=$(/usr/libexec/java_home)
# -------------------------------------------------------------------------------------


# CUSTOM FUNCTIONS
# -------------------------------------------------------------------------------------
function mkcd() {
  mkdir -p "$1" && cd "$1"
}

function trash() {
  mv "$1" $HOME/.Trash/
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
  dir=$(find "${1:-.}" -type d 2> /dev/null | fzf --height 50% --preview='tree -C {} | head -200') && cd "$dir"
}

function fopen() {
  local items
  items=$(find "${1:-.}" 2> /dev/null | fzf -m --height 50% --reverse \
    --preview='[ -d {} ] && tree -C {} || bat -pP {} --color=always')
  if [[ -n "$items" ]]; then
    while IFS= read -r line; do
      open "$line"
    done <<< "$items"
  fi
}

function fh() {
  history | fzf --height 50% --reverse --tiebreak=index | sed 's/ *[0-9]* *//'
}

function fkill() {
  ps -ef | sed 1d | fzf -m --height 50% --reverse --preview 'echo {}' | awk '{print $2}' | xargs -r kill -9
}

function fgb() {
  git branch --all | grep -v HEAD | sed 's/remotes\/origin\///' | sort -u | fzf --height 50% --reverse | xargs git checkout
}

function fco() {
  git log --pretty=oneline --abbrev-commit | fzf --height 50% --reverse | cut -d ' ' -f 1 | xargs git checkout
}

function fzo() {
  local files
  files=$(find "${1:-.}" 2> /dev/null | fzf --height 50% -m \
    --preview='[ -d {} ] && tree -C {} || bat -pP {} --color=always') || return

  # If no selection was made, return with exit code 0
  [[ -z "$files" ]] && return 0

  hx $files
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
  ids=$(seqkit seq -i -n "$infile" | fzf --height 50% --multi \
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
# source $ZSH/oh-my-zsh.sh # loading this is quite slow
eval "$(zoxide init zsh)"
source <(fzf --zsh)
eval "$(starship init zsh)"
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
alias bfx="z ~/Documents/bioinformatics"
alias books="z ~/Documents/books"
alias dholk="z ~/Documents/dholk_experiments"
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
alias fseq=fseq # query a FASTA or FASTQ for specific IDs
alias fzeq=fseq
alias frm=frm # fuzzy find and move files into trash
alias fzrm=frm
alias z-="z -"
alias uvv='uv sync && source .venv/bin/activate'
alias uvs='uv sync'
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
# -------------------------------------------------------------------------------------


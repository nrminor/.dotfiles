# ============================================================================
# Interactive shell configuration
# For aliases, functions, completions, and prompt initialization
# ============================================================================

# INTERACTIVE SHELL INITIALIZATION
# -------------------------------------------------------------------------------------
# These only run in interactive shells, not scripts

# Initialize completion system (currently commented out because nix already runs it through /etc/zshrc)
# autoload -Uz compinit
# zcompdump="${HOME}/.zcompdump"

# if [[ -f "$zcompdump" ]]; then
# 	# File exists, check age
# 	cache_age_seconds=$(($(date +%s) - $(stat -f %m "$zcompdump" 2>/dev/null ||
# 		echo 0)))
# 	if ((cache_age_seconds > 86400)); then
# 		# Cache is old (>24 hours), rebuild
# 		compinit
# 	else
# 		# Cache is fresh, use it
# 		compinit -C
# 	fi
# else
# 	# No cache file, create it
# 	compinit
# fi
# -------------------------------------------------------------------------------------

# EXTERNAL TOOL INITIALIZATION (the slow stuff)
# -------------------------------------------------------------------------------------
# Only initialize these for interactive shells

# nicer tab completions
zstyle ':completion:*' format $'\e[2;37mCompleting %d\e[m'
source <(carapace _carapace zsh)

# Fast directory jumping
eval "$(zoxide init zsh)"

# Fuzzy finder integration
source <(fzf --zsh)

# Prompt
eval "$(starship init zsh)"

# Shell history
eval "$(atuin init zsh)"
# -------------------------------------------------------------------------------------

# CONDITIONAL TOOL INITIALIZATION
# -------------------------------------------------------------------------------------
# Load these only if they exist

# OCaml
[[ -r $HOME/.opam/opam-init/init.zsh ]] && source "$HOME/.opam/opam-init/init.
zsh" >/dev/null 2>/dev/null

# Local overrides
[[ -f "$HOME/.zshrc.local" ]] && source "$HOME/.zshrc.local"

# Local environment scripts
[ -f "$HOME/.local/bin/env" ] && source "$HOME/.local/bin/env"

# Bun completions
[ -s "$HOME/.bun/_bun" ] && source "$HOME/.bun/_bun"

# NVM (Node Version Manager) - lazy-loads when first called for interactive shells
nvm() {
	unset -f nvm node npm npx
	[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
	nvm "$@"
}
node() {
	unset -f nvm node npm npx
	[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
	node "$@"
}
npm() {
	unset -f nvm node npm npx
	[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
	npm "$@"
}
npx() {
	unset -f nvm node npm npx
	[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
	npx "$@"
}
eval "$(fnm env --use-on-cd --shell zsh)"
# -------------------------------------------------------------------------------------

# CUSTOM FUNCTIONS
# -------------------------------------------------------------------------------------
mkcd() {
	mkdir -p "$1" && cd "$1" || exit
}

gitcc() {
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
	git clone "$url" && cd "$repo" || exit
}

trash() {
	if [[ "$(uname -s)" == "Darwin" ]]; then
		# On macOS, move to user's Trash folder
		mv "$@" "$HOME/.Trash/"
	else
		# On Linux (or other OS), permanently remove
		rm "$@"
	fi
}

ycd() {
	local tmp="$(mktemp -t "yazi-cwd.XXXXXX")"
	yazi "$@" --cwd-file="$tmp"
	if cwd="$(cat -- "$tmp")" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
		cd -- "$cwd" || exit
	fi
	rm -f -- "$tmp"
}

fcd() {
	local dir
	dir=$(find "${1:-.}" -type d 2>/dev/null | fzf --height 70% --preview='tree -C {} | head -200') && cd "$dir" || exit
}

fopen() {
	local items
	items=$(find "${1:-.}" 2>/dev/null | fzf -m --height 70% --reverse \
		--preview='[ -d {} ] && tree -C {} || bat -p --paging=never {} --color=always')
	if [[ -n "$items" ]]; then
		while IFS= read -r line; do
			open "$line"
		done <<<"$items"
	fi
}

fh() {
	history | fzf --height 70% --reverse --tiebreak=index | sed 's/ *[0-9]* *//'
}

fkill() {
	ps -ef | sed 1d | fzf -m --height 70% --reverse --preview 'echo {}' | awk '{print $2}' | xargs -r kill -9
}

fgb() {
	git branch --all | grep -v HEAD | sed 's/remotes\/origin\///' | sort -u | fzf --height 70% --reverse | xargs git checkout
}

fco() {
	git log --pretty=oneline --abbrev-commit | fzf --height 70% --reverse | cut -d ' ' -f 1 | xargs git checkout
}

fzo() {
	local files
	files=$(find "${1:-.}" 2>/dev/null | fzf --height 70% -m \
		--preview='[ -d {} ] && tree -C {} || bat -p --paging=never {} --color=always') || return

	# If no selection was made, return with exit code 0
	[[ -z "$files" ]] && return 0

	hx $files
}

hxs() {
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

fseq() {

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

frm() {
	# Use find to list files (and directories if you want) from the given path or current dir
	# Adjust find arguments to suit your needs (e.g., just files, recursive, etc.)
	local files
	files=$(find "${1:-.}" -mindepth 1 -maxdepth 1 2>/dev/null | fzf --multi --height 75% \
		--preview='[ -d {} ] && tree -C {} || bat -p --paging=never {} --color=always') || return

	# If no selection was made, exit
	[[ -z "$files" ]] && return 0

	# Move each selected file to the trash
	while IFS= read -r file; do
		trash "$file"
	done <<<"$files"
}

bam2fq() {
	find . -maxdepth 1 -type f -name '*.bam' -print0 |
		parallel -0 -j 6 '
      echo "Converting {}..."
      samtools fastq {} | gzip -c > {.}.fastq.gz
      echo "Finished {}"
    '
}

seqstats() {
	local dir="."
	local output_file=""

	# Parse arguments
	while [[ $# -gt 0 ]]; do
		case "$1" in
		-o)
			output_file="$2"
			shift 2
			;;
		*)
			if [[ "$1" != -* ]]; then
				dir="$1"
				shift
			else
				echo "Unknown option: $1" >&2
				return 1
			fi
			;;
		esac
	done

	# Check if directory exists
	if [ ! -d "$dir" ]; then
		echo "Error: Directory '$dir' does not exist" >&2
		return 1
	fi

	shopt -s extglob nullglob
	local files=()
	for f in "$dir"/*.+(fa|fasta|fq|fastq)?(.gz); do
		[[ -e "$f" ]] && files+=("$f")
	done

	# If there are no matching files, let the user know and exit
	if (($#files == 0)); then
		echo "No FASTA/FASTQ files found in '$dir'." >&2
		return 1
	fi

	if [ -n "$output_file" ]; then
		seqkit stats -b -a -T -j 1 "${files[@]}" >"$output_file"
	else
		seqkit stats -b -a -T -j 1 "${files[@]}" | csvtk pretty -t --style 3line
	fi
}

allow_ghostty() {
	local location="$1"
	if [[ -z "$location" ]]; then
		echo "Usage: allow_ghostty USERNAME@ADDRESS"
		return 1
	fi

	infocmp -x | ssh $location -- tic -x -
}

mo() {
	local file="${1:-scratch.py}"
	local user_provided=false

	# Detect if user passed a path
	if [[ -n "$1" ]]; then
		user_provided=true
	fi

	# Run marimo in the foreground (blocking)
	RUST_LOG=warn uvx \
		--with polars \
		--with biopython \
		--with pysam \
		--with polars-bio \
		--with altair \
		--with plotnine \
		marimo edit "$file"

	# Only prompt for cleanup if using default scratch file
	if [[ "$user_provided" == false ]]; then
		print -n "Keep $file? [y/N]: "
		read -r keep

		case "$keep" in
		[yY][eE][sS] | [yY])
			print -n "Rename $file? (leave empty to keep name): "
			read -r newname
			if [[ -n "$newname" ]]; then
				mv -- "$file" "$newname"
				echo "Saved as $newname"
			else
				echo "Keeping as $file"
			fi
			;;
		*)
			rm -f -- "$file"
			echo "Deleted $file"
			;;
		esac
	fi
}
# -------------------------------------------------------------------------------------

# ALIASES
# -------------------------------------------------------------------------------------
alias b="btop"
alias cd="z"
alias cat="bat -p --paging=never"
alias lg="lazygit"
alias lj="lazyjj"
alias gst="git status"
alias curll='curl -L' # curl but follow redirects
alias h="hx"
alias h.="hx ."
alias x="hx"
alias z.="zed ."
alias o.="open ." # open the current directory in Finder on MacOS
alias dots="dotter deploy -f -v -y"
alias ls="eza -1a --group-directories-first --color=always"
alias ll="eza -la --group-directories-first --icons --color=always"
alias la="ll"
alias less="less -R"
alias py="RUST_LOG=warn uvx --with polars --with biopython --with pysam --with polars-bio python" # run a uv-managed version of the python repl with some of my go to libs
if [ -x "$(which radian)" ]; then
	alias r="radian"
	alias R="radian"
fi
alias u="utop"
alias db="duckdb"
alias tw="tw --theme catppuccin"
alias tab="tw"
alias ff="fastfetch"
alias y="yazi"
alias zj="zellij"
alias zjs="zellij ls"
alias zjls="zellij ls"
alias zja="zellij a"
alias zjd="zellij d"
alias f="fzf"
alias fhis=fh
alias fhist=fh
alias fop=fopen
alias fzopen=fopen
alias fzop=fopen
alias fk=fkill
alias fkl=fkill
alias fzgb=fgb
alias fbranches=fgb
alias fzbranches=fgb
alias fzmake="fzf-make"
alias gitcd=gitcc
alias fzeq=fseq
alias fzrm=frm
alias z-="z -"
alias uvv='uv sync --all-extras && source .venv/bin/activate'
alias uvs='uv sync --all-extras'
alias a='source .venv/bin/activate'
alias d='deactivate'
alias sq='seqkit'
alias mm='minimap2'
alias bt='bedtools'
alias st='samtools'
alias bcf='bcftools'
alias nf='nextflow'
alias k="clear"
alias zr="source $HOME/.zshenv && source $HOME/.zshrc"
alias zrl="source $HOME/.zshenv && source $HOME/.zshrc"
alias zshrc="source $HOME/.zshenv && source $HOME/.zshrc"
if [[ "$(uname -s)" == "Darwin" ]]; then
	alias bfx="z $HOME/Documents/bioinformatics"
	alias books="z $HOME/Documents/books"
	alias dholk="z $HOME/Documents/dholk_experiments"
else
	alias bfx="z $HOME/bioinformatics"
	alias books="z $HOME/books"
	alias dholk="z $HOME/dholk_experiments"

fi
alias l="ls"
alias s="ls"
alias ks="ls"
alias cld="claude"
alias cl="claude"
alias oc="opencode"
alias code="opencode"
# -------------------------------------------------------------------------------------

# bun completions
[ -s "/Users/nickminor/.bun/_bun" ] && source "/Users/nickminor/.bun/_bun"

# NVD shell integration
eval "$(nvd setup shell-hook)"

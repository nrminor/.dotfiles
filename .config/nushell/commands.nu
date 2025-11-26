# commands.nu
#
# Custom commands and functions for nushell
# Organized by category: directory navigation, file operations, editor integration,
# git workflow, process management, bioinformatics tools, and development tools

# ============================================================================
# DIRECTORY NAVIGATION
# ============================================================================

# Create a directory and change into it
#
# Creates parent directories as needed, then changes to the new directory.
#
# Examples:
#   > mkcd foo                      # Create and cd into ./foo
#   > mkcd ~/projects/new-project   # Create with full path
#   > mkcd foo/bar/baz              # Create nested directories
export def --env mkcd [
  dir: string # The directory path to create
] {
  mkdir ($dir | path expand)
  cd $dir
}

# ============================================================================
# PYTHON VIRTUAL ENVIRONMENTS
# ============================================================================

# Note: Python venv activation in nushell requires running the overlay command directly:
#   overlay use .venv/bin/activate.nu    # to activate (aliased to 'a')
#   overlay hide activate                 # to deactivate (aliased to 'd')

# Sync dependencies with uv
#
# Examples:
#   > uvs                    # Sync all extras
export def uvs [] {
  ^uv sync --all-extras
}

# Clone a git repository and cd into it
#
# Opens yazi and changes to the directory you navigate to when you exit.
# Passes all arguments through to yazi.
#
# Examples:
#   > ycd              # Launch yazi in current directory
#   > ycd ~/Documents  # Launch yazi in specific directory
#   > ycd --help       # Pass flags to yazi
export def --env ycd [
  ...args: string # Arguments to pass to yazi
] {
  let tmp = (^mktemp -t "yazi-cwd.XXXXXX" | str trim)
  ^yazi ...$args --cwd-file $tmp
  let cwd = (open $tmp | str trim)
  if ($cwd | is-not-empty) and ($cwd != $env.PWD) {
    cd $cwd
  }
  rm -f $tmp
}

# Fuzzy find and cd into a directory
#
# Uses fd to find directories and fzf for interactive selection with tree preview.
# By default, respects .gitignore and ignores common directories like .git and node_modules.
# Use --no-ignore to include all directories.
#
# Examples:
#   > fcd                    # Search from current directory
#   > fcd ~/projects         # Search from specific directory
#   > fcd --no-ignore        # Include ignored directories
export def --env fcd [
  path: string = "." # Starting path to search from
  --no-ignore # Include directories that are normally ignored (.git, node_modules, etc)
] {
  let dir = if $no_ignore {
    ^fd --type d --no-ignore . $path
    | lines
    | to text
    | ^fzf --height 70% --preview='tree -C {} | head -200'
    | str trim
  } else {
    ^fd --type d . $path
    | lines
    | to text
    | ^fzf --height 70% --preview='tree -C {} | head -200'
    | str trim
  }

  if ($dir | is-not-empty) { cd $dir }
}

# List files in long format, sorted by type
#
# Shows detailed file information including permissions, size, and modification time.
# Directories are listed before files.
#
# Examples:
#   > ll                # List current directory
#   > ll ~/Documents    # List specific directory
export def ll [
  path: string = "." # Directory path to list
] {
  ls --all --long $path | sort-by type
}

# ============================================================================
# FILE OPERATIONS
# ============================================================================

# Move files to trash (macOS) or permanently delete (Linux)
#
# On macOS, moves files to ~/.Trash for safe recovery (in parallel!).
# On other systems, permanently deletes files.
# Use --force to suppress errors if files don't exist.
#
# Examples:
#   > trash file.txt                    # Trash a single file
#   > trash file1.txt file2.txt         # Trash multiple files
#   > trash *.log                       # Trash files matching pattern
#   > trash --force old-file.txt        # Don't error if file doesn't exist
export def trash [
  ...files: string # Files or directories to trash
  --force (-f) # Suppress errors if files don't exist
] {
  if $nu.os-info.name == "macos" {
    $files | par-each {|file|
      if $force {
        try { mv $file ($env.HOME | path join ".Trash") }
      } else {
        mv $file ($env.HOME | path join ".Trash")
      }
    } | ignore
  } else {
    if $force {
      rm --force ...$files
    } else {
      rm ...$files
    }
  }
}

# Fuzzy find and open files or directories
#
# Uses fd to find files and fzf for interactive multi-selection.
# Shows tree preview for directories and bat preview for files.
# Opens selected items with the system default application (in parallel!).
#
# Examples:
#   > fopen                  # Search from current directory
#   > fopen ~/Documents      # Search from specific directory
export def fopen [
  path: string = "." # Starting path to search from
] {
  let items = (
    ^fd . $path
    | lines
    | to text
    | ^fzf -m --height 70% --reverse --preview='[ -d {} ] && tree -C {} || bat -p --paging=never {} --color=always'
    | lines
  )

  if ($items | is-not-empty) {
    $items | par-each {|item|
      ^open $item
    } | ignore
  }
}

# Fuzzy find and remove files (move to trash)
#
# Uses fd to find files in the current directory (non-recursive) and fzf for interactive multi-selection.
# Selected items are moved to trash (safe on macOS, permanent delete on Linux).
#
# Examples:
#   > frm                  # Remove from current directory
#   > frm ~/Downloads      # Remove from specific directory
export def frm [
  path: string = "." # Directory to search in
] {
  let items = (
    ^fd --max-depth 1 . $path
    | lines
    | to text
    | ^fzf --multi --height 75% --preview='[ -d {} ] && tree -C {} || bat -p --paging=never {} --color=always'
    | str trim
    | split row "\n"
    | where $it != ""
  )

  if ($items | is-not-empty) {
    $items | each {|item|
      trash $item
    } | ignore
  }
}

# ============================================================================
# EDITOR INTEGRATION
# ============================================================================

# Fuzzy find and open files in Helix editor
#
# Uses fd to find files and fzf for interactive multi-selection.
# Opens all selected files in Helix, with directories opening as project roots.
#
# Examples:
#   > fzo                  # Search from current directory
#   > fzo ~/projects       # Search from specific directory
export def fzo [
  path: string = "." # Starting path to search from
] {
  let files = (
    ^fd . $path
    | lines
    | to text
    | ^fzf --height 70% -m --preview='[ -d {} ] && tree -C {} || bat -p --paging=never {} --color=always'
    | str trim
    | split row "\n"
    | where $it != ""
  )

  if ($files | is-not-empty) {
    hx ...$files
  }
}

# Interactive ripgrep search and open in Helix
#
# Searches file contents using ripgrep with live-updating results.
# Preview shows matching lines with context. Opens selected files in Helix with vertical splits.
#
# Examples:
#   > hxs                    # Interactive search (type query in fzf)
#   > hxs "function"         # Search for "function"
export def hxs [
  query: string = "" # Initial search query (optional)
] {
  let rg_prefix = "rg -i --files-with-matches"

  let files = (
    ^fzf
    --disabled # Start with search disabled (phony mode)
    --ansi
    --multi
    --print0
    --query $query
    --bind $"change:reload:($rg_prefix) {q} || true"
    --preview "rg --pretty --ignore-case --context 5 {q} {}"
    --preview-window "70%:wrap"
    --bind "ctrl-a:select-all"
    --prompt "Search: "
    | str trim
    | split row (char -i 0) # Split by null character
    | where $it != ""
  )

  if ($files | is-not-empty) {
    hx --vsplit ...$files
  }
}

# Open modified git files in Helix
#
# Opens git-modified files as buffers in Helix.
# By default shows unstaged changes only.
#
# Examples:
#   > hg                     # Open unstaged modified files
#   > hg --staged            # Open all changes (staged + unstaged)
#   > hg --untracked         # Open all changes including untracked files
export def hg [
  --staged (-s)     # Include staged files (shows all changes vs HEAD)
  --untracked (-u)  # Include untracked files
] {
  let files = if $untracked {
    # Get all changes including untracked
    git status --short | lines | parse "{status} {file}" | get file
  } else if $staged {
    # Get staged and unstaged changes (all changes vs HEAD)
    git diff --name-only HEAD | lines
  } else {
    # Just unstaged changes
    git diff --name-only | lines
  }

  if ($files | is-not-empty) {
    hx ...$files
  } else {
    print "No modified files"
  }
}

# ============================================================================
# GIT WORKFLOW
# ============================================================================

# Clone a git repository and cd into it
#
# Clones a git repository and automatically changes into the cloned directory.
# Extracts the repository name from the URL and removes .git suffix if present.
#
# Examples:
#   > gitcd https://github.com/user/repo.git
#   > gitcd git@github.com:user/repo.git
#   > gitcc https://github.com/user/repo      # Using alias
export def --env gitcd [
  url: string # Git repository URL to clone
] {
  # Extract the last path component (e.g., "myrepo.git" or "myrepo")
  let base = ($url | path basename)

  # Remove trailing ".git" if present
  let repo = ($base | str replace --regex '\.git$' '')

  # Clone and change into the repo directory if successful
  git clone $url
  if $env.LAST_EXIT_CODE == 0 {
    cd $repo
  }
}

# Fuzzy find and checkout a git branch
#
# Lists all branches (local and remote), removes duplicates, and allows fuzzy selection.
# Checks out the selected branch.
#
# Examples:
#   > fgb                    # Select and checkout a branch
export def --env fgb [] {
  let branch = (
    ^git branch --all
    | lines
    | where $it !~ "HEAD"
    | str replace "remotes/origin/" ""
    | uniq
    | to text
    | ^fzf --height 70% --reverse
    | str trim
  )

  if ($branch | is-not-empty) {
    git checkout $branch
  }
}

# Fuzzy find and checkout a git commit
#
# Shows git log with one-line format and allows fuzzy selection.
# Checks out the selected commit.
#
# Examples:
#   > fco                    # Select and checkout a commit
export def --env fco [] {
  let commit = (
    ^git log --pretty=oneline --abbrev-commit
    | lines
    | to text
    | ^fzf --height 70% --reverse
    | str trim
    | split row " "
    | first
  )

  if ($commit | is-not-empty) {
    git checkout $commit
  }
}

# ============================================================================
# PROCESS MANAGEMENT
# ============================================================================

# Fuzzy find and kill processes
#
# Lists running processes and allows multi-selection for termination.
# Kills selected processes with SIGKILL (-9).
#
# Examples:
#   > fkill                  # Select processes to kill
export def fkill [] {
  let pids = (
    ^ps -ef
    | lines
    | skip 1 # Skip header
    | to text
    | ^fzf -m --height 70% --reverse --preview 'echo {}'
    | lines
    | each {|line|
      $line | split row -r '\s+' | get 1
    }
  )

  if ($pids | is-not-empty) {
    $pids | each {|pid|
      kill -9 $pid
    } | ignore
  }
}

# ============================================================================
# BIOINFORMATICS TOOLS
# ============================================================================

# Parse FASTA format into a nushell table
#
# Converts FASTA sequences into a structured table with id and sequence columns.
# Uses seqkit for fast, reliable parsing.
#
# Examples:
#   > open sequences.fasta | from fasta
#   > cat sequences.fasta | from fasta | where ($it.sequence | str length) > 100
export def "from fasta" [] {
  $in
  | ^seqkit fx2tab --name --only-id
  | from tsv --noheaders
  | rename id sequence
}

# Parse gzipped FASTA format into a nushell table
#
# Converts gzipped FASTA sequences into a structured table with id and sequence columns.
# Uses seqkit for fast, reliable parsing.
#
# Examples:
#   > open sequences.fasta.gz | from fasta-gz
#   > cat sequences.fa.gz | from fasta-gz | where ($it.sequence | str length) > 100
export def "from fasta-gz" [] {
  $in
  | ^gunzip -c
  | ^seqkit fx2tab --name --only-id
  | from tsv --noheaders
  | rename id sequence
}

# Parse FASTQ format into a nushell table
#
# Converts FASTQ sequences into a structured table with id, sequence, and quality columns.
# Uses seqkit for fast, reliable parsing.
#
# Examples:
#   > open sequences.fastq | from fastq
#   > cat sequences.fastq | from fastq | where ($it.sequence | str length) > 50
export def "from fastq" [] {
  $in
  | ^seqkit fx2tab --name --only-id --qual
  | from tsv --noheaders
  | rename id sequence quality
}

# Parse gzipped FASTQ format into a nushell table
#
# Converts gzipped FASTQ sequences into a structured table with id, sequence, and quality columns.
# Uses seqkit for fast, reliable parsing.
#
# Examples:
#   > open sequences.fastq.gz | from fastq-gz
#   > cat reads.fq.gz | from fastq-gz | where ($it.sequence | str length) > 50
export def "from fastq-gz" [] {
  $in
  | ^gunzip -c
  | ^seqkit fx2tab --name --only-id --qual
  | from tsv --noheaders
  | rename id sequence quality
}

# Convert nushell table to FASTA format
#
# Takes a table with 'id' and 'sequence' columns and converts to FASTA format.
#
# Examples:
#   > open sequences.fasta | from fasta | where ($it.sequence | str length) > 100 | to fasta
#   > [{id: "seq1", sequence: "ATCG"}] | to fasta | save output.fasta
export def "to fasta" [] {
  $in
  | each {|row|
    $">($row.id)\n($row.sequence)"
  }
  | str join "\n"
}

# Convert nushell table to gzipped FASTA format
#
# Takes a table with 'id' and 'sequence' columns and converts to gzipped FASTA format.
#
# Examples:
#   > open sequences.fasta | from fasta | where ($it.sequence | str length) > 100 | to fasta-gz | save output.fasta.gz
export def "to fasta-gz" [] {
  $in
  | each {|row|
    $">($row.id)\n($row.sequence)"
  }
  | str join "\n"
  | ^gzip -c
}

# Convert nushell table to FASTQ format
#
# Takes a table with 'id', 'sequence', and 'quality' columns and converts to FASTQ format.
#
# Examples:
#   > open sequences.fastq | from fastq | first 10 | to fastq | save subset.fastq
export def "to fastq" [] {
  $in
  | each {|row|
    $"@($row.id)\n($row.sequence)\n+\n($row.quality)"
  }
  | str join "\n"
}

# Convert nushell table to gzipped FASTQ format
#
# Takes a table with 'id', 'sequence', and 'quality' columns and converts to gzipped FASTQ format.
#
# Examples:
#   > open sequences.fastq | from fastq | first 10 | to fastq-gz | save subset.fastq.gz
export def "to fastq-gz" [] {
  $in
  | each {|row|
    $"@($row.id)\n($row.sequence)\n+\n($row.quality)"
  }
  | str join "\n"
  | ^gzip -c
}

# Fuzzy select sequences from FASTA/FASTQ files
#
# Extracts sequence IDs, allows multi-selection with preview, and outputs selected sequences.
# Can write to a file or stdout.
#
# Examples:
#   > fseq input.fasta                    # Output to stdout
#   > fseq input.fastq output.fastq       # Output to file
export def fseq [
  infile: string # Input FASTA or FASTQ file
  outfile?: string # Optional output file (stdout if not provided)
] {
  let ids = (
    ^seqkit seq -i -n $infile
    | lines
    | to text
    | ^fzf --height 70% --multi --preview $"seqkit grep -p {} '($infile)' | bat --wrap=auto --style=numbers,grid --color=always --theme=ansi"
    | lines
  )

  if ($ids | is-empty) {
    return
  }

  let comma_list = ($ids | str join ",")

  if ($outfile | is-not-empty) {
    ^seqkit grep -p $comma_list $infile -o $outfile
  } else {
    ^seqkit grep -p $comma_list $infile
  }
}

# Convert BAM files to FASTQ in parallel
#
# Finds all BAM files in current directory and converts them to gzipped FASTQ files
# using GNU parallel with 6 concurrent jobs.
#
# Examples:
#   > bam2fq                 # Convert all .bam files in current directory
export def bam2fq [] {
  ^find . -maxdepth 1 -type f -name '*.bam' -print0
  | ^parallel -0 -j 6 'echo "Converting {}..."; samtools fastq {} | gzip -c > {.}.fastq.gz; echo "Finished {}"'
}

# Generate statistics for sequence files
#
# Runs seqkit stats on all FASTA/FASTQ files in a directory.
# Outputs a formatted table or writes to a file.
#
# Examples:
#   > seqstats                           # Stats for current directory
#   > seqstats ~/data                    # Stats for specific directory
#   > seqstats -o stats.tsv              # Write to file
#   > seqstats ~/data -o stats.tsv       # Directory and output file
export def seqstats [
  dir: string = "." # Directory containing sequence files
  --output (-o): string # Output file (stdout if not provided)
] {
  if not ($dir | path exists) {
    error make {msg: $"Directory '($dir)' does not exist"}
  }

  let files = (
    glob $"($dir)/*.{fa,fasta,fq,fastq,fa.gz,fasta.gz,fq.gz,fastq.gz}"
  )

  if ($files | is-empty) {
    error make {msg: $"No FASTA/FASTQ files found in '($dir)'"}
  }

  if ($output | is-not-empty) {
    ^seqkit stats -b -a -T -j 1 ...$files | save -f $output
  } else {
    ^seqkit stats -b -a -T -j 1 ...$files | ^csvtk pretty -t --style 3line
  }
}

# ============================================================================
# DEVELOPMENT TOOLS
# ============================================================================

# Set up Ghostty terminal info on remote server
#
# Compiles local terminal info and sends it to a remote server via SSH.
# Allows Ghostty to work properly over SSH connections.
#
# Examples:
#   > allow_ghostty user@server.com
export def allow_ghostty [
  location: string # SSH destination (user@host)
] {
  ^infocmp -x | ^ssh $location -- tic -x -
}

# Launch Marimo notebook with interactive cleanup
#
# Opens a Marimo Python notebook with common data science libraries.
# For scratch files, prompts to keep/rename/delete after closing.
#
# Examples:
#   > mo                     # Create/edit scratch.py
#   > mo analysis.py         # Edit specific file (no cleanup prompt)
export def mo [
  file: string = "scratch.py" # Notebook file to edit
] {
  let user_provided = ($file != "scratch.py")

  # Run marimo with common libraries
  ^env RUST_LOG=warn uvx --with polars --with biopython --with pysam --with polars-bio --with altair --with plotnine marimo edit $file

  # Only prompt for cleanup if using default scratch file
  if not $user_provided {
    print -n $"Keep ($file)? [y/N]: "
    let keep = (input)

    if ($keep | str downcase) in ["y" "yes"] {
      print -n $"Rename ($file)? (leave empty to keep name): "
      let newname = (input)

      if ($newname | is-not-empty) {
        mv $file $newname
        print $"Saved as ($newname)"
      } else {
        print $"Keeping as ($file)"
      }
    } else {
      rm -f $file
      print $"Deleted ($file)"
    }
  }
}

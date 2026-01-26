# commands.nu
#
# Custom commands and functions for nushell
# Organized by category: directory navigation, file operations, editor integration,
# git workflow, process management, bioinformatics tools, and development tools

use std/assert

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

# Change to the local directory storing DHOLK experiment directories. See
# https://dholk.primate.wisc.edu/project/dho/experiments/begin.view for the online
# equivalents of the files in these directories.
export def --env dholk [] {
  let dholk_dir = if $nu.os-info.name == "macos" {
    $env.HOME | path join "Documents" "dholk_experiments"
  } else {
    $env.HOME | path join "dholk_experiments"
  }

  if not ($dholk_dir | path exists) {
    mkdir $dholk_dir
  }

  cd $dholk_dir
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

# Convert tabular data files between formats using DuckDB
#
# Converts between CSV, TSV, Parquet, and JSON formats.
# DuckDB auto-detects the source format based on file extension.
# Requires duckdb to be installed and available in PATH.
#
# Examples:
#   > convert_file data.csv data.parquet        # CSV to Parquet
#   > convert_file results.parquet results.csv  # Parquet to CSV
#   > convert_file input.json output.tsv        # JSON to TSV
export def convert_file [
  src: string # Source file path (csv, tsv, parquet, json, ndjson)
  dest: string # Destination file path (csv, tsv, parquet, json, ndjson)
] {
  assert ($src | path exists) $"The source file provided, ($src), does not exist."

  let src_ext = $src | path parse | get extension | str downcase
  let dest_ext = $dest | path parse | get extension | str downcase

  let supported = ["csv" "tsv" "parquet" "json" "ndjson"]

  assert ($src_ext in $supported) $"The source file's extension, ($src_ext), is not supported. Supported formats: ($supported | str join ', ')."
  assert ($dest_ext in $supported) $"The destination file's extension, ($dest_ext), is not supported. Supported formats: ($supported | str join ', ')."

  try {
    ^duckdb -c $"copy \(select * from '($src)') to '($dest)'"
  } catch {|err|
    error make {msg: $"Conversion failed: ($err.msg)"}
  }

  print $"Conversion complete: ($dest)"
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
# By default shows all changes including untracked files, excluding deleted files.
#
# Note: This command name conflicts with Mercurial's CLI. If Mercurial is installed,
# this command will error with instructions on how to disable it.
#
# Examples:
#   > hg                     # Open all modified files including untracked
#   > hg --tracked           # Open only tracked modified files (staged + unstaged)
#   > hg --unstaged          # Open only unstaged modified files
export def hg [
  --tracked (-t) # Only show tracked files (staged + unstaged vs HEAD)
  --unstaged (-w) # Only show unstaged changes (working tree vs index)
] {
  if (which jj | is-not-empty) {
    print $"(ansi yellow)WARNING:(ansi reset) It is recommended you use `hj` instead of `hg` given that you have Jujutsu installed."
  }

  # Check if mercurial (external hg) is installed - if so, we shouldn't shadow it
  let mercurial = (which -a hg | where type == "external" | length)
  if ($mercurial != 0) {
    error make {
      msg: "Command collision: 'hg' conflicts with Mercurial"
      help: $"Mercurial is installed at ($mercurial.path). This custom 'hg' command cannot coexist with it.

To disable this custom command and use Mercurial instead, add to your config.nu:
    hide commands hg

Or remove/rename the 'hg' command in commands.nu"
    }
  }

  let files = if $unstaged {
    # Just unstaged changes, excluding deleted files
    git diff --name-only --diff-filter=d | lines
  } else if $tracked {
    # Get staged and unstaged changes (all changes vs HEAD), excluding deleted files
    git diff --name-only --diff-filter=d HEAD | lines
  } else {
    # Get all changes including untracked, excluding deleted files
    # Porcelain format: XY filename (2-char status, space, filename)
    # Note: 0..<2 is exclusive range; 0..2 would include index 2
    git status --porcelain -uall
    | lines
    | where ($it | str substring 0..<2) != "D " and ($it | str substring 0..<2) != " D"
    | each { $in | str substring 3.. }
  }

  if ($files | is-not-empty) {
    hx ...$files
  } else {
    print "No modified files"
  }
}

# Open modified jj files in Helix
#
# Opens files modified in a jj revision as buffers in Helix.
# Defaults to the working copy (@).
#
# Examples:
#   > jj hx                  # Open files modified in working copy
#   > jj hx -r @-            # Open files modified in parent revision
#   > jj hx -r abc123        # Open files modified in specific revision
export def "jj hx" [
  --revision (-r): string = "@" # Revision to show changes for
] {
  # find modified files, filtering out deleted ones
  let files = ^jj diff --summary -r $revision
  | lines
  | where not ($it | str starts-with "D ")
  | each { $in | str substring 2.. }

  # exit if there are no files in this revision
  if ($files | is-empty) {
    print $"No modified files in revision ($revision)"
    return
  }

  if ($files | is-not-empty) {
    hx ...$files
  } else {
    print $"No modified files in revision ($revision)"
  }
}
export alias hj = jj hx
export alias hjj = jj hx
export alias hxjj = jj hx
export alias jjhx = jj hx

# ============================================================================
# VERSION CONTROL WORKFLOW
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

# Clone a repository into a dedicated code reviews directory.
#
# By default, clones into ~/Documents/code-reviews, creating the directory if it
# doesn't exist. Uses Jujutsu (jj) for cloning, falling back to git if jj fails.
#
# Examples:
#   # Clone a repo into the default code reviews directory
#   review https://github.com/nushell/nushell.git
#
#   # Clone into a custom directory
#   review https://github.com/nushell/nushell.git ~/reviews
#
#   # Fail if the code reviews directory doesn't exist
#   review --no-create https://github.com/nushell/nushell.git
#
#   # Immediately open the cloned directory into the editor set up with $VISUAL,
#   # falling back to $EDITOR
#   review --edit https://github.com/nushell/nushell.git
export def --env review [
  repo: string # URL for repository to clone
  directory?: string # override default behavior and place the repo in this destination
  --no-create (-n) # fail instead of creating a code-reviews parent directory
  --edit (-e) # open editor once the clone is complete
] {
  # link up the components of a directory for code reviews (note that this path will
  # not be idiomatic on windows)
  let reviews_dir = match $directory {
    null | "" => ($env.HOME | path join "Documents" "code-reviews")
    _ => $directory
  }

  # run existence check on the reviews directory
  let dir_exists = $reviews_dir | path exists

  # create the directory if it doesn't exist
  match [$dir_exists $no_create] {
    [false true] => {
      error make {
        msg: $"The expected code reviews directory, ($reviews_dir), does not exist, and `--no-create` was specified."
      }
    }
    [false false] => { mkdir -v $reviews_dir }
    _ => { }
  }

  # pull out the name of the repo so we can check if it already exists
  let repo_name = $repo
  | path basename
  | str replace -r '\.git$' ''

  # change to the reviews dir that we now know exists
  cd $reviews_dir

  # if the repo directory already exists, just cd into it, fetch updates, and optionally open editor
  if ($repo_name | path exists) {
    print $"Repository '($repo_name)' already exists, switching to it."
    cd $repo_name

    # try to fetch updates with jj, falling back to git
    try { jj git fetch } catch {
      try { git fetch } catch {
        print "WARNING: failed to fetch updates (you may be offline)."
      }
    }

    if $edit {
      try { ^$env.VISUAL . } catch {
        try { ^$env.EDITOR . } catch {|err|
          error make {
            msg: $"Could not open editor: '($err.msg)'"
          }
        }
      }
    }
    return
  }

  # make sure the user's repo exists
  try { git ls-remote $repo | ignore } catch {
    error make {
      msg: $"The provided repo '($repo)' does not exist, is private to you, or there is no network connection."
    }
  }

  # try to clone with `jj`, falling back to git if needed
  try { jj git clone $repo } catch {
    print "WARNING: failed to clone with Jujutsu; falling back to git."
    git clone $repo
  }

  cd $repo_name

  # if the user doesn't want to immediately open their editor, we're done here
  if not $edit { return }

  # if the editor is requested, open the directory in this repo
  try { ^$env.VISUAL . } catch {
    try {
      ^$env.EDITOR .
    } catch {|err|
      error make {
        msg: $"Could not automatically open the repo for review using the editor in $VISUAL or $EDITOR: '($err.msg)'"
      }
    }
  }
}
export alias code-review = review
# export alias "code review" = code-review

# Describe the current jj change with an optional message
#
# Opens the editor for interactive description if no message provided.
# Requires jj (Jujutsu) to be installed and available in PATH.
#
# Examples:
#   > jjd                           # Open editor to write description
#   > jjd "Fix typo in README"      # Set description directly
export def jjd [
  msg?: string # Optional commit message
] {
  if ($msg | is-not-empty) {
    ^jj describe -m $msg
  } else {
    ^jj describe
  }
}

# Create a new jj change with an optional description
#
# Creates a new change after the current one. If a message is provided,
# sets the description immediately; otherwise leaves it empty.
# Requires jj (Jujutsu) to be installed and available in PATH.
#
# Examples:
#   > jjn                           # Create new empty change
#   > jjn "Add user authentication" # Create new change with description
export def jjn [
  msg?: string # Optional description for the new change
] {
  if ($msg | is-not-empty) {
    ^jj new -m $msg
  } else {
    ^jj new
  }
}

# Initialize a colocated jj repo from an existing git repo
#
# Runs `jj git init --colocate` and then tracks all remote-tracking branches
# from origin as jj bookmarks. This is useful when migrating a git repo to jj
# while keeping it colocated (sharing the .git directory).
#
# Examples:
#   > jj from git            # Initialize jj and track all origin branches
export def "jj from git" [] {
  # start with an init
  ^jj git init --colocate

  # determine which bookmarks to create based on branches on the remote origin
  let origin_branches = git branch -r
  | lines
  | where $it !~ "HEAD" # Filter out HEAD -> main pointer
  | str trim
  | each {|b| $b | str replace "origin/" "" }

  # track any detected git origin branches
  if ($origin_branches | is-not-empty) {
    ^jj bookmark track --remote=origin ...$origin_branches
  }
}

# Set the most recent ancestor bookmark to the latest commit and then push it to a
# git remote branch.
#
# This command replaces running `jj bookmark move --from heads(::@- & bookmarks()) --to @-`
# followed by `jj git push`. And it is also funny. It is a portmanteau of tug and push.
#
# NOTE: This command requires the following section in the jujutsu config TOML:
#
# ```toml
# [aliases]
# tug = ["bookmark", "move", "--from", "heads(::@- & bookmarks())", "--to", "@-"]
#
# ```
export def "jj tush" [] { jj tug; jj git push }

# Hybrid zoxide + local directory completer
#
# Provides completions from both local directories and zoxide's frecency database.
# Local directories are shown first (as relative paths), followed by zoxide
# frecency results (as absolute paths). Duplicates are filtered out.
# Used internally by the z command below.
def "nu-complete zoxide path" [context: string] {
  let parts = $context | split row " " | skip 1
  let query = ($parts | str join " ")

  # Get local directories, filtered by query if present
  let local_dirs = (
    ls | where type == dir | get name
    | if ($query | is-empty) { $in } else { where { $in =~ $query } }
  )

  # Get zoxide frecency results
  let zoxide_dirs = (
    do { ^zoxide query --list --exclude $env.PWD -- ...$parts } | complete
    | if ($in.exit_code == 0) { $in.stdout | lines } else { [] }
  )

  # Combine: local first, then zoxide (excluding duplicates by basename)
  let zoxide_filtered = ($zoxide_dirs | where { ($in | path basename) not-in $local_dirs })

  {
    options: {
      sort: false
      completion_algorithm: substring
      case_sensitive: false
    }
    completions: ($local_dirs | append $zoxide_filtered)
  }
}

# Jump to a directory using zoxide with completions
#
# Overrides the z alias from .zoxide.nu to provide tab completions
# from zoxide's frecency database. Wraps __zoxide_z for the actual navigation.
#
# Examples:
#   > z dot<TAB>             # Complete to ~/.dotfiles (if visited frequently)
#   > z bio des<TAB>         # Complete with multiple keywords
export def --env --wrapped z [...rest: string@"nu-complete zoxide path"] {
  __zoxide_z ...$rest
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
  | ^seqkit fx2tab
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
  | ^seqkit fx2tab
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
  | ^seqkit fx2tab
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
  | ^seqkit fx2tab
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

# Build and optionally push Docker images with sticky configuration
#
# On first run, provide options to create a .dockerup config file in nuon format.
# Subsequent runs in the same directory will use the saved config.
# Command-line args override and update the config file.
#
# The .dockerup file stores all settings, so after initial setup you can just
# run `dockerup` with no arguments to repeat the same build/push workflow.
#
# Examples:
#   > dockerup -i nrminor/nvd -t v2.4.0 -p -l     # First run: creates .dockerup
#   > dockerup                                     # Uses saved config
#   > dockerup -t v2.5.0                           # Bump tag, updates .dockerup
#   > dockerup --no-push                           # Build only, disables push in config
export def dockerup [
  --image (-i): string # Image name (e.g., "nrminor/nvd")
  --tag (-t): string # Version tag (e.g., "v2.4.0")
  --push (-p) # Push to Docker Hub after building
  --no-push # Disable pushing (overrides config)
  --latest (-l) # Also build/push :latest tag
  --no-latest # Disable :latest tagging (overrides config)
  --file (-f): string # Containerfile path (default: "Containerfile")
  --platform: string # Target platform (default: "linux/amd64")
] {
  let config_file = ".dockerup"

  # Load existing config or start empty
  let config = if ($config_file | path exists) {
    open $config_file | from nuon
  } else {
    {}
  }

  # Resolve all settings: CLI args override config, then defaults
  let resolved_image = $image | default $config.image?
  let resolved_tag = $tag | default $config.tag?
  let resolved_file = $file | default ($config.file? | default "Containerfile")
  let resolved_platform = $platform | default ($config.platform? | default "linux/amd64")

  # Boolean flags: --no-* takes precedence, then --*, then config, then false
  let resolved_push = if $no_push {
    false
  } else if $push {
    true
  } else {
    $config.push? | default false
  }

  let resolved_latest = if $no_latest {
    false
  } else if $latest {
    true
  } else {
    $config.latest? | default false
  }

  # Validate required values
  if $resolved_image == null {
    error make {msg: "No image specified. Provide --image or create a .dockerup file."}
  }
  if $resolved_tag == null {
    error make {msg: "No tag specified. Provide --tag or create a .dockerup file."}
  }

  # Build new config from resolved values
  let new_config = {
    image: $resolved_image
    tag: $resolved_tag
    push: $resolved_push
    latest: $resolved_latest
    file: $resolved_file
    platform: $resolved_platform
  }

  # Save config if any CLI arg was provided or config didn't exist
  let config_changed = (
    $image != null or $tag != null or $push or $no_push or $latest or $no_latest
    or $file != null or $platform != null or not ($config_file | path exists)
  )

  if $config_changed {
    $new_config | to nuon | save -f $config_file
    print $"Updated ($config_file)"
  }

  # Validate containerfile exists
  if not ($resolved_file | path exists) {
    error make {msg: $"Containerfile not found: ($resolved_file)"}
  }

  let versioned_tag = $"($resolved_image):($resolved_tag)"
  let latest_tag = $"($resolved_image):latest"

  # Build versioned image
  print $"Building ($versioned_tag)..."
  ^docker buildx build --platform $resolved_platform --file $resolved_file --tag $versioned_tag --load .

  if $resolved_push {
    print $"Pushing ($versioned_tag)..."
    ^docker push $versioned_tag
  }

  # Handle latest tag
  if $resolved_latest {
    print $"Tagging ($latest_tag)..."
    ^docker tag $versioned_tag $latest_tag

    if $resolved_push {
      print $"Pushing ($latest_tag)..."
      ^docker push $latest_tag
    }
  }

  print "Done!"
}

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

# ============================================================================
# SYSTEM MANAGEMENT
# ============================================================================

# Update nix flake and rebuild system
#
# Updates flake.lock inputs and rebuilds the system configuration.
# Use --dry-run to build without activating (no sudo required).
# Equivalent to: just update (but works from any directory)
#
# Examples:
#   > sysupdate              # Update flake and rebuild system
#   > sysupdate --dry-run    # Update flake and build without activating
export def sysupdate [
  --dry-run (-n) # Build without activating (no sudo required)
] {
  let flake_dir = $env.HOME | path join ".dotfiles" ".config" "nix"

  print "Updating nix flake..."
  ^nix flake update --flake $flake_dir

  if $dry_run {
    print "Building system (dry run)..."
    ^darwin-rebuild build --flake $"($flake_dir)#starter"
    print "[ok] Build succeeded (no changes applied)"
  } else {
    print "Rebuilding system..."
    ^sudo darwin-rebuild switch --flake $"($flake_dir)#starter"
    print "[ok] System updated and rebuilt"
  }
}

# Open and modify the nix flake in the editor configured with $VISUAL.
#
# This command is useful shorthand for changing to the dotfiles directory and opening
# the nix flake for modification, e.g., adding a nixpkgs system dependency.
export def --env sysmod [
  --update (-u) # run system update on exit
  --stay (-s) # stay in dotfiles repo on exit
] {
  # record the directory we're starting in (this can be anywhere in the system)
  let current_dir = $env.PWD

  # move to the dotfiles directory and find the flake
  let dotfiles_dir = $env.HOME | path join ".dotfiles"
  let darwin_flake = $dotfiles_dir | path join ".config" "nix" "flake.nix"

  # make sure the flake exists
  if not ($darwin_flake | path exists) {
    error make {msg: $"The system nix flake expected at the path ($darwin_flake) is missing. Aborting."}
  }

  # move into the dotfiles repo and open it in the user's editor
  cd $dotfiles_dir
  ^$env.VISUAL $darwin_flake

  # move back to the directory we started in unless the user requested otherwise
  if not $stay {
    cd $current_dir
  }

  # eagerly run a nixOS system update with any changes if requested by the user. This
  # command defaults to lazy updating unless given `--update`.
  if $update {
    sysupdate
  }
}
export alias sysedit = sysmod

# Display nix system health and storage information
#
# Shows system status including flake info and generations.
# Use --store to show nix store size (slow).
# Use --gc to scan for reclaimable space (very slow).
# Use --check to validate the flake.
#
# Examples:
#   > syscheck                  # Show system status (fast)
#   > syscheck --store          # Include store size (slow)
#   > syscheck --gc             # Include garbage collection analysis (very slow)
#   > syscheck --check          # Also run nix flake check
#   > syscheck --store --gc -c  # Full analysis
export def syscheck [
  --check (-c) # Also run nix flake check to validate flake
  --store (-s) # Show nix store size (slow)
  --gc (-g) # Scan for reclaimable space (very slow)
] {
  let flake_dir = $env.HOME | path join ".dotfiles" ".config" "nix"
  let flake_lock = $flake_dir | path join "flake.lock"

  # Header
  print "==================================================================="
  print "                       nix system status"
  print "==================================================================="
  print ""

  # Flake info
  print "[flake]"
  print $"  location: ($flake_dir)"
  if ($flake_lock | path exists) {
    let lock_info = (ls -l $flake_lock | first)
    let lock_age = ($lock_info.modified | into int) / 1_000_000_000
    let now = (date now | into int) / 1_000_000_000
    let age_days = (($now - $lock_age) / 86400 | math floor)
    print $"  lock age: ($age_days) days"
  }
  print ""

  # Current generation
  print "[current system]"
  let system_link = "/nix/var/nix/profiles/system"
  if ($system_link | path exists) {
    let current = (ls -l $system_link | first | get target | path basename)
    let gen_num = ($current | parse "system-{num}-link" | get 0?.num? | default "unknown")
    let current_target = (^readlink "/run/current-system" | str trim)
    print $"  generation: ($gen_num)"
    print $"  store path: ($current_target | path basename)"
  }
  print ""

  # Count all generations
  print "[generations]"
  let gen_links = (ls /nix/var/nix/profiles/system-*-link | length)
  print $"  total: ($gen_links)"
  # Show last 3
  let recent = (ls -l /nix/var/nix/profiles/system-*-link | sort-by modified | last 3 | reverse)
  print "  recent:"
  $recent | each {|g|
    let name = ($g.name | path basename)
    let num = ($name | parse "system-{num}-link" | get 0?.num? | default "?")
    let age = ($g.modified | date humanize)
    print $"    gen ($num): ($age)"
  }
  # Store size (opt-in due to slowness)
  if $store {
    print ""
    print "[nix store]"
    let store_size = (^du -sh /nix/store | split row "\t" | first | str trim)
    print $"  total size: ($store_size)"
  }

  # Garbage collection info (opt-in due to slowness)
  if $gc {
    print ""
    print "[garbage collection]"
    print "  scanning for reclaimable paths..."
    let dead_paths = (^nix-store --gc --print-dead err> /dev/null | lines)
    let dead_count = ($dead_paths | length)
    print $"  reclaimable paths: ($dead_count)"
    if $dead_count > 0 {
      # Estimate size of dead paths (sample first 100 for speed)
      let sample = ($dead_paths | first ([$dead_count 100] | math min))
      let sample_sizes = (
        $sample | each {|p|
          let info = (^nix path-info -S $p err> /dev/null | str trim | split row "\t")
          if ($info | length) >= 2 {
            $info | get 1 | into int
          } else {
            0
          }
        }
      )
      let sample_total = ($sample_sizes | math sum)
      let estimated_total = if $dead_count > 100 {
        ($sample_total * $dead_count / 100)
      } else {
        $sample_total
      }
      let human_size = if $estimated_total > 1073741824 {
        $"~(($estimated_total / 1073741824 | math round --precision 1))GB"
      } else if $estimated_total > 1048576 {
        $"~(($estimated_total / 1048576 | math round --precision 0))MB"
      } else {
        $"~(($estimated_total / 1024 | math round --precision 0))KB"
      }
      print $"  estimated reclaimable: ($human_size)"
      print "  hint: run 'nix-collect-garbage -d' to reclaim space"
    } else {
      print "  store is clean"
    }
  }

  # Optional flake check
  if $check {
    print ""
    print "[flake validation]"
    print "  running nix flake check..."
    let check_result = (do { ^nix flake check $flake_dir } | complete)
    if $check_result.exit_code == 0 {
      print "  [ok] flake check passed"
    } else {
      print "  [error] flake check failed"
      print $check_result.stderr
    }
  }

  print ""
  print "==================================================================="
}

# ============================================================================
# SHELL DIAGNOSTICS
# ============================================================================

# Display shell startup time and diagnostic information
#
# Shows timing and configuration details useful for optimizing shell startup.
# Includes nushell startup time, loaded commands/plugins, PATH analysis,
# active integrations, and starship module timings.
#
# Examples:
#   > startup                # Show all startup diagnostics
export def startup [] {
  # Core timing and version info
  print $"Nushell startup: ($nu.startup-time)"
  print $"Version: (version | get version)"
  print $"Config: ($nu.config-path)"

  # Load metrics
  let cmd_count = (help commands | length)
  let plugin_count = (plugin list | length)
  let overlay_count = (overlay list | length)
  print $"Commands loaded: ($cmd_count)"
  print $"Plugins: ($plugin_count)"
  print $"Overlays: ($overlay_count)"

  # Environment analysis
  let path_count = ($env.PATH | length)
  print $"PATH entries: ($path_count)"

  # History info
  let history_count = (history | length)
  print $"History entries: ($history_count)"

  # Detect active integrations
  let integrations = (
    [
      (if (which atuin | is-not-empty) { "atuin" })
      (if (which zoxide | is-not-empty) { "zoxide" })
      (if (which carapace | is-not-empty) { "carapace" })
      (if (which fnm | is-not-empty) { "fnm" })
      (if (which direnv | is-not-empty) { "direnv" })
      (if (which starship | is-not-empty) { "starship" })
    ]
    | compact
    | str join ", "
  )
  print $"Active integrations: ($integrations)"

  # Starship timings
  print ""
  print "Starship module timings:"
  ^starship timings
}

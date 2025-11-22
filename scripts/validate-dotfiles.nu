#!/usr/bin/env nu

# Dotfiles Repository Validation Script (Nushell Edition)
#
# A composable validation framework using a Rules API.
# Each rule is a function that returns a validation result,
# and rules can be easily composed together.

# ============================================================================
# ANSI COLORS & SYMBOLS
# ============================================================================

const colors = {
  reset: "\e[0m"
  bold: "\e[1m"
  red: "\e[31m"
  green: "\e[32m"
  yellow: "\e[33m"
  blue: "\e[34m"
  cyan: "\e[36m"
}

const symbols = {
  success: "✓"
  failure: "✗"
  warning: "⚠"
  info: "ℹ"
}

# ============================================================================
# TYPES & RECORDS
# ============================================================================

# Create an issue record
def create-issue [
  severity: string
  message: string
  --file: string = ""
  --fix: string = ""
] {
  {
    severity: $severity
    message: $message
    file: $file
    fix_suggestion: $fix
  }
}

# Create a validation result record
def create-validation-result [
  rule_name: string
  passed: bool
  issues: list
] {
  {
    rule_name: $rule_name
    passed: $passed
    issues: $issues
  }
}

# ============================================================================
# LOGGING HELPERS
# ============================================================================

def log-colored [message: string color: string] {
  print $"($color)($message)($colors.reset)"
}

def log-success [message: string] {
  log-colored $"($symbols.success) ($message)" $colors.green
}

def log-failure [message: string] {
  log-colored $"($symbols.failure) ($message)" $colors.red
}

def log-warning [message: string] {
  log-colored $"($symbols.warning) ($message)" $colors.yellow
}

def log-info [message: string] {
  log-colored $"($symbols.info) ($message)" $colors.cyan
}

def log-verbose [config: record message: string] {
  if $config.verbose {
    log-colored $"  ($message)" $colors.blue
  }
}

# ============================================================================
# UTILITIES
# ============================================================================

def is-tracked-by-git [config: record filepath: string] {
  let result = (
    do -i {
      cd $config.dotfiles_dir
      git ls-files --error-unmatch $filepath
    } | complete
  )
  $result.exit_code == 0
}

def is-ignored-by-git [config: record filepath: string] {
  let result = (
    do -i {
      cd $config.dotfiles_dir
      git check-ignore $filepath
    } | complete
  )
  $result.exit_code == 0
}

def get-tracked-files [config: record] {
  let result = (
    do -i {
      cd $config.dotfiles_dir
      git ls-files
    } | complete
  )

  if $result.exit_code == 0 {
    $result.stdout | lines | where {|it| $it != "" }
  } else {
    []
  }
}

def is-broken-symlink [filepath: string] {
  # Check if the path is a symlink using ls command
  let result = (do -i { ^ls -l $filepath } | complete)
  if $result.exit_code != 0 {
    return true
  }

  # If it's a symlink (contains ->), check if target exists
  if ($result.stdout | str contains "->") {
    # Try to stat the file - this will fail if symlink is broken
    let stat_result = (do -i { ^stat $filepath } | complete)
    $stat_result.exit_code != 0
  } else {
    false
  }
}

# ============================================================================
# TOML PARSING (Simple)
# ============================================================================

def parse-toml-file [filepath: string] {
  if not ($filepath | path exists) {
    return []
  }

  let content = (open --raw $filepath | lines)
  mut current_section = ""
  mut files = []

  for line in $content {
    let trimmed = ($line | str trim)

    # Skip empty lines and comments
    if ($trimmed | is-empty) or ($trimmed | str starts-with "#") {
      continue
    }

    # Check for section header
    if ($trimmed | str starts-with "[") and ($trimmed | str ends-with "]") {
      $current_section = ($trimmed | str substring 1..-2)
      continue
    }

    # Check for key-value pairs in .files sections
    if ($current_section | str ends-with ".files") and ($trimmed | str contains "=") {
      let parts = ($trimmed | split row "=" | each {|p| $p | str trim | str trim -c '"' })
      if ($parts | length) == 2 {
        let group = ($current_section | split row "." | first)
        $files = (
          $files | append {
            source: ($parts | first)
            target: ($parts | last)
            group: $group
          }
        )
      }
    }
  }

  $files
}

# ============================================================================
# VALIDATION RULES
# ============================================================================

# Rule: Dotter configuration files exist
def rule-dotter-configs-exist [config: record] {
  let global_toml = ($config.dotfiles_dir | path join ".dotter" "global.toml")

  mut issues = []

  if not ($global_toml | path exists) {
    $issues = ($issues | append (create-issue "error" "Dotter global.toml not found" --file $global_toml))
  }

  return (create-validation-result "Dotter configuration files exist" ($issues | is-empty) $issues)
}

# Rule: All files referenced in dotter config exist and are tracked
def rule-dotter-files-tracked [config: record] {
  let global_toml = ($config.dotfiles_dir | path join ".dotter" "global.toml")
  let macos_toml = ($config.dotfiles_dir | path join ".dotter" "macos.toml")

  let global_files = (parse-toml-file $global_toml)
  let macos_files = (parse-toml-file $macos_toml)
  let all_files = ($global_files | append $macos_files)

  if $config.verbose {
    log-info $"Found ($all_files | length) files referenced in dotter configs"
  }

  mut issues = []

  for file in $all_files {
    let filepath = ($config.dotfiles_dir | path join $file.source)

    if not ($filepath | path exists) {
      let source = $file.source
      let group = $file.group
      $issues = (
        $issues | append (
          create-issue "error" $"File missing: ($source) \(from ($group)\)" --file $source
        )
      )
      continue
    }

    if not (is-tracked-by-git $config $file.source) {
      let source = $file.source
      let group = $file.group
      if (is-ignored-by-git $config $source) {
        $issues = (
          $issues | append (
            create-issue "error"
            $"File ignored by git: ($source) \(from ($group)\)"
            --file $source
            --fix $"Add to .gitignore: !($source)"
          )
        )
      } else {
        $issues = (
          $issues | append (
            create-issue "warning"
            $"File not tracked: ($source) \(from ($group)\)"
            --file $source
            --fix $"Run: git add ($source)"
          )
        )
      }
    }
  }

  let passed = ($issues | where severity == "error" | is-empty)
  return (create-validation-result "Dotter files exist and are tracked" $passed $issues)
}

# Rule: No broken symlinks
def rule-no-broken-symlinks [config: record] {
  let tracked = (get-tracked-files $config)

  mut issues = []

  for file in $tracked {
    let filepath = ($config.dotfiles_dir | path join $file)
    if (is-broken-symlink $filepath) {
      $issues = (
        $issues | append (
          create-issue "error" $"Broken symlink: ($file)" --file $file
        )
      )
    }
  }

  return (create-validation-result "No broken symlinks" ($issues | is-empty) $issues)
}

# Rule: TOML files are valid
def rule-toml-files-valid [config: record] {
  let tracked = (get-tracked-files $config)
  let toml_files = ($tracked | where {|f| $f | str ends-with ".toml" })

  let issues = (
    $toml_files | each {|file|
      let filepath = ($config.dotfiles_dir | path join $file)

      let is_valid = (
        try {
          open $filepath | describe | str contains "record"
        } catch {
          false
        }
      )

      if not $is_valid {
        create-issue "error" $"Invalid TOML syntax: ($file)" --file $file
      } else {
        null
      }
    } | compact
  )

  return (create-validation-result $"All ($toml_files | length) TOML files are valid" ($issues | is-empty) $issues)
}

# Rule: JSON files are valid
def rule-json-files-valid [config: record] {
  let tracked = (get-tracked-files $config)
  let json_files = ($tracked | where {|f| ($f | str ends-with ".json") or ($f | str ends-with ".jsonc") })

  let issues = (
    $json_files | each {|file|
      # Skip JSONC files
      if ($file | str ends-with ".jsonc") or ($file | str contains "/.config/zed/") {
        return null
      }

      let filepath = ($config.dotfiles_dir | path join $file)

      let is_valid = (
        try {
          let desc = (open $filepath | describe)
          ($desc | str contains "record") or ($desc | str contains "list")
        } catch {
          false
        }
      )

      if not $is_valid {
        create-issue "error" $"Invalid JSON syntax: ($file)" --file $file
      } else {
        null
      }
    } | compact
  )

  return (create-validation-result $"All ($json_files | length) JSON files are valid" ($issues | is-empty) $issues)
}

# ============================================================================
# VALIDATOR
# ============================================================================

def run-rule [config: record rule: closure] {
  if $config.verbose {
    log-verbose $config "Checking..."
  }
  do $rule $config
}

def run-rules [config: record rules: list] {
  $rules | each {|rule| run-rule $config $rule }
}

def print-result [result: record] {
  if $result.passed {
    log-success $result.rule_name
  } else {
    log-failure $result.rule_name
  }

  for issue in $result.issues {
    let message = $"  ($issue.message)"

    match $issue.severity {
      "error" => { log-failure $message }
      "warning" => { log-warning $message }
      _ => { log-info $message }
    }

    if not ($issue.fix_suggestion | is-empty) {
      log-info $"    ($issue.fix_suggestion)"
    }
  }
}

def summarize [results: list config: record] {
  let separator = (1..60 | each { '=' } | str join)
  print $"\n($colors.bold)($separator)($colors.reset)"

  let total_issues = ($results | each {|r| $r.issues | length } | math sum)
  let errors = ($results | each {|r| $r.issues | where severity == "error" | length } | math sum)
  let warnings = ($total_issues - $errors)

  if $errors > 0 {
    log-failure $"Validation failed: ($total_issues) issue\(s\) found \(($errors) errors, ($warnings) warnings\)"

    if $config.fix_mode {
      print $"\n($colors.bold)Fix suggestions:($colors.reset)\n"

      let ignored_files = (
        $results
        | each {|r| $r.issues }
        | flatten
        | where {|i| $i.fix_suggestion | str contains ".gitignore" }
        | get file
      )

      if not ($ignored_files | is-empty) {
        log-info "Add these lines to .gitignore:"
        for file in $ignored_files {
          log-success $"  !($file)"
        }
        print ""
      }

      let untracked_files = (
        $results
        | each {|r| $r.issues }
        | flatten
        | where {|i| $i.fix_suggestion | str contains "git add" }
        | get file
      )

      if not ($untracked_files | is-empty) {
        log-info "Run this command to track files:"
        log-success $"  git add ($untracked_files | str join ' ')"
        print ""
      }
    }

    return 1
  } else if $warnings > 0 {
    log-warning $"Validation completed with ($warnings) warning\(s\)"
    return 0
  } else {
    log-success "All validations passed!\n"
    return 0
  }
}

# ============================================================================
# MAIN
# ============================================================================

def main [
  --fix (-f) # Show fix suggestions
  --verbose (-v) # Show detailed output
  --help (-h) # Show help message
] {
  if $help {
    print "
Usage: validate-dotfiles.nu [options]

Options:
  -f, --fix       Show fix suggestions
  -v, --verbose   Show detailed output
  -h, --help      Show this help message

Exit codes:
  0 - All validations passed
  1 - Validation failures found
  2 - Critical error
"
    exit 0
  }

  let dotfiles_dir = (
    $env.DOTFILES_DIR? | default (
      $env.FILE_PWD | path dirname
    )
  )

  let config = {
    dotfiles_dir: $dotfiles_dir
    verbose: ($verbose | default false)
    fix_mode: ($fix | default false)
  }

  print $"\n($colors.bold)Validating dotfiles repository...($colors.reset)\n"

  # Define all validation rules
  let rules = [
    {|c| rule-dotter-configs-exist $c }
    {|c| rule-dotter-files-tracked $c }
    {|c| rule-no-broken-symlinks $c }
    {|c| rule-toml-files-valid $c }
    {|c| rule-json-files-valid $c }
  ]

  # Run all rules and collect results
  let results = (run-rules $config $rules)

  # Print each result
  for result in $results {
    print-result $result
  }

  # Summarize and exit
  let exit_code = (summarize $results $config)
  exit $exit_code
}

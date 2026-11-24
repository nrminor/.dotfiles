const source_dir = path self ../.config/herdr-app
const targets = [
  "~/.config/herdr-core/config.toml"
  "~/.config/herdr-app/settings.json"
  "~/.config/herdr-app/keys.json"
  "~/.config/herdr-app/themes/catppuccin-macchiato.json"
]

def app-binary [] {
  let apps = ["/Applications/Herdr.app" ($env.HOME | path join "Applications/Herdr.app")]
  for app in $apps {
    if ($app | path exists) {
      let binary = $app | path join "Contents/MacOS/Herdr"
      if not ($binary | path exists) {
        error make {msg: $"Incomplete application at ($app); refusing to overwrite it."}
      }
      return $binary
    }
  }
  error make {msg: "Herdr Desktop is not installed. Run mise run herdr:desktop:install."}
}

def reject-extra-fields [managed: any, stored: any, address: string] {
  if not (($managed | describe) starts-with "record") { return }
  if not (($stored | describe) starts-with "record") { return }
  for key in ($stored | columns) {
    if $key not-in ($managed | columns) {
      error make {msg: $"Conflicting Herdr shortcut field ($address).($key). Back up keys.json and remove this extra field before deployment; recursive merge would retain it."}
    }
    reject-extra-fields ($managed | get $key) ($stored | get $key) $"($address).($key)"
  }
}

def check-bindings [] {
  let app = app-binary
  let commands = ^$app commands | from json
  let names = $commands | get name
  let bindings = open ($source_dir | path join keys.json)
  let target = $env.HOME | path join .config/herdr-app/keys.json
  let existing = if ($target | path exists) { open $target } else { {} }
  for section in ($bindings | columns) {
    let owned = $bindings | get $section
    let stored = $existing | get --optional $section | default {}
    for key in ($owned | columns) {
      reject-extra-fields ($owned | get $key) ($stored | get --optional $key) $"($section).($key)"
    }
  }
  for section in ($bindings | values) {
    for binding in ($section | values) {
      let command = if ($binding | describe) == string {
        $binding | split row ":" | first
      } else { $binding.command }
      if $command not-in ($names | append [send terminal]) {
        error make {msg: $"Unknown Herdr Desktop command: ($command)"}
      }
    }
  }
}

def main [] {
  print "Use mise run herdr:desktop:install, herdr:desktop:setup, or herdr:desktop:check."
}

def "main install" [] {
  if $nu.os-info.name != "macos" { return }
  let apps = ["/Applications/Herdr.app" ($env.HOME | path join "Applications/Herdr.app")]
  if ($apps | any {|app| $app | path exists }) {
    print $"Keeping installed application: (app-binary)"
    return
  }
  let work = mktemp -d
  try {
    let installer = $work | path join install.sh
    ^curl --fail --location --proto '=https' --proto-redir '=https' "https://releases.herdr.dev/app/install.sh" -o $installer
    ^sh $installer
  } catch {|error|
    rm --recursive --force $work
    error make $error
  }
  rm --recursive --force $work
}

def "main bootstrap" [] {
  if $nu.os-info.name != "macos" { return }
  main install
  print "Herdr Desktop installed. Run mise run herdr:desktop:setup to apply managed preferences."
  print "Open Herdr and run mise run herdr:desktop:check. Existing servers were not restarted."
}

def "main setup" [--dry-run] {
  check-bindings
  if $dry_run {
    ^mise --env macos dot apply --dry-run ...$targets
    return
  }
  let state = $env.XDG_STATE_HOME? | default ($env.HOME | path join ".local/state")
  let backup = $state | path join "dotfiles/backups" $"herdr-desktop-(date now | format date '%Y%m%d-%H%M%S-%f')"
  mkdir $backup
  ^chmod 700 $backup
  for target in $targets {
    let file = $target | path expand
    if ($file | path exists) {
      open --raw $file | save ($backup | path join ($file | path basename))
    }
  }
  print $"Previous preferences saved to ($backup)"
  ^mise --env macos dot apply --yes ...$targets
  print "Herdr Desktop configured. New shells use nu-login; existing processes and the TUI are unchanged."
}

def "main check" [] {
  check-bindings
  let app = app-binary
  ^$app --version
  ^hc --version
  let status = ^mise --env macos dot status --json ...$targets | from json
  let drift = ($status.files | append $status.edits) | where state != applied
  if ($drift | is-not-empty) {
    print $drift
    error make {msg: "Herdr Desktop preferences have drifted. Run mise run herdr:desktop:setup."}
  }
  let errors = glob ($env.HOME | path join ".config/herdr-app/*.error")
  if ($errors | is-not-empty) {
    error make {msg: $"Herdr reports config errors: ($errors | str join ', ')"}
  }
  print "Herdr Desktop bindings and deployed preferences checked; live agent input and recovery are separate tests."
}

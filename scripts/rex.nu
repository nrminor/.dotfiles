const source_dir = path self ../.config/rex

def rex-cli [] {
  $env.HOME | path join ".local/bin/rex"
}

def preferences [] {
  let shell = $env.HOME | path join ".local/bin/nu-login"
  if not ($shell | path exists) {
    error make {msg: $"Shell launcher missing: ($shell). Run mise run dots first."}
  }
  open ($source_dir | path join "preferences.json")
  | merge {"terminal.shell.command": $"\"($shell)\""}
}

def inspect-client [] {
  let cli = rex-cli
  let server = ^$cli --autostart=false whoami --json | from json
  let inspected = ^$cli --autostart=false client inspect --json | from json
  if (
    not ($server.endpoint | str starts-with "unix://")
    or $server.principal.transport != "unix"
    or $inspected.client.principal.transport != "unix"
    or $inspected.client.principal.uid != $server.principal.uid
    or $inspected.client.info.platform != "macos"
    or $inspected.client.info.kind != "app"
  ) {
    error make {msg: "Rex setup/check requires this user's local Mac client and Unix-socket server."}
  }
  $inspected
}

def check-actions [client: record, settings: record] {
  let names = $client.actions | get name
  let required = ($settings | columns | each {|key| $"client.setting.($key)" })
    | append [client.theme.import client.setting.themes.dark.palette]
  let missing = $required | where {|name| $name not-in $names }
  if ($missing | is-not-empty) {
    error make {msg: $"Rex lacks required actions: ($missing | str join ', ')"}
  }
}

def select-theme [cli: path, client: string, backup: path] {
  # Rex has no read-preferences action. Read the exported snapshot only;
  # writes still go through its supported client API.
  let stored = ^plutil -extract 'Workspace\.customThemes' raw -o - $backup | complete
  let themes = if $stored.exit_code == 0 {
    $stored.stdout | str trim | decode base64 | decode utf-8 | from json
  } else {
    if not ($stored.stdout | str contains "No value at that key path") {
      error make {msg: $"Cannot read Rex theme snapshot: ($stored.stdout)($stored.stderr)"}
    }
    []
  }
  let matches = $themes | where name == "Catppuccin Macchiato"
  if ($matches | length) > 1 {
    error make {msg: "Multiple Catppuccin Macchiato themes exist. Remove duplicates in Rex before setup."}
  }
  if ($matches | is-empty) {
    ^$cli --autostart=false -C $client do client.theme.import --args (
      {path: ($source_dir | path join "Catppuccin Macchiato")} | to json --raw
    )
  } else {
    ^$cli --autostart=false -C $client do client.setting.themes.dark.palette --args (
      {value: $matches.0.id} | to json --raw
    )
  }
}

def main [] {
  print "Use mise run rex:bootstrap, rex:setup, or rex:check."
}

# Bootstrap never opens the app, changes permissions, or restarts the server.
def "main bootstrap" [] {
  if $nu.os-info.name != "macos" { return }
  ^sh (path self install-rex.sh)
  print "Rex installed. Open Rex Beta, enable Remote Control, then run mise run rex:setup."
}

def "main setup" [--dry-run] {
  let cli = rex-cli
  let settings = preferences
  let client = inspect-client
  check-actions $client $settings
  ^$cli --autostart=false config check ($source_dir | path join "init.lua")
  if $dry_run {
    print ($settings | to json)
    print "Would deploy Rex files, back up preferences, import Macchiato, apply settings, reload bindings, and set up the OpenCode/Pi skill."
    return
  }

  let state = $env.XDG_STATE_HOME? | default ($env.HOME | path join ".local/state")
  let backup = $state | path join "dotfiles/backups" $"rex-(date now | format date '%Y%m%d-%H%M%S-%f')"
  mkdir $backup
  ^defaults export com.superlogical.rex ($backup | path join "preferences.plist")
  print $"Preferences backed up to ($backup)"
  ^mise --env macos dot apply --yes "~/.config/rex/init.lua" "~/.local/bin/rex"
  let id = $client.client.client_id
  for setting in ($settings | transpose name value) {
    ^$cli --autostart=false -C $id do $"client.setting.($setting.name)" --args ({value: $setting.value} | to json --raw)
  }
  select-theme $cli $id ($backup | path join "preferences.plist")
  ^$cli --autostart=false config reload
  ^$cli --autostart=false skill setup --agent opencode --agent pi
  print "Rex configured. Open a new terminal to use Nushell; existing processes were not restarted."
}

def "main check" [] {
  let cli = rex-cli
  ^$cli --autostart=false version
  ^$cli --autostart=false config check
  let client = inspect-client
  check-actions $client (preferences)
  let deployed = $env.HOME | path join ".config/rex/init.lua"
  if (open --raw $deployed) != (open --raw ($source_dir | path join "init.lua")) {
    error make {msg: "Rex configuration differs from dotfiles. Run mise run dots."}
  }
  print "Rex configuration and client action support checked; this does not test live keyboard input or agent recovery."
}

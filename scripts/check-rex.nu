#!/usr/bin/env nu
use std/assert

const root = path self ..

def calls [work: path] { open --raw ($work | path join calls) | lines }

def setup [work: path, scenario: string, ...args: string] {
  "" | save --force ($work | path join calls)
  with-env {REX_CASE: $scenario} {
    ^$nu.current-exe --no-config-file ($root | path join scripts/rex.nu) setup ...$args | complete
  }
}

def exercise [work: path] {
  let home = $work | path join home
  let bin = $work | path join bin
  let shell = $home | path join .local/bin/nu-login
  mkdir ($home | path join .local/bin) $bin
  "" | save $shell
  let settings = open ($root | path join .config/rex/preferences.json)
    | merge {"terminal.shell.command": $"\"($shell)\""}
  let actions = $settings | columns | each {|key| {name: $"client.setting.($key)"} }
    | append [{name: client.theme.import} {name: client.setting.themes.dark.palette}]
  let client = {client_id: test-client, info: {platform: macos, kind: app}, principal: {transport: unix, uid: 501}}
  {client: $client, actions: $actions}
    | to json | save ($work | path join client.json)
  {client: $client, actions: []}
    | to json | save ($work | path join unsupported.json)
  {endpoint: "unix:///test/rex.sock", principal: {transport: unix, uid: 501}}
    | to json | save ($work | path join server.json)
  {endpoint: "tcp://remote-mac:1234", principal: {transport: unix, uid: 501}}
    | to json | save ($work | path join remote.json)
  # Use real plutil on exported fixtures, including a near-name distractor.
  let decoy = {name: "Catppuccin Macchiato extra", id: wrong-id}
  for fixture in [
    {file: themes.plist, themes: [$decoy]}
    {file: imported.plist, themes: [$decoy {name: "Catppuccin Macchiato", id: existing-theme-id}]}
  ] {
    let encoded = $fixture.themes | to json --raw | encode base64
    $"<?xml version=\"1.0\"?><plist version=\"1.0\"><dict><key>Workspace.customThemes</key><data>($encoded)</data></dict></plist>"
      | save ($work | path join $fixture.file)
  }
  let mock = '#!/bin/sh
set -eu
printf "%s %s\n" "${0##*/}" "$*" >> "$REX_LOG"
case "${0##*/}:$*" in
  rex:*whoami\ --json*)
    if [ "$REX_CASE" = remote ]; then cat "$REX_WORK/remote.json"; else cat "$REX_WORK/server.json"; fi ;;
  rex:*client\ inspect*)
    case "$REX_CASE" in
      disconnected) echo "No connected client" >&2; exit 1 ;;
      unsupported) cat "$REX_WORK/unsupported.json" ;;
      *) cat "$REX_WORK/client.json" ;;
    esac ;;
  rex:*config\ check*)
    if [ "$REX_CASE" = invalid-config ]; then echo "invalid test Lua" >&2; exit 1; fi ;;
  defaults:export*)
    if [ "$REX_CASE" = backup-failure ]; then echo "test backup refused" >&2; exit 74; fi
    cp "$REX_WORK/themes.plist" "$3" ;;
  rex:*do\ client.theme.import*)
    cp "$REX_WORK/imported.plist" "$REX_WORK/themes.plist" ;;
  rex:*do\ client.setting.*)
    if [ "$REX_CASE" = setting-failure ]; then echo "test preference refused" >&2; exit 75; fi ;;
  curl:*) echo "blocked test download" >&2; exit 73 ;;
  uname:-s) echo Darwin ;;
  uname:-m) echo arm64 ;;
esac
'
  for name in [rex defaults mise curl uname hdiutil codesign spctl ditto] {
    let target = if $name == rex { $home | path join .local/bin/rex } else { $bin | path join $name }
    $mock | save $target
    ^chmod +x $target
  }
  with-env {
    HOME: $home, MISE_DATA_DIR: ($work | path join "mise data"),
    XDG_STATE_HOME: ($work | path join state), TMPDIR: $work, REX_WORK: $work,
    REX_LOG: ($work | path join calls), PATH: ([$bin] | append $env.PATH)
  } {
    for attempt in 1..2 {
      let result = setup $work supported "--dry-run"
      assert equal $result.exit_code 0 $result.stderr
      assert equal ($result.stdout | split row "Would deploy" | first | from json) $settings
      assert equal (calls $work | length) 3
      assert ((calls $work | all {|line| $line =~ '^rex --autostart=false (whoami --json|client inspect --json|config check .*/init.lua)$' }))
      assert (not ($work | path join state | path exists))
    }
    print "PASS setup dry-run twice: inspect/check only, no backup or mutations"

    for scenario in [disconnected unsupported invalid-config remote] {
      let result = setup $work $scenario
      assert ($result.exit_code != 0) $"setup must refuse ($scenario)"
      let expected = match $scenario {
        disconnected => "No connected client"
        unsupported => "Rex lacks required actions"
        remote => "requires this user's local Mac client and Unix-socket server"
        _ => "invalid test Lua"
      }
      assert ($result.stderr | str contains $expected) $result.stderr
      assert (calls $work | all {|line| $line =~ '^rex --autostart=false (whoami|client inspect|config check)' })
      assert (not ($work | path join state | path exists))
    }
    print "PASS disconnected/remote client, unsupported actions and invalid config refuse before mutation"

    for attempt in 1..2 {
      let result = setup $work supported
      assert equal $result.exit_code 0 $result.stderr
      let applied = calls $work | where {|line| $line =~ ' do client.setting\.' and $line !~ 'client.setting.themes.dark.palette' }
      assert equal ($applied | length) ($settings | columns | length)
      for setting in ($settings | transpose name value) {
        let expected = $"rex --autostart=false -C test-client do client.setting.($setting.name) --args ({value: $setting.value} | to json --raw)"
        assert ($expected in $applied) $"Missing or wrong setting: ($setting.name)"
      }
      assert equal (calls $work | where {|line| $line == "rex --autostart=false config reload" } | length) 1
      assert ("mise --env macos dot apply --yes ~/.config/rex/init.lua ~/.local/bin/rex" in (calls $work))
      assert equal (calls $work | where {|line| $line =~ ' do client.theme.import ' } | length) (if $attempt == 1 { 1 } else { 0 })
      let selected = calls $work | where {|line| $line =~ ' do client.setting.themes.dark.palette ' }
      assert equal ($selected | length) (if $attempt == 1 { 0 } else { 1 })
      if $attempt == 2 {
        assert equal ($selected | first) 'rex --autostart=false -C test-client do client.setting.themes.dark.palette --args {"value":"existing-theme-id"}'
      }
    }
    assert equal (glob ($work | path join state/dotfiles/backups/*/preferences.plist) | length) 2
    print "PASS repeated setup: typed settings, separate backups, exact-name theme reused without duplicate import"

    for scenario in [backup-failure setting-failure] {
      let result = setup $work $scenario
      assert ($result.exit_code != 0) $"setup must stop on ($scenario)"
      assert ($result.stderr | str contains (if $scenario == backup-failure { "test backup refused" } else { "test preference refused" }))
      let attempted = calls $work
      if $scenario == backup-failure {
        assert (not ($attempted | any {|line| $line =~ '^(mise |rex .* do )' }))
      } else {
        assert equal ($attempted | where {|line| $line =~ ' do client.setting\.' } | length) 1
      }
      assert (not ($attempted | any {|line| $line =~ '(client.theme.import|config reload|skill setup)' }))
    }
    print "PASS backup and preference failures stop before subsequent mutations"

    let launcher = $root | path join scripts/rex.sh
    let missing = ^sh $launcher version | complete
    assert equal $missing.exit_code 127
    assert ($missing.stderr | str contains "Open Rex Beta once")
    let server = $home | path join "Library/Application Support/com.superlogical.rex/RexServer/Versions/Current/Rex Server.app/Contents/MacOS/rex"
    mkdir ($server | path dirname)
    "#!/bin/sh\nprintf '<%s>\\n' \"$@\"\nexit 23\n" | save $server
    ^chmod +x $server
    let forwarded = ^sh $launcher "two words" "" "--autostart=false" | complete
    assert equal $forwarded.exit_code 23
    assert equal $forwarded.stdout "<two words>\n<>\n<--autostart=false>\n"
    print "PASS launcher missing-server error, argument boundaries and exit propagation"

    # Intercept only system-app directory probes so an installed real Rex cannot
    # hide the missing-install path. All other tests and commands remain real.
    "" | save --force ($work | path join calls)
    let install = ^sh -c '[() { case "$2" in /Applications/Rex*.app) return 1;; esac; command [ "$@"; }; . "$1"' test ($root | path join scripts/install-rex.sh) | complete
    assert equal $install.exit_code 73
    assert ($install.stderr | str contains "blocked test download")
    assert (calls $work | all {|line| $line =~ '^(uname|curl) ' })
    assert (not ($home | path join Applications | path exists))
    assert equal (glob ($work | path join "rex-install.*")) []
    mkdir ($home | path join "Applications/Rex Beta.app")
    "" | save --force ($work | path join calls)
    for attempt in 1..2 {
      let kept = ^sh ($root | path join scripts/install-rex.sh) | complete
      assert equal $kept.exit_code 0 $kept.stderr
      assert ($kept.stdout | str contains "Keeping installed application")
    }
    assert (calls $work | all {|line| $line == "uname -s" })
    print "PASS missing install download failure is safe; existing app bootstrap is repeat-safe"
  }
}

def main [] {
  let cli = $env.HOME | path join .local/bin/rex
  if ($cli | path exists) {
    let checked = ^$cli --autostart=false config check ($root | path join .config/rex/init.lua) --json | complete
    assert equal $checked.exit_code 0 $checked.stderr
    let config = $checked.stdout | from json
    assert equal $config.diagnostics []
    assert equal [$config.bindings $config.removals $config.modes] [44 0 1]
    assert equal ($config.actions | get name | sort) [open_btop open_opencode open_pi open_tuicr open_yazi]
    print "PASS real Rex loads Lua: 44 bindings, native shortcuts retained, resize mode, five utility actions"
  } else {
    print "SKIP real Rex Lua check: CLI not installed"
  }
  let work = mktemp -d
  try {
    exercise $work
  } catch {|error|
    rm --recursive --force $work
    error make $error
  }
  rm --recursive --force $work
}

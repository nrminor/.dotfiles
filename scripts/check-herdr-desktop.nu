#!/usr/bin/env nu
use std/assert

const root = path self ..
const targets = [
  "~/.config/herdr-core/config.toml"
  "~/.config/herdr-app/settings.json"
  "~/.config/herdr-app/keys.json"
  "~/.config/herdr-app/themes/catppuccin-macchiato.json"
]

def check-shortcuts [] {
  let bindings = open ($root | path join .config/herdr-app/keys.json) | get global
  for shortcut in [
    {key: cmd-alt-b, name: Btop, program: btop}
    {key: cmd-alt-y, name: Yazi, program: yazi}
    {key: cmd-alt-r, name: Tuicr, program: tuicr}
    {key: cmd-alt-o, name: OpenCode, program: opencode}
    {key: cmd-alt-p, name: Pi, program: pi}
  ] {
    # -c exits Nu when the utility exits, allowing Herdr to fall back to stale SHELL.
    assert equal ($bindings | get $shortcut.key) {
      command: tab.new,
      args: {name: $shortcut.name, argv: [nu-login --interactive --execute $shortcut.program]}
    } $"($shortcut.key) must return to configured interactive Nu after the utility quits"
  }
  print "PASS five utility shortcuts use --execute, preserving configured Nu after tool exit"
}

def check-catalog [] {
  let app = ["/Applications/Herdr.app" ($env.HOME | path join Applications/Herdr.app)]
    | each {|dir| $dir | path join Contents/MacOS/Herdr }
    | where {|file| $file | path exists }
  if ($app | is-empty) {
    print "SKIP installed Herdr command validation: app not installed"
    return false
  }
  let result = ^($app | first) commands | complete
  assert equal $result.exit_code 0 $result.stderr
  let catalog = $result.stdout | from json
  let bindings = open ($root | path join .config/herdr-app/keys.json)
  for section in ($bindings | values) {
    for binding in ($section | values) {
      let name = if ($binding | describe) == string {
        $binding | split row ":" | first
      } else { $binding.command }
      if $name == send { continue }
      let command = $catalog | where name == $name
      assert equal ($command | length) 1 $"Unknown Herdr command: ($name)"
      if ($binding | describe) != string {
        let args = $command | first | get args
        let supplied = $binding.args | columns
        assert ($supplied | all {|key| $key in ($args | get name) }) $"Unknown arguments for ($name)"
        assert ($args | where required | all {|arg| $arg.name in $supplied }) $"Missing arguments for ($name)"
      }
    }
  }
  print "PASS installed Herdr recognizes keymap commands and object argument names (read-only)"
  true
}

def contents [home: path] {
  glob ($home | path join "**/*") --no-dir
    | sort
    | each {|file| {file: ($file | path relative-to $home), content: (open --raw $file)} }
}

def check-merges [work: path, mise: path] {
  let home = $work | path join "home with spaces"
  mkdir ($home | path join .config/herdr-core) ($home | path join .config/herdr-app)
  let core = $home | path join .config/herdr-core/config.toml
  let settings = $home | path join .config/herdr-app/settings.json
  let keys = $home | path join .config/herdr-app/keys.json
  {shell: ["/old/shell"], scrollback: 54321, machine: {local: {label: "keep core"}}}
    | to toml | save $core
  {font_size: 9, personal: {nested: {keep: true}}, pane_scrollbars: true}
    | to json | save $settings
  {global: {cmd-t: "app.quit", f12: "app.help"}, terminal: {f11: "terminal.copy"}, personal: {nested: {keep: true}}}
    | to json | save $keys
  let rules = open ($root | path join .config/mise/config.macos.toml) | get dotfiles
    | transpose target rule
    | where {|entry| $entry.target =~ '^~/.config/herdr-(app|core)/' }
    | each {|entry|
        {target: ($entry.target | str replace "~/" $"($home)/"),
         rule: ($entry.rule | update source {|rule| $rule.source | str replace "~/.dotfiles/" $"($root)/" })}
      }
    | transpose --header-row --as-record
  {dotfiles: $rules} | to toml | save ($work | path join mise.toml)
  let before = contents $home
  with-env {
    HOME: $home, MISE_CONFIG_DIR: ($work | path join mise-config),
    MISE_DATA_DIR: ($work | path join mise-data), MISE_CACHE_DIR: ($work | path join mise-cache),
    MISE_STATE_DIR: ($work | path join mise-state), MISE_TRUSTED_CONFIG_PATHS: $work,
    MISE_GLOBAL_CONFIG_FILE: ($work | path join global.toml), MISE_SYSTEM_CONFIG_FILE: ($work | path join system.toml)
  } {
    cd $work
    let preview = ^$mise dot apply --dry-run | complete
    assert equal $preview.exit_code 0 $preview.stderr
    assert equal (contents $home) $before "mise dry-run changed target files"
    mut first = []
    for attempt in 1..2 {
      let result = ^$mise dot apply --yes | complete
      assert equal $result.exit_code 0 $result.stderr
      assert equal (open $core) {
        shell: [($home | path join .local/bin/nu-login)],
        scrollback: 54321, machine: {local: {label: "keep core"}}
      }
      assert equal (open $settings) ((open ($root | path join .config/herdr-app/settings.json))
        | insert personal {nested: {keep: true}})
      let expected = open ($root | path join .config/herdr-app/keys.json)
        | insert global.f12 "app.help" | insert terminal.f11 "terminal.copy"
        | insert personal {nested: {keep: true}}
      assert equal (open $keys) $expected
      let theme = $home | path join .config/herdr-app/themes/catppuccin-macchiato.json
      assert equal (open $theme) (open ($root | path join .config/herdr-app/themes/catppuccin-macchiato.json))
      let current = contents $home
      if $attempt == 1 { $first = $current } else {
        assert equal $current $first "Second apply must leave target bytes unchanged"
      }
      let status = ^$mise dot status --json | from json
      assert equal (($status.files | append $status.edits) | where state != applied) []
      assert equal (($status.files | length) + ($status.edits | length)) 4
    }
  }
  print "PASS real mise JSON/TOML merges preserve nested personal keys, resolve HOME, and repeat byte-stably"
}

def check-dry-run [work: path] {
  let home = $work | path join "dry home"
  let bin = $work | path join bin
  mkdir ($home | path join .config/herdr-app) $bin
  '{"personal":true}' | save ($home | path join .config/herdr-app/settings.json)
  let mock = '#!/bin/sh
set -eu
printf "%s\n" "$@" >> "$HERDR_TEST_LOG"
if [ "$*" != "--env macos dot apply --dry-run ~/.config/herdr-core/config.toml ~/.config/herdr-app/settings.json ~/.config/herdr-app/keys.json ~/.config/herdr-app/themes/catppuccin-macchiato.json" ]; then
  echo "unexpected mise operation" >&2
  exit 71
fi
'
  $mock | save ($bin | path join mise)
  ^chmod +x ($bin | path join mise)
  let log = $work | path join dry-calls
  let state = $work | path join dry-state
  with-env {
    HOME: $home, XDG_STATE_HOME: $state, HERDR_TEST_LOG: $log,
    PATH: ([$bin] | append $env.PATH)
  } {
    let keys = $home | path join .config/herdr-app/keys.json
    let personal = {command: pane.split, args: {direction: right}}
    {global: {cmd-alt-b: $personal}} | to json | save $keys
    let conflicting = contents $home
    let refused = ^$nu.current-exe --no-config-file ($root | path join scripts/herdr-desktop.nu) setup | complete
    assert ($refused.exit_code != 0) "setup must refuse retained fields on managed shortcuts"
    assert ($refused.stderr | str contains "Conflicting Herdr shortcut field global.cmd-alt-b.args.direction.") $refused.stderr
    assert (not ($log | path exists)) "conflicting shortcut reached mise"
    assert (not ($state | path exists)) "conflicting shortcut created a backup"
    assert equal (contents $home) $conflicting "preflight changed preferences"
    {global: {f12: $personal}} | to json | save --force $keys
    let before = contents $home
    for attempt in 1..2 {
      let result = ^$nu.current-exe --no-config-file ($root | path join scripts/herdr-desktop.nu) setup --dry-run | complete
      assert equal $result.exit_code 0 $result.stderr
      assert equal (contents $home) $before "setup dry-run changed preferences"
      assert (not ($state | path exists)) "setup dry-run created backup state"
    }
  }
  let expected = [--env macos dot apply --dry-run] | append $targets
  assert equal (open --raw $log | lines) ($expected | append $expected)
  print "PASS managed shortcut extra fields refuse before mise/backup; unrelated object chords accepted"
  print "PASS setup dry-run twice: only mise preview, no preference writes or backups"
}

def main [] {
  check-shortcuts
  let installed = check-catalog
  let mise = which mise | first | get path
  let work = mktemp -d
  try {
    check-merges $work $mise
    # setup resolves the system app before HOME's app; do not copy or launch it.
    if $installed and ("/Applications/Herdr.app/Contents/MacOS/Herdr" | path exists) {
      check-dry-run $work
    } else {
      print "SKIP setup dry-run: requires Herdr in /Applications"
    }
  } catch {|error|
    rm --recursive --force $work
    error make $error
  }
  rm --recursive --force $work
}

#!/usr/bin/env nu
use std/assert

const launcher = path self nu-login.sh

def exercise [work: path] {
  let home = $work | path join "GUI home"
  let custom = $work | path join "custom mise"
  let default = $home | path join .local/share/mise
  for data in [$default $custom] {
    let shim = $data | path join shims/nu
    mkdir ($shim | path dirname)
    '#!/bin/sh
printf "shim=<%s>\nconfig=<%s>\n" "$0" "$XDG_CONFIG_HOME"
printf "<%s>\n" "$@"
exit 37
' | save $shim
    ^chmod +x $shim
  }
  for case in [
    {name: unset, env: [], data: $default, config: ($home | path join .config)}
    {name: empty, env: [XDG_CONFIG_HOME= MISE_DATA_DIR=], data: $default, config: ($home | path join .config)}
    {name: preserved, env: ["XDG_CONFIG_HOME=/custom config" $"MISE_DATA_DIR=($custom)"], data: $custom, config: "/custom config"}
  ] {
    let result = ^/usr/bin/env -u XDG_CONFIG_HOME -u MISE_DATA_DIR $"HOME=($home)" ...$case.env /bin/sh $launcher --interactive -c "two words" "" | complete
    assert equal $result.exit_code 37 $"($case.name): child exit status must propagate"
    let expected = [
      $"shim=<($case.data | path join shims/nu)>"
      $"config=<($case.config)>"
      "<--login>" "<--interactive>" "<-c>" "<two words>" "<>"
    ] | str join (char newline)
    assert equal $result.stdout $"($expected)(char newline)" $"($case.name): launcher environment and argument boundaries"
    assert equal $result.stderr ""
    print $"PASS nu-login ($case.name): config path, shim selection, login argv, empty/spaced args, exit status"
  }
}

def main [] {
  let work = mktemp -d
  try { exercise $work } catch {|error|
    rm --recursive --force $work
    error make $error
  }
  rm --recursive --force $work
}

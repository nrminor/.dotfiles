#!/usr/bin/env nu
use std/assert

const root = path self ..
const packages = [.config/opencode/plugins/rex .config/pi/extensions/rex]

def calls [work: path] { open --raw ($work | path join calls) | lines }

def install [work: path, scenario: string] {
  "" | save --force ($work | path join calls)
  with-env {REX_CASE: $scenario} {
    ^$nu.current-exe --no-config-file ($work | path join scripts/install-rex-sdk.nu) | complete
  }
}

def assert-clean [work: path, revision: string] {
  assert (not ($work | path join .cache/rex-sdk $revision | path exists)) "Failed install published a cache"
  assert equal (glob ($work | path join .cache/rex-sdk/build.*)) [] "Temporary build leaked"
}

def exercise [work: path] {
  let revision = "0123456789abcdef0123456789abcdef01234567"
  let bin = $work | path join bin
  let source = $work | path join archive $"rex-sdk-($revision)"
  mkdir $bin ($work | path join scripts) ($work | path join .config/rex) ($source | path join node_modules/.bin)
  cp ($root | path join scripts/install-rex-sdk.nu) ($work | path join scripts)
  {name: rex-sdk, type: module, exports: "./dist/index.mjs"} | to json | save ($source | path join package.json)
  "Fixture license" | save ($source | path join LICENSE)
  let mock = '#!/bin/sh
set -eu
printf "%s %s\n" "${0##*/}" "$*" >> "$REX_WORK/calls"
case "${0##*/}" in
  curl)
    while [ "$#" -gt 0 ]; do
      if [ "$1" = --output ]; then cp "$REX_WORK/source.tar.gz" "$2"; exit 0; fi
      shift
    done
    exit 90 ;;
  tar) exec "$REX_TAR" "$@" ;;
  pnpm)
    if [ "$REX_CASE" = install-failure ]; then echo "fixture install refused" >&2; exit 71; fi ;;
  vp)
    if [ "$REX_CASE" = build-failure ]; then echo "fixture build refused" >&2; exit 72; fi
    mkdir dist
    printf "export const fixture = true;\n" > dist/index.mjs ;;
esac
'
  for name in [curl tar pnpm] {
    $mock | save ($bin | path join $name)
    ^chmod +x ($bin | path join $name)
  }
  $mock | save ($source | path join node_modules/.bin/vp)
  ^chmod +x ($source | path join node_modules/.bin/vp)
  let tar = which tar | first | get path
  ^$tar -czf ($work | path join source.tar.gz) -C ($work | path join archive) $"rex-sdk-($revision)"
  assert equal $env.LAST_EXIT_CODE 0
  let digest = open --raw ($work | path join source.tar.gz) | hash sha256
  let pin = {revision: $revision, sha256: $digest}
  let config = $work | path join .config/rex/sdk-source.json
  with-env {REX_WORK: $work, REX_TAR: $tar, PATH: ([$bin] | append $env.PATH)} {
    for invalid in [
      ($pin | update revision main)
      ($pin | update revision ("a" | fill --width 39 --character a))
      ($pin | update sha256 "not-a-digest")
    ] {
      $invalid | to json | save --force $config
      let result = install $work success
      assert ($result.exit_code != 0) "Invalid pin was accepted"
      assert ($result.stderr | str contains "exact revision and SHA-256") $result.stderr
      assert equal (calls $work) [] "Invalid pin reached external commands"
      assert-clean $work $revision
    }
    print "PASS invalid pins refuse before external commands"

    $pin | update sha256 ("0" | fill --width 64 --character 0) | to json | save --force $config
    let mismatch = install $work success
    assert ($mismatch.exit_code != 0)
    assert ($mismatch.stderr | str contains "checksum mismatch") $mismatch.stderr
    assert equal (calls $work | length) 1
    assert ((calls $work | first) | str starts-with "curl ")
    assert-clean $work $revision
    print "PASS checksum mismatch prevents extraction and execution, cleans temporary build"

    $pin | to json | save --force $config
    for scenario in [install-failure build-failure] {
      let result = install $work $scenario
      assert ($result.exit_code != 0) $"Ignored ($scenario)"
      let expected = if $scenario == install-failure { "fixture install refused" } else { "fixture build refused" }
      assert ($result.stderr | str contains $expected) $result.stderr
      assert equal (calls $work | where {|line| $line =~ '^vp ' } | length) (if $scenario == install-failure { 0 } else { 1 })
      assert-clean $work $revision
    }
    print "PASS install/build failures stop, publish nothing and clean temporary builds"

    let target = $work | path join .cache/rex-sdk $revision
    let built = install $work success
    assert equal $built.exit_code 0 $built.stderr
    assert equal (open --raw ($target | path join .source-sha256)) $digest
    for file in [dist/index.mjs package.json LICENSE] {
      assert ($target | path join $file | path exists) $"Published cache missing ($file)"
    }
    assert equal (calls $work | each {|line| $line | split row " " | first }) [curl tar pnpm vp]
    assert ("pnpm install --frozen-lockfile --ignore-scripts" in (calls $work))
    assert equal (glob ($work | path join .cache/rex-sdk/build.*)) []
    let reused = install $work success
    assert equal $reused.exit_code 0 $reused.stderr
    assert equal (calls $work) [] "Cache reuse downloaded or rebuilt SDK"
    print "PASS successful publication is complete; repeat install reuses cache offline"

    rm ($target | path join dist/index.mjs)
    let incomplete = install $work success
    assert ($incomplete.exit_code != 0)
    assert ($incomplete.stderr | str contains "Incomplete Rex SDK cache") $incomplete.stderr
    assert equal (calls $work) []
    "export {};" | save ($target | path join dist/index.mjs)
    "wrong digest" | save --force ($target | path join .source-sha256)
    let stale = install $work success
    assert ($stale.exit_code != 0)
    assert ($stale.stderr | str contains "Incomplete Rex SDK cache") $stale.stderr
    assert equal (calls $work) []
    print "PASS missing build output and mismatched cache digest are refused without downloads"
  }
}

def main [--offline] {
  let pin = open ($root | path join .config/rex/sdk-source.json)
  for package in $packages {
    let directory = $root | path join $package
    let dependency = open ($directory | path join package.json) | get dependencies.rex-sdk
    assert equal $dependency $"file:../../../../.cache/rex-sdk/($pin.revision)"
  }
  print "PASS both runtime manifests use the pinned generated SDK cache"
  let work = mktemp -d
  try {
    exercise $work
    if not $offline {
      for package in $packages {
        # Resolve exactly as each consumer does, without relying on the caller's cwd.
        let result = do {
          cd $work
          ^node --input-type=module -e 'import { createRequire } from "node:module"; import { pathToFileURL } from "node:url"; const require = createRequire(process.argv[1]); await import(pathToFileURL(require.resolve("rex-sdk")).href);' ($root | path join $package package.json) | complete
        }
        assert equal $result.exit_code 0 $result.stderr
      }
      print "PASS SDK imports from both consumer packages with unrelated cwd (no Rex connection)"
    }
  } catch {|error|
    rm --recursive --force $work
    error make $error
  }
  rm --recursive --force $work
}

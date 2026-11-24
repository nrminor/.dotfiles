const root = path self ..

def --wrapped checked [command: string, ...args: string] {
  ^$command ...$args
  if $env.LAST_EXIT_CODE != 0 {
    error make {msg: $"($command) failed with exit code ($env.LAST_EXIT_CODE)"}
  }
}

def main [] {
  let pin = open ($root | path join .config/rex/sdk-source.json)
  if $pin.revision !~ '^[a-f0-9]{40}$' or $pin.sha256 !~ '^[a-f0-9]{64}$' {
    error make {msg: "Rex SDK requires an exact revision and SHA-256."}
  }
  let cache = $root | path join .cache/rex-sdk
  let target = $cache | path join $pin.revision
  if ($target | path exists) {
    if (
      (open --raw ($target | path join .source-sha256) | str trim) != $pin.sha256
      or not ($target | path join dist/index.mjs | path exists)
    ) {
      error make {msg: $"Incomplete Rex SDK cache: remove ($target) and rerun deps:install."}
    }
    print $"Rex SDK ($pin.revision) already built."
    return
  }

  mkdir $cache
  let work = mktemp --directory --tmpdir-path $cache build.XXXXXX
  try {
    let archive = $work | path join source.tar.gz
    checked curl --fail --location --silent --show-error --max-time 120 (
      $"https://codeload.github.com/dmmulroy/rex-sdk/tar.gz/($pin.revision)"
    ) --output $archive
    if (open --raw $archive | hash sha256) != $pin.sha256 {
      error make {msg: "Rex SDK archive checksum mismatch; refusing to build."}
    }
    checked tar -xzf $archive -C $work
    let source = $work | path join $"rex-sdk-($pin.revision)"
    do {
      cd $source
      # Upstream prepare configures development hooks, not the SDK distribution.
      checked pnpm install --frozen-lockfile --ignore-scripts
      checked ./node_modules/.bin/vp pack
    }
    let package = $work | path join package
    mkdir $package
    cp --recursive ($source | path join dist) $package
    cp ($source | path join package.json) ($source | path join LICENSE) $package
    $pin.sha256 | save ($package | path join .source-sha256)
    # rename fails rather than nesting a second build in an existing cache.
    checked node --input-type=module -e (
      'import { renameSync } from "node:fs"; renameSync(process.argv[1], process.argv[2]);'
    ) $package $target
  } catch {|err|
    rm --recursive --force $work
    error make {msg: $err.msg}
  }
  rm --recursive --force $work
  print $"Built Rex SDK ($pin.revision)."
}

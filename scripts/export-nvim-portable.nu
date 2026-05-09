#!/usr/bin/env nu

# Export the nixvim-generated Neovim config into a relocatable bundle.
# This script runs in the local dotfiles environment, where Nix and Nushell are
# available. The generated bundle uses only POSIX sh at runtime and expects
# Neovim plus language servers, formatters, and search tools to be available on
# PATH on the target machine.

const nixvim_config_attr = ".#darwinConfigurations.starter.config.home-manager.users.nickminor.programs.nixvim"
const xdg_config_attr = ".#darwinConfigurations.starter.config.home-manager.users.nickminor.xdg.configFile"

def log-info [message: string] {
  print $"ℹ ($message)"
}

def log-success [message: string] {
  print $"✓ ($message)"
}

def fail [message: string] {
  error make { msg: $message }
}

def nix-eval-raw [flake_dir: path attr: string] {
  let result = (
    do {
      cd $flake_dir
      ^nix eval --raw $attr
    } | complete
  )

  if $result.exit_code != 0 {
    fail $"nix eval failed for ($attr):\n($result.stderr)"
  }

  $result.stdout | str trim
}

def nix-eval-json-attr-names [flake_dir: path attr: string] {
  let result = (
    do {
      cd $flake_dir
      ^nix eval --json $attr --apply builtins.attrNames
    } | complete
  )

  if $result.exit_code != 0 {
    fail $"nix eval failed for ($attr) attr names:\n($result.stderr)"
  }

  $result.stdout | from json
}

def nix-build-output [flake_dir: path attr: string] {
  let result = (
    do {
      cd $flake_dir
      ^nix build --no-link --print-out-paths $attr
    } | complete
  )

  if $result.exit_code != 0 {
    fail $"nix build failed for ($attr):\n($result.stderr)"
  }

  $result.stdout | lines | where {|line| not ($line | is-empty) } | last
}

def recreate-dir [dir: path] {
  if ($dir | path exists) {
    ^chmod -R u+w $dir
    rm --recursive --force $dir
  }
  mkdir $dir
}

def copy-dereference [source: path target: path] {
  let parent = ($target | path dirname)
  mkdir $parent
  ^cp -R -L $source $target
}

def find-pack-dir [nixvim_package: path] {
  let wrapper = ($nixvim_package | path join "bin" "nvim")

  if not ($wrapper | path exists) {
    fail $"nixvim wrapper not found at ($wrapper)"
  }

  let matches = (
    open --raw $wrapper
    | parse --regex '(?P<pack_dir>/nix/store/[^" ]+-vim-pack-dir)'
  )

  if ($matches | is-empty) {
    fail $"Could not find vim-pack-dir in ($wrapper)"
  }

  $matches | get pack_dir | first
}

def copy-generated-config-files [flake_dir: path config_nvim_dir: path] {
  let names = (nix-eval-json-attr-names $flake_dir $xdg_config_attr)

  for name in $names {
    if not ($name | str starts-with "nvim/") {
      continue
    }

    if $name == "nvim/init.lua" {
      continue
    }

    let source_attr = $'($xdg_config_attr)."($name)".source'
    let source = (nix-eval-raw $flake_dir $source_attr)
    let relative = ($name | str replace "nvim/" "")
    let target = ($config_nvim_dir | path join $relative)
    copy-dereference $source $target
  }
}

def copy-plugin-pack [pack_dir: path data_dir: path] {
  let source_start = ($pack_dir | path join "pack" "myNeovimPackages" "start")
  let target_start = ($data_dir | path join "nvim" "site" "pack" "portable" "start")

  if not ($source_start | path exists) {
    fail $"Plugin pack start directory not found at ($source_start)"
  }

  mkdir $target_start

  for entry in (ls $source_start) {
    copy-dereference $entry.name ($target_start | path join ($entry.name | path basename))
  }
}

def copy-snippets [dotfiles_dir: path config_nvim_dir: path] {
  let source = ($dotfiles_dir | path join ".config" "neovim" "plugins" "snippets")
  let target = ($config_nvim_dir | path join "snippets")

  if ($source | path exists) {
    copy-dereference $source $target
  }
}

def sanitize-init [init_path: path] {
  ^chmod u+w $init_path

  let sanitized = (
    open --raw $init_path
    | str replace --regex 'vim\.g\.ruby_host_prog = "/nix/store/[^"]+"\n' "vim.g.loaded_ruby_provider = 0\n"
    | str replace --regex 'vim\.g\.python3_host_prog = "/nix/store/[^"]+"\n' "vim.g.loaded_python3_provider = 0\n"
    | str replace --regex --all '"/nix/store/[a-z0-9]+-[^"]*snippets"' 'vim.fn.stdpath("config") .. "/snippets"'
    | str replace --regex --all '/nix/store/[a-z0-9]+-oxlint-wrapper' 'oxlint'
    | str replace --regex --all '/nix/store/[a-z0-9]+-[^"\s]+/bin/([^"/\s]+)' '$1'
  )

  $sanitized | save --force $init_path

  let remaining = (
    open --raw $init_path
    | lines
    | where {|line| $line | str contains "/nix/store/" }
  )

  if not ($remaining | is-empty) {
    print "⚠ init.lua still contains Nix store references:"
    $remaining | first 20 | each {|line| print $"  ($line)" }
  }
}

def write-launcher [out_dir: path] {
  let bin_dir = ($out_dir | path join "bin")
  let launcher = ($bin_dir | path join "nvim-portable")
  let launcher_content = ([
    "#!/usr/bin/env sh"
    "set -eu"
    ""
    'script_dir=$(CDPATH= cd "$(dirname "$0")" && pwd)'
    'bundle_dir=$(CDPATH= cd "$script_dir/.." && pwd)'
    ""
    'export XDG_CONFIG_HOME="$bundle_dir/config"'
    'export XDG_DATA_HOME="$bundle_dir/data"'
    'export XDG_STATE_HOME="$bundle_dir/state"'
    'export XDG_CACHE_HOME="$bundle_dir/cache"'
    ""
    'exec nvim "$@"'
    ""
  ] | str join "\n")

  mkdir $bin_dir
  $launcher_content | save --force $launcher

  ^chmod +x $launcher
}

def archive-bundle [out_dir: path] {
  let parent = ($out_dir | path dirname)
  let name = ($out_dir | path basename)
  let archive = ($parent | path join $"($name).tar.gz")

  if ($archive | path exists) {
    rm --force $archive
  }

  ^tar -C $parent -czf $archive $name
  log-success $"Wrote archive to ($archive)"
}

def main [
  --dotfiles-dir: path
  --flake-dir: path
  --out-dir: path
  --archive
] {
  if ($dotfiles_dir | is-empty) {
    fail "--dotfiles-dir is required"
  }

  if ($flake_dir | is-empty) {
    fail "--flake-dir is required"
  }

  if ($out_dir | is-empty) {
    fail "--out-dir is required"
  }

  log-info "Evaluating nixvim outputs"
  let init_source = (nix-eval-raw $flake_dir $"($nixvim_config_attr).build.initFile")
  let nixvim_package = (nix-build-output $flake_dir $"($nixvim_config_attr).build.package")
  let pack_dir = (find-pack-dir $nixvim_package)

  log-info $"Recreating export directory at ($out_dir)"
  recreate-dir $out_dir

  let config_nvim_dir = ($out_dir | path join "config" "nvim")
  let data_dir = ($out_dir | path join "data")

  mkdir $config_nvim_dir
  mkdir ($out_dir | path join "state")
  mkdir ($out_dir | path join "cache")

  log-info "Copying generated init.lua"
  copy-dereference $init_source ($config_nvim_dir | path join "init.lua")

  log-info "Copying generated config extras"
  copy-generated-config-files $flake_dir $config_nvim_dir

  log-info "Copying LuaSnip snippets"
  copy-snippets $dotfiles_dir $config_nvim_dir

  log-info "Copying plugin pack"
  copy-plugin-pack $pack_dir $data_dir

  log-info "Sanitizing generated init.lua"
  sanitize-init ($config_nvim_dir | path join "init.lua")

  log-info "Writing POSIX launcher"
  write-launcher $out_dir

  if $archive {
    archive-bundle $out_dir
  }

  log-success $"Portable Neovim bundle written to ($out_dir)"
  print $"Run it with: ($out_dir | path join "bin" "nvim-portable")"
}

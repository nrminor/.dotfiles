# theme.nu
#
# Runtime theme authority for terminal tools and Neovim.
#
# This module resolves the effective theme mode using the following precedence:
#   1. Manual override written by `theme set light` or `theme set dark`
#   2. macOS appearance via `defaults read -g AppleInterfaceStyle`
#
# The exported `theme ...` commands are intended for interactive use from Nushell
# and for non-interactive use via `nu ~/.config/nushell/theme.nu ...`.

def theme-state-dir [] {
  $env.HOME | path join ".local" "state" "theme"
}

def theme-override-path [] {
  theme-state-dir | path join "override.nuon"
}

def ensure-theme-state-dir [] {
  let dir = (theme-state-dir)
  if not ($dir | path exists) {
    mkdir $dir
  }
}

def theme-system-mode [] {
  let result = (do -i { ^defaults read -g AppleInterfaceStyle } | complete)
  if $result.exit_code == 0 and ($result.stdout | str trim) == "Dark" {
    "dark"
  } else {
    "light"
  }
}

def theme-effective-mode [] {
  let override_path = (theme-override-path)

  if ($override_path | path exists) {
    open $override_path | get mode
  } else {
    theme-system-mode
  }
}

def theme-btop-name [] {
  if (theme-effective-mode) == "dark" {
    "catppuccin-macchiato"
  } else {
    "catppuccin-latte"
  }
}

def refresh-bat-theme [] {
  $env.BAT_THEME = (theme get bat)
}

def sync-btop-theme [] {
  let themes_dir = ($env.HOME | path join ".config" "btop" "themes")
  let theme_name = (theme-btop-name)
  let source = ($themes_dir | path join $"($theme_name).theme")
  let target = ($themes_dir | path join "current.theme")

  if not ($themes_dir | path exists) {
    mkdir $themes_dir
  }

  if not ($source | path exists) {
    error make { msg: $"Missing btop theme file: ($source)" }
  }

  ^ln -sfn $source $target
}

def sync-yazi-theme [] {
  let flavors_dir = ($env.HOME | path join ".config" "yazi" "flavors")
  let latte = ($flavors_dir | path join "catppuccin-latte.yazi")
  let macchiato = ($flavors_dir | path join "catppuccin-macchiato.yazi")
  let current_dark = ($flavors_dir | path join "current-dark.yazi")
  let current_light = ($flavors_dir | path join "current-light.yazi")

  if not ($flavors_dir | path exists) {
    mkdir $flavors_dir
  }

  if not ($latte | path exists) {
    error make { msg: $"Missing Yazi flavor: ($latte)" }
  }

  if not ($macchiato | path exists) {
    error make { msg: $"Missing Yazi flavor: ($macchiato)" }
  }

  if (theme source) == "override" {
    let selected = if (theme-effective-mode) == "dark" { $macchiato } else { $latte }
    ^ln -sfn $selected $current_dark
    ^ln -sfn $selected $current_light
  } else {
    ^ln -sfn $macchiato $current_dark
    ^ln -sfn $latte $current_light
  }
}

# Return the effective theme mode.
#
# This is the main entry point other tools should consult. It returns only one of
# two valid values:
#   - "light"
#   - "dark"
export def "theme mode" [] {
  theme-effective-mode
}

# Report where the effective theme mode came from.
#
# Valid values:
#   - "override" when `theme set` has written a manual override
#   - "system" when the current mode is inherited from macOS appearance
export def "theme source" [] {
  let override_path = (theme-override-path)
  if ($override_path | path exists) {
    "override"
  } else {
    "system"
  }
}

# Map the effective theme mode to a tool-specific theme name.
#
# Valid tool names:
#   - "bat"
#   - "btop"
#   - "nvim"
#   - "yazi-dark"
#   - "yazi-light"
#
# Any other value is rejected.
export def "theme get" [tool: string] {
  let mode = (theme-effective-mode)

  match $tool {
    "bat" => {
      if $mode == "dark" { "Catppuccin Macchiato" } else { "Catppuccin Latte" }
    }
    "btop" => { theme-btop-name }
    "nvim" => {
      if $mode == "dark" { "macchiato" } else { "latte" }
    }
    "yazi-dark" => {
      if (theme source) == "override" {
        if $mode == "dark" { "catppuccin-macchiato" } else { "catppuccin-latte" }
      } else {
        "catppuccin-macchiato"
      }
    }
    "yazi-light" => {
      if (theme source) == "override" {
        if $mode == "dark" { "catppuccin-macchiato" } else { "catppuccin-latte" }
      } else {
        "catppuccin-latte"
      }
    }
    _ => {
      error make { msg: $"unknown theme target: ($tool)" }
    }
  }
}

# Show a summary of the current effective theme state and derived tool mappings.
export def "theme status" [] {
  {
    mode: (theme mode)
    source: (theme source)
    system: (theme-system-mode)
    bat: (theme get bat)
    btop: (theme get btop)
    nvim: (theme get nvim)
    yazi_dark: (theme get yazi-dark)
    yazi_light: (theme get yazi-light)
  }
}

# Synchronize runtime-selected theme artifacts used by tools that read files or
# symlinks at launch time.
#
# Valid targets:
#   - omitted or "all": sync btop and yazi runtime selections
#   - "btop": sync only ~/.config/btop/themes/current.theme
#   - "yazi": sync only ~/.config/yazi/flavors/current-{dark,light}.yazi
export def "theme sync" [target?: string] {
  match $target {
    null => {
      sync-btop-theme
      sync-yazi-theme
    }
    "all" => {
      sync-btop-theme
      sync-yazi-theme
    }
    "btop" => { sync-btop-theme }
    "yazi" => { sync-yazi-theme }
    _ => {
      error make { msg: $"unknown sync target: ($target)" }
    }
  }
}

# Override the entire runtime theme system.
#
# Valid mode values:
#   - "light"
#   - "dark"
#
# This writes override state under ~/.local/state/theme and immediately refreshes
# the current shell's BAT_THEME plus any runtime symlinks for btop and yazi.
export def --env "theme set" [mode: string] {
  if $mode not-in ["light" "dark"] {
    error make { msg: "theme set expects 'light' or 'dark'" }
  }

  ensure-theme-state-dir
  { mode: $mode } | save -f (theme-override-path)
  refresh-bat-theme
  theme sync all
  theme status
}

# Clear any manual override and return control to macOS appearance.
#
# This also refreshes the current shell's BAT_THEME plus runtime symlinks for
# btop and yazi.
export def --env "theme clear" [] {
  let override_path = (theme-override-path)
  if ($override_path | path exists) {
    rm $override_path
  }

  refresh-bat-theme
  theme sync all
  theme status
}

def main [...args: string] {
  match $args {
    ["mode"] => { theme mode }
    ["source"] => { theme source }
    ["status"] => { theme status }
    ["get", $tool] => { theme get $tool }
    ["sync"] => { theme sync all }
    ["sync", $target] => { theme sync $target }
    ["set", $mode] => { theme set $mode }
    ["clear"] => { theme clear }
    _ => {
      error make {
        msg: "Usage: nu ~/.config/nushell/theme.nu [mode|source|status|get <tool>|sync [target]|set <light|dark>|clear]"
      }
    }
  }
}

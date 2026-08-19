# macOS application and nix-darwin commands loaded through Nushell's vendor autoload directory.

export alias o. = ^open .
export alias bearcli = /Applications/Bear.app/Contents/MacOS/bearcli
export alias bear = bearcli

# Update nix flake and rebuild system.
#
# Updates flake.lock inputs and rebuilds the system configuration.
# Use --dry-run to build without activating (no sudo required).
#
# Examples:
#   > sysupdate              # Update flake and rebuild system
#   > sysupdate --dry-run    # Update flake and build without activating
export def sysupdate [
  --dry-run (-n) # Build without activating (no sudo required)
] {
  let flake_dir = $env.HOME | path join ".dotfiles" ".config" "nix"

  print "Updating nix flake..."
  ^nix flake update --flake $flake_dir

  if $dry_run {
    print "Building system (dry run)..."
    ^darwin-rebuild build --flake $"($flake_dir)#starter"
    print "[ok] Build succeeded (no changes applied)"
  } else {
    print "Rebuilding system..."
    ^sudo darwin-rebuild switch --flake $"($flake_dir)#starter"
    print "[ok] System updated and rebuilt"
  }
}

# Display nix system health and storage information.
#
# Shows system status including flake info and generations.
# Use --store to show nix store size (slow).
# Use --gc to scan for reclaimable space (very slow).
# Use --check to validate the flake.
#
# Examples:
#   > syscheck                  # Show system status (fast)
#   > syscheck --store          # Include store size (slow)
#   > syscheck --gc             # Include garbage collection analysis (very slow)
#   > syscheck --check          # Also run nix flake check
#   > syscheck --store --gc -c  # Full analysis
export def syscheck [
  --check (-c) # Also run nix flake check to validate flake
  --store (-s) # Show nix store size (slow)
  --gc (-g) # Scan for reclaimable space (very slow)
] {
  let flake_dir = $env.HOME | path join ".dotfiles" ".config" "nix"
  let flake_lock = $flake_dir | path join "flake.lock"

  print "==================================================================="
  print "                       nix system status"
  print "==================================================================="
  print ""

  print "[flake]"
  print $"  location: ($flake_dir)"
  if ($flake_lock | path exists) {
    let lock_info = (ls -l $flake_lock | first)
    let lock_age = ($lock_info.modified | into int) / 1_000_000_000
    let now = (date now | into int) / 1_000_000_000
    let age_days = (($now - $lock_age) / 86400 | math floor)
    print $"  lock age: ($age_days) days"
  }
  print ""

  print "[current system]"
  let system_link = "/nix/var/nix/profiles/system"
  if ($system_link | path exists) {
    let current = (ls -l $system_link | first | get target | path basename)
    let gen_num = ($current | parse "system-{num}-link" | get 0?.num? | default "unknown")
    let current_target = (^readlink "/run/current-system" | str trim)
    print $"  generation: ($gen_num)"
    print $"  store path: ($current_target | path basename)"
  }
  print ""

  print "[generations]"
  let gen_links = (ls /nix/var/nix/profiles/system-*-link | length)
  print $"  total: ($gen_links)"
  let recent = (ls -l /nix/var/nix/profiles/system-*-link | sort-by modified | last 3 | reverse)
  print "  recent:"
  $recent | each {|generation|
    let name = ($generation.name | path basename)
    let num = ($name | parse "system-{num}-link" | get 0?.num? | default "?")
    let age = ($generation.modified | date humanize)
    print $"    gen ($num): ($age)"
  }

  if $store {
    print ""
    print "[nix store]"
    let store_size = (^du -sh /nix/store | split row "\t" | first | str trim)
    print $"  total size: ($store_size)"
  }

  if $gc {
    print ""
    print "[garbage collection]"
    print "  scanning for reclaimable paths..."
    let dead_paths = (^nix-store --gc --print-dead err> /dev/null | lines)
    let dead_count = ($dead_paths | length)
    print $"  reclaimable paths: ($dead_count)"
    if $dead_count > 0 {
      let sample = ($dead_paths | first ([$dead_count 100] | math min))
      let sample_sizes = (
        $sample | each {|path|
          let info = (^nix path-info -S $path err> /dev/null | str trim | split row "\t")
          if ($info | length) >= 2 {
            $info | get 1 | into int
          } else {
            0
          }
        }
      )
      let sample_total = ($sample_sizes | math sum)
      let estimated_total = if $dead_count > 100 {
        ($sample_total * $dead_count / 100)
      } else {
        $sample_total
      }
      let human_size = if $estimated_total > 1073741824 {
        $"~(($estimated_total / 1073741824 | math round --precision 1))GB"
      } else if $estimated_total > 1048576 {
        $"~(($estimated_total / 1048576 | math round --precision 0))MB"
      } else {
        $"~(($estimated_total / 1024 | math round --precision 0))KB"
      }
      print $"  estimated reclaimable: ($human_size)"
      print "  hint: run 'nix-collect-garbage -d' to reclaim space"
    } else {
      print "  store is clean"
    }
  }

  if $check {
    print ""
    print "[flake validation]"
    print "  running nix flake check..."
    let check_result = (do { ^nix flake check $flake_dir } | complete)
    if $check_result.exit_code == 0 {
      print "  [ok] flake check passed"
    } else {
      print "  [error] flake check failed"
      print $check_result.stderr
    }
  }

  print ""
  print "==================================================================="
}

# Remind interactive macOS shells when the system flake lock is stale.
if (which nix | is-not-empty) {
  let flake_dir = $env.XDG_CONFIG_HOME | path join "nix"
  let flake_lock = $flake_dir | path join "flake.lock"

  if ($flake_lock | path exists) {
    let real_lock = $flake_lock | path expand
    let lock_info = ls -l $real_lock | first
    let lock_age = ($lock_info.modified | into int) / 1_000_000_000
    let now = (date now | into int) / 1_000_000_000
    let age_days = (($now - $lock_age) / 86400 | math floor)

    if $age_days > 7 {
      print $"💡 Tip: Your nix flake hasn't been updated in ($age_days) days."
      print "   Run: sysupdate"
    }
  }
}

const plugin_names = [
    nu_plugin_polars
    nu_plugin_query
    nu_plugin_gstat
    nu_plugin_formats
]

def nushell-install-root []: nothing -> string {
    if "MISE_TOOL_INSTALL_PATH" in $env {
        $env.MISE_TOOL_INSTALL_PATH | path expand
    } else {
        ^mise where aqua:nushell/nushell | str trim | path expand
    }
}

def bundled-plugin [install_root: path, name: string]: nothing -> string {
    let executable = if $nu.os-info.name == "windows" { $"($name).exe" } else { $name }
    let matches = glob ($install_root | path join "**" $executable)

    if ($matches | length) != 1 {
        error make {
            msg: $"Expected exactly one ($executable) under ($install_root)"
            help: $"Found ($matches | length): ($matches | str join ', ')"
        }
    }

    $matches.0
}

# Synchronize plugin support with the active mise-managed Nushell release.
#
# Finds the core plugin binaries bundled with Nushell, validates them with the
# active `nu`, and atomically replaces `plugin.msgpackz`. Mise runs this command
# automatically after installing or updating Nushell; run it manually to repair
# or refresh plugin registration. Start a new Nushell process afterward to load
# the refreshed command signatures.
#
# Examples:
#   > nu plugins sync
#   > mise run nu:plugins
export def "nu plugins sync" []: nothing -> nothing {
    let install_root = nushell-install-root
    let plugins = $plugin_names | each {|name| bundled-plugin $install_root $name }
    let config_home = $env.XDG_CONFIG_HOME? | default ($env.HOME | path join ".config")
    let registry_dir = $config_home | path join "nushell"
    let registry = $registry_dir | path join "plugin.msgpackz"
    let staged = $registry_dir | path join $"plugin.msgpackz.($nu.pid).tmp"

    mkdir $registry_dir
    rm --force $staged

    try {
        for plugin in $plugins {
            plugin add --plugin-config $staged $plugin
        }
        mv --force $staged $registry
    } catch {|error|
        rm --force $staged
        error make $error.raw
    }

    print $"Registered ($plugin_names | str join ', ') for Nushell ((version).version)."
    print "Restart Nushell to load the refreshed plugin commands."
}

def main []: nothing -> nothing {
    nu plugins sync
}

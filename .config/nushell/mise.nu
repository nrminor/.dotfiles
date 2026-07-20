def "parse vars" [] {
  $in | from csv --noheaders --no-infer | rename op name value
}

def --env "update-env" [] {
  for var in $in {
    if $var.op == "set" {
      if ($var.name | str uppercase) == "PATH" {
        $env.PATH = ($var.value | split row (char esep))
      } else {
        load-env {($var.name): $var.value}
      }
    } else if $var.op == "hide" and $var.name in $env {
      hide-env $var.name
    }
  }
}

def --env add-hook [field: cell-path new_hook: any] {
  let field = $field | split cell-path | update optional true | into cell-path
  let old_config = $env.config? | default {}
  let old_hooks = $old_config | get $field | default []
  $env.config = ($old_config | upsert $field ($old_hooks ++ [$new_hook]))
}

def --env mise_hook [] {
  ^mise hook-env -s nu
  | parse vars
  | update-env
}

def "mise usage spec path" [] {
  $nu.cache-dir | path join "mise.usage.kdl"
}

def "mise ensure usage spec" [] {
  let spec_file = (mise usage spec path)

  if not ($spec_file | path exists) {
    ^mise usage | save --force $spec_file
  }

  $spec_file
}

def mise_completer [spans: list<string>] {
  if (which usage | is-empty) {
    return []
  }

  let spec_file = (mise ensure usage spec)

  ^usage complete-word -f $spec_file --shell nu -- ...$spans
  | lines
  | each {|line|
    let parts = ($line | split row "\t")
    let description = if ($parts | length) > 1 { $parts.1 } else { "" }

    {value: $parts.0 description: $description}
  }
}

export-env {
  $env.MISE_SHELL = "nu"
  mise_hook

  let hook = {
    condition: { "MISE_SHELL" in $env }
    code: { mise_hook }
  }

  add-hook hooks.pre_prompt $hook
  add-hook hooks.env_change.PWD $hook
}

@complete mise_completer
export def --env --wrapped main [command?: string --help ...rest: string] {
  let env_commands = ["deactivate" "shell" "sh"]

  if $command == null {
    ^mise
  } else if $command == "activate" {
    $env.MISE_SHELL = "nu"
  } else if $command in $env_commands {
    ^mise $command ...$rest
    | parse vars
    | update-env
  } else {
    ^mise $command ...$rest
  }
}

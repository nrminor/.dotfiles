#!/usr/bin/env nu

def osc52-copy [text: string] {
  let payload = $text | encode base64
  let sequence = [(char --unicode "1b") "]52;c;" $payload (char bel)] | str join
  print -n $sequence
}

def main [] {
  let text = open --raw /dev/stdin | decode utf-8

  if ("SSH_TTY" in $env) or ("SSH_CONNECTION" in $env) {
    osc52-copy $text
  } else if $nu.os-info.name == "macos" and (which pbcopy | is-not-empty) {
    $text | ^pbcopy
  } else if ("WAYLAND_DISPLAY" in $env) and (which wl-copy | is-not-empty) {
    $text | ^wl-copy
  } else if ("DISPLAY" in $env) and (which xclip | is-not-empty) {
    $text | ^xclip -selection clipboard
  } else {
    error make { msg: "No clipboard provider is available" }
  }
}

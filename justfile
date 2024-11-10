@default:
    just --list

alias ext := install-positron-extensions
alias extensions := install-positron-extensions

install-positron-extensions:
    bat -pP ~/.dotfiles/.config/positron/extensions.txt | xargs -L 1 positron --install-extension

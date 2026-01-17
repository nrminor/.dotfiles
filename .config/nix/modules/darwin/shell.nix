# Shell configuration
#
# Zsh setup with plugins for SSH sessions and fallback use.
# The actual dotfiles (.zshrc, etc.) are managed by dotter.
# Direnv is configured in home-manager (modules/home/programs.nix).
{ pkgs, ... }:

{
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    promptInit = "";

    interactiveShellInit = ''
      source ${pkgs.zsh-autosuggestions}/share/zsh-autosuggestions/zsh-autosuggestions.zsh
      source ${pkgs.zsh-syntax-highlighting}/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
    '';
  };
}

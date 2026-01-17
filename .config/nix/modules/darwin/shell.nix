# Shell configuration
#
# Zsh setup with plugins. The actual dotfiles (.zshrc, etc.)
# are managed by dotter; this module ensures zsh and its
# plugins are installed and integrated.
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

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };
}

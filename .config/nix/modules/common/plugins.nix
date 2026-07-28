# Common plugin lists
#
# Yazi plugins to symlink during system activation.
{ pkgs }:

{
  yazi = with pkgs.yaziPlugins; [
    sudo
    starship
    rsync
    ouch
    smart-filter
    smart-enter
    mount
    mediainfo
    chmod
    git
    lazygit
  ];
}

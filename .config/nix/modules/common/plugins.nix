# Common plugin lists
#
# Lists of plugins for tools like Yazi and Nushell. This is pure data -
# it returns an attribute set of lists. The consuming module decides
# how to install/symlink them.
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
    duckdb
  ];

  nushell = with pkgs.nushellPlugins; [
    polars
    query
    highlight
    gstat
    formats
  ];
}

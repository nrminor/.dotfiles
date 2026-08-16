let
  jjDescriptionOpts = {
    extraConfigVim =
      # vimscript
      ''
        " Disable hard wrapping while typing commit descriptions.
        setlocal textwidth=0
        setlocal formatoptions-=t
      '';
  };
in
{
  files = {
    "after/ftplugin/jjdescription.vim" = jjDescriptionOpts;
  };
}

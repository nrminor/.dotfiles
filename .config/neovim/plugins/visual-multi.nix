{ pkgs, ... }:
{
  globals.VM_maps = {
    "Add Cursor Down" = "<M-j>";
    "Add Cursor Up" = "<M-k>";
  };

  extraConfigVim = ''
    nmap <M-Down> <Plug>(VM-Add-Cursor-Down)
    nmap <M-Up> <Plug>(VM-Add-Cursor-Up)
  '';

  extraPlugins = [
    pkgs.vimPlugins.vim-visual-multi
  ];
}

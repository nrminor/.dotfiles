vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1
vim.g.no_ocaml_maps = 1
vim.g.floating_window_options = { border = "rounded", winblend = 10 }

vim.opt_global.statusline = "%#Normal#"

local options = {
	number = true,
	relativenumber = true,
	numberwidth = 2,
	showmode = false,
	tabstop = 2,
	softtabstop = 2,
	expandtab = true,
	smartindent = true,
	shiftwidth = 2,
	breakindent = true,
	linebreak = true,
	list = false,
	wrap = true,
	incsearch = true,
	hlsearch = true,
	splitbelow = true,
	splitright = true,
	splitkeep = "screen",
	colorcolumn = "88",
	mouse = "a",
	ignorecase = true,
	smartcase = true,
	updatetime = 250,
	completeopt = { "menu", "menuone", "noselect" },
	undofile = true,
	termguicolors = true,
	signcolumn = "yes",
	clipboard = "unnamed,unnamedplus",
	cursorline = true,
	scrolloff = 10,
	timeoutlen = 400,
	winborder = "rounded",
	showtabline = 2,
}

for name, value in pairs(options) do
	vim.opt[name] = value
end

vim.diagnostic.config({
	virtual_text = false,
	signs = true,
	underline = true,
	severity_sort = true,
	float = { border = "rounded", source = "always" },
})

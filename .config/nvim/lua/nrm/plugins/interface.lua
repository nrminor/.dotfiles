local function packadd(name)
	vim.cmd.packadd(name)
end

local function map(lhs, rhs, desc)
	vim.keymap.set("n", lhs, rhs, { desc = desc, silent = true })
end

packadd("catppuccin")
require("catppuccin").setup({
	flavour = "auto",
	background = { light = "latte", dark = "macchiato" },
	transparent_background = true,
	no_bold = true,
	no_italic = true,
	integrations = {
		blink_cmp = true,
		gitsigns = true,
		indent_blankline = { enabled = false, scope_color = "sapphire", colored_indent_levels = false },
		native_lsp = { enabled = true },
		symbols_outline = true,
		telescope = true,
		treesitter = true,
		treesitter_context = true,
	},
})
vim.cmd.colorscheme("catppuccin")

for _, theme in ipairs({ "deepwhite.nvim", "everforest", "miasma.nvim", "vim-frign", "quietlight.vim" }) do
	packadd(theme)
end

packadd("nvim-web-devicons")
require("nvim-web-devicons").setup()

packadd("bufferline.nvim")
require("bufferline").setup({
	options = {
		mode = "buffers",
		diagnostics = "nvim_lsp",
		show_buffer_close_icons = false,
		show_close_icon = false,
		always_show_bufferline = true,
		separator_style = "thin",
		offsets = { { filetype = "oil", text = "File Explorer", highlight = "Directory", separator = true } },
	},
})
vim.o.showtabline = 2

packadd("lualine.nvim")
require("lualine").setup({
	options = {
		theme = "auto",
		globalstatus = true,
		component_separators = { left = "", right = "" },
		section_separators = { left = "█", right = "█" },
	},
	sections = {
		lualine_a = { "mode" },
		lualine_b = { { "branch", icon = "" } },
		lualine_c = { { "filename", path = 1, symbols = { modified = "[+]", readonly = "[RO]" } } },
		lualine_x = { "diagnostics", "selectioncount" },
		lualine_y = {
			"location",
			"progress",
			function()
				return vim.api.nvim_buf_line_count(0) .. "L"
			end,
		},
		lualine_z = { "filetype" },
	},
})

packadd("which-key.nvim")
require("which-key").setup({
	delay = 300,
	icons = { breadcrumb = "»", separator = "→" },
	win = {
		border = "rounded",
		padding = { 1, 2 },
		col = vim.o.columns,
		row = math.huge,
		width = math.floor(vim.o.columns * 0.4),
		height = { min = 4, max = 20 },
	},
	layout = { width = { min = 20 }, spacing = 3 },
	spec = {
		{ "<leader>f", group = "Find" },
		{ "<leader>g", group = "Git" },
		{ "<leader>h", group = "VCS hunks" },
		{ "<leader>l", group = "LSP" },
		{ "<leader>t", group = "Toggle" },
		{ "<leader>w", group = "Window" },
		{ "<leader><tab>", group = "Tabs" },
		{ "<leader>d", group = "Diagnostics/Dadbod" },
	},
})

packadd("snacks.nvim")
local Snacks = require("snacks")
Snacks.setup({
	input = { enabled = true },
	indent = {
		enabled = true,
		indent = { enabled = false },
		scope = { hl = "Comment" },
		chunk = {
			enabled = true,
			only_current = true,
			char = { arrow = "─", corner_top = "╭", corner_bottom = "╰" },
			hl = "Comment",
		},
	},
	notifier = { enabled = true, timeout = 3000 },
	picker = {
		enabled = true,
		matcher = { frecency = true },
		layout = {
			preset = function()
				return vim.o.columns >= 120 and "telescope" or "vertical"
			end,
		},
		layouts = {
			telescope = {
				reverse = false,
				layout = {
					box = "horizontal",
					backdrop = false,
					width = 0.8,
					height = 0.9,
					border = "none",
					{
						box = "vertical",
						{
							win = "input",
							height = 1,
							border = "rounded",
							title = "{title} {live} {flags}",
							title_pos = "center",
						},
						{ win = "list", title = " Results ", title_pos = "center", border = "rounded" },
					},
					{
						win = "preview",
						title = "{preview:Preview}",
						width = 0.51,
						border = "rounded",
						title_pos = "center",
					},
				},
			},
		},
		sources = {
			files = { hidden = true },
			projects = {
				confirm = function(picker, item)
					picker:close()
					if not item or not item.file then
						return
					end
					for _, tabpage in ipairs(vim.api.nvim_list_tabpages()) do
						if vim.fn.getcwd(-1, tabpage) == item.file then
							vim.api.nvim_set_current_tabpage(tabpage)
							return
						end
					end
					for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
						if vim.api.nvim_buf_is_loaded(bufnr) and vim.api.nvim_buf_get_name(bufnr) ~= "" then
							vim.cmd.tabnew()
							break
						end
					end
					vim.cmd("tcd " .. vim.fn.fnameescape(item.file))
					Snacks.picker.smart()
				end,
			},
			lsp_symbols = { filter = { ocaml = true, ocamlinterface = true } },
		},
	},
})

vim.api.nvim_create_autocmd("LspProgress", {
	desc = "Show language server progress",
	callback = function(event)
		local spinner = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
		local value = event.data and event.data.params and event.data.params.value or {}
		local client = event.data and event.data.client_id and vim.lsp.get_client_by_id(event.data.client_id)
		local parts = {}
		if client and client.name then
			table.insert(parts, client.name)
		end
		if value.title and value.title ~= "" then
			table.insert(parts, value.title)
		end
		if value.message and value.message ~= "" then
			table.insert(parts, value.message)
		end
		vim.notify(#parts > 0 and table.concat(parts, ": ") or "LSP progress", vim.log.levels.INFO, {
			id = "lsp_progress",
			title = "LSP Progress",
			opts = function(notification)
				notification.icon = value.kind == "end" and " "
					or spinner[math.floor(vim.uv.hrtime() / (1e6 * 80)) % #spinner + 1]
			end,
		})
	end,
})

for _, mapping in ipairs({
	{ "<leader>fd", Snacks.picker.diagnostics_buffer, "Find buffer diagnostics" },
	{ "<leader>d", Snacks.picker.diagnostics_buffer, "Buffer diagnostics (short)" },
	{ "<leader>fD", Snacks.picker.diagnostics, "Find workspace diagnostics" },
	{ "<leader>D", Snacks.picker.diagnostics, "Workspace diagnostics (short)" },
	{ "<leader>fs", Snacks.picker.lsp_symbols, "Find lsp document symbols" },
	{ "<leader>s", Snacks.picker.lsp_symbols, "Document symbols (short)" },
	{ "<leader>ld", Snacks.picker.lsp_definitions, "Goto Definition" },
	{ "<leader>li", Snacks.picker.lsp_implementations, "Goto Implementation" },
	{ "<leader>lD", Snacks.picker.lsp_references, "Find references" },
	{ "<leader>lt", Snacks.picker.lsp_type_definitions, "Goto Type Definition" },
	{ "gr", Snacks.picker.lsp_references, "[G]oto [R]eferences" },
	{ "<leader>fb", Snacks.picker.buffers, "Find buffers" },
	{ "<leader>b", Snacks.picker.buffers, "Buffer Picker" },
	{ "<leader>fo", Snacks.picker.recent, "Find recent files" },
	{ "<leader>fO", Snacks.picker.smart, "Find Smart (Frecency)" },
	{ "<leader>f?", Snacks.picker.grep_buffers, "Fuzzy find in open buffers" },
	{ "<leader>f/", Snacks.picker.lines, "Fuzzy find in current buffer" },
	{ "<leader>fr", Snacks.picker.resume, "Resume find" },
	{ "<leader>fh", Snacks.picker.help, "Find help tags" },
	{ "<leader>fk", Snacks.picker.keymaps, "Find keymaps" },
	{ "<leader>fp", Snacks.picker.projects, "Find projects" },
	{ "<leader>fm", Snacks.picker.man, "Find man pages" },
	{ "<leader>fq", Snacks.picker.qflist, "Find quickfix" },
	{ "<leader>fT", Snacks.picker.colorschemes, "Find theme" },
	{ "<leader>fH", Snacks.picker.highlights, "Find highlights" },
	{ "<leader>fS", Snacks.picker.spelling, "Find spelling suggestions" },
	{ "<leader>fr", Snacks.picker.registers, "Find registers" },
	{ "<leader>f'", Snacks.picker.marks, "Find marks" },
	{ "<leader>gB", Snacks.picker.git_branches, "Find git branches" },
	{ "<leader>gs", Snacks.picker.git_status, "Find git status" },
	{ "<leader>gS", Snacks.picker.git_stash, "Find git stashes" },
}) do
	map(mapping[1], mapping[2], mapping[3])
end

packadd("oil.nvim")
local function parse_output(process)
	local result, entries = process:wait(), {}
	if result.code == 0 then
		for line in vim.gsplit(result.stdout, "\n", { plain = true, trimempty = true }) do
			entries[line:gsub("/$", "")] = true
		end
	end
	return entries
end
local function new_git_status()
	return setmetatable({}, {
		__index = function(cache, directory)
			local status = {
				ignored = parse_output(
					vim.system(
						{ "git", "ls-files", "--ignored", "--exclude-standard", "--others", "--directory" },
						{ cwd = directory, text = true }
					)
				),
				tracked = parse_output(
					vim.system({ "git", "ls-tree", "HEAD", "--name-only" }, { cwd = directory, text = true })
				),
			}
			rawset(cache, directory, status)
			return status
		end,
	})
end
local git_status = new_git_status()
local refresh = require("oil.actions").refresh
local original_refresh = refresh.callback
refresh.callback = function(...)
	git_status = new_git_status()
	return original_refresh(...)
end
require("oil").setup({
	default_file_explorer = false,
	use_default_keymaps = false,
	preview = { border = "rounded" },
	float = { padding = 4, max_width = 0.6, max_height = 0.7, border = "rounded", win_options = { winblend = 0 } },
	keymaps = {
		["g?"] = "actions.show_help",
		["<CR>"] = "actions.select",
		["<C-j>"] = { "actions.select", opts = { horizontal = true } },
		["<C-l>"] = { "actions.select", opts = { vertical = true } },
		["<C-t>"] = { "actions.select", opts = { tab = true } },
		["<C-p>"] = "actions.preview",
		["<C-c>"] = "actions.close",
		["<C-r>"] = "actions.refresh",
		["-"] = "actions.parent",
		["_"] = "actions.open_cwd",
		["`"] = "actions.cd",
		["~"] = "actions.tcd",
		gs = "actions.change_sort",
		gx = "actions.open_external",
		["g."] = "actions.toggle_hidden",
		q = "actions.close",
	},
	view_options = {
		is_hidden_file = function(name, bufnr)
			local directory, is_dotfile =
				require("oil").get_current_dir(bufnr), vim.startswith(name, ".") and name ~= ".."
			if not directory then
				return is_dotfile
			end
			return is_dotfile and not git_status[directory].tracked[name]
				or not is_dotfile and git_status[directory].ignored[name]
		end,
	},
})
map("<leader>e", "<Cmd>Oil --float<CR>", "Open Oil")

packadd("fff")
require("fff").setup({
	lazy_sync = true,
	layout = { height = 0.8, width = 0.8, prompt_position = "bottom", preview_position = "right", preview_size = 0.5 },
})
map("<leader>ff", "<Cmd>lua require('fff').find_files()<CR>", "Find files (fff)")
map("<leader><space>", "<Cmd>lua require('fff').find_files()<CR>", "Find files (fff)")
map("<leader>fw", "<Cmd>lua require('fff').live_grep()<CR>", "Live grep (fff)")
map("<leader>/", "<Cmd>lua require('fff').live_grep()<CR>", "Live grep (fff)")
map(
	"<leader>fc",
	"<Cmd>lua require('fff').live_grep({ query = vim.fn.expand('<cword>') })<CR>",
	"Search current word (fff)"
)

vim.api.nvim_create_autocmd("VimEnter", {
	desc = "Open fff when starting on a directory",
	callback = function()
		if vim.fn.argc() ~= 1 or vim.fn.isdirectory(vim.fn.argv(0)) == 0 then
			return
		end
		if vim.bo.filetype == "netrw" then
			vim.cmd.enew()
		end
		vim.cmd.cd(vim.fn.fnamemodify(vim.fn.argv(0), ":p"))
		vim.schedule(function()
			require("fff").find_files()
		end)
	end,
})

packadd("flash.nvim")
require("flash").setup({ labels = "asdfghjklqwertyuiopzxcvbnm", modes = { search = { enabled = false } } })
map("<CR>", "<Cmd>lua require('nrm.flash').helix_word_jump()<CR>", "Flash Helix-style word jump")
map("S", "<Cmd>lua require('flash').treesitter()<CR>", "Flash treesitter select")
vim.keymap.set(
	"x",
	"S",
	"<Esc><Cmd>lua MiniSurround.add('visual')<CR>",
	{ desc = "Surround visual selection", silent = true }
)

packadd("mini.nvim")
require("mini.cursorword").setup()
require("mini.surround").setup()

vim.g.VM_maps = { ["Add Cursor Down"] = "<M-j>", ["Add Cursor Up"] = "<M-k>" }
packadd("vim-visual-multi")
map("<M-Down>", "<Plug>(VM-Add-Cursor-Down)", "Add Cursor Down")
map("<M-Up>", "<Plug>(VM-Add-Cursor-Up)", "Add Cursor Up")

vim.g.tmux_navigator_no_mappings = 1
packadd("vim-tmux-navigator")

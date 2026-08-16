local app = vim.env.NVIM_APPNAME or "nvim"
local native = vim.env.NRM_EXPECTED_CONFIG == "native"
local failures = {}

local function check(label, actual, expected)
	if actual ~= expected then
		failures[#failures + 1] = string.format("%s: expected %q, observed %q", label, expected, actual)
	end
end

local function check_truthy(label, value)
	if not value then
		failures[#failures + 1] = label .. ": expected a truthy value"
	end
end

local function check_mapping(mode, lhs, description, category)
	local mapping = vim.fn.maparg(lhs, mode, false, true)
	if description then
		check(lhs .. " description", mapping.desc, description)
	end
	if category == "callback" then
		check_truthy(lhs .. " callback", mapping.callback)
	elseif category == "write" then
		local rhs = (mapping.rhs or ""):lower()
		check_truthy(lhs .. " write mapping", rhs:find("w<cr>", 1, true) or rhs:find("write<cr>", 1, true))
	else
		check_truthy(lhs .. " " .. category .. " mapping", (mapping.rhs or ""):lower():find(category, 1, true))
	end
end

local expected_flavour = vim.o.background == "light" and "latte" or "macchiato"
check("colorscheme", vim.g.colors_name, "catppuccin-" .. expected_flavour)
check("RotateWindows command", vim.fn.exists(":RotateWindows"), 2)

for option, expected in pairs({
	number = true,
	relativenumber = true,
	splitbelow = true,
	splitright = true,
	wrap = true,
	termguicolors = true,
	cursorline = true,
	colorcolumn = "88",
	signcolumn = "yes",
	scrolloff = 10,
	timeoutlen = 400,
	winborder = "rounded",
}) do
	check(option, vim.o[option], expected)
end

local mappings = {
	{ "n", "<C-s>", "Save Current Buffer", "write" },
	{ "n", "gn", "[G]o [N]ext Buffer", "bnext" },
	{ "n", "gb", "[G]o [B]ack Buffer (Previous)", "bprev" },
	{ "n", "gp", "[G]o [P]revious Buffer", "bprev" },
	{ "n", "<Leader>w-", "Split [W]indow Vertical", "<c-w>s" },
	{ "n", "<Leader>w|", "Split [W]indow Horizontal", "<c-w>v" },
	{ "n", "<Leader>wd", "Delete [W]indow", "<c-w>c" },
	{ "n", "<Leader>=", "Resize Windows Equal", "<c-w>=" },
	{ "n", "<Leader>e", "Open Oil", "oil" },
	{ "n", "<Leader>ff", "Find files (fff)", "find_files" },
	{ "n", "<Leader>fw", "Live grep (fff)", "live_grep" },
	{ "n", "<Leader>gs", "Find changed files", "callback" },
	{ "n", "<CR>", "Flash Helix-style word jump", "helix_word_jump" },
}

for _, mapping in ipairs(mappings) do
	check_mapping(unpack(mapping))
end

local navigation = {
	{ "<C-h>", "Left", "navigateleft" },
	{ "<C-j>", "Down", "navigatedown" },
	{ "<C-k>", "Up", "navigateup" },
	{ "<C-l>", "Right", "navigateright" },
}

for _, mapping in ipairs(navigation) do
	local lhs, direction, legacy_rhs = unpack(mapping)
	if native then
		check_mapping("n", lhs, "Navigate Window " .. direction, "callback")
	else
		check_mapping("n", lhs, nil, legacy_rhs)
	end
end

local function press(keys)
	vim.api.nvim_feedkeys(vim.keycode(keys), "x", false)
end

vim.cmd("silent only")
vim.cmd("belowright vsplit")
local right_window = vim.api.nvim_get_current_win()
press("<C-h>")
local left_window = vim.api.nvim_get_current_win()
check_truthy("<C-h> moves left", left_window ~= right_window)
press("<C-l>")
check("<C-l> moves right", vim.api.nvim_get_current_win(), right_window)

vim.cmd("silent only")
vim.cmd("belowright split")
local bottom_window = vim.api.nvim_get_current_win()
press("<C-k>")
local top_window = vim.api.nvim_get_current_win()
check_truthy("<C-k> moves up", top_window ~= bottom_window)
press("<C-j>")
check("<C-j> moves down", vim.api.nvim_get_current_win(), bottom_window)
vim.cmd("silent only")

if #failures > 0 then
	for _, failure in ipairs(failures) do
		io.stderr:write("FAIL ", app, " interface/navigation: ", failure, "\n")
	end
	vim.cmd("cquit 1")
end

io.stdout:write("PASS ", app, " interface/navigation\n")
vim.cmd("qa!")

local app = vim.env.NVIM_APPNAME or "nvim"
local failures = {}

local function check(label, actual, expected)
	if actual ~= expected then
		failures[#failures + 1] = string.format("%s: expected %q, observed %q", label, expected, actual)
	end
end

local function feed(keys)
	vim.api.nvim_feedkeys(vim.keycode(keys), "xt", false)
end

local fixture = {
	"function add(left, right)",
	"  local total = left + right",
	"  return total",
	"end",
	"",
	"local result = placeholder",
}

vim.api.nvim_buf_set_lines(0, 0, -1, false, fixture)
vim.cmd("setfiletype lua")

vim.api.nvim_win_set_cursor(0, { 1, 13 })
feed("vaf")
local selected = vim.fn.getregion(vim.fn.getpos("v"), vim.fn.getpos("."), { type = "v" })
check("function textobject", table.concat(selected, "\n"), table.concat(vim.list_slice(fixture, 1, 4), "\n"))
feed("<Esc>")

vim.api.nvim_win_set_cursor(0, { 2, 2 })
feed("gcc")
check("line comment", vim.api.nvim_buf_get_lines(0, 1, 2, false)[1], "  -- local total = left + right")

vim.api.nvim_win_set_cursor(0, { 6, 15 })
feed("cw(")
check("paired insertion", vim.api.nvim_buf_get_lines(0, 5, 6, false)[1], "local result = ()")
feed("<Esc>")

if #failures > 0 then
	for _, failure in ipairs(failures) do
		io.stderr:write("FAIL ", app, " structured editing: ", failure, "\n")
	end
	vim.cmd("cquit 1")
end

io.stdout:write("PASS ", app, " structured editing\n")
vim.cmd("qa!")

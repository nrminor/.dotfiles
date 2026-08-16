local expected_app = assert(vim.env.NRM_EXPECTED_APP, "expected an application name")
local expected_config = assert(vim.env.NRM_EXPECTED_CONFIG, "expected a configuration identity")
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

for _, scope in ipairs({ "config", "data", "state", "cache" }) do
	local path = vim.fn.stdpath(scope)
	check(scope .. " application directory", vim.fs.basename(path), expected_app)
end

check("mapleader", vim.g.mapleader, " ")
check("maplocalleader", vim.g.maplocalleader, " ")

local config_source = vim.fn.resolve(vim.fn.stdpath("config") .. "/init.lua")
if expected_config == "native" then
	check("configuration source", config_source, vim.env.NRM_EXPECTED_CONFIG_SOURCE)
	check("native configuration completion", vim.g.nrm_config_loaded, true)
elseif expected_config == "nixvim" then
	check_truthy("nixvim configuration source", vim.startswith(config_source, "/nix/store/"))
	check("native configuration isolation", vim.g.nrm_config_loaded, nil)
	check("nixvim colorscheme", vim.g.colors_name, "catppuccin-macchiato")
else
	failures[#failures + 1] = "unknown configuration identity: " .. expected_config
end

if #failures > 0 then
	for _, failure in ipairs(failures) do
		io.stderr:write("FAIL ", expected_app, ": ", failure, "\n")
	end
	vim.cmd("cquit 1")
end

io.stdout:write("PASS ", expected_app, " startup\n")
vim.cmd("qa")

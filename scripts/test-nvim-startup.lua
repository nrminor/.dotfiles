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

local function check_call_truthy(label, callable, ...)
	local ok, result = pcall(callable, ...)
	if not ok then
		failures[#failures + 1] = label .. ": " .. tostring(result)
	elseif not result then
		failures[#failures + 1] = label .. ": expected a truthy result"
	end
end

local function sorted_keys(values)
	local keys = vim.tbl_keys(values)
	table.sort(keys)
	return table.concat(keys, "\n")
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

	local plugins = vim.pack.get()
	local lockfile = vim.fn.stdpath("config") .. "/nvim-pack-lock.json"
	local declared_plugins = {}
	for _, spec in ipairs(assert(package.loaded["nrm.pack.specs"], "plugin specifications were not loaded")) do
		declared_plugins[spec.name] = true
	end
	local expected_pack_count = #vim.tbl_keys(declared_plugins)
	local managed_plugins = {}
	check("managed plugin count", #plugins, expected_pack_count)
	check("plugin lockfile", vim.fn.filereadable(lockfile), 1)
	local locked_plugins = vim.json.decode(table.concat(vim.fn.readfile(lockfile), "\n")).plugins
	local locked_plugin_count = 0
	for _ in pairs(locked_plugins) do
		locked_plugin_count = locked_plugin_count + 1
	end
	check("locked plugin count", locked_plugin_count, expected_pack_count)
	for _, plugin in ipairs(plugins) do
		managed_plugins[plugin.spec.name] = true
		check("active plugin " .. plugin.spec.name, plugin.active, true)
		check_truthy("portable plugin path for " .. plugin.spec.name, not plugin.path:find("/nix/store/", 1, true))
		local locked_plugin = locked_plugins[plugin.spec.name]
		check_truthy("lock entry for " .. plugin.spec.name, locked_plugin)
		if locked_plugin then
			check("locked revision for " .. plugin.spec.name, plugin.rev, locked_plugin.rev)
		end
	end
	check("managed plugin names", sorted_keys(managed_plugins), sorted_keys(declared_plugins))
	check("locked plugin names", sorted_keys(locked_plugins), sorted_keys(declared_plugins))
	for _, path in ipairs(vim.api.nvim_list_runtime_paths()) do
		check_truthy("portable runtime path " .. path, not path:find("/nix/store/", 1, true))
	end

	check_call_truthy("FFF native backend", require, "fff.rust")
	if vim.env.NRM_SKIP_PARSER_CHECKS ~= "1" then
		local installed_parsers = require("nvim-treesitter").get_installed("parsers")
		for _, language in ipairs({ "lua", "typescript" }) do
			check_truthy("managed Tree-sitter parser for " .. language, vim.tbl_contains(installed_parsers, language))
			check_call_truthy("Tree-sitter parser for " .. language, vim.treesitter.language.inspect, language)
		end
	end
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

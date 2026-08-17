local specs = require("nrm.pack.specs")
local parsers = require("nrm.pack.parsers")

local maintenance_kinds = { install = true, update = true }

local function activate(change)
	if not change.active then
		vim.cmd.packadd(change.spec.name)
	end
end

local function build_fff_with_ripgrep()
	-- TEMPORARY FFF WORKAROUND — REMOVE THIS AS SOON AS UPSTREAM CAN SCAN
	-- HIDDEN FILES IN PURE JUJUTSU WORKSPACES WITH ITS ZLOB RELEASE BINARY.
	--
	-- FFF currently treats "libgit2 found a Git worktree" as both permission to
	-- scan hidden paths and permission to collect Git status. Its prebuilt zlob
	-- binary therefore applies SKIP_HIDDEN to a pure `.jj` workspace and drops
	-- tracked trees such as `.config` and `.mise`. A source build using FFF's
	-- ripgrep walker respects this repository's `.gitignore` negations and keeps
	-- those files visible. Do not replace this with download_or_build_binary()
	-- until FFF separates hidden-path traversal from Git repository discovery.
	if vim.fn.executable("cargo") == 0 then
		error("FFF's temporary ripgrep build requires cargo in PATH")
	end

	local binary = require("fff.download").get_binary_path()
	local plugin_root = vim.fn.fnamemodify(binary, ":h:h:h")
	local result = vim.system({
		"cargo",
		"build",
		"--release",
		"--locked",
		"--no-default-features",
		"--features",
		"ripgrep",
		"--package",
		"fff-nvim",
	}, { cwd = plugin_root, text = true }):wait(600000)

	if result.code ~= 0 then
		error("Failed to compile FFF with its ripgrep backend:\n" .. (result.stderr or "unknown error"))
	end
end

vim.api.nvim_create_autocmd("User", {
	pattern = "TSUpdate",
	desc = "Register custom Tree-sitter parsers",
	callback = parsers.register_custom_parsers,
})

vim.api.nvim_create_autocmd("PackChanged", {
	desc = "Maintain native Neovim plugin artifacts",
	callback = function(event)
		local change = event.data
		if not maintenance_kinds[change.kind] then
			return
		end

		if change.spec.name == "fff" then
			activate(change)
			build_fff_with_ripgrep()
		elseif change.spec.name == "nvim-treesitter" then
			activate(change)
			local treesitter = require("nvim-treesitter")
			if treesitter.install(parsers.languages):wait(300000) ~= true then
				error("Tree-sitter parser installation failed")
			end
			if change.kind == "update" and treesitter.update(parsers.languages):wait(300000) ~= true then
				error("Tree-sitter parser update failed")
			end
		end
	end,
})

vim.pack.add(specs, { confirm = false, load = false })

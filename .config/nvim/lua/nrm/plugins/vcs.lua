vim.cmd.packadd("async.nvim")
vim.cmd.packadd("snacks.nvim")
vim.cmd.packadd("vclib.nvim")
vim.cmd.packadd("vcsigns.nvim")

local Snacks = require("snacks")
local vcsigns = require("vcsigns")
local actions = vcsigns.actions

-- VCSigns offset zero compares the working-copy commit with its parent;
-- offset one would incorrectly carry the parent's changes into this commit.
vcsigns.setup({ auto_enable = false, target_commit = 0 })

local function find_changed_files()
	local directory = vim.fn.getcwd()
	if vim.fs.root(directory, ".git") then
		Snacks.picker.git_status()
		return
	end

	local jj_root = vim.fs.root(directory, ".jj")
	if not jj_root then
		vim.notify("No Git or Jujutsu repository found", vim.log.levels.WARN)
		return
	end

	-- `jj diff --git` lets Snacks reuse the same changed-file list, status
	-- formatting, and diff preview used by its Git picker without inventing a
	-- second picker UI or pretending that a pure Jujutsu workspace is Git.
	Snacks.picker({
		title = "Jujutsu Changes",
		cwd = jj_root,
		finder = "diff",
		cmd = "jj",
		args = { "diff", "--git", "-r", "@" },
		group = true,
		format = "git_status",
		preview = "diff",
	})
end

vim.keymap.set("n", "<leader>gs", find_changed_files, { desc = "Find changed files", silent = true })

local function attach(buffer)
	local path = vim.api.nvim_buf_get_name(buffer)
	if path == "" then
		return
	end
	local directory = vim.fs.dirname(path)
	local resolved_path = vim.uv.fs_realpath(path) or vim.uv.fs_realpath(directory) or directory
	if not vim.fs.root(resolved_path, ".jj") then
		return
	end

	actions.start_if_needed(buffer)
	local options = { buffer = buffer, silent = true }
	local function map(mode, lhs, rhs, description)
		vim.keymap.set(mode, lhs, rhs, vim.tbl_extend("force", options, { desc = description }))
	end

	map("n", "]c", function()
		actions.hunk_next(buffer, vim.v.count1)
	end, "Next hunk")
	map("n", "[c", function()
		actions.hunk_prev(buffer, vim.v.count1)
	end, "Previous hunk")
	map("n", "<leader>hr", function()
		actions.hunk_undo(buffer)
	end, "Reset hunk")
	map("x", "<leader>hr", function()
		actions.hunk_undo(buffer)
	end, "Reset selected hunks")
	map("n", "<leader>hp", function()
		actions.toggle_hunk_diff(buffer)
	end, "Toggle inline hunk diff")
	map("n", "<leader>hd", function()
		actions.diffview(buffer)
	end, "Open VCS diff view")
	map("n", "<leader>hf", function()
		actions.toggle_fold(buffer)
	end, "Fold outside hunks")
end

vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile" }, {
	desc = "Attach VCSigns to Jujutsu buffers",
	group = vim.api.nvim_create_augroup("nrm_vcsigns", { clear = true }),
	callback = function(event)
		attach(event.buf)
	end,
})

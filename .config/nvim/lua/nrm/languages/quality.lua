vim.cmd.packadd("conform.nvim")
vim.cmd.packadd("nvim-lint")

local conform = require("conform")
local javascript_formatters = { "oxfmt", "biome", stop_after_first = true }

conform.setup({
	notify_no_formatters = false,
	formatters_by_ft = {
		javascript = javascript_formatters,
		javascriptreact = javascript_formatters,
		typescript = javascript_formatters,
		typescriptreact = javascript_formatters,
		ocaml = { "ocamlformat_impl" },
		ocamlinterface = { "ocamlformat_intf" },
		ocamllex = { "ocamlformat_impl" },
		menhir = { "ocamlformat_impl" },
		nu = { "topiary" },
	},
	formatters = {
		topiary = { command = "topiary", args = { "format", "--language", "nu" }, stdin = true },
		ocamlformat_impl = {
			command = "ocamlformat",
			args = { "-", "--impl", "--enable-outside-detected-project" },
			stdin = true,
		},
		ocamlformat_intf = {
			command = "ocamlformat",
			args = { "-", "--intf", "--enable-outside-detected-project" },
			stdin = true,
		},
	},
	format_after_save = function(buffer)
		if vim.g.disable_autoformat or vim.b[buffer].disable_autoformat then
			return
		end

		local filetype = vim.bo[buffer].filetype
		local is_ocaml = filetype == "ocaml"
			or filetype == "ocamlinterface"
			or filetype == "ocamllex"
			or filetype == "menhir"
		local is_javascript = filetype == "javascript"
			or filetype == "javascriptreact"
			or filetype == "typescript"
			or filetype == "typescriptreact"
		return {
			lsp_format = (is_ocaml or is_javascript) and "never" or "fallback",
		}
	end,
})

vim.api.nvim_create_user_command("FormatEnable", function()
	vim.b.disable_autoformat = false
	vim.g.disable_autoformat = false
end, { desc = "Enable format on save" })

vim.api.nvim_create_user_command("FormatDisable", function(command)
	if command.bang then
		vim.b.disable_autoformat = true
	else
		vim.g.disable_autoformat = true
	end
end, { bang = true, desc = "Disable format on save" })

vim.keymap.set("n", "<leader>f", function()
	conform.format({ async = true, lsp_format = "fallback" })
end, { desc = "[F]ormat buffer", silent = true })

local lint = require("lint")
lint.linters_by_ft = { nix = { "statix" } }

vim.api.nvim_create_autocmd({ "BufReadPost", "BufWritePost" }, {
	desc = "Lint current buffer",
	group = vim.api.nvim_create_augroup("nrm_lint", { clear = true }),
	callback = function()
		lint.try_lint()
	end,
})

vim.cmd.packadd("nvim-lspconfig")

vim.lsp.config("*", {
	capabilities = require("blink.cmp").get_lsp_capabilities(),
})

vim.filetype.add({
	extension = {
		mdx = "mdx",
		nf = "nextflow",
		rn = "rune",
	},
	pattern = {
		["nextflow%.config"] = "nextflow",
		[".*%.nf%.test"] = "nextflow",
	},
})

vim.lsp.config("jsonls", {
	init_options = { provideFormatter = false },
})

vim.lsp.config("lua_ls", {
	settings = {
		Lua = {
			diagnostics = { globals = { "vim" } },
			workspace = { checkThirdParty = false },
		},
	},
})

vim.lsp.config("ruff", {
	init_options = {
		settings = {
			lineLength = 100,
			lint = {
				select = { "ALL" },
				ignore = { "D", "S101", "E501", "PTH123", "TD003" },
			},
		},
	},
})

vim.lsp.config("rust_analyzer", {
	settings = {
		["rust-analyzer"] = {
			check = { command = "clippy", extraArgs = { "--all-features" } },
			inlayHints = { enable = false },
		},
	},
})

vim.lsp.config("nixd", {
	settings = {
		nixd = {
			nixpkgs = { expr = 'import (builtins.getFlake "nixpkgs") { }' },
			formatting = { command = { "nixfmt" } },
		},
	},
})

vim.lsp.config("nextflow_ls", {
	root_markers = { "nextflow.config", "main.nf", ".git" },
	settings = {
		nextflow = {
			files = { exclude = { ".pixi", ".git", ".nf-test", "work" } },
			formatting = { harshilAlignment = true },
		},
	},
})

vim.lsp.config("just", {
	root_markers = { "justfile", "Justfile", ".git" },
})

vim.lsp.config("air", {
	filetypes = { "r", "rmd" },
	root_markers = { "air.toml", ".air.toml", "DESCRIPTION", ".git" },
})

vim.lsp.config("tsc", {
	settings = {
		typescript = {
			inlayHints = {
				parameterNames = { enabled = "literals", suppressWhenArgumentMatchesName = true },
				parameterTypes = { enabled = false },
				variableTypes = { enabled = false },
				propertyDeclarationTypes = { enabled = false },
				functionLikeReturnTypes = { enabled = false },
				enumMemberValues = { enabled = false },
			},
		},
	},
})

local oyui_config_paths = {
	[vim.fs.normalize(vim.fn.expand("~/.config/oyui/config.rn"))] = true,
	[vim.fs.normalize(vim.fn.expand("~/.dotfiles/.config/oyui/config.rn"))] = true,
}

vim.lsp.config("oyui_ls", {
	cmd = { "oyui", "language-server" },
	filetypes = { "rune" },
	root_dir = function(buffer, on_dir)
		local path = vim.fs.normalize(vim.api.nvim_buf_get_name(buffer))
		if oyui_config_paths[path] then
			on_dir(vim.fs.dirname(path))
		end
	end,
})

vim.lsp.enable({
	"astro",
	"awk_ls",
	"bashls",
	"tailwindcss",
	"gopls",
	"hls",
	"superhtml",
	"jsonls",
	"just",
	"lua_ls",
	"markdown_oxide",
	"nextflow_ls",
	"nixd",
	"nushell",
	"ocamllsp",
	"ty",
	"ruff",
	"air",
	"rust_analyzer",
	"sqls",
	"taplo",
	"tinymist",
	"yamlls",
	"zls",
	"tsc",
	"eslint",
	"oxlint",
	"oyui_ls",
})

local lsp_group = vim.api.nvim_create_augroup("nrm_lsp", { clear = true })

vim.api.nvim_create_autocmd("LspAttach", {
	group = lsp_group,
	desc = "Set LSP buffer mappings",
	callback = function(event)
		local function map(mode, lhs, rhs, description)
			vim.keymap.set(mode, lhs, rhs, { buffer = event.buf, desc = description, silent = true })
		end

		map("n", "<D-k>", vim.lsp.buf.hover, "Hover Documentation")
		map("n", "<leader>ca", vim.lsp.buf.code_action, "LSP: [C]ode [A]ction")
		map("x", "<leader>ca", vim.lsp.buf.code_action, "LSP: [C]ode [A]ction")
		map("n", "<leader>rn", vim.lsp.buf.rename, "LSP: [R]ename")
		map("n", "<leader>k", vim.lsp.buf.signature_help, "LSP: [S]ignature [H]elp")
		map("i", "<C-k>", vim.lsp.buf.signature_help, "LSP: [S]ignature [H]elp")
		map("n", "gd", vim.lsp.buf.definition, "LSP: [G]oto [D]efinition")
		map("n", "gD", vim.lsp.buf.declaration, "LSP: [G]oto [D]eclaration")
		map("n", "gt", vim.lsp.buf.type_definition, "LSP: [G]oto [T]ype Definition")
		map("n", "<leader>d", function()
			vim.diagnostic.open_float({ border = "rounded" })
		end, "LSP: Show Line [D]iagnostics")
		map("n", "<leader>ll", function()
			local config = vim.diagnostic.config()
			vim.diagnostic.config({
				virtual_text = config.virtual_text == false and { source = "always", prefix = "●" } or false,
			})
		end, "LSP: Toggle Inline Diagnostics")
		map("n", "<leader>lL", function()
			vim.diagnostic.enable(not vim.diagnostic.is_enabled())
		end, "LSP: Toggle Diagnostics")
	end,
})

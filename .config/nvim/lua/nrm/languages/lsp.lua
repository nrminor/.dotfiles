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

local default_oxlint_cmd = vim.lsp.config.oxlint.cmd

vim.lsp.config("oxlint", {
	cmd = function(dispatchers, config)
		local root = config and config.root_dir
		local manifest = root and vim.fs.joinpath(root, "package.json")
		if not manifest or not vim.uv.fs_stat(manifest) then
			return default_oxlint_cmd(dispatchers, config)
		end

		local package = vim.json.decode(table.concat(vim.fn.readfile(manifest), "\n"))
		if type(package) ~= "table" or (package.scripts ~= nil and type(package.scripts) ~= "table") then
			error("Invalid package.json scripts in: " .. manifest)
		end
		local script = package.scripts and package.scripts["lint:lsp"]
		if script == nil then
			return default_oxlint_cmd(dispatchers, config)
		end
		if type(script) ~= "string" or script == "" then
			error("Invalid lint:lsp script in: " .. manifest)
		end
		if type(package.packageManager) ~= "string" or not package.packageManager:match("^pnpm@.+") then
			error("lint:lsp requires an explicit pnpm packageManager in: " .. manifest)
		end
		return vim.lsp.rpc.start({ "pnpm", "--silent", "run", "lint:lsp" }, dispatchers, { cwd = root })
	end,
})

local function uses_effect_tsgo(root)
	local manifest = vim.fs.joinpath(root, "package.json")
	if not vim.uv.fs_stat(manifest) then
		return false
	end
	local package = vim.json.decode(table.concat(vim.fn.readfile(manifest), "\n"))
	for _, field in ipairs({ "dependencies", "devDependencies", "optionalDependencies", "peerDependencies" }) do
		if package[field] and package[field]["@effect/tsgo"] ~= nil then
			return true
		end
	end
	return false
end

local function typescript_major(root)
	local manifest = vim.fs.joinpath(root, "node_modules/typescript/package.json")
	if not vim.uv.fs_stat(manifest) then
		return nil
	end
	local package = vim.json.decode(table.concat(vim.fn.readfile(manifest), "\n"))
	local major = tonumber(tostring(package.version):match("^(%d+)%."))
	assert(major, "Invalid installed TypeScript version in: " .. manifest)
	return major
end

local function typescript_root(server)
	local upstream_root = vim.lsp.config[server].root_dir
	return function(buffer, on_dir)
		upstream_root(buffer, function(root)
			local classic = false
			if not uses_effect_tsgo(root) then
				local major = typescript_major(root)
				classic = major ~= nil and major < 7
			end
			if (server == "ts_ls") == classic then
				on_dir(root)
			end
		end)
	end
end

vim.lsp.config("ts_ls", {
	root_dir = typescript_root("ts_ls"),
	cmd = function(dispatchers, config)
		local cli = vim.fs.joinpath(config.root_dir, "node_modules/.bin/typescript-language-server")
		if vim.fn.executable(cli) ~= 1 then
			error("Install typescript-language-server as a project devDependency: " .. cli)
		end
		local tsserver = vim.fs.joinpath(config.root_dir, "node_modules/typescript/lib/tsserver.js")
		if vim.fn.filereadable(tsserver) ~= 1 then
			error("Project-local TypeScript server is missing: " .. tsserver)
		end
		return vim.lsp.rpc.start({ cli, "--stdio" }, dispatchers)
	end,
	init_options = { disableAutomaticTypingAcquisition = true },
	before_init = function(params, config)
		params.initializationOptions.tsserver = {
			path = vim.fs.joinpath(config.root_dir, "node_modules/typescript/lib/tsserver.js"),
		}
	end,
})

vim.lsp.config("tsc", {
	root_dir = typescript_root("tsc"),
	cmd = function(dispatchers, config)
		local root = config.root_dir
		if not uses_effect_tsgo(root) then
			local major = typescript_major(root)
			for _, binary in ipairs({ "tsc", "tsgo" }) do
				local cli = vim.fs.joinpath(root, "node_modules/.bin", binary)
				if (binary == "tsgo" or (major and major >= 7)) and vim.fn.executable(cli) == 1 then
					return vim.lsp.rpc.start({ cli, "--lsp", "--stdio" }, dispatchers)
				end
			end
			error("Install a project-local TypeScript compiler in: " .. root)
		end

		local cli = vim.fs.joinpath(root, "node_modules/.bin/effect-tsgo")
		if vim.fn.executable(cli) ~= 1 then
			error("@effect/tsgo is declared but its project-local CLI is missing: " .. cli)
		end
		local result = vim.system({ cli, "get-exe-path" }, { cwd = root, text = true }):wait(5000)
		if result.code == 124 then
			error("@effect/tsgo get-exe-path timed out after 5000ms: " .. cli)
		end
		if result.code ~= 0 then
			error("@effect/tsgo get-exe-path failed: " .. vim.trim((result.stderr or "") ~= "" and result.stderr or (result.stdout or "")))
		end
		local exe = vim.trim(result.stdout or "")
		if exe == "" then
			error("@effect/tsgo get-exe-path returned no executable path: " .. cli)
		end
		if not vim.startswith(exe, "/") or vim.fn.executable(exe) ~= 1 then
			error("@effect/tsgo returned a non-executable path: " .. exe)
		end
		return vim.lsp.rpc.start({ exe, "--lsp", "--stdio" }, dispatchers)
	end,
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
	"ts_ls",
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

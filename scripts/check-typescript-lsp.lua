local temporary = vim.fn.tempname()
vim.fn.mkdir(temporary, "p")
temporary = assert(vim.uv.fs_realpath(temporary))
local original_start = vim.lsp.rpc.start
local original_path = vim.env.PATH
local started

local function write(path, lines)
	vim.fn.mkdir(vim.fs.dirname(path), "p")
	vim.fn.writefile(lines, path)
end

local function executable(path, lines)
	write(path, lines or { "#!/bin/sh", "exit 0" })
	assert(vim.uv.fs_chmod(path, 493))
end

local function project(name, dependencies)
	local root = vim.fs.joinpath(temporary, name)
	write(root .. "/package.json", { vim.json.encode({ devDependencies = dependencies or {} }) })
	if dependencies and dependencies.typescript then
		write(root .. "/node_modules/typescript/package.json", {
			vim.json.encode({ name = "typescript", version = dependencies.typescript }),
		})
	end
	write(root .. "/pnpm-lock.yaml", {})
	write(root .. "/src/main.ts", { "export const answer = 42;" })
	local buffer = vim.api.nvim_create_buf(false, false)
	vim.api.nvim_buf_set_name(buffer, root .. "/src/main.ts")
	return root, buffer
end

local function selected(buffer)
	local servers = {}
	for _, name in ipairs({ "tsc", "ts_ls" }) do
		if vim.lsp.is_enabled(name) then
			vim.lsp.config[name].root_dir(buffer, function(root)
				servers[#servers + 1] = { name = name, root = root }
			end)
		end
	end
	return servers
end

local function expect_server(buffer, name, root)
	local actual = selected(buffer)
	assert(vim.deep_equal(actual, { { name = name, root = root } }), vim.inspect(actual))
end

local function expect_error(call, message)
	started = nil
	local ok, failure = pcall(call)
	assert(not ok and tostring(failure):find(message, 1, true), tostring(failure))
	assert(started == nil, "A server was launched despite missing local dependencies")
end

local function run()
	vim.lsp.rpc.start = function(command)
		started = command
		return {}
	end
	local global_bin = temporary .. "/global-bin"
	for _, name in ipairs({ "tsc", "tsgo", "typescript-language-server" }) do
		executable(global_bin .. "/" .. name)
	end
	vim.env.PATH = global_bin .. ":" .. original_path

	local root, buffer = project("classic", { typescript = "6.0.3" })
	write(root .. "/node_modules/typescript/lib/tsserver.js", {})
	executable(root .. "/node_modules/.bin/tsc")
	executable(root .. "/node_modules/.bin/typescript-language-server")
	expect_server(buffer, "ts_ls", root)
	vim.lsp.config.ts_ls.cmd({}, { root_dir = root })
	assert(vim.deep_equal(started, { root .. "/node_modules/.bin/typescript-language-server", "--stdio" }))
	local params = { initializationOptions = vim.deepcopy(vim.lsp.config.ts_ls.init_options) }
	vim.lsp.config.ts_ls.before_init(params, { root_dir = root })
	assert(params.initializationOptions.hostInfo == "neovim")
	assert(params.initializationOptions.disableAutomaticTypingAcquisition == true)
	assert(params.initializationOptions.tsserver.path == root .. "/node_modules/typescript/lib/tsserver.js")
	print("PASS: classic TypeScript selects only its project-local language server")

	executable(root .. "/node_modules/.bin/tsgo")
	expect_server(buffer, "ts_ls", root)
	print("PASS: installed classic TypeScript wins over coinstalled native preview")

	assert(vim.uv.fs_unlink(root .. "/node_modules/typescript/lib/tsserver.js"))
	expect_server(buffer, "ts_ls", root)
	expect_error(function()
		vim.lsp.config.ts_ls.cmd({}, { root_dir = root })
	end, "Project-local TypeScript server is missing")
	write(root .. "/node_modules/typescript/lib/tsserver.js", {})
	print("PASS: a partial classic installation is not mistaken for a native compiler")

	assert(vim.uv.fs_unlink(root .. "/node_modules/.bin/typescript-language-server"))
	expect_error(function()
		vim.lsp.config.ts_ls.cmd({}, { root_dir = root })
	end, "Install typescript-language-server as a project devDependency")
	print("PASS: missing classic dependencies do not fall back to global tools")

	root, buffer = project("native", { typescript = "7.0.2" })
	executable(root .. "/node_modules/.bin/tsc")
	expect_server(buffer, "tsc", root)
	vim.lsp.config.tsc.cmd({}, { root_dir = root })
	assert(vim.deep_equal(started, { root .. "/node_modules/.bin/tsc", "--lsp", "--stdio" }))
	print("PASS: native TypeScript uses the project-local compiler")

	assert(vim.uv.fs_unlink(root .. "/node_modules/.bin/tsc"))
	executable(root .. "/node_modules/.bin/tsgo")
	expect_server(buffer, "tsc", root)
	vim.lsp.config.tsc.cmd({}, { root_dir = root })
	assert(vim.deep_equal(started, { root .. "/node_modules/.bin/tsgo", "--lsp", "--stdio" }))
	print("PASS: local native preview wins over a global tsc")

	assert(vim.uv.fs_unlink(root .. "/node_modules/.bin/tsgo"))
	expect_error(function()
		vim.lsp.config.tsc.cmd({}, { root_dir = root })
	end, "Install a project-local TypeScript compiler")
	print("PASS: missing native compiler does not fall back to global tools")

	root, buffer = project("effect with spaces", { ["@effect/tsgo"] = "0.67.5", typescript = "6.0.3" })
	write(root .. "/node_modules/typescript/lib/tsserver.js", {})
	executable(root .. "/node_modules/.bin/tsc")
	local effect_binary = root .. "/node_modules/.bin/effect-native"
	executable(effect_binary)
	executable(root .. "/node_modules/.bin/effect-tsgo", {
		"#!/bin/sh",
		'[ "$1" = get-exe-path ] || exit 2',
		"printf '%s\\n' " .. vim.fn.shellescape(effect_binary),
	})
	expect_server(buffer, "tsc", root)
	vim.lsp.config.tsc.cmd({}, { root_dir = root })
	assert(vim.deep_equal(started, { effect_binary, "--lsp", "--stdio" }))
	print("PASS: declared Effect compiler takes precedence over classic TypeScript")

	assert(vim.uv.fs_unlink(root .. "/node_modules/.bin/effect-tsgo"))
	expect_server(buffer, "tsc", root)
	expect_error(function()
		vim.lsp.config.tsc.cmd({}, { root_dir = root })
	end, "@effect/tsgo is declared but its project-local CLI is missing")
	print("PASS: missing declared Effect compiler does not silently fall back")

	root, buffer = project("deno", { typescript = "6.0.3" })
	write(root .. "/node_modules/typescript/lib/tsserver.js", {})
	write(root .. "/deno.json", { "{}" })
	assert(#selected(buffer) == 0)
	print("PASS: upstream Deno exclusion is preserved")
end

local ok, failure = xpcall(run, debug.traceback)
vim.lsp.rpc.start = original_start
vim.env.PATH = original_path
vim.fn.delete(temporary, "rf")
if not ok then
	io.stderr:write(failure .. "\n")
	vim.cmd("cquit 1")
else
	vim.cmd("qa!")
end

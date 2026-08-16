local app = vim.env.NRM_EXPECTED_APP or "unknown"
local failures = {}
local uv = vim.uv
local fixture
local fixture_created = false
local buffer

local function fail(message)
	failures[#failures + 1] = message
end

local function check(label, actual, expected)
	if actual ~= expected then
		fail(string.format("%s: expected %q, observed %q", label, expected, actual))
	end
end

local function check_truthy(label, value)
	if not value then
		fail(label .. ": expected a truthy value")
	end
end

local function write(path, lines)
	assert(vim.fn.writefile(lines, path) == 0, "could not write " .. path)
end

local function clients_supporting_definition(buffer, root)
	local clients = vim.lsp.get_clients({ bufnr = buffer })
	return vim.tbl_filter(function(client)
		return client:supports_method("textDocument/definition", { bufnr = buffer })
			and client.root_dir
			and vim.fs.normalize(client.root_dir) == vim.fs.normalize(root)
	end, clients)
end

local function has_definition_in(results, definition_uri)
	for _, response in pairs(results or {}) do
		local result = response.result
		local locations = result and (result.uri and { result } or result) or {}
		for _, location in ipairs(locations) do
			local target_uri = location.targetUri or location.uri
			local target_range = location.targetSelectionRange or location.range
			if target_uri == definition_uri and target_range and target_range.start.line == 0 then
				return true
			end
		end
	end
	return false
end

local function has_expected_diagnostic(buffer, namespaces)
	for _, namespace in ipairs(namespaces) do
		for _, diagnostic in ipairs(vim.diagnostic.get(buffer, { namespace = namespace })) do
			if
				tostring(diagnostic.code) == "2322"
				and diagnostic.lnum == 1
				and diagnostic.col == 6
				and diagnostic.end_lnum == 1
				and diagnostic.end_col == 14
			then
				return true
			end
		end
	end
	return false
end

local function client_diagnostics(buffer, namespaces)
	return vim.iter(namespaces):fold({}, function(diagnostics, namespace)
		vim.list_extend(diagnostics, vim.diagnostic.get(buffer, { namespace = namespace }))
		return diagnostics
	end)
end

local function run()
	local root = assert(vim.env.NRM_REPO_ROOT, "expected the repository root")
	fixture = vim.fs.joinpath(root, ".nvim-typescript-contract-" .. string.format("%.0f", uv.hrtime()))
	local expected_tsc = vim.fn.resolve(vim.fs.joinpath(root, "node_modules", ".bin", "tsc"))
	check_truthy("project-local tsc", vim.fn.executable(expected_tsc) == 1)
	check("tsc resolution", vim.fn.resolve(vim.fn.exepath("tsc")), expected_tsc)

	assert(vim.fn.mkdir(fixture, "p") == 1, "could not create fixture directory")
	fixture_created = true
	write(vim.fs.joinpath(fixture, "tsconfig.json"), {
		'{ "compilerOptions": { "strict": true, "noEmit": true }, "include": ["*.ts"] }',
	})
	write(vim.fs.joinpath(fixture, "definition.ts"), { "export const answer: number = 42" })
	write(vim.fs.joinpath(fixture, "main.ts"), {
		'import { answer } from "./definition"',
		"const greeting: string = answer",
		"const unformatted={answer}",
	})

	local main_path = vim.fs.joinpath(fixture, "main.ts")
	vim.cmd.edit(vim.fn.fnameescape(main_path))
	buffer = vim.api.nvim_get_current_buf()
	local attached = vim.wait(5000, function()
		return #clients_supporting_definition(buffer, root) > 0
	end, 50)
	check_truthy("attached client supporting definitions within 5000ms", attached)
	local language_client

	if attached then
		vim.api.nvim_win_set_cursor(0, { 2, 26 })
		language_client = clients_supporting_definition(buffer, root)[1]
		local params = vim.lsp.util.make_position_params(0, language_client.offset_encoding)
		local response, request_error = language_client:request_sync("textDocument/definition", params, 3000, buffer)
		check_truthy("definition request completed within 3000ms", response and not response.err)
		if response and not response.err then
			local has_definition =
				has_definition_in({ response }, vim.uri_from_fname(vim.fs.joinpath(fixture, "definition.ts")))
			if not has_definition then
				fail("cross-file definition: " .. vim.inspect(response))
			end
		elseif request_error then
			fail("definition request: " .. request_error)
		end
	end

	local diagnostic_namespaces = {}
	if language_client then
		local provider = language_client.server_capabilities.diagnosticProvider
		local pull_id = type(provider) == "table" and provider.identifier or nil
		diagnostic_namespaces = {
			vim.lsp.diagnostic.get_namespace(language_client.id),
			vim.lsp.diagnostic.get_namespace(language_client.id, true, pull_id),
		}
	end
	local diagnosed = vim.wait(5000, function()
		return has_expected_diagnostic(buffer, diagnostic_namespaces)
	end, 50)
	if not diagnosed then
		fail(
			"type diagnostic TS2322 on main.ts greeting declaration within 5000ms: "
				.. vim.inspect(client_diagnostics(buffer, diagnostic_namespaces))
		)
	end

	local mapping = vim.fn.maparg("<leader>f", "n", false, true)
	local has_mapping = mapping and mapping.lhs ~= nil
	check_truthy("format action <leader>f", has_mapping)
	if has_mapping then
		vim.api.nvim_feedkeys(vim.keycode("<leader>f"), "x", false)
		local formatted = vim.wait(5000, function()
			return vim.api.nvim_buf_get_lines(buffer, 2, 3, false)[1] == "const unformatted = { answer };"
		end, 50)
		check_truthy("format action formats main.ts within 5000ms", formatted)
	end
end

local ok, err = xpcall(run, debug.traceback)
if buffer and vim.api.nvim_buf_is_valid(buffer) then
	local clients = vim.lsp.get_clients({ bufnr = buffer })
	for _, client in ipairs(clients) do
		client:stop()
	end
	local stopped = vim.wait(2000, function()
		return vim.iter(clients):all(function(client)
			return client:is_stopped()
		end)
	end, 20)
	if not stopped then
		for _, client in ipairs(clients) do
			if not client:is_stopped() then
				client:stop(true)
			end
		end
		stopped = vim.wait(1000, function()
			return vim.iter(clients):all(function(client)
				return client:is_stopped()
			end)
		end, 20)
	end
	if not stopped then
		fail("fixture cleanup: language clients did not stop; preserving " .. fixture)
		fixture_created = false
	else
		local deleted, delete_error = pcall(vim.api.nvim_buf_delete, buffer, { force = true })
		if not deleted then
			fail("fixture cleanup: could not delete buffer: " .. tostring(delete_error))
		end
	end
end
if fixture_created then
	local removed = vim.fn.delete(fixture, "rf")
	if removed ~= 0 then
		fail("fixture cleanup: could not remove " .. fixture)
	end
end
if not ok then
	fail("runner error: " .. err)
end

if #failures > 0 then
	for _, failure in ipairs(failures) do
		io.stderr:write("FAIL ", app, " TypeScript: ", failure, "\n")
	end
	vim.cmd("cquit 1")
end

io.stdout:write("PASS ", app, " TypeScript\n")
vim.cmd("qa!")

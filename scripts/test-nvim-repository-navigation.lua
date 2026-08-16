local app = vim.env.NVIM_APPNAME or "nvim"
local timeout_ms = 3000
local command_timeout_ms = 5000

local fixture
local fixture_created = false
local original_cwd = vim.fn.getcwd()
local original_tab = vim.api.nvim_get_current_tabpage()
local original_clients = {}
local failures = {}
local test_tab
local subprocesses_reaped = true

for _, client in pairs(vim.lsp.get_clients()) do
	original_clients[client.id] = true
end

local function fail(message)
	error(message, 0)
end

local function run_git(arguments)
	local command = { "git" }
	vim.list_extend(command, arguments)
	local process = vim.system(command, { cwd = fixture, text = true })
	local result = process:wait(command_timeout_ms)
	if result.code == 124 then
		process:kill(9)
		local killed = process:wait(1000)
		subprocesses_reaped = subprocesses_reaped and killed.code ~= 124
		fail(
			string.format(
				"git %s exceeded its %dms timeout (reaped=%s)",
				table.concat(arguments, " "),
				command_timeout_ms,
				tostring(killed.code ~= 124)
			)
		)
	end
	if result.code ~= 0 then
		fail(
			string.format(
				"git %s failed within %dms (exit %s):\nstdout: %s\nstderr: %s",
				table.concat(arguments, " "),
				command_timeout_ms,
				tostring(result.code),
				result.stdout or "",
				result.stderr or ""
			)
		)
	end
end

local function run_jj(arguments)
	local command = { "jj", "--no-pager" }
	vim.list_extend(command, arguments)
	local process = vim.system(command, { cwd = fixture, text = true })
	local result = process:wait(command_timeout_ms)
	if result.code == 124 then
		process:kill(9)
		local killed = process:wait(1000)
		subprocesses_reaped = subprocesses_reaped and killed.code ~= 124
		fail(
			string.format(
				"jj %s exceeded its %dms timeout (reaped=%s)",
				table.concat(arguments, " "),
				command_timeout_ms,
				tostring(killed.code ~= 124)
			)
		)
	end
	if result.code ~= 0 then
		fail(
			string.format(
				"jj %s failed within %dms (exit %s):\nstdout: %s\nstderr: %s",
				table.concat(arguments, " "),
				command_timeout_ms,
				tostring(result.code),
				result.stdout or "",
				result.stderr or ""
			)
		)
	end
end

local function wait_for(label, predicate)
	if not vim.wait(timeout_ms, predicate, 20, false) then
		fail(
			string.format(
				"%s did not become ready within %dms (buffer=%q, filetype=%q, line=%d)\nmessages:\n%s",
				label,
				timeout_ms,
				vim.api.nvim_buf_get_name(0),
				vim.bo.filetype,
				vim.api.nvim_win_get_cursor(0)[1],
				vim.api.nvim_exec2("messages", { output = true }).output
			)
		)
	end
end

local function feed(keys)
	vim.api.nvim_feedkeys(vim.keycode(keys), "xt", false)

	-- Let mappings that schedule their work receive one event-loop turn.
	vim.wait(20, function()
		return false
	end, 5, false)
end

local function listing_contains(lines, name)
	for _, line in ipairs(lines) do
		local from = 1
		while true do
			local start_index, end_index = line:find(name, from, true)
			if not start_index then
				break
			end

			local before = start_index == 1 and "" or line:sub(start_index - 1, start_index - 1)
			local after = end_index == #line and "" or line:sub(end_index + 1, end_index + 1)
			if not before:match("[%w_.-]") and not after:match("[%w_.-]") then
				return true
			end
			from = end_index + 1
		end
	end
	return false
end

local function fixture_listing()
	return vim.api.nvim_buf_get_lines(0, 0, -1, false)
end

local function check_listing(name, expected_visible)
	local lines = fixture_listing()
	local visible = listing_contains(lines, name)
	if visible ~= expected_visible then
		fail(
			string.format(
				"Oil listing for %q: expected visible=%s, observed visible=%s\nlisting:\n%s",
				name,
				expected_visible,
				visible,
				table.concat(lines, "\n")
			)
		)
	end
end

local function create_fixture()
	fixture = vim.fn.tempname() .. "-nvim-repository-navigation"
	if vim.fn.mkdir(fixture, "0700") ~= 1 then
		fail("could not create unique fixture directory: " .. fixture)
	end
	fixture_created = true

	vim.fn.writefile({ "ignored.txt" }, fixture .. "/.gitignore")
	vim.fn.writefile({ "tracked metadata" }, fixture .. "/.tracked")
	vim.fn.writefile({ "one", "two", "three", "four", "five", "six", "seven" }, fixture .. "/tracked.txt")

	run_git({ "init", "--quiet" })
	run_git({ "config", "user.email", "repository-navigation@example.test" })
	run_git({ "config", "user.name", "Repository Navigation Contract" })
	run_git({ "add", ".gitignore", ".tracked", "tracked.txt" })
	run_git({ "commit", "--quiet", "-m", "fixture" })
	run_git({ "commit", "--quiet", "--allow-empty", "-m", "working change anchor" })
	run_jj({ "git", "init", "--colocate", "." })

	vim.fn.writefile({ "untracked" }, fixture .. "/.untracked")
	vim.fn.writefile({ "ignored" }, fixture .. "/ignored.txt")
	vim.fn.writefile({ "one", "TWO", "three", "four", "five", "SIX", "seven" }, fixture .. "/tracked.txt")
end

local function exercise_contract()
	create_fixture()
	vim.cmd("tabnew")
	test_tab = vim.api.nvim_get_current_tabpage()
	vim.fn.chdir(fixture)

	feed("<leader>e")
	wait_for("Oil float", function()
		return vim.bo.filetype == "oil" and vim.api.nvim_win_get_config(0).relative ~= ""
	end)
	wait_for("Oil fixture listing", function()
		local lines = fixture_listing()
		return listing_contains(lines, ".tracked") and listing_contains(lines, "tracked.txt")
	end)
	check_listing(".tracked", true)
	check_listing("tracked.txt", true)
	check_listing(".untracked", false)
	check_listing("ignored.txt", false)

	vim.cmd("edit " .. vim.fn.fnameescape(fixture .. "/tracked.txt"))
	vim.api.nvim_win_set_cursor(0, { 1, 0 })
	wait_for("hunk-navigation mapping", function()
		return next(vim.fn.maparg("]c", "n", false, true)) ~= nil
	end)

	wait_for("first next-hunk navigation", function()
		vim.api.nvim_win_set_cursor(0, { 1, 0 })
		feed("]c")
		return vim.api.nvim_win_get_cursor(0)[1] == 2
	end)
	feed("]c")
	wait_for("second next-hunk navigation", function()
		return vim.api.nvim_win_get_cursor(0)[1] == 6
	end)
	feed("[c")
	wait_for("previous-hunk navigation", function()
		return vim.api.nvim_win_get_cursor(0)[1] == 2
	end)
	feed("V<leader>hr")
	wait_for("visual hunk reset", function()
		local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
		return lines[2] == "two" and lines[6] == "SIX"
	end)
end

local function cleanup()
	local clients_stopped = true
	for _, client in pairs(vim.lsp.get_clients()) do
		if not original_clients[client.id] then
			vim.lsp.stop_client(client.id, true)
			local client_stopped = vim.wait(1000, function()
				return vim.lsp.get_client_by_id(client.id) == nil
			end, 20, false)
			clients_stopped = clients_stopped and client_stopped
		end
	end

	local test_tab_closed = true
	if test_tab and vim.api.nvim_tabpage_is_valid(test_tab) then
		pcall(vim.api.nvim_set_current_tabpage, test_tab)
		test_tab_closed = pcall(vim.cmd, "tabclose!")
	end
	local cwd_restored = pcall(vim.fn.chdir, original_cwd)
	local original_tab_restored = pcall(vim.api.nvim_set_current_tabpage, original_tab)

	if fixture then
		local fixture_buffers_closed = true
		for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
			if vim.api.nvim_buf_is_valid(buffer) and vim.api.nvim_buf_get_name(buffer):find(fixture, 1, true) then
				pcall(vim.api.nvim_buf_delete, buffer, { force = true })
				fixture_buffers_closed = fixture_buffers_closed and not vim.api.nvim_buf_is_valid(buffer)
			end
		end

		local temporary_root = vim.uv.fs_realpath(vim.uv.os_tmpdir()) or vim.uv.os_tmpdir()
		temporary_root = vim.fs.normalize(temporary_root) .. "/"
		local real_fixture = vim.uv.fs_realpath(fixture)
		local safe_to_delete = fixture_created
			and real_fixture
			and vim.startswith(vim.fs.normalize(real_fixture), temporary_root)
			and subprocesses_reaped
			and clients_stopped
			and test_tab_closed
			and cwd_restored
			and original_tab_restored
			and fixture_buffers_closed
		if not safe_to_delete then
			failures[#failures + 1] = "fixture cleanup was incomplete; preserved: " .. fixture
		elseif vim.fn.delete(fixture, "rf") ~= 0 or vim.fn.isdirectory(fixture) == 1 then
			failures[#failures + 1] = "fixture cleanup failed; preserved: " .. fixture
		end
	end
end

local ok, error_message = xpcall(exercise_contract, debug.traceback)
if not ok then
	failures[#failures + 1] = error_message
end
cleanup()

if #failures > 0 then
	for _, failure in ipairs(failures) do
		io.stderr:write("FAIL ", app, " repository navigation: ", failure, "\n")
	end
	vim.cmd("cquit 1")
end

io.stdout:write("PASS ", app, " repository navigation\n")
vim.cmd("qa!")

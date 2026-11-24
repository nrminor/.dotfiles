-- Keep Rex's native shortcuts, with Herdr-style navigation on Cmd+B.
rex.bind("cmd+[", "pane.focus", { direction = "left" })
rex.bind("cmd+]", "pane.focus", { direction = "right" })
rex.bind("shift+enter", "pane.send_key", { key = "ctrl+j" })

for key, direction in pairs({ h = "left", j = "down", k = "up", l = "right" }) do
  rex.bind("cmd+b>" .. key, "pane.focus", { direction = direction })
  rex.bind("resize/" .. key, "pane.resize", { direction = direction, amount = 5 })
end
rex.mode("resize", { exclusive = true })
rex.bind("cmd+b>r", "client.mode.enter", { name = "resize" })
rex.bind("resize/esc", "client.mode.exit")
rex.bind("resize/enter", "client.mode.exit")
rex.bind("cmd+b>v", "pane.split", { direction = "right" })
rex.bind("cmd+b>-", "pane.split", { direction = "down" })
rex.bind("cmd+b>z", "pane.zoom")
rex.bind("cmd+b>x", "pane.close")
rex.bind("cmd+b>c", "client.tab.new")
rex.bind("cmd+b>n", "client.tab.next")
rex.bind("cmd+b>p", "client.tab.previous")
rex.bind("cmd+b>shift+t", "client.tab.rename")
rex.bind("cmd+b>shift+x", "client.tab.close")
rex.bind("cmd+b>o", "session.previous")
rex.bind("cmd+b>i", "session.next")
rex.bind("cmd+b>w", "session.switch")
rex.bind("cmd+b>shift+n", "session.new")
rex.bind("cmd+b>b", "client.sidebar.toggle")
rex.bind("cmd+b>s", "client.settings")
rex.bind("cmd+b>shift+r", "client.config.reload")
for i = 1, 9 do
  rex.bind("cmd+b>" .. i, "client.tab.goto", { index = i })
end

local function focused_cwd(ctx)
  local block_id = ctx.block_id
  if not block_id then
    local view = assert(rex.session.view({}))
    for _, window in ipairs(view.windows or {}) do
      if window.window_id == view.active_window_id then
        block_id = window.focused_block_id
        break
      end
    end
  end
  assert(block_id, "No focused terminal")
  local process = assert(rex.block.call("com.superlogical.terminal", "process", {
    block_id = block_id,
  }))
  local cwd = process.foreground and process.foreground.cwd
  assert(cwd and cwd ~= "", "Focused terminal's working directory is unavailable")
  return cwd
end

-- Local-server actions use the same Nushell startup as ordinary terminals.
-- A floating utility is a new Rex layer, not a toggle of an existing popup.
local shell = os.getenv("HOME") .. "/.local/bin/nu-login"
for _, entry in ipairs({
  { "btop", "cmd+b>alt+b", 0.8 },
  { "yazi", "cmd+b>alt+y", 0.8 },
  { "tuicr", "cmd+b>cmd+r", 0.9 },
  { "opencode", "cmd+b>alt+o" },
  { "pi", "cmd+b>alt+p" },
}) do
  local program, key, size = entry[1], entry[2], entry[3]
  rex.action({
    name = "open_" .. program,
    title = "Open " .. program,
    run = function(ctx)
      local layout = rex.layout.block({
        flavor = "com.superlogical.terminal.shell",
        options = {
          cwd = focused_cwd(ctx),
          shell = "none",
          command = { shell, "--interactive", "-c", program },
        },
      })
      if size then
        local inset = (1 - size) / 2
        return assert(rex.session.new_layer({
          bounds = { inset, inset, size, size }, focus = true, layout = layout,
        }))
      end
      return assert(rex.session.new_window({ window_label = program, layout = layout }))
    end,
  })
  rex.bind(key, "open_" .. program)
end

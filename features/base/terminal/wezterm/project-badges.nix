# WezTerm Project Badge System
# Dynamic group/project badges in tab bar based on current directory.
#
# Reads the $HOME/<projects-root>/<group>/<project>/... layout, where the root
# comes from features.base.shell.projectsRoot. Group + project names are
# extracted from the path; colors are hashed from the names so each gets a
# stable, distinct badge.
{ projectInfoLua }:

''
  -- Toggle tab bar event (per-window state via overrides)
  wezterm.on('toggle-tab-bar', function(window, pane)
    local overrides = window:get_config_overrides() or {}
    if overrides.enable_tab_bar then
      -- Hide tab bar and clear status
      overrides.enable_tab_bar = nil
      window:set_right_status("")
    else
      -- Show tab bar with project badges
      overrides.enable_tab_bar = true
      local cwd = pane:get_current_working_dir()
      local path = cwd and cwd.file_path
      local project = project_helpers.get_project_info(path)
      if project then
        local group_bg = project_helpers.color_from_string(project.group)
        local project_bg = project_helpers.color_from_string(project.group .. "/" .. project.project)
        local group_fg = project_helpers.is_dark(group_bg) and "#ffffff" or "#000000"
        local project_fg = project_helpers.is_dark(project_bg) and "#ffffff" or "#000000"
        window:set_right_status(wezterm.format({
          { Background = { Color = group_bg } },
          { Foreground = { Color = group_fg } },
          { Text = " " .. project.group .. " " },
          { Background = { Color = project_bg } },
          { Foreground = { Color = project_fg } },
          { Text = " " .. project.project .. " " },
        }))
      end
    end
    window:set_config_overrides(overrides)
  end)

  -- Update status when directory changes (reactive badges)
  wezterm.on('update-status', function(window, pane)
    local cwd = pane:get_current_working_dir()
    local path = cwd and cwd.file_path
    local project = project_helpers.get_project_info(path)

    if project then
      local group_bg = project_helpers.color_from_string(project.group)
      local project_bg = project_helpers.color_from_string(project.group .. "/" .. project.project)
      local group_fg = project_helpers.is_dark(group_bg) and "#ffffff" or "#000000"
      local project_fg = project_helpers.is_dark(project_bg) and "#ffffff" or "#000000"
      window:set_right_status(wezterm.format({
        { Background = { Color = group_bg } },
        { Foreground = { Color = group_fg } },
        { Text = " " .. project.group .. " " },
        { Background = { Color = project_bg } },
        { Foreground = { Color = project_fg } },
        { Text = " " .. project.project .. " " },
      }))
    else
      window:set_right_status("")
    end
  end)

  -- Unified agent title contract via OSC 1337 SetUserVar:
  --   tab_title       — manual override (fish set-tab-title), highest priority
  --   agent_kind      — "claude" | "opencode" (emitted by agent on start, cleared on exit)
  --   agent_session   — agent session title (optional)
  --
  -- Window title format: prepend the agent label if an agent claims this pane.
  wezterm.on('format-window-title', function(tab, pane, tabs, panes, config)
    local title = pane.title or ""
    local user_vars = pane.user_vars or {}
    local kind = user_vars.agent_kind
    if kind and #kind > 0 then
      local label = kind == "claude" and "Claude" or kind == "opencode" and "OpenCode" or kind
      return label .. ": " .. title
    end
    return title
  end)

  -- Tab title format priority chain.
  wezterm.on('format-tab-title', function(tab, tabs, panes, config, hover, max_width)
    local pane = tab.active_pane
    local user_vars = pane.user_vars or {}

    -- 1. Manual override
    -- 2. agent_session (set by the agent itself)
    -- 3. agent_kind label (Claude / OpenCode) when agent is running but no session yet
    local custom = user_vars.tab_title
    if not (custom and #custom > 0) and user_vars.agent_session and #user_vars.agent_session > 0 then
      custom = user_vars.agent_session
    end
    if not (custom and #custom > 0) and user_vars.agent_kind and #user_vars.agent_kind > 0 then
      local k = user_vars.agent_kind
      custom = k == "claude" and "Claude" or k == "opencode" and "OpenCode" or k
    end

    if custom and #custom > 0 then
      local bg = hsl_to_hex((hash_string("tab:" .. custom) % 360) / 360, 0.35, 0.25)
      local fg = is_dark(bg) and "#ffffff" or "#000000"
      local badges_width = 0
      local cwd = pane.current_working_dir
      if cwd and cwd.file_path then
        local project = project_helpers.get_project_info(cwd.file_path)
        if project then
          badges_width = #(" " .. project.group .. " ") + #(" " .. project.project .. " ") - 3
        end
      end
      local title_text = " " .. custom .. " "
      local title_width = wezterm.column_width(title_text)
      local total_width = max_width - badges_width
      if total_width > title_width then
        title_text = title_text .. string.rep(" ", total_width - title_width)
      end
      return {
        { Background = { Color = bg } },
        { Foreground = { Color = fg } },
        { Text = title_text },
      }
    end

    -- 4. Otherwise show foreground process (if not fish)
    if pane.foreground_process_name then
      local process = pane.foreground_process_name:match("([^/]+)$")
      if process and process ~= "fish" then
        return process
      end
    end

    -- 5. If in project directory - show project name
    local cwd = pane.current_working_dir
    if cwd and cwd.file_path then
      local project = project_helpers.get_project_info(cwd.file_path)
      if project then
        return project.project
      end
      -- 6. Fallback: current directory
      return cwd.file_path:match("([^/]+)$") or "~"
    end

    return "terminal"
  end)
''

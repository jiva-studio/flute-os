-- Extract group/project from a path like $HOME/<projects-root>/<group>/<project>/...
--
-- The root is not hardcoded: @PROJECTS_ROOT@ is substituted at build time from
-- features.base.shell.projectsRoot (see ./default.nix), already escaped for use
-- inside a Lua pattern. The placeholder keeps this file valid Lua on its own.
local PROJECTS_ROOT = '@PROJECTS_ROOT@'

local function get_project_info(path)
  if not path then return nil end
  local group, project = path:match('/' .. PROJECTS_ROOT .. '/([^/]+)/([^/]+)')
  if group and project then
    return { group = group, project = project }
  end
  return nil
end

-- Generate hash from string
local function hash_string(str)
  local hash = 5381
  for i = 1, #str do
    hash = ((hash * 33) + str:byte(i)) % 0xFFFFFFFF
  end
  return hash
end

-- Convert HSL to RGB hex
local function hsl_to_hex(h, s, l)
  local function hue_to_rgb(p, q, t)
    if t < 0 then t = t + 1 end
    if t > 1 then t = t - 1 end
    if t < 1/6 then return p + (q - p) * 6 * t end
    if t < 1/2 then return q end
    if t < 2/3 then return p + (q - p) * (2/3 - t) * 6 end
    return p
  end
  local r, g, b
  if s == 0 then
    r, g, b = l, l, l
  else
    local q = l < 0.5 and l * (1 + s) or l + s - l * s
    local p = 2 * l - q
    r = hue_to_rgb(p, q, h + 1/3)
    g = hue_to_rgb(p, q, h)
    b = hue_to_rgb(p, q, h - 1/3)
  end
  return string.format("#%02x%02x%02x", math.floor(r * 255), math.floor(g * 255), math.floor(b * 255))
end

-- Generate color from string (different hue per string, good saturation)
local function color_from_string(str)
  local h = (hash_string(str) % 360) / 360
  return hsl_to_hex(h, 0.65, 0.45)  -- saturated, medium lightness
end

-- Check if color is dark (for text contrast)
local function is_dark(hex)
  local r = tonumber(hex:sub(2, 3), 16) / 255
  local g = tonumber(hex:sub(4, 5), 16) / 255
  local b = tonumber(hex:sub(6, 7), 16) / 255
  local luminance = 0.299 * r + 0.587 * g + 0.114 * b
  return luminance < 0.5
end

local M = {}

local function trim(value)
  return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function scalar(value)
  value = trim(value)
  if #value >= 2 then
    local first = value:sub(1, 1)
    local last = value:sub(-1)
    if (first == '"' and last == '"') or (first == "'" and last == "'") then
      return value:sub(2, -2)
    end
  end
  if value == "true" then
    return true
  end
  if value == "false" then
    return false
  end
  if value:match("^%-?%d+$") then
    return tonumber(value)
  end
  return value
end

function M.parse(text)
  local lines = vim.split(text or "", "\n", { plain = true })
  local meta = {}
  if not lines[1] or trim(lines[1]) ~= "---" then
    return { meta = meta, body_start = 1 }
  end
  local current
  for index = 2, #lines do
    local line = lines[index]
    if trim(line) == "---" then
      return { meta = meta, body_start = index + 1 }
    end
    local key, value = line:match("^%s*([%w_-]+)%s*:%s*(.*)$")
    if key then
      current = key
      if trim(value) == "" then
        meta[key] = {}
      elseif trim(value):sub(1, 1) == "[" and trim(value):sub(-1) == "]" then
        meta[key] = M.list(value)
      else
        meta[key] = scalar(value)
      end
    elseif current and type(meta[current]) == "table" then
      local item = line:match("^%s*%-%s*(.+)$")
      if item then
        meta[current][#meta[current] + 1] = scalar(item)
      end
    end
  end
  return { meta = meta, body_start = #lines }
end

function M.list(value)
  if type(value) == "table" then
    return value
  end
  if type(value) ~= "string" then
    return {}
  end
  value = trim(value)
  if value == "" then
    return {}
  end
  if value:sub(1, 1) == "[" and value:sub(-1) == "]" then
    local out = {}
    for item in value:sub(2, -2):gmatch("[^,]+") do
      local parsed = scalar(item)
      if parsed ~= "" then
        out[#out + 1] = parsed
      end
    end
    return out
  end
  return { scalar(value) }
end

function M.tags(value)
  local out = {}
  for _, tag in ipairs(M.list(value)) do
    if type(tag) == "string" then
      tag = trim(tag):gsub("^#", "")
      if tag ~= "" then
        out[#out + 1] = tag
      end
    end
  end
  return out
end

return M

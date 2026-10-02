local M = {}

M.defaults = {
  root = nil,
  max_files = 20000,
  extensions = nil,
  ignore = {
    ".git",
    ".hg",
    ".svn",
    ".obsidian",
    "node_modules",
    "target",
    "dist",
    "build",
    "vendor",
    ".venv",
    "venv",
    "__pycache__",
    "zig-cache",
    ".zig-cache",
    "zig-out",
  },
  cache = {
    enabled = true,
  },
  links = {
    include_markdown = true,
    include_embeds = true,
    scan_all_files = false,
    link_extensions = { ".md", ".mdx", ".markdown", ".txt", ".org", ".rst", ".adoc", ".tex", ".typ" },
    case_sensitive = false,
  },
  graph = {
    max_nodes = 500,
    linked_only = true,
    show_function_edges = false,
    show_unresolved = false,
    show_orphans = true,
    animate = true,
    fps = 30,
    iterations = 240,
    edge_length = 16,
    repulsion = 1.0,
    spring = 1.0,
    gravity = 0.06,
    window = {
      width = 0.85,
      height = 0.85,
      border = "rounded",
    },
    label_max = 28,
    label_count = 80,
  },
  ui = {
    return_to_previous = true,
  },
}

M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
  return M.options
end

function M.get()
  return M.options
end

local root_markers = { ".git", ".hg", "Cargo.toml", "package.json", "pyproject.toml", "go.mod", "Makefile" }

local function find_root(start)
  local found = vim.fs.find(root_markers, { path = start, upward = true, type = "directory" })
  if #found == 0 then
    found = vim.fs.find(root_markers, { path = start, upward = true, type = "file" })
  end
  return found[1] and vim.fs.dirname(found[1]) or nil
end

local function is_container(dir)
  local util = require("nvaph.util")
  return dir == util.normalize(vim.fn.expand("~"))
    or dir == "/Users"
    or dir == "/"
    or vim.fs.basename(dir) == "Projects"
end

local function root_info(opts)
  opts = opts or {}
  local util = require("nvaph.util")
  if opts.root then
    return { root = util.normalize(vim.fn.expand(opts.root)), shallow = false }
  end
  if M.options.root then
    return { root = util.normalize(vim.fn.expand(M.options.root)), shallow = false }
  end
  local name = vim.api.nvim_buf_get_name(0)
  local absolute = name:sub(1, 1) == "/" or name:match("^%a:[/\\]")
  if absolute then
    local dir = vim.fs.dirname(name)
    if dir and vim.fn.isdirectory(dir) == 1 then
      dir = util.normalize(dir)
      local detected = find_root(dir)
      if detected then
        return { root = util.normalize(detected), shallow = false }
      end
      return { root = dir, shallow = is_container(dir) }
    end
  end
  local cwd = util.normalize(vim.fn.getcwd())
  local detected = find_root(cwd)
  if detected then
    return { root = util.normalize(detected), shallow = false }
  end
  if is_container(cwd) then
    return { root = nil, shallow = true }
  end
  return { root = cwd, shallow = false }
end

function M.root_info(opts)
  return root_info(opts)
end

function M.root(opts)
  return root_info(opts).root
end

function M.shallow(opts)
  return root_info(opts).shallow
end

return M

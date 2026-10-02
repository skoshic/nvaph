vim.opt.runtimepath:prepend(vim.fn.getcwd())

local M = {
  passed = 0,
  failed = 0,
}

local function fail(name, message)
  M.failed = M.failed + 1
  io.stderr:write("FAIL " .. name .. ": " .. message .. "\n")
end

local function test(name, callback)
  local ok, message = xpcall(callback, debug.traceback)
  if ok then
    M.passed = M.passed + 1
  else
    fail(name, message)
  end
end

local function equal(actual, expected, message)
  if actual ~= expected then
    error((message or "values differ") .. ": expected " .. vim.inspect(expected) .. ", got " .. vim.inspect(actual), 2)
  end
end

local function contains(list, value)
  for _, item in ipairs(list) do
    if item == value then
      return true
    end
  end
  return false
end

local parser = require("nvaph.links.parser")
local frontmatter = require("nvaph.links.frontmatter")
local resolver = require("nvaph.links.resolve")
local index = require("nvaph.index")
local model = require("nvaph.graph.model")
local layout = require("nvaph.graph.layout")
local render = require("nvaph.graph.render")
local helpers = require("tests.helpers")

test("frontmatter parses lists and scalars", function()
  local parsed = frontmatter.parse("---\ntitle: Demo\naliases:\n  - Bee\ntags: [one, two]\n---\n# Body\n")
  equal(parsed.meta.title, "Demo")
  equal(parsed.meta.aliases[1], "Bee")
  equal(parsed.meta.tags[2], "two")
end)

test("parser ignores fenced and inline code", function()
  local text = "# Note\n[[Alpha]]\n[[Beta|B]]\n![[Image]]\n```text\n[[Fenced]]\n```\n`[[Inline]]`\n[Markdown](Gamma.md#Head)\n"
  local links = parser.parse(text)
  equal(#links, 4)
  equal(links[1].target, "Alpha")
  equal(links[2].alias, "B")
  equal(links[3].kind, "embed")
  equal(links[4].kind, "markdown")
  equal(links[4].target, "Gamma.md")
  equal(links[4].fragment, "Head")
  for _, link in ipairs(links) do
    equal(link.target ~= "Fenced", true)
    equal(link.target ~= "Inline", true)
  end
end)

test("resolver handles aliases and ambiguous basenames", function()
  local files = {
    { path = "folder/One.md", stem = "One", title = "First", aliases = { "Bee" } },
    { path = "Other/One.md", stem = "One", title = "Second", aliases = {} },
  }
  local lookup = resolver.build_lookup(files, { case_sensitive = false })
  equal(resolver.resolve({ target = "Bee" }, files[1], lookup, {}).file.path, "folder/One.md")
  equal(resolver.resolve({ target = "folder/One" }, files[1], lookup, {}).status, "resolved")
  equal(resolver.resolve({ target = "One" }, files[1], lookup, {}).status, "ambiguous")
  equal(resolver.resolve({ target = "Nope" }, files[1], lookup, {}).status, "unresolved")
end)

test("index builds files, edges, ghosts, and degrees", function()
  local root = helpers.temp_project({
    ["Index.md"] = "# Index\n[[Alpha]]\n[[Missing]]\n",
    ["Alpha.md"] = "# Alpha\n[[Beta]]\n",
    ["Beta.md"] = "# Beta\n",
  })
  local data = index.build(root, { cache = false, extensions = { ".md" }, ignore = {} })
  equal(#data.files, 3)
  equal(#data.edges, 2)
  equal(#data.unresolved, 1)
  equal(data.by_path["Alpha.md"].in_degree, 1)
  equal(data.by_path["Beta.md"].in_degree, 1)
  helpers.remove(root)
end)

test("project index links arbitrary source files", function()
  local root = helpers.temp_project({
    ["notes.md"] = "# Notes\n[[src/main.rs]]\n",
    ["src/main.rs"] = "fn main() {}\n",
  })
  local data = index.build(root, { cache = false, ignore = {} })
  equal(data.by_path["src/main.rs"].title, "src/main.rs")
  equal(data.by_path["notes.md"].out_degree, 1)
  equal(data.by_path["src/main.rs"].in_degree, 1)
  local graph = model.build(data, { linked_only = true, show_unresolved = false })
  equal(#graph.nodes, 2)
  helpers.remove(root)
end)

test("an unmarked directory is still a project", function()
  local root = helpers.temp_project({
    ["PROJECTS.md"] = "# Projects\n",
    ["alden/notes.md"] = "# Alden\n[[something]]\n",
  })
  vim.cmd("edit " .. root .. "/PROJECTS.md")
  require("nvaph.config").setup({ cache = { enabled = false } })
  local data = require("nvaph.actions").data({ silent = true })
  equal(data.root, require("nvaph.util").normalize(root))
  equal(data.shallow, false)
  equal(#data.files, 2)
  helpers.remove(root)
end)

test("container directories stay shallow", function()
  local root = helpers.temp_project({
    ["Projects/PROJECTS.md"] = "# Projects\n",
    ["Projects/alden/notes.md"] = "# Alden\n[[something]]\n",
  })
  vim.cmd("edit " .. root .. "/Projects/PROJECTS.md")
  require("nvaph.config").setup({ cache = { enabled = false } })
  local data = require("nvaph.actions").data({ silent = true })
  equal(data.root, require("nvaph.util").normalize(root .. "/Projects"))
  equal(data.shallow, true)
  equal(#data.files, 1)
  equal(#data.edges, 0)
  helpers.remove(root)
end)

test("unsaved buffer content is indexed", function()
  local root = helpers.temp_project({
    ["notes.md"] = "# Notes\n",
    ["target.md"] = "# Target\n",
  })
  require("nvaph.config").setup({ root = root, cache = { enabled = false } })
  vim.cmd("edit " .. root .. "/notes.md")
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "# Notes", "[[target]]" })
  local data = require("nvaph.actions").data({ silent = true })
  equal(#data.edges, 1)
  equal(data.edges[1].target, "target.md")
  vim.cmd("enew!")
  helpers.remove(root)
end)

test("function edges are hidden by default", function()
  local data = {
    files = {
      { path = "a.md", title = "A", stem = "a", aliases = {}, tags = {}, in_degree = 0, out_degree = 0 },
      { path = "b.md", title = "B", stem = "b", aliases = {}, tags = {}, in_degree = 0, out_degree = 0 },
    },
    edges = { { source = "a.md", target = "b.md", kind = "function", count = 1, links = {} } },
    unresolved = {},
  }
  local hidden = model.build(data, { linked_only = true, show_function_edges = false })
  equal(#hidden.nodes, 0)
  local visible = model.build(data, { linked_only = true, show_function_edges = true })
  equal(#visible.nodes, 2)
end)

test("unlinked files and unresolved targets stay out of the default graph", function()
  local root = helpers.temp_project({
    ["notes.md"] = "# Notes\n[[missing]]\n",
    ["src/main.rs"] = "fn main() {}\n",
  })
  local data = index.build(root, { cache = false, ignore = {} })
  equal(#data.unresolved, 1)
  local graph = model.build(data, { linked_only = true, show_unresolved = false })
  equal(#graph.nodes, 0)
  helpers.remove(root)
end)


test("layout is deterministic and finite", function()
  local root = helpers.temp_project({
    ["A.md"] = "# A\n[[B]]\n",
    ["B.md"] = "# B\n[[C]]\n",
    ["C.md"] = "# C\n",
  })
  local data = index.build(root, { cache = false, extensions = { ".md" }, ignore = {} })
  local graph = model.build(data, { show_unresolved = false, max_nodes = 100 })
  local first = layout.new(graph, 80, 40, { iterations = 30 })
  local second = layout.new(graph, 80, 40, { iterations = 30 })
  first:run()
  second:run()
  for id, point in pairs(first:positions_map()) do
    equal(point.x == point.x, true)
    equal(point.y == point.y, true)
    equal(point.x, second:positions_map()[id].x)
  end
  helpers.remove(root)
end)


test("cache reuses an unchanged project", function()
  local root = helpers.temp_project({
    ["A.md"] = "# A\n[[B]]\n",
    ["B.md"] = "# B\n",
  })
  local opts = { cache = true, extensions = { ".md" }, ignore = {} }
  local first = index.build(root, opts)
  local second = index.build(root, opts)
  equal(#first.files, #second.files)
  equal(#second.edges, 1)
  helpers.remove(root)
end)

test("renderer produces text, spans, and a hitmap", function()
  local root = helpers.temp_project({
    ["A.md"] = "# A\n[[B]]\n",
    ["B.md"] = "# B\n",
  })
  local data = index.build(root, { cache = false, extensions = { ".md" }, ignore = {} })
  local graph = model.build(data, { show_unresolved = false, max_nodes = 100 })
  local positions = layout.new(graph, 80, 40, { iterations = 30 })
  positions:run()
  local frame = render.build(graph, positions:positions_map(), 40, 20, { label_count = 10 })
  equal(#frame.lines, 20)
  equal(#frame.spans > 0, true)
  equal(frame.hitmap ~= nil, true)
  local found
  for id, cell in pairs(frame.node_cell) do
    found = render.hit_cell(frame, cell.row, cell.col)
    equal(found, id)
    break
  end
  equal(found ~= nil, true)
  helpers.remove(root)
end)

io.stdout:write(string.format("nvaph tests: %d passed, %d failed\n", M.passed, M.failed))
if M.failed > 0 then
  vim.cmd("cq")
end

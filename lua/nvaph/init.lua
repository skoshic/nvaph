local M = {}
local autocmd_group

local function install_autocmds()
  if autocmd_group then
    return
  end
  autocmd_group = vim.api.nvim_create_augroup("Nvaph", { clear = true })
  vim.api.nvim_create_autocmd({ "BufReadPost", "BufWritePost" }, {
    group = autocmd_group,
    pattern = "*",
    callback = function(args)
      local config = require("nvaph.config")
      local root = config.root()
      if root and require("nvaph.util").is_within(args.file, root) then
        require("nvaph.index").invalidate(root)
      end
    end,
  })
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = autocmd_group,
    callback = function()
      require("nvaph.graph.render").define_highlights()
    end,
  })
end

function M.autoload()
  install_autocmds()
  require("nvaph.graph.render").define_highlights()
end

function M.setup(opts)
  local result = require("nvaph.config").setup(opts)
  M.autoload()
  return result
end

function M.graph(opts)
  return require("nvaph.actions").graph(opts)
end

function M.completion()
  return require("nvaph.completion").cmp_source()
end

return M

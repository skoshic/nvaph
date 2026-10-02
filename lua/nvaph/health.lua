local M = {}

function M.check()
  local health = vim.health
  health.start("nvaph")
  health.info("Neovim " .. tostring(vim.version().major) .. "." .. tostring(vim.version().minor))
  health.info("LuaJIT available: " .. tostring(_G.jit ~= nil))
  local config = require("nvaph.config").get()
  local root = require("nvaph.config").root()
  health.info("Root: " .. (root or "not detected"))
  health.info("Cache: " .. tostring(config.cache.enabled))
  if root and vim.fn.isdirectory(root) == 0 then
    health.error("Root does not exist")
  end
  if not root then
    health.info("Open a project file or configure a root to enable Nvaph")
  end
end

return M

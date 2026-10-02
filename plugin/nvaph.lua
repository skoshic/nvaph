vim.api.nvim_create_user_command("GraphView", function(args)
  require("nvaph").graph({ root = args.args ~= "" and args.args or nil })
end, { nargs = "?", desc = "Open the project graph" })

require("nvaph").autoload()

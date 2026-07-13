-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")

vim.api.nvim_create_user_command("Format", function()
  LazyVim.format({ force = true })
end, { desc = "Format selection or buffer" })

vim.api.nvim_create_user_command("FormatInfo", function()
  LazyVim.format.info()
end, { desc = "Show formatters for the current buffer" })

vim.api.nvim_create_autocmd("FileType", {
  pattern = { "cs", "java" },
  callback = function()
    vim.opt_local.expandtab = false
    vim.opt_local.shiftwidth = 4
    vim.opt_local.softtabstop = 0
    vim.opt_local.tabstop = 4
  end,
  desc = "Use tabs for C# and Java indentation",
})

local function conform_formatters()
  require("lazy").load({ plugins = { "conform.nvim" } })
  return require("conform").list_all_formatters()
end

local function format_with(name)
  require("lazy").load({ plugins = { "conform.nvim" } })
  local default_filetypes = {
    biome = "json",
    jq = "json",
  }

  if vim.bo.filetype == "" and default_filetypes[name] then
    vim.bo.filetype = default_filetypes[name]
  end

  require("conform").format({
    bufnr = 0,
    formatters = { name },
    lsp_format = "never",
  })
end

vim.api.nvim_create_user_command("FormatChoose", function()
  local formatters = vim.tbl_filter(function(formatter)
    return formatter.available
  end, conform_formatters())

  vim.ui.select(formatters, {
    prompt = "Formatter",
    format_item = function(formatter)
      return formatter.name
    end,
  }, function(formatter)
    if formatter then
      format_with(formatter.name)
    end
  end)
end, { desc = "Choose a formatter for the current buffer" })

vim.api.nvim_create_user_command("FormatWith", function(opts)
  format_with(opts.args)
end, {
  nargs = 1,
  complete = function(arg_lead)
    return vim.tbl_filter(
      function(name)
        return name:find(arg_lead, 1, true) == 1
      end,
      vim.tbl_map(function(formatter)
        return formatter.name
      end, conform_formatters())
    )
  end,
  desc = "Format current buffer with a specific formatter",
})

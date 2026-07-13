local function telescope_references()
  local bufnr = vim.api.nvim_get_current_buf()
  local win = vim.api.nvim_get_current_win()
  local clients = vim.lsp.get_clients({ bufnr = bufnr, method = "textDocument/references" })

  if vim.tbl_isempty(clients) then
    vim.notify("No LSP client with references support attached", vim.log.levels.INFO)
    return
  end

  local items = {}
  local pending = #clients
  local errors = {}

  local function finish()
    pending = pending - 1
    if pending > 0 then
      return
    end

    if vim.tbl_isempty(items) then
      local suffix = vim.tbl_isempty(errors) and "" or (": " .. table.concat(errors, "; "))
      vim.notify("No LSP references found" .. suffix, vim.log.levels.INFO)
      return
    end

    local opts = {}
    local conf = require("telescope.config").values
    require("telescope.pickers")
      .new(opts, {
        prompt_title = "LSP References",
        finder = require("telescope.finders").new_table({
          results = items,
          entry_maker = require("telescope.make_entry").gen_from_quickfix(opts),
        }),
        previewer = conf.qflist_previewer(opts),
        sorter = conf.generic_sorter(opts),
        push_cursor_on_edit = true,
        push_tagstack_on_edit = true,
      })
      :find()
  end

  for _, client in ipairs(clients) do
    local params = vim.lsp.util.make_position_params(win, client.offset_encoding)
    params.context = { includeDeclaration = true }

    client:request("textDocument/references", params, function(err, result)
      if err then
        errors[#errors + 1] = client.name .. ": " .. (err.message or tostring(err))
      elseif result and not vim.tbl_isempty(result) then
        vim.list_extend(items, vim.lsp.util.locations_to_items(result, client.offset_encoding))
      end

      vim.schedule(finish)
    end, bufnr)
  end
end

return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        ["*"] = {
          keys = {
            { "gr", telescope_references, desc = "References", has = "references", nowait = true },
            { "grr", telescope_references, desc = "References", has = "references", nowait = true },
          },
        },
      },
    },
  },
}

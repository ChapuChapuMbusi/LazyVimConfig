local source_cache = {}

local function normalize(path)
  return vim.fs.normalize(vim.fn.fnamemodify(path, ":p"))
end

local function add_root(roots, seen, path)
  if not path or path == "" then
    return
  end

  path = normalize(path)
  local stat = vim.uv.fs_stat(path)
  if stat and stat.type == "directory" and not seen[path] then
    seen[path] = true
    roots[#roots + 1] = path
  end
end

local function project_cwd()
  local cwd = vim.fn.getcwd(0, 0)
  if cwd == "" then
    cwd = vim.uv.cwd()
  end
  return cwd
end

local function is_within(path, root)
  if not path or not root then
    return false
  end

  path = normalize(path)
  root = normalize(root)
  return path == root or path:sub(1, #root + 1) == root .. "/"
end

local function workspace_roots(bufnr)
  local roots = {}
  local seen = {}
  local cwd = project_cwd()

  add_root(roots, seen, cwd)

  for _, client in ipairs(vim.lsp.get_clients({ name = "jdtls", bufnr = bufnr })) do
    local root_dir = client.config and client.config.root_dir
    if is_within(root_dir, cwd) then
      add_root(roots, seen, root_dir)
    end

    for _, folder in ipairs(client.workspace_folders or {}) do
      local folder_path = vim.uri_to_fname(folder.uri)
      if is_within(folder_path, cwd) then
        add_root(roots, seen, folder_path)
      end
    end
  end

  local current = vim.api.nvim_buf_get_name(bufnr)
  if current ~= "" and not current:match("^jdt://") then
    local current_root = vim.fs.root(current, { "pom.xml", "build.gradle", "settings.gradle", ".git" })
    if is_within(current_root, cwd) then
      add_root(roots, seen, current_root)
    end
  end

  return roots
end

local function java_files(root)
  if source_cache[root] then
    return source_cache[root]
  end

  local files = {}
  if vim.fn.executable("rg") == 1 then
    files = vim.fn.systemlist({ "rg", "--files", "--glob", "*.java", root })
    if vim.v.shell_error ~= 0 then
      files = {}
    end
  else
    files = vim.fs.find(function(name)
      return name:sub(-5) == ".java"
    end, { path = root, type = "file", limit = math.huge })
  end

  local by_name = {}
  for _, file in ipairs(files) do
    file = normalize(file)
    local name = vim.fn.fnamemodify(file, ":t")
    by_name[name] = by_name[name] or {}
    by_name[name][#by_name[name] + 1] = file
  end

  source_cache[root] = by_name
  return by_name
end

local function package_from_buffer(bufnr)
  for _, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, 80, false)) do
    local package_name = line:match("^%s*package%s+([%w_.]+)%s*;")
    if package_name then
      return package_name
    end
  end
end

local function type_from_buffer(bufnr)
  for _, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, 200, false)) do
    local type_name = line:match("%f[%w_]class%s+([%w_]+)%f[^%w_]")
      or line:match("%f[%w_]interface%s+([%w_]+)%f[^%w_]")
      or line:match("%f[%w_]enum%s+([%w_]+)%f[^%w_]")
      or line:match("%f[%w_]record%s+([%w_]+)%f[^%w_]")
    if type_name then
      return type_name
    end
  end
end

local function class_info_from_uri(uri)
  uri = tostring(uri or "")
  local decoded = vim.uri_decode(uri:gsub("[?#].*$", ""))
  local type_name = decoded:match("([^/%$]+)%$[^/]*%.class$") or decoded:match("([^/]+)%.class$")
  if not type_name then
    return
  end

  local package_path
  local segment, rest = decoded:match("contents/[^/]+/([^/]+)/(.+%.class)$")
  if rest then
    rest = rest:gsub("%$[^/]*%.class$", ".java"):gsub("%.class$", ".java")
    if rest:find("/", 1, true) then
      package_path = rest
    elseif segment and segment:find("%.") then
      package_path = segment:gsub("%.", "/") .. "/" .. rest
    end
  end

  if not package_path then
    local path = decoded
    if path:match("^file://") then
      path = vim.uri_to_fname(path)
    end
    package_path = path:match("src/[^/]+/java/(.+)%.class$")
    if package_path then
      package_path = package_path:gsub("%$[^/]*$", "") .. ".java"
    end
  end

  return {
    type_name = type_name,
    file_name = type_name .. ".java",
    package_path = package_path,
  }
end

local function class_info_from_buffer(bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr)
  if not (name:match("^jdt://") or name:match("%.class$")) then
    return
  end

  local info = class_info_from_uri(name) or {}
  info.type_name = type_from_buffer(bufnr) or info.type_name
  if not info.type_name then
    return
  end

  local package_name = package_from_buffer(bufnr)
  if package_name then
    info.package_path = package_name:gsub("%.", "/") .. "/" .. info.type_name .. ".java"
  end
  info.file_name = info.type_name .. ".java"
  return info
end

local function score_candidate(path, package_path, root_index)
  local score = 1000 - root_index
  if package_path and path:sub(-#package_path) == package_path then
    score = score + 10000
  end
  if path:find("/src/main/java/", 1, true) then
    score = score + 200
  elseif path:find("/src/test/java/", 1, true) then
    score = score + 100
  end
  return score
end

local function resolve_source(info, roots)
  if not (info and info.file_name) then
    return
  end

  local best
  local best_score = -math.huge
  local matches = 0
  for root_index, root in ipairs(roots) do
    for _, path in ipairs(java_files(root)[info.file_name] or {}) do
      if not info.package_path or path:sub(-#info.package_path) == info.package_path then
        matches = matches + 1
        local score = score_candidate(path, info.package_path, root_index)
        if score > best_score then
          best = path
          best_score = score
        end
      end
    end
  end

  if best then
    return best
  end

  if info.package_path then
    return
  end

  for root_index, root in ipairs(roots) do
    for _, path in ipairs(java_files(root)[info.file_name] or {}) do
      matches = matches + 1
      local score = score_candidate(path, nil, root_index)
      if score > best_score then
        best = path
        best_score = score
      end
    end
  end

  return matches > 0 and best or nil
end

local function type_declaration_line(path, type_name)
  if not type_name then
    return 1, 1, ""
  end

  local ok, lines = pcall(vim.fn.readfile, path, "", 400)
  if not ok then
    return 1, 1, ""
  end

  local escaped = vim.pesc(type_name)
  for index, line in ipairs(lines) do
    if
      line:match("%f[%w_]class%s+" .. escaped .. "%f[^%w_]")
      or line:match("%f[%w_]interface%s+" .. escaped .. "%f[^%w_]")
      or line:match("%f[%w_]enum%s+" .. escaped .. "%f[^%w_]")
      or line:match("%f[%w_]record%s+" .. escaped .. "%f[^%w_]")
    then
      return index, 1, line
    end
  end

  return 1, 1, lines[1] or ""
end

local function set_cursor_safely(lnum, col)
  lnum = tonumber(lnum) or 1
  col = tonumber(col) or 0

  local line_count = vim.api.nvim_buf_line_count(0)
  lnum = math.max(1, math.min(lnum, line_count))

  local line = vim.api.nvim_buf_get_lines(0, lnum - 1, lnum, false)[1] or ""
  col = math.max(0, math.min(col, #line))

  vim.api.nvim_win_set_cursor(0, { lnum, col })
end

local function filename_from_location(item)
  local uri = item.user_data and (item.user_data.uri or item.user_data.targetUri)
  local filename = uri or item.filename
  if not filename or filename == "" then
    return
  end

  filename = tostring(filename)
  if filename:match("^file://") then
    local ok, decoded = pcall(vim.uri_to_fname, filename)
    if ok and decoded and decoded ~= "" then
      return decoded
    end
  end

  return filename
end

local function jump_to_file(path, type_name)
  local lnum, col = type_declaration_line(path, type_name)
  vim.cmd("normal! m'")
  vim.cmd.edit(vim.fn.fnameescape(path))
  set_cursor_safely(lnum, math.max(col - 1, 0))
  vim.cmd("normal! zv")
end

local function fallback_jump(item)
  local filename = filename_from_location(item)
  if not filename then
    return
  end

  vim.cmd("normal! m'")
  vim.cmd.edit(vim.fn.fnameescape(filename))
  if item.lnum then
    set_cursor_safely(item.lnum, math.max((item.col or 1) - 1, 0))
    vim.cmd("normal! zv")
  end
end

local function rewrite_item(item, roots)
  local uri = item.user_data and (item.user_data.uri or item.user_data.targetUri) or item.filename
  local info = class_info_from_uri(uri)
  local source = resolve_source(info, roots)
  if not source then
    return
  end

  local lnum, col, text = type_declaration_line(source, info.type_name)
  item.filename = source
  item.bufnr = nil
  item.lnum = lnum
  item.col = col
  item.end_lnum = lnum
  item.end_col = col
  item.text = text
  item._jdtls_source = source
  item._jdtls_type = info.type_name
end

local function goto_implementation()
  local bufnr = vim.api.nvim_get_current_buf()
  local roots = workspace_roots(bufnr)
  local current_source = resolve_source(class_info_from_buffer(bufnr), roots)

  if current_source then
    jump_to_file(current_source, class_info_from_buffer(bufnr).type_name)
    return
  end

  vim.lsp.buf.implementation({
    on_list = function(options)
      local items = options.items or {}
      for _, item in ipairs(items) do
        rewrite_item(item, roots)
      end

      if vim.tbl_isempty(items) then
        vim.notify("No implementations found", vim.log.levels.INFO)
      elseif #items == 1 then
        if items[1]._jdtls_source then
          jump_to_file(items[1]._jdtls_source, items[1]._jdtls_type)
        else
          fallback_jump(items[1])
        end
      else
        vim.fn.setqflist({}, " ", {
          title = options.title or "LSP implementations",
          items = items,
        })
        vim.cmd("botright copen")
      end
    end,
  })
end

return {
  {
    "neovim/nvim-lspconfig",
    init = function()
      vim.api.nvim_create_autocmd("LspAttach", {
        group = vim.api.nvim_create_augroup("jdtls-source-navigation", { clear = true }),
        callback = function(args)
          local client = vim.lsp.get_client_by_id(args.data.client_id)
          if not (client and client.name == "jdtls") then
            return
          end

          vim.schedule(function()
            if vim.api.nvim_buf_is_valid(args.buf) then
              vim.keymap.set("n", "gI", goto_implementation, {
                buffer = args.buf,
                desc = "Goto Implementation",
              })
            end
          end)
        end,
      })
    end,
    opts = function(_, opts)
      opts.servers = opts.servers or {}
      opts.servers["*"] = opts.servers["*"] or {}
      opts.servers["*"].keys = opts.servers["*"].keys or {}
      table.insert(opts.servers["*"].keys, {
        "gI",
        goto_implementation,
        desc = "Goto Implementation",
        has = "implementation",
      })
    end,
  },
}

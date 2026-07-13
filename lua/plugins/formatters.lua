return {
  {
    "mason-org/mason.nvim",
    opts = {
      ensure_installed = {
        "biome",
        "java-debug-adapter",
        "jdtls",
        "json-lsp",
      },
    },
  },
  {
    "neovim/nvim-lspconfig",
    opts = {
      inlay_hints = {
        exclude = { "java", "vue" },
      },
      servers = {
        jdtls = {},
        jsonls = {},
      },
    },
  },
  {
    "mfussenegger/nvim-jdtls",
    opts = function(_, opts)
      local mason = vim.env.MASON or (vim.fn.stdpath("data") .. "/mason")
      local java21 = vim.fn.expand("~/.local/share/mise/installs/java/21.0.2/bin/java")
      local java = vim.uv.fs_stat(java21) and java21 or vim.fn.exepath("java")

      if java:match("/mise/shims/java$") and vim.fn.executable("mise") == 1 then
        local mise_java = vim.trim(vim.fn.system({ "mise", "which", "java" }))
        if vim.v.shell_error == 0 and mise_java ~= "" then
          java = mise_java
        end
      end

      local jdtls_dir = mason .. "/packages/jdtls"
      local launcher = vim.fn.glob(jdtls_dir .. "/plugins/org.eclipse.equinox.launcher_*.jar")
      opts.cmd = {
        java ~= "" and java or "java",
        "-Declipse.application=org.eclipse.jdt.ls.core.id1",
        "-Dosgi.bundles.defaultStartLevel=4",
        "-Declipse.product=org.eclipse.jdt.ls.core.product",
        "-Dosgi.checkConfiguration=true",
        "-Dosgi.sharedConfiguration.area=" .. jdtls_dir .. "/config_linux",
        "-Dosgi.sharedConfiguration.area.readOnly=true",
        "-Dosgi.configuration.cascaded=true",
        "-Xms1G",
        "--add-modules=ALL-SYSTEM",
        "--add-opens",
        "java.base/java.util=ALL-UNNAMED",
        "--add-opens",
        "java.base/java.lang=ALL-UNNAMED",
      }

      local lombok = mason .. "/share/jdtls/lombok.jar"
      if vim.uv.fs_stat(lombok) then
        table.insert(opts.cmd, "-javaagent:" .. lombok)
      end

      vim.list_extend(opts.cmd, { "-jar", launcher })

      opts.settings = vim.tbl_deep_extend("force", opts.settings or {}, {
        java = {
          format = {
            enabled = true,
          },
          inlayHints = {
            parameterNames = {
              enabled = "none",
            },
          },
        },
      })

      local existing_jdtls = opts.jdtls
      opts.jdtls = function(config, ...)
        if type(existing_jdtls) == "function" then
          config = existing_jdtls(config, ...) or config
        elseif existing_jdtls then
          config = vim.tbl_deep_extend("force", config, existing_jdtls)
        end

        local function disable_unstable_jdtls_features(client)
          client.server_capabilities.inlayHintProvider = false
          client.server_capabilities.semanticTokensProvider = nil
          client.server_capabilities.foldingRangeProvider = false
          if client.server_capabilities.completionProvider then
            client.server_capabilities.completionProvider.resolveProvider = false
          end
        end

        local function suppress_empty_jdtls_responses(client)
          local original_write_error = client.write_error
          if type(original_write_error) ~= "function" or client._mysas_jdtls_error_filter then
            return
          end

          client._mysas_jdtls_error_filter = true
          client.write_error = function(self, code, err)
            local is_empty_response = code == vim.lsp.rpc.client_errors.INVALID_SERVER_MESSAGE
              and type(err) == "table"
              and err.jsonrpc == "2.0"
              and err.id ~= nil
              and err.result == nil
              and err.error == nil
              and err.method == nil

            if is_empty_response then
              vim.notify_once(
                "Ignoring malformed empty response from jdtls. See :LspLog for details.",
                vim.log.levels.DEBUG
              )
              return
            end

            return original_write_error(self, code, err)
          end
        end

        local existing_on_init = config.on_init
        config.on_init = function(client, initialize_result)
          disable_unstable_jdtls_features(client)
          suppress_empty_jdtls_responses(client)
          if existing_on_init then
            existing_on_init(client, initialize_result)
          end
        end

        local existing_on_attach = config.on_attach
        config.on_attach = function(client, bufnr)
          disable_unstable_jdtls_features(client)
          suppress_empty_jdtls_responses(client)
          if existing_on_attach then
            existing_on_attach(client, bufnr)
          end
        end

        return config
      end
    end,
  },
  {
    "stevearc/conform.nvim",
    opts = {
      formatters_by_ft = {
        java = {},
        json = { "jq" },
        jsonc = { "jq" },
        json5 = { "jq" },
      },
      formatters = {
        biome = {
          args = function(self, ctx)
            local filename = ctx.filename ~= "" and "$FILENAME" or "scratch.json"
            if self:cwd(ctx) then
              return { "format", "--stdin-file-path", filename }
            end
            return {
              "format",
              "--stdin-file-path",
              filename,
              "--indent-style",
              vim.bo[ctx.buf].expandtab and "space" or "tab",
              "--indent-width",
              ctx.shiftwidth,
            }
          end,
        },
      },
    },
  },
}

return {
  {
    "mfussenegger/nvim-jdtls",
    opts = {
      settings = {
        java = {
          configuration = {
            runtimes = {
              {
                name = "JavaSE-21",
                path = vim.fn.expand("~/.local/share/mise/installs/java/21.0.2"),
                default = true,
              },
            },
          },
          format = {
            enabled = true,
          },
          saveActions = {
            organizeImports = false,
          },
        },
      },
    },
  },
}

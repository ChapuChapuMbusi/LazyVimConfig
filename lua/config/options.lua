-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here
vim.opt.relativenumber = false
vim.g.lazyvim_picker = "telescope"
-- Enable this option to avoid conflicts with Prettier.
vim.g.lazyvim_prettier_needs_config = true

-- Allow trusted project-local .nvim.lua files, such as MySAS DAP configs.
vim.opt.exrc = true
vim.opt.secure = true

if vim.g.loaded_vsplit_asm then
  return
end
vim.g.loaded_vsplit_asm = true

if vim.fn.has("nvim-0.10") == 0 then
  vim.notify("vsplit_asm.nvim requires Neovim >= 0.10 (vim.system)", vim.log.levels.ERROR)
  return
end

-- :VsplitAsm [compiler] [flags...]   e.g.  :VsplitAsm gcc -O2 -march=native
vim.api.nvim_create_user_command("VsplitAsm", function(opts)
  local args = opts.fargs
  local cc = table.remove(args, 1)
  require("vsplit_asm").run(cc, args)
end, {
  nargs = "*",
  complete = function(_, line)
    -- Complete compiler names for the first argument only.
    if #vim.split(line, "%s+") <= 2 then
      return { "clang", "gcc" }
    end
  end,
  desc = "Compile current file and show its linked disassembly in a vsplit",
})

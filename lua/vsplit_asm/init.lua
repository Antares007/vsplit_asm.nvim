local M = {}

M.config = {
  -- One flag per line, same format clang uses.
  compile_flags_file = "compile_flags.txt",
  -- Passed to objdump before the ELF path. Use "-D" instead of "-d" to also dump data.
  objdump_args = { "-m", "i386:x86-64", "-d", "-M", "intel" },
  -- Set to true to create <leader>1/2/3/0 (gcc) and <leader>!/@/#/) (clang) mappings.
  keymaps = false,
  leader = "<leader>",
}

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.ERROR, { title = "vsplit_asm" })
end

-- Run a command without a shell. Returns the result table, or nil and an error message.
local function exec(cmd, cwd)
  local ok, res = pcall(function()
    return vim.system(cmd, { text = true, cwd = cwd }):wait()
  end)
  if not ok then
    return nil, tostring(res)
  end
  if res.code ~= 0 then
    return nil, res.stderr ~= "" and res.stderr or res.stdout
  end
  return res
end

local function read_flags(dir)
  local path = dir .. "/" .. M.config.compile_flags_file
  if vim.fn.filereadable(path) == 0 then
    return {}
  end
  local flags = {}
  for _, line in ipairs(vim.fn.readfile(path)) do
    for _, flag in ipairs(vim.split(line, "%s+", { trimempty = true })) do
      flags[#flags + 1] = flag
    end
  end
  return flags
end

-- Flat linker script: every section packed together, plus a 0x10-byte slot for
-- each undefined symbol so the link succeeds and calls get readable labels.
local function linker_script(obj)
  local res, err = exec({ "nm", "--undefined-only", obj })
  if not res then
    return nil, err
  end
  local stubs = {}
  for line in res.stdout:gmatch("[^\n]+") do
    local sym = line:match("^%s*U%s+(%S+)")
    if sym then
      stubs[#stubs + 1] = ("%s = .; . += 0x10;"):format(sym)
    end
  end
  return "SECTIONS { "
    .. ".text   : { *(.text .text.*); } "
    .. ".data   : { *(.rodata .rodata.*); *(.data .data.*); *(.bss .bss.*); *(COMMON); } "
    .. ".extern : { " .. table.concat(stubs, " ") .. " BYTE(0xab); } "
    .. "/DISCARD/ : { *(.comment); *(.note*); *(.eh_frame); } }"
end

--- Compile the current file, link it flat, and show the disassembly in a vsplit.
---@param cc string|nil     compiler, default "clang"
---@param cflags string|string[]|nil  extra flags, e.g. "-O2"
function M.run(cc, cflags)
  cc = cc or "clang"
  if type(cflags) == "string" then
    cflags = vim.split(vim.trim(cflags), "%s+", { trimempty = true })
  end
  cflags = cflags or {}

  local path = vim.api.nvim_buf_get_name(0)
  if path == "" then
    return notify("Current buffer has no file")
  end

  local name = vim.fn.expand("<cword>")
  local dir = vim.fn.fnamemodify(path, ":p:h")
  local src = vim.fn.fnamemodify(path, ":t")
  vim.cmd("silent! write")

  local base = vim.fn.tempname() .. '.' .. cc
  local obj, ld, elf, asm = base .. ".o", base .. ".ld", base .. ".elf", base .. ".asm"

  -- 1. compile
  local cmd = { cc }
  vim.list_extend(cmd, read_flags(dir))
  vim.list_extend(cmd, { "-c", src })
  vim.list_extend(cmd, cflags)
  vim.list_extend(cmd, { "-o", obj })

  local res, err = exec(cmd, dir)
  if not res then
    return notify(err)
  end

  -- 2. link (-e 0 silences GNU ld's "cannot find entry symbol _start")
  local script
  script, err = linker_script(obj)
  if not script then
    return notify(err)
  end
  vim.fn.writefile({ script }, ld)
  res, err = exec({ "ld", "-T", ld, obj, "-o", elf, "-e", "0" })
  if not res then
    return notify(err)
  end

  -- 3. disassemble
  local dump = { "objdump" }
  vim.list_extend(dump, M.config.objdump_args)
  dump[#dump + 1] = elf
  res, err = exec(dump)
  if not res then
    return notify(err)
  end
  vim.fn.writefile(vim.split(res.stdout, "\n"), asm)

  -- 4. show
  vim.cmd("vsplit " .. vim.fn.fnameescape(asm))
  vim.cmd("normal! gg0")
  if name ~= "" then
    local label = "<" .. vim.fn.escape(name, [[\/.*$^~[]]) .. ">:"
    if vim.fn.search(label, "w") > 0 then
      vim.cmd("normal! zt")
    end
  end
end

local function set_keymaps()
  local leader = M.config.leader
  local levels = {
    { digit = "3", shifted = "#", opt = "-O3" },
    { digit = "2", shifted = "@", opt = "-O2" },
    { digit = "1", shifted = "!", opt = "-O1" },
    { digit = "0", shifted = ")", opt = "-O0" },
  }
  for _, l in ipairs(levels) do
    for cc, key in pairs({ gcc = l.digit, clang = l.shifted }) do
      vim.keymap.set("n", leader .. key, function()
        M.run(cc, l.opt)
      end, { silent = true, desc = ("Asm: %s %s"):format(cc, l.opt) })
    end
  end
end

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
  if M.config.keymaps then
    set_keymaps()
  end
end

return M

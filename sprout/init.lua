-- sprout/init.lua -- entry point for running .sprout files and the REPL.
--
-- Usage:
--   luajit sprout/init.lua <file.sprout>   -- compile and run
--   luajit sprout/init.lua                 -- interactive REPL
--   luajit sprout/init.lua --emit <file>   -- print the emitted Lua
--   luajit sprout/init.lua --tokenize <f>  -- print token stream
--   luajit sprout/init.lua --parse <f>     -- print AST

-- Resolve the runtime library relative to this file.
local this_dir = (arg and arg[0] and arg[0]:match("(.*/)")) or "./"
package.path = this_dir .. "?.lua;"
            .. this_dir .. "runtime/?.lua;"
            .. package.path

local Tokenizer = require("tokenizer")
local Parser    = require("parser")
local Emitter   = require("emitter")
local sprout    = require("sprout")

local M = {}

function M.tokenize(src, filename)
  return Tokenizer.tokenize(src, filename)
end

function M.parse(src, filename)
  return Parser.parse(Tokenizer.tokenize(src, filename), filename)
end

function M.compile(src, filename)
  local tokens = Tokenizer.tokenize(src, filename)
  local tree   = Parser.parse(tokens, filename)
  local em     = Emitter.new{ filename = filename or "<input>" }
  return em:emit_file(tree)
end

function M.compile_file(path)
  local f, err = io.open(path, "r")
  if not f then error("cannot read " .. path .. ": " .. tostring(err), 2) end
  local src = f:read("*a")
  f:close()
  return M.compile(src, path)
end

local load_chunk
if loadstring then
  load_chunk = function(src, name) return loadstring(src, name) end
else
  load_chunk = function(src, name) return load(src, name, "t") end
end

local function run_chunk(lua_src, chunk_name)
  local fn, err = load_chunk(lua_src, chunk_name or "<sprout>")
  if not fn then
    error("compile error in emitted Lua: " .. tostring(err)
          .. "\n--- source ---\n" .. lua_src, 2)
  end
  return fn()
end

function M.run_file(path)
  local lua_src = M.compile_file(path)
  return run_chunk(lua_src, "@" .. path)
end

function M.run_source(src, filename)
  local lua_src = M.compile(src, filename)
  return run_chunk(lua_src, filename or "<sprout>")
end

function M.repl()
  io.write("sprout 0.1 (LuaJIT)  -- type a line, ctrl-d to exit\n")
  local scope = sprout.new_scope()
  local defined = {}

  local function step(line)
    local tokens = Tokenizer.tokenize(line, "<repl>")
    local tree   = Parser.parse(tokens, "<repl>")
    local em     = Emitter.new{ filename = "<repl>", persistent_scope = defined }
    local chunk  = em:emit_repl(tree)
    for k in pairs(em.known) do defined[k] = true end

    local wrapped =
      "local scope, send, block, list, sprout = ...\n" .. chunk .. "\n"
    local fn, err = load_chunk(wrapped, "<repl>")
    if not fn then error("REPL compile error: " .. tostring(err), 0) end
    return fn(scope, sprout.send, sprout.block, sprout.list, sprout)
  end

  while true do
    io.write("> "); io.flush()
    local line = io.read("*l")
    if not line then io.write("\n"); break end
    if not line:match("^%s*$") then
      local ok, result = pcall(step, line)
      if not ok then
        io.write("error: " .. tostring(result) .. "\n")
      elseif result ~= nil then
        io.write(sprout.format_for_display(result) .. "\n")
      end
    end
  end
end

-- Command line
if arg and arg[0] and arg[0]:match("init%.lua$") then
  local args = arg
  if #args == 0 then
    M.repl()
  elseif args[1] == "--tokenize" then
    local f = assert(io.open(args[2], "r"))
    local src = f:read("*a"); f:close()
    for _, t in ipairs(Tokenizer.tokenize(src, args[2])) do
      io.write(string.format("%-12s %s\n", t.type, tostring(t.value)))
    end
  elseif args[1] == "--parse" then
    local f = assert(io.open(args[2], "r"))
    local src = f:read("*a"); f:close()
    local tree = Parser.parse(Tokenizer.tokenize(src, args[2]), args[2])
    local function dump(cell, indent)
      indent = indent or ""
      io.write(indent .. "cell(" .. cell.kind .. ") steps=" .. #cell.steps .. "\n")
      for i, step in ipairs(cell.steps) do
        io.write(indent .. "  step " .. i .. ":\n")
        for _, el in ipairs(step) do
          if el.kind then dump(el, indent .. "    ")
          else io.write(indent .. "    " .. el.type .. ": " .. tostring(el.value) .. "\n") end
        end
      end
    end
    dump(tree)
  elseif args[1] == "--emit" then
    io.write(M.compile_file(args[2]))
  elseif args[1] == "--help" or args[1] == "-h" then
    io.write("usage: luajit sprout/init.lua [--tokenize|--parse|--emit] [file.sprout]\n")
  else
    M.run_file(args[1])
  end
end

return M

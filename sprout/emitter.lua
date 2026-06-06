-- emitter.lua -- Sprout AST -> Lua source.
--
-- Compile model:
--   * Every step becomes one Lua line.
--   * `name : RHS` is recognised syntactically and lowered to
--       scope.data.name = RHS_eval
--   * `lit OP lit` lowers to native Lua arithmetic ((1 + 1) etc.).
--   * `[block]` becomes either `list(...)` (when the block is one step of
--       only literals) or `block(scope, function(at_) ... end)`.
--   * `(group)` is an eager parenthesised expression.
--   * All other steps emit a left-to-right chain of `send(...)` calls.
--
-- Chain rule for a step of n elements:
--   * First element is the receiver expression (resolved).
--   * Walking i = 2..n:
--       - If step[i] is a symbol and step[i+1] exists:
--           emit send(acc, "<sym>", arg_eval) ; consume 2
--       - If step[i] is a symbol and i == n:
--           emit send(acc, "<sym>") ; consume 1
--       - If step[i] is a literal/block/group:
--           emit send(acc, value_eval) ; consume 1
--
-- Scope model (per spec §23.10): names are fields on the enclosing scope
-- cell.  `x : 5` writes scope.data.x; `x` reads scope.data.x.  Block bodies
-- read/write the same scope, with `@` bound as the block parameter (lowered
-- to the Lua local `at_`).  The emitter tracks defined names so that
-- undefined references become compile errors.

local M = {}

-- ---------------------------------------------------------------------
-- Names provided by the Cell mixin -- always resolvable.
local CELL_MIXIN = {
  ["say"]=true, ["if"]=true, ["while"]=true, ["until"]=true,
  ["match"]=true, ["map"]=true, ["each"]=true,
  ["true"]=true, ["false"]=true,
  ["length"]=true, ["first"]=true, ["last"]=true,
  ["not"]=true, ["="]=true,
}

local ARITH_MSGS = { ["+"]=true, ["-"]=true, ["*"]=true, ["/"]=true, ["%"]=true }
local CMP_MSGS   = { ["<"]=true, [">"]=true, ["<="]=true, [">="]=true }

-- Lua reserved words (so we don't emit `scope.data.if`).
local LUA_KEYWORDS = {
  ["and"]=true, ["break"]=true, ["do"]=true, ["else"]=true,
  ["elseif"]=true, ["end"]=true, ["false"]=true, ["for"]=true,
  ["function"]=true, ["goto"]=true, ["if"]=true, ["in"]=true,
  ["local"]=true, ["nil"]=true, ["not"]=true, ["or"]=true,
  ["repeat"]=true, ["return"]=true, ["then"]=true, ["true"]=true,
  ["until"]=true, ["while"]=true,
}

local function q(s) return string.format("%q", s) end

local function is_number_token(el)
  return el and el.type == "number"
end

local function is_arith_op(el)
  return el and el.type == "symbol"
     and (ARITH_MSGS[el.value] or CMP_MSGS[el.value] or el.value == "=")
end

local function all_literals(step)
  if #step < 1 then return false end
  for _, el in ipairs(step) do
    if not (el.type == "number" or el.type == "string") then
      return false
    end
  end
  return true
end

-- Map from Cell-mixin name to the Lua local that the prologue defines.
-- These are hoisted because the runtime stores them on sprout.Cell.data
-- (not scope.data) and LuaJIT traces are faster through locals than table
-- chains -- see spec §23.13.
local MIXIN_LOCALS = {
  ["say"]     = "C_say",
  ["if"]      = "C_if",
  ["while"]   = "C_while",
  ["until"]   = "C_until",
  ["match"]   = "C_match",
  ["map"]     = "C_map",
  ["each"]    = "C_each",
  ["length"]  = "C_length",
  ["first"]   = "C_first",
  ["last"]    = "C_last",
  ["not"]     = "C_not",
  ["="]       = "C_eq",
  ["true"]    = "true",
  ["false"]   = "false",
}

-- Reference a name as a Lua expression.  `@` -> `at_`.  Cell-mixin names
-- use their hoisted local.  Hyphenated or reserved names use the indexed
-- form scope.data["name"].
local function data_ref(name)
  if name == "@" then return "at_" end
  if MIXIN_LOCALS[name] then return MIXIN_LOCALS[name] end
  if name:find("[-?!]") or LUA_KEYWORDS[name] then
    return "scope.data[" .. q(name) .. "]"
  end
  return "scope.data." .. name
end

-- ---------------------------------------------------------------------
local Emitter = {}
Emitter.__index = Emitter

function M.new(opts)
  opts = opts or {}
  local e = setmetatable({
    filename   = opts.filename or "<input>",
    scopes     = { {} },              -- stack of {name=true}
    known      = {},                  -- flat set of names ever defined here
    in_block   = 0,                   -- block-nesting depth (for `@`)
    persistent = opts.persistent_scope,
  }, Emitter)
  if opts.persistent_scope then
    for k in pairs(opts.persistent_scope) do
      e.scopes[1][k] = true
      e.known[k] = true
    end
  end
  return e
end

function Emitter:define(name)
  self.scopes[#self.scopes][name] = true
  self.known[name] = true
end

function Emitter:is_defined(name)
  if CELL_MIXIN[name] then return true end
  if name == "@" and self.in_block > 0 then return true end
  for i = #self.scopes, 1, -1 do
    if self.scopes[i][name] then return true end
  end
  return false
end

function Emitter:fail(tok, msg)
  error(string.format("%s:%d:%d: %s",
    tok.file or self.filename, tok.line or 0, tok.col or 0, msg), 0)
end

-- ---------------------------------------------------------------------
-- Emit a single element as a Lua value expression.
function Emitter:emit_value(el)
  if el.kind == "block" then
    return self:emit_block(el)
  elseif el.kind == "group" then
    return self:emit_group(el)
  elseif el.type == "number" then
    return tostring(el.value)
  elseif el.type == "string" then
    return q(el.value)
  elseif el.type == "symbol" then
    local name = el.value
    if name == "true"  then return "true"  end
    if name == "false" then return "false" end
    if not self:is_defined(name) then
      self:fail(el, "undefined name: '" .. name .. "'")
    end
    return data_ref(name)
  else
    error("emit_value: unexpected element " .. tostring(el.type or el.kind))
  end
end

-- Is the element a "value" (non-symbol)?  These chain into bare `send(acc, val)`.
local function is_value_element(el)
  return el.kind == "block" or el.kind == "group"
      or el.type == "number" or el.type == "string"
end

-- ---------------------------------------------------------------------
-- Emit an expression (one parsed step).
function Emitter:emit_expr(step)
  if #step == 0 then return "nil" end

  -- List literal: a step whose only contents are >=2 number/string tokens.
  if #step >= 2 and all_literals(step) then
    local parts = {}
    for i, el in ipairs(step) do parts[i] = self:emit_value(el) end
    return "list(" .. table.concat(parts, ", ") .. ")"
  end

  -- Assignment: NAME `:` RHS...
  if #step >= 3 and step[1].type == "symbol"
     and step[2].type == "symbol" and step[2].value == ":"
  then
    local name = step[1].value
    self:define(name)
    local rhs_step = {}
    for i = 3, #step do rhs_step[#rhs_step+1] = step[i] end
    local rhs_src = self:emit_expr(rhs_step)
    return data_ref(name) .. " = " .. rhs_src
  end

  -- Numeric lowering: `lit OP lit` -> native Lua op.
  if #step == 3 and is_number_token(step[1])
     and is_arith_op(step[2]) and is_number_token(step[3])
  then
    local op = step[2].value
    if op == "=" then op = "==" end
    return "(" .. tostring(step[1].value) .. " " .. op .. " "
               .. tostring(step[3].value) .. ")"
  end

  -- General left-to-right chain.
  --   first element        -> receiver, value-resolved
  --   subsequent symbol with follow-up   -> binary send(acc, "<sym>", next_eval)
  --   subsequent symbol w/o follow-up:
  --       defined in scope -> value-resolve, send(acc, value)
  --       not defined      -> message-string, send(acc, "<sym>")
  --   subsequent literal/block/group     -> send(acc, value)
  local acc = self:emit_value(step[1])
  local i = 2
  while i <= #step do
    local el = step[i]
    if el.type == "symbol" then
      local msg = el.value
      if i + 1 <= #step then
        local arg_src = self:emit_value(step[i+1])
        acc = "send(" .. acc .. ", " .. q(msg) .. ", " .. arg_src .. ")"
        i = i + 2
      else
        if self:is_defined(msg) or msg == "true" or msg == "false" then
          local arg_src = self:emit_value(el)
          acc = "send(" .. acc .. ", " .. arg_src .. ")"
        else
          acc = "send(" .. acc .. ", " .. q(msg) .. ")"
        end
        i = i + 1
      end
    elseif is_value_element(el) then
      local arg_src = self:emit_value(el)
      acc = "send(" .. acc .. ", " .. arg_src .. ")"
      i = i + 1
    else
      self:fail(el, "unexpected element in chain")
    end
  end
  return acc
end

-- ---------------------------------------------------------------------
-- Block: `[...]`.  Two cases:
--   1. The block is one step of all-literal contents (`[1 2 3]`, `[1]`):
--      emit as a list literal directly.
--   2. Otherwise emit as a deferred closure carrying its scope.
function Emitter:emit_block(cell)
  if #cell.steps == 1 then
    local s = cell.steps[1]
    if #s >= 1 and all_literals(s) then
      local parts = {}
      for i, el in ipairs(s) do parts[i] = self:emit_value(el) end
      return "list(" .. table.concat(parts, ", ") .. ")"
    end
  end

  table.insert(self.scopes, {})
  self.in_block = self.in_block + 1

  local lines = {}
  for idx, step in ipairs(cell.steps) do
    local src = self:emit_expr(step)
    if idx == #cell.steps then
      -- last step: return its value (unless it's an assignment statement)
      if src:find("^scope%.data") and src:find("=") and not src:find("^send") then
        lines[#lines+1] = "    " .. src
        lines[#lines+1] = "    return nil"
      else
        lines[#lines+1] = "    return " .. src
      end
    else
      if src:find("^scope%.data") and src:find("=") and not src:find("^send") then
        lines[#lines+1] = "    " .. src
      else
        lines[#lines+1] = "    local _ = " .. src
      end
    end
  end
  if #lines == 0 then lines[1] = "    return nil" end

  self.in_block = self.in_block - 1
  table.remove(self.scopes)

  return "block(scope, function(at_)\n" .. table.concat(lines, "\n") .. "\n  end)"
end

-- ---------------------------------------------------------------------
-- Group: `(...)`.  Eager.  Empty -> nil.  Single step -> parens around the
-- expression.  Multi-step -> IIFE returning the last step's value.
function Emitter:emit_group(cell)
  if #cell.steps == 0 then return "nil" end
  if #cell.steps == 1 then
    return "(" .. self:emit_expr(cell.steps[1]) .. ")"
  end
  local lines = {}
  for i = 1, #cell.steps - 1 do
    lines[#lines+1] = "    local _ = " .. self:emit_expr(cell.steps[i])
  end
  lines[#lines+1] = "    return " .. self:emit_expr(cell.steps[#cell.steps])
  return "(function()\n" .. table.concat(lines, "\n") .. "\n  end)()"
end

-- ---------------------------------------------------------------------
-- File emission: prelude + every step on its own line.
local function step_is_assignment(step)
  return #step >= 3
     and step[1] and step[1].type == "symbol"
     and step[2] and step[2].type == "symbol" and step[2].value == ":"
end

-- Hoist Cell-mixin names into Lua locals at the top of every emitted
-- file (see spec §23.13).  Two locals per name (the Lua local + a comment
-- naming the Sprout-side identifier) are deliberately avoided for cycle
-- speed; the comments below are debug-friendly enough.
local function prologue()
  local lines = {
    "local sprout = require('sprout')",
    "local send   = sprout.send",
    "local block  = sprout.block",
    "local list   = sprout.list",
    "local Cell_data = sprout.Cell.data",
    "local C_say    = Cell_data['say']",
    "local C_if     = Cell_data['if']",
    "local C_while  = Cell_data['while']",
    "local C_until  = Cell_data['until']",
    "local C_match  = Cell_data['match']",
    "local C_map    = Cell_data['map']",
    "local C_each   = Cell_data['each']",
    "local C_length = Cell_data['length']",
    "local C_first  = Cell_data['first']",
    "local C_last   = Cell_data['last']",
    "local C_not    = Cell_data['not']",
    "local C_eq     = Cell_data['=']",
    "local scope = sprout.new_scope()",
  }
  return table.concat(lines, "\n") .. "\n"
end

function Emitter:emit_file(root)
  local out = {}
  if not self.persistent then
    out[#out+1] = "-- " .. self.filename .. " compiled by sprout 0.1"
    out[#out+1] = prologue()
  end
  for _, step in ipairs(root.steps) do
    local src = self:emit_expr(step)
    if step_is_assignment(step) then
      out[#out+1] = src
    else
      out[#out+1] = "local _ = " .. src
    end
  end
  return table.concat(out, "\n") .. "\n"
end

-- REPL form: outputs a chunk whose last expression returns its value.
function Emitter:emit_repl(root)
  local out = {}
  for idx, step in ipairs(root.steps) do
    local src = self:emit_expr(step)
    local is_last = idx == #root.steps
    if step_is_assignment(step) then
      out[#out+1] = src
      if is_last then out[#out+1] = "return nil" end
    else
      if is_last then
        out[#out+1] = "return " .. src
      else
        out[#out+1] = "local _ = " .. src
      end
    end
  end
  if #out == 0 then out[1] = "return nil" end
  return table.concat(out, "\n")
end

return M

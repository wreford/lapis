-- sprout.lua -- runtime library for the Sprout language
-- Hand-written Lua that both user programs and the Sprout emitter call.
-- The emitter's output looks indistinguishable from hand-written calls
-- into this module.

local sprout = {}

-- =========================================================================
-- Cell representation
-- =========================================================================
local function is_cell(v) return type(v) == "table" and v.data ~= nil end
sprout.is_cell = is_cell

function sprout.cell(init)
  local c = { data = {}, parent = sprout.Cell }
  if init then
    for k, v in pairs(init) do c.data[k] = v end
  end
  return c
end

-- =========================================================================
-- Lists
-- =========================================================================
function sprout.list(...)
  local n = select("#", ...)
  local c = { data = {}, parent = sprout.Cell, kind = "list" }
  for i = 1, n do c.data[i] = (select(i, ...)) end
  return c
end

-- =========================================================================
-- Blocks (deferred evaluation)
-- =========================================================================
function sprout.block(scope, fn)
  return {
    data   = {},
    parent = sprout.Cell,
    kind   = "block",
    scope  = scope,
    fn     = fn,
  }
end

function sprout.force(b, arg)
  if type(b) == "table" and b.kind == "block" then
    return b.fn(arg)
  end
  return b
end
local force = sprout.force

-- =========================================================================
-- Mixin (dead copy)
-- =========================================================================
function sprout.mixin(target, src)
  if not is_cell(target) or not is_cell(src) then
    error("mixin: both target and src must be cells", 2)
  end
  for k, v in pairs(src.data) do
    if target.data[k] == nil then target.data[k] = v end
  end
  return target
end

-- =========================================================================
-- Operator tables (fast paths for primitive receivers)
-- =========================================================================
local number_ops, string_ops, bool_ops = {}, {}, {}

number_ops["+"]  = function(a, b) return a + b end
number_ops["-"]  = function(a, b) return a - b end
number_ops["*"]  = function(a, b) return a * b end
number_ops["/"]  = function(a, b) return a / b end
number_ops["%"]  = function(a, b) return a % b end
number_ops["<"]  = function(a, b) return a <  b end
number_ops[">"]  = function(a, b) return a >  b end
number_ops["<="] = function(a, b) return a <= b end
number_ops[">="] = function(a, b) return a >= b end
number_ops["="]  = function(a, b) return a == b end
number_ops[".."] = function(a, b) return tostring(a) .. tostring(b) end

string_ops[".."]     = function(a, b) return a .. tostring(b) end
string_ops["="]      = function(a, b) return a == b end
string_ops["<"]      = function(a, b) return a <  b end
string_ops[">"]      = function(a, b) return a >  b end
string_ops["length"] = function(a)    return #a end
string_ops["first"]  = function(a)    return a:sub(1, 1) end
string_ops["last"]   = function(a)    return a:sub(-1) end

bool_ops["="]   = function(a, b) return a == b end
bool_ops["not"] = function(a)    return not a end
bool_ops["and"] = function(a, b)
  if not a then return false end
  return force(b)
end
bool_ops["or"] = function(a, b)
  if a then return a end
  return force(b)
end

-- =========================================================================
-- send: the core dispatch
-- =========================================================================
-- send(recv, msg, arg):
--   * primitive receiver + op-string msg -> fast path
--   * function receiver -> recv(msg, arg) (function IS the "step", msg is its arg)
--   * cell receiver -> look up msg in data, walking the parent chain.
--       found function   -> call(recv, arg)
--       found block      -> force(found, arg)
--       found other      -> return it as a value
--   * if no field found and the cell has __apply__, treat the cell as
--     a callable: __apply__(recv, msg, arg).
local function send(recv, msg, arg)
  -- Message-is-callable fast path: trailing-symbol value-resolves to a
  -- Cell-mixin function (e.g. `[1 2 3] length` -> send(list, C_length)).
  -- Apply the function to the receiver.
  local mt = type(msg)
  if mt == "function" then return msg(recv, arg) end

  local rt = type(recv)
  if rt == "number" then
    if mt == "string" then
      local op = number_ops[msg]
      if op then return op(recv, arg) end
    end
  elseif rt == "string" then
    if mt == "string" then
      local op = string_ops[msg]
      if op then return op(recv, arg) end
    end
  elseif rt == "boolean" then
    if mt == "string" then
      local op = bool_ops[msg]
      if op then return op(recv, arg) end
    end
  elseif rt == "function" then
    return recv(msg, arg)
  elseif rt == "table" and recv.data then
    local cur = recv
    while cur do
      local found = cur.data[msg]
      if found ~= nil then
        local ft = type(found)
        if ft == "function" then return found(recv, arg) end
        if ft == "table" and found.kind == "block" then return found.fn(arg) end
        return found
      end
      cur = cur.parent
    end
    -- Fall-through: cell-as-callable
    local ap = recv.data["__apply__"]
    if ap then return ap(recv, msg, arg) end
    error("cell has no '" .. tostring(msg) .. "'", 2)
  end
  error("cannot send '" .. tostring(msg) .. "' to "
        .. rt .. " value " .. tostring(recv), 2)
end
sprout.send = send

-- =========================================================================
-- Structural equality
-- =========================================================================
local function deep_equal(a, b)
  if a == b then return true end
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return false end
  local ad, bd = a.data, b.data
  if not ad or not bd then return false end
  for k, v in pairs(ad) do
    if not deep_equal(v, bd[k]) then return false end
  end
  for k in pairs(bd) do
    if ad[k] == nil then return false end
  end
  return true
end
sprout.deep_equal = deep_equal

-- =========================================================================
-- Display formatter
-- =========================================================================
local function format_for_display(v, seen)
  seen = seen or {}
  local t = type(v)
  if t == "number" or t == "boolean" then return tostring(v) end
  if t == "string" then return v end
  if t == "nil" then return "," end
  if t == "function" then return "<native>" end
  if t == "table" then
    if seen[v] then return "<cycle>" end
    seen[v] = true
    if v.kind == "block" then return "<block>" end
    if v.kind == "error" then
      return "error(" .. tostring(v.data.kind or "?") .. "): "
             .. tostring(v.data.message or "")
    end
    local n, only_int = 0, true
    for k in pairs(v.data) do
      if type(k) == "number" and k == math.floor(k) and k >= 1 then
        if k > n then n = k end
      else
        only_int = false
      end
    end
    if only_int and n > 0 then
      local parts = {}
      for i = 1, n do parts[i] = format_for_display(v.data[i], seen) end
      return "[" .. table.concat(parts, ", ") .. "]"
    end
    local parts = {}
    for k, val in pairs(v.data) do
      parts[#parts+1] = tostring(k) .. " : " .. format_for_display(val, seen)
    end
    table.sort(parts)
    return "{" .. table.concat(parts, ", ") .. "}"
  end
  return tostring(v)
end
sprout.format_for_display = format_for_display

-- =========================================================================
-- Standard library cells (Cell mixin)
-- =========================================================================

-- say receives whatever is sent and prints it.  Function receiver, msg=arg.
local function stdlib_say(msg, _) io.write(format_for_display(msg) .. "\n"); return msg end

local function len_of(recv)
  if type(recv) == "string" then return #recv end
  if is_cell(recv) then
    local n = 0
    for k in pairs(recv.data) do
      if type(k) == "number" and k == math.floor(k) and k >= 1 and k > n then
        n = k
      end
    end
    return n
  end
  error("length: not a list or string", 2)
end

local function stdlib_length(recv) return len_of(recv) end
local function stdlib_first(recv)
  if type(recv) == "string" then return recv:sub(1, 1) end
  if is_cell(recv) then return recv.data[1] end
  error("first: not a list or string", 2)
end
local function stdlib_last(recv)
  if type(recv) == "string" then return recv:sub(-1) end
  if is_cell(recv) then return recv.data[len_of(recv)] end
  error("last: not a list or string", 2)
end

local function stdlib_each(recv, block)
  if not is_cell(recv) then error("each: receiver must be a list", 2) end
  local n = len_of(recv)
  for i = 1, n do force(block, recv.data[i]) end
  return recv
end

local function stdlib_map(recv, block)
  if not is_cell(recv) then error("map: receiver must be a list", 2) end
  local n = len_of(recv)
  local out = { data = {}, parent = sprout.Cell, kind = "list" }
  for i = 1, n do out.data[i] = force(block, recv.data[i]) end
  return out
end

-- ---------------------------------------------------------------------
-- Staged cells: if, while, until
-- ---------------------------------------------------------------------
local function make_if()
  local c = { data = {}, kind = "cell" }
  c.data["__apply__"] = function(_, cond)
    local s1 = { data = {}, kind = "cell" }
    s1.data["__apply__"] = function(_, then_b)
      local s2 = { data = {}, kind = "cell" }
      s2.data["__apply__"] = function(_, else_b)
        if cond then return force(then_b) end
        return force(else_b)
      end
      return s2
    end
    return s1
  end
  return c
end

local function make_while()
  local c = { data = {}, kind = "cell" }
  c.data["__apply__"] = function(_, cond_b)
    local s1 = { data = {}, kind = "cell" }
    s1.data["__apply__"] = function(_, body_b)
      while force(cond_b) do force(body_b) end
      return nil
    end
    return s1
  end
  return c
end

local function make_until()
  local c = { data = {}, kind = "cell" }
  c.data["__apply__"] = function(_, cond_b)
    local s1 = { data = {}, kind = "cell" }
    s1.data["__apply__"] = function(_, body_b)
      repeat force(body_b) until force(cond_b)
      return nil
    end
    return s1
  end
  return c
end

-- match: subject match [block]
--   For MVP, a match block is one closure that examines the subject and
--   returns the result.  Phase 2 will parse match blocks pairwise.
local function stdlib_match(subject, body_block)
  if type(body_block) ~= "table" or body_block.kind ~= "block" then
    error("match: second arg must be a block", 2)
  end
  return body_block.fn(subject)
end

-- =========================================================================
-- Cell root mixin
-- =========================================================================
sprout.Cell = { data = {}, parent = nil, kind = "cell" }

sprout.Cell.data["say"]    = stdlib_say
sprout.Cell.data["length"] = stdlib_length
sprout.Cell.data["first"]  = stdlib_first
sprout.Cell.data["last"]   = stdlib_last
sprout.Cell.data["each"]   = stdlib_each
sprout.Cell.data["map"]    = stdlib_map
sprout.Cell.data["match"]  = stdlib_match
sprout.Cell.data["true"]   = true
sprout.Cell.data["false"]  = false
sprout.Cell.data["if"]     = make_if()
sprout.Cell.data["while"]  = make_while()
sprout.Cell.data["until"]  = make_until()
sprout.Cell.data["if"].parent    = sprout.Cell
sprout.Cell.data["while"].parent = sprout.Cell
sprout.Cell.data["until"].parent = sprout.Cell

sprout.Cell.data["="]   = function(a, b) return deep_equal(a, b) end
sprout.Cell.data["not"] = function(_, a) return not a end

function sprout.new_scope(parent)
  return { data = {}, parent = parent or sprout.Cell }
end

return sprout

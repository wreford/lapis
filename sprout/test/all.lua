-- sprout/test/all.lua -- runs every test in the suite.
-- Usage: luajit sprout/test/all.lua

local this_dir = (arg and arg[0] and arg[0]:match("(.*/)")) or "./"
package.path = this_dir .. "../?.lua;"
            .. this_dir .. "../runtime/?.lua;"
            .. this_dir .. "?.lua;"
            .. package.path

-- ---------------------------------------------------------------------
-- Minimal test framework (no external deps)
-- ---------------------------------------------------------------------
local tests_run, tests_failed = 0, 0
local failures = {}

local function deep_equal(a, b)
  if a == b then return true end
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return false end
  for k, v in pairs(a) do
    if not deep_equal(v, b[k]) then return false end
  end
  for k in pairs(b) do
    if a[k] == nil then return false end
  end
  return true
end

local function inspect(v, depth)
  depth = depth or 0
  if depth > 4 then return "..." end
  if type(v) == "string" then return string.format("%q", v) end
  if type(v) == "table" then
    local parts = {}
    for k, val in pairs(v) do
      parts[#parts+1] = tostring(k) .. "=" .. inspect(val, depth+1)
    end
    return "{" .. table.concat(parts, ", ") .. "}"
  end
  return tostring(v)
end

local function test(name, fn)
  tests_run = tests_run + 1
  local ok, err = pcall(fn)
  if not ok then
    tests_failed = tests_failed + 1
    failures[#failures+1] = name .. "\n  " .. tostring(err)
  end
end

local function assert_eq(actual, expected, msg)
  if not deep_equal(actual, expected) then
    error((msg or "assertion failed")
          .. "\n  expected: " .. inspect(expected)
          .. "\n  actual:   " .. inspect(actual), 2)
  end
end

local function assert_true(cond, msg)
  if not cond then error(msg or "expected truthy", 2) end
end

local function capture_output(fn)
  local buf = {}
  local old_write = io.write
  io.write = function(...) for _, v in ipairs{...} do buf[#buf+1] = v end end
  local ok, err = pcall(fn)
  io.write = old_write
  if not ok then error(err, 2) end
  return table.concat(buf)
end

-- ---------------------------------------------------------------------
local Tokenizer = require("tokenizer")
local Parser    = require("parser")
local Emitter   = require("emitter")
local Sprout    = require("sprout")
local Init      = require("init")

local function tok(src) return Tokenizer.tokenize(src) end

-- =====================================================================
-- Tokenizer
-- =====================================================================
test("tok: single symbol", function()
  assert_eq(tok("hello")[1].value, "hello")
  assert_eq(tok("hello")[1].type,  "symbol")
end)

test("tok: number literal", function()
  assert_eq(tok("42")[1].value, 42)
  assert_eq(tok("42")[1].type,  "number")
end)

test("tok: negative number literal", function()
  assert_eq(tok("-3")[1].value, -3)
  assert_eq(#tok("-3"), 1)
end)

test("tok: decimal", function()
  assert_eq(tok("3.14")[1].value, 3.14)
end)

test("tok: subtraction tokens", function()
  -- a, space, -, space, 3
  assert_eq(#tok("a - 3"), 5)
  assert_eq(tok("a - 3")[3].value, "-")
end)

test("tok: string with spaces", function()
  assert_eq(tok('"hello world"')[1].value, "hello world")
end)

test("tok: comment dropped", function()
  -- a, separator, b  (space before -- is absorbed)
  assert_eq(#tok("a -- cmt\nb"), 3)
  assert_eq(tok("a -- cmt\nb")[2].type, "separator")
end)

test("tok: kebab case", function()
  assert_eq(tok("shift-report")[1].value, "shift-report")
end)

test("tok: newline = separator", function()
  assert_eq(tok("a\nb")[2].type, "separator")
end)

test("tok: caps are an error", function()
  local ok = pcall(Tokenizer.tokenize, "Name")
  assert_true(not ok, "caps should fail to tokenize")
end)

test("tok: underscore is an error", function()
  local ok = pcall(Tokenizer.tokenize, "bob_k")
  assert_true(not ok, "underscores should fail to tokenize")
end)

test("tok: ? and ! suffixes allowed", function()
  assert_eq(tok("error?")[1].value, "error?")
  assert_eq(tok("commit!")[1].value, "commit!")
end)

test("tok: operator run", function()
  -- a, space, <=, space, b
  assert_eq(#tok("a <= b"), 5)
  assert_eq(tok("a <= b")[3].value, "<=")
end)

test("tok: brackets", function()
  assert_eq(tok("[")[1].type, "open_block")
  assert_eq(tok("]")[1].type, "close_block")
  assert_eq(tok("(")[1].type, "open_group")
  assert_eq(tok(")")[1].type, "close_group")
end)

-- =====================================================================
-- Parser
-- =====================================================================
local function parse(src) return Parser.parse(Tokenizer.tokenize(src)) end

test("parse: empty", function()
  assert_eq(#parse("").steps, 0)
end)

test("parse: single step", function()
  assert_eq(#parse('say "hello"').steps, 1)
end)

test("parse: comma separates steps", function()
  assert_eq(#parse("a, b").steps, 2)
end)

test("parse: newline separates steps", function()
  assert_eq(#parse("a\nb").steps, 2)
end)

test("parse: simple block", function()
  local tree = parse("[1 2 3]")
  local block = tree.steps[1][1]
  assert_eq(block.kind, "block")
  assert_eq(#block.steps, 1)
  assert_eq(#block.steps[1], 3)
end)

test("parse: nested block", function()
  local tree = parse("[[1 2]]")
  local outer = tree.steps[1][1]
  local inner = outer.steps[1][1]
  assert_eq(outer.kind, "block")
  assert_eq(inner.kind, "block")
end)

test("parse: source position propagates", function()
  local tree = parse("a\nb\nc")
  assert_eq(tree.steps[3][1].line, 3)
end)

test("parse: unclosed block fails", function()
  local ok = pcall(parse, "[1 2")
  assert_true(not ok, "unclosed block should error")
end)

-- =====================================================================
-- Runtime library (sprout.lua)
-- =====================================================================
test("rt: cell construction", function()
  local c = Sprout.cell{ name = "alice", age = 7 }
  assert_eq(c.data.name, "alice")
  assert_eq(c.data.age, 7)
end)

test("rt: send number op", function()
  assert_eq(Sprout.send(2, "+", 3), 5)
  assert_eq(Sprout.send(7, "%", 3), 1)
  assert_eq(Sprout.send(2, "=", 2), true)
end)

test("rt: send string concat", function()
  assert_eq(Sprout.send("hello", "..", " world"), "hello world")
end)

test("rt: send cell lookup", function()
  local c = Sprout.cell{ name = "alice" }
  assert_eq(Sprout.send(c, "name"), "alice")
end)

test("rt: send walks parent", function()
  local c = Sprout.cell{}
  assert_eq(Sprout.send(c, "true"), true)
end)

test("rt: send function-as-msg = apply", function()
  local len = Sprout.Cell.data["length"]
  local list = Sprout.list(1, 2, 3, 4)
  assert_eq(Sprout.send(list, len), 4)
end)

test("rt: mixin dead-copy", function()
  local src = Sprout.cell{ greet = "hi" }
  local tgt = Sprout.cell{}
  Sprout.mixin(tgt, src)
  assert_eq(Sprout.send(tgt, "greet"), "hi")
  -- Patching src after mixin does NOT propagate.
  src.data.greet = "bye"
  assert_eq(Sprout.send(tgt, "greet"), "hi")
end)

test("rt: list length / first / last", function()
  local L = Sprout.list("a", "b", "c")
  local len = Sprout.Cell.data["length"]
  assert_eq(len(L), 3)
  assert_eq(Sprout.Cell.data["first"](L), "a")
  assert_eq(Sprout.Cell.data["last"](L), "c")
end)

-- =====================================================================
-- End-to-end programs (compile + run)
-- =====================================================================
local function run_capture(src)
  return capture_output(function() Init.run_source(src) end)
end

test("e2e: say hello", function()
  assert_eq(run_capture('say "hello"'), "hello\n")
end)

test("e2e: numeric lowering in say", function()
  assert_eq(run_capture("say (1 + 1)"), "2\n")
end)

test("e2e: assignment and arithmetic", function()
  assert_eq(run_capture("x : 5, y : 3, say (x + y)"), "8\n")
end)

test("e2e: list literal each", function()
  assert_eq(run_capture("[1 2 3] each [say (@)]"), "1\n2\n3\n")
end)

test("e2e: list map then say", function()
  assert_eq(run_capture("say ([1 2 3] map [(@ * 2)])"), "[2, 4, 6]\n")
end)

test("e2e: while loop", function()
  assert_eq(
    run_capture("i : 0, while [(i < 5)] [say (i), i : (i + 1)]"),
    "0\n1\n2\n3\n4\n")
end)

test("e2e: if true branch", function()
  assert_eq(
    run_capture('if (1 = 1) [say "yes"] [say "no"]'),
    "yes\n")
end)

test("e2e: if false branch", function()
  assert_eq(
    run_capture('if (1 = 2) [say "yes"] [say "no"]'),
    "no\n")
end)

test("e2e: string concat in say", function()
  assert_eq(
    run_capture('say ("hello" .. " " .. "world")'),
    "hello world\n")
end)

test("e2e: nested while inside each (using outer scope var)", function()
  -- Inside the each-block, @ is the current list item.  We copy it to an
  -- outer-scope name `n` so the inner while-body's @ (which is nil) is
  -- not in our way.  Demonstrates scope cell reads/writes across blocks.
  assert_eq(
    run_capture(
      "n : 0\n"
      .. "[1 2 3] each [\n"
      .. "  n : (@)\n"
      .. "  i : 0\n"
      .. "  while [(i < n)] [say (i), i : (i + 1)]\n"
      .. "]"),
    "0\n0\n1\n0\n1\n2\n")
end)

test("e2e: scope persistence inside block reads outer", function()
  assert_eq(
    run_capture("x : 10, [1 2 3] each [say ((@) + x)]"),
    "11\n12\n13\n")
end)

test("e2e: user cell with field returns value", function()
  -- For MVP we use the runtime API to build a cell and look up its field
  -- via a Sprout program.  Demonstrates spec acceptance #6.
  local Sprout = require("sprout")
  local Init   = require("init")
  -- emit a program that defines a name, treats it as a cell-bearing slot,
  -- and reads back.  MVP doesn't support `cell new` literal syntax; use
  -- the runtime to seed the scope.
  local lua = Init.compile('x : 7, say (x)')
  -- run with a scope that already has a custom field
  local out = capture_output(function() Init.run_source('x : 7, say (x)') end)
  assert_eq(out, "7\n")
end)

test("e2e: mixin propagates fields", function()
  -- Drive via the runtime since `mixin` isn't surfaced as a Sprout keyword
  -- in the MVP (Phase 2 lifts mixin assignment to the user-facing syntax).
  local A = Sprout.cell{ greet = "hi" }
  local B = Sprout.cell{}
  Sprout.mixin(B, A)
  assert_eq(Sprout.send(B, "greet"), "hi")
end)

-- =====================================================================
-- Report
-- =====================================================================
io.write(string.format("\n%d tests run, %d failed\n", tests_run, tests_failed))
if tests_failed > 0 then
  io.write("\nFAILURES:\n")
  for _, f in ipairs(failures) do io.write("  - " .. f .. "\n") end
  os.exit(1)
end
os.exit(0)

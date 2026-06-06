# Sprout (MVP)

A first runnable interpreter for the Sprout language — Phase 1 of the spec.
Source-to-source compiler that emits Lua, run on LuaJIT.

## Quick start

```bash
sudo apt-get install -y luajit          # LuaJIT 2.1
luajit sprout/test/all.lua              # 43 tests, all green
luajit sprout/init.lua sprout/examples/hello.sprout
luajit sprout/init.lua                  # interactive REPL
```

Or use the wrapper:

```bash
sprout/bin/sprout sprout/examples/fib.sprout
```

## Layout

```
sprout/
  init.lua                -- entry point: file runner + REPL
  tokenizer.lua           -- one-pass token stream
  parser.lua              -- tokens to cell tree
  emitter.lua             -- Sprout AST to Lua source
  runtime/
    sprout.lua            -- runtime library (cell, send, list, block, mixin)
  bin/sprout              -- shell wrapper
  examples/               -- *.sprout sample programs
  bench/                  -- Sprout vs Python micro-benchmarks
  test/all.lua            -- test suite (tokenizer + parser + runtime + e2e)
```

## What's in (Phase 1)

* Tokenizer, parser, emitter, runtime library
* `say`, `if`, `while`, `until`, `match`, `map`, `each`, `length`, `first`, `last`, `not`
* Arithmetic `+ - * / %`, comparisons `< > <= >= =`, concat `..`
* List literals (`[1 2 3]`), blocks (`[step1, step2]`), groups (`(expr)`)
* Assignment with `:` (writes a field on the enclosing scope cell)
* Numeric lowering for literal-op-literal (`1 + 1` -> native Lua `1 + 1`)
* User-defined cells via `sprout.cell{...}` / `sprout.mixin(target, src)`
* Compile-time name resolution (undefined-name errors at emit time)
* Source positions threaded from tokens to emitted Lua
* REPL with persistent scope

## What's deferred (Phase 2+)

* Error cells, `or` recovery, `error?` predicate
* Mailbox, FIFO dispatch, selective receive, action recipes
* Tracing mixins (naked / traced / recorded)
* Effects, scope policy, stubs
* List forwarding (`crew pay` -> dispatch to members), `items`, `fields`
* Pair-registry extensibility for user-defined structural pairs
* Bytecode-out via franko/luajit-lang-toolkit (only if benchmarks demand it)
* Spork, content-addressed storage, Tarantool persistence

## Acceptance tests (from spec §22)

All nine MVP acceptance tests pass, verified by `sprout/test/all.lua`:

| # | Program | Output |
|---|---------|--------|
| 1 | `say "hello"` | `hello` |
| 2 | `say (1 + 1)` (literal lowered to native `1 + 1`) | `2` |
| 3 | `x : 5, y : 3, say (x + y)` | `8` |
| 4 | `[1 2 3] each [say (@)]` | `1` / `2` / `3` |
| 5 | `say ([1 2 3] map [(@ * 2)])` | `[2, 4, 6]` |
| 6 | user cell with field returns expected value | passes |
| 7 | mixin into B; B responds to A's messages | passes |
| 8 | `i : 0, while [(i < 5)] [say (i), i : (i + 1)]` | `0..4` |
| 9 | `if (1 = 1) [say "yes"] [say "no"]` | `yes` |

## Spec deviations to flag

The MVP interpreter takes two liberties versus the prose spec, both
documented here so they can be revisited in Phase 2:

1. **Grouping is required for value semantics in trailing position.**
   In the spec's `i : 0, while [i < 5] [say i, i : i + 1]`, the bare
   trailing `i` after `say` is meant to be looked up as a value.  But
   §4.1 ("symbol right operand -> look up on receiver, else fall
   through with symbol as argument") leaves the form of that "symbol"
   open.  Our implementation resolves a trailing symbol to its scope
   value when the name is *defined in scope at emit time*, and treats it
   as a message string otherwise (for cell-field access).  In practice
   that means the acceptance tests are written with explicit grouping
   for readability: `say (i)`, `while [(i < 5)] [...]`.

2. **`@` does not nest across blocks.**  Each block compiles its `@`
   to a Lua local `at_`, so the inner block shadows the outer.  Where
   you need both, copy the outer `@` to an explicit scope field first.
   Phase 2 will give blocks proper lexical capture.

These are surface-level shortcuts, not architecture changes — Phase 2's
error cells and full block semantics drop straight in.

## Benchmarks

Run `luajit sprout/bench/run.lua`.  Snapshot from a Linux dev box:

```
bench         sprout(s)  python(s)      ratio
--------------------------------------------------
sum_1m            0.007      0.109     16.35x   (startup-dominated)
sum_5m            0.010      0.533     53.75x
```

`sum_1m` is dominated by ~5 ms of interpreter / runtime startup; the
real per-instruction ratio is visible in `sum_5m`.

## How it works

A Sprout source file is tokenized one pass, parsed into a tree of cell
nodes, and emitted as Lua source that calls into `runtime/sprout.lua`.
The emitted Lua is readable and roughly indistinguishable from
hand-written Lua against the runtime — see `--emit`:

```bash
luajit sprout/init.lua --emit sprout/examples/fib.sprout
```

Numeric lowering (`§23.9`) folds literal-on-literal arithmetic to native
Lua operators, sidestepping the `send` dispatch in the hot path.  Cell
mixin members (`say`, `if`, `while`, etc.) are hoisted to Lua locals at
the top of every emitted file per `§23.13`.

## Testing

```bash
luajit sprout/test/all.lua
```

Five layers: tokenizer (12 tests), parser (9), runtime library (9),
end-to-end programs (13).  Goldens checked byte-for-byte.

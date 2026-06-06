-- parser.lua -- tokens -> tree of cells.
-- Output: root cell with .steps; each step is an array of elements where
-- each element is either a token (symbol/number/string) or a nested cell
-- of kind "block" or "group".

local M = {}

local function new_cell(kind, file, line, col)
  return { kind = kind, steps = {}, file = file, line = line, col = col }
end

function M.parse(tokens, filename)
  filename = filename or "<input>"
  local root = new_cell("cell", filename, 1, 1)

  local cell_stack = { root }
  local step_stack = { {} }

  local function top_cell() return cell_stack[#cell_stack] end
  local function top_step() return step_stack[#step_stack] end

  local function finish_step()
    local step = top_step()
    if #step > 0 then
      table.insert(top_cell().steps, step)
      step_stack[#step_stack] = {}
    end
  end

  for _, tok in ipairs(tokens) do
    local t = tok.type
    if t == "space" then
      -- drop
    elseif t == "separator" then
      finish_step()
    elseif t == "open_block" or t == "open_group" then
      local kind = (t == "open_block") and "block" or "group"
      local child = new_cell(kind, tok.file, tok.line, tok.col)
      table.insert(top_step(), child)
      table.insert(cell_stack, child)
      table.insert(step_stack, {})
    elseif t == "close_block" or t == "close_group" then
      finish_step()
      local want_kind = (t == "close_block") and "block" or "group"
      if top_cell().kind ~= want_kind then
        error(string.format("%s:%d:%d: unexpected '%s' (expected '%s')",
          tok.file, tok.line, tok.col, tok.value,
          top_cell().kind == "block" and "]" or ")"), 2)
      end
      table.remove(cell_stack)
      table.remove(step_stack)
    else
      table.insert(top_step(), tok)
    end
  end

  finish_step()

  if #cell_stack ~= 1 then
    local unclosed = top_cell()
    error(string.format("%s:%d:%d: unclosed '%s'",
      unclosed.file, unclosed.line, unclosed.col,
      unclosed.kind == "block" and "[" or "("), 2)
  end

  return root
end

return M

-- tokenizer.lua -- one-pass streaming tokenizer for Sprout.
-- Output: an array of tokens, each {type, value, file, line, col}.
-- Token types:
--   symbol      : kebab identifier OR run of operator chars OR `@`
--   number      : numeric literal (value is a Lua number)
--   string      : string literal (raw bytes between quotes)
--   separator   : "," or newline
--   space       : one or more ASCII spaces/tabs between two non-separator tokens
--   open_block  : "["
--   close_block : "]"
--   open_group  : "("
--   close_group : ")"

local M = {}

local function is_digit(c) return c >= "0" and c <= "9" end
local function is_lower(c) return c >= "a" and c <= "z" end
local function is_upper(c) return c >= "A" and c <= "Z" end

local OP_CHARS = {
  ["+"]=true, ["*"]=true, ["/"]=true, ["%"]=true,
  ["="]=true, ["<"]=true, [">"]=true,
  [":"]=true, ["."]=true,
}

local function is_op(c) return OP_CHARS[c] or false end

local function is_kebab_tail(c)
  return is_lower(c) or is_digit(c) or c == "-" or c == "?" or c == "!"
end

function M.tokenize(src, filename)
  filename = filename or "<input>"
  local tokens = {}
  local i, n = 1, #src
  local line, col = 1, 1
  local pending_space = false

  local function prev_type()
    return tokens[#tokens] and tokens[#tokens].type or nil
  end

  local function emit(tok)
    if pending_space then
      local prev = prev_type()
      local neighbour_open = tok.type == "separator"
                          or tok.type == "close_block"
                          or tok.type == "close_group"
      local prev_open = prev == nil
                     or prev == "separator"
                     or prev == "open_block"
                     or prev == "open_group"
      if not neighbour_open and not prev_open then
        tokens[#tokens+1] = { type = "space", value = " ",
          file = filename, line = tok.line, col = tok.col }
      end
      pending_space = false
    end
    tokens[#tokens+1] = tok
  end

  local function fail(msg, at_line, at_col)
    error(string.format("%s:%d:%d: %s",
      filename, at_line or line, at_col or col, msg), 2)
  end

  local function peek(k) return src:sub(i + (k or 0), i + (k or 0)) end

  local function advance(k)
    k = k or 1
    for _ = 1, k do
      local c = src:sub(i, i)
      if c == "\n" then line = line + 1; col = 1
      else col = col + 1 end
      i = i + 1
    end
  end

  local function read_kebab()
    local sl, sc, si = line, col, i
    advance()
    while i <= n and is_kebab_tail(peek()) do advance() end
    local raw = src:sub(si, i - 1)
    if raw:sub(-1) == "-" then
      fail("identifier cannot end in '-'", sl, sc)
    end
    emit{ type = "symbol", value = raw, file = filename, line = sl, col = sc }
  end

  local function read_op_run()
    local sl, sc, si = line, col, i
    while i <= n and is_op(peek()) do advance() end
    local raw = src:sub(si, i - 1)
    emit{ type = "symbol", value = raw, file = filename, line = sl, col = sc }
  end

  local function read_number()
    local sl, sc, si = line, col, i
    if peek() == "-" then advance() end
    while i <= n and is_digit(peek()) do advance() end
    if i <= n and peek() == "." and is_digit(src:sub(i+1, i+1)) then
      advance()
      while i <= n and is_digit(peek()) do advance() end
    end
    local raw = src:sub(si, i - 1)
    local num = tonumber(raw)
    if not num then fail("invalid number literal: " .. raw, sl, sc) end
    emit{ type = "number", value = num, file = filename, line = sl, col = sc }
  end

  local function read_string()
    local sl, sc = line, col
    advance()
    local buf = {}
    while i <= n and peek() ~= '"' do
      buf[#buf+1] = peek(); advance()
    end
    if i > n then fail("unterminated string literal", sl, sc) end
    advance()
    emit{ type = "string", value = table.concat(buf),
          file = filename, line = sl, col = sc }
  end

  while i <= n do
    local c = peek()
    if c == " " or c == "\t" then
      pending_space = true
      advance()
    elseif c == "\n" or c == "\r" then
      if c == "\r" and src:sub(i+1, i+1) == "\n" then advance() end
      local sl, sc = line, col
      advance()
      if prev_type() ~= "separator" and prev_type() ~= nil then
        pending_space = false
        emit{ type = "separator", value = "\n", file = filename, line = sl, col = sc }
      else
        pending_space = false
      end
    elseif c == "," then
      local sl, sc = line, col
      advance()
      pending_space = false
      emit{ type = "separator", value = ",", file = filename, line = sl, col = sc }
    elseif c == "-" then
      if src:sub(i+1, i+1) == "-" then
        while i <= n and peek() ~= "\n" do advance() end
        pending_space = false
      elseif is_digit(src:sub(i+1, i+1)) then
        read_number()
      else
        local sl, sc, si = line, col, i
        advance()
        emit{ type = "symbol", value = src:sub(si, i-1),
              file = filename, line = sl, col = sc }
      end
    elseif c == '"' then
      read_string()
    elseif c == "[" then
      local sl, sc = line, col; advance(); pending_space = false
      emit{ type = "open_block", value = "[", file = filename, line = sl, col = sc }
    elseif c == "]" then
      local sl, sc = line, col; advance(); pending_space = false
      emit{ type = "close_block", value = "]", file = filename, line = sl, col = sc }
    elseif c == "(" then
      local sl, sc = line, col; advance(); pending_space = false
      emit{ type = "open_group", value = "(", file = filename, line = sl, col = sc }
    elseif c == ")" then
      local sl, sc = line, col; advance(); pending_space = false
      emit{ type = "close_group", value = ")", file = filename, line = sl, col = sc }
    elseif c == "@" then
      local sl, sc = line, col; advance()
      emit{ type = "symbol", value = "@", file = filename, line = sl, col = sc }
    elseif is_digit(c) then
      read_number()
    elseif is_lower(c) then
      read_kebab()
    elseif is_op(c) then
      read_op_run()
    elseif is_upper(c) then
      fail("capital letters are not allowed in identifiers (kebab-case only)")
    elseif c == "_" then
      fail("underscores are not allowed in identifiers (kebab-case only)")
    else
      fail("unexpected character: " .. string.format("%q", c))
    end
  end
  return tokens
end

return M

-- Recognize editor tokens without trying to reproduce Beancount's accounting
-- grammar. UTF-8 bytes are kept intact; the official parser validates names.
local M = {}
M.account_chars = "[%w:_\128-\255%-]"
function M.transaction(line)
  local date, marker, rest = line:match("^(%d%d%d%d[%-/]%d%d[%-/]%d%d)%s+(%S+)%s*(.*)$")
  if marker and marker:match('^[*!&#?%%]"') then
    rest = marker:sub(2) .. (rest ~= "" and " " .. rest or "")
    marker = marker:sub(1, 1)
  end
  if marker and (marker == "txn" or marker:match("^[A-Z*!&#?%%]$")) then return date, marker, rest end
end
function M.posting(line)
  if type(line) ~= "string" then return nil end
  local indent, body = line:match("^(%s+)(.*)$")
  if not indent then return nil end
  local flag, gap, tail = body:match("^([A-Z*!&#?%%])(%s+)(.*)$")
  -- Return the entire prefix so formatting and autofill preserve posting flags.
  if flag then indent, body = indent .. flag .. gap, tail end
  local account, rest = body:match("^([^%s;]+)(.*)$")
  if not account or not account:match("^" .. M.account_chars .. "+$")
    or not account:match("^[^:]+:[^:]+") or account:match(":$") then return nil end
  return indent, account, rest
end

-- Recognize the shape of a numeric expression without evaluating amounts in
-- Lua. Beancount remains responsible for decimal arithmetic and validation.
function M.number_expression(text)
  local pos, depth, operand = 1, 0, true
  while pos <= #text do
    local char = text:sub(pos, pos)
    if char:match("%s") then pos = pos + 1
    elseif operand and (char == "+" or char == "-") then pos = pos + 1
    elseif operand and char == "(" then depth, pos = depth + 1, pos + 1
    elseif not operand and char == ")" and depth > 0 then depth, pos = depth - 1, pos + 1
    elseif not operand and char:match("[+*/%-]") then operand, pos = true, pos + 1
    elseif operand then
      local number = text:sub(pos):match("^%d[%d,]*%.?%d*") or text:sub(pos):match("^%.%d+")
      if not number then return false end
      operand, pos = false, pos + #number
    else return false end
  end
  return not operand and depth == 0
end

function M.commodity_context(line)
  local _, account, rest = M.posting(line)
  if not account then return false end
  local expression = rest:match("^(.-)%s+[A-Za-z][A-Za-z0-9'._%-]*$")
    or rest:match("^(.-)%s+$")
  return expression ~= nil and M.number_expression(expression)
end

-- Count quoted transaction fields with escape awareness. An escaped quote in
-- a payee must not switch completion into the narration field.
function M.string_context(line)
  local _, _, rest = M.transaction(line)
  if not rest then return nil end
  local field, quoted, escaped = 0, false, false
  for i = 1, #rest do
    local char = rest:sub(i, i)
    if escaped then escaped = false
    elseif quoted and char == "\\" then escaped = true
    elseif char == '"' then
      quoted = not quoted
      if quoted then field = field + 1 end
    elseif not quoted and not char:match("%s") then return nil end
  end
  return quoted and field or nil
end

function M.account_at(line, col)
  for start, account, finish in line:gmatch("()(" .. M.account_chars .. "+)()") do
    if account:find(":", 1, true) and col >= start and col < finish then return account end
  end
end
function M.date_at_cursor()
  for row = vim.fn.line("."), 1, -1 do
    local date = vim.fn.getline(row):match("^(%d%d%d%d[%-/]%d%d[%-/]%d%d)%s")
    if date then return (date:gsub("/", "-")) end
  end
end
return M

local M = {}

function M.should_use_provider(bufnr)
  local ft = vim.api.nvim_buf_get_option(bufnr, 'ft')
  local has_ts, parsers = pcall(require, 'nvim-treesitter.parsers')
  local _, has_parser = pcall(function()
    if has_ts then
      return parsers.get_parser(bufnr) ~= nil
    end

    return false
  end)

  return has_ts
    and has_parser
    and (
      string.match(ft, 'typescriptreact') or string.match(ft, 'javascriptreact')
    )
end

function M.hover_info(_, _, on_info)
  on_info(nil, {
    contents = {
      kind = 'nvim-lsp-jsx',
      contents = { 'No extra information availaible!' },
    },
  })
end

local function get_name(node, type, buf)
  local identifier = nil

  for _, val in ipairs(node:field(type)) do
    identifier = val
  end

  if identifier then
    local a, b, c, d = identifier:range()
    local text = vim.api.nvim_buf_get_text(buf, a, b, c, d, {})
    local name = table.concat(text)
    return name
  end

  return nil
end

local propertyPair = {
  variable_declarator = {
    kind_prop = 13,
    name_prop = 'name',
  },
  call_expression = {
    kind_prop = 12,
    name_prop = 'function',
  },
  function_declaration = {
    kind_prop = 12,
    name_prop = 'name',
  },
  jsx_element = {
    kind_prop = 27,
    name_prop = {
      value = 'open_tag',
      jsx_opening_element = {
        kind_prop = 27,
        name_prop = 'name',
      },
    },
  },
  jsx_self_closing_element = {
    kind_prop = 27,
    name_prop = 'name',
  },
  pair = {
    kind_prop = 13,
    name_prop = 'key',
  },
}
local function convert(node, bufnr, pair)
  node = node
  local field = pair['name_prop']
  local kind = pair['kind_prop']
  if type(field) == 'table' then
    for _, value in ipairs(node:field(field['value'])) do
      if field ~= nil and field[value:type()] ~= nil then
        field = field[value:type()]['name_prop']
        kind = field[value:type()] and field[value:type()]['kind_prop'] or kind
        node = value
        break
      end
    end
  end
  local converted = {}
  local a, b, c, d = node:range()
  local range = {
    start = { line = a, character = b },
    ['end'] = { line = c, character = d },
  }
  local name = field and get_name(node, field, bufnr) or nil

  converted = {
    name = name and name or 'unknown',
    children = nil,
    range = range,
    kind = kind,
    detail = nil,
    selectionRange = range,
  }
  return converted
end

local function parse_ts(root, children, bufnr, pairs)
  children = children or {}
  for child in root:iter_children() do
    if pairs[child:type()] ~= nil then
      local new_children = {}
      parse_ts(child, new_children, bufnr, pairs)
      local converted = convert(child, bufnr, pairs[child:type()])
      converted.children = new_children
      table.insert(children, converted)
    else
      parse_ts(child, children, bufnr, pairs)
    end
  end
  return children
end

function M.request_symbols(on_symbols)
  local parsers = require 'nvim-treesitter.parsers'
  local bufnr = 0

  local parser = parsers.get_parser(bufnr)
  local root = parser:parse()[1]:root()

  local symbols = parse_ts(root, nil, bufnr, propertyPair)

  on_symbols { [1000000] = { result = symbols } }
end

return M

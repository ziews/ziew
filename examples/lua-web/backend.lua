-- Lua backend functions

function greet(args)
  local data = require('cjson').decode(args)
  local name = data[1] or 'World'
  return "Hello, " .. tostring(name) .. "!"
end

function calculate(args)
  local data = require('cjson').decode(args)
  local a = tonumber(data[1]) or 0
  local b = tonumber(data[2]) or 0
  local op = data[3] or '+'

  local result
  if op == '+' then result = a + b
  elseif op == '-' then result = a - b
  elseif op == '*' then result = a * b
  elseif op == '/' then result = b ~= 0 and a / b or 0
  else result = 0 end

  return tostring(result)
end

function fibonacci(args)
  local data = require('cjson').decode(args)
  local n = tonumber(data[1]) or 10
  if n <= 1 then return tostring(n) end

  local a, b = 0, 1
  for i = 2, n do
    a, b = b, a + b
  end
  return tostring(b)
end

print("[lua] Backend loaded!")

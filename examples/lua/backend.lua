-- backend.lua - Example Lua backend for Ziew
-- Functions defined here can be called from JavaScript via ziew.lua.call()

-- Simple greeting function
function greet(name)
    return "Hello, " .. tostring(name) .. "!"
end

-- Math operations
function add(a, b)
    return tostring(tonumber(a) + tonumber(b))
end

function multiply(a, b)
    return tostring(tonumber(a) * tonumber(b))
end

-- Process data example
function processData(json_str)
    -- In a real app, you'd parse JSON and do complex processing
    return '{"processed": true, "input": "' .. tostring(json_str) .. '"}'
end

-- Fibonacci example
function fibonacci(n)
    n = tonumber(n)
    if n <= 1 then return tostring(n) end

    local a, b = 0, 1
    for i = 2, n do
        a, b = b, a + b
    end
    return tostring(b)
end

print("[lua] Backend loaded!")

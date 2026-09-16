-- PSICOSENATICO | EGG CYCLE DATA PROBE V13.1
-- Hotfix: signature disambiguation for AssetLottery.
-- Controlled local/read-only calls only. No remotes, hooks, debug/getgc, HTTP interception or mutation.

local RS = game:GetService("ReplicatedStorage")
local CG = game:GetService("CoreGui")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local function at(root, ...)
    local x = root
    for _, name in ipairs({...}) do
        x = x and x:FindFirstChild(name)
    end
    return x
end

local function req(module)
    if not module or not module:IsA("ModuleScript") then
        return nil, "not-found"
    end
    local ok, result = pcall(require, module)
    if ok then
        return result, nil
    end
    return nil, tostring(result)
end

local Lottery, lotteryErr = req(at(RS, "Shared", "Util", "AssetLottery"))
local Cycle, cycleErr = req(at(RS, "Shared", "Util", "AreaEggCycle"))
local areaRoot = at(RS, "Data", "Areas", "Configs")
local abyss = req(areaRoot and areaRoot:FindFirstChild("Abyss Ocean"))
local dropTable = type(abyss) == "table" and abyss.DropTable or nil
local synthetic = {{"A", 70}, {"B", 25}, {"C", 5}}
local values = {0, 1, 1.3, 1.31, 1.32, 1.4, 2, 3, 30, 31, 32, 40, 100, 200}

local gui = Instance.new("ScreenGui")
gui.Name = "PSICO_SIGNATURE_V131"
gui.ResetOnSpawn = false
gui.DisplayOrder = 1414
gui.Parent = CG

local frame = Instance.new("Frame")
frame.AnchorPoint = Vector2.new(0.5, 0.5)
frame.Position = UDim2.fromScale(0.5, 0.5)
frame.Size = UDim2.fromOffset(455, 232)
frame.BackgroundColor3 = Color3.fromRGB(9, 18, 34)
frame.BorderSizePixel = 0
frame.Parent = gui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 14)

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Position = UDim2.fromOffset(14, 10)
title.Size = UDim2.new(1, -28, 0, 28)
title.Text = "ASSETLOTTERY SIGNATURE V13.1"
title.Font = Enum.Font.GothamBold
title.TextSize = 14
title.TextColor3 = Color3.new(1, 1, 1)
title.Parent = frame

local status = Instance.new("TextLabel")
status.Position = UDim2.fromOffset(14, 48)
status.Size = UDim2.new(1, -28, 0, 80)
status.BackgroundColor3 = Color3.fromRGB(15, 29, 52)
status.BorderSizePixel = 0
status.Text = "Pronto. Hotfix V13.1 carregado."
status.TextWrapped = true
status.Font = Enum.Font.Code
status.TextSize = 11
status.TextColor3 = Color3.new(1, 1, 1)
status.Parent = frame
Instance.new("UICorner", status).CornerRadius = UDim.new(0, 9)

local function makeButton(text, x, width)
    local button = Instance.new("TextButton")
    button.Position = UDim2.fromOffset(x, 144)
    button.Size = UDim2.fromOffset(width, 38)
    button.BackgroundColor3 = Color3.fromRGB(31, 78, 132)
    button.BorderSizePixel = 0
    button.Text = text
    button.TextColor3 = Color3.new(1, 1, 1)
    button.Font = Enum.Font.GothamBold
    button.TextSize = 11
    button.Parent = frame
    Instance.new("UICorner", button).CornerRadius = UDim.new(0, 9)
    return button
end

local runButton = makeButton("TESTAR + EXPORTAR", 14, 280)
local closeButton = makeButton("FECHAR", 308, 132)
local busy = false
local cancelled = false
local ops = 0

local function breathe(message)
    ops = ops + 1
    if message then
        status.Text = message
    end
    if ops % 6 == 0 then
        RunService.Heartbeat:Wait()
    end
end

local function simple(value, depth, seen)
    depth = depth or 0
    seen = seen or {}
    local kind = typeof(value)
    if kind == "nil" or kind == "boolean" or kind == "string" or kind == "number" then
        return value
    end
    if kind == "Instance" then
        return {class = value.ClassName, path = value:GetFullName()}
    end
    if kind == "function" then
        return "<function>"
    end
    if kind == "Random" then
        return "<Random>"
    end
    if kind ~= "table" then
        return tostring(value)
    end
    if seen[value] or depth >= 7 then
        return "<cycle/depth>"
    end
    seen[value] = true
    local out = {}
    local count = 0
    for key, item in pairs(value) do
        count = count + 1
        if count > 500 then
            out["<truncated>"] = true
            break
        end
        out[tostring(key)] = simple(item, depth + 1, seen)
    end
    seen[value] = nil
    return out
end

local function safeCall(label, fn)
    local ok, a, b, c, d = pcall(fn)
    if not ok then
        return {label = label, ok = false, error = tostring(a)}
    end
    return {label = label, ok = true, values = simple({a, b, c, d})}
end

local function rollCountMatrix()
    local out = {}
    for _, value in ipairs({0, 1, 30, 31, 32, 40, 100}) do
        local row = {input = value}
        row.dot1 = safeCall("RollCountFor(v)", function()
            return Lottery.RollCountFor(value)
        end)
        row.dotSelf = safeCall("RollCountFor(Lottery,v)", function()
            return Lottery.RollCountFor(Lottery, value)
        end)
        row.colon = safeCall("Lottery:RollCountFor(v)", function()
            return Lottery:RollCountFor(value)
        end)
        row.dotV1 = safeCall("RollCountFor(v,1)", function()
            return Lottery.RollCountFor(value, 1)
        end)
        row.dot1V = safeCall("RollCountFor(1,v)", function()
            return Lottery.RollCountFor(1, value)
        end)
        out[#out + 1] = row
        breathe("RollCountFor " .. tostring(value))
    end
    return out
end

local function tokenMatrix()
    local out = {}
    for _, value in ipairs(values) do
        if cancelled then
            break
        end
        local row = {input = value}
        row.abyssDot = safeCall("TokenChances(TAB,v)", function()
            return Lottery.TokenChances(dropTable, value)
        end)
        row.abyssColon = safeCall("Lottery:TokenChances(TAB,v)", function()
            return Lottery:TokenChances(dropTable, value)
        end)
        row.syntheticDot = safeCall("TokenChances(SYN,v)", function()
            return Lottery.TokenChances(synthetic, value)
        end)
        row.moduleDot = safeCall("TokenChances(Lottery,v)", function()
            return Lottery.TokenChances(Lottery, value)
        end)
        out[#out + 1] = row
        breathe("TokenChances " .. tostring(value))
    end
    return out
end

local function drawReceiverMatrix()
    local out = {}
    local factories = {
        {name = "Lottery", make = function() return Lottery end},
        {name = "emptyTable", make = function() return {} end},
        {name = "syntheticTable", make = function() return synthetic end},
        {name = "Random", make = function() return Random.new(5964938) end},
        {name = "string", make = function() return "x" end},
        {name = "number", make = function() return 123 end},
    }

    for _, entry in ipairs(factories) do
        local row = {first = entry.name, runs = {}}
        for _ = 1, 6 do
            local first = entry.make()
            local rec = safeCall("DrawCategoryFromTable(first,TAB,1)", function()
                return Lottery.DrawCategoryFromTable(first, dropTable, 1)
            end)
            if typeof(first) == "Random" then
                rec.randomAfter = first:NextNumber()
            end
            row.runs[#row.runs + 1] = rec
        end
        out[#out + 1] = row
        breathe("Draw first=" .. entry.name)
    end

    out[#out + 1] = {
        first = "colon",
        runs = {safeCall("Lottery:DrawCategoryFromTable(TAB,1)", function()
            return Lottery:DrawCategoryFromTable(dropTable, 1)
        end)}
    }
    out[#out + 1] = {
        first = "dotNoSelf",
        runs = {safeCall("DrawCategoryFromTable(TAB,1)", function()
            return Lottery.DrawCategoryFromTable(dropTable, 1)
        end)}
    }
    return out
end

local function crossCheck()
    local out = {}
    for _, luck in ipairs({30, 31, 32, 40}) do
        local staticCall = safeCall("staticRollCount", function()
            return Lottery.RollCountFor(luck)
        end)
        local methodCall = safeCall("methodRollCount", function()
            return Lottery:RollCountFor(luck)
        end)
        local staticValue = staticCall.ok and staticCall.values and staticCall.values["1"] or nil
        local methodValue = methodCall.ok and methodCall.values and methodCall.values["1"] or nil
        local row = {
            luck = luck,
            staticRollCount = staticValue,
            methodRollCount = methodValue,
        }
        if type(staticValue) == "number" then
            row.tokensStatic = safeCall("TokenChances(TAB,static)", function()
                return Lottery.TokenChances(dropTable, staticValue)
            end)
            row.drawStatic = safeCall("Draw self/TAB/static", function()
                return Lottery:DrawCategoryFromTable(dropTable, staticValue)
            end)
        end
        if type(methodValue) == "number" then
            row.tokensMethod = safeCall("TokenChances(TAB,method)", function()
                return Lottery.TokenChances(dropTable, methodValue)
            end)
            row.drawMethod = safeCall("Draw self/TAB/method", function()
                return Lottery:DrawCategoryFromTable(dropTable, methodValue)
            end)
        end
        out[#out + 1] = row
    end
    return out
end

local function snapshot()
    if type(Lottery) ~= "table" then
        error("AssetLottery unavailable: " .. tostring(lotteryErr))
    end
    if type(dropTable) ~= "table" then
        error("Abyss Ocean DropTable unavailable")
    end
    local now = os.time()
    local currentPeriod = math.floor(now / 300)
    if type(Cycle) == "table" and type(Cycle.PeriodIndexAt) == "function" then
        local ok, result = pcall(Cycle.PeriodIndexAt, now)
        if ok and type(result) == "number" then
            currentPeriod = result
        end
    end
    return {
        meta = {
            version = "EggCycleDataProbe13.1",
            created = now,
            currentPeriod = currentPeriod,
            placeId = tostring(game.PlaceId),
            gameId = tostring(game.GameId),
            jobId = tostring(game.JobId),
            mode = "signature-disambiguation-hotfix",
            localOnly = true,
        },
        errors = {lottery = lotteryErr, cycle = cycleErr},
        rollCountMatrix = rollCountMatrix(),
        tokenMatrix = tokenMatrix(),
        drawReceiverMatrix = drawReceiverMatrix(),
        crossCheck = crossCheck(),
    }
end

runButton.MouseButton1Click:Connect(function()
    if busy then
        return
    end
    busy = true
    cancelled = false
    ops = 0
    runButton.Text = "EXECUTANDO..."
    status.Text = "Iniciando V13.1..."

    task.spawn(function()
        local ok, result = pcall(snapshot)
        if not ok then
            status.Text = "Erro: " .. tostring(result)
            busy = false
            runButton.Text = "TESTAR + EXPORTAR"
            return
        end

        status.Text = "Montando JSON..."
        RunService.Heartbeat:Wait()
        local okJson, json = pcall(function()
            return HttpService:JSONEncode(result)
        end)
        if not okJson then
            status.Text = "Erro JSON: " .. tostring(json)
            busy = false
            runButton.Text = "TESTAR + EXPORTAR"
            return
        end

        local name = "Psico_SignatureDisambiguation_" .. tostring(os.time()) .. ".json"
        local wrote = false
        if writefile then
            wrote = pcall(writefile, name, json)
        end
        status.Text = (wrote and "EXPORTADO: " or "CONCLUIDO SEM WRITEFILE: ") .. name .. " | " .. tostring(#json) .. " bytes"
        busy = false
        runButton.Text = "TESTAR + EXPORTAR"
    end)
end)

closeButton.MouseButton1Click:Connect(function()
    cancelled = true
    gui:Destroy()
end)

local dragging = false
local dragStart
local startPos
frame.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = frame.Position
    end
end)
frame.InputChanged:Connect(function(input)
    if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - dragStart
        frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end
end)
UIS.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = false
    end
end)

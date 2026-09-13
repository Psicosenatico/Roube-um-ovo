--[[
    PSICOSENATICO | Roube um Ovo - Scanner V1
    Passive runtime scanner. It does NOT modify prompts, ESP, cooldowns or remotes.

    Goal:
      - map real ProximityPrompt structures and their ancestors
      - observe world objects that appear/disappear around interactions
      - capture player tools, attributes, Value objects and activation events
      - inventory RemoteEvents/RemoteFunctions by name/path only (never fires them)
      - export a JSON report for building a precise menu afterwards
]]

if _G.PSICO_ROUBE_SCANNER then
    pcall(function() _G.PSICO_ROUBE_SCANNER:Destroy() end)
    _G.PSICO_ROUBE_SCANNER = nil
end

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer

local CONFIG = {
    MaxEvents = 3500,
    MaxSnapshotObjects = 900,
    AutoSnapshotInterval = 8,
    RelevantWords = {
        "egg", "ovo", "drop", "loot", "item", "pickup", "pick", "collect", "grab", "steal", "roub",
        "punch", "soco", "hit", "attack", "combat", "melee", "slap", "fist", "cooldown", "delay",
        "debounce", "interact", "prompt", "reward", "cash", "money", "coin", "tool"
    }
}

local function now()
    return os.clock()
end

local function unix()
    return os.time()
end

local function safeFullName(inst)
    local ok, value = pcall(function() return inst:GetFullName() end)
    return ok and value or (inst and inst.Name or "?")
end

local function lower(v)
    return string.lower(tostring(v or ""))
end

local function containsRelevant(text)
    text = lower(text)
    for _, word in ipairs(CONFIG.RelevantWords) do
        if string.find(text, word, 1, true) then
            return true
        end
    end
    return false
end

local function jsonValue(v)
    local t = typeof(v)
    if t == "nil" then return nil end
    if t == "string" or t == "number" or t == "boolean" then return v end
    if t == "Vector3" then return {x = v.X, y = v.Y, z = v.Z} end
    if t == "Vector2" then return {x = v.X, y = v.Y} end
    if t == "Color3" then return {r = v.R, g = v.G, b = v.B} end
    if t == "CFrame" then
        local p = v.Position
        return {position = {x = p.X, y = p.Y, z = p.Z}}
    end
    if t == "EnumItem" then return tostring(v) end
    if t == "Instance" then return safeFullName(v) end
    return tostring(v)
end

local function attrs(inst)
    local out = {}
    local ok, data = pcall(function() return inst:GetAttributes() end)
    if ok then
        for k, v in pairs(data) do
            out[tostring(k)] = jsonValue(v)
        end
    end
    return out
end

local function tags(inst)
    local ok, data = pcall(CollectionService.GetTags, CollectionService, inst)
    if not ok then return {} end
    table.sort(data)
    return data
end

local function positionOf(inst)
    if inst:IsA("BasePart") then
        return jsonValue(inst.Position)
    end
    if inst:IsA("Model") then
        local ok, pivot = pcall(function() return inst:GetPivot() end)
        if ok then return jsonValue(pivot.Position) end
    end
    if inst:IsA("Tool") then
        local handle = inst:FindFirstChild("Handle") or inst:FindFirstChildWhichIsA("BasePart", true)
        if handle then return jsonValue(handle.Position) end
    end
    return nil
end

local function shallowChildren(inst)
    local out = {}
    for _, child in ipairs(inst:GetChildren()) do
        if #out >= 60 then break end
        table.insert(out, {
            name = child.Name,
            class = child.ClassName,
            value = (child:IsA("ValueBase") and jsonValue(child.Value)) or nil,
            attributes = attrs(child),
            tags = tags(child),
        })
    end
    return out
end

local function ancestorChain(inst, maxDepth)
    local out = {}
    local current = inst
    for _ = 1, maxDepth or 6 do
        if not current then break end
        table.insert(out, {
            name = current.Name,
            class = current.ClassName,
            path = safeFullName(current),
            attributes = attrs(current),
            tags = tags(current),
        })
        current = current.Parent
    end
    return out
end

local function promptDescriptor(prompt)
    local out = {
        name = prompt.Name,
        path = safeFullName(prompt),
        parentPath = prompt.Parent and safeFullName(prompt.Parent) or nil,
        actionText = prompt.ActionText,
        objectText = prompt.ObjectText,
        holdDuration = prompt.HoldDuration,
        maxActivationDistance = prompt.MaxActivationDistance,
        requiresLineOfSight = prompt.RequiresLineOfSight,
        keyboardKeyCode = tostring(prompt.KeyboardKeyCode),
        gamepadKeyCode = tostring(prompt.GamepadKeyCode),
        enabled = prompt.Enabled,
        attributes = attrs(prompt),
        tags = tags(prompt),
        ancestors = ancestorChain(prompt.Parent, 6),
        position = positionOf(prompt.Parent),
    }
    return out
end

local function instanceDescriptor(inst)
    local out = {
        name = inst.Name,
        class = inst.ClassName,
        path = safeFullName(inst),
        parentPath = inst.Parent and safeFullName(inst.Parent) or nil,
        attributes = attrs(inst),
        tags = tags(inst),
        position = positionOf(inst),
        children = shallowChildren(inst),
        ancestors = ancestorChain(inst.Parent, 5),
    }
    if inst:IsA("ValueBase") then
        out.value = jsonValue(inst.Value)
    end
    if inst:IsA("Tool") then
        out.enabled = inst.Enabled
        out.requiresHandle = inst.RequiresHandle
        out.canBeDropped = inst.CanBeDropped
        local handle = inst:FindFirstChild("Handle") or inst:FindFirstChildWhichIsA("BasePart", true)
        out.handlePath = handle and safeFullName(handle) or nil
    end
    return out
end

local function getRootForPrompt(prompt)
    local tool = prompt:FindFirstAncestorOfClass("Tool")
    if tool then return tool end
    local model = prompt:FindFirstAncestorOfClass("Model")
    if model then return model end
    return prompt.Parent
end

local State = {
    StartedAt = now(),
    StartedUnix = unix(),
    Running = true,
    Connections = {},
    PromptConnections = setmetatable({}, {__mode = "k"}),
    ToolConnections = setmetatable({}, {__mode = "k"}),
    KnownPrompts = setmetatable({}, {__mode = "k"}),
    KnownTools = setmetatable({}, {__mode = "k"}),
    EventCount = 0,
    DroppedEventCount = 0,
    LastSnapshotAt = 0,
    Report = {
        version = "Scanner V1",
        meta = {
            placeId = game.PlaceId,
            gameId = game.GameId,
            jobId = game.JobId,
            startedUnix = unix(),
        },
        summary = {},
        prompts = {},
        playerTools = {},
        worldTools = {},
        remotes = {},
        snapshots = {},
        events = {},
    }
}

local function connect(signal, callback)
    local c = signal:Connect(callback)
    table.insert(State.Connections, c)
    return c
end

local function addEvent(kind, data)
    if not State.Running then return end
    State.EventCount += 1
    local event = {
        i = State.EventCount,
        t = now() - State.StartedAt,
        unix = unix(),
        kind = kind,
        data = data,
    }
    table.insert(State.Report.events, event)
    if #State.Report.events > CONFIG.MaxEvents then
        table.remove(State.Report.events, 1)
        State.DroppedEventCount += 1
    end
end

local function recordPrompt(prompt, source)
    if not prompt:IsA("ProximityPrompt") then return end
    local key = safeFullName(prompt)
    State.Report.prompts[key] = promptDescriptor(prompt)
    State.Report.prompts[key].lastSource = source
    State.Report.prompts[key].lastSeen = now() - State.StartedAt
end

local function hookPrompt(prompt)
    if not prompt:IsA("ProximityPrompt") or State.PromptConnections[prompt] then return end
    State.KnownPrompts[prompt] = true
    recordPrompt(prompt, "hook")

    local cons = {}
    local function c(signal, fn)
        local con = signal:Connect(fn)
        table.insert(cons, con)
        table.insert(State.Connections, con)
    end

    c(prompt.Triggered, function(player)
        addEvent("prompt_triggered", {
            prompt = promptDescriptor(prompt),
            root = getRootForPrompt(prompt) and instanceDescriptor(getRootForPrompt(prompt)) or nil,
            playerIsLocal = player == LocalPlayer,
        })
    end)

    pcall(function()
        c(prompt.PromptButtonHoldBegan, function(player)
            addEvent("prompt_hold_began", {
                prompt = promptDescriptor(prompt),
                playerIsLocal = player == LocalPlayer,
            })
        end)
    end)

    pcall(function()
        c(prompt.PromptButtonHoldEnded, function(player)
            addEvent("prompt_hold_ended", {
                prompt = promptDescriptor(prompt),
                playerIsLocal = player == LocalPlayer,
            })
        end)
    end)

    c(prompt.AncestryChanged, function(_, parent)
        if not parent then
            addEvent("prompt_removed", {path = key, last = promptDescriptor(prompt)})
        end
    end)

    State.PromptConnections[prompt] = cons
end

local function collectValueState(tool)
    local out = {}
    for _, d in ipairs(tool:GetDescendants()) do
        if d:IsA("ValueBase") then
            if #out >= 100 then break end
            table.insert(out, {
                name = d.Name,
                class = d.ClassName,
                path = safeFullName(d),
                value = jsonValue(d.Value),
                attributes = attrs(d),
            })
        end
    end
    return out
end

local function toolSnapshot(tool)
    local base = instanceDescriptor(tool)
    base.valueState = collectValueState(tool)
    local descendants = {}
    for _, d in ipairs(tool:GetDescendants()) do
        if #descendants >= 120 then break end
        if d:IsA("LocalScript") or d:IsA("Script") or d:IsA("ModuleScript") or d:IsA("RemoteEvent") or d:IsA("RemoteFunction") or d:IsA("BindableEvent") or d:IsA("BindableFunction") then
            table.insert(descendants, {
                name = d.Name,
                class = d.ClassName,
                path = safeFullName(d),
                attributes = attrs(d),
            })
        end
    end
    base.specialDescendants = descendants
    return base
end

local function isPlayerTool(tool)
    local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
    if backpack and tool:IsDescendantOf(backpack) then return true end
    if LocalPlayer.Character and tool:IsDescendantOf(LocalPlayer.Character) then return true end
    return false
end

local function recordTool(tool, source)
    if not tool:IsA("Tool") then return end
    local key = safeFullName(tool)
    local snap = toolSnapshot(tool)
    snap.lastSource = source
    snap.lastSeen = now() - State.StartedAt
    if isPlayerTool(tool) then
        State.Report.playerTools[key] = snap
    elseif tool:IsDescendantOf(Workspace) then
        State.Report.worldTools[key] = snap
    end
end

local function hookTool(tool)
    if not tool:IsA("Tool") or State.ToolConnections[tool] then return end
    State.KnownTools[tool] = true
    recordTool(tool, "hook")

    local cons = {}
    local function c(signal, fn)
        local con = signal:Connect(fn)
        table.insert(cons, con)
        table.insert(State.Connections, con)
    end

    c(tool.Equipped, function()
        addEvent("tool_equipped", {tool = toolSnapshot(tool)})
    end)
    c(tool.Unequipped, function()
        addEvent("tool_unequipped", {tool = toolSnapshot(tool)})
    end)
    c(tool.Activated, function()
        addEvent("tool_activated", {tool = toolSnapshot(tool)})
        task.delay(0.05, function()
            if tool and tool.Parent and State.Running then
                addEvent("tool_after_005", {tool = toolSnapshot(tool)})
            end
        end)
        task.delay(0.25, function()
            if tool and tool.Parent and State.Running then
                addEvent("tool_after_025", {tool = toolSnapshot(tool)})
            end
        end)
        task.delay(0.75, function()
            if tool and tool.Parent and State.Running then
                addEvent("tool_after_075", {tool = toolSnapshot(tool)})
            end
        end)
    end)
    c(tool.Deactivated, function()
        addEvent("tool_deactivated", {tool = toolSnapshot(tool)})
    end)
    c(tool.AncestryChanged, function(_, parent)
        if parent then
            recordTool(tool, "ancestry_changed")
            addEvent("tool_moved", {tool = toolSnapshot(tool)})
        else
            addEvent("tool_removed", {name = tool.Name})
        end
    end)

    for _, d in ipairs(tool:GetDescendants()) do
        if d:IsA("ValueBase") then
            c(d.Changed, function(value)
                addEvent("tool_value_changed", {
                    tool = safeFullName(tool),
                    valueObject = safeFullName(d),
                    name = d.Name,
                    class = d.ClassName,
                    value = jsonValue(value),
                })
            end)
        end
    end

    State.ToolConnections[tool] = cons
end

local function remoteDescriptor(remote)
    return {
        name = remote.Name,
        class = remote.ClassName,
        path = safeFullName(remote),
        attributes = attrs(remote),
        relevantByName = containsRelevant(remote.Name .. " " .. safeFullName(remote)),
    }
end

local function scanRemotes()
    State.Report.remotes = {}
    local roots = {ReplicatedStorage, Workspace}
    for _, root in ipairs(roots) do
        for _, d in ipairs(root:GetDescendants()) do
            if d:IsA("RemoteEvent") or d:IsA("RemoteFunction") then
                table.insert(State.Report.remotes, remoteDescriptor(d))
            end
        end
    end
end

local function promptRootsSnapshot()
    local out, seen = {}, {}
    for prompt in pairs(State.KnownPrompts) do
        if prompt and prompt.Parent and prompt:IsDescendantOf(Workspace) then
            local root = getRootForPrompt(prompt)
            if root and not seen[root] then
                seen[root] = true
                table.insert(out, instanceDescriptor(root))
                if #out >= CONFIG.MaxSnapshotObjects then break end
            end
        end
    end
    return out
end

local function snapshot(reason)
    local snap = {
        t = now() - State.StartedAt,
        reason = reason or "manual",
        promptCount = 0,
        worldToolCount = 0,
        playerToolCount = 0,
        promptRoots = promptRootsSnapshot(),
        nearbyRelevant = {},
    }

    for _, d in ipairs(Workspace:GetDescendants()) do
        if d:IsA("ProximityPrompt") then snap.promptCount += 1 end
        if d:IsA("Tool") then snap.worldToolCount += 1 end
        if #snap.nearbyRelevant < CONFIG.MaxSnapshotObjects and (d:IsA("Model") or d:IsA("Tool") or d:IsA("BasePart") or d:IsA("Folder")) then
            local text = d.Name .. " " .. (d.Parent and d.Parent.Name or "")
            if containsRelevant(text) then
                table.insert(snap.nearbyRelevant, instanceDescriptor(d))
            end
        end
    end

    local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
    if backpack then
        for _, child in ipairs(backpack:GetChildren()) do
            if child:IsA("Tool") then snap.playerToolCount += 1 end
        end
    end
    if LocalPlayer.Character then
        for _, child in ipairs(LocalPlayer.Character:GetChildren()) do
            if child:IsA("Tool") then snap.playerToolCount += 1 end
        end
    end

    table.insert(State.Report.snapshots, snap)
    if #State.Report.snapshots > 30 then table.remove(State.Report.snapshots, 1) end
    State.LastSnapshotAt = now()
    addEvent("snapshot", {reason = snap.reason, promptCount = snap.promptCount, worldToolCount = snap.worldToolCount, playerToolCount = snap.playerToolCount})
    return snap
end

local function initialScan()
    for _, d in ipairs(Workspace:GetDescendants()) do
        if d:IsA("ProximityPrompt") then hookPrompt(d) end
        if d:IsA("Tool") then hookTool(d) end
    end

    local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
    if backpack then
        for _, d in ipairs(backpack:GetDescendants()) do
            if d:IsA("Tool") then hookTool(d) end
        end
    end
    if LocalPlayer.Character then
        for _, d in ipairs(LocalPlayer.Character:GetDescendants()) do
            if d:IsA("Tool") then hookTool(d) end
        end
    end

    scanRemotes()
    snapshot("initial")
end

local function buildReport()
    scanRemotes()
    for prompt in pairs(State.KnownPrompts) do
        if prompt and prompt.Parent then recordPrompt(prompt, "export") end
    end
    for tool in pairs(State.KnownTools) do
        if tool and tool.Parent then recordTool(tool, "export") end
    end

    State.Report.meta.finishedUnix = unix()
    State.Report.meta.durationSeconds = now() - State.StartedAt
    State.Report.summary = {
        promptRecords = 0,
        playerToolRecords = 0,
        worldToolRecords = 0,
        remoteCount = #State.Report.remotes,
        snapshotCount = #State.Report.snapshots,
        eventCountStored = #State.Report.events,
        eventCountTotal = State.EventCount,
        droppedOldEvents = State.DroppedEventCount,
    }
    for _ in pairs(State.Report.prompts) do State.Report.summary.promptRecords += 1 end
    for _ in pairs(State.Report.playerTools) do State.Report.summary.playerToolRecords += 1 end
    for _ in pairs(State.Report.worldTools) do State.Report.summary.worldToolRecords += 1 end
    return State.Report
end

local function exportReport()
    local report = buildReport()
    local ok, encoded = pcall(HttpService.JSONEncode, HttpService, report)
    if not ok then
        return false, "JSONEncode falhou: " .. tostring(encoded)
    end

    local fileName = "Psico_RoubeUmOvo_Scan_" .. tostring(os.time()) .. ".json"
    if writefile then
        local wOk, wErr = pcall(writefile, fileName, encoded)
        if wOk then
            return true, "Arquivo salvo: " .. fileName
        end
        return false, "writefile falhou: " .. tostring(wErr)
    end

    if setclipboard then
        local cOk, cErr = pcall(setclipboard, encoded)
        if cOk then
            return true, "JSON copiado para a área de transferência"
        end
        return false, "setclipboard falhou: " .. tostring(cErr)
    end

    return false, "Executor sem writefile/setclipboard"
end

-- Passive runtime watchers ----------------------------------------------------
connect(Workspace.DescendantAdded, function(inst)
    if not State.Running then return end
    if inst:IsA("ProximityPrompt") then
        task.defer(function()
            if inst.Parent then
                hookPrompt(inst)
                addEvent("prompt_added", {prompt = promptDescriptor(inst), root = getRootForPrompt(inst) and instanceDescriptor(getRootForPrompt(inst)) or nil})
            end
        end)
    elseif inst:IsA("Tool") then
        task.defer(function()
            if inst.Parent then
                hookTool(inst)
                addEvent("world_tool_added", {tool = toolSnapshot(inst)})
            end
        end)
    elseif (inst:IsA("Model") or inst:IsA("BasePart") or inst:IsA("Folder")) and containsRelevant(inst.Name) then
        task.defer(function()
            if inst.Parent then
                addEvent("relevant_world_added", {instance = instanceDescriptor(inst)})
            end
        end)
    end
end)

connect(Workspace.DescendantRemoving, function(inst)
    if not State.Running then return end
    if inst:IsA("Tool") then
        addEvent("world_tool_removing", {tool = toolSnapshot(inst)})
    elseif inst:IsA("ProximityPrompt") then
        addEvent("prompt_removing", {prompt = promptDescriptor(inst)})
    elseif (inst:IsA("Model") or inst:IsA("BasePart") or inst:IsA("Folder")) and containsRelevant(inst.Name) then
        addEvent("relevant_world_removing", {instance = instanceDescriptor(inst)})
    end
end)

local function hookPlayerContainer(container)
    if not container then return end
    for _, child in ipairs(container:GetDescendants()) do
        if child:IsA("Tool") then hookTool(child) end
    end
    connect(container.DescendantAdded, function(inst)
        if inst:IsA("Tool") then
            task.defer(function()
                if inst.Parent then
                    hookTool(inst)
                    addEvent("player_tool_added", {tool = toolSnapshot(inst)})
                end
            end)
        end
    end)
end

hookPlayerContainer(LocalPlayer:FindFirstChildOfClass("Backpack"))
if LocalPlayer.Character then hookPlayerContainer(LocalPlayer.Character) end
connect(LocalPlayer.CharacterAdded, function(character)
    addEvent("character_added", {path = safeFullName(character)})
    task.wait(0.5)
    hookPlayerContainer(character)
end)

-- UI -------------------------------------------------------------------------
local function uiParent()
    local ok, hui = pcall(function()
        if gethui then return gethui() end
    end)
    return (ok and hui) or CoreGui
end

local gui = Instance.new("ScreenGui")
gui.Name = "PsicoRoubeUmOvoScanner"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = uiParent()
_G.PSICO_ROUBE_SCANNER = gui

local frame = Instance.new("Frame")
frame.AnchorPoint = Vector2.new(0.5, 0.5)
frame.Position = UDim2.fromScale(0.5, 0.5)
frame.Size = UDim2.fromOffset(300, 220)
frame.BackgroundColor3 = Color3.fromRGB(15, 21, 33)
frame.BorderSizePixel = 0
frame.Parent = gui
local fc = Instance.new("UICorner")
fc.CornerRadius = UDim.new(0, 12)
fc.Parent = frame
local fs = Instance.new("UIStroke")
fs.Thickness = 1.2
fs.Transparency = 0.25
fs.Color = Color3.fromRGB(68, 121, 230)
fs.Parent = frame

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Position = UDim2.fromOffset(12, 8)
title.Size = UDim2.new(1, -48, 0, 26)
title.Font = Enum.Font.GothamBold
title.Text = "ROUBE UM OVO • SCANNER V1"
title.TextColor3 = Color3.fromRGB(240, 244, 255)
title.TextSize = 14
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = frame

local close = Instance.new("TextButton")
close.AnchorPoint = Vector2.new(1, 0)
close.Position = UDim2.new(1, -8, 0, 7)
close.Size = UDim2.fromOffset(30, 30)
close.BackgroundColor3 = Color3.fromRGB(33, 42, 60)
close.BorderSizePixel = 0
close.Font = Enum.Font.GothamBold
close.Text = "×"
close.TextColor3 = Color3.fromRGB(240, 244, 255)
close.TextSize = 17
close.Parent = frame
local cc = Instance.new("UICorner")
cc.CornerRadius = UDim.new(0, 8)
cc.Parent = close

local status = Instance.new("TextLabel")
status.Position = UDim2.fromOffset(12, 43)
status.Size = UDim2.new(1, -24, 0, 64)
status.BackgroundColor3 = Color3.fromRGB(20, 28, 43)
status.BorderSizePixel = 0
status.Font = Enum.Font.Code
status.TextColor3 = Color3.fromRGB(164, 190, 239)
status.TextSize = 11
status.TextWrapped = true
status.Text = "Scanner passivo iniciado.\nUse prompts, pegue/drope itens e teste o soco normalmente."
status.Parent = frame
local sc = Instance.new("UICorner")
sc.CornerRadius = UDim.new(0, 9)
sc.Parent = status

local function button(text, x, width)
    local b = Instance.new("TextButton")
    b.Position = UDim2.fromOffset(x, 118)
    b.Size = UDim2.fromOffset(width, 40)
    b.BackgroundColor3 = Color3.fromRGB(32, 75, 155)
    b.BorderSizePixel = 0
    b.Font = Enum.Font.GothamMedium
    b.Text = text
    b.TextColor3 = Color3.fromRGB(245, 248, 255)
    b.TextSize = 12
    b.Parent = frame
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 9)
    c.Parent = b
    return b
end

local snapButton = button("Snapshot", 12, 87)
local exportButton = button("Exportar JSON", 106, 118)
local runButton = button("Pausar", 231, 57)

local hint = Instance.new("TextLabel")
hint.BackgroundTransparency = 1
hint.Position = UDim2.fromOffset(12, 168)
hint.Size = UDim2.new(1, -24, 0, 42)
hint.Font = Enum.Font.Gotham
hint.Text = "Importante: faça pelo menos 1 interação, 1 item dropado/coletado e alguns socos antes de exportar."
hint.TextColor3 = Color3.fromRGB(137, 151, 179)
hint.TextSize = 10
hint.TextWrapped = true
hint.Parent = frame

local dragging, dragStart, startPos, activeInput
frame.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        activeInput = input
        dragStart = input.Position
        startPos = frame.Position
    end
end)
frame.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
        activeInput = input
    end
end)
UIS.InputChanged:Connect(function(input)
    if dragging and input == activeInput then
        local delta = input.Position - dragStart
        frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end
end)
UIS.InputEnded:Connect(function(input)
    if input == activeInput then dragging = false end
end)

snapButton.MouseButton1Click:Connect(function()
    local s = snapshot("manual")
    status.Text = string.format("Snapshot salvo.\nPrompts: %d  |  Tools mundo: %d  |  Tools jogador: %d", s.promptCount, s.worldToolCount, s.playerToolCount)
end)

exportButton.MouseButton1Click:Connect(function()
    local ok, message = exportReport()
    status.Text = (ok and "✓ " or "✗ ") .. message
end)

runButton.MouseButton1Click:Connect(function()
    State.Running = not State.Running
    runButton.Text = State.Running and "Pausar" or "Retomar"
    addEvent(State.Running and "scanner_resumed" or "scanner_paused", {})
end)

local function cleanup()
    State.Running = false
    for _, c in ipairs(State.Connections) do
        pcall(function() c:Disconnect() end)
    end
    _G.PSICO_ROUBE_SCANNER = nil
    pcall(function() gui:Destroy() end)
end
close.MouseButton1Click:Connect(cleanup)

connect(RunService.Heartbeat, function()
    if not State.Running then return end
    if now() - State.LastSnapshotAt >= CONFIG.AutoSnapshotInterval then
        snapshot("auto")
    end

    local promptCount = 0
    for p in pairs(State.KnownPrompts) do
        if p and p.Parent then promptCount += 1 end
    end
    local playerToolCount = 0
    for t in pairs(State.KnownTools) do
        if t and t.Parent and isPlayerTool(t) then playerToolCount += 1 end
    end
    status.Text = string.format(
        "Scanner ativo • %.0fs\nPrompts: %d  |  Tools jogador: %d  |  Eventos: %d",
        now() - State.StartedAt,
        promptCount,
        playerToolCount,
        State.EventCount
    )
end)

task.spawn(initialScan)

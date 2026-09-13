--[[
    PSICOSENATICO | Roube um Ovo
    Adaptive client-side utility menu.

    Features:
      • Instant Prompt: removes ProximityPrompt hold time as prompts appear.
      • Dropped Item ESP: highlights dropped/interactable objects using runtime heuristics.
      • Instant Punch: removes client-visible punch/tool cooldown values when possible.
      • Adaptive Scanner: watches new instances continuously so no fixed folder names are required.

    Notes:
      • Everything here works from client-visible state only.
      • Server-authoritative cooldowns/validation cannot be bypassed by local property changes.
]]

if _G.PSICO_ROUBE_UM_OVO_LOADED then
    pcall(function()
        if _G.PSICO_ROUBE_UM_OVO_TOGGLE then
            _G.PSICO_ROUBE_UM_OVO_TOGGLE()
        end
    end)
    return
end
_G.PSICO_ROUBE_UM_OVO_LOADED = true

local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

local CONFIG = {
    InstantPrompt = true,
    ItemESP = true,
    InstantPunch = true,
    ScanInterval = 1.25,
    MaxEspDistance = 1500,
}

local State = {
    Alive = true,
    Connections = {},
    PromptOriginals = setmetatable({}, {__mode = "k"}),
    CooldownOriginals = setmetatable({}, {__mode = "k"}),
    EspObjects = setmetatable({}, {__mode = "k"}),
    SeenCandidates = setmetatable({}, {__mode = "k"}),
    Stats = {
        Prompts = 0,
        Items = 0,
        PunchTools = 0,
    }
}

local function connect(signal, callback)
    local c = signal:Connect(callback)
    table.insert(State.Connections, c)
    return c
end

local function safeDisconnect(c)
    pcall(function()
        c:Disconnect()
    end)
end

local function lower(v)
    return string.lower(tostring(v or ""))
end

local function containsAny(text, words)
    text = lower(text)
    for _, word in ipairs(words) do
        if string.find(text, word, 1, true) then
            return true
        end
    end
    return false
end

local ITEM_WORDS = {
    "ovo", "egg", "item", "drop", "dropped", "loot", "pickup", "pick up",
    "colet", "collect", "grab", "steal", "roub", "reward", "coin", "cash",
    "money", "gema", "gem", "crate", "box", "presente", "gift"
}

local PUNCH_WORDS = {
    "soco", "punch", "fist", "hit", "attack", "combat", "melee", "tapa",
    "slap", "murro", "bater"
}

local COOLDOWN_WORDS = {
    "cooldown", "cool_down", "cd", "delay", "debounce", "interval", "recovery",
    "recover", "attackspeed", "attack_speed", "swingdelay", "swing_delay",
    "hitdelay", "hit_delay", "punchdelay", "punch_delay"
}

local function isCharacter(inst)
    if not inst then return false end
    local model = inst:IsA("Model") and inst or inst:FindFirstAncestorOfClass("Model")
    if not model then return false end
    if model:FindFirstChildOfClass("Humanoid") then
        return true
    end
    for _, player in ipairs(Players:GetPlayers()) do
        if player.Character == model then
            return true
        end
    end
    return false
end

local function getAdornee(inst)
    if not inst or not inst.Parent then return nil end
    if inst:IsA("BasePart") then
        return inst
    end
    if inst:IsA("Tool") then
        return inst:FindFirstChild("Handle") or inst:FindFirstChildWhichIsA("BasePart", true)
    end
    if inst:IsA("Model") then
        return inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart", true)
    end
    return inst:FindFirstAncestorWhichIsA("BasePart")
end

local function nearestVisualRoot(inst)
    if not inst then return nil end
    if inst:IsA("Tool") or inst:IsA("Model") or inst:IsA("BasePart") then
        return inst
    end

    local tool = inst:FindFirstAncestorOfClass("Tool")
    if tool and tool:IsDescendantOf(Workspace) then
        return tool
    end

    local model = inst:FindFirstAncestorOfClass("Model")
    if model and model:IsDescendantOf(Workspace) and not isCharacter(model) then
        return model
    end

    return inst:FindFirstAncestorWhichIsA("BasePart")
end

local function hasItemTag(inst)
    local current = inst
    for _ = 1, 4 do
        if not current then break end
        local ok, tags = pcall(CollectionService.GetTags, CollectionService, current)
        if ok then
            for _, tag in ipairs(tags) do
                if containsAny(tag, ITEM_WORDS) then
                    return true
                end
            end
        end
        current = current.Parent
    end
    return false
end

local function hasItemAttribute(inst)
    local current = inst
    for _ = 1, 4 do
        if not current then break end
        local ok, attrs = pcall(current.GetAttributes, current)
        if ok then
            for key, value in pairs(attrs) do
                local joined = tostring(key) .. " " .. tostring(value)
                if containsAny(joined, ITEM_WORDS) then
                    return true
                end
            end
        end
        current = current.Parent
    end
    return false
end

local function hasPrompt(inst)
    if not inst then return false end
    if inst:IsA("ProximityPrompt") then return true end
    return inst:FindFirstChildWhichIsA("ProximityPrompt", true) ~= nil
end

local function looksLikeDroppedItem(inst)
    if not inst or not inst.Parent or not inst:IsDescendantOf(Workspace) then
        return false
    end
    if isCharacter(inst) then
        return false
    end

    if inst:IsA("Tool") then
        return true
    end

    local root = nearestVisualRoot(inst)
    if not root or isCharacter(root) then
        return false
    end

    local combinedName = root.Name
    if root.Parent then
        combinedName = combinedName .. " " .. root.Parent.Name
    end

    if containsAny(combinedName, ITEM_WORDS) then
        return true
    end

    if hasItemTag(root) or hasItemAttribute(root) then
        return true
    end

    -- Interactable world objects are strong candidates in this game type.
    -- Ignore very generic character/NPC-like models above.
    if hasPrompt(root) and (root:IsA("Model") or root:IsA("Tool") or root:IsA("BasePart")) then
        return true
    end

    return false
end

local function removeESP(root)
    local record = State.EspObjects[root]
    if record then
        for _, obj in pairs(record) do
            if typeof(obj) == "Instance" then
                pcall(function() obj:Destroy() end)
            end
        end
        State.EspObjects[root] = nil
    end
end

local function createESP(root)
    if not CONFIG.ItemESP or not root or not root.Parent or State.EspObjects[root] then
        return
    end

    local adornee = getAdornee(root)
    if not adornee then return end

    local highlight = Instance.new("Highlight")
    highlight.Name = "PsicoItemHighlight"
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.FillTransparency = 0.55
    highlight.OutlineTransparency = 0
    highlight.Adornee = root
    highlight.Parent = root

    local billboard = Instance.new("BillboardGui")
    billboard.Name = "PsicoItemBillboard"
    billboard.AlwaysOnTop = true
    billboard.Size = UDim2.fromOffset(180, 34)
    billboard.StudsOffset = Vector3.new(0, 2.25, 0)
    billboard.MaxDistance = CONFIG.MaxEspDistance
    billboard.Adornee = adornee
    billboard.Parent = adornee

    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.Size = UDim2.fromScale(1, 1)
    label.Font = Enum.Font.GothamBold
    label.TextScaled = true
    label.TextStrokeTransparency = 0.15
    label.Text = "📦 " .. root.Name
    label.Parent = billboard

    State.EspObjects[root] = {
        Highlight = highlight,
        Billboard = billboard,
    }
end

local function refreshESP()
    local count = 0
    local candidates = {}

    for _, inst in ipairs(Workspace:GetDescendants()) do
        if inst:IsA("Tool") or inst:IsA("ProximityPrompt") then
            local root = nearestVisualRoot(inst)
            if root and not candidates[root] and looksLikeDroppedItem(root) then
                candidates[root] = true
                count += 1
                if CONFIG.ItemESP then
                    createESP(root)
                end
            end
        elseif (inst:IsA("Model") or inst:IsA("BasePart")) and containsAny(inst.Name, ITEM_WORDS) then
            local root = nearestVisualRoot(inst)
            if root and not candidates[root] and looksLikeDroppedItem(root) then
                candidates[root] = true
                count += 1
                if CONFIG.ItemESP then
                    createESP(root)
                end
            end
        end
    end

    for root in pairs(State.EspObjects) do
        if not CONFIG.ItemESP or not root.Parent or not candidates[root] then
            removeESP(root)
        end
    end

    State.Stats.Items = count
end

local function applyPrompt(prompt)
    if not prompt:IsA("ProximityPrompt") then return end

    if State.PromptOriginals[prompt] == nil then
        State.PromptOriginals[prompt] = {
            HoldDuration = prompt.HoldDuration,
        }
    end

    if CONFIG.InstantPrompt then
        pcall(function()
            prompt.HoldDuration = 0
        end)
    else
        local original = State.PromptOriginals[prompt]
        if original then
            pcall(function()
                prompt.HoldDuration = original.HoldDuration
            end)
        end
    end
end

local function refreshPrompts()
    local count = 0
    for _, inst in ipairs(Workspace:GetDescendants()) do
        if inst:IsA("ProximityPrompt") then
            count += 1
            applyPrompt(inst)
        end
    end
    State.Stats.Prompts = count
end

local function isPunchTool(tool)
    if not tool or not tool:IsA("Tool") then return false end
    if containsAny(tool.Name, PUNCH_WORDS) then return true end

    local ok, attrs = pcall(tool.GetAttributes, tool)
    if ok then
        for key, value in pairs(attrs) do
            if containsAny(tostring(key) .. " " .. tostring(value), PUNCH_WORDS) then
                return true
            end
        end
    end

    for _, child in ipairs(tool:GetDescendants()) do
        if containsAny(child.Name, PUNCH_WORDS) then
            return true
        end
    end

    return false
end

local function zeroCooldownObject(obj)
    if not containsAny(obj.Name, COOLDOWN_WORDS) then return end

    if obj:IsA("NumberValue") or obj:IsA("IntValue") then
        if State.CooldownOriginals[obj] == nil then
            State.CooldownOriginals[obj] = obj.Value
        end
        if CONFIG.InstantPunch then
            pcall(function() obj.Value = 0 end)
        else
            local original = State.CooldownOriginals[obj]
            if original ~= nil then
                pcall(function() obj.Value = original end)
            end
        end
    end
end

local function patchTool(tool)
    if not isPunchTool(tool) then return false end

    if CONFIG.InstantPunch then
        pcall(function() tool.Enabled = true end)
    end

    for _, child in ipairs(tool:GetDescendants()) do
        zeroCooldownObject(child)
    end

    local ok, attrs = pcall(tool.GetAttributes, tool)
    if ok then
        for key, value in pairs(attrs) do
            if containsAny(key, COOLDOWN_WORDS) and typeof(value) == "number" then
                local cacheKey = tostring(tool:GetDebugId()) .. ":attr:" .. key
                if State.CooldownOriginals[cacheKey] == nil then
                    State.CooldownOriginals[cacheKey] = value
                end
                if CONFIG.InstantPunch then
                    pcall(function() tool:SetAttribute(key, 0) end)
                else
                    pcall(function() tool:SetAttribute(key, State.CooldownOriginals[cacheKey]) end)
                end
            end
        end
    end

    return true
end

local function getPlayerContainers()
    local out = {}
    if LocalPlayer.Character then table.insert(out, LocalPlayer.Character) end
    local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
    if backpack then table.insert(out, backpack) end
    return out
end

local function refreshPunch()
    local found = 0
    for _, container in ipairs(getPlayerContainers()) do
        for _, child in ipairs(container:GetChildren()) do
            if child:IsA("Tool") and patchTool(child) then
                found += 1
            end
        end
    end
    State.Stats.PunchTools = found
end

-- UI -------------------------------------------------------------------------
local function uiParent()
    local ok, hui = pcall(function()
        if gethui then return gethui() end
    end)
    if ok and hui then return hui end
    return CoreGui
end

local old = uiParent():FindFirstChild("PsicoRoubeUmOvo")
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "PsicoRoubeUmOvo"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = uiParent()

local frame = Instance.new("Frame")
frame.Name = "Main"
frame.AnchorPoint = Vector2.new(0.5, 0.5)
frame.Position = UDim2.fromScale(0.5, 0.5)
frame.Size = UDim2.new(0, 330, 0, 290)
frame.BackgroundColor3 = Color3.fromRGB(14, 21, 35)
frame.BorderSizePixel = 0
frame.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 14)
corner.Parent = frame

local stroke = Instance.new("UIStroke")
stroke.Thickness = 1.4
stroke.Transparency = 0.2
stroke.Color = Color3.fromRGB(43, 116, 255)
stroke.Parent = frame

local top = Instance.new("Frame")
top.BackgroundTransparency = 1
top.Size = UDim2.new(1, -16, 0, 58)
top.Position = UDim2.fromOffset(8, 4)
top.Parent = frame

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Position = UDim2.fromOffset(8, 4)
title.Size = UDim2.new(1, -92, 0, 24)
title.Font = Enum.Font.GothamBold
title.Text = "PSICOSENATICO PANEL"
title.TextColor3 = Color3.fromRGB(236, 241, 255)
title.TextSize = 16
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = top

local subtitle = Instance.new("TextLabel")
subtitle.BackgroundTransparency = 1
subtitle.Position = UDim2.fromOffset(8, 28)
subtitle.Size = UDim2.new(1, -92, 0, 18)
subtitle.Font = Enum.Font.Gotham
subtitle.Text = "ROUBE UM OVO • Adaptive Scanner"
subtitle.TextColor3 = Color3.fromRGB(117, 151, 210)
subtitle.TextSize = 11
subtitle.TextXAlignment = Enum.TextXAlignment.Left
subtitle.Parent = top

local function smallButton(text, x)
    local b = Instance.new("TextButton")
    b.Size = UDim2.fromOffset(32, 32)
    b.Position = UDim2.new(1, x, 0, 8)
    b.BackgroundColor3 = Color3.fromRGB(24, 35, 56)
    b.BorderSizePixel = 0
    b.Font = Enum.Font.GothamBold
    b.Text = text
    b.TextColor3 = Color3.fromRGB(225, 232, 247)
    b.TextSize = 16
    b.AutoButtonColor = true
    b.Parent = top
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 9)
    c.Parent = b
    return b
end

local minButton = smallButton("—", -72)
local closeButton = smallButton("×", -36)

local content = Instance.new("Frame")
content.BackgroundTransparency = 1
content.Position = UDim2.fromOffset(14, 66)
content.Size = UDim2.new(1, -28, 1, -78)
content.Parent = frame

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 9)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = content

local buttonRefs = {}

local function makeToggle(labelText, configKey, order)
    local row = Instance.new("TextButton")
    row.LayoutOrder = order
    row.Size = UDim2.new(1, 0, 0, 46)
    row.BackgroundColor3 = Color3.fromRGB(20, 30, 48)
    row.BorderSizePixel = 0
    row.AutoButtonColor = false
    row.Text = ""
    row.Parent = content

    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 10)
    c.Parent = row

    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.Position = UDim2.fromOffset(13, 0)
    label.Size = UDim2.new(1, -78, 1, 0)
    label.Font = Enum.Font.GothamMedium
    label.Text = labelText
    label.TextColor3 = Color3.fromRGB(229, 235, 247)
    label.TextSize = 14
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = row

    local pill = Instance.new("Frame")
    pill.AnchorPoint = Vector2.new(1, 0.5)
    pill.Position = UDim2.new(1, -12, 0.5, 0)
    pill.Size = UDim2.fromOffset(44, 24)
    pill.BorderSizePixel = 0
    pill.Parent = row

    local pc = Instance.new("UICorner")
    pc.CornerRadius = UDim.new(1, 0)
    pc.Parent = pill

    local dot = Instance.new("Frame")
    dot.Size = UDim2.fromOffset(18, 18)
    dot.BorderSizePixel = 0
    dot.Parent = pill
    local dc = Instance.new("UICorner")
    dc.CornerRadius = UDim.new(1, 0)
    dc.Parent = dot

    local function paint()
        local on = CONFIG[configKey]
        pill.BackgroundColor3 = on and Color3.fromRGB(40, 105, 235) or Color3.fromRGB(60, 67, 82)
        dot.BackgroundColor3 = Color3.fromRGB(242, 246, 255)
        dot.Position = on and UDim2.fromOffset(23, 3) or UDim2.fromOffset(3, 3)
    end

    row.MouseButton1Click:Connect(function()
        CONFIG[configKey] = not CONFIG[configKey]
        paint()
        if configKey == "InstantPrompt" then refreshPrompts() end
        if configKey == "ItemESP" then refreshESP() end
        if configKey == "InstantPunch" then refreshPunch() end
    end)

    paint()
    buttonRefs[configKey] = paint
end

makeToggle("Instant Prompt", "InstantPrompt", 1)
makeToggle("ESP • Itens dropados", "ItemESP", 2)
makeToggle("Instant Soco", "InstantPunch", 3)

local status = Instance.new("TextLabel")
status.LayoutOrder = 4
status.Size = UDim2.new(1, 0, 0, 46)
status.BackgroundColor3 = Color3.fromRGB(17, 26, 42)
status.BorderSizePixel = 0
status.Font = Enum.Font.Code
status.TextColor3 = Color3.fromRGB(139, 172, 226)
status.TextSize = 11
status.TextWrapped = true
status.Parent = content
local sc = Instance.new("UICorner")
sc.CornerRadius = UDim.new(0, 10)
sc.Parent = status

local floating = Instance.new("TextButton")
floating.Name = "Floating"
floating.Visible = false
floating.AnchorPoint = Vector2.new(1, 0.5)
floating.Position = UDim2.new(1, -22, 0.55, 0)
floating.Size = UDim2.fromOffset(54, 54)
floating.BackgroundColor3 = Color3.fromRGB(14, 35, 72)
floating.BorderSizePixel = 0
floating.Font = Enum.Font.GothamBlack
floating.Text = "PS"
floating.TextColor3 = Color3.fromRGB(233, 240, 255)
floating.TextSize = 17
floating.Parent = gui
local fc = Instance.new("UICorner")
fc.CornerRadius = UDim.new(1, 0)
fc.Parent = floating
local fs = Instance.new("UIStroke")
fs.Thickness = 1.5
fs.Color = Color3.fromRGB(55, 119, 255)
fs.Parent = floating

local function makeDraggable(handle, target)
    local dragging = false
    local dragStart
    local startPos
    local activeInput

    handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            activeInput = input
            dragStart = input.Position
            startPos = target.Position
        end
    end)

    handle.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            activeInput = input
        end
    end)

    UIS.InputChanged:Connect(function(input)
        if dragging and input == activeInput then
            local delta = input.Position - dragStart
            target.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
        end
    end)

    UIS.InputEnded:Connect(function(input)
        if input == activeInput then
            dragging = false
        end
    end)
end

makeDraggable(top, frame)
makeDraggable(floating, floating)

local function setMinimized(v)
    frame.Visible = not v
    floating.Visible = v
end

minButton.MouseButton1Click:Connect(function() setMinimized(true) end)
floating.MouseButton1Click:Connect(function() setMinimized(false) end)

local function cleanup()
    if not State.Alive then return end
    State.Alive = false

    CONFIG.InstantPrompt = false
    CONFIG.ItemESP = false
    CONFIG.InstantPunch = false

    for prompt, original in pairs(State.PromptOriginals) do
        if prompt and prompt.Parent and original then
            pcall(function() prompt.HoldDuration = original.HoldDuration end)
        end
    end

    for root in pairs(State.EspObjects) do
        removeESP(root)
    end

    for _, c in ipairs(State.Connections) do
        safeDisconnect(c)
    end

    pcall(function() gui:Destroy() end)
    _G.PSICO_ROUBE_UM_OVO_LOADED = nil
    _G.PSICO_ROUBE_UM_OVO_TOGGLE = nil
end

closeButton.MouseButton1Click:Connect(cleanup)
_G.PSICO_ROUBE_UM_OVO_TOGGLE = function()
    if State.Alive then
        setMinimized(frame.Visible)
    end
end

-- Runtime scanner -------------------------------------------------------------
connect(Workspace.DescendantAdded, function(inst)
    if inst:IsA("ProximityPrompt") then
        task.defer(function()
            if State.Alive and inst.Parent then
                applyPrompt(inst)
                if CONFIG.ItemESP then
                    local root = nearestVisualRoot(inst)
                    if root and looksLikeDroppedItem(root) then
                        createESP(root)
                    end
                end
            end
        end)
    elseif inst:IsA("Tool") then
        task.defer(function()
            if State.Alive and inst.Parent and inst:IsDescendantOf(Workspace) and CONFIG.ItemESP then
                createESP(inst)
            end
        end)
    end
end)

connect(LocalPlayer.CharacterAdded, function()
    task.wait(0.8)
    if State.Alive then refreshPunch() end
end)

local heartbeatAccumulator = 0
connect(RunService.Heartbeat, function(dt)
    heartbeatAccumulator += dt

    if CONFIG.InstantPunch then
        for _, container in ipairs(getPlayerContainers()) do
            for _, child in ipairs(container:GetChildren()) do
                if child:IsA("Tool") and isPunchTool(child) then
                    pcall(function() child.Enabled = true end)
                end
            end
        end
    end

    if heartbeatAccumulator >= CONFIG.ScanInterval then
        heartbeatAccumulator = 0
        refreshPrompts()
        refreshESP()
        refreshPunch()
        status.Text = string.format(
            "Scanner: %d prompts  •  %d itens  •  %d ferramenta(s) de soco",
            State.Stats.Prompts,
            State.Stats.Items,
            State.Stats.PunchTools
        )
    end
end)

-- Initial pass.
task.spawn(function()
    refreshPrompts()
    refreshESP()
    refreshPunch()
    status.Text = string.format(
        "Scanner: %d prompts  •  %d itens  •  %d ferramenta(s) de soco",
        State.Stats.Prompts,
        State.Stats.Items,
        State.Stats.PunchTools
    )
end)

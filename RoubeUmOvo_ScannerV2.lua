--[[
PSICOSENATICO | Roube um Ovo - Menu V2
Built from passive Scan V2 data.
Stable loader path: RoubeUmOvo_ScannerV2.lua
]]

if _G.PSICO_ROUBE_MENU_CLEANUP then
    pcall(_G.PSICO_ROUBE_MENU_CLEANUP)
end
if _G.PSICO_ROUBE_SCANNER_V2 then
    pcall(function() _G.PSICO_ROUBE_SCANNER_V2:Destroy() end)
    _G.PSICO_ROUBE_SCANNER_V2 = nil
end

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CoreGui = game:GetService("CoreGui")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local LP = Players.LocalPlayer

local CONFIG = {
    InstantPrompt = true,
    DropESP = true,
    InstantHit = true,
}

local State = {
    Alive = true,
    Connections = {},
    RemoteConnections = {},
    PromptOriginals = setmetatable({}, {__mode="k"}),
    BatHooks = setmetatable({}, {__mode="k"}),
    BatPatching = setmetatable({}, {__mode="k"}),
    Drops = {},
    ESP = {},
}

local function connect(signal, fn)
    local c = signal:Connect(fn)
    table.insert(State.Connections, c)
    return c
end

local function disconnect(c)
    pcall(function() c:Disconnect() end)
end

local function parentGui()
    local ok, h = pcall(function()
        if gethui then return gethui() end
    end)
    return (ok and h) or CoreGui
end

-- Instant Prompt -------------------------------------------------------------

local function applyPrompt(prompt)
    if not prompt:IsA("ProximityPrompt") then return end
    if State.PromptOriginals[prompt] == nil then
        State.PromptOriginals[prompt] = prompt.HoldDuration
    end
    if CONFIG.InstantPrompt then
        pcall(function() prompt.HoldDuration = 0 end)
    else
        local original = State.PromptOriginals[prompt]
        if original ~= nil then
            pcall(function() prompt.HoldDuration = original end)
        end
    end
end

local function refreshPrompts()
    for _, d in ipairs(Workspace:GetDescendants()) do
        if d:IsA("ProximityPrompt") then
            applyPrompt(d)
        end
    end
end

connect(Workspace.DescendantAdded, function(d)
    if d:IsA("ProximityPrompt") then
        task.defer(function()
            if State.Alive and d.Parent then applyPrompt(d) end
        end)
    end
end)

-- Dropped Item ESP ------------------------------------------------------------

local function getAdornee(model)
    if not model then return nil end
    if model:IsA("BasePart") then return model end
    return model.PrimaryPart
        or model:FindFirstChild("Hitbox", true)
        or model:FindFirstChildWhichIsA("BasePart", true)
end

local function destroyESP(uid)
    local rec = State.ESP[uid]
    if not rec then return end
    if rec.highlight then pcall(function() rec.highlight:Destroy() end) end
    if rec.billboard then pcall(function() rec.billboard:Destroy() end) end
    State.ESP[uid] = nil
end

local function createESP(uid)
    destroyESP(uid)
    if not CONFIG.DropESP then return end

    local drop = State.Drops[uid]
    if not drop or drop.State ~= "Dropped" then return end

    local model = Workspace:FindFirstChild(uid)
    if not model then return end

    local adornee = getAdornee(model)
    if not adornee then return end

    local h = Instance.new("Highlight")
    h.Name = "PsicoDropESP"
    h.Adornee = model
    h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    h.FillColor = Color3.fromRGB(255, 179, 71)
    h.OutlineColor = Color3.fromRGB(255, 239, 190)
    h.FillTransparency = 0.62
    h.OutlineTransparency = 0
    h.Parent = model

    local b = Instance.new("BillboardGui")
    b.Name = "PsicoDropLabel"
    b.Adornee = adornee
    b.AlwaysOnTop = true
    b.MaxDistance = 1200
    b.Size = UDim2.fromOffset(150, 28)
    b.StudsOffset = Vector3.new(0, 2.2, 0)
    b.Parent = adornee

    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.Size = UDim2.fromScale(1,1)
    label.Font = Enum.Font.GothamBold
    label.TextSize = 12
    label.TextColor3 = Color3.fromRGB(255, 238, 190)
    label.TextStrokeTransparency = 0.25
    label.Text = tostring(drop.AssetCategory or "Item") .. " • DROP"
    label.Parent = b

    State.ESP[uid] = {
        model = model,
        highlight = h,
        billboard = b,
    }
end

local function clearAllESP()
    local uids = {}
    for uid in pairs(State.ESP) do table.insert(uids, uid) end
    for _, uid in ipairs(uids) do destroyESP(uid) end
end

local function setDropRecord(record)
    if typeof(record) ~= "table" then return end
    local uid = record.Uid
    if type(uid) ~= "string" or uid == "" then return end

    if record.State == "Dropped" then
        State.Drops[uid] = record
        task.defer(function()
            if State.Alive then
                task.wait()
                createESP(uid)
            end
        end)
    else
        State.Drops[uid] = nil
        destroyESP(uid)
    end
end

local function onFieldEggGone(uid)
    if type(uid) ~= "string" then return end
    State.Drops[uid] = nil
    destroyESP(uid)
end

local function onFieldEggBatchShifted(payload)
    if typeof(payload) ~= "table" then return end

    local removed = payload.RemovedUids
    if typeof(removed) == "table" then
        for _, uid in pairs(removed) do
            if type(uid) == "string" then
                State.Drops[uid] = nil
                destroyESP(uid)
            end
        end
    end

    local updated = payload.UpdatedRecords
    if typeof(updated) == "table" then
        for _, record in pairs(updated) do
            setDropRecord(record)
        end
    end
end

local hookedRemotes = {}
local function hookRemote(remote)
    if hookedRemotes[remote] then return end
    hookedRemotes[remote] = true

    if remote.Name == "RE/EggWorld/FieldEggShifted" then
        table.insert(State.RemoteConnections, remote.OnClientEvent:Connect(setDropRecord))
    elseif remote.Name == "RE/EggWorld/FieldEggGone" then
        table.insert(State.RemoteConnections, remote.OnClientEvent:Connect(onFieldEggGone))
    elseif remote.Name == "RE/EggWorld/FieldEggBatchShifted" then
        table.insert(State.RemoteConnections, remote.OnClientEvent:Connect(onFieldEggBatchShifted))
    end
end

local TARGET_REMOTES = {
    ["RE/EggWorld/FieldEggShifted"] = true,
    ["RE/EggWorld/FieldEggGone"] = true,
    ["RE/EggWorld/FieldEggBatchShifted"] = true,
}

local function hookDropRemotes()
    for _, d in ipairs(ReplicatedStorage:GetDescendants()) do
        if d:IsA("RemoteEvent") and TARGET_REMOTES[d.Name] then
            hookRemote(d)
        end
    end
end

connect(ReplicatedStorage.DescendantAdded, function(d)
    if d:IsA("RemoteEvent") and TARGET_REMOTES[d.Name] then
        hookRemote(d)
    end
end)

connect(Workspace.ChildAdded, function(child)
    local uid = child.Name
    if State.Drops[uid] and State.Drops[uid].State == "Dropped" then
        task.defer(function()
            if State.Alive and child.Parent == Workspace then createESP(uid) end
        end)
    end
end)

connect(Workspace.ChildRemoved, function(child)
    local uid = child.Name
    local rec = State.ESP[uid]
    if rec and rec.model == child then
        destroyESP(uid)
    end
end)

-- Instant Hit / Bat -----------------------------------------------------------

local function isBat(tool)
    if not tool or not tool:IsA("Tool") then return false end
    if tool:GetAttribute("IsBat") == true then return true end
    local gearName = tostring(tool:GetAttribute("GearName") or "")
    return string.find(string.lower(gearName), "bat", 1, true) ~= nil
end

local function patchBat(tool)
    if not CONFIG.InstantHit or not isBat(tool) then return end
    if State.BatPatching[tool] then return end
    State.BatPatching[tool] = true

    pcall(function() tool.Enabled = true end)
    pcall(function()
        if tool:GetAttribute("CooldownActive") ~= false then
            tool:SetAttribute("CooldownActive", false)
        end
        if tool:GetAttribute("CooldownDuration") ~= 0 then
            tool:SetAttribute("CooldownDuration", 0)
        end
        if tool:GetAttribute("CooldownEndTime") ~= 0 then
            tool:SetAttribute("CooldownEndTime", 0)
        end
    end)

    State.BatPatching[tool] = nil
end

local function hookBat(tool)
    if not isBat(tool) or State.BatHooks[tool] then return end
    State.BatHooks[tool] = true

    for _, attr in ipairs({"CooldownActive","CooldownDuration","CooldownEndTime"}) do
        connect(tool:GetAttributeChangedSignal(attr), function()
            if CONFIG.InstantHit then
                task.defer(function()
                    if State.Alive and tool.Parent then patchBat(tool) end
                end)
            end
        end)
    end

    connect(tool.Activated, function()
        if CONFIG.InstantHit then
            patchBat(tool)
            task.defer(function()
                if State.Alive and tool.Parent then patchBat(tool) end
            end)
        end
    end)

    patchBat(tool)
end

local function scanBats()
    local backpack = LP:FindFirstChildOfClass("Backpack")
    if backpack then
        for _, d in ipairs(backpack:GetChildren()) do
            if d:IsA("Tool") then hookBat(d) end
        end
    end
    if LP.Character then
        for _, d in ipairs(LP.Character:GetChildren()) do
            if d:IsA("Tool") then hookBat(d) end
        end
    end
end

local function hookContainer(container)
    if not container then return end
    connect(container.ChildAdded, function(d)
        if d:IsA("Tool") then
            task.defer(function()
                if State.Alive and d.Parent then hookBat(d) end
            end)
        end
    end)
end

hookContainer(LP:FindFirstChildOfClass("Backpack"))
if LP.Character then hookContainer(LP.Character) end
connect(LP.CharacterAdded, function(char)
    task.wait(0.3)
    if not State.Alive then return end
    hookContainer(char)
    scanBats()
end)

local acc = 0
connect(RunService.Heartbeat, function(dt)
    if not State.Alive then return end
    acc += dt
    if acc < 0.12 then return end
    acc = 0
    if CONFIG.InstantHit then
        scanBats()
        local backpack = LP:FindFirstChildOfClass("Backpack")
        if backpack then
            for _, tool in ipairs(backpack:GetChildren()) do patchBat(tool) end
        end
        if LP.Character then
            for _, tool in ipairs(LP.Character:GetChildren()) do patchBat(tool) end
        end
    end
end)

-- Compact UI -----------------------------------------------------------------

local old = parentGui():FindFirstChild("PsicoRoubeUmOvoMenuV2")
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "PsicoRoubeUmOvoMenuV2"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = parentGui()

local frame = Instance.new("Frame")
frame.AnchorPoint = Vector2.new(.5,.5)
frame.Position = UDim2.fromScale(.5,.5)
frame.Size = UDim2.fromOffset(250, 190)
frame.BackgroundColor3 = Color3.fromRGB(15,21,33)
frame.BorderSizePixel = 0
frame.Parent = gui
local fc = Instance.new("UICorner", frame)
fc.CornerRadius = UDim.new(0,11)

local stroke = Instance.new("UIStroke", frame)
stroke.Thickness = 1
stroke.Transparency = .35
stroke.Color = Color3.fromRGB(73,126,230)

local header = Instance.new("Frame")
header.BackgroundTransparency = 1
header.Size = UDim2.new(1,-10,0,38)
header.Position = UDim2.fromOffset(5,3)
header.Parent = frame

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Position = UDim2.fromOffset(8,4)
title.Size = UDim2.new(1,-72,0,28)
title.Font = Enum.Font.GothamBold
title.Text = "ROUBE UM OVO • V2"
title.TextColor3 = Color3.fromRGB(241,245,255)
title.TextSize = 13
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = header

local function headButton(text, x)
    local b = Instance.new("TextButton")
    b.AnchorPoint = Vector2.new(1,0)
    b.Position = UDim2.new(1,x,0,3)
    b.Size = UDim2.fromOffset(28,28)
    b.BackgroundColor3 = Color3.fromRGB(32,42,60)
    b.BorderSizePixel = 0
    b.Font = Enum.Font.GothamBold
    b.Text = text
    b.TextColor3 = Color3.fromRGB(240,244,255)
    b.TextSize = 15
    b.Parent = header
    local c = Instance.new("UICorner",b)
    c.CornerRadius = UDim.new(0,8)
    return b
end

local minButton = headButton("—",-32)
local closeButton = headButton("×",0)

local body = Instance.new("Frame")
body.BackgroundTransparency = 1
body.Position = UDim2.fromOffset(10,43)
body.Size = UDim2.new(1,-20,1,-53)
body.Parent = frame

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0,6)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = body

local function makeToggle(text, key, order)
    local row = Instance.new("TextButton")
    row.LayoutOrder = order
    row.Size = UDim2.new(1,0,0,34)
    row.BackgroundColor3 = Color3.fromRGB(22,30,46)
    row.BorderSizePixel = 0
    row.Text = ""
    row.AutoButtonColor = false
    row.Parent = body
    local rc = Instance.new("UICorner",row)
    rc.CornerRadius = UDim.new(0,8)

    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.Position = UDim2.fromOffset(10,0)
    label.Size = UDim2.new(1,-62,1,0)
    label.Font = Enum.Font.GothamMedium
    label.Text = text
    label.TextColor3 = Color3.fromRGB(230,235,247)
    label.TextSize = 12
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = row

    local pill = Instance.new("Frame")
    pill.AnchorPoint = Vector2.new(1,.5)
    pill.Position = UDim2.new(1,-9,.5,0)
    pill.Size = UDim2.fromOffset(36,20)
    pill.BorderSizePixel = 0
    pill.Parent = row
    local pc = Instance.new("UICorner",pill)
    pc.CornerRadius = UDim.new(1,0)

    local dot = Instance.new("Frame")
    dot.Size = UDim2.fromOffset(14,14)
    dot.BorderSizePixel = 0
    dot.Parent = pill
    local dc = Instance.new("UICorner",dot)
    dc.CornerRadius = UDim.new(1,0)

    local function paint()
        local on = CONFIG[key]
        pill.BackgroundColor3 = on and Color3.fromRGB(48,109,232) or Color3.fromRGB(64,70,82)
        dot.BackgroundColor3 = Color3.fromRGB(245,248,255)
        dot.Position = on and UDim2.fromOffset(19,3) or UDim2.fromOffset(3,3)
    end

    row.MouseButton1Click:Connect(function()
        CONFIG[key] = not CONFIG[key]
        paint()

        if key == "InstantPrompt" then
            refreshPrompts()
        elseif key == "DropESP" then
            if CONFIG.DropESP then
                for uid in pairs(State.Drops) do createESP(uid) end
            else
                clearAllESP()
            end
        elseif key == "InstantHit" and CONFIG.InstantHit then
            scanBats()
        end
    end)

    paint()
end

makeToggle("Instant Prompt","InstantPrompt",1)
makeToggle("ESP • Drops confirmados","DropESP",2)
makeToggle("Instant Hit • Bat","InstantHit",3)

local status = Instance.new("TextLabel")
status.LayoutOrder = 4
status.Size = UDim2.new(1,0,0,24)
status.BackgroundTransparency = 1
status.Font = Enum.Font.Code
status.TextColor3 = Color3.fromRGB(132,158,205)
status.TextSize = 10
status.TextXAlignment = Enum.TextXAlignment.Left
status.Parent = body

local floating = Instance.new("TextButton")
floating.Visible = false
floating.AnchorPoint = Vector2.new(1,.5)
floating.Position = UDim2.new(1,-14,.55,0)
floating.Size = UDim2.fromOffset(42,42)
floating.BackgroundColor3 = Color3.fromRGB(18,40,78)
floating.BorderSizePixel = 0
floating.Font = Enum.Font.GothamBlack
floating.Text = "P"
floating.TextColor3 = Color3.fromRGB(240,245,255)
floating.TextSize = 15
floating.Parent = gui
local flc = Instance.new("UICorner",floating)
flc.CornerRadius = UDim.new(1,0)

local function draggable(handle,target)
    local dragging=false
    local dragStart,startPos,activeInput

    handle.InputBegan:Connect(function(input)
        if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
            dragging=true
            activeInput=input
            dragStart=input.Position
            startPos=target.Position
        end
    end)

    handle.InputChanged:Connect(function(input)
        if input.UserInputType==Enum.UserInputType.MouseMovement or input.UserInputType==Enum.UserInputType.Touch then
            activeInput=input
        end
    end)

    UIS.InputChanged:Connect(function(input)
        if dragging and input==activeInput then
            local delta=input.Position-dragStart
            target.Position=UDim2.new(
                startPos.X.Scale,startPos.X.Offset+delta.X,
                startPos.Y.Scale,startPos.Y.Offset+delta.Y
            )
        end
    end)

    UIS.InputEnded:Connect(function(input)
        if input==activeInput then dragging=false end
    end)
end

draggable(header,frame)
draggable(floating,floating)

minButton.MouseButton1Click:Connect(function()
    frame.Visible=false
    floating.Visible=true
end)

floating.MouseButton1Click:Connect(function()
    floating.Visible=false
    frame.Visible=true
end)

local function cleanup()
    if not State.Alive then return end
    State.Alive=false

    CONFIG.InstantPrompt=false
    for prompt, original in pairs(State.PromptOriginals) do
        if prompt and prompt.Parent then
            pcall(function() prompt.HoldDuration=original end)
        end
    end

    clearAllESP()

    for _,c in ipairs(State.RemoteConnections) do disconnect(c) end
    for _,c in ipairs(State.Connections) do disconnect(c) end

    _G.PSICO_ROUBE_MENU_CLEANUP=nil
    pcall(function() gui:Destroy() end)
end

_G.PSICO_ROUBE_MENU_CLEANUP=cleanup
closeButton.MouseButton1Click:Connect(cleanup)

-- Start ----------------------------------------------------------------------

hookDropRemotes()
refreshPrompts()
scanBats()

task.spawn(function()
    while State.Alive do
        local drops=0
        for uid,record in pairs(State.Drops) do
            if record.State=="Dropped" then drops += 1 end
            if CONFIG.DropESP and not State.ESP[uid] then createESP(uid) end
        end
        status.Text=string.format("Drops confirmados: %d",drops)
        task.wait(.5)
    end
end)

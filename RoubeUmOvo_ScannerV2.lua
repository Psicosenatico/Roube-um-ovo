--[[
PSICOSENATICO | Roube um Ovo - Scanner V3
Focused passive scanner for eggs that are actually in nests.
Stable loader path: RoubeUmOvo_ScannerV2.lua

Rules:
  • Only FieldEgg records with State == "Slot" are stored as current eggs.
  • Carried/Dropped records are NOT stored as eggs; they only remove a known Slot egg.
  • Rarity is learned separately from FieldEggRedeemVerdict by AssetCategory.
  • No ESP, no prompt edits, no cooldown edits, no remote firing.
]]

if _G.PSICO_ROUBE_MENU_CLEANUP then
    pcall(_G.PSICO_ROUBE_MENU_CLEANUP)
    _G.PSICO_ROUBE_MENU_CLEANUP = nil
end
if _G.PSICO_ROUBE_SCANNER_CLEANUP then
    pcall(_G.PSICO_ROUBE_SCANNER_CLEANUP)
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")
local UIS = game:GetService("UserInputService")

local startedClock = os.clock()
local startedUnix = os.time()

local State = {
    Alive = true,
    Connections = {},
    RemoteConnections = {},
    Eggs = {},
    RarityCatalog = {},
    Events = {},
    EventCount = 0,
}

local TARGETS = {
    ["RE/EggWorld/FieldEggShifted"] = true,
    ["RE/EggWorld/FieldEggBatchShifted"] = true,
    ["RE/EggWorld/FieldEggGone"] = true,
    ["RE/EggWorld/FieldEggRedeemVerdict"] = true,
}

local function elapsed()
    return os.clock() - startedClock
end

local function connect(signal, fn, bucket)
    local c = signal:Connect(fn)
    table.insert(bucket or State.Connections, c)
    return c
end

local function safeDisconnect(c)
    pcall(function() c:Disconnect() end)
end

local function plain(v)
    local tv = typeof(v)
    if tv == "nil" then return nil end
    if tv == "string" or tv == "number" or tv == "boolean" then return v end
    if tv == "Vector3" then return {x=v.X,y=v.Y,z=v.Z} end
    if tv == "Vector2" then return {x=v.X,y=v.Y} end
    if tv == "Color3" then return {r=v.R,g=v.G,b=v.B} end
    if tv == "CFrame" then
        local p = v.Position
        return {x=p.X,y=p.Y,z=p.Z}
    end
    if tv == "EnumItem" then return tostring(v) end
    if tv == "table" then
        local out = {}
        for k,val in pairs(v) do out[tostring(k)] = plain(val) end
        return out
    end
    return tostring(v)
end

local function copyMutations(v)
    if typeof(v) ~= "table" then return {} end
    local out = {}
    for _, mutation in pairs(v) do
        table.insert(out, tostring(mutation))
    end
    table.sort(out)
    return out
end

local function addEvent(kind, data)
    State.EventCount += 1
    table.insert(State.Events, {
        i = State.EventCount,
        t = elapsed(),
        kind = kind,
        data = data,
    })
    if #State.Events > 1200 then
        table.remove(State.Events, 1)
    end
end

local function normalizedSlot(record)
    local category = tostring(record.AssetCategory or "Unknown")
    local known = State.RarityCatalog[category]
    return {
        Uid = tostring(record.Uid),
        State = "Slot",
        NestId = record.NestId,
        AreaId = record.AreaId,
        AssetCategory = record.AssetCategory,
        DisplayName = known and known.DisplayName or nil,
        Rarity = record.Rarity or (known and known.Rarity) or nil,

        -- Size/filter signals discovered by Scan V2.
        NestScale = record.NestScale,
        AssetScale = record.AssetScale,
        BoundsSize = plain(record.BoundsSize),
        BoundsCFrame = plain(record.BoundsCFrame),
        BottomCFrame = plain(record.BottomCFrame),

        -- Useful future filters/visual variants.
        BaseMutation = record.BaseMutation,
        Mutations = copyMutations(record.Mutations),
        HasParasite = record.HasParasite == true,
        AssetColorIndex = record.AssetColorIndex,
        AssetColorSeed = record.AssetColorSeed,
        AssetEyeColor = record.AssetEyeColor,
        Version = record.Version,

        FirstSeen = State.Eggs[tostring(record.Uid)] and State.Eggs[tostring(record.Uid)].FirstSeen or elapsed(),
        LastSeen = elapsed(),
    }
end

local statusLabel
local function counts()
    local eggCount, categoryCount, rarityCount = 0, 0, 0
    local categories = {}
    for _, egg in pairs(State.Eggs) do
        eggCount += 1
        local c = tostring(egg.AssetCategory or "Unknown")
        categories[c] = true
    end
    for _ in pairs(categories) do categoryCount += 1 end
    for _ in pairs(State.RarityCatalog) do rarityCount += 1 end
    return eggCount, categoryCount, rarityCount
end

local function refreshStatus(extra)
    if not statusLabel then return end
    local eggs, cats, rarities = counts()
    statusLabel.Text = string.format(
        "Ovos nos ninhos: %d  |  Tipos: %d\nRaridades conhecidas: %d%s",
        eggs, cats, rarities, extra and ("\n" .. extra) or ""
    )
end

local function removeEgg(uid, reason)
    if type(uid) ~= "string" then return end
    local old = State.Eggs[uid]
    if old then
        State.Eggs[uid] = nil
        addEvent("slot_removed", {
            Uid = uid,
            AssetCategory = old.AssetCategory,
            AreaId = old.AreaId,
            NestId = old.NestId,
            Reason = reason,
        })
        refreshStatus()
    end
end

local function ingestFieldRecord(record, source)
    if typeof(record) ~= "table" then return end
    local uid = record.Uid
    if type(uid) ~= "string" or uid == "" then return end

    if record.State == "Slot" then
        local slot = normalizedSlot(record)
        State.Eggs[uid] = slot
        addEvent("slot_seen", {
            Source = source,
            Uid = uid,
            AssetCategory = slot.AssetCategory,
            AreaId = slot.AreaId,
            NestId = slot.NestId,
            Rarity = slot.Rarity,
            NestScale = slot.NestScale,
            AssetScale = slot.AssetScale,
            BoundsSize = slot.BoundsSize,
            Mutations = slot.Mutations,
            BaseMutation = slot.BaseMutation,
        })
        refreshStatus()
    else
        -- Do not record carried/dropped metadata. If this egg was in a nest,
        -- its departure simply removes it from the current Slot set.
        removeEgg(uid, "state:" .. tostring(record.State))
    end
end

local function onBatch(payload)
    if typeof(payload) ~= "table" then return end

    if typeof(payload.RemovedUids) == "table" then
        for _, uid in pairs(payload.RemovedUids) do
            if type(uid) == "string" then removeEgg(uid, "batch_removed") end
        end
    end

    if typeof(payload.UpdatedRecords) == "table" then
        for _, record in pairs(payload.UpdatedRecords) do
            ingestFieldRecord(record, "batch")
        end
    end
end

local function onRedeemVerdict(info)
    if typeof(info) ~= "table" then return end
    local category = info.AssetCategory
    local rarity = info.Rarity
    if type(category) ~= "string" or category == "" then return end
    if type(rarity) ~= "string" or rarity == "" then return end

    State.RarityCatalog[category] = {
        AssetCategory = category,
        Rarity = rarity,
        DisplayName = info.DisplayName,
        Color = plain(info.Color),
        LastSeen = elapsed(),
    }

    -- Backfill current eggs of the same category without tracking any redeemed egg.
    for _, egg in pairs(State.Eggs) do
        if egg.AssetCategory == category then
            egg.Rarity = rarity
            egg.DisplayName = info.DisplayName or egg.DisplayName
        end
    end

    addEvent("rarity_learned", {
        AssetCategory = category,
        Rarity = rarity,
        DisplayName = info.DisplayName,
    })
    refreshStatus("Catálogo atualizado: " .. category .. " = " .. rarity)
end

local hooked = setmetatable({}, {__mode="k"})
local function hookRemote(remote)
    if hooked[remote] then return end
    hooked[remote] = true

    if remote.Name == "RE/EggWorld/FieldEggShifted" then
        connect(remote.OnClientEvent, function(record)
            if State.Alive then ingestFieldRecord(record, "shifted") end
        end, State.RemoteConnections)
    elseif remote.Name == "RE/EggWorld/FieldEggBatchShifted" then
        connect(remote.OnClientEvent, function(payload)
            if State.Alive then onBatch(payload) end
        end, State.RemoteConnections)
    elseif remote.Name == "RE/EggWorld/FieldEggGone" then
        connect(remote.OnClientEvent, function(uid)
            if State.Alive and type(uid) == "string" then removeEgg(uid, "gone") end
        end, State.RemoteConnections)
    elseif remote.Name == "RE/EggWorld/FieldEggRedeemVerdict" then
        connect(remote.OnClientEvent, function(info)
            if State.Alive then onRedeemVerdict(info) end
        end, State.RemoteConnections)
    end
end

local function scanRemotes()
    for _, d in ipairs(ReplicatedStorage:GetDescendants()) do
        if d:IsA("RemoteEvent") and TARGETS[d.Name] then hookRemote(d) end
    end
end

connect(ReplicatedStorage.DescendantAdded, function(d)
    if d:IsA("RemoteEvent") and TARGETS[d.Name] then
        task.defer(function()
            if State.Alive and d.Parent then hookRemote(d) end
        end)
    end
end)
scanRemotes()

local function buildSummary()
    local summary = {
        EggCount = 0,
        Categories = {},
        Areas = {},
        Rarities = {},
        SizeRanges = {
            NestScaleMin = nil,
            NestScaleMax = nil,
            AssetScaleMin = nil,
            AssetScaleMax = nil,
            BoundsYMin = nil,
            BoundsYMax = nil,
        },
        EventCount = State.EventCount,
    }

    local function range(keyMin, keyMax, v)
        if type(v) ~= "number" then return end
        if summary.SizeRanges[keyMin] == nil or v < summary.SizeRanges[keyMin] then summary.SizeRanges[keyMin] = v end
        if summary.SizeRanges[keyMax] == nil or v > summary.SizeRanges[keyMax] then summary.SizeRanges[keyMax] = v end
    end

    for _, egg in pairs(State.Eggs) do
        summary.EggCount += 1
        local category = tostring(egg.AssetCategory or "Unknown")
        local area = tostring(egg.AreaId or "Unknown")
        summary.Categories[category] = (summary.Categories[category] or 0) + 1
        summary.Areas[area] = (summary.Areas[area] or 0) + 1
        if egg.Rarity then summary.Rarities[egg.Rarity] = (summary.Rarities[egg.Rarity] or 0) + 1 end
        range("NestScaleMin", "NestScaleMax", egg.NestScale)
        range("AssetScaleMin", "AssetScaleMax", egg.AssetScale)
        if type(egg.BoundsSize) == "table" then range("BoundsYMin", "BoundsYMax", egg.BoundsSize.y) end
    end

    return summary
end

local function buildReport()
    return {
        Version = "NestEgg Scanner V3",
        Meta = {
            PlaceId = game.PlaceId,
            GameId = game.GameId,
            JobId = game.JobId,
            StartedUnix = startedUnix,
            FinishedUnix = os.time(),
            DurationSeconds = elapsed(),
            SelectionRule = "FieldEgg State == Slot only",
        },
        Summary = buildSummary(),
        EggsInNests = State.Eggs,
        RarityCatalog = State.RarityCatalog,
        Events = State.Events,
    }
end

local function exportReport()
    local ok, encoded = pcall(HttpService.JSONEncode, HttpService, buildReport())
    if not ok then return false, "JSONEncode falhou: " .. tostring(encoded) end

    local fileName = "Psico_RoubeUmOvo_NestEggScan_" .. tostring(os.time()) .. ".json"
    if writefile then
        local wok, err = pcall(writefile, fileName, encoded)
        if wok then return true, "Salvo: " .. fileName end
        return false, "writefile falhou: " .. tostring(err)
    end
    if setclipboard then
        local cok, err = pcall(setclipboard, encoded)
        if cok then return true, "JSON copiado" end
        return false, "setclipboard falhou: " .. tostring(err)
    end
    return false, "Executor sem writefile/setclipboard"
end

local function parentGui()
    local ok, h = pcall(function()
        if gethui then return gethui() end
    end)
    return (ok and h) or CoreGui
end

local old = parentGui():FindFirstChild("PsicoNestEggScannerV3")
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "PsicoNestEggScannerV3"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = parentGui()

local frame = Instance.new("Frame")
frame.AnchorPoint = Vector2.new(.5,.5)
frame.Position = UDim2.fromScale(.5,.5)
frame.Size = UDim2.fromOffset(292,176)
frame.BackgroundColor3 = Color3.fromRGB(15,21,33)
frame.BorderSizePixel = 0
frame.Parent = gui
local corner = Instance.new("UICorner",frame)
corner.CornerRadius = UDim.new(0,12)
local stroke = Instance.new("UIStroke",frame)
stroke.Thickness = 1
stroke.Transparency = .32
stroke.Color = Color3.fromRGB(73,126,230)

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Position = UDim2.fromOffset(12,8)
title.Size = UDim2.new(1,-52,0,25)
title.Font = Enum.Font.GothamBold
title.Text = "NEST EGG SCANNER • V3"
title.TextColor3 = Color3.fromRGB(241,245,255)
title.TextSize = 13
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = frame

local close = Instance.new("TextButton")
close.AnchorPoint = Vector2.new(1,0)
close.Position = UDim2.new(1,-8,0,7)
close.Size = UDim2.fromOffset(28,28)
close.BackgroundColor3 = Color3.fromRGB(32,42,60)
close.BorderSizePixel = 0
close.Font = Enum.Font.GothamBold
close.Text = "×"
close.TextColor3 = Color3.fromRGB(240,244,255)
close.TextSize = 15
close.Parent = frame
Instance.new("UICorner",close).CornerRadius = UDim.new(0,8)

statusLabel = Instance.new("TextLabel")
statusLabel.Position = UDim2.fromOffset(12,43)
statusLabel.Size = UDim2.new(1,-24,0,68)
statusLabel.BackgroundColor3 = Color3.fromRGB(21,29,44)
statusLabel.BorderSizePixel = 0
statusLabel.Font = Enum.Font.Code
statusLabel.TextColor3 = Color3.fromRGB(174,198,241)
statusLabel.TextSize = 11
statusLabel.TextWrapped = true
statusLabel.Parent = frame
Instance.new("UICorner",statusLabel).CornerRadius = UDim.new(0,9)

local export = Instance.new("TextButton")
export.Position = UDim2.fromOffset(12,121)
export.Size = UDim2.new(1,-24,0,39)
export.BackgroundColor3 = Color3.fromRGB(37,82,170)
export.BorderSizePixel = 0
export.Font = Enum.Font.GothamMedium
export.Text = "Exportar ovos dos ninhos"
export.TextColor3 = Color3.fromRGB(245,248,255)
export.TextSize = 12
export.Parent = frame
Instance.new("UICorner",export).CornerRadius = UDim.new(0,9)

local dragging = false
local dragStart, startPos, dragInput
frame.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = true
        dragStart = input.Position
        startPos = frame.Position
        dragInput = input
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then dragging = false end
        end)
    end
end)
frame.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseMovement then
        dragInput = input
    end
end)
UIS.InputChanged:Connect(function(input)
    if dragging and input == dragInput then
        local delta = input.Position - dragStart
        frame.Position = UDim2.new(startPos.X.Scale,startPos.X.Offset+delta.X,startPos.Y.Scale,startPos.Y.Offset+delta.Y)
    end
end)

export.MouseButton1Click:Connect(function()
    local ok, message = exportReport()
    refreshStatus((ok and "✓ " or "✗ ") .. message)
end)

local function cleanup()
    if not State.Alive then return end
    State.Alive = false
    for _, c in ipairs(State.RemoteConnections) do safeDisconnect(c) end
    for _, c in ipairs(State.Connections) do safeDisconnect(c) end
    _G.PSICO_ROUBE_SCANNER_CLEANUP = nil
    pcall(function() gui:Destroy() end)
end
_G.PSICO_ROUBE_SCANNER_CLEANUP = cleanup
close.MouseButton1Click:Connect(cleanup)

refreshStatus("Somente State = Slot")

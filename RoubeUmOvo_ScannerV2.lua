--[[
PSICOSENATICO | Roube um Ovo - Scanner V4
Focused passive scanner for eggs that are currently in nests (FieldEgg State == "Slot").
Stable loader path: RoubeUmOvo_ScannerV2.lua

Goals:
  • keep only current nest eggs
  • map each egg Uid to its exact/nearby Workspace visual instance
  • collect nearby TextLabel/TextButton text and attributes that may expose rarity
  • preserve size/mutation/category metadata for future ESP filters
  • never create ESP, change prompts/cooldowns, or fire remotes
]]

if _G.PSICO_ROUBE_MENU_CLEANUP then
    pcall(_G.PSICO_ROUBE_MENU_CLEANUP)
    _G.PSICO_ROUBE_MENU_CLEANUP = nil
end
if _G.PSICO_ROUBE_SCANNER_CLEANUP then
    pcall(_G.PSICO_ROUBE_SCANNER_CLEANUP)
end

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local startedClock = os.clock()
local startedUnix = os.time()

local KNOWN_RARITIES = {
    ["Frog"] = {Rarity="Common", DisplayName="Frog Egg"},
    ["Burrowing Owl"] = {Rarity="Rare", DisplayName="Burrowing Owl Egg"},
    ["Toucan"] = {Rarity="Rare", DisplayName="Toucan Egg"},
    ["Dodo"] = {Rarity="Rare", DisplayName="Dodo Egg"},
    ["Polar Bear"] = {Rarity="Legendary", DisplayName="Polar Bear Egg"},
    ["Orca"] = {Rarity="Mythic", DisplayName="Orca Egg"},
}

local State = {
    Alive = true,
    Connections = {},
    RemoteConnections = {},
    Eggs = {},
    RarityCatalog = {},
    Events = {},
    EventCount = 0,
    LastVisualRefresh = 0,
}

for category, info in pairs(KNOWN_RARITIES) do
    State.RarityCatalog[category] = {
        AssetCategory = category,
        Rarity = info.Rarity,
        DisplayName = info.DisplayName,
        Source = "seeded_from_scan_v3",
        LastSeen = 0,
    }
end

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

local function fullName(inst)
    local ok, v = pcall(function() return inst:GetFullName() end)
    return ok and v or (inst and inst.Name or "?")
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
    if tv == "Instance" then
        return {name=v.Name,class=v.ClassName,path=fullName(v)}
    end
    if tv == "table" then
        local out = {}
        for k,val in pairs(v) do out[tostring(k)] = plain(val) end
        return out
    end
    return tostring(v)
end

local function attrs(inst)
    local out = {}
    local ok, data = pcall(function() return inst:GetAttributes() end)
    if ok then
        for k,v in pairs(data) do out[tostring(k)] = plain(v) end
    end
    return out
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
    if #State.Events > 1600 then table.remove(State.Events, 1) end
end

local function rarityFor(category, record)
    if record and type(record.Rarity) == "string" and record.Rarity ~= "" then
        return record.Rarity
    end
    local known = State.RarityCatalog[tostring(category)]
    return known and known.Rarity or nil
end

local function getPositionFromRecord(record)
    if typeof(record.BoundsCFrame) == "CFrame" then return record.BoundsCFrame.Position end
    if typeof(record.BottomCFrame) == "CFrame" then return record.BottomCFrame.Position end
    return nil
end

local function candidateRoot(inst)
    if not inst then return nil end
    local current = inst
    local last = inst
    for _ = 1, 8 do
        if not current or current == Workspace then break end
        last = current
        if current:IsA("Model") and current.Parent == Workspace then
            return current
        end
        if current.Parent == Workspace then
            return current
        end
        current = current.Parent
    end
    return last
end

local function collectTexts(root)
    local out, seen = {}, {}
    if not root then return out end
    local n = 0
    for _, d in ipairs(root:GetDescendants()) do
        if d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox") then
            local text = tostring(d.Text or "")
            if text ~= "" and not seen[text] then
                seen[text] = true
                n += 1
                table.insert(out, {
                    text = text,
                    name = d.Name,
                    class = d.ClassName,
                    path = fullName(d),
                    attributes = attrs(d),
                })
                if n >= 40 then break end
            end
        end
    end
    return out
end

local function describeVisual(root, referencePosition)
    if not root then return nil end
    local pos
    if root:IsA("BasePart") then
        pos = root.Position
    elseif root:IsA("Model") then
        local ok, cf = pcall(function() return root:GetPivot() end)
        if ok then pos = cf.Position end
    else
        local bp = root:FindFirstChildWhichIsA("BasePart", true)
        if bp then pos = bp.Position end
    end
    local distance = nil
    if pos and referencePosition then
        distance = (pos - referencePosition).Magnitude
    end

    local children = {}
    for _, c in ipairs(root:GetChildren()) do
        if #children >= 35 then break end
        table.insert(children, {
            name = c.Name,
            class = c.ClassName,
            attributes = attrs(c),
        })
    end

    return {
        name = root.Name,
        class = root.ClassName,
        path = fullName(root),
        attributes = attrs(root),
        position = pos and plain(pos) or nil,
        distanceToEgg = distance,
        children = children,
        texts = collectTexts(root),
    }
end

local function findNearbyVisuals(uid, record)
    local result = {
        exact = nil,
        nearby = {},
        method = "none",
    }

    local referencePosition = getPositionFromRecord(record)
    local exact = Workspace:FindFirstChild(uid, true)
    if exact then
        local root = candidateRoot(exact)
        result.exact = describeVisual(root, referencePosition)
        result.method = "uid_exact"
    end

    if referencePosition then
        local size = record.BoundsSize
        local radius = 7
        if typeof(size) == "Vector3" then
            radius = math.max(5, math.min(18, math.max(size.X, size.Y, size.Z) * 1.8 + 3))
        end

        local parts = {}
        local ok, found = pcall(function()
            return Workspace:GetPartBoundsInBox(CFrame.new(referencePosition), Vector3.new(radius*2, radius*2, radius*2))
        end)
        if ok and typeof(found) == "table" then parts = found end

        local seen = {}
        local candidates = {}
        for _, part in ipairs(parts) do
            local root = candidateRoot(part)
            if root and not seen[root] then
                seen[root] = true
                local desc = describeVisual(root, referencePosition)
                if desc then table.insert(candidates, desc) end
            end
        end
        table.sort(candidates, function(a,b)
            return (a.distanceToEgg or math.huge) < (b.distanceToEgg or math.huge)
        end)
        for i = 1, math.min(12, #candidates) do
            table.insert(result.nearby, candidates[i])
        end
        if not result.exact and #result.nearby > 0 then result.method = "spatial" end
    end

    return result
end

local function normalizedSlot(record)
    local category = tostring(record.AssetCategory or "Unknown")
    local known = State.RarityCatalog[category]
    local uid = tostring(record.Uid)
    local previous = State.Eggs[uid]
    return {
        Uid = uid,
        State = "Slot",
        NestId = record.NestId,
        AreaId = record.AreaId,
        AssetCategory = record.AssetCategory,
        DisplayName = (known and known.DisplayName) or record.DisplayName,
        Rarity = rarityFor(category, record),

        NestScale = record.NestScale,
        AssetScale = record.AssetScale,
        BoundsSize = plain(record.BoundsSize),
        BoundsCFrame = plain(record.BoundsCFrame),
        BottomCFrame = plain(record.BottomCFrame),

        BaseMutation = record.BaseMutation,
        Mutations = copyMutations(record.Mutations),
        HasParasite = record.HasParasite == true,
        AssetColorIndex = record.AssetColorIndex,
        AssetColorSeed = record.AssetColorSeed,
        AssetEyeColor = record.AssetEyeColor,
        Version = record.Version,

        FirstSeen = previous and previous.FirstSeen or elapsed(),
        LastSeen = elapsed(),
        Visual = previous and previous.Visual or nil,
    }
end

local statusLabel
local function counts()
    local eggs, mapped, rarities = 0, 0, 0
    for _, egg in pairs(State.Eggs) do
        eggs += 1
        if egg.Visual and (egg.Visual.exact or #egg.Visual.nearby > 0) then mapped += 1 end
    end
    for _ in pairs(State.RarityCatalog) do rarities += 1 end
    return eggs, mapped, rarities
end

local function refreshStatus(extra)
    if not statusLabel then return end
    local eggs, mapped, rarities = counts()
    statusLabel.Text = string.format(
        "Ovos em ninhos: %d | Visuais mapeados: %d\nRaridades conhecidas: %d%s",
        eggs, mapped, rarities, extra and ("\n"..extra) or ""
    )
end

local function refreshVisual(uid, record)
    if not State.Alive or not State.Eggs[uid] then return end
    local visual = findNearbyVisuals(uid, record)
    State.Eggs[uid].Visual = visual
    State.Eggs[uid].LastVisualScan = elapsed()
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

        task.defer(function()
            task.wait(0.05)
            if State.Alive and State.Eggs[uid] then
                refreshVisual(uid, record)
                refreshStatus()
            end
        end)

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
    else
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
    local category, rarity = info.AssetCategory, info.Rarity
    if type(category) ~= "string" or category == "" then return end
    if type(rarity) ~= "string" or rarity == "" then return end

    State.RarityCatalog[category] = {
        AssetCategory = category,
        Rarity = rarity,
        DisplayName = info.DisplayName,
        Color = plain(info.Color),
        Source = "redeem_verdict",
        LastSeen = elapsed(),
    }

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
    refreshStatus("Raridade: "..category.." = "..rarity)
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

connect(Workspace.DescendantAdded, function(inst)
    if not State.Alive then return end
    local uid = inst.Name
    if State.Eggs[uid] then
        task.defer(function()
            task.wait()
            local egg = State.Eggs[uid]
            if egg then
                local pseudo = {
                    Uid = uid,
                    AssetCategory = egg.AssetCategory,
                }
                if egg.BoundsCFrame and type(egg.BoundsCFrame) == "table" then
                    pseudo.BoundsCFrame = CFrame.new(egg.BoundsCFrame.x or 0, egg.BoundsCFrame.y or 0, egg.BoundsCFrame.z or 0)
                end
                refreshVisual(uid, pseudo)
            end
        end)
    end
end)

connect(RunService.Heartbeat, function()
    if not State.Alive then return end
    if elapsed() - State.LastVisualRefresh < 2 then return end
    State.LastVisualRefresh = elapsed()

    local refreshed = 0
    for uid, egg in pairs(State.Eggs) do
        if refreshed >= 12 then break end
        if not egg.Visual or (not egg.Visual.exact and #egg.Visual.nearby == 0) then
            local pseudo = {
                Uid = uid,
                AssetCategory = egg.AssetCategory,
                BoundsSize = egg.BoundsSize and Vector3.new(egg.BoundsSize.x or 1, egg.BoundsSize.y or 1, egg.BoundsSize.z or 1) or nil,
                BoundsCFrame = egg.BoundsCFrame and CFrame.new(egg.BoundsCFrame.x or 0, egg.BoundsCFrame.y or 0, egg.BoundsCFrame.z or 0) or nil,
                BottomCFrame = egg.BottomCFrame and CFrame.new(egg.BottomCFrame.x or 0, egg.BottomCFrame.y or 0, egg.BottomCFrame.z or 0) or nil,
            }
            refreshVisual(uid, pseudo)
            refreshed += 1
        end
    end
    refreshStatus()
end)

local function buildSummary()
    local summary = {
        EggCount = 0,
        VisualExact = 0,
        VisualSpatialOnly = 0,
        VisualUnresolved = 0,
        Categories = {},
        Areas = {},
        Rarities = {},
        Mutations = {},
        SizeRanges = {
            NestScaleMin=nil,NestScaleMax=nil,
            AssetScaleMin=nil,AssetScaleMax=nil,
            BoundsYMin=nil,BoundsYMax=nil,
        },
        EventCount = State.EventCount,
    }

    local function range(a,b,v)
        if type(v) ~= "number" then return end
        if summary.SizeRanges[a] == nil or v < summary.SizeRanges[a] then summary.SizeRanges[a] = v end
        if summary.SizeRanges[b] == nil or v > summary.SizeRanges[b] then summary.SizeRanges[b] = v end
    end

    for _, egg in pairs(State.Eggs) do
        summary.EggCount += 1
        local cat = tostring(egg.AssetCategory or "Unknown")
        local area = tostring(egg.AreaId or "Unknown")
        summary.Categories[cat] = (summary.Categories[cat] or 0) + 1
        summary.Areas[area] = (summary.Areas[area] or 0) + 1
        if egg.Rarity then summary.Rarities[egg.Rarity] = (summary.Rarities[egg.Rarity] or 0) + 1 end
        for _,m in ipairs(egg.Mutations or {}) do summary.Mutations[m] = (summary.Mutations[m] or 0) + 1 end

        if egg.Visual and egg.Visual.exact then
            summary.VisualExact += 1
        elseif egg.Visual and #egg.Visual.nearby > 0 then
            summary.VisualSpatialOnly += 1
        else
            summary.VisualUnresolved += 1
        end

        range("NestScaleMin","NestScaleMax",egg.NestScale)
        range("AssetScaleMin","AssetScaleMax",egg.AssetScale)
        if type(egg.BoundsSize) == "table" then range("BoundsYMin","BoundsYMax",egg.BoundsSize.y) end
    end
    return summary
end

local function buildReport()
    return {
        Version = "NestEgg Visual Scanner V4",
        Meta = {
            PlaceId = game.PlaceId,
            GameId = game.GameId,
            JobId = game.JobId,
            StartedUnix = startedUnix,
            FinishedUnix = os.time(),
            DurationSeconds = elapsed(),
            SelectionRule = "FieldEgg State == Slot only",
            VisualRule = "exact Uid match, then spatial candidates around BoundsCFrame",
        },
        Summary = buildSummary(),
        EggsInNests = State.Eggs,
        RarityCatalog = State.RarityCatalog,
        Events = State.Events,
    }
end

local function exportReport()
    local ok, encoded = pcall(HttpService.JSONEncode, HttpService, buildReport())
    if not ok then return false, "JSONEncode falhou: "..tostring(encoded) end
    local fileName = "Psico_RoubeUmOvo_NestVisualScan_"..tostring(os.time())..".json"
    if writefile then
        local wok, err = pcall(writefile, fileName, encoded)
        if wok then return true, "Salvo: "..fileName end
        return false, "writefile falhou: "..tostring(err)
    end
    if setclipboard then
        local cok, err = pcall(setclipboard, encoded)
        if cok then return true, "JSON copiado" end
        return false, "setclipboard falhou: "..tostring(err)
    end
    return false, "Executor sem writefile/setclipboard"
end

local function parentGui()
    local ok, h = pcall(function() if gethui then return gethui() end end)
    return (ok and h) or CoreGui
end

local old = parentGui():FindFirstChild("PsicoNestEggScannerV4")
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "PsicoNestEggScannerV4"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = parentGui()

local frame = Instance.new("Frame")
frame.AnchorPoint = Vector2.new(.5,.5)
frame.Position = UDim2.fromScale(.5,.5)
frame.Size = UDim2.fromOffset(300,184)
frame.BackgroundColor3 = Color3.fromRGB(15,21,33)
frame.BorderSizePixel = 0
frame.Parent = gui
Instance.new("UICorner",frame).CornerRadius = UDim.new(0,12)
local stroke = Instance.new("UIStroke",frame)
stroke.Thickness = 1
stroke.Transparency = .32
stroke.Color = Color3.fromRGB(73,126,230)

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Position = UDim2.fromOffset(12,8)
title.Size = UDim2.new(1,-52,0,25)
title.Font = Enum.Font.GothamBold
title.Text = "NEST VISUAL SCANNER • V4"
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
statusLabel.Size = UDim2.new(1,-24,0,76)
statusLabel.BackgroundColor3 = Color3.fromRGB(21,29,44)
statusLabel.BorderSizePixel = 0
statusLabel.Font = Enum.Font.Code
statusLabel.TextColor3 = Color3.fromRGB(174,198,241)
statusLabel.TextSize = 11
statusLabel.TextWrapped = true
statusLabel.Parent = frame
Instance.new("UICorner",statusLabel).CornerRadius = UDim.new(0,9)

local export = Instance.new("TextButton")
export.Position = UDim2.fromOffset(12,130)
export.Size = UDim2.new(1,-24,0,39)
export.BackgroundColor3 = Color3.fromRGB(37,82,170)
export.BorderSizePixel = 0
export.Font = Enum.Font.GothamMedium
export.Text = "Exportar mapa visual dos ovos"
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
    refreshStatus((ok and "✓ " or "✗ ")..message)
end)

local function cleanup()
    if not State.Alive then return end
    State.Alive = false
    for _,c in ipairs(State.RemoteConnections) do safeDisconnect(c) end
    for _,c in ipairs(State.Connections) do safeDisconnect(c) end
    _G.PSICO_ROUBE_SCANNER_CLEANUP = nil
    pcall(function() gui:Destroy() end)
end
_G.PSICO_ROUBE_SCANNER_CLEANUP = cleanup
close.MouseButton1Click:Connect(cleanup)

refreshStatus("Somente ovos State = Slot")

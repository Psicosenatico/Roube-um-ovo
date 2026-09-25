-- PSICOSENATICO Inventory V5
-- V8.7.4 baseline: compact inventory list + direct egg equip by EggInventory UID.
-- Equip path verified from Egg Equip Scanner: EggInventory UID -> RF/EggWorld/AskWearTool -> AssetEgg Tool.

if _G.PSICO_INVENTORY_PANEL_CLEANUP then
    pcall(_G.PSICO_INVENTORY_PANEL_CLEANUP)
end

local Players = game:GetService('Players')
local RS = game:GetService('ReplicatedStorage')
local CoreGui = game:GetService('CoreGui')
local Workspace = game:GetService('Workspace')
local LP = Players.LocalPlayer

local conns = {}
local function conn(signal, fn)
    local c = signal:Connect(fn)
    conns[#conns + 1] = c
    return c
end

local function norm(v)
    return tostring(v or ''):lower():gsub('[%s_%-%.:/%[%]%(%)\'•]', '')
end

local function path(p)
    local x = RS
    for q in p:gmatch('[^%.]+') do
        x = x and x:FindFirstChild(q)
    end
    return x
end

local function req(p)
    local x = path(p)
    if not (x and x:IsA('ModuleScript')) then return nil end
    local ok, v = pcall(require, x)
    return ok and v or nil
end

local Save = req('Shared.Save') or req('Data.Save')
local EggState = req('Client.EggState')
local ER = req('Shared.Util.EggRecords')
local AssetEarnings = req('Shared.Util.AssetEarnings')
local Assets = req('Data.Assets')
local Networking = RS:FindFirstChild('Packages') and RS.Packages:FindFirstChild('Networking')
local AskWearTool = Networking and Networking:FindFirstChild('RF/EggWorld/AskWearTool')

local function call(t, n, ...)
    if type(t) ~= 'table' or type(t[n]) ~= 'function' then return nil end
    local ok, v = pcall(t[n], ...)
    if ok then return v end
    ok, v = pcall(t[n], t, ...)
    return ok and v or nil
end

local function round(o, r)
    local c = Instance.new('UICorner')
    c.CornerRadius = UDim.new(0, r or 8)
    c.Parent = o
end

local function label(p, t, pos, size, sz)
    local x = Instance.new('TextLabel')
    x.BackgroundTransparency = 1
    x.Position = pos
    x.Size = size
    x.Font = Enum.Font.Gotham
    x.Text = t
    x.TextSize = sz or 9
    x.TextColor3 = Color3.fromRGB(225, 232, 245)
    x.TextXAlignment = Enum.TextXAlignment.Left
    x.Parent = p
    return x
end

local function button(p, t, pos, size)
    local x = Instance.new('TextButton')
    x.BackgroundColor3 = Color3.fromRGB(35, 44, 61)
    x.BorderSizePixel = 0
    x.Position = pos
    x.Size = size
    x.Font = Enum.Font.GothamMedium
    x.Text = t
    x.TextSize = 10
    x.TextColor3 = Color3.fromRGB(242, 246, 255)
    x.Parent = p
    round(x, 8)
    return x
end

local root = (function()
    local ok, h = pcall(function()
        return gethui and gethui()
    end)
    return (ok and h) or CoreGui
end)()

local gui, main
for _, g in ipairs(root:GetChildren()) do
    if g:IsA('ScreenGui') and g.Name:find('PsicoRoubeUmOvo', 1, true) == 1 then
        gui = g
        main = g:FindFirstChild('Main')
        if main then break end
    end
end
if not main then error('main panel not found') end

local function text(s)
    for _, d in ipairs(main:GetDescendants()) do
        if (d:IsA('TextButton') or d:IsA('TextLabel')) and d.Text == s then
            return d
        end
    end
end

local fun = text('FUNÇÕES')
local filters = text('FILTROS ESP')
local normal = text('ESP • Ovos  ON') or text('ESP • Ovos ON') or text('ESP • Ovos  OFF') or text('ESP • Ovos OFF') or text('ESP • Ovos')
local rarity = text('Raridade mínima')
if not (fun and filters and normal and rarity) then
    error('base anchors not found')
end

local sidebar = filters.Parent
local mainPage = normal.Parent
local filterPage = rarity.Parent
local host = mainPage.Parent

local gap = filters.Position.Y.Offset - fun.Position.Y.Offset - fun.Size.Y.Offset
if gap < 0 or gap > 80 then gap = 12 end

local tab = button(
    sidebar,
    'OVOS INVENTÁRIO',
    UDim2.new(filters.Position.X.Scale, filters.Position.X.Offset, filters.Position.Y.Scale, filters.Position.Y.Offset + filters.Size.Y.Offset + gap),
    filters.Size
)

local page = Instance.new('Frame')
page.Name = 'InventoryEggPageV5'
page.BackgroundTransparency = 1
page.Position = mainPage.Position
page.Size = mainPage.Size
page.AnchorPoint = mainPage.AnchorPoint
page.Visible = false
page.Parent = host

-- Keep the compact layout that is already working.
local refresh = button(page, 'Atualizar', UDim2.new(0, 10, 0, 8), UDim2.new(1/3, -8, 0, 30))
local sort = button(page, 'Ordenar: $/s', UDim2.new(1/3, 4, 0, 8), UDim2.new(1/3, -8, 0, 30))
local baseEspButton = button(page, 'ESP Base: OFF', UDim2.new(2/3, 2, 0, 8), UDim2.new(1/3, -12, 0, 30))
local status = label(page, '', UDim2.new(0, 10, 0, 40), UDim2.new(1, -20, 0, 14), 7)
status.TextXAlignment = Enum.TextXAlignment.Center

local list = Instance.new('ScrollingFrame')
list.BackgroundTransparency = 1
list.BorderSizePixel = 0
list.Position = UDim2.new(0, 10, 0, 56)
list.Size = UDim2.new(1, -20, 1, -60)
list.ScrollBarThickness = 4
list.ScrollingDirection = Enum.ScrollingDirection.Y
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.CanvasSize = UDim2.new()
list.Parent = page

local lay = Instance.new('UIListLayout')
lay.Padding = UDim.new(0, 5)
lay.Parent = list

local pad = Instance.new('UIPadding')
pad.PaddingBottom = UDim.new(0, 6)
pad.Parent = list

local modes = {'$/s', 'Raridade', 'Valor do ovo'}
local mode = 1
local rarityNum = {
    Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5,
    Mythic = 6, Cosmic = 7, Secret = 8, Eternal = 9, Divine = 10
}
local colors = {
    Legendary = Color3.fromRGB(255, 174, 58),
    Mythic = Color3.fromRGB(255, 71, 121),
    Cosmic = Color3.fromRGB(150, 67, 255),
    Secret = Color3.fromRGB(245, 245, 245),
    Eternal = Color3.fromRGB(245, 71, 255),
    Divine = Color3.fromRGB(52, 255, 238)
}

local function compact(n)
    n = tonumber(n)
    if not n then return '?' end
    if math.abs(n) >= 1e12 then return ('%.2fT'):format(n / 1e12) end
    if math.abs(n) >= 1e9 then return ('%.2fB'):format(n / 1e9) end
    if math.abs(n) >= 1e6 then return ('%.2fM'):format(n / 1e6) end
    if math.abs(n) >= 1e3 then return ('%.1fK'):format(n / 1e3) end
    return tostring(math.floor(n + .5))
end

local function rv(r, k)
    if type(r) ~= 'table' then return nil end
    if r[k] ~= nil then return r[k] end
    local i = type(r.ItemData) == 'table' and r.ItemData
    return i and i[k]
end

local function isPlaced(rec)
    return type(rec) == 'table' and rec.Placement ~= nil
end

local ownedSyncTried = false
local function readOwnedEggs()
    -- Primary source: the game's own live EggState cache.
    -- It tracks OwnerShifted/OwnerDropped and stores Placement on each runtime record.
    if type(EggState) == 'table' and type(EggState.ReadOwnerEggs) == 'function' then
        local ok, inv = pcall(EggState.ReadOwnerEggs, LP.UserId)
        if not ok then
            ok, inv = pcall(EggState.ReadOwnerEggs, EggState, LP.UserId)
        end
        if ok and type(inv) == 'table' and next(inv) ~= nil then
            return inv, 'EggState'
        end

        if not ownedSyncTried and type(EggState.SyncOwnedEggs) == 'function' then
            ownedSyncTried = true
            pcall(EggState.SyncOwnedEggs)
            task.wait(.05)
            ok, inv = pcall(EggState.ReadOwnerEggs, LP.UserId)
            if not ok then
                ok, inv = pcall(EggState.ReadOwnerEggs, EggState, LP.UserId)
            end
            if ok and type(inv) == 'table' then
                return inv, 'EggState'
            end
        elseif ok and type(inv) == 'table' then
            return inv, 'EggState'
        end
    end

    -- Compatibility fallback for older builds.
    local sd = Save and call(Save, 'Get')
    local inv = type(sd) == 'table' and sd.EggInventory
    if type(inv) == 'table' then
        return inv, 'Save'
    end
    return {}, 'none'
end

local function cat(r)
    return rv(r, 'AssetCategory') or rv(r, 'Category') or rv(r, 'Name')
end

local function catalog(c)
    if type(Assets) ~= 'table' then return nil end
    local n = norm(c)
    local function scan(t)
        for k, v in pairs(t or {}) do
            if type(v) == 'table' and type(v.Rarity) == 'table' and (norm(k) == n or norm(v.DisplayName) == n) then
                return v
            end
        end
    end
    if type(Assets.ByRarity) == 'table' then
        for _, g in pairs(Assets.ByRarity) do
            local v = scan(g)
            if v then return v end
        end
    end
    return type(Assets.Configs) == 'table' and scan(Assets.Configs)
end

local function tableImage(t, depth, seen)
    if type(t) ~= 'table' or depth > 4 then return nil end
    seen = seen or {}
    if seen[t] then return nil end
    seen[t] = true
    for k, v in pairs(t) do
        local nk = norm(k)
        if nk:find('image', 1, true) or nk:find('icon', 1, true) or nk:find('texture', 1, true) then
            if type(v) == 'string' and v ~= '' then
                return v:match('^%d+$') and ('rbxassetid://' .. v) or v
            elseif type(v) == 'number' and v > 1000 then
                return 'rbxassetid://' .. math.floor(v)
            end
        end
    end
    for _, v in pairs(t) do
        if type(v) == 'table' then
            local x = tableImage(v, depth + 1, seen)
            if x then return x end
        end
    end
end

local function oval(o, k)
    local ok, v = pcall(function()
        return o:GetAttribute(k)
    end)
    if ok and v ~= nil then return v end
    local c = o:FindFirstChild(k)
    return c and c:IsA('ValueBase') and c.Value or nil
end

local function tools()
    local a = {}
    for _, r in ipairs({LP:FindFirstChildOfClass('Backpack'), LP.Character}) do
        if r then
            for _, t in ipairs(r:GetChildren()) do
                if t:IsA('Tool') then a[#a + 1] = t end
            end
        end
    end
    return a
end

-- Exact identity rule from the scanner: an equipped egg is a Tool with
-- ItemType == AssetEgg and UID equal to the key in Save.Get().EggInventory.
local function eggToolForUID(uid)
    uid = tostring(uid or '')
    if uid == '' then return nil end
    for _, t in ipairs(tools()) do
        if tostring(oval(t, 'ItemType') or '') == 'AssetEgg' and tostring(oval(t, 'UID') or '') == uid then
            return t
        end
    end
    return nil
end

local function toolImage(t)
    if not t then return nil end
    if t.TextureId and t.TextureId ~= '' then return t.TextureId end
    for _, d in ipairs(t:GetDescendants()) do
        if (d:IsA('ImageLabel') or d:IsA('ImageButton')) and d.Image ~= '' then
            return d.Image
        end
    end
end

local function inCharacterUID(uid)
    local ch = LP.Character
    if not ch then return nil end
    for _, t in ipairs(ch:GetChildren()) do
        if t:IsA('Tool') and tostring(oval(t, 'ItemType') or '') == 'AssetEgg' and tostring(oval(t, 'UID') or '') == uid then
            return t
        end
    end
end

local function equipRecord(key, rec)
    local liveInv = readOwnedEggs()
    local liveRec = type(liveInv) == 'table' and (liveInv[key] or liveInv[tostring(key)]) or nil
    if liveRec == nil then
        return false, 'Este ovo não está mais disponível no inventário'
    end
    if isPlaced(liveRec) then
        return false, 'Este ovo já está colocado na base'
    end
    rec = liveRec

    local uid = tostring(key or rv(rec, 'UID') or '')
    if uid == '' then
        return false, 'UID do ovo não encontrado'
    end

    -- If this exact AssetEgg Tool is already materialized, equip it locally.
    local tool = eggToolForUID(uid)
    local hum = LP.Character and LP.Character:FindFirstChildOfClass('Humanoid')
    if tool then
        if tool.Parent ~= LP.Character and hum then
            local ok = pcall(function()
                hum:EquipTool(tool)
            end)
            if not ok then
                return false, 'Tool encontrada, mas EquipTool falhou'
            end
        end
        if inCharacterUID(uid) then
            return true, 'Equipado • UID confirmado'
        end
    end

    local ok, result, reason
    if type(EggState) == 'table' and type(EggState.WearEggTool) == 'function' then
        ok, result, reason = pcall(EggState.WearEggTool, uid)
        if not ok then
            ok, result, reason = pcall(EggState.WearEggTool, EggState, uid)
        end
        if ok and result ~= true then
            return false, tostring(reason or 'WearEggTool recusou o ovo')
        end
    else
        if not (AskWearTool and AskWearTool:IsA('RemoteFunction')) then
            return false, 'WearEggTool/AskWearTool não encontrado'
        end
        ok, result = pcall(function()
            return AskWearTool:InvokeServer(uid)
        end)
        if not ok then
            return false, 'AskWearTool falhou: ' .. tostring(result)
        end
    end

    -- The server normally places the AssetEgg Tool directly in Character.
    -- Poll briefly because replication can arrive a few frames later.
    local deadline = os.clock() + 1.5
    repeat
        local equipped = inCharacterUID(uid)
        if equipped then
            return true, 'Equipado • AskWearTool • UID confirmado'
        end

        tool = eggToolForUID(uid)
        if tool and hum and tool.Parent ~= LP.Character then
            pcall(function()
                hum:EquipTool(tool)
            end)
            if inCharacterUID(uid) then
                return true, 'Equipado • Tool recebida • UID confirmado'
            end
        end
        task.wait(.05)
    until os.clock() >= deadline

    return false, 'Pedido enviado, mas a Tool AssetEgg não apareceu'
end

local function preciseEarnings(rec)
    if type(rec) ~= 'table' then return nil end

    -- Best path: the game itself converts SavedEgg -> AssetItemData using
    -- the same category, scale, mutations, personality and other fields
    -- that will exist on the pet after hatching.
    local item = call(ER, 'ToAssetItemData', rec)
    if type(item) == 'table' and type(AssetEarnings) == 'table' then
        local v = call(AssetEarnings, 'MutationOnlyRatePerSecond', item)
        v = tonumber(v)
        if v and v >= 0 then return v end
    end

    -- Compatibility fallback: same shape used by the normal field-egg ESP.
    if type(AssetEarnings) == 'table' then
        local probe = {
            Category = rec.AssetCategory or rec.Category,
            Scale = rec.AssetScale or rec.Scale,
            Mutations = rec.Mutations or {},
            BaseMutation = rec.BaseMutation,
            Personality = rec.AssetPersonality or rec.Personality,
            CreatorTemporary = rec.CreatorTemporary,
        }
        local v = call(AssetEarnings, 'MutationOnlyRatePerSecond', probe)
        v = tonumber(v)
        if v and v >= 0 then return v end
    end
    return nil
end

local renderedIndex = {}
local renderedIndexAt = 0

local function refreshRenderedIndex(force)
    local now = os.clock()
    if not force and now - renderedIndexAt < .5 then return renderedIndex end
    renderedIndexAt = now
    renderedIndex = {}

    -- Correct source for eggs already placed on plots.
    -- The game renders them under Workspace.PlacedEggRenders using
    -- <OwnerUserId>_<UID> as the root model name.
    local placed = Workspace:FindFirstChild('PlacedEggRenders')
    if placed then
        local prefix = tostring(LP.UserId) .. '_'
        for _, inst in ipairs(placed:GetChildren()) do
            if inst:IsA('Model') then
                local name = tostring(inst.Name or '')
                if name:sub(1, #prefix) == prefix then
                    local uid = name:sub(#prefix + 1)
                    if uid ~= '' then
                        renderedIndex[uid] = inst
                    end
                else
                    -- Compatibility fallback if a future build adds attributes.
                    local uid = inst:GetAttribute('UID')
                    local owner = tonumber(inst:GetAttribute('OwnerUserId'))
                    if uid ~= nil and (owner == nil or owner == LP.UserId) then
                        renderedIndex[tostring(uid)] = inst
                    end
                end
            end
        end
    end

    -- Old/general renderer fallback. This is NOT the primary path for
    -- placed eggs, but keeping it costs little and helps across builds.
    local generic = Workspace:FindFirstChild('ClientRenderedAssets')
    if generic then
        for _, inst in ipairs(generic:GetChildren()) do
            if inst:IsA('Model') then
                local uid = inst:GetAttribute('UID')
                local owner = tonumber(inst:GetAttribute('OwnerUserId'))
                if uid ~= nil and owner == LP.UserId and not renderedIndex[tostring(uid)] then
                    renderedIndex[tostring(uid)] = inst
                end
            end
        end
    end

    return renderedIndex
end

local function recordUid(key, rec)
    return tostring(
        (type(rec) == 'table' and (rec.Uid or rec.UID or rec.Id or rec.ID))
        or key
        or ''
    )
end

local function visualForPlacedUid(uid)
    uid = tostring(uid or '')
    if uid == '' then return nil end

    -- Fast exact lookup using the game's real naming convention.
    local placed = Workspace:FindFirstChild('PlacedEggRenders')
    if placed then
        local direct = placed:FindFirstChild(tostring(LP.UserId) .. '_' .. uid)
        if direct and direct:IsA('Model') then return direct end
    end

    return refreshRenderedIndex(false)[uid]
end

local baseEspEnabled = false
local baseEsp = {}

local function placedAdornee(model)
    if not model then return nil end
    return model.PrimaryPart or model:FindFirstChildWhichIsA('BasePart', true)
end

local function destroyBaseEsp(uid)
    local e = baseEsp[uid]
    if not e then return end
    for _, obj in pairs(e) do
        if typeof(obj) == 'Instance' then
            pcall(function() obj:Destroy() end)
        end
    end
    baseEsp[uid] = nil
end

local function clearBaseEsp()
    for uid in pairs(baseEsp) do destroyBaseEsp(uid) end
end

local function rarityForRecord(rec)
    local c = tostring(cat(rec) or '?')
    local cfg = catalog(c)
    local rar = cfg and (cfg.Rarity.DisplayName or cfg.Rarity._id) or tostring(rec.Rarity or '?')
    local pet = cfg and (cfg.DisplayName or c) or c
    return rar, pet
end

local function ensureBaseEsp(uid, rec, model)
    local adornee = placedAdornee(model)
    if not adornee then return end
    local e = baseEsp[uid]
    if e and e.Model ~= model then
        destroyBaseEsp(uid)
        e = nil
    end

    if not e then
        local h = Instance.new('Highlight')
        h.Name = 'PSICO_BASE_EGG_HIGHLIGHT'
        h.Adornee = model
        h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        h.FillTransparency = .88
        h.OutlineTransparency = .12
        h.Parent = model

        local bb = Instance.new('BillboardGui')
        bb.Name = 'PSICO_BASE_EGG_BILLBOARD'
        bb.Adornee = adornee
        bb.AlwaysOnTop = true
        bb.MaxDistance = 10000
        bb.Size = UDim2.fromOffset(190, 42)
        bb.StudsOffset = Vector3.new(0, 2.2, 0)
        bb.Parent = gui

        local a = label(bb, '', UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, 14), 10)
        a.TextXAlignment = Enum.TextXAlignment.Center
        a.Font = Enum.Font.GothamBold
        a.TextStrokeTransparency = .15

        local b = label(bb, '', UDim2.fromOffset(0, 14), UDim2.new(1, 0, 0, 14), 9)
        b.TextXAlignment = Enum.TextXAlignment.Center
        b.TextStrokeTransparency = .15

        local c = label(bb, '', UDim2.fromOffset(0, 28), UDim2.new(1, 0, 0, 14), 8)
        c.TextXAlignment = Enum.TextXAlignment.Center
        c.TextStrokeTransparency = .15

        e = {Highlight=h, Billboard=bb, L1=a, L2=b, L3=c, Model=model}
        baseEsp[uid] = e
    end

    local rar, pet = rarityForRecord(rec)
    local col = colors[rar] or Color3.fromRGB(225,232,245)
    e.Highlight.FillColor = col
    e.Highlight.OutlineColor = col
    e.L1.TextColor3 = col
    e.L1.Text = pet .. ' • ' .. rar

    local eps = preciseEarnings(rec)
    e.L2.Text = eps and ('$' .. compact(eps) .. '/s após chocar') or '$?/s após chocar'

    local wl = call(ER, 'WeightLabel', rec)
    local remain = call(ER, 'GrowthSecondsRemaining', rec)
    remain = tonumber(remain)
    if remain and remain >= 0 then
        e.L3.Text = tostring(wl or '') .. (wl and ' • ' or '') .. ('%.0fs restantes'):format(remain)
    else
        e.L3.Text = tostring(wl or '')
    end
end

local function refreshBaseEsp()
    if not baseEspEnabled then
        clearBaseEsp()
        baseEspButton.Text = 'ESP Base: OFF'
        return
    end

    -- Rebuild once per refresh so every placed record is matched against
    -- the same renderer snapshot.
    refreshRenderedIndex(true)

    local inv = readOwnedEggs()
    local keep = {}
    local placedCount, matchedCount = 0, 0

    for key, rec in pairs(type(inv) == 'table' and inv or {}) do
        if type(rec) == 'table' and isPlaced(rec) then
            placedCount = placedCount + 1
            local uid = recordUid(key, rec)
            local model = visualForPlacedUid(uid)
            if model then
                matchedCount = matchedCount + 1
                keep[uid] = true
                ensureBaseEsp(uid, rec, model)
            end
        end
    end

    for uid in pairs(baseEsp) do
        if not keep[uid] then destroyBaseEsp(uid) end
    end

    baseEspButton.Text = ('ESP Base: ON • %d/%d'):format(matchedCount, placedCount)
end

local rows = {}
local inventoryTotal = 0
local cachedCapacity = nil

local function nativeCapacity()
    local pg = LP:FindFirstChildOfClass('PlayerGui')
    if not pg then return cachedCapacity end

    for _, d in ipairs(pg:GetDescendants()) do
        if d:IsA('TextLabel') or d:IsA('TextButton') or d:IsA('TextBox') then
            local txt = tostring(d.Text or '')
            local used, cap = txt:match('Eggs:%s*(%d+)%s*/%s*(%d+)')
            if used and cap then
                cachedCapacity = tonumber(cap) or cachedCapacity
                return cachedCapacity
            end
        end
    end
    return cachedCapacity
end

local function clear()
    for _, x in ipairs(list:GetChildren()) do
        if x:IsA('GuiObject') then x:Destroy() end
    end
end

local function read()
    rows = {}
    inventoryTotal = 0
    local inv = readOwnedEggs()
    if type(inv) ~= 'table' then return end

    for key, r in pairs(inv) do
        if type(r) == 'table' then
            inventoryTotal = inventoryTotal + 1
        end
        if type(r) == 'table' and not isPlaced(r) then
            local c = tostring(cat(r) or '?')
            local cfg = catalog(c)
            local rar = cfg and (cfg.Rarity.DisplayName or cfg.Rarity._id) or tostring(r.Rarity or '?')
            local earn = preciseEarnings(r)
            local sell = tonumber(call(ER, 'SellPrice', r))
            local w = tonumber(call(ER, 'WeightKg', r))
            local wl = call(ER, 'WeightLabel', r)
            local tool = eggToolForUID(key)
            local img = toolImage(tool) or tableImage(r, 0, {}) or tableImage(cfg, 0, {})
            rows[#rows + 1] = {
                key = key,
                r = r,
                c = c,
                rar = rar,
                earn = earn,
                sell = sell,
                w = w,
                wl = wl,
                tool = tool,
                img = img
            }
        end
    end
end

local function render()
    clear()
    read()

    table.sort(rows, function(a, b)
        if mode == 1 then
            return (a.earn or 0) > (b.earn or 0)
        elseif mode == 2 then
            return (rarityNum[a.rar] or 0) > (rarityNum[b.rar] or 0)
        else
            return (a.sell or 0) > (b.sell or 0)
        end
    end)

    local cap = nativeCapacity()
    if cap then
        status.Text = ('Inventário:%d/%d • Disponíveis:%d • %s'):format(inventoryTotal, cap, #rows, modes[mode])
    else
        status.Text = ('Inventário:%d • Disponíveis:%d • %s'):format(inventoryTotal, #rows, modes[mode])
    end

    for i, e in ipairs(rows) do
        local card = Instance.new('TextButton')
        card.Text = ''
        card.BackgroundColor3 = Color3.fromRGB(25, 34, 50)
        card.BorderSizePixel = 0
        card.Size = UDim2.new(1, -4, 0, 60)
        card.LayoutOrder = i
        card.Parent = list
        round(card, 9)

        local st = Instance.new('UIStroke')
        st.Thickness = 1.5
        st.Color = colors[e.rar] or Color3.fromRGB(74, 112, 190)
        st.Parent = card

        local im = Instance.new('ImageLabel')
        im.BackgroundColor3 = Color3.fromRGB(17, 24, 37)
        im.BorderSizePixel = 0
        im.Position = UDim2.new(0, 5, 0, 5)
        im.Size = UDim2.new(0, 50, 0, 50)
        im.ScaleType = Enum.ScaleType.Fit
        im.Image = e.img or ''
        im.Parent = card
        round(im, 7)

        local title = 'Ovo ' .. tostring(e.wl or (e.w and (compact(e.w) .. 'Kg') or '?'))
        local t = label(card, title, UDim2.new(0, 62, 0, 5), UDim2.new(1, -68, 0, 18), 10)
        t.Font = Enum.Font.GothamBold
        t.TextColor3 = colors[e.rar] or Color3.fromRGB(235, 240, 250)

        label(card, e.rar .. ' • Conteúdo: ' .. e.c, UDim2.new(0, 62, 0, 24), UDim2.new(1, -68, 0, 15), 8)
        label(card, '$' .. compact(e.earn) .. '/s • Valor $' .. compact(e.sell), UDim2.new(0, 62, 0, 41), UDim2.new(1, -68, 0, 14), 7)

        conn(card.Activated, function()
            status.Text = 'Equipando ' .. title .. '...'
            local ok, msg = equipRecord(e.key, e.r)
            status.Text = (ok and '✓ ' or '! ') .. msg
        end)
    end
end

local function show()
    for _, x in ipairs(host:GetChildren()) do
        if x:IsA('GuiObject') then
            x.Visible = (x == page)
        end
    end
    page.Visible = true
    render()
end

conn(tab.Activated, show)
conn(refresh.Activated, function()
    render()
    refreshBaseEsp()
end)

conn(baseEspButton.Activated, function()
    baseEspEnabled = not baseEspEnabled
    baseEspButton.BackgroundColor3 = baseEspEnabled and Color3.fromRGB(42, 91, 190) or Color3.fromRGB(35, 44, 61)
    refreshBaseEsp()
end)

local placementSignature = ''
local function inventorySignature()
    local inv = readOwnedEggs()
    if type(inv) ~= 'table' then return '' end
    local keys = {}
    for key, rec in pairs(inv) do
        if type(rec) == 'table' and not isPlaced(rec) then
            keys[#keys + 1] = tostring(key)
        end
    end
    table.sort(keys)
    return table.concat(keys, '|')
end

task.spawn(function()
    while page.Parent do
        task.wait(.75)
        if page.Visible then
            local sig = inventorySignature()
            if placementSignature ~= '' and sig ~= placementSignature then
                render()
            end
            placementSignature = sig
        end
        if baseEspEnabled then
            refreshBaseEsp()
        end
    end
end)

conn(Workspace.DescendantAdded, function(inst)
    local placed = Workspace:FindFirstChild('PlacedEggRenders')
    local generic = Workspace:FindFirstChild('ClientRenderedAssets')
    if (placed and inst:IsDescendantOf(placed)) or (generic and inst:IsDescendantOf(generic)) then
        renderedIndexAt = 0
        if baseEspEnabled then task.defer(refreshBaseEsp) end
    end
end)

conn(Workspace.DescendantRemoving, function(inst)
    local p = inst.Parent
    if p and (p.Name == 'PlacedEggRenders' or p.Name == 'ClientRenderedAssets') then
        renderedIndexAt = 0
        if baseEspEnabled then task.defer(refreshBaseEsp) end
    end
end)

conn(sort.Activated, function()
    mode = mode % 3 + 1
    sort.Text = 'Ordenar: ' .. modes[mode]
    render()
end)

conn(fun.Activated, function()
    page.Visible = false
    mainPage.Visible = true
    filterPage.Visible = false
end)

conn(filters.Activated, function()
    page.Visible = false
    mainPage.Visible = false
    filterPage.Visible = true
end)

_G.PSICO_INVENTORY_PANEL_CLEANUP = function()
    baseEspEnabled = false
    clearBaseEsp()
    for _, c in ipairs(conns) do
        pcall(function()
            c:Disconnect()
        end)
    end
    pcall(function() page:Destroy() end)
    pcall(function() tab:Destroy() end)
end
--[[
PSICOSENATICO | Roube um Ovo - Earnings Scanner V9
Stable loader path: RoubeUmOvo_ScannerV2.lua

Objetivo desta leitura:
  * Ler ReplicatedStorage.Shared.Util.AssetEarnings.
  * Ler ReplicatedStorage.Shared.Util.AssetItems.ProfileIncomePerSecond.
  * Ler todos os EarningsScalar do catálogo de mutações.
  * Comparar pets reais do Backpack/Character com EarningRate, Scale, mutações
    e o perSecond final já calculado pelo jogo.
  * Testar, de forma passiva e protegida por pcall, assinaturas prováveis de
    MutationOnlyRatePerSecond para descobrir como o próprio cliente calcula
    o rendimento por mutação.
  * Exportar um JSON pequeno e focado para análise.

Este scanner NÃO altera prompts, ESP, cooldowns, remotes de combate ou pets.
]]

if _G.PSICO_ROUBE_SCANNER_CLEANUP then
    pcall(_G.PSICO_ROUBE_SCANNER_CLEANUP)
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CoreGui = game:GetService("CoreGui")
local HttpService = game:GetService("HttpService")
local UIS = game:GetService("UserInputService")

local LP = Players.LocalPlayer

local State = {
    Alive = true,
    Connections = {},
    Gui = nil,
    Report = nil,
}

local function safeString(v)
    local ok, s = pcall(tostring, v)
    return ok and s or "?"
end

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function connect(signal, fn)
    local c = signal:Connect(fn)
    table.insert(State.Connections, c)
    return c
end

local function disconnectAll()
    for _, c in ipairs(State.Connections) do
        pcall(function() c:Disconnect() end)
    end
    State.Connections = {}
end

local function uiParent()
    local ok, h = pcall(function()
        if gethui then return gethui() end
    end)
    return (ok and h) or CoreGui
end

local function resolvePath(root, path)
    local cur = root
    for token in string.gmatch(path, "[^%.]+") do
        if not cur then return nil end
        cur = cur:FindFirstChild(token)
    end
    return cur
end

local function safeRequire(module)
    if not (module and module:IsA("ModuleScript")) then
        return nil, "module ausente"
    end
    local ok, value = pcall(require, module)
    if not ok then return nil, safeString(value) end
    return value, nil
end

local function shallowSerialize(v, depth, seen)
    depth = depth or 0
    seen = seen or {}
    local tv = typeof(v)
    if tv == "nil" or tv == "boolean" or tv == "string" then return v end
    if tv == "number" then return finite(v) and v or safeString(v) end
    if tv == "Instance" then
        return {
            __type = "Instance",
            class = v.ClassName,
            name = v.Name,
            path = v:GetFullName(),
        }
    end
    if tv == "Vector3" then return {x=v.X,y=v.Y,z=v.Z,__type="Vector3"} end
    if tv == "Vector2" then return {x=v.X,y=v.Y,__type="Vector2"} end
    if tv == "Color3" then return {r=v.R,g=v.G,b=v.B,__type="Color3"} end
    if tv == "CFrame" then
        local p = v.Position
        return {x=p.X,y=p.Y,z=p.Z,__type="CFrame"}
    end
    if tv == "function" then return safeString(v) end
    if tv ~= "table" then return safeString(v) end
    if depth >= 3 or seen[v] then return "<table>" end
    seen[v] = true
    local out, n = {}, 0
    for k, child in pairs(v) do
        n = n + 1
        if n > 80 then
            out.__truncated = true
            break
        end
        local key = type(k) == "string" and k or safeString(k)
        out[key] = shallowSerialize(child, depth + 1, seen)
    end
    seen[v] = nil
    return out
end

local function functionInfo(fn)
    local out = { tostring = safeString(fn) }

    if debug and type(debug.info) == "function" then
        local okS, source = pcall(debug.info, fn, "s")
        if okS then out.source = source end
        local okN, name = pcall(debug.info, fn, "n")
        if okN then out.name = name end
        local okA, arity, variadic = pcall(debug.info, fn, "a")
        if okA then
            out.arity = arity
            out.variadic = variadic
        end
    elseif debug and type(debug.getinfo) == "function" then
        local ok, info = pcall(debug.getinfo, fn)
        if ok and type(info) == "table" then
            out.info = shallowSerialize(info)
        end
    end

    if debug and type(debug.getconstants) == "function" then
        local ok, constants = pcall(debug.getconstants, fn)
        if ok then out.constants = shallowSerialize(constants) end
    end

    if debug and type(debug.getupvalues) == "function" then
        local ok, upvalues = pcall(debug.getupvalues, fn)
        if ok then out.upvalues = shallowSerialize(upvalues) end
    end

    if debug and type(debug.getprotos) == "function" then
        local ok, protos = pcall(debug.getprotos, fn)
        if ok and type(protos) == "table" then
            local p = {}
            for i, proto in ipairs(protos) do
                if i > 12 then break end
                p[i] = safeString(proto)
            end
            out.protos = p
        end
    end

    return out
end

local function moduleSummary(value)
    local out = { type = typeof(value), fields = {} }
    if typeof(value) ~= "table" then return out end
    local keys = {}
    for k in pairs(value) do keys[#keys+1] = safeString(k) end
    table.sort(keys)
    for _, key in ipairs(keys) do
        local v = value[key]
        if type(v) == "function" then
            out.fields[key] = { kind = "function", info = functionInfo(v) }
        else
            out.fields[key] = { kind = typeof(v), value = shallowSerialize(v) }
        end
    end
    return out
end

local function parseMutationList(v)
    local out = {}
    if typeof(v) == "table" then
        for _, m in pairs(v) do
            if m ~= nil and safeString(m) ~= "" then out[#out+1] = safeString(m) end
        end
    elseif type(v) == "string" then
        for token in string.gmatch(v, "[^,]+") do
            token = token:gsub("^%s+", ""):gsub("%s+$", "")
            if token ~= "" then out[#out+1] = token end
        end
    end
    return out
end

local function catalogIndex(assets)
    local index = {}
    local function add(key, cfg)
        if typeof(cfg) ~= "table" then return end
        local display = cfg.DisplayName or safeString(key)
        local entry = {
            key = safeString(key),
            displayName = display,
            earningRate = cfg.EarningRate,
            modelWeight = cfg.ModelWeight,
            baseModelScale = cfg.BaseModelScale,
            rarity = typeof(cfg.Rarity)=="table" and (cfg.Rarity.DisplayName or cfg.Rarity._id) or nil,
        }
        index[safeString(key)] = entry
        if type(display) == "string" then index[display] = entry end
    end

    if typeof(assets) == "table" and typeof(assets.Directory) == "table" then
        for key, cfg in pairs(assets.Directory) do add(key, cfg) end
    elseif typeof(assets) == "table" and typeof(assets.ByRarity) == "table" then
        for _, group in pairs(assets.ByRarity) do
            if typeof(group) == "table" then
                for key, cfg in pairs(group) do add(key, cfg) end
            end
        end
    end
    return index
end

local function mutationCatalogSummary(catalog)
    local out = {}
    if typeof(catalog) ~= "table" then return out end
    for name, cfg in pairs(catalog) do
        if typeof(cfg) == "table" then
            out[safeString(name)] = {
                EarningsScalar = cfg.EarningsScalar,
                RollWeight = cfg.RollWeight,
                EggDisplayName = cfg.EggDisplayName,
                EggModelName = cfg.EggModelName,
            }
        end
    end
    return out
end

local function combinedMutationScalars(mutations, mutationCatalog)
    local additive = 1
    local product = 1
    local known = 0
    for _, name in ipairs(mutations or {}) do
        local cfg = mutationCatalog and mutationCatalog[name]
        local scalar = typeof(cfg)=="table" and tonumber(cfg.EarningsScalar) or nil
        if scalar then
            known = known + 1
            additive = additive + (scalar - 1)
            product = product * scalar
        end
    end
    return additive, product, known
end

local function readPetTool(tool, assetsIndex, mutationCatalog)
    if not (tool and tool:IsA("Tool")) then return nil end
    local itemType = tool:GetAttribute("ItemType")
    if itemType ~= "Asset" then return nil end

    local category = tool:GetAttribute("Category")
    local displayName = tool:GetAttribute("DisplayName") or tool.Name
    local scale = tonumber(tool:GetAttribute("Scale"))
    local mutationRaw = tool:GetAttribute("Mutations")
    local mutations = parseMutationList(mutationRaw)
    local cfg = tool:FindFirstChild("Configuration")
    local attrs = cfg and cfg:GetAttributes() or {}
    local catalog = assetsIndex[category] or assetsIndex[displayName]
    local additive, product, known = combinedMutationScalars(mutations, mutationCatalog)

    return {
        toolName = tool.Name,
        path = tool:GetFullName(),
        uid = tool:GetAttribute("UID"),
        category = category,
        displayName = displayName,
        scale = scale,
        weight = tool:GetAttribute("Weight"),
        baseMutation = tool:GetAttribute("BaseMutation"),
        mutations = mutations,
        mutationRaw = mutationRaw,
        catalog = catalog,
        observed = {
            perSecond = attrs.perSecond,
            perSecondDisplay = attrs.perSecondDisplay,
            configScale = attrs.scale,
            configMutations = attrs.mutations,
            configBaseMutation = attrs.baseMutation,
            rarity = attrs.rarity,
        },
        derivedMutationScalar = {
            additiveBonusModel = additive,
            productModel = product,
            knownMutations = known,
        },
    }
end

local function collectPets(assetsIndex, mutationCatalog)
    local out = {}
    local seen = {}
    local containers = {}
    local backpack = LP:FindFirstChildOfClass("Backpack")
    if backpack then containers[#containers+1] = backpack end
    if LP.Character then containers[#containers+1] = LP.Character end

    for _, container in ipairs(containers) do
        for _, child in ipairs(container:GetChildren()) do
            if child:IsA("Tool") and not seen[child] then
                seen[child] = true
                local pet = readPetTool(child, assetsIndex, mutationCatalog)
                if pet then out[#out+1] = pet end
            end
        end
    end

    table.sort(out, function(a,b)
        return (tonumber(a.observed and a.observed.perSecond) or 0) > (tonumber(b.observed and b.observed.perSecond) or 0)
    end)
    return out
end

local function resultShape(ok, value)
    if not ok then return { ok=false, error=safeString(value) } end
    return { ok=true, type=typeof(value), value=shallowSerialize(value) }
end

local function callProbe(fn, moduleSelf, label, args, withSelf)
    local ok, value
    if withSelf then
        ok, value = pcall(fn, moduleSelf, table.unpack(args))
    else
        ok, value = pcall(fn, table.unpack(args))
    end
    local r = resultShape(ok, value)
    r.label = label .. (withSelf and " [self]" or "")
    return r
end

local function probeMutationFunction(assetEarnings, assetsRaw, assetsIndex, pets)
    local out = {
        functionFound = false,
        functionInfo = nil,
        pets = {},
    }
    if typeof(assetEarnings) ~= "table" then return out end
    local fn = assetEarnings.MutationOnlyRatePerSecond
    if type(fn) ~= "function" then return out end
    out.functionFound = true
    out.functionInfo = functionInfo(fn)

    local maxPets = math.min(#pets, 12)
    for i = 1, maxPets do
        local pet = pets[i]
        local category = pet.category
        local display = pet.displayName
        local scale = pet.scale or 1
        local muts = pet.mutations or {}
        local mutString = table.concat(muts, ", ")
        local entry = assetsIndex[category] or assetsIndex[display]
        local baseRate = entry and entry.earningRate or nil
        local assetCfg = nil
        if typeof(assetsRaw)=="table" and typeof(assetsRaw.Directory)=="table" and category then
            assetCfg = assetsRaw.Directory[category]
        end

        local record = {
            Category = category,
            AssetCategory = category,
            DisplayName = display,
            Scale = scale,
            AssetScale = scale,
            Mutations = muts,
            BaseMutation = pet.baseMutation,
        }

        local probes = {}
        local candidates = {
            {"record", {record}},
            {"record+mutations", {record, muts}},
            {"record+scale+mutations", {record, scale, muts}},
            {"category+mutations", {category, muts}},
            {"category+mutString", {category, mutString}},
            {"category+scale+mutations", {category, scale, muts}},
            {"category+mutations+scale", {category, muts, scale}},
            {"display+mutations", {display, muts}},
            {"assetCfg+mutations", {assetCfg, muts}},
            {"assetCfg+scale+mutations", {assetCfg, scale, muts}},
            {"baseRate+mutations", {baseRate, muts}},
            {"baseRate+scale+mutations", {baseRate, scale, muts}},
        }

        for _, c in ipairs(candidates) do
            local label, args = c[1], c[2]
            local valid = true
            for _, a in ipairs(args) do
                if a == nil then valid = false break end
            end
            if valid then
                probes[#probes+1] = callProbe(fn, assetEarnings, label, args, false)
                probes[#probes+1] = callProbe(fn, assetEarnings, label, args, true)
            end
        end

        out.pets[#out.pets+1] = {
            category = category,
            displayName = display,
            scale = scale,
            mutations = muts,
            baseRate = baseRate,
            observedPerSecond = pet.observed and pet.observed.perSecond,
            probes = probes,
        }
    end

    return out
end

local function countProbeSuccesses(probeReport)
    local success, numeric = 0, 0
    for _, pet in ipairs(probeReport and probeReport.pets or {}) do
        for _, p in ipairs(pet.probes or {}) do
            if p.ok then
                success = success + 1
                if p.type == "number" then numeric = numeric + 1 end
            end
        end
    end
    return success, numeric
end

local function buildReport()
    local report = {
        Meta = {
            Version = "EarningsScannerV9",
            StartedUnix = os.time(),
            PlaceId = game.PlaceId,
            GameId = game.GameId,
            JobId = game.JobId,
            UserId = LP and LP.UserId or nil,
            Notes = "Targeted read of AssetEarnings, mutation scalars and observed pet income.",
        },
        Modules = {},
        Mutations = {},
        InventoryPets = {},
        MutationProbes = {},
        Summary = {},
    }

    local assetsModule = resolvePath(ReplicatedStorage, "Data.Assets")
    local mutationModule = resolvePath(ReplicatedStorage, "Shared.Modules.Mutations.Catalog")
    local earningsModule = resolvePath(ReplicatedStorage, "Shared.Util.AssetEarnings")
    local assetItemsModule = resolvePath(ReplicatedStorage, "Shared.Util.AssetItems")
    local itemDisplayModule = resolvePath(ReplicatedStorage, "Shared.Modules.ItemDisplay")

    local assets, assetsErr = safeRequire(assetsModule)
    local mutations, mutErr = safeRequire(mutationModule)
    local earnings, earningsErr = safeRequire(earningsModule)
    local assetItems, assetItemsErr = safeRequire(assetItemsModule)
    local itemDisplay, itemDisplayErr = safeRequire(itemDisplayModule)

    report.Modules.Assets = { path=assetsModule and assetsModule:GetFullName() or nil, error=assetsErr }
    report.Modules.MutationCatalog = { path=mutationModule and mutationModule:GetFullName() or nil, error=mutErr, summary=moduleSummary(mutations) }
    report.Modules.AssetEarnings = { path=earningsModule and earningsModule:GetFullName() or nil, error=earningsErr, summary=moduleSummary(earnings) }
    report.Modules.AssetItems = { path=assetItemsModule and assetItemsModule:GetFullName() or nil, error=assetItemsErr, summary=moduleSummary(assetItems) }
    report.Modules.ItemDisplay = { path=itemDisplayModule and itemDisplayModule:GetFullName() or nil, error=itemDisplayErr, summary=moduleSummary(itemDisplay) }

    local assetsIndex = catalogIndex(assets)
    report.Mutations = mutationCatalogSummary(mutations)
    report.InventoryPets = collectPets(assetsIndex, mutations)
    report.MutationProbes = probeMutationFunction(earnings, assets, assetsIndex, report.InventoryPets)

    local success, numeric = countProbeSuccesses(report.MutationProbes)
    local mutationCount = 0
    for _ in pairs(report.Mutations) do mutationCount = mutationCount + 1 end

    report.Summary = {
        MutationCount = mutationCount,
        InventoryPetCount = #report.InventoryPets,
        MutationFunctionFound = report.MutationProbes.functionFound == true,
        ProbeSuccessCount = success,
        NumericProbeCount = numeric,
        HasAssetItemsProfileIncomePerSecond = typeof(assetItems)=="table" and type(assetItems.ProfileIncomePerSecond)=="function" or false,
        HasMutationOnlyRatePerSecond = typeof(earnings)=="table" and type(earnings.MutationOnlyRatePerSecond)=="function" or false,
    }

    report.Meta.FinishedUnix = os.time()
    State.Report = report
    return report
end

local function exportReport()
    local report = State.Report or buildReport()
    local ok, json = pcall(function() return HttpService:JSONEncode(report) end)
    if not ok then return false, "JSONEncode falhou: "..safeString(json) end

    local filename = "Psico_RoubeUmOvo_EarningsScan_"..tostring(os.time())..".json"
    if type(writefile) == "function" then
        local wok, werr = pcall(writefile, filename, json)
        if wok then return true, filename end
        return false, "writefile falhou: "..safeString(werr)
    end

    if type(setclipboard) == "function" then
        local cok, cerr = pcall(setclipboard, json)
        if cok then return true, "JSON copiado para a área de transferência" end
        return false, "clipboard falhou: "..safeString(cerr)
    end

    return false, "executor sem writefile/setclipboard"
end

local function round(obj, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r or 9)
    c.Parent = obj
end

local function mkButton(parent, text, pos, size)
    local b = Instance.new("TextButton")
    b.BackgroundColor3 = Color3.fromRGB(31, 43, 66)
    b.BorderSizePixel = 0
    b.Position = pos
    b.Size = size
    b.Font = Enum.Font.GothamMedium
    b.Text = text
    b.TextColor3 = Color3.fromRGB(240, 245, 255)
    b.TextSize = 11
    b.Parent = parent
    round(b, 9)
    return b
end

local function mkLabel(parent, text, pos, size, textSize)
    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1
    l.Position = pos
    l.Size = size
    l.Font = Enum.Font.Gotham
    l.Text = text
    l.TextColor3 = Color3.fromRGB(176, 190, 216)
    l.TextSize = textSize or 10
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.TextWrapped = true
    l.Parent = parent
    return l
end

local old = uiParent():FindFirstChild("PsicoEarningsScannerV9")
if old then pcall(function() old:Destroy() end) end

local gui = Instance.new("ScreenGui")
gui.Name = "PsicoEarningsScannerV9"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = uiParent()
State.Gui = gui

local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(844,390)
local width = math.floor(math.clamp(vp.X * 0.36, 286, 330))
local height = math.floor(math.min(206, vp.Y * 0.70))

local frame = Instance.new("Frame")
frame.AnchorPoint = Vector2.new(.5,.5)
frame.Position = UDim2.fromScale(.5,.5)
frame.Size = UDim2.fromOffset(width, height)
frame.BackgroundColor3 = Color3.fromRGB(14, 20, 32)
frame.BorderSizePixel = 0
frame.Parent = gui
round(frame, 13)

local stroke = Instance.new("UIStroke")
stroke.Thickness = 1.1
stroke.Transparency = .28
stroke.Color = Color3.fromRGB(61,118,230)
stroke.Parent = frame

local title = mkLabel(frame, "EARNINGS SCAN V9", UDim2.fromOffset(12,8), UDim2.new(1,-52,0,20), 14)
title.Font = Enum.Font.GothamBold
title.TextColor3 = Color3.fromRGB(242,246,255)
local sub = mkLabel(frame, "AssetEarnings • mutações • $/s", UDim2.fromOffset(12,27), UDim2.new(1,-52,0,16), 9)
sub.TextColor3 = Color3.fromRGB(102,148,232)

local close = mkButton(frame, "×", UDim2.new(1,-38,0,8), UDim2.fromOffset(28,28))
local status = mkLabel(frame, "Lendo módulos...", UDim2.fromOffset(12,53), UDim2.new(1,-24,0,54), 10)
status.TextColor3 = Color3.fromRGB(193,205,229)

local scanButton = mkButton(frame, "ANALISAR NOVAMENTE", UDim2.new(0,12,1,-83), UDim2.new(1,-24,0,31))
local exportButton = mkButton(frame, "EXPORTAR JSON", UDim2.new(0,12,1,-45), UDim2.new(1,-24,0,31))

local function updateStatus(extra)
    local r = State.Report
    if not r then
        status.Text = extra or "Lendo módulos..."
        return
    end
    local s = r.Summary or {}
    status.Text = string.format(
        "Pets: %d • Mutações: %d\nMutationOnly: %s • Probes numéricos: %d%s",
        tonumber(s.InventoryPetCount) or 0,
        tonumber(s.MutationCount) or 0,
        s.HasMutationOnlyRatePerSecond and "OK" or "NÃO",
        tonumber(s.NumericProbeCount) or 0,
        extra and ("\n"..extra) or ""
    )
end

local function rescan()
    status.Text = "Lendo AssetEarnings e pets..."
    task.defer(function()
        local ok, err = pcall(buildReport)
        if ok then
            updateStatus("leitura concluída")
        else
            status.Text = "Erro na leitura: "..safeString(err)
        end
    end)
end

connect(scanButton.MouseButton1Click, rescan)
connect(exportButton.MouseButton1Click, function()
    exportButton.Text = "EXPORTANDO..."
    task.defer(function()
        local ok, msg = exportReport()
        exportButton.Text = ok and "EXPORTADO ✓" or "FALHOU"
        updateStatus(msg)
        task.wait(1.8)
        if State.Alive and exportButton.Parent then exportButton.Text = "EXPORTAR JSON" end
    end)
end)

local dragging = false
local dragInput, dragStart, startPos
connect(frame.InputBegan, function(input)
    if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = true
        dragStart = input.Position
        startPos = frame.Position
    end
end)
connect(frame.InputChanged, function(input)
    if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseMovement then
        dragInput = input
    end
end)
connect(UIS.InputChanged, function(input)
    if dragging and input == dragInput then
        local d = input.Position - dragStart
        frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset+d.X, startPos.Y.Scale, startPos.Y.Offset+d.Y)
    end
end)
connect(UIS.InputEnded, function(input)
    if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = false
    end
end)

local function cleanup()
    if not State.Alive then return end
    State.Alive = false
    disconnectAll()
    _G.PSICO_ROUBE_SCANNER_CLEANUP = nil
    pcall(function() if State.Gui then State.Gui:Destroy() end end)
end

_G.PSICO_ROUBE_SCANNER_CLEANUP = cleanup
connect(close.MouseButton1Click, cleanup)

task.defer(function()
    task.wait(.35)
    if State.Alive then rescan() end
end)

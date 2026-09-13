--[[
PSICOSENATICO | Roube um Ovo - Precision Egg Scanner V7
Stable loader path: RoubeUmOvo_ScannerV2.lua

Purpose:
  * Recover current nest eggs immediately, without waiting for a reset.
  * Read the real pet catalog from ReplicatedStorage.Data.Assets.
  * Use ReplicatedStorage.Shared.Util.EggRecords for the game's own
    WeightKg / SellPrice / WeightLabel / DisplayName calculations.
  * Export a compact per-UID dataset ready for the future ESP filters.
  * No ESP, combat, prompt or gameplay modification.
]]

if _G.PSICO_ROUBE_MENU_CLEANUP then pcall(_G.PSICO_ROUBE_MENU_CLEANUP) end
if _G.PSICO_ROUBE_SCANNER_CLEANUP then pcall(_G.PSICO_ROUBE_SCANNER_CLEANUP) end

local Workspace = game:GetService("Workspace")
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
    RawRecords = {},
    Eggs = {},
    Catalog = {},
    CatalogIndex = {},
    Rarities = {},
    FunctionDiagnostics = {},
    Events = {},
    Stats = {
        SnapshotRequests = 0,
        SnapshotSuccesses = 0,
        SnapshotRecords = 0,
        VisualNestModels = 0,
        CatalogPets = 0,
        CatalogRarities = 0,
        EnrichedEggs = 0,
        WeightResolved = 0,
        SellPriceResolved = 0,
    },
    EventCount = 0,
    LastDiag = "READY",
}

local AssetsData
local EggRecords

local function elapsed()
    return os.clock() - startedClock
end

local function safeString(v)
    local ok, s = pcall(tostring, v)
    return ok and s or "<unprintable>"
end

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function fullName(inst)
    local ok, s = pcall(function() return inst:GetFullName() end)
    return ok and s or (inst and inst.Name or "?")
end

local function normalize(v)
    return string.lower(safeString(v or "")):gsub("[%s_%-%.:/%[%]%(%)']", "")
end

local function connect(signal, fn, bucket)
    local c = signal:Connect(fn)
    table.insert(bucket or State.Connections, c)
    return c
end

local function disconnect(c)
    pcall(function() c:Disconnect() end)
end

local function countMap(t)
    local n = 0
    for _ in pairs(t) do n += 1 end
    return n
end

local function addEvent(kind, data)
    State.EventCount += 1
    State.Events[#State.Events + 1] = {i=State.EventCount,t=elapsed(),kind=kind,data=data}
    if #State.Events > 500 then table.remove(State.Events, 1) end
end

local function plain(v, depth, seen)
    depth = depth or 0
    seen = seen or {}
    if depth > 7 then return "<max-depth>" end
    local t = typeof(v)
    if t == "nil" then return nil end
    if t == "boolean" or t == "string" then return v end
    if t == "number" then
        if finite(v) then return v end
        if v ~= v then return "<NaN>" end
        return v == math.huge and "<Infinity>" or "<-Infinity>"
    end
    if t == "Vector3" then return {x=v.X,y=v.Y,z=v.Z} end
    if t == "Vector2" then return {x=v.X,y=v.Y} end
    if t == "Color3" then return {r=v.R,g=v.G,b=v.B} end
    if t == "CFrame" then local p=v.Position return {x=p.X,y=p.Y,z=p.Z} end
    if t == "EnumItem" then return safeString(v) end
    if t == "Instance" then return {name=v.Name,class=v.ClassName,path=fullName(v)} end
    if t ~= "table" then return "<"..t.."> "..safeString(v) end
    if seen[v] then return "<cycle>" end
    seen[v] = true
    local out,n = {},0
    local ok = pcall(function()
        for k,val in pairs(v) do
            n += 1
            if n > 300 then out["<truncated>"] = true break end
            out[safeString(k)] = plain(val, depth+1, seen)
        end
    end)
    seen[v] = nil
    if not ok then out["<iteration-error>"] = true end
    return out
end

local function findDescendantByExactName(className, exactName)
    for _,d in ipairs(ReplicatedStorage:GetDescendants()) do
        if d.ClassName == className and d.Name == exactName then return d end
    end
end

local function resolveModules()
    local dataFolder = ReplicatedStorage:FindFirstChild("Data")
    local assetsModule = dataFolder and dataFolder:FindFirstChild("Assets")
    local shared = ReplicatedStorage:FindFirstChild("Shared")
    local util = shared and shared:FindFirstChild("Util")
    local eggRecordsModule = util and util:FindFirstChild("EggRecords")

    if not (assetsModule and assetsModule:IsA("ModuleScript")) then
        State.LastDiag = "EA01"
        return false, "EA01 | Data.Assets não encontrado"
    end
    if not (eggRecordsModule and eggRecordsModule:IsA("ModuleScript")) then
        State.LastDiag = "ER01"
        return false, "ER01 | EggRecords não encontrado"
    end

    local aok, assets = pcall(require, assetsModule)
    if not aok or typeof(assets) ~= "table" then
        State.LastDiag = "EA02"
        return false, "EA02 | require Assets | "..safeString(assets):sub(1,40)
    end
    local eok, records = pcall(require, eggRecordsModule)
    if not eok or typeof(records) ~= "table" then
        State.LastDiag = "ER02"
        return false, "ER02 | require EggRecords | "..safeString(records):sub(1,40)
    end

    AssetsData = assets
    EggRecords = records
    State.Stats.AssetsModule = fullName(assetsModule)
    State.Stats.EggRecordsModule = fullName(eggRecordsModule)
    return true
end

local function rarityInfo(r)
    if typeof(r) ~= "table" then return nil end
    return {
        Id=r._id or r.Id or r.DisplayName,
        DisplayName=r.DisplayName or r._id,
        RarityNumber=r.RarityNumber,
        DefaultRarityValue=r.DefaultRarityValue,
        Announce=r.Announce,
        Color=plain(r.Color),
    }
end

local function petCatalogEntry(key, cfg)
    if typeof(cfg) ~= "table" or typeof(cfg.Egg) ~= "table" or typeof(cfg.Rarity) ~= "table" then return nil end
    local egg = cfg.Egg
    local rarity = rarityInfo(cfg.Rarity)
    return {
        Key=key,
        DisplayName=cfg.DisplayName or key,
        Rarity=rarity and (rarity.DisplayName or rarity.Id) or nil,
        RarityId=rarity and rarity.Id or nil,
        RarityNumber=rarity and rarity.RarityNumber or nil,
        RarityOdds=rarity and rarity.DefaultRarityValue or nil,
        EggDisplayName=egg.DisplayName,
        EggBaseWeightKg=egg.WeightKg,
        GrowthTime=egg.GrowthTime,
        EggModelName=egg.ModelName,
        EggIcon=egg.Icon,
        HideRarity=egg.HideRarity,
        IgnoreSizeGrowthMultiplier=egg.IgnoreSizeGrowthMultiplier,
        EarningRate=cfg.EarningRate,
        ModelWeight=cfg.ModelWeight,
        BaseModelScale=cfg.BaseModelScale,
        VisualOdds=cfg.VisualOdds,
        DropWeight=cfg.DropWeight,
    }
end

local function indexCatalogEntry(entry)
    for _,k in ipairs({entry.Key,entry.DisplayName,entry.EggDisplayName}) do
        if type(k) == "string" and k ~= "" then
            State.CatalogIndex[normalize(k)] = entry
            local withoutEgg = k:gsub("%s+[Ee][Gg][Gg]$", "")
            State.CatalogIndex[normalize(withoutEgg)] = State.CatalogIndex[normalize(withoutEgg)] or entry
        end
    end
end

local function buildCatalog()
    State.Catalog = {}
    State.CatalogIndex = {}
    State.Rarities = {}
    if typeof(AssetsData) ~= "table" then return false, "EA03 | AssetsData inválido" end

    local found = 0
    local byRarity = AssetsData.ByRarity
    if typeof(byRarity) == "table" then
        for rarityKey,group in pairs(byRarity) do
            if typeof(group) == "table" then
                for petKey,cfg in pairs(group) do
                    local entry = petCatalogEntry(safeString(petKey), cfg)
                    if entry then
                        found += 1
                        State.Catalog[entry.Key] = entry
                        indexCatalogEntry(entry)
                        local rid = entry.RarityId or entry.Rarity or safeString(rarityKey)
                        if rid and rid ~= "" then
                            local existing = State.Rarities[rid] or {}
                            existing.Id = rid
                            existing.DisplayName = entry.Rarity or rid
                            existing.RarityNumber = entry.RarityNumber
                            existing.DefaultRarityValue = entry.RarityOdds
                            State.Rarities[rid] = existing
                        end
                    end
                end
            end
        end
    end

    if found == 0 and typeof(AssetsData.Configs) == "table" then
        for petKey,cfg in pairs(AssetsData.Configs) do
            local entry = petCatalogEntry(safeString(petKey), cfg)
            if entry then
                found += 1
                State.Catalog[entry.Key] = entry
                indexCatalogEntry(entry)
                local rid = entry.RarityId or entry.Rarity
                if rid then
                    State.Rarities[rid] = {Id=rid,DisplayName=entry.Rarity or rid,RarityNumber=entry.RarityNumber,DefaultRarityValue=entry.RarityOdds}
                end
            end
        end
    end

    State.Stats.CatalogPets = found
    State.Stats.CatalogRarities = countMap(State.Rarities)
    if found == 0 then return false, "EA04 | catálogo sem pets" end
    return true
end

local function findCatalog(assetCategory)
    return type(assetCategory) == "string" and State.CatalogIndex[normalize(assetCategory)] or nil
end

local function diagFn(name, ok, value)
    local d = State.FunctionDiagnostics[name] or {Calls=0,Success=0,Failed=0,Errors={}}
    d.Calls += 1
    if ok then
        d.Success += 1
        d.LastType = typeof(value)
    else
        d.Failed += 1
        if #d.Errors < 4 then d.Errors[#d.Errors+1] = safeString(value):sub(1,180) end
    end
    State.FunctionDiagnostics[name] = d
end

local function callRecordFunction(name, record)
    if typeof(EggRecords) ~= "table" then return nil,false end
    local fn = EggRecords[name]
    if type(fn) ~= "function" then diagFn(name,false,"function missing") return nil,false end

    local ok,value = pcall(fn, record)
    if ok then diagFn(name,true,value) return value,true end
    local firstErr = value

    local ok2,value2 = pcall(fn, EggRecords, record)
    if ok2 then diagFn(name,true,value2) return value2,true end

    diagFn(name,false,safeString(firstErr).." | self:"..safeString(value2))
    return nil,false
end

local function callScaleFunction(record, config)
    if typeof(EggRecords) ~= "table" or type(EggRecords.WeightKgForScale) ~= "function" then return nil,false,"missing" end
    local fn = EggRecords.WeightKgForScale
    local scale = record.AssetScale
    local baseWeight = config and config.EggBaseWeightKg
    local tries = {
        {"record_scale",record,scale},
        {"config_scale",config,scale},
        {"base_scale",baseWeight,scale},
        {"category_scale",record.AssetCategory,scale},
        {"scale_base",scale,baseWeight},
    }
    for _,args in ipairs(tries) do
        if args[2] ~= nil and args[3] ~= nil then
            local ok,value = pcall(fn,args[2],args[3])
            if ok and (finite(value) or type(value) == "string") then
                diagFn("WeightKgForScale:"..args[1],true,value)
                return value,true,args[1]
            else
                diagFn("WeightKgForScale:"..args[1],false,value)
            end
        end
    end
    return nil,false,"no_signature"
end

local function visualPath(uid)
    local folder = Workspace:FindFirstChild("AreaEggSlotsClient")
    if folder then local m=folder:FindFirstChild(uid) if m then return fullName(m) end end
    local direct = Workspace:FindFirstChild(uid)
    return direct and fullName(direct) or nil
end

local function copyMutations(v)
    local out = {}
    if typeof(v) == "table" then
        for _,m in pairs(v) do out[#out+1] = safeString(m) end
        table.sort(out)
    end
    return out
end

local function enrichRecord(record, source)
    if typeof(record) ~= "table" or type(record.Uid) ~= "string" or record.State ~= "Slot" then return false end
    local uid = record.Uid
    local cfg = findCatalog(record.AssetCategory)

    local weight,weightOk = callRecordFunction("WeightKg",record)
    local sell,sellOk = callRecordFunction("SellPrice",record)
    local weightLabel,labelOk = callRecordFunction("WeightLabel",record)
    local displayName,displayOk = callRecordFunction("DisplayName",record)
    local displayWithWeight,displayWeightOk = callRecordFunction("DisplayNameWithWeight",record)

    local fallbackWeight,fallbackOk,fallbackSignature
    if not weightOk then
        fallbackWeight,fallbackOk,fallbackSignature = callScaleFunction(record,cfg)
        if fallbackOk then weight=fallbackWeight weightOk=true end
    end

    State.RawRecords[uid] = record
    State.Eggs[uid] = {
        Uid=uid,State="Slot",Source=source,AreaId=record.AreaId,NestId=record.NestId,
        AssetCategory=record.AssetCategory,AssetScale=record.AssetScale,NestScale=record.NestScale,
        BoundsSize=plain(record.BoundsSize),BoundsCFrame=plain(record.BoundsCFrame),
        BaseMutation=record.BaseMutation,Mutations=copyMutations(record.Mutations),HasParasite=record.HasParasite==true,
        VisualPath=visualPath(uid),
        PetName=cfg and cfg.DisplayName or record.AssetCategory,
        EggName=cfg and cfg.EggDisplayName or (displayOk and plain(displayName) or nil),
        Rarity=cfg and cfg.Rarity or record.Rarity,
        RarityId=cfg and cfg.RarityId or nil,
        RarityNumber=cfg and cfg.RarityNumber or nil,
        RarityOdds=cfg and cfg.RarityOdds or nil,
        BaseWeightKg=cfg and cfg.EggBaseWeightKg or nil,
        GrowthTime=cfg and cfg.GrowthTime or nil,
        EarningRate=cfg and cfg.EarningRate or nil,
        ModelWeight=cfg and cfg.ModelWeight or nil,
        VisualOdds=cfg and cfg.VisualOdds or nil,
        WeightKg=weightOk and plain(weight) or nil,
        WeightLabel=labelOk and plain(weightLabel) or nil,
        SellPrice=sellOk and plain(sell) or nil,
        GameDisplayName=displayOk and plain(displayName) or nil,
        DisplayNameWithWeight=displayWeightOk and plain(displayWithWeight) or nil,
        WeightFallbackSignature=fallbackSignature,
    }
    return true
end

local function removeEgg(uid,reason)
    if type(uid) ~= "string" then return end
    if State.Eggs[uid] or State.RawRecords[uid] then
        State.Eggs[uid] = nil
        State.RawRecords[uid] = nil
        addEvent("slot_removed",{Uid=uid,Reason=reason})
    end
end

local function ingestTree(value,source,seen,depth)
    if typeof(value) ~= "table" then return 0 end
    seen = seen or {}
    depth = depth or 0
    if depth > 8 or seen[value] then return 0 end
    seen[value] = true
    local found = 0
    if type(value.Uid) == "string" and value.State ~= nil then
        if value.State == "Slot" then
            if enrichRecord(value,source) then found += 1 end
        else
            removeEgg(value.Uid,"state:"..safeString(value.State))
        end
    else
        local ok = pcall(function()
            local n = 0
            for _,child in pairs(value) do
                n += 1
                if n > 2200 then break end
                if typeof(child) == "table" then found += ingestTree(child,source,seen,depth+1) end
            end
        end)
        if not ok then addEvent("tree_iteration_error",{Source=source}) end
    end
    seen[value] = nil
    return found
end

local function requestSnapshots()
    local total = 0
    for _,name in ipairs({"RF/EggWorld/AskFieldEggSnapshot","RF/EggWorld/AskLiveSnapshot"}) do
        local rf = findDescendantByExactName("RemoteFunction",name)
        if rf then
            State.Stats.SnapshotRequests += 1
            local ok,result = pcall(function() return rf:InvokeServer() end)
            if ok then
                State.Stats.SnapshotSuccesses += 1
                local n = ingestTree(result,"snapshot:"..name)
                total += n
                addEvent("snapshot",{Name=name,Records=n,ResultType=typeof(result)})
            else
                addEvent("snapshot_error",{Name=name,Error=safeString(result)})
            end
        end
    end
    State.Stats.SnapshotRecords = total
    return total
end

local function hookRemotes()
    for _,d in ipairs(ReplicatedStorage:GetDescendants()) do
        if d:IsA("RemoteEvent") then
            if d.Name == "RE/EggWorld/FieldEggShifted" then
                connect(d.OnClientEvent,function(record)
                    if not State.Alive or typeof(record) ~= "table" then return end
                    if record.State == "Slot" then enrichRecord(record,"shifted")
                    elseif type(record.Uid) == "string" then removeEgg(record.Uid,"state:"..safeString(record.State)) end
                end,State.RemoteConnections)
            elseif d.Name == "RE/EggWorld/FieldEggBatchShifted" then
                connect(d.OnClientEvent,function(payload)
                    if not State.Alive or typeof(payload) ~= "table" then return end
                    if typeof(payload.RemovedUids) == "table" then for _,uid in pairs(payload.RemovedUids) do removeEgg(uid,"batch_removed") end end
                    if typeof(payload.UpdatedRecords) == "table" then
                        for _,record in pairs(payload.UpdatedRecords) do
                            if typeof(record) == "table" then
                                if record.State == "Slot" then enrichRecord(record,"batch")
                                elseif type(record.Uid) == "string" then removeEgg(record.Uid,"batch_state:"..safeString(record.State)) end
                            end
                        end
                    end
                end,State.RemoteConnections)
            elseif d.Name == "RE/EggWorld/FieldEggGone" then
                connect(d.OnClientEvent,function(uid) removeEgg(uid,"gone") end,State.RemoteConnections)
            end
        end
    end
end

local function refreshStats()
    local enriched,weights,prices = 0,0,0
    for _,egg in pairs(State.Eggs) do
        if egg.PetName and egg.Rarity then enriched += 1 end
        if egg.WeightKg ~= nil then weights += 1 end
        if egg.SellPrice ~= nil then prices += 1 end
    end
    State.Stats.EnrichedEggs = enriched
    State.Stats.WeightResolved = weights
    State.Stats.SellPriceResolved = prices
    local folder = Workspace:FindFirstChild("AreaEggSlotsClient")
    State.Stats.VisualNestModels = folder and #folder:GetChildren() or 0
end

local statusLabel
local function refreshStatus(extra)
    refreshStats()
    if not statusLabel then return end
    statusLabel.Text = string.format(
        "Ninhos: %d | Enriquecidos: %d\nCatálogo: %d | Raridades: %d\nPeso: %d | Valor: %d%s",
        countMap(State.Eggs),State.Stats.EnrichedEggs,State.Stats.CatalogPets,State.Stats.CatalogRarities,
        State.Stats.WeightResolved,State.Stats.SellPriceResolved,extra and ("\n"..extra) or ""
    )
end

local running = false
local function runPrecisionScan()
    if running then return end
    running = true
    State.FunctionDiagnostics = {}
    refreshStatus("D0 | carregando módulos...")
    local ok,err = pcall(function()
        local moduleOk,moduleErr = resolveModules()
        if not moduleOk then error(moduleErr) end
        local catalogOk,catalogErr = buildCatalog()
        if not catalogOk then error(catalogErr) end
        State.RawRecords = {}
        State.Eggs = {}
        requestSnapshots()
    end)
    running = false
    if ok then
        State.LastDiag = "D0"
        addEvent("precision_scan_complete",{Nests=countMap(State.Eggs),Catalog=State.Stats.CatalogPets,Rarities=State.Stats.CatalogRarities})
        refreshStatus("D0 | cálculo concluído")
    else
        local msg = safeString(err)
        if msg:find("EA0",1,true) then State.LastDiag = "EA"
        elseif msg:find("ER0",1,true) then State.LastDiag = "ER"
        else State.LastDiag = "ES01" end
        addEvent("precision_scan_error",{Error=msg})
        refreshStatus(State.LastDiag.." | "..msg:sub(1,48))
    end
end

local function sortedRarities()
    local arr = {}
    for _,r in pairs(State.Rarities) do arr[#arr+1] = r end
    table.sort(arr,function(a,b)
        local an,bn = tonumber(a.RarityNumber) or 999,tonumber(b.RarityNumber) or 999
        if an == bn then return safeString(a.DisplayName) < safeString(b.DisplayName) end
        return an < bn
    end)
    return arr
end

local function sortedCatalog()
    local arr = {}
    for _,entry in pairs(State.Catalog) do arr[#arr+1] = entry end
    table.sort(arr,function(a,b)
        local ar,br = tonumber(a.RarityNumber) or 999,tonumber(b.RarityNumber) or 999
        if ar == br then return safeString(a.DisplayName) < safeString(b.DisplayName) end
        return ar < br
    end)
    return arr
end

local function sortedEggs()
    local arr = {}
    for _,egg in pairs(State.Eggs) do arr[#arr+1] = egg end
    table.sort(arr,function(a,b)
        local ar,br = tonumber(a.RarityNumber) or -1,tonumber(b.RarityNumber) or -1
        if ar == br then
            local aw,bw = tonumber(a.WeightKg) or -1,tonumber(b.WeightKg) or -1
            if aw == bw then return safeString(a.Uid) < safeString(b.Uid) end
            return aw > bw
        end
        return ar > br
    end)
    return arr
end

local function report()
    refreshStats()
    return {
        Version="Precision Egg Scanner V7",
        Meta={PlaceId=game.PlaceId,GameId=game.GameId,JobId=game.JobId,StartedUnix=startedUnix,FinishedUnix=os.time(),DurationSeconds=elapsed(),InteractionRequired=false,Notes="Uses Data.Assets + EggRecords utility functions on current Slot records."},
        Stats=State.Stats,Rarities=sortedRarities(),PetCatalog=sortedCatalog(),CurrentNestEggs=sortedEggs(),
        FunctionDiagnostics=State.FunctionDiagnostics,Events=State.Events,
    }
end

local function asciiSafe(v)
    local s = safeString(v)
    local out = {}
    for i=1,#s do
        local b = string.byte(s,i)
        if b >= 32 and b <= 126 then out[#out+1] = string.char(b)
        elseif b == 9 then out[#out+1] = "\\t"
        elseif b == 10 then out[#out+1] = "\\n"
        elseif b == 13 then out[#out+1] = "\\r"
        else out[#out+1] = string.format("\\u%04X",b) end
    end
    return table.concat(out)
end

local function sanitize(v,depth,seen)
    depth = depth or 0
    seen = seen or {}
    if depth > 12 then return "<max-depth>" end
    local t = typeof(v)
    if t == "nil" then return nil end
    if t == "boolean" then return v end
    if t == "number" then return finite(v) and v or asciiSafe(v) end
    if t == "string" then return asciiSafe(v) end
    if t == "Vector3" then return {x=v.X,y=v.Y,z=v.Z} end
    if t == "Vector2" then return {x=v.X,y=v.Y} end
    if t == "Color3" then return {r=v.R,g=v.G,b=v.B} end
    if t == "CFrame" then local p=v.Position return {x=p.X,y=p.Y,z=p.Z} end
    if t == "EnumItem" then return asciiSafe(v) end
    if t == "Instance" then return {name=asciiSafe(v.Name),class=asciiSafe(v.ClassName),path=asciiSafe(fullName(v))} end
    if t ~= "table" then return "<"..asciiSafe(t).."> "..asciiSafe(v) end
    if seen[v] then return "<cycle>" end
    seen[v] = true
    local total,numeric,maxIndex = 0,0,0
    for k in pairs(v) do
        total += 1
        if type(k) == "number" and k >= 1 and k % 1 == 0 then numeric += 1 if k > maxIndex then maxIndex = k end end
        if total > 8000 then break end
    end
    local out = {}
    local dense = total > 0 and total == numeric and maxIndex == total
    if dense then
        for i=1,total do out[i] = sanitize(v[i],depth+1,seen) end
    else
        local n = 0
        for k,val in pairs(v) do
            n += 1
            if n > 8000 then out["<truncated>"] = true break end
            out[asciiSafe(k)] = sanitize(val,depth+1,seen)
        end
    end
    seen[v] = nil
    return out
end

local function customEscape(s)
    s = asciiSafe(s)
    s = s:gsub("\\","\\\\"):gsub('"','\\"'):gsub("\b","\\b"):gsub("\f","\\f"):gsub("\n","\\n"):gsub("\r","\\r"):gsub("\t","\\t")
    return '"'..s..'"'
end

local function customJson(v,depth,seen)
    depth = depth or 0
    seen = seen or {}
    if depth > 14 then return customEscape("<max-depth>") end
    local t = type(v)
    if v == nil then return "null" end
    if t == "boolean" then return v and "true" or "false" end
    if t == "number" then return finite(v) and tostring(v) or customEscape(v) end
    if t == "string" then return customEscape(v) end
    if t ~= "table" then return customEscape(v) end
    if seen[v] then return customEscape("<cycle>") end
    seen[v] = true
    local total,numeric,maxIndex = 0,0,0
    for k in pairs(v) do
        total += 1
        if type(k) == "number" and k >= 1 and k % 1 == 0 then numeric += 1 if k > maxIndex then maxIndex = k end end
    end
    local parts = {}
    local dense = total > 0 and total == numeric and maxIndex == total
    if dense then
        for i=1,total do parts[#parts+1] = customJson(v[i],depth+1,seen) end
        seen[v] = nil
        return "["..table.concat(parts,",").."]"
    end
    for k,val in pairs(v) do parts[#parts+1] = customEscape(k)..":"..customJson(val,depth+1,seen) end
    seen[v] = nil
    return "{"..table.concat(parts,",").."}"
end

local function exportReport()
    local okReport,raw = pcall(report)
    if not okReport then State.LastDiag="EJ01" return false,"EJ01 | report | "..safeString(raw):sub(1,42) end
    local okSan,clean = pcall(sanitize,raw)
    if not okSan then State.LastDiag="EJ02" return false,"EJ02 | sanitize | "..safeString(clean):sub(1,40) end
    local nativeOk,encoded = pcall(HttpService.JSONEncode,HttpService,clean)
    local diag = "J0"
    if not nativeOk then
        local fallbackOk,fallback = pcall(customJson,clean)
        if not fallbackOk then State.LastDiag="EJ03" return false,"EJ03 | fallback | "..safeString(fallback):sub(1,38) end
        encoded = fallback
        diag = "J1"
    end
    local name = "Psico_RoubeUmOvo_PrecisionEggs_"..os.time()..".json"
    if writefile then
        local wok,e = pcall(writefile,name,encoded)
        if wok then State.LastDiag=diag return true,diag.." | salvo | "..math.floor(#encoded/1024).."KB" end
        State.LastDiag="EW01" return false,"EW01 | writefile | "..safeString(e):sub(1,38)
    end
    if setclipboard then
        local cok,e = pcall(setclipboard,encoded)
        if cok then State.LastDiag=diag return true,diag.." | JSON copiado" end
        State.LastDiag="EC01" return false,"EC01 | clipboard | "..safeString(e):sub(1,38)
    end
    State.LastDiag="EO01" return false,"EO01 | sem writefile/setclipboard"
end

hookRemotes()

local function parentGui()
    local ok,h = pcall(function() if gethui then return gethui() end end)
    return (ok and h) or CoreGui
end

local old = parentGui():FindFirstChild("PsicoPrecisionEggScannerV7")
if old then old:Destroy() end
local gui = Instance.new("ScreenGui")
gui.Name="PsicoPrecisionEggScannerV7" gui.ResetOnSpawn=false gui.IgnoreGuiInset=true gui.Parent=parentGui()
local frame = Instance.new("Frame")
frame.AnchorPoint=Vector2.new(.5,.5) frame.Position=UDim2.fromScale(.5,.5) frame.Size=UDim2.fromOffset(318,230)
frame.BackgroundColor3=Color3.fromRGB(15,21,33) frame.BorderSizePixel=0 frame.Parent=gui
Instance.new("UICorner",frame).CornerRadius=UDim.new(0,12)
local stroke=Instance.new("UIStroke",frame) stroke.Thickness=1 stroke.Transparency=.3 stroke.Color=Color3.fromRGB(73,126,230)
local title=Instance.new("TextLabel")
title.BackgroundTransparency=1 title.Position=UDim2.fromOffset(12,8) title.Size=UDim2.new(1,-52,0,25)
title.Font=Enum.Font.GothamBold title.Text="EGG PRECISION SCANNER • V7" title.TextColor3=Color3.fromRGB(241,245,255) title.TextSize=13 title.TextXAlignment=Enum.TextXAlignment.Left title.Parent=frame
local close=Instance.new("TextButton")
close.AnchorPoint=Vector2.new(1,0) close.Position=UDim2.new(1,-8,0,7) close.Size=UDim2.fromOffset(28,28)
close.BackgroundColor3=Color3.fromRGB(32,42,60) close.BorderSizePixel=0 close.Font=Enum.Font.GothamBold close.Text="×" close.TextColor3=Color3.fromRGB(240,244,255) close.TextSize=15 close.Parent=frame
Instance.new("UICorner",close).CornerRadius=UDim.new(0,8)
statusLabel=Instance.new("TextLabel")
statusLabel.Position=UDim2.fromOffset(12,43) statusLabel.Size=UDim2.new(1,-24,0,82) statusLabel.BackgroundColor3=Color3.fromRGB(21,29,44)
statusLabel.BorderSizePixel=0 statusLabel.Font=Enum.Font.Code statusLabel.TextColor3=Color3.fromRGB(174,198,241) statusLabel.TextSize=9 statusLabel.TextWrapped=true statusLabel.Parent=frame
Instance.new("UICorner",statusLabel).CornerRadius=UDim.new(0,9)
local rescan=Instance.new("TextButton")
rescan.Position=UDim2.fromOffset(12,135) rescan.Size=UDim2.new(.5,-17,0,36) rescan.BackgroundColor3=Color3.fromRGB(31,55,100) rescan.BorderSizePixel=0 rescan.Font=Enum.Font.GothamMedium rescan.Text="Atualizar dados" rescan.TextColor3=Color3.fromRGB(240,244,255) rescan.TextSize=11 rescan.Parent=frame
Instance.new("UICorner",rescan).CornerRadius=UDim.new(0,9)
local export=Instance.new("TextButton")
export.Position=UDim2.new(.5,5,0,135) export.Size=UDim2.new(.5,-17,0,36) export.BackgroundColor3=Color3.fromRGB(37,82,170) export.BorderSizePixel=0 export.Font=Enum.Font.GothamMedium export.Text="Exportar JSON" export.TextColor3=Color3.fromRGB(245,248,255) export.TextSize=11 export.Parent=frame
Instance.new("UICorner",export).CornerRadius=UDim.new(0,9)
local hint=Instance.new("TextLabel")
hint.BackgroundTransparency=1 hint.Position=UDim2.fromOffset(12,180) hint.Size=UDim2.new(1,-24,0,38) hint.Font=Enum.Font.Gotham
hint.Text="Peso/valor vêm do EggRecords. Se algum contador ficar 0, exporte mesmo assim para diagnóstico." hint.TextColor3=Color3.fromRGB(151,163,188) hint.TextSize=9 hint.TextWrapped=true hint.Parent=frame

local drag=false local dragInput,dragStart,startPos
connect(frame.InputBegan,function(input) if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1 then drag=true dragStart=input.Position startPos=frame.Position end end)
connect(frame.InputChanged,function(input) if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseMovement then dragInput=input end end)
connect(UIS.InputChanged,function(input) if drag and input==dragInput then local d=input.Position-dragStart frame.Position=UDim2.new(startPos.X.Scale,startPos.X.Offset+d.X,startPos.Y.Scale,startPos.Y.Offset+d.Y) end end)
connect(UIS.InputEnded,function(input) if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1 then drag=false end end)
connect(rescan.MouseButton1Click,function() task.defer(runPrecisionScan) end)
connect(export.MouseButton1Click,function() local ok,msg=exportReport() refreshStatus((ok and "✓ " or "✗ ")..msg) end)

local function cleanup()
    if not State.Alive then return end
    State.Alive=false
    for _,c in ipairs(State.RemoteConnections) do disconnect(c) end
    for _,c in ipairs(State.Connections) do disconnect(c) end
    _G.PSICO_ROUBE_SCANNER_CLEANUP=nil
    pcall(function() gui:Destroy() end)
end
_G.PSICO_ROUBE_SCANNER_CLEANUP=cleanup
connect(close.MouseButton1Click,cleanup)

refreshStatus("D0 | preparando cálculo direto...")
task.defer(function() task.wait(.7) if State.Alive then runPrecisionScan() end end)
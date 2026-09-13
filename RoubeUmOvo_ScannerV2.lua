--[[
PSICOSENATICO | Roube um Ovo - Static Egg Catalog Scanner V6
Stable loader path: RoubeUmOvo_ScannerV2.lua

Goal:
  * Discover egg/pet metadata WITHOUT requiring the user to interact with every egg.
  * Track current nest eggs only (FieldEgg State == "Slot") for correlation.
  * Inspect already-loaded client modules, in-memory tables, constants and replicated values.
  * Search for rarity, pet identity, value/price and official weight/mass fields.
  * Keep visual scale fields separate from official weight fields.
  * Passive only: does not fire remotes, alter prompts, cooldowns or game state.

Important:
  * Already-loaded ModuleScripts may be required because Roblox caches their return value.
  * Unloaded ModuleScripts are NOT required by this scanner.
  * Executor-only inspection APIs are optional and used only when available.
]]

if _G.PSICO_ROUBE_MENU_CLEANUP then
    pcall(_G.PSICO_ROUBE_MENU_CLEANUP)
    _G.PSICO_ROUBE_MENU_CLEANUP = nil
end
if _G.PSICO_ROUBE_SCANNER_CLEANUP then
    pcall(_G.PSICO_ROUBE_SCANNER_CLEANUP)
end

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")
local UIS = game:GetService("UserInputService")

local LP = Players.LocalPlayer
local startedClock = os.clock()
local startedUnix = os.time()

local CONFIG = {
    MaxEvents = 1500,
    MaxEvidence = 1200,
    MaxCatalogEntries = 700,
    MaxLoadedModules = 350,
    MaxGcObjects = 60000,
    MaxGcRoots = 300,
    MaxWalkNodesPerSource = 4500,
    MaxWalkDepth = 6,
    MaxConstantsPerModule = 180,
}

local TOPIC_WORDS = {
    "egg","pet","animal","asset","hatch","rarity","tier","weight","mass","kg",
    "value","price","worth","sell","cost","income","earn","economy","currency",
    "config","data","database","directory","library","catalog","item","codex"
}

local RELEVANT_KEY_WORDS = {
    "assetcategory","category","pet","petname","animal","species","displayname","egg",
    "rarity","tier","rank","grade","value","price","worth","sell","cost","income","earn",
    "weight","mass","kg","gram","pound","lb","size","scale","height","width","length",
    "mutation","parasite","chance","odds","hatch","multiplier"
}

local CONFIRMED_RARITY = {
    ["Frog"] = {Rarity="Common", DisplayName="Frog Egg"},
    ["Chicken"] = {Rarity="Common", DisplayName="Chicken Egg"},
    ["Burrowing Owl"] = {Rarity="Rare", DisplayName="Burrowing Owl Egg"},
    ["Toucan"] = {Rarity="Rare", DisplayName="Toucan Egg"},
    ["Dodo"] = {Rarity="Rare", DisplayName="Dodo Egg"},
    ["Tob Tobi Tob Tob"] = {Rarity="Epic", DisplayName="Tob Tobi Tob Tob Egg"},
    ["Polar Bear"] = {Rarity="Legendary", DisplayName="Polar Bear Egg"},
    ["Finned Thresher"] = {Rarity="Legendary", DisplayName="Shark Egg"},
    ["Orca"] = {Rarity="Mythic", DisplayName="Orca Egg"},
    ["Sand Spider"] = {Rarity="Mythic", DisplayName="Sand Spider Egg"},
    ["Cave Dragon"] = {Rarity="Secret", DisplayName="Cosmic Dragon Egg"},
}

local State = {
    Alive = true,
    Connections = {},
    RemoteConnections = {},
    Eggs = {},
    Catalog = {},
    RarityCatalog = {},
    RarityNames = {},
    RarityCandidates = {},
    LoadedModuleEvidence = {},
    GcEvidence = {},
    ConstantEvidence = {},
    ReplicatedEvidence = {},
    Events = {},
    SeenEvidence = {},
    Stats = {},
    EventCount = 0,
    StaticScanRuns = 0,
}

for category, info in pairs(CONFIRMED_RARITY) do
    State.RarityCatalog[category] = {
        AssetCategory = category,
        Rarity = info.Rarity,
        DisplayName = info.DisplayName,
        Source = "confirmed_previous_scans",
    }
    State.RarityNames[info.Rarity] = true
end

local function elapsed()
    return os.clock() - startedClock
end

local function connect(signal, fn, bucket)
    local c = signal:Connect(fn)
    table.insert(bucket or State.Connections, c)
    return c
end

local function disconnect(c)
    pcall(function() c:Disconnect() end)
end

local function fullName(inst)
    local ok, value = pcall(function() return inst:GetFullName() end)
    return ok and value or (inst and inst.Name or "?")
end

local function lower(v)
    return string.lower(tostring(v or ""))
end

local function normalizeKey(v)
    return lower(v):gsub("[%s_%-%.:/]", "")
end

local function containsWord(text, words)
    local s = lower(text)
    for _, word in ipairs(words) do
        if s:find(word, 1, true) then return true end
    end
    return false
end

local function relevantKey(key)
    local n = normalizeKey(key)
    for _, word in ipairs(RELEVANT_KEY_WORDS) do
        if n:find(word, 1, true) then return true end
    end
    return false
end

local function primitive(v)
    local t = typeof(v)
    return t == "string" or t == "number" or t == "boolean"
end

local function plain(v, depth, seen)
    depth = depth or 0
    if depth > 3 then return "<depth>" end
    local tv = typeof(v)
    if primitive(v) or tv == "nil" then return v end
    if tv == "Vector3" then return {x=v.X,y=v.Y,z=v.Z} end
    if tv == "Vector2" then return {x=v.X,y=v.Y} end
    if tv == "Color3" then return {r=v.R,g=v.G,b=v.B} end
    if tv == "CFrame" then
        local p = v.Position
        return {x=p.X,y=p.Y,z=p.Z}
    end
    if tv == "EnumItem" then return tostring(v) end
    if tv == "Instance" then return {name=v.Name,class=v.ClassName,path=fullName(v)} end
    if tv == "table" then
        seen = seen or {}
        if seen[v] then return "<cycle>" end
        seen[v] = true
        local out, count = {}, 0
        for k,val in pairs(v) do
            count += 1
            if count > 60 then
                out["<truncated>"] = true
                break
            end
            out[tostring(k)] = plain(val, depth+1, seen)
        end
        seen[v] = nil
        return out
    end
    return tostring(v)
end

local function addLimited(list, value, maxn)
    table.insert(list, value)
    if #list > (maxn or CONFIG.MaxEvidence) then
        table.remove(list, 1)
    end
end

local function addEvent(kind, data)
    State.EventCount += 1
    addLimited(State.Events, {i=State.EventCount,t=elapsed(),kind=kind,data=data}, CONFIG.MaxEvents)
end

local function getFieldCaseInsensitive(t, names)
    if typeof(t) ~= "table" then return nil,nil end
    local wanted = {}
    for _,n in ipairs(names) do wanted[normalizeKey(n)] = true end
    local count = 0
    for k,v in pairs(t) do
        count += 1
        if count > 200 then break end
        if wanted[normalizeKey(k)] then return v,tostring(k) end
    end
    return nil,nil
end

local function mergeCatalog(identity, fields, source, path)
    if type(identity) ~= "string" or identity == "" then return end
    if #identity > 100 then return end

    local count = 0
    for _ in pairs(State.Catalog) do count += 1 end
    if not State.Catalog[identity] and count >= CONFIG.MaxCatalogEntries then return end

    local entry = State.Catalog[identity] or {
        Identity = identity,
        Fields = {},
        Sources = {},
    }
    State.Catalog[identity] = entry

    for k,v in pairs(fields or {}) do
        if primitive(v) then
            entry.Fields[k] = v
        elseif typeof(v) == "table" then
            entry.Fields[k] = plain(v)
        end

        local nk = normalizeKey(k)
        if nk:find("rarity",1,true) or nk == "tier" or nk == "grade" then
            if type(v) == "string" and v ~= "" and #v <= 50 then
                State.RarityNames[v] = true
            end
        end
    end

    local sourceKey = tostring(source or "?") .. "|" .. tostring(path or "")
    if not entry.Sources[sourceKey] then
        entry.Sources[sourceKey] = {source=source,path=path}
    end
end

local function extractRelevantFields(t)
    local fields = {}
    local count = 0
    for k,v in pairs(t) do
        count += 1
        if count > 220 then break end
        local key = tostring(k)
        if relevantKey(key) then
            if primitive(v) or typeof(v)=="Vector3" or typeof(v)=="Color3" or typeof(v)=="CFrame" then
                fields[key] = plain(v)
            elseif typeof(v) == "table" then
                fields[key] = plain(v)
            end
        end
    end
    return fields
end

local IDENTITY_KEYS = {
    "AssetCategory","PetName","Pet","Animal","Species","DisplayName","AssetName","EggName","Name","Id","ID"
}

local function inferIdentity(t, fallbackKey)
    local v = getFieldCaseInsensitive(t, IDENTITY_KEYS)
    if type(v) == "string" and v ~= "" and #v <= 100 then return v end
    if type(fallbackKey) == "string" and fallbackKey ~= "" and #fallbackKey <= 100 then
        if not tonumber(fallbackKey) then return fallbackKey end
    end
    return nil
end

local function directRelevantScore(t)
    local score, count = 0, 0
    for k,v in pairs(t) do
        count += 1
        if count > 120 then break end
        if relevantKey(k) then
            score += primitive(v) and 2 or 1
        end
    end
    return score
end

local function inspectTableTree(root, sourceName, evidenceList, sourceLooksLikeRarity)
    if typeof(root) ~= "table" then return end
    local seen = {}
    local nodes = 0

    local function walk(t, path, depth, fallbackKey)
        if not State.Alive or typeof(t) ~= "table" or seen[t] then return end
        if depth > CONFIG.MaxWalkDepth or nodes >= CONFIG.MaxWalkNodesPerSource then return end
        seen[t] = true
        nodes += 1

        local fields = extractRelevantFields(t)
        local fieldCount = 0
        for _ in pairs(fields) do fieldCount += 1 end
        local identity = inferIdentity(t, fallbackKey)

        if fieldCount > 0 then
            local sig = tostring(sourceName).."|"..path.."|"..tostring(identity or "")
            if not State.SeenEvidence[sig] then
                State.SeenEvidence[sig] = true
                addLimited(evidenceList, {
                    source = sourceName,
                    path = path,
                    identity = identity,
                    fields = fields,
                })
            end
            if identity then mergeCatalog(identity, fields, sourceName, path) end
        end

        if sourceLooksLikeRarity then
            local checked = 0
            for k,v in pairs(t) do
                checked += 1
                if checked > 140 then break end
                if type(v)=="string" and #v>0 and #v<=40 then
                    local keyName = tostring(k)
                    if normalizeKey(keyName):find("name",1,true) or normalizeKey(keyName):find("rarity",1,true) then
                        State.RarityCandidates[v] = {source=sourceName,path=path,key=keyName}
                    end
                elseif type(k)=="string" and #k>0 and #k<=40 and typeof(v)=="table" then
                    if directRelevantScore(v)>0 then
                        State.RarityCandidates[k] = State.RarityCandidates[k] or {source=sourceName,path=path,key="table_key"}
                    end
                end
            end
        end

        local childCount = 0
        for k,v in pairs(t) do
            childCount += 1
            if childCount > 220 then break end
            if typeof(v) == "table" then
                local childKey = tostring(k)
                walk(v, path.."."..childKey, depth+1, childKey)
            end
        end
    end

    walk(root, "$", 0, nil)
    return nodes
end

local function visualForUid(uid)
    local folder = Workspace:FindFirstChild("AreaEggSlotsClient")
    if folder then
        local m = folder:FindFirstChild(uid)
        if m then return m, "AreaEggSlotsClient" end
    end
    local direct = Workspace:FindFirstChild(uid)
    if direct then return direct, "Workspace" end
    return nil,nil
end

local function modelEvidence(uid)
    local model, method = visualForUid(uid)
    if not model then return nil end
    local out = {
        path=fullName(model), method=method, attributes={}, values={}, texts={}, named={}
    }
    local ok,a = pcall(function() return model:GetAttributes() end)
    if ok then
        for k,v in pairs(a) do
            if relevantKey(k) then out.attributes[tostring(k)] = plain(v) end
        end
    end
    local n = 0
    for _,d in ipairs(model:GetDescendants()) do
        n += 1
        if n > 400 then break end
        local nameRelevant = relevantKey(d.Name)
        if d:IsA("ValueBase") and nameRelevant then
            local vok,v = pcall(function() return d.Value end)
            table.insert(out.values,{path=fullName(d),name=d.Name,value=vok and plain(v) or "<read-failed>"})
        elseif d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox") then
            local text = tostring(d.Text or "")
            if text ~= "" and (containsWord(text, RELEVANT_KEY_WORDS) or text:find("%$") or lower(text):find("kg",1,true)) then
                table.insert(out.texts,{path=fullName(d),name=d.Name,text=text})
            end
        elseif nameRelevant then
            table.insert(out.named,{path=fullName(d),name=d.Name,class=d.ClassName})
        end
    end
    return out
end

local function rarityFor(category)
    return State.RarityCatalog[tostring(category or "")]
end

local function copyMutations(v)
    if typeof(v) ~= "table" then return {} end
    local out = {}
    for _,m in pairs(v) do table.insert(out,tostring(m)) end
    table.sort(out)
    return out
end

local statusLabel
local function countMap(t)
    local n=0
    for _ in pairs(t) do n+=1 end
    return n
end

local function refreshStatus(extra)
    if not statusLabel then return end
    statusLabel.Text = string.format(
        "Ninhos: %d | Catálogo: %d | Raridades: %d\nMódulos: %d | Memória: %d | Constantes: %d%s",
        countMap(State.Eggs), countMap(State.Catalog), countMap(State.RarityNames),
        #State.LoadedModuleEvidence, #State.GcEvidence, #State.ConstantEvidence,
        extra and ("\n"..extra) or ""
    )
end

local function makeEgg(record)
    local uid = tostring(record.Uid)
    local category = tostring(record.AssetCategory or "Unknown")
    local known = rarityFor(category)
    local fields = extractRelevantFields(record)
    local egg = {
        Uid=uid,
        State="Slot",
        NestId=record.NestId,
        AreaId=record.AreaId,
        AssetCategory=record.AssetCategory,
        PetOrAsset=record.AssetCategory,
        DisplayName=record.DisplayName or (known and known.DisplayName) or nil,
        Rarity=record.Rarity or (known and known.Rarity) or nil,
        NestScale=record.NestScale,
        AssetScale=record.AssetScale,
        BoundsSize=plain(record.BoundsSize),
        BoundsCFrame=plain(record.BoundsCFrame),
        BottomCFrame=plain(record.BottomCFrame),
        BaseMutation=record.BaseMutation,
        Mutations=copyMutations(record.Mutations),
        HasParasite=record.HasParasite==true,
        ServerFields=fields,
        VisualEvidence=modelEvidence(uid),
        FirstSeen=(State.Eggs[uid] and State.Eggs[uid].FirstSeen) or elapsed(),
        LastSeen=elapsed(),
    }
    mergeCatalog(category, fields, "FieldEggRecord", uid)
    if egg.Rarity then State.RarityNames[egg.Rarity]=true end
    return egg
end

local function removeEgg(uid, reason)
    if type(uid)~="string" then return end
    local old=State.Eggs[uid]
    if old then
        State.Eggs[uid]=nil
        addEvent("slot_removed",{Uid=uid,AssetCategory=old.AssetCategory,Reason=reason})
        refreshStatus()
    end
end

local function ingestFieldRecord(record, source)
    if typeof(record)~="table" or type(record.Uid)~="string" then return end
    if record.State=="Slot" then
        local egg=makeEgg(record)
        State.Eggs[egg.Uid]=egg
        addEvent("slot_seen",{Source=source,Uid=egg.Uid,AssetCategory=egg.AssetCategory,Rarity=egg.Rarity,NestScale=egg.NestScale,AssetScale=egg.AssetScale})
        refreshStatus()
    else
        removeEgg(record.Uid,"state:"..tostring(record.State))
    end
end

local function onBatch(payload)
    if typeof(payload)~="table" then return end
    if typeof(payload.RemovedUids)=="table" then
        for _,uid in pairs(payload.RemovedUids) do if type(uid)=="string" then removeEgg(uid,"batch_removed") end end
    end
    if typeof(payload.UpdatedRecords)=="table" then
        for _,record in pairs(payload.UpdatedRecords) do ingestFieldRecord(record,"batch") end
    end
end

local function onRedeem(info)
    if typeof(info)~="table" then return end
    local category=info.AssetCategory
    if type(category)~="string" or category=="" then return end
    State.RarityCatalog[category]={
        AssetCategory=category,
        Rarity=info.Rarity,
        DisplayName=info.DisplayName,
        Color=plain(info.Color),
        Source="redeem_verdict",
        LastSeen=elapsed(),
    }
    if type(info.Rarity)=="string" then State.RarityNames[info.Rarity]=true end
    local fields=extractRelevantFields(info)
    mergeCatalog(category,fields,"FieldEggRedeemVerdict",category)
    for _,egg in pairs(State.Eggs) do
        if egg.AssetCategory==category then
            egg.Rarity=info.Rarity or egg.Rarity
            egg.DisplayName=info.DisplayName or egg.DisplayName
        end
    end
    addEvent("redeem_metadata",{AssetCategory=category,Rarity=info.Rarity,DisplayName=info.DisplayName})
    refreshStatus()
end

local function hookEggRemotes()
    for _,d in ipairs(ReplicatedStorage:GetDescendants()) do
        if d:IsA("RemoteEvent") then
            if d.Name=="RE/EggWorld/FieldEggShifted" then
                connect(d.OnClientEvent,function(record) if State.Alive then ingestFieldRecord(record,"shifted") end end,State.RemoteConnections)
            elseif d.Name=="RE/EggWorld/FieldEggBatchShifted" then
                connect(d.OnClientEvent,function(payload) if State.Alive then onBatch(payload) end end,State.RemoteConnections)
            elseif d.Name=="RE/EggWorld/FieldEggGone" then
                connect(d.OnClientEvent,function(uid) if State.Alive and type(uid)=="string" then removeEgg(uid,"gone") end end,State.RemoteConnections)
            elseif d.Name=="RE/EggWorld/FieldEggRedeemVerdict" then
                connect(d.OnClientEvent,function(info) if State.Alive then onRedeem(info) end end,State.RemoteConnections)
            end
        end
    end
end

local function scanReplicatedValues()
    State.ReplicatedEvidence={}
    local scanned=0
    for _,d in ipairs(ReplicatedStorage:GetDescendants()) do
        scanned+=1
        if scanned>30000 then break end
        local path=fullName(d)
        local topic=containsWord(path,TOPIC_WORDS)
        if topic then
            local rec=nil
            if d:IsA("ValueBase") and relevantKey(d.Name) then
                local ok,v=pcall(function() return d.Value end)
                rec={path=path,class=d.ClassName,name=d.Name,value=ok and plain(v) or "<read-failed>"}
            else
                local ok,a=pcall(function() return d:GetAttributes() end)
                if ok then
                    local ra={}
                    for k,v in pairs(a) do if relevantKey(k) then ra[tostring(k)]=plain(v) end end
                    if next(ra) then rec={path=path,class=d.ClassName,name=d.Name,attributes=ra} end
                end
            end
            if rec then addLimited(State.ReplicatedEvidence,rec) end
        end
    end
    State.Stats.ReplicatedDescendantsScanned=scanned
end

local function getLoadedModulesSafe()
    if type(getloadedmodules)~="function" then return {} end
    local ok,list=pcall(getloadedmodules)
    return ok and type(list)=="table" and list or {}
end

local function scanLoadedModules()
    State.LoadedModuleEvidence={}
    local list=getLoadedModulesSafe()
    local inspected=0
    local loadedSet=setmetatable({},{__mode="k"})
    for _,m in ipairs(list) do loadedSet[m]=true end
    State._LoadedSet=loadedSet

    for _,m in ipairs(list) do
        if inspected>=CONFIG.MaxLoadedModules then break end
        if typeof(m)=="Instance" and m:IsA("ModuleScript") then
            local path=fullName(m)
            if containsWord(path,TOPIC_WORDS) then
                inspected+=1
                local ok,result=pcall(require,m)
                if ok then
                    if typeof(result)=="table" then
                        local nodes=inspectTableTree(result,"LoadedModule:"..path,State.LoadedModuleEvidence,lower(path):find("rarity",1,true)~=nil)
                        if nodes and nodes>0 then
                            addEvent("module_inspected",{path=path,nodes=nodes})
                        end
                    elseif typeof(result)=="function" then
                        local getups=(debug and debug.getupvalues) or getupvalues
                        if type(getups)=="function" then
                            local uok,ups=pcall(getups,result)
                            if uok and typeof(ups)=="table" then
                                for i,v in pairs(ups) do
                                    if typeof(v)=="table" then
                                        inspectTableTree(v,"LoadedModuleFn:"..path..":upvalue:"..tostring(i),State.LoadedModuleEvidence,lower(path):find("rarity",1,true)~=nil)
                                    end
                                end
                            end
                        end
                    end
                else
                    addLimited(State.LoadedModuleEvidence,{source="LoadedModule:"..path,error=tostring(result)})
                end
            end
        end
    end
    State.Stats.LoadedModulesTotal=#list
    State.Stats.LoadedModulesInspected=inspected
end

local function getConstantsFunction()
    if debug and type(debug.getconstants)=="function" then return debug.getconstants end
    if type(getconstants)=="function" then return getconstants end
    return nil
end

local function scanModuleConstants()
    State.ConstantEvidence={}
    local getconst=getConstantsFunction()
    if type(getscriptclosure)~="function" or type(getconst)~="function" then
        State.Stats.ConstantScannerAvailable=false
        return
    end
    State.Stats.ConstantScannerAvailable=true

    local modules=0
    for _,m in ipairs(ReplicatedStorage:GetDescendants()) do
        if m:IsA("ModuleScript") and containsWord(fullName(m),TOPIC_WORDS) then
            modules+=1
            if modules>260 then break end
            local cok,closure=pcall(getscriptclosure,m)
            if cok and typeof(closure)=="function" then
                local ok,consts=pcall(getconst,closure)
                if ok and type(consts)=="table" then
                    local kept={}
                    local n=0
                    for _,v in pairs(consts) do
                        if primitive(v) then
                            local keep=false
                            if type(v)=="string" then
                                keep=#v>0 and #v<=100 and (containsWord(v,RELEVANT_KEY_WORDS) or lower(fullName(m)):find("rarity",1,true)~=nil or lower(fullName(m)):find("weight",1,true)~=nil)
                            elseif type(v)=="number" then
                                keep=lower(fullName(m)):find("weight",1,true)~=nil or lower(fullName(m)):find("price",1,true)~=nil or lower(fullName(m)):find("value",1,true)~=nil
                            end
                            if keep then
                                n+=1
                                table.insert(kept,v)
                                if n>=CONFIG.MaxConstantsPerModule then break end
                            end
                        end
                    end
                    if #kept>0 then
                        addLimited(State.ConstantEvidence,{module=fullName(m),constants=kept})
                        if lower(fullName(m)):find("rarity",1,true) then
                            for _,v in ipairs(kept) do
                                if type(v)=="string" and #v<=40 and not relevantKey(v) then
                                    State.RarityCandidates[v]=State.RarityCandidates[v] or {source="module_constants",path=fullName(m)}
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    State.Stats.ConstantModulesScanned=modules
end

local function scanGcMemory()
    State.GcEvidence={}
    if type(getgc)~="function" then
        State.Stats.GetGcAvailable=false
        return
    end
    State.Stats.GetGcAvailable=true
    local ok,objects=pcall(getgc,true)
    if not ok or type(objects)~="table" then return end

    local objectCount=0
    local roots=0
    for _,obj in ipairs(objects) do
        objectCount+=1
        if objectCount>CONFIG.MaxGcObjects or roots>=CONFIG.MaxGcRoots then break end
        if typeof(obj)=="table" then
            local score=0
            local sok,sres=pcall(directRelevantScore,obj)
            if sok then score=sres end
            if score>=3 then
                roots+=1
                local source="GC:"..tostring(roots)
                pcall(inspectTableTree,obj,source,State.GcEvidence,false)
            end
        end
    end
    State.Stats.GcObjectsScanned=objectCount
    State.Stats.GcRelevantRoots=roots
end

local function refreshCurrentVisuals()
    for _,egg in pairs(State.Eggs) do
        egg.VisualEvidence=modelEvidence(egg.Uid)
        egg.LastMetadataScan=elapsed()
    end
end

local scanningStatic=false
local function runStaticScan()
    if scanningStatic then return end
    scanningStatic=true
    State.StaticScanRuns+=1
    refreshStatus("Lendo catálogo client-side...")

    local ok,err=pcall(function()
        scanReplicatedValues()
        scanLoadedModules()
        scanModuleConstants()
        scanGcMemory()
        refreshCurrentVisuals()
    end)

    scanningStatic=false
    if ok then
        addEvent("static_scan_complete",{
            run=State.StaticScanRuns,
            catalog=countMap(State.Catalog),
            rarities=countMap(State.RarityNames),
            candidates=countMap(State.RarityCandidates),
        })
        refreshStatus("Varredura estática concluída")
    else
        addEvent("static_scan_error",{error=tostring(err)})
        refreshStatus("Erro parcial: "..tostring(err))
    end
end

local function report()
    local rarityNames={}
    for name in pairs(State.RarityNames) do table.insert(rarityNames,name) end
    table.sort(rarityNames)

    local candidates={}
    for name,source in pairs(State.RarityCandidates) do
        table.insert(candidates,{name=name,source=source})
    end
    table.sort(candidates,function(a,b) return tostring(a.name)<tostring(b.name) end)

    return {
        Version="Static Egg Catalog Scanner V6",
        Meta={
            PlaceId=game.PlaceId,
            GameId=game.GameId,
            JobId=game.JobId,
            StartedUnix=startedUnix,
            FinishedUnix=os.time(),
            DurationSeconds=elapsed(),
            InteractionRequired=false,
            Notes="Static client data + current Slot eggs; official weight/value only when explicitly found.",
        },
        Stats=State.Stats,
        CurrentNestEggs=State.Eggs,
        StaticCatalog=State.Catalog,
        ConfirmedRarityCatalog=State.RarityCatalog,
        RarityNames=rarityNames,
        RarityCandidates=candidates,
        LoadedModuleEvidence=State.LoadedModuleEvidence,
        GcEvidence=State.GcEvidence,
        ConstantEvidence=State.ConstantEvidence,
        ReplicatedEvidence=State.ReplicatedEvidence,
        Events=State.Events,
    }
end

local function exportReport()
    local ok,encoded=pcall(HttpService.JSONEncode,HttpService,report())
    if not ok then return false,"JSONEncode falhou: "..tostring(encoded) end
    local name="Psico_RoubeUmOvo_StaticCatalog_"..tostring(os.time())..".json"
    if writefile then
        local wok,werr=pcall(writefile,name,encoded)
        if wok then return true,"Salvo: "..name end
        return false,"writefile falhou: "..tostring(werr)
    end
    if setclipboard then
        local cok,cerr=pcall(setclipboard,encoded)
        if cok then return true,"JSON copiado" end
        return false,"setclipboard falhou: "..tostring(cerr)
    end
    return false,"Executor sem writefile/setclipboard"
end

hookEggRemotes()

task.defer(function()
    task.wait(1.5)
    if State.Alive then runStaticScan() end
end)

local function parentGui()
    local ok,h=pcall(function() if gethui then return gethui() end end)
    return (ok and h) or CoreGui
end

local old=parentGui():FindFirstChild("PsicoStaticEggScannerV6")
if old then old:Destroy() end

local gui=Instance.new("ScreenGui")
gui.Name="PsicoStaticEggScannerV6"
gui.ResetOnSpawn=false
gui.IgnoreGuiInset=true
gui.Parent=parentGui()

local frame=Instance.new("Frame")
frame.AnchorPoint=Vector2.new(.5,.5)
frame.Position=UDim2.fromScale(.5,.5)
frame.Size=UDim2.fromOffset(306,218)
frame.BackgroundColor3=Color3.fromRGB(15,21,33)
frame.BorderSizePixel=0
frame.Parent=gui
Instance.new("UICorner",frame).CornerRadius=UDim.new(0,12)
local stroke=Instance.new("UIStroke",frame)
stroke.Thickness=1
stroke.Transparency=.3
stroke.Color=Color3.fromRGB(73,126,230)

local title=Instance.new("TextLabel")
title.BackgroundTransparency=1
title.Position=UDim2.fromOffset(12,8)
title.Size=UDim2.new(1,-52,0,25)
title.Font=Enum.Font.GothamBold
title.Text="EGG CATALOG SCANNER • V6"
title.TextColor3=Color3.fromRGB(241,245,255)
title.TextSize=13
title.TextXAlignment=Enum.TextXAlignment.Left
title.Parent=frame

local close=Instance.new("TextButton")
close.AnchorPoint=Vector2.new(1,0)
close.Position=UDim2.new(1,-8,0,7)
close.Size=UDim2.fromOffset(28,28)
close.BackgroundColor3=Color3.fromRGB(32,42,60)
close.BorderSizePixel=0
close.Font=Enum.Font.GothamBold
close.Text="×"
close.TextColor3=Color3.fromRGB(240,244,255)
close.TextSize=15
close.Parent=frame
Instance.new("UICorner",close).CornerRadius=UDim.new(0,8)

statusLabel=Instance.new("TextLabel")
statusLabel.Position=UDim2.fromOffset(12,43)
statusLabel.Size=UDim2.new(1,-24,0,72)
statusLabel.BackgroundColor3=Color3.fromRGB(21,29,44)
statusLabel.BorderSizePixel=0
statusLabel.Font=Enum.Font.Code
statusLabel.TextColor3=Color3.fromRGB(174,198,241)
statusLabel.TextSize=10
statusLabel.TextWrapped=true
statusLabel.Parent=frame
Instance.new("UICorner",statusLabel).CornerRadius=UDim.new(0,9)

local rescan=Instance.new("TextButton")
rescan.Position=UDim2.fromOffset(12,125)
rescan.Size=UDim2.new(.5,-17,0,36)
rescan.BackgroundColor3=Color3.fromRGB(31,55,100)
rescan.BorderSizePixel=0
rescan.Font=Enum.Font.GothamMedium
rescan.Text="Revarrer memória"
rescan.TextColor3=Color3.fromRGB(240,244,255)
rescan.TextSize=11
rescan.Parent=frame
Instance.new("UICorner",rescan).CornerRadius=UDim.new(0,9)

local export=Instance.new("TextButton")
export.Position=UDim2.new(.5,5,0,125)
export.Size=UDim2.new(.5,-17,0,36)
export.BackgroundColor3=Color3.fromRGB(37,82,170)
export.BorderSizePixel=0
export.Font=Enum.Font.GothamMedium
export.Text="Exportar JSON"
export.TextColor3=Color3.fromRGB(245,248,255)
export.TextSize=11
export.Parent=frame
Instance.new("UICorner",export).CornerRadius=UDim.new(0,9)

local hint=Instance.new("TextLabel")
hint.BackgroundTransparency=1
hint.Position=UDim2.fromOffset(12,169)
hint.Size=UDim2.new(1,-24,0,36)
hint.Font=Enum.Font.Gotham
hint.Text="Não precisa interagir com ovos. Aguarde a varredura estática terminar."
hint.TextColor3=Color3.fromRGB(151,163,188)
hint.TextSize=10
hint.TextWrapped=true
hint.Parent=frame

local drag=false
local dragInput,dragStart,startPos
connect(frame.InputBegan,function(input)
    if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1 then
        drag=true
        dragStart=input.Position
        startPos=frame.Position
    end
end)
connect(frame.InputChanged,function(input)
    if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseMovement then dragInput=input end
end)
connect(UIS.InputChanged,function(input)
    if drag and input==dragInput then
        local delta=input.Position-dragStart
        frame.Position=UDim2.new(startPos.X.Scale,startPos.X.Offset+delta.X,startPos.Y.Scale,startPos.Y.Offset+delta.Y)
    end
end)
connect(UIS.InputEnded,function(input)
    if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1 then drag=false end
end)

connect(rescan.MouseButton1Click,function()
    task.defer(runStaticScan)
end)

connect(export.MouseButton1Click,function()
    local ok,msg=exportReport()
    refreshStatus((ok and "✓ " or "✗ ")..msg)
end)

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

refreshStatus("Iniciando varredura passiva...")
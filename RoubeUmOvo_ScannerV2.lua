--[[
PSICOSENATICO | Roube um Ovo - Egg Catalog Scanner V6.3
Stable loader path: RoubeUmOvo_ScannerV2.lua

V6.3
  * Keeps the V6.2 pre-existing nest recovery.
  * Adds export diagnostics with short codes visible in screenshots.
  * Sanitizes every string/table before Roblox JSONEncode.
  * Falls back to a custom ASCII-safe JSON encoder if native JSONEncode still fails.
  * Never requires interaction with individual eggs.
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

local CONFIG = {
    MaxEvents=1400,
    MaxEvidence=1000,
    MaxCatalog=900,
    MaxGcObjects=70000,
    MaxGcEggRecords=500,
    MaxGcCatalogRoots=420,
    MaxWalkDepth=5,
    MaxWalkNodes=4500,
    MaxConstants=220,
    JsonDepth=11,
    JsonEntries=7000,
    JsonString=12000,
}

local TOPIC_WORDS={
    "egg","pet","animal","asset","hatch","rarity","tier","weight","mass","kg",
    "value","price","worth","sell","cost","income","earn","catalog","config",
    "database","directory","library","item","codex"
}
local RELEVANT_KEYS={
    "assetcategory","category","pet","petname","animal","species","displayname","egg",
    "rarity","tier","rank","grade","value","price","worth","sell","cost","income","earn",
    "weight","mass","kg","gram","pound","lb","size","scale","height","width","length",
    "mutation","parasite","chance","odds","hatch","multiplier"
}

local CONFIRMED_RARITY={
    ["Frog"]={Rarity="Common",DisplayName="Frog Egg"},
    ["Chicken"]={Rarity="Common",DisplayName="Chicken Egg"},
    ["Burrowing Owl"]={Rarity="Rare",DisplayName="Burrowing Owl Egg"},
    ["Toucan"]={Rarity="Rare",DisplayName="Toucan Egg"},
    ["Dodo"]={Rarity="Rare",DisplayName="Dodo Egg"},
    ["Tob Tobi Tob Tob"]={Rarity="Epic",DisplayName="Tob Tobi Tob Tob Egg"},
    ["Polar Bear"]={Rarity="Legendary",DisplayName="Polar Bear Egg"},
    ["Finned Thresher"]={Rarity="Legendary",DisplayName="Shark Egg"},
    ["Orca"]={Rarity="Mythic",DisplayName="Orca Egg"},
    ["Sand Spider"]={Rarity="Mythic",DisplayName="Sand Spider Egg"},
    ["Cave Dragon"]={Rarity="Secret",DisplayName="Cosmic Dragon Egg"},
}

local State={
    Alive=true,Connections={},RemoteConnections={},Eggs={},Catalog={},RarityCatalog={},RarityNames={},RarityCandidates={},
    LoadedModuleEvidence={},GcEvidence={},ConstantEvidence={},ReplicatedEvidence={},Events={},SeenEvidence={},
    Stats={VisualNestModels=0,SnapshotRequests=0,SnapshotSuccesses=0,SnapshotRecords=0,MemoryEggRecords=0},
    EventCount=0,ScanRuns=0,LastDiag="READY"
}
for category,info in pairs(CONFIRMED_RARITY) do
    State.RarityCatalog[category]={AssetCategory=category,Rarity=info.Rarity,DisplayName=info.DisplayName,Source="confirmed_previous_scans"}
    State.RarityNames[info.Rarity]=true
end

local function elapsed() return os.clock()-startedClock end
local function safeString(v) local ok,s=pcall(tostring,v) return ok and s or "<unprintable>" end
local function lower(v) return string.lower(safeString(v or "")) end
local function normalize(v) return lower(v):gsub("[%s_%-%.:/]","") end
local function finite(v) return type(v)=="number" and v==v and v~=math.huge and v~=-math.huge end
local function fullName(i) local ok,v=pcall(function() return i:GetFullName() end) return ok and v or (i and i.Name or "?") end
local function countMap(t) local n=0 for _ in pairs(t) do n+=1 end return n end

local function containsWord(text,list)
    local s=lower(text)
    for _,w in ipairs(list) do if s:find(w,1,true) then return true end end
    return false
end
local function relevantKey(k)
    local n=normalize(k)
    for _,w in ipairs(RELEVANT_KEYS) do if n:find(w,1,true) then return true end end
    return false
end

-- Produces ASCII-only strings for export. This also neutralizes invalid UTF-8 bytes.
local function asciiSafe(s)
    s=safeString(s)
    local out={}
    local limit=math.min(#s,CONFIG.JsonString)
    for i=1,limit do
        local b=string.byte(s,i)
        if b>=32 and b<=126 then
            out[#out+1]=string.char(b)
        elseif b==9 then out[#out+1]="\\t"
        elseif b==10 then out[#out+1]="\\n"
        elseif b==13 then out[#out+1]="\\r"
        else out[#out+1]=string.format("\\x%02X",b) end
    end
    if #s>limit then out[#out+1]="<truncated>" end
    return table.concat(out)
end

local function plain(v,depth,seen)
    depth=depth or 0
    if depth>4 then return "<depth>" end
    local t=typeof(v)
    if t=="nil" then return nil end
    if t=="boolean" then return v end
    if t=="string" then return v end
    if t=="number" then
        if finite(v) then return v end
        if v~=v then return "<NaN>" end
        return v==math.huge and "<Infinity>" or "<-Infinity>"
    end
    if t=="Vector3" then return {x=v.X,y=v.Y,z=v.Z} end
    if t=="Vector2" then return {x=v.X,y=v.Y} end
    if t=="Color3" then return {r=v.R,g=v.G,b=v.B} end
    if t=="CFrame" then local p=v.Position return {x=p.X,y=p.Y,z=p.Z} end
    if t=="UDim" then return {scale=v.Scale,offset=v.Offset} end
    if t=="UDim2" then return {x={scale=v.X.Scale,offset=v.X.Offset},y={scale=v.Y.Scale,offset=v.Y.Offset}} end
    if t=="EnumItem" then return safeString(v) end
    if t=="Instance" then return {name=v.Name,class=v.ClassName,path=fullName(v)} end
    if t=="table" then
        seen=seen or {}
        if seen[v] then return "<cycle>" end
        seen[v]=true
        local out,count={},0
        local k,val=next(v,nil)
        while k~=nil do
            count+=1
            if count>140 then out["<truncated>"]=true break end
            out[safeString(k)]=plain(val,depth+1,seen)
            k,val=next(v,k)
        end
        seen[v]=nil
        return out
    end
    return "<"..t.."> "..safeString(v)
end

local function connect(signal,fn,bucket)
    local c=signal:Connect(fn)
    table.insert(bucket or State.Connections,c)
    return c
end
local function disconnect(c) pcall(function() c:Disconnect() end) end
local function addLimited(list,v,maxn) table.insert(list,v) if #list>(maxn or CONFIG.MaxEvidence) then table.remove(list,1) end end
local function addEvent(kind,data)
    State.EventCount+=1
    addLimited(State.Events,{i=State.EventCount,t=elapsed(),kind=kind,data=plain(data)},CONFIG.MaxEvents)
end

local function extractFields(t)
    local out={}
    if typeof(t)~="table" then return out end
    local n=0
    local k,v=next(t,nil)
    while k~=nil do
        n+=1 if n>260 then break end
        if relevantKey(k) then out[safeString(k)]=plain(v) end
        k,v=next(t,k)
    end
    return out
end

local ID_KEYS={"AssetCategory","PetName","Pet","Animal","Species","DisplayName","AssetName","EggName","Name","Id","ID"}
local function getField(t,names)
    local wanted={}
    for _,n in ipairs(names) do wanted[normalize(n)]=true end
    local n=0
    local k,v=next(t,nil)
    while k~=nil do
        n+=1 if n>260 then break end
        if wanted[normalize(k)] then return v end
        k,v=next(t,k)
    end
end
local function inferIdentity(t,fallback)
    local v=getField(t,ID_KEYS)
    if type(v)=="string" and v~="" and #v<=100 then return v end
    if type(fallback)=="string" and fallback~="" and #fallback<=100 and not tonumber(fallback) then return fallback end
end
local function mergeCatalog(identity,fields,source,path)
    if type(identity)~="string" or identity=="" or #identity>100 then return end
    if not State.Catalog[identity] and countMap(State.Catalog)>=CONFIG.MaxCatalog then return end
    local e=State.Catalog[identity] or {Identity=identity,Fields={},Sources={}}
    State.Catalog[identity]=e
    for k,v in pairs(fields or {}) do
        e.Fields[safeString(k)]=plain(v)
        local nk=normalize(k)
        if (nk:find("rarity",1,true) or nk=="tier" or nk=="grade") and type(v)=="string" and v~="" and #v<=50 then State.RarityNames[v]=true end
    end
    local sk=safeString(source).."|"..safeString(path)
    e.Sources[sk]=e.Sources[sk] or {source=source,path=path}
end
local function directScore(t)
    local score,n=0,0
    local k,v=next(t,nil)
    while k~=nil do
        n+=1 if n>150 then break end
        if relevantKey(k) then score+=((typeof(v)=="string" or typeof(v)=="number" or typeof(v)=="boolean") and 2 or 1) end
        k,v=next(t,k)
    end
    return score
end
local function inspectTree(root,source,evidence)
    if typeof(root)~="table" then return 0 end
    local seen,nodes={},0
    local function walk(t,path,depth,fallback)
        if not State.Alive or typeof(t)~="table" or seen[t] or depth>CONFIG.MaxWalkDepth or nodes>=CONFIG.MaxWalkNodes then return end
        seen[t]=true nodes+=1
        local fields=extractFields(t)
        if next(fields) then
            local id=inferIdentity(t,fallback)
            local sig=source.."|"..path.."|"..safeString(id or "")
            if not State.SeenEvidence[sig] then State.SeenEvidence[sig]=true addLimited(evidence,{source=source,path=path,identity=id,fields=fields}) end
            if id then mergeCatalog(id,fields,source,path) end
        end
        local c=0
        local k,v=next(t,nil)
        while k~=nil do
            c+=1 if c>260 then break end
            if typeof(v)=="table" then walk(v,path.."."..safeString(k),depth+1,safeString(k)) end
            k,v=next(t,k)
        end
        seen[t]=nil
    end
    pcall(walk,root,"$",0,nil)
    return nodes
end

local function visualForUid(uid)
    local folder=Workspace:FindFirstChild("AreaEggSlotsClient")
    if folder then local m=folder:FindFirstChild(uid) if m then return m,"AreaEggSlotsClient" end end
    local direct=Workspace:FindFirstChild(uid)
    if direct then return direct,"Workspace" end
end
local function modelEvidence(uid)
    local m,method=visualForUid(uid)
    if not m then return nil end
    local out={path=fullName(m),method=method,attributes={},values={},texts={}}
    local ok,a=pcall(function() return m:GetAttributes() end)
    if ok then for k,v in pairs(a) do if relevantKey(k) then out.attributes[safeString(k)]=plain(v) end end end
    local n=0
    for _,d in ipairs(m:GetDescendants()) do
        n+=1 if n>450 then break end
        if d:IsA("ValueBase") and relevantKey(d.Name) then
            local vok,val=pcall(function() return d.Value end)
            table.insert(out.values,{path=fullName(d),name=d.Name,value=vok and plain(val) or "<read-failed>"})
        elseif d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox") then
            local text=safeString(d.Text or "")
            if text~="" and (containsWord(text,RELEVANT_KEYS) or text:find("%$") or lower(text):find("kg",1,true)) then table.insert(out.texts,{path=fullName(d),name=d.Name,text=text}) end
        end
    end
    return out
end

local statusLabel
local function refreshStatus(extra)
    if not statusLabel then return end
    statusLabel.Text=string.format(
        "Ninhos: %d | Catálogo: %d | Raridades: %d\nMemória ovos: %d | Memória catálogo: %d | Constantes: %d%s",
        countMap(State.Eggs),countMap(State.Catalog),countMap(State.RarityNames),
        State.Stats.MemoryEggRecords or 0,#State.GcEvidence,#State.ConstantEvidence,
        extra and ("\n"..extra) or ""
    )
end

local function copyMutations(v)
    local out={}
    if typeof(v)=="table" then for _,m in pairs(v) do table.insert(out,safeString(m)) end table.sort(out) end
    return out
end
local function makeEgg(record,source)
    local uid=safeString(record.Uid)
    local category=safeString(record.AssetCategory or "Unknown")
    local known=State.RarityCatalog[category]
    local old=State.Eggs[uid]
    local fields=extractFields(record)
    local e={
        Uid=uid,State="Slot",Source=source or "record",NestId=record.NestId,AreaId=record.AreaId,
        AssetCategory=record.AssetCategory,PetOrAsset=record.AssetCategory,
        DisplayName=record.DisplayName or (known and known.DisplayName) or nil,
        Rarity=record.Rarity or (known and known.Rarity) or nil,
        NestScale=record.NestScale,AssetScale=record.AssetScale,BoundsSize=plain(record.BoundsSize),BoundsCFrame=plain(record.BoundsCFrame),BottomCFrame=plain(record.BottomCFrame),
        BaseMutation=record.BaseMutation,Mutations=copyMutations(record.Mutations),HasParasite=record.HasParasite==true,
        ServerFields=fields,VisualEvidence=modelEvidence(uid),FirstSeen=old and old.FirstSeen or elapsed(),LastSeen=elapsed()
    }
    mergeCatalog(category,fields,"FieldEggRecord",uid)
    if e.Rarity then State.RarityNames[e.Rarity]=true end
    return e
end
local function ingestRecord(record,source)
    if typeof(record)~="table" or type(record.Uid)~="string" then return false end
    if record.State=="Slot" then State.Eggs[record.Uid]=makeEgg(record,source) return true end
    return false
end
local function removeEgg(uid,reason)
    if type(uid)=="string" and State.Eggs[uid] then
        local old=State.Eggs[uid]
        State.Eggs[uid]=nil
        addEvent("slot_removed",{Uid=uid,AssetCategory=old.AssetCategory,Reason=reason})
        refreshStatus()
    end
end
local function onBatch(p)
    if typeof(p)~="table" then return end
    if typeof(p.RemovedUids)=="table" then for _,u in pairs(p.RemovedUids) do removeEgg(u,"batch_removed") end end
    if typeof(p.UpdatedRecords)=="table" then for _,r in pairs(p.UpdatedRecords) do ingestRecord(r,"batch") end end
    refreshStatus()
end
local function onRedeem(info)
    if typeof(info)~="table" or type(info.AssetCategory)~="string" then return end
    local c=info.AssetCategory
    State.RarityCatalog[c]={AssetCategory=c,Rarity=info.Rarity,DisplayName=info.DisplayName,Color=plain(info.Color),Source="redeem_verdict"}
    if type(info.Rarity)=="string" then State.RarityNames[info.Rarity]=true end
    mergeCatalog(c,extractFields(info),"FieldEggRedeemVerdict",c)
    for _,e in pairs(State.Eggs) do if e.AssetCategory==c then e.Rarity=info.Rarity or e.Rarity e.DisplayName=info.DisplayName or e.DisplayName end end
    refreshStatus()
end
local function hookRemotes()
    for _,d in ipairs(ReplicatedStorage:GetDescendants()) do
        if d:IsA("RemoteEvent") then
            if d.Name=="RE/EggWorld/FieldEggShifted" then
                connect(d.OnClientEvent,function(r)
                    if typeof(r)=="table" and type(r.Uid)=="string" then
                        if r.State=="Slot" then ingestRecord(r,"shifted") else removeEgg(r.Uid,"state:"..safeString(r.State)) end
                        refreshStatus()
                    end
                end,State.RemoteConnections)
            elseif d.Name=="RE/EggWorld/FieldEggBatchShifted" then connect(d.OnClientEvent,onBatch,State.RemoteConnections)
            elseif d.Name=="RE/EggWorld/FieldEggGone" then connect(d.OnClientEvent,function(uid) removeEgg(uid,"gone") end,State.RemoteConnections)
            elseif d.Name=="RE/EggWorld/FieldEggRedeemVerdict" then connect(d.OnClientEvent,onRedeem,State.RemoteConnections) end
        end
    end
end

local function refreshVisualFallback()
    local folder=Workspace:FindFirstChild("AreaEggSlotsClient")
    if not folder then State.Stats.VisualNestModels=0 return 0 end
    local present,count={},0
    for _,child in ipairs(folder:GetChildren()) do
        if child:IsA("Model") or child:IsA("BasePart") then
            count+=1
            local uid=child.Name
            present[uid]=true
            if not State.Eggs[uid] then
                State.Eggs[uid]={Uid=uid,State="SlotVisual",Source="visual_folder",VisualPath=fullName(child),VisualEvidence=modelEvidence(uid),FirstSeen=elapsed(),LastSeen=elapsed()}
            elseif State.Eggs[uid].Source=="visual_folder" then State.Eggs[uid].LastSeen=elapsed() end
        end
    end
    local rm={}
    for uid,e in pairs(State.Eggs) do if e.Source=="visual_folder" and not present[uid] then table.insert(rm,uid) end end
    for _,uid in ipairs(rm) do State.Eggs[uid]=nil end
    State.Stats.VisualNestModels=count
    refreshStatus()
    return count
end
local function findRF(name)
    for _,d in ipairs(ReplicatedStorage:GetDescendants()) do if d:IsA("RemoteFunction") and d.Name==name then return d end end
end
local function ingestTree(v,source,seen,depth)
    if typeof(v)~="table" then return 0 end
    seen=seen or {} depth=depth or 0
    if depth>7 or seen[v] then return 0 end
    seen[v]=true
    local found=0
    if type(v.Uid)=="string" and v.State~=nil then
        if ingestRecord(v,source) then found+=1 end
    else
        local n=0
        local _,child=next(v,nil)
        local k
        k,child=next(v,nil)
        while k~=nil do
            n+=1 if n>1800 then break end
            if typeof(child)=="table" then found+=ingestTree(child,source,seen,depth+1) end
            k,child=next(v,k)
        end
    end
    seen[v]=nil
    return found
end
local function requestSnapshots()
    local total=0
    for _,name in ipairs({"RF/EggWorld/AskFieldEggSnapshot","RF/EggWorld/AskLiveSnapshot"}) do
        local rf=findRF(name)
        if rf then
            State.Stats.SnapshotRequests+=1
            local ok,res=pcall(function() return rf:InvokeServer() end)
            if ok then
                State.Stats.SnapshotSuccesses+=1
                local n=ingestTree(res,"snapshot:"..name)
                total+=n
                addEvent("snapshot",{name=name,records=n,resultType=typeof(res)})
            else addEvent("snapshot_error",{name=name,error=safeString(res)}) end
        end
    end
    State.Stats.SnapshotRecords=total
    return total
end
local function scanMemoryForExistingEggs()
    if type(getgc)~="function" then State.Stats.GetGcAvailable=false return 0 end
    State.Stats.GetGcAvailable=true
    local ok,objects=pcall(getgc,true)
    if not ok or type(objects)~="table" then return 0 end
    local found,scanned=0,0
    local seenUid={}
    for _,obj in ipairs(objects) do
        scanned+=1
        if scanned>CONFIG.MaxGcObjects or found>=CONFIG.MaxGcEggRecords then break end
        if typeof(obj)=="table" then
            local uid,state
            pcall(function() uid=rawget(obj,"Uid") or rawget(obj,"UID") or rawget(obj,"uid") state=rawget(obj,"State") or rawget(obj,"state") end)
            if type(uid)=="string" and state=="Slot" and not seenUid[uid] then
                seenUid[uid]=true
                if ingestRecord(obj,"memory_existing") then found+=1 end
            end
        end
    end
    State.Stats.GcObjectsScanned=scanned
    State.Stats.MemoryEggRecords=found
    return found
end
local function scanReplicated()
    State.ReplicatedEvidence={}
    local n=0
    for _,d in ipairs(ReplicatedStorage:GetDescendants()) do
        n+=1 if n>32000 then break end
        local p=fullName(d)
        if containsWord(p,TOPIC_WORDS) then
            local rec
            if d:IsA("ValueBase") and relevantKey(d.Name) then
                local ok,v=pcall(function() return d.Value end)
                rec={path=p,class=d.ClassName,name=d.Name,value=ok and plain(v) or "<read-failed>"}
            else
                local ok,a=pcall(function() return d:GetAttributes() end)
                if ok then
                    local r={}
                    for k,v in pairs(a) do if relevantKey(k) then r[safeString(k)]=plain(v) end end
                    if next(r) then rec={path=p,class=d.ClassName,name=d.Name,attributes=r} end
                end
            end
            if rec then addLimited(State.ReplicatedEvidence,rec) end
        end
    end
    State.Stats.ReplicatedDescendantsScanned=n
end
local function scanLoadedModules()
    State.LoadedModuleEvidence={}
    if type(getloadedmodules)~="function" then State.Stats.LoadedModulesAvailable=false return end
    State.Stats.LoadedModulesAvailable=true
    local ok,list=pcall(getloadedmodules)
    if not ok or type(list)~="table" then return end
    local inspected=0
    for _,m in ipairs(list) do
        if inspected>=350 then break end
        if typeof(m)=="Instance" and m:IsA("ModuleScript") then
            local p=fullName(m)
            if containsWord(p,TOPIC_WORDS) then
                inspected+=1
                local rok,res=pcall(require,m)
                if rok and typeof(res)=="table" then inspectTree(res,"LoadedModule:"..p,State.LoadedModuleEvidence) end
            end
        end
    end
    State.Stats.LoadedModulesTotal=#list
    State.Stats.LoadedModulesInspected=inspected
end
local function scanGcCatalog()
    State.GcEvidence={}
    if type(getgc)~="function" then return end
    local ok,objects=pcall(getgc,true)
    if not ok or type(objects)~="table" then return end
    local roots,scanned=0,0
    for _,obj in ipairs(objects) do
        scanned+=1
        if scanned>CONFIG.MaxGcObjects or roots>=CONFIG.MaxGcCatalogRoots then break end
        if typeof(obj)=="table" then
            local score=0
            local sok,s=pcall(directScore,obj)
            if sok then score=s end
            if score>=3 then roots+=1 inspectTree(obj,"GC:"..roots,State.GcEvidence) end
        end
    end
    State.Stats.GcCatalogRoots=roots
end
local function scanConstants()
    State.ConstantEvidence={}
    local getconst=(debug and type(debug.getconstants)=="function" and debug.getconstants) or (type(getconstants)=="function" and getconstants)
    if type(getscriptclosure)~="function" or type(getconst)~="function" then State.Stats.ConstantScannerAvailable=false return end
    State.Stats.ConstantScannerAvailable=true
    local modules=0
    for _,m in ipairs(ReplicatedStorage:GetDescendants()) do
        if m:IsA("ModuleScript") and containsWord(fullName(m),TOPIC_WORDS) then
            modules+=1 if modules>280 then break end
            local ok,fn=pcall(getscriptclosure,m)
            if ok and typeof(fn)=="function" then
                local cok,consts=pcall(getconst,fn)
                if cok and type(consts)=="table" then
                    local kept={}
                    for _,v in pairs(consts) do
                        if type(v)=="string" and #v>0 and #v<=100 and containsWord(v,RELEVANT_KEYS) then table.insert(kept,v)
                        elseif finite(v) then
                            local p=lower(fullName(m))
                            if p:find("weight",1,true) or p:find("price",1,true) or p:find("value",1,true) then table.insert(kept,v) end
                        end
                        if #kept>=CONFIG.MaxConstants then break end
                    end
                    if #kept>0 then addLimited(State.ConstantEvidence,{module=fullName(m),constants=kept}) end
                end
            end
        end
    end
    State.Stats.ConstantModulesScanned=modules
end

local scanning=false
local function runScan()
    if scanning then return end
    scanning=true State.ScanRuns+=1
    refreshStatus("D0 | recuperando estado atual...")
    local ok,err=pcall(function()
        refreshVisualFallback()
        requestSnapshots()
        scanMemoryForExistingEggs()
        refreshVisualFallback()
        scanReplicated()
        scanLoadedModules()
        scanGcCatalog()
        scanConstants()
        refreshVisualFallback()
        for _,e in pairs(State.Eggs) do e.VisualEvidence=modelEvidence(e.Uid) e.LastMetadataScan=elapsed() end
    end)
    scanning=false
    if ok then
        addEvent("scan_complete",{run=State.ScanRuns,nests=countMap(State.Eggs),catalog=countMap(State.Catalog),rarities=countMap(State.RarityNames)})
        State.LastDiag="D0"
        refreshStatus("D0 | varredura concluída")
    else
        State.LastDiag="ES01"
        addEvent("scan_error",{error=safeString(err)})
        refreshStatus("ES01 | scan | "..safeString(err):sub(1,44))
    end
end

local function report()
    local rarities={}
    for r in pairs(State.RarityNames) do table.insert(rarities,r) end
    table.sort(rarities)
    local candidates={}
    for n,s in pairs(State.RarityCandidates) do table.insert(candidates,{name=n,source=s}) end
    table.sort(candidates,function(a,b) return safeString(a.name)<safeString(b.name) end)
    return {
        Version="Static Egg Catalog Scanner V6.3",
        Meta={PlaceId=game.PlaceId,GameId=game.GameId,JobId=game.JobId,StartedUnix=startedUnix,FinishedUnix=os.time(),DurationSeconds=elapsed(),InteractionRequired=false,Notes="Pre-existing Slot eggs + client static catalog; export has native and custom JSON fallback."},
        Stats=State.Stats,CurrentNestEggs=State.Eggs,StaticCatalog=State.Catalog,ConfirmedRarityCatalog=State.RarityCatalog,
        RarityNames=rarities,RarityCandidates=candidates,LoadedModuleEvidence=State.LoadedModuleEvidence,GcEvidence=State.GcEvidence,
        ConstantEvidence=State.ConstantEvidence,ReplicatedEvidence=State.ReplicatedEvidence,Events=State.Events,
    }
end

-- Strict sanitization for Roblox HttpService:JSONEncode.
local function sanitize(v,depth,seen)
    depth=depth or 0
    seen=seen or {}
    if depth>CONFIG.JsonDepth then return "<max-depth>" end
    local t=typeof(v)
    if t=="nil" then return nil end
    if t=="boolean" then return v end
    if t=="number" then return finite(v) and v or asciiSafe(v) end
    if t=="string" then return asciiSafe(v) end
    if t=="Vector3" then return {x=v.X,y=v.Y,z=v.Z} end
    if t=="Vector2" then return {x=v.X,y=v.Y} end
    if t=="Color3" then return {r=v.R,g=v.G,b=v.B} end
    if t=="CFrame" then local p=v.Position return {x=p.X,y=p.Y,z=p.Z} end
    if t=="UDim" then return {scale=v.Scale,offset=v.Offset} end
    if t=="UDim2" then return {x={scale=v.X.Scale,offset=v.X.Offset},y={scale=v.Y.Scale,offset=v.Y.Offset}} end
    if t=="EnumItem" then return asciiSafe(v) end
    if t=="Instance" then return {name=asciiSafe(v.Name),class=asciiSafe(v.ClassName),path=asciiSafe(fullName(v))} end
    if t~="table" then return "<"..asciiSafe(t).."> "..asciiSafe(v) end
    if seen[v] then return "<cycle>" end
    seen[v]=true

    local total,numeric,maxIndex=0,0,0
    local k,val=next(v,nil)
    while k~=nil do
        total+=1
        if type(k)=="number" and k>=1 and k%1==0 then numeric+=1 if k>maxIndex then maxIndex=k end end
        if total>CONFIG.JsonEntries then break end
        k,val=next(v,k)
    end
    local dense=total>0 and total==numeric and maxIndex==total
    local out={}
    if dense then
        for i=1,total do out[i]=sanitize(v[i],depth+1,seen) end
    else
        local count=0
        k,val=next(v,nil)
        while k~=nil do
            count+=1
            if count>CONFIG.JsonEntries then out["<truncated>"]=true break end
            out[asciiSafe(k)]=sanitize(val,depth+1,seen)
            k,val=next(v,k)
        end
    end
    seen[v]=nil
    return out
end

local function diagnoseNative(clean)
    local bad={}
    for _,key in ipairs({"Meta","Stats","CurrentNestEggs","StaticCatalog","ConfirmedRarityCatalog","RarityNames","RarityCandidates","LoadedModuleEvidence","GcEvidence","ConstantEvidence","ReplicatedEvidence","Events"}) do
        local ok=pcall(HttpService.JSONEncode,HttpService,clean[key])
        if not ok then table.insert(bad,key) end
    end
    return #bad>0 and table.concat(bad,",") or "FULL_ONLY"
end

local function customEscape(s)
    s=asciiSafe(s)
    s=s:gsub("\\","\\\\"):gsub('"','\\"'):gsub("\b","\\b"):gsub("\f","\\f"):gsub("\n","\\n"):gsub("\r","\\r"):gsub("\t","\\t")
    return '"'..s..'"'
end
local function customJson(v,depth,seen)
    depth=depth or 0
    seen=seen or {}
    if depth>CONFIG.JsonDepth+2 then return customEscape("<max-depth>") end
    local t=type(v)
    if v==nil then return "null" end
    if t=="boolean" then return v and "true" or "false" end
    if t=="number" then return finite(v) and tostring(v) or customEscape(v) end
    if t=="string" then return customEscape(v) end
    if t~="table" then return customEscape(v) end
    if seen[v] then return customEscape("<cycle>") end
    seen[v]=true

    local total,numeric,maxIndex=0,0,0
    local k,val=next(v,nil)
    while k~=nil do
        total+=1
        if type(k)=="number" and k>=1 and k%1==0 then numeric+=1 if k>maxIndex then maxIndex=k end end
        if total>CONFIG.JsonEntries then break end
        k,val=next(v,k)
    end
    local dense=total>0 and total==numeric and maxIndex==total
    local parts={}
    if dense then
        for i=1,total do parts[#parts+1]=customJson(v[i],depth+1,seen) end
        seen[v]=nil
        return "["..table.concat(parts,",").."]"
    end
    local count=0
    k,val=next(v,nil)
    while k~=nil do
        count+=1
        if count>CONFIG.JsonEntries then parts[#parts+1]=customEscape("<truncated>")..":true" break end
        parts[#parts+1]=customEscape(k)..":"..customJson(val,depth+1,seen)
        k,val=next(v,k)
    end
    seen[v]=nil
    return "{"..table.concat(parts,",").."}"
end

local function exportReport()
    refreshVisualFallback()

    local okReport,raw=pcall(report)
    if not okReport then State.LastDiag="EJ01" return false,"EJ01 | report | "..safeString(raw):sub(1,42) end

    local okSan,clean=pcall(sanitize,raw)
    if not okSan then State.LastDiag="EJ02" return false,"EJ02 | sanitize | "..safeString(clean):sub(1,40) end

    local nativeOk,encoded=pcall(HttpService.JSONEncode,HttpService,clean)
    local diag="J0"
    if not nativeOk then
        local bad=diagnoseNative(clean)
        State.Stats.NativeJsonError=asciiSafe(encoded)
        State.Stats.NativeJsonBadSection=bad
        local fallbackOk,fallback=pcall(customJson,clean)
        if not fallbackOk then State.LastDiag="EJ03" return false,"EJ03 | fallback | "..safeString(fallback):sub(1,38) end
        encoded=fallback
        diag="J1:"..bad
    end

    local name="Psico_RoubeUmOvo_StaticCatalog_"..os.time()..".json"
    if writefile then
        local wok,e=pcall(writefile,name,encoded)
        if wok then
            State.LastDiag=diag
            return true,diag.." | salvo | "..math.floor(#encoded/1024).."KB"
        end
        State.LastDiag="EW01"
        return false,"EW01 | writefile | "..safeString(e):sub(1,38)
    end
    if setclipboard then
        local cok,e=pcall(setclipboard,encoded)
        if cok then State.LastDiag=diag return true,diag.." | JSON copiado" end
        State.LastDiag="EC01"
        return false,"EC01 | clipboard | "..safeString(e):sub(1,38)
    end
    State.LastDiag="EO01"
    return false,"EO01 | sem writefile/setclipboard"
end

hookRemotes()
refreshVisualFallback()
task.defer(function() task.wait(.8) if State.Alive then runScan() end end)
task.defer(function() while State.Alive do task.wait(1.5) pcall(refreshVisualFallback) end end)

local function parentGui()
    local ok,h=pcall(function() if gethui then return gethui() end end)
    return (ok and h) or CoreGui
end
local old=parentGui():FindFirstChild("PsicoStaticEggScannerV6")
if old then old:Destroy() end
local gui=Instance.new("ScreenGui")
gui.Name="PsicoStaticEggScannerV6" gui.ResetOnSpawn=false gui.IgnoreGuiInset=true gui.Parent=parentGui()
local frame=Instance.new("Frame")
frame.AnchorPoint=Vector2.new(.5,.5) frame.Position=UDim2.fromScale(.5,.5) frame.Size=UDim2.fromOffset(316,226)
frame.BackgroundColor3=Color3.fromRGB(15,21,33) frame.BorderSizePixel=0 frame.Parent=gui
Instance.new("UICorner",frame).CornerRadius=UDim.new(0,12)
local stroke=Instance.new("UIStroke",frame) stroke.Thickness=1 stroke.Transparency=.3 stroke.Color=Color3.fromRGB(73,126,230)
local title=Instance.new("TextLabel")
title.BackgroundTransparency=1 title.Position=UDim2.fromOffset(12,8) title.Size=UDim2.new(1,-52,0,25)
title.Font=Enum.Font.GothamBold title.Text="EGG CATALOG SCANNER • V6.3" title.TextColor3=Color3.fromRGB(241,245,255) title.TextSize=13 title.TextXAlignment=Enum.TextXAlignment.Left title.Parent=frame
local close=Instance.new("TextButton")
close.AnchorPoint=Vector2.new(1,0) close.Position=UDim2.new(1,-8,0,7) close.Size=UDim2.fromOffset(28,28)
close.BackgroundColor3=Color3.fromRGB(32,42,60) close.BorderSizePixel=0 close.Font=Enum.Font.GothamBold close.Text="×" close.TextColor3=Color3.fromRGB(240,244,255) close.TextSize=15 close.Parent=frame
Instance.new("UICorner",close).CornerRadius=UDim.new(0,8)
statusLabel=Instance.new("TextLabel")
statusLabel.Position=UDim2.fromOffset(12,43) statusLabel.Size=UDim2.new(1,-24,0,78) statusLabel.BackgroundColor3=Color3.fromRGB(21,29,44)
statusLabel.BorderSizePixel=0 statusLabel.Font=Enum.Font.Code statusLabel.TextColor3=Color3.fromRGB(174,198,241) statusLabel.TextSize=9 statusLabel.TextWrapped=true statusLabel.Parent=frame
Instance.new("UICorner",statusLabel).CornerRadius=UDim.new(0,9)
local rescan=Instance.new("TextButton")
rescan.Position=UDim2.fromOffset(12,131) rescan.Size=UDim2.new(.5,-17,0,36) rescan.BackgroundColor3=Color3.fromRGB(31,55,100) rescan.BorderSizePixel=0 rescan.Font=Enum.Font.GothamMedium rescan.Text="Revarrer memória" rescan.TextColor3=Color3.fromRGB(240,244,255) rescan.TextSize=11 rescan.Parent=frame
Instance.new("UICorner",rescan).CornerRadius=UDim.new(0,9)
local export=Instance.new("TextButton")
export.Position=UDim2.new(.5,5,0,131) export.Size=UDim2.new(.5,-17,0,36) export.BackgroundColor3=Color3.fromRGB(37,82,170) export.BorderSizePixel=0 export.Font=Enum.Font.GothamMedium export.Text="Exportar JSON" export.TextColor3=Color3.fromRGB(245,248,255) export.TextSize=11 export.Parent=frame
Instance.new("UICorner",export).CornerRadius=UDim.new(0,9)
local hint=Instance.new("TextLabel")
hint.BackgroundTransparency=1 hint.Position=UDim2.fromOffset(12,176) hint.Size=UDim2.new(1,-24,0,38) hint.Font=Enum.Font.Gotham
hint.Text="Se falhar, envie print com o código EJ/EW/EC/EO mostrado na linha final." hint.TextColor3=Color3.fromRGB(151,163,188) hint.TextSize=9 hint.TextWrapped=true hint.Parent=frame

local drag=false local dragInput,dragStart,startPos
connect(frame.InputBegan,function(input) if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1 then drag=true dragStart=input.Position startPos=frame.Position end end)
connect(frame.InputChanged,function(input) if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseMovement then dragInput=input end end)
connect(UIS.InputChanged,function(input) if drag and input==dragInput then local d=input.Position-dragStart frame.Position=UDim2.new(startPos.X.Scale,startPos.X.Offset+d.X,startPos.Y.Scale,startPos.Y.Offset+d.Y) end end)
connect(UIS.InputEnded,function(input) if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1 then drag=false end end)
connect(rescan.MouseButton1Click,function() task.defer(runScan) end)
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
refreshStatus("D0 | recuperando ovos que já estavam no mapa...")
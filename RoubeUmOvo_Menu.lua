--[[
PSICOSENATICO | Roube um Ovo - Precision Menu V8.2.1
Stable loader path: RoubeUmOvo_Menu.lua

- ESP por rendimento do pet ($/s) com filtro K/M/B/T.
- Valor do ovo e peso opcionais.
- Risco de fuga usa GuardEscapePrediction/GuardEscapeRequirement.
- Boost atual entra automaticamente no calculo de risco.
- Filtros removem somente ESP; nunca o modelo real do ovo.
]]

if _G.PSICO_ROUBE_SCANNER_CLEANUP then pcall(_G.PSICO_ROUBE_SCANNER_CLEANUP) end
if _G.PSICO_ROUBE_MENU_CLEANUP then pcall(_G.PSICO_ROUBE_MENU_CLEANUP) end

local Players=game:GetService("Players")
local Workspace=game:GetService("Workspace")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local CoreGui=game:GetService("CoreGui")
local UIS=game:GetService("UserInputService")
local LP=Players.LocalPlayer

local CONFIG={
    EggESP=true,
    InstantPrompt=true,
    InstantHit=true,
    MinRarity=0,
    MinEarnings=0,
    MinSellPrice=0,
    SelectedPet="",
    MutationMode="Todas",
    PetListAvailableOnly=false,
    ShowEarnings=true,
    ShowEggValue=false,
    ShowWeight=false,
    ShowRisk=true,
    BoostAuto=true,
    MaxEspDistance=10000,
}

local RARITY_ORDER={
    "Common","Uncommon","Rare","Epic","Legendary",
    "Mythic","Cosmic","Secret","Eternal","Divine"
}

local State={
    Alive=true,
    Connections={},
    RemoteConnections={},
    Eggs={},
    CatalogIndex={},
    CatalogEntries={},
    MutationScalars={},
    ESP={},
    PromptOriginals=setmetatable({}, {__mode="k"}),
    BatOriginals=setmetatable({}, {__mode="k"}),
    WatchedBats=setmetatable({}, {__mode="k"}),
    AreaParams={},
    CarryMultiplier=1,
    Stats={EspVisible=0,CatalogPets=0},
}

local AssetsData
local EggRecords
local AssetEarnings
local MutationCatalog
local GuardEscapePrediction
local GuardEscapeRequirement
local TreadmillUtil
local SpeedPowerProjection

local gui,mainFrame,uiScale,floatButton
local statusLabel,liveInfoLabel
local rarityButton,mutationButton,petButton,availabilityButton
local espToggleButton,promptToggleButton,hitToggleButton
local petModal,petSearchBox,petList

local function safeString(v)
    local ok,s=pcall(tostring,v)
    return ok and s or "?"
end

local function lower(v)
    return string.lower(safeString(v or ""))
end

local function normalize(v)
    return lower(v):gsub("[%s_%-%.:/%[%]%(%)']","")
end

local function finite(v)
    return type(v)=="number" and v==v and v~=math.huge and v~=-math.huge
end

local function connect(signal,fn,bucket)
    local c=signal:Connect(fn)
    table.insert(bucket or State.Connections,c)
    return c
end

local function disconnect(c)
    pcall(function() c:Disconnect() end)
end

local function uiParent()
    local ok,h=pcall(function() if gethui then return gethui() end end)
    return (ok and h) or CoreGui
end

local function findPath(root,pathText)
    local cur=root
    for token in string.gmatch(pathText,"[^%.]+") do
        if not cur then return nil end
        cur=cur:FindFirstChild(token)
    end
    return cur
end

local function findExact(className,name)
    for _,d in ipairs(ReplicatedStorage:GetDescendants()) do
        if d.ClassName==className and d.Name==name then return d end
    end
end

local function requireOptional(pathText)
    local m=findPath(ReplicatedStorage,pathText)
    if not (m and m:IsA("ModuleScript")) then return nil end
    local ok,v=pcall(require,m)
    return ok and v or nil
end

local function callTableFn(tbl,name,...)
    if typeof(tbl)~="table" or type(tbl[name])~="function" then return nil,false end
    local fn=tbl[name]
    local ok,v=pcall(fn,...)
    if ok then return v,true end
    ok,v=pcall(fn,tbl,...)
    return ok and v or nil,ok
end

local function formatCompact(n)
    if not finite(n) then return "?" end
    local a=math.abs(n)
    if a>=1e12 then return string.format("%.2fT",n/1e12):gsub("%.?0+T$","T") end
    if a>=1e9 then return string.format("%.2fB",n/1e9):gsub("%.?0+B$","B") end
    if a>=1e6 then return string.format("%.2fM",n/1e6):gsub("%.?0+M$","M") end
    if a>=1e3 then return string.format("%.1fK",n/1e3):gsub("%.0K$","K") end
    if a>=100 then return tostring(math.floor(n+0.5)) end
    return string.format("%.1f",n):gsub("%.0$","")
end

local function parseSmartNumber(text)
    local s=string.upper(safeString(text or ""))
    s=s:gsub("%s+",""):gsub("%$",""):gsub("/S",""):gsub("KG","")
    if s=="" then return 0 end
    local suffix=s:match("([KMBT])$")
    if suffix then s=s:sub(1,-2) end
    s=s:gsub(",",".")
    local n=tonumber(s)
    if not n then return 0 end
    local mult={K=1e3,M=1e6,B=1e9,T=1e12}
    if suffix then n=n*(mult[suffix] or 1) end
    if not finite(n) or n<0 then return 0 end
    return n
end

local function rarityFallbackColor(rarity)
    local map={
        Common=Color3.fromRGB(210,210,210),Uncommon=Color3.fromRGB(91,210,116),
        Rare=Color3.fromRGB(77,151,255),Epic=Color3.fromRGB(181,91,255),
        Legendary=Color3.fromRGB(255,174,58),Mythic=Color3.fromRGB(255,71,121),
        Cosmic=Color3.fromRGB(150,67,255),Secret=Color3.fromRGB(245,245,245),
        Eternal=Color3.fromRGB(245,71,255),Divine=Color3.fromRGB(52,255,238),
    }
    return map[rarity] or Color3.fromRGB(230,235,255)
end

local function copyMutations(v)
    local out,seen={},{}
    if typeof(v)=="table" then
        for _,m in pairs(v) do
            local s=safeString(m)
            local k=normalize(s)
            if k~="" and not seen[k] then
                seen[k]=true
                out[#out+1]=s
            end
        end
    end
    table.sort(out)
    return out
end

local function indexMutationScalars()
    State.MutationScalars={
        silver=1.2,golden=2.5,rainbow=3.5,sakura=1.25,boss=2.75,
        monstrous=3,greatbloom=2.5,fractured=2.75,parasite=3,bloom=1.25,spiritbloom=2.5,
    }
    if typeof(MutationCatalog)~="table" then return end
    local seen={}
    local function walk(t,depth)
        if depth>4 or seen[t] then return end
        seen[t]=true
        for k,v in pairs(t) do
            if typeof(v)=="table" then
                local scalar=tonumber(v.EarningsScalar)
                if scalar then
                    for _,name in ipairs({k,v._id,v.Id,v.Name,v.DisplayName,v.EggDisplayName,v.EggModelName}) do
                        if name~=nil then State.MutationScalars[normalize(name)]=scalar end
                    end
                end
                walk(v,depth+1)
            end
        end
    end
    walk(MutationCatalog,0)
end

local function resolveModules()
    AssetsData=requireOptional("Data.Assets")
    EggRecords=requireOptional("Shared.Util.EggRecords")
    if typeof(AssetsData)~="table" then return false,"Data.Assets ausente" end
    if typeof(EggRecords)~="table" then return false,"EggRecords ausente" end
    AssetEarnings=requireOptional("Shared.Util.AssetEarnings")
    MutationCatalog=requireOptional("Shared.Modules.Mutations.Catalog")
    GuardEscapePrediction=requireOptional("Shared.Modules.GuardAreas.GuardEscapePrediction")
    GuardEscapeRequirement=requireOptional("Shared.Modules.GuardAreas.GuardEscapeRequirement")
    TreadmillUtil=requireOptional("Shared.Util.TreadmillUtil")
    SpeedPowerProjection=requireOptional("Client.SpeedPowerProjection")
    indexMutationScalars()
    return true
end

local function indexEntry(key,cfg)
    if typeof(cfg)~="table" or typeof(cfg.Rarity)~="table" then return false end
    local entry={
        Key=safeString(key),
        PetName=cfg.DisplayName or safeString(key),
        Rarity=cfg.Rarity.DisplayName or cfg.Rarity._id,
        RarityNumber=cfg.Rarity.RarityNumber,
        RarityColor=cfg.Rarity.Color,
        EarningRate=tonumber(cfg.EarningRate),
    }
    for _,name in ipairs({entry.Key,entry.PetName}) do
        if type(name)=="string" and name~="" then State.CatalogIndex[normalize(name)]=entry end
    end
    if typeof(cfg.Egg)=="table" and type(cfg.Egg.DisplayName)=="string" then
        State.CatalogIndex[normalize(cfg.Egg.DisplayName)]=entry
        State.CatalogIndex[normalize(cfg.Egg.DisplayName:gsub("%s+[Ee][Gg][Gg]$",""))]=entry
    end
    State.CatalogEntries[#State.CatalogEntries+1]=entry
    return true
end

local function buildCatalog()
    State.CatalogIndex={}
    State.CatalogEntries={}
    local found=0
    if typeof(AssetsData.ByRarity)=="table" then
        for _,group in pairs(AssetsData.ByRarity) do
            if typeof(group)=="table" then
                for key,cfg in pairs(group) do if indexEntry(key,cfg) then found=found+1 end end
            end
        end
    end
    if found==0 and typeof(AssetsData.Configs)=="table" then
        for key,cfg in pairs(AssetsData.Configs) do if indexEntry(key,cfg) then found=found+1 end end
    end
    table.sort(State.CatalogEntries,function(a,b)
        local ar,br=tonumber(a.RarityNumber) or 999,tonumber(b.RarityNumber) or 999
        if ar==br then return safeString(a.PetName)<safeString(b.PetName) end
        return ar<br
    end)
    State.Stats.CatalogPets=found
    return found>0
end

local function findCatalog(category)
    if type(category)~="string" then return nil end
    return State.CatalogIndex[normalize(category)]
end

local function validEggState(state)
    return state=="Slot" or state=="Dropped"
end

local function visualForUid(uid)
    local folder=Workspace:FindFirstChild("AreaEggSlotsClient")
    if folder then
        local model=folder:FindFirstChild(uid)
        if model then return model end
    end
    return Workspace:FindFirstChild(uid)
end

local function getAdornee(root)
    if not root then return nil end
    if root:IsA("BasePart") then return root end
    if root:IsA("Model") then return root.PrimaryPart or root:FindFirstChildWhichIsA("BasePart",true) end
    return root:FindFirstChildWhichIsA("BasePart",true)
end

local function visualPosition(visual)
    if not visual then return nil end
    if visual:IsA("BasePart") then return visual.Position end
    if visual:IsA("Model") then
        local ok,cf=pcall(visual.GetPivot,visual)
        if ok then return cf.Position end
    end
    local p=visual:FindFirstChildWhichIsA("BasePart",true)
    return p and p.Position or nil
end

local function boundsMagnitude(v)
    if typeof(v)=="Vector3" then return v.Magnitude end
    if typeof(v)=="table" then
        local x,y,z=tonumber(v.X or v.x),tonumber(v.Y or v.y),tonumber(v.Z or v.z)
        if x and y and z then return math.sqrt(x*x+y*y+z*z) end
    end
    return nil
end

local function estimateCarryMultiplier(record)
    local mag=boundsMagnitude(record.BoundsSize)
    if not finite(mag) then return nil end
    return math.clamp(1.0000706-(0.0079809*mag),0.55,0.96)
end

local function mutationFactor(record)
    local factor=1
    local seen={}
    local function add(name)
        if name==nil then return end
        local k=normalize(name)
        if k=="" or seen[k] then return end
        seen[k]=true
        local scalar=State.MutationScalars[k]
        if finite(scalar) then factor=factor+math.max(0,scalar-1) end
    end
    add(record.BaseMutation)
    if typeof(record.Mutations)=="table" then for _,m in pairs(record.Mutations) do add(m) end end
    if record.HasParasite==true then add("Parasite") end
    return factor
end

local function fallbackEarnings(record,cfg)
    local base=cfg and tonumber(cfg.EarningRate)
    local scale=tonumber(record.AssetScale or record.Scale)
    if not (finite(base) and finite(scale) and scale>0) then return nil end
    local sizeFactor=scale<=5 and scale^1.85 or (5^1.85)*((scale/5)^1.2)
    return math.floor(base*sizeFactor*mutationFactor(record)+0.5)
end

local function resolveEarnings(record,cfg)
    if typeof(AssetEarnings)=="table" and type(AssetEarnings.MutationOnlyRatePerSecond)=="function" then
        local probe={}
        for k,v in pairs(record) do probe[k]=v end
        probe.Scale=probe.Scale or probe.AssetScale
        probe.Category=probe.Category or probe.AssetCategory
        probe.ItemType=probe.ItemType or "Asset"
        if cfg then probe.DisplayName=probe.DisplayName or cfg.PetName end
        local v,ok=callTableFn(AssetEarnings,"MutationOnlyRatePerSecond",probe)
        v=tonumber(v)
        if ok and finite(v) and v>=0 then return math.floor(v+0.5) end
    end
    return fallbackEarnings(record,cfg)
end

local function enrichRecord(record)
    if typeof(record)~="table" or type(record.Uid)~="string" or not validEggState(record.State) then return false end
    local cfg=findCatalog(record.AssetCategory)
    local weight,wok=callTableFn(EggRecords,"WeightKg",record)
    local weightLabel,lok=callTableFn(EggRecords,"WeightLabel",record)
    local sell,sok=callTableFn(EggRecords,"SellPrice",record)
    State.Eggs[record.Uid]={
        Uid=record.Uid,
        State=record.State,
        AreaId=record.AreaId,
        AssetCategory=record.AssetCategory,
        Mutations=copyMutations(record.Mutations),
        HasParasite=record.HasParasite==true,
        PetName=cfg and cfg.PetName or record.AssetCategory,
        Rarity=cfg and cfg.Rarity or record.Rarity,
        RarityNumber=cfg and cfg.RarityNumber or nil,
        RarityColor=cfg and cfg.RarityColor or nil,
        EarningsPerSecond=resolveEarnings(record,cfg),
        WeightKg=(wok and finite(tonumber(weight))) and tonumber(weight) or nil,
        WeightLabel=lok and safeString(weightLabel) or nil,
        SellPrice=(sok and finite(tonumber(sell))) and tonumber(sell) or nil,
        CarryMultiplierEstimate=estimateCarryMultiplier(record),
    }
    return true
end

local function removeEgg(uid)
    if type(uid)=="string" then State.Eggs[uid]=nil end
end

local function ingestTree(value,seen,depth)
    if typeof(value)~="table" then return 0 end
    seen=seen or {}
    depth=depth or 0
    if depth>8 or seen[value] then return 0 end
    seen[value]=true
    local found=0
    if type(value.Uid)=="string" and value.State~=nil then
        if validEggState(value.State) then
            if enrichRecord(value) then found=1 end
        else
            removeEgg(value.Uid)
        end
    else
        local n=0
        for _,child in pairs(value) do
            n=n+1
            if n>2200 then break end
            if typeof(child)=="table" then found=found+ingestTree(child,seen,depth+1) end
        end
    end
    seen[value]=nil
    return found
end

local function requestSnapshots()
    local total=0
    for _,name in ipairs({"RF/EggWorld/AskFieldEggSnapshot","RF/EggWorld/AskLiveSnapshot"}) do
        local rf=findExact("RemoteFunction",name)
        if rf then
            local ok,res=pcall(function() return rf:InvokeServer() end)
            if ok then total=total+ingestTree(res) end
        end
    end
    return total
end

local function playerHumanoid()
    local c=LP.Character
    return c and c:FindFirstChildOfClass("Humanoid") or nil
end

local function playerRoot()
    local c=LP.Character
    return c and (c:FindFirstChild("HumanoidRootPart") or c.PrimaryPart) or nil
end

local function readSpeedPower()
    local v,ok=callTableFn(SpeedPowerProjection,"ReadProjected")
    v=tonumber(v)
    if ok and finite(v) then return v end
    local ls=LP:FindFirstChild("leaderstats")
    local stat=ls and (ls:FindFirstChild("Speed") or ls:FindFirstChild("SpeedPower"))
    if stat and stat:IsA("ValueBase") and finite(tonumber(stat.Value)) then return tonumber(stat.Value) end
    for _,name in ipairs({"SpeedPower","Speed"}) do
        local a=tonumber(LP:GetAttribute(name))
        if finite(a) then return a end
    end
    return nil
end

local function baseWalkSpeed()
    local p=readSpeedPower()
    if not p then return nil end
    local v,ok=callTableFn(TreadmillUtil,"SpeedPowerToWalkSpeed",p)
    v=tonumber(v)
    return ok and finite(v) and v or nil
end

local function actualFreeWalkSpeed()
    local h=playerHumanoid()
    if not h then return baseWalkSpeed() end
    local w=tonumber(h.WalkSpeed)
    if not finite(w) then return baseWalkSpeed() end
    local cm=tonumber(State.CarryMultiplier) or 1
    if cm>0 and cm<1 then w=w/cm end
    return w
end

local function riskFreeWalkSpeed()
    if CONFIG.BoostAuto then return actualFreeWalkSpeed() end
    return baseWalkSpeed() or actualFreeWalkSpeed()
end

local function currentBoostFactor()
    local base=baseWalkSpeed()
    local free=actualFreeWalkSpeed()
    if finite(base) and base>0 and finite(free) then return free/base end
    return nil
end

local function guardAreaRoot()
    return findPath(Workspace,"__OBJECTS.Areas.GuardAreas")
end

local function separationLine()
    local areas=findPath(Workspace,"__OBJECTS.Areas")
    local p=areas and areas:FindFirstChild("SeparationLine")
    return p and p:IsA("BasePart") and p or nil
end

local function guardPosition(areaModel)
    if not areaModel then return nil end
    local preferred=areaModel:FindFirstChild("Guard") or areaModel:FindFirstChild("ForestGuardAuthored")
    if preferred then
        if preferred:IsA("BasePart") then return preferred.Position end
        if preferred:IsA("Model") then
            local ok,cf=pcall(preferred.GetPivot,preferred)
            if ok then return cf.Position end
        end
    end
    for _,d in ipairs(areaModel:GetDescendants()) do
        if (d.Name=="HumanoidRootPart" or d.Name=="CENTER" or d.Name=="Root") and d:IsA("BasePart") then return d.Position end
    end
    return nil
end

local function basePathParams(areaId)
    if State.AreaParams[areaId] then return State.AreaParams[areaId] end
    if typeof(GuardEscapeRequirement)~="table" then return nil end
    local root=guardAreaRoot()
    local area=root and root:FindFirstChild(areaId)
    local line=separationLine()
    local gpos=guardPosition(area)
    if not (area and line and gpos) then return nil end
    local params,ok=callTableFn(GuardEscapeRequirement,"BuildPathParameters",area,gpos,line)
    if not ok or typeof(params)~="table" then return nil end
    State.AreaParams[areaId]={Area=area,Params=params}
    return State.AreaParams[areaId]
end

local function copyTable(t)
    local o={}
    for k,v in pairs(t or {}) do o[k]=v end
    return o
end

local function resolveRisk(egg,visual)
    if egg.State~="Slot" then return nil end
    local mult=tonumber(egg.CarryMultiplierEstimate)
    local free=riskFreeWalkSpeed()
    if not (finite(mult) and finite(free)) then return nil end
    local cached=basePathParams(egg.AreaId)
    if not cached then return nil end
    local params=copyTable(cached.Params)
    local pos=visualPosition(visual)
    if pos then
        params.PlayerStartPosition=pos
        local bounds=cached.Area:FindFirstChild("Bounds")
        if bounds and bounds:IsA("BasePart") and typeof(GuardEscapePrediction)=="table" then
            local dist,ok=callTableFn(GuardEscapePrediction,"ResolveExitDistance",bounds.CFrame,bounds.Size,pos,params.ExitDirection)
            if ok and finite(tonumber(dist)) then params.ExitDistance=tonumber(dist) end
        end
    end
    params.PlayerWalkSpeed=free*mult
    local result,ok=callTableFn(GuardEscapePrediction,"Resolve",params)
    if ok and typeof(result)=="table" then
        if result.Outcome=="EscapedSafely" then return "Seguro" end
        if result.Outcome=="EscapedAtRisk" then return "Arriscado" end
        if result.Outcome=="Caught" then return "Alto risco" end
    end
    local min,okMin=callTableFn(GuardEscapePrediction,"ResolvePlayerWalkSpeedRequirement",params,1)
    local green,okGreen=callTableFn(GuardEscapePrediction,"ResolveGreenPlayerWalkSpeedRequirement",params)
    min=tonumber(min)
    green=tonumber(green)
    if okMin and finite(min) then
        if params.PlayerWalkSpeed<min then return "Alto risco" end
        if okGreen and finite(green) and params.PlayerWalkSpeed<green then return "Arriscado" end
        return "Seguro"
    end
    return nil
end

local function currentAreaName()
    local root=playerRoot()
    local areas=guardAreaRoot()
    if not (root and areas) then return "?" end
    local pos=root.Position
    for _,area in ipairs(areas:GetChildren()) do
        local b=area:FindFirstChild("Bounds")
        if b and b:IsA("BasePart") then
            local p=b.CFrame:PointToObjectSpace(pos)
            local s=b.Size*0.5
            if math.abs(p.X)<=s.X and math.abs(p.Z)<=s.Z and math.abs(p.Y)<=s.Y+12 then return area.Name end
        end
    end
    return "Safe / corredor"
end

local function riskColor(risk)
    if risk=="Seguro" then return Color3.fromRGB(75,255,111) end
    if risk=="Arriscado" then return Color3.fromRGB(255,197,63) end
    if risk=="Alto risco" then return Color3.fromRGB(255,82,82) end
    return Color3.fromRGB(205,215,235)
end

local function eggColor(egg)
    return typeof(egg.RarityColor)=="Color3" and egg.RarityColor or rarityFallbackColor(egg.Rarity)
end

local function mutationText(egg)
    if egg.Mutations and #egg.Mutations>0 then return table.concat(egg.Mutations,"+") end
    if egg.HasParasite then return "Parasite" end
    return "Normal"
end

local function mutationPass(egg)
    local mode=CONFIG.MutationMode
    local muts=egg.Mutations or {}
    if mode=="Todas" then return true end
    if mode=="Com mutação" then return #muts>0 or egg.HasParasite end
    if mode=="Sem mutação" then return #muts==0 and not egg.HasParasite end
    local target=normalize(mode)
    if egg.HasParasite and target=="parasite" then return true end
    for _,m in ipairs(muts) do if normalize(m)==target then return true end end
    return false
end

local function currentMutationOptions()
    local out={"Todas","Com mutação","Sem mutação"}
    local seen={}
    for _,egg in pairs(State.Eggs) do
        for _,m in ipairs(egg.Mutations or {}) do
            local k=normalize(m)
            if not seen[k] then seen[k]=true; out[#out+1]=m end
        end
        if egg.HasParasite and not seen.parasite then seen.parasite=true; out[#out+1]="Parasite" end
    end
    table.sort(out,function(a,b)
        local fixed={ ["Todas"]=1,["Com mutação"]=2,["Sem mutação"]=3 }
        local aa,bb=fixed[a],fixed[b]
        if aa or bb then return (aa or 99)<(bb or 99) end
        return a<b
    end)
    return out
end

local function eggPasses(egg)
    if not CONFIG.EggESP then return false end
    if (tonumber(egg.RarityNumber) or 0)<CONFIG.MinRarity then return false end
    if (tonumber(egg.EarningsPerSecond) or 0)<CONFIG.MinEarnings then return false end
    if (tonumber(egg.SellPrice) or 0)<CONFIG.MinSellPrice then return false end
    if CONFIG.SelectedPet~="" then
        local selected=normalize(CONFIG.SelectedPet)
        local pet=normalize(egg.PetName or egg.AssetCategory or "")
        local cat=normalize(egg.AssetCategory or "")
        if pet~=selected and cat~=selected then return false end
    end
    return mutationPass(egg)
end

local function espLines(egg,visual)
    local lines={
        {Text=(egg.PetName or egg.AssetCategory or "Ovo").." • "..(egg.Rarity or "?"),Color=eggColor(egg),Bold=true}
    }
    if CONFIG.ShowEarnings then
        local e=egg.EarningsPerSecond and ("$"..formatCompact(egg.EarningsPerSecond).."/s") or "$?/s"
        lines[#lines+1]={Text=e.." • "..mutationText(egg),Color=Color3.fromRGB(245,248,255),Bold=true}
    end
    local extra={}
    if CONFIG.ShowWeight then
        extra[#extra+1]=egg.WeightLabel or (egg.WeightKg and (formatCompact(egg.WeightKg).."kg") or "?kg")
    end
    if CONFIG.ShowEggValue then
        extra[#extra+1]=egg.SellPrice and ("Ovo $"..formatCompact(egg.SellPrice)) or "Ovo $?"
    end
    if #extra>0 then
        lines[#lines+1]={Text=table.concat(extra," • "),Color=Color3.fromRGB(220,228,242)}
    end
    if CONFIG.ShowRisk then
        local risk=resolveRisk(egg,visual)
        lines[#lines+1]={Text="Risco: "..(risk or "?"),Color=riskColor(risk),Bold=true}
    end
    return lines
end

local function destroyEspRecord(uid)
    local rec=State.ESP[uid]
    if not rec then return end
    for _,key in ipairs({"Highlight","Billboard"}) do
        local obj=rec[key]
        if typeof(obj)=="Instance" then pcall(function() obj:Destroy() end) end
    end
    State.ESP[uid]=nil
end

local function sweepOwnedESP()
    for uid in pairs(State.ESP) do destroyEspRecord(uid) end
    local owned={PSICO_EGG_HIGHLIGHT=true,PSICO_EGG_BILLBOARD=true}
    for _,d in ipairs(Workspace:GetDescendants()) do
        if owned[d.Name] then pcall(function() d:Destroy() end) end
    end
    if gui then
        for _,d in ipairs(gui:GetDescendants()) do
            if owned[d.Name] then pcall(function() d:Destroy() end) end
        end
    end
end

local function createESP(uid,egg,visual)
    local adornee=getAdornee(visual)
    if not adornee then return end
    local color=eggColor(egg)

    local h=Instance.new("Highlight")
    h.Name="PSICO_EGG_HIGHLIGHT"
    h.Adornee=visual
    h.DepthMode=Enum.HighlightDepthMode.AlwaysOnTop
    h.FillColor=color
    h.OutlineColor=color
    h.FillTransparency=.87
    h.OutlineTransparency=.12
    h.Parent=visual

    local bb=Instance.new("BillboardGui")
    bb.Name="PSICO_EGG_BILLBOARD"
    bb.Adornee=adornee
    bb.AlwaysOnTop=true
    bb.MaxDistance=CONFIG.MaxEspDistance
    bb.Size=UDim2.fromOffset(168,54)
    bb.StudsOffset=Vector3.new(0,1.9,0)
    bb.Parent=gui

    local labels={}
    for i=1,4 do
        local l=Instance.new("TextLabel")
        l.BackgroundTransparency=1
        l.Position=UDim2.fromOffset(0,(i-1)*13)
        l.Size=UDim2.new(1,0,0,13)
        l.Font=Enum.Font.Gotham
        l.TextSize=(i==1 and 10 or 9)
        l.TextXAlignment=Enum.TextXAlignment.Center
        l.TextColor3=Color3.fromRGB(240,245,255)
        l.TextStrokeColor3=Color3.new(0,0,0)
        l.TextStrokeTransparency=.14
        l.Parent=bb
        labels[i]=l
    end
    State.ESP[uid]={Highlight=h,Billboard=bb,Visual=visual,Labels=labels}
end

local function updateESPRecord(uid,egg,visual)
    local rec=State.ESP[uid]
    if not rec or rec.Visual~=visual or not rec.Highlight.Parent or not rec.Billboard.Parent then
        destroyEspRecord(uid)
        createESP(uid,egg,visual)
        rec=State.ESP[uid]
    end
    if not rec then return end
    local color=eggColor(egg)
    rec.Highlight.FillColor=color
    rec.Highlight.OutlineColor=color
    local lines=espLines(egg,visual)
    rec.Billboard.Size=UDim2.fromOffset(168,math.max(28,#lines*13+3))
    for i,l in ipairs(rec.Labels) do
        local row=lines[i]
        if row then
            l.Visible=true
            l.Text=row.Text
            l.TextColor3=row.Color
            l.Font=row.Bold and Enum.Font.GothamBold or Enum.Font.Gotham
        else
            l.Visible=false
            l.Text=""
        end
    end
end

local function refreshESP()
    if not State.Alive then return end
    local keep,visible={},0
    for uid,egg in pairs(State.Eggs) do
        if eggPasses(egg) then
            local visual=visualForUid(uid)
            if visual then
                keep[uid]=true
                visible=visible+1
                updateESPRecord(uid,egg,visual)
            end
        end
    end
    for uid in pairs(State.ESP) do
        if not keep[uid] then destroyEspRecord(uid) end
    end
    State.Stats.EspVisible=visible
end

local function stateCounts()
    local slots,dropped=0,0
    for _,egg in pairs(State.Eggs) do
        if egg.State=="Slot" then slots=slots+1 elseif egg.State=="Dropped" then dropped=dropped+1 end
    end
    return slots,dropped
end

local function refreshStatus(extra)
    if not statusLabel then return end
    local slots,dropped=stateCounts()
    statusLabel.Text=string.format(
        "Ovos:%d • Chão:%d • ESP:%d • Catálogo:%d%s",
        slots,dropped,State.Stats.EspVisible,State.Stats.CatalogPets,
        extra and (" • "..extra) or ""
    )
end

local function refreshLiveInfo()
    if not liveInfoLabel then return end
    local p=readSpeedPower()
    local boost=currentBoostFactor()
    liveInfoLabel.Text="Velocidade atual: "..(p and formatCompact(p) or "?")
        .."\nBoost: "..(boost and ("x"..string.format("%.2f",boost)) or "?")
        .."\nÁrea: "..currentAreaName()
        .."\nRisco: "..((GuardEscapePrediction and GuardEscapeRequirement) and "AUTO" or "indisponível")
end

local function updateToggleVisual(btn,on)
    if not btn then return end
    btn.TextColor3=Color3.fromRGB(245,248,255)
    btn.BackgroundColor3=on and Color3.fromRGB(42,91,190) or Color3.fromRGB(35,44,61)
    local base=btn:GetAttribute("BaseLabel") or btn.Text
    btn.Text=base..(on and "  ON" or "  OFF")
end

local function applyPrompt(prompt)
    if not prompt:IsA("ProximityPrompt") then return end
    local original=State.PromptOriginals[prompt]
    if not original and prompt.HoldDuration>0 then
        original=prompt.HoldDuration
        State.PromptOriginals[prompt]=original
    end
    if CONFIG.InstantPrompt then
        if original and prompt.HoldDuration~=0 then pcall(function() prompt.HoldDuration=0 end) end
    elseif original then
        pcall(function() prompt.HoldDuration=original end)
    end
end

local function refreshPrompts()
    for _,d in ipairs(Workspace:GetDescendants()) do
        if d:IsA("ProximityPrompt") then applyPrompt(d) end
    end
end

local BAT_ATTRS={"CooldownActive","CooldownEndTime","CooldownDuration"}
local function isBat(tool)
    if not (tool and tool:IsA("Tool")) then return false end
    if tool:GetAttribute("IsBat")==true then return true end
    return lower(tool:GetAttribute("GearName") or ""):find("bat",1,true)~=nil
end

local function patchBat(tool)
    if not isBat(tool) then return false end
    local original=State.BatOriginals[tool]
    if not original then
        original={Enabled=tool.Enabled,Attrs={}}
        for _,a in ipairs(BAT_ATTRS) do original.Attrs[a]=tool:GetAttribute(a) end
        State.BatOriginals[tool]=original
    end
    if CONFIG.InstantHit then
        pcall(function() tool.Enabled=true end)
        pcall(function() tool:SetAttribute("CooldownActive",false) end)
        pcall(function() tool:SetAttribute("CooldownEndTime",0) end)
        pcall(function() tool:SetAttribute("CooldownDuration",0) end)
    else
        pcall(function() tool.Enabled=original.Enabled end)
        for _,a in ipairs(BAT_ATTRS) do
            pcall(function() tool:SetAttribute(a,original.Attrs[a]) end)
        end
    end
    if not State.WatchedBats[tool] then
        State.WatchedBats[tool]=true
        for _,a in ipairs(BAT_ATTRS) do
            connect(tool:GetAttributeChangedSignal(a),function()
                if State.Alive and CONFIG.InstantHit then
                    task.defer(function() if tool.Parent then patchBat(tool) end end)
                end
            end)
        end
    end
    return true
end

local function refreshBats()
    for _,container in ipairs({LP.Character,LP:FindFirstChildOfClass("Backpack")}) do
        if container then
            for _,child in ipairs(container:GetChildren()) do
                if child:IsA("Tool") then patchBat(child) end
            end
        end
    end
end

local function restoreBats()
    for tool,original in pairs(State.BatOriginals) do
        if tool and tool.Parent then
            pcall(function() tool.Enabled=original.Enabled end)
            for _,a in ipairs(BAT_ATTRS) do
                pcall(function() tool:SetAttribute(a,original.Attrs[a]) end)
            end
        end
    end
end

local refreshQueued=false
local function queueRefresh()
    if refreshQueued then return end
    refreshQueued=true
    task.defer(function()
        task.wait(.05)
        refreshQueued=false
        refreshESP()
        refreshStatus()
        refreshLiveInfo()
    end)
end

local function hookEggRemotes()
    for _,d in ipairs(ReplicatedStorage:GetDescendants()) do
        if d:IsA("RemoteEvent") then
            if d.Name=="RE/EggWorld/FieldEggShifted" then
                connect(d.OnClientEvent,function(record)
                    if not State.Alive or typeof(record)~="table" then return end
                    if validEggState(record.State) then enrichRecord(record)
                    elseif type(record.Uid)=="string" then removeEgg(record.Uid) end
                    queueRefresh()
                end,State.RemoteConnections)
            elseif d.Name=="RE/EggWorld/FieldEggBatchShifted" then
                connect(d.OnClientEvent,function(payload)
                    if not State.Alive or typeof(payload)~="table" then return end
                    if typeof(payload.RemovedUids)=="table" then
                        for _,uid in pairs(payload.RemovedUids) do removeEgg(uid) end
                    end
                    if typeof(payload.UpdatedRecords)=="table" then
                        for _,record in pairs(payload.UpdatedRecords) do
                            if typeof(record)=="table" then
                                if validEggState(record.State) then enrichRecord(record)
                                elseif type(record.Uid)=="string" then removeEgg(record.Uid) end
                            end
                        end
                    end
                    queueRefresh()
                end,State.RemoteConnections)
            elseif d.Name=="RE/EggWorld/FieldEggGone" then
                connect(d.OnClientEvent,function(uid)
                    if typeof(uid)=="table" then uid=uid.Uid end
                    removeEgg(uid)
                    queueRefresh()
                end,State.RemoteConnections)
            elseif d.Name=="RE/EggWorld/FieldEggCarry" then
                connect(d.OnClientEvent,function(payload)
                    if typeof(payload)=="table" then
                        if payload.IsCarrying==true and finite(tonumber(payload.SpeedMultiplier)) then
                            State.CarryMultiplier=tonumber(payload.SpeedMultiplier)
                        else
                            State.CarryMultiplier=1
                        end
                        queueRefresh()
                    end
                end,State.RemoteConnections)
            elseif d.Name=="RE/EggWorld/OwnerDropped" or d.Name=="RE/EggWorld/OwnerShifted" then
                connect(d.OnClientEvent,function(...)
                    local args=table.pack(...)
                    for i=1,args.n do
                        if typeof(args[i])=="table" then ingestTree(args[i]) end
                    end
                    queueRefresh()
                end,State.RemoteConnections)
            end
        end
    end
end

local function round(obj,r)
    local c=Instance.new("UICorner")
    c.CornerRadius=UDim.new(0,r or 9)
    c.Parent=obj
end

local function mkButton(parent,text,pos,size)
    local b=Instance.new("TextButton")
    b.BackgroundColor3=Color3.fromRGB(35,44,61)
    b.BorderSizePixel=0
    b.Position=pos
    b.Size=size
    b.Font=Enum.Font.GothamMedium
    b.Text=text
    b.TextColor3=Color3.fromRGB(239,244,255)
    b.TextSize=10
    b.Parent=parent
    round(b,8)
    return b
end

local function mkLabel(parent,text,pos,size,fontSize)
    local l=Instance.new("TextLabel")
    l.BackgroundTransparency=1
    l.Position=pos
    l.Size=size
    l.Font=Enum.Font.Gotham
    l.Text=text
    l.TextColor3=Color3.fromRGB(170,184,210)
    l.TextSize=fontSize or 9
    l.TextXAlignment=Enum.TextXAlignment.Left
    l.Parent=parent
    return l
end

local function mkTextBox(parent,placeholder,pos,size)
    local b=Instance.new("TextBox")
    b.BackgroundColor3=Color3.fromRGB(31,40,56)
    b.BorderSizePixel=0
    b.Position=pos
    b.Size=size
    b.Font=Enum.Font.GothamMedium
    b.Text=""
    b.PlaceholderText=placeholder
    b.TextColor3=Color3.fromRGB(240,244,255)
    b.PlaceholderColor3=Color3.fromRGB(115,128,151)
    b.TextSize=10
    b.ClearTextOnFocus=false
    b.Parent=parent
    round(b,8)
    return b
end

local function makeMainToggle(parent,label,y,key)
    local b=mkButton(parent,label,UDim2.fromOffset(0,y),UDim2.new(1,0,0,32))
    b:SetAttribute("BaseLabel",label)
    updateToggleVisual(b,CONFIG[key])
    connect(b.MouseButton1Click,function()
        CONFIG[key]=not CONFIG[key]
        updateToggleVisual(b,CONFIG[key])
        if key=="EggESP" then
            if CONFIG.EggESP then refreshESP() else sweepOwnedESP(); State.Stats.EspVisible=0 end
        elseif key=="InstantPrompt" then
            refreshPrompts()
        elseif key=="InstantHit" then
            if CONFIG.InstantHit then refreshBats() else restoreBats() end
        end
        refreshStatus()
    end)
    return b
end

local function makeInlineToggle(parent,label,y,key)
    mkLabel(parent,label,UDim2.fromOffset(0,y),UDim2.new(.66,0,0,26),9)
    local b=mkButton(parent,"",UDim2.new(.70,0,0,y),UDim2.new(.30,-4,0,26))
    local function paint()
        b.Text=CONFIG[key] and "ON" or "OFF"
        b.BackgroundColor3=CONFIG[key] and Color3.fromRGB(42,91,190) or Color3.fromRGB(35,44,61)
    end
    paint()
    connect(b.MouseButton1Click,function()
        CONFIG[key]=not CONFIG[key]
        paint()
        refreshESP()
        refreshLiveInfo()
    end)
    return b
end

for _,oldName in ipairs({"PsicoRoubeUmOvoV821","PsicoRoubeUmOvoV82","PsicoRoubeUmOvoV811","PsicoRoubeUmOvoV81","PsicoRoubeUmOvoV8","PsicoRoubeUmOvo"}) do
    local old=uiParent():FindFirstChild(oldName)
    if old then pcall(function() old:Destroy() end) end
end

gui=Instance.new("ScreenGui")
gui.Name="PsicoRoubeUmOvoV821"
gui.ResetOnSpawn=false
gui.IgnoreGuiInset=true
gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling
gui.Parent=uiParent()

mainFrame=Instance.new("Frame")
mainFrame.Name="Main"
mainFrame.AnchorPoint=Vector2.new(.5,.5)
mainFrame.Position=UDim2.fromScale(.5,.5)
mainFrame.Size=UDim2.fromOffset(455,320)
mainFrame.BackgroundColor3=Color3.fromRGB(14,20,32)
mainFrame.BorderSizePixel=0
mainFrame.Parent=gui
round(mainFrame,13)

uiScale=Instance.new("UIScale")
uiScale.Scale=1
uiScale.Parent=mainFrame

local stroke=Instance.new("UIStroke")
stroke.Thickness=1.1
stroke.Transparency=.28
stroke.Color=Color3.fromRGB(61,118,230)
stroke.Parent=mainFrame

local title=mkLabel(mainFrame,"PSICOSENATICO PANEL",UDim2.fromOffset(12,6),UDim2.new(1,-84,0,20),13)
title.Font=Enum.Font.GothamBold
title.TextColor3=Color3.fromRGB(242,246,255)
local version=mkLabel(mainFrame,"V8.2.1 • EARNINGS + RISK ESP",UDim2.fromOffset(12,24),UDim2.new(1,-84,0,14),8)
version.TextColor3=Color3.fromRGB(102,148,232)
local minimize=mkButton(mainFrame,"—",UDim2.new(1,-62,0,6),UDim2.fromOffset(25,25))
local close=mkButton(mainFrame,"×",UDim2.new(1,-32,0,6),UDim2.fromOffset(25,25))

local sidebar=Instance.new("Frame")
sidebar.BackgroundTransparency=1
sidebar.Position=UDim2.fromOffset(10,47)
sidebar.Size=UDim2.new(0,104,1,-77)
sidebar.Parent=mainFrame
local tabMain=mkButton(sidebar,"FUNÇÕES",UDim2.fromOffset(0,0),UDim2.new(1,0,0,42))
local tabFilters=mkButton(sidebar,"FILTROS ESP",UDim2.fromOffset(0,50),UDim2.new(1,0,0,42))

local contentHost=Instance.new("Frame")
contentHost.BackgroundColor3=Color3.fromRGB(20,28,43)
contentHost.BackgroundTransparency=.12
contentHost.BorderSizePixel=0
contentHost.Position=UDim2.fromOffset(122,47)
contentHost.Size=UDim2.new(1,-132,1,-77)
contentHost.Parent=mainFrame
round(contentHost,10)

local mainPage=Instance.new("ScrollingFrame")
mainPage.BackgroundTransparency=1
mainPage.BorderSizePixel=0
mainPage.Position=UDim2.fromOffset(8,8)
mainPage.Size=UDim2.new(1,-16,1,-16)
mainPage.CanvasSize=UDim2.fromOffset(0,166)
mainPage.ScrollBarThickness=3
mainPage.ScrollBarImageColor3=Color3.fromRGB(94,139,223)
mainPage.Parent=contentHost

local filterPage=Instance.new("ScrollingFrame")
filterPage.BackgroundTransparency=1
filterPage.BorderSizePixel=0
filterPage.Position=UDim2.fromOffset(8,8)
filterPage.Size=UDim2.new(1,-16,1,-16)
filterPage.CanvasSize=UDim2.fromOffset(0,500)
filterPage.ScrollBarThickness=3
filterPage.ScrollBarImageColor3=Color3.fromRGB(94,139,223)
filterPage.Visible=false
filterPage.Parent=contentHost

espToggleButton=makeMainToggle(mainPage,"ESP • Ovos",0,"EggESP")
promptToggleButton=makeMainToggle(mainPage,"Instant Prompt",38,"InstantPrompt")
hitToggleButton=makeMainToggle(mainPage,"Instant Hit • Bat",76,"InstantHit")
local refreshButton=mkButton(mainPage,"Atualizar ovos",UDim2.fromOffset(0,114),UDim2.new(1,0,0,32))

local filterY=0
mkLabel(filterPage,"Raridade mínima",UDim2.fromOffset(0,filterY),UDim2.new(.45,0,0,28),9)
rarityButton=mkButton(filterPage,"Todas",UDim2.new(.47,0,0,filterY),UDim2.new(.53,-4,0,28)); filterY=filterY+34
mkLabel(filterPage,"Rendimento mínimo ($/s)",UDim2.fromOffset(0,filterY),UDim2.new(.45,0,0,28),9)
local earningBox=mkTextBox(filterPage,"Ex: 2M",UDim2.new(.47,0,0,filterY),UDim2.new(.53,-4,0,28)); filterY=filterY+34
mkLabel(filterPage,"Valor do ovo mín. ($)",UDim2.fromOffset(0,filterY),UDim2.new(.45,0,0,28),9)
local valueBox=mkTextBox(filterPage,"Opcional",UDim2.new(.47,0,0,filterY),UDim2.new(.53,-4,0,28)); filterY=filterY+34
mkLabel(filterPage,"Pet",UDim2.fromOffset(0,filterY),UDim2.new(.45,0,0,28),9)
petButton=mkButton(filterPage,"Selecionar pet...",UDim2.new(.47,0,0,filterY),UDim2.new(.53,-4,0,28)); filterY=filterY+34
mkLabel(filterPage,"Lista de pets",UDim2.fromOffset(0,filterY),UDim2.new(.45,0,0,28),9)
availabilityButton=mkButton(filterPage,"Todos do jogo",UDim2.new(.47,0,0,filterY),UDim2.new(.53,-4,0,28)); filterY=filterY+34
mkLabel(filterPage,"Mutação",UDim2.fromOffset(0,filterY),UDim2.new(.45,0,0,28),9)
mutationButton=mkButton(filterPage,"Todas",UDim2.new(.47,0,0,filterY),UDim2.new(.53,-4,0,28)); filterY=filterY+38

makeInlineToggle(filterPage,"Mostrar $/s do pet",filterY,"ShowEarnings"); filterY=filterY+30
makeInlineToggle(filterPage,"Mostrar valor do ovo",filterY,"ShowEggValue"); filterY=filterY+30
makeInlineToggle(filterPage,"Mostrar peso",filterY,"ShowWeight"); filterY=filterY+30
makeInlineToggle(filterPage,"Mostrar risco",filterY,"ShowRisk"); filterY=filterY+30
makeInlineToggle(filterPage,"Boost auto",filterY,"BoostAuto"); filterY=filterY+36

local liveCard=Instance.new("Frame")
liveCard.Position=UDim2.fromOffset(0,filterY)
liveCard.Size=UDim2.new(1,-4,0,72)
liveCard.BackgroundColor3=Color3.fromRGB(20,31,50)
liveCard.BorderSizePixel=0
liveCard.Parent=filterPage
round(liveCard,9)
liveInfoLabel=mkLabel(liveCard,"Velocidade atual: ?\nBoost: ?\nÁrea: ?\nRisco: AUTO",UDim2.fromOffset(10,7),UDim2.new(1,-20,1,-14),9)
liveInfoLabel.TextColor3=Color3.fromRGB(176,203,245)
liveInfoLabel.TextYAlignment=Enum.TextYAlignment.Top
filterY=filterY+80
local resetFilters=mkButton(filterPage,"Limpar filtros",UDim2.fromOffset(0,filterY),UDim2.new(1,-4,0,30)); filterY=filterY+36
filterPage.CanvasSize=UDim2.fromOffset(0,filterY)

statusLabel=mkLabel(mainFrame,"Carregando dados...",UDim2.new(0,12,1,-24),UDim2.new(1,-24,0,16),8)
statusLabel.TextXAlignment=Enum.TextXAlignment.Center
statusLabel.TextColor3=Color3.fromRGB(139,164,207)

local function showPage(which)
    local filters=(which=="filters")
    mainPage.Visible=not filters
    filterPage.Visible=filters
    tabMain.BackgroundColor3=not filters and Color3.fromRGB(42,91,190) or Color3.fromRGB(35,44,61)
    tabFilters.BackgroundColor3=filters and Color3.fromRGB(42,91,190) or Color3.fromRGB(35,44,61)
end
connect(tabMain.MouseButton1Click,function() showPage("main") end)
connect(tabFilters.MouseButton1Click,function() showPage("filters") end)
showPage("main")

local function applyResponsive()
    local camera=Workspace.CurrentCamera
    local vp=(camera and camera.ViewportSize) or Vector2.new(844,390)
    local widthLimit=math.max(280,vp.X-24)
    local heightLimit=math.max(210,vp.Y*.70)
    uiScale.Scale=math.min(widthLimit/455,heightLimit/320,1)
end

local function attachCameraResize(camera)
    if camera then connect(camera:GetPropertyChangedSignal("ViewportSize"),applyResponsive) end
end

applyResponsive()
attachCameraResize(Workspace.CurrentCamera)
connect(Workspace:GetPropertyChangedSignal("CurrentCamera"),function()
    task.defer(function()
        attachCameraResize(Workspace.CurrentCamera)
        applyResponsive()
    end)
end)

connect(rarityButton.MouseButton1Click,function()
    CONFIG.MinRarity=CONFIG.MinRarity+1
    if CONFIG.MinRarity>#RARITY_ORDER then CONFIG.MinRarity=0 end
    rarityButton.Text=CONFIG.MinRarity==0 and "Todas" or RARITY_ORDER[CONFIG.MinRarity]
    refreshESP()
    refreshStatus()
end)

connect(earningBox.FocusLost,function()
    CONFIG.MinEarnings=parseSmartNumber(earningBox.Text)
    earningBox.Text=CONFIG.MinEarnings==0 and "" or formatCompact(CONFIG.MinEarnings)
    refreshESP()
    refreshStatus()
end)

connect(valueBox.FocusLost,function()
    CONFIG.MinSellPrice=parseSmartNumber(valueBox.Text)
    valueBox.Text=CONFIG.MinSellPrice==0 and "" or formatCompact(CONFIG.MinSellPrice)
    refreshESP()
    refreshStatus()
end)

connect(mutationButton.MouseButton1Click,function()
    local opts=currentMutationOptions()
    local idx=1
    for i,v in ipairs(opts) do if v==CONFIG.MutationMode then idx=i break end end
    idx=idx+1
    if idx>#opts then idx=1 end
    CONFIG.MutationMode=opts[idx]
    mutationButton.Text=CONFIG.MutationMode
    refreshESP()
    refreshStatus()
end)

local function availablePetNames()
    local map={}
    for _,egg in pairs(State.Eggs) do
        local name=egg.PetName or egg.AssetCategory
        if type(name)=="string" and name~="" then map[normalize(name)]=true end
    end
    return map
end

local function catalogForPicker()
    local out,available,seen={},availablePetNames(),{}
    for _,entry in ipairs(State.CatalogEntries) do
        local name=entry.PetName
        local key=normalize(name)
        if name and name~="" and not seen[key] and (not CONFIG.PetListAvailableOnly or available[key]) then
            seen[key]=true
            out[#out+1]=entry
        end
    end
    table.sort(out,function(a,b) return lower(a.PetName)<lower(b.PetName) end)
    return out
end

local function closePetModal()
    if petModal then
        pcall(function() petModal:Destroy() end)
        petModal=nil
        petSearchBox=nil
        petList=nil
    end
end

local function buildPetRows(query)
    if not petList then return end
    for _,child in ipairs(petList:GetChildren()) do
        if child:IsA("GuiObject") then child:Destroy() end
    end
    local y=0
    local q=lower(query or "")
    local all=mkButton(petList,"Todos os pets",UDim2.fromOffset(0,y),UDim2.new(1,-4,0,28))
    all.TextXAlignment=Enum.TextXAlignment.Left
    all.ZIndex=32
    connect(all.MouseButton1Click,function()
        CONFIG.SelectedPet=""
        petButton.Text="Selecionar pet..."
        closePetModal()
        refreshESP()
        refreshStatus()
    end)
    y=y+32
    for _,entry in ipairs(catalogForPicker()) do
        local name=safeString(entry.PetName)
        local rarity=safeString(entry.Rarity or "?")
        if q=="" or lower(name):find(q,1,true) or lower(rarity):find(q,1,true) then
            local row=mkButton(petList,name.."  •  "..rarity,UDim2.fromOffset(0,y),UDim2.new(1,-4,0,28))
            row.TextXAlignment=Enum.TextXAlignment.Left
            row.ZIndex=32
            row.TextColor3=rarityFallbackColor(rarity)
            connect(row.MouseButton1Click,function()
                CONFIG.SelectedPet=name
                petButton.Text=name
                closePetModal()
                refreshESP()
                refreshStatus()
            end)
            y=y+32
        end
    end
    petList.CanvasSize=UDim2.fromOffset(0,math.max(y,1))
end

local function openPetModal()
    closePetModal()
    petModal=Instance.new("Frame")
    petModal.Name="PetPicker"
    petModal.AnchorPoint=Vector2.new(.5,.5)
    petModal.Position=UDim2.fromScale(.5,.5)
    petModal.Size=UDim2.fromOffset(300,224)
    petModal.BackgroundColor3=Color3.fromRGB(15,22,35)
    petModal.BorderSizePixel=0
    petModal.ZIndex=30
    petModal.Parent=gui
    round(petModal,11)

    local ps=Instance.new("UIStroke")
    ps.Color=Color3.fromRGB(61,118,230)
    ps.Transparency=.2
    ps.Parent=petModal

    local modalScale=Instance.new("UIScale")
    modalScale.Scale=uiScale.Scale
    modalScale.Parent=petModal

    local pt=mkLabel(petModal,"Selecionar Pet",UDim2.fromOffset(12,7),UDim2.new(1,-50,0,20),12)
    pt.Font=Enum.Font.GothamBold
    pt.TextColor3=Color3.fromRGB(242,246,255)

    local px=mkButton(petModal,"×",UDim2.new(1,-34,0,6),UDim2.fromOffset(26,26))
    px.ZIndex=31
    connect(px.MouseButton1Click,closePetModal)

    petSearchBox=mkTextBox(petModal,"Buscar pet...",UDim2.fromOffset(12,37),UDim2.new(1,-24,0,30))
    petSearchBox.ZIndex=31
    local mode=mkButton(petModal,CONFIG.PetListAvailableOnly and "Só disponíveis agora" or "Todos os pets do jogo",UDim2.fromOffset(12,73),UDim2.new(1,-24,0,28))
    mode.ZIndex=31
    connect(mode.MouseButton1Click,function()
        CONFIG.PetListAvailableOnly=not CONFIG.PetListAvailableOnly
        availabilityButton.Text=CONFIG.PetListAvailableOnly and "Só disponíveis" or "Todos do jogo"
        mode.Text=CONFIG.PetListAvailableOnly and "Só disponíveis agora" or "Todos os pets do jogo"
        buildPetRows(petSearchBox.Text)
    end)

    petList=Instance.new("ScrollingFrame")
    petList.BackgroundTransparency=1
    petList.BorderSizePixel=0
    petList.Position=UDim2.fromOffset(12,107)
    petList.Size=UDim2.new(1,-24,1,-119)
    petList.CanvasSize=UDim2.fromOffset(0,0)
    petList.ScrollBarThickness=3
    petList.ScrollBarImageColor3=Color3.fromRGB(94,139,223)
    petList.ZIndex=31
    petList.Parent=petModal
    connect(petSearchBox:GetPropertyChangedSignal("Text"),function() buildPetRows(petSearchBox.Text) end)
    buildPetRows("")
end

connect(petButton.MouseButton1Click,openPetModal)
connect(availabilityButton.MouseButton1Click,function()
    CONFIG.PetListAvailableOnly=not CONFIG.PetListAvailableOnly
    availabilityButton.Text=CONFIG.PetListAvailableOnly and "Só disponíveis" or "Todos do jogo"
end)

connect(resetFilters.MouseButton1Click,function()
    CONFIG.MinRarity=0
    CONFIG.MinEarnings=0
    CONFIG.MinSellPrice=0
    CONFIG.SelectedPet=""
    CONFIG.MutationMode="Todas"
    CONFIG.PetListAvailableOnly=false
    rarityButton.Text="Todas"
    mutationButton.Text="Todas"
    availabilityButton.Text="Todos do jogo"
    petButton.Text="Selecionar pet..."
    earningBox.Text=""
    valueBox.Text=""
    refreshESP()
    refreshStatus()
end)

connect(refreshButton.MouseButton1Click,function()
    local old=State.Eggs
    State.Eggs={}
    State.AreaParams={}
    local n=requestSnapshots()
    if n==0 and next(old) then State.Eggs=old end
    refreshESP()
    refreshStatus("snapshot:"..tostring(n))
    refreshLiveInfo()
end)

local dragging=false
local dragInput,dragStart,startPos
connect(mainFrame.InputBegan,function(input)
    if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1 then
        dragging=true
        dragStart=input.Position
        startPos=mainFrame.Position
    end
end)
connect(mainFrame.InputChanged,function(input)
    if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseMovement then dragInput=input end
end)
connect(UIS.InputChanged,function(input)
    if dragging and input==dragInput then
        local d=input.Position-dragStart
        mainFrame.Position=UDim2.new(startPos.X.Scale,startPos.X.Offset+d.X,startPos.Y.Scale,startPos.Y.Offset+d.Y)
    end
end)
connect(UIS.InputEnded,function(input)
    if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1 then dragging=false end
end)

floatButton=Instance.new("TextButton")
floatButton.Name="PSICO_FLOAT"
floatButton.Size=UDim2.fromOffset(46,46)
floatButton.Position=UDim2.new(0,18,.5,-23)
floatButton.BackgroundColor3=Color3.fromRGB(18,42,84)
floatButton.BorderSizePixel=0
floatButton.Font=Enum.Font.GothamBold
floatButton.Text="PS"
floatButton.TextColor3=Color3.fromRGB(240,245,255)
floatButton.TextSize=12
floatButton.Visible=false
floatButton.Parent=gui
round(floatButton,23)

local fdrag=false
local fstart,fpos
connect(floatButton.InputBegan,function(input)
    if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1 then
        fdrag=true
        fstart=input.Position
        fpos=floatButton.Position
    end
end)
connect(UIS.InputChanged,function(input)
    if fdrag and (input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseMovement) then
        local d=input.Position-fstart
        floatButton.Position=UDim2.new(fpos.X.Scale,fpos.X.Offset+d.X,fpos.Y.Scale,fpos.Y.Offset+d.Y)
    end
end)
connect(UIS.InputEnded,function(input)
    if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1 then fdrag=false end
end)
connect(floatButton.MouseButton1Click,function() mainFrame.Visible=true; floatButton.Visible=false end)
connect(minimize.MouseButton1Click,function() closePetModal(); mainFrame.Visible=false; floatButton.Visible=true end)

local function initializeData()
    local ok,err=resolveModules()
    if not ok then refreshStatus("ERRO:"..err); return false end
    if not buildCatalog() then refreshStatus("ERRO:catálogo"); return false end
    requestSnapshots()
    refreshESP()
    refreshStatus()
    refreshLiveInfo()
    return true
end

hookEggRemotes()
connect(Workspace.DescendantAdded,function(inst)
    if inst:IsA("ProximityPrompt") then
        task.defer(function() if State.Alive then applyPrompt(inst) end end)
    end
    if inst.Name=="AreaEggSlotsClient" or (inst.Parent and inst.Parent.Name=="AreaEggSlotsClient") then queueRefresh() end
    if type(inst.Name)=="string" and State.Eggs[inst.Name] then queueRefresh() end
end)
connect(Workspace.DescendantRemoving,function(inst)
    if type(inst.Name)=="string" and State.Eggs[inst.Name] then queueRefresh() end
end)
connect(LP.ChildAdded,function(child)
    if child:IsA("Backpack") then
        connect(child.ChildAdded,function(tool)
            if tool:IsA("Tool") then task.defer(function() patchBat(tool) end) end
        end)
    end
end)
connect(LP.CharacterAdded,function(char)
    State.CarryMultiplier=1
    connect(char.ChildAdded,function(tool)
        if tool:IsA("Tool") then task.defer(function() patchBat(tool) end) end
    end)
    task.defer(refreshBats)
end)
local backpack=LP:FindFirstChildOfClass("Backpack")
if backpack then
    connect(backpack.ChildAdded,function(tool)
        if tool:IsA("Tool") then task.defer(function() patchBat(tool) end) end
    end)
end
if LP.Character then
    connect(LP.Character.ChildAdded,function(tool)
        if tool:IsA("Tool") then task.defer(function() patchBat(tool) end) end
    end)
end

local function cleanup()
    if not State.Alive then return end
    State.Alive=false
    closePetModal()
    sweepOwnedESP()
    for prompt,original in pairs(State.PromptOriginals) do
        if prompt and prompt.Parent then pcall(function() prompt.HoldDuration=original end) end
    end
    restoreBats()
    for _,c in ipairs(State.RemoteConnections) do disconnect(c) end
    for _,c in ipairs(State.Connections) do disconnect(c) end
    _G.PSICO_ROUBE_MENU_CLEANUP=nil
    pcall(function() if gui then gui:Destroy() end end)
end
_G.PSICO_ROUBE_MENU_CLEANUP=cleanup
connect(close.MouseButton1Click,cleanup)

sweepOwnedESP()
refreshPrompts()
refreshBats()
updateToggleVisual(espToggleButton,CONFIG.EggESP)
updateToggleVisual(promptToggleButton,CONFIG.InstantPrompt)
updateToggleVisual(hitToggleButton,CONFIG.InstantHit)

task.defer(function()
    task.wait(.4)
    if State.Alive then initializeData() end
end)

task.defer(function()
    while State.Alive do
        task.wait(.65)
        if CONFIG.EggESP then refreshESP() end
        if CONFIG.InstantHit then refreshBats() end
        refreshStatus()
        refreshLiveInfo()
    end
end)

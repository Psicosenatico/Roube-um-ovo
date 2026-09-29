--[[
PSICOSENATICO | Roube um Ovo - Precision Menu V8.3
Stable loader path: RoubeUmOvo_Menu.lua

- ESP por rendimento do pet ($/s), raridade, mutacao e filtros K/M/B/T.
- Valor do ovo e peso continuam opcionais.
- O risco agora usa velocidade efetiva carregando x referencia oficial da area.
- Raridade e valor do pet NAO entram como penalidade de transporte.
- Penalidade estimada usa tamanho fisico do ovo, com piso observado de x0.67.
- Boost atual entra automaticamente no calculo quando Boost auto esta ligado.
- GuardEscapePrediction fica somente como dado auxiliar; nao decide mais o risco principal.
- Filtros removem somente ESP; nunca o modelo real do ovo.
]]

if _G.PSICO_ROUBE_SCANNER_CLEANUP then pcall(_G.PSICO_ROUBE_SCANNER_CLEANUP) end
if _G.PSICO_ROUBE_MENU_CLEANUP then pcall(_G.PSICO_ROUBE_MENU_CLEANUP) end

local Players=game:GetService("Players")
local Workspace=game:GetService("Workspace")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local CoreGui=game:GetService("CoreGui")
local UIS=game:GetService("UserInputService")
local LocalizationService=game:GetService("LocalizationService")
local LP=Players.LocalPlayer

local CONFIG={
    EggESP=true,
    InstantPrompt=true,
    InstantHit=true,
    AutoTrain=true,
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

-- Valores encontrados no proprio cliente do jogo (RequiredSpeedPowerByAreaId).
local AREA_REQUIRED_POWER={
    Forest=11,
    Lake=900,
    Desert=10000,
    Jungle=40000,
    Snow=170000,
    Volcano=700000,
    ["Abyss Ocean"]=2500000,
    Prehistoric=18000000,
    Cosmic=700000000,
    ["Cherry Blossom"]=2500000000,
    ["Titan Temple"]=7000000000,
    ["Light Dark"]=20000000000,
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
    CarryMultiplier=1,
    LastCarryUid=nil,
    LastCarryServerMultiplier=nil,
    AutoTrainLastWear=0,
    AutoTrainLastPower=nil,
    AutoTrainLastPowerAt=0,
    AutoTrainRate=0,
    AutoTrainEarned=0,
    AutoTrainStatus="Inicializando",
    AutoTrainBelt=nil,
    AutoTrainBeltAt=0,
    FusionSelected={},
    FusionSortMode=1,
    FusionBusy=false,
    FusionLastResult=nil,
    Stats={EspVisible=0,CatalogPets=0},
}

local AssetsData
local EggRecords
local AssetEarnings
local MutationCatalog
local GuardEscapePrediction
local TreadmillUtil
local SpeedPowerProjection
local PlotState
local SharedRemotes
local SaveData
local AssetItems
local FuseKernel
local PetTranslator
local PetLocalizedCache={}

local gui,mainFrame,uiScale,floatButton
local statusLabel,liveInfoLabel
local rarityButton,mutationButton,petButton,availabilityButton
local espToggleButton,promptToggleButton,hitToggleButton,autoTrainToggleButton
local autoTrainStatusLabel
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

-- Accent-insensitive text used only by the pet picker search.
-- This lets "passaro" match "Pássaro", for example.
local SEARCH_ACCENTS={
    ["á"]="a",["à"]="a",["â"]="a",["ã"]="a",["ä"]="a",
    ["Á"]="a",["À"]="a",["Â"]="a",["Ã"]="a",["Ä"]="a",
    ["é"]="e",["è"]="e",["ê"]="e",["ë"]="e",
    ["É"]="e",["È"]="e",["Ê"]="e",["Ë"]="e",
    ["í"]="i",["ì"]="i",["î"]="i",["ï"]="i",
    ["Í"]="i",["Ì"]="i",["Î"]="i",["Ï"]="i",
    ["ó"]="o",["ò"]="o",["ô"]="o",["õ"]="o",["ö"]="o",
    ["Ó"]="o",["Ò"]="o",["Ô"]="o",["Õ"]="o",["Ö"]="o",
    ["ú"]="u",["ù"]="u",["û"]="u",["ü"]="u",
    ["Ú"]="u",["Ù"]="u",["Û"]="u",["Ü"]="u",
    ["ç"]="c",["Ç"]="c",
}

local function searchText(v)
    local s=safeString(v or "")
    for from,to in pairs(SEARCH_ACCENTS) do s=s:gsub(from,to) end
    return string.lower(s)
end

local function resolvePetTranslator()
    if PetTranslator then return PetTranslator end

    -- Force Brazilian Portuguese so the picker matches the names shown by
    -- the game's Portuguese localization, regardless of executor UI locale.
    local ok,tr=pcall(function()
        return LocalizationService:GetTranslatorForLocaleAsync("pt-br")
    end)
    if ok and tr then
        PetTranslator=tr
        return PetTranslator
    end

    -- Compatibility fallback: use Roblox's translator for the local player.
    ok,tr=pcall(function()
        return LocalizationService:GetTranslatorForPlayerAsync(LP)
    end)
    if ok and tr then PetTranslator=tr end
    return PetTranslator
end

local function localizedPetName(source)
    source=safeString(source or "")
    if source=="" then return source end
    if PetLocalizedCache[source] then return PetLocalizedCache[source] end

    local translated=source
    local tr=resolvePetTranslator()
    if tr then
        local context=LP:FindFirstChildOfClass("PlayerGui") or game
        local ok,result=pcall(function()
            return tr:Translate(context,source)
        end)
        if ok and type(result)=="string" and result~="" then translated=result end
    end

    PetLocalizedCache[source]=translated
    return translated
end

local function finite(v)
    return type(v)=="number" and v==v and v~=math.huge and v~=-math.huge
end

-- Use the displayed rarity name as the canonical filter rank.
-- Some current asset configs do not expose a usable RarityNumber, which
-- previously made every egg rank as 0 and caused any rarity filter to hide all ESP.
local function rarityRank(name,raw)
    local key=normalize(name)
    if key~="" then
        for i,rarity in ipairs(RARITY_ORDER) do
            if normalize(rarity)==key then return i end
        end
    end
    local n=tonumber(raw)
    if finite(n) and n>=1 and n<=#RARITY_ORDER then
        return math.floor(n+0.5)
    end
    return 0
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
    TreadmillUtil=requireOptional("Shared.Util.TreadmillUtil")
    SpeedPowerProjection=requireOptional("Client.SpeedPowerProjection")
    PlotState=requireOptional("Client.PlotState")
    SharedRemotes=requireOptional("Shared.Remotes")
    SaveData=requireOptional("Shared.Save")
    AssetItems=requireOptional("Shared.Util.AssetItems")
    FuseKernel=requireOptional("Shared.Util.FuseKernel")
    indexMutationScalars()
    return true
end

local function indexEntry(key,cfg)
    if typeof(cfg)~="table" or typeof(cfg.Rarity)~="table" then return false end
    local rarityName=cfg.Rarity.DisplayName or cfg.Rarity._id
    local petName=cfg.DisplayName or safeString(key)
    local entry={
        Key=safeString(key),
        PetName=petName,
        PetNameLocalized=localizedPetName(petName),
        Rarity=rarityName,
        RarityNumber=rarityRank(rarityName,cfg.Rarity.RarityNumber),
        RarityColor=cfg.Rarity.Color,
        EarningRate=tonumber(cfg.EarningRate),
    }
    for _,name in ipairs({entry.Key,entry.PetName,entry.PetNameLocalized}) do
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
        if ar==br then
            return searchText(a.PetNameLocalized or a.PetName)<searchText(b.PetNameLocalized or b.PetName)
        end
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
    -- O V13 observou x0.9593 em ~5.11 studs, x0.7783 em ~26.72 e piso x0.67 em ovo gigante.
    -- Mantemos a regressao mais ampla ja usada, corrigindo o piso que antes estava pessimista em x0.55.
    return math.clamp(1.0000706-(0.0079809*mag),0.67,0.96)
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
    local rarityName=cfg and cfg.Rarity or record.Rarity
    State.Eggs[record.Uid]={
        Uid=record.Uid,
        State=record.State,
        AreaId=record.AreaId,
        AssetCategory=record.AssetCategory,
        Mutations=copyMutations(record.Mutations),
        HasParasite=record.HasParasite==true,
        PetName=cfg and cfg.PetName or record.AssetCategory,
        Rarity=rarityName,
        RarityNumber=rarityRank(rarityName,cfg and cfg.RarityNumber or record.RarityNumber),
        RarityColor=cfg and cfg.RarityColor or nil,
        EarningsPerSecond=resolveEarnings(record,cfg),
        WeightKg=(wok and finite(tonumber(weight))) and tonumber(weight) or nil,
        WeightLabel=lok and safeString(weightLabel) or nil,
        SellPrice=(sok and finite(tonumber(sell))) and tonumber(sell) or nil,
        CarryMultiplierEstimate=estimateCarryMultiplier(record),
        BoundsMagnitude=boundsMagnitude(record.BoundsSize),
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

local function areaRequiredWalkSpeed(areaId)
    local power=AREA_REQUIRED_POWER[areaId]
    if not finite(power) then return nil,nil end
    local walk,ok=callTableFn(TreadmillUtil,"SpeedPowerToWalkSpeed",power)
    walk=tonumber(walk)
    if ok and finite(walk) and walk>0 then return walk,power end
    return nil,power
end

local function guardAreaRoot()
    return findPath(Workspace,"__OBJECTS.Areas.GuardAreas")
end

local function separationLine()
    local areas=findPath(Workspace,"__OBJECTS.Areas")
    local p=areas and areas:FindFirstChild("SeparationLine")
    return p and p:IsA("BasePart") and p or nil
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

local function contactOutcomeFor(egg,visual,carryWalk)
    -- Auxiliar apenas: se falhar ou estiver indisponivel, o risco principal continua funcionando.
    if typeof(GuardEscapePrediction)~="table" or type(GuardEscapePrediction.Resolve)~="function" then return nil end
    local areas=guardAreaRoot()
    local area=areas and areas:FindFirstChild(egg.AreaId or "")
    local bounds=area and area:FindFirstChild("Bounds")
    local guard=area and (area:FindFirstChild("Guard") or area:FindFirstChild("ForestGuardAuthored"))
    local pos=visualPosition(visual)
    if not (bounds and bounds:IsA("BasePart") and guard and pos and finite(carryWalk)) then return nil end

    local guardPos
    if guard:IsA("BasePart") then guardPos=guard.Position
    elseif guard:IsA("Model") then
        local ok,cf=pcall(guard.GetPivot,guard)
        if ok then guardPos=cf.Position end
    end
    if not guardPos then return nil end

    local exitDirection=-bounds.CFrame.LookVector
    local exitDistance,okDist=callTableFn(GuardEscapePrediction,"ResolveExitDistance",bounds.CFrame,bounds.Size,pos,exitDirection)
    exitDistance=tonumber(exitDistance)
    if not (okDist and finite(exitDistance)) then return nil end

    local baseGuardWalk=tonumber(guard:GetAttribute("WalkSpeed"))
    if not finite(baseGuardWalk) and guard:IsA("Model") then
        local hum=guard:FindFirstChildOfClass("Humanoid")
        baseGuardWalk=hum and tonumber(hum.WalkSpeed) or nil
    end
    if not finite(baseGuardWalk) or baseGuardWalk<=0 then return nil end

    local result,ok=callTableFn(GuardEscapePrediction,"Resolve",{
        BaseGuardWalkSpeed=baseGuardWalk,
        ExitDirection=exitDirection,
        ExitDistance=exitDistance,
        FlatRadius=tonumber(guard:GetAttribute("FlatRadius")) or 10,
        GuardStartPosition=guardPos,
        HitDistance=tonumber(guard:GetAttribute("HitDistance")) or 10,
        PlayerWalkSpeed=carryWalk,
        PlayerStartPosition=pos,
    })
    return ok and typeof(result)=="table" and result.Outcome or nil
end

local function resolveRisk(egg,visual)
    local mult=tonumber(egg.CarryMultiplierEstimate)
    local free=riskFreeWalkSpeed()
    local required,requiredPower=areaRequiredWalkSpeed(egg.AreaId)
    if not (finite(mult) and finite(free) and finite(required) and required>0) then return nil end

    local carry=free*mult
    local ratio=carry/required
    local label
    if ratio>=1 then label="Seguro"
    elseif ratio>=0.90 then label="Viável"
    elseif ratio>=0.80 then label="Arriscado"
    else label="Alto risco" end

    local line=separationLine()
    local pos=visualPosition(visual)
    local distance,timeToSafe
    if line and pos then
        local a=Vector3.new(pos.X,0,pos.Z)
        local b=Vector3.new(line.Position.X,0,line.Position.Z)
        distance=(a-b).Magnitude
        if carry>0 then timeToSafe=distance/carry end
    end

    return {
        Label=label,
        Ratio=ratio,
        FreeWalk=free,
        CarryWalk=carry,
        RequiredWalk=required,
        RequiredPower=requiredPower,
        Multiplier=mult,
        Distance=distance,
        TimeToSafe=timeToSafe,
        ContactOutcome=contactOutcomeFor(egg,visual,carry),
    }
end

local function riskColor(risk)
    local label=typeof(risk)=="table" and risk.Label or risk
    if label=="Seguro" then return Color3.fromRGB(75,255,111) end
    if label=="Viável" then return Color3.fromRGB(97,220,255) end
    if label=="Arriscado" then return Color3.fromRGB(255,197,63) end
    if label=="Alto risco" then return Color3.fromRGB(255,82,82) end
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
    if rarityRank(egg.Rarity,egg.RarityNumber)<CONFIG.MinRarity then return false end
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
        if risk then
            local pct=math.floor(risk.Ratio*100+0.5)
            lines[#lines+1]={
                Text=string.format("%s • %d%% • x%.3f",risk.Label,pct,risk.Multiplier),
                Color=riskColor(risk),
                Bold=true,
            }
        else
            lines[#lines+1]={Text="Viabilidade: ?",Color=riskColor(nil),Bold=true}
        end
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
    bb.Size=UDim2.fromOffset(172,54)
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
    rec.Billboard.Size=UDim2.fromOffset(172,math.max(28,#lines*13+3))
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
    local power=readSpeedPower()
    local free=riskFreeWalkSpeed()
    local boost=currentBoostFactor()
    local area=currentAreaName()
    local required,requiredPower=areaRequiredWalkSpeed(area)

    local refText="?"
    if finite(required) then
        refText=string.format("%.0f Walk",required)
        if finite(requiredPower) then refText=refText.." ("..formatCompact(requiredPower)..")" end
    elseif area=="Safe / corredor" then
        refText="sem exigência"
    end

    liveInfoLabel.Text="Speed Power: "..(power and formatCompact(power) or "?")
        .."\nWalk livre: "..(free and string.format("%.0f",free) or "?")
        .." • Boost "..(boost and ("x"..string.format("%.2f",boost)) or "?")
        .."\nÁrea: "..area
        .."\nReferência: "..refText
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


-- Auto Train uses the game's own treadmill flow:
-- own plot treadmill -> walk onto belt -> AskWearStill every 1.2s.
local AUTO_TRAIN_WEAR_INTERVAL=1.2

local function unwrapRemote(v)
    if typeof(v)=="Instance" then return v end
    if typeof(v)~="table" then return nil end
    for _,key in ipairs({"Remote","remote","Instance","_remote","_instance","Event"}) do
        if typeof(v[key])=="Instance" then return v[key] end
    end
    return v
end

local function resolveOwnPlot()
    if typeof(PlotState)~="table" then PlotState=requireOptional("Client.PlotState") end
    local info,ok=callTableFn(PlotState,"ResolvePlot")
    return ok and typeof(info)=="table" and info or nil
end

local function findTreadmillPart()
    local now=os.clock()
    local cached=State.AutoTrainBelt
    if cached and cached.Parent and now-(State.AutoTrainBeltAt or 0)<.85 then return cached end

    local belt
    local info=resolveOwnPlot()
    local folder=info and info.PlotFolder
    if folder then
        belt=folder:FindFirstChild("TreadmillBottom",true)
        if not (belt and belt:IsA("BasePart")) then
            belt=nil
            local bestVolume=-1
            for _,d in ipairs(folder:GetDescendants()) do
                if d:IsA("BasePart") then
                    local n=lower(d.Name)
                    if n:find("treadmill",1,true) or n=="bottom" or n:find("belt",1,true) then
                        local volume=d.Size.X*d.Size.Y*d.Size.Z
                        if volume>bestVolume then bestVolume=volume; belt=d end
                    end
                end
            end
        end
    end

    if not belt then
        local renders=Workspace:FindFirstChild("__ClientTreadmillRenders")
        local root=playerRoot()
        local bestDist=math.huge
        if renders and root then
            for _,d in ipairs(renders:GetDescendants()) do
                if d:IsA("BasePart") then
                    local n=lower(d.Name)
                    if n=="treadmillbottom" or n=="bottom" or n:find("belt",1,true) then
                        local dist=(d.Position-root.Position).Magnitude
                        if dist<bestDist then bestDist=dist; belt=d end
                    end
                end
            end
        end
    end

    State.AutoTrainBelt=belt
    State.AutoTrainBeltAt=now
    return belt
end

local function onTreadmill(root,belt)
    if not (root and belt and belt:IsA("BasePart")) then return false end
    local localPos=belt.CFrame:PointToObjectSpace(root.Position)
    local sx=belt.Size.X*.5+2
    local sz=belt.Size.Z*.5+2
    local inBounds=math.abs(localPos.X)<=sx and math.abs(localPos.Z)<=sz
    if inBounds then return math.abs(root.Position.Y-belt.Position.Y)<10 end
    local flat=Vector3.new(root.Position.X-belt.Position.X,0,root.Position.Z-belt.Position.Z).Magnitude
    return flat<6 and math.abs(root.Position.Y-belt.Position.Y)<10
end

local function treadmillTarget(belt)
    return belt and (belt.Position+Vector3.new(0,belt.Size.Y*.5+3.2,0)) or nil
end

local function treadmillRemote()
    if typeof(SharedRemotes)~="table" then SharedRemotes=requireOptional("Shared.Remotes") end
    local group=typeof(SharedRemotes)=="table" and SharedRemotes.Treadmill or nil
    return unwrapRemote(typeof(group)=="table" and group.AskWearStill or nil)
end

local function askWearStill()
    local remote=treadmillRemote()
    if not remote then return false,"remote ausente" end
    if typeof(remote)=="Instance" and remote:IsA("RemoteFunction") then
        local ok,result=pcall(function() return remote:InvokeServer() end)
        return ok and result==true, ok and result or "InvokeServer falhou"
    end
    if typeof(remote)=="table" and type(remote.InvokeServer)=="function" then
        local ok,result=pcall(function() return remote:InvokeServer() end)
        if not ok then ok,result=pcall(remote.InvokeServer,remote) end
        return ok and result==true, ok and result or "wrapper falhou"
    end
    return false,"remote inválido"
end

local function stopAutoTrainMovement()
    local hum=playerHumanoid()
    if hum then
        pcall(function() hum:Move(Vector3.zero,false) end)
    end
end

local function refreshAutoTrainStatus()
    if not autoTrainStatusLabel then return end
    if not CONFIG.AutoTrain then
        autoTrainStatusLabel.Text="Auto Train desativado"
        autoTrainStatusLabel.TextColor3=Color3.fromRGB(170,184,210)
        return
    end
    local rate=tonumber(State.AutoTrainRate) or 0
    local earned=tonumber(State.AutoTrainEarned) or 0
    autoTrainStatusLabel.Text=string.format(
        "%s • +%s/s • sessão +%s",
        State.AutoTrainStatus or "Auto Train",
        formatCompact(rate),
        formatCompact(earned)
    )
    autoTrainStatusLabel.TextColor3=Color3.fromRGB(139,164,207)
end

local function autoTrainTick()
    if not (State.Alive and CONFIG.AutoTrain) then return end

    local hum=playerHumanoid()
    local root=playerRoot()
    if not (hum and root) or hum.Health<=0 then
        State.AutoTrainStatus="Aguardando personagem"
        return
    end

    local power=readSpeedPower()
    local now=os.clock()
    if finite(power) then
        if finite(State.AutoTrainLastPower) and now>(State.AutoTrainLastPowerAt or 0) then
            local dt=now-(State.AutoTrainLastPowerAt or 0)
            if dt>.2 then
                local gain=math.max(0,power-State.AutoTrainLastPower)
                State.AutoTrainEarned=(State.AutoTrainEarned or 0)+gain
                State.AutoTrainRate=gain/dt
            end
        end
        State.AutoTrainLastPower=power
        State.AutoTrainLastPowerAt=now
    end

    local belt=findTreadmillPart()
    if not belt then
        State.AutoTrainStatus="Esteira não encontrada"
        return
    end

    local target=treadmillTarget(belt)
    if not onTreadmill(root,belt) then
        State.AutoTrainStatus="Indo para esteira"
        pcall(function()
            hum.PlatformStand=false
            hum.Sit=false
            hum:MoveTo(target)
        end)
        return
    end

    stopAutoTrainMovement()
    State.AutoTrainStatus="Treinando"

    if now-(State.AutoTrainLastWear or 0)>=AUTO_TRAIN_WEAR_INTERVAL then
        State.AutoTrainLastWear=now
        local ok,why=askWearStill()
        if ok then
            State.AutoTrainStatus="Treinando"
        else
            -- Remaining physically on the treadmill still lets the next tick retry.
            State.AutoTrainStatus="Na esteira • sincronizando"
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
                            State.LastCarryUid=payload.Uid
                            State.LastCarryServerMultiplier=State.CarryMultiplier
                        else
                            State.CarryMultiplier=1
                            State.LastCarryUid=nil
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
        elseif key=="AutoTrain" then
            if CONFIG.AutoTrain then
                State.AutoTrainStatus="Ativando"
                State.AutoTrainLastWear=0
                State.AutoTrainBelt=nil
                State.AutoTrainBeltAt=0
            else
                State.AutoTrainStatus="Desativado"
                stopAutoTrainMovement()
            end
            refreshAutoTrainStatus()
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

for _,oldName in ipairs({"PsicoRoubeUmOvoV83","PsicoRoubeUmOvoV821","PsicoRoubeUmOvoV82","PsicoRoubeUmOvoV811","PsicoRoubeUmOvoV81","PsicoRoubeUmOvoV8","PsicoRoubeUmOvo"}) do
    local old=uiParent():FindFirstChild(oldName)
    if old then pcall(function() old:Destroy() end) end
end

gui=Instance.new("ScreenGui")
gui.Name="PsicoRoubeUmOvoV83"
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
local version=mkLabel(mainFrame,"V8.3 • CARRY MARGIN",UDim2.fromOffset(12,24),UDim2.new(1,-84,0,14),8)
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
local tabFusion=mkButton(sidebar,"FUSÃO",UDim2.fromOffset(0,100),UDim2.new(1,0,0,42))

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
mainPage.CanvasSize=UDim2.fromOffset(0,222)
mainPage.ScrollBarThickness=3
mainPage.ScrollBarImageColor3=Color3.fromRGB(94,139,223)
mainPage.Parent=contentHost

local filterPage=Instance.new("ScrollingFrame")
filterPage.BackgroundTransparency=1
filterPage.BorderSizePixel=0
filterPage.Position=UDim2.fromOffset(8,8)
filterPage.Size=UDim2.new(1,-16,1,-16)
filterPage.CanvasSize=UDim2.fromOffset(0,520)
filterPage.ScrollBarThickness=3
filterPage.ScrollBarImageColor3=Color3.fromRGB(94,139,223)
filterPage.Visible=false
filterPage.Parent=contentHost

local fusionPage=Instance.new("Frame")
fusionPage.BackgroundTransparency=1
fusionPage.BorderSizePixel=0
fusionPage.Position=UDim2.fromOffset(8,8)
fusionPage.Size=UDim2.new(1,-16,1,-16)
fusionPage.Visible=false
fusionPage.Parent=contentHost

local FUSION_SORT_MODES={"VALOR + MUT","$/S","PESO","PET"}
local fusionSortButton=mkButton(fusionPage,"CLASSIFICAR: VALOR + MUT",UDim2.fromOffset(0,0),UDim2.new(.67,-3,0,27))
local fusionRefreshButton=mkButton(fusionPage,"ATUALIZAR",UDim2.new(.68,0,0,0),UDim2.new(.32,0,0,27))
local fusionStatusLabel=mkLabel(fusionPage,"0/3 • selecione 3 do mesmo pet",UDim2.fromOffset(2,31),UDim2.new(.76,-2,0,21),8)
fusionStatusLabel.TextColor3=Color3.fromRGB(139,164,207)
local fusionClearButton=mkButton(fusionPage,"LIMPAR",UDim2.new(.78,0,0,31),UDim2.new(.22,0,0,21))
fusionClearButton.TextSize=8

local fusionList=Instance.new("ScrollingFrame")
fusionList.BackgroundColor3=Color3.fromRGB(16,24,38)
fusionList.BackgroundTransparency=.18
fusionList.BorderSizePixel=0
fusionList.Position=UDim2.fromOffset(0,57)
fusionList.Size=UDim2.new(1,0,1,-57)
fusionList.CanvasSize=UDim2.fromOffset(0,0)
fusionList.ScrollBarThickness=3
fusionList.ScrollBarImageColor3=Color3.fromRGB(94,139,223)
fusionList.Parent=fusionPage
round(fusionList,8)

local function fusionCallTable(tbl,name,...)
    if typeof(tbl)~="table" or type(tbl[name])~="function" then return false,nil,"função ausente" end
    local fn=tbl[name]
    local args=table.pack(...)
    local r=table.pack(pcall(fn,table.unpack(args,1,args.n)))
    if r[1] then return true,table.unpack(r,2,r.n) end
    r=table.pack(pcall(fn,tbl,table.unpack(args,1,args.n)))
    if r[1] then return true,table.unpack(r,2,r.n) end
    return false,nil,tostring(r[2])
end

local function fusionCurrentSave()
    if typeof(SaveData)~="table" then SaveData=requireOptional("Shared.Save") end
    if typeof(SaveData)~="table" then return nil end
    for _,name in ipairs({"Peek","Get"}) do
        if type(SaveData[name])=="function" then
            local ok,data=fusionCallTable(SaveData,name)
            if ok and typeof(data)=="table" then return data end
        end
    end
    if type(SaveData.Await)=="function" then
        local ok,data=fusionCallTable(SaveData,"Await")
        if ok and typeof(data)=="table" then return data end
    end
    return nil
end

local function fusionDecode(raw)
    if typeof(AssetItems)~="table" then AssetItems=requireOptional("Shared.Util.AssetItems") end
    if typeof(AssetItems)=="table" and type(AssetItems.Decode)=="function" then
        local ok,item=fusionCallTable(AssetItems,"Decode",raw)
        if ok and typeof(item)=="table" then return item end
    end
    return typeof(raw)=="table" and raw or nil
end

local function fusionAssetConfig(category)
    if typeof(AssetsData)~="table" then return nil end
    local dir=AssetsData.Directory or AssetsData.Configs
    return typeof(dir)=="table" and dir[category] or nil
end

local function fusionMutationNames(item)
    local out,seen={},{}
    local function add(v)
        if v==nil then return end
        local name
        if typeof(v)=="table" then
            name=v._id or v.DisplayName or v.Name or v.Id
        else
            name=v
        end
        name=name and safeString(name) or nil
        local key=name and normalize(name) or ""
        if key~="" and not seen[key] then
            seen[key]=true
            out[#out+1]=name
        end
    end
    add(item and item.BaseMutation)
    if item and typeof(item.Mutations)=="table" then
        for _,m in pairs(item.Mutations) do add(m) end
    end
    table.sort(out,function(a,b) return searchText(a)<searchText(b) end)
    return out
end

local function fusionPetRate(item)
    if typeof(AssetEarnings)~="table" then return 0 end
    for _,name in ipairs({"CatalogRatePerSecond","MutationOnlyRatePerSecond"}) do
        if type(AssetEarnings[name])=="function" then
            local target=item
            if name=="MutationOnlyRatePerSecond" then
                target={
                    Category=item.Category or item.AssetCategory,
                    Scale=item.Scale or item.AssetScale,
                    Mutations=item.Mutations or {},
                }
            end
            local ok,value=fusionCallTable(AssetEarnings,name,target)
            if ok and finite(tonumber(value)) then return tonumber(value) end
        end
    end
    return 0
end

local function fusionPetWeight(item)
    if typeof(AssetItems)=="table" and type(AssetItems.WeightKg)=="function" then
        local ok,value=fusionCallTable(AssetItems,"WeightKg",item)
        if ok and finite(tonumber(value)) then return tonumber(value) end
    end
    return tonumber(item.Weight or item.AssetWeight or item.Kg or item.Mass) or 0
end

local function fusionMayEnter(item,cfg)
    if not item then return false end
    if item.InFuse==true or item.IsFavorite==true or item.Favorite==true then return false end
    if cfg and cfg.CannotFuse==true then return false end
    if typeof(FuseKernel)~="table" then FuseKernel=requireOptional("Shared.Util.FuseKernel") end
    if typeof(FuseKernel)=="table" and type(FuseKernel.MayEnterFuse)=="function" then
        local ok,allowed=fusionCallTable(FuseKernel,"MayEnterFuse",item)
        if ok and type(allowed)=="boolean" then return allowed end
    end
    return true
end

local function fusionInventoryEntries()
    local save=fusionCurrentSave()
    local inventory=save and save.Inventory
    if typeof(inventory)~="table" then return {},save end
    local equipped=typeof(save.EquippedAssets)=="table" and save.EquippedAssets or {}
    local out={}
    for uid,raw in pairs(inventory) do
        local item=fusionDecode(raw)
        if item and item.Category then
            local category=safeString(item.Category)
            local cfg=fusionAssetConfig(category)
            if not equipped[uid] and fusionMayEnter(item,cfg) then
                local mutations=fusionMutationNames(item)
                local display=(cfg and cfg.DisplayName) or item.DisplayName or category
                local rarity=cfg and cfg.Rarity
                local rarityName=rarity and (rarity.DisplayName or rarity._id) or "?"
                out[#out+1]={
                    uid=safeString(uid),
                    category=category,
                    displayName=localizedPetName(display),
                    rarity=safeString(rarityName),
                    mutations=mutations,
                    hasMutation=#mutations>0,
                    rate=fusionPetRate(item),
                    weight=fusionPetWeight(item),
                    scale=tonumber(item.Scale or item.AssetScale) or 1,
                    item=item,
                }
            end
        end
    end
    return out,save
end

local function fusionSelectedMap()
    local map={}
    for _,entry in ipairs(State.FusionSelected) do map[entry.uid]=true end
    return map
end

local function fusionSelectedCategory()
    return State.FusionSelected[1] and State.FusionSelected[1].category or nil
end

local function fusionUpdateStatus(message,color)
    if not fusionStatusLabel then return end
    if message then
        fusionStatusLabel.Text=message
        fusionStatusLabel.TextColor3=color or Color3.fromRGB(139,164,207)
        return
    end
    local total=0
    for _,entry in ipairs(State.FusionSelected) do total+=tonumber(entry.rate) or 0 end
    local cat=fusionSelectedCategory()
    fusionStatusLabel.Text=string.format(
        "%d/3%s • total %s/s",
        #State.FusionSelected,
        cat and (" • "..safeString(State.FusionSelected[1].displayName)) or "",
        formatCompact(total)
    )
    fusionStatusLabel.TextColor3=Color3.fromRGB(139,164,207)
end

local refreshFusionList
local runSelectedFusion

local function fusionSortEntries(entries)
    local mode=FUSION_SORT_MODES[State.FusionSortMode] or FUSION_SORT_MODES[1]
    local selectedCategory=fusionSelectedCategory()
    table.sort(entries,function(a,b)
        if selectedCategory then
            local ac=a.category==selectedCategory
            local bc=b.category==selectedCategory
            if ac~=bc then return ac end
        end
        if mode=="VALOR + MUT" then
            if a.hasMutation~=b.hasMutation then return a.hasMutation end
            if a.rate~=b.rate then return a.rate>b.rate end
            if a.weight~=b.weight then return a.weight>b.weight end
        elseif mode=="$/S" then
            if a.rate~=b.rate then return a.rate>b.rate end
            if a.hasMutation~=b.hasMutation then return a.hasMutation end
        elseif mode=="PESO" then
            if a.weight~=b.weight then return a.weight>b.weight end
            if a.rate~=b.rate then return a.rate>b.rate end
        else
            local an,bn=searchText(a.displayName),searchText(b.displayName)
            if an~=bn then return an<bn end
            if a.rate~=b.rate then return a.rate>b.rate end
        end
        return a.uid<b.uid
    end)
end

local function fusionRemoveSelected(uid)
    for i=#State.FusionSelected,1,-1 do
        if State.FusionSelected[i].uid==uid then table.remove(State.FusionSelected,i) end
    end
end

local function fusionInvoke(name,...)
    if typeof(SharedRemotes)~="table" then SharedRemotes=requireOptional("Shared.Remotes") end
    local group=typeof(SharedRemotes)=="table" and SharedRemotes.Fusery or nil
    local remote=typeof(group)=="table" and group[name] or nil
    remote=unwrapRemote(remote)
    if not remote then return false,nil,"remote "..name.." ausente" end
    local args=table.pack(...)
    if typeof(remote)=="Instance" and remote:IsA("RemoteFunction") then
        local r=table.pack(pcall(function() return remote:InvokeServer(table.unpack(args,1,args.n)) end))
        if not r[1] then return false,nil,tostring(r[2]) end
        return true,table.unpack(r,2,r.n)
    end
    if typeof(remote)=="table" and type(remote.InvokeServer)=="function" then
        local r=table.pack(pcall(remote.InvokeServer,remote,table.unpack(args,1,args.n)))
        if not r[1] then
            r=table.pack(pcall(remote.InvokeServer,table.unpack(args,1,args.n)))
        end
        if not r[1] then return false,nil,tostring(r[2]) end
        return true,table.unpack(r,2,r.n)
    end
    return false,nil,"remote inválido"
end

local function fusionRewardText(reward)
    if typeof(reward)~="table" then return "Fusão concluída" end
    local category=reward.AssetCategory or reward.Category
    local cfg=category and fusionAssetConfig(category) or nil
    local name=localizedPetName((cfg and cfg.DisplayName) or category or "Pet")
    local muts=fusionMutationNames({Mutations=reward.Mutations or {},BaseMutation=reward.BaseMutation})
    local item={
        Category=category,
        AssetCategory=category,
        Scale=reward.AssetScale or reward.Scale or 1,
        AssetScale=reward.AssetScale or reward.Scale or 1,
        Mutations=reward.Mutations or {},
        BaseMutation=reward.BaseMutation,
    }
    local rate=fusionPetRate(item)
    local mutText=#muts>0 and table.concat(muts,", ") or "sem mutação"
    return string.format("%s • %s/s • %.3fx • %s",name,formatCompact(rate),tonumber(item.Scale) or 1,mutText)
end

runSelectedFusion=function()
    if State.FusionBusy or #State.FusionSelected~=3 then return end
    State.FusionBusy=true
    fusionUpdateStatus("3/3 • preparando fusão...",Color3.fromRGB(255,204,102))

    local selected={}
    for i,entry in ipairs(State.FusionSelected) do selected[i]=entry end
    local category=selected[1].category
    for i=2,3 do
        if selected[i].category~=category then
            fusionUpdateStatus("Os 3 precisam ser do mesmo pet.",Color3.fromRGB(255,115,115))
            State.FusionBusy=false
            return
        end
    end

    local save=fusionCurrentSave()
    local inventory=save and save.Inventory
    if typeof(inventory)~="table" then
        fusionUpdateStatus("Inventário indisponível.",Color3.fromRGB(255,115,115))
        State.FusionBusy=false
        return
    end

    local fresh={}
    for i,entry in ipairs(selected) do
        local raw=inventory[entry.uid]
        local item=raw and fusionDecode(raw)
        if not item or safeString(item.Category)~=category then
            fusionUpdateStatus("Um pet saiu do inventário. Atualize a lista.",Color3.fromRGB(255,115,115))
            State.FusionBusy=false
            task.defer(refreshFusionList)
            return
        end
        fresh[i]={uid=entry.uid,item=item}
    end

    if typeof(FuseKernel)=="table" and type(FuseKernel.PriceFor)=="function" then
        local items={fresh[1].item,fresh[2].item,fresh[3].item}
        local ok,price=fusionCallTable(FuseKernel,"PriceFor",items)
        local money=tonumber(save.Money)
        if ok and finite(tonumber(price)) and money and money<tonumber(price) then
            fusionUpdateStatus("Dinheiro insuficiente • custo "..formatCompact(tonumber(price)),Color3.fromRGB(255,115,115))
            State.FusionBusy=false
            return
        end
    end

    -- Keep remote FusionSlots clean so the three menu selections are exactly
    -- the three pets consumed by this fusion.
    for _,uid in ipairs(save.FusionSlots or {}) do
        fusionInvoke("EjectPet",uid)
        task.wait(.05)
    end

    local loaded={}
    for i=1,3 do
        fusionUpdateStatus(string.format("Carregando pet %d/3...",i),Color3.fromRGB(255,204,102))
        local ok,accepted,reason=fusionInvoke("LoadPet",fresh[i].uid)
        if not ok or accepted~=true then
            for _,uid in ipairs(loaded) do fusionInvoke("EjectPet",uid) end
            fusionUpdateStatus("Falha ao carregar: "..safeString(reason or accepted or "?"),Color3.fromRGB(255,115,115))
            State.FusionBusy=false
            task.defer(refreshFusionList)
            return
        end
        loaded[#loaded+1]=fresh[i].uid
        task.wait(.07)
    end

    fusionUpdateStatus("Fundindo...",Color3.fromRGB(255,204,102))
    local ok,accepted,reason,reward=fusionInvoke("BeginFuse")
    if not ok or accepted~=true then
        for _,uid in ipairs(loaded) do fusionInvoke("EjectPet",uid) end
        fusionUpdateStatus("Fusão recusada: "..safeString(reason or accepted or "?"),Color3.fromRGB(255,115,115))
        State.FusionBusy=false
        task.defer(refreshFusionList)
        return
    end

    local granted=false
    for _=1,5 do
        task.wait(.12)
        local ok2,accepted2=fusionInvoke("FinishReveal")
        if ok2 and accepted2==true then granted=true break end
    end

    State.FusionLastResult=reward
    State.FusionSelected={}
    local resultText=fusionRewardText(reward)
    if not granted then resultText=resultText.." • recompensa pendente" end
    fusionUpdateStatus("✓ "..resultText,Color3.fromRGB(111,220,143))
    State.FusionBusy=false
    task.wait(.15)
    refreshFusionList(true)
end

refreshFusionList=function(keepMessage)
    if not fusionList then return end
    for _,child in ipairs(fusionList:GetChildren()) do
        if child:IsA("GuiObject") then child:Destroy() end
    end

    local entries=fusionInventoryEntries()
    local availableMap={}
    for _,entry in ipairs(entries) do availableMap[entry.uid]=entry end
    for i=#State.FusionSelected,1,-1 do
        local current=availableMap[State.FusionSelected[i].uid]
        if not current then
            table.remove(State.FusionSelected,i)
        else
            State.FusionSelected[i]=current
        end
    end

    fusionSortEntries(entries)
    local selected=fusionSelectedMap()
    local selectedCategory=fusionSelectedCategory()
    local y=2

    if #entries==0 then
        local empty=mkLabel(fusionList,"Nenhum pet disponível para fusão.",UDim2.fromOffset(8,8),UDim2.new(1,-16,0,26),9)
        empty.TextColor3=Color3.fromRGB(150,165,190)
        fusionList.CanvasSize=UDim2.fromOffset(0,42)
    else
        for _,entry in ipairs(entries) do
            local isSelected=selected[entry.uid]==true
            local compatible=(not selectedCategory) or entry.category==selectedCategory or isSelected
            local mutText=entry.hasMutation and table.concat(entry.mutations,", ") or "sem mutação"
            local prefix=isSelected and "✓ " or ""
            local text=string.format(
                "%s%s • %s • %s\n%s/s • %s Kg • %.3fx",
                prefix,
                safeString(entry.displayName),
                safeString(entry.rarity),
                mutText,
                formatCompact(entry.rate),
                formatCompact(entry.weight),
                entry.scale
            )
            local row=mkButton(fusionList,text,UDim2.fromOffset(2,y),UDim2.new(1,-7,0,43))
            row.TextXAlignment=Enum.TextXAlignment.Left
            row.TextYAlignment=Enum.TextYAlignment.Center
            row.TextWrapped=true
            row.TextSize=8
            if isSelected then
                row.BackgroundColor3=Color3.fromRGB(42,91,190)
            elseif not compatible then
                row.BackgroundColor3=Color3.fromRGB(28,34,47)
                row.TextColor3=Color3.fromRGB(100,112,132)
            elseif entry.hasMutation then
                row.BackgroundColor3=Color3.fromRGB(47,45,72)
            end
            connect(row.MouseButton1Click,function()
                if State.FusionBusy then return end
                if selected[entry.uid] then
                    fusionRemoveSelected(entry.uid)
                    fusionUpdateStatus()
                    refreshFusionList()
                    return
                end
                local cat=fusionSelectedCategory()
                if cat and entry.category~=cat then
                    fusionUpdateStatus("Escolha 3 do mesmo pet • atual: "..safeString(State.FusionSelected[1].displayName),Color3.fromRGB(255,166,102))
                    return
                end
                if #State.FusionSelected>=3 then return end
                State.FusionSelected[#State.FusionSelected+1]=entry
                fusionUpdateStatus()
                refreshFusionList()
                if #State.FusionSelected==3 then task.defer(runSelectedFusion) end
            end)
            y+=47
        end
        fusionList.CanvasSize=UDim2.fromOffset(0,math.max(y+2,1))
    end

    if not keepMessage and not State.FusionBusy then fusionUpdateStatus() end
end

connect(fusionSortButton.MouseButton1Click,function()
    if State.FusionBusy then return end
    State.FusionSortMode=State.FusionSortMode%#FUSION_SORT_MODES+1
    fusionSortButton.Text="CLASSIFICAR: "..FUSION_SORT_MODES[State.FusionSortMode]
    refreshFusionList()
end)

connect(fusionRefreshButton.MouseButton1Click,function()
    if not State.FusionBusy then refreshFusionList() end
end)

connect(fusionClearButton.MouseButton1Click,function()
    if State.FusionBusy then return end
    State.FusionSelected={}
    fusionUpdateStatus()
    refreshFusionList()
end)

espToggleButton=makeMainToggle(mainPage,"ESP • Ovos",0,"EggESP")
promptToggleButton=makeMainToggle(mainPage,"Instant Prompt",38,"InstantPrompt")
hitToggleButton=makeMainToggle(mainPage,"Instant Hit • Bat",76,"InstantHit")
autoTrainToggleButton=makeMainToggle(mainPage,"Auto Train • Esteira",114,"AutoTrain")
autoTrainStatusLabel=mkLabel(mainPage,"Inicializando Auto Train...",UDim2.fromOffset(4,150),UDim2.new(1,-8,0,24),8)
autoTrainStatusLabel.TextXAlignment=Enum.TextXAlignment.Center
autoTrainStatusLabel.TextColor3=Color3.fromRGB(139,164,207)
local refreshButton=mkButton(mainPage,"Atualizar ovos",UDim2.fromOffset(0,180),UDim2.new(1,0,0,32))

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
makeInlineToggle(filterPage,"Mostrar viabilidade",filterY,"ShowRisk"); filterY=filterY+30
makeInlineToggle(filterPage,"Usar boost atual",filterY,"BoostAuto"); filterY=filterY+36

local liveCard=Instance.new("Frame")
liveCard.Position=UDim2.fromOffset(0,filterY)
liveCard.Size=UDim2.new(1,-4,0,82)
liveCard.BackgroundColor3=Color3.fromRGB(20,31,50)
liveCard.BorderSizePixel=0
liveCard.Parent=filterPage
round(liveCard,9)
liveInfoLabel=mkLabel(liveCard,"Speed Power: ?\nWalk livre: ?\nÁrea: ?\nReferência: ?",UDim2.fromOffset(10,7),UDim2.new(1,-20,1,-14),9)
liveInfoLabel.TextColor3=Color3.fromRGB(176,203,245)
liveInfoLabel.TextYAlignment=Enum.TextYAlignment.Top
filterY=filterY+90
local resetFilters=mkButton(filterPage,"Limpar filtros",UDim2.fromOffset(0,filterY),UDim2.new(1,-4,0,30)); filterY=filterY+36
filterPage.CanvasSize=UDim2.fromOffset(0,filterY)

statusLabel=mkLabel(mainFrame,"Carregando dados...",UDim2.new(0,12,1,-24),UDim2.new(1,-24,0,16),8)
statusLabel.TextXAlignment=Enum.TextXAlignment.Center
statusLabel.TextColor3=Color3.fromRGB(139,164,207)

local function showPage(which)
    local filters=(which=="filters")
    local fusion=(which=="fusion")
    local main=(which=="main")
    mainPage.Visible=main
    filterPage.Visible=filters
    fusionPage.Visible=fusion
    tabMain.BackgroundColor3=main and Color3.fromRGB(42,91,190) or Color3.fromRGB(35,44,61)
    tabFilters.BackgroundColor3=filters and Color3.fromRGB(42,91,190) or Color3.fromRGB(35,44,61)
    tabFusion.BackgroundColor3=fusion and Color3.fromRGB(42,91,190) or Color3.fromRGB(35,44,61)
    if fusion and not State.FusionBusy then task.defer(refreshFusionList) end
end
connect(tabMain.MouseButton1Click,function() showPage("main") end)
connect(tabFilters.MouseButton1Click,function() showPage("filters") end)
connect(tabFusion.MouseButton1Click,function() showPage("fusion") end)
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
    table.sort(out,function(a,b)
        return searchText(a.PetNameLocalized or a.PetName)<searchText(b.PetNameLocalized or b.PetName)
    end)
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
    local q=searchText(query or "")
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
        local canonical=safeString(entry.PetName)
        local name=safeString(entry.PetNameLocalized or localizedPetName(canonical))
        local rarity=safeString(entry.Rarity or "?")
        local localizedSearch=searchText(name)
        local canonicalSearch=searchText(canonical)
        if q=="" or localizedSearch:find(q,1,true) or canonicalSearch:find(q,1,true) or searchText(rarity):find(q,1,true) then
            local row=mkButton(petList,name.."  •  "..rarity,UDim2.fromOffset(0,y),UDim2.new(1,-4,0,28))
            row.TextXAlignment=Enum.TextXAlignment.Left
            row.ZIndex=32
            row.TextColor3=rarityFallbackColor(rarity)
            connect(row.MouseButton1Click,function()
                -- Store the canonical game name for filtering, but show Portuguese.
                CONFIG.SelectedPet=canonical
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
    refreshFusionList()
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
    State.LastCarryUid=nil
    State.AutoTrainLastWear=0
    State.AutoTrainLastPower=nil
    State.AutoTrainLastPowerAt=0
    State.AutoTrainBelt=nil
    State.AutoTrainBeltAt=0
    if CONFIG.AutoTrain then State.AutoTrainStatus="Aguardando personagem" end
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
    stopAutoTrainMovement()
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
updateToggleVisual(autoTrainToggleButton,CONFIG.AutoTrain)
refreshAutoTrainStatus()

task.defer(function()
    task.wait(.4)
    if State.Alive then initializeData() end
end)

task.defer(function()
    while State.Alive do
        task.wait(.65)
        if CONFIG.EggESP then refreshESP() end
        if CONFIG.InstantHit then refreshBats() end
        if CONFIG.AutoTrain then autoTrainTick() end
        refreshAutoTrainStatus()
        refreshStatus()
        refreshLiveInfo()
    end
end)

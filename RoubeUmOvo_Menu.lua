--[[
PSICOSENATICO | Roube um Ovo - Precision Menu V8.1.1
Stable loader path: RoubeUmOvo_Menu.lua

Changes in V8.1.1
  * HOTFIX: ESP filters never destroy the game's egg visual/model.
  * ESP cleanup now destroys only PSICOSENATICO-owned Highlight/Billboard objects.
  * Compact, fully transparent ESP text (no pet image / no info background).
  * ESP keeps metadata for Slot and Dropped eggs.
  * Responsive menu: reads viewport size and scales itself to <= 70% screen height.
  * Left vertical navigation + scrollable content.
  * Smart K/M/B/T number inputs for weight/value filters.
  * Pet picker with search, full catalog and "available now" mode.

Ground truth from Scanner V7
  * Egg metadata: ReplicatedStorage.Data.Assets
  * Weight/value/name: ReplicatedStorage.Shared.Util.EggRecords
  * Current eggs: EggWorld snapshots/events
]]

if _G.PSICO_ROUBE_SCANNER_CLEANUP then pcall(_G.PSICO_ROUBE_SCANNER_CLEANUP) end
if _G.PSICO_ROUBE_MENU_CLEANUP then pcall(_G.PSICO_ROUBE_MENU_CLEANUP) end

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CoreGui = game:GetService("CoreGui")
local UIS = game:GetService("UserInputService")

local LP = Players.LocalPlayer

local CONFIG = {
    EggESP = true,
    InstantPrompt = true,
    InstantHit = true,
    MinRarity = 0,
    MinWeightKg = 0,
    MinSellPrice = 0,
    SelectedPet = "",
    MutationMode = "Todas",
    PetListAvailableOnly = false,
    MaxEspDistance = 10000,
}

local RARITY_ORDER = {
    "Common","Uncommon","Rare","Epic","Legendary",
    "Mythic","Cosmic","Secret","Eternal","Divine"
}

local State = {
    Alive = true,
    Connections = {},
    RemoteConnections = {},
    RawRecords = {},
    Eggs = {},
    CatalogIndex = {},
    CatalogEntries = {},
    RarityMeta = {},
    ESP = {},
    PromptOriginals = setmetatable({}, {__mode="k"}),
    BatOriginals = setmetatable({}, {__mode="k"}),
    WatchedBats = setmetatable({}, {__mode="k"}),
    Stats = {EspVisible=0,CatalogPets=0,CatalogRarities=0},
    LastError = nil,
}

local AssetsData
local EggRecords
local gui
local mainFrame
local uiScale
local floatButton
local statusLabel
local rarityButton
local mutationButton
local petButton
local availabilityButton
local espToggleButton
local promptToggleButton
local hitToggleButton
local petModal
local petSearchBox
local petList

local function safeString(v)
    local ok,s = pcall(tostring,v)
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
    local c = signal:Connect(fn)
    table.insert(bucket or State.Connections,c)
    return c
end

local function disconnect(c)
    pcall(function() c:Disconnect() end)
end

local function countMap(t)
    local n=0
    for _ in pairs(t) do n=n+1 end
    return n
end

local function uiParent()
    local ok,h = pcall(function() if gethui then return gethui() end end)
    return (ok and h) or CoreGui
end

local function findExact(className,name)
    for _,d in ipairs(ReplicatedStorage:GetDescendants()) do
        if d.ClassName==className and d.Name==name then return d end
    end
end

local function resolveModules()
    local data = ReplicatedStorage:FindFirstChild("Data")
    local assetsModule = data and data:FindFirstChild("Assets")
    local shared = ReplicatedStorage:FindFirstChild("Shared")
    local util = shared and shared:FindFirstChild("Util")
    local recordsModule = util and util:FindFirstChild("EggRecords")
    if not (assetsModule and assetsModule:IsA("ModuleScript")) then return false,"Data.Assets ausente" end
    if not (recordsModule and recordsModule:IsA("ModuleScript")) then return false,"EggRecords ausente" end
    local aok,a = pcall(require,assetsModule)
    if not aok or typeof(a)~="table" then return false,"Assets require falhou" end
    local rok,r = pcall(require,recordsModule)
    if not rok or typeof(r)~="table" then return false,"EggRecords require falhou" end
    AssetsData = a
    EggRecords = r
    return true
end

local function indexEntry(key,cfg)
    if typeof(cfg)~="table" or typeof(cfg.Egg)~="table" or typeof(cfg.Rarity)~="table" then return false end
    local rarity = cfg.Rarity
    local egg = cfg.Egg
    local entry = {
        Key = safeString(key),
        PetName = cfg.DisplayName or safeString(key),
        EggName = egg.DisplayName,
        BaseWeightKg = egg.WeightKg,
        Rarity = rarity.DisplayName or rarity._id,
        RarityId = rarity._id or rarity.DisplayName,
        RarityNumber = rarity.RarityNumber,
        RarityOdds = rarity.DefaultRarityValue,
        RarityColor = rarity.Color,
        GrowthTime = egg.GrowthTime,
        EarningRate = cfg.EarningRate,
        ModelWeight = cfg.ModelWeight,
        VisualOdds = cfg.VisualOdds,
    }
    for _,name in ipairs({entry.Key,entry.PetName,entry.EggName}) do
        if type(name)=="string" and name~="" then
            State.CatalogIndex[normalize(name)] = entry
            local noEgg = name:gsub("%s+[Ee][Gg][Gg]$","")
            local nk = normalize(noEgg)
            if not State.CatalogIndex[nk] then State.CatalogIndex[nk]=entry end
        end
    end
    State.CatalogEntries[#State.CatalogEntries+1] = entry
    if entry.RarityId then
        State.RarityMeta[entry.RarityId] = {
            Name=entry.Rarity,
            Number=entry.RarityNumber,
            Odds=entry.RarityOdds,
            Color=entry.RarityColor,
        }
    end
    return true
end

local function buildCatalog()
    State.CatalogIndex = {}
    State.CatalogEntries = {}
    State.RarityMeta = {}
    local found=0
    if typeof(AssetsData)~="table" then return false end
    if typeof(AssetsData.ByRarity)=="table" then
        for _,group in pairs(AssetsData.ByRarity) do
            if typeof(group)=="table" then
                for key,cfg in pairs(group) do
                    if indexEntry(key,cfg) then found=found+1 end
                end
            end
        end
    end
    if found==0 and typeof(AssetsData.Configs)=="table" then
        for key,cfg in pairs(AssetsData.Configs) do
            if indexEntry(key,cfg) then found=found+1 end
        end
    end
    table.sort(State.CatalogEntries,function(a,b)
        local ar,br = tonumber(a.RarityNumber) or 999,tonumber(b.RarityNumber) or 999
        if ar==br then return safeString(a.PetName)<safeString(b.PetName) end
        return ar<br
    end)
    State.Stats.CatalogPets = found
    State.Stats.CatalogRarities = countMap(State.RarityMeta)
    return found>0
end

local function findCatalog(assetCategory)
    if type(assetCategory)~="string" then return nil end
    return State.CatalogIndex[normalize(assetCategory)]
end

local function callEggFn(name,record)
    if typeof(EggRecords)~="table" then return nil,false end
    local fn = EggRecords[name]
    if type(fn)~="function" then return nil,false end
    local ok,v = pcall(fn,record)
    if ok then return v,true end
    local ok2,v2 = pcall(fn,EggRecords,record)
    if ok2 then return v2,true end
    return nil,false
end

local function copyMutations(v)
    local out={}
    if typeof(v)=="table" then
        for _,m in pairs(v) do out[#out+1]=safeString(m) end
        table.sort(out)
    end
    return out
end

local function visualForUid(uid)
    local folder = Workspace:FindFirstChild("AreaEggSlotsClient")
    if folder then
        local model = folder:FindFirstChild(uid)
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

local function validEggState(state)
    return state=="Slot" or state=="Dropped"
end

local function enrichRecord(record,source)
    if typeof(record)~="table" or type(record.Uid)~="string" or not validEggState(record.State) then return false end
    local cfg = findCatalog(record.AssetCategory)
    local weight,wok = callEggFn("WeightKg",record)
    local weightLabel,lok = callEggFn("WeightLabel",record)
    local sell,sok = callEggFn("SellPrice",record)
    local gameName,nok = callEggFn("DisplayName",record)
    local withWeight,dok = callEggFn("DisplayNameWithWeight",record)
    local uid = record.Uid
    State.RawRecords[uid] = record
    State.Eggs[uid] = {
        Uid=uid,
        Source=source,
        State=record.State,
        AreaId=record.AreaId,
        NestId=record.NestId,
        AssetCategory=record.AssetCategory,
        AssetScale=record.AssetScale,
        NestScale=record.NestScale,
        BaseMutation=record.BaseMutation,
        Mutations=copyMutations(record.Mutations),
        HasParasite=record.HasParasite==true,
        PetName=cfg and cfg.PetName or record.AssetCategory,
        EggName=cfg and cfg.EggName or nil,
        Rarity=cfg and cfg.Rarity or record.Rarity,
        RarityId=cfg and cfg.RarityId or nil,
        RarityNumber=cfg and cfg.RarityNumber or nil,
        RarityOdds=cfg and cfg.RarityOdds or nil,
        RarityColor=cfg and cfg.RarityColor or nil,
        BaseWeightKg=cfg and cfg.BaseWeightKg or nil,
        GrowthTime=cfg and cfg.GrowthTime or nil,
        EarningRate=cfg and cfg.EarningRate or nil,
        ModelWeight=cfg and cfg.ModelWeight or nil,
        VisualOdds=cfg and cfg.VisualOdds or nil,
        WeightKg=(wok and finite(weight)) and weight or nil,
        WeightLabel=lok and safeString(weightLabel) or nil,
        SellPrice=(sok and finite(sell)) and sell or nil,
        GameDisplayName=nok and safeString(gameName) or nil,
        DisplayNameWithWeight=dok and safeString(withWeight) or nil,
    }
    return true
end

local function removeEgg(uid)
    if type(uid)~="string" then return end
    State.RawRecords[uid]=nil
    State.Eggs[uid]=nil
end

local function ingestTree(value,source,seen,depth)
    if typeof(value)~="table" then return 0 end
    seen=seen or {}
    depth=depth or 0
    if depth>8 or seen[value] then return 0 end
    seen[value]=true
    local found=0
    if type(value.Uid)=="string" and value.State~=nil then
        if validEggState(value.State) then
            if enrichRecord(value,source) then found=found+1 end
        else
            removeEgg(value.Uid)
        end
    else
        pcall(function()
            local n=0
            for _,child in pairs(value) do
                n=n+1
                if n>2200 then break end
                if typeof(child)=="table" then found=found+ingestTree(child,source,seen,depth+1) end
            end
        end)
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
            if ok then total=total+ingestTree(res,"snapshot:"..name) end
        end
    end
    return total
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
    s=s:gsub("%s+",""):gsub("%$",""):gsub("KG","")
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
        Common=Color3.fromRGB(210,210,210),
        Uncommon=Color3.fromRGB(91,210,116),
        Rare=Color3.fromRGB(77,151,255),
        Epic=Color3.fromRGB(181,91,255),
        Legendary=Color3.fromRGB(255,174,58),
        Mythic=Color3.fromRGB(255,71,121),
        Cosmic=Color3.fromRGB(150,67,255),
        Secret=Color3.fromRGB(245,245,245),
        Eternal=Color3.fromRGB(245,71,255),
        Divine=Color3.fromRGB(52,255,238),
    }
    return map[rarity] or Color3.fromRGB(230,235,255)
end

local function eggColor(egg)
    return typeof(egg.RarityColor)=="Color3" and egg.RarityColor or rarityFallbackColor(egg.Rarity)
end

local function currentMutationOptions()
    local out={"Todas","Com mutação","Sem mutação"}
    local seen={}
    for _,egg in pairs(State.Eggs) do
        for _,m in ipairs(egg.Mutations or {}) do
            if not seen[m] then seen[m]=true out[#out+1]=m end
        end
    end
    table.sort(out,function(a,b)
        local fixed={ ["Todas"]=1,["Com mutação"]=2,["Sem mutação"]=3 }
        local aa,bb=fixed[a],fixed[b]
        if aa or bb then return (aa or 99)<(bb or 99) end
        return a<b
    end)
    return out
end

local function mutationPass(egg)
    local mode=CONFIG.MutationMode
    local muts=egg.Mutations or {}
    if mode=="Todas" then return true end
    if mode=="Com mutação" then return #muts>0 end
    if mode=="Sem mutação" then return #muts==0 end
    for _,m in ipairs(muts) do if m==mode then return true end end
    return false
end

local function eggPasses(egg)
    if not CONFIG.EggESP then return false end
    if (tonumber(egg.RarityNumber) or 0)<CONFIG.MinRarity then return false end
    if (tonumber(egg.WeightKg) or 0)<CONFIG.MinWeightKg then return false end
    if (tonumber(egg.SellPrice) or 0)<CONFIG.MinSellPrice then return false end
    if CONFIG.SelectedPet~="" then
        local selected=normalize(CONFIG.SelectedPet)
        local pet=normalize(egg.PetName or egg.AssetCategory or "")
        local cat=normalize(egg.AssetCategory or "")
        if pet~=selected and cat~=selected then return false end
    end
    return mutationPass(egg)
end

local function destroyEspRecord(uid)
    local rec=State.ESP[uid]
    if not rec then return end
    -- IMPORTANT: rec.Visual points at the game's real egg model. Never destroy it.
    -- Only destroy Instances created by this script. Text labels are children of
    -- Billboard and are destroyed together with it.
    for _,key in ipairs({"Highlight","Billboard"}) do
        local obj=rec[key]
        if typeof(obj)=="Instance" then pcall(function() obj:Destroy() end) end
    end
    State.ESP[uid]=nil
end

local function sweepOwnedESP()
    for uid in pairs(State.ESP) do destroyEspRecord(uid) end
    local ownedNames={PSICO_EGG_HIGHLIGHT=true,PSICO_EGG_BILLBOARD=true,PsicoItemHighlight=true,PsicoItemBillboard=true,PSICO_DROP_HIGHLIGHT=true,PSICO_DROP_BILLBOARD=true}
    for _,d in ipairs(Workspace:GetDescendants()) do
        if ownedNames[d.Name] then pcall(function() d:Destroy() end) end
    end
    if gui then
        for _,d in ipairs(gui:GetDescendants()) do
            if ownedNames[d.Name] then pcall(function() d:Destroy() end) end
        end
    end
end

local function playerRoot()
    local char=LP.Character
    return char and (char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart)
end

local function visualPosition(visual)
    if not visual then return nil end
    if visual:IsA("BasePart") then return visual.Position end
    if visual:IsA("Model") then
        local ok,cf=pcall(visual.GetPivot,visual)
        if ok then return cf.Position end
        local p=visual.PrimaryPart or visual:FindFirstChildWhichIsA("BasePart",true)
        return p and p.Position or nil
    end
    local p=visual:FindFirstChildWhichIsA("BasePart",true)
    return p and p.Position or nil
end

local function distanceLabel(visual)
    local root=playerRoot()
    local pos=visualPosition(visual)
    if not root or not pos then return "" end
    return tostring(math.floor((root.Position-pos).Magnitude+0.5)).."m"
end

local function espText(egg,visual)
    local line1=(egg.PetName or egg.AssetCategory or "Ovo").." • "..(egg.Rarity or "?")
    local w=egg.WeightLabel or ((egg.WeightKg and (formatCompact(egg.WeightKg).."Kg")) or "?Kg")
    local value=egg.SellPrice and ("$"..formatCompact(egg.SellPrice)) or "$?"
    local line2=w.." • "..value
    if egg.Mutations and #egg.Mutations>0 then line2=line2.." • "..table.concat(egg.Mutations,"+") end
    return line1,line2,distanceLabel(visual)
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
    h.FillTransparency=.84
    h.OutlineTransparency=.08
    h.Parent=visual

    local bb=Instance.new("BillboardGui")
    bb.Name="PSICO_EGG_BILLBOARD"
    bb.Adornee=adornee
    bb.AlwaysOnTop=true
    bb.MaxDistance=CONFIG.MaxEspDistance
    bb.Size=UDim2.fromOffset(150,44)
    bb.StudsOffset=Vector3.new(0,1.9,0)
    bb.Parent=gui

    local l1=Instance.new("TextLabel")
    l1.BackgroundTransparency=1
    l1.Position=UDim2.fromOffset(0,0)
    l1.Size=UDim2.new(1,0,0,15)
    l1.Font=Enum.Font.GothamBold
    l1.TextSize=10
    l1.TextXAlignment=Enum.TextXAlignment.Center
    l1.TextColor3=color
    l1.TextStrokeColor3=Color3.new(0,0,0)
    l1.TextStrokeTransparency=.12
    l1.Parent=bb

    local l2=Instance.new("TextLabel")
    l2.BackgroundTransparency=1
    l2.Position=UDim2.fromOffset(0,14)
    l2.Size=UDim2.new(1,0,0,14)
    l2.Font=Enum.Font.GothamSemibold
    l2.TextSize=9
    l2.TextXAlignment=Enum.TextXAlignment.Center
    l2.TextColor3=Color3.fromRGB(245,248,255)
    l2.TextStrokeColor3=Color3.new(0,0,0)
    l2.TextStrokeTransparency=.18
    l2.Parent=bb

    local l3=Instance.new("TextLabel")
    l3.BackgroundTransparency=1
    l3.Position=UDim2.fromOffset(0,27)
    l3.Size=UDim2.new(1,0,0,12)
    l3.Font=Enum.Font.Gotham
    l3.TextSize=8
    l3.TextXAlignment=Enum.TextXAlignment.Center
    l3.TextColor3=Color3.fromRGB(220,226,239)
    l3.TextStrokeColor3=Color3.new(0,0,0)
    l3.TextStrokeTransparency=.25
    l3.Parent=bb

    local t1,t2,t3=espText(egg,visual)
    l1.Text=t1 l2.Text=t2 l3.Text=t3
    State.ESP[uid]={Highlight=h,Billboard=bb,Visual=visual,Line1=l1,Line2=l2,Line3=l3}
end

local function refreshESP()
    if not State.Alive then return end
    local visible=0
    local keep={}
    for uid,egg in pairs(State.Eggs) do
        if eggPasses(egg) then
            local visual=visualForUid(uid)
            if visual then
                keep[uid]=true
                visible=visible+1
                local rec=State.ESP[uid]
                if not rec or rec.Visual~=visual or not rec.Highlight.Parent or not rec.Billboard.Parent then
                    destroyEspRecord(uid)
                    createESP(uid,egg,visual)
                else
                    local color=eggColor(egg)
                    rec.Highlight.FillColor=color
                    rec.Highlight.OutlineColor=color
                    local t1,t2,t3=espText(egg,visual)
                    rec.Line1.Text=t1 rec.Line1.TextColor3=color rec.Line2.Text=t2 rec.Line3.Text=t3
                end
            end
        end
    end
    for uid in pairs(State.ESP) do if not keep[uid] then destroyEspRecord(uid) end end
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
    local minR=CONFIG.MinRarity==0 and "Todas" or (RARITY_ORDER[CONFIG.MinRarity] or tostring(CONFIG.MinRarity))
    statusLabel.Text=string.format("N:%d • Chão:%d • ESP:%d • ≥%s%s",slots,dropped,State.Stats.EspVisible,minR,extra and (" • "..extra) or "")
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
    if not original and prompt.HoldDuration>0 then original=prompt.HoldDuration State.PromptOriginals[prompt]=original end
    if CONFIG.InstantPrompt then
        if original and prompt.HoldDuration~=0 then pcall(function() prompt.HoldDuration=0 end) end
    elseif original then pcall(function() prompt.HoldDuration=original end) end
end

local function refreshPrompts()
    for _,d in ipairs(Workspace:GetDescendants()) do if d:IsA("ProximityPrompt") then applyPrompt(d) end end
end

local BAT_ATTRS={"CooldownActive","CooldownEndTime","CooldownDuration"}
local function isBat(tool)
    if not (tool and tool:IsA("Tool")) then return false end
    if tool:GetAttribute("IsBat")==true then return true end
    return lower(safeString(tool:GetAttribute("GearName") or "")):find("bat",1,true)~=nil
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
        pcall(function() if tool:GetAttribute("CooldownActive")~=false then tool:SetAttribute("CooldownActive",false) end end)
        pcall(function() if tool:GetAttribute("CooldownEndTime")~=0 then tool:SetAttribute("CooldownEndTime",0) end end)
        pcall(function() if tool:GetAttribute("CooldownDuration")~=0 then tool:SetAttribute("CooldownDuration",0) end end)
    else
        pcall(function() tool.Enabled=original.Enabled end)
        for _,a in ipairs(BAT_ATTRS) do pcall(function() tool:SetAttribute(a,original.Attrs[a]) end) end
    end
    if not State.WatchedBats[tool] then
        State.WatchedBats[tool]=true
        for _,a in ipairs(BAT_ATTRS) do
            connect(tool:GetAttributeChangedSignal(a),function()
                if State.Alive and CONFIG.InstantHit then task.defer(function() if tool.Parent then patchBat(tool) end end) end
            end)
        end
    end
    return true
end

local function refreshBats()
    local containers={}
    if LP.Character then containers[#containers+1]=LP.Character end
    local bp=LP:FindFirstChildOfClass("Backpack")
    if bp then containers[#containers+1]=bp end
    for _,container in ipairs(containers) do
        for _,child in ipairs(container:GetChildren()) do if child:IsA("Tool") then patchBat(child) end end
    end
end

local function restoreBats()
    for tool,original in pairs(State.BatOriginals) do
        if tool and tool.Parent then
            pcall(function() tool.Enabled=original.Enabled end)
            for _,a in ipairs(BAT_ATTRS) do pcall(function() tool:SetAttribute(a,original.Attrs[a]) end) end
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
    end)
end

local function hookEggRemotes()
    for _,d in ipairs(ReplicatedStorage:GetDescendants()) do
        if d:IsA("RemoteEvent") then
            if d.Name=="RE/EggWorld/FieldEggShifted" then
                connect(d.OnClientEvent,function(record)
                    if not State.Alive or typeof(record)~="table" then return end
                    if validEggState(record.State) then enrichRecord(record,"shifted") elseif type(record.Uid)=="string" then removeEgg(record.Uid) end
                    queueRefresh()
                end,State.RemoteConnections)
            elseif d.Name=="RE/EggWorld/FieldEggBatchShifted" then
                connect(d.OnClientEvent,function(payload)
                    if not State.Alive or typeof(payload)~="table" then return end
                    if typeof(payload.RemovedUids)=="table" then for _,uid in pairs(payload.RemovedUids) do removeEgg(uid) end end
                    if typeof(payload.UpdatedRecords)=="table" then
                        for _,record in pairs(payload.UpdatedRecords) do
                            if typeof(record)=="table" then
                                if validEggState(record.State) then enrichRecord(record,"batch") elseif type(record.Uid)=="string" then removeEgg(record.Uid) end
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
            elseif d.Name=="RE/EggWorld/OwnerDropped" or d.Name=="RE/EggWorld/OwnerShifted" then
                connect(d.OnClientEvent,function(...)
                    local args=table.pack(...)
                    for i=1,args.n do if typeof(args[i])=="table" then ingestTree(args[i],"owner:"..d.Name) end end
                    queueRefresh()
                end,State.RemoteConnections)
            end
        end
    end
end

local function round(obj,r)
    local c=Instance.new("UICorner") c.CornerRadius=UDim.new(0,r or 9) c.Parent=obj
end

local function mkButton(parent,text,pos,size)
    local b=Instance.new("TextButton")
    b.BackgroundColor3=Color3.fromRGB(35,44,61) b.BorderSizePixel=0 b.Position=pos b.Size=size
    b.Font=Enum.Font.GothamMedium b.Text=text b.TextColor3=Color3.fromRGB(239,244,255) b.TextSize=10 b.Parent=parent
    round(b,8)
    return b
end

local function mkLabel(parent,text,pos,size,fontSize)
    local l=Instance.new("TextLabel")
    l.BackgroundTransparency=1 l.Position=pos l.Size=size l.Font=Enum.Font.Gotham l.Text=text
    l.TextColor3=Color3.fromRGB(170,184,210) l.TextSize=fontSize or 9 l.TextXAlignment=Enum.TextXAlignment.Left l.Parent=parent
    return l
end

local function mkTextBox(parent,placeholder,pos,size)
    local b=Instance.new("TextBox")
    b.BackgroundColor3=Color3.fromRGB(31,40,56) b.BorderSizePixel=0 b.Position=pos b.Size=size b.Font=Enum.Font.GothamMedium
    b.Text="" b.PlaceholderText=placeholder b.TextColor3=Color3.fromRGB(240,244,255) b.PlaceholderColor3=Color3.fromRGB(115,128,151)
    b.TextSize=10 b.ClearTextOnFocus=false b.Parent=parent round(b,8)
    return b
end

local function makeToggle(parent,label,y,key)
    local b=mkButton(parent,label,UDim2.new(0,0,0,y),UDim2.new(1,0,0,32))
    b:SetAttribute("BaseLabel",label)
    updateToggleVisual(b,CONFIG[key])
    connect(b.MouseButton1Click,function()
        CONFIG[key]=not CONFIG[key]
        updateToggleVisual(b,CONFIG[key])
        if key=="EggESP" then if CONFIG.EggESP then refreshESP() else sweepOwnedESP() State.Stats.EspVisible=0 end
        elseif key=="InstantPrompt" then refreshPrompts()
        elseif key=="InstantHit" then if CONFIG.InstantHit then refreshBats() else restoreBats() end end
        refreshStatus()
    end)
    return b
end

for _,oldName in ipairs({"PsicoRoubeUmOvoV811","PsicoRoubeUmOvoV81","PsicoRoubeUmOvoV8","PsicoRoubeUmOvo","PsicoPrecisionEggScannerV7","PsicoStaticEggScannerV6"}) do
    local old=uiParent():FindFirstChild(oldName)
    if old then pcall(function() old:Destroy() end) end
end

gui=Instance.new("ScreenGui")
gui.Name="PsicoRoubeUmOvoV811" gui.ResetOnSpawn=false gui.IgnoreGuiInset=true gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling gui.Parent=uiParent()

mainFrame=Instance.new("Frame")
mainFrame.Name="Main" mainFrame.AnchorPoint=Vector2.new(.5,.5) mainFrame.Position=UDim2.fromScale(.5,.5)
mainFrame.Size=UDim2.fromOffset(430,300) mainFrame.BackgroundColor3=Color3.fromRGB(14,20,32) mainFrame.BorderSizePixel=0 mainFrame.Parent=gui
round(mainFrame,13)
uiScale=Instance.new("UIScale") uiScale.Scale=1 uiScale.Parent=mainFrame
local stroke=Instance.new("UIStroke") stroke.Thickness=1.1 stroke.Transparency=.28 stroke.Color=Color3.fromRGB(61,118,230) stroke.Parent=mainFrame

local title=mkLabel(mainFrame,"PSICOSENATICO PANEL",UDim2.fromOffset(12,6),UDim2.new(1,-84,0,20),13)
title.Font=Enum.Font.GothamBold title.TextColor3=Color3.fromRGB(242,246,255)
local version=mkLabel(mainFrame,"V8.1.1 • EGG PRECISION ESP",UDim2.fromOffset(12,24),UDim2.new(1,-84,0,14),8)
version.TextColor3=Color3.fromRGB(102,148,232)
local minimize=mkButton(mainFrame,"—",UDim2.new(1,-62,0,6),UDim2.fromOffset(25,25))
local close=mkButton(mainFrame,"×",UDim2.new(1,-32,0,6),UDim2.fromOffset(25,25))

local sidebar=Instance.new("Frame") sidebar.BackgroundTransparency=1 sidebar.Position=UDim2.fromOffset(10,47) sidebar.Size=UDim2.new(0,104,1,-77) sidebar.Parent=mainFrame
local tabMain=mkButton(sidebar,"FUNÇÕES",UDim2.fromOffset(0,0),UDim2.new(1,0,0,42))
local tabFilters=mkButton(sidebar,"FILTROS ESP",UDim2.fromOffset(0,50),UDim2.new(1,0,0,42))

local contentHost=Instance.new("Frame")
contentHost.BackgroundColor3=Color3.fromRGB(20,28,43) contentHost.BackgroundTransparency=.12 contentHost.BorderSizePixel=0
contentHost.Position=UDim2.fromOffset(122,47) contentHost.Size=UDim2.new(1,-132,1,-77) contentHost.Parent=mainFrame round(contentHost,10)

local mainPage=Instance.new("ScrollingFrame")
mainPage.BackgroundTransparency=1 mainPage.BorderSizePixel=0 mainPage.Position=UDim2.fromOffset(8,8) mainPage.Size=UDim2.new(1,-16,1,-16)
mainPage.CanvasSize=UDim2.fromOffset(0,166) mainPage.ScrollBarThickness=3 mainPage.ScrollBarImageColor3=Color3.fromRGB(94,139,223) mainPage.Parent=contentHost

local filterPage=Instance.new("ScrollingFrame")
filterPage.BackgroundTransparency=1 filterPage.BorderSizePixel=0 filterPage.Position=UDim2.fromOffset(8,8) filterPage.Size=UDim2.new(1,-16,1,-16)
filterPage.CanvasSize=UDim2.fromOffset(0,286) filterPage.ScrollBarThickness=3 filterPage.ScrollBarImageColor3=Color3.fromRGB(94,139,223) filterPage.Visible=false filterPage.Parent=contentHost

espToggleButton=makeToggle(mainPage,"ESP • Ovos",0,"EggESP")
promptToggleButton=makeToggle(mainPage,"Instant Prompt",38,"InstantPrompt")
hitToggleButton=makeToggle(mainPage,"Instant Hit • Bat",76,"InstantHit")
local refreshButton=mkButton(mainPage,"Atualizar ovos",UDim2.fromOffset(0,114),UDim2.new(1,0,0,32))

local filterY=0
mkLabel(filterPage,"Raridade mínima",UDim2.fromOffset(0,filterY),UDim2.new(.43,0,0,28),9)
rarityButton=mkButton(filterPage,"Todas",UDim2.new(.45,0,0,filterY),UDim2.new(.55,-4,0,28)) filterY=filterY+34
mkLabel(filterPage,"Peso mínimo (kg)",UDim2.fromOffset(0,filterY),UDim2.new(.43,0,0,28),9)
local weightBox=mkTextBox(filterPage,"Ex: 100K",UDim2.new(.45,0,0,filterY),UDim2.new(.55,-4,0,28)) filterY=filterY+34
mkLabel(filterPage,"Valor mínimo ($)",UDim2.fromOffset(0,filterY),UDim2.new(.43,0,0,28),9)
local valueBox=mkTextBox(filterPage,"Ex: 2M",UDim2.new(.45,0,0,filterY),UDim2.new(.55,-4,0,28)) filterY=filterY+34
mkLabel(filterPage,"Pet",UDim2.fromOffset(0,filterY),UDim2.new(.43,0,0,28),9)
petButton=mkButton(filterPage,"Selecionar pet...",UDim2.new(.45,0,0,filterY),UDim2.new(.55,-4,0,28)) filterY=filterY+34
mkLabel(filterPage,"Lista de pets",UDim2.fromOffset(0,filterY),UDim2.new(.43,0,0,28),9)
availabilityButton=mkButton(filterPage,"Todos do jogo",UDim2.new(.45,0,0,filterY),UDim2.new(.55,-4,0,28)) filterY=filterY+34
mkLabel(filterPage,"Mutação",UDim2.fromOffset(0,filterY),UDim2.new(.43,0,0,28),9)
mutationButton=mkButton(filterPage,"Todas",UDim2.new(.45,0,0,filterY),UDim2.new(.55,-4,0,28)) filterY=filterY+36
local resetFilters=mkButton(filterPage,"Limpar filtros",UDim2.fromOffset(0,filterY),UDim2.new(1,-4,0,30))

statusLabel=mkLabel(mainFrame,"Carregando dados...",UDim2.new(0,12,1,-24),UDim2.new(1,-24,0,16),8)
statusLabel.TextXAlignment=Enum.TextXAlignment.Center statusLabel.TextColor3=Color3.fromRGB(139,164,207)

local function showPage(which)
    local filters=(which=="filters")
    mainPage.Visible=not filters filterPage.Visible=filters
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
    uiScale.Scale=math.min(widthLimit/430,heightLimit/300,1)
end
applyResponsive()
local function attachCameraResize(camera)
    if camera then connect(camera:GetPropertyChangedSignal("ViewportSize"),applyResponsive) end
end
attachCameraResize(Workspace.CurrentCamera)
connect(Workspace:GetPropertyChangedSignal("CurrentCamera"),function() task.defer(function() attachCameraResize(Workspace.CurrentCamera) applyResponsive() end) end)

connect(rarityButton.MouseButton1Click,function()
    CONFIG.MinRarity=CONFIG.MinRarity+1
    if CONFIG.MinRarity>#RARITY_ORDER then CONFIG.MinRarity=0 end
    rarityButton.Text=CONFIG.MinRarity==0 and "Todas" or RARITY_ORDER[CONFIG.MinRarity]
    refreshESP() refreshStatus()
end)
connect(weightBox.FocusLost,function()
    CONFIG.MinWeightKg=parseSmartNumber(weightBox.Text)
    weightBox.Text=CONFIG.MinWeightKg==0 and "" or formatCompact(CONFIG.MinWeightKg)
    refreshESP() refreshStatus()
end)
connect(valueBox.FocusLost,function()
    CONFIG.MinSellPrice=parseSmartNumber(valueBox.Text)
    valueBox.Text=CONFIG.MinSellPrice==0 and "" or formatCompact(CONFIG.MinSellPrice)
    refreshESP() refreshStatus()
end)
connect(mutationButton.MouseButton1Click,function()
    local opts=currentMutationOptions()
    local idx=1
    for i,v in ipairs(opts) do if v==CONFIG.MutationMode then idx=i break end end
    idx=idx+1 if idx>#opts then idx=1 end
    CONFIG.MutationMode=opts[idx] mutationButton.Text=CONFIG.MutationMode
    refreshESP() refreshStatus()
end)

local function availablePetNames()
    local map={}
    for _,egg in pairs(State.Eggs) do
        local name=egg.PetName or egg.AssetCategory
        if type(name)=="string" and name~="" then map[normalize(name)]=name end
    end
    return map
end
local function catalogForPicker()
    local out={} local available=availablePetNames() local seen={}
    for _,entry in ipairs(State.CatalogEntries) do
        local name=entry.PetName local key=normalize(name)
        if name and name~="" and not seen[key] and (not CONFIG.PetListAvailableOnly or available[key]) then
            seen[key]=true out[#out+1]=entry
        end
    end
    table.sort(out,function(a,b) return lower(a.PetName)<lower(b.PetName) end)
    return out
end

local function closePetModal()
    if petModal then pcall(function() petModal:Destroy() end) petModal=nil petSearchBox=nil petList=nil end
end

local function buildPetRows(query)
    if not petList then return end
    for _,child in ipairs(petList:GetChildren()) do if child:IsA("GuiObject") then child:Destroy() end end
    local y=0 local q=lower(query or "")
    local all=mkButton(petList,"Todos os pets",UDim2.fromOffset(0,y),UDim2.new(1,-4,0,28))
    all.TextXAlignment=Enum.TextXAlignment.Left all.ZIndex=32
    connect(all.MouseButton1Click,function()
        CONFIG.SelectedPet="" petButton.Text="Selecionar pet..." closePetModal() refreshESP() refreshStatus()
    end)
    y=y+32
    for _,entry in ipairs(catalogForPicker()) do
        local name=safeString(entry.PetName) local rarity=safeString(entry.Rarity or "?")
        if q=="" or lower(name):find(q,1,true) or lower(rarity):find(q,1,true) then
            local row=mkButton(petList,name.."  •  "..rarity,UDim2.fromOffset(0,y),UDim2.new(1,-4,0,28))
            row.TextXAlignment=Enum.TextXAlignment.Left row.ZIndex=32 row.TextColor3=rarityFallbackColor(rarity)
            connect(row.MouseButton1Click,function()
                CONFIG.SelectedPet=name petButton.Text=name closePetModal() refreshESP() refreshStatus()
            end)
            y=y+32
        end
    end
    petList.CanvasSize=UDim2.fromOffset(0,math.max(y,1))
end

local function openPetModal()
    closePetModal()
    petModal=Instance.new("Frame")
    petModal.Name="PetPicker" petModal.AnchorPoint=Vector2.new(.5,.5) petModal.Position=UDim2.fromScale(.5,.5) petModal.Size=UDim2.fromOffset(300,224)
    petModal.BackgroundColor3=Color3.fromRGB(15,22,35) petModal.BorderSizePixel=0 petModal.ZIndex=30 petModal.Parent=gui round(petModal,11)
    local ps=Instance.new("UIStroke") ps.Color=Color3.fromRGB(61,118,230) ps.Transparency=.2 ps.Parent=petModal
    local modalScale=Instance.new("UIScale") modalScale.Scale=uiScale.Scale modalScale.Parent=petModal
    local pt=mkLabel(petModal,"Selecionar Pet",UDim2.fromOffset(12,7),UDim2.new(1,-50,0,20),12)
    pt.Font=Enum.Font.GothamBold pt.TextColor3=Color3.fromRGB(242,246,255)
    local px=mkButton(petModal,"×",UDim2.new(1,-34,0,6),UDim2.fromOffset(26,26)) px.ZIndex=31 connect(px.MouseButton1Click,closePetModal)
    petSearchBox=mkTextBox(petModal,"Buscar pet...",UDim2.fromOffset(12,37),UDim2.new(1,-24,0,30)) petSearchBox.ZIndex=31
    local mode=mkButton(petModal,CONFIG.PetListAvailableOnly and "Só disponíveis agora" or "Todos os pets do jogo",UDim2.fromOffset(12,73),UDim2.new(1,-24,0,28))
    mode.ZIndex=31
    connect(mode.MouseButton1Click,function()
        CONFIG.PetListAvailableOnly=not CONFIG.PetListAvailableOnly
        availabilityButton.Text=CONFIG.PetListAvailableOnly and "Só disponíveis" or "Todos do jogo"
        mode.Text=CONFIG.PetListAvailableOnly and "Só disponíveis agora" or "Todos os pets do jogo"
        buildPetRows(petSearchBox.Text)
    end)
    petList=Instance.new("ScrollingFrame")
    petList.BackgroundTransparency=1 petList.BorderSizePixel=0 petList.Position=UDim2.fromOffset(12,107) petList.Size=UDim2.new(1,-24,1,-119)
    petList.CanvasSize=UDim2.fromOffset(0,0) petList.ScrollBarThickness=3 petList.ScrollBarImageColor3=Color3.fromRGB(94,139,223) petList.ZIndex=31 petList.Parent=petModal
    connect(petSearchBox:GetPropertyChangedSignal("Text"),function() buildPetRows(petSearchBox.Text) end)
    buildPetRows("")
end

connect(petButton.MouseButton1Click,openPetModal)
connect(availabilityButton.MouseButton1Click,function()
    CONFIG.PetListAvailableOnly=not CONFIG.PetListAvailableOnly
    availabilityButton.Text=CONFIG.PetListAvailableOnly and "Só disponíveis" or "Todos do jogo"
end)
connect(resetFilters.MouseButton1Click,function()
    CONFIG.MinRarity=0 CONFIG.MinWeightKg=0 CONFIG.MinSellPrice=0 CONFIG.SelectedPet="" CONFIG.MutationMode="Todas" CONFIG.PetListAvailableOnly=false
    rarityButton.Text="Todas" mutationButton.Text="Todas" availabilityButton.Text="Todos do jogo" petButton.Text="Selecionar pet..." weightBox.Text="" valueBox.Text=""
    refreshESP() refreshStatus()
end)
connect(refreshButton.MouseButton1Click,function()
    State.RawRecords={} State.Eggs={}
    local n=requestSnapshots()
    refreshESP() refreshStatus("snapshot:"..tostring(n))
end)

local dragging=false local dragInput,dragStart,startPos
connect(mainFrame.InputBegan,function(input)
    if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1 then dragging=true dragStart=input.Position startPos=mainFrame.Position end
end)
connect(mainFrame.InputChanged,function(input)
    if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseMovement then dragInput=input end
end)
connect(UIS.InputChanged,function(input)
    if dragging and input==dragInput then local d=input.Position-dragStart mainFrame.Position=UDim2.new(startPos.X.Scale,startPos.X.Offset+d.X,startPos.Y.Scale,startPos.Y.Offset+d.Y) end
end)
connect(UIS.InputEnded,function(input)
    if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1 then dragging=false end
end)

floatButton=Instance.new("TextButton")
floatButton.Name="PSICO_FLOAT" floatButton.Size=UDim2.fromOffset(46,46) floatButton.Position=UDim2.new(0,18,.5,-23)
floatButton.BackgroundColor3=Color3.fromRGB(18,42,84) floatButton.BorderSizePixel=0 floatButton.Font=Enum.Font.GothamBold floatButton.Text="PS"
floatButton.TextColor3=Color3.fromRGB(240,245,255) floatButton.TextSize=12 floatButton.Visible=false floatButton.Parent=gui round(floatButton,23)
local fdrag=false local fstart,fpos
connect(floatButton.InputBegan,function(input)
    if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1 then fdrag=true fstart=input.Position fpos=floatButton.Position end
end)
connect(UIS.InputChanged,function(input)
    if fdrag and (input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseMovement) then
        local d=input.Position-fstart floatButton.Position=UDim2.new(fpos.X.Scale,fpos.X.Offset+d.X,fpos.Y.Scale,fpos.Y.Offset+d.Y)
    end
end)
connect(UIS.InputEnded,function(input)
    if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1 then fdrag=false end
end)
connect(floatButton.MouseButton1Click,function() mainFrame.Visible=true floatButton.Visible=false end)
connect(minimize.MouseButton1Click,function() closePetModal() mainFrame.Visible=false floatButton.Visible=true end)

local function initializeData()
    local ok,err=resolveModules()
    if not ok then State.LastError=err refreshStatus("ERRO:"..err) return false end
    if not buildCatalog() then State.LastError="catálogo vazio" refreshStatus("ERRO:catálogo") return false end
    requestSnapshots() refreshESP() refreshStatus()
    return true
end

hookEggRemotes()
connect(Workspace.DescendantAdded,function(inst)
    if inst:IsA("ProximityPrompt") then task.defer(function() if State.Alive then applyPrompt(inst) end end) end
    if inst.Name=="AreaEggSlotsClient" or (inst.Parent and inst.Parent.Name=="AreaEggSlotsClient") then queueRefresh() end
    if type(inst.Name)=="string" and State.Eggs[inst.Name] then queueRefresh() end
end)
connect(Workspace.DescendantRemoving,function(inst) if type(inst.Name)=="string" and State.Eggs[inst.Name] then queueRefresh() end end)
connect(LP.ChildAdded,function(child)
    if child:IsA("Backpack") then connect(child.ChildAdded,function(tool) if tool:IsA("Tool") then task.defer(function() patchBat(tool) end) end end) end
end)
connect(LP.CharacterAdded,function(char)
    connect(char.ChildAdded,function(tool) if tool:IsA("Tool") then task.defer(function() patchBat(tool) end) end end)
    task.defer(refreshBats)
end)
local backpack=LP:FindFirstChildOfClass("Backpack")
if backpack then connect(backpack.ChildAdded,function(tool) if tool:IsA("Tool") then task.defer(function() patchBat(tool) end) end end) end
if LP.Character then connect(LP.Character.ChildAdded,function(tool) if tool:IsA("Tool") then task.defer(function() patchBat(tool) end) end end) end

local function cleanup()
    if not State.Alive then return end
    State.Alive=false closePetModal() sweepOwnedESP()
    for prompt,original in pairs(State.PromptOriginals) do if prompt and prompt.Parent then pcall(function() prompt.HoldDuration=original end) end end
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

task.defer(function() task.wait(.4) if State.Alive then initializeData() end end)
task.defer(function()
    while State.Alive do
        task.wait(.55)
        if CONFIG.EggESP then refreshESP() end
        if CONFIG.InstantHit then refreshBats() end
        refreshStatus()
    end
end)

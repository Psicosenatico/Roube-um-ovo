--[[
PSICOSENATICO | Roube um Ovo - Precision Menu V8
Stable loader path: RoubeUmOvo_ScannerV2.lua

Based on Scanner V7 ground truth:
  * Current nest eggs come from EggWorld Slot records.
  * Pet/rarity metadata comes from ReplicatedStorage.Data.Assets.
  * Weight/value/name calculations use ReplicatedStorage.Shared.Util.EggRecords.
  * ESP targets only the exact UID visual in AreaEggSlotsClient / Workspace.

Features:
  * Nest Egg ESP with filters: minimum rarity, minimum kg, minimum sell value,
    pet text and mutation.
  * Instant Prompt for prompts that actually have hold time.
  * Instant Hit for bat tools using the confirmed cooldown attributes.
  * Full deterministic cleanup so owned ESP cannot remain stuck after disabling.
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
    PetQuery = "",
    MutationMode = "Todas",
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
local floatButton
local statusLabel
local rarityButton
local mutationButton
local espToggleButton
local promptToggleButton
local hitToggleButton

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

local function enrichRecord(record,source)
    if typeof(record)~="table" or type(record.Uid)~="string" or record.State~="Slot" then return false end
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
        State="Slot",
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
        if value.State=="Slot" then
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
    if a>=1e12 then return string.format("%.2fT",n/1e12) end
    if a>=1e9 then return string.format("%.2fB",n/1e9) end
    if a>=1e6 then return string.format("%.2fM",n/1e6) end
    if a>=1e3 then return string.format("%.1fK",n/1e3) end
    return tostring(math.floor(n+0.5))
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
    local rn=tonumber(egg.RarityNumber) or 0
    if rn<CONFIG.MinRarity then return false end
    local weight=tonumber(egg.WeightKg) or 0
    if weight<CONFIG.MinWeightKg then return false end
    local value=tonumber(egg.SellPrice) or 0
    if value<CONFIG.MinSellPrice then return false end
    local q=lower(CONFIG.PetQuery)
    if q~="" then
        local hay=lower((egg.PetName or "").." "..(egg.EggName or "").." "..(egg.AssetCategory or ""))
        if not hay:find(q,1,true) then return false end
    end
    if not mutationPass(egg) then return false end
    return true
end

local function destroyEspRecord(uid)
    local rec=State.ESP[uid]
    if not rec then return end
    for _,obj in pairs(rec) do
        if typeof(obj)=="Instance" then pcall(function() obj:Destroy() end) end
    end
    State.ESP[uid]=nil
end

local function sweepOwnedESP()
    for uid in pairs(State.ESP) do destroyEspRecord(uid) end
    local ownedNames={
        PSICO_EGG_HIGHLIGHT=true,
        PsicoItemHighlight=true,
        PSICO_DROP_HIGHLIGHT=true,
    }
    for _,d in ipairs(Workspace:GetDescendants()) do
        if ownedNames[d.Name] then pcall(function() d:Destroy() end) end
    end
    if gui then
        for _,d in ipairs(gui:GetDescendants()) do
            if d.Name=="PSICO_EGG_BILLBOARD" or d.Name=="PsicoItemBillboard" or d.Name=="PSICO_DROP_BILLBOARD" then pcall(function() d:Destroy() end) end
        end
    end
end

local function espText(egg)
    local line1=(egg.PetName or egg.AssetCategory or "Ovo").." • "..(egg.Rarity or "?")
    local w=egg.WeightLabel or ((egg.WeightKg and string.format("%.1fKg",egg.WeightKg)) or "?Kg")
    local value=egg.SellPrice and ("$"..formatCompact(egg.SellPrice)) or "$?"
    local line2=w.." • "..value
    if egg.Mutations and #egg.Mutations>0 then line2=line2.." • "..table.concat(egg.Mutations,"+") end
    return line1,line2
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
    h.FillTransparency=.72
    h.OutlineTransparency=.05
    h.Parent=visual

    local bb=Instance.new("BillboardGui")
    bb.Name="PSICO_EGG_BILLBOARD"
    bb.Adornee=adornee
    bb.AlwaysOnTop=true
    bb.MaxDistance=CONFIG.MaxEspDistance
    bb.Size=UDim2.fromOffset(210,48)
    bb.StudsOffset=Vector3.new(0,2.4,0)
    bb.Parent=gui

    local bg=Instance.new("Frame")
    bg.BackgroundColor3=Color3.fromRGB(10,14,24)
    bg.BackgroundTransparency=.18
    bg.BorderSizePixel=0
    bg.Size=UDim2.fromScale(1,1)
    bg.Parent=bb
    Instance.new("UICorner",bg).CornerRadius=UDim.new(0,7)

    local l1=Instance.new("TextLabel")
    l1.BackgroundTransparency=1
    l1.Position=UDim2.fromOffset(5,3)
    l1.Size=UDim2.new(1,-10,0,20)
    l1.Font=Enum.Font.GothamBold
    l1.TextSize=12
    l1.TextXAlignment=Enum.TextXAlignment.Center
    l1.TextColor3=color
    l1.TextStrokeTransparency=.55
    l1.Parent=bg

    local l2=Instance.new("TextLabel")
    l2.BackgroundTransparency=1
    l2.Position=UDim2.fromOffset(5,23)
    l2.Size=UDim2.new(1,-10,0,19)
    l2.Font=Enum.Font.GothamMedium
    l2.TextSize=10
    l2.TextXAlignment=Enum.TextXAlignment.Center
    l2.TextColor3=Color3.fromRGB(240,244,255)
    l2.TextStrokeTransparency=.65
    l2.Parent=bg

    local t1,t2=espText(egg)
    l1.Text=t1
    l2.Text=t2
    State.ESP[uid]={Highlight=h,Billboard=bb,Visual=visual,Line1=l1,Line2=l2}
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
                    local t1,t2=espText(egg)
                    rec.Line1.Text=t1
                    rec.Line1.TextColor3=color
                    rec.Line2.Text=t2
                end
            end
        end
    end
    for uid in pairs(State.ESP) do
        if not keep[uid] then destroyEspRecord(uid) end
    end
    State.Stats.EspVisible=visible
end

local function refreshStatus(extra)
    if not statusLabel then return end
    local minR=CONFIG.MinRarity==0 and "Todas" or (RARITY_ORDER[CONFIG.MinRarity] or tostring(CONFIG.MinRarity))
    statusLabel.Text=string.format("Ovos: %d  •  ESP: %d  •  ≥%s%s",countMap(State.Eggs),State.Stats.EspVisible,minR,extra and ("\n"..extra) or "")
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
    local gear=safeString(tool:GetAttribute("GearName") or "")
    return lower(gear):find("bat",1,true)~=nil
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
        for _,a in ipairs(BAT_ATTRS) do
            pcall(function() tool:SetAttribute(a,original.Attrs[a]) end)
        end
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
                    if record.State=="Slot" then enrichRecord(record,"shifted")
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
                                if record.State=="Slot" then enrichRecord(record,"batch")
                                elseif type(record.Uid)=="string" then removeEgg(record.Uid) end
                            end
                        end
                    end
                    queueRefresh()
                end,State.RemoteConnections)
            elseif d.Name=="RE/EggWorld/FieldEggGone" then
                connect(d.OnClientEvent,function(uid) removeEgg(uid) queueRefresh() end,State.RemoteConnections)
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
    b.TextSize=11
    b.Parent=parent
    round(b,9)
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
    l.TextSize=fontSize or 10
    l.TextXAlignment=Enum.TextXAlignment.Left
    l.Parent=parent
    return l
end

local function makeToggle(parent,label,y,key)
    local b=mkButton(parent,label,UDim2.new(0,0,0,y),UDim2.new(1,0,0,34))
    b:SetAttribute("BaseLabel",label)
    updateToggleVisual(b,CONFIG[key])
    connect(b.MouseButton1Click,function()
        CONFIG[key]=not CONFIG[key]
        updateToggleVisual(b,CONFIG[key])
        if key=="EggESP" then
            if CONFIG.EggESP then refreshESP() else sweepOwnedESP() State.Stats.EspVisible=0 end
        elseif key=="InstantPrompt" then
            refreshPrompts()
        elseif key=="InstantHit" then
            if CONFIG.InstantHit then refreshBats() else restoreBats() end
        end
        refreshStatus()
    end)
    return b
end

for _,oldName in ipairs({"PsicoRoubeUmOvoV8","PsicoRoubeUmOvo","PsicoPrecisionEggScannerV7","PsicoStaticEggScannerV6"}) do
    local old=uiParent():FindFirstChild(oldName)
    if old then pcall(function() old:Destroy() end) end
end

gui=Instance.new("ScreenGui")
gui.Name="PsicoRoubeUmOvoV8"
gui.ResetOnSpawn=false
gui.IgnoreGuiInset=true
gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling
gui.Parent=uiParent()

local vp=(Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize) or Vector2.new(844,390)
local width=math.floor(math.clamp(vp.X*0.39,286,350))
local height=math.floor(math.min(292,vp.Y*0.70))

mainFrame=Instance.new("Frame")
mainFrame.AnchorPoint=Vector2.new(.5,.5)
mainFrame.Position=UDim2.fromScale(.5,.5)
mainFrame.Size=UDim2.fromOffset(width,height)
mainFrame.BackgroundColor3=Color3.fromRGB(14,20,32)
mainFrame.BorderSizePixel=0
mainFrame.Parent=gui
round(mainFrame,13)
local stroke=Instance.new("UIStroke")
stroke.Thickness=1.2
stroke.Transparency=.25
stroke.Color=Color3.fromRGB(61,118,230)
stroke.Parent=mainFrame

local title=mkLabel(mainFrame,"PSICOSENATICO PANEL",UDim2.fromOffset(12,7),UDim2.new(1,-90,0,22),14)
title.Font=Enum.Font.GothamBold
title.TextColor3=Color3.fromRGB(242,246,255)
local version=mkLabel(mainFrame,"V8 • EGG PRECISION ESP",UDim2.fromOffset(12,27),UDim2.new(1,-90,0,15),9)
version.TextColor3=Color3.fromRGB(102,148,232)

local minimize=mkButton(mainFrame,"—",UDim2.new(1,-68,0,7),UDim2.fromOffset(27,27))
local close=mkButton(mainFrame,"×",UDim2.new(1,-36,0,7),UDim2.fromOffset(27,27))

local tabMain=mkButton(mainFrame,"FUNÇÕES",UDim2.fromOffset(12,49),UDim2.new(.5,-15,0,30))
local tabFilters=mkButton(mainFrame,"FILTROS ESP",UDim2.new(.5,3,0,49),UDim2.new(.5,-15,0,30))

local content=Instance.new("Frame")
content.BackgroundTransparency=1
content.Position=UDim2.fromOffset(12,86)
content.Size=UDim2.new(1,-24,1,-119)
content.Parent=mainFrame

local mainPage=Instance.new("Frame")
mainPage.BackgroundTransparency=1
mainPage.Size=UDim2.fromScale(1,1)
mainPage.Parent=content

local filterPage=Instance.new("ScrollingFrame")
filterPage.BackgroundTransparency=1
filterPage.Size=UDim2.fromScale(1,1)
filterPage.CanvasSize=UDim2.fromOffset(0,224)
filterPage.ScrollBarThickness=3
filterPage.Visible=false
filterPage.Parent=content

espToggleButton=makeToggle(mainPage,"ESP • Ovos nos ninhos",0,"EggESP")
promptToggleButton=makeToggle(mainPage,"Instant Prompt",40,"InstantPrompt")
hitToggleButton=makeToggle(mainPage,"Instant Hit • Bat",80,"InstantHit")
local refreshButton=mkButton(mainPage,"Atualizar ovos",UDim2.new(0,0,0,120),UDim2.new(1,0,0,32))

local filterY=0
mkLabel(filterPage,"Raridade mínima",UDim2.fromOffset(0,filterY),UDim2.new(.42,0,0,30),10)
rarityButton=mkButton(filterPage,"Todas",UDim2.new(.44,0,0,filterY),UDim2.new(.56,0,0,30))
filterY=filterY+36
mkLabel(filterPage,"Peso mínimo (kg)",UDim2.fromOffset(0,filterY),UDim2.new(.42,0,0,30),10)
local weightBox=Instance.new("TextBox")
weightBox.BackgroundColor3=Color3.fromRGB(31,40,56) weightBox.BorderSizePixel=0 weightBox.Position=UDim2.new(.44,0,0,filterY) weightBox.Size=UDim2.new(.56,0,0,30)
weightBox.Font=Enum.Font.GothamMedium weightBox.Text="0" weightBox.PlaceholderText="0" weightBox.TextColor3=Color3.fromRGB(240,244,255) weightBox.TextSize=11 weightBox.ClearTextOnFocus=false weightBox.Parent=filterPage round(weightBox,8)
filterY=filterY+36
mkLabel(filterPage,"Valor mínimo ($)",UDim2.fromOffset(0,filterY),UDim2.new(.42,0,0,30),10)
local valueBox=Instance.new("TextBox")
valueBox.BackgroundColor3=Color3.fromRGB(31,40,56) valueBox.BorderSizePixel=0 valueBox.Position=UDim2.new(.44,0,0,filterY) valueBox.Size=UDim2.new(.56,0,0,30)
valueBox.Font=Enum.Font.GothamMedium valueBox.Text="0" valueBox.PlaceholderText="0" valueBox.TextColor3=Color3.fromRGB(240,244,255) valueBox.TextSize=11 valueBox.ClearTextOnFocus=false valueBox.Parent=filterPage round(valueBox,8)
filterY=filterY+36
mkLabel(filterPage,"Pet contém",UDim2.fromOffset(0,filterY),UDim2.new(.42,0,0,30),10)
local petBox=Instance.new("TextBox")
petBox.BackgroundColor3=Color3.fromRGB(31,40,56) petBox.BorderSizePixel=0 petBox.Position=UDim2.new(.44,0,0,filterY) petBox.Size=UDim2.new(.56,0,0,30)
petBox.Font=Enum.Font.GothamMedium petBox.Text="" petBox.PlaceholderText="Ex.: Orca" petBox.TextColor3=Color3.fromRGB(240,244,255) petBox.PlaceholderColor3=Color3.fromRGB(115,128,151) petBox.TextSize=11 petBox.ClearTextOnFocus=false petBox.Parent=filterPage round(petBox,8)
filterY=filterY+36
mkLabel(filterPage,"Mutação",UDim2.fromOffset(0,filterY),UDim2.new(.42,0,0,30),10)
mutationButton=mkButton(filterPage,"Todas",UDim2.new(.44,0,0,filterY),UDim2.new(.56,0,0,30))
filterY=filterY+38
local resetFilters=mkButton(filterPage,"Resetar filtros",UDim2.fromOffset(0,filterY),UDim2.new(1,0,0,30))

statusLabel=mkLabel(mainFrame,"Carregando dados...",UDim2.new(0,12,1,-28),UDim2.new(1,-24,0,20),9)
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

connect(rarityButton.MouseButton1Click,function()
    CONFIG.MinRarity=CONFIG.MinRarity+1
    if CONFIG.MinRarity>#RARITY_ORDER then CONFIG.MinRarity=0 end
    rarityButton.Text=CONFIG.MinRarity==0 and "Todas" or RARITY_ORDER[CONFIG.MinRarity]
    refreshESP() refreshStatus()
end)

local function parseNumberText(text)
    local cleaned=safeString(text):gsub("[^%d%.%-]","")
    local n=tonumber(cleaned)
    return n or 0
end
connect(weightBox.FocusLost,function()
    CONFIG.MinWeightKg=math.max(0,parseNumberText(weightBox.Text))
    weightBox.Text=tostring(CONFIG.MinWeightKg)
    refreshESP() refreshStatus()
end)
connect(valueBox.FocusLost,function()
    CONFIG.MinSellPrice=math.max(0,parseNumberText(valueBox.Text))
    valueBox.Text=tostring(CONFIG.MinSellPrice)
    refreshESP() refreshStatus()
end)
connect(petBox.FocusLost,function()
    CONFIG.PetQuery=petBox.Text or ""
    refreshESP() refreshStatus()
end)
connect(mutationButton.MouseButton1Click,function()
    local opts=currentMutationOptions()
    local idx=1
    for i,v in ipairs(opts) do if v==CONFIG.MutationMode then idx=i break end end
    idx=idx+1 if idx>#opts then idx=1 end
    CONFIG.MutationMode=opts[idx]
    mutationButton.Text=CONFIG.MutationMode
    refreshESP() refreshStatus()
end)
connect(resetFilters.MouseButton1Click,function()
    CONFIG.MinRarity=0 CONFIG.MinWeightKg=0 CONFIG.MinSellPrice=0 CONFIG.PetQuery="" CONFIG.MutationMode="Todas"
    rarityButton.Text="Todas" mutationButton.Text="Todas" weightBox.Text="0" valueBox.Text="0" petBox.Text=""
    refreshESP() refreshStatus()
end)

connect(refreshButton.MouseButton1Click,function()
    State.RawRecords={} State.Eggs={}
    local n=requestSnapshots()
    refreshESP()
    refreshStatus("snapshot: "..tostring(n))
end)

local dragging=false
local dragInput,dragStart,startPos
connect(mainFrame.InputBegan,function(input)
    if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1 then dragging=true dragStart=input.Position startPos=mainFrame.Position end
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
floatButton.Size=UDim2.fromOffset(48,48)
floatButton.Position=UDim2.new(0,18,.5,-24)
floatButton.BackgroundColor3=Color3.fromRGB(18,42,84)
floatButton.BorderSizePixel=0
floatButton.Font=Enum.Font.GothamBold
floatButton.Text="PS"
floatButton.TextColor3=Color3.fromRGB(240,245,255)
floatButton.TextSize=13
floatButton.Visible=false
floatButton.Parent=gui
round(floatButton,24)

local fdrag=false
local fstart,fpos
connect(floatButton.InputBegan,function(input)
    if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1 then fdrag=true fstart=input.Position fpos=floatButton.Position end
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
connect(floatButton.MouseButton1Click,function()
    mainFrame.Visible=true
    floatButton.Visible=false
end)
connect(minimize.MouseButton1Click,function()
    mainFrame.Visible=false
    floatButton.Visible=true
end)

local function initializeData()
    local ok,err=resolveModules()
    if not ok then State.LastError=err refreshStatus("ERRO: "..err) return false end
    if not buildCatalog() then State.LastError="catálogo vazio" refreshStatus("ERRO: catálogo vazio") return false end
    requestSnapshots()
    refreshESP()
    refreshStatus()
    return true
end

hookEggRemotes()

connect(Workspace.DescendantAdded,function(inst)
    if inst:IsA("ProximityPrompt") then task.defer(function() if State.Alive then applyPrompt(inst) end end) end
    if inst.Name=="AreaEggSlotsClient" or (inst.Parent and inst.Parent.Name=="AreaEggSlotsClient") then queueRefresh() end
end)

connect(LP.ChildAdded,function(child)
    if child:IsA("Backpack") then
        connect(child.ChildAdded,function(tool) if tool:IsA("Tool") then task.defer(function() patchBat(tool) end) end end)
    end
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
    State.Alive=false
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
        task.wait(.6)
        if CONFIG.EggESP then refreshESP() end
        if CONFIG.InstantHit then refreshBats() end
        refreshStatus()
    end
end)

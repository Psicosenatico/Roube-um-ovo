--[[
PSICOSENATICO | Steal An Egg - Inventory Egg ESP V1
Companion module for RoubeUmOvo_Menu.lua V8.3.
- Reads Save.Get().EggInventory.
- Reuses the same visible filters/options from the normal egg ESP.
- Adds rarity-colored information overlays to Roblox Backpack/hotbar slots.
- No hooks, no remote mutation, no game-state mutation.
]]

if _G.PSICO_INVENTORY_ESP_CLEANUP then pcall(_G.PSICO_INVENTORY_ESP_CLEANUP) end

local Players=game:GetService("Players")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local CoreGui=game:GetService("CoreGui")
local LP=Players.LocalPlayer

local State={
    Alive=true,
    Enabled=false,
    Connections={},
    CatalogIndex={},
    CatalogEntries={},
    MutationScalars={},
    InventoryEggs={},
    LastVisible=0,
}

local AssetsData
local EggRecords
local AssetEarnings
local MutationCatalog
local SaveMod
local baseGui,mainFrame,mainPage,filterPage,toggleButton

local RARITY_ORDER={
    "Common","Uncommon","Rare","Epic","Legendary",
    "Mythic","Cosmic","Secret","Eternal","Divine"
}

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

local function connect(signal,fn)
    local c=signal:Connect(fn)
    State.Connections[#State.Connections+1]=c
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

local function copyMutations(record)
    local out,seen={},{}
    local function add(v)
        if v==nil then return end
        local s=safeString(v)
        local k=normalize(s)
        if k~="" and not seen[k] then seen[k]=true; out[#out+1]=s end
    end
    local src=record and (record.Mutations or (record.ItemData and record.ItemData.Mutations))
    if typeof(src)=="table" then for _,m in pairs(src) do add(m) end end
    add(record and (record.BaseMutation or (record.ItemData and record.ItemData.BaseMutation)))
    if record and (record.HasParasite==true or (record.ItemData and record.ItemData.HasParasite==true)) then add("Parasite") end
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
    AssetEarnings=requireOptional("Shared.Util.AssetEarnings")
    MutationCatalog=requireOptional("Shared.Modules.Mutations.Catalog")
    SaveMod=requireOptional("Shared.Save") or requireOptional("Data.Save")
    indexMutationScalars()
    return typeof(AssetsData)=="table" and typeof(EggRecords)=="table" and typeof(SaveMod)=="table"
end

local function indexEntry(key,cfg)
    if typeof(cfg)~="table" or typeof(cfg.Rarity)~="table" then return end
    local entry={
        Key=safeString(key),
        PetName=cfg.DisplayName or safeString(key),
        Rarity=cfg.Rarity.DisplayName or cfg.Rarity._id,
        RarityNumber=cfg.Rarity.RarityNumber,
        RarityColor=cfg.Rarity.Color,
        EarningRate=tonumber(cfg.EarningRate),
        EggDisplayName=typeof(cfg.Egg)=="table" and cfg.Egg.DisplayName or nil,
    }
    for _,name in ipairs({entry.Key,entry.PetName,entry.EggDisplayName}) do
        if type(name)=="string" and name~="" then
            State.CatalogIndex[normalize(name)]=entry
            State.CatalogIndex[normalize(name:gsub("%s+[Ee][Gg][Gg]$",""))]=entry
        end
    end
    State.CatalogEntries[#State.CatalogEntries+1]=entry
end

local function buildCatalog()
    State.CatalogIndex={}
    State.CatalogEntries={}
    if typeof(AssetsData.ByRarity)=="table" then
        for _,group in pairs(AssetsData.ByRarity) do
            if typeof(group)=="table" then for key,cfg in pairs(group) do indexEntry(key,cfg) end end
        end
    end
    if #State.CatalogEntries==0 and typeof(AssetsData.Configs)=="table" then
        for key,cfg in pairs(AssetsData.Configs) do indexEntry(key,cfg) end
    end
end

local function findCatalog(category)
    if type(category)~="string" then return nil end
    return State.CatalogIndex[normalize(category)]
end

local function mutationFactor(record)
    local factor=1
    local seen={}
    for _,m in ipairs(copyMutations(record)) do
        local k=normalize(m)
        if not seen[k] then
            seen[k]=true
            local scalar=State.MutationScalars[k]
            if finite(scalar) then factor=factor+math.max(0,scalar-1) end
        end
    end
    return factor
end

local function fallbackEarnings(record,cfg)
    local base=cfg and tonumber(cfg.EarningRate)
    local scale=tonumber(record.AssetScale or record.Scale or (record.ItemData and (record.ItemData.AssetScale or record.ItemData.Scale)))
    if not (finite(base) and finite(scale) and scale>0) then return nil end
    local sizeFactor=scale<=5 and scale^1.85 or (5^1.85)*((scale/5)^1.2)
    return math.floor(base*sizeFactor*mutationFactor(record)+0.5)
end

local function resolveEarnings(record,cfg)
    if typeof(AssetEarnings)=="table" and type(AssetEarnings.MutationOnlyRatePerSecond)=="function" then
        local probe={}
        for k,v in pairs(record) do probe[k]=v end
        if typeof(record.ItemData)=="table" then
            for k,v in pairs(record.ItemData) do if probe[k]==nil then probe[k]=v end end
        end
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

local function recordCategory(record)
    local item=typeof(record.ItemData)=="table" and record.ItemData or nil
    return record.AssetCategory or record.Category or (item and (item.AssetCategory or item.Category or item.Name))
end

local function recordUid(record,key)
    local item=typeof(record.ItemData)=="table" and record.ItemData or nil
    local v=record.Uid or record.UID or record.Id or record.ID or (item and (item.Uid or item.UID or item.Id or item.ID)) or key
    return v~=nil and safeString(v) or nil
end

local function makeInventoryInfo(record,key)
    if typeof(record)~="table" then return nil end
    local category=recordCategory(record)
    if type(category)~="string" or category=="" then return nil end
    local cfg=findCatalog(category)
    local weight,wok=callTableFn(EggRecords,"WeightKg",record)
    local weightLabel,lok=callTableFn(EggRecords,"WeightLabel",record)
    local sell,sok=callTableFn(EggRecords,"SellPrice",record)
    local muts=copyMutations(record)
    local hasParasite=false
    for _,m in ipairs(muts) do if normalize(m)=="parasite" then hasParasite=true break end end
    return {
        Uid=recordUid(record,key),
        AssetCategory=category,
        PetName=cfg and cfg.PetName or category,
        EggDisplayName=cfg and cfg.EggDisplayName or nil,
        Rarity=cfg and cfg.Rarity or record.Rarity,
        RarityNumber=cfg and cfg.RarityNumber or tonumber(record.RarityNumber),
        RarityColor=cfg and cfg.RarityColor or nil,
        EarningsPerSecond=resolveEarnings(record,cfg),
        SellPrice=(sok and finite(tonumber(sell))) and tonumber(sell) or nil,
        WeightKg=(wok and finite(tonumber(weight))) and tonumber(weight) or nil,
        WeightLabel=lok and safeString(weightLabel) or nil,
        Mutations=muts,
        HasParasite=hasParasite,
        Raw=record,
    }
end

local function refreshInventoryData()
    State.InventoryEggs={}
    if not (SaveMod and type(SaveMod.Get)=="function") then return 0 end
    local ok,sd=pcall(SaveMod.Get)
    if not ok or typeof(sd)~="table" then return 0 end
    local inv=sd.EggInventory
    if typeof(inv)~="table" then return 0 end
    local n=0
    for key,record in pairs(inv) do
        local info=makeInventoryInfo(record,key)
        if info then n=n+1; State.InventoryEggs[n]=info end
    end
    return n
end

local function findTextDesc(root,text)
    if not root then return nil end
    for _,d in ipairs(root:GetDescendants()) do
        if (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Text==text then return d end
    end
end

local function findBaseGui()
    local parent=uiParent()
    for _,child in ipairs(parent:GetChildren()) do
        if child:IsA("ScreenGui") and child.Name:find("PsicoRoubeUmOvo",1,true)==1 and child:FindFirstChild("Main") then
            return child,child.Main
        end
    end
    return nil,nil
end

local function findPages()
    local normal=findTextDesc(mainFrame,"ESP • Ovos  ON") or findTextDesc(mainFrame,"ESP • Ovos  OFF") or findTextDesc(mainFrame,"ESP • Ovos")
    if normal then mainPage=normal.Parent end
    local rarity=findTextDesc(mainFrame,"Raridade mínima")
    if rarity then filterPage=rarity.Parent end
end

local function siblingAtY(label,className)
    if not label or not label.Parent then return nil end
    local y=label.Position.Y.Offset
    local best,bestDist=nil,999
    for _,child in ipairs(label.Parent:GetChildren()) do
        if child~=label and child:IsA(className) then
            local d=math.abs(child.Position.Y.Offset-y)
            if d<bestDist then best,bestDist=child,d end
        end
    end
    return bestDist<=4 and best or nil
end

local function readFilterConfig()
    local f={MinRarity=0,MinEarnings=0,MinSellPrice=0,SelectedPet="",MutationMode="Todas",ShowEarnings=true,ShowEggValue=false,ShowWeight=false}
    if not filterPage or not filterPage.Parent then findPages() end
    if not filterPage then return f end
    local function label(text) return findTextDesc(filterPage,text) end
    local rarity=siblingAtY(label("Raridade mínima"),"TextButton")
    if rarity then
        for i,v in ipairs(RARITY_ORDER) do if rarity.Text==v then f.MinRarity=i break end end
    end
    local earn=siblingAtY(label("Rendimento mínimo ($/s)"),"TextBox")
    local val=siblingAtY(label("Valor do ovo mín. ($)"),"TextBox")
    if earn then f.MinEarnings=parseSmartNumber(earn.Text) end
    if val then f.MinSellPrice=parseSmartNumber(val.Text) end
    local pet=siblingAtY(label("Pet"),"TextButton")
    if pet and pet.Text~="Selecionar pet..." then f.SelectedPet=pet.Text end
    local mut=siblingAtY(label("Mutação"),"TextButton")
    if mut and mut.Text~="" then f.MutationMode=mut.Text end
    local function readToggle(text,default)
        local b=siblingAtY(label(text),"TextButton")
        if not b then return default end
        return b.Text=="ON"
    end
    f.ShowEarnings=readToggle("Mostrar $/s do pet",true)
    f.ShowEggValue=readToggle("Mostrar valor do ovo",false)
    f.ShowWeight=readToggle("Mostrar peso",false)
    return f
end

local function mutationText(egg)
    if egg.Mutations and #egg.Mutations>0 then return table.concat(egg.Mutations,"+") end
    return "Normal"
end

local function mutationPass(egg,mode)
    local muts=egg.Mutations or {}
    if mode=="Todas" then return true end
    if mode=="Com mutação" then return #muts>0 end
    if mode=="Sem mutação" then return #muts==0 end
    local target=normalize(mode)
    for _,m in ipairs(muts) do if normalize(m)==target then return true end end
    return false
end

local function eggPasses(egg,f)
    if (tonumber(egg.RarityNumber) or 0)<f.MinRarity then return false end
    if (tonumber(egg.EarningsPerSecond) or 0)<f.MinEarnings then return false end
    if (tonumber(egg.SellPrice) or 0)<f.MinSellPrice then return false end
    if f.SelectedPet~="" then
        local selected=normalize(f.SelectedPet)
        local pet=normalize(egg.PetName or "")
        local cat=normalize(egg.AssetCategory or "")
        if pet~=selected and cat~=selected then return false end
    end
    return mutationPass(egg,f.MutationMode)
end

local function eggColor(egg)
    return typeof(egg.RarityColor)=="Color3" and egg.RarityColor or rarityFallbackColor(egg.Rarity)
end

local function backpackRoot()
    local rg=CoreGui:FindFirstChild("RobloxGui")
    return rg and rg:FindFirstChild("Backpack",true) or nil
end

local function sweepInventoryESP()
    local root=backpackRoot()
    if not root then return end
    for _,d in ipairs(root:GetDescendants()) do
        if d.Name=="PSICO_INV_ESP_INFO" or d.Name=="PSICO_INV_ESP_STROKE" then
            pcall(function() d:Destroy() end)
        end
    end
    State.LastVisible=0
end

local UID_ATTRS={"Uid","UID","EggUid","EggUID","ItemUid","ItemUID","InventoryUid","InventoryUID"}
local CATEGORY_ATTRS={"AssetCategory","Category","PetName","EggName","DisplayName"}

local function toolUid(tool)
    for _,name in ipairs(UID_ATTRS) do
        local v=tool:GetAttribute(name)
        if v~=nil then return safeString(v) end
        local child=tool:FindFirstChild(name)
        if child and child:IsA("ValueBase") then return safeString(child.Value) end
    end
end

local function toolCategory(tool)
    for _,name in ipairs(CATEGORY_ATTRS) do
        local v=tool:GetAttribute(name)
        if type(v)=="string" and v~="" then return v end
        local child=tool:FindFirstChild(name)
        if child and child:IsA("StringValue") and child.Value~="" then return child.Value end
    end
end

local function scoreName(text,egg)
    local t=normalize(text:gsub("%s*%[[Xx]%d+%]%s*$",""))
    if t=="" then return 0 end
    local best=0
    for _,name in ipairs({egg.PetName,egg.AssetCategory,egg.EggDisplayName}) do
        local k=normalize(name or "")
        if k~="" then
            if t==k then best=math.max(best,100)
            elseif t:find(k,1,true) or k:find(t,1,true) then best=math.max(best,70) end
        end
    end
    for _,m in ipairs(egg.Mutations or {}) do
        local k=normalize(m)
        if k~="" and t:find(k,1,true) then best=best+8 end
    end
    return best
end

local function collectTools()
    local out={}
    for _,container in ipairs({LP:FindFirstChildOfClass("Backpack"),LP.Character}) do
        if container then
            for _,child in ipairs(container:GetChildren()) do if child:IsA("Tool") then out[#out+1]=child end end
        end
    end
    return out
end

local function assignToolsToEggs(eggs)
    local byUid={}
    for i,egg in ipairs(eggs) do if egg.Uid then byUid[normalize(egg.Uid)]=i end end
    local tools=collectTools()
    local assignments={}
    local used={}
    for _,tool in ipairs(tools) do
        local idx
        local uid=toolUid(tool)
        if uid then idx=byUid[normalize(uid)] end
        if not idx then
            local cat=toolCategory(tool)
            local bestScore=0
            for i,egg in ipairs(eggs) do
                if not used[i] then
                    local s=math.max(scoreName(tool.Name,egg),scoreName(cat or "",egg))
                    if s>bestScore then bestScore=s; idx=i end
                end
            end
            if bestScore<60 then idx=nil end
        end
        if idx and not used[idx] then assignments[tool]=eggs[idx]; used[idx]=true end
    end
    return assignments,used
end

local function overlayText(egg,f)
    local lines={safeString(egg.Rarity or "?").." • "..mutationText(egg)}
    if f.ShowEarnings then
        lines[#lines+1]=egg.EarningsPerSecond and ("$"..formatCompact(egg.EarningsPerSecond).."/s") or "$?/s"
    end
    local extra={}
    if f.ShowEggValue then extra[#extra+1]=egg.SellPrice and ("$"..formatCompact(egg.SellPrice)) or "$?" end
    if f.ShowWeight then extra[#extra+1]=egg.WeightLabel or (egg.WeightKg and (formatCompact(egg.WeightKg).."kg") or "?kg") end
    if #extra>0 then lines[#lines+1]=table.concat(extra," • ") end
    return table.concat(lines,"\n")
end

local function addOverlay(toolNameLabel,egg,f)
    local slot=toolNameLabel.Parent
    if not slot or not slot:IsA("GuiObject") then return false end
    local old=slot:FindFirstChild("PSICO_INV_ESP_INFO")
    if old then old:Destroy() end
    local oldStroke=slot:FindFirstChild("PSICO_INV_ESP_STROKE")
    if oldStroke then oldStroke:Destroy() end

    local color=eggColor(egg)
    local stroke=Instance.new("UIStroke")
    stroke.Name="PSICO_INV_ESP_STROKE"
    stroke.Color=color
    stroke.Thickness=1.35
    stroke.Transparency=.18
    stroke.Parent=slot

    local label=Instance.new("TextLabel")
    label.Name="PSICO_INV_ESP_INFO"
    label.BackgroundColor3=Color3.fromRGB(5,9,16)
    label.BackgroundTransparency=.28
    label.BorderSizePixel=0
    label.Position=UDim2.new(0,2,0,2)
    label.Size=UDim2.new(1,-4,0,31)
    label.ZIndex=math.max(toolNameLabel.ZIndex+3,10)
    label.Font=Enum.Font.GothamBold
    label.Text=overlayText(egg,f)
    label.TextColor3=color
    label.TextSize=7
    label.TextStrokeColor3=Color3.new(0,0,0)
    label.TextStrokeTransparency=.12
    label.TextWrapped=true
    label.TextXAlignment=Enum.TextXAlignment.Center
    label.TextYAlignment=Enum.TextYAlignment.Top
    label.Parent=slot
    local corner=Instance.new("UICorner")
    corner.CornerRadius=UDim.new(0,4)
    corner.Parent=label
    return true
end

local function refreshInventoryESP()
    if not State.Alive then return end
    if not State.Enabled then sweepInventoryESP(); return end
    refreshInventoryData()
    local f=readFilterConfig()
    local eligible={}
    for _,egg in ipairs(State.InventoryEggs) do if eggPasses(egg,f) then eligible[#eligible+1]=egg end end

    local root=backpackRoot()
    if not root then State.LastVisible=0; return end
    sweepInventoryESP()

    local assignments,used=assignToolsToEggs(eligible)
    local toolByName={}
    for tool,egg in pairs(assignments) do
        local k=normalize(tool.Name:gsub("%s*%[[Xx]%d+%]%s*$",""))
        toolByName[k]=toolByName[k] or {}
        toolByName[k][#toolByName[k]+1]={Tool=tool,Egg=egg}
    end
    local consumedTools={}
    local consumedEggs={}
    local visible=0

    for _,d in ipairs(root:GetDescendants()) do
        if d:IsA("TextLabel") and d.Name=="ToolName" and d.Text~="" then
            local picked
            local k=normalize(d.Text:gsub("%s*%[[Xx]%d+%]%s*$",""))
            local bucket=toolByName[k]
            if bucket then
                for _,pair in ipairs(bucket) do
                    if not consumedTools[pair.Tool] then picked=pair.Egg; consumedTools[pair.Tool]=true; break end
                end
            end
            if not picked then
                local bestScore,bestIdx=0,nil
                for i,egg in ipairs(eligible) do
                    if not consumedEggs[i] then
                        local s=scoreName(d.Text,egg)
                        if s>bestScore then bestScore=s; bestIdx=i end
                    end
                end
                if bestIdx and bestScore>=60 then picked=eligible[bestIdx]; consumedEggs[bestIdx]=true end
            end
            if picked and addOverlay(d,picked,f) then visible=visible+1 end
        end
    end
    State.LastVisible=visible
end

local function paintToggle()
    if not toggleButton then return end
    toggleButton.Text="ESP • Inventário"..(State.Enabled and "  ON" or "  OFF")
    toggleButton.BackgroundColor3=State.Enabled and Color3.fromRGB(42,91,190) or Color3.fromRGB(35,44,61)
    toggleButton.TextColor3=Color3.fromRGB(245,248,255)
end

local function injectButton()
    findPages()
    if not mainPage then return false end
    for _,d in ipairs(mainPage:GetChildren()) do
        if d:IsA("TextButton") and d:GetAttribute("PSICOInventoryESP")==true then
            toggleButton=d; paintToggle(); return true
        end
    end

    for _,d in ipairs(mainPage:GetChildren()) do
        if d:IsA("GuiObject") and d.Position.Y.Scale==0 and d.Position.Y.Offset>=38 then
            d.Position=UDim2.new(d.Position.X.Scale,d.Position.X.Offset,d.Position.Y.Scale,d.Position.Y.Offset+38)
        end
    end
    mainPage.CanvasSize=UDim2.new(mainPage.CanvasSize.X.Scale,mainPage.CanvasSize.X.Offset,mainPage.CanvasSize.Y.Scale,mainPage.CanvasSize.Y.Offset+38)

    local normal=findTextDesc(mainPage,"ESP • Ovos  ON") or findTextDesc(mainPage,"ESP • Ovos  OFF") or findTextDesc(mainPage,"ESP • Ovos")
    if normal and normal:IsA("TextButton") then
        toggleButton=normal:Clone()
        for _,child in ipairs(toggleButton:GetChildren()) do
            if child:IsA("LocalScript") or child:IsA("Script") then child:Destroy() end
        end
    else
        toggleButton=Instance.new("TextButton")
        toggleButton.BackgroundColor3=Color3.fromRGB(35,44,61)
        toggleButton.BorderSizePixel=0
        toggleButton.Font=Enum.Font.GothamMedium
        toggleButton.TextSize=10
        local corner=Instance.new("UICorner")
        corner.CornerRadius=UDim.new(0,8)
        corner.Parent=toggleButton
    end
    toggleButton.Name="PSICO_INVENTORY_ESP_TOGGLE"
    toggleButton:SetAttribute("PSICOInventoryESP",true)
    toggleButton.Position=UDim2.fromOffset(0,38)
    toggleButton.Size=UDim2.new(1,0,0,32)
    toggleButton.Parent=mainPage
    paintToggle()
    connect(toggleButton.MouseButton1Click,function()
        State.Enabled=not State.Enabled
        paintToggle()
        refreshInventoryESP()
    end)
    return true
end

local function updateVersionLabel()
    if not mainFrame then return end
    for _,d in ipairs(mainFrame:GetDescendants()) do
        if d:IsA("TextLabel") and d.Text:find("V8.3",1,true)==1 then
            d.Text="V8.4 • INVENTORY ESP"
            return
        end
    end
end

local function cleanup()
    if not State.Alive then return end
    State.Alive=false
    sweepInventoryESP()
    if toggleButton and toggleButton.Parent then pcall(function() toggleButton:Destroy() end) end
    for _,c in ipairs(State.Connections) do disconnect(c) end
    _G.PSICO_INVENTORY_ESP_CLEANUP=nil
end
_G.PSICO_INVENTORY_ESP_CLEANUP=cleanup

local deadline=os.clock()+8
repeat
    baseGui,mainFrame=findBaseGui()
    if baseGui and mainFrame then break end
    task.wait(.1)
until os.clock()>=deadline or not State.Alive

if not (baseGui and mainFrame) then cleanup(); return end
if not resolveModules() then
    warn("[PSICO Inventory ESP] módulos de inventário não encontrados")
    cleanup()
    return
end
buildCatalog()
injectButton()
updateVersionLabel()

connect(baseGui.AncestryChanged,function(_,parent)
    if parent==nil then cleanup() end
end)

local backpack=LP:FindFirstChildOfClass("Backpack")
if backpack then
    connect(backpack.ChildAdded,function() task.defer(refreshInventoryESP) end)
    connect(backpack.ChildRemoved,function() task.defer(refreshInventoryESP) end)
end
connect(LP.ChildAdded,function(child)
    if child:IsA("Backpack") then
        connect(child.ChildAdded,function() task.defer(refreshInventoryESP) end)
        connect(child.ChildRemoved,function() task.defer(refreshInventoryESP) end)
    end
end)

-- Keep the inventory overlay synced with Save.EggInventory and the normal ESP filter controls.
task.defer(function()
    while State.Alive do
        task.wait(1.15)
        if State.Enabled then refreshInventoryESP() end
    end
end)

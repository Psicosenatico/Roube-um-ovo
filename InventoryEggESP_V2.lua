--[[
PSICOSENATICO | Steal An Egg - Inventory Egg ESP V2
Companion module for RoubeUmOvo_Menu.lua V8.3/V8.4.
- Targets the real Roblox Backpack inventory grid + hotbar.
- Reads Save.Get().EggInventory when available.
- Falls back to direct slot-name -> game catalog recognition.
- Reuses visible filters from the normal ESP page.
- Shows diagnostics in the menu: Save eggs / recognized slots / overlays.
- No hooks and no remote/game-state mutation.
]]

if _G.PSICO_INVENTORY_ESP_CLEANUP then pcall(_G.PSICO_INVENTORY_ESP_CLEANUP) end

local Players=game:GetService("Players")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local CoreGui=game:GetService("CoreGui")
local LP=Players.LocalPlayer

local State={Alive=true,Enabled=false,Connections={},CatalogIndex={},CatalogEntries={},InventoryEggs={},LastSave=0,LastRecognized=0,LastVisible=0}
local AssetsData,EggRecords,AssetEarnings,SaveMod
local baseGui,mainFrame,mainPage,filterPage,toggleButton,statusText

local RARITY_ORDER={"Common","Uncommon","Rare","Epic","Legendary","Mythic","Cosmic","Secret","Eternal","Divine"}

local function safeString(v) local ok,s=pcall(tostring,v); return ok and s or "?" end
local function lower(v) return string.lower(safeString(v or "")) end
local function normalize(v) return lower(v):gsub("[%s_%-%.:/%[%]%(%)']","") end
local function finite(v) return type(v)=="number" and v==v and v~=math.huge and v~=-math.huge end
local function connect(sig,fn) local c=sig:Connect(fn); State.Connections[#State.Connections+1]=c; return c end
local function disconnect(c) pcall(function() c:Disconnect() end) end
local function uiParent() local ok,h=pcall(function() if gethui then return gethui() end end); return (ok and h) or CoreGui end
local function findPath(root,pathText) local cur=root; for token in string.gmatch(pathText,"[^%.]+") do if not cur then return nil end; cur=cur:FindFirstChild(token) end; return cur end
local function requireOptional(pathText) local m=findPath(ReplicatedStorage,pathText); if not (m and m:IsA("ModuleScript")) then return nil end; local ok,v=pcall(require,m); return ok and v or nil end
local function callTableFn(tbl,name,...) if typeof(tbl)~="table" or type(tbl[name])~="function" then return nil,false end; local fn=tbl[name]; local ok,v=pcall(fn,...); if ok then return v,true end; ok,v=pcall(fn,tbl,...); return ok and v or nil,ok end

local function formatCompact(n)
    if not finite(n) then return "?" end
    local a=math.abs(n)
    if a>=1e12 then return string.format("%.2fT",n/1e12):gsub("%.?0+T$","T") end
    if a>=1e9 then return string.format("%.2fB",n/1e9):gsub("%.?0+B$","B") end
    if a>=1e6 then return string.format("%.2fM",n/1e6):gsub("%.?0+M$","M") end
    if a>=1e3 then return string.format("%.1fK",n/1e3):gsub("%.0K$","K") end
    return tostring(math.floor(n+0.5))
end

local function parseSmartNumber(text)
    local s=string.upper(safeString(text or "")):gsub("%s+",""):gsub("%$",""):gsub("/S",""):gsub("KG","")
    local suffix=s:match("([KMBT])$"); if suffix then s=s:sub(1,-2) end
    s=s:gsub(",","."); local n=tonumber(s) or 0; local mult={K=1e3,M=1e6,B=1e9,T=1e12}; if suffix then n=n*(mult[suffix] or 1) end
    return finite(n) and math.max(0,n) or 0
end

local function rarityFallbackColor(rarity)
    local map={Common=Color3.fromRGB(210,210,210),Uncommon=Color3.fromRGB(91,210,116),Rare=Color3.fromRGB(77,151,255),Epic=Color3.fromRGB(181,91,255),Legendary=Color3.fromRGB(255,174,58),Mythic=Color3.fromRGB(255,71,121),Cosmic=Color3.fromRGB(150,67,255),Secret=Color3.fromRGB(245,245,245),Eternal=Color3.fromRGB(245,71,255),Divine=Color3.fromRGB(52,255,238)}
    return map[rarity] or Color3.fromRGB(230,235,255)
end

local function resolveModules()
    AssetsData=requireOptional("Data.Assets")
    EggRecords=requireOptional("Shared.Util.EggRecords")
    AssetEarnings=requireOptional("Shared.Util.AssetEarnings")
    SaveMod=requireOptional("Shared.Save") or requireOptional("Data.Save")
    return typeof(AssetsData)=="table"
end

local function indexEntry(key,cfg)
    if typeof(cfg)~="table" or typeof(cfg.Rarity)~="table" then return end
    local e={Key=safeString(key),PetName=cfg.DisplayName or safeString(key),Rarity=cfg.Rarity.DisplayName or cfg.Rarity._id,RarityNumber=cfg.Rarity.RarityNumber,RarityColor=cfg.Rarity.Color,EarningRate=tonumber(cfg.EarningRate),EggDisplayName=typeof(cfg.Egg)=="table" and cfg.Egg.DisplayName or nil}
    for _,name in ipairs({e.Key,e.PetName,e.EggDisplayName}) do
        if type(name)=="string" and name~="" then
            State.CatalogIndex[normalize(name)]=e
            State.CatalogIndex[normalize(name:gsub("%s+[Ee][Gg][Gg]$",""))]=e
        end
    end
    State.CatalogEntries[#State.CatalogEntries+1]=e
end

local function buildCatalog()
    State.CatalogIndex={}; State.CatalogEntries={}
    if typeof(AssetsData.ByRarity)=="table" then for _,group in pairs(AssetsData.ByRarity) do if typeof(group)=="table" then for k,cfg in pairs(group) do indexEntry(k,cfg) end end end end
    if #State.CatalogEntries==0 and typeof(AssetsData.Configs)=="table" then for k,cfg in pairs(AssetsData.Configs) do indexEntry(k,cfg) end end
end
local function findCatalog(name) return type(name)=="string" and State.CatalogIndex[normalize(name)] or nil end

local function copyMutations(record)
    local out,seen={},{}
    if typeof(record)~="table" then return out end
    local item=typeof(record.ItemData)=="table" and record.ItemData or nil
    local src=record.Mutations or (item and item.Mutations)
    local function add(v) if v==nil then return end; local s=safeString(v); local k=normalize(s); if k~="" and not seen[k] then seen[k]=true; out[#out+1]=s end end
    if typeof(src)=="table" then for _,m in pairs(src) do add(m) end end
    add(record.BaseMutation or (item and item.BaseMutation)); if record.HasParasite==true or (item and item.HasParasite==true) then add("Parasite") end
    table.sort(out); return out
end

local function recordCategory(record)
    if typeof(record)~="table" then return nil end
    local item=typeof(record.ItemData)=="table" and record.ItemData or nil
    return record.AssetCategory or record.Category or record.Name or (item and (item.AssetCategory or item.Category or item.Name))
end

local function calcEarnings(record,cfg)
    if typeof(record)~="table" then return cfg and cfg.EarningRate or nil end
    if typeof(AssetEarnings)=="table" and type(AssetEarnings.MutationOnlyRatePerSecond)=="function" then
        local probe={}; for k,v in pairs(record) do probe[k]=v end
        if typeof(record.ItemData)=="table" then for k,v in pairs(record.ItemData) do if probe[k]==nil then probe[k]=v end end end
        probe.Scale=probe.Scale or probe.AssetScale; probe.Category=probe.Category or probe.AssetCategory; probe.ItemType=probe.ItemType or "Asset"
        local v,ok=callTableFn(AssetEarnings,"MutationOnlyRatePerSecond",probe); v=tonumber(v); if ok and finite(v) then return math.floor(v+0.5) end
    end
    local base=cfg and tonumber(cfg.EarningRate); local scale=tonumber(record.AssetScale or record.Scale or (record.ItemData and (record.ItemData.AssetScale or record.ItemData.Scale)))
    if finite(base) and finite(scale) and scale>0 then local sf=scale<=5 and scale^1.85 or (5^1.85)*((scale/5)^1.2); return math.floor(base*sf+0.5) end
    return base
end

local function makeInfo(record,key)
    local cat=recordCategory(record); if type(cat)~="string" or cat=="" then return nil end
    local cfg=findCatalog(cat); local weight,weightLabel,sell
    if typeof(EggRecords)=="table" then
        local v,ok=callTableFn(EggRecords,"WeightKg",record); if ok and finite(tonumber(v)) then weight=tonumber(v) end
        v,ok=callTableFn(EggRecords,"WeightLabel",record); if ok then weightLabel=safeString(v) end
        v,ok=callTableFn(EggRecords,"SellPrice",record); if ok and finite(tonumber(v)) then sell=tonumber(v) end
    end
    return {Uid=safeString(record.Uid or record.UID or record.Id or key or ""),AssetCategory=cat,PetName=cfg and cfg.PetName or cat,EggDisplayName=cfg and cfg.EggDisplayName or nil,Rarity=cfg and cfg.Rarity or record.Rarity,RarityNumber=cfg and cfg.RarityNumber or tonumber(record.RarityNumber),RarityColor=cfg and cfg.RarityColor or nil,EarningsPerSecond=calcEarnings(record,cfg),SellPrice=sell,WeightKg=weight,WeightLabel=weightLabel,Mutations=copyMutations(record),Exact=true}
end

local function refreshInventoryData()
    State.InventoryEggs={}; State.LastSave=0
    if not (SaveMod and type(SaveMod.Get)=="function") then return 0 end
    local ok,sd=pcall(SaveMod.Get); if not ok or typeof(sd)~="table" or typeof(sd.EggInventory)~="table" then return 0 end
    for key,record in pairs(sd.EggInventory) do local info=makeInfo(record,key); if info then State.InventoryEggs[#State.InventoryEggs+1]=info end end
    State.LastSave=#State.InventoryEggs; return State.LastSave
end

local function findTextDesc(root,text)
    if not root then return nil end
    for _,d in ipairs(root:GetDescendants()) do if (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Text==text then return d end end
end
local function findBaseGui()
    for _,child in ipairs(uiParent():GetChildren()) do if child:IsA("ScreenGui") and child.Name:find("PsicoRoubeUmOvo",1,true)==1 and child:FindFirstChild("Main") then return child,child.Main end end
end
local function findPages()
    local normal=findTextDesc(mainFrame,"ESP • Ovos  ON") or findTextDesc(mainFrame,"ESP • Ovos  OFF") or findTextDesc(mainFrame,"ESP • Ovos"); if normal then mainPage=normal.Parent end
    local rarity=findTextDesc(mainFrame,"Raridade mínima"); if rarity then filterPage=rarity.Parent end
end
local function siblingAtY(label,className)
    if not label or not label.Parent then return nil end
    local y=label.Position.Y.Offset; local best,dist=nil,999
    for _,c in ipairs(label.Parent:GetChildren()) do if c~=label and c:IsA(className) then local d=math.abs(c.Position.Y.Offset-y); if d<dist then best,dist=c,d end end end
    return dist<=4 and best or nil
end
local function readFilterConfig()
    local f={MinRarity=0,MinEarnings=0,MinSellPrice=0,SelectedPet="",MutationMode="Todas",ShowEarnings=true,ShowEggValue=false,ShowWeight=false}
    if not filterPage or not filterPage.Parent then findPages() end; if not filterPage then return f end
    local function lab(t) return findTextDesc(filterPage,t) end
    local b=siblingAtY(lab("Raridade mínima"),"TextButton"); if b then for i,v in ipairs(RARITY_ORDER) do if b.Text==v then f.MinRarity=i end end end
    local e=siblingAtY(lab("Rendimento mínimo ($/s)"),"TextBox"); if e then f.MinEarnings=parseSmartNumber(e.Text) end
    local val=siblingAtY(lab("Valor do ovo mín. ($)"),"TextBox"); if val then f.MinSellPrice=parseSmartNumber(val.Text) end
    local p=siblingAtY(lab("Pet"),"TextButton"); if p and p.Text~="Selecionar pet..." then f.SelectedPet=p.Text end
    local m=siblingAtY(lab("Mutação"),"TextButton"); if m and m.Text~="" then f.MutationMode=m.Text end
    local function tog(text,def) local x=siblingAtY(lab(text),"TextButton"); if not x then return def end; return x.Text=="ON" end
    f.ShowEarnings=tog("Mostrar $/s do pet",true); f.ShowEggValue=tog("Mostrar valor do ovo",false); f.ShowWeight=tog("Mostrar peso",false)
    return f
end

local function mutationPass(egg,mode)
    local muts=egg.Mutations or {}; if mode=="Todas" then return true end; if mode=="Com mutação" then return #muts>0 end; if mode=="Sem mutação" then return #muts==0 end
    local t=normalize(mode); for _,m in ipairs(muts) do if normalize(m)==t then return true end end; return false
end
local function passes(egg,f)
    if (tonumber(egg.RarityNumber) or 0)<f.MinRarity then return false end
    if f.MinEarnings>0 and (tonumber(egg.EarningsPerSecond) or 0)<f.MinEarnings then return false end
    if f.MinSellPrice>0 and (tonumber(egg.SellPrice) or 0)<f.MinSellPrice then return false end
    if f.SelectedPet~="" then local t=normalize(f.SelectedPet); if normalize(egg.PetName or "")~=t and normalize(egg.AssetCategory or "")~=t then return false end end
    return mutationPass(egg,f.MutationMode)
end

local function colorOf(egg) return typeof(egg.RarityColor)=="Color3" and egg.RarityColor or rarityFallbackColor(egg.Rarity) end
local function mutationText(egg) return egg.Mutations and #egg.Mutations>0 and table.concat(egg.Mutations,"+") or "Normal" end
local function overlayText(egg,f)
    local lines={(egg.Rarity or "?").." • "..mutationText(egg)}
    if f.ShowEarnings then lines[#lines+1]=egg.EarningsPerSecond and ("$"..formatCompact(egg.EarningsPerSecond).."/s") or "$?/s" end
    local ex={}; if f.ShowEggValue then ex[#ex+1]=egg.SellPrice and ("$"..formatCompact(egg.SellPrice)) or "$?" end; if f.ShowWeight then ex[#ex+1]=egg.WeightLabel or (egg.WeightKg and (formatCompact(egg.WeightKg).."kg") or "?kg") end
    if #ex>0 then lines[#lines+1]=table.concat(ex," • ") end; return table.concat(lines,"\n")
end

local function backpackRoot() local rg=CoreGui:FindFirstChild("RobloxGui"); return rg and rg:FindFirstChild("Backpack") end
local function sweep()
    local root=backpackRoot(); if not root then return end
    for _,d in ipairs(root:GetDescendants()) do if d.Name=="PSICO_INV_ESP_INFO" or d.Name=="PSICO_INV_ESP_STROKE" then pcall(function() d:Destroy() end) end end
    State.LastVisible=0
end

local function cleanSlotName(text) return safeString(text or ""):gsub("%s*%[[Xx]%d+%]%s*$",""):gsub("^%s+",""):gsub("%s+$","") end
local function slotCatalog(text)
    local name=cleanSlotName(text); local cfg=findCatalog(name); if cfg then return cfg end
    local n=normalize(name); local best,bestScore=nil,0
    if #n<3 then return nil end
    for _,e in ipairs(State.CatalogEntries) do
        for _,candidate in ipairs({e.PetName,e.Key,e.EggDisplayName}) do
            local c=normalize(candidate or ""); if c~="" then local score=(c==n and 100) or ((c:find(n,1,true) or n:find(c,1,true)) and math.min(#c,#n) or 0); if score>bestScore then best,bestScore=e,score end end
        end
    end
    return bestScore>=4 and best or nil
end

local function buildRecordBuckets()
    local buckets={}
    local function add(k,egg) k=normalize(k or ""); if k=="" then return end; buckets[k]=buckets[k] or {}; buckets[k][#buckets[k]+1]=egg end
    for _,egg in ipairs(State.InventoryEggs) do add(egg.PetName,egg); add(egg.AssetCategory,egg); add(egg.EggDisplayName,egg) end
    return buckets
end
local function popBucket(buckets,cfg,name)
    for _,k in ipairs({normalize(name),normalize(cfg and cfg.PetName or ""),normalize(cfg and cfg.Key or ""),normalize(cfg and cfg.EggDisplayName or "")}) do local b=buckets[k]; if b and #b>0 then return table.remove(b,1) end end
end
local function fallbackInfo(cfg,name)
    return {AssetCategory=cfg.Key,PetName=cfg.PetName or name,EggDisplayName=cfg.EggDisplayName,Rarity=cfg.Rarity,RarityNumber=cfg.RarityNumber,RarityColor=cfg.RarityColor,EarningsPerSecond=cfg.EarningRate,Mutations={},Exact=false}
end

local function addOverlay(toolNameLabel,egg,f)
    local slot=toolNameLabel.Parent; if not (slot and slot:IsA("GuiObject")) then return false end
    local color=colorOf(egg)
    local stroke=Instance.new("UIStroke"); stroke.Name="PSICO_INV_ESP_STROKE"; stroke.Color=color; stroke.Thickness=1.45; stroke.Transparency=.08; stroke.Parent=slot
    local label=Instance.new("TextLabel"); label.Name="PSICO_INV_ESP_INFO"; label.BackgroundColor3=Color3.fromRGB(4,7,13); label.BackgroundTransparency=.18; label.BorderSizePixel=0; label.Position=UDim2.new(0,1,0,1); label.Size=UDim2.new(1,-2,1,-2); label.ZIndex=math.max(toolNameLabel.ZIndex+5,20); label.Font=Enum.Font.GothamBold; label.Text=overlayText(egg,f); label.TextColor3=color; label.TextSize=7; label.TextStrokeColor3=Color3.new(0,0,0); label.TextStrokeTransparency=.08; label.TextWrapped=true; label.TextScaled=false; label.TextXAlignment=Enum.TextXAlignment.Center; label.TextYAlignment=Enum.TextYAlignment.Center; label.Parent=slot
    local corner=Instance.new("UICorner"); corner.CornerRadius=UDim.new(0,4); corner.Parent=label
    return true
end

local function updateStatus()
    if statusText then statusText.Text=string.format("Inv:%d  •  Slots:%d  •  ESP:%d",State.LastSave,State.LastRecognized,State.LastVisible) end
end

local function refreshESP()
    if not State.Alive then return end; if not State.Enabled then sweep(); updateStatus(); return end
    refreshInventoryData(); local f=readFilterConfig(); local root=backpackRoot(); if not root then State.LastRecognized=0; State.LastVisible=0; updateStatus(); return end
    sweep(); local buckets=buildRecordBuckets(); local recognized,visible=0,0
    for _,d in ipairs(root:GetDescendants()) do
        if d:IsA("TextLabel") and d.Name=="ToolName" and d.Text~="" then
            local cfg=slotCatalog(d.Text)
            if cfg then
                recognized=recognized+1
                local egg=popBucket(buckets,cfg,cleanSlotName(d.Text)) or fallbackInfo(cfg,cleanSlotName(d.Text))
                if passes(egg,f) and addOverlay(d,egg,f) then visible=visible+1 end
            end
        end
    end
    State.LastRecognized=recognized; State.LastVisible=visible; updateStatus()
end

local function paintToggle()
    if not toggleButton then return end; toggleButton.Text="ESP • Inventário"..(State.Enabled and "  ON" or "  OFF"); toggleButton.BackgroundColor3=State.Enabled and Color3.fromRGB(42,91,190) or Color3.fromRGB(35,44,61); toggleButton.TextColor3=Color3.fromRGB(245,248,255)
end

local function injectControls()
    findPages(); if not mainPage then return false end
    for _,d in ipairs(mainPage:GetChildren()) do if d:IsA("GuiObject") and d.Position.Y.Scale==0 and d.Position.Y.Offset>=38 then d.Position=UDim2.new(d.Position.X.Scale,d.Position.X.Offset,d.Position.Y.Scale,d.Position.Y.Offset+54) end end
    mainPage.CanvasSize=UDim2.new(mainPage.CanvasSize.X.Scale,mainPage.CanvasSize.X.Offset,mainPage.CanvasSize.Y.Scale,mainPage.CanvasSize.Y.Offset+54)
    local normal=findTextDesc(mainPage,"ESP • Ovos  ON") or findTextDesc(mainPage,"ESP • Ovos  OFF") or findTextDesc(mainPage,"ESP • Ovos")
    toggleButton=normal and normal:Clone() or Instance.new("TextButton"); toggleButton.Name="PSICO_INVENTORY_ESP_TOGGLE"; toggleButton.Position=UDim2.fromOffset(0,38); toggleButton.Size=UDim2.new(1,0,0,32); toggleButton.Parent=mainPage
    if not normal then toggleButton.BackgroundColor3=Color3.fromRGB(35,44,61); toggleButton.BorderSizePixel=0; toggleButton.Font=Enum.Font.GothamMedium; toggleButton.TextSize=10; local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0,8); c.Parent=toggleButton end
    paintToggle(); connect(toggleButton.MouseButton1Click,function() State.Enabled=not State.Enabled; paintToggle(); refreshESP() end)
    statusText=Instance.new("TextLabel"); statusText.Name="PSICO_INV_ESP_STATUS"; statusText.BackgroundTransparency=1; statusText.Position=UDim2.fromOffset(2,71); statusText.Size=UDim2.new(1,-4,0,16); statusText.Font=Enum.Font.Gotham; statusText.TextSize=8; statusText.TextColor3=Color3.fromRGB(130,158,205); statusText.TextXAlignment=Enum.TextXAlignment.Center; statusText.Parent=mainPage; updateStatus(); return true
end

local function updateVersion()
    for _,d in ipairs(mainFrame:GetDescendants()) do if d:IsA("TextLabel") and d.Text:find("V8.3",1,true)==1 then d.Text="V8.4.1 • INVENTORY ESP V2"; return end end
end
local function cleanup()
    if not State.Alive then return end; State.Alive=false; sweep(); if toggleButton and toggleButton.Parent then pcall(function() toggleButton:Destroy() end) end; if statusText and statusText.Parent then pcall(function() statusText:Destroy() end) end; for _,c in ipairs(State.Connections) do disconnect(c) end; _G.PSICO_INVENTORY_ESP_CLEANUP=nil
end
_G.PSICO_INVENTORY_ESP_CLEANUP=cleanup

local deadline=os.clock()+8
repeat baseGui,mainFrame=findBaseGui(); if baseGui and mainFrame then break end; task.wait(.1) until os.clock()>=deadline or not State.Alive
if not (baseGui and mainFrame) then cleanup(); return end
if not resolveModules() then warn("[PSICO Inventory ESP V2] Data.Assets não encontrado"); cleanup(); return end
buildCatalog(); injectControls(); updateVersion(); refreshInventoryData(); updateStatus()
connect(baseGui.AncestryChanged,function(_,p) if p==nil then cleanup() end end)
connect(CoreGui.DescendantAdded,function(d) if State.Enabled and (d.Name=="ToolName" or d.Name=="UIGridFrame" or d.Name=="Inventory") then task.defer(refreshESP) end end)

task.defer(function() while State.Alive do task.wait(.85); if State.Enabled then refreshESP() else updateStatus() end end end)

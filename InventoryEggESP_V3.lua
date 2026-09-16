--[[
PSICOSENATICO | Steal An Egg - Inventory Egg ESP V3
Independent overlay version.
- Does NOT parent labels inside Roblox Backpack slots.
- Uses slot AbsolutePosition/AbsoluteSize only as anchors.
- Draws in its own ScreenGui above the inventory.
- Reads Save.Get().EggInventory when available.
- Reuses normal ESP filters from RoubeUmOvo_Menu.lua.
]]

if _G.PSICO_INVENTORY_ESP_CLEANUP then pcall(_G.PSICO_INVENTORY_ESP_CLEANUP) end

local Players=game:GetService("Players")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local CoreGui=game:GetService("CoreGui")
local LP=Players.LocalPlayer

local State={
    Alive=true,Enabled=false,Connections={},CatalogIndex={},CatalogEntries={},InventoryEggs={},
    LastSave=0,LastRecognized=0,LastVisibleSlots=0,LastDrawn=0,Drawn={}
}

local AssetsData,EggRecords,AssetEarnings,SaveMod
local baseGui,mainFrame,mainPage,filterPage,toggleButton,statusText,overlayGui,overlayRoot
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

local function rarityColor(r)
    local m={Common=Color3.fromRGB(210,210,210),Uncommon=Color3.fromRGB(91,210,116),Rare=Color3.fromRGB(77,151,255),Epic=Color3.fromRGB(181,91,255),Legendary=Color3.fromRGB(255,174,58),Mythic=Color3.fromRGB(255,71,121),Cosmic=Color3.fromRGB(150,67,255),Secret=Color3.fromRGB(245,245,245),Eternal=Color3.fromRGB(245,71,255),Divine=Color3.fromRGB(52,255,238)}
    return m[r] or Color3.fromRGB(230,235,255)
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
    if typeof(AssetsData.ByRarity)=="table" then
        for _,group in pairs(AssetsData.ByRarity) do if typeof(group)=="table" then for k,cfg in pairs(group) do indexEntry(k,cfg) end end end
    end
    if #State.CatalogEntries==0 and typeof(AssetsData.Configs)=="table" then for k,cfg in pairs(AssetsData.Configs) do indexEntry(k,cfg) end end
end

local function findCatalog(name)
    if type(name)~="string" then return nil end
    local n=normalize(name)
    local exact=State.CatalogIndex[n]
    if exact then return exact end
    if #n<4 or n=="ovo" or n=="egg" then return nil end
    local best,bestScore=nil,0
    for _,e in ipairs(State.CatalogEntries) do
        for _,cand in ipairs({e.PetName,e.Key,e.EggDisplayName}) do
            local c=normalize(cand or "")
            if c~="" then
                local score=0
                if c==n then score=100 elseif c:find(n,1,true) or n:find(c,1,true) then score=math.min(#c,#n) end
                if score>bestScore then best,bestScore=e,score end
            end
        end
    end
    return bestScore>=4 and best or nil
end

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
    return cfg and cfg.EarningRate or nil
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

local function mutationText(egg) return egg.Mutations and #egg.Mutations>0 and table.concat(egg.Mutations,"+") or "Normal" end
local function infoText(egg,f)
    local first=egg.Rarity or "?"
    if egg.Mutations and #egg.Mutations>0 then first=first.." • "..mutationText(egg) end
    local second={}
    if f.ShowEarnings then second[#second+1]=egg.EarningsPerSecond and ("$"..formatCompact(egg.EarningsPerSecond).."/s") or "$?/s" end
    if f.ShowEggValue then second[#second+1]=egg.SellPrice and ("$"..formatCompact(egg.SellPrice)) or "$?" end
    if f.ShowWeight then second[#second+1]=egg.WeightLabel or (egg.WeightKg and (formatCompact(egg.WeightKg).."kg") or "?kg") end
    return first,(#second>0 and table.concat(second," • ") or nil)
end

local function cleanSlotName(text) return safeString(text or ""):gsub("%s*%[[Xx]%d+%]%s*$",""):gsub("^%s+",""):gsub("%s+$","") end
local function backpackRoot() local rg=CoreGui:FindFirstChild("RobloxGui"); return rg and rg:FindFirstChild("Backpack") end
local function isActuallyVisible(obj,stop)
    local cur=obj
    while cur and cur~=stop do
        if cur:IsA("GuiObject") and not cur.Visible then return false end
        cur=cur.Parent
    end
    return true
end

local function buildBuckets()
    local b={}
    local function add(k,e) k=normalize(k or ""); if k=="" then return end; b[k]=b[k] or {}; b[k][#b[k]+1]=e end
    for _,e in ipairs(State.InventoryEggs) do add(e.PetName,e); add(e.AssetCategory,e); add(e.EggDisplayName,e) end
    return b
end
local function popBucket(b,cfg,name)
    for _,k in ipairs({normalize(name),normalize(cfg and cfg.PetName or ""),normalize(cfg and cfg.Key or ""),normalize(cfg and cfg.EggDisplayName or "")}) do local q=b[k]; if q and #q>0 then return table.remove(q,1) end end
end
local function fallbackInfo(cfg,name)
    if not cfg then return nil end
    return {AssetCategory=cfg.Key,PetName=cfg.PetName or name,EggDisplayName=cfg.EggDisplayName,Rarity=cfg.Rarity,RarityNumber=cfg.RarityNumber,RarityColor=cfg.RarityColor,EarningsPerSecond=cfg.EarningRate,Mutations={},Exact=false}
end

local function ensureOverlayGui()
    if overlayGui and overlayGui.Parent then return end
    overlayGui=Instance.new("ScreenGui")
    overlayGui.Name="PSICO_INV_ESP_LAYER"
    overlayGui.ResetOnSpawn=false
    overlayGui.IgnoreGuiInset=true
    overlayGui.DisplayOrder=1000000
    overlayGui.ZIndexBehavior=Enum.ZIndexBehavior.Global
    overlayGui.Parent=uiParent()
    overlayRoot=Instance.new("Frame")
    overlayRoot.Name="Layer"
    overlayRoot.BackgroundTransparency=1
    overlayRoot.Size=UDim2.fromScale(1,1)
    overlayRoot.Parent=overlayGui
end

local function destroyDraw(slot)
    local rec=State.Drawn[slot]
    if rec then pcall(function() rec.Frame:Destroy() end); State.Drawn[slot]=nil end
end
local function clearDrawn()
    for slot in pairs(State.Drawn) do destroyDraw(slot) end
    State.LastDrawn=0
end

local function drawSlot(slot,egg,f)
    ensureOverlayGui()
    local pos,size=slot.AbsolutePosition,slot.AbsoluteSize
    if size.X<20 or size.Y<20 then return false end
    local rec=State.Drawn[slot]
    if not rec or not rec.Frame.Parent then
        local frame=Instance.new("Frame")
        frame.Name="EggSlotOverlay"
        frame.BackgroundTransparency=1
        frame.ZIndex=500
        frame.Parent=overlayRoot
        local stroke=Instance.new("UIStroke")
        stroke.Name="Border"
        stroke.Thickness=2
        stroke.Transparency=.05
        stroke.Parent=frame
        local corner=Instance.new("UICorner")
        corner.CornerRadius=UDim.new(0,8)
        corner.Parent=frame
        local badge=Instance.new("TextLabel")
        badge.Name="Badge"
        badge.BackgroundColor3=Color3.fromRGB(5,8,14)
        badge.BackgroundTransparency=.12
        badge.BorderSizePixel=0
        badge.ZIndex=501
        badge.Font=Enum.Font.GothamBold
        badge.TextSize=10
        badge.TextStrokeColor3=Color3.new(0,0,0)
        badge.TextStrokeTransparency=.15
        badge.TextWrapped=true
        badge.TextXAlignment=Enum.TextXAlignment.Center
        badge.TextYAlignment=Enum.TextYAlignment.Center
        badge.Parent=frame
        local bc=Instance.new("UICorner"); bc.CornerRadius=UDim.new(0,6); bc.Parent=badge
        rec={Frame=frame,Stroke=stroke,Badge=badge}; State.Drawn[slot]=rec
    end
    rec.Frame.Position=UDim2.fromOffset(pos.X,pos.Y)
    rec.Frame.Size=UDim2.fromOffset(size.X,size.Y)
    local color=typeof(egg.RarityColor)=="Color3" and egg.RarityColor or rarityColor(egg.Rarity)
    rec.Stroke.Color=color
    local a,b=infoText(egg,f)
    rec.Badge.Text=b and (a.."\n"..b) or a
    rec.Badge.TextColor3=color
    local h=b and math.clamp(math.floor(size.Y*.27),30,42) or math.clamp(math.floor(size.Y*.18),22,30)
    rec.Badge.Position=UDim2.fromOffset(4,4)
    rec.Badge.Size=UDim2.new(1,-8,0,h)
    rec.Frame.Visible=true
    return true
end

local function updateStatus()
    if statusText then statusText.Text=string.format("Inv:%d • Slots:%d • Vis:%d • Draw:%d",State.LastSave,State.LastRecognized,State.LastVisibleSlots,State.LastDrawn) end
end

local function refreshESP()
    if not State.Alive then return end
    if not State.Enabled then clearDrawn(); updateStatus(); return end
    refreshInventoryData()
    local root=backpackRoot(); if not root then clearDrawn(); State.LastRecognized=0; State.LastVisibleSlots=0; updateStatus(); return end
    local f=readFilterConfig(); local buckets=buildBuckets(); local keep={}; local recognized,visibleSlots,drawn=0,0,0
    for _,d in ipairs(root:GetDescendants()) do
        if d:IsA("TextLabel") and d.Name=="ToolName" and d.Text~="" then
            local name=cleanSlotName(d.Text)
            local cfg=findCatalog(name)
            if cfg then
                recognized=recognized+1
                local slot=d.Parent
                if slot and slot:IsA("GuiObject") and isActuallyVisible(slot,root) and isActuallyVisible(d,root) then
                    visibleSlots=visibleSlots+1
                    local egg=popBucket(buckets,cfg,name) or fallbackInfo(cfg,name)
                    if egg and passes(egg,f) and drawSlot(slot,egg,f) then keep[slot]=true; drawn=drawn+1 end
                end
            end
        end
    end
    for slot in pairs(State.Drawn) do if not keep[slot] then destroyDraw(slot) end end
    State.LastRecognized=recognized; State.LastVisibleSlots=visibleSlots; State.LastDrawn=drawn; updateStatus()
end

local function paintToggle()
    if not toggleButton then return end
    toggleButton.Text="ESP • Inventário"..(State.Enabled and "  ON" or "  OFF")
    toggleButton.BackgroundColor3=State.Enabled and Color3.fromRGB(42,91,190) or Color3.fromRGB(35,44,61)
    toggleButton.TextColor3=Color3.fromRGB(245,248,255)
end

local function injectControls()
    findPages(); if not mainPage then return false end
    for _,d in ipairs(mainPage:GetChildren()) do if d:IsA("GuiObject") and d.Position.Y.Scale==0 and d.Position.Y.Offset>=38 then d.Position=UDim2.new(d.Position.X.Scale,d.Position.X.Offset,d.Position.Y.Scale,d.Position.Y.Offset+54) end end
    mainPage.CanvasSize=UDim2.new(mainPage.CanvasSize.X.Scale,mainPage.CanvasSize.X.Offset,mainPage.CanvasSize.Y.Scale,mainPage.CanvasSize.Y.Offset+54)
    local normal=findTextDesc(mainPage,"ESP • Ovos  ON") or findTextDesc(mainPage,"ESP • Ovos  OFF") or findTextDesc(mainPage,"ESP • Ovos")
    toggleButton=normal and normal:Clone() or Instance.new("TextButton")
    toggleButton.Name="PSICO_INVENTORY_ESP_TOGGLE"; toggleButton.Position=UDim2.fromOffset(0,38); toggleButton.Size=UDim2.new(1,0,0,32); toggleButton.Parent=mainPage
    if not normal then toggleButton.BackgroundColor3=Color3.fromRGB(35,44,61); toggleButton.BorderSizePixel=0; toggleButton.Font=Enum.Font.GothamMedium; toggleButton.TextSize=10; local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0,8); c.Parent=toggleButton end
    paintToggle(); connect(toggleButton.MouseButton1Click,function() State.Enabled=not State.Enabled; paintToggle(); refreshESP() end)
    statusText=Instance.new("TextLabel"); statusText.Name="PSICO_INV_ESP_STATUS"; statusText.BackgroundTransparency=1; statusText.Position=UDim2.fromOffset(2,71); statusText.Size=UDim2.new(1,-4,0,16); statusText.Font=Enum.Font.Gotham; statusText.TextSize=8; statusText.TextColor3=Color3.fromRGB(130,158,205); statusText.TextXAlignment=Enum.TextXAlignment.Center; statusText.Parent=mainPage; updateStatus(); return true
end

local function updateVersion()
    for _,d in ipairs(mainFrame:GetDescendants()) do if d:IsA("TextLabel") and d.Text:find("V8.3",1,true)==1 then d.Text="V8.4.2 • INVENTORY ESP V3"; return end end
end
local function cleanup()
    if not State.Alive then return end
    State.Alive=false; clearDrawn(); if overlayGui then pcall(function() overlayGui:Destroy() end) end
    if toggleButton and toggleButton.Parent then pcall(function() toggleButton:Destroy() end) end
    if statusText and statusText.Parent then pcall(function() statusText:Destroy() end) end
    for _,c in ipairs(State.Connections) do disconnect(c) end
    _G.PSICO_INVENTORY_ESP_CLEANUP=nil
end
_G.PSICO_INVENTORY_ESP_CLEANUP=cleanup

local deadline=os.clock()+8
repeat baseGui,mainFrame=findBaseGui(); if baseGui and mainFrame then break end; task.wait(.1) until os.clock()>=deadline or not State.Alive
if not (baseGui and mainFrame) then cleanup(); return end
if not resolveModules() then warn("[PSICO Inventory ESP V3] Data.Assets não encontrado"); cleanup(); return end
buildCatalog(); injectControls(); updateVersion(); refreshInventoryData(); ensureOverlayGui(); updateStatus()
connect(baseGui.AncestryChanged,function(_,p) if p==nil then cleanup() end end)

task.defer(function()
    while State.Alive do
        task.wait(.35)
        if State.Enabled then refreshESP() else updateStatus() end
    end
end)

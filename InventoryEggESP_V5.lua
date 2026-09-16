--[[
PSICOSENATICO | Steal An Egg - Inventory Egg ESP V5
Independent inventory ESP page + independent filters.
Fixes V4 visual anchoring by iterating the real UIGridFrame slots.
]]

if _G.PSICO_INVENTORY_ESP_CLEANUP then pcall(_G.PSICO_INVENTORY_ESP_CLEANUP) end

local Players=game:GetService("Players")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local CoreGui=game:GetService("CoreGui")
local LP=Players.LocalPlayer

local CFG={Enabled=false,MinRarity=0,MinEarnings=0,MinSellPrice=0,PetFilter="",MutationMode="Todas",ShowEarnings=true,ShowEggValue=false,ShowWeight=false}
local State={Alive=true,Connections={},CatalogIndex={},CatalogEntries={},InventoryEggs={},Drawn={},LastSave=0,LastRecognized=0,LastVisible=0,LastDrawn=0}
local AssetsData,EggRecords,AssetEarnings,SaveMod
local baseGui,mainFrame,mainPage,filterPage,contentHost,sidebar,tabMain,tabFilters,tabInv,invPage,statusText
local overlayGui,overlayRoot
local RARITY_ORDER={"Common","Uncommon","Rare","Epic","Legendary","Mythic","Cosmic","Secret","Eternal","Divine"}
local MUTATION_MODES={"Todas","Com mutação","Sem mutação","Silver","Golden","Rainbow","Sakura","Boss","Monstrous","GreatBloom","Fractured","Parasite","Bloom","SpiritBloom"}

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
local function round(o,r) local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0,r or 8); c.Parent=o; return c end
local function mkLabel(parent,text,pos,size,ts) local l=Instance.new("TextLabel"); l.BackgroundTransparency=1;l.BorderSizePixel=0;l.Position=pos;l.Size=size;l.Font=Enum.Font.Gotham;l.Text=text;l.TextColor3=Color3.fromRGB(230,235,246);l.TextSize=ts or 9;l.TextXAlignment=Enum.TextXAlignment.Left;l.Parent=parent;return l end
local function mkButton(parent,text,pos,size) local b=Instance.new("TextButton");b.BackgroundColor3=Color3.fromRGB(35,44,61);b.BorderSizePixel=0;b.Position=pos;b.Size=size;b.Font=Enum.Font.GothamMedium;b.Text=text;b.TextColor3=Color3.fromRGB(242,246,255);b.TextSize=10;b.AutoButtonColor=true;b.Parent=parent;round(b,8);return b end
local function mkBox(parent,placeholder,pos,size) local b=Instance.new("TextBox");b.BackgroundColor3=Color3.fromRGB(29,38,55);b.BorderSizePixel=0;b.Position=pos;b.Size=size;b.Font=Enum.Font.Gotham;b.Text="";b.PlaceholderText=placeholder;b.TextColor3=Color3.fromRGB(242,246,255);b.PlaceholderColor3=Color3.fromRGB(128,145,176);b.TextSize=9;b.ClearTextOnFocus=false;b.Parent=parent;round(b,8);return b end

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
    for _,name in ipairs({e.Key,e.PetName,e.EggDisplayName}) do if type(name)=="string" and name~="" then State.CatalogIndex[normalize(name)]=e;State.CatalogIndex[normalize(name:gsub("%s+[Ee][Gg][Gg]$",""))]=e end end
    State.CatalogEntries[#State.CatalogEntries+1]=e
end
local function buildCatalog()
    State.CatalogIndex={};State.CatalogEntries={}
    if typeof(AssetsData.ByRarity)=="table" then for _,group in pairs(AssetsData.ByRarity) do if typeof(group)=="table" then for k,cfg in pairs(group) do indexEntry(k,cfg) end end end end
    if #State.CatalogEntries==0 and typeof(AssetsData.Configs)=="table" then for k,cfg in pairs(AssetsData.Configs) do indexEntry(k,cfg) end end
end
local function findCatalog(name)
    if type(name)~="string" then return nil end
    local n=normalize(name);local exact=State.CatalogIndex[n];if exact then return exact end
    if #n<4 or n=="ovo" or n=="egg" then return nil end
    local best,bestScore=nil,0
    for _,e in ipairs(State.CatalogEntries) do for _,cand in ipairs({e.PetName,e.Key,e.EggDisplayName}) do local c=normalize(cand or "");if c~="" then local score=(c==n and 100) or ((c:find(n,1,true) or n:find(c,1,true)) and math.min(#c,#n) or 0);if score>bestScore then best,bestScore=e,score end end end end
    return bestScore>=4 and best or nil
end
local function copyMutations(record)
    local out,seen={},{};if typeof(record)~="table" then return out end
    local item=typeof(record.ItemData)=="table" and record.ItemData or nil;local src=record.Mutations or (item and item.Mutations)
    local function add(v) if v==nil then return end;local s=safeString(v);local k=normalize(s);if k~="" and not seen[k] then seen[k]=true;out[#out+1]=s end end
    if typeof(src)=="table" then for _,m in pairs(src) do add(m) end end;add(record.BaseMutation or (item and item.BaseMutation));if record.HasParasite==true or (item and item.HasParasite==true) then add("Parasite") end;table.sort(out);return out
end
local function recordCategory(record) if typeof(record)~="table" then return nil end;local item=typeof(record.ItemData)=="table" and record.ItemData or nil;return record.AssetCategory or record.Category or record.Name or (item and (item.AssetCategory or item.Category or item.Name)) end
local function calcEarnings(record,cfg)
    if typeof(record)~="table" then return cfg and cfg.EarningRate or nil end
    if typeof(AssetEarnings)=="table" and type(AssetEarnings.MutationOnlyRatePerSecond)=="function" then local probe={};for k,v in pairs(record) do probe[k]=v end;if typeof(record.ItemData)=="table" then for k,v in pairs(record.ItemData) do if probe[k]==nil then probe[k]=v end end end;probe.Scale=probe.Scale or probe.AssetScale;probe.Category=probe.Category or probe.AssetCategory;probe.ItemType=probe.ItemType or "Asset";local v,ok=callTableFn(AssetEarnings,"MutationOnlyRatePerSecond",probe);v=tonumber(v);if ok and finite(v) then return math.floor(v+0.5) end end
    return cfg and cfg.EarningRate or nil
end
local function makeInfo(record,key)
    local cat=recordCategory(record);if type(cat)~="string" or cat=="" then return nil end
    local cfg=findCatalog(cat);local weight,weightLabel,sell
    if typeof(EggRecords)=="table" then local v,ok=callTableFn(EggRecords,"WeightKg",record);if ok and finite(tonumber(v)) then weight=tonumber(v) end;v,ok=callTableFn(EggRecords,"WeightLabel",record);if ok then weightLabel=safeString(v) end;v,ok=callTableFn(EggRecords,"SellPrice",record);if ok and finite(tonumber(v)) then sell=tonumber(v) end end
    return {AssetCategory=cat,PetName=cfg and cfg.PetName or cat,EggDisplayName=cfg and cfg.EggDisplayName or nil,Rarity=cfg and cfg.Rarity or record.Rarity,RarityNumber=cfg and cfg.RarityNumber or tonumber(record.RarityNumber),RarityColor=cfg and cfg.RarityColor or nil,EarningsPerSecond=calcEarnings(record,cfg),SellPrice=sell,WeightKg=weight,WeightLabel=weightLabel,Mutations=copyMutations(record),Exact=true}
end
local function refreshInventoryData()
    State.InventoryEggs={};State.LastSave=0
    if not (SaveMod and type(SaveMod.Get)=="function") then return 0 end
    local ok,sd=pcall(SaveMod.Get);if not ok or typeof(sd)~="table" or typeof(sd.EggInventory)~="table" then return 0 end
    for key,record in pairs(sd.EggInventory) do local info=makeInfo(record,key);if info then State.InventoryEggs[#State.InventoryEggs+1]=info end end;State.LastSave=#State.InventoryEggs;return State.LastSave
end
local function buildBuckets()
    local buckets={};local function add(k,e) k=normalize(k or "");if k=="" then return end;buckets[k]=buckets[k] or {};buckets[k][#buckets[k]+1]=e end
    for _,e in ipairs(State.InventoryEggs) do add(e.PetName,e);add(e.AssetCategory,e);add(e.EggDisplayName,e) end;return buckets
end
local function popBucket(buckets,cfg,name) for _,k in ipairs({normalize(name),normalize(cfg and cfg.PetName or ""),normalize(cfg and cfg.Key or ""),normalize(cfg and cfg.EggDisplayName or "")}) do local b=buckets[k];if b and #b>0 then return table.remove(b,1) end end end
local function fallbackInfo(cfg,name) return {AssetCategory=cfg.Key,PetName=cfg.PetName or name,EggDisplayName=cfg.EggDisplayName,Rarity=cfg.Rarity,RarityNumber=cfg.RarityNumber,RarityColor=cfg.RarityColor,EarningsPerSecond=cfg.EarningRate,Mutations={},Exact=false} end
local function mutationPass(egg) local mode=CFG.MutationMode;local muts=egg.Mutations or {};if mode=="Todas" then return true end;if mode=="Com mutação" then return #muts>0 end;if mode=="Sem mutação" then return #muts==0 end;local t=normalize(mode);for _,m in ipairs(muts) do if normalize(m)==t then return true end end;return false end
local function passes(egg) if (tonumber(egg.RarityNumber) or 0)<CFG.MinRarity then return false end;if CFG.MinEarnings>0 and (tonumber(egg.EarningsPerSecond) or 0)<CFG.MinEarnings then return false end;if CFG.MinSellPrice>0 and (tonumber(egg.SellPrice) or 0)<CFG.MinSellPrice then return false end;if CFG.PetFilter~="" then local t=normalize(CFG.PetFilter);if not normalize(egg.PetName or ""):find(t,1,true) and not normalize(egg.AssetCategory or ""):find(t,1,true) then return false end end;return mutationPass(egg) end
local function infoText(egg)
    local first=egg.Rarity or "?";if egg.Mutations and #egg.Mutations>0 then first=first.." • "..table.concat(egg.Mutations,"+") end
    local second={};if CFG.ShowEarnings then second[#second+1]=egg.EarningsPerSecond and ("$"..formatCompact(egg.EarningsPerSecond).."/s") or "$?/s" end;if CFG.ShowEggValue then second[#second+1]=egg.SellPrice and ("$"..formatCompact(egg.SellPrice)) or "$?" end;if CFG.ShowWeight then second[#second+1]=egg.WeightLabel or (egg.WeightKg and (formatCompact(egg.WeightKg).."kg") or "?kg") end;return first,(#second>0 and table.concat(second," • ") or nil)
end

local function ensureOverlay()
    if overlayGui and overlayGui.Parent then return end
    overlayGui=Instance.new("ScreenGui");overlayGui.Name="PsicoInventoryESPOverlay";overlayGui.ResetOnSpawn=false;overlayGui.IgnoreGuiInset=true;overlayGui.DisplayOrder=999999;overlayGui.ZIndexBehavior=Enum.ZIndexBehavior.Global;overlayGui.Parent=CoreGui
    overlayRoot=Instance.new("Frame");overlayRoot.Name="Root";overlayRoot.BackgroundTransparency=1;overlayRoot.Size=UDim2.fromScale(1,1);overlayRoot.Parent=overlayGui
end
local function clearDrawn() for _,rec in pairs(State.Drawn) do if rec.Frame then pcall(function() rec.Frame:Destroy() end) end end;State.Drawn={};State.LastDrawn=0 end
local function destroyDraw(slot) local r=State.Drawn[slot];if r and r.Frame then pcall(function() r.Frame:Destroy() end) end;State.Drawn[slot]=nil end
local function drawSlot(slot,egg)
    ensureOverlay();local pos,size=slot.AbsolutePosition,slot.AbsoluteSize;if size.X<40 or size.Y<40 then return false end
    local rec=State.Drawn[slot]
    if not rec or not rec.Frame.Parent then
        local f=Instance.new("Frame");f.Name="EggSlotOverlay";f.BackgroundTransparency=1;f.BorderSizePixel=0;f.ZIndex=100;f.Parent=overlayRoot
        local stroke=Instance.new("UIStroke");stroke.Name="Border";stroke.Thickness=2;stroke.Transparency=.04;stroke.Parent=f
        local badge=Instance.new("TextLabel");badge.Name="Badge";badge.BackgroundColor3=Color3.fromRGB(5,8,15);badge.BackgroundTransparency=.12;badge.BorderSizePixel=0;badge.Font=Enum.Font.GothamBold;badge.TextWrapped=true;badge.TextScaled=true;badge.TextStrokeColor3=Color3.new(0,0,0);badge.TextStrokeTransparency=.05;badge.ZIndex=101;badge.Parent=f;round(badge,5)
        rec={Frame=f,Stroke=stroke,Badge=badge};State.Drawn[slot]=rec
    end
    local color=typeof(egg.RarityColor)=="Color3" and egg.RarityColor or rarityColor(egg.Rarity);rec.Frame.Position=UDim2.fromOffset(pos.X,pos.Y);rec.Frame.Size=UDim2.fromOffset(size.X,size.Y);rec.Stroke.Color=color
    local a,b=infoText(egg);rec.Badge.Text=b and (a.."\n"..b) or a;rec.Badge.TextColor3=color
    local h=b and math.clamp(math.floor(size.Y*.30),34,50) or math.clamp(math.floor(size.Y*.20),25,34)
    rec.Badge.Position=UDim2.new(0,4,1,-h-4);rec.Badge.Size=UDim2.new(1,-8,0,h);rec.Frame.Visible=true;return true
end

local function cleanSlotName(text) return safeString(text or ""):gsub("%s*%[[Xx]%d+%]%s*$",""):gsub("^%s+",""):gsub("%s+$","") end
local function getInventoryParts()
    local rg=CoreGui:FindFirstChild("RobloxGui");local backpack=rg and rg:FindFirstChild("Backpack");local inv=backpack and backpack:FindFirstChild("Inventory");local scroll=inv and inv:FindFirstChild("ScrollingFrame",true);local grid=scroll and scroll:FindFirstChild("UIGridFrame",true);return backpack,inv,scroll,grid
end
local function overlaps(slot,scroll)
    local p,s=slot.AbsolutePosition,slot.AbsoluteSize;local rp,rs=scroll.AbsolutePosition,scroll.AbsoluteSize
    return (p.X+s.X)>rp.X and p.X<(rp.X+rs.X) and (p.Y+s.Y)>rp.Y and p.Y<(rp.Y+rs.Y)
end
local function findToolName(slot)
    if not slot then return nil end
    for _,d in ipairs(slot:GetDescendants()) do if d:IsA("TextLabel") and d.Name=="ToolName" and d.Text~="" then return d end end
end
local function collectSlots(scroll,grid)
    local out={}
    if grid then
        for _,child in ipairs(grid:GetChildren()) do if child:IsA("GuiObject") then local t=findToolName(child);if t then out[#out+1]={Slot=child,Label=t} end end end
    end
    if #out==0 and scroll then
        local seen={}
        for _,d in ipairs(scroll:GetDescendants()) do
            if d:IsA("TextLabel") and d.Name=="ToolName" and d.Text~="" then
                local cur=d.Parent
                while cur and cur.Parent~=scroll and cur.Parent~=grid and cur~=scroll do cur=cur.Parent end
                if cur and cur:IsA("GuiObject") and not seen[cur] then seen[cur]=true;out[#out+1]={Slot=cur,Label=d} end
            end
        end
    end
    return out
end
local function updateStatus() if statusText then statusText.Text=string.format("Inv:%d • Slots:%d • Vis:%d • Draw:%d",State.LastSave,State.LastRecognized,State.LastVisible,State.LastDrawn) end end
local function refreshESP()
    if not State.Alive then return end
    if not CFG.Enabled then clearDrawn();updateStatus();return end
    refreshInventoryData();local _,inv,scroll,grid=getInventoryParts()
    if not (inv and scroll and inv.Visible) then clearDrawn();State.LastRecognized=0;State.LastVisible=0;State.LastDrawn=0;updateStatus();return end
    local buckets=buildBuckets();local keep={};local recognized,visible,drawn=0,0,0
    for _,pair in ipairs(collectSlots(scroll,grid)) do
        local slot,label=pair.Slot,pair.Label;local name=cleanSlotName(label.Text);local cfg=findCatalog(name)
        if cfg then
            recognized=recognized+1
            if slot.AbsoluteSize.X>=40 and slot.AbsoluteSize.Y>=40 and overlaps(slot,scroll) then
                visible=visible+1;local egg=popBucket(buckets,cfg,name) or fallbackInfo(cfg,name)
                if egg and passes(egg) and drawSlot(slot,egg) then keep[slot]=true;drawn=drawn+1 end
            end
        end
    end
    for slot in pairs(State.Drawn) do if not keep[slot] then destroyDraw(slot) end end
    State.LastRecognized=recognized;State.LastVisible=visible;State.LastDrawn=drawn;updateStatus()
end

local function findTextDesc(root,text) if not root then return nil end;for _,d in ipairs(root:GetDescendants()) do if (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Text==text then return d end end end
local function findBaseGui() for _,child in ipairs(uiParent():GetChildren()) do if child:IsA("ScreenGui") and child.Name:find("PsicoRoubeUmOvo",1,true)==1 and child:FindFirstChild("Main") then return child,child.Main end end end
local function locateBaseUi()
    tabMain=findTextDesc(mainFrame,"FUNÇÕES");tabFilters=findTextDesc(mainFrame,"FILTROS ESP");local normal=findTextDesc(mainFrame,"ESP • Ovos  ON") or findTextDesc(mainFrame,"ESP • Ovos  OFF") or findTextDesc(mainFrame,"ESP • Ovos");local rarity=findTextDesc(mainFrame,"Raridade mínima");mainPage=normal and normal.Parent or nil;filterPage=rarity and rarity.Parent or nil;contentHost=mainPage and mainPage.Parent or (filterPage and filterPage.Parent);sidebar=tabFilters and tabFilters.Parent or nil;return tabMain and tabFilters and mainPage and filterPage and contentHost and sidebar
end
local function makeCycleButton(parent,labelText,y,values,getter,setter)
    mkLabel(parent,labelText,UDim2.fromOffset(0,y),UDim2.new(.45,0,0,28),9);local b=mkButton(parent,getter(),UDim2.new(.47,0,0,y),UDim2.new(.53,-4,0,28));connect(b.MouseButton1Click,function() local cur=getter();local idx=1;for i,v in ipairs(values) do if v==cur then idx=i break end end;idx=idx%#values+1;setter(values[idx]);b.Text=getter();refreshESP() end);return b
end
local function makeInlineToggle(parent,text,y,key)
    mkLabel(parent,text,UDim2.fromOffset(0,y),UDim2.new(.72,0,0,26),9);local b=mkButton(parent,CFG[key] and "ON" or "OFF",UDim2.new(.74,0,0,y),UDim2.new(.26,-4,0,26));connect(b.MouseButton1Click,function() CFG[key]=not CFG[key];b.Text=CFG[key] and "ON" or "OFF";refreshESP() end);return b
end
local function buildIndependentPage()
    tabInv=mkButton(sidebar,"ESP INVENTÁRIO",UDim2.fromOffset(0,100),UDim2.new(1,0,0,42));invPage=Instance.new("ScrollingFrame");invPage.Name="InventoryESPPage";invPage.BackgroundTransparency=1;invPage.BorderSizePixel=0;invPage.Position=UDim2.fromOffset(8,8);invPage.Size=UDim2.new(1,-16,1,-16);invPage.ScrollBarThickness=3;invPage.ScrollBarImageColor3=Color3.fromRGB(94,139,223);invPage.Visible=false;invPage.Parent=contentHost
    local y=0;mkLabel(invPage,"Ativar ESP do inventário",UDim2.fromOffset(0,y),UDim2.new(.45,0,0,30),9);local enable=mkButton(invPage,"OFF",UDim2.new(.47,0,0,y),UDim2.new(.53,-4,0,30));y=y+36
    local function paintEnable() enable.Text=CFG.Enabled and "ON" or "OFF";enable.BackgroundColor3=CFG.Enabled and Color3.fromRGB(42,91,190) or Color3.fromRGB(35,44,61) end;paintEnable();connect(enable.MouseButton1Click,function() CFG.Enabled=not CFG.Enabled;paintEnable();refreshESP() end)
    local rarityValues={"Todas"};for _,v in ipairs(RARITY_ORDER) do rarityValues[#rarityValues+1]=v end
    makeCycleButton(invPage,"Raridade mínima",y,rarityValues,function() return CFG.MinRarity==0 and "Todas" or RARITY_ORDER[CFG.MinRarity] end,function(v) CFG.MinRarity=0;for i,r in ipairs(RARITY_ORDER) do if r==v then CFG.MinRarity=i break end end end);y=y+34
    mkLabel(invPage,"Rendimento mínimo ($/s)",UDim2.fromOffset(0,y),UDim2.new(.45,0,0,28),9);local earnings=mkBox(invPage,"Ex: 2M",UDim2.new(.47,0,0,y),UDim2.new(.53,-4,0,28));y=y+34
    mkLabel(invPage,"Valor do ovo mín. ($)",UDim2.fromOffset(0,y),UDim2.new(.45,0,0,28),9);local value=mkBox(invPage,"Opcional",UDim2.new(.47,0,0,y),UDim2.new(.53,-4,0,28));y=y+34
    mkLabel(invPage,"Pet",UDim2.fromOffset(0,y),UDim2.new(.45,0,0,28),9);local pet=mkBox(invPage,"Todos / nome",UDim2.new(.47,0,0,y),UDim2.new(.53,-4,0,28));y=y+34
    makeCycleButton(invPage,"Mutação",y,MUTATION_MODES,function() return CFG.MutationMode end,function(v) CFG.MutationMode=v end);y=y+38
    makeInlineToggle(invPage,"Mostrar $/s do pet",y,"ShowEarnings");y=y+30;makeInlineToggle(invPage,"Mostrar valor do ovo",y,"ShowEggValue");y=y+30;makeInlineToggle(invPage,"Mostrar peso",y,"ShowWeight");y=y+36
    statusText=mkLabel(invPage,"Inv:0 • Slots:0 • Vis:0 • Draw:0",UDim2.fromOffset(0,y),UDim2.new(1,-4,0,24),8);statusText.TextXAlignment=Enum.TextXAlignment.Center;statusText.TextColor3=Color3.fromRGB(139,164,207);y=y+30
    local reset=mkButton(invPage,"Limpar filtros do inventário",UDim2.fromOffset(0,y),UDim2.new(1,-4,0,30));y=y+36;invPage.CanvasSize=UDim2.fromOffset(0,y)
    local function syncBoxes() CFG.MinEarnings=parseSmartNumber(earnings.Text);CFG.MinSellPrice=parseSmartNumber(value.Text);CFG.PetFilter=pet.Text or "";refreshESP() end;connect(earnings.FocusLost,syncBoxes);connect(value.FocusLost,syncBoxes);connect(pet.FocusLost,syncBoxes)
    connect(reset.MouseButton1Click,function() CFG.MinRarity=0;CFG.MinEarnings=0;CFG.MinSellPrice=0;CFG.PetFilter="";CFG.MutationMode="Todas";CFG.ShowEarnings=true;CFG.ShowEggValue=false;CFG.ShowWeight=false;earnings.Text="";value.Text="";pet.Text="";refreshESP() end)
    local function hideInv() invPage.Visible=false;tabInv.BackgroundColor3=Color3.fromRGB(35,44,61) end;connect(tabMain.MouseButton1Click,hideInv);connect(tabFilters.MouseButton1Click,hideInv)
    connect(tabInv.MouseButton1Click,function() mainPage.Visible=false;filterPage.Visible=false;invPage.Visible=true;tabMain.BackgroundColor3=Color3.fromRGB(35,44,61);tabFilters.BackgroundColor3=Color3.fromRGB(35,44,61);tabInv.BackgroundColor3=Color3.fromRGB(42,91,190) end)
end
local function updateVersion() for _,d in ipairs(mainFrame:GetDescendants()) do if d:IsA("TextLabel") and d.Text:find("V8.3",1,true)==1 then d.Text="V8.4.4 • INVENTORY ESP V5";return end end end
local function cleanup() if not State.Alive then return end;State.Alive=false;clearDrawn();if overlayGui then pcall(function() overlayGui:Destroy() end) end;if invPage then pcall(function() invPage:Destroy() end) end;if tabInv then pcall(function() tabInv:Destroy() end) end;for _,c in ipairs(State.Connections) do disconnect(c) end;_G.PSICO_INVENTORY_ESP_CLEANUP=nil end
_G.PSICO_INVENTORY_ESP_CLEANUP=cleanup

local deadline=os.clock()+8
repeat baseGui,mainFrame=findBaseGui();if baseGui and mainFrame then break end;task.wait(.1) until os.clock()>=deadline or not State.Alive
if not (baseGui and mainFrame) then cleanup();return end
if not locateBaseUi() then warn("[PSICO Inventory ESP V5] base UI não localizada");cleanup();return end
if not resolveModules() then warn("[PSICO Inventory ESP V5] Data.Assets não encontrado");cleanup();return end
buildCatalog();buildIndependentPage();updateVersion();refreshInventoryData();updateStatus();connect(baseGui.AncestryChanged,function(_,p) if p==nil then cleanup() end end)

task.defer(function()
    while State.Alive do
        local _,inv=getInventoryParts()
        if CFG.Enabled and inv and inv.Visible then refreshESP();task.wait(.15) else if CFG.Enabled then clearDrawn();State.LastVisible=0;State.LastDrawn=0;updateStatus() end;task.wait(.45) end
    end
end)

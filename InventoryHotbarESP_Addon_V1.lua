--[[
PSICOSENATICO | Steal An Egg - Inventory Hotbar ESP Addon V1
Companion for InventoryEggESP_V5.lua.
Adds inventory ESP to Roblox Backpack.Hotbar slots while reusing the same
ESP INVENTÁRIO page/toggle/filters already created by V5.
]]

local Players=game:GetService("Players")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local CoreGui=game:GetService("CoreGui")
local LP=Players.LocalPlayer

local Alive=true
local Connections={}
local Drawn={}
local CatalogIndex={}
local CatalogEntries={}
local InventoryEggs={}
local AssetsData,EggRecords,AssetEarnings,SaveMod
local overlayGui,overlayRoot

local RARITY_ORDER={"Common","Uncommon","Rare","Epic","Legendary","Mythic","Cosmic","Secret","Eternal","Divine"}

local function safeString(v) local ok,s=pcall(tostring,v); return ok and s or "?" end
local function normalize(v) return string.lower(safeString(v or "")):gsub("[%s_%-%.:/%[%]%(%)']","") end
local function finite(v) return type(v)=="number" and v==v and v~=math.huge and v~=-math.huge end
local function connect(sig,fn) local c=sig:Connect(fn); Connections[#Connections+1]=c; return c end
local function findPath(root,pathText) local cur=root; for token in string.gmatch(pathText,"[^%.]+") do if not cur then return nil end;cur=cur:FindFirstChild(token) end;return cur end
local function requireOptional(pathText) local m=findPath(ReplicatedStorage,pathText);if not (m and m:IsA("ModuleScript")) then return nil end;local ok,v=pcall(require,m);return ok and v or nil end
local function callTableFn(tbl,name,...) if typeof(tbl)~="table" or type(tbl[name])~="function" then return nil,false end;local fn=tbl[name];local ok,v=pcall(fn,...);if ok then return v,true end;ok,v=pcall(fn,tbl,...);return ok and v or nil,ok end
local function round(o,r) local c=Instance.new("UICorner");c.CornerRadius=UDim.new(0,r or 5);c.Parent=o end

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
    local suffix=s:match("([KMBT])$");if suffix then s=s:sub(1,-2) end
    s=s:gsub(",",".");local n=tonumber(s) or 0;local mult={K=1e3,M=1e6,B=1e9,T=1e12};if suffix then n=n*(mult[suffix] or 1) end
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
            CatalogIndex[normalize(name)]=e
            CatalogIndex[normalize(name:gsub("%s+[Ee][Gg][Gg]$",""))]=e
        end
    end
    CatalogEntries[#CatalogEntries+1]=e
end
local function buildCatalog()
    CatalogIndex={};CatalogEntries={}
    if typeof(AssetsData.ByRarity)=="table" then for _,group in pairs(AssetsData.ByRarity) do if typeof(group)=="table" then for k,cfg in pairs(group) do indexEntry(k,cfg) end end end end
    if #CatalogEntries==0 and typeof(AssetsData.Configs)=="table" then for k,cfg in pairs(AssetsData.Configs) do indexEntry(k,cfg) end end
end
local function findCatalog(name)
    local n=normalize(name);local exact=CatalogIndex[n];if exact then return exact end
    if #n<4 or n=="ovo" or n=="egg" then return nil end
    local best,bestScore=nil,0
    for _,e in ipairs(CatalogEntries) do
        for _,cand in ipairs({e.PetName,e.Key,e.EggDisplayName}) do
            local c=normalize(cand or "");if c~="" then local score=(c==n and 100) or ((c:find(n,1,true) or n:find(c,1,true)) and math.min(#c,#n) or 0);if score>bestScore then best,bestScore=e,score end end
        end
    end
    return bestScore>=4 and best or nil
end
local function copyMutations(record)
    local out,seen={},{};if typeof(record)~="table" then return out end
    local item=typeof(record.ItemData)=="table" and record.ItemData or nil;local src=record.Mutations or (item and item.Mutations)
    local function add(v) if v==nil then return end;local s=safeString(v);local k=normalize(s);if k~="" and not seen[k] then seen[k]=true;out[#out+1]=s end end
    if typeof(src)=="table" then for _,m in pairs(src) do add(m) end end;add(record.BaseMutation or (item and item.BaseMutation));if record.HasParasite==true or (item and item.HasParasite==true) then add("Parasite") end;table.sort(out);return out
end
local function recordCategory(record)
    if typeof(record)~="table" then return nil end;local item=typeof(record.ItemData)=="table" and record.ItemData or nil
    return record.AssetCategory or record.Category or record.Name or (item and (item.AssetCategory or item.Category or item.Name))
end
local function calcEarnings(record,cfg)
    if typeof(record)~="table" then return cfg and cfg.EarningRate or nil end
    if typeof(AssetEarnings)=="table" and type(AssetEarnings.MutationOnlyRatePerSecond)=="function" then
        local probe={};for k,v in pairs(record) do probe[k]=v end;if typeof(record.ItemData)=="table" then for k,v in pairs(record.ItemData) do if probe[k]==nil then probe[k]=v end end end
        probe.Scale=probe.Scale or probe.AssetScale;probe.Category=probe.Category or probe.AssetCategory;probe.ItemType=probe.ItemType or "Asset"
        local v,ok=callTableFn(AssetEarnings,"MutationOnlyRatePerSecond",probe);v=tonumber(v);if ok and finite(v) then return math.floor(v+0.5) end
    end
    return cfg and cfg.EarningRate or nil
end
local function makeInfo(record)
    local cat=recordCategory(record);if type(cat)~="string" or cat=="" then return nil end
    local cfg=findCatalog(cat);local weight,weightLabel,sell
    if typeof(EggRecords)=="table" then
        local v,ok=callTableFn(EggRecords,"WeightKg",record);if ok and finite(tonumber(v)) then weight=tonumber(v) end
        v,ok=callTableFn(EggRecords,"WeightLabel",record);if ok then weightLabel=safeString(v) end
        v,ok=callTableFn(EggRecords,"SellPrice",record);if ok and finite(tonumber(v)) then sell=tonumber(v) end
    end
    return {AssetCategory=cat,PetName=cfg and cfg.PetName or cat,EggDisplayName=cfg and cfg.EggDisplayName or nil,Rarity=cfg and cfg.Rarity or record.Rarity,RarityNumber=cfg and cfg.RarityNumber or tonumber(record.RarityNumber),RarityColor=cfg and cfg.RarityColor or nil,EarningsPerSecond=calcEarnings(record,cfg),SellPrice=sell,WeightKg=weight,WeightLabel=weightLabel,Mutations=copyMutations(record)}
end
local function refreshInventory()
    InventoryEggs={};if not (SaveMod and type(SaveMod.Get)=="function") then return end
    local ok,sd=pcall(SaveMod.Get);if not ok or typeof(sd)~="table" or typeof(sd.EggInventory)~="table" then return end
    for _,record in pairs(sd.EggInventory) do local e=makeInfo(record);if e then InventoryEggs[#InventoryEggs+1]=e end end
end
local function buildBuckets()
    local buckets={};local function add(k,e) k=normalize(k or "");if k=="" then return end;buckets[k]=buckets[k] or {};buckets[k][#buckets[k]+1]=e end
    for _,e in ipairs(InventoryEggs) do add(e.PetName,e);add(e.AssetCategory,e);add(e.EggDisplayName,e) end;return buckets
end
local function popBucket(buckets,cfg,name)
    for _,k in ipairs({normalize(name),normalize(cfg and cfg.PetName or ""),normalize(cfg and cfg.Key or ""),normalize(cfg and cfg.EggDisplayName or "")}) do local b=buckets[k];if b and #b>0 then return table.remove(b,1) end end
end
local function fallbackInfo(cfg,name) return {AssetCategory=cfg.Key,PetName=cfg.PetName or name,EggDisplayName=cfg.EggDisplayName,Rarity=cfg.Rarity,RarityNumber=cfg.RarityNumber,RarityColor=cfg.RarityColor,EarningsPerSecond=cfg.EarningRate,Mutations={}} end

local function findText(root,text)
    if not root then return nil end
    for _,d in ipairs(root:GetDescendants()) do if (d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox")) and d.Text==text then return d end end
end
local function siblingAtY(label,className)
    if not label or not label.Parent then return nil end;local y=label.Position.Y.Offset;local best,dist=nil,999
    for _,c in ipairs(label.Parent:GetChildren()) do if c~=label and c:IsA(className) then local dd=math.abs(c.Position.Y.Offset-y);if dd<dist then best,dist=c,dd end end end
    return dist<=5 and best or nil
end
local function getInventoryPage()
    local gui
    for _,g in ipairs(CoreGui:GetChildren()) do if g:IsA("ScreenGui") and g.Name:find("PsicoRoubeUmOvo",1,true)==1 then gui=g break end end
    if not gui and gethui then local ok,h=pcall(gethui);if ok and h then for _,g in ipairs(h:GetChildren()) do if g:IsA("ScreenGui") and g.Name:find("PsicoRoubeUmOvo",1,true)==1 then gui=g break end end end end
    if not gui then return nil end
    local tab=findText(gui,"ESP INVENTÁRIO");if not tab then return nil end
    for _,d in ipairs(gui:GetDescendants()) do if d:IsA("ScrollingFrame") and d.Name=="InventoryESPPage" then return d end end
end
local function readCfg()
    local f={Enabled=false,MinRarity=0,MinEarnings=0,MinSellPrice=0,PetFilter="",MutationMode="Todas",ShowEarnings=true,ShowEggValue=false,ShowWeight=false}
    local page=getInventoryPage();if not page then return f end
    local function lab(t) return findText(page,t) end
    local b=siblingAtY(lab("Ativar ESP do inventário"),"TextButton");f.Enabled=b and b.Text=="ON" or false
    b=siblingAtY(lab("Raridade mínima"),"TextButton");if b and b.Text~="Todas" then for i,r in ipairs(RARITY_ORDER) do if r==b.Text then f.MinRarity=i break end end end
    local bx=siblingAtY(lab("Rendimento mínimo ($/s)"),"TextBox");if bx then f.MinEarnings=parseSmartNumber(bx.Text) end
    bx=siblingAtY(lab("Valor do ovo mín. ($)"),"TextBox");if bx then f.MinSellPrice=parseSmartNumber(bx.Text) end
    bx=siblingAtY(lab("Pet"),"TextBox");if bx then f.PetFilter=bx.Text or "" end
    b=siblingAtY(lab("Mutação"),"TextButton");if b then f.MutationMode=b.Text end
    local function tog(t,def) local x=siblingAtY(lab(t),"TextButton");if not x then return def end;return x.Text=="ON" end
    f.ShowEarnings=tog("Mostrar $/s do pet",true);f.ShowEggValue=tog("Mostrar valor do ovo",false);f.ShowWeight=tog("Mostrar peso",false)
    return f
end
local function mutationPass(egg,mode)
    local muts=egg.Mutations or {};if mode=="Todas" then return true end;if mode=="Com mutação" then return #muts>0 end;if mode=="Sem mutação" then return #muts==0 end
    local t=normalize(mode);for _,m in ipairs(muts) do if normalize(m)==t then return true end end;return false
end
local function passes(egg,f)
    if (tonumber(egg.RarityNumber) or 0)<f.MinRarity then return false end
    if f.MinEarnings>0 and (tonumber(egg.EarningsPerSecond) or 0)<f.MinEarnings then return false end
    if f.MinSellPrice>0 and (tonumber(egg.SellPrice) or 0)<f.MinSellPrice then return false end
    if f.PetFilter~="" then local t=normalize(f.PetFilter);if not normalize(egg.PetName or ""):find(t,1,true) and not normalize(egg.AssetCategory or ""):find(t,1,true) then return false end end
    return mutationPass(egg,f.MutationMode)
end
local function infoText(egg,f)
    local first=egg.Rarity or "?";if egg.Mutations and #egg.Mutations>0 then first=first.." • "..table.concat(egg.Mutations,"+") end
    local second={};if f.ShowEarnings then second[#second+1]=egg.EarningsPerSecond and ("$"..formatCompact(egg.EarningsPerSecond).."/s") or "$?/s" end;if f.ShowEggValue then second[#second+1]=egg.SellPrice and ("$"..formatCompact(egg.SellPrice)) or "$?" end;if f.ShowWeight then second[#second+1]=egg.WeightLabel or (egg.WeightKg and (formatCompact(egg.WeightKg).."kg") or "?kg") end
    return first,(#second>0 and table.concat(second," • ") or nil)
end

local function ensureOverlay()
    if overlayGui and overlayGui.Parent then return end
    overlayGui=Instance.new("ScreenGui");overlayGui.Name="PsicoInventoryHotbarESP";overlayGui.ResetOnSpawn=false;overlayGui.IgnoreGuiInset=true;overlayGui.DisplayOrder=1000000;overlayGui.ZIndexBehavior=Enum.ZIndexBehavior.Global;overlayGui.Parent=CoreGui
    overlayRoot=Instance.new("Frame");overlayRoot.BackgroundTransparency=1;overlayRoot.Size=UDim2.fromScale(1,1);overlayRoot.Parent=overlayGui
end
local function clearDrawn() for _,r in pairs(Drawn) do if r.Frame then pcall(function() r.Frame:Destroy() end) end end;Drawn={} end
local function draw(slot,egg,f)
    ensureOverlay();local p,s=slot.AbsolutePosition,slot.AbsoluteSize;if s.X<35 or s.Y<35 then return false end
    local r=Drawn[slot]
    if not r or not r.Frame.Parent then
        local frame=Instance.new("Frame");frame.BackgroundTransparency=1;frame.BorderSizePixel=0;frame.ZIndex=200;frame.Parent=overlayRoot
        local stroke=Instance.new("UIStroke");stroke.Thickness=2;stroke.Transparency=.05;stroke.Parent=frame
        local badge=Instance.new("TextLabel");badge.BackgroundColor3=Color3.fromRGB(5,8,15);badge.BackgroundTransparency=.12;badge.BorderSizePixel=0;badge.Font=Enum.Font.GothamBold;badge.TextScaled=true;badge.TextWrapped=true;badge.TextStrokeTransparency=.08;badge.TextStrokeColor3=Color3.new();badge.ZIndex=201;badge.Parent=frame;round(badge,4)
        r={Frame=frame,Stroke=stroke,Badge=badge};Drawn[slot]=r
    end
    local color=typeof(egg.RarityColor)=="Color3" and egg.RarityColor or rarityColor(egg.Rarity);r.Frame.Position=UDim2.fromOffset(p.X,p.Y);r.Frame.Size=UDim2.fromOffset(s.X,s.Y);r.Stroke.Color=color
    local a,b=infoText(egg,f);r.Badge.Text=b and (a.."\n"..b) or a;r.Badge.TextColor3=color
    local h=b and math.clamp(math.floor(s.Y*.34),24,40) or math.clamp(math.floor(s.Y*.22),18,28);r.Badge.Position=UDim2.new(0,3,1,-h-3);r.Badge.Size=UDim2.new(1,-6,0,h);r.Frame.Visible=true;return true
end
local function cleanName(t) return safeString(t or ""):gsub("%s*%[[Xx]%d+%]%s*$",""):gsub("^%s+",""):gsub("%s+$","") end
local function getHotbar()
    local rg=CoreGui:FindFirstChild("RobloxGui");local bp=rg and rg:FindFirstChild("Backpack");return bp and bp:FindFirstChild("Hotbar")
end
local function collectHotbarSlots(hotbar)
    local out={},seen={};if not hotbar then return out end
    for _,d in ipairs(hotbar:GetDescendants()) do
        if d:IsA("TextLabel") and d.Name=="ToolName" and d.Text~="" then
            local cur=d.Parent
            while cur and cur~=hotbar do
                if cur:IsA("GuiObject") and cur.AbsoluteSize.X>=45 and cur.AbsoluteSize.Y>=45 then
                    local parent=cur.Parent
                    if parent==hotbar or (parent and parent.Parent==hotbar) then if not seen[cur] then seen[cur]=true;out[#out+1]={Slot=cur,Label=d} end;break end
                end
                cur=cur.Parent
            end
        end
    end
    return out
end

local prevCleanup=_G.PSICO_INVENTORY_ESP_CLEANUP
local function cleanupAddon()
    if not Alive then return end;Alive=false;clearDrawn();if overlayGui then pcall(function() overlayGui:Destroy() end) end;for _,c in ipairs(Connections) do pcall(function() c:Disconnect() end) end
end
_G.PSICO_INVENTORY_ESP_CLEANUP=function()
    cleanupAddon();if prevCleanup then pcall(prevCleanup) end
end

if not resolveModules() then return end
buildCatalog()

-- Update visible version label from V5 to V6.
task.defer(function()
    task.wait(.4)
    for _,root in ipairs({CoreGui,(gethui and select(2,pcall(gethui)) or nil)}) do
        if root then for _,d in ipairs(root:GetDescendants()) do if d:IsA("TextLabel") and d.Text:find("V8.4.4",1,true)==1 then d.Text="V8.4.5 • INVENTORY ESP V6";return end end end
    end
end)

task.defer(function()
    while Alive do
        local f=readCfg()
        local hotbar=getHotbar()
        if f.Enabled and hotbar and hotbar.Visible then
            refreshInventory();local buckets=buildBuckets();local keep={}
            for _,pair in ipairs(collectHotbarSlots(hotbar)) do
                local slot,label=pair.Slot,pair.Label;local name=cleanName(label.Text);local cfg=findCatalog(name)
                if cfg then local egg=popBucket(buckets,cfg,name) or fallbackInfo(cfg,name);if egg and passes(egg,f) and draw(slot,egg,f) then keep[slot]=true end end
            end
            for slot in pairs(Drawn) do if not keep[slot] then local r=Drawn[slot];if r and r.Frame then pcall(function() r.Frame:Destroy() end) end;Drawn[slot]=nil end end
            task.wait(.15)
        else
            clearDrawn();task.wait(.4)
        end
    end
end)

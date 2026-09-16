--[[
PSICOSENATICO | Steal An Egg - Inventory Panel V2
Integrated inventory reader rendered inside PSICOSENATICO PANEL.
- independent filters
- robust scrolling (no 1-second full rebuild)
- mirrors egg image from matching Tool/Backpack slot when possible
- card tap can request hotbar placement and equip the matching Tool
]]

if _G.PSICO_INVENTORY_PANEL_ENHANCER_CLEANUP then pcall(_G.PSICO_INVENTORY_PANEL_ENHANCER_CLEANUP) end
if _G.PSICO_INVENTORY_PANEL_CLEANUP then pcall(_G.PSICO_INVENTORY_PANEL_CLEANUP) end
if _G.PSICO_INVENTORY_ESP_CLEANUP then pcall(_G.PSICO_INVENTORY_ESP_CLEANUP) end

local Players=game:GetService("Players")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local CoreGui=game:GetService("CoreGui")
local LP=Players.LocalPlayer

local State={Alive=true,Connections={},Cards={},LastCount=-1,ListStartY=0}
local CFG={
    Enabled=true,MinRarity=0,MinEarnings=0,MinSellPrice=0,PetFilter="",MutationMode="Todas",
    ShowEarnings=true,ShowEggValue=true,ShowWeight=true,ShowImage=true,
    AutoEquip=true,SendHotbar=true
}
local RARITY_ORDER={"Common","Uncommon","Rare","Epic","Legendary","Mythic","Cosmic","Secret","Eternal","Divine"}
local MUTATION_MODES={"Todas","Com mutação","Sem mutação","Silver","Golden","Rainbow","Sakura","Boss","Monstrous","GreatBloom","Fractured","Parasite","Bloom","SpiritBloom"}

local AssetsData,EggRecords,AssetEarnings,SaveMod
local CatalogIndex,CatalogEntries={},{}
local baseGui,mainFrame,mainPage,filterPage,contentHost,sidebar,tabMain,tabFilters,tabInv,invPage
local enabledButton,earningsBox,valueBox,petBox,statusText,listFrame,listLayout

local function safeString(v) local ok,s=pcall(tostring,v);return ok and s or "?" end
local function lower(v) return string.lower(safeString(v or "")) end
local function normalize(v) return lower(v):gsub("[%s_%-%.:/%[%]%(%)'•]","") end
local function finite(v) return type(v)=="number" and v==v and v~=math.huge and v~=-math.huge end
local function connect(sig,fn) local c=sig:Connect(fn);State.Connections[#State.Connections+1]=c;return c end
local function disconnect(c) pcall(function() c:Disconnect() end) end
local function uiParent() local ok,h=pcall(function() if gethui then return gethui() end end);return (ok and h) or CoreGui end
local function findPath(root,pathText) local cur=root;for token in string.gmatch(pathText,"[^%.]+") do if not cur then return nil end;cur=cur:FindFirstChild(token) end;return cur end
local function requireOptional(pathText) local m=findPath(ReplicatedStorage,pathText);if not (m and m:IsA("ModuleScript")) then return nil end;local ok,v=pcall(require,m);return ok and v or nil end
local function callTableFn(tbl,name,...) if typeof(tbl)~="table" or type(tbl[name])~="function" then return nil,false end;local fn=tbl[name];local ok,v=pcall(fn,...);if ok then return v,true end;ok,v=pcall(fn,tbl,...);return ok and v or nil,ok end
local function round(o,r) local c=Instance.new("UICorner");c.CornerRadius=UDim.new(0,r or 8);c.Parent=o;return c end
local function mkLabel(parent,text,pos,size,ts) local l=Instance.new("TextLabel");l.BackgroundTransparency=1;l.BorderSizePixel=0;l.Position=pos;l.Size=size;l.Font=Enum.Font.Gotham;l.Text=text;l.TextColor3=Color3.fromRGB(230,235,246);l.TextSize=ts or 9;l.TextXAlignment=Enum.TextXAlignment.Left;l.Parent=parent;return l end
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
    local suffix=s:match("([KMBT])$");if suffix then s=s:sub(1,-2) end
    s=s:gsub(",",".")
    local n=tonumber(s) or 0;local mult={K=1e3,M=1e6,B=1e9,T=1e12}
    if suffix then n=n*(mult[suffix] or 1) end
    return finite(n) and math.max(0,n) or 0
end

local function rarityColor(r)
    local m={Common=Color3.fromRGB(210,210,210),Uncommon=Color3.fromRGB(91,210,116),Rare=Color3.fromRGB(77,151,255),Epic=Color3.fromRGB(181,91,255),Legendary=Color3.fromRGB(255,174,58),Mythic=Color3.fromRGB(255,71,121),Cosmic=Color3.fromRGB(150,67,255),Secret=Color3.fromRGB(245,245,245),Eternal=Color3.fromRGB(245,71,255),Divine=Color3.fromRGB(52,255,238)}
    return m[r] or Color3.fromRGB(230,235,255)
end

local function imageLike(v,key)
    local kn=normalize(key or "")
    if not (kn:find("image",1,true) or kn:find("icon",1,true) or kn:find("thumb",1,true) or kn:find("texture",1,true)) then return nil end
    if type(v)=="string" then
        if v:match("^rbxassetid://%d+") or v:match("^rbxthumb://") or v:match("^https?://") then return v end
        if v:match("^%d+$") then return "rbxassetid://"..v end
    elseif type(v)=="number" and v>1000 then return "rbxassetid://"..tostring(math.floor(v)) end
end

local function findImageInTable(t,depth,seen)
    if typeof(t)~="table" or depth>4 then return nil end
    seen=seen or {};if seen[t] then return nil end;seen[t]=true
    for k,v in pairs(t) do local img=imageLike(v,k);if img then return img end end
    for _,v in pairs(t) do if typeof(v)=="table" then local img=findImageInTable(v,depth+1,seen);if img then return img end end end
end

local function resolveModules()
    AssetsData=requireOptional("Data.Assets")
    EggRecords=requireOptional("Shared.Util.EggRecords")
    AssetEarnings=requireOptional("Shared.Util.AssetEarnings")
    SaveMod=requireOptional("Shared.Save") or requireOptional("Data.Save")
    return typeof(AssetsData)=="table" and typeof(SaveMod)=="table"
end

local function indexEntry(key,cfg)
    if typeof(cfg)~="table" or typeof(cfg.Rarity)~="table" then return end
    local e={
        Key=safeString(key),PetName=cfg.DisplayName or safeString(key),
        Rarity=cfg.Rarity.DisplayName or cfg.Rarity._id,RarityNumber=cfg.Rarity.RarityNumber,
        RarityColor=cfg.Rarity.Color,EarningRate=tonumber(cfg.EarningRate),
        EggDisplayName=typeof(cfg.Egg)=="table" and cfg.Egg.DisplayName or nil,
        Image=findImageInTable(cfg,0,{})
    }
    for _,name in ipairs({e.Key,e.PetName,e.EggDisplayName}) do
        if type(name)=="string" and name~="" then CatalogIndex[normalize(name)]=e end
    end
    CatalogEntries[#CatalogEntries+1]=e
end

local function buildCatalog()
    CatalogIndex,CatalogEntries={},{}
    if typeof(AssetsData.ByRarity)=="table" then for _,group in pairs(AssetsData.ByRarity) do if typeof(group)=="table" then for k,cfg in pairs(group) do indexEntry(k,cfg) end end end end
    if #CatalogEntries==0 and typeof(AssetsData.Configs)=="table" then for k,cfg in pairs(AssetsData.Configs) do indexEntry(k,cfg) end end
end

local function findCatalog(name)
    if type(name)~="string" then return nil end
    local n=normalize(name);local exact=CatalogIndex[n];if exact then return exact end
    if #n<4 or n=="ovo" or n=="egg" then return nil end
    local best,bestScore=nil,0
    for _,e in ipairs(CatalogEntries) do
        for _,cand in ipairs({e.PetName,e.Key,e.EggDisplayName}) do
            local c=normalize(cand or "")
            if c~="" then local score=(c==n and 100) or ((c:find(n,1,true) or n:find(c,1,true)) and math.min(#c,#n) or 0);if score>bestScore then best,bestScore=e,score end end
        end
    end
    return bestScore>=4 and best or nil
end

local function copyMutations(record)
    local out,seen={},{};if typeof(record)~="table" then return out end
    local item=typeof(record.ItemData)=="table" and record.ItemData or nil;local src=record.Mutations or (item and item.Mutations)
    local function add(v) if v==nil then return end;local s=safeString(v);local k=normalize(s);if k~="" and not seen[k] then seen[k]=true;out[#out+1]=s end end
    if typeof(src)=="table" then for _,m in pairs(src) do add(m) end end
    add(record.BaseMutation or (item and item.BaseMutation));if record.HasParasite==true or (item and item.HasParasite==true) then add("Parasite") end
    table.sort(out);return out
end

local function recordCategory(record)
    if typeof(record)~="table" then return nil end
    local item=typeof(record.ItemData)=="table" and record.ItemData or nil
    return record.AssetCategory or record.Category or record.Name or (item and (item.AssetCategory or item.Category or item.Name))
end

local function calcEarnings(record,cfg)
    if typeof(record)~="table" then return cfg and cfg.EarningRate or nil end
    if typeof(AssetEarnings)=="table" and type(AssetEarnings.MutationOnlyRatePerSecond)=="function" then
        local probe={};for k,v in pairs(record) do probe[k]=v end
        if typeof(record.ItemData)=="table" then for k,v in pairs(record.ItemData) do if probe[k]==nil then probe[k]=v end end end
        probe.Scale=probe.Scale or probe.AssetScale;probe.Category=probe.Category or probe.AssetCategory;probe.ItemType=probe.ItemType or "Asset"
        local v,ok=callTableFn(AssetEarnings,"MutationOnlyRatePerSecond",probe);v=tonumber(v);if ok and finite(v) then return math.floor(v+0.5) end
    end
    return cfg and cfg.EarningRate or nil
end

local function makeInfo(record,key)
    local cat=recordCategory(record);if type(cat)~="string" or cat=="" then return nil end
    local cfg=findCatalog(cat);local weight,weightLabel,sell
    if typeof(EggRecords)=="table" then
        local v,ok=callTableFn(EggRecords,"WeightKg",record);if ok and finite(tonumber(v)) then weight=tonumber(v) end
        v,ok=callTableFn(EggRecords,"WeightLabel",record);if ok then weightLabel=safeString(v) end
        v,ok=callTableFn(EggRecords,"SellPrice",record);if ok and finite(tonumber(v)) then sell=tonumber(v) end
    end
    return {
        Key=safeString(key),Record=record,AssetCategory=cat,PetName=cfg and cfg.PetName or cat,
        Rarity=cfg and cfg.Rarity or record.Rarity,RarityNumber=cfg and cfg.RarityNumber or tonumber(record.RarityNumber),
        RarityColor=cfg and cfg.RarityColor or nil,EarningsPerSecond=calcEarnings(record,cfg),SellPrice=sell,
        WeightKg=weight,WeightLabel=weightLabel,Mutations=copyMutations(record),FallbackImage=cfg and cfg.Image or nil
    }
end

local function readInventory()
    local out={};if not (SaveMod and type(SaveMod.Get)=="function") then return out end
    local ok,sd=pcall(SaveMod.Get);if not ok or typeof(sd)~="table" or typeof(sd.EggInventory)~="table" then return out end
    for key,record in pairs(sd.EggInventory) do local info=makeInfo(record,key);if info then out[#out+1]=info end end
    table.sort(out,function(a,b)
        local ar,br=tonumber(a.RarityNumber) or 0,tonumber(b.RarityNumber) or 0;if ar~=br then return ar>br end
        local ae,be=tonumber(a.EarningsPerSecond) or 0,tonumber(b.EarningsPerSecond) or 0;if ae~=be then return ae>be end
        return safeString(a.PetName)<safeString(b.PetName)
    end)
    return out
end

local function mutationPass(egg)
    local mode=CFG.MutationMode;local muts=egg.Mutations or {}
    if mode=="Todas" then return true end;if mode=="Com mutação" then return #muts>0 end;if mode=="Sem mutação" then return #muts==0 end
    local t=normalize(mode);for _,m in ipairs(muts) do if normalize(m)==t then return true end end;return false
end

local function passes(egg)
    if (tonumber(egg.RarityNumber) or 0)<CFG.MinRarity then return false end
    if CFG.MinEarnings>0 and (tonumber(egg.EarningsPerSecond) or 0)<CFG.MinEarnings then return false end
    if CFG.MinSellPrice>0 and (tonumber(egg.SellPrice) or 0)<CFG.MinSellPrice then return false end
    if CFG.PetFilter~="" then local t=normalize(CFG.PetFilter);if not normalize(egg.PetName or ""):find(t,1,true) and not normalize(egg.AssetCategory or ""):find(t,1,true) then return false end end
    return mutationPass(egg)
end

local function weightToken(v)
    local s=safeString(v or "");local body=s:match("([%d%.,]+)%s*[Kk][Gg]") or s:match("%(([%d%.,]+)%)")
    return body and body:gsub("%D","") or nil
end

local function allTools()
    local out={}
    for _,root in ipairs({LP:FindFirstChildOfClass("Backpack"),LP.Character}) do if root then for _,c in ipairs(root:GetChildren()) do if c:IsA("Tool") then out[#out+1]=c end end end end
    return out
end

local function toolScore(tool,egg)
    local score=0;local key=normalize(egg.Key);local cat=normalize(egg.AssetCategory);local pet=normalize(egg.PetName);local wt=weightToken(egg.WeightLabel)
    local function test(v,mult)
        if v==nil then return end;local s=normalize(v);if s=="" then return end
        if key~="" and s==key then score=score+1000*mult end
        if cat~="" and (s==cat or s:find(cat,1,true) or cat:find(s,1,true)) then score=score+180*mult end
        if pet~="" and (s==pet or s:find(pet,1,true) or pet:find(s,1,true)) then score=score+160*mult end
        if wt and weightToken(v)==wt then score=score+220*mult end
    end
    test(tool.Name,1);test(tool.ToolTip,1)
    for k,v in pairs(tool:GetAttributes()) do test(k,.1);test(v,1.5) end
    local n=0;for _,d in ipairs(tool:GetDescendants()) do if d:IsA("StringValue") then test(d.Value,1.25);n=n+1;if n>20 then break end end end
    return score
end

local function matchTool(egg,used)
    local best,bestScore=nil,0
    for _,tool in ipairs(allTools()) do if not used[tool] then local s=toolScore(tool,egg);if s>bestScore then best,bestScore=tool,s end end end
    if best and bestScore>0 then used[best]=true;return best end
end

local function backpackRoot() local rg=CoreGui:FindFirstChild("RobloxGui");return rg and rg:FindFirstChild("Backpack") end
local function collectSlots()
    local root=backpackRoot();local out={},seen={};if not root then return out end
    for _,d in ipairs(root:GetDescendants()) do
        if d:IsA("GuiButton") and not seen[d] then
            local nameLabel=d:FindFirstChild("ToolName",true);local imgObj
            for _,x in ipairs(d:GetDescendants()) do if x:IsA("ImageLabel") and type(x.Image)=="string" and x.Image~="" then imgObj=x;break end end
            if nameLabel and nameLabel:IsA("TextLabel") then seen[d]=true;out[#out+1]={Button=d,Label=nameLabel,ImageObject=imgObj,Image=imgObj and imgObj.Image or "",Path=d:GetFullName()} end
        end
    end
    return out
end

local function slotScore(slot,egg,tool)
    local score=0;local text=slot.Label and slot.Label.Text or "";local nt=normalize(text);local wt=weightToken(egg.WeightLabel);local sw=weightToken(text)
    if wt and sw and wt==sw then score=score+500 end
    local cat,pet=normalize(egg.AssetCategory),normalize(egg.PetName)
    if cat~="" and (nt:find(cat,1,true) or cat:find(nt,1,true)) then score=score+170 end
    if pet~="" and (nt:find(pet,1,true) or pet:find(nt,1,true)) then score=score+160 end
    if tool then local tex=tool.TextureId or "";if tex~="" and slot.Image==tex then score=score+350 end end
    return score
end

local function matchSlot(egg,tool,slots,used)
    local best,bestScore=nil,0
    for _,slot in ipairs(slots) do if not used[slot.Button] then local s=slotScore(slot,egg,tool);if s>bestScore then best,bestScore=slot,s end end end
    if best and bestScore>0 then used[best.Button]=true;return best end
end

local function fireSlot(slot)
    if not (slot and slot.Button and slot.Button.Parent) then return false end
    if firesignal then
        local ok=pcall(function() firesignal(slot.Button.MouseButton1Click) end)
        if ok then return true end
    end
    return false
end

local function equipEgg(egg,tool,slot)
    if not State.Alive then return end
    statusText.Text="Ação: selecionando "..safeString(egg.PetName)
    local hotbarOk=false
    if CFG.SendHotbar then hotbarOk=fireSlot(slot);if hotbarOk then task.wait(.1) end end
    if CFG.AutoEquip then
        if not tool or not tool.Parent then local used={};tool=matchTool(egg,used) end
        local char=LP.Character;local hum=char and char:FindFirstChildOfClass("Humanoid")
        if tool and hum then
            if tool.Parent~=char then pcall(function() hum:UnequipTools();hum:EquipTool(tool) end) end
            task.wait(.05)
            if tool.Parent==char then statusText.Text="Ação: segurando "..safeString(egg.PetName)..(hotbarOk and " • hotbar solicitada" or "");return end
        end
    end
    if hotbarOk then statusText.Text="Ação: envio à hotbar solicitado" else statusText.Text="Ação: Tool/slot correspondente não localizado" end
end

local function findTextDesc(root,text)
    if not root then return nil end
    for _,d in ipairs(root:GetDescendants()) do if (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Text==text then return d end end
end
local function findBaseGui() for _,child in ipairs(uiParent():GetChildren()) do if child:IsA("ScreenGui") and child.Name:find("PsicoRoubeUmOvo",1,true)==1 and child:FindFirstChild("Main") then return child,child.Main end end end
local function locateBaseUi()
    tabMain=findTextDesc(mainFrame,"FUNÇÕES");tabFilters=findTextDesc(mainFrame,"FILTROS ESP")
    local normal=findTextDesc(mainFrame,"ESP • Ovos  ON") or findTextDesc(mainFrame,"ESP • Ovos  OFF") or findTextDesc(mainFrame,"ESP • Ovos")
    local rarity=findTextDesc(mainFrame,"Raridade mínima")
    mainPage=normal and normal.Parent or nil;filterPage=rarity and rarity.Parent or nil;contentHost=mainPage and mainPage.Parent or (filterPage and filterPage.Parent);sidebar=tabFilters and tabFilters.Parent or nil
    return tabMain and tabFilters and mainPage and filterPage and contentHost and sidebar
end

local function clearCards() for _,c in ipairs(State.Cards) do if c and c.Parent then pcall(function() c:Destroy() end) end end;State.Cards={} end
local function cardText(egg)
    local details={}
    if CFG.ShowEarnings then details[#details+1]=egg.EarningsPerSecond and ("$"..formatCompact(egg.EarningsPerSecond).."/s") or "$?/s" end
    if CFG.ShowEggValue then details[#details+1]=egg.SellPrice and ("Ovo $"..formatCompact(egg.SellPrice)) or "Ovo $?" end
    if CFG.ShowWeight then details[#details+1]=egg.WeightLabel or (egg.WeightKg and (formatCompact(egg.WeightKg).."kg") or "?kg") end
    if egg.Mutations and #egg.Mutations>0 then details[#details+1]=table.concat(egg.Mutations,"+") end
    return table.concat(details," • ")
end

local function updateCanvas()
    if not (invPage and listFrame and listLayout) then return end
    local content=listLayout.AbsoluteContentSize.Y
    listFrame.Size=UDim2.new(1,-4,0,content)
    local bottom=State.ListStartY+content+18
    invPage.CanvasSize=UDim2.fromOffset(0,math.max(bottom,invPage.AbsoluteSize.Y+1))
end

local function deriveImage(egg,tool,slot)
    local tex=(tool and tool.TextureId and tool.TextureId~="" and tool.TextureId) or (slot and slot.Image) or egg.FallbackImage
    return tex,slot and slot.ImageObject or nil
end

local function renderInventory()
    if not State.Alive or not listFrame then return end
    local oldPos=invPage.CanvasPosition
    clearCards()
    if not CFG.Enabled then statusText.Text="Leitura do inventário desligada";updateCanvas();return end
    local all=readInventory();State.LastCount=#all
    local usedTools,usedSlots={},{};local slots=collectSlots();local shown=0
    for _,egg in ipairs(all) do
        if passes(egg) then
            shown=shown+1
            local tool=matchTool(egg,usedTools);local slot=matchSlot(egg,tool,slots,usedSlots)
            local color=typeof(egg.RarityColor)=="Color3" and egg.RarityColor or rarityColor(egg.Rarity)
            local card=Instance.new("TextButton");card.Name="EggInventoryCard";card.BackgroundColor3=Color3.fromRGB(24,33,49);card.BorderSizePixel=0;card.Size=UDim2.new(1,-4,0,72);card.Text="";card.AutoButtonColor=true;card.Parent=listFrame;round(card,8)
            local stroke=Instance.new("UIStroke");stroke.Thickness=1.4;stroke.Transparency=.12;stroke.Color=color;stroke.Parent=card
            local x0=8
            if CFG.ShowImage then
                local image=Instance.new("ImageLabel");image.Name="EggImage";image.BackgroundColor3=Color3.fromRGB(13,19,30);image.BackgroundTransparency=.1;image.BorderSizePixel=0;image.Position=UDim2.fromOffset(7,7);image.Size=UDim2.fromOffset(56,56);image.ScaleType=Enum.ScaleType.Fit;image.Parent=card;round(image,7)
                local tex,imgObj=deriveImage(egg,tool,slot);if tex and tex~="" then image.Image=tex end
                if imgObj then pcall(function() image.ImageRectOffset=imgObj.ImageRectOffset;image.ImageRectSize=imgObj.ImageRectSize;image.ImageColor3=imgObj.ImageColor3 end) end
                x0=71
            end
            local title=mkLabel(card,(egg.PetName or egg.AssetCategory or "Ovo").."  •  "..(egg.Rarity or "?"),UDim2.fromOffset(x0,8),UDim2.new(1,-x0-84,0,21),10);title.Font=Enum.Font.GothamBold;title.TextColor3=color
            local details=mkLabel(card,cardText(egg),UDim2.fromOffset(x0,33),UDim2.new(1,-x0-12,0,24),8);details.TextColor3=Color3.fromRGB(205,217,238);details.TextWrapped=true
            local hint=mkLabel(card,"SEGURAR",UDim2.new(1,-78,0,8),UDim2.fromOffset(68,18),7);hint.Font=Enum.Font.GothamBold;hint.TextColor3=Color3.fromRGB(126,166,235);hint.TextXAlignment=Enum.TextXAlignment.Right
            connect(card.MouseButton1Click,function() task.spawn(equipEgg,egg,tool,slot) end)
            State.Cards[#State.Cards+1]=card
        end
    end
    statusText.Text=string.format("Inventário:%d • Exibidos:%d • Toque em um ovo para selecionar",#all,shown)
    task.defer(function() if State.Alive then updateCanvas();task.wait();local maxY=math.max(0,invPage.CanvasSize.Y.Offset-invPage.AbsoluteSize.Y);invPage.CanvasPosition=Vector2.new(0,math.min(oldPos.Y,maxY)) end end)
end

local function setEnabledVisual() if enabledButton then enabledButton.Text=CFG.Enabled and "ON" or "OFF";enabledButton.BackgroundColor3=CFG.Enabled and Color3.fromRGB(42,91,190) or Color3.fromRGB(35,44,61) end end
local function makeCycleButton(parent,labelText,y,values,getter,setter)
    mkLabel(parent,labelText,UDim2.fromOffset(0,y),UDim2.new(.45,0,0,28),9);local b=mkButton(parent,getter(),UDim2.new(.47,0,0,y),UDim2.new(.53,-4,0,28))
    connect(b.MouseButton1Click,function() local cur=getter();local idx=1;for i,v in ipairs(values) do if v==cur then idx=i break end end;idx=idx%#values+1;setter(values[idx]);b.Text=getter();renderInventory() end);return b
end
local function makeInlineToggle(parent,text,y,key,rerender)
    mkLabel(parent,text,UDim2.fromOffset(0,y),UDim2.new(.72,0,0,26),9);local b=mkButton(parent,CFG[key] and "ON" or "OFF",UDim2.new(.74,0,0,y),UDim2.new(.26,-4,0,26))
    connect(b.MouseButton1Click,function() CFG[key]=not CFG[key];b.Text=CFG[key] and "ON" or "OFF";if rerender~=false then renderInventory() end end);return b
end

local function buildPage()
    tabInv=mkButton(sidebar,"OVOS INVENTÁRIO",UDim2.fromOffset(0,100),UDim2.new(1,0,0,42))
    invPage=Instance.new("ScrollingFrame");invPage.Name="InventoryEggPanel";invPage.BackgroundTransparency=1;invPage.BorderSizePixel=0;invPage.Position=UDim2.fromOffset(8,8);invPage.Size=UDim2.new(1,-16,1,-16);invPage.CanvasSize=UDim2.new();invPage.ScrollBarThickness=4;invPage.ScrollBarImageColor3=Color3.fromRGB(94,139,223);invPage.ScrollingDirection=Enum.ScrollingDirection.Y;invPage.Visible=false;invPage.Parent=contentHost
    pcall(function() invPage.ElasticBehavior=Enum.ElasticBehavior.WhenScrollable end)
    local y=0
    mkLabel(invPage,"Ativar leitura do inventário",UDim2.fromOffset(0,y),UDim2.new(.45,0,0,30),9);enabledButton=mkButton(invPage,"ON",UDim2.new(.47,0,0,y),UDim2.new(.53,-4,0,30));y=y+36;setEnabledVisual();connect(enabledButton.MouseButton1Click,function() CFG.Enabled=not CFG.Enabled;setEnabledVisual();renderInventory() end)
    local rarityValues={"Todas"};for _,r in ipairs(RARITY_ORDER) do rarityValues[#rarityValues+1]=r end
    makeCycleButton(invPage,"Raridade mínima",y,rarityValues,function() return CFG.MinRarity==0 and "Todas" or RARITY_ORDER[CFG.MinRarity] end,function(v) CFG.MinRarity=0;for i,r in ipairs(RARITY_ORDER) do if r==v then CFG.MinRarity=i break end end end);y=y+34
    mkLabel(invPage,"Rendimento mínimo ($/s)",UDim2.fromOffset(0,y),UDim2.new(.45,0,0,28),9);earningsBox=mkBox(invPage,"Ex: 2M",UDim2.new(.47,0,0,y),UDim2.new(.53,-4,0,28));y=y+34
    mkLabel(invPage,"Valor do ovo mín. ($)",UDim2.fromOffset(0,y),UDim2.new(.45,0,0,28),9);valueBox=mkBox(invPage,"Opcional",UDim2.new(.47,0,0,y),UDim2.new(.53,-4,0,28));y=y+34
    mkLabel(invPage,"Pet",UDim2.fromOffset(0,y),UDim2.new(.45,0,0,28),9);petBox=mkBox(invPage,"Todos / nome",UDim2.new(.47,0,0,y),UDim2.new(.53,-4,0,28));y=y+34
    makeCycleButton(invPage,"Mutação",y,MUTATION_MODES,function() return CFG.MutationMode end,function(v) CFG.MutationMode=v end);y=y+38
    makeInlineToggle(invPage,"Mostrar imagem do ovo",y,"ShowImage");y=y+30
    makeInlineToggle(invPage,"Mostrar $/s do pet",y,"ShowEarnings");y=y+30
    makeInlineToggle(invPage,"Mostrar valor do ovo",y,"ShowEggValue");y=y+30
    makeInlineToggle(invPage,"Mostrar peso",y,"ShowWeight");y=y+30
    makeInlineToggle(invPage,"Ao tocar: segurar ovo",y,"AutoEquip",false);y=y+30
    makeInlineToggle(invPage,"Ao tocar: enviar à hotbar",y,"SendHotbar",false);y=y+34
    local refreshButton=mkButton(invPage,"Atualizar inventário",UDim2.fromOffset(0,y),UDim2.new(1,-4,0,30));y=y+36
    statusText=mkLabel(invPage,"Inventário:0 • Exibidos:0",UDim2.fromOffset(0,y),UDim2.new(1,-4,0,22),8);statusText.TextXAlignment=Enum.TextXAlignment.Center;statusText.TextColor3=Color3.fromRGB(139,164,207);y=y+28
    State.ListStartY=y
    listFrame=Instance.new("Frame");listFrame.Name="InventoryEggList";listFrame.BackgroundTransparency=1;listFrame.Position=UDim2.fromOffset(0,y);listFrame.Size=UDim2.new(1,-4,0,0);listFrame.Parent=invPage
    listLayout=Instance.new("UIListLayout");listLayout.Padding=UDim.new(0,4);listLayout.SortOrder=Enum.SortOrder.LayoutOrder;listLayout.Parent=listFrame
    connect(listLayout:GetPropertyChangedSignal("AbsoluteContentSize"),function() task.defer(updateCanvas) end)
    local function syncInputs() CFG.MinEarnings=parseSmartNumber(earningsBox.Text);CFG.MinSellPrice=parseSmartNumber(valueBox.Text);CFG.PetFilter=petBox.Text or "";renderInventory() end
    connect(earningsBox.FocusLost,syncInputs);connect(valueBox.FocusLost,syncInputs);connect(petBox.FocusLost,syncInputs);connect(refreshButton.MouseButton1Click,renderInventory)
    local function hideInventoryPage() invPage.Visible=false;tabInv.BackgroundColor3=Color3.fromRGB(35,44,61) end
    connect(tabMain.MouseButton1Click,hideInventoryPage);connect(tabFilters.MouseButton1Click,hideInventoryPage)
    connect(tabInv.MouseButton1Click,function() mainPage.Visible=false;filterPage.Visible=false;invPage.Visible=true;tabMain.BackgroundColor3=Color3.fromRGB(35,44,61);tabFilters.BackgroundColor3=Color3.fromRGB(35,44,61);tabInv.BackgroundColor3=Color3.fromRGB(42,91,190);renderInventory() end)
end

local function updateVersion()
    for _,d in ipairs(mainFrame:GetDescendants()) do if d:IsA("TextLabel") and d.Text:find("V8.3",1,true)==1 then d.Text="V8.7 • INVENTORY V2";return end end
end
local function cleanup()
    if not State.Alive then return end;State.Alive=false;clearCards();if invPage then pcall(function() invPage:Destroy() end) end;if tabInv then pcall(function() tabInv:Destroy() end) end;for _,c in ipairs(State.Connections) do disconnect(c) end;_G.PSICO_INVENTORY_PANEL_CLEANUP=nil
end
_G.PSICO_INVENTORY_PANEL_CLEANUP=cleanup

local deadline=os.clock()+8
repeat baseGui,mainFrame=findBaseGui();if baseGui and mainFrame then break end;task.wait(.1) until os.clock()>=deadline or not State.Alive
if not (baseGui and mainFrame) then cleanup();return end
if not locateBaseUi() then warn("[PSICO Inventory Panel V2] base UI não localizada");cleanup();return end
if not resolveModules() then warn("[PSICO Inventory Panel V2] módulos do inventário indisponíveis");cleanup();return end
buildCatalog();buildPage();updateVersion();connect(baseGui.AncestryChanged,function(_,p) if p==nil then cleanup() end end)

-- Lightweight count watcher: no continuous full rebuild while the user scrolls.
task.defer(function()
    while State.Alive do
        if invPage and invPage.Visible and CFG.Enabled then
            local all=readInventory();if State.LastCount>=0 and #all~=State.LastCount then renderInventory() end
            task.wait(2.5)
        else task.wait(.7) end
    end
end)

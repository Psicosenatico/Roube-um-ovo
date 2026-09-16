--[[
PSICOSENATICO | Steal An Egg - Inventory Egg Panel V1
Independent inventory reader rendered inside PSICOSENATICO PANEL.
Does not depend on Roblox Backpack/Hotbar UI.
]]

if _G.PSICO_INVENTORY_ESP_CLEANUP then pcall(_G.PSICO_INVENTORY_ESP_CLEANUP) end
if _G.PSICO_INVENTORY_PANEL_CLEANUP then pcall(_G.PSICO_INVENTORY_PANEL_CLEANUP) end

local ReplicatedStorage=game:GetService("ReplicatedStorage")
local CoreGui=game:GetService("CoreGui")

local State={Alive=true,Connections={},Cards={}}
local CFG={Enabled=true,MinRarity=0,MinEarnings=0,MinSellPrice=0,PetFilter="",MutationMode="Todas",ShowEarnings=true,ShowEggValue=true,ShowWeight=true}
local RARITY_ORDER={"Common","Uncommon","Rare","Epic","Legendary","Mythic","Cosmic","Secret","Eternal","Divine"}
local MUTATION_MODES={"Todas","Com mutação","Sem mutação","Silver","Golden","Rainbow","Sakura","Boss","Monstrous","GreatBloom","Fractured","Parasite","Bloom","SpiritBloom"}

local AssetsData,EggRecords,AssetEarnings,SaveMod
local CatalogIndex,CatalogEntries={},{}
local baseGui,mainFrame,mainPage,filterPage,contentHost,sidebar,tabMain,tabFilters,tabInv,invPage
local enabledButton,earningsBox,valueBox,petBox,statusText,listFrame

local function safeString(v) local ok,s=pcall(tostring,v);return ok and s or "?" end
local function lower(v) return string.lower(safeString(v or "")) end
local function normalize(v) return lower(v):gsub("[%s_%-%.:/%[%]%(%)']","") end
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
    local n=tonumber(s) or 0
    local mult={K=1e3,M=1e6,B=1e9,T=1e12}
    if suffix then n=n*(mult[suffix] or 1) end
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
    return typeof(AssetsData)=="table" and typeof(SaveMod)=="table"
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
    CatalogIndex,CatalogEntries={},{}
    if typeof(AssetsData.ByRarity)=="table" then
        for _,group in pairs(AssetsData.ByRarity) do if typeof(group)=="table" then for k,cfg in pairs(group) do indexEntry(k,cfg) end end end
    end
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
    local out,seen={},{}
    if typeof(record)~="table" then return out end
    local item=typeof(record.ItemData)=="table" and record.ItemData or nil;local src=record.Mutations or (item and item.Mutations)
    local function add(v) if v==nil then return end;local s=safeString(v);local k=normalize(s);if k~="" and not seen[k] then seen[k]=true;out[#out+1]=s end end
    if typeof(src)=="table" then for _,m in pairs(src) do add(m) end end
    add(record.BaseMutation or (item and item.BaseMutation))
    if record.HasParasite==true or (item and item.HasParasite==true) then add("Parasite") end
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
    return {Key=safeString(key),AssetCategory=cat,PetName=cfg and cfg.PetName or cat,Rarity=cfg and cfg.Rarity or record.Rarity,RarityNumber=cfg and cfg.RarityNumber or tonumber(record.RarityNumber),RarityColor=cfg and cfg.RarityColor or nil,EarningsPerSecond=calcEarnings(record,cfg),SellPrice=sell,WeightKg=weight,WeightLabel=weightLabel,Mutations=copyMutations(record)}
end

local function readInventory()
    local out={}
    if not (SaveMod and type(SaveMod.Get)=="function") then return out end
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

local function findTextDesc(root,text)
    if not root then return nil end
    for _,d in ipairs(root:GetDescendants()) do if (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Text==text then return d end end
end

local function findBaseGui()
    for _,child in ipairs(uiParent():GetChildren()) do if child:IsA("ScreenGui") and child.Name:find("PsicoRoubeUmOvo",1,true)==1 and child:FindFirstChild("Main") then return child,child.Main end end
end

local function locateBaseUi()
    tabMain=findTextDesc(mainFrame,"FUNÇÕES");tabFilters=findTextDesc(mainFrame,"FILTROS ESP")
    local normal=findTextDesc(mainFrame,"ESP • Ovos  ON") or findTextDesc(mainFrame,"ESP • Ovos  OFF") or findTextDesc(mainFrame,"ESP • Ovos")
    local rarity=findTextDesc(mainFrame,"Raridade mínima")
    mainPage=normal and normal.Parent or nil;filterPage=rarity and rarity.Parent or nil;contentHost=mainPage and mainPage.Parent or (filterPage and filterPage.Parent);sidebar=tabFilters and tabFilters.Parent or nil
    return tabMain and tabFilters and mainPage and filterPage and contentHost and sidebar
end

local function clearCards()
    for _,c in ipairs(State.Cards) do if c and c.Parent then pcall(function() c:Destroy() end) end end;State.Cards={}
end

local function cardText(egg)
    local details={}
    if CFG.ShowEarnings then details[#details+1]=egg.EarningsPerSecond and ("$"..formatCompact(egg.EarningsPerSecond).."/s") or "$?/s" end
    if CFG.ShowEggValue then details[#details+1]=egg.SellPrice and ("Ovo $"..formatCompact(egg.SellPrice)) or "Ovo $?" end
    if CFG.ShowWeight then details[#details+1]=egg.WeightLabel or (egg.WeightKg and (formatCompact(egg.WeightKg).."kg") or "?kg") end
    if egg.Mutations and #egg.Mutations>0 then details[#details+1]=table.concat(egg.Mutations,"+") end
    return table.concat(details," • ")
end

local function renderInventory()
    if not State.Alive or not listFrame then return end
    clearCards()
    if not CFG.Enabled then statusText.Text="Leitura do inventário desligada";invPage.CanvasSize=UDim2.fromOffset(0,230);return end
    local all=readInventory();local shown=0
    for _,egg in ipairs(all) do
        if passes(egg) then
            shown=shown+1
            local card=Instance.new("Frame");card.Name="EggInventoryCard";card.BackgroundColor3=Color3.fromRGB(24,33,49);card.BorderSizePixel=0;card.Size=UDim2.new(1,-4,0,48);card.Parent=listFrame;round(card,8)
            local color=typeof(egg.RarityColor)=="Color3" and egg.RarityColor or rarityColor(egg.Rarity)
            local stroke=Instance.new("UIStroke");stroke.Thickness=1.4;stroke.Transparency=.12;stroke.Color=color;stroke.Parent=card
            local title=mkLabel(card,(egg.PetName or egg.AssetCategory or "Ovo").."  •  "..(egg.Rarity or "?"),UDim2.fromOffset(8,4),UDim2.new(1,-16,0,19),10);title.Font=Enum.Font.GothamBold;title.TextColor3=color
            local details=mkLabel(card,cardText(egg),UDim2.fromOffset(8,23),UDim2.new(1,-16,0,19),8);details.TextColor3=Color3.fromRGB(205,217,238)
            State.Cards[#State.Cards+1]=card
        end
    end
    statusText.Text=string.format("Inventário:%d • Exibidos:%d",#all,shown)
    local contentH=math.max(0,shown*52);listFrame.Size=UDim2.new(1,-4,0,contentH);invPage.CanvasSize=UDim2.fromOffset(0,225+contentH)
end

local function setEnabledVisual()
    if enabledButton then enabledButton.Text=CFG.Enabled and "ON" or "OFF";enabledButton.BackgroundColor3=CFG.Enabled and Color3.fromRGB(42,91,190) or Color3.fromRGB(35,44,61) end
end

local function makeCycleButton(parent,labelText,y,values,getter,setter)
    mkLabel(parent,labelText,UDim2.fromOffset(0,y),UDim2.new(.45,0,0,28),9)
    local b=mkButton(parent,getter(),UDim2.new(.47,0,0,y),UDim2.new(.53,-4,0,28))
    connect(b.MouseButton1Click,function() local cur=getter();local idx=1;for i,v in ipairs(values) do if v==cur then idx=i break end end;idx=idx%#values+1;setter(values[idx]);b.Text=getter();renderInventory() end)
    return b
end

local function makeInlineToggle(parent,text,y,key)
    mkLabel(parent,text,UDim2.fromOffset(0,y),UDim2.new(.72,0,0,26),9)
    local b=mkButton(parent,CFG[key] and "ON" or "OFF",UDim2.new(.74,0,0,y),UDim2.new(.26,-4,0,26))
    connect(b.MouseButton1Click,function() CFG[key]=not CFG[key];b.Text=CFG[key] and "ON" or "OFF";renderInventory() end)
    return b
end

local function buildPage()
    tabInv=mkButton(sidebar,"OVOS INVENTÁRIO",UDim2.fromOffset(0,100),UDim2.new(1,0,0,42))
    invPage=Instance.new("ScrollingFrame");invPage.Name="InventoryEggPanel";invPage.BackgroundTransparency=1;invPage.BorderSizePixel=0;invPage.Position=UDim2.fromOffset(8,8);invPage.Size=UDim2.new(1,-16,1,-16);invPage.ScrollBarThickness=3;invPage.ScrollBarImageColor3=Color3.fromRGB(94,139,223);invPage.Visible=false;invPage.Parent=contentHost
    local y=0
    mkLabel(invPage,"Ativar leitura do inventário",UDim2.fromOffset(0,y),UDim2.new(.45,0,0,30),9);enabledButton=mkButton(invPage,"ON",UDim2.new(.47,0,0,y),UDim2.new(.53,-4,0,30));y=y+36;setEnabledVisual();connect(enabledButton.MouseButton1Click,function() CFG.Enabled=not CFG.Enabled;setEnabledVisual();renderInventory() end)
    local rarityValues={"Todas"};for _,r in ipairs(RARITY_ORDER) do rarityValues[#rarityValues+1]=r end
    makeCycleButton(invPage,"Raridade mínima",y,rarityValues,function() return CFG.MinRarity==0 and "Todas" or RARITY_ORDER[CFG.MinRarity] end,function(v) CFG.MinRarity=0;for i,r in ipairs(RARITY_ORDER) do if r==v then CFG.MinRarity=i break end end end);y=y+34
    mkLabel(invPage,"Rendimento mínimo ($/s)",UDim2.fromOffset(0,y),UDim2.new(.45,0,0,28),9);earningsBox=mkBox(invPage,"Ex: 2M",UDim2.new(.47,0,0,y),UDim2.new(.53,-4,0,28));y=y+34
    mkLabel(invPage,"Valor do ovo mín. ($)",UDim2.fromOffset(0,y),UDim2.new(.45,0,0,28),9);valueBox=mkBox(invPage,"Opcional",UDim2.new(.47,0,0,y),UDim2.new(.53,-4,0,28));y=y+34
    mkLabel(invPage,"Pet",UDim2.fromOffset(0,y),UDim2.new(.45,0,0,28),9);petBox=mkBox(invPage,"Todos / nome",UDim2.new(.47,0,0,y),UDim2.new(.53,-4,0,28));y=y+34
    makeCycleButton(invPage,"Mutação",y,MUTATION_MODES,function() return CFG.MutationMode end,function(v) CFG.MutationMode=v end);y=y+38
    makeInlineToggle(invPage,"Mostrar $/s do pet",y,"ShowEarnings");y=y+30;makeInlineToggle(invPage,"Mostrar valor do ovo",y,"ShowEggValue");y=y+30;makeInlineToggle(invPage,"Mostrar peso",y,"ShowWeight");y=y+34
    local refreshButton=mkButton(invPage,"Atualizar inventário",UDim2.fromOffset(0,y),UDim2.new(1,-4,0,30));y=y+36
    statusText=mkLabel(invPage,"Inventário:0 • Exibidos:0",UDim2.fromOffset(0,y),UDim2.new(1,-4,0,22),8);statusText.TextXAlignment=Enum.TextXAlignment.Center;statusText.TextColor3=Color3.fromRGB(139,164,207);y=y+28
    listFrame=Instance.new("Frame");listFrame.Name="InventoryEggList";listFrame.BackgroundTransparency=1;listFrame.Position=UDim2.fromOffset(0,y);listFrame.Size=UDim2.new(1,-4,0,0);listFrame.Parent=invPage
    local listLayout=Instance.new("UIListLayout");listLayout.Padding=UDim.new(0,4);listLayout.SortOrder=Enum.SortOrder.LayoutOrder;listLayout.Parent=listFrame
    local function syncInputs() CFG.MinEarnings=parseSmartNumber(earningsBox.Text);CFG.MinSellPrice=parseSmartNumber(valueBox.Text);CFG.PetFilter=petBox.Text or "";renderInventory() end
    connect(earningsBox.FocusLost,syncInputs);connect(valueBox.FocusLost,syncInputs);connect(petBox.FocusLost,syncInputs);connect(refreshButton.MouseButton1Click,renderInventory)
    local function hideInventoryPage() invPage.Visible=false;tabInv.BackgroundColor3=Color3.fromRGB(35,44,61) end
    connect(tabMain.MouseButton1Click,hideInventoryPage);connect(tabFilters.MouseButton1Click,hideInventoryPage)
    connect(tabInv.MouseButton1Click,function() mainPage.Visible=false;filterPage.Visible=false;invPage.Visible=true;tabMain.BackgroundColor3=Color3.fromRGB(35,44,61);tabFilters.BackgroundColor3=Color3.fromRGB(35,44,61);tabInv.BackgroundColor3=Color3.fromRGB(42,91,190);renderInventory() end)
end

local function updateVersion() for _,d in ipairs(mainFrame:GetDescendants()) do if d:IsA("TextLabel") and d.Text:find("V8.3",1,true)==1 then d.Text="V8.5 • INVENTORY PANEL";return end end end
local function cleanup() if not State.Alive then return end;State.Alive=false;clearCards();if invPage then pcall(function() invPage:Destroy() end) end;if tabInv then pcall(function() tabInv:Destroy() end) end;for _,c in ipairs(State.Connections) do disconnect(c) end;_G.PSICO_INVENTORY_PANEL_CLEANUP=nil end
_G.PSICO_INVENTORY_PANEL_CLEANUP=cleanup

local deadline=os.clock()+8
repeat baseGui,mainFrame=findBaseGui();if baseGui and mainFrame then break end;task.wait(.1) until os.clock()>=deadline or not State.Alive
if not (baseGui and mainFrame) then cleanup();return end
if not locateBaseUi() then warn("[PSICO Inventory Panel] base UI não localizada");cleanup();return end
if not resolveModules() then warn("[PSICO Inventory Panel] módulos do inventário indisponíveis");cleanup();return end
buildCatalog();buildPage();updateVersion();connect(baseGui.AncestryChanged,function(_,p) if p==nil then cleanup() end end)

task.defer(function() while State.Alive do if invPage and invPage.Visible and CFG.Enabled then renderInventory();task.wait(1.0) else task.wait(.5) end end end)

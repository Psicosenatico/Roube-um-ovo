--[[
PSICOSENATICO | Steal An Egg - Inventory Panel Enhancer V1
Enhances InventoryEggPanel_V1 without replacing its working reader.
- fixes scroll canvas using the real list position/content height
- mirrors egg images from Roblox Backpack Tool/slot when possible
- falls back to catalog image-like fields
- tap a card to promote/select/equip the matching Tool
]]

if _G.PSICO_INVENTORY_PANEL_ENHANCER_CLEANUP then pcall(_G.PSICO_INVENTORY_PANEL_ENHANCER_CLEANUP) end

local Players=game:GetService("Players")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local CoreGui=game:GetService("CoreGui")
local LP=Players.LocalPlayer

local Alive=true
local Connections={}
local AssetsData,EggRecords,SaveMod
local CatalogIndex={}
local baseGui,mainFrame,invPage,listFrame,statusText

local function safeString(v) local ok,s=pcall(tostring,v);return ok and s or "?" end
local function normalize(v) return string.lower(safeString(v or "")):gsub("[%s_%-%.:/%[%]%(%)'•]","") end
local function connect(sig,fn) local c=sig:Connect(fn);Connections[#Connections+1]=c;return c end
local function uiParent() local ok,h=pcall(function() if gethui then return gethui() end end);return (ok and h) or CoreGui end
local function findPath(root,pathText) local cur=root;for token in string.gmatch(pathText,"[^%.]+") do if not cur then return nil end;cur=cur:FindFirstChild(token) end;return cur end
local function requireOptional(pathText) local m=findPath(ReplicatedStorage,pathText);if not (m and m:IsA("ModuleScript")) then return nil end;local ok,v=pcall(require,m);return ok and v or nil end
local function callTableFn(tbl,name,...) if typeof(tbl)~="table" or type(tbl[name])~="function" then return nil,false end;local fn=tbl[name];local ok,v=pcall(fn,...);if ok then return v,true end;ok,v=pcall(fn,tbl,...);return ok and v or nil,ok end
local function round(o,r) local c=Instance.new("UICorner");c.CornerRadius=UDim.new(0,r or 7);c.Parent=o;return c end

local function imageLike(v,key)
    local kn=normalize(key or "")
    local likely=kn:find("image",1,true) or kn:find("icon",1,true) or kn:find("thumb",1,true) or kn:find("texture",1,true)
    if not likely then return nil end
    if type(v)=="string" then
        if v:match("^rbxassetid://%d+") or v:match("^rbxthumb://") or v:match("^https?://") then return v end
        if v:match("^%d+$") then return "rbxassetid://"..v end
    elseif type(v)=="number" and v>1000 then
        return "rbxassetid://"..tostring(math.floor(v))
    end
end

local function findImageInTable(t,depth,seen)
    if typeof(t)~="table" or depth>4 then return nil end
    seen=seen or {};if seen[t] then return nil end;seen[t]=true
    for k,v in pairs(t) do local img=imageLike(v,k);if img then return img end end
    for k,v in pairs(t) do
        if typeof(v)=="table" then
            local kn=normalize(k)
            if kn:find("egg",1,true) or kn:find("display",1,true) or kn:find("asset",1,true) or kn:find("icon",1,true) then
                local img=findImageInTable(v,depth+1,seen);if img then return img end
            end
        end
    end
    for _,v in pairs(t) do if typeof(v)=="table" then local img=findImageInTable(v,depth+1,seen);if img then return img end end end
end

local function resolveModules()
    AssetsData=requireOptional("Data.Assets")
    EggRecords=requireOptional("Shared.Util.EggRecords")
    SaveMod=requireOptional("Shared.Save") or requireOptional("Data.Save")
    return typeof(AssetsData)=="table" and typeof(SaveMod)=="table"
end

local function indexEntry(key,cfg)
    if typeof(cfg)~="table" then return end
    local rarity=typeof(cfg.Rarity)=="table" and (cfg.Rarity.DisplayName or cfg.Rarity._id) or nil
    local e={Key=safeString(key),PetName=cfg.DisplayName or safeString(key),Rarity=rarity,EggDisplayName=typeof(cfg.Egg)=="table" and cfg.Egg.DisplayName or nil,Image=findImageInTable(cfg,0,{})}
    for _,name in ipairs({e.Key,e.PetName,e.EggDisplayName}) do if type(name)=="string" and name~="" then CatalogIndex[normalize(name)]=e end end
end

local function buildCatalog()
    CatalogIndex={}
    if typeof(AssetsData.ByRarity)=="table" then for _,group in pairs(AssetsData.ByRarity) do if typeof(group)=="table" then for k,cfg in pairs(group) do indexEntry(k,cfg) end end end end
    if next(CatalogIndex)==nil and typeof(AssetsData.Configs)=="table" then for k,cfg in pairs(AssetsData.Configs) do indexEntry(k,cfg) end end
end

local function findCatalog(name)
    local n=normalize(name);local exact=CatalogIndex[n];if exact then return exact end
    local best,bestScore=nil,0
    for _,e in pairs(CatalogIndex) do for _,cand in ipairs({e.PetName,e.Key,e.EggDisplayName}) do local c=normalize(cand or "");if c~="" then local score=(c==n and 100) or ((c:find(n,1,true) or n:find(c,1,true)) and math.min(#c,#n) or 0);if score>bestScore then best,bestScore=e,score end end end end
    return bestScore>=4 and best or nil
end

local function recordCategory(record)
    if typeof(record)~="table" then return nil end
    local item=typeof(record.ItemData)=="table" and record.ItemData or nil
    return record.AssetCategory or record.Category or record.Name or (item and (item.AssetCategory or item.Category or item.Name))
end

local function readInventory()
    local out={}
    local ok,sd=pcall(function() return SaveMod.Get() end)
    if not ok or typeof(sd)~="table" or typeof(sd.EggInventory)~="table" then return out end
    for key,record in pairs(sd.EggInventory) do
        if typeof(record)=="table" then
            local cat=recordCategory(record)
            if type(cat)=="string" and cat~="" then
                local cfg=findCatalog(cat);local weightLabel
                if typeof(EggRecords)=="table" then local v,wok=callTableFn(EggRecords,"WeightLabel",record);if wok then weightLabel=safeString(v) end end
                out[#out+1]={Key=safeString(key),AssetCategory=cat,PetName=cfg and cfg.PetName or cat,Rarity=cfg and cfg.Rarity or record.Rarity,WeightLabel=weightLabel,FallbackImage=cfg and cfg.Image or nil,Record=record}
            end
        end
    end
    return out
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
    local n=0
    for _,d in ipairs(tool:GetDescendants()) do
        if d:IsA("StringValue") then test(d.Value,1.25);n=n+1;if n>20 then break end end
    end
    return score
end

local function matchTool(egg,used)
    local best,bestScore=nil,0
    for _,tool in ipairs(allTools()) do if not used[tool] then local s=toolScore(tool,egg);if s>bestScore then best,bestScore=tool,s end end end
    if best and bestScore>0 then used[best]=true;return best end
end

local function backpackRoot()
    local rg=CoreGui:FindFirstChild("RobloxGui");return rg and rg:FindFirstChild("Backpack")
end

local function collectBackpackSlots()
    local root=backpackRoot();local out={},seen={};if not root then return out end
    for _,d in ipairs(root:GetDescendants()) do
        if d:IsA("TextLabel") and d.Name=="ToolName" and d.Text~="" then
            local cur=d.Parent
            while cur and cur~=root and not cur:IsA("GuiButton") do cur=cur.Parent end
            if cur and cur:IsA("GuiButton") and not seen[cur] then
                seen[cur]=true;local imgObj
                for _,x in ipairs(cur:GetDescendants()) do if x:IsA("ImageLabel") and type(x.Image)=="string" and x.Image~="" then imgObj=x;break end end
                out[#out+1]={Button=cur,Label=d,ImageObject=imgObj,Image=imgObj and imgObj.Image or "",Path=cur:GetFullName()}
            end
        end
    end
    return out
end

local function slotScore(slot,egg,tool)
    local score=0;local wt=weightToken(egg.WeightLabel);local sw=weightToken(slot.Label and slot.Label.Text)
    if wt and sw and wt==sw then score=score+500 end
    if tool then
        local tex=tool.TextureId or "";if tex~="" and slot.Image==tex then score=score+350 end
        local tn=normalize(tool.Name);local ln=normalize(slot.Label and slot.Label.Text);if tn~="" and ln~="" and (tn==ln or ln:find(tn,1,true) or tn:find(ln,1,true)) then score=score+180 end
    end
    return score
end

local function matchSlot(egg,tool,slots,used)
    local best,bestScore=nil,0
    for _,slot in ipairs(slots) do if not used[slot.Button] then local s=slotScore(slot,egg,tool);if s>bestScore then best,bestScore=slot,s end end end
    if best and bestScore>0 then used[best.Button]=true;return best end
end

local function titleParts(card)
    local labels={}
    for _,d in ipairs(card:GetChildren()) do if d:IsA("TextLabel") then labels[#labels+1]=d end end
    table.sort(labels,function(a,b) return a.Position.Y.Offset<b.Position.Y.Offset end)
    local title=labels[1] and labels[1].Text or "";local details=labels[2] and labels[2].Text or ""
    local pet,rarity=title:match("^%s*(.-)%s+•%s+(.-)%s*$")
    return pet or title,rarity or "",details,labels
end

local function chooseEggForCard(card,eggs,used)
    local pet,rarity,details=titleParts(card);local pn,rn=normalize(pet),normalize(rarity);local dw=weightToken(details)
    local best,bestScore=nil,-1
    for _,egg in ipairs(eggs) do
        if not used[egg] then
            local score=0
            if normalize(egg.PetName)==pn then score=score+300 elseif normalize(egg.AssetCategory)==pn then score=score+260 end
            if rn~="" and normalize(egg.Rarity)==rn then score=score+100 end
            local ew=weightToken(egg.WeightLabel);if dw and ew and dw==ew then score=score+500 end
            if score>bestScore then best,bestScore=egg,score end
        end
    end
    if best and bestScore>=250 then used[best]=true;return best end
end

local function status(msg)
    if not statusText or not statusText.Parent then return end
    local base=statusText.Text:gsub("%s+•%s+Ação:.*$","")
    statusText.Text=base.." • Ação: "..msg
end

local function findBestToolNow(egg,preferredTexture)
    local best,bestScore=nil,0
    for _,tool in ipairs(allTools()) do
        local s=toolScore(tool,egg)
        if preferredTexture and preferredTexture~="" and tool.TextureId==preferredTexture then s=s+400 end
        if s>bestScore then best,bestScore=tool,s end
    end
    return best,bestScore
end

local function activateEgg(egg,tool,slot)
    if not Alive then return end
    status("selecionando "..safeString(egg.PetName))
    if slot and slot.Button and slot.Button.Parent and firesignal then
        pcall(function() firesignal(slot.Button.MouseButton1Click) end)
        task.wait(.08)
    end
    if not tool or not tool.Parent then tool=findBestToolNow(egg,slot and slot.Image or nil) end
    if not tool then task.wait(.12);tool=findBestToolNow(egg,slot and slot.Image or nil) end
    local char=LP.Character;local hum=char and char:FindFirstChildOfClass("Humanoid")
    if tool and hum then
        if tool.Parent~=char then pcall(function() hum:UnequipTools();hum:EquipTool(tool) end) end
        task.wait(.05)
        if tool.Parent==char then status("segurando "..safeString(egg.PetName));return end
    end
    if slot and slot.Button and slot.Button.Parent then status("enviado para a hotbar; toque novamente se necessário") else status("item correspondente não localizado") end
end

local function fixCanvas()
    if not (invPage and listFrame and invPage.Parent and listFrame.Parent) then return end
    local layout=listFrame:FindFirstChildOfClass("UIListLayout")
    local content=(layout and layout.AbsoluteContentSize.Y) or listFrame.AbsoluteSize.Y
    if content<0 then content=0 end
    listFrame.Size=UDim2.new(1,-4,0,content)
    local bottom=listFrame.Position.Y.Offset+content+12
    invPage.CanvasSize=UDim2.fromOffset(0,math.max(bottom,invPage.AbsoluteSize.Y+1))
end

local function enhanceCard(card,egg,tool,slot)
    if card:GetAttribute("PsicoEnhanced") then return end
    card:SetAttribute("PsicoEnhanced",true)
    card.Size=UDim2.new(1,-4,0,66)
    local pet,rarity,details,labels=titleParts(card)
    for _,l in ipairs(labels) do l.Position=UDim2.fromOffset(64,l.Position.Y.Offset+5);l.Size=UDim2.new(1,-138,0,l.Size.Y.Offset);l.ZIndex=3 end

    local image=Instance.new("ImageLabel")
    image.Name="EggMirrorImage";image.BackgroundColor3=Color3.fromRGB(14,20,31);image.BackgroundTransparency=.18;image.BorderSizePixel=0;image.Position=UDim2.fromOffset(7,7);image.Size=UDim2.fromOffset(52,52);image.ScaleType=Enum.ScaleType.Fit;image.ZIndex=3;image.Parent=card;round(image,7)
    local texture=(tool and tool.TextureId and tool.TextureId~="" and tool.TextureId) or (slot and slot.Image) or egg.FallbackImage
    if texture and texture~="" then image.Image=texture end
    if slot and slot.ImageObject then
        pcall(function() image.ImageRectOffset=slot.ImageObject.ImageRectOffset;image.ImageRectSize=slot.ImageObject.ImageRectSize;image.ImageColor3=slot.ImageObject.ImageColor3 end)
    end

    local hint=Instance.new("TextLabel")
    hint.Name="EquipHint";hint.BackgroundTransparency=1;hint.Position=UDim2.new(1,-70,0,5);hint.Size=UDim2.fromOffset(64,17);hint.Font=Enum.Font.GothamBold;hint.Text="SEGURAR";hint.TextSize=7;hint.TextColor3=Color3.fromRGB(126,166,235);hint.TextXAlignment=Enum.TextXAlignment.Right;hint.ZIndex=4;hint.Parent=card

    local click=Instance.new("TextButton")
    click.Name="SelectEgg";click.BackgroundTransparency=1;click.Text="";click.AutoButtonColor=false;click.Size=UDim2.fromScale(1,1);click.ZIndex=10;click.Parent=card
    click.MouseButton1Click:Connect(function() task.spawn(activateEgg,egg,tool,slot) end)
end

local function findUi()
    local root=uiParent()
    for _,g in ipairs(root:GetChildren()) do
        if g:IsA("ScreenGui") and g.Name:find("PsicoRoubeUmOvo",1,true)==1 then
            local main=g:FindFirstChild("Main")
            local page=main and main:FindFirstChild("InventoryEggPanel",true)
            local list=page and page:FindFirstChild("InventoryEggList",true)
            if main and page and list then
                baseGui,mainFrame,invPage,listFrame=g,main,page,list
                for _,d in ipairs(page:GetDescendants()) do if d:IsA("TextLabel") and d.Text:find("Inventário:",1,true)==1 then statusText=d break end end
                return true
            end
        end
    end
end

local function updateVersion()
    if not mainFrame then return end
    for _,d in ipairs(mainFrame:GetDescendants()) do if d:IsA("TextLabel") and d.Text:find("V8.5",1,true)==1 then d.Text="V8.6 • INVENTORY IMAGE + EQUIP";return end end
end

local function enhanceAll()
    if not (Alive and invPage and invPage.Parent and listFrame and listFrame.Parent) then return end
    fixCanvas()
    if not invPage.Visible then return end
    local eggs=readInventory();local usedEggs,usedTools,usedSlots={},{},{};local slots=collectBackpackSlots()
    for _,card in ipairs(listFrame:GetChildren()) do
        if card:IsA("Frame") and card.Name=="EggInventoryCard" and not card:GetAttribute("PsicoEnhanced") then
            local egg=chooseEggForCard(card,eggs,usedEggs)
            if egg then
                local tool=matchTool(egg,usedTools)
                local slot=matchSlot(egg,tool,slots,usedSlots)
                enhanceCard(card,egg,tool,slot)
            end
        end
    end
    fixCanvas()
end

local function cleanup()
    if not Alive then return end;Alive=false
    for _,c in ipairs(Connections) do pcall(function() c:Disconnect() end) end
    _G.PSICO_INVENTORY_PANEL_ENHANCER_CLEANUP=nil
end
_G.PSICO_INVENTORY_PANEL_ENHANCER_CLEANUP=cleanup

local deadline=os.clock()+8
repeat if findUi() then break end;task.wait(.1) until os.clock()>deadline
if not (baseGui and invPage and listFrame) then cleanup();return end
if not resolveModules() then cleanup();return end
buildCatalog();updateVersion()
connect(baseGui.AncestryChanged,function(_,p) if p==nil then cleanup() end end)
local layout=listFrame:FindFirstChildOfClass("UIListLayout")
if layout then connect(layout:GetPropertyChangedSignal("AbsoluteContentSize"),function() task.defer(fixCanvas) end) end
connect(listFrame.ChildAdded,function() task.defer(enhanceAll) end)
connect(listFrame.ChildRemoved,function() task.defer(fixCanvas) end)

task.defer(function()
    while Alive do
        if not baseGui.Parent then cleanup();break end
        enhanceAll();task.wait(.18)
    end
end)

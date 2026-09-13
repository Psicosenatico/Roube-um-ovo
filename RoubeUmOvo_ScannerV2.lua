--[[
PSICOSENATICO | Roube um Ovo - Nest Egg Metadata Scanner V5
Stable loader path: RoubeUmOvo_ScannerV2.lua

Purpose:
  * Track ONLY eggs that are currently in nests (FieldEgg State == "Slot").
  * Map Uid -> exact visual model: Workspace.AreaEggSlotsClient[Uid], fallback Workspace[Uid].
  * Collect the game's own metadata/evidence for pet, rarity, value, weight/size and mutations.
  * Scan relevant Attributes, ValueBase objects, UI text and targeted RemoteEvents.
  * Keep true scale fields separate from any discovered official Weight/Value fields.
  * Passive only: no ESP, no prompt changes, no cooldown changes, no remote firing.
]]

if _G.PSICO_ROUBE_MENU_CLEANUP then
    pcall(_G.PSICO_ROUBE_MENU_CLEANUP)
    _G.PSICO_ROUBE_MENU_CLEANUP = nil
end
if _G.PSICO_ROUBE_SCANNER_CLEANUP then
    pcall(_G.PSICO_ROUBE_SCANNER_CLEANUP)
end

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local LP = Players.LocalPlayer
local startedClock = os.clock()
local startedUnix = os.time()

local CONFIRMED_RARITY = {
    ["Frog"] = {Rarity="Common", DisplayName="Frog Egg"},
    ["Chicken"] = {Rarity="Common", DisplayName="Chicken Egg"},
    ["Burrowing Owl"] = {Rarity="Rare", DisplayName="Burrowing Owl Egg"},
    ["Toucan"] = {Rarity="Rare", DisplayName="Toucan Egg"},
    ["Dodo"] = {Rarity="Rare", DisplayName="Dodo Egg"},
    ["Tob Tobi Tob Tob"] = {Rarity="Epic", DisplayName="Tob Tobi Tob Tob Egg"},
    ["Polar Bear"] = {Rarity="Legendary", DisplayName="Polar Bear Egg"},
    ["Finned Thresher"] = {Rarity="Legendary", DisplayName="Shark Egg"},
    ["Orca"] = {Rarity="Mythic", DisplayName="Orca Egg"},
    ["Sand Spider"] = {Rarity="Mythic", DisplayName="Sand Spider Egg"},
    ["Cave Dragon"] = {Rarity="Secret", DisplayName="Cosmic Dragon Egg"},
}

local KEY_WORDS = {
    "value","price","worth","sell","cost","cash","money","coin","income","earn",
    "weight","mass","kg","gram","lb","pound","size","scale","height","width","length",
    "pet","animal","hatch","species","category","assetcategory","displayname","egg",
    "rarity","rare","epic","legendary","mythic","secret","common","mutation","parasite"
}

local REMOTE_WORDS = {
    "egg","pet","hatch","rarity","weight","size","value","price","sell","worth","redeem"
}

local State = {
    Alive = true,
    Connections = {},
    RemoteConnections = {},
    Eggs = {},
    RarityCatalog = {},
    RemoteEvidence = {},
    UiEvidence = {},
    DefinitionEvidence = {},
    Events = {},
    SeenUi = {},
    SeenRemoteEvidence = {},
    SeenDefinition = {},
    EventCount = 0,
}

for category, info in pairs(CONFIRMED_RARITY) do
    State.RarityCatalog[category] = {
        AssetCategory = category,
        Rarity = info.Rarity,
        DisplayName = info.DisplayName,
        Source = "confirmed_previous_scans",
    }
end

local function elapsed()
    return os.clock() - startedClock
end

local function connect(signal, fn, bucket)
    local c = signal:Connect(fn)
    table.insert(bucket or State.Connections, c)
    return c
end

local function disconnect(c)
    pcall(function() c:Disconnect() end)
end

local function fullName(inst)
    local ok, v = pcall(function() return inst:GetFullName() end)
    return ok and v or (inst and inst.Name or "?")
end

local function norm(s)
    s = tostring(s or ""):lower()
    return (s:gsub("[^%w]", ""))
end

local function containsAny(s, words)
    local x = tostring(s or ""):lower()
    for _,w in ipairs(words) do
        if x:find(w, 1, true) then return true end
    end
    return false
end

local function plain(v, depth, seen)
    depth = depth or 0
    seen = seen or {}
    if depth > 5 then return "<max-depth>" end

    local tv = typeof(v)
    if tv == "nil" then return nil end
    if tv == "string" or tv == "number" or tv == "boolean" then return v end
    if tv == "Vector3" then return {x=v.X,y=v.Y,z=v.Z} end
    if tv == "Vector2" then return {x=v.X,y=v.Y} end
    if tv == "Color3" then return {r=v.R,g=v.G,b=v.B} end
    if tv == "CFrame" then local p=v.Position return {x=p.X,y=p.Y,z=p.Z} end
    if tv == "EnumItem" then return tostring(v) end
    if tv == "Instance" then return {name=v.Name,class=v.ClassName,path=fullName(v)} end
    if tv == "table" then
        if seen[v] then return "<cycle>" end
        seen[v] = true
        local out, n = {}, 0
        for k,val in pairs(v) do
            n += 1
            if n > 120 then break end
            out[tostring(k)] = plain(val, depth+1, seen)
        end
        seen[v] = nil
        return out
    end
    return tostring(v)
end

local function attrs(inst, onlyRelevant)
    local out = {}
    local ok, data = pcall(function() return inst:GetAttributes() end)
    if ok then
        for k,v in pairs(data) do
            if not onlyRelevant or containsAny(k, KEY_WORDS) or (typeof(v)=="string" and containsAny(v, KEY_WORDS)) then
                out[tostring(k)] = plain(v)
            end
        end
    end
    return out
end

local function addEvent(kind, data)
    State.EventCount += 1
    table.insert(State.Events, {i=State.EventCount,t=elapsed(),kind=kind,data=data})
    if #State.Events > 1600 then table.remove(State.Events,1) end
end

local function visualForUid(uid)
    local container = Workspace:FindFirstChild("AreaEggSlotsClient")
    if container then
        local exact = container:FindFirstChild(uid)
        if exact then return exact, "AreaEggSlotsClient" end
    end
    local direct = Workspace:FindFirstChild(uid)
    if direct then return direct, "Workspace" end
    if container then
        local recursive = container:FindFirstChild(uid, true)
        if recursive then return recursive, "AreaEggSlotsClient_recursive" end
    end
    return nil, "not_found"
end

local function isTextObject(d)
    return d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox")
end

local function collectInstanceEvidence(root)
    if not root then return nil end
    local evidence = {
        path = fullName(root),
        class = root.ClassName,
        name = root.Name,
        attributes = attrs(root, false),
        relevantAttributes = attrs(root, true),
        values = {},
        texts = {},
        relevantNamedObjects = {},
    }

    local count = 0
    for _,d in ipairs(root:GetDescendants()) do
        count += 1
        if count > 350 then break end

        local relevantName = containsAny(d.Name, KEY_WORDS)
        if d:IsA("ValueBase") and relevantName then
            local ok,v = pcall(function() return d.Value end)
            table.insert(evidence.values, {
                path=fullName(d), name=d.Name, class=d.ClassName,
                value=ok and plain(v) or "<read-failed>", attributes=attrs(d,false)
            })
        elseif isTextObject(d) then
            local text = tostring(d.Text or "")
            if text ~= "" and (containsAny(text, KEY_WORDS) or text:find("%$") or text:lower():find("kg",1,true)) then
                table.insert(evidence.texts, {
                    path=fullName(d), name=d.Name, text=text, attributes=attrs(d,false)
                })
            end
        elseif relevantName then
            table.insert(evidence.relevantNamedObjects, {
                path=fullName(d), name=d.Name, class=d.ClassName, attributes=attrs(d,false)
            })
        else
            local ra = attrs(d, true)
            if next(ra) then
                table.insert(evidence.relevantNamedObjects, {
                    path=fullName(d), name=d.Name, class=d.ClassName, relevantAttributes=ra
                })
            end
        end
    end
    return evidence
end

local function rarityFor(category)
    return State.RarityCatalog[tostring(category or "")]
end

local function copyMutations(v)
    if typeof(v) ~= "table" then return {} end
    local out = {}
    for _,m in pairs(v) do table.insert(out, tostring(m)) end
    table.sort(out)
    return out
end

local function officialFieldsFromTable(t, out, prefix, depth)
    if typeof(t) ~= "table" then return end
    depth = depth or 0
    if depth > 4 then return end
    prefix = prefix or ""
    for k,v in pairs(t) do
        local key = tostring(k)
        local path = prefix == "" and key or (prefix .. "." .. key)
        if containsAny(key, KEY_WORDS) then
            out[path] = plain(v)
        end
        if typeof(v) == "table" then
            officialFieldsFromTable(v, out, path, depth+1)
        end
    end
end

local statusLabel
local function countEggs()
    local n=0
    for _ in pairs(State.Eggs) do n+=1 end
    return n
end

local function countRich()
    local n=0
    for _,e in pairs(State.Eggs) do
        if e.Official and (next(e.Official) or (e.VisualEvidence and (#e.VisualEvidence.values>0 or #e.VisualEvidence.texts>0 or next(e.VisualEvidence.relevantAttributes)))) then
            n+=1
        end
    end
    return n
end

local function refreshStatus(extra)
    if not statusLabel then return end
    local rarities=0
    for _ in pairs(State.RarityCatalog) do rarities+=1 end
    statusLabel.Text = string.format(
        "Ovos nos ninhos: %d | Raridades: %d\nMetadata rica: %d | UI: %d | Remotes: %d%s",
        countEggs(), rarities, countRich(), #State.UiEvidence, #State.RemoteEvidence,
        extra and ("\n"..extra) or ""
    )
end

local function refreshEggVisual(egg)
    local model, method = visualForUid(egg.Uid)
    egg.VisualPath = model and fullName(model) or nil
    egg.VisualMethod = method
    egg.VisualEvidence = model and collectInstanceEvidence(model) or nil
    egg.LastMetadataScan = elapsed()
end

local function makeEgg(record)
    local category = tostring(record.AssetCategory or "Unknown")
    local known = rarityFor(category)
    local uid = tostring(record.Uid)
    local existing = State.Eggs[uid]
    local official = {}
    officialFieldsFromTable(record, official)

    local egg = {
        Uid = uid,
        State = "Slot",
        NestId = record.NestId,
        AreaId = record.AreaId,

        -- Pet/egg identity supplied by the game.
        AssetCategory = record.AssetCategory,
        PetOrAsset = record.AssetCategory,
        DisplayName = record.DisplayName or (known and known.DisplayName) or nil,
        Rarity = record.Rarity or (known and known.Rarity) or nil,

        -- Raw size signals. These are NOT labeled as official weight unless the game exposes one.
        NestScale = record.NestScale,
        AssetScale = record.AssetScale,
        BoundsSize = plain(record.BoundsSize),
        BoundsCFrame = plain(record.BoundsCFrame),
        BottomCFrame = plain(record.BottomCFrame),

        BaseMutation = record.BaseMutation,
        Mutations = copyMutations(record.Mutations),
        HasParasite = record.HasParasite == true,
        AssetColorIndex = record.AssetColorIndex,
        AssetColorSeed = record.AssetColorSeed,
        AssetEyeColor = record.AssetEyeColor,
        Version = record.Version,

        -- Any official-looking keys the server record itself exposes.
        Official = official,
        FirstSeen = existing and existing.FirstSeen or elapsed(),
        LastSeen = elapsed(),
    }
    refreshEggVisual(egg)
    return egg
end

local function removeEgg(uid, reason)
    if type(uid) ~= "string" then return end
    local old = State.Eggs[uid]
    if old then
        State.Eggs[uid] = nil
        addEvent("slot_removed", {Uid=uid,AssetCategory=old.AssetCategory,AreaId=old.AreaId,NestId=old.NestId,Reason=reason})
        refreshStatus()
    end
end

local function ingestFieldRecord(record, source)
    if typeof(record) ~= "table" then return end
    if type(record.Uid) ~= "string" or record.Uid == "" then return end

    if record.State == "Slot" then
        local egg = makeEgg(record)
        State.Eggs[egg.Uid] = egg
        addEvent("slot_seen", {
            Source=source,Uid=egg.Uid,AssetCategory=egg.AssetCategory,AreaId=egg.AreaId,NestId=egg.NestId,
            Rarity=egg.Rarity,NestScale=egg.NestScale,AssetScale=egg.AssetScale,
            Mutations=egg.Mutations,VisualPath=egg.VisualPath,Official=egg.Official
        })
        refreshStatus()
    else
        removeEgg(record.Uid, "state:"..tostring(record.State))
    end
end

local function onBatch(payload)
    if typeof(payload) ~= "table" then return end
    if typeof(payload.RemovedUids) == "table" then
        for _,uid in pairs(payload.RemovedUids) do
            if type(uid)=="string" then removeEgg(uid,"batch_removed") end
        end
    end
    if typeof(payload.UpdatedRecords) == "table" then
        for _,record in pairs(payload.UpdatedRecords) do ingestFieldRecord(record,"batch") end
    end
end

local function onRedeem(info)
    if typeof(info) ~= "table" then return end
    local category = info.AssetCategory
    if type(category) ~= "string" or category == "" then return end

    local fields = {}
    officialFieldsFromTable(info, fields)
    State.RarityCatalog[category] = {
        AssetCategory=category,
        Rarity=info.Rarity,
        DisplayName=info.DisplayName,
        Color=plain(info.Color),
        Official=fields,
        Source="redeem_verdict",
        LastSeen=elapsed(),
    }

    for _,egg in pairs(State.Eggs) do
        if egg.AssetCategory == category then
            egg.Rarity = info.Rarity or egg.Rarity
            egg.DisplayName = info.DisplayName or egg.DisplayName
            for k,v in pairs(fields) do egg.Official[k]=v end
        end
    end
    addEvent("redeem_metadata", {AssetCategory=category,Rarity=info.Rarity,DisplayName=info.DisplayName,Official=fields})
    refreshStatus("Catálogo: "..category)
end

local function relevantRemote(remote)
    local p = fullName(remote):lower()
    local n = remote.Name:lower()
    for _,w in ipairs(REMOTE_WORDS) do
        if n:find(w,1,true) or p:find(w,1,true) then return true end
    end
    return false
end

local hooked = setmetatable({}, {__mode="k"})
local function hookRemote(remote)
    if hooked[remote] or not remote:IsA("RemoteEvent") then return end
    if not relevantRemote(remote) then return end
    hooked[remote] = true

    connect(remote.OnClientEvent, function(...)
        if not State.Alive then return end
        local args = table.pack(...)

        if remote.Name == "RE/EggWorld/FieldEggShifted" then
            ingestFieldRecord(args[1], "shifted")
            return
        elseif remote.Name == "RE/EggWorld/FieldEggBatchShifted" then
            onBatch(args[1])
            return
        elseif remote.Name == "RE/EggWorld/FieldEggGone" then
            if type(args[1])=="string" then removeEgg(args[1],"gone") end
            return
        elseif remote.Name == "RE/EggWorld/FieldEggRedeemVerdict" then
            onRedeem(args[1])
        end

        local packed = {}
        local interesting = false
        for i=1,args.n do
            packed[i] = plain(args[i])
            if typeof(args[i])=="table" then
                local f = {}
                officialFieldsFromTable(args[i], f)
                if next(f) then interesting = true end
            elseif typeof(args[i])=="string" and containsAny(args[i], KEY_WORDS) then
                interesting = true
            end
        end
        if interesting or remote.Name == "RE/EggWorld/FieldEggRedeemVerdict" then
            local signature = remote.Name .. "|" .. HttpService:JSONEncode(packed)
            if not State.SeenRemoteEvidence[signature] then
                State.SeenRemoteEvidence[signature] = true
                table.insert(State.RemoteEvidence, {t=elapsed(),name=remote.Name,path=fullName(remote),args=packed})
                if #State.RemoteEvidence > 500 then table.remove(State.RemoteEvidence,1) end
                refreshStatus()
            end
        end
    end, State.RemoteConnections)
end

local function scanRemotes()
    for _,d in ipairs(ReplicatedStorage:GetDescendants()) do
        if d:IsA("RemoteEvent") and relevantRemote(d) then hookRemote(d) end
    end
end

connect(ReplicatedStorage.DescendantAdded, function(d)
    if d:IsA("RemoteEvent") and relevantRemote(d) then task.defer(function() if State.Alive then hookRemote(d) end end) end
end)
scanRemotes()

local function matchEggForText(text)
    local nt = norm(text)
    if nt == "" then return nil end
    local best, bestLen = nil, 0
    for _,egg in pairs(State.Eggs) do
        local c = norm(egg.AssetCategory)
        local d = norm(egg.DisplayName)
        if c ~= "" and #c >= 3 and nt:find(c,1,true) and #c > bestLen then
            best,bestLen=egg,#c
        elseif d ~= "" and #d >= 3 and nt:find(d,1,true) and #d > bestLen then
            best,bestLen=egg,#d
        end
    end
    return best
end

local function relevantUiText(text)
    text = tostring(text or "")
    if text == "" or #text > 260 then return false end
    local l = text:lower()
    if text:find("%$") then return true end
    if l:find("kg",1,true) or l:find(" lbs",1,true) or l:find("weight",1,true) then return true end
    if containsAny(l, KEY_WORDS) then return true end
    return false
end

local function scanPlayerGui()
    local pg = LP:FindFirstChildOfClass("PlayerGui")
    if not pg then return end
    local scanned=0
    for _,d in ipairs(pg:GetDescendants()) do
        scanned+=1
        if scanned>4500 then break end
        if isTextObject(d) then
            local ok,text = pcall(function() return d.Text end)
            if ok and relevantUiText(text) then
                local visible = true
                pcall(function() visible=d.Visible end)
                if visible then
                    local key = fullName(d).."|"..tostring(text)
                    if not State.SeenUi[key] then
                        State.SeenUi[key]=true
                        local ancestor = d.Parent
                        local ancestorAttrs = {}
                        local steps=0
                        while ancestor and ancestor~=pg and steps<5 do
                            local a=attrs(ancestor,true)
                            for k,v in pairs(a) do ancestorAttrs[fullName(ancestor).."."..k]=v end
                            ancestor=ancestor.Parent
                            steps+=1
                        end
                        local egg = matchEggForText(text)
                        local rec={t=elapsed(),path=fullName(d),name=d.Name,text=tostring(text),attributes=attrs(d,false),ancestorRelevantAttributes=ancestorAttrs}
                        if egg then
                            rec.MatchedUid=egg.Uid
                            rec.MatchedAssetCategory=egg.AssetCategory
                            egg.UiEvidence = egg.UiEvidence or {}
                            table.insert(egg.UiEvidence, rec)
                        end
                        table.insert(State.UiEvidence,rec)
                        if #State.UiEvidence>700 then table.remove(State.UiEvidence,1) end
                    end
                end
            end
        end
    end
end

local function scanDefinitions()
    local categories = {}
    for _,egg in pairs(State.Eggs) do categories[norm(egg.AssetCategory)] = egg.AssetCategory end
    if not next(categories) then return end

    local scanned=0
    for _,d in ipairs(ReplicatedStorage:GetDescendants()) do
        scanned+=1
        if scanned>18000 then break end
        local dn=norm(d.Name)
        local category = categories[dn]
        if category then
            local key=fullName(d)
            if not State.SeenDefinition[key] then
                State.SeenDefinition[key]=true
                local rec={path=key,name=d.Name,class=d.ClassName,category=category,attributes=attrs(d,false),relevantAttributes=attrs(d,true)}
                if d:IsA("ValueBase") then
                    local ok,v=pcall(function() return d.Value end)
                    if ok then rec.value=plain(v) end
                end
                local children={}
                for _,c in ipairs(d:GetChildren()) do
                    if #children>=30 then break end
                    local item={name=c.Name,class=c.ClassName,attributes=attrs(c,true)}
                    if c:IsA("ValueBase") then local ok,v=pcall(function() return c.Value end) if ok then item.value=plain(v) end end
                    table.insert(children,item)
                end
                rec.children=children
                table.insert(State.DefinitionEvidence,rec)
            end
        end
    end
end

local function refreshAllVisuals()
    for _,egg in pairs(State.Eggs) do refreshEggVisual(egg) end
end

local uiAcc, visualAcc = 0,0
connect(RunService.Heartbeat,function(dt)
    if not State.Alive then return end
    uiAcc+=dt; visualAcc+=dt
    if uiAcc>=0.65 then uiAcc=0 scanPlayerGui() end
    if visualAcc>=3 then visualAcc=0 refreshAllVisuals() end
end)

local function buildSummary()
    local s={EggCount=0,Categories={},Rarities={},Areas={},OfficialFieldNames={},VisualResolved=0,WithUiEvidence=0,Mutations={},SizeRanges={NestScaleMin=nil,NestScaleMax=nil,AssetScaleMin=nil,AssetScaleMax=nil}}
    local function range(minK,maxK,v)
        if type(v)~="number" then return end
        if s.SizeRanges[minK]==nil or v<s.SizeRanges[minK] then s.SizeRanges[minK]=v end
        if s.SizeRanges[maxK]==nil or v>s.SizeRanges[maxK] then s.SizeRanges[maxK]=v end
    end
    for _,e in pairs(State.Eggs) do
        s.EggCount+=1
        local c=tostring(e.AssetCategory or "Unknown") s.Categories[c]=(s.Categories[c] or 0)+1
        local a=tostring(e.AreaId or "Unknown") s.Areas[a]=(s.Areas[a] or 0)+1
        if e.Rarity then s.Rarities[e.Rarity]=(s.Rarities[e.Rarity] or 0)+1 end
        if e.VisualPath then s.VisualResolved+=1 end
        if e.UiEvidence and #e.UiEvidence>0 then s.WithUiEvidence+=1 end
        for k in pairs(e.Official or {}) do s.OfficialFieldNames[k]=(s.OfficialFieldNames[k] or 0)+1 end
        for _,m in ipairs(e.Mutations or {}) do s.Mutations[m]=(s.Mutations[m] or 0)+1 end
        range("NestScaleMin","NestScaleMax",e.NestScale)
        range("AssetScaleMin","AssetScaleMax",e.AssetScale)
    end
    return s
end

local function buildReport()
    refreshAllVisuals()
    scanPlayerGui()
    scanDefinitions()
    return {
        Version="NestEgg Metadata Scanner V5",
        Meta={PlaceId=game.PlaceId,GameId=game.GameId,JobId=game.JobId,StartedUnix=startedUnix,FinishedUnix=os.time(),DurationSeconds=elapsed(),SelectionRule="FieldEgg State == Slot only",VisualRule="AreaEggSlotsClient[Uid], fallback Workspace[Uid]"},
        Summary=buildSummary(),
        EggsInNests=State.Eggs,
        RarityCatalog=State.RarityCatalog,
        UiEvidence=State.UiEvidence,
        RemoteEvidence=State.RemoteEvidence,
        DefinitionEvidence=State.DefinitionEvidence,
        Events=State.Events,
    }
end

local function exportReport()
    local ok, encoded = pcall(HttpService.JSONEncode,HttpService,buildReport())
    if not ok then return false,"JSONEncode falhou: "..tostring(encoded) end
    local filename="Psico_RoubeUmOvo_EggMetadata_"..tostring(os.time())..".json"
    if writefile then
        local wok,err=pcall(writefile,filename,encoded)
        if wok then return true,"Salvo: "..filename end
        return false,"writefile falhou: "..tostring(err)
    end
    if setclipboard then
        local cok,err=pcall(setclipboard,encoded)
        if cok then return true,"JSON copiado" end
        return false,"setclipboard falhou: "..tostring(err)
    end
    return false,"Executor sem writefile/setclipboard"
end

local function parentGui()
    local ok,h=pcall(function() if gethui then return gethui() end end)
    return (ok and h) or CoreGui
end

local old=parentGui():FindFirstChild("PsicoNestEggMetadataV5")
if old then old:Destroy() end

local gui=Instance.new("ScreenGui")
gui.Name="PsicoNestEggMetadataV5"
gui.ResetOnSpawn=false
gui.IgnoreGuiInset=true
gui.Parent=parentGui()

local frame=Instance.new("Frame")
frame.AnchorPoint=Vector2.new(.5,.5)
frame.Position=UDim2.fromScale(.5,.5)
frame.Size=UDim2.fromOffset(300,190)
frame.BackgroundColor3=Color3.fromRGB(15,21,33)
frame.BorderSizePixel=0
frame.Parent=gui
Instance.new("UICorner",frame).CornerRadius=UDim.new(0,12)
local stroke=Instance.new("UIStroke",frame)
stroke.Thickness=1
stroke.Transparency=.32
stroke.Color=Color3.fromRGB(73,126,230)

local title=Instance.new("TextLabel")
title.BackgroundTransparency=1
title.Position=UDim2.fromOffset(12,8)
title.Size=UDim2.new(1,-52,0,25)
title.Font=Enum.Font.GothamBold
title.Text="EGG METADATA SCANNER • V5"
title.TextColor3=Color3.fromRGB(241,245,255)
title.TextSize=13
title.TextXAlignment=Enum.TextXAlignment.Left
title.Parent=frame

local close=Instance.new("TextButton")
close.AnchorPoint=Vector2.new(1,0)
close.Position=UDim2.new(1,-8,0,7)
close.Size=UDim2.fromOffset(28,28)
close.BackgroundColor3=Color3.fromRGB(32,42,60)
close.BorderSizePixel=0
close.Font=Enum.Font.GothamBold
close.Text="×"
close.TextColor3=Color3.fromRGB(240,244,255)
close.TextSize=15
close.Parent=frame
Instance.new("UICorner",close).CornerRadius=UDim.new(0,8)

statusLabel=Instance.new("TextLabel")
statusLabel.Position=UDim2.fromOffset(12,43)
statusLabel.Size=UDim2.new(1,-24,0,83)
statusLabel.BackgroundColor3=Color3.fromRGB(21,29,44)
statusLabel.BorderSizePixel=0
statusLabel.Font=Enum.Font.Code
statusLabel.TextColor3=Color3.fromRGB(174,198,241)
statusLabel.TextSize=10
statusLabel.TextWrapped=true
statusLabel.Parent=frame
Instance.new("UICorner",statusLabel).CornerRadius=UDim.new(0,9)

local export=Instance.new("TextButton")
export.Position=UDim2.fromOffset(12,136)
export.Size=UDim2.new(1,-24,0,38)
export.BackgroundColor3=Color3.fromRGB(37,82,170)
export.BorderSizePixel=0
export.Font=Enum.Font.GothamMedium
export.Text="Exportar metadata completa"
export.TextColor3=Color3.fromRGB(245,248,255)
export.TextSize=12
export.Parent=frame
Instance.new("UICorner",export).CornerRadius=UDim.new(0,9)

local dragging=false
local dragStart,startPos,dragInput
connect(frame.InputBegan,function(input)
    if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1 then
        dragging=true dragStart=input.Position startPos=frame.Position dragInput=input
    end
end)
connect(frame.InputChanged,function(input)
    if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseMovement then dragInput=input end
end)
connect(UIS.InputChanged,function(input)
    if dragging and input==dragInput then
        local delta=input.Position-dragStart
        frame.Position=UDim2.new(startPos.X.Scale,startPos.X.Offset+delta.X,startPos.Y.Scale,startPos.Y.Offset+delta.Y)
    end
end)
connect(UIS.InputEnded,function(input)
    if input==dragInput or input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1 then dragging=false end
end)

connect(export.MouseButton1Click,function()
    local ok,msg=exportReport()
    refreshStatus((ok and "✓ " or "✗ ")..msg)
end)

local function cleanup()
    if not State.Alive then return end
    State.Alive=false
    for _,c in ipairs(State.RemoteConnections) do disconnect(c) end
    for _,c in ipairs(State.Connections) do disconnect(c) end
    _G.PSICO_ROUBE_SCANNER_CLEANUP=nil
    pcall(function() gui:Destroy() end)
end
_G.PSICO_ROUBE_SCANNER_CLEANUP=cleanup
connect(close.MouseButton1Click,cleanup)

refreshStatus("Aproxime/interaja com ovos para capturar UI")

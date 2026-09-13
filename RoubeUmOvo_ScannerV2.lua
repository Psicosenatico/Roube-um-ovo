--[[
PSICOSENATICO | Roube um Ovo - Scanner V2
Targeted passive scanner for dropped-item lifecycle and bat cooldown.
Does not fire remotes or modify gameplay state.
]]

if _G.PSICO_ROUBE_SCANNER_V2 then
    pcall(function() _G.PSICO_ROUBE_SCANNER_V2:Destroy() end)
    _G.PSICO_ROUBE_SCANNER_V2 = nil
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
local connections = {}
local trackedRoots = setmetatable({}, {__mode = "k"})
local trackedTools = setmetatable({}, {__mode = "k"})
local running = true

local REPORT = {
    version = "Scanner V2",
    meta = {
        placeId = game.PlaceId,
        gameId = game.GameId,
        jobId = game.JobId,
        startedUnix = startedUnix,
    },
    remoteEvents = {},
    rootEvents = {},
    rootSamples = {},
    batEvents = {},
    promptEvents = {},
    summary = {},
}

local TARGET_REMOTE_NAMES = {
    ["RE/EggWorld/OwnerDropped"] = true,
    ["RE/EggWorld/OwnerShifted"] = true,
    ["RE/EggWorld/FieldEggGone"] = true,
    ["RE/EggWorld/FieldEggShifted"] = true,
    ["RE/EggWorld/FieldEggCarry"] = true,
    ["RE/EggWorld/FieldEggBatchShifted"] = true,
    ["RE/EggWorld/FieldEggRedeemVerdict"] = true,
    ["RE/BatSwing/Trigger"] = true,
    ["RE/GearSatchel/Gained"] = true,
    ["RE/GearSatchel/Lost"] = true,
}

local function connect(signal, fn)
    local c = signal:Connect(fn)
    table.insert(connections, c)
    return c
end

local function tnow()
    return os.clock() - startedClock
end

local function fullname(inst)
    local ok, value = pcall(function() return inst:GetFullName() end)
    return ok and value or (inst and inst.Name or "?")
end

local function attrs(inst)
    local out = {}
    local ok, a = pcall(function() return inst:GetAttributes() end)
    if ok then
        for k,v in pairs(a) do
            local tv = typeof(v)
            if tv == "string" or tv == "number" or tv == "boolean" then
                out[k] = v
            elseif tv == "Vector3" then
                out[k] = {x=v.X,y=v.Y,z=v.Z}
            elseif tv == "Color3" then
                out[k] = {r=v.R,g=v.G,b=v.B}
            else
                out[k] = tostring(v)
            end
        end
    end
    return out
end

local function pos(inst)
    if not inst then return nil end
    if inst:IsA("BasePart") then
        local p = inst.Position
        return {x=p.X,y=p.Y,z=p.Z}
    elseif inst:IsA("Model") then
        local ok, cf = pcall(function() return inst:GetPivot() end)
        if ok then
            local p = cf.Position
            return {x=p.X,y=p.Y,z=p.Z}
        end
    elseif inst:IsA("Tool") then
        local h = inst:FindFirstChild("Handle") or inst:FindFirstChildWhichIsA("BasePart", true)
        if h then
            local p = h.Position
            return {x=p.X,y=p.Y,z=p.Z}
        end
    end
    return nil
end

local function isHex32(s)
    return type(s)=="string" and #s==32 and string.match(s, "^[0-9a-fA-F]+$") ~= nil
end

local function hasHitbox(inst)
    return inst and inst:FindFirstChild("Hitbox", true) ~= nil
end

local function rootCandidate(inst)
    if not inst or inst.Parent ~= Workspace then return false end
    if inst:IsA("Model") or inst:IsA("Tool") or inst:IsA("BasePart") then
        return isHex32(inst.Name) or hasHitbox(inst)
    end
    return false
end

local function describeRoot(root)
    if not root then return nil end
    local out = {
        name = root.Name,
        class = root.ClassName,
        path = fullname(root),
        attributes = attrs(root),
        position = pos(root),
        descendants = {},
    }
    local n = 0
    for _,d in ipairs(root:GetDescendants()) do
        n += 1
        if n > 180 then break end
        local rec = {name=d.Name,class=d.ClassName,path=fullname(d),attributes=attrs(d)}
        if d:IsA("BasePart") then rec.position = pos(d) end
        if d:IsA("ValueBase") then
            local ok,v = pcall(function() return d.Value end)
            if ok then
                local tv=typeof(v)
                rec.value=(tv=="string" or tv=="number" or tv=="boolean") and v or tostring(v)
            end
        end
        table.insert(out.descendants, rec)
    end
    return out
end

local function describeTool(tool)
    return {
        name = tool.Name,
        path = fullname(tool),
        parent = tool.Parent and fullname(tool.Parent) or nil,
        attributes = attrs(tool),
        enabled = tool.Enabled,
        position = pos(tool),
    }
end

local function serialize(v, depth, seen)
    depth = depth or 0
    seen = seen or {}
    if depth > 5 then return "<max-depth>" end
    local tv = typeof(v)
    if tv == "nil" then return nil end
    if tv == "string" or tv == "number" or tv == "boolean" then return v end
    if tv == "Instance" then
        return {__type="Instance",name=v.Name,class=v.ClassName,path=fullname(v),attributes=attrs(v),position=pos(v)}
    end
    if tv == "Vector3" then return {__type="Vector3",x=v.X,y=v.Y,z=v.Z} end
    if tv == "Vector2" then return {__type="Vector2",x=v.X,y=v.Y} end
    if tv == "CFrame" then local p=v.Position return {__type="CFrame",x=p.X,y=p.Y,z=p.Z} end
    if tv == "Color3" then return {__type="Color3",r=v.R,g=v.G,b=v.B} end
    if tv == "EnumItem" then return tostring(v) end
    if tv == "table" then
        if seen[v] then return "<cycle>" end
        seen[v]=true
        local out={}
        local count=0
        for k,val in pairs(v) do
            count += 1
            if count > 80 then break end
            out[tostring(k)] = serialize(val, depth+1, seen)
        end
        seen[v]=nil
        return out
    end
    return tostring(v)
end

local function add(list, rec, maxn)
    table.insert(list, rec)
    if #list > (maxn or 1200) then table.remove(list,1) end
end

local function eventArgs(...)
    local packed = table.pack(...)
    local out = {n=packed.n, values={}}
    for i=1,packed.n do
        out.values[i] = serialize(packed[i])
    end
    return out
end

local function findRemoteExact(name)
    for _,d in ipairs(ReplicatedStorage:GetDescendants()) do
        if d:IsA("RemoteEvent") and d.Name == name then
            return d
        end
    end
end

local hookedRemotes = {}
local function hookRemote(remote)
    if hookedRemotes[remote] then return end
    hookedRemotes[remote]=true
    connect(remote.OnClientEvent, function(...)
        if not running then return end
        add(REPORT.remoteEvents, {
            t=tnow(),
            name=remote.Name,
            path=fullname(remote),
            args=eventArgs(...),
        })
    end)
end

local function hookTargetRemotes()
    for _,d in ipairs(ReplicatedStorage:GetDescendants()) do
        if d:IsA("RemoteEvent") and TARGET_REMOTE_NAMES[d.Name] then
            hookRemote(d)
        end
    end
end

local function hookRoot(root, source)
    if trackedRoots[root] then return end
    trackedRoots[root] = true
    add(REPORT.rootEvents, {t=tnow(),kind="root_seen",source=source,root=describeRoot(root)})
    connect(root.AncestryChanged, function(_,parent)
        if not running then return end
        add(REPORT.rootEvents, {
            t=tnow(),
            kind=parent and "root_moved" or "root_removed",
            root=describeRoot(root),
            newParent=parent and fullname(parent) or nil,
        })
    end)
end

local function scanRoots()
    for _,child in ipairs(Workspace:GetChildren()) do
        if rootCandidate(child) then hookRoot(child,"initial") end
    end
end

local function isBat(tool)
    if not tool or not tool:IsA("Tool") then return false end
    local a=attrs(tool)
    return a.IsBat == true or tostring(a.GearName or ""):lower():find("bat",1,true) ~= nil
end

local function hookBat(tool)
    if trackedTools[tool] or not isBat(tool) then return end
    trackedTools[tool]=true
    local function rec(kind)
        if running then add(REPORT.batEvents,{t=tnow(),kind=kind,tool=describeTool(tool)}) end
    end
    rec("bat_seen")
    connect(tool.Activated,function() rec("activated") end)
    connect(tool.Deactivated,function() rec("deactivated") end)
    for _,name in ipairs({"CooldownActive","CooldownEndTime","CooldownDuration","Uses"}) do
        connect(tool:GetAttributeChangedSignal(name),function() rec("attr_"..name) end)
    end
    connect(tool.AncestryChanged,function() rec("ancestry") end)
end

local function scanBats()
    local backpack=LP:FindFirstChildOfClass("Backpack")
    if backpack then
        for _,d in ipairs(backpack:GetChildren()) do if d:IsA("Tool") then hookBat(d) end end
    end
    if LP.Character then
        for _,d in ipairs(LP.Character:GetChildren()) do if d:IsA("Tool") then hookBat(d) end end
    end
end

local function hookPrompts()
    for _,d in ipairs(Workspace:GetDescendants()) do
        if d:IsA("ProximityPrompt") and d.HoldDuration > 0 then
            local p=d
            connect(p.Triggered,function(player)
                if running then
                    add(REPORT.promptEvents,{t=tnow(),kind="triggered",localPlayer=player==LP,prompt={name=p.Name,path=fullname(p),actionText=p.ActionText,objectText=p.ObjectText,holdDuration=p.HoldDuration,parent=p.Parent and fullname(p.Parent) or nil}})
                end
            end)
        end
    end
end

connect(Workspace.ChildAdded,function(child)
    if not running then return end
    if rootCandidate(child) then
        task.defer(function()
            if child.Parent==Workspace then hookRoot(child,"child_added") end
        end)
    end
end)

connect(Workspace.ChildRemoved,function(child)
    if not running then return end
    if trackedRoots[child] or isHex32(child.Name) or hasHitbox(child) then
        add(REPORT.rootEvents,{t=tnow(),kind="workspace_child_removed",root=describeRoot(child)})
    end
end)

connect(ReplicatedStorage.DescendantAdded,function(d)
    if d:IsA("RemoteEvent") and TARGET_REMOTE_NAMES[d.Name] then hookRemote(d) end
end)

local function hookPlayerContainer(container)
    if not container then return end
    for _,d in ipairs(container:GetChildren()) do if d:IsA("Tool") then hookBat(d) end end
    connect(container.ChildAdded,function(d)
        if d:IsA("Tool") then task.defer(function() if d.Parent then hookBat(d) end end) end
    end)
end

hookPlayerContainer(LP:FindFirstChildOfClass("Backpack"))
if LP.Character then hookPlayerContainer(LP.Character) end
connect(LP.CharacterAdded,function(char)
    task.wait(0.4)
    hookPlayerContainer(char)
end)

hookTargetRemotes()
scanRoots()
scanBats()
hookPrompts()

local sampleAccumulator=0
connect(RunService.Heartbeat,function(dt)
    if not running then return end
    sampleAccumulator += dt
    if sampleAccumulator < 0.25 then return end
    sampleAccumulator=0
    local sample={t=tnow(),roots={}}
    for root in pairs(trackedRoots) do
        if root and root.Parent==Workspace then
            table.insert(sample.roots,{name=root.Name,position=pos(root),attributes=attrs(root),hasHitbox=hasHitbox(root)})
        end
    end
    add(REPORT.rootSamples,sample,500)
    scanBats()
end)

local function exportReport()
    REPORT.meta.finishedUnix=os.time()
    REPORT.meta.durationSeconds=tnow()
    REPORT.summary={
        remoteEvents=#REPORT.remoteEvents,
        rootEvents=#REPORT.rootEvents,
        rootSamples=#REPORT.rootSamples,
        batEvents=#REPORT.batEvents,
        promptEvents=#REPORT.promptEvents,
    }
    local ok,encoded=pcall(HttpService.JSONEncode,HttpService,REPORT)
    if not ok then return false,"JSONEncode falhou: "..tostring(encoded) end
    local name="Psico_RoubeUmOvo_ScanV2_"..tostring(os.time())..".json"
    if writefile then
        local wok,werr=pcall(writefile,name,encoded)
        if wok then return true,"Arquivo salvo: "..name end
        return false,"writefile falhou: "..tostring(werr)
    end
    if setclipboard then
        local cok,cerr=pcall(setclipboard,encoded)
        if cok then return true,"JSON copiado para a área de transferência" end
        return false,"setclipboard falhou: "..tostring(cerr)
    end
    return false,"Executor sem writefile/setclipboard"
end

local function parentGui()
    local ok,h=pcall(function() if gethui then return gethui() end end)
    return (ok and h) or CoreGui
end

local gui=Instance.new("ScreenGui")
gui.Name="PsicoRoubeUmOvoScannerV2"
gui.ResetOnSpawn=false
gui.IgnoreGuiInset=true
gui.Parent=parentGui()
_G.PSICO_ROUBE_SCANNER_V2=gui

local frame=Instance.new("Frame")
frame.AnchorPoint=Vector2.new(.5,.5)
frame.Position=UDim2.fromScale(.5,.5)
frame.Size=UDim2.fromOffset(286,176)
frame.BackgroundColor3=Color3.fromRGB(15,21,33)
frame.BorderSizePixel=0
frame.Parent=gui
Instance.new("UICorner",frame).CornerRadius=UDim.new(0,12)

local title=Instance.new("TextLabel")
title.BackgroundTransparency=1
title.Position=UDim2.fromOffset(12,8)
title.Size=UDim2.new(1,-52,0,24)
title.Font=Enum.Font.GothamBold
title.Text="ROUBE UM OVO • SCANNER V2"
title.TextColor3=Color3.fromRGB(240,244,255)
title.TextSize=13
title.TextXAlignment=Enum.TextXAlignment.Left
title.Parent=frame

local close=Instance.new("TextButton")
close.AnchorPoint=Vector2.new(1,0)
close.Position=UDim2.new(1,-8,0,7)
close.Size=UDim2.fromOffset(28,28)
close.BackgroundColor3=Color3.fromRGB(35,44,62)
close.BorderSizePixel=0
close.Font=Enum.Font.GothamBold
close.Text="×"
close.TextColor3=Color3.fromRGB(240,244,255)
close.TextSize=16
close.Parent=frame
Instance.new("UICorner",close).CornerRadius=UDim.new(0,8)

local status=Instance.new("TextLabel")
status.Position=UDim2.fromOffset(12,42)
status.Size=UDim2.new(1,-24,0,57)
status.BackgroundColor3=Color3.fromRGB(20,28,43)
status.BorderSizePixel=0
status.Font=Enum.Font.Code
status.TextColor3=Color3.fromRGB(165,190,239)
status.TextSize=10
status.TextWrapped=true
status.Text="V2 ativo. Faça um item cair no chão, pegue-o novamente e use o bastão várias vezes."
status.Parent=frame
Instance.new("UICorner",status).CornerRadius=UDim.new(0,9)

local export=Instance.new("TextButton")
export.Position=UDim2.fromOffset(12,110)
export.Size=UDim2.new(1,-24,0,38)
export.BackgroundColor3=Color3.fromRGB(34,79,164)
export.BorderSizePixel=0
export.Font=Enum.Font.GothamMedium
export.Text="EXPORTAR JSON V2"
export.TextColor3=Color3.fromRGB(245,248,255)
export.TextSize=12
export.Parent=frame
Instance.new("UICorner",export).CornerRadius=UDim.new(0,9)

local hint=Instance.new("TextLabel")
hint.BackgroundTransparency=1
hint.Position=UDim2.fromOffset(12,151)
hint.Size=UDim2.new(1,-24,0,18)
hint.Font=Enum.Font.Gotham
hint.Text="Ideal: drop → esperar 2s → pegar → bater 5x → exportar"
hint.TextColor3=Color3.fromRGB(133,148,177)
hint.TextSize=9
hint.Parent=frame

local dragging=false
local dragStart,startPos,activeInput
frame.InputBegan:Connect(function(input)
    if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
        dragging=true activeInput=input dragStart=input.Position startPos=frame.Position
    end
end)
frame.InputChanged:Connect(function(input)
    if input.UserInputType==Enum.UserInputType.MouseMovement or input.UserInputType==Enum.UserInputType.Touch then activeInput=input end
end)
UIS.InputChanged:Connect(function(input)
    if dragging and input==activeInput then
        local d=input.Position-dragStart
        frame.Position=UDim2.new(startPos.X.Scale,startPos.X.Offset+d.X,startPos.Y.Scale,startPos.Y.Offset+d.Y)
    end
end)
UIS.InputEnded:Connect(function(input) if input==activeInput then dragging=false end end)

export.MouseButton1Click:Connect(function()
    local ok,msg=exportReport()
    status.Text=(ok and "✓ " or "✗ ")..msg
end)

close.MouseButton1Click:Connect(function()
    running=false
    for _,c in ipairs(connections) do pcall(function() c:Disconnect() end) end
    _G.PSICO_ROUBE_SCANNER_V2=nil
    gui:Destroy()
end)

connect(RunService.RenderStepped,function()
    if running then
        status.Text=string.format("V2 ativo • %.0fs\nRemotes: %d | Roots: %d | Bat: %d",tnow(),#REPORT.remoteEvents,#REPORT.rootEvents,#REPORT.batEvents)
    end
end)

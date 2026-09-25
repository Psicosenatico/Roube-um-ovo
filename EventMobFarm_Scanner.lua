-- PSICOSENATICO | EVENT MOB FARM SCANNER V2
-- Targeted scanner for Dr. Scramble / drone combat + bat hit flow.
-- Keeps the same stable file/loadstring.

if _G.PSICO_EVENT_MOB_SCANNER_CLEANUP then
    pcall(_G.PSICO_EVENT_MOB_SCANNER_CLEANUP)
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local CoreGui = game:GetService("CoreGui")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")

local LP = Players.LocalPlayer
local conns = {}
local state = {
    active=false,
    startedUnix=os.time(),
    events={},
    before=nil,
    after=nil,
    moduleInfo={},
    hookSupported=false,
    hookInstalled=false,
}

local function full(inst)
    local ok,v=pcall(function() return inst:GetFullName() end)
    return ok and v or tostring(inst)
end

local function simple(v, depth, seen)
    depth=depth or 0
    seen=seen or {}
    local tv=typeof(v)
    if tv=="nil" or tv=="boolean" or tv=="string" or tv=="number" then return v end
    if tv=="Vector3" then return {x=v.X,y=v.Y,z=v.Z} end
    if tv=="CFrame" then local p=v.Position return {x=p.X,y=p.Y,z=p.Z} end
    if tv=="Color3" then return {r=v.R,g=v.G,b=v.B} end
    if tv=="Instance" then return {class=v.ClassName,name=v.Name,path=full(v)} end
    if tv=="table" then
        if seen[v] then return "<cycle>" end
        if depth>=4 then return "<depth>" end
        seen[v]=true
        local out={}
        local n=0
        for k,x in pairs(v) do
            n+=1
            if n>80 then out.__truncated=true break end
            out[tostring(k)]=simple(x,depth+1,seen)
        end
        seen[v]=nil
        return out
    end
    return tostring(v)
end

local function packArgs(...)
    local p=table.pack(...)
    local out={}
    for i=1,p.n do out[i]=simple(p[i]) end
    return out
end

local function attrs(inst)
    local out={}
    local ok,a=pcall(function() return inst:GetAttributes() end)
    if ok and type(a)=="table" then
        for k,v in pairs(a) do out[k]=simple(v) end
    end
    return out
end

local function push(kind,data)
    state.events[#state.events+1]={
        t=os.clock(),unix=os.time(),kind=kind,data=data
    }
    if #state.events>5000 then table.remove(state.events,1) end
end

local function findPath(path)
    local x=ReplicatedStorage
    for seg in path:gmatch("[^%.]+") do
        x=x and x:FindFirstChild(seg)
    end
    return x
end

local function remote(name)
    for _,d in ipairs(ReplicatedStorage:GetDescendants()) do
        if (d:IsA("RemoteEvent") or d:IsA("RemoteFunction")) and d.Name==name then
            return d
        end
    end
end

local TARGET_REMOTE_NAMES={
    "RE/BatSwing/Trigger",
    "RE/Scramble/Drones",
    "RE/Scramble/State",
    "RE/Scramble/Drops",
    "RE/Scramble/RemoveDrops",
    "RE/Scramble/Effect",
    "RE/Scramble/Collect",
}

local targetRemotes={}
for _,name in ipairs(TARGET_REMOTE_NAMES) do
    local r=remote(name)
    if r then targetRemotes[name]=r end
end

local function connectInbound()
    for name,r in pairs(targetRemotes) do
        if r:IsA("RemoteEvent") then
            conns[#conns+1]=r.OnClientEvent:Connect(function(...)
                if state.active then
                    push("remote_in",{
                        remote=name,
                        args=packArgs(...)
                    })
                end
            end)
        end
    end
end

local oldNamecall=nil
local hookClosure=nil

local function installOutgoingHook()
    if state.hookInstalled then return true end
    if type(hookmetamethod)~="function" or type(getnamecallmethod)~="function" then
        return false
    end

    local targetByInstance={}
    for name,r in pairs(targetRemotes) do targetByInstance[r]=name end

    local wrap = type(newcclosure)=="function" and newcclosure or function(f) return f end

    local ok,old=pcall(function()
        local previous
        previous=hookmetamethod(game,"__namecall",wrap(function(self,...)
            local method=getnamecallmethod()
            if state.active and method=="FireServer" then
                local n=targetByInstance[self]
                if n then
                    push("remote_out",{
                        remote=n,
                        args=packArgs(...)
                    })
                end
            end
            return previous(self,...)
        end))
        return previous
    end)

    if ok and old then
        oldNamecall=old
        state.hookInstalled=true
        state.hookSupported=true
        return true
    end
    return false
end

local function uninstallOutgoingHook()
    if not state.hookInstalled then return end
    state.active=false
    -- Restore only if executor supports replacing the metamethod again.
    if oldNamecall and type(hookmetamethod)=="function" then
        pcall(function() hookmetamethod(game,"__namecall",oldNamecall) end)
    end
    state.hookInstalled=false
    oldNamecall=nil
end

local function fnMeta(fn)
    local out={type="function"}
    if debug and debug.info then
        pcall(function()
            out.name=debug.info(fn,"n")
            out.source=debug.info(fn,"s")
            out.line=debug.info(fn,"l")
            out.argc=debug.info(fn,"a")
        end)
    end

    local gc=(debug and debug.getconstants) or getconstants
    if type(gc)=="function" then
        local ok,c=pcall(gc,fn)
        if ok and type(c)=="table" then
            out.constants={}
            for _,v in ipairs(c) do
                local t=typeof(v)
                if t=="string" or t=="number" or t=="boolean" then
                    out.constants[#out.constants+1]=v
                    if #out.constants>=120 then break end
                end
            end
        end
    end

    local gu=(debug and debug.getupvalues) or getupvalues
    if type(gu)=="function" then
        local ok,u=pcall(gu,fn)
        if ok and type(u)=="table" then
            out.upvalues={}
            local n=0
            for k,v in pairs(u) do
                n+=1
                if n>40 then break end
                local tv=typeof(v)
                if tv=="string" or tv=="number" or tv=="boolean" then
                    out.upvalues[tostring(k)]=v
                elseif tv=="Instance" then
                    out.upvalues[tostring(k)]=simple(v)
                elseif tv=="table" then
                    local shallow={}
                    local m=0
                    for kk,vv in pairs(v) do
                        m+=1
                        if m>30 then break end
                        local tt=typeof(vv)
                        if tt=="string" or tt=="number" or tt=="boolean" then
                            shallow[tostring(kk)]=vv
                        end
                    end
                    out.upvalues[tostring(k)]=shallow
                end
            end
        end
    end
    return out
end

local MODULE_PATHS={
    "Controllers.Game.ScrambleClientController",
    "Controllers.Game.ScrambleClientController.PersonalDrones",
    "Controllers.Game.ScrambleClientController.DroneVisual",
    "Controllers.Game.ScrambleClientController.HitFeedback",
    "Shared.Util.ScrambleRules",
    "Shared.Util.ScrambleDroneMotion",
    "Shared.Modules.BatController.Client",
    "Shared.Modules.BatController.Config",
}

local function inspectModules()
    local out={}
    for _,path in ipairs(MODULE_PATHS) do
        local m=findPath(path)
        local row={path=path,found=m~=nil}
        if m and m:IsA("ModuleScript") then
            local ok,v=pcall(require,m)
            row.requireOk=ok
            row.returnType=typeof(v)
            if ok then
                if type(v)=="table" then
                    row.keys={}
                    local n=0
                    for k,x in pairs(v) do
                        n+=1
                        if n>100 then break end
                        local item={key=tostring(k),type=typeof(x)}
                        if type(x)=="function" then item.meta=fnMeta(x)
                        elseif typeof(x)=="Instance" then item.value=simple(x)
                        elseif type(x)=="string" or type(x)=="number" or type(x)=="boolean" then item.value=x
                        end
                        row.keys[#row.keys+1]=item
                    end
                elseif type(v)=="function" then
                    row.functionMeta=fnMeta(v)
                end
            else
                row.error=tostring(v)
            end
        end
        out[#out+1]=row
    end
    state.moduleInfo=out
    return out
end

local function isBat(tool)
    return tool and tool:IsA("Tool") and (
        tool:GetAttribute("IsBat")==true
        or tostring(tool:GetAttribute("GearName") or ""):lower():find("bat",1,true)
        or tool.Name:lower():find("bat",1,true)
    )
end

local function batInfo()
    local out={}
    for _,pair in ipairs({
        {LP.Character,"Character"},
        {LP:FindFirstChildOfClass("Backpack"),"Backpack"}
    }) do
        local box,where=pair[1],pair[2]
        if box then
            for _,tool in ipairs(box:GetChildren()) do
                if isBat(tool) then
                    local row={
                        where=where,name=tool.Name,attrs=attrs(tool),enabled=tool.Enabled,
                        descendants={}
                    }
                    for _,d in ipairs(tool:GetDescendants()) do
                        if d:IsA("LocalScript") or d:IsA("ModuleScript") or d:IsA("Animation")
                            or d:IsA("RemoteEvent") or d:IsA("RemoteFunction") or d:IsA("ValueBase") then
                            row.descendants[#row.descendants+1]={
                                name=d.Name,class=d.ClassName,path=full(d),attrs=attrs(d)
                            }
                        end
                    end
                    out[#out+1]=row
                end
            end
        end
    end
    return out
end

local function watchBatActivations()
    local function attach(box,where)
        if not box then return end
        local function one(tool)
            if not isBat(tool) then return end
            conns[#conns+1]=tool.Activated:Connect(function()
                if state.active then
                    push("bat_activated",{where=where,name=tool.Name,attrs=attrs(tool)})
                end
            end)
        end
        for _,x in ipairs(box:GetChildren()) do one(x) end
        conns[#conns+1]=box.ChildAdded:Connect(one)
    end
    attach(LP:FindFirstChildOfClass("Backpack"),"Backpack")
    if LP.Character then attach(LP.Character,"Character") end
    conns[#conns+1]=LP.CharacterAdded:Connect(function(ch) attach(ch,"Character") end)
end

local function interestingName(s)
    s=tostring(s or ""):lower()
    return s:find("drone",1,true)
        or s:find("scramble",1,true)
        or s:find("brock",1,true)
        or s:find("mob",1,true)
        or s:find("enemy",1,true)
        or s:find("monster",1,true)
end

local function rootPart(inst)
    if inst:IsA("BasePart") then return inst end
    if inst:IsA("Model") then return inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart",true) end
    return nil
end

local function nearEventObjects(radius)
    radius=radius or 220
    local out={}
    local ch=LP.Character
    local pr=ch and (ch:FindFirstChild("HumanoidRootPart") or ch.PrimaryPart)
    if not pr then return out end

    for _,inst in ipairs(Workspace:GetDescendants()) do
        if inst:IsA("Model") or inst:IsA("Folder") then
            local r=rootPart(inst)
            local dist=r and (r.Position-pr.Position).Magnitude or nil
            if (dist and dist<=radius) or interestingName(inst.Name) then
                local row={
                    name=inst.Name,class=inst.ClassName,path=full(inst),
                    distance=dist,attrs=attrs(inst),tags={}
                }
                local ok,tags=pcall(CollectionService.GetTags,CollectionService,inst)
                if ok then row.tags=tags end
                row.children={}
                local n=0
                for _,d in ipairs(inst:GetDescendants()) do
                    n+=1
                    if n>100 then break end
                    if d:IsA("ValueBase") or d:IsA("BillboardGui") or d:IsA("SurfaceGui")
                        or d:IsA("ProximityPrompt") or d:IsA("ClickDetector") then
                        local x={name=d.Name,class=d.ClassName,path=full(d),attrs=attrs(d)}
                        if d:IsA("ValueBase") then pcall(function() x.value=simple(d.Value) end) end
                        if d:IsA("BillboardGui") or d:IsA("SurfaceGui") then
                            x.texts={}
                            for _,g in ipairs(d:GetDescendants()) do
                                if g:IsA("TextLabel") or g:IsA("TextButton") then
                                    x.texts[#x.texts+1]=g.Text
                                    if #x.texts>=20 then break end
                                end
                            end
                        end
                        row.children[#row.children+1]=x
                    end
                end
                out[#out+1]=row
                if #out>=350 then break end
            end
        end
    end

    table.sort(out,function(a,b)
        return (a.distance or 1e9)<(b.distance or 1e9)
    end)
    return out
end

local function playerPos()
    local c=LP.Character
    local r=c and (c:FindFirstChild("HumanoidRootPart") or c.PrimaryPart)
    return r and simple(r.Position) or nil
end

local function snapshot(label)
    return {
        label=label,
        unix=os.time(),
        playerPos=playerPos(),
        bats=batInfo(),
        nearby=nearEventObjects(240),
        modules=state.moduleInfo,
        remotes=(function()
            local out={}
            for n,r in pairs(targetRemotes) do out[#out+1]={name=n,path=full(r),class=r.ClassName} end
            table.sort(out,function(a,b)return a.name<b.name end)
            return out
        end)(),
    }
end

connectInbound()
watchBatActivations()
inspectModules()

local root=(function()
    local ok,h=pcall(function() return gethui and gethui() end)
    return (ok and h) or CoreGui
end)()

local gui=Instance.new("ScreenGui")
gui.Name="PsicoEventMobScannerV2"
gui.ResetOnSpawn=false
gui.IgnoreGuiInset=true
gui.Parent=root

local vp=Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize or Vector2.new(1280,720)
local w=math.clamp(math.floor(vp.X*.64),560,850)
local h=math.clamp(math.floor(vp.Y*.58),330,470)

local main=Instance.new("Frame")
main.Size=UDim2.fromOffset(w,h)
main.Position=UDim2.new(.5,-w/2,.5,-h/2)
main.BackgroundColor3=Color3.fromRGB(10,20,38)
main.BorderSizePixel=0
main.Parent=gui
Instance.new("UICorner",main).CornerRadius=UDim.new(0,18)

local header=Instance.new("Frame")
header.Size=UDim2.new(1,0,0,54)
header.BackgroundTransparency=1
header.Active=true
header.Parent=main

local title=Instance.new("TextLabel")
title.BackgroundTransparency=1
title.Position=UDim2.fromOffset(18,8)
title.Size=UDim2.new(1,-90,0,38)
title.Font=Enum.Font.GothamBold
title.Text="EVENT MOB FARM SCANNER • V2"
title.TextSize=21
title.TextColor3=Color3.fromRGB(245,248,255)
title.TextXAlignment=Enum.TextXAlignment.Left
title.Parent=header

local close=Instance.new("TextButton")
close.Size=UDim2.fromOffset(48,38)
close.Position=UDim2.new(1,-60,0,8)
close.BackgroundColor3=Color3.fromRGB(35,44,61)
close.Text="×"
close.TextSize=22
close.TextColor3=Color3.new(1,1,1)
close.Font=Enum.Font.GothamBold
close.Parent=header
Instance.new("UICorner",close).CornerRadius=UDim.new(0,10)

local status=Instance.new("TextLabel")
status.BackgroundColor3=Color3.fromRGB(16,34,58)
status.BorderSizePixel=0
status.Position=UDim2.fromOffset(18,64)
status.Size=UDim2.new(1,-36,0,118)
status.Font=Enum.Font.Code
status.TextSize=14
status.TextColor3=Color3.fromRGB(220,230,245)
status.TextWrapped=true
status.TextXAlignment=Enum.TextXAlignment.Left
status.TextYAlignment=Enum.TextYAlignment.Top
status.Text="V2 pronto. Vá até os mobs do evento.\nINICIAR → bata manualmente em 2–3 mobs → FINALIZAR → EXPORTAR."
status.Parent=main
Instance.new("UICorner",status).CornerRadius=UDim.new(0,12)

local function button(text,x,y,wid,cb)
    local b=Instance.new("TextButton")
    b.Size=UDim2.new(wid,-8,0,48)
    b.Position=UDim2.new(x,18,y,0)
    b.BackgroundColor3=Color3.fromRGB(42,91,151)
    b.TextColor3=Color3.new(1,1,1)
    b.Text=text
    b.TextSize=16
    b.Font=Enum.Font.GothamBold
    b.Parent=main
    Instance.new("UICorner",b).CornerRadius=UDim.new(0,10)
    b.Activated:Connect(cb)
    return b
end

button("INICIAR",0,.56,.5,function()
    state.events={}
    inspectModules()
    state.before=snapshot("before")
    local hooked=installOutgoingHook()
    state.active=true
    status.Text=("CAPTURA ATIVA\nHook de saída: %s | Scramble remotes: %d\nAgora bata manualmente em 2–3 mobs e depois FINALIZAR."):format(
        hooked and "SIM" or "NÃO",
        (function() local n=0 for k in pairs(targetRemotes) do if k:find("Scramble",1,true) then n+=1 end end return n end)()
    )
end)

button("FINALIZAR",.5,.56,.5,function()
    state.active=false
    state.after=snapshot("after")
    uninstallOutgoingHook()
    local rin,rout,bat=0,0,0
    for _,e in ipairs(state.events) do
        if e.kind=="remote_in" then rin+=1 end
        if e.kind=="remote_out" then rout+=1 end
        if e.kind=="bat_activated" then bat+=1 end
    end
    status.Text=("FINALIZADO\nRemote IN:%d | Remote OUT:%d | Bat Activated:%d | Eventos:%d\nAgora EXPORTAR JSON."):format(rin,rout,bat,#state.events)
end)

button("EXPORTAR JSON",0,.74,.62,function()
    if not state.before then status.Text="Use INICIAR primeiro." return end
    if state.active then state.active=false uninstallOutgoingHook() end
    if not state.after then state.after=snapshot("after_auto") end

    local payload={
        scanner="Psico Event Mob Farm Scanner V2",
        placeId=game.PlaceId,gameId=game.GameId,
        startedUnix=state.startedUnix,
        hookSupported=state.hookSupported,
        before=state.before,after=state.after,
        moduleInfo=state.moduleInfo,
        events=state.events,
    }

    local ok,json=pcall(HttpService.JSONEncode,HttpService,payload)
    if not ok then status.Text="Erro JSON: "..tostring(json) return end
    local name="Psico_EventMobFarm_V2_"..os.time()..".json"
    if writefile then
        local ok2,err=pcall(writefile,name,json)
        status.Text=ok2 and ("Exportado: "..name) or ("writefile falhou: "..tostring(err))
    elseif setclipboard then
        pcall(setclipboard,json)
        status.Text="JSON copiado."
    else
        status.Text="Sem writefile/setclipboard."
    end
end)

button("SNAPSHOT",.62,.74,.38,function()
    local s=snapshot("manual")
    push("manual_snapshot",s)
    status.Text=("Snapshot: %d objetos próximos | %d módulos inspecionados"):format(#s.nearby,#state.moduleInfo)
end)

-- Mobile-friendly drag.
do
    local dragging=false
    local dragStart,startPos
    header.InputBegan:Connect(function(input)
        if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
            dragging=true dragStart=input.Position startPos=main.Position
        end
    end)
    header.InputEnded:Connect(function(input)
        if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
            dragging=false
        end
    end)
    conns[#conns+1]=UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType==Enum.UserInputType.MouseMovement or input.UserInputType==Enum.UserInputType.Touch) then
            local d=input.Position-dragStart
            main.Position=UDim2.new(startPos.X.Scale,startPos.X.Offset+d.X,startPos.Y.Scale,startPos.Y.Offset+d.Y)
        end
    end)
end

local function cleanup()
    state.active=false
    uninstallOutgoingHook()
    for _,c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    table.clear(conns)
    pcall(function() gui:Destroy() end)
    if _G.PSICO_EVENT_MOB_SCANNER_CLEANUP==cleanup then
        _G.PSICO_EVENT_MOB_SCANNER_CLEANUP=nil
    end
end

close.Activated:Connect(cleanup)
_G.PSICO_EVENT_MOB_SCANNER_CLEANUP=cleanup

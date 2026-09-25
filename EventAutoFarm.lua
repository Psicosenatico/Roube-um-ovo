-- PSICOSENATICO | EVENT AUTO FARM TEST V1
-- Dr. Scramble: targets local drone visuals and uses the equipped bat's normal Activate flow.

if _G.PSICO_EVENT_AUTOFARM_CLEANUP then
    pcall(_G.PSICO_EVENT_AUTOFARM_CLEANUP)
end

local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local WS=game:GetService("Workspace")
local RunService=game:GetService("RunService")
local CoreGui=game:GetService("CoreGui")

local LP=Players.LocalPlayer
local CFG={
    Enabled=false,
    Priority="Rarest",
    Augmented=true,
    Reactor=true,
    Scrap=true,
    OnlyDuringEvent=true,
    AttackDelay=.12,
    FollowDistance=3,
    FlySpeed=500,
    SafetyEnabled=true,
    RetreatHealthPct=.70,
    ResumeHealthPct=.90,
}
-- Published AttackDrone navigation constants.
local ATTACK_RANGE=16
local ATTACK_INTERVAL=.05
local FOLLOW_SPEED=500
local FOLLOW_BEHIND_DISTANCE=3
local SHORT_TP_DISTANCE=20
local SPAWNS={Vector3.new(2140,77,-367),Vector3.new(5723,77,-376)}
local SAFE_ZONE=Vector3.new(533,70,-366)
local POINT_1=Vector3.new(559,70,-370)
local SAFE_WAIT_TIME=1
local SPAWN_WAIT_TIME=2
local ARRIVE_TIMEOUT=15
local PRIORITY={AugmentedDrone=1,ReactorDrone=2,ScrapDrone=3}
local PREFIXES={"DroneVisual_","PersonalDrone_"}
local state={
    token=0,target=nil,kills=0,attacks=0,spawnIndex=1,movers={},
    lastError=nil,lock=nil,damageTaken=false,lastHealth=nil,healthConn=nil,
    retreats=0
}
local conns={}

local function humRoot()
    local c=LP.Character
    if not c then return nil,nil end
    return c:FindFirstChildOfClass("Humanoid"),c:FindFirstChild("HumanoidRootPart") or c.PrimaryPart
end

local function healthRatio()
    local h=select(1,humRoot())
    if not h or h.MaxHealth<=0 then return 0 end
    return h.Health/h.MaxHealth
end

local function bindDamageWatch()
    if state.healthConn then
        pcall(function() state.healthConn:Disconnect() end)
        state.healthConn=nil
    end
    local h=select(1,humRoot())
    if not h then return end
    state.lastHealth=h.Health
    state.damageTaken=false
    state.healthConn=h.HealthChanged:Connect(function(v)
        local old=state.lastHealth
        state.lastHealth=v
        if CFG.Enabled and CFG.SafetyEnabled and old and v<old then
            local max=math.max(1,h.MaxHealth)
            if (old-v)/max>=.08 or v/max<=CFG.RetreatHealthPct then
                state.damageTaken=true
            end
        end
    end)
end

local function isBat(t)
    return t and t:IsA("Tool") and (
        t:GetAttribute("IsBat")==true
        or tostring(t:GetAttribute("GearName") or ""):lower():find("bat",1,true)
        or t.Name:lower():find("bat",1,true)
    )
end

local function equipBat()
    local c=LP.Character
    if c then
        for _,x in ipairs(c:GetChildren()) do if isBat(x) then return x end end
    end
    local bp=LP:FindFirstChildOfClass("Backpack")
    if bp then
        for _,x in ipairs(bp:GetChildren()) do
            if isBat(x) then
                local h=select(1,humRoot())
                if not h then return nil end
                local ok=pcall(function() h:EquipTool(x) end)
                if ok then task.wait(.08) return x end
            end
        end
    end
end

local function eventInfo()
    local ok,t=pcall(function()
        return LP.PlayerGui.HUD.GameHUD.BottomRight.ExperimentTimer.Value.Text
    end)
    t=ok and tostring(t or "") or ""
    local active=t:find("Event ends",1,true)~=nil
    local m=tonumber(t:match("(%d+)m")) or 0
    local sec=tonumber(t:match("(%d+)s")) or 0
    return active,(m*60+sec),t
end

local function eventShouldFarm()
    if not CFG.OnlyDuringEvent then return true end
    local active,sec=eventInfo()
    -- Same cutoff used by the published ManagerDrone.
    return active and sec>10
end

local function isDrone(x)
    if not x then return false end
    for _,p in ipairs(PREFIXES) do
        if x.Name:sub(1,#p)==p then return true end
    end
    return false
end

local function pos(x)
    if not x then return nil end
    if x:IsA("BasePart") then return x.Position end
    if x:IsA("Model") then
        local p=x.PrimaryPart or x:FindFirstChildWhichIsA("BasePart",true)
        return p and p.Position
    end
end

local function look(x)
    if not x then return Vector3.new(0,0,-1) end
    local p=x:IsA("BasePart") and x or (x:IsA("Model") and (x.PrimaryPart or x:FindFirstChildWhichIsA("BasePart",true)))
    return p and p.CFrame.LookVector or Vector3.new(0,0,-1)
end

local function allowed(tier)
    if tier=="AugmentedDrone" then return CFG.Augmented end
    if tier=="ReactorDrone" then return CFG.Reactor end
    if tier=="ScrapDrone" then return CFG.Scrap end
    return false
end

local function drones()
    local c=WS:FindFirstChild("ScrambleLocalVisuals")
    local out={}
    if not c then return out end
    local currentSpawn=SPAWNS[state.spawnIndex] or SPAWNS[1]
    local _,root=humRoot()
    if not root then return out end
    for _,x in ipairs(c:GetChildren()) do
        local tier=x:GetAttribute("ScrambleTier")
        local p=pos(x)
        if isDrone(x) and p and PRIORITY[tier] and allowed(tier) then
            out[#out+1]={
                obj=x,tier=tier,p=p,
                d=(p-root.Position).Magnitude,
                spawnDist=math.floor((p-currentSpawn).Magnitude),
                pri=PRIORITY[tier]
            }
        end
    end
    table.sort(out,function(a,b)
        if CFG.Priority=="Closest" then
            if math.abs(a.d-b.d)>.05 then return a.d<b.d end
            return a.pri<b.pri
        end
        -- Published behavior: rarity/tier first, then distance from the
        -- currently selected event spawn (not distance from the player).
        if a.pri~=b.pri then return a.pri<b.pri end
        return a.spawnDist<b.spawnDist
    end)
    return out
end

local function cleanupMove()
    if state.lock then
        pcall(function() state.lock:Disconnect() end)
        state.lock=nil
    end
    for _,x in ipairs(state.movers) do
        if typeof(x)=="Instance" then
            pcall(function()
                if x:IsA("BodyVelocity") then x.Velocity=Vector3.zero x.MaxForce=Vector3.zero end
                if x:IsA("BodyGyro") then x.MaxTorque=Vector3.zero end
                x:Destroy()
            end)
        end
    end
    table.clear(state.movers)
    local h,r=humRoot()
    if h then pcall(function() h.PlatformStand=false h.Sit=false end) end
    if r then pcall(function() r.AssemblyLinearVelocity=Vector3.zero r.AssemblyAngularVelocity=Vector3.zero end) end
end

local function fly(dest,token,stopDist,timeout)
    cleanupMove()
    local h,r=humRoot()
    if not h or not r or h.Health<=0 then return false end
    h.PlatformStand=true

    local bv=Instance.new("BodyVelocity")
    bv.Name="YokudoBV"
    bv.MaxForce=Vector3.new(math.huge,math.huge,math.huge)
    bv.P=1250
    bv.Velocity=Vector3.zero
    bv.Parent=r

    local bg=Instance.new("BodyGyro")
    bg.Name="YokudoBG"
    bg.MaxTorque=Vector3.new(math.huge,math.huge,math.huge)
    bg.P=3000
    bg.D=500
    bg.CFrame=r.CFrame
    bg.Parent=r
    state.movers={bv,bg}

    local started=os.clock()
    local arrive=stopDist or 2
    local limit=timeout or ARRIVE_TIMEOUT
    while CFG.Enabled and state.token==token and r.Parent and h.Health>0 do
        local delta=dest-r.Position
        local dist=math.floor(delta.Magnitude)
        if dist<=arrive then
            bv.Velocity=Vector3.zero
            bv.MaxForce=Vector3.zero
            bg.MaxTorque=Vector3.zero
            task.wait(.1)
            cleanupMove()
            local _,root=humRoot()
            if root then
                pcall(function()
                    root.CFrame=CFrame.new(dest)
                    root.AssemblyLinearVelocity=Vector3.zero
                    root.AssemblyAngularVelocity=Vector3.zero
                end)
            end
            return true
        end
        if os.clock()-started>limit then cleanupMove() return false end
        if delta.Magnitude>.01 then
            bv.Velocity=delta.Unit*FOLLOW_SPEED
            bg.CFrame=CFrame.new(r.Position,dest)
        end
        RunService.Heartbeat:Wait()
    end
    cleanupMove()
    return false
end

local function behind(target)
    local p=pos(target)
    if not p then return nil end
    local b=p-look(target)*FOLLOW_BEHIND_DISTANCE
    return Vector3.new(b.X,p.Y+1,b.Z)
end

local function lockBehind(target,token)
    cleanupMove()
    state.lock=RunService.Heartbeat:Connect(function()
        if not CFG.Enabled or state.token~=token or not target or not target.Parent then
            if state.lock then pcall(function() state.lock:Disconnect() end) state.lock=nil end
            return
        end
        local _,r=humRoot()
        local tp=pos(target)
        local bp=behind(target)
        if r and tp and bp then
            pcall(function()
                r.CFrame=CFrame.new(bp,tp)
                r.AssemblyLinearVelocity=Vector3.zero
                r.AssemblyAngularVelocity=Vector3.zero
            end)
        end
    end)
end

local function attack(info,token)
    local target=info and info.obj
    if not target or not target.Parent then return end
    state.target=target

    local tool=equipBat()
    if not tool then
        state.lastError="Nenhum bastão encontrado"
        task.wait(.5)
        state.target=nil
        return
    end

    while CFG.Enabled and state.token==token and target.Parent do
        local h,r=humRoot()
        local tp=pos(target)
        local bp=behind(target)
        if not h or not r or h.Health<=0 or not tp or not bp then break end

        local totalDist=math.floor((bp-r.Position).Magnitude)
        if totalDist>SHORT_TP_DISTANCE then
            fly(bp,token,2,ARRIVE_TIMEOUT)
        else
            cleanupMove()
            pcall(function()
                r.CFrame=CFrame.new(bp,tp)
                r.AssemblyLinearVelocity=Vector3.zero
                r.AssemblyAngularVelocity=Vector3.zero
            end)
            lockBehind(target,token)

            -- Keep the normal Tool activation in our build. Navigation and
            -- follow behavior now match the published implementation.
            local ok=pcall(function() tool:Activate() end)
            if ok then state.attacks+=1 end
            task.wait(ATTACK_INTERVAL)
        end
    end

    cleanupMove()
    if not target.Parent then state.kills+=1 end
    state.target=nil
end

local function loop(token)
    state.lastError=nil
    state.spawnIndex=1
    local routeReady=false

    while CFG.Enabled and state.token==token do
        local h=select(1,humRoot())
        if not h or h.Health<=0 then
            cleanupMove()
            routeReady=false
            task.wait(.5)
            continue
        end

        -- Published ManagerDrone does not start AttackDrone at all until
        -- the event is active and has more than 10 seconds remaining.
        if not eventShouldFarm() then
            cleanupMove()
            routeReady=false
            task.wait(.6)
            continue
        end

        if not routeReady then
            local _,initialRoot=humRoot()
            if initialRoot and math.floor(initialRoot.Position.X-POINT_1.X)<=0 then
                state.lastError="Rota segura inicial..."
                fly(SAFE_ZONE,token,2,ARRIVE_TIMEOUT)
                if not CFG.Enabled or state.token~=token then cleanupMove() return end
                task.wait(SAFE_WAIT_TIME)
                state.lastError=nil
            end
            state.spawnIndex=1
            routeReady=true
        end

        local list=drones()
        if list[1] then
            attack(list[1],token)
            state.spawnIndex=1
        else
            fly(SPAWNS[state.spawnIndex],token,2,ARRIVE_TIMEOUT)
            if not CFG.Enabled or state.token~=token then break end
            if not eventShouldFarm() then
                routeReady=false
                cleanupMove()
                continue
            end

            task.wait(SPAWN_WAIT_TIME)
            local after=drones()
            if after[1] then
                attack(after[1],token)
                state.spawnIndex=1
            else
                state.spawnIndex=state.spawnIndex==1 and 2 or 1
            end
            task.wait(.2)
        end
    end
    cleanupMove()
end

local function start()
    if CFG.Enabled then return end
    CFG.Enabled=true
    state.token+=1
    local token=state.token
    task.spawn(function() loop(token) end)
end

local function stop()
    CFG.Enabled=false
    state.token+=1
    state.target=nil
    cleanupMove()
end

local function round(o,r)
    local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0,r or 8); c.Parent=o
end
local function button(p,t,posi,size)
    local b=Instance.new("TextButton")
    b.BackgroundColor3=Color3.fromRGB(35,44,61); b.BorderSizePixel=0
    b.Position=posi; b.Size=size; b.Font=Enum.Font.GothamMedium
    b.Text=t; b.TextSize=9; b.TextColor3=Color3.fromRGB(242,246,255); b.Parent=p; round(b,8)
    return b
end
local function label(p,t,posi,size,ts)
    local l=Instance.new("TextLabel")
    l.BackgroundTransparency=1; l.Position=posi; l.Size=size; l.Font=Enum.Font.Gotham
    l.Text=t; l.TextSize=ts or 8; l.TextColor3=Color3.fromRGB(220,228,242)
    l.TextXAlignment=Enum.TextXAlignment.Left; l.TextYAlignment=Enum.TextYAlignment.Center; l.Parent=p
    return l
end

local root=(function()
    local ok,h=pcall(function() return gethui and gethui() end)
    return (ok and h) or CoreGui
end)()
local gui,main
for _,g in ipairs(root:GetChildren()) do
    if g:IsA("ScreenGui") and g.Name:find("PsicoRoubeUmOvo",1,true)==1 then
        gui=g; main=g:FindFirstChild("Main"); if main then break end
    end
end
if not main then error("main panel not found") end

local function findText(t)
    for _,d in ipairs(main:GetDescendants()) do
        if (d:IsA("TextButton") or d:IsA("TextLabel")) and d.Text==t then return d end
    end
end

local fun=findText("FUNÇÕES")
local filters=findText("FILTROS ESP")
local inv=findText("OVOS INVENTÁRIO")
local base=findText("ESP BASE")
local normal=findText("ESP • Ovos  ON") or findText("ESP • Ovos ON") or findText("ESP • Ovos  OFF") or findText("ESP • Ovos OFF") or findText("ESP • Ovos")
if not(fun and filters and inv and base and normal) then error("event farm anchors not found") end

local sidebar=base.Parent
local host=normal.Parent.Parent
local gap=inv.Position.Y.Offset-filters.Position.Y.Offset-filters.Size.Y.Offset
if gap<0 or gap>80 then gap=8 end

local tab=button(sidebar,"AUTO FARM",UDim2.new(base.Position.X.Scale,base.Position.X.Offset,base.Position.Y.Scale,base.Position.Y.Offset+base.Size.Y.Offset+gap),base.Size)

local page=Instance.new("ScrollingFrame")
page.Name="EventAutoFarmPage"; page.BackgroundTransparency=1; page.BorderSizePixel=0
page.Position=normal.Parent.Position; page.Size=normal.Parent.Size; page.AnchorPoint=normal.Parent.AnchorPoint
page.Visible=false; page.ScrollBarThickness=3; page.CanvasSize=UDim2.fromOffset(0,300); page.Parent=host

local y=0
local enable=button(page,"AUTO FARM: OFF",UDim2.fromOffset(0,y),UDim2.new(1,-4,0,32)); y+=38
local status=label(page,"Aguardando...",UDim2.fromOffset(4,y),UDim2.new(1,-8,0,52),8); status.TextWrapped=true; status.TextYAlignment=Enum.TextYAlignment.Top; y+=56
local priority=button(page,"Prioridade: Raros primeiro",UDim2.fromOffset(0,y),UDim2.new(1,-4,0,28)); y+=34
local only=button(page,"Somente durante evento: ON",UDim2.fromOffset(0,y),UDim2.new(1,-4,0,28)); y+=38
label(page,"Tipos de drone",UDim2.fromOffset(2,y),UDim2.new(1,-4,0,18),8); y+=22
local aug=button(page,"Augmented: ON",UDim2.fromOffset(0,y),UDim2.new(1/3,-4,0,28))
local rea=button(page,"Reactor: ON",UDim2.new(1/3,2,0,y),UDim2.new(1/3,-4,0,28))
local scr=button(page,"Scrap: ON",UDim2.new(2/3,4,0,y),UDim2.new(1/3,-8,0,28)); y+=34
local reset=button(page,"PARAR / RESETAR",UDim2.fromOffset(0,y),UDim2.new(1,-4,0,30)); y+=36
page.CanvasSize=UDim2.fromOffset(0,y)

local function bs(btn,on,prefix)
    btn.Text=prefix..(on and "ON" or "OFF")
    btn.BackgroundColor3=on and Color3.fromRGB(42,91,190) or Color3.fromRGB(35,44,61)
end
local function refresh()
    bs(enable,CFG.Enabled,"AUTO FARM: ")
    priority.Text=CFG.Priority=="Rarest" and "Prioridade: Raros primeiro" or "Prioridade: Mais próximo"
    bs(only,CFG.OnlyDuringEvent,"Somente durante evento: ")
    bs(aug,CFG.Augmented,"Augmented: "); bs(rea,CFG.Reactor,"Reactor: "); bs(scr,CFG.Scrap,"Scrap: ")
end

conns[#conns+1]=tab.Activated:Connect(function()
    for _,x in ipairs(host:GetChildren()) do if x:IsA("GuiObject") then x.Visible=(x==page) end end
    page.Visible=true; tab.BackgroundColor3=Color3.fromRGB(42,91,190)
end)
for _,x in ipairs({fun,filters,inv,base}) do
    conns[#conns+1]=x.Activated:Connect(function() page.Visible=false; tab.BackgroundColor3=Color3.fromRGB(35,44,61) end)
end
conns[#conns+1]=enable.Activated:Connect(function() if CFG.Enabled then stop() else start() end refresh() end)
conns[#conns+1]=priority.Activated:Connect(function() CFG.Priority=CFG.Priority=="Rarest" and "Closest" or "Rarest"; refresh() end)
conns[#conns+1]=only.Activated:Connect(function() CFG.OnlyDuringEvent=not CFG.OnlyDuringEvent; refresh() end)
conns[#conns+1]=aug.Activated:Connect(function() CFG.Augmented=not CFG.Augmented; refresh() end)
conns[#conns+1]=rea.Activated:Connect(function() CFG.Reactor=not CFG.Reactor; refresh() end)
conns[#conns+1]=scr.Activated:Connect(function() CFG.Scrap=not CFG.Scrap; refresh() end)
conns[#conns+1]=reset.Activated:Connect(function() stop(); state.kills=0; state.attacks=0; state.lastError=nil; refresh() end)
conns[#conns+1]=LP.CharacterAdded:Connect(function()
    if CFG.Enabled then
        state.token+=1; cleanupMove()
        local t=state.token
        task.delay(1,function() if CFG.Enabled and state.token==t then task.spawn(function() loop(t) end) end end)
    end
end)

task.spawn(function()
    while page.Parent do
        task.wait(.25)
        local active,txt=eventInfo()
        local list=drones()
        local tier=state.target and state.target:GetAttribute("ScrambleTier")
        local target=state.target and ((tier or "?").." • "..state.target.Name) or "nenhum"
        status.Text=state.lastError and ("ERRO: "..state.lastError) or string.format(
            "Evento: %s\nDrones visíveis: %d • Alvo: %s\nAtaques: %d • Eliminados: %d",
            txt~="" and txt or (active and "ativo" or "não detectado"),#list,target,state.attacks,state.kills
        )
        refresh()
    end
end)

local function cleanup()
    stop()
    for _,c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    pcall(function() page:Destroy() end); pcall(function() tab:Destroy() end)
    if _G.PSICO_EVENT_AUTOFARM_CLEANUP==cleanup then _G.PSICO_EVENT_AUTOFARM_CLEANUP=nil end
end
_G.PSICO_EVENT_AUTOFARM_CLEANUP=cleanup
refresh()

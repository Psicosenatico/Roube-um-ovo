-- PSICOSENATICO | EVENT MOB FARM SCANNER V1
-- Scanner leve e passivo para mapear mobs/evento/arma antes do Auto Farm.
-- Nao usa __namecall, hookfunction, getgc, decompile ou interceptacao global.

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
local watchedHealth = {}
local state = {
    active = false,
    startedUnix = os.time(),
    events = {},
    candidates = {},
    relevantRemotes = {},
    relevantModules = {},
    bat = {},
    startSnapshot = nil,
    endSnapshot = nil,
}

local TERMS = {
    "mob","enemy","npc","boss","event","rift","scramble","sakura","bloom",
    "hit","damage","attack","bat","combat","health","hp","monster","crystal"
}

local HEALTH_NAMES = {
    Health=true, HP=true, Hp=true, HitPoints=true, Hitpoints=true,
    Life=true, Lives=true, CurrentHealth=true, MaxHealth=true,
}

local function pushEvent(kind, data)
    local e = {
        t = os.clock(),
        unix = os.time(),
        kind = kind,
        data = data,
    }
    state.events[#state.events+1] = e
    if #state.events > 3000 then
        table.remove(state.events, 1)
    end
end

local function safeFullName(inst)
    local ok, v = pcall(function() return inst:GetFullName() end)
    return ok and v or tostring(inst)
end

local function serial(v)
    local tv = typeof(v)
    if tv == "nil" or tv == "boolean" or tv == "string" or tv == "number" then return v end
    if tv == "Vector3" then return {x=v.X,y=v.Y,z=v.Z} end
    if tv == "CFrame" then
        local p = v.Position
        return {x=p.X,y=p.Y,z=p.Z}
    end
    if tv == "Color3" then return {r=v.R,g=v.G,b=v.B} end
    if tv == "Instance" then
        return {class=v.ClassName,name=v.Name,path=safeFullName(v)}
    end
    return tostring(v)
end

local function attrs(inst)
    local out = {}
    local ok, a = pcall(function() return inst:GetAttributes() end)
    if ok and type(a) == "table" then
        for k,v in pairs(a) do out[k] = serial(v) end
    end
    return out
end

local function lower(s)
    return string.lower(tostring(s or ""))
end

local function matchesTerm(s)
    s = lower(s)
    for _,term in ipairs(TERMS) do
        if s:find(term,1,true) then return true, term end
    end
    return false
end

local function rootOf(model)
    if not model then return nil end
    if model:IsA("BasePart") then return model end
    if model:IsA("Model") then
        return model:FindFirstChild("HumanoidRootPart")
            or model.PrimaryPart
            or model:FindFirstChildWhichIsA("BasePart", true)
    end
    return nil
end

local function healthObject(model)
    if not model then return nil,nil,nil end

    local hum = model:FindFirstChildOfClass("Humanoid")
    if hum then return hum, tonumber(hum.Health), tonumber(hum.MaxHealth) end

    for _,d in ipairs(model:GetDescendants()) do
        if d:IsA("ValueBase") and HEALTH_NAMES[d.Name] then
            local v = tonumber(d.Value)
            if v then
                local mx = tonumber(d:GetAttribute("Max"))
                    or tonumber(d:GetAttribute("MaxHealth"))
                    or v
                return d, v, mx
            end
        end
    end

    for _,key in ipairs({"Health","HP","Hp","HitPoints","Life","CurrentHealth"}) do
        local v = tonumber(model:GetAttribute(key))
        if v then
            local mx = tonumber(model:GetAttribute("MaxHealth"))
                or tonumber(model:GetAttribute("MaxHP"))
                or v
            return model, v, mx
        end
    end

    return nil,nil,nil
end

local function currentHealth(model)
    local obj,h,m = healthObject(model)
    return obj,h,m
end

local function modelTags(model)
    local out = {}
    local ok, tags = pcall(CollectionService.GetTags, CollectionService, model)
    if ok and type(tags) == "table" then
        for _,t in ipairs(tags) do out[#out+1] = t end
    end
    table.sort(out)
    return out
end

local function childSummary(model)
    local out = {}
    local n = 0
    for _,d in ipairs(model:GetDescendants()) do
        n += 1
        if n > 80 then break end
        if d:IsA("Humanoid") or d:IsA("ValueBase") or d:IsA("ProximityPrompt")
            or d:IsA("ClickDetector") or d:IsA("Animation")
            or d:IsA("RemoteEvent") or d:IsA("RemoteFunction") then
            local r = {name=d.Name,class=d.ClassName,path=safeFullName(d)}
            if d:IsA("ValueBase") then
                pcall(function() r.value = serial(d.Value) end)
            elseif d:IsA("ProximityPrompt") then
                r.actionText = d.ActionText
                r.objectText = d.ObjectText
                r.hold = d.HoldDuration
            end
            out[#out+1] = r
        end
    end
    return out
end

local function candidateRow(model)
    local _,h,mx = currentHealth(model)
    local root = rootOf(model)
    return {
        name = model.Name,
        class = model.ClassName,
        path = safeFullName(model),
        health = h,
        maxHealth = mx,
        attrs = attrs(model),
        tags = modelTags(model),
        pos = root and serial(root.Position) or nil,
        children = childSummary(model),
    }
end

local function isCandidateModel(inst)
    if not inst:IsA("Model") then return false end
    if LP.Character and inst == LP.Character then return false end
    for _,p in ipairs(Players:GetPlayers()) do
        if p.Character == inst then return false end
    end

    local obj,h,mx = currentHealth(inst)
    if obj then
        if h and mx and mx <= 100 then return true end
        local hit = matchesTerm(inst.Name)
        if hit then return true end
    end

    if matchesTerm(inst.Name) then
        local root = rootOf(inst)
        if root then return true end
    end

    return false
end

local function watchCandidate(model)
    if watchedHealth[model] then return end
    if not isCandidateModel(model) then return end
    watchedHealth[model] = true

    local key = safeFullName(model)
    state.candidates[key] = candidateRow(model)
    pushEvent("candidate_seen", state.candidates[key])

    local obj,h = healthObject(model)
    if obj then
        if obj:IsA("Humanoid") then
            local last = tonumber(obj.Health)
            local c = obj.HealthChanged:Connect(function(v)
                if not state.active then return end
                local nv = tonumber(v)
                pushEvent("health_changed", {
                    path=safeFullName(model),
                    name=model.Name,
                    from=last,
                    to=nv,
                })
                last = nv
            end)
            conns[#conns+1] = c

            local d = obj.Died:Connect(function()
                if state.active then
                    pushEvent("mob_died", {
                        path=safeFullName(model),
                        name=model.Name,
                    })
                end
            end)
            conns[#conns+1] = d
        elseif obj:IsA("ValueBase") then
            local last = tonumber(obj.Value)
            local c = obj.Changed:Connect(function(v)
                if not state.active then return end
                local nv = tonumber(v)
                pushEvent("health_value_changed", {
                    path=safeFullName(model),
                    valuePath=safeFullName(obj),
                    name=model.Name,
                    from=last,
                    to=nv,
                })
                last = nv
            end)
            conns[#conns+1] = c
        else
            local last = tonumber(h)
            for _,keyName in ipairs({"Health","HP","Hp","HitPoints","Life","CurrentHealth"}) do
                if model:GetAttribute(keyName) ~= nil then
                    local c = model:GetAttributeChangedSignal(keyName):Connect(function()
                        if not state.active then return end
                        local nv = tonumber(model:GetAttribute(keyName))
                        pushEvent("health_attr_changed", {
                            path=safeFullName(model),
                            attr=keyName,
                            name=model.Name,
                            from=last,
                            to=nv,
                        })
                        last = nv
                    end)
                    conns[#conns+1] = c
                end
            end
        end
    end

    local anc = model.AncestryChanged:Connect(function(_,parent)
        if state.active and parent == nil then
            pushEvent("candidate_removed", {
                path=key,
                name=model.Name,
            })
        end
    end)
    conns[#conns+1] = anc
end

local function scanCandidates()
    local count = 0
    for _,inst in ipairs(Workspace:GetDescendants()) do
        if inst:IsA("Model") and isCandidateModel(inst) then
            watchCandidate(inst)
            count += 1
        end
    end
    return count
end

local function scanRelevantObjects()
    local remotes, modules = {}, {}
    for _,d in ipairs(ReplicatedStorage:GetDescendants()) do
        local path = safeFullName(d)
        local hit = matchesTerm(path)
        if hit then
            if d:IsA("RemoteEvent") or d:IsA("RemoteFunction") then
                remotes[#remotes+1] = {
                    name=d.Name,class=d.ClassName,path=path,attrs=attrs(d)
                }
            elseif d:IsA("ModuleScript") then
                modules[#modules+1] = {
                    name=d.Name,path=path,attrs=attrs(d)
                }
            end
        end
        if #remotes > 400 and #modules > 400 then break end
    end
    table.sort(remotes,function(a,b) return a.path < b.path end)
    table.sort(modules,function(a,b) return a.path < b.path end)
    state.relevantRemotes = remotes
    state.relevantModules = modules
end

local function isBat(tool)
    if not (tool and tool:IsA("Tool")) then return false end
    if tool:GetAttribute("IsBat") == true then return true end
    if lower(tool:GetAttribute("GearName")):find("bat",1,true) then return true end
    if lower(tool.Name):find("bat",1,true) then return true end
    return false
end

local function toolRow(tool, where)
    local descendants = {}
    for _,d in ipairs(tool:GetDescendants()) do
        if d:IsA("LocalScript") or d:IsA("ModuleScript") or d:IsA("RemoteEvent")
            or d:IsA("RemoteFunction") or d:IsA("Animation")
            or d:IsA("Sound") or d:IsA("ValueBase") then
            local r = {name=d.Name,class=d.ClassName,path=safeFullName(d),attrs=attrs(d)}
            if d:IsA("ValueBase") then
                pcall(function() r.value = serial(d.Value) end)
            end
            descendants[#descendants+1] = r
        end
    end
    return {
        where=where,
        name=tool.Name,
        attrs=attrs(tool),
        enabled=tool.Enabled,
        canBeDropped=tool.CanBeDropped,
        textureId=tool.TextureId,
        descendants=descendants,
    }
end

local function scanBat()
    local out = {}
    for _,pair in ipairs({
        {LP.Character,"Character"},
        {LP:FindFirstChildOfClass("Backpack"),"Backpack"}
    }) do
        local box,where = pair[1],pair[2]
        if box then
            for _,x in ipairs(box:GetChildren()) do
                if x:IsA("Tool") and isBat(x) then
                    out[#out+1] = toolRow(x, where)
                end
            end
        end
    end
    state.bat = out
    return #out
end

local function playerPos()
    local c = LP.Character
    local root = c and (c:FindFirstChild("HumanoidRootPart") or c.PrimaryPart)
    return root and serial(root.Position) or nil
end

local function nearbyInteresting(limit)
    limit = limit or 120
    local out = {}
    local c = LP.Character
    local pr = c and (c:FindFirstChild("HumanoidRootPart") or c.PrimaryPart)
    if not pr then return out end

    for _,inst in ipairs(Workspace:GetDescendants()) do
        if inst:IsA("Model") or inst:IsA("Folder") then
            local hit = matchesTerm(inst.Name)
            if hit or inst:IsA("Model") then
                local r = rootOf(inst)
                if r then
                    local dist = (r.Position - pr.Position).Magnitude
                    if dist <= limit then
                        local _,h,mx = currentHealth(inst)
                        if hit or h ~= nil then
                            out[#out+1] = {
                                name=inst.Name,
                                class=inst.ClassName,
                                path=safeFullName(inst),
                                distance=dist,
                                health=h,
                                maxHealth=mx,
                                attrs=attrs(inst),
                                tags=modelTags(inst),
                            }
                        end
                    end
                end
            end
        end
        if #out >= 250 then break end
    end

    table.sort(out,function(a,b) return (a.distance or 1e9) < (b.distance or 1e9) end)
    return out
end

local function snapshot(label)
    scanCandidates()
    scanRelevantObjects()
    scanBat()

    local cand = {}
    for _,row in pairs(state.candidates) do cand[#cand+1] = row end
    table.sort(cand,function(a,b) return a.path < b.path end)

    return {
        label=label,
        unix=os.time(),
        playerPos=playerPos(),
        bats=state.bat,
        candidates=cand,
        nearby=nearbyInteresting(150),
        relevantRemotes=state.relevantRemotes,
        relevantModules=state.relevantModules,
    }
end

local root = (function()
    local ok,h = pcall(function() return gethui and gethui() end)
    return (ok and h) or CoreGui
end)()

local gui = Instance.new("ScreenGui")
gui.Name = "PsicoEventMobScannerV1"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = root

local viewport = Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize or Vector2.new(1280,720)
local w = math.clamp(math.floor(viewport.X * .62), 560, 820)
local h = math.clamp(math.floor(viewport.Y * .58), 330, 470)

local main = Instance.new("Frame")
main.Size = UDim2.fromOffset(w,h)
main.Position = UDim2.new(.5,-w/2,.5,-h/2)
main.BackgroundColor3 = Color3.fromRGB(10,20,38)
main.BorderSizePixel = 0
main.Parent = gui
Instance.new("UICorner",main).CornerRadius = UDim.new(0,18)

local header = Instance.new("Frame")
header.Size = UDim2.new(1,0,0,54)
header.BackgroundTransparency = 1
header.Active = true
header.Parent = main

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Position = UDim2.fromOffset(18,8)
title.Size = UDim2.new(1,-90,0,38)
title.Font = Enum.Font.GothamBold
title.Text = "EVENT MOB FARM SCANNER • V1"
title.TextSize = 22
title.TextColor3 = Color3.fromRGB(245,248,255)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = header

local close = Instance.new("TextButton")
close.Size = UDim2.fromOffset(48,38)
close.Position = UDim2.new(1,-60,0,8)
close.BackgroundColor3 = Color3.fromRGB(35,44,61)
close.Text = "×"
close.TextSize = 22
close.TextColor3 = Color3.new(1,1,1)
close.Font = Enum.Font.GothamBold
close.Parent = header
Instance.new("UICorner",close).CornerRadius = UDim.new(0,10)

local status = Instance.new("TextLabel")
status.BackgroundColor3 = Color3.fromRGB(16,34,58)
status.BorderSizePixel = 0
status.Position = UDim2.fromOffset(18,64)
status.Size = UDim2.new(1,-36,0,112)
status.Font = Enum.Font.Code
status.TextSize = 15
status.TextColor3 = Color3.fromRGB(220,230,245)
status.TextWrapped = true
status.TextXAlignment = Enum.TextXAlignment.Left
status.TextYAlignment = Enum.TextYAlignment.Top
status.Text = "1) Vá até a área do evento\n2) INICIAR CAPTURA\n3) Mate manualmente 1–3 mobs usando o bastão\n4) FINALIZAR e EXPORTAR JSON"
status.Parent = main
Instance.new("UICorner",status).CornerRadius = UDim.new(0,12)

local function btn(txt,x,y,ww,cb)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(ww,-8,0,48)
    b.Position = UDim2.new(x,18,y,0)
    b.BackgroundColor3 = Color3.fromRGB(42,91,151)
    b.TextColor3 = Color3.new(1,1,1)
    b.Text = txt
    b.TextSize = 16
    b.Font = Enum.Font.GothamBold
    b.Parent = main
    Instance.new("UICorner",b).CornerRadius = UDim.new(0,10)
    b.Activated:Connect(cb)
    return b
end

local startBtn, stopBtn, exportBtn, rescanBtn

startBtn = btn("INICIAR CAPTURA",0,0.55,.5,function()
    state.events = {}
    state.candidates = {}
    state.startSnapshot = snapshot("before")
    state.active = true
    local c = #state.startSnapshot.candidates
    local b = #state.startSnapshot.bats
    status.Text = ("CAPTURA ATIVA\nCandidatos encontrados: %d | Bastões: %d\nAgora mate manualmente 1–3 mobs do evento e depois toque FINALIZAR."):format(c,b)
end)

stopBtn = btn("FINALIZAR",.5,0.55,.5,function()
    state.active = false
    state.endSnapshot = snapshot("after")
    local healthEvents, deaths = 0,0
    for _,e in ipairs(state.events) do
        if e.kind:find("health",1,true) then healthEvents += 1 end
        if e.kind == "mob_died" or e.kind == "candidate_removed" then deaths += 1 end
    end
    status.Text = ("CAPTURA FINALIZADA\nEventos: %d | Mudanças de vida: %d | mortes/remoções: %d\nAgora EXPORTAR JSON."):format(#state.events,healthEvents,deaths)
end)

exportBtn = btn("EXPORTAR JSON",0,0.73,.62,function()
    if not state.startSnapshot then
        status.Text = "Faça INICIAR CAPTURA antes de exportar."
        return
    end
    if not state.endSnapshot then
        state.active = false
        state.endSnapshot = snapshot("after_auto")
    end

    local payload = {
        scanner="Psico Event Mob Farm Scanner V1",
        placeId=game.PlaceId,
        gameId=game.GameId,
        startedUnix=state.startedUnix,
        startSnapshot=state.startSnapshot,
        endSnapshot=state.endSnapshot,
        events=state.events,
    }

    local ok,json = pcall(HttpService.JSONEncode,HttpService,payload)
    if not ok then
        status.Text = "Erro JSON: "..tostring(json)
        return
    end

    local name = "Psico_EventMobFarm_"..os.time()..".json"
    if writefile then
        local ok2,err = pcall(writefile,name,json)
        status.Text = ok2 and ("Exportado: "..name) or ("writefile falhou: "..tostring(err))
    elseif setclipboard then
        pcall(setclipboard,json)
        status.Text = "JSON copiado para o clipboard."
    else
        status.Text = "Executor sem writefile/setclipboard."
    end
end)

rescanBtn = btn("REFAZER LEITURA",.62,0.73,.38,function()
    local c = scanCandidates()
    local b = scanBat()
    scanRelevantObjects()
    status.Text = ("Leitura refeita\nCandidatos: %d | Bastões: %d | Remotes relevantes: %d | Modules relevantes: %d"):format(c,b,#state.relevantRemotes,#state.relevantModules)
end)

-- Workspace additions are cheap to observe and help identify event-spawned mobs.
conns[#conns+1] = Workspace.DescendantAdded:Connect(function(inst)
    if inst:IsA("Model") then
        task.defer(function()
            if inst.Parent and isCandidateModel(inst) then
                watchCandidate(inst)
                if state.active then
                    pushEvent("candidate_spawned", candidateRow(inst))
                end
            end
        end)
    end
end)

-- Bat movement between Backpack/Character is useful for reconstructing equip/attack flow.
local function watchToolContainer(container,where)
    if not container then return end
    conns[#conns+1] = container.ChildAdded:Connect(function(x)
        if x:IsA("Tool") and isBat(x) and state.active then
            pushEvent("bat_added", toolRow(x,where))
        end
    end)
    conns[#conns+1] = container.ChildRemoved:Connect(function(x)
        if x:IsA("Tool") and isBat(x) and state.active then
            pushEvent("bat_removed", {name=x.Name,from=where,attrs=attrs(x)})
        end
    end)
end
watchToolContainer(LP:FindFirstChildOfClass("Backpack"),"Backpack")
if LP.Character then watchToolContainer(LP.Character,"Character") end
conns[#conns+1] = LP.CharacterAdded:Connect(function(ch)
    watchToolContainer(ch,"Character")
end)

-- Mobile-friendly drag by header.
do
    local dragging=false
    local dragStart,startPos
    header.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging=true
            dragStart=input.Position
            startPos=main.Position
        end
    end)
    header.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging=false
        end
    end)
    conns[#conns+1] = UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch) then
            local delta=input.Position-dragStart
            main.Position=UDim2.new(
                startPos.X.Scale,startPos.X.Offset+delta.X,
                startPos.Y.Scale,startPos.Y.Offset+delta.Y
            )
        end
    end)
end

local function cleanup()
    state.active=false
    for _,c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    table.clear(conns)
    pcall(function() gui:Destroy() end)
    if _G.PSICO_EVENT_MOB_SCANNER_CLEANUP == cleanup then
        _G.PSICO_EVENT_MOB_SCANNER_CLEANUP = nil
    end
end

close.Activated:Connect(cleanup)
_G.PSICO_EVENT_MOB_SCANNER_CLEANUP = cleanup

-- Initial passive reading only.
task.defer(function()
    local c=scanCandidates()
    local b=scanBat()
    scanRelevantObjects()
    status.Text = ("Pronto para capturar.\nCandidatos atuais: %d | Bastões: %d | Remotes: %d\nVá até o evento e toque INICIAR CAPTURA."):format(c,b,#state.relevantRemotes)
end)

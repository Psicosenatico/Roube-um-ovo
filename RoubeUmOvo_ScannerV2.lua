--[[
PSICOSENATICO | Roube um Ovo - Carry / Guard Scanner V10
Stable loader path: RoubeUmOvo_ScannerV2.lua

Objetivo:
  * Medir a penalidade real de velocidade quando um ovo e carregado.
  * Cruzar o SpeedMultiplier recebido do servidor com o peso real do ovo.
  * Ler a velocidade recomendada de cada GuardArea.
  * Registrar velocidade/atributos relevantes do player antes e durante a carga.
  * Inspecionar apenas modulos/constantes client-side ligados a carry/speed/guard.
  * Exportar JSON focado para descobrir o limite/risco de cada ovo.

O scanner nao altera velocidade, ovos, guardioes, prompts, bats ou remotes.
Para uma boa amostra, pegue e solte/entregue 3-6 ovos de pesos diferentes.
]]

if _G.PSICO_ROUBE_SCANNER_CLEANUP then pcall(_G.PSICO_ROUBE_SCANNER_CLEANUP) end

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CoreGui = game:GetService("CoreGui")
local HttpService = game:GetService("HttpService")
local UIS = game:GetService("UserInputService")

local LP = Players.LocalPlayer

local State = {
    Alive = true,
    Connections = {},
    RemoteConnections = {},
    Records = {},
    CarrySamples = {},
    MovementChanges = {},
    LastFreeWalkSpeed = nil,
    CurrentCarry = nil,
    Report = nil,
    Gui = nil,
}

local EggRecords

local function safeString(v)
    local ok,s = pcall(tostring,v)
    return ok and s or "?"
end

local function finite(v)
    return type(v)=="number" and v==v and v~=math.huge and v~=-math.huge
end

local function connect(signal,fn,bucket)
    local c = signal:Connect(fn)
    table.insert(bucket or State.Connections,c)
    return c
end

local function disconnectAll()
    for _,c in ipairs(State.RemoteConnections) do pcall(function() c:Disconnect() end) end
    for _,c in ipairs(State.Connections) do pcall(function() c:Disconnect() end) end
    State.RemoteConnections = {}
    State.Connections = {}
end

local function uiParent()
    local ok,h = pcall(function() if gethui then return gethui() end end)
    return (ok and h) or CoreGui
end

local function resolvePath(root,path)
    local cur=root
    for token in string.gmatch(path,"[^%.]+") do
        if not cur then return nil end
        cur=cur:FindFirstChild(token)
    end
    return cur
end

local function safeRequire(module)
    if not (module and module:IsA("ModuleScript")) then return nil,"module ausente" end
    local ok,v=pcall(require,module)
    if not ok then return nil,safeString(v) end
    return v,nil
end

local function serialize(v,depth,seen)
    depth=depth or 0
    seen=seen or {}
    if depth>5 then return "<depth>" end
    local tv=typeof(v)
    if tv=="nil" or tv=="boolean" or tv=="string" then return v end
    if tv=="number" then return finite(v) and v or safeString(v) end
    if tv=="Vector3" or tv=="Vector2" then return {x=v.X,y=v.Y,z=v.Z} end
    if tv=="Color3" then return {r=v.R,g=v.G,b=v.B} end
    if tv=="CFrame" then
        local p=v.Position
        return {position={x=p.X,y=p.Y,z=p.Z}}
    end
    if tv=="Instance" then return {class=v.ClassName,name=v.Name,path=v:GetFullName()} end
    if tv=="function" then return "<function> "..safeString(v) end
    if tv~="table" then return safeString(v) end
    if seen[v] then return "<cycle>" end
    seen[v]=true
    local out={}
    local n=0
    for k,val in pairs(v) do
        n=n+1
        if n>250 then out.__truncated=true break end
        local key=(type(k)=="string" or type(k)=="number") and k or safeString(k)
        out[key]=serialize(val,depth+1,seen)
    end
    seen[v]=nil
    return out
end

local function keyword(name)
    local s=string.lower(safeString(name or ""))
    return s:find("speed",1,true) or s:find("carry",1,true) or s:find("power",1,true)
        or s:find("weight",1,true) or s:find("capacity",1,true) or s:find("treadmill",1,true)
        or s:find("walk",1,true) or s:find("guard",1,true)
end

local function relevantAttributes(inst)
    local out={}
    if not inst then return out end
    local ok,attrs=pcall(function() return inst:GetAttributes() end)
    if ok then
        for k,v in pairs(attrs) do if keyword(k) then out[k]=serialize(v) end end
    end
    return out
end

local function relevantValues(root,limit)
    local out={}
    if not root then return out end
    local n=0
    for _,d in ipairs(root:GetDescendants()) do
        if keyword(d.Name) then
            local value=nil
            if d:IsA("ValueBase") then value=serialize(d.Value)
            elseif d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox") then value=d.Text end
            if value~=nil then
                n=n+1
                out[#out+1]={path=d:GetFullName(),class=d.ClassName,name=d.Name,value=value,attributes=relevantAttributes(d)}
                if n>=(limit or 80) then break end
            end
        end
    end
    return out
end

local function getHumanoid()
    local ch=LP and LP.Character
    return ch and ch:FindFirstChildOfClass("Humanoid") or nil
end

local function movementSnapshot()
    local hum=getHumanoid()
    local ch=LP and LP.Character
    return {
        unix=os.time(),
        clock=os.clock(),
        walkSpeed=hum and hum.WalkSpeed or nil,
        jumpHeight=hum and hum.JumpHeight or nil,
        playerAttributes=relevantAttributes(LP),
        characterAttributes=relevantAttributes(ch),
        humanoidAttributes=relevantAttributes(hum),
    }
end

local function functionInfo(fn)
    if type(fn)~="function" then return nil end
    local out={tostring=safeString(fn)}
    pcall(function()
        if debug and debug.info then
            out.name=debug.info(fn,"n")
            out.source=debug.info(fn,"s")
            local a,var=debug.info(fn,"a")
            out.arity=a out.variadic=var
        elseif debug and debug.getinfo then
            local i=debug.getinfo(fn)
            if i then out.name=i.name out.source=i.source out.arity=i.nparams out.variadic=i.isvararg end
        end
    end)
    pcall(function()
        if type(getconstants)=="function" then
            local c=getconstants(fn)
            out.constants=serialize(c,0,{})
        end
    end)
    pcall(function()
        if type(getupvalues)=="function" then
            local u=getupvalues(fn)
            local picked={}
            for k,v in pairs(u) do
                if typeof(v)=="table" then
                    local small={}
                    local hit=false
                    for kk,vv in pairs(v) do
                        if keyword(kk) or kk=="BASE_WALK_SPEED" or kk=="BASE_ASSETS_WALK_SPEED" or kk=="BASE_CARRY_POWER" then
                            small[kk]=serialize(vv) hit=true
                        end
                    end
                    if hit then picked[k]=small end
                elseif type(v)=="number" or type(v)=="string" then
                    if keyword(v) then picked[k]=v end
                end
            end
            if next(picked) then out.relevantUpvalues=picked end
        end
    end)
    return out
end

local function moduleSummary(tbl)
    local out={type=typeof(tbl),fields={}}
    if typeof(tbl)~="table" then return out end
    local n=0
    for k,v in pairs(tbl) do
        n=n+1
        if n>100 then out.truncated=true break end
        if type(v)=="function" then out.fields[safeString(k)]={kind="function",info=functionInfo(v)}
        elseif typeof(v)=="table" then
            local small={}
            for kk,vv in pairs(v) do
                if keyword(kk) or kk=="BASE_WALK_SPEED" or kk=="BASE_ASSETS_WALK_SPEED" or kk=="BASE_CARRY_POWER" then small[kk]=serialize(vv) end
            end
            out.fields[safeString(k)]={kind="table",relevant=small}
        elseif keyword(k) then out.fields[safeString(k)]={kind=typeof(v),value=serialize(v)} end
    end
    return out
end

local function findExact(className,name)
    for _,d in ipairs(ReplicatedStorage:GetDescendants()) do
        if d.ClassName==className and d.Name==name then return d end
    end
end

local function callEggFn(name,record)
    if typeof(EggRecords)~="table" then return nil,false end
    local fn=EggRecords[name]
    if type(fn)~="function" then return nil,false end
    local ok,v=pcall(fn,record)
    if ok then return v,true end
    local ok2,v2=pcall(fn,EggRecords,record)
    if ok2 then return v2,true end
    return nil,false
end

local function recordSummary(record)
    if typeof(record)~="table" then return nil end
    local weight,wok=callEggFn("WeightKg",record)
    local label,lok=callEggFn("WeightLabel",record)
    return {
        Uid=record.Uid,
        State=record.State,
        AreaId=record.AreaId,
        NestId=record.NestId,
        AssetCategory=record.AssetCategory,
        AssetScale=record.AssetScale,
        NestScale=record.NestScale,
        BaseMutation=record.BaseMutation,
        Mutations=serialize(record.Mutations),
        WeightKg=(wok and finite(weight)) and weight or nil,
        WeightLabel=lok and safeString(label) or nil,
    }
end

local function ingestTree(v,seen,depth)
    if typeof(v)~="table" then return 0 end
    seen=seen or {} depth=depth or 0
    if depth>8 or seen[v] then return 0 end
    seen[v]=true
    local n=0
    if type(v.Uid)=="string" and v.State~=nil then
        State.Records[v.Uid]=v
        n=1
    else
        local c=0
        for _,child in pairs(v) do
            c=c+1 if c>2500 then break end
            if typeof(child)=="table" then n=n+ingestTree(child,seen,depth+1) end
        end
    end
    seen[v]=nil
    return n
end

local function requestSnapshots()
    local total=0
    for _,name in ipairs({"RF/EggWorld/AskFieldEggSnapshot","RF/EggWorld/AskLiveSnapshot"}) do
        local rf=findExact("RemoteFunction",name)
        if rf then
            local ok,res=pcall(function() return rf:InvokeServer() end)
            if ok then total=total+ingestTree(res) end
        end
    end
    return total
end

local function recommendedSpeeds()
    local out={}
    local objects=Workspace:FindFirstChild("__OBJECTS")
    local areas=objects and objects:FindFirstChild("Areas")
    local guards=areas and areas:FindFirstChild("GuardAreas")
    if not guards then return out end
    for _,area in ipairs(guards:GetChildren()) do
        local sign=area:FindFirstChild("RequiredSpeedSign")
        local speedText=nil
        if sign then
            for _,d in ipairs(sign:GetDescendants()) do
                if (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Name=="Speed" then speedText=d.Text break end
            end
        end
        out[area.Name]={recommendedSpeedText=speedText,attributes=relevantAttributes(area)}
    end
    return out
end

local function capturePlayerEvidence()
    local out={
        movement=movementSnapshot(),
        playerValues=relevantValues(LP,100),
        characterValues=relevantValues(LP and LP.Character,80),
        guiValues=relevantValues(LP and LP:FindFirstChildOfClass("PlayerGui"),120),
    }
    return out
end

local function inspectTargetModules()
    local targets={
        "Shared.Modules.GuardAreas.GuardEggRetrievalComponent",
        "Client.EggState",
        "Shared.Util.EggRecords",
        "Shared.Types.AreaEggs",
        "Shared.Modules.ItemDisplay",
    }
    local out={}
    for _,path in ipairs(targets) do
        local m=resolvePath(ReplicatedStorage,path)
        local value,err=safeRequire(m)
        out[path]={path=m and m:GetFullName() or nil,error=err,summary=moduleSummary(value)}
    end
    return out
end

local function scanLoadedRelevantModules()
    local out={}
    if type(getloadedmodules)~="function" then return out end
    local ok,mods=pcall(getloadedmodules)
    if not ok or type(mods)~="table" then return out end
    local count=0
    for _,m in ipairs(mods) do
        if m and m:IsA("ModuleScript") then
            local p=m:GetFullName()
            if keyword(p) or string.find(string.lower(p),"areaegg",1,true) then
                count=count+1
                local v,err=safeRequire(m)
                out[#out+1]={path=p,error=err,summary=moduleSummary(v)}
                if count>=60 then break end
            end
        end
    end
    return out
end

local function captureCarry(payload)
    if typeof(payload)~="table" then return end
    local now=movementSnapshot()
    if payload.IsCarrying==true then
        local uid=payload.Uid
        local raw=type(uid)=="string" and State.Records[uid] or nil
        local sample={
            index=#State.CarrySamples+1,
            startedUnix=os.time(),
            startedClock=os.clock(),
            payload=serialize(payload),
            egg=recordSummary(raw),
            freeWalkSpeedBefore=State.LastFreeWalkSpeed,
            movementAtEvent=now,
            recommendedArea=(State.Report and State.Report.GuardRecommended and payload.AreaId) and State.Report.GuardRecommended[payload.AreaId] or nil,
            delayedMovement={},
        }
        State.CarrySamples[#State.CarrySamples+1]=sample
        State.CurrentCarry=sample
        task.defer(function()
            task.wait(.08)
            if State.Alive and sample then sample.delayedMovement[1]=movementSnapshot() end
            task.wait(.22)
            if State.Alive and sample then sample.delayedMovement[2]=movementSnapshot() end
            task.wait(.50)
            if State.Alive and sample then sample.delayedMovement[3]=movementSnapshot() end
        end)
    elseif payload.IsCarrying==false then
        if State.CurrentCarry then
            State.CurrentCarry.endedUnix=os.time()
            State.CurrentCarry.endPayload=serialize(payload)
            State.CurrentCarry.movementAtEnd=now
        end
        State.CurrentCarry=nil
    end
end

local function hookRemotes()
    for _,d in ipairs(ReplicatedStorage:GetDescendants()) do
        if d:IsA("RemoteEvent") then
            if d.Name=="RE/EggWorld/FieldEggShifted" then
                connect(d.OnClientEvent,function(record)
                    if typeof(record)=="table" and type(record.Uid)=="string" then State.Records[record.Uid]=record end
                end,State.RemoteConnections)
            elseif d.Name=="RE/EggWorld/FieldEggBatchShifted" then
                connect(d.OnClientEvent,function(payload)
                    if typeof(payload)=="table" and typeof(payload.UpdatedRecords)=="table" then
                        for _,r in pairs(payload.UpdatedRecords) do
                            if typeof(r)=="table" and type(r.Uid)=="string" then State.Records[r.Uid]=r end
                        end
                    end
                end,State.RemoteConnections)
            elseif d.Name=="RE/EggWorld/FieldEggGone" then
                connect(d.OnClientEvent,function(uid) if type(uid)=="string" then State.Records[uid]=nil end end,State.RemoteConnections)
            elseif d.Name=="RE/EggWorld/FieldEggCarry" then
                connect(d.OnClientEvent,function(payload) captureCarry(payload) end,State.RemoteConnections)
            end
        end
    end
end

local function buildReport()
    local shared=ReplicatedStorage:FindFirstChild("Shared")
    local util=shared and shared:FindFirstChild("Util")
    local eggModule=util and util:FindFirstChild("EggRecords")
    EggRecords=safeRequire(eggModule)

    local report={
        Meta={
            Version="CarryGuardScannerV10",
            PlaceId=game.PlaceId,
            GameId=game.GameId,
            JobId=game.JobId,
            StartedUnix=os.time(),
            Notes="Passive carry/guard scan. Pick several eggs of different weights before exporting.",
        },
        GuardRecommended=recommendedSpeeds(),
        PlayerEvidence=capturePlayerEvidence(),
        Modules=inspectTargetModules(),
        LoadedRelevantModules=scanLoadedRelevantModules(),
        CarrySamples=State.CarrySamples,
        MovementChanges=State.MovementChanges,
        SnapshotRecordCount=requestSnapshots(),
        Summary={},
    }
    State.Report=report
    return report
end

local function finalizeReport()
    local report=State.Report or buildReport()
    report.CarrySamples=State.CarrySamples
    report.MovementChanges=State.MovementChanges
    report.PlayerEvidenceAtExport=capturePlayerEvidence()
    report.Summary={
        CarrySampleCount=#State.CarrySamples,
        RecordCount=(function() local n=0 for _ in pairs(State.Records) do n=n+1 end return n end)(),
        LastFreeWalkSpeed=State.LastFreeWalkSpeed,
    }
    report.Meta.FinishedUnix=os.time()
    return report
end

local function exportReport()
    local report=finalizeReport()
    local ok,json=pcall(function() return HttpService:JSONEncode(report) end)
    if not ok then return false,"JSONEncode falhou: "..safeString(json) end
    local filename="Psico_RoubeUmOvo_CarryGuardScan_"..tostring(os.time())..".json"
    if type(writefile)=="function" then
        local wok,werr=pcall(writefile,filename,json)
        if wok then return true,filename end
        return false,"writefile falhou: "..safeString(werr)
    end
    if type(setclipboard)=="function" then
        local cok,cerr=pcall(setclipboard,json)
        if cok then return true,"JSON copiado" end
        return false,"clipboard falhou: "..safeString(cerr)
    end
    return false,"executor sem writefile/setclipboard"
end

local function round(obj,r)
    local c=Instance.new("UICorner") c.CornerRadius=UDim.new(0,r or 9) c.Parent=obj
end

local function mkButton(parent,text,pos,size)
    local b=Instance.new("TextButton")
    b.BackgroundColor3=Color3.fromRGB(31,43,66) b.BorderSizePixel=0 b.Position=pos b.Size=size
    b.Font=Enum.Font.GothamMedium b.Text=text b.TextColor3=Color3.fromRGB(240,245,255) b.TextSize=11 b.Parent=parent
    round(b,9) return b
end

local function mkLabel(parent,text,pos,size,ts)
    local l=Instance.new("TextLabel")
    l.BackgroundTransparency=1 l.Position=pos l.Size=size l.Font=Enum.Font.Gotham l.Text=text
    l.TextColor3=Color3.fromRGB(176,190,216) l.TextSize=ts or 10 l.TextXAlignment=Enum.TextXAlignment.Left
    l.TextWrapped=true l.Parent=parent return l
end

local old=uiParent():FindFirstChild("PsicoCarryGuardScannerV10")
if old then pcall(function() old:Destroy() end) end

local gui=Instance.new("ScreenGui")
gui.Name="PsicoCarryGuardScannerV10" gui.ResetOnSpawn=false gui.IgnoreGuiInset=true gui.Parent=uiParent()
State.Gui=gui

local vp=Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize or Vector2.new(844,390)
local width=math.floor(math.clamp(vp.X*.38,292,342))
local height=math.floor(math.min(230,vp.Y*.70))

local frame=Instance.new("Frame")
frame.AnchorPoint=Vector2.new(.5,.5) frame.Position=UDim2.fromScale(.5,.5) frame.Size=UDim2.fromOffset(width,height)
frame.BackgroundColor3=Color3.fromRGB(14,20,32) frame.BorderSizePixel=0 frame.Parent=gui round(frame,13)
local stroke=Instance.new("UIStroke") stroke.Thickness=1.1 stroke.Transparency=.28 stroke.Color=Color3.fromRGB(61,118,230) stroke.Parent=frame

local title=mkLabel(frame,"CARRY / GUARD SCAN V10",UDim2.fromOffset(12,8),UDim2.new(1,-52,0,20),14)
title.Font=Enum.Font.GothamBold title.TextColor3=Color3.fromRGB(242,246,255)
local sub=mkLabel(frame,"peso • penalidade de velocidade • guardião",UDim2.fromOffset(12,28),UDim2.new(1,-52,0,16),9)
sub.TextColor3=Color3.fromRGB(102,148,232)
local close=mkButton(frame,"×",UDim2.new(1,-38,0,8),UDim2.fromOffset(28,28))
local status=mkLabel(frame,"Preparando leitura...",UDim2.fromOffset(12,54),UDim2.new(1,-24,0,70),10)
status.TextColor3=Color3.fromRGB(198,210,232)
local rescan=mkButton(frame,"ATUALIZAR BASE",UDim2.new(0,12,1,-83),UDim2.new(1,-24,0,31))
local export=mkButton(frame,"EXPORTAR JSON",UDim2.new(0,12,1,-45),UDim2.new(1,-24,0,31))

local function updateStatus(extra)
    local last=State.CarrySamples[#State.CarrySamples]
    local mult=last and last.payload and tonumber(last.payload.SpeedMultiplier)
    local weight=last and last.egg and tonumber(last.egg.WeightKg)
    status.Text=string.format(
        "Amostras: %d%s%s\nPegue e solte/entregue 3-6 ovos de pesos diferentes.%s",
        #State.CarrySamples,
        mult and (" • último x"..string.format("%.4f",mult)) or "",
        weight and (" • "..string.format("%.0fKg",weight)) or "",
        extra and ("\n"..extra) or ""
    )
end

connect(rescan.MouseButton1Click,function()
    State.Report=buildReport()
    updateStatus("base atualizada")
end)
connect(export.MouseButton1Click,function()
    export.Text="EXPORTANDO..."
    task.defer(function()
        local ok,msg=exportReport()
        export.Text=ok and "EXPORTADO ✓" or "FALHOU"
        updateStatus(msg)
        task.wait(1.8)
        if State.Alive and export.Parent then export.Text="EXPORTAR JSON" end
    end)
end)

local dragging=false
local dragInput,dragStart,startPos
connect(frame.InputBegan,function(input)
    if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1 then
        dragging=true dragStart=input.Position startPos=frame.Position
    end
end)
connect(frame.InputChanged,function(input)
    if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseMovement then dragInput=input end
end)
connect(UIS.InputChanged,function(input)
    if dragging and input==dragInput then
        local d=input.Position-dragStart
        frame.Position=UDim2.new(startPos.X.Scale,startPos.X.Offset+d.X,startPos.Y.Scale,startPos.Y.Offset+d.Y)
    end
end)
connect(UIS.InputEnded,function(input)
    if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1 then dragging=false end
end)

local function cleanup()
    if not State.Alive then return end
    State.Alive=false
    disconnectAll()
    _G.PSICO_ROUBE_SCANNER_CLEANUP=nil
    pcall(function() if State.Gui then State.Gui:Destroy() end end)
end
_G.PSICO_ROUBE_SCANNER_CLEANUP=cleanup
connect(close.MouseButton1Click,cleanup)

hookRemotes()

local lastObserved=nil
task.defer(function()
    while State.Alive do
        task.wait(.15)
        local hum=getHumanoid()
        local ws=hum and hum.WalkSpeed or nil
        if not State.CurrentCarry and finite(ws) then State.LastFreeWalkSpeed=ws end
        if ws~=lastObserved then
            State.MovementChanges[#State.MovementChanges+1]={clock=os.clock(),walkSpeed=ws,carrying=State.CurrentCarry~=nil}
            if #State.MovementChanges>180 then table.remove(State.MovementChanges,1) end
            lastObserved=ws
        end
        updateStatus()
    end
end)

task.defer(function()
    task.wait(.35)
    if State.Alive then
        local ok,err=pcall(function() State.Report=buildReport() end)
        if ok then updateStatus("leitura pronta") else updateStatus("erro: "..safeString(err)) end
    end
end)

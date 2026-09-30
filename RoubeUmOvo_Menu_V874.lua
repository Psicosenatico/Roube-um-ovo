-- PSICOSENATICO V8.7.8 (stable V874 loader path)
-- Stable loader + server-transition auto execute.
local Players=game:GetService("Players")
local HttpService=game:GetService("HttpService")

repeat task.wait(.2) until game:IsLoaded()
repeat task.wait(.2) until Players.LocalPlayer

local LOADER_URL="https://raw.githubusercontent.com/Psicosenatico/Roube-um-ovo/main/RoubeUmOvo_Menu_V874.lua"
local STATE_FILE="Psico_RoubeUmOvo_AutoExec.json"

-- Prevent a queued teleport run and the executor auto-exec from racing each other
-- in the same server, while still allowing a later manual reload.
do
    local env=(getgenv and getgenv()) or _G
    local now=os.clock()
    if env.PSICO_RUO_LOADER_JOB==game.JobId
        and type(env.PSICO_RUO_LOADER_AT)=="number"
        and now-env.PSICO_RUO_LOADER_AT<8 then
        return
    end
    env.PSICO_RUO_LOADER_JOB=game.JobId
    env.PSICO_RUO_LOADER_AT=now
end

local previousState
local function readState()
    if type(readfile)~="function" or type(isfile)~="function" then return nil end
    local ok,exists=pcall(isfile,STATE_FILE)
    if not (ok and exists) then return nil end
    local okRead,raw=pcall(readfile,STATE_FILE)
    if not okRead or type(raw)~="string" then return nil end
    local okJson,data=pcall(HttpService.JSONDecode,HttpService,raw)
    return okJson and type(data)=="table" and data or nil
end

local function writeState(reason)
    if type(writefile)~="function" then return false end
    local payload={
        jobId=tostring(game.JobId or ""),
        placeId=tonumber(game.PlaceId) or 0,
        gameId=tonumber(game.GameId) or 0,
        userId=Players.LocalPlayer and Players.LocalPlayer.UserId or 0,
        lastSeen=os.time(),
        reason=reason or "heartbeat",
    }
    local okJson,json=pcall(HttpService.JSONEncode,HttpService,payload)
    if not okJson then return false end
    return pcall(writefile,STATE_FILE,json)
end

previousState=readState()
local now=os.time()
local previousJob=previousState and tostring(previousState.jobId or "") or ""
local previousSeen=previousState and tonumber(previousState.lastSeen) or nil
local offlineSeconds=previousSeen and math.max(0,now-previousSeen) or nil
local sessionReason="first_run"
if previousJob~="" and previousJob~=tostring(game.JobId) then
    sessionReason="server_changed"
elseif offlineSeconds and offlineSeconds>=12 then
    sessionReason="returned_after_"..tostring(math.floor(offlineSeconds)).."s"
elseif previousJob==tostring(game.JobId) then
    sessionReason="same_server_reload"
end
writeState(sessionReason)

-- Queue the same stable loader for the next Roblox server transition.
-- Different executors expose the queue function under different names.
local function queueFunction()
    if type(queue_on_teleport)=="function" then return queue_on_teleport end
    if type(queueonteleport)=="function" then return queueonteleport end
    if type(syn)=="table" and type(syn.queue_on_teleport)=="function" then return syn.queue_on_teleport end
    if type(fluxus)=="table" and type(fluxus.queue_on_teleport)=="function" then return fluxus.queue_on_teleport end
    return nil
end

local queue=queueFunction()
if queue then
    local queued=[[
repeat task.wait(.25) until game:IsLoaded()
local Players=game:GetService("Players")
repeat task.wait(.25) until Players.LocalPlayer
task.wait(1)
loadstring(game:HttpGet("]]..LOADER_URL..[[?teleport="..tostring(os.time())))()
]]
    pcall(queue,queued)
end

-- While this server is alive, keep a small persistent heartbeat.
-- On the next launch this lets the loader tell a quick server transition
-- from a longer period where Roblox/executor was not running.
task.defer(function()
    while true do
        task.wait(5)
        local ok=writeState("heartbeat")
        if not game:IsLoaded() then break end
    end
end)

-- Clear stale diagnostic banners from previous failed attempts.
_G.PSICO_LAST_LOADER_ERROR=nil
pcall(function()
    local ok,h=pcall(function() return gethui and gethui() end)
    local root=(ok and h) or game:GetService("CoreGui")
    local old=root:FindFirstChild("PsicoLoaderDiagnostics")
    if old then old:Destroy() end
end)

local cb=tostring(os.time())..'_'..tostring(math.random(100000,999999))

-- The loader must not fail silently on mobile if a downstream module cannot
-- compile or run. A failure in the add-on must not conceal the main menu.
local function showLoaderError(path,err)
    local message=path..": "..tostring(err)
    _G.PSICO_LAST_LOADER_ERROR=message
    warn("[PSICO LOADER] "..message)
    local ok=pcall(function()
        local root=(function()
            local canGet,h=pcall(function() return gethui and gethui() end)
            return (canGet and h) or game:GetService("CoreGui")
        end)()
        local previous=root:FindFirstChild("PsicoLoaderDiagnostics")
        if previous then previous:Destroy() end

        local screen=Instance.new("ScreenGui")
        screen.Name="PsicoLoaderDiagnostics"
        screen.ResetOnSpawn=false
        screen.IgnoreGuiInset=true
        screen.DisplayOrder=200000
        screen.Parent=root

        local box=Instance.new("Frame")
        box.AnchorPoint=Vector2.new(.5,0)
        box.Position=UDim2.new(.5,0,.05,0)
        box.Size=UDim2.new(.85,0,0,105)
        box.BackgroundColor3=Color3.fromRGB(67,25,32)
        box.BorderSizePixel=0
        box.Parent=screen
        local corner=Instance.new("UICorner")
        corner.CornerRadius=UDim.new(0,10)
        corner.Parent=box

        local msg=Instance.new("TextLabel")
        msg.BackgroundTransparency=1
        msg.Position=UDim2.fromOffset(8,6)
        msg.Size=UDim2.new(1,-16,1,-12)
        msg.TextWrapped=true
        msg.TextXAlignment=Enum.TextXAlignment.Left
        msg.TextYAlignment=Enum.TextYAlignment.Top
        msg.TextSize=13
        msg.Font=Enum.Font.GothamMedium
        msg.TextColor3=Color3.fromRGB(255,220,220)
        msg.Text="PSICOSENATICO: falha em "..path.."\n"..tostring(err):sub(1,320)..
            "\nDetalhes: _G.PSICO_LAST_LOADER_ERROR"
        msg.Parent=box
    end)
    if not ok then warn("[PSICO LOADER] Não foi possível exibir o diagnóstico.") end
end

local function run(path)
    local ok,err=pcall(function()
        local src=game:HttpGet(
            'https://raw.githubusercontent.com/Psicosenatico/Roube-um-ovo/main/'..path..'?cb='..cb
        )
        local fn,compileError=loadstring(src)
        if not fn then error("ERRO DE COMPILAÇÃO: "..tostring(compileError)) end
        local didRun,runtimeError=pcall(fn)
        if not didRun then error("ERRO DE EXECUÇÃO: "..tostring(runtimeError)) end
    end)
    if not ok then showLoaderError(path,err) end
    return ok
end

if not run('RoubeUmOvo_Menu.lua') then return end
if not run('InventoryEggPanel_V5.lua') then return end

task.defer(function()
    task.wait(.2)
    local root=(function()
        local ok,h=pcall(function()return gethui and gethui()end)
        return(ok and h)or game:GetService('CoreGui')
    end)()
    for _,g in ipairs(root:GetChildren())do
        if g:IsA('ScreenGui')and g.Name:find('PsicoRoubeUmOvo',1,true)==1 then
            local m=g:FindFirstChild('Main')
            if m then
                for _,d in ipairs(m:GetDescendants())do
                    if d:IsA('TextLabel')and d.Text:find('V8.',1,true)==1 then
                        d.Text='V8.7.8 • PREDICT % VISÍVEL + $/S POR SLOT'
                        return
                    end
                end
            end
        end
    end
end)

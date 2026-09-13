--[[
PSICOSENATICO | Nasi Game Select Observer Lite V1

Uso:
1) Abra o hub Nasi e espere a interface carregar.
2) Execute este observer.
3) Clique em Steal An Egg no hub.
4) Espere o menu do jogo abrir.
5) Clique EXPORTAR JSON e envie o arquivo gerado.

Este observer foi feito para ser LEVE:
- NAO intercepta loadstring
- NAO copia/analisa corpo de scripts
- NAO procura keywords em payloads grandes
- NAO altera ovos, remotes, sorte, velocidade, combate ou ciclo
- registra somente URL, metodo, status, tamanho de resposta e tempo
]]

if _G.PSICO_NASI_LITE_CLEANUP then pcall(_G.PSICO_NASI_LITE_CLEANUP) end

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")
local UIS = game:GetService("UserInputService")
local LP = Players.LocalPlayer
local G = (getgenv and getgenv()) or _G

local START = os.clock()
local START_UNIX = os.time()
local State = {
    Alive = true,
    Rows = {},
    Originals = {},
    Gui = nil,
}

local function now()
    return os.clock() - START
end

local function safe(v)
    local ok, r = pcall(tostring, v)
    return ok and r or "?"
end

local function hostOf(url)
    return (safe(url):match("^https?://([^/%?]+)") or "")
end

local function redactUrl(url)
    url = safe(url)
    local base, query = url:match("^([^?]+)%?(.*)$")
    if not query then return url end
    local out = {}
    for part in query:gmatch("[^&]+") do
        local k, v = part:match("^([^=]+)=(.*)$")
        if k then
            local q = string.lower(k)
            if q:find("key",1,true) or q:find("token",1,true) or q:find("auth",1,true) or q:find("secret",1,true) or q:find("session",1,true) then
                out[#out+1] = k .. "=<redacted>"
            else
                out[#out+1] = k .. "=" .. string.sub(v,1,180)
            end
        else
            out[#out+1] = string.sub(part,1,180)
        end
    end
    return base .. "?" .. table.concat(out,"&")
end

local function push(source, method, url, status, bytes, okFlag, err)
    if not State.Alive then return end
    local row = {
        t = now(),
        unix = os.time(),
        source = source,
        method = safe(method or "GET"),
        url = redactUrl(url or "?"),
        host = hostOf(url or ""),
        status = status,
        bytes = bytes,
        ok = okFlag,
        error = err and string.sub(safe(err),1,300) or nil,
    }
    State.Rows[#State.Rows+1] = row
    if #State.Rows > 250 then table.remove(State.Rows,1) end
end

local function wrapRequest(holder, key, label)
    local ok, original = pcall(function() return holder[key] end)
    if not ok or type(original) ~= "function" then return false end

    State.Originals[#State.Originals+1] = {holder=holder,key=key,fn=original}

    local wrapper = function(opts, ...)
        local url, method = "?", "GET"
        if type(opts) == "table" then
            url = opts.Url or opts.URL or opts.url or "?"
            method = opts.Method or opts.method or "GET"
        elseif type(opts) == "string" then
            url = opts
        end

        local packed = table.pack(pcall(original, opts, ...))
        if packed[1] then
            local resp = packed[2]
            local status, bytes = nil, nil
            if type(resp) == "table" then
                status = resp.StatusCode or resp.Status or resp.status_code or resp.status
                local body = resp.Body or resp.body or resp.ResponseBody or resp.responseBody
                if type(body) == "string" then bytes = #body end
            elseif type(resp) == "string" then
                status = 200
                bytes = #resp
            end
            push(label, method, url, status, bytes, true, nil)
            return table.unpack(packed,2,packed.n)
        else
            push(label, method, url, nil, nil, false, packed[2])
            error(packed[2],0)
        end
    end

    return pcall(function() holder[key] = wrapper end)
end

local function installRequestHooks()
    local seen = {}
    local function add(holder,key,label)
        local ok,fn = pcall(function() return holder and holder[key] end)
        if ok and type(fn)=="function" and not seen[fn] then
            if wrapRequest(holder,key,label) then seen[fn]=true end
        end
    end

    for _,name in ipairs({"request","http_request","httprequest"}) do
        add(G,name,name)
    end
    if type(G.syn)=="table" then add(G.syn,"request","syn.request") end
    if type(G.http)=="table" then add(G.http,"request","http.request") end
    if type(G.fluxus)=="table" then add(G.fluxus,"request","fluxus.request") end
end

local oldNamecall
local function installHttpGetHook()
    if type(hookmetamethod)~="function" or type(getnamecallmethod)~="function" then return end
    local closure = function(self,...)
        local method = getnamecallmethod()
        if State.Alive and (method=="HttpGet" or method=="HttpGetAsync") then
            local args={...}
            local url=args[1]
            local packed=table.pack(pcall(oldNamecall,self,...))
            if packed[1] then
                local body=packed[2]
                push("game:"..method,"GET",url,200,type(body)=="string" and #body or nil,true,nil)
                return table.unpack(packed,2,packed.n)
            else
                push("game:"..method,"GET",url,nil,nil,false,packed[2])
                error(packed[2],0)
            end
        end
        return oldNamecall(self,...)
    end
    local ok,res=pcall(function()
        oldNamecall=hookmetamethod(game,"__namecall",type(newcclosure)=="function" and newcclosure(closure) or closure)
        return oldNamecall
    end)
    if not ok then oldNamecall=nil end
end

local function report()
    local domains={}
    for _,r in ipairs(State.Rows) do
        if r.host and r.host~="" then domains[r.host]=(domains[r.host] or 0)+1 end
    end
    return {
        Meta={
            Version="NasiGameSelectObserverLiteV1",
            PlaceId=game.PlaceId,
            GameId=game.GameId,
            JobId=game.JobId,
            StartedUnix=START_UNIX,
            FinishedUnix=os.time(),
            Note="Low-impact capture after hub UI is already open. No loadstring/body inspection."
        },
        Summary={Requests=#State.Rows,Domains=domains},
        Requests=State.Rows,
    }
end

local statusLabel
local function exportJson()
    local ok,json=pcall(HttpService.JSONEncode,HttpService,report())
    if not ok then
        if statusLabel then statusLabel.Text="Erro no JSON: "..safe(json) end
        return
    end
    local name="Psico_Nasi_GameSelect_Lite_"..tostring(os.time())..".json"
    local wrote=false
    if type(writefile)=="function" then wrote=pcall(writefile,name,json) end
    if type(setclipboard)=="function" then pcall(setclipboard,json) end
    if statusLabel then
        statusLabel.Text=(wrote and "Exportado: " or "Copiado: ")..name.."\nRequests: "..#State.Rows
    end
end

local function parentGui()
    local ok,h=pcall(function() return gethui and gethui() end)
    return (ok and h) or CoreGui
end

local function makeGui()
    local p=parentGui()
    local old=p:FindFirstChild("PSICO_NASI_GAMESELECT_LITE")
    if old then old:Destroy() end

    local gui=Instance.new("ScreenGui")
    gui.Name="PSICO_NASI_GAMESELECT_LITE"
    gui.ResetOnSpawn=false
    gui.DisplayOrder=1100
    gui.Parent=p
    State.Gui=gui

    local frame=Instance.new("Frame")
    frame.AnchorPoint=Vector2.new(.5,.5)
    frame.Position=UDim2.fromScale(.5,.5)
    frame.Size=UDim2.fromOffset(410,210)
    frame.BackgroundColor3=Color3.fromRGB(10,19,36)
    frame.BorderSizePixel=0
    frame.Parent=gui
    Instance.new("UICorner",frame).CornerRadius=UDim.new(0,14)

    local title=Instance.new("TextLabel")
    title.BackgroundTransparency=1
    title.Position=UDim2.fromOffset(14,10)
    title.Size=UDim2.new(1,-55,0,25)
    title.Font=Enum.Font.GothamBold
    title.Text="NASI GAME SELECT OBSERVER • LITE"
    title.TextSize=14
    title.TextColor3=Color3.fromRGB(235,244,255)
    title.TextXAlignment=Enum.TextXAlignment.Left
    title.Parent=frame

    statusLabel=Instance.new("TextLabel")
    statusLabel.Position=UDim2.fromOffset(14,48)
    statusLabel.Size=UDim2.new(1,-28,0,90)
    statusLabel.BackgroundColor3=Color3.fromRGB(15,29,52)
    statusLabel.BorderSizePixel=0
    statusLabel.Font=Enum.Font.Code
    statusLabel.TextSize=11
    statusLabel.TextColor3=Color3.fromRGB(214,228,247)
    statusLabel.TextXAlignment=Enum.TextXAlignment.Left
    statusLabel.TextYAlignment=Enum.TextYAlignment.Top
    statusLabel.Text="Ativo. Agora clique em Steal An Egg no hub.\nSem scan de payload / sem hook de loadstring."
    statusLabel.Parent=frame
    Instance.new("UICorner",statusLabel).CornerRadius=UDim.new(0,9)
    local pad=Instance.new("UIPadding",statusLabel)
    pad.PaddingLeft=UDim.new(0,8)
    pad.PaddingTop=UDim.new(0,7)

    local export=Instance.new("TextButton")
    export.Position=UDim2.new(0,14,1,-54)
    export.Size=UDim2.new(.65,-18,0,34)
    export.BackgroundColor3=Color3.fromRGB(28,74,125)
    export.BorderSizePixel=0
    export.Text="EXPORTAR JSON"
    export.TextColor3=Color3.fromRGB(240,247,255)
    export.Font=Enum.Font.GothamBold
    export.TextSize=12
    export.Parent=frame
    Instance.new("UICorner",export).CornerRadius=UDim.new(0,9)

    local close=Instance.new("TextButton")
    close.Position=UDim2.new(.65,4,1,-54)
    close.Size=UDim2.new(.35,-18,0,34)
    close.BackgroundColor3=Color3.fromRGB(48,56,72)
    close.BorderSizePixel=0
    close.Text="FECHAR"
    close.TextColor3=Color3.fromRGB(238,242,248)
    close.Font=Enum.Font.GothamBold
    close.TextSize=12
    close.Parent=frame
    Instance.new("UICorner",close).CornerRadius=UDim.new(0,9)

    export.MouseButton1Click:Connect(exportJson)
    close.MouseButton1Click:Connect(function()
        State.Alive=false
        if State.Gui then State.Gui:Destroy() end
    end)

    local dragging=false
    local dragStart,startPos
    frame.InputBegan:Connect(function(input)
        if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
            dragging=true;dragStart=input.Position;startPos=frame.Position
        end
    end)
    frame.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType==Enum.UserInputType.MouseMovement or input.UserInputType==Enum.UserInputType.Touch) then
            local d=input.Position-dragStart
            frame.Position=UDim2.new(startPos.X.Scale,startPos.X.Offset+d.X,startPos.Y.Scale,startPos.Y.Offset+d.Y)
        end
    end)
    UIS.InputEnded:Connect(function(input)
        if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then dragging=false end
    end)

    task.spawn(function()
        while State.Alive and statusLabel and statusLabel.Parent do
            task.wait(.75)
            local last=State.Rows[#State.Rows]
            statusLabel.Text="Ativo • requests: "..#State.Rows.."\n"..(last and (last.method.." "..(last.host~="" and last.host or last.url).."\n"..tostring(last.status or "?").." • "..tostring(last.bytes or "?").." bytes") or "Clique em Steal An Egg no hub.")
        end
    end)
end

_G.PSICO_NASI_LITE_CLEANUP=function()
    State.Alive=false
    for _,x in ipairs(State.Originals) do
        pcall(function() x.holder[x.key]=x.fn end)
    end
    if State.Gui then pcall(function() State.Gui:Destroy() end) end
end

installRequestHooks()
installHttpGetHook()
makeGui()

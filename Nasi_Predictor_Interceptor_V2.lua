--[[
PSICOSENATICO | NASI PREDICTOR INTERCEPTOR V2

Objetivo:
Capturar, com baixo impacto, o que o hub Nasi carrega/consulta ao abrir
Steal An Egg e a aba de Predictor.

Fluxo recomendado:
1) Abra o hub Nasi e espere a interface generica carregar.
2) Execute este interceptor.
3) No Nasi, selecione Steal An Egg.
4) Quando o menu especifico abrir, pressione MARCAR FASE PREDICTOR.
5) Abra/atualize a aba Predictor e aguarde alguns segundos.
6) Pressione SNAPSHOT e depois EXPORTAR JSON.

Captura:
- game:HttpGet / HttpGetAsync
- request/http_request/syn.request equivalentes
- corpos com aparencia de Lua, salvos separadamente quando writefile existir
- chamadas globais de loadstring feitas depois da instalacao do interceptor
- require(ModuleScript) observado via __namecall NAO e usado; para evitar hook pesado
- remotes APENAS quando nome/caminho combina com Egg/Rarity/Cycle/Predict/Spawn/Field
- diferencas leves em getgenv/_G
- textos novos na UI entre snapshots

Seguranca/performance:
- observacional; nao altera ovos, ciclo, sorte, dinheiro, movimento ou combate
- sem getgc, decompile, debug hooks ou varredura de closures
- sem log de Authorization/Cookie e query keys sensiveis
- respostas nao-Lua nao sao salvas integralmente
- limites de quantidade/tamanho para celular
]]

if _G.PSICO_NASI_INTERCEPTOR_V2_CLEANUP then
    pcall(_G.PSICO_NASI_INTERCEPTOR_V2_CLEANUP)
end

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")
local UIS = game:GetService("UserInputService")

local LP = Players.LocalPlayer
local G = (getgenv and getgenv()) or _G
local START_CLOCK = os.clock()
local START_UNIX = os.time()

local LIMITS = {
    Requests = 400,
    Loadstrings = 100,
    Remotes = 250,
    Payloads = 40,
    UITexts = 500,
    GlobalKeys = 700,
    Preview = 240,
    ArgPreview = 180,
    MaxSavedPayloadBytes = 2500000,
}

local KEYWORDS = {"egg", "rarity", "cycle", "predict", "spawn", "field", "lottery"}

local State = {
    Alive = true,
    Phase = "game_select",
    Requests = {},
    Loadstrings = {},
    Remotes = {},
    Payloads = {},
    Marks = {},
    Originals = {},
    SeenPayloads = {},
    UiBaseline = {},
    GlobalBaseline = {},
    Snapshots = {},
    Gui = nil,
    Status = nil,
}

local function now()
    return os.clock() - START_CLOCK
end

local function safe(v)
    local ok, r = pcall(tostring, v)
    return ok and r or "?"
end

local function trim(s, n)
    s = safe(s)
    n = n or LIMITS.Preview
    if #s <= n then return s end
    return string.sub(s, 1, n) .. "...<" .. tostring(#s - n) .. " more>"
end

local function lower(s)
    return string.lower(safe(s))
end

local function containsKeyword(s)
    local x = lower(s)
    for _, k in ipairs(KEYWORDS) do
        if string.find(x, k, 1, true) then return true end
    end
    return false
end

local function hostOf(url)
    return (safe(url):match("^https?://([^/%?]+)") or "")
end

local function sensitiveKey(k)
    k = lower(k)
    return k:find("key",1,true)
        or k:find("token",1,true)
        or k:find("auth",1,true)
        or k:find("secret",1,true)
        or k:find("session",1,true)
        or k:find("cookie",1,true)
        or k:find("password",1,true)
end

local function redactUrl(url)
    url = safe(url)
    local base, query = url:match("^([^?]+)%?(.*)$")
    if not query then return url end
    local out = {}
    for part in query:gmatch("[^&]+") do
        local k, v = part:match("^([^=]+)=(.*)$")
        if k then
            if sensitiveKey(k) then
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

local function redactHeaders(h)
    if type(h) ~= "table" then return nil end
    local out = {}
    local count = 0
    for k, v in pairs(h) do
        count += 1
        if count > 30 then break end
        if sensitiveKey(k) then
            out[safe(k)] = "<redacted>"
        else
            out[safe(k)] = trim(v,120)
        end
    end
    return out
end

local function simpleFingerprint(s)
    if type(s) ~= "string" then return "?" end
    local n = #s
    local a = n > 0 and string.byte(s,1) or 0
    local b = n > 1 and string.byte(s,math.floor(n/2)) or 0
    local c = n > 0 and string.byte(s,n) or 0
    local d = 0
    local step = math.max(1, math.floor(n / 16))
    for i=1,n,step do d = (d + string.byte(s,i) * ((i % 251)+1)) % 2147483647 end
    return table.concat({n,a,b,c,d},":")
end

local function looksLikeLua(body, url)
    if type(body) ~= "string" or #body < 20 then return false end
    local u = lower(url or "")
    local p = string.sub(body,1,1000)
    if u:find(".lua",1,true) or u:find("raw.githubusercontent.com",1,true) then return true end
    if p:find("loadstring",1,true) or p:find("getgenv",1,true) or p:find("game:GetService",1,true) then return true end
    if p:find("-- This file was protected using Luraph",1,true) then return true end
    if p:match("^%s*return%s") or p:match("^%s*local%s") then return true end
    return false
end

local function payloadName(kind, index)
    return string.format("Psico_Nasi_V2_%s_%03d_%d.lua.txt", kind, index, os.time())
end

local function savePayload(kind, body, source)
    if type(body) ~= "string" then return nil end
    if #State.Payloads >= LIMITS.Payloads then return nil end

    local fp = simpleFingerprint(body)
    if State.SeenPayloads[fp] then return State.SeenPayloads[fp] end

    local idx = #State.Payloads + 1
    local filename = payloadName(kind, idx)
    local wrote = false
    local note = nil

    if #body <= LIMITS.MaxSavedPayloadBytes and type(writefile) == "function" then
        local ok, err = pcall(writefile, filename, body)
        wrote = ok
        if not ok then note = trim(err,200) end
    elseif #body > LIMITS.MaxSavedPayloadBytes then
        note = "payload_too_large_for_auto_save"
    else
        note = "writefile_unavailable"
    end

    local row = {
        id = idx,
        t = now(),
        unix = os.time(),
        phase = State.Phase,
        kind = kind,
        source = redactUrl(source or ""),
        bytes = #body,
        fingerprint = fp,
        file = wrote and filename or nil,
        saved = wrote,
        note = note,
        preview = trim(body, LIMITS.Preview),
    }
    State.Payloads[idx] = row
    State.SeenPayloads[fp] = row
    return row
end

local function pushBounded(list, row, max)
    list[#list+1] = row
    if #list > max then table.remove(list,1) end
end

local function recordRequest(source, method, url, opts, response, okFlag, err)
    if not State.Alive then return end

    local status, body, headers
    if type(response) == "table" then
        status = response.StatusCode or response.Status or response.status_code or response.status
        body = response.Body or response.body or response.ResponseBody or response.responseBody
        headers = response.Headers or response.headers
    elseif type(response) == "string" then
        status = 200
        body = response
    end

    local savedPayload
    if looksLikeLua(body, url) then
        savedPayload = savePayload("http", body, url)
    end

    local row = {
        t = now(),
        unix = os.time(),
        phase = State.Phase,
        source = source,
        method = safe(method or "GET"),
        url = redactUrl(url or "?"),
        host = hostOf(url or ""),
        status = status,
        bytes = type(body)=="string" and #body or nil,
        ok = okFlag,
        error = err and trim(err,300) or nil,
        requestHeaders = type(opts)=="table" and redactHeaders(opts.Headers or opts.headers) or nil,
        responseHeaders = redactHeaders(headers),
        luaPayloadId = savedPayload and savedPayload.id or nil,
    }
    pushBounded(State.Requests,row,LIMITS.Requests)
end

local function wrapRequest(holder,key,label)
    local ok, original = pcall(function() return holder and holder[key] end)
    if not ok or type(original) ~= "function" then return false end

    local wrapper
    wrapper = function(opts,...)
        local url, method = "?", "GET"
        if type(opts)=="table" then
            url = opts.Url or opts.URL or opts.url or "?"
            method = opts.Method or opts.method or "GET"
        elseif type(opts)=="string" then
            url = opts
        end

        local packed = table.pack(pcall(original,opts,...))
        if packed[1] then
            recordRequest(label,method,url,opts,packed[2],true,nil)
            return table.unpack(packed,2,packed.n)
        else
            recordRequest(label,method,url,opts,nil,false,packed[2])
            error(packed[2],0)
        end
    end

    local setOk = pcall(function() holder[key] = wrapper end)
    if setOk then
        State.Originals[#State.Originals+1] = {holder=holder,key=key,fn=original,wrapper=wrapper}
    end
    return setOk
end

local function installRequestHooks()
    local seen = {}
    local function add(holder,key,label)
        local ok,fn = pcall(function() return holder and holder[key] end)
        if ok and type(fn)=="function" and not seen[fn] then
            if wrapRequest(holder,key,label) then seen[fn]=true end
        end
    end
    for _,name in ipairs({"request","http_request","httprequest"}) do add(G,name,name) end
    if type(G.syn)=="table" then add(G.syn,"request","syn.request") end
    if type(G.http)=="table" then add(G.http,"request","http.request") end
    if type(G.fluxus)=="table" then add(G.fluxus,"request","fluxus.request") end
end

local function installLoadstringWrapper()
    local original = rawget(G,"loadstring") or loadstring
    if type(original) ~= "function" then return end

    local wrapper
    wrapper = function(source, chunkname, ...)
        if State.Alive and type(source)=="string" then
            local p = savePayload("loadstring",source,chunkname or "loadstring")
            pushBounded(State.Loadstrings,{
                t=now(), unix=os.time(), phase=State.Phase,
                bytes=#source, fingerprint=simpleFingerprint(source),
                chunkname=chunkname and trim(chunkname,180) or nil,
                payloadId=p and p.id or nil,
            },LIMITS.Loadstrings)
        end
        return original(source,chunkname,...)
    end

    local ok = pcall(function() G.loadstring = wrapper end)
    if ok then State.Originals[#State.Originals+1]={holder=G,key="loadstring",fn=original,wrapper=wrapper} end

    if G ~= _G then
        local oldGlobal = rawget(_G,"loadstring")
        if type(oldGlobal)=="function" and oldGlobal==original then
            local ok2=pcall(function() _G.loadstring=wrapper end)
            if ok2 then State.Originals[#State.Originals+1]={holder=_G,key="loadstring",fn=oldGlobal,wrapper=wrapper} end
        end
    end
end

local function summarizeArg(v, depth)
    depth = depth or 0
    local tv = typeof(v)
    if tv=="string" then return trim(v,LIMITS.ArgPreview) end
    if tv=="number" or tv=="boolean" or tv=="nil" then return v end
    if tv=="Instance" then
        local ok,r=pcall(function() return v:GetFullName() end)
        return ok and r or safe(v)
    end
    if tv=="table" and depth < 1 then
        local out,n={},0
        for k,x in pairs(v) do
            n += 1
            if n>12 then out["<more>"]="..." break end
            local ks=safe(k)
            if sensitiveKey(ks) then out[ks]="<redacted>"
            else out[ks]=summarizeArg(x,depth+1) end
        end
        return out
    end
    return "<"..tv..":"..trim(v,80)..">"
end

local oldNamecall
local function installNamecallHook()
    if type(hookmetamethod)~="function" or type(getnamecallmethod)~="function" then return end

    local closure
    closure = function(self,...)
        local method = getnamecallmethod()

        if State.Alive and (method=="HttpGet" or method=="HttpGetAsync") then
            local args={...}
            local url=args[1]
            local packed=table.pack(pcall(oldNamecall,self,...))
            if packed[1] then
                recordRequest("game:"..method,"GET",url,nil,packed[2],true,nil)
                return table.unpack(packed,2,packed.n)
            else
                recordRequest("game:"..method,"GET",url,nil,nil,false,packed[2])
                error(packed[2],0)
            end
        end

        if State.Alive and (method=="FireServer" or method=="InvokeServer") then
            local full=""
            local ok=pcall(function() full=self:GetFullName() end)
            if not ok then full=safe(self) end
            if containsKeyword(full) then
                local args={...}
                local a={}
                for i=1,math.min(#args,10) do a[i]=summarizeArg(args[i],0) end
                local row={
                    t=now(), unix=os.time(), phase=State.Phase,
                    method=method, remote=full, args=a,
                }

                if method=="InvokeServer" then
                    local packed=table.pack(pcall(oldNamecall,self,...))
                    if packed[1] then
                        row.ok=true
                        local returns={}
                        for i=2,math.min(packed.n,7) do returns[#returns+1]=summarizeArg(packed[i],0) end
                        row.returns=returns
                        pushBounded(State.Remotes,row,LIMITS.Remotes)
                        return table.unpack(packed,2,packed.n)
                    else
                        row.ok=false; row.error=trim(packed[2],220)
                        pushBounded(State.Remotes,row,LIMITS.Remotes)
                        error(packed[2],0)
                    end
                else
                    pushBounded(State.Remotes,row,LIMITS.Remotes)
                end
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

local function compactGlobal(v)
    local tv=typeof(v)
    if tv=="string" then return {type=tv,value=trim(v,180)} end
    if tv=="number" or tv=="boolean" then return {type=tv,value=v} end
    if tv=="table" then
        local n=0
        for _ in pairs(v) do n+=1;if n>1000 then break end end
        return {type=tv,count=n}
    end
    return {type=tv}
end

local function captureGlobals()
    local out,count={},0
    local function addFrom(tbl,prefix)
        if type(tbl)~="table" then return end
        for k,v in pairs(tbl) do
            count += 1
            if count>LIMITS.GlobalKeys then return end
            local ks=prefix..safe(k)
            if not sensitiveKey(ks) then out[ks]=compactGlobal(v) end
        end
    end
    addFrom(G,"G:")
    if G~=_G then addFrom(_G,"_G:") end
    return out
end

local function diffMaps(old,new)
    local added,changed={},{}
    for k,v in pairs(new) do
        if old[k]==nil then
            added[k]=v
        else
            local ok1,a=pcall(HttpService.JSONEncode,HttpService,old[k])
            local ok2,b=pcall(HttpService.JSONEncode,HttpService,v)
            if ok1 and ok2 and a~=b then changed[k]={before=old[k],after=v} end
        end
    end
    return added,changed
end

local function guiRoots()
    local roots={}
    local ok,h=pcall(function() return gethui and gethui() end)
    if ok and h then roots[#roots+1]=h end
    roots[#roots+1]=CoreGui
    local pg=LP and LP:FindFirstChildOfClass("PlayerGui")
    if pg then roots[#roots+1]=pg end
    return roots
end

local function captureUI()
    local set,out={},{}
    for _,root in ipairs(guiRoots()) do
        local ok,desc=pcall(function() return root:GetDescendants() end)
        if ok then
            for _,x in ipairs(desc) do
                if #out>=LIMITS.UITexts then break end
                local isText=x:IsA("TextLabel") or x:IsA("TextButton") or x:IsA("TextBox")
                if isText then
                    local okT,txt=pcall(function() return x.Text end)
                    if okT and type(txt)=="string" and txt~="" and #txt<=800 then
                        local key=txt
                        if not set[key] then
                            set[key]=true
                            local full=safe(x)
                            pcall(function() full=x:GetFullName() end)
                            out[#out+1]={text=txt,path=full}
                        end
                    end
                end
            end
        end
    end
    return out,set
end

local function snapshot(label)
    local globals=captureGlobals()
    local ui,uiSet=captureUI()
    local addedG,changedG=diffMaps(State.GlobalBaseline,globals)
    local newUI={}
    for _,r in ipairs(ui) do if not State.UiBaseline[r.text] then newUI[#newUI+1]=r end end

    local row={
        t=now(), unix=os.time(), phase=State.Phase, label=label,
        globalsAdded=addedG, globalsChanged=changedG,
        newUITexts=newUI,
        counts={requests=#State.Requests,loadstrings=#State.Loadstrings,remotes=#State.Remotes,payloads=#State.Payloads}
    }
    State.Snapshots[#State.Snapshots+1]=row
    State.GlobalBaseline=globals
    State.UiBaseline=uiSet
    return row
end

local function markPhase(name)
    State.Phase=name
    State.Marks[#State.Marks+1]={t=now(),unix=os.time(),phase=name}
    snapshot("phase:"..name)
end

local function report()
    local domains={}
    for _,r in ipairs(State.Requests) do if r.host and r.host~="" then domains[r.host]=(domains[r.host] or 0)+1 end end
    return {
        Meta={
            Version="NasiPredictorInterceptorV2",
            PlaceId=game.PlaceId,
            GameId=game.GameId,
            JobId=game.JobId,
            StartedUnix=START_UNIX,
            FinishedUnix=os.time(),
            FinalPhase=State.Phase,
            Note="Low-impact observational capture. Sensitive auth/cookie/query values are redacted. Lua-like payload bodies are stored as separate local files when writefile is available."
        },
        Summary={
            Requests=#State.Requests,
            Loadstrings=#State.Loadstrings,
            Remotes=#State.Remotes,
            Payloads=#State.Payloads,
            Snapshots=#State.Snapshots,
            Domains=domains,
        },
        Marks=State.Marks,
        Requests=State.Requests,
        Loadstrings=State.Loadstrings,
        Remotes=State.Remotes,
        Payloads=State.Payloads,
        Snapshots=State.Snapshots,
    }
end

local function setStatus(text)
    if State.Status and State.Status.Parent then State.Status.Text=text end
end

local function exportJson()
    snapshot("export")
    local ok,json=pcall(HttpService.JSONEncode,HttpService,report())
    if not ok then setStatus("Erro ao gerar JSON: "..trim(json,220));return end

    local name="Psico_Nasi_Predictor_Interceptor_V2_"..tostring(os.time())..".json"
    local wrote=false
    if type(writefile)=="function" then wrote=pcall(writefile,name,json) end
    if type(setclipboard)=="function" then pcall(setclipboard,json) end
    setStatus((wrote and "Exportado: " or "JSON copiado: ")..name.."\nPayloads salvos: "..#State.Payloads.." | Requests: "..#State.Requests.." | Remotes: "..#State.Remotes)
end

local function parentGui()
    local ok,h=pcall(function() return gethui and gethui() end)
    return (ok and h) or CoreGui
end

local function makeButton(parent,text,pos,size)
    local b=Instance.new("TextButton")
    b.Position=pos;b.Size=size;b.BackgroundColor3=Color3.fromRGB(27,67,114);b.BorderSizePixel=0
    b.Text=text;b.TextColor3=Color3.fromRGB(240,247,255);b.Font=Enum.Font.GothamBold;b.TextSize=11;b.Parent=parent
    Instance.new("UICorner",b).CornerRadius=UDim.new(0,8)
    return b
end

local function makeGui()
    local p=parentGui()
    local old=p:FindFirstChild("PSICO_NASI_PREDICTOR_INTERCEPTOR_V2")
    if old then old:Destroy() end

    local gui=Instance.new("ScreenGui")
    gui.Name="PSICO_NASI_PREDICTOR_INTERCEPTOR_V2";gui.ResetOnSpawn=false;gui.DisplayOrder=1200;gui.Parent=p
    State.Gui=gui

    local frame=Instance.new("Frame")
    frame.AnchorPoint=Vector2.new(.5,.5);frame.Position=UDim2.fromScale(.5,.5);frame.Size=UDim2.fromOffset(440,260)
    frame.BackgroundColor3=Color3.fromRGB(10,19,36);frame.BorderSizePixel=0;frame.Parent=gui
    Instance.new("UICorner",frame).CornerRadius=UDim.new(0,14)

    local title=Instance.new("TextLabel")
    title.BackgroundTransparency=1;title.Position=UDim2.fromOffset(14,9);title.Size=UDim2.new(1,-28,0,28)
    title.Font=Enum.Font.GothamBold;title.Text="NASI PREDICTOR INTERCEPTOR • V2";title.TextSize=14
    title.TextColor3=Color3.fromRGB(235,244,255);title.TextXAlignment=Enum.TextXAlignment.Left;title.Parent=frame

    local status=Instance.new("TextLabel")
    status.Position=UDim2.fromOffset(14,43);status.Size=UDim2.new(1,-28,0,92);status.BackgroundColor3=Color3.fromRGB(15,29,52)
    status.BorderSizePixel=0;status.Font=Enum.Font.Code;status.TextSize=11;status.TextColor3=Color3.fromRGB(214,228,247)
    status.TextXAlignment=Enum.TextXAlignment.Left;status.TextYAlignment=Enum.TextYAlignment.Top;status.Parent=frame
    Instance.new("UICorner",status).CornerRadius=UDim.new(0,9)
    local pad=Instance.new("UIPadding",status);pad.PaddingLeft=UDim.new(0,8);pad.PaddingTop=UDim.new(0,7)
    State.Status=status
    setStatus("Ativo • fase: game_select\nAgora selecione Steal An Egg no Nasi.\nDepois use MARCAR FASE PREDICTOR antes de abrir a aba Predictor.")

    local mark=makeButton(frame,"MARCAR FASE PREDICTOR",UDim2.fromOffset(14,146),UDim2.new(.5,-20,0,34))
    local snap=makeButton(frame,"SNAPSHOT",UDim2.new(.5,6,0,146),UDim2.new(.5,-20,0,34))
    local export=makeButton(frame,"EXPORTAR JSON",UDim2.fromOffset(14,190),UDim2.new(.65,-20,0,34))
    local close=makeButton(frame,"FECHAR",UDim2.new(.65,6,0,190),UDim2.new(.35,-20,0,34))

    mark.MouseButton1Click:Connect(function()
        markPhase("predictor")
        setStatus("Fase PREDICTOR marcada.\nAbra/atualize a aba Predictor no Nasi e aguarde alguns segundos.\nDepois pressione SNAPSHOT.")
    end)
    snap.MouseButton1Click:Connect(function()
        local s=snapshot("manual")
        setStatus("Snapshot registrado.\nNovos textos UI: "..#s.newUITexts.."\nRequests: "..#State.Requests.." | Loadstrings: "..#State.Loadstrings.." | Remotes: "..#State.Remotes)
    end)
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
        while State.Alive and status.Parent do
            task.wait(1)
            if State.Phase~="game_select" and State.Phase~="predictor" then continue end
            local last=State.Requests[#State.Requests]
            local tail=last and ("\nUltimo host: "..(last.host~="" and last.host or "?")) or ""
            status.Text="Ativo • fase: "..State.Phase.."\nReq "..#State.Requests.." | LS "..#State.Loadstrings.." | Remote "..#State.Remotes.." | Payload "..#State.Payloads..tail
        end
    end)
end

_G.PSICO_NASI_INTERCEPTOR_V2_CLEANUP=function()
    State.Alive=false
    for i=#State.Originals,1,-1 do
        local x=State.Originals[i]
        pcall(function()
            if x.holder[x.key]==x.wrapper then x.holder[x.key]=x.fn end
        end)
    end
    if State.Gui then pcall(function() State.Gui:Destroy() end) end
end

State.GlobalBaseline=captureGlobals()
local _,baselineSet=captureUI()
State.UiBaseline=baselineSet
State.Marks[#State.Marks+1]={t=now(),unix=os.time(),phase="game_select"}

installRequestHooks()
installLoadstringWrapper()
installNamecallHook()
makeGui()

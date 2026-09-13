--[[
PSICOSENATICO | Steal an Egg - Predictor Traffic Observer V1

OBJETIVO
- observar requisicoes HTTP feitas por hubs de prediction carregados DEPOIS deste observer
- registrar dominios, URL redigida, metodo, status e trechos de resposta relevantes
- observar chunks enviados para loadstring e procurar URLs/palavras ligadas a prediction

IMPORTANTE
- execute ESTE observer primeiro
- depois execute o hub alvo (ex.: Nasi Rendang)
- abra a aba de predictor e altere "Hours Ahead"/filtros se existirem
- por fim clique EXPORTAR JSON

SEGURANCA
- nao altera ovos, ciclo, sorte, velocidade ou remotes do jogo
- nao bloqueia nem modifica respostas HTTP
- tenta redigir token/key/auth/license/password/secret/cookie dos logs
]]

if _G.PSICO_PREDICT_OBSERVER_CLEANUP then pcall(_G.PSICO_PREDICT_OBSERVER_CLEANUP) end

local Players=game:GetService("Players")
local CoreGui=game:GetService("CoreGui")
local Http=game:GetService("HttpService")
local UIS=game:GetService("UserInputService")
local Workspace=game:GetService("Workspace")
local LP=Players.LocalPlayer
local G=(getgenv and getgenv()) or _G

local START=os.clock()
local START_UNIX=os.time()
local S={Alive=true,Events={},Requests={},Loads={},Originals={},Gui=nil}

local KEYWORDS={
    "predict","prediction","egg","spawn","upcoming","hours ahead","rare","rarity",
    "divine","eternal","secret","superior","periodindex","daystartsat","rarespawns",
    "server hop","serverhop","forecast","schedule","cycle","seed","random"
}
local SENSITIVE={"key","token","auth","authorization","license","password","passwd","pass","secret","cookie","session"}

local function now() return os.clock()-START end
local function lower(v) return string.lower(tostring(v or "")) end
local function finite(v) return type(v)=="number" and v==v and v~=math.huge and v~=-math.huge end
local function safe(v) local ok,r=pcall(tostring,v) return ok and r or "?" end
local function trim(s,n) s=safe(s);n=n or 16000;if #s>n then return string.sub(s,1,n).."<truncated:"..tostring(#s)..">" end return s end
local function isSensitive(k)
    local q=lower(k)
    for _,x in ipairs(SENSITIVE) do if string.find(q,x,1,true) then return true end end
    return false
end
local function containsKeyword(v)
    local q=lower(v)
    for _,k in ipairs(KEYWORDS) do if string.find(q,k,1,true) then return true,k end end
    return false,nil
end

local function redactUrl(url)
    url=safe(url)
    local base,query=url:match("^([^?]+)%?(.*)$")
    if not query then return url end
    local out={}
    for part in string.gmatch(query,"[^&]+") do
        local k,v=part:match("^([^=]+)=(.*)$")
        if k then
            out[#out+1]=k.."="..(isSensitive(k) and "<redacted>" or trim(v,300))
        else
            out[#out+1]=part
        end
    end
    return base.."?"..table.concat(out,"&")
end

local function redactHeaders(h)
    if typeof(h)~="table" then return nil end
    local out={}
    for k,v in pairs(h) do out[safe(k)]=isSensitive(k) and "<redacted>" or trim(v,500) end
    return out
end

local function redactText(s)
    s=trim(s,18000)
    for _,k in ipairs(SENSITIVE) do
        local p='(["\']?'..k..'["\']?%s*[:=]%s*["\']?)[^"\'&,}%s]+'
        pcall(function() s=s:gsub(p,'%1<redacted>') end)
    end
    return s
end

local function event(kind,data)
    local row={t=now(),unix=os.time(),serverTime=(pcall(function()return Workspace:GetServerTimeNow()end) and Workspace:GetServerTimeNow() or nil),kind=kind,data=data}
    S.Events[#S.Events+1]=row
    if #S.Events>1200 then table.remove(S.Events,1) end
    return row
end

local function serialize(v,d,seen)
    d=d or 0;seen=seen or {}
    if d>5 then return "<depth>" end
    local t=typeof(v)
    if t=="nil" or t=="boolean" or t=="string" then return v end
    if t=="number" then return finite(v) and v or safe(v) end
    if t=="Instance" then return {class=v.ClassName,name=v.Name,path=v:GetFullName()} end
    if t~="table" then return safe(v) end
    if seen[v] then return "<cycle>" end
    seen[v]=true
    local o,n={},0
    for k,x in pairs(v) do
        n=n+1;if n>180 then o.__truncated=true break end
        o[(type(k)=="string" or type(k)=="number") and k or safe(k)]=serialize(x,d+1,seen)
    end
    seen[v]=nil
    return o
end

local function responseInfo(resp)
    if typeof(resp)~="table" then return {type=typeof(resp),value=trim(resp,3000)} end
    local body=resp.Body or resp.body or resp.ResponseBody or resp.responseBody
    local code=resp.StatusCode or resp.Status or resp.status_code or resp.status
    local headers=resp.Headers or resp.headers
    local relevant=false
    local keyword=nil
    if type(body)=="string" then relevant,keyword=containsKeyword(body) end
    return {
        status=code,
        success=resp.Success,
        headers=redactHeaders(headers),
        bodyLength=type(body)=="string" and #body or nil,
        relevant=relevant,
        keyword=keyword,
        bodyPreview=(type(body)=="string" and (relevant or (#body<4000))) and redactText(body) or nil,
    }
end

local function logRequest(source,opts,resp,err)
    local url,method,headers,body
    if type(opts)=="string" then url=opts;method="GET" else
        opts=typeof(opts)=="table" and opts or {}
        url=opts.Url or opts.URL or opts.url
        method=opts.Method or opts.method or "GET"
        headers=opts.Headers or opts.headers
        body=opts.Body or opts.body
    end
    local row={
        t=now(),unix=os.time(),source=source,
        url=redactUrl(url or "?"),method=safe(method),
        headers=redactHeaders(headers),
        bodyPreview=type(body)=="string" and redactText(body) or nil,
        response=resp and responseInfo(resp) or nil,
        error=err and trim(err,1000) or nil,
    }
    S.Requests[#S.Requests+1]=row
    if #S.Requests>600 then table.remove(S.Requests,1) end
    event("http",{source=source,url=row.url,method=row.method,status=row.response and row.response.status,relevant=row.response and row.response.relevant})
end

local function wrapRequestTable(holder,key,label)
    local ok,fn=pcall(function() return holder[key] end)
    if not ok or type(fn)~="function" then return false end
    S.Originals[#S.Originals+1]={holder=holder,key=key,fn=fn}
    local wrapper=function(opts,...)
        local packed=table.pack(pcall(fn,opts,...))
        if packed[1] then
            logRequest(label,opts,packed[2],nil)
            return table.unpack(packed,2,packed.n)
        else
            logRequest(label,opts,nil,packed[2])
            error(packed[2],0)
        end
    end
    return pcall(function() holder[key]=wrapper end)
end

local function installRequestHooks()
    local hooked={}
    local function add(holder,key,label)
        local ok,fn=pcall(function()return holder and holder[key]end)
        if ok and type(fn)=="function" and not hooked[fn] then
            if wrapRequestTable(holder,key,label) then hooked[fn]=true;event("hook",{target=label}) end
        end
    end
    for _,name in ipairs({"request","http_request","httprequest"}) do add(G,name,name) end
    if type(G.syn)=="table" then add(G.syn,"request","syn.request") end
    if type(G.http)=="table" then add(G.http,"request","http.request") end
    if type(G.fluxus)=="table" then add(G.fluxus,"request","fluxus.request") end
end

local function installLoadstringHook()
    local fn=G.loadstring or loadstring
    if type(fn)~="function" then return end
    S.Originals[#S.Originals+1]={holder=G,key="loadstring",fn=fn}
    local wrapper=function(src,...)
        if type(src)=="string" then
            local rel,key=containsKeyword(src)
            local urls={}
            for u in src:gmatch("https?://[^%s%\"%'%)%]]+") do
                urls[#urls+1]=redactUrl(u)
                if #urls>=30 then break end
            end
            local row={t=now(),unix=os.time(),length=#src,relevant=rel,keyword=key,urls=urls}
            if rel then
                local q=lower(src)
                local pos=nil
                for _,k in ipairs(KEYWORDS) do local p=string.find(q,k,1,true);if p and (not pos or p<pos) then pos=p end end
                if pos then row.preview=redactText(src:sub(math.max(1,pos-1000),math.min(#src,pos+5000))) end
            end
            S.Loads[#S.Loads+1]=row
            if #S.Loads>250 then table.remove(S.Loads,1) end
            event("loadstring",{length=#src,relevant=rel,keyword=key,urlCount=#urls})
        end
        return fn(src,...)
    end
    if pcall(function() G.loadstring=wrapper end) then event("hook",{target="loadstring"}) end
end

local oldNamecall=nil
local function installNamecallHook()
    if type(hookmetamethod)~="function" or type(getnamecallmethod)~="function" then return end
    local ok,res=pcall(function()
        oldNamecall=hookmetamethod(game,"__namecall",newcclosure and newcclosure(function(self,...)
            local method=getnamecallmethod()
            if S.Alive and (method=="HttpGet" or method=="HttpGetAsync") then
                local args={...};local url=args[1]
                local packed=table.pack(pcall(oldNamecall,self,...))
                if packed[1] then
                    local body=packed[2]
                    logRequest("game:"..method,url,{StatusCode=200,Body=body},nil)
                    return table.unpack(packed,2,packed.n)
                else
                    logRequest("game:"..method,url,nil,packed[2]);error(packed[2],0)
                end
            end
            return oldNamecall(self,...)
        end) or function(self,...)
            local method=getnamecallmethod()
            if S.Alive and (method=="HttpGet" or method=="HttpGetAsync") then
                local args={...};local url=args[1]
                local packed=table.pack(pcall(oldNamecall,self,...))
                if packed[1] then logRequest("game:"..method,url,{StatusCode=200,Body=packed[2]},nil);return table.unpack(packed,2,packed.n) end
                logRequest("game:"..method,url,nil,packed[2]);error(packed[2],0)
            end
            return oldNamecall(self,...)
        end)
    end)
    if ok and res then event("hook",{target="__namecall HttpGet"}) end
end

local function report()
    local domains={}
    for _,r in ipairs(S.Requests) do
        local host=(r.url or ""):match("^https?://([^/%?]+)")
        if host then domains[host]=(domains[host] or 0)+1 end
    end
    return {
        Meta={Version="PredictorTrafficObserverV1",PlaceId=game.PlaceId,GameId=game.GameId,JobId=game.JobId,StartedUnix=START_UNIX,FinishedUnix=os.time(),Notes="Run observer before third-party predictor. Sensitive-looking keys/tokens/headers are redacted when possible."},
        Summary={Requests=#S.Requests,Loadstrings=#S.Loads,Events=#S.Events,Domains=domains},
        Requests=S.Requests,Loads=S.Loads,Events=S.Events,
    }
end

local function exportJson()
    local ok,json=pcall(Http.JSONEncode,Http,report())
    if not ok then return false,safe(json) end
    local name="Psico_NasiPrediction_Traffic_"..tostring(os.time())..".json"
    local wrote=false
    if writefile then wrote=pcall(writefile,name,json) end
    if setclipboard then pcall(setclipboard,json) end
    return true,name,wrote,#json
end

local function parent()
    local ok,h=pcall(function()return gethui and gethui()end)
    return ok and h or CoreGui
end

local function makeGui()
    local p=parent();local old=p:FindFirstChild("PSICO_PREDICT_TRAFFIC_V1");if old then old:Destroy() end
    local gui=Instance.new("ScreenGui");gui.Name="PSICO_PREDICT_TRAFFIC_V1";gui.ResetOnSpawn=false;gui.DisplayOrder=1000;gui.Parent=p;S.Gui=gui
    local f=Instance.new("Frame");f.AnchorPoint=Vector2.new(.5,.5);f.Position=UDim2.fromScale(.5,.48);f.Size=UDim2.fromOffset(430,235);f.BackgroundColor3=Color3.fromRGB(10,19,36);f.BorderSizePixel=0;f.Parent=gui
    local c=Instance.new("UICorner");c.CornerRadius=UDim.new(0,14);c.Parent=f
    local title=Instance.new("TextLabel");title.BackgroundTransparency=1;title.Position=UDim2.fromOffset(14,8);title.Size=UDim2.new(1,-55,0,28);title.Font=Enum.Font.GothamBold;title.Text="PREDICTOR TRAFFIC OBSERVER";title.TextSize=15;title.TextColor3=Color3.fromRGB(235,244,255);title.TextXAlignment=Enum.TextXAlignment.Left;title.Parent=f
    local status=Instance.new("TextLabel");status.BackgroundColor3=Color3.fromRGB(15,29,52);status.Position=UDim2.fromOffset(14,48);status.Size=UDim2.new(1,-28,0,105);status.BorderSizePixel=0;status.Font=Enum.Font.Code;status.TextSize=11;status.TextColor3=Color3.fromRGB(214,228,247);status.TextXAlignment=Enum.TextXAlignment.Left;status.TextYAlignment=Enum.TextYAlignment.Top;status.Parent=f
    local sc=Instance.new("UICorner");sc.CornerRadius=UDim.new(0,9);sc.Parent=status
    local pad=Instance.new("UIPadding");pad.PaddingLeft=UDim.new(0,9);pad.PaddingTop=UDim.new(0,7);pad.Parent=status
    local exp=Instance.new("TextButton");exp.Position=UDim2.new(0,14,1,-58);exp.Size=UDim2.new(.62,-18,0,34);exp.BackgroundColor3=Color3.fromRGB(28,74,125);exp.BorderSizePixel=0;exp.Text="EXPORTAR JSON";exp.TextColor3=Color3.fromRGB(240,247,255);exp.Font=Enum.Font.GothamBold;exp.TextSize=12;exp.Parent=f
    local ec=Instance.new("UICorner");ec.CornerRadius=UDim.new(0,9);ec.Parent=exp
    local close=Instance.new("TextButton");close.Position=UDim2.new(.62,4,1,-58);close.Size=UDim2.new(.38,-18,0,34);close.BackgroundColor3=Color3.fromRGB(48,56,72);close.BorderSizePixel=0;close.Text="FECHAR";close.TextColor3=Color3.fromRGB(238,242,248);close.Font=Enum.Font.GothamBold;close.TextSize=12;close.Parent=f
    local cc=Instance.new("UICorner");cc.CornerRadius=UDim.new(0,9);cc.Parent=close

    local function refresh(msg)
        local rel=0
        for _,r in ipairs(S.Requests) do if r.response and r.response.relevant then rel=rel+1 end end
        status.Text=table.concat({msg or "Observando...","1) Agora execute o hub alvo.","2) Abra Prediction / Upcoming Eggs e altere Hours Ahead.",string.format("HTTP capturados: %d | relevantes: %d",#S.Requests,rel),string.format("loadstring capturados: %d",#S.Loads)},"\n")
    end
    S.Refresh=refresh
    exp.Activated:Connect(function()
        exp.Text="EXPORTANDO...";task.defer(function()local ok,name,wrote,bytes=exportJson();refresh(ok and ((wrote and "Salvo: " or "Copiado: ")..name.." • "..tostring(bytes).." bytes") or ("Erro: "..safe(name)));exp.Text="EXPORTAR JSON" end)
    end)
    close.Activated:Connect(function()if _G.PSICO_PREDICT_OBSERVER_CLEANUP then _G.PSICO_PREDICT_OBSERVER_CLEANUP() end end)
    local dragging=false;local ds,sp
    f.InputBegan:Connect(function(i)if i.UserInputType==Enum.UserInputType.Touch or i.UserInputType==Enum.UserInputType.MouseButton1 then dragging=true;ds=i.Position;sp=f.Position end end)
    UIS.InputChanged:Connect(function(i)if dragging and (i.UserInputType==Enum.UserInputType.Touch or i.UserInputType==Enum.UserInputType.MouseMovement) then local d=i.Position-ds;f.Position=UDim2.new(sp.X.Scale,sp.X.Offset+d.X,sp.Y.Scale,sp.Y.Offset+d.Y) end end)
    UIS.InputEnded:Connect(function(i)if i.UserInputType==Enum.UserInputType.Touch or i.UserInputType==Enum.UserInputType.MouseButton1 then dragging=false end end)
    task.spawn(function()while S.Alive and gui.Parent do task.wait(1);refresh() end end)
    refresh("Observer pronto ANTES do hub.")
end

local function cleanup()
    if not S.Alive then return end
    S.Alive=false
    for _,o in ipairs(S.Originals) do pcall(function()if o.holder[o.key]~=o.fn then o.holder[o.key]=o.fn end end) end
    if S.Gui then pcall(function()S.Gui:Destroy()end) end
    _G.PSICO_PREDICT_OBSERVER_CLEANUP=nil
end
_G.PSICO_PREDICT_OBSERVER_CLEANUP=cleanup

installRequestHooks()
installLoadstringHook()
installNamecallHook()
makeGui()
event("ready",{placeId=game.PlaceId,jobId=game.JobId})

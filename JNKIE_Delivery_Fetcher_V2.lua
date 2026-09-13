--[[
PSICOSENATICO | JNKIE Delivery Fetcher V2

OBJETIVO
- reproduzir SOMENTE o fluxo de entrega historico do Nasi Rendang
- POST com SCRIPT_KEY=KEYLESS para o endpoint /delivery
- seguir apenas URL https://cdn.jnkie.com/ retornada pelo servidor
- salvar o payload bruto em arquivo
- gerar resumo JSON com URLs/keywords/metadata
- NUNCA executar loadstring do payload recebido

NAO altera ovos, remotes, sorte, ciclo, velocidade ou combate.
]]

if _G.PSICO_JNKIE_V2_CLEANUP then pcall(_G.PSICO_JNKIE_V2_CLEANUP) end

local Players=game:GetService("Players")
local CoreGui=game:GetService("CoreGui")
local Http=game:GetService("HttpService")
local UIS=game:GetService("UserInputService")
local Workspace=game:GetService("Workspace")
local LP=Players.LocalPlayer

local DELIVERY="https://api.jnkie.com/api/v1/luascripts/delivery/c090866e4201baecfe09dce16546ea747661d2d0861ae16f1eacf1d98dee3e3c?v=2&errors=text"
local KEY="KEYLESS"
local CDN_PREFIX="https://cdn.jnkie.com/"
local START=os.clock()

local KEYWORDS={
    "predict","prediction","egg","spawn","upcoming","hours ahead","rarity",
    "divine","eternal","secret","cosmic","periodindex","daystartsat","rarespawns",
    "serverhop","server hop","forecast","schedule","cycle","seed","random",
    "assetlottery","fieldegg","askfieldeggrarityshows"
}

local S={
    delivery=nil,
    cdn=nil,
    payload=nil,
    payloadFile=nil,
    summaryFile=nil,
    status="Aguardando",
    logs={}
}

local function log(msg)
    local row={t=os.clock()-START,unix=os.time(),msg=tostring(msg)}
    S.logs[#S.logs+1]=row
    print("[PSICO JNKIE V2] "..row.msg)
end

local function getReq()
    return request or http_request or (http and http.request) or (syn and syn.request)
end

local function doRequest(opts)
    local req=getReq()
    if type(req)~="function" then
        return false,{error="executor sem request/http_request"}
    end
    local done,ok,res=false,false,nil
    task.spawn(function()
        ok,res=pcall(req,opts)
        done=true
    end)
    local t0=os.clock()
    repeat task.wait() until done or os.clock()-t0>20
    if not done then return false,{error="timeout 20s"} end
    if not ok then return false,{error=tostring(res)} end
    if type(res)~="table" then return false,{error="resposta nao-table",raw=tostring(res)} end
    return true,res
end

local function header(res,name)
    local h=res.Headers or res.headers
    if type(h)~="table" then return nil end
    return h[name] or h[string.lower(name)] or h[string.upper(name)]
end

local function statusCode(res)
    return tonumber(res.StatusCode or res.Status or res.status_code)
end

local function bodyOf(res)
    local b=res.Body or res.body
    return type(b)=="string" and b or nil
end

local function extractUrls(text)
    local out,seen={},{}
    if type(text)~="string" then return out end
    for u in text:gmatch("https?://[^%s%'%\"%)%]}>,]+") do
        if not seen[u] then seen[u]=true; out[#out+1]=u end
        if #out>=100 then break end
    end
    return out
end

local function scanKeywords(text)
    local out={}
    if type(text)~="string" then return out end
    local low=string.lower(text)
    for _,k in ipairs(KEYWORDS) do
        if string.find(low,string.lower(k),1,true) then out[#out+1]=k end
    end
    return out
end

local function looksLua(text)
    if type(text)~="string" then return false end
    local low=string.lower(text:sub(1,4000))
    return low:find("local ",1,true)~=nil or low:find("function",1,true)~=nil or low:find("return",1,true)~=nil
end

local function writeSafe(name,data)
    if type(writefile)~="function" then return false,"writefile indisponivel" end
    local ok,err=pcall(writefile,name,data)
    return ok,err
end

local function buildSummary()
    local p=S.payload
    return {
        Meta={
            Version="JNKIEDeliveryFetcherV2",
            PlaceId=game.PlaceId,
            JobId=game.JobId,
            Unix=os.time(),
            ServerTime=Workspace:GetServerTimeNow(),
        },
        Delivery=S.delivery,
        CDN=S.cdn,
        Payload=p and {
            bytes=#p,
            urls=extractUrls(p),
            keywords=scanKeywords(p),
            looksLua=looksLua(p),
            hasLuraph=string.find(string.lower(p),"luraph",1,true)~=nil,
            file=S.payloadFile,
        } or nil,
        Logs=S.logs,
    }
end

local function exportSummary()
    local name="Psico_JNKIE_Delivery_Summary_"..os.time()..".json"
    local ok,err=writeSafe(name,Http:JSONEncode(buildSummary()))
    if ok then
        S.summaryFile=name
        log("Resumo exportado: "..name)
    else
        log("Falha ao exportar resumo: "..tostring(err))
    end
    return ok
end

local function fetchDelivery()
    S.status="Consultando delivery..."
    log("POST delivery com KEYLESS")

    local ok,res=doRequest({
        Url=DELIVERY,
        Method="POST",
        Headers={["Content-Type"]="text/plain",["User-Agent"]="Mozilla/5.0"},
        Body=KEY,
    })

    if not ok then
        S.delivery={ok=false,error=res.error}
        S.status="Falha no delivery"
        log("Delivery falhou: "..tostring(res.error))
        exportSummary()
        return false
    end

    local code=statusCode(res)
    local body=bodyOf(res) or ""
    local loc=header(res,"Location")
    S.delivery={
        ok=true,
        status=code,
        bodyPreview=body:sub(1,1000),
        location=loc,
        bytes=#body,
    }
    log("Delivery HTTP "..tostring(code).." | "..#body.." bytes")

    local cdnUrl=nil
    if code==200 and body:sub(1,#CDN_PREFIX)==CDN_PREFIX then
        cdnUrl=body:match("^(https://cdn%.jnkie%.com/[^%s]+)")
    elseif (code==302 or code==303 or code==307 or code==308) and type(loc)=="string" and loc:sub(1,#CDN_PREFIX)==CDN_PREFIX then
        cdnUrl=loc
    end

    if not cdnUrl then
        S.status="Delivery respondeu sem CDN"
        log("Nenhuma URL cdn.jnkie.com valida retornada")
        exportSummary()
        return false
    end

    S.cdn={url=cdnUrl}
    S.status="Baixando payload CDN..."
    log("GET CDN")

    local ok2,res2=doRequest({
        Url=cdnUrl,
        Method="GET",
        Headers={["User-Agent"]="Mozilla/5.0"},
    })
    if not ok2 then
        S.cdn.ok=false
        S.cdn.error=res2.error
        S.status="Falha na CDN"
        log("CDN falhou: "..tostring(res2.error))
        exportSummary()
        return false
    end

    local code2=statusCode(res2)
    local body2=bodyOf(res2) or ""
    S.cdn.ok=(code2==200 and #body2>0)
    S.cdn.status=code2
    S.cdn.bytes=#body2
    log("CDN HTTP "..tostring(code2).." | "..#body2.." bytes")

    if code2~=200 or #body2==0 then
        S.status="Payload vazio/erro"
        exportSummary()
        return false
    end

    S.payload=body2
    local filename="Psico_JNKIE_Payload_"..os.time()..".lua.txt"
    local wrote,err=writeSafe(filename,body2)
    if wrote then
        S.payloadFile=filename
        log("Payload salvo SEM executar: "..filename)
    else
        log("Nao foi possivel salvar payload: "..tostring(err))
    end

    local keys=scanKeywords(body2)
    log("Keywords encontradas: "..(#keys>0 and table.concat(keys,", ") or "nenhuma"))
    log("URLs encontradas: "..tostring(#extractUrls(body2)))
    log("LooksLua="..tostring(looksLua(body2)).." | Luraph="..tostring(string.find(string.lower(body2),"luraph",1,true)~=nil))

    S.status="Concluido"
    exportSummary()
    return true
end

-- UI simples/mobile
local function guiParent()
    local ok,h=pcall(function() return gethui and gethui() end)
    if ok and h then return h end
    return CoreGui
end

pcall(function()
    local old=guiParent():FindFirstChild("PSICO_JNKIE_V2")
    if old then old:Destroy() end
end)

local gui=Instance.new("ScreenGui")
gui.Name="PSICO_JNKIE_V2"
gui.ResetOnSpawn=false
gui.Parent=guiParent()

local f=Instance.new("Frame")
f.Parent=gui
f.AnchorPoint=Vector2.new(.5,.5)
f.Position=UDim2.fromScale(.5,.5)
f.Size=UDim2.fromOffset(390,205)
f.BackgroundColor3=Color3.fromRGB(12,18,30)
f.BorderSizePixel=0
f.Active=true
Instance.new("UICorner",f).CornerRadius=UDim.new(0,14)

local sc=Instance.new("UIScale")
sc.Parent=f
local cam=workspace.CurrentCamera
local function fit()
    local vp=(cam and cam.ViewportSize) or Vector2.new(800,600)
    sc.Scale=math.clamp(math.min((vp.X-20)/390,(vp.Y-20)/205),.55,1)
end
fit()
if cam then cam:GetPropertyChangedSignal("ViewportSize"):Connect(fit) end

local title=Instance.new("TextLabel")
title.Parent=f
title.BackgroundTransparency=1
title.Position=UDim2.fromOffset(16,10)
title.Size=UDim2.new(1,-32,0,28)
title.Font=Enum.Font.GothamBold
title.TextSize=16
title.TextColor3=Color3.fromRGB(235,240,255)
title.TextXAlignment=Enum.TextXAlignment.Left
title.Text="JNKIE DELIVERY FETCHER V2"

local status=Instance.new("TextLabel")
status.Parent=f
status.BackgroundTransparency=1
status.Position=UDim2.fromOffset(16,42)
status.Size=UDim2.new(1,-32,0,50)
status.Font=Enum.Font.Gotham
status.TextSize=12
status.TextWrapped=true
status.TextColor3=Color3.fromRGB(170,185,210)
status.TextXAlignment=Enum.TextXAlignment.Left
status.TextYAlignment=Enum.TextYAlignment.Top
status.Text="Pronto. O payload sera baixado e salvo, nunca executado."

local function btn(text,x,w,cb)
    local b=Instance.new("TextButton")
    b.Parent=f
    b.Position=UDim2.fromOffset(x,112)
    b.Size=UDim2.fromOffset(w,40)
    b.BackgroundColor3=Color3.fromRGB(24,38,64)
    b.BorderSizePixel=0
    b.Font=Enum.Font.GothamBold
    b.TextSize=12
    b.TextColor3=Color3.fromRGB(235,240,255)
    b.Text=text
    Instance.new("UICorner",b).CornerRadius=UDim.new(0,10)
    b.MouseButton1Click:Connect(cb)
    return b
end

local busy=false
btn("BUSCAR PAYLOAD",16,175,function()
    if busy then return end
    busy=true
    task.spawn(function()
        fetchDelivery()
        busy=false
    end)
end)
btn("EXPORTAR RESUMO",199,175,function()
    exportSummary()
end)

local foot=Instance.new("TextLabel")
foot.Parent=f
foot.BackgroundTransparency=1
foot.Position=UDim2.fromOffset(16,163)
foot.Size=UDim2.new(1,-32,0,28)
foot.Font=Enum.Font.Gotham
foot.TextSize=11
foot.TextColor3=Color3.fromRGB(115,135,165)
foot.TextWrapped=true
foot.Text="Sem loadstring do payload • endpoint historico JNKIE • somente leitura"

-- drag
local dragging,startPos,startInput,dragInput=false,nil,nil,nil
f.InputBegan:Connect(function(input)
    if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
        dragging=true; startInput=input.Position; startPos=f.Position
        input.Changed:Connect(function() if input.UserInputState==Enum.UserInputState.End then dragging=false end end)
    end
end)
f.InputChanged:Connect(function(input)
    if input.UserInputType==Enum.UserInputType.MouseMovement or input.UserInputType==Enum.UserInputType.Touch then dragInput=input end
end)
UIS.InputChanged:Connect(function(input)
    if dragging and input==dragInput then
        local d=input.Position-startInput
        f.Position=UDim2.new(startPos.X.Scale,startPos.X.Offset+d.X,startPos.Y.Scale,startPos.Y.Offset+d.Y)
    end
end)

task.spawn(function()
    while gui.Parent do
        status.Text=("Status: %s\nPayload: %s\nResumo: %s"):format(S.status,S.payloadFile or "-",S.summaryFile or "-")
        task.wait(.25)
    end
end)

_G.PSICO_JNKIE_V2_CLEANUP=function()
    pcall(function() if gui then gui:Destroy() end end)
end

log("JNKIE Delivery Fetcher V2 iniciado")
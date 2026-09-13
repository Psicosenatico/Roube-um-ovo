--[[
PSICOSENATICO | Nasi Payload Fetcher V1

Baixa o payload historico/atual do Nasi Rendang SEM executar loadstring.
Salva o texto bruto em arquivo para analise offline.
Nao altera jogo, ovos, remotes, velocidade ou ciclo.
]]

local Http=game:GetService("HttpService")
local CoreGui=game:GetService("CoreGui")
local UIS=game:GetService("UserInputService")
local Workspace=game:GetService("Workspace")

local TARGETS={
    {
        name="nrl_current",
        url="https://www.nrlscript.com/raw/wrijQVqSGC",
    },
    {
        name="jnkie_historical",
        url="https://api.jnkie.com/api/v1/luascripts/public/c090866e4201baecfe09dce16546ea747661d2d0861ae16f1eacf1d98dee3e3c/download",
        genvKeyless=true,
    },
}

local function parentGui()
    local ok,x=pcall(function() if gethui then return gethui() end end)
    return (ok and x) or CoreGui
end

local function fetch(url)
    local attempts={}
    local req=request or http_request or (http and http.request) or (syn and syn.request)
    if type(req)=="function" then
        attempts[#attempts+1]=function()
            local r=req({Url=url,Method="GET",Headers={['User-Agent']='Mozilla/5.0'}})
            if type(r)=="table" then
                local body=r.Body or r.body
                return body, r.StatusCode or r.Status or r.status_code
            end
        end
    end
    attempts[#attempts+1]=function()
        return game:HttpGet(url,true),200
    end
    for _,fn in ipairs(attempts) do
        local ok,body,status=pcall(fn)
        if ok and type(body)=="string" and #body>0 then
            return true,body,status
        end
    end
    return false,nil,nil
end

local function safeName(s)
    return (tostring(s):gsub("[^%w_%-.]","_"))
end

local function analyze(body)
    local out={bytes=#body,urls={},keywords={}}
    local seen={}
    for u in body:gmatch("https?://[^%s%\"%'%)%]>]+") do
        if not seen[u] then seen[u]=true; out.urls[#out.urls+1]=u end
        if #out.urls>=100 then break end
    end
    local keys={"predict","prediction","egg","spawn","hours","ahead","rarity","divine","eternal","secret","periodindex","daystartsat","rarespawns","schedule","cycle","seed","random","serverhop","server hop"}
    local low=body:lower()
    for _,k in ipairs(keys) do if low:find(k,1,true) then out.keywords[#out.keywords+1]=k end end
    out.luraph=low:find("luraph",1,true)~=nil
    out.looksLua=low:find("loadstring",1,true)~=nil or low:find("local ",1,true)~=nil
    return out
end

local results={Meta={Version="NasiPayloadFetcherV1",PlaceId=game.PlaceId,JobId=game.JobId,Unix=os.time()},Targets={}}

local gui=Instance.new("ScreenGui")
gui.Name="PSICO_NASI_PAYLOAD_FETCHER"
gui.ResetOnSpawn=false
gui.DisplayOrder=1000
gui.Parent=parentGui()

local frame=Instance.new("Frame")
frame.AnchorPoint=Vector2.new(.5,.5)
frame.Position=UDim2.fromScale(.5,.5)
frame.Size=UDim2.fromOffset(430,245)
frame.BackgroundColor3=Color3.fromRGB(10,19,35)
frame.BorderSizePixel=0
frame.Parent=gui
local c=Instance.new("UICorner");c.CornerRadius=UDim.new(0,12);c.Parent=frame

local title=Instance.new("TextLabel")
title.BackgroundTransparency=1
title.Position=UDim2.fromOffset(14,10)
title.Size=UDim2.new(1,-28,0,28)
title.Font=Enum.Font.GothamBold
title.Text="NASI PAYLOAD FETCHER V1"
title.TextColor3=Color3.fromRGB(235,244,255)
title.TextSize=16
title.TextXAlignment=Enum.TextXAlignment.Left
title.Parent=frame

local status=Instance.new("TextLabel")
status.BackgroundColor3=Color3.fromRGB(15,28,50)
status.Position=UDim2.fromOffset(14,48)
status.Size=UDim2.new(1,-28,0,112)
status.BorderSizePixel=0
status.Font=Enum.Font.Code
status.TextColor3=Color3.fromRGB(210,227,247)
status.TextSize=11
status.TextWrapped=true
status.TextXAlignment=Enum.TextXAlignment.Left
status.TextYAlignment=Enum.TextYAlignment.Top
status.Text="Não executa código externo.\nUse os botões abaixo para baixar somente o texto bruto."
status.Parent=frame
local sc=Instance.new("UICorner");sc.CornerRadius=UDim.new(0,8);sc.Parent=status
local pad=Instance.new("UIPadding");pad.PaddingLeft=UDim.new(0,9);pad.PaddingTop=UDim.new(0,7);pad.Parent=status

local function mk(text,x,w)
    local b=Instance.new("TextButton")
    b.Position=UDim2.new(0,x,1,-70)
    b.Size=UDim2.new(0,w,0,34)
    b.BackgroundColor3=Color3.fromRGB(24,67,113)
    b.BorderSizePixel=0
    b.Font=Enum.Font.GothamBold
    b.Text=text
    b.TextSize=11
    b.TextColor3=Color3.fromRGB(240,247,255)
    b.Parent=frame
    local cc=Instance.new("UICorner");cc.CornerRadius=UDim.new(0,8);cc.Parent=b
    return b
end

local btn1=mk("BAIXAR NRL",14,124)
local btn2=mk("BAIXAR JNKIE",146,124)
local btn3=mk("EXPORTAR RESUMO",278,138)

local function runTarget(t)
    status.Text="Baixando SOMENTE texto:\n"..t.url
    if t.genvKeyless and getgenv then pcall(function() getgenv().SCRIPT_KEY="KEYLESS" end) end
    local ok,body,httpStatus=fetch(t.url)
    if not ok then
        results.Targets[t.name]={ok=false,url=t.url}
        status.Text="Falha ao baixar "..t.name..". Nenhum código foi executado."
        return
    end
    local a=analyze(body)
    local filename="Psico_NasiPayload_"..safeName(t.name).."_"..tostring(os.time())..".lua.txt"
    local wrote=false
    if writefile then wrote=pcall(writefile,filename,body) end
    results.Targets[t.name]={ok=true,url=t.url,httpStatus=httpStatus,file=filename,wrote=wrote,analysis=a}
    status.Text=string.format("%s baixado sem executar.\n%d bytes | Luraph: %s | URLs: %d\nArquivo: %s",t.name,#body,a.luraph and "SIM" or "NÃO",#a.urls,filename)
end

btn1.Activated:Connect(function() task.spawn(runTarget,TARGETS[1]) end)
btn2.Activated:Connect(function() task.spawn(runTarget,TARGETS[2]) end)
btn3.Activated:Connect(function()
    local ok,json=pcall(Http.JSONEncode,Http,results)
    if not ok then status.Text="Erro ao gerar resumo." return end
    local name="Psico_NasiPayload_Summary_"..tostring(os.time())..".json"
    local wrote=false
    if writefile then wrote=pcall(writefile,name,json) end
    if setclipboard then pcall(setclipboard,json) end
    status.Text=(wrote and "Resumo salvo: " or "Resumo copiado: ")..name
end)

local dragging=false
local dragStart,startPos
frame.InputBegan:Connect(function(i)
    if i.UserInputType==Enum.UserInputType.Touch or i.UserInputType==Enum.UserInputType.MouseButton1 then dragging=true;dragStart=i.Position;startPos=frame.Position end
end)
UIS.InputChanged:Connect(function(i)
    if dragging and (i.UserInputType==Enum.UserInputType.Touch or i.UserInputType==Enum.UserInputType.MouseMovement) then
        local d=i.Position-dragStart
        frame.Position=UDim2.new(startPos.X.Scale,startPos.X.Offset+d.X,startPos.Y.Scale,startPos.Y.Offset+d.Y)
    end
end)
UIS.InputEnded:Connect(function(i) if i.UserInputType==Enum.UserInputType.Touch or i.UserInputType==Enum.UserInputType.MouseButton1 then dragging=false end end)

local cam=Workspace.CurrentCamera
local function resize()
    cam=Workspace.CurrentCamera or cam
    if not cam then return end
    local vp=cam.ViewportSize
    frame.Size=UDim2.fromOffset(math.clamp(vp.X*.62,330,430),math.clamp(vp.Y*.58,220,245))
end
resize()
if cam then cam:GetPropertyChangedSignal("ViewportSize"):Connect(resize) end

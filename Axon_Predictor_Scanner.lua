-- PSICOSENATICO | AXON PREDICTOR SCANNER
-- Passive / zero-hook. Observes UI and replicated state only.

local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local player = Players.LocalPlayer

local state = {base=nil,predictor=nil,refresh=nil,gui=nil,status=nil}
local keywords = {"predict","forecast","upcoming","spawn","egg","pet","rarity","rare","secret","eternal","divine","mythic","cosmic","area","chance","refresh","period","daystart","server"}

local function lower(s) return string.lower(tostring(s or "")) end
local function interesting(s)
    s = lower(s)
    for _,k in ipairs(keywords) do
        if string.find(s,k,1,true) then return true end
    end
    return false
end

local function pathOf(x)
    local ok,r = pcall(function() return x:GetFullName() end)
    return ok and r or tostring(x)
end

local function safeText(x)
    local ok,r = pcall(function() return x.Text end)
    return ok and r or nil
end

local function captureUI()
    local out = {}
    local roots = {CoreGui}
    local pg = player and player:FindFirstChildOfClass("PlayerGui")
    if pg then table.insert(roots,pg) end
    for _,root in ipairs(roots) do
        local ok,list = pcall(function() return root:GetDescendants() end)
        if ok then
            for _,x in ipairs(list) do
                if x:IsA("TextLabel") or x:IsA("TextButton") or x:IsA("TextBox") then
                    local text = safeText(x)
                    local p = pathOf(x)
                    if text and text ~= "" and (interesting(text) or interesting(p)) then
                        out[p] = {class=x.ClassName,text=text,visible=x.Visible}
                    end
                elseif x:IsA("ScreenGui") then
                    local p = pathOf(x)
                    out[p] = {class="ScreenGui",enabled=x.Enabled,displayOrder=x.DisplayOrder}
                end
            end
        end
    end
    return out
end

local function captureRelevant()
    local out = {}
    local ok,list = pcall(function() return ReplicatedStorage:GetDescendants() end)
    if not ok then return out end
    for _,x in ipairs(list) do
        local useful = x:IsA("RemoteEvent") or x:IsA("RemoteFunction") or x:IsA("ModuleScript") or x:IsA("ValueBase")
        if useful then
            local p = pathOf(x)
            if interesting(p) or interesting(x.Name) then
                local item = {class=x.ClassName,name=x.Name}
                if x:IsA("ValueBase") then
                    pcall(function() item.value=tostring(x.Value) end)
                end
                out[p]=item
            end
        end
    end
    return out
end

local function snapshot(label)
    return {
        label=label,
        unix=os.time(),
        placeId=game.PlaceId,
        gameId=game.GameId,
        jobId=game.JobId,
        ui=captureUI(),
        relevant=captureRelevant()
    }
end

local function diffMap(a,b)
    a=a or {}; b=b or {}
    local added,removed,changed={},{},{}
    for k,v in pairs(b) do
        if a[k]==nil then
            added[k]=v
        else
            local ok1,s1=pcall(HttpService.JSONEncode,HttpService,a[k])
            local ok2,s2=pcall(HttpService.JSONEncode,HttpService,v)
            if ok1 and ok2 and s1~=s2 then changed[k]={before=a[k],after=v} end
        end
    end
    for k,v in pairs(a) do if b[k]==nil then removed[k]=v end end
    return {added=added,removed=removed,changed=changed}
end

local function report()
    return {
        meta={version="AxonPredictorScanner",zeroHook=true,created=os.time()},
        base=state.base,
        predictor=state.predictor,
        refresh=state.refresh,
        predictorDiff=(state.base and state.predictor) and {
            ui=diffMap(state.base.ui,state.predictor.ui),
            relevant=diffMap(state.base.relevant,state.predictor.relevant)
        } or nil,
        refreshDiff=(state.predictor and state.refresh) and {
            ui=diffMap(state.predictor.ui,state.refresh.ui),
            relevant=diffMap(state.predictor.relevant,state.refresh.relevant)
        } or nil
    }
end

local function setStatus(s)
    if state.status and state.status.Parent then state.status.Text=s end
end

local function captureBase()
    setStatus("Capturando BASE...")
    task.defer(function()
        state.base=snapshot("base")
        state.predictor=nil
        state.refresh=nil
        setStatus("BASE capturada. Carregue o Axon e abra Egg Predictor.")
    end)
end

local function capturePredictor()
    if not state.base then setStatus("Capture BASE primeiro."); return end
    setStatus("Capturando PREDICTOR...")
    task.defer(function()
        state.predictor=snapshot("predictor")
        setStatus("PREDICTOR capturado. Agora use Refresh Predictions.")
    end)
end

local function captureRefresh()
    if not state.predictor then setStatus("Capture PREDICTOR primeiro."); return end
    setStatus("Capturando REFRESH...")
    task.defer(function()
        state.refresh=snapshot("refresh")
        setStatus("REFRESH capturado. Pode EXPORTAR.")
    end)
end

local function exportData()
    if not state.base then setStatus("Nada para exportar."); return end
    local ok,json = pcall(function() return HttpService:JSONEncode(report()) end)
    if not ok then setStatus("Erro JSON: "..tostring(json)); return end
    local name = "Psico_Axon_Predictor_"..os.time()..".json"
    local wrote=false
    if writefile then wrote=pcall(writefile,name,json) end
    if setclipboard then pcall(setclipboard,json) end
    setStatus((wrote and "EXPORTADO: " or "JSON COPIADO: ")..name)
end

local parent = CoreGui
local sg = Instance.new("ScreenGui")
sg.Name="PSICO_AXON_PRED_SCANNER"
sg.ResetOnSpawn=false
sg.DisplayOrder=1400
sg.Parent=parent
state.gui=sg

local frame=Instance.new("Frame")
frame.AnchorPoint=Vector2.new(.5,.5)
frame.Position=UDim2.fromScale(.5,.5)
frame.Size=UDim2.fromOffset(470,285)
frame.BackgroundColor3=Color3.fromRGB(9,18,34)
frame.BorderSizePixel=0
frame.Parent=sg
Instance.new("UICorner",frame).CornerRadius=UDim.new(0,14)

local title=Instance.new("TextLabel")
title.BackgroundTransparency=1
title.Position=UDim2.fromOffset(14,10)
title.Size=UDim2.new(1,-28,0,28)
title.Text="AXON PREDICTOR SCANNER • ZERO-HOOK"
title.Font=Enum.Font.GothamBold
title.TextSize=14
title.TextColor3=Color3.fromRGB(238,245,255)
title.TextXAlignment=Enum.TextXAlignment.Left
title.Parent=frame

local status=Instance.new("TextLabel")
status.Position=UDim2.fromOffset(14,48)
status.Size=UDim2.new(1,-28,0,78)
status.BackgroundColor3=Color3.fromRGB(15,29,52)
status.BorderSizePixel=0
status.Text="Pronto. Comece com CAPTURAR BASE."
status.Font=Enum.Font.Code
status.TextSize=11
status.TextColor3=Color3.fromRGB(215,229,247)
status.TextWrapped=true
status.Parent=frame
Instance.new("UICorner",status).CornerRadius=UDim.new(0,9)
state.status=status

local function button(text,x,y,w)
    local b=Instance.new("TextButton")
    b.Position=UDim2.fromOffset(x,y)
    b.Size=UDim2.fromOffset(w,38)
    b.BackgroundColor3=Color3.fromRGB(31,78,132)
    b.BorderSizePixel=0
    b.Text=text
    b.TextColor3=Color3.fromRGB(244,248,255)
    b.Font=Enum.Font.GothamBold
    b.TextSize=11
    b.Parent=frame
    Instance.new("UICorner",b).CornerRadius=UDim.new(0,9)
    return b
end

local b1=button("CAPTURAR BASE",14,140,210)
local b2=button("CAPTURAR PREDICTOR",246,140,210)
local b3=button("CAPTURAR REFRESH",14,188,210)
local b4=button("EXPORTAR",246,188,210)
local close=button("FECHAR",14,236,442)

b1.MouseButton1Click:Connect(captureBase)
b2.MouseButton1Click:Connect(capturePredictor)
b3.MouseButton1Click:Connect(captureRefresh)
b4.MouseButton1Click:Connect(exportData)
close.MouseButton1Click:Connect(function() sg:Destroy() end)

local dragging=false
local dragStart,startPos
frame.InputBegan:Connect(function(i)
    if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then
        dragging=true; dragStart=i.Position; startPos=frame.Position
    end
end)
frame.InputChanged:Connect(function(i)
    if dragging and (i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch) then
        local d=i.Position-dragStart
        frame.Position=UDim2.new(startPos.X.Scale,startPos.X.Offset+d.X,startPos.Y.Scale,startPos.Y.Offset+d.Y)
    end
end)
UserInputService.InputEnded:Connect(function(i)
    if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then dragging=false end
end)

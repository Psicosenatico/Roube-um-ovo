-- PSICOSENATICO | FUSION RESEARCH SCANNER V2
-- Purpose: capture the exact 3 pets in Save.FusionSlots BEFORE FuseStarted,
-- then pair them with the server-selected fusion reward for predictor research.

if _G.PSICO_FUSION_SCAN_CLEANUP then
    pcall(_G.PSICO_FUSION_SCAN_CLEANUP)
end

local Players=game:GetService("Players")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local HttpService=game:GetService("HttpService")
local CoreGui=game:GetService("CoreGui")
local UIS=game:GetService("UserInputService")
local Workspace=game:GetService("Workspace")

local LP=Players.LocalPlayer
local STARTED=os.time()
local scannerName="Psico Fusion Research Scanner V2"

local function safeRequire(path)
    local cur=ReplicatedStorage
    for seg in string.gmatch(path,"[^%.]+") do
        cur=cur and cur:FindFirstChild(seg)
        if not cur then return nil end
    end
    local ok,res=pcall(require,cur)
    return ok and res or nil
end

local Save=safeRequire("Shared.Save")
local AssetItems=safeRequire("Shared.Util.AssetItems")
local AssetEarnings=safeRequire("Shared.Util.AssetEarnings")
local FuseKernel=safeRequire("Shared.Util.FuseKernel")
local FuseSignals=safeRequire("Client.FuseMachineSignals")
local FuseTypes=safeRequire("Shared.Types.FuseMachine")
local Assets=safeRequire("Data.Assets")

local function finite(n)
    return type(n)=="number" and n==n and n~=math.huge and n~=-math.huge
end

local function cloneArray(t)
    local out={}
    if type(t)=="table" then
        for _,v in ipairs(t) do
            if type(v)=="table" then
                out[#out+1]=tostring(v._id or v.DisplayName or v.Name or "?")
            else
                out[#out+1]=tostring(v)
            end
        end
    end
    return out
end

local function jsonSafe(v,depth,seen)
    depth=depth or 0
    seen=seen or {}
    if depth>6 then return "<max-depth>" end
    local tv=typeof(v)
    if tv=="nil" then return nil end
    if tv=="string" or tv=="boolean" then return v end
    if tv=="number" then return finite(v) and v or tostring(v) end
    if tv=="Vector3" then return {x=v.X,y=v.Y,z=v.Z} end
    if tv=="Vector2" then return {x=v.X,y=v.Y} end
    if tv=="Color3" then return {r=v.R,g=v.G,b=v.B} end
    if tv=="CFrame" then return {components={v:GetComponents()}} end
    if tv=="EnumItem" then return tostring(v) end
    if tv=="Instance" then
        local ok,name=pcall(function() return v:GetFullName() end)
        return ok and name or tostring(v)
    end
    if tv~="table" then return tostring(v) end
    if seen[v] then return "<cycle>" end
    seen[v]=true

    local maxIndex=0
    local count=0
    local array=true
    for k in pairs(v) do
        count+=1
        if type(k)~="number" or k<1 or math.floor(k)~=k then
            array=false
            break
        end
        if k>maxIndex then maxIndex=k end
    end
    if array and maxIndex==count then
        local out={}
        for i=1,maxIndex do out[i]=jsonSafe(v[i],depth+1,seen) end
        seen[v]=nil
        return out
    end

    local out={}
    local n=0
    for k,val in pairs(v) do
        n+=1
        if n>120 then
            out["<truncated>"]=true
            break
        end
        out[tostring(k)]=jsonSafe(val,depth+1,seen)
    end
    seen[v]=nil
    return out
end

local function moduleKeys(mod)
    local out={}
    if type(mod)=="table" then
        for k,v in pairs(mod) do
            out[#out+1]={key=tostring(k),valueType=typeof(v)}
        end
        table.sort(out,function(a,b) return a.key<b.key end)
    end
    return out
end

local function getSave()
    if type(Save)~="table" or type(Save.Get)~="function" then return nil end
    local ok,data=pcall(Save.Get)
    if not ok then ok,data=pcall(Save.Get,Save) end
    return ok and type(data)=="table" and data or nil
end

local function decodeItem(raw)
    if type(AssetItems)=="table" and type(AssetItems.Decode)=="function" then
        local ok,item=pcall(AssetItems.Decode,raw)
        if not ok then ok,item=pcall(AssetItems.Decode,AssetItems,raw) end
        if ok and type(item)=="table" then return item,"AssetItems.Decode" end
    end
    if type(raw)=="table" then return raw,"raw-table" end
    return nil,"unavailable"
end

local function assetCfg(cat)
    local dir=type(Assets)=="table" and (Assets.Directory or Assets)
    return type(dir)=="table" and dir[cat] or nil
end

local function itemRate(item)
    if type(item)~="table" then return nil,nil end
    if type(AssetEarnings)=="table" then
        if type(AssetEarnings.CatalogRatePerSecond)=="function" then
            local ok,v=pcall(AssetEarnings.CatalogRatePerSecond,item)
            if not ok then ok,v=pcall(AssetEarnings.CatalogRatePerSecond,AssetEarnings,item) end
            if ok and tonumber(v) then return tonumber(v),"AssetEarnings.CatalogRatePerSecond" end
        end
        if type(AssetEarnings.MutationOnlyRatePerSecond)=="function" then
            local shape={
                Category=item.Category or item.AssetCategory,
                Scale=item.Scale or item.AssetScale,
                Mutations=item.Mutations or {},
            }
            local ok,v=pcall(AssetEarnings.MutationOnlyRatePerSecond,shape)
            if not ok then ok,v=pcall(AssetEarnings.MutationOnlyRatePerSecond,AssetEarnings,shape) end
            if ok and tonumber(v) then return tonumber(v),"AssetEarnings.MutationOnlyRatePerSecond" end
        end
    end
    return nil,nil
end

local function directNumber(item,raw,keys)
    for _,src in ipairs({item,raw}) do
        if type(src)=="table" then
            for _,k in ipairs(keys) do
                local n=tonumber(src[k])
                if n then return n,k end
            end
        end
    end
end

local function summarizeInput(uid,raw)
    local item,decodeMethod=decodeItem(raw)
    item=item or {}
    local category=item.Category or item.AssetCategory or (type(raw)=="table" and (raw.Category or raw.AssetCategory))
    category=category and tostring(category) or nil
    local cfg=category and assetCfg(category) or nil
    local display=item.DisplayName or item.Name or (cfg and cfg.DisplayName) or category
    local rarity=cfg and cfg.Rarity
    local rarityName=rarity and (rarity.DisplayName or rarity._id) or nil
    local scale=tonumber(item.Scale or item.AssetScale or (type(raw)=="table" and (raw.Scale or raw.AssetScale))) or 1
    local weight,weightSource=directNumber(item,raw,{"Weight","AssetWeight","Kg","Mass"})
    local rate,rateMethod=itemRate(item)
    local salePrice
    if type(AssetItems)=="table" and type(AssetItems.SalePrice)=="function" then
        local ok,v=pcall(AssetItems.SalePrice,item)
        if not ok then ok,v=pcall(AssetItems.SalePrice,AssetItems,item) end
        if ok and tonumber(v) then salePrice=tonumber(v) end
    end

    return {
        uid=tostring(uid),
        category=category,
        displayName=display and tostring(display) or nil,
        rarity=rarityName and {name=tostring(rarityName),number=tonumber(rarity.RarityNumber)} or nil,
        scale=scale,
        weight=weight,
        weightSource=weightSource,
        earningsPerSecond=rate,
        earningsMethod=rateMethod,
        salePrice=salePrice,
        mutations=cloneArray(item.Mutations or (type(raw)=="table" and raw.Mutations)),
        baseMutation=item.BaseMutation or (type(raw)=="table" and raw.BaseMutation) or nil,
        favorite=item.IsFavorite==true or item.Favorite==true,
        inFuse=item.InFuse==true,
        decodeMethod=decodeMethod,
        decoded=jsonSafe(item),
        raw=jsonSafe(raw),
    }
end

local function summarizeReward(reward)
    local raw=reward
    if type(reward)~="table" then return {raw=jsonSafe(reward)} end
    if not (reward.AssetCategory or reward.Category) and type(FuseTypes)=="table" and type(FuseTypes.FuseResult)=="function" then
        local ok,decoded=pcall(FuseTypes.FuseResult,reward)
        if not ok then ok,decoded=pcall(FuseTypes.FuseResult,FuseTypes,reward) end
        if ok and type(decoded)=="table" then reward=decoded end
    end
    local category=reward.AssetCategory or reward.Category
    local cfg=category and assetCfg(category) or nil
    local rarity=cfg and cfg.Rarity
    local item={
        Category=category,
        AssetCategory=category,
        Scale=reward.AssetScale or reward.Scale or 1,
        AssetScale=reward.AssetScale or reward.Scale or 1,
        Mutations=reward.Mutations or {},
        BaseMutation=reward.BaseMutation,
    }
    local rate,method=itemRate(item)
    return {
        uid="reward",
        category=category and tostring(category) or nil,
        displayName=(cfg and cfg.DisplayName) or (category and tostring(category)) or nil,
        rarity=rarity and {name=tostring(rarity.DisplayName or rarity._id),number=tonumber(rarity.RarityNumber)} or nil,
        scale=tonumber(reward.AssetScale or reward.Scale) or 1,
        earningsPerSecond=rate,
        earningsMethod=method,
        mutations=cloneArray(reward.Mutations),
        baseMutation=reward.BaseMutation,
        raw=jsonSafe(raw),
        decoded=jsonSafe(reward),
    }
end

local function calcMetrics(inputs,rewardSummary,decodedInputs)
    local m={
        count=#inputs,
        sumScale=0,
        sumEarningsPerSecond=0,
        sumWeight=0,
        weightCount=0,
        minScale=nil,maxScale=nil,
        minEarningsPerSecond=nil,maxEarningsPerSecond=nil,
        minWeight=nil,maxWeight=nil,
        allSameCategory=true,
        category=inputs[1] and inputs[1].category or nil,
    }
    for _,x in ipairs(inputs) do
        local sc=tonumber(x.scale) or 0
        m.sumScale+=sc
        m.minScale=m.minScale and math.min(m.minScale,sc) or sc
        m.maxScale=m.maxScale and math.max(m.maxScale,sc) or sc
        local e=tonumber(x.earningsPerSecond)
        if e then
            m.sumEarningsPerSecond+=e
            m.minEarningsPerSecond=m.minEarningsPerSecond and math.min(m.minEarningsPerSecond,e) or e
            m.maxEarningsPerSecond=m.maxEarningsPerSecond and math.max(m.maxEarningsPerSecond,e) or e
        end
        local w=tonumber(x.weight)
        if w then
            m.sumWeight+=w
            m.weightCount+=1
            m.minWeight=m.minWeight and math.min(m.minWeight,w) or w
            m.maxWeight=m.maxWeight and math.max(m.maxWeight,w) or w
        end
        if m.category and x.category~=m.category then m.allSameCategory=false end
    end
    if m.count>0 then
        m.meanScale=m.sumScale/m.count
        m.meanEarningsPerSecond=m.sumEarningsPerSecond/m.count
    end
    if m.weightCount>0 then m.meanWeight=m.sumWeight/m.weightCount end

    if type(FuseKernel)=="table" and type(FuseKernel.PriceFor)=="function" and #decodedInputs==3 then
        local ok,v=pcall(FuseKernel.PriceFor,decodedInputs)
        if not ok then ok,v=pcall(FuseKernel.PriceFor,FuseKernel,decodedInputs) end
        if ok and tonumber(v) then m.fusionPrice=tonumber(v) end
    end

    if rewardSummary then
        local oscale=tonumber(rewardSummary.scale)
        local orate=tonumber(rewardSummary.earningsPerSecond)
        if oscale and m.meanScale and m.meanScale>0 then
            m.outputScaleVsMeanInputScale=oscale/m.meanScale
        end
        if orate and m.sumEarningsPerSecond>0 then
            m.outputEarningsVsInputSum=orate/m.sumEarningsPerSecond
        end
    end
    return m
end

local state={
    alive=true,
    samples={},
    events={},
    lastThree=nil,
    lastSlotCount=0,
    lastSlotSnapshot=nil,
    lastFusionAt=0,
    status="Aguardando 3 pets na máquina",
}
local conns={}

local function captureSlots()
    local save=getSave()
    if not save then return nil end
    local slots={}
    local inputs={}
    local decodedInputs={}
    for index,uid in ipairs(save.FusionSlots or {}) do
        if uid then
            slots[#slots+1]=tostring(uid)
            local raw=save.Inventory and save.Inventory[uid]
            local summary=summarizeInput(uid,raw)
            summary.slot=index
            inputs[#inputs+1]=summary
            local item=decodeItem(raw)
            decodedInputs[#decodedInputs+1]=item or {}
        end
    end
    return {
        capturedUnix=os.time(),
        capturedServerTime=Workspace:GetServerTimeNow(),
        capturedClock=os.clock(),
        slots=slots,
        inputs=inputs,
        decodedInputs=decodedInputs,
        fusionLocked=save.FusionLocked==true,
        fusionEggReward=jsonSafe(save.FusionEggReward),
        saveFusionInfoAcknowledged=save.FusionInfoAcknowledged,
    }
end

local function pollSlots()
    local snap=captureSlots()
    if not snap then
        state.status="Save.Get indisponível"
        return
    end
    state.lastSlotCount=#snap.inputs
    state.lastSlotSnapshot=snap
    if #snap.inputs==3 then
        state.lastThree=snap
        state.status="3/3 capturados • pronto para fundir"
    elseif #snap.inputs>0 then
        state.status=string.format("%d/3 pets carregados",#snap.inputs)
    elseif os.clock()-state.lastFusionAt>1.5 then
        state.status="Aguardando pets na máquina"
    end
end

local function handleFuseStarted(reward)
    local rewardSummary=summarizeReward(reward)
    local snap=state.lastThree
    local age=snap and (os.clock()-(snap.capturedClock or 0)) or math.huge
    local method="none"
    local inputs={}
    local decodedInputs={}
    if snap and #snap.inputs==3 and age<20 then
        inputs=snap.inputs
        decodedInputs=snap.decodedInputs or {}
        method="Save.FusionSlots pre-fuse snapshot"
    else
        local nowSnap=captureSlots()
        if nowSnap and #nowSnap.inputs==3 then
            inputs=nowSnap.inputs
            decodedInputs=nowSnap.decodedInputs or {}
            method="Save.FusionSlots at FuseStarted"
        end
    end

    local metrics=calcMetrics(inputs,rewardSummary,decodedInputs)
    local sample={
        index=#state.samples+1,
        unix=os.time(),
        serverTime=Workspace:GetServerTimeNow(),
        source="Client.FuseMachineSignals.FuseStarted",
        inputCaptureMethod=method,
        inputs=inputs,
        inputMetrics=metrics,
        reward=jsonSafe(reward),
        rewardSummary=rewardSummary,
        preFuseSnapshot=snap and {
            capturedUnix=snap.capturedUnix,
            capturedServerTime=snap.capturedServerTime,
            ageSeconds=age,
            fusionLocked=snap.fusionLocked,
            fusionEggReward=snap.fusionEggReward,
            slots=snap.slots,
        } or nil,
        derived={
            outputScale=rewardSummary.scale,
            inputMeanScale=metrics.meanScale,
            inputSumEarningsPerSecond=metrics.sumEarningsPerSecond,
            inputSumWeight=metrics.weightCount>0 and metrics.sumWeight or nil,
            outputScaleVsMeanInputScale=metrics.outputScaleVsMeanInputScale,
            outputEarningsVsInputSum=metrics.outputEarningsVsInputSum,
        },
    }
    state.samples[#state.samples+1]=sample
    state.events[#state.events+1]={kind="FuseReward",unix=sample.unix,serverTime=sample.serverTime,data=sample}
    state.lastFusionAt=os.clock()
    state.status=string.format("Fusão #%d capturada • inputs %d/3",sample.index,#inputs)
end

if type(FuseSignals)=="table" and FuseSignals.FuseStarted and type(FuseSignals.FuseStarted.Connect)=="function" then
    local ok,c=pcall(function()
        return FuseSignals.FuseStarted:Connect(function(reward)
            task.defer(handleFuseStarted,reward)
        end)
    end)
    if ok and c then conns[#conns+1]=c end
else
    state.status="FuseMachineSignals.FuseStarted não encontrado"
end

-- Save.FieldSignal gives us a faster update when available; polling remains as fallback.
if type(Save)=="table" and type(Save.FieldSignal)=="function" then
    local ok,sig=pcall(Save.FieldSignal,"FusionSlots")
    if not ok then ok,sig=pcall(Save.FieldSignal,Save,"FusionSlots") end
    if ok and sig and type(sig.Connect)=="function" then
        local ok2,c=pcall(function() return sig:Connect(function() task.defer(pollSlots) end) end)
        if ok2 and c then conns[#conns+1]=c end
    end
end

local function exportData()
    local payload={
        scanner=scannerName,
        started=STARTED,
        exported=os.time(),
        userId=LP.UserId,
        placeId=game.PlaceId,
        gameId=game.GameId,
        jobId=game.JobId,
        moduleAvailability={
            Save=Save~=nil,
            AssetItems=AssetItems~=nil,
            AssetEarnings=AssetEarnings~=nil,
            FuseKernel=FuseKernel~=nil,
            FuseMachineSignals=FuseSignals~=nil,
            FuseMachineTypes=FuseTypes~=nil,
            Assets=Assets~=nil,
        },
        moduleKeys={
            AssetItems=moduleKeys(AssetItems),
            AssetEarnings=moduleKeys(AssetEarnings),
            FuseKernel=moduleKeys(FuseKernel),
            FuseMachineSignals=moduleKeys(FuseSignals),
        },
        samples=state.samples,
        events=state.events,
        notes={
            "Inputs are read directly from Save.Get().FusionSlots before FuseStarted.",
            "Input $/s prefers AssetEarnings.CatalogRatePerSecond(decodedItem).",
            "Weight is exported when present in decoded/raw pet data; missing weight stays null.",
            "Fusion price uses FuseKernel.PriceFor when available.",
        },
    }
    local ok,json=pcall(HttpService.JSONEncode,HttpService,payload)
    if not ok then return false,"JSONEncode falhou: "..tostring(json) end
    local fileName="Psico_FusionScan_"..tostring(os.time())..".json"
    if type(writefile)=="function" then
        local okw,err=pcall(writefile,fileName,json)
        if okw then return true,fileName end
        return false,tostring(err)
    end
    local clip=setclipboard or toclipboard
    if type(clip)=="function" then
        local okc=pcall(clip,json)
        if okc then return true,"JSON copiado para a área de transferência" end
    end
    return false,"Executor sem writefile/setclipboard"
end

local function round(o,r)
    local c=Instance.new("UICorner")
    c.CornerRadius=UDim.new(0,r or 12)
    c.Parent=o
end

local function makeButton(parent,text,pos,size)
    local b=Instance.new("TextButton")
    b.BackgroundColor3=Color3.fromRGB(42,91,145)
    b.BorderSizePixel=0
    b.Position=pos
    b.Size=size
    b.Font=Enum.Font.GothamBold
    b.Text=text
    b.TextSize=18
    b.TextColor3=Color3.fromRGB(245,248,255)
    b.Parent=parent
    round(b,10)
    return b
end

local root=(function()
    local ok,h=pcall(function() return gethui and gethui() end)
    return (ok and h) or CoreGui
end)()

local old=root:FindFirstChild("PsicoFusionResearchScanner")
if old then old:Destroy() end

local gui=Instance.new("ScreenGui")
gui.Name="PsicoFusionResearchScanner"
gui.ResetOnSpawn=false
gui.IgnoreGuiInset=true
gui.DisplayOrder=998
gui.Parent=root

local main=Instance.new("Frame")
main.Name="Main"
main.AnchorPoint=Vector2.new(.5,.5)
main.Position=UDim2.fromScale(.5,.5)
main.Size=UDim2.new(.86,0,.68,0)
main.BackgroundColor3=Color3.fromRGB(12,24,43)
main.BorderSizePixel=0
main.Active=true
main.Parent=gui
round(main,20)

local stroke=Instance.new("UIStroke")
stroke.Color=Color3.fromRGB(69,134,204)
stroke.Thickness=2
stroke.Parent=main

local title=Instance.new("TextLabel")
title.BackgroundTransparency=1
title.Position=UDim2.new(0,24,0,14)
title.Size=UDim2.new(1,-90,0,42)
title.Font=Enum.Font.GothamBold
title.Text="FUSION RESEARCH SCANNER • V2"
title.TextSize=26
title.TextColor3=Color3.fromRGB(245,248,255)
title.TextXAlignment=Enum.TextXAlignment.Left
title.Parent=main

local sub=Instance.new("TextLabel")
sub.BackgroundTransparency=1
sub.Position=UDim2.new(0,24,0,54)
sub.Size=UDim2.new(1,-48,0,28)
sub.Font=Enum.Font.Gotham
sub.Text="FusionSlots • $/s • Scale • Peso • Resultado"
sub.TextSize=16
sub.TextColor3=Color3.fromRGB(139,164,207)
sub.TextXAlignment=Enum.TextXAlignment.Left
sub.Parent=main

local close=makeButton(main,"×",UDim2.new(1,-64,0,16),UDim2.fromOffset(44,44))
close.TextSize=25
close.BackgroundColor3=Color3.fromRGB(35,44,61)

local body=Instance.new("Frame")
body.BackgroundColor3=Color3.fromRGB(16,34,58)
body.BorderSizePixel=0
body.Position=UDim2.new(0,24,0,92)
body.Size=UDim2.new(1,-48,1,-174)
body.Parent=main
round(body,16)

local statusLabel=Instance.new("TextLabel")
statusLabel.BackgroundTransparency=1
statusLabel.Position=UDim2.new(0,20,0,16)
statusLabel.Size=UDim2.new(1,-40,1,-32)
statusLabel.Font=Enum.Font.Code
statusLabel.TextSize=17
statusLabel.TextColor3=Color3.fromRGB(230,237,248)
statusLabel.TextXAlignment=Enum.TextXAlignment.Left
statusLabel.TextYAlignment=Enum.TextYAlignment.Top
statusLabel.TextWrapped=true
statusLabel.Parent=body

local capture=makeButton(main,"LER SLOTS AGORA",UDim2.new(0,24,1,-66),UDim2.new(.31,-10,0,44))
local export=makeButton(main,"EXPORTAR JSON",UDim2.new(.34,0,1,-66),UDim2.new(.31,-10,0,44))
local clear=makeButton(main,"LIMPAR AMOSTRAS",UDim2.new(.67,0,1,-66),UDim2.new(.31,-24,0,44))
clear.BackgroundColor3=Color3.fromRGB(35,44,61)

local dragging=false
local dragStart,startPos
main.InputBegan:Connect(function(input)
    if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
        dragging=true
        dragStart=input.Position
        startPos=main.Position
    end
end)
main.InputEnded:Connect(function(input)
    if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
        dragging=false
    end
end)
conns[#conns+1]=UIS.InputChanged:Connect(function(input)
    if dragging and (input.UserInputType==Enum.UserInputType.MouseMovement or input.UserInputType==Enum.UserInputType.Touch) then
        local d=input.Position-dragStart
        main.Position=UDim2.new(startPos.X.Scale,startPos.X.Offset+d.X,startPos.Y.Scale,startPos.Y.Offset+d.Y)
    end
end)

capture.Activated:Connect(function()
    pollSlots()
    local snap=state.lastSlotSnapshot
    if snap then
        state.status=string.format("Leitura manual: %d/3 slots • %s",#snap.inputs,#snap.inputs==3 and "snapshot salvo" or "aguardando 3")
        if #snap.inputs==3 then state.lastThree=snap end
    end
end)

export.Activated:Connect(function()
    local ok,msg=exportData()
    state.status=ok and ("Exportado: "..tostring(msg)) or ("Falha ao exportar: "..tostring(msg))
end)

clear.Activated:Connect(function()
    table.clear(state.samples)
    table.clear(state.events)
    state.status="Amostras limpas • aguardando nova fusão"
end)

local function cleanup()
    state.alive=false
    for _,c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    pcall(function() gui:Destroy() end)
    if _G.PSICO_FUSION_SCAN_CLEANUP==cleanup then _G.PSICO_FUSION_SCAN_CLEANUP=nil end
end
_G.PSICO_FUSION_SCAN_CLEANUP=cleanup
close.Activated:Connect(cleanup)

task.spawn(function()
    while state.alive and gui.Parent do
        pollSlots()
        local snap=state.lastSlotSnapshot
        local lines={
            state.status,
            "",
            string.format("Slots agora: %d/3  |  Amostras: %d",state.lastSlotCount,#state.samples),
        }
        if snap and #snap.inputs>0 then
            lines[#lines+1]=""
            for _,x in ipairs(snap.inputs) do
                lines[#lines+1]=string.format(
                    "[%d] %s | Scale %.4f | $/s %s | Peso %s",
                    x.slot or 0,
                    tostring(x.displayName or x.category or "?"),
                    tonumber(x.scale) or 0,
                    x.earningsPerSecond and string.format("%.0f",x.earningsPerSecond) or "?",
                    x.weight and string.format("%.3f",x.weight) or "?"
                )
            end
        end
        if #state.samples>0 then
            local last=state.samples[#state.samples]
            local r=last.rewardSummary or {}
            lines[#lines+1]=""
            lines[#lines+1]=string.format(
                "Último resultado: %s | %s | Scale %.4f | $/s %s",
                tostring(r.displayName or r.category or "?"),
                tostring(r.rarity and r.rarity.name or "?"),
                tonumber(r.scale) or 0,
                r.earningsPerSecond and string.format("%.0f",r.earningsPerSecond) or "?"
            )
            lines[#lines+1]=string.format(
                "Inputs capturados: %d/3 | método: %s",
                #(last.inputs or {}),
                tostring(last.inputCaptureMethod or "none")
            )
        end
        statusLabel.Text=table.concat(lines,"\n")
        task.wait(.15)
    end
end)

pollSlots()

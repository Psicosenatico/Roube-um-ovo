-- PSICOSENATICO | Fusion Research Scanner V1.1
-- Observa fusões MANUAIS e registra os 3 pets de entrada + recompensa gerada.
-- Não inicia fusão, não carrega/ejecta pets e não chama BeginFuse/FinishReveal.
-- V1.1: captura incremental de FusionSlots + sinais do Save + recuperação por diff do Inventory.

if _G.PSICO_FUSION_SCAN_CLEANUP then pcall(_G.PSICO_FUSION_SCAN_CLEANUP) end

local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local CoreGui=game:GetService("CoreGui")
local Http=game:GetService("HttpService")
local UIS=game:GetService("UserInputService")
local Workspace=game:GetService("Workspace")
local LP=Players.LocalPlayer
local Camera=Workspace.CurrentCamera

local C={}
local S={
    started=os.time(),
    enabled=true,
    samples={},
    events={},
    lastReady=nil,
    lastSlotSnapshot=nil,
    lastSlotAt=0,
    lastObservedSlotSignature="",
    cycleInventoryBefore=nil,
    cycleStartedAt=0,
    lastInventorySnapshot=nil,
    lastInventoryAt=0,
    lastRewardKey=nil,
    lastRewardAt=0,
    modules={},
}

local function findPath(path)
    local x=RS
    for q in tostring(path):gmatch("[^%.]+") do
        x=x and x:FindFirstChild(q)
        if not x then return nil end
    end
    return x
end

local function req(path)
    local m=findPath(path)
    if not (m and m:IsA("ModuleScript")) then return nil end
    local ok,v=pcall(require,m)
    return ok and v or nil
end

local Save=req("Shared.Save")
local Assets=req("Data.Assets")
local AssetEarnings=req("Shared.Util.AssetEarnings")
local FuseKernel=req("Shared.Util.FuseKernel")
local FuseMachineSignals=req("Client.FuseMachineSignals")
local AssetSizeClassification=req("Client.Util.AssetSizeClassification")

S.modules={
    Save=type(Save)=="table",
    Assets=type(Assets)=="table",
    AssetEarnings=type(AssetEarnings)=="table",
    FuseKernel=type(FuseKernel)=="table",
    FuseMachineSignals=type(FuseMachineSignals)=="table",
    AssetSizeClassification=type(AssetSizeClassification)=="table",
}

local function safeString(v)
    local ok,s=pcall(tostring,v)
    return ok and s or "?"
end

local function primitive(v,depth,seen)
    depth=depth or 0
    seen=seen or {}
    local t=typeof(v)
    if t=="nil" or t=="boolean" or t=="string" or t=="number" then return v end
    if t=="Vector3" then return {x=v.X,y=v.Y,z=v.Z} end
    if t=="CFrame" then
        local p=v.Position
        return {x=p.X,y=p.Y,z=p.Z}
    end
    if t=="Color3" then return {r=v.R,g=v.G,b=v.B} end
    if t=="Instance" then return {class=v.ClassName,name=v.Name,path=v:GetFullName()} end
    if t~="table" then return safeString(v) end
    if depth>=5 or seen[v] then return "<depth/cycle>" end
    seen[v]=true
    local out={}
    local n=0
    for k,x in pairs(v) do
        n+=1
        if n>160 then
            out.__truncated=true
            break
        end
        local key=(type(k)=="string" or type(k)=="number") and k or safeString(k)
        out[key]=primitive(x,depth+1,seen)
    end
    seen[v]=nil
    return out
end

local function saveData()
    if type(Save)~="table" or type(Save.Get)~="function" then return nil end
    local ok,v=pcall(Save.Get)
    if not ok then ok,v=pcall(Save.Get,Save) end
    return ok and type(v)=="table" and v or nil
end

local function assetCfg(category)
    if type(Assets)~="table" then return nil end
    local dir=Assets.Directory or Assets.Configs or Assets
    return type(dir)=="table" and dir[category] or nil
end

local function rarityOf(category)
    local cfg=assetCfg(category)
    local r=cfg and cfg.Rarity
    if type(r)=="table" then
        return {
            name=r.DisplayName or r._id or r.Name,
            number=tonumber(r.RarityNumber),
        }
    end
    return nil
end

local function earningsOf(item)
    if type(item)~="table" then return nil end
    if type(AssetEarnings)=="table" and type(AssetEarnings.MutationOnlyRatePerSecond)=="function" then
        local probe={}
        for k,v in pairs(item) do probe[k]=v end
        probe.Category=probe.Category or probe.AssetCategory
        probe.AssetCategory=probe.AssetCategory or probe.Category
        probe.Scale=probe.Scale or probe.AssetScale
        local ok,v=pcall(AssetEarnings.MutationOnlyRatePerSecond,probe)
        if not ok then ok,v=pcall(AssetEarnings.MutationOnlyRatePerSecond,AssetEarnings,probe) end
        v=tonumber(v)
        if ok and v then return v end
    end
    local cfg=assetCfg(item.Category or item.AssetCategory)
    return cfg and tonumber(cfg.EarningRate) or nil
end

local function sizeLabel(scale)
    scale=tonumber(scale)
    if not scale then return nil end
    if type(AssetSizeClassification)=="table" and type(AssetSizeClassification.Classify)=="function" then
        local ok,v=pcall(AssetSizeClassification.Classify,scale)
        if not ok then ok,v=pcall(AssetSizeClassification.Classify,AssetSizeClassification,scale) end
        if ok and type(v)=="table" then
            return v.DisplayName or v.Name or v.RichText
        end
    end
    return nil
end

local function itemRow(uid,item)
    if type(item)~="table" then return {uid=tostring(uid),missing=true} end
    local category=item.Category or item.AssetCategory
    local cfg=assetCfg(category)
    return {
        uid=tostring(uid),
        category=category,
        displayName=cfg and cfg.DisplayName or category,
        scale=tonumber(item.AssetScale or item.Scale),
        sizeLabel=sizeLabel(item.AssetScale or item.Scale),
        mutations=primitive(item.Mutations or {}),
        baseMutation=primitive(item.BaseMutation),
        favorite=item.Favorite or item.Favorited or item.IsFavorite,
        raw=primitive(item),
        rarity=rarityOf(category),
        earningsPerSecond=earningsOf(item),
    }
end

local function slotRows(data)
    if type(data)~="table" then return {},0 end
    local inv=data.Inventory or data.AssetInventory or data.PetInventory or {}
    local slots=data.FusionSlots or {}
    local rows={}
    local ordered={}
    for k,uid in pairs(slots) do
        if uid then ordered[#ordered+1]={k=k,uid=uid} end
    end
    table.sort(ordered,function(a,b)
        local an,bn=tonumber(a.k),tonumber(b.k)
        if an and bn then return an<bn end
        return tostring(a.k)<tostring(b.k)
    end)
    for _,slot in ipairs(ordered) do
        rows[#rows+1]=itemRow(slot.uid,inv[slot.uid])
    end
    return rows,#rows
end

local function inventorySnapshot(data)
    if type(data)~="table" then return {} end
    local inv=data.Inventory or data.AssetInventory or data.PetInventory or {}
    local out={}
    for uid,item in pairs(inv) do
        if type(item)=="table" then out[tostring(uid)]=itemRow(uid,item) end
    end
    return out
end

local function mergeInputRows(...)
    local out,seen={},{}
    for i=1,select("#",...) do
        local rows=select(i,...)
        for _,r in ipairs(type(rows)=="table" and rows or {}) do
            local uid=tostring(r.uid or "")
            if uid~="" and not seen[uid] then
                seen[uid]=true
                out[#out+1]=r
            end
        end
    end
    return out
end

local function removedInventoryRows(before,data)
    if type(before)~="table" or type(data)~="table" then return {} end
    local inv=data.Inventory or data.AssetInventory or data.PetInventory or {}
    local removed={}
    for uid,row in pairs(before) do
        if inv[uid]==nil and inv[tonumber(uid)]==nil then
            removed[#removed+1]=row
        end
    end
    return removed
end

local function signature(rows)
    local a={}
    for _,r in ipairs(rows or {}) do
        a[#a+1]=tostring(r.uid)
    end
    table.sort(a)
    return table.concat(a,"|")
end

local function fusePrice(rows,data)
    if type(FuseKernel)~="table" or type(FuseKernel.PriceFor)~="function" then return nil end
    data=data or saveData()
    local inv=data and (data.Inventory or data.PetInventory) or {}
    local items={}
    for _,r in ipairs(rows or {}) do
        if inv[r.uid] then items[#items+1]=inv[r.uid] end
    end
    if #items~=3 then return nil end
    local ok,v=pcall(FuseKernel.PriceFor,items)
    if not ok then ok,v=pcall(FuseKernel.PriceFor,FuseKernel,items) end
    return ok and tonumber(v) or nil
end

local function derived(inputs,reward)
    local d={}
    local scales={}
    local rates={}
    for _,r in ipairs(inputs or {}) do
        if tonumber(r.scale) then scales[#scales+1]=tonumber(r.scale) end
        if tonumber(r.earningsPerSecond) then rates[#rates+1]=tonumber(r.earningsPerSecond) end
    end
    if #scales>0 then
        local sum,minv,maxv=0,math.huge,-math.huge
        for _,v in ipairs(scales) do sum+=v;minv=math.min(minv,v);maxv=math.max(maxv,v) end
        d.inputScaleAverage=sum/#scales
        d.inputScaleMin=minv
        d.inputScaleMax=maxv
    end
    if #rates>0 then
        local sum=0
        for _,v in ipairs(rates) do sum+=v end
        d.inputEarningsTotal=sum
        d.inputEarningsAverage=sum/#rates
    end
    if type(reward)=="table" then
        local outScale=tonumber(reward.AssetScale or reward.Scale)
        d.outputScale=outScale
        if outScale and d.inputScaleAverage and d.inputScaleAverage>0 then
            d.outputScaleVsInputAverage=outScale/d.inputScaleAverage
        end
    end
    return d
end

local status

local function updateStatus(extra)
    if not status then return end
    local ready=S.lastReady and #S.lastReady.inputs or 0
    local last=S.samples[#S.samples]
    local lastText="nenhuma"
    if last and last.reward then
        local cat=last.reward.AssetCategory or last.reward.Category or "?"
        local scale=tonumber(last.reward.AssetScale or last.reward.Scale)
        lastText=tostring(cat)..(scale and (" • escala "..string.format("%.3f",scale)) or "")
    end
    status.Text=string.format(
        "Scanner: %s\nSlots prontos: %d/3 • Fusões registradas: %d\nÚltimo resultado: %s%s",
        S.enabled and "ATIVO" or "PAUSADO",
        ready,#S.samples,lastText,
        extra and ("\n"..extra) or ""
    )
end

local function event(kind,data)
    S.events[#S.events+1]={
        unix=os.time(),
        serverTime=Workspace:GetServerTimeNow(),
        kind=kind,
        data=primitive(data),
    }
end

local function captureFusionState(data,source)
    if type(data)~="table" then return end
    local rows,n=slotRows(data)
    local nowClock=os.clock()

    -- Keep a pre-fusion copy of Inventory from the first visible loaded slot.
    -- If the 3rd slot exists only for one server update, the three consumed UIDs
    -- can still be recovered by comparing this snapshot against Inventory at reward time.
    if n>0 and not S.cycleInventoryBefore then
        S.cycleInventoryBefore=inventorySnapshot(data)
        S.cycleStartedAt=nowClock
        event("FusionCycleStart",{source=source,count=n,inputs=rows})
    end

    if n>0 then
        S.lastSlotSnapshot=rows
        S.lastSlotAt=nowClock
        local observedSig=signature(rows)
        if observedSig~=S.lastObservedSlotSignature then
            S.lastObservedSlotSignature=observedSig
            event("SlotState",{source=source,count=n,inputs=rows})
            updateStatus("Entradas observadas: "..tostring(n).."/3")
        end
    elseif S.lastObservedSlotSignature~="" and nowClock-(S.lastSlotAt or 0)>20 then
        -- User likely cancelled/ejected without fusing; discard the stale cycle.
        S.lastObservedSlotSignature=""
        S.lastSlotSnapshot=nil
        S.cycleInventoryBefore=nil
        S.cycleStartedAt=0
    end

    if n==3 then
        local sig=signature(rows)
        if not (S.lastReady and S.lastReady.signature==sig) then
            S.lastReady={
                unix=os.time(),
                serverTime=Workspace:GetServerTimeNow(),
                signature=sig,
                inputs=rows,
                fusePrice=fusePrice(rows,data),
                moneyBefore=tonumber(data.Money),
                fusionLocked=data.FusionLocked,
                captureSource=source,
            }
            event("Ready3",S.lastReady)
            updateStatus("3 pets capturados; faça a fusão normalmente.")
        end
    end

    S.lastInventorySnapshot=inventorySnapshot(data)
    S.lastInventoryAt=nowClock
end

local function rewardKey(reward)
    if type(reward)~="table" then return tostring(reward) end
    local encoded
    pcall(function() encoded=Http:JSONEncode(primitive(reward)) end)
    return encoded or table.concat({
        tostring(reward.AssetCategory or reward.Category or "?"),
        tostring(reward.AssetScale or reward.Scale or "?"),
        tostring(reward.Uid or reward.UID or ""),
    },"|")
end

local function recordReward(reward,source)
    if not S.enabled or type(reward)~="table" then return end
    local key=rewardKey(reward)
    local nowClock=os.clock()
    if S.lastRewardKey==key and nowClock-(S.lastRewardAt or 0)<3 then return end
    S.lastRewardKey=key
    S.lastRewardAt=nowClock

    local data=saveData()
    local before=S.lastReady

    -- Prefer the exact 3-slot snapshot. If the machine began immediately after
    -- loading slot 3, recover consumed pets from the pre-cycle Inventory diff and
    -- merge with any 1/2-slot snapshot we did observe.
    local exactInputs=before and before.inputs or {}
    local recentSlots=(os.clock()-(S.lastSlotAt or 0)<=8) and S.lastSlotSnapshot or {}
    local removed=removedInventoryRows(S.cycleInventoryBefore,data or {})
    local recovered=mergeInputRows(exactInputs,recentSlots,removed)
    if #recovered>3 and #exactInputs~=3 then
        -- Fusion consumes exactly 3 same-category pets. Prefer a category that has
        -- at least 3 removed/recent rows, then keep the first three in slot/diff order.
        local groups={}
        for _,r in ipairs(recovered) do
            local k=tostring(r.category or "?")
            groups[k]=groups[k] or {}
            groups[k][#groups[k]+1]=r
        end
        for _,g in pairs(groups) do
            if #g>=3 then recovered={g[1],g[2],g[3]}; break end
        end
    end
    if #recovered>3 then
        recovered={recovered[1],recovered[2],recovered[3]}
    end

    local sample={
        index=#S.samples+1,
        unix=os.time(),
        serverTime=Workspace:GetServerTimeNow(),
        source=source,
        inputs=recovered,
        inputCaptureMethod=(#exactInputs==3 and "FusionSlots3") or (#removed>=3 and "InventoryDiff") or (#recentSlots>0 and "PartialSlots") or "none",
        inputSignature=#recovered>0 and signature(recovered) or nil,
        fusePrice=before and before.fusePrice or nil,
        moneyBefore=before and before.moneyBefore or nil,
        moneyAfter=data and tonumber(data.Money) or nil,
        reward=primitive(reward),
        rewardSummary=itemRow(reward.Uid or reward.UID or "reward",{
            Category=reward.AssetCategory or reward.Category,
            AssetCategory=reward.AssetCategory or reward.Category,
            AssetScale=reward.AssetScale or reward.Scale,
            Mutations=reward.Mutations,
            BaseMutation=reward.BaseMutation,
        }),
    }
    sample.derived=derived(sample.inputs,reward)
    if sample.moneyBefore and sample.moneyAfter then
        sample.moneySpent=math.max(0,sample.moneyBefore-sample.moneyAfter)
    end
    S.samples[#S.samples+1]=sample
    event("FuseReward",sample)
    updateStatus("Amostra #"..sample.index.." registrada • inputs "..tostring(#sample.inputs).."/3 ("..sample.inputCaptureMethod..").")
    S.lastReady=nil
    S.lastSlotSnapshot=nil
    S.lastSlotAt=0
    S.lastObservedSlotSignature=""
    S.cycleInventoryBefore=nil
    S.cycleStartedAt=0
end

-- Primary: official client signal fired when the server has chosen the fuse reward.
if type(FuseMachineSignals)=="table" then
    local sig=FuseMachineSignals.FuseStarted
    if sig and type(sig.Connect)=="function" then
        local ok,c=pcall(function()
            return sig:Connect(function(reward)
                recordReward(reward,"Client.FuseMachineSignals.FuseStarted")
            end)
        end)
        if ok and c then C[#C+1]=c end
    end
end

-- Event-driven Save capture. This is important because some game builds start
-- fusion immediately when slot 3 is inserted, making a polling-only scanner miss it.
if type(Save)=="table" and type(Save.FieldSignal)=="function" then
    local ok,sig=pcall(Save.FieldSignal,"FusionSlots")
    if not ok then ok,sig=pcall(Save.FieldSignal,Save,"FusionSlots") end
    if ok and sig and type(sig.Connect)=="function" then
        local ok2,c=pcall(function()
            return sig:Connect(function()
                if S.enabled then
                    local data=saveData()
                    if data then captureFusionState(data,"Save.FieldSignal(FusionSlots)") end
                end
            end)
        end)
        if ok2 and c then C[#C+1]=c; S.modules.FusionSlotSignal=true end
    end
end

if type(Save)=="table" and type(Save.WatchFields)=="function" then
    local fields={"FusionSlots","FusionLocked","FusionEggReward","Inventory"}
    local callback=function()
        if not S.enabled then return end
        local data=saveData()
        if data then captureFusionState(data,"Save.WatchFields") end
    end
    local ok,c=pcall(Save.WatchFields,fields,callback)
    if not ok then ok,c=pcall(Save.WatchFields,Save,fields,callback) end
    if ok then
        S.modules.SaveWatchFields=true
        if c and type(c.Disconnect)=="function" then C[#C+1]=c end
    end
end

-- Fast polling remains as a compatibility fallback.
task.spawn(function()
    local lastRewardRef=nil
    while S.enabled or (_G.PSICO_FUSION_SCAN_CLEANUP~=nil) do
        task.wait(.05)
        if not _G.PSICO_FUSION_SCAN_CLEANUP then break end
        local data=saveData()
        if data then
            captureFusionState(data,"poll")
            local reward=data.FusionEggReward
            if reward and reward~=false and type(reward)=="table" then
                local encoded
                pcall(function() encoded=Http:JSONEncode(primitive(reward)) end)
                encoded=encoded or safeString(reward)
                if encoded~=lastRewardRef then
                    lastRewardRef=encoded
                    recordReward(reward,"Save.FusionEggReward")
                end
            elseif reward==false or reward==nil then
                lastRewardRef=nil
            end
        end
    end
end)

local function uiParent()
    local ok,h=pcall(function() return gethui and gethui() end)
    return (ok and h) or CoreGui
end

local function corner(o,r)
    local c=Instance.new("UICorner")
    c.CornerRadius=UDim.new(0,r or 12)
    c.Parent=o
end

local gui=Instance.new("ScreenGui")
gui.Name="PsicoFusionResearchScanner"
gui.ResetOnSpawn=false
gui.IgnoreGuiInset=false
gui.Parent=uiParent()

local vp=Camera and Camera.ViewportSize or Vector2.new(1280,720)
local W=math.floor(math.clamp(vp.X*.62,520,820))
local H=math.floor(math.clamp(vp.Y*.58,330,450))
local main=Instance.new("Frame")
main.AnchorPoint=Vector2.new(.5,.5)
main.Position=UDim2.fromScale(.5,.5)
main.Size=UDim2.fromOffset(W,H)
main.BackgroundColor3=Color3.fromRGB(9,19,36)
main.BorderSizePixel=0
main.Parent=gui
corner(main,18)

local header=Instance.new("Frame")
header.BackgroundTransparency=1
header.Position=UDim2.fromOffset(16,8)
header.Size=UDim2.new(1,-32,0,42)
header.Active=true
header.Parent=main

local title=Instance.new("TextLabel")
title.BackgroundTransparency=1
title.Size=UDim2.new(1,-56,1,0)
title.Font=Enum.Font.GothamBold
title.Text="FUSION RESEARCH SCANNER • V1.1"
title.TextSize=21
title.TextColor3=Color3.new(1,1,1)
title.TextXAlignment=Enum.TextXAlignment.Left
title.Parent=header

local close=Instance.new("TextButton")
close.AnchorPoint=Vector2.new(1,0)
close.Position=UDim2.new(1,0,0,0)
close.Size=UDim2.fromOffset(42,38)
close.BackgroundColor3=Color3.fromRGB(31,43,62)
close.BorderSizePixel=0
close.Text="×"
close.TextSize=24
close.Font=Enum.Font.GothamBold
close.TextColor3=Color3.new(1,1,1)
close.Parent=header
corner(close,11)

status=Instance.new("TextLabel")
status.Position=UDim2.fromOffset(18,58)
status.Size=UDim2.new(1,-36,0,104)
status.BackgroundColor3=Color3.fromRGB(16,34,58)
status.BorderSizePixel=0
status.TextColor3=Color3.fromRGB(220,230,245)
status.Font=Enum.Font.Code
status.TextSize=14
status.TextWrapped=true
status.TextXAlignment=Enum.TextXAlignment.Left
status.TextYAlignment=Enum.TextYAlignment.Top
status.Parent=main
corner(status,12)
local pad=Instance.new("UIPadding")
pad.PaddingTop=UDim.new(0,10)
pad.PaddingLeft=UDim.new(0,12)
pad.PaddingRight=UDim.new(0,12)
pad.Parent=status

local help=Instance.new("TextLabel")
help.BackgroundTransparency=1
help.Position=UDim2.fromOffset(18,170)
help.Size=UDim2.new(1,-36,0,55)
help.Text="Uso: coloque 3 pets iguais na máquina e faça a fusão normalmente.\nO scanner registra automaticamente os 3 pets e o ovo escolhido pelo servidor."
help.TextWrapped=true
help.TextColor3=Color3.fromRGB(166,186,218)
help.Font=Enum.Font.Gotham
help.TextSize=13
help.TextXAlignment=Enum.TextXAlignment.Left
help.TextYAlignment=Enum.TextYAlignment.Top
help.Parent=main

local buttons=Instance.new("Frame")
buttons.BackgroundTransparency=1
buttons.Position=UDim2.fromOffset(18,232)
buttons.Size=UDim2.new(1,-36,1,-248)
buttons.Parent=main

local function mkButton(txt,x,w,fn)
    local b=Instance.new("TextButton")
    b.Position=UDim2.new(x,0,0,0)
    b.Size=UDim2.new(w,-6,1,0)
    b.BackgroundColor3=Color3.fromRGB(42,91,151)
    b.BorderSizePixel=0
    b.Text=txt
    b.TextColor3=Color3.new(1,1,1)
    b.Font=Enum.Font.GothamBold
    b.TextSize=14
    b.Parent=buttons
    corner(b,11)
    C[#C+1]=b.Activated:Connect(fn)
    return b
end

local pauseButton
pauseButton=mkButton("PAUSAR",0,.23,function()
    S.enabled=not S.enabled
    pauseButton.Text=S.enabled and "PAUSAR" or "RETOMAR"
    updateStatus()
end)

mkButton("EXPORTAR JSON",.23,.34,function()
    local payload={
        scanner="Psico Fusion Research Scanner V1.1",
        placeId=game.PlaceId,
        gameId=game.GameId,
        jobId=game.JobId,
        userId=LP.UserId,
        started=S.started,
        exported=os.time(),
        modules=S.modules,
        samples=S.samples,
        events=S.events,
    }
    local ok,json=pcall(Http.JSONEncode,Http,payload)
    if not ok then updateStatus("Erro JSON: "..safeString(json));return end
    local name="Psico_FusionScan_"..os.time()..".json"
    if type(writefile)=="function" then
        local ok2,e=pcall(writefile,name,json)
        updateStatus(ok2 and ("Exportado: "..name) or ("writefile falhou: "..safeString(e)))
    elseif type(setclipboard)=="function" then
        pcall(setclipboard,json)
        updateStatus("JSON copiado para clipboard.")
    else
        updateStatus("Executor sem writefile/setclipboard.")
    end
end)

mkButton("LIMPAR",.57,.20,function()
    S.samples={}
    S.events={}
    S.lastReady=nil
    S.lastSlotSnapshot=nil
    S.lastSlotAt=0
    S.lastObservedSlotSignature=""
    S.cycleInventoryBefore=nil
    S.cycleStartedAt=0
    S.lastInventorySnapshot=nil
    S.lastInventoryAt=0
    S.lastRewardKey=nil
    S.lastRewardAt=0
    updateStatus("Amostras limpas.")
end)

mkButton("FECHAR",.77,.23,function()
    if _G.PSICO_FUSION_SCAN_CLEANUP then _G.PSICO_FUSION_SCAN_CLEANUP() end
end)

local dragging=false
local dragStart,startPos,dragInput
C[#C+1]=header.InputBegan:Connect(function(input)
    if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
        dragging=true
        dragStart=input.Position
        startPos=main.Position
        dragInput=input
    end
end)
C[#C+1]=UIS.InputChanged:Connect(function(input)
    if not dragging then return end
    if input.UserInputType==Enum.UserInputType.MouseMovement or input.UserInputType==Enum.UserInputType.Touch then
        local d=input.Position-dragStart
        main.Position=UDim2.new(startPos.X.Scale,startPos.X.Offset+d.X,startPos.Y.Scale,startPos.Y.Offset+d.Y)
    end
end)
C[#C+1]=UIS.InputEnded:Connect(function(input)
    if input==dragInput or input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
        dragging=false
    end
end)
C[#C+1]=close.Activated:Connect(function()
    if _G.PSICO_FUSION_SCAN_CLEANUP then _G.PSICO_FUSION_SCAN_CLEANUP() end
end)

_G.PSICO_FUSION_SCAN_CLEANUP=function()
    S.enabled=false
    for _,c in ipairs(C) do pcall(function() c:Disconnect() end) end
    pcall(function() gui:Destroy() end)
    _G.PSICO_FUSION_SCAN_CLEANUP=nil
end

updateStatus("Faça algumas fusões diferentes e exporte o JSON.")

-- PSICOSENATICO | FUSION RESEARCH SCANNER V2.8
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
local scannerName="Psico Fusion Research Scanner V2.8"

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

local saveDiagnostics={
    calls=0,
    source=nil,
    lastError=nil,
    getAvailable=type(Save)=="table" and type(Save.Get)=="function" or false,
    peekAvailable=type(Save)=="table" and type(Save.Peek)=="function" or false,
    awaitAvailable=type(Save)=="table" and type(Save.Await)=="function" or false,
    peekFullDirectType=nil,
    peekFullSelfType=nil,
    peekFusionSlotsType=nil,
    peekInventoryType=nil,
    awaitType=nil,
}

local function callSaveFunction(name,...)
    if type(Save)~="table" then return nil,false,nil end
    local fn=Save[name]
    if type(fn)~="function" then return nil,false,"missing" end

    local args=table.pack(...)
    local ok,value=pcall(fn,table.unpack(args,1,args.n))
    if ok and value~=nil then return value,true,"direct" end

    local ok2,value2=pcall(fn,Save,table.unpack(args,1,args.n))
    if ok2 and value2~=nil then return value2,true,"self" end

    local err=(not ok and value) or (not ok2 and value2) or "nil"
    return nil,false,tostring(err)
end

local function getSave()
    if type(Save)~="table" then
        saveDiagnostics.lastError="Shared.Save ausente"
        return nil
    end
    saveDiagnostics.calls+=1

    -- Older builds exposed Get(); the current build from the user's V2.1
    -- export exposes Peek/Await instead. Try both families without assuming one.
    if type(Save.Get)=="function" then
        local data,ok,mode=callSaveFunction("Get")
        if ok and type(data)=="table" then
            saveDiagnostics.source="Get/"..tostring(mode)
            saveDiagnostics.lastError=nil
            return data
        end
    end

    if type(Save.Peek)=="function" then
        local data,ok,mode=callSaveFunction("Peek")
        saveDiagnostics.peekFullDirectType=ok and typeof(data) or saveDiagnostics.peekFullDirectType
        if ok and type(data)=="table" then
            -- A no-argument Peek normally returns the full client save.
            if data.FusionSlots~=nil or data.Inventory~=nil or data.Money~=nil or data.SpeedPower~=nil then
                saveDiagnostics.source="Peek/full/"..tostring(mode)
                saveDiagnostics.lastError=nil
                return data
            end
        end
    end

    saveDiagnostics.lastError="nenhum snapshot completo disponível"
    return nil
end

local function peekField(field)
    if type(Save)~="table" or type(Save.Peek)~="function" then return nil,false,nil end

    local value,ok,mode=callSaveFunction("Peek",field)
    if ok then
        if field=="FusionSlots" then saveDiagnostics.peekFusionSlotsType=typeof(value) end
        if field=="Inventory" then saveDiagnostics.peekInventoryType=typeof(value) end
        if type(value)=="table" and value[field]~=nil then
            return value[field],true,"Peek/"..field.."/wrapped/"..tostring(mode)
        end
        return value,true,"Peek/"..field.."/"..tostring(mode)
    end

    -- Some versions only support full Peek().
    local full=getSave()
    if type(full)=="table" and full[field]~=nil then
        return full[field],true,"Peek/full."..field
    end
    return nil,false,nil
end

local function decodeItem(raw)
    if type(AssetItems)=="table" and type(AssetItems.Decode)=="function" then
        local ok,item=pcall(AssetItems.Decode,raw)
        if ok and type(item)=="table" then return item,"AssetItems.Decode" end

        local ok2,item2=pcall(AssetItems.Decode,AssetItems,raw)
        if ok2 and type(item2)=="table" then return item2,"AssetItems:Decode" end
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
            if ok and tonumber(v) then return tonumber(v),"AssetEarnings.CatalogRatePerSecond" end
            local ok2,v2=pcall(AssetEarnings.CatalogRatePerSecond,AssetEarnings,item)
            if ok2 and tonumber(v2) then return tonumber(v2),"AssetEarnings:CatalogRatePerSecond" end
        end
        if type(AssetEarnings.MutationOnlyRatePerSecond)=="function" then
            local shape={
                Category=item.Category or item.AssetCategory,
                Scale=item.Scale or item.AssetScale,
                Mutations=item.Mutations or {},
            }
            local ok,v=pcall(AssetEarnings.MutationOnlyRatePerSecond,shape)
            if ok and tonumber(v) then return tonumber(v),"AssetEarnings.MutationOnlyRatePerSecond" end
            local ok2,v2=pcall(AssetEarnings.MutationOnlyRatePerSecond,AssetEarnings,shape)
            if ok2 and tonumber(v2) then return tonumber(v2),"AssetEarnings:MutationOnlyRatePerSecond" end
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
    local weightLabel

    -- The V2 test exposed the game's own exact helpers:
    -- AssetItems.WeightKg and AssetItems.WeightLabel.
    if type(AssetItems)=="table" and type(AssetItems.WeightKg)=="function" then
        local ok,v=pcall(AssetItems.WeightKg,item)
        if ok and tonumber(v) then
            weight=tonumber(v)
            weightSource="AssetItems.WeightKg"
        else
            local ok2,v2=pcall(AssetItems.WeightKg,AssetItems,item)
            if ok2 and tonumber(v2) then
                weight=tonumber(v2)
                weightSource="AssetItems:WeightKg"
            end
        end
    end
    if type(AssetItems)=="table" and type(AssetItems.WeightLabel)=="function" then
        local ok,v=pcall(AssetItems.WeightLabel,item)
        if ok and v~=nil then
            weightLabel=tostring(v)
        else
            local ok2,v2=pcall(AssetItems.WeightLabel,AssetItems,item)
            if ok2 and v2~=nil then weightLabel=tostring(v2) end
        end
    end

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
        weightLabel=weightLabel,
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
    local salePrice
    if type(AssetItems)=="table" and type(AssetItems.SalePrice)=="function" then
        local ok,v=pcall(AssetItems.SalePrice,item)
        if not ok then ok,v=pcall(AssetItems.SalePrice,AssetItems,item) end
        if ok and tonumber(v) then salePrice=tonumber(v) end
    end
    return {
        uid="reward",
        category=category and tostring(category) or nil,
        displayName=(cfg and cfg.DisplayName) or (category and tostring(category)) or nil,
        rarity=rarity and {name=tostring(rarity.DisplayName or rarity._id),number=tonumber(rarity.RarityNumber)} or nil,
        scale=tonumber(reward.AssetScale or reward.Scale) or 1,
        earningsPerSecond=rate,
        earningsMethod=method,
        salePrice=salePrice,
        mutations=cloneArray(reward.Mutations),
        baseMutation=reward.BaseMutation,
        raw=jsonSafe(raw),
        decoded=jsonSafe(reward),
    }
end

local function mutationNames(summary)
    local out,seen={},{}
    if type(summary)~="table" then return out end
    local function add(v)
        if v==nil then return end
        local name=type(v)=="table" and (v._id or v.DisplayName or v.Name) or v
        name=name and tostring(name) or nil
        local key=name and string.lower(name) or ""
        if key~="" and not seen[key] then
            seen[key]=true
            out[#out+1]=name
        end
    end
    add(summary.baseMutation)
    if type(summary.mutations)=="table" then
        for _,v in pairs(summary.mutations) do add(v) end
    end
    table.sort(out)
    return out
end

local function mutationProfile(inputs,rewardSummary)
    local inputNames={}
    local inputNameCounts={}
    local mutatedPets=0
    for _,x in ipairs(inputs or {}) do
        local names=mutationNames(x)
        if #names>0 then mutatedPets+=1 end
        for _,name in ipairs(names) do
            inputNames[name]=true
            inputNameCounts[name]=(inputNameCounts[name] or 0)+1
        end
    end
    local distinct={}
    for name in pairs(inputNames) do distinct[#distinct+1]=name end
    table.sort(distinct)

    local outputNames=mutationNames(rewardSummary)
    local outputSet={}
    for _,name in ipairs(outputNames) do outputSet[name]=true end
    local retained={}
    for _,name in ipairs(distinct) do
        if outputSet[name] then retained[#retained+1]=name end
    end

    return {
        inputMutatedPets=mutatedPets,
        inputMutationBucket=tostring(mutatedPets).."/3",
        inputDistinctMutations=distinct,
        inputMutationCounts=inputNameCounts,
        outputHasMutation=#outputNames>0,
        outputMutations=outputNames,
        retainedInputMutations=retained,
        anyInputMutationRetained=#retained>0,
    }
end

local function calcMetrics(inputs,rewardSummary,decodedInputs)
    local m={
        count=#inputs,
        sumScale=0,
        sumEarningsPerSecond=0,
        sumSalePrice=0,
        salePriceCount=0,
        sumWeight=0,
        weightCount=0,
        minScale=nil,maxScale=nil,
        minEarningsPerSecond=nil,maxEarningsPerSecond=nil,
        minSalePrice=nil,maxSalePrice=nil,
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

        local sale=tonumber(x.salePrice)
        if sale then
            m.sumSalePrice+=sale
            m.salePriceCount+=1
            m.minSalePrice=m.minSalePrice and math.min(m.minSalePrice,sale) or sale
            m.maxSalePrice=m.maxSalePrice and math.max(m.maxSalePrice,sale) or sale
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
    if m.salePriceCount>0 then m.meanSalePrice=m.sumSalePrice/m.salePriceCount end

    if type(FuseKernel)=="table" and type(FuseKernel.PriceFor)=="function" and #decodedInputs==3 then
        local ok,v=pcall(FuseKernel.PriceFor,decodedInputs)
        if not ok then ok,v=pcall(FuseKernel.PriceFor,FuseKernel,decodedInputs) end
        if ok and tonumber(v) then m.fusionPrice=tonumber(v) end
    end

    if rewardSummary then
        local oscale=tonumber(rewardSummary.scale)
        local orate=tonumber(rewardSummary.earningsPerSecond)
        local osale=tonumber(rewardSummary.salePrice)

        if oscale and m.meanScale and m.meanScale>0 then
            m.outputScaleVsMeanInputScale=oscale/m.meanScale
        end
        if orate and m.sumEarningsPerSecond>0 then
            m.outputEarningsVsInputSum=orate/m.sumEarningsPerSecond
            m.retainedEarningsPercent=m.outputEarningsVsInputSum*100
            m.earningsLostVsInputSum=m.sumEarningsPerSecond-orate
        end
        if orate and m.maxEarningsPerSecond and m.maxEarningsPerSecond>0 then
            m.outputEarningsVsBestInput=orate/m.maxEarningsPerSecond
            m.retainedBestInputPercent=m.outputEarningsVsBestInput*100
        end
        if orate and m.meanEarningsPerSecond and m.meanEarningsPerSecond>0 then
            m.outputEarningsVsMeanInput=orate/m.meanEarningsPerSecond
        end
        if osale and m.sumSalePrice>0 then
            m.outputSaleValueVsInputSaleValue=osale/m.sumSalePrice
        end
    end

    if m.fusionPrice and m.sumSalePrice>0 then
        m.fusionPriceVsInputSalePrice=m.fusionPrice/m.sumSalePrice
    end
    if m.fusionPrice and m.sumEarningsPerSecond>0 then
        m.fusionPricePerInputEarnings=m.fusionPrice/m.sumEarningsPerSecond
    end

    m.mutation=mutationProfile(inputs,rewardSummary)
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
    observedFusionSlots=nil,
    observedInventory=nil,
    observedSave=nil,
    fieldSignalEvents=0,
    watchFieldEvents=0,
    lastKernelSlotSignature="",
    sessionInventoryIncomeTarget=nil,
    kernelResearch={
        inspected=false,
        functionInfo={},
        probes={},
        lastRun=nil,
    },
}
local conns={}
local cleanupFns={}

local function keepCleanupHandle(handle)
    if typeof(handle)=="RBXScriptConnection" then
        conns[#conns+1]=handle
    elseif type(handle)=="function" then
        cleanupFns[#cleanupFns+1]=handle
    elseif type(handle)=="table" and type(handle.Disconnect)=="function" then
        cleanupFns[#cleanupFns+1]=function() pcall(handle.Disconnect,handle) end
    end
end

local function looksLikeFusionSlots(t)
    if type(t)~="table" then return false end
    if t.FusionSlots~=nil then return false end
    local seen=0
    for k,v in pairs(t) do
        if type(k)=="number" then
            if v~=nil and type(v)~="string" then return false end
            if v~=nil then seen+=1 end
        else
            return false
        end
    end
    return seen<=3
end

local function absorbObservedTable(t,source)
    if type(t)~="table" then return end
    if type(t.FusionSlots)=="table" then
        state.observedFusionSlots=t.FusionSlots
        state.observedSave=t
    end
    if type(t.Inventory)=="table" then
        state.observedInventory=t.Inventory
        state.observedSave=t
    end
    if looksLikeFusionSlots(t) then
        state.observedFusionSlots=t
    end
end

local function absorbSignalArgs(source,...)
    local args=table.pack(...)
    for i=1,args.n do
        if type(args[i])=="table" then absorbObservedTable(args[i],source) end
    end
end

local function refreshObservedFromPeek()
    -- This is the main V2.2 fix for the visual "one pet behind" behavior.
    -- V2.1's WatchFields payload represented the previous FusionSlots state;
    -- Peek reads the committed/current value after the callback.
    local slots,slotsOk=peekField("FusionSlots")
    if slotsOk and type(slots)=="table" then
        if type(slots.FusionSlots)=="table" then slots=slots.FusionSlots end
        if looksLikeFusionSlots(slots) then
            state.observedFusionSlots=slots
        end
    end

    local inv,invOk=peekField("Inventory")
    if invOk and type(inv)=="table" then
        if type(inv.Inventory)=="table" then inv=inv.Inventory end
        state.observedInventory=inv
    end
end

local function captureSlots()
    refreshObservedFromPeek()

    local save=getSave()
    if save then
        absorbObservedTable(save,"Save snapshot")
    else
        if state.observedSave then
            save=state.observedSave
        elseif state.observedFusionSlots or state.observedInventory then
            save={
                FusionSlots=state.observedFusionSlots or {},
                Inventory=state.observedInventory or {},
            }
        end
    end
    if not save then return nil end

    local fusionSlots=type(save.FusionSlots)=="table" and save.FusionSlots or state.observedFusionSlots or {}
    local inventory=type(save.Inventory)=="table" and save.Inventory or state.observedInventory or {}

    local slots={}
    local inputs={}
    local decodedInputs={}
    for index,uid in ipairs(fusionSlots) do
        if uid then
            slots[#slots+1]=tostring(uid)
            local raw=inventory and inventory[uid]
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

local function dataCopy(v,depth,seen)
    depth=depth or 0
    seen=seen or {}
    if depth>8 then return nil end
    if type(v)~="table" then return v end
    if seen[v] then return nil end
    seen[v]=true
    local out={}
    for k,val in pairs(v) do
        local tk,tv=type(k),typeof(val)
        if (tk=="string" or tk=="number") and (tv=="table" or tv=="string" or tv=="number" or tv=="boolean" or tv=="nil") then
            out[k]=dataCopy(val,depth+1,seen)
        end
    end
    seen[v]=nil
    return out
end

local function inspectFunction(name,fn)
    local out={name=name,available=type(fn)=="function"}
    if type(fn)~="function" then return out end

    local dbg=debug
    if type(dbg)=="table" and type(dbg.info)=="function" then
        local ok,a,b=pcall(dbg.info,fn,"a")
        if ok then
            out.arity=tonumber(a)
            out.isVararg=b==true
        end
        local ok2,src=pcall(dbg.info,fn,"s")
        if ok2 then out.source=tostring(src) end
        local ok3,nm=pcall(dbg.info,fn,"n")
        if ok3 and nm~=nil then out.debugName=tostring(nm) end
    end

    local getinfo=(type(dbg)=="table" and dbg.getinfo) or getinfo
    if type(getinfo)=="function" then
        local ok,info=pcall(getinfo,fn)
        if ok and type(info)=="table" then
            out.getinfo=jsonSafe(info)
        end
    end

    local getconstants=(type(dbg)=="table" and dbg.getconstants) or getconstants
    if type(getconstants)=="function" then
        local ok,constants=pcall(getconstants,fn)
        if ok and type(constants)=="table" then
            local clean={}
            for i=1,math.min(#constants,120) do
                local v=constants[i]
                local tv=typeof(v)
                if tv=="string" or tv=="number" or tv=="boolean" then clean[#clean+1]=v end
            end
            out.constants=clean
        end
    end

    local getups=(type(dbg)=="table" and dbg.getupvalues) or getupvalues
    if type(getups)=="function" then
        local ok,ups=pcall(getups,fn)
        if ok and type(ups)=="table" then
            local clean={}
            local n=0
            for k,v in pairs(ups) do
                n+=1
                if n>80 then break end
                clean[tostring(k)]=typeof(v)=="table" and jsonSafe(v,0,{}) or tostring(v)
            end
            out.upvalues=clean
        end
    end
    return out
end

local function debugUpvalues(fn)
    if type(fn)~="function" then return nil end
    local dbg=debug
    local getups=(type(dbg)=="table" and dbg.getupvalues) or getupvalues
    if type(getups)~="function" then return nil end
    local ok,ups=pcall(getups,fn)
    return ok and type(ups)=="table" and ups or nil
end

local function flatPrimitiveTable(tbl,maxDepth)
    local out={}
    maxDepth=maxDepth or 4
    local seen={}
    local function walk(v,path,depth)
        if depth>maxDepth then return end
        local tv=typeof(v)
        if tv=="number" or tv=="string" or tv=="boolean" then
            out[#out+1]={path=path,value=v}
            return
        end
        if tv~="table" or seen[v] then return end
        seen[v]=true
        local n=0
        for k,val in pairs(v) do
            n+=1
            if n>240 then break end
            local child=(path=="" and tostring(k)) or (path.."."..tostring(k))
            walk(val,child,depth+1)
        end
        seen[v]=nil
    end
    walk(tbl,"",0)
    return out
end

local function assetHelpersFromDrawFusedScale()
    if type(FuseKernel)~="table" or type(FuseKernel.DrawFusedScale)~="function" then
        return nil,nil
    end
    local ups=debugUpvalues(FuseKernel.DrawFusedScale)
    if not ups then return nil,nil end
    for k,v in pairs(ups) do
        if type(v)=="table" and type(v.DrawAssetScale)=="function" then
            return v,k
        end
    end
    return nil,nil
end

local function inspectChildUpvalues(fn)
    local out={functions={},tables={}}
    local ups=debugUpvalues(fn)
    if not ups then return out end
    for k,v in pairs(ups) do
        if type(v)=="function" then
            out.functions[tostring(k)]=inspectFunction("upvalue_"..tostring(k),v)
        elseif type(v)=="table" then
            out.tables[tostring(k)]=flatPrimitiveTable(v,4)
        end
    end
    return out
end

local function inspectFuseKernel()
    if state.kernelResearch.inspected then return state.kernelResearch.functionInfo end
    state.kernelResearch.inspected=true
    if type(FuseKernel)=="table" then
        state.kernelResearch.functionInfo.BandWeightBias=inspectFunction("BandWeightBias",FuseKernel.BandWeightBias)
        state.kernelResearch.functionInfo.DrawFusedScale=inspectFunction("DrawFusedScale",FuseKernel.DrawFusedScale)
        state.kernelResearch.functionInfo.PriceFor=inspectFunction("PriceFor",FuseKernel.PriceFor)
        state.kernelResearch.functionInfo.MayEnterFuse=inspectFunction("MayEnterFuse",FuseKernel.MayEnterFuse)
        state.kernelResearch.functionInfo.DrawAssetScale=inspectFunction("DrawAssetScale",AssetItems and AssetItems.DrawAssetScale)
        state.kernelResearch.functionInfo.WeightKgForScale=inspectFunction("WeightKgForScale",AssetItems and AssetItems.WeightKgForScale)

        local helperTable,helperUpvalueKey=assetHelpersFromDrawFusedScale()
        state.kernelResearch.assetHelperUpvalueKey=helperUpvalueKey and tostring(helperUpvalueKey) or nil
        state.kernelResearch.assetHelperKeys=moduleKeys(helperTable)
        if type(helperTable)=="table" then
            state.kernelResearch.functionInfo.DrawAssetScaleFromFuseUpvalue=
                inspectFunction("DrawAssetScaleFromFuseUpvalue",helperTable.DrawAssetScale)
            state.kernelResearch.functionInfo.WeightKgForScaleFromFuseUpvalue=
                inspectFunction("WeightKgForScaleFromFuseUpvalue",helperTable.WeightKgForScale)
            state.kernelResearch.drawAssetScaleChildren=inspectChildUpvalues(helperTable.DrawAssetScale)
            state.kernelResearch.drawAssetScaleHelperPrimitives=flatPrimitiveTable(helperTable,2)
        end
    end
    return state.kernelResearch.functionInfo
end

local function distributionFromValues(values,keepValues)
    if type(values)~="table" or #values==0 then return nil end
    local sorted={}
    for _,v in ipairs(values) do
        if finite(tonumber(v)) then sorted[#sorted+1]=tonumber(v) end
    end
    if #sorted==0 then return nil end
    table.sort(sorted)

    local sum=0
    for _,v in ipairs(sorted) do sum+=v end
    local mean=sum/#sorted
    local var=0
    for _,v in ipairs(sorted) do var+=(v-mean)^2 end
    var=var/#sorted

    local function quantile(p)
        local idx=math.clamp(math.floor((#sorted-1)*p+1.5),1,#sorted)
        return sorted[idx]
    end

    local out={
        n=#sorted,
        min=sorted[1],
        max=sorted[#sorted],
        mean=mean,
        stddev=math.sqrt(var),
        p01=quantile(.01),
        p05=quantile(.05),
        p10=quantile(.10),
        p25=quantile(.25),
        p50=quantile(.50),
        p75=quantile(.75),
        p90=quantile(.90),
        p95=quantile(.95),
        p99=quantile(.99),
    }
    if keepValues then out.values=sorted end
    return out
end

local function directNumericCall(fn,args)
    if type(fn)~="function" then return false,nil,"function unavailable" end
    local copied={}
    for i,v in ipairs(args or {}) do copied[i]=dataCopy(v) end
    local ok,res=pcall(fn,table.unpack(copied))
    if ok and finite(tonumber(res)) then return true,tonumber(res),nil end
    return false,res,ok and "non-numeric result" or tostring(res)
end

local function drawScaleDistribution(scales,count)
    local fn=type(FuseKernel)=="table" and FuseKernel.DrawFusedScale or nil
    if type(fn)~="function" then return nil,"DrawFusedScale unavailable" end
    if type(scales)~="table" or #scales~=3 then return nil,"need exactly 3 scales" end

    local values={}
    local errors={}
    count=math.clamp(tonumber(count) or 256,16,1024)
    for _=1,count do
        local ok,value,err=directNumericCall(fn,{scales})
        if ok then
            values[#values+1]=value
        elseif #errors<8 then
            errors[#errors+1]=tostring(err)
        end
    end
    local dist=distributionFromValues(values,true)
    if dist then
        dist.inputScales={scales[1],scales[2],scales[3]}
        dist.requestedDraws=count
        dist.errors=errors
    end
    return dist,#values>0 and nil or errors[1]
end

local function baselineRateForScale(category,scale)
    if not category or not finite(tonumber(scale)) then return nil end
    local rate=itemRate({
        Category=category,
        AssetCategory=category,
        Scale=tonumber(scale),
        AssetScale=tonumber(scale),
        Mutations={},
    })
    return tonumber(rate)
end

-- V2.8: use the actual SCALE_BANDS table embedded in the client's
-- DrawAssetScale, rather than inventing research bands. Weight does not
-- participate in either roulette scoring or the economic objectives.
local cachedScaleRules=nil
local cachedScaleRulesAttempted=false

local function loadClientScaleRules()
    if cachedScaleRulesAttempted then return cachedScaleRules end
    cachedScaleRulesAttempted=true
    local helperTable=assetHelpersFromDrawFusedScale()
    local draw=helperTable and helperTable.DrawAssetScale
    if type(draw)~="function" and type(AssetItems)=="table" then
        draw=AssetItems.DrawAssetScale
    end
    local ups=debugUpvalues(draw)
    for _,up in pairs(ups or {}) do
        if type(up)=="table" and type(up.SCALE_BANDS)=="table" then
            local bands={}
            for idx,raw in ipairs(up.SCALE_BANDS) do
                local lo=tonumber(raw.min)
                local hi=tonumber(raw.max)
                local weight=tonumber(raw.weight)
                if not (finite(lo) and finite(hi) and finite(weight) and lo>0 and hi>lo and weight>0) then
                    return nil
                end
                bands[#bands+1]={index=idx,min=lo,max=hi,rawWeight=weight}
            end
            local cap=tonumber(up.SCALE_HARD_CAP)
            local odds=tonumber(up.SCALE_DOUBLING_ODDS)
            if #bands>0 and finite(cap) and cap>0 and finite(odds) and odds>=0 and odds<1 then
                cachedScaleRules={
                    source="Runtime DrawAssetScale upvalue SCALE_BANDS",
                    bands=bands,
                    bandCount=#bands,
                    scaleHardCap=cap,
                    doublingOdds=odds,
                    assumptions={
                        "SCALE_BANDS and their weights are read directly from the loaded client.",
                        "BandWeightBias is called for each exact original band using this trio.",
                        "The uniform draw inside a band is supported by observed local samples but not formally proved.",
                        "Repeated 1% doubling until the cap is a WORKING HYPOTHESIS: the exact control flow of DrawAssetScale has not been recovered.",
                        "Output mutations and their effects are excluded from the economic projection.",
                    },
                }
                return cachedScaleRules
            end
        end
    end
    return nil
end

local function buildWeightedClientBands(scales)
    local rules=loadClientScaleRules()
    local biasFn=type(FuseKernel)=="table" and FuseKernel.BandWeightBias or nil
    if not rules then return nil,"Exact client SCALE_BANDS unavailable" end
    if type(biasFn)~="function" then return nil,"BandWeightBias unavailable" end
    if type(scales)~="table" or #scales~=3 then return nil,"Exactly 3 input Scales required" end

    local orderedScales={scales[1],scales[2],scales[3]}
    table.sort(orderedScales)
    local rows={}
    local total=0
    for _,b in ipairs(rules.bands) do
        local ok,bias,err=directNumericCall(biasFn,{orderedScales,b.min,b.max})
        if not ok or not finite(bias) or bias<=0 then
            return nil,"BandWeightBias failed on official band "..tostring(b.index)..": "..tostring(err or bias)
        end
        local effective=b.rawWeight*bias
        total+=effective
        rows[#rows+1]={
            index=b.index,
            min=b.min,
            max=b.max,
            rawWeight=b.rawWeight,
            bias=bias,
            effectiveWeight=effective,
        }
    end
    if total<=0 or not finite(total) then return nil,"Invalid effective band weight sum" end
    for _,b in ipairs(rows) do b.probability=b.effectiveWeight/total end
    return {
        source=rules.source,
        rules=rules,
        inputScales={scales[1],scales[2],scales[3]},
        bands=rows,
        effectiveWeightTotal=total,
        bandCount=#rows,
        modelStatus="Experimental: exact client bands/bias; geometric doubling and within-band uniformity require validation.",
    }
end

-- The geometric doubling treatment below is intentionally a hypothesis.
-- Retain the base-band-only distribution for independent comparison.
local ANALYTIC_TAIL_STEPS=6
local function analyticPAboveScale(model,threshold,withDoubling)
    if type(model)~="table" then return nil end
    threshold=tonumber(threshold)
    if not finite(threshold) then return nil end
    local cap=model.rules.scaleHardCap
    if threshold<0 then return 1 end
    if threshold>=cap then return 0 end
    local odds=withDoubling and model.rules.doublingOdds or 0
    local probability=0

    for _,band in ipairs(model.bands or {}) do
        local width=band.max-band.min
        for k=0,ANALYTIC_TAIL_STEPS do
            local factor
            if odds==0 then
                factor=k==0 and 1 or 0
            elseif k==ANALYTIC_TAIL_STEPS then
                factor=odds^k
            else
                factor=(1-odds)*(odds^k)
            end
            if factor>0 then
                local thresholdAtBase=threshold/(2^k)
                local fraction=math.clamp((band.max-math.max(band.min,thresholdAtBase))/width,0,1)
                probability+=band.probability*factor*fraction
            end
        end
    end

    return math.clamp(probability,0,1)
end

local function analyticScaleQuantile(model,q,withDoubling)
    local cap=model.rules.scaleHardCap
    local left=0
    local right=cap
    for _=1,38 do
        local middle=(left+right)/2
        local above=analyticPAboveScale(model,middle,withDoubling)
        if above and 1-above>=q then right=middle else left=middle end
    end
    return right
end

local function analyticModelDrawAgreement(model,dist)
    if not dist or type(dist.values)~="table" or #dist.values<32 then return nil end
    local thresholdMap={.45,.85,1.05,1.45,1.55,1.9,2.1,3.15,4.2,6.2,10,17,35}
    local rows={}
    local sumRaw,sumHypo,maxRaw,maxHypo=0,0,0,0
    for _,t in ipairs(thresholdMap) do
        local n=0
        for _,v in ipairs(dist.values) do if tonumber(v) and v>t then n+=1 end end
        local empirical=n/#dist.values
        local bandOnly=analyticPAboveScale(model,t,false)
        local withDoubling=analyticPAboveScale(model,t,true)
        local rawErr=math.abs(empirical-bandOnly)
        local hypoErr=math.abs(empirical-withDoubling)
        sumRaw+=rawErr
        sumHypo+=hypoErr
        maxRaw=math.max(maxRaw,rawErr)
        maxHypo=math.max(maxHypo,hypoErr)
        rows[#rows+1]={
            thresholdScale=t,
            observedLocalDrawRate=empirical,
            undoubledBandProbability=bandOnly,
            hypotheticalDoubledProbability=withDoubling,
            undoubledAbsoluteError=rawErr,
            hypotheticalAbsoluteError=hypoErr,
        }
    end
    return {
        source="256 local DrawFusedScale calls, NOT real server fusion results",
        n=#dist.values,
        thresholds=rows,
        bandOnlyMeanAbsDifference=sumRaw/#rows,
        hypotheticalMeanAbsDifference=sumHypo/#rows,
        bandOnlyMaxAbsDifference=maxRaw,
        hypotheticalMaxAbsDifference=maxHypo,
        status="Sampling checks consistency only; rare outcomes and exact doubling control flow remain unverified.",
    }
end

local function scaleForIncomeThreshold(category,target,cap)
    target=tonumber(target)
    if not finite(target) or target<0 then return nil,"invalid income target" end
    local low=.00001
    local lowRate=baselineRateForScale(category,low)
    local highRate=baselineRateForScale(category,cap)
    if not (finite(lowRate) and finite(highRate)) then return nil,"client income helper unavailable" end
    if lowRate>highRate then return nil,"income function decreases" end
    if target<lowRate then return 0 end
    if target>=highRate then return cap end
    local left=low
    local right=cap
    for _=1,38 do
        local middle=(left+right)/2
        local rate=baselineRateForScale(category,middle)
        if not finite(rate) then return nil,"income helper failed during inverse" end
        if rate>target then right=middle else left=middle end
    end
    return right
end

local function inventoryIncomeBenchmark()
    local inventory=state.observedInventory
    if type(inventory)~="table" then return nil end
    local best=0
    for _,raw in pairs(inventory) do
        local item=decodeItem(raw)
        if type(item)=="table" then
            local rate=itemRate(item)
            if finite(rate) and rate>best then best=rate end
        end
    end
    return best>0 and best or nil
end

local function analyticIncomeProjection(model,inputs,inventoryBenchmark)
    if not model or type(inputs)~="table" or #inputs~=3 then return nil end
    local cat=inputs[1] and inputs[1].category
    if not cat then return nil end
    for _,x in ipairs(inputs) do
        if x.category~=cat then return {error="Fusion inputs belong to different categories"} end
    end
    local worst=math.huge
    local best=0
    local sum=0
    for _,x in ipairs(inputs) do
        local rate=tonumber(x.earningsPerSecond)
        if not finite(rate) then return {error="Missing observed input earnings"} end
        worst=math.min(worst,rate)
        best=math.max(best,rate)
        sum+=rate
    end

    local cap=model.rules.scaleHardCap
    local checkpoints={.1,.5,.85,1,1.5,2,4,6,12,20,35,cap}
    local prior=nil
    for _,sc in ipairs(checkpoints) do
        local rate=baselineRateForScale(cat,sc)
        if not finite(rate) then return {error="Income helper unavailable for "..tostring(cat)} end
        if prior and rate<prior-1e-7 then
            return {error="Income is not monotonic on validation grid; do not invert rates"}
        end
        prior=rate
    end

    local function pAboveIncome(target)
        local sc,err=scaleForIncomeThreshold(cat,target,cap)
        if sc==nil then return nil,err end
        return analyticPAboveScale(model,sc,true),nil
    end

    local aboveWorst=pAboveIncome(worst)
    local aboveBest=pAboveIncome(best)
    local aboveOneAndHalf=pAboveIncome(1.5*best)
    local aboveDouble=pAboveIncome(2*best)
    local aboveSum=pAboveIncome(sum)
    if not aboveBest then return {error="Could not compute income probabilities"} end

    local quantileScales={}
    local quantileRates={}
    for _,nameAndQ in ipairs({
        {"p10",.10},{"p50",.50},{"p90",.90},{"p95",.95},{"p99",.99},
    }) do
        local name,q=nameAndQ[1],nameAndQ[2]
        local sc=analyticScaleQuantile(model,q,true)
        quantileScales[name]=sc
        quantileRates[name]=baselineRateForScale(cat,sc)
    end

    -- Integrate earnings across the complete client band mixture.
    -- 28 deterministic midpoints per official band capture very small-probability
    -- bands that 256 random draws almost never encounter.
    local expected=0
    local integrationNodes=28
    for _,band in ipairs(model.bands) do
        local bandAverage=0
        for i=1,integrationNodes do
            local base=band.min+(i-.5)*(band.max-band.min)/integrationNodes
            for k=0,ANALYTIC_TAIL_STEPS do
                local odds=model.rules.doublingOdds
                local factor=(k==ANALYTIC_TAIL_STEPS)
                    and odds^k or ((1-odds)*(odds^k))
                if factor>0 then
                    local sc=math.min(base*(2^k),cap)
                    local rate=baselineRateForScale(cat,sc)
                    if not finite(rate) then return {error="Income helper failed while integrating"} end
                    bandAverage+=rate*factor
                end
            end
        end
        expected+=band.probability*bandAverage/integrationNodes
    end

    local absolute={}
    for _,target in ipairs({1e6,1e7,1e8,1e9,1e10,1e11,1e12}) do
        local prob=pAboveIncome(target)
        absolute[#absolute+1]={targetEarningsPerSecond=target,probabilityAbove=prob}
    end
    local benchmarkChance=finite(inventoryBenchmark) and pAboveIncome(inventoryBenchmark) or nil

    return {
        category=cat,
        modelStatus="EXPERIMENTAL: real band weights and bias; the doubling-loop shape and no-mutation earnings assumptions still need server validation.",
        objective="Maximize actual $/s (absolute or chance to exceed a target), NOT pet weight.",
        mutationModel="UNKNOWN; all projected output rates assume NO output mutation.",
        outputRateQuantiles=quantileRates,
        outputScaleQuantiles=quantileScales,
        expectedEarningsPerSecond=expected,
        inputWorstEarningsPerSecond=worst,
        inputBestEarningsPerSecond=best,
        inputSumEarningsPerSecond=sum,
        inventoryBestEarningsPerSecond=inventoryBenchmark,
        probabilityAboveInventoryBest=benchmarkChance,
        probabilityBelowWorstInput=aboveWorst and (1-aboveWorst) or nil,
        probabilityBelowBestInput=1-aboveBest,
        probabilityAboveBestInput=aboveBest,
        probabilityAbove1_5xBestInput=aboveOneAndHalf,
        probabilityAbove2xBestInput=aboveDouble,
        probabilityAboveInputSum=aboveSum,
        probabilityScaleBelowInputMin=1-analyticPAboveScale(model,math.min(
            tonumber(inputs[1].scale) or 1,tonumber(inputs[2].scale) or 1,tonumber(inputs[3].scale) or 1
        ),true),
        probabilityScaleAboveInputMax=analyticPAboveScale(model,math.max(
            tonumber(inputs[1].scale) or 1,tonumber(inputs[2].scale) or 1,tonumber(inputs[3].scale) or 1
        ),true),
        absoluteIncomeTargets=absolute,
        thresholds={
            worstInputRate=worst,
            bestInputRate=best,
            oneAndHalfBestRate=1.5*best,
            doubleBestRate=2*best,
            inputSumRate=sum,
            inventoryBestRate=inventoryBenchmark,
        },
        expectedIncomeIntegrationNodesPerBand=integrationNodes,
        includedWeight=false,
    }
end

local function economicProjectionFromDraw(dist,inputs)
    if not dist or type(dist.values)~="table" or #dist.values==0 or type(inputs)~="table" or #inputs~=3 then
        return nil
    end
    local category=inputs[1] and inputs[1].category
    if not category then return nil end

    local best=0
    local worst=math.huge
    local sum=0
    local rates={}
    local inputScaleMin,inputScaleMax=math.huge,0
    local inputScaleSum=0

    for _,x in ipairs(inputs) do
        local r=tonumber(x.earningsPerSecond) or 0
        best=math.max(best,r)
        if r>0 then worst=math.min(worst,r) end
        sum+=r

        local sc=tonumber(x.scale) or 0
        inputScaleMin=math.min(inputScaleMin,sc)
        inputScaleMax=math.max(inputScaleMax,sc)
        inputScaleSum+=sc
    end
    if worst==math.huge then worst=0 end

    local counts={
        belowWorst=0,
        belowBest=0,
        aboveBest=0,
        above1_5xBest=0,
        above2xBest=0,
        aboveInputSum=0,
        scaleBelowInputMin=0,
        scaleAboveInputMax=0,
    }

    for _,scale in ipairs(dist.values) do
        local rate=baselineRateForScale(category,scale)
        if rate then
            rates[#rates+1]=rate
            if worst>0 and rate<worst then counts.belowWorst+=1 end
            if best>0 and rate<best then counts.belowBest+=1 end
            if best>0 and rate>best then counts.aboveBest+=1 end
            if best>0 and rate>best*1.5 then counts.above1_5xBest+=1 end
            if best>0 and rate>best*2 then counts.above2xBest+=1 end
            if sum>0 and rate>sum then counts.aboveInputSum+=1 end
        end
        if inputScaleMin<math.huge and scale<inputScaleMin then counts.scaleBelowInputMin+=1 end
        if inputScaleMax>0 and scale>inputScaleMax then counts.scaleAboveInputMax+=1 end
    end
    if #rates==0 then return nil end

    local rateDist=distributionFromValues(rates,true)
    local n=#rates
    local meanScale=inputScaleSum/3
    local spread=inputScaleMin>0 and inputScaleMax/inputScaleMin or nil

    local function p(count)
        return n>0 and count/n or nil
    end

    local risk="INDETERMINADO"
    local pBelowBest=p(counts.belowBest)
    local pBelowHalfBest=0
    for _,rate in ipairs(rates) do
        if best>0 and rate<best*.5 then pBelowHalfBest+=1 end
    end
    pBelowHalfBest=p(pBelowHalfBest)

    if pBelowHalfBest and pBelowHalfBest>=.35 then
        risk="MUITO ALTO"
    elseif pBelowBest and pBelowBest>=.80 then
        risk="ALTO"
    elseif pBelowBest and pBelowBest>=.55 then
        risk="MODERADO"
    elseif pBelowBest then
        risk="MENOR"
    end

    return {
        note="Scale-only baseline: same category and NO output mutation. Probabilities come from local DrawFusedScale draws, not a guaranteed server result.",
        category=category,
        drawCount=n,
        inputWorstEarningsPerSecond=worst,
        inputBestEarningsPerSecond=best,
        inputSumEarningsPerSecond=sum,
        inputMeanScale=meanScale,
        inputScaleMin=inputScaleMin,
        inputScaleMax=inputScaleMax,
        inputScaleSpreadRatio=spread,
        baselineNoMutationRateDistribution=rateDist,

        -- Economic roulette probabilities.
        probabilityBelowWorstInput=p(counts.belowWorst),
        probabilityBelowBestInput=pBelowBest,
        probabilityBelowHalfBestInput=pBelowHalfBest,
        probabilityAboveBestInput=p(counts.aboveBest),
        probabilityAbove1_5xBestInput=p(counts.above1_5xBest),
        probabilityAbove2xBestInput=p(counts.above2xBest),
        probabilityAboveInputSum=p(counts.aboveInputSum),

        -- Pure Scale checks, useful for validating whether the worst input is a floor.
        probabilityScaleBelowInputMin=p(counts.scaleBelowInputMin),
        probabilityScaleAboveInputMax=p(counts.scaleAboveInputMax),

        thresholds={
            worstInputRate=worst,
            bestInputRate=best,
            oneAndHalfBestRate=best*1.5,
            doubleBestRate=best*2,
            inputSumRate=sum,
            inputScaleMin=inputScaleMin,
            inputScaleMax=inputScaleMax,
        },
        riskLabel=risk,
    }
end

local function probeBandWeightBias(snap)
    local fn=type(FuseKernel)=="table" and FuseKernel.BandWeightBias or nil
    local report={
        available=type(fn)=="function",
        arity=3,
        inferredSignature="BandWeightBias(scaleTable, bandStart, bandEnd)",
        signatureEvidence={
            "V2.4 showed argument 1 expects a table.",
            "Arguments 2 and 3 are tested as ordered positive band bounds.",
            "V2.5 uses the three pet Scales as the first argument.",
        },
        references={},
        validationCalls={},
    }
    if type(fn)~="function" or not snap or #snap.inputs~=3 then return report end

    local scales={}
    for i=1,3 do scales[i]=tonumber(snap.inputs[i] and snap.inputs[i].scale) or 1 end
    table.sort(scales)
    local minScale,maxScale=scales[1],scales[3]
    local mean=(scales[1]+scales[2]+scales[3])/3
    local median=scales[2]
    local geo=(math.max(scales[1]*scales[2]*scales[3],1e-12))^(1/3)

    local refs={
        {name="inputScales",value=scales},
    }

    local low=math.max(.05,math.min(minScale*.55,.55))
    local high=math.max(maxScale*1.8,2.5)
    local boundaries={low,.65,.80,.90,1.00,1.10,1.25,1.50,2.00,high}
    table.sort(boundaries)
    local clean={}
    for _,v in ipairs(boundaries) do
        if v>0 and (#clean==0 or math.abs(v-clean[#clean])>1e-6) then clean[#clean+1]=v end
    end

    -- Explicitly confirm the first two numeric arguments behave as band bounds.
    local validOk,validRes,validErr=directNumericCall(fn,{scales,.8,1.2})
    report.validationCalls.validBand={argsSummary={scaleTable=scales,bandStart=.8,bandEnd=1.2},ok=validOk,result=validRes,error=validErr}
    local reversedOk,reversedRes,reversedErr=directNumericCall(fn,{scales,1.2,.8})
    report.validationCalls.reversedBand={argsSummary={scaleTable=scales,bandStart=1.2,bandEnd=.8},ok=reversedOk,result=reversedRes,error=reversedErr}

    for _,ref in ipairs(refs) do
        local rows={}
        local total=0
        for b=1,#clean-1 do
            local a,z=clean[b],clean[b+1]
            if z>=a then
                local ok,value,err=directNumericCall(fn,{scales,a,z})
                rows[#rows+1]={
                    bandStart=a,
                    bandEnd=z,
                    ok=ok,
                    weight=ok and value or nil,
                    error=not ok and string.sub(tostring(err),1,240) or nil,
                }
                if ok and value and value>0 then total+=value end
            end
        end
        if total>0 then
            for _,row in ipairs(rows) do
                if row.weight and row.weight>0 then row.normalizedWeight=row.weight/total end
            end
        end
        report.references[#report.references+1]={
            referenceName=ref.name,
            scaleTable=ref.value,
            bands=rows,
            totalPositiveWeight=total,
        }
    end
    return report
end

local function percentileOf(sortedValues,value)
    if type(sortedValues)~="table" or #sortedValues==0 or not finite(tonumber(value)) then return nil end
    local n=0
    for _,v in ipairs(sortedValues) do
        if tonumber(v)<=tonumber(value) then n+=1 else break end
    end
    return n/#sortedValues
end

local function runKernelResearch(snap)
    inspectFuseKernel()
    snap=snap or state.lastThree or state.lastSlotSnapshot
    local run={
        unix=os.time(),
        serverTime=Workspace:GetServerTimeNow(),
        hasThree=snap and #snap.inputs==3 or false,
        slotSignature=snap and table.concat(snap.slots or {},"|") or "",
        inputSummary=snap and jsonSafe(snap.inputs) or nil,
        note="Local-only probes on copied/local numeric data; no remotes are invoked and no pets are consumed.",
    }
    if not snap or #snap.inputs~=3 then
        run.error="É necessário ter 3 pets carregados para analisar o Kernel."
        state.kernelResearch.lastRun=run
        state.kernelResearch.probes[#state.kernelResearch.probes+1]=run
        return run
    end

    local scales={}
    for i=1,3 do scales[i]=tonumber(snap.inputs[i] and snap.inputs[i].scale) or 1 end

    -- V2.3 established that DrawFusedScale accepts one list containing exactly 3 Scales.
    run.DrawFusedScale={
        available=type(FuseKernel)=="table" and type(FuseKernel.DrawFusedScale)=="function",
        confirmedShape="scale-list",
        distribution=nil,
    }
    local dist,drawErr=drawScaleDistribution(scales,256)
    run.DrawFusedScale.distribution=dist
    run.DrawFusedScale.error=drawErr
    run.DrawFusedScale.economicProjection=economicProjectionFromDraw(dist,snap.inputs)

    -- Preserve the old exploratory bands for regression comparisons.
    run.BandWeightBias=probeBandWeightBias(snap)

    -- New: recover the eleven ACTUAL client bands. The pet's category and the
    -- client's income helper determine output $/s; weight is never used here.
    local weightedBands,bandErr=buildWeightedClientBands(scales)
    run.AnalyticClientBands={
        available=weightedBands~=nil,
        error=bandErr,
        clientScaleRules=weightedBands and weightedBands.rules or nil,
        bands=weightedBands and weightedBands.bands or nil,
        effectiveWeightTotal=weightedBands and weightedBands.effectiveWeightTotal or nil,
        modelStatus=weightedBands and weightedBands.modelStatus or nil,
    }
    if weightedBands then
        -- Fix this benchmark for the session so comparisons across trios use
        -- the SAME absolute $/s target even if inventory changes after fusion.
        if not state.sessionInventoryIncomeTarget then
            state.sessionInventoryIncomeTarget=inventoryIncomeBenchmark()
        end
        local invBest=state.sessionInventoryIncomeTarget
        run.AnalyticClientBands.inventoryBenchmark=invBest
        run.AnalyticClientBands.localDrawAgreement=analyticModelDrawAgreement(weightedBands,dist)
        run.AnalyticClientBands.economicProjection=analyticIncomeProjection(
            weightedBands,snap.inputs,invBest
        )
    end

    if type(FuseKernel)=="table" and type(FuseKernel.PriceFor)=="function" then
        local ok,cost=directNumericCall(FuseKernel.PriceFor,{snap.decodedInputs})
        if ok then run.inputFusionPrice=cost end
    end

    state.kernelResearch.lastRun=run
    state.kernelResearch.probes[#state.kernelResearch.probes+1]=run
    return run
end

local function pollSlots()
    local snap=captureSlots()
    if not snap then
        state.status="Save indisponível • aguardando FieldSignal/WatchFields"
        return
    end
    state.lastSlotCount=#snap.inputs
    state.lastSlotSnapshot=snap
    if #snap.inputs==3 then
        state.lastThree=snap
        state.status="3/3 capturados • pronto para fundir"

        -- Run the local FuseKernel study once for each distinct trio. This is
        -- automatic so it can also catch the short 3/3 window created by the
        -- direct-fusion menu before BeginFuse. No remote is called here.
        local sig=table.concat(snap.slots or {},"|")
        if sig~="" and sig~=state.lastKernelSlotSignature then
            state.lastKernelSlotSignature=sig
            task.defer(function()
                local run=runKernelResearch(snap)
                if run and not run.error then
                    local d=run.DrawFusedScale or {}
                    local p=d.economicProjection or {}
                    state.status=string.format(
                        "3/3 • Kernel %s • risco %s",
                        tostring(d.confirmedShape or "não identificado"),
                        tostring(p.riskLabel or "indeterminado")
                    )
                end
            end)
        end
    elseif #snap.inputs>0 then
        state.status=string.format("%d/3 pets carregados",#snap.inputs)
    elseif os.clock()-state.lastFusionAt>1.5 then
        state.status="Aguardando pets na máquina"
    end
end

local function predictionOutcomeForSample(prediction,rewardSummary,metrics)
    if type(prediction)~="table" or type(rewardSummary)~="table" or type(metrics)~="table" then return nil end

    local actualRate=tonumber(rewardSummary.earningsPerSecond)
    local actualScale=tonumber(rewardSummary.scale)
    local baselineRate=baselineRateForScale(rewardSummary.category,actualScale)
    local worst=tonumber(prediction.inputWorstEarningsPerSecond or metrics.minEarningsPerSecond)
    local best=tonumber(prediction.inputBestEarningsPerSecond or metrics.maxEarningsPerSecond)
    local sum=tonumber(prediction.inputSumEarningsPerSecond or metrics.sumEarningsPerSecond)
    local inventoryBest=tonumber(prediction.inventoryBestEarningsPerSecond)

    local function flags(rate)
        if not rate then return nil end
        return {
            belowWorstInput=worst and worst>0 and rate<worst or false,
            belowBestInput=best and best>0 and rate<best or false,
            aboveBestInput=best and best>0 and rate>best or false,
            above1_5xBestInput=best and best>0 and rate>best*1.5 or false,
            above2xBestInput=best and best>0 and rate>best*2 or false,
            aboveInputSum=sum and sum>0 and rate>sum or false,
            aboveInventoryBest=inventoryBest and inventoryBest>0 and rate>inventoryBest or false,
        }
    end

    return {
        prediction={
            belowWorstInput=prediction.probabilityBelowWorstInput,
            belowBestInput=prediction.probabilityBelowBestInput,
            aboveBestInput=prediction.probabilityAboveBestInput,
            above1_5xBestInput=prediction.probabilityAbove1_5xBestInput,
            above2xBestInput=prediction.probabilityAbove2xBestInput,
            aboveInputSum=prediction.probabilityAboveInputSum,
            aboveInventoryBest=prediction.probabilityAboveInventoryBest,
            scaleBelowInputMin=prediction.probabilityScaleBelowInputMin,
            scaleAboveInputMax=prediction.probabilityScaleAboveInputMax,
        },
        thresholds=prediction.thresholds,
        observed={
            actualRate=actualRate,
            baselineNoMutationRate=baselineRate,
            actualScale=actualScale,
            actualEconomic=flags(actualRate),
            scaleOnlyBaseline=flags(baselineRate),
            scaleBelowInputMin=actualScale and metrics.minScale and actualScale<metrics.minScale or false,
            scaleAboveInputMax=actualScale and metrics.maxScale and actualScale>metrics.maxScale or false,
            outputHasMutation=#mutationNames(rewardSummary)>0,
        },
        calibrationBasis="scaleOnlyBaseline compares the observed Scale converted to a no-mutation rate against the pre-fusion scale-only probabilities. actualEconomic is stored separately because output mutation can change $/s.",
    }
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

    local kernelValidation
    local snapSignature=snap and table.concat(snap.slots or {},"|") or ""
    if snapSignature~="" then
        for idx=#state.kernelResearch.probes,1,-1 do
            local run=state.kernelResearch.probes[idx]
            if run and run.slotSignature==snapSignature then
                local dist=run.DrawFusedScale and run.DrawFusedScale.distribution
                local observedScale=tonumber(rewardSummary.scale)
                kernelValidation={
                    matchedKernelProbeIndex=idx,
                    observedOutputScale=observedScale,
                }
                if dist and type(dist.values)=="table" and observedScale then
                    kernelValidation.drawSampleCount=#dist.values
                    kernelValidation.observedScalePercentile=percentileOf(dist.values,observedScale)
                    kernelValidation.insideP10P90=observedScale>=tonumber(dist.p10 or -math.huge)
                        and observedScale<=tonumber(dist.p90 or math.huge)
                    kernelValidation.localP10=dist.p10
                    kernelValidation.localP50=dist.p50
                    kernelValidation.localP90=dist.p90
                    kernelValidation.scaleOnlyEconomicProjection=run.DrawFusedScale.economicProjection
                    kernelValidation.predictionOutcome=predictionOutcomeForSample(
                        run.DrawFusedScale.economicProjection,
                        rewardSummary,
                        metrics
                    )
                end
                local analytic=run.AnalyticClientBands
                local econ=analytic and analytic.economicProjection
                if econ and not econ.error then
                    kernelValidation.analyticBandCount=analytic.clientScaleRules and analytic.clientScaleRules.bandCount
                    kernelValidation.analyticDrawAgreement=analytic.localDrawAgreement and {
                        bandOnlyMeanAbsDifference=analytic.localDrawAgreement.bandOnlyMeanAbsDifference,
                        hypotheticalMeanAbsDifference=analytic.localDrawAgreement.hypotheticalMeanAbsDifference,
                        hypotheticalMaxAbsDifference=analytic.localDrawAgreement.hypotheticalMaxAbsDifference,
                    } or nil
                    kernelValidation.analyticPredictionOutcome=predictionOutcomeForSample(
                        econ,rewardSummary,metrics
                    )
                end
                break
            end
        end
    end

    local sample={
        index=#state.samples+1,
        unix=os.time(),
        serverTime=Workspace:GetServerTimeNow(),
        source="Client.FuseMachineSignals.FuseStarted",
        inputCaptureMethod=method,
        kernelValidation=kernelValidation,
        preFusionProbabilityModel=kernelValidation and kernelValidation.scaleOnlyEconomicProjection or nil,
        predictionOutcome=kernelValidation and kernelValidation.predictionOutcome or nil,
        analyticPredictionOutcome=kernelValidation and kernelValidation.analyticPredictionOutcome or nil,
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
            outputEarningsPerSecond=rewardSummary.earningsPerSecond,
            outputSalePrice=rewardSummary.salePrice,
            inputMeanScale=metrics.meanScale,
            inputSumEarningsPerSecond=metrics.sumEarningsPerSecond,
            inputBestEarningsPerSecond=metrics.maxEarningsPerSecond,
            inputSumSalePrice=metrics.salePriceCount>0 and metrics.sumSalePrice or nil,
            inputSumWeight=metrics.weightCount>0 and metrics.sumWeight or nil,
            fusionPrice=metrics.fusionPrice,
            outputScaleVsMeanInputScale=metrics.outputScaleVsMeanInputScale,
            outputEarningsVsInputSum=metrics.outputEarningsVsInputSum,
            outputEarningsVsBestInput=metrics.outputEarningsVsBestInput,
            retainedEarningsPercent=metrics.retainedEarningsPercent,
            retainedBestInputPercent=metrics.retainedBestInputPercent,
            earningsLostVsInputSum=metrics.earningsLostVsInputSum,
            mutation=metrics.mutation,
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

-- Listen to Save fields as a fallback for executors/builds where Save.Get returns nil.
-- Unlike V2, callbacks retain their payload instead of throwing it away.
local function connectFieldSignal(field)
    if type(Save)~="table" or type(Save.FieldSignal)~="function" then return false end

    local ok,sig=pcall(Save.FieldSignal,field)
    if not (ok and sig and type(sig.Connect)=="function") then
        ok,sig=pcall(Save.FieldSignal,Save,field)
    end
    if not (ok and sig and type(sig.Connect)=="function") then return false end

    local ok2,c=pcall(function()
        return sig:Connect(function(...)
            state.fieldSignalEvents+=1
            local args=table.pack(...)
            if field=="FusionSlots" then
                for i=1,args.n do
                    if type(args[i])=="table" then
                        if type(args[i].FusionSlots)=="table" then
                            state.observedFusionSlots=args[i].FusionSlots
                            absorbObservedTable(args[i],"FieldSignal:"..field)
                        elseif looksLikeFusionSlots(args[i]) then
                            state.observedFusionSlots=args[i]
                        end
                    end
                end
            elseif field=="Inventory" then
                for i=1,args.n do
                    if type(args[i])=="table" then
                        if type(args[i].Inventory)=="table" then
                            state.observedInventory=args[i].Inventory
                            absorbObservedTable(args[i],"FieldSignal:"..field)
                        elseif not looksLikeFusionSlots(args[i]) then
                            state.observedInventory=args[i]
                        end
                    end
                end
            end
            absorbSignalArgs("FieldSignal:"..field,...)
            task.defer(pollSlots)
        end)
    end)
    if ok2 and c then conns[#conns+1]=c return true end
    return false
end

connectFieldSignal("FusionSlots")
connectFieldSignal("Inventory")

local function scheduleCommittedRefresh()
    -- WatchFields in the current build fires before the local snapshot is fully
    -- committed. Refresh immediately and again shortly after to avoid 0/1,1/2,2/3.
    task.defer(function()
        refreshObservedFromPeek()
        pollSlots()
        task.wait(.04)
        refreshObservedFromPeek()
        pollSlots()
        task.wait(.10)
        refreshObservedFromPeek()
        pollSlots()
    end)
end

local function extractFieldPayload(field,...)
    local args=table.pack(...)
    for i=1,args.n do
        local v=args[i]
        if type(v)=="table" then
            if type(v[field])=="table" then return v[field] end
            if field=="FusionSlots" and looksLikeFusionSlots(v) then return v end
            if field=="Inventory" and not looksLikeFusionSlots(v) then
                -- Because this callback watches Inventory only, an arbitrary UID map
                -- is the inventory payload even when it is not wrapped as {Inventory=...}.
                return v
            end
        end
    end
    return nil
end

local function watchOneField(field)
    if type(Save)~="table" then return false end

    local callback=function(...)
        state.watchFieldEvents+=1
        local payload=extractFieldPayload(field,...)
        if field=="FusionSlots" and type(payload)=="table" then
            -- Keep the callback payload as fallback, but Peek after commit is authoritative.
            state.observedFusionSlots=payload
        elseif field=="Inventory" and type(payload)=="table" then
            state.observedInventory=payload
        end
        absorbSignalArgs("Watch:"..field,...)
        scheduleCommittedRefresh()
    end

    if type(Save.WatchFields)=="function" then
        local ok,res=pcall(Save.WatchFields,{field},callback)
        if not ok then ok,res=pcall(Save.WatchFields,Save,{field},callback) end
        if ok then
            keepCleanupHandle(res)
            return true
        end
    end

    if type(Save.Watch)=="function" then
        local ok,res=pcall(Save.Watch,field,callback)
        if not ok then ok,res=pcall(Save.Watch,Save,field,callback) end
        if ok then
            keepCleanupHandle(res)
            return true
        end
    end
    return false
end

watchOneField("FusionSlots")
watchOneField("Inventory")

-- Seed the caches immediately instead of waiting for the first mutation event.
refreshObservedFromPeek()

-- Await is only used once as an asynchronous bootstrap fallback. It never blocks
-- the scanner UI or polling loop.
if type(Save)=="table" and type(Save.Await)=="function" then
    task.spawn(function()
        local value,ok,mode=callSaveFunction("Await")
        saveDiagnostics.awaitType=typeof(value)
        if ok and type(value)=="table" then
            saveDiagnostics.source="Await/"..tostring(mode)
            absorbObservedTable(value,"Await")
            if type(value.FusionSlots)=="table" then state.observedFusionSlots=value.FusionSlots end
            if type(value.Inventory)=="table" then state.observedInventory=value.Inventory end
            scheduleCommittedRefresh()
        end
    end)
end

local CALIBRATION_TARGETS={
    {key="belowWorstInput",label="Resultado < pior input"},
    {key="belowBestInput",label="Resultado < melhor input"},
    {key="aboveBestInput",label="Resultado > melhor input"},
    {key="above1_5xBestInput",label="Resultado > 1.5x melhor input"},
    {key="above2xBestInput",label="Resultado > 2x melhor input"},
    {key="aboveInputSum",label="Resultado > soma dos inputs"},
    {key="aboveInventoryBest",label="Resultado > melhor pet do inventário (alvo fixado antes)"},
    {key="scaleBelowInputMin",label="Scale < menor Scale de entrada"},
    {key="scaleAboveInputMax",label="Scale > maior Scale de entrada"},
}

local function newCalibrationTarget(label)
    local bins={}
    for idx=1,5 do
        bins[idx]={
            minProbability=(idx-1)*.2,
            maxProbability=idx*.2,
            n=0,
            predictedSum=0,
            observedCount=0,
        }
    end
    return {label=label,n=0,predictedSum=0,observedCount=0,bins=bins}
end

local function addCalibrationObservation(target,predicted,observed)
    predicted=tonumber(predicted)
    if not predicted or type(observed)~="boolean" then return end
    predicted=math.clamp(predicted,0,1)
    target.n+=1
    target.predictedSum+=predicted
    if observed then target.observedCount+=1 end
    local idx=math.clamp(math.floor(predicted*5)+1,1,5)
    local bin=target.bins[idx]
    bin.n+=1
    bin.predictedSum+=predicted
    if observed then bin.observedCount+=1 end
end

local function finalizeCalibrationTarget(target)
    if target.n>0 then
        target.averagePredicted=target.predictedSum/target.n
        target.observedRate=target.observedCount/target.n
        target.calibrationGap=target.observedRate-target.averagePredicted
    end
    for _,bin in ipairs(target.bins) do
        if bin.n>0 then
            bin.averagePredicted=bin.predictedSum/bin.n
            bin.observedRate=bin.observedCount/bin.n
            bin.calibrationGap=bin.observedRate-bin.averagePredicted
        end
    end
end

local function buildSessionStatistics()
    local stats={
        sampleCount=#state.samples,
        economics={
            valid=0,
            averageOutputVsInputSum=nil,
            averageOutputVsBestInput=nil,
            averageScaleVsMean=nil,
            averageRetainedEarningsPercent=nil,
            totalInputEarnings=0,
            totalOutputEarnings=0,
            totalFusionPrice=0,
        },
        mutationBuckets={},
        mutationTypes={},
        calibration={
            basis="V2.7 256-draw scale-only prediction vs observed Scale converted to no-mutation $/s",
            targets={},
            samplesWithPrediction=0,
        },
        analyticCalibration={
            basis="V2.8 original client bands × exact BandWeightBias; hypothesized doubling; observed Scale converted to no-mutation $/s",
            status="EXPERIMENTAL: compare multiple fusions before treating percentages as calibrated.",
            targets={},
            samplesWithPrediction=0,
        },
        observedOutcomeCounts={
            actualEconomic={belowWorstInput=0,belowBestInput=0,aboveBestInput=0,above1_5xBestInput=0,above2xBestInput=0,aboveInputSum=0},
            scaleOnlyBaseline={belowWorstInput=0,belowBestInput=0,aboveBestInput=0,above1_5xBestInput=0,above2xBestInput=0,aboveInputSum=0},
            scale={belowInputMin=0,aboveInputMax=0},
        },
    }
    for _,def in ipairs(CALIBRATION_TARGETS) do
        stats.calibration.targets[def.key]=newCalibrationTarget(def.label)
        stats.analyticCalibration.targets[def.key]=newCalibrationTarget(def.label)
    end

    local sumVsInput,sumVsBest,sumScaleRatio=0,0,0
    local nVsInput,nVsBest,nScale=0,0,0

    for _,sample in ipairs(state.samples) do
        local m=sample.inputMetrics or {}
        local mp=m.mutation or mutationProfile(sample.inputs or {},sample.rewardSummary)
        local bucket=mp.inputMutationBucket or "?"
        local b=stats.mutationBuckets[bucket]
        if not b then
            b={samples=0,outputMutated=0,outputUnmutated=0,retainedAnyInputMutation=0}
            stats.mutationBuckets[bucket]=b
        end
        b.samples+=1
        if mp.outputHasMutation then b.outputMutated+=1 else b.outputUnmutated+=1 end
        if mp.anyInputMutationRetained then b.retainedAnyInputMutation+=1 end

        for name,count in pairs(mp.inputMutationCounts or {}) do
            local rec=stats.mutationTypes[name]
            if not rec then
                rec={samplesWithInput=0,totalInputPets=0,outputSameMutation=0}
                stats.mutationTypes[name]=rec
            end
            rec.samplesWithInput+=1
            rec.totalInputPets+=tonumber(count) or 0
            local found=false
            for _,outName in ipairs(mp.outputMutations or {}) do
                if outName==name then found=true break end
            end
            if found then rec.outputSameMutation+=1 end
        end

        local po=sample.predictionOutcome
        if type(po)=="table" and type(po.prediction)=="table" and type(po.observed)=="table" then
            stats.calibration.samplesWithPrediction+=1
            local observedBasis=po.observed.scaleOnlyBaseline or {}
            for _,def in ipairs(CALIBRATION_TARGETS) do
                local observedValue
                if def.key=="scaleBelowInputMin" then
                    observedValue=po.observed.scaleBelowInputMin
                elseif def.key=="scaleAboveInputMax" then
                    observedValue=po.observed.scaleAboveInputMax
                else
                    observedValue=observedBasis[def.key]
                end
                addCalibrationObservation(
                    stats.calibration.targets[def.key],
                    po.prediction[def.key],
                    observedValue
                )
            end

            local ae=po.observed.actualEconomic or {}
            local sb=po.observed.scaleOnlyBaseline or {}
            for _,key in ipairs({"belowWorstInput","belowBestInput","aboveBestInput","above1_5xBestInput","above2xBestInput","aboveInputSum"}) do
                if ae[key]==true then stats.observedOutcomeCounts.actualEconomic[key]+=1 end
                if sb[key]==true then stats.observedOutcomeCounts.scaleOnlyBaseline[key]+=1 end
            end
            if po.observed.scaleBelowInputMin==true then stats.observedOutcomeCounts.scale.belowInputMin+=1 end
            if po.observed.scaleAboveInputMax==true then stats.observedOutcomeCounts.scale.aboveInputMax+=1 end
        end

        local analytic=sample.analyticPredictionOutcome
        if type(analytic)=="table" and type(analytic.prediction)=="table" and type(analytic.observed)=="table" then
            stats.analyticCalibration.samplesWithPrediction+=1
            local actualBaseline=analytic.observed.scaleOnlyBaseline or {}
            for _,def in ipairs(CALIBRATION_TARGETS) do
                local observedValue
                if def.key=="scaleBelowInputMin" then
                    observedValue=analytic.observed.scaleBelowInputMin
                elseif def.key=="scaleAboveInputMax" then
                    observedValue=analytic.observed.scaleAboveInputMax
                else
                    observedValue=actualBaseline[def.key]
                end
                addCalibrationObservation(
                    stats.analyticCalibration.targets[def.key],
                    analytic.prediction[def.key],
                    observedValue
                )
            end
        end

        local inputSum=tonumber(m.sumEarningsPerSecond)
        local output=tonumber(sample.rewardSummary and sample.rewardSummary.earningsPerSecond)
        if inputSum and output then
            stats.economics.valid+=1
            stats.economics.totalInputEarnings+=inputSum
            stats.economics.totalOutputEarnings+=output
        end
        if tonumber(m.fusionPrice) then stats.economics.totalFusionPrice+=tonumber(m.fusionPrice) end
        if tonumber(m.outputEarningsVsInputSum) then
            sumVsInput+=m.outputEarningsVsInputSum
            nVsInput+=1
        end
        if tonumber(m.outputEarningsVsBestInput) then
            sumVsBest+=m.outputEarningsVsBestInput
            nVsBest+=1
        end
        if tonumber(m.outputScaleVsMeanInputScale) then
            sumScaleRatio+=m.outputScaleVsMeanInputScale
            nScale+=1
        end
    end

    if nVsInput>0 then
        stats.economics.averageOutputVsInputSum=sumVsInput/nVsInput
        stats.economics.averageRetainedEarningsPercent=stats.economics.averageOutputVsInputSum*100
    end
    if nVsBest>0 then stats.economics.averageOutputVsBestInput=sumVsBest/nVsBest end
    if nScale>0 then stats.economics.averageScaleVsMean=sumScaleRatio/nScale end

    for _,b in pairs(stats.mutationBuckets) do
        if b.samples>0 then
            b.outputMutationRate=b.outputMutated/b.samples
            b.outputMutationPercent=b.outputMutationRate*100
            b.retainedAnyInputMutationRate=b.retainedAnyInputMutation/b.samples
        end
    end
    for _,rec in pairs(stats.mutationTypes) do
        if rec.samplesWithInput>0 then
            rec.sameMutationOutputRate=rec.outputSameMutation/rec.samplesWithInput
        end
    end
    for _,target in pairs(stats.calibration.targets) do
        finalizeCalibrationTarget(target)
    end
    for _,target in pairs(stats.analyticCalibration.targets) do
        finalizeCalibrationTarget(target)
    end
    return stats
end

local function flatBandWeightExport()
    local out={}
    local function addRun(run,runIndex,kind)
        local bias=run and run.BandWeightBias
        local refs=bias and bias.references
        if type(refs)~="table" then return end
        for _,ref in ipairs(refs) do
            for _,row in ipairs(ref.bands or {}) do
                out[#out+1]={
                    runIndex=runIndex,
                    runKind=kind,
                    slotSignature=run.slotSignature,
                    scale1=run.inputSummary and run.inputSummary[1] and run.inputSummary[1].scale or nil,
                    scale2=run.inputSummary and run.inputSummary[2] and run.inputSummary[2].scale or nil,
                    scale3=run.inputSummary and run.inputSummary[3] and run.inputSummary[3].scale or nil,
                    bandStart=tonumber(row.bandStart),
                    bandEnd=tonumber(row.bandEnd),
                    weight=tonumber(row.weight),
                    normalizedWeight=tonumber(row.normalizedWeight),
                    ok=row.ok==true,
                    error=row.error and tostring(row.error) or nil,
                }
            end
        end
    end
    for idx,run in ipairs(state.kernelResearch.probes or {}) do
        addRun(run,idx,"probe")
    end
    if state.kernelResearch.lastRun then
        addRun(state.kernelResearch.lastRun,#(state.kernelResearch.probes or {}),"lastRun")
    end
    return out
end

local function flatAnalyticBandExport()
    local rows={}
    for runIndex,run in ipairs(state.kernelResearch.probes or {}) do
        local analytic=run.AnalyticClientBands
        if analytic and type(analytic.bands)=="table" then
            local inputs=run.inputSummary or {}
            for _,band in ipairs(analytic.bands) do
                rows[#rows+1]={
                    runIndex=runIndex,
                    slotSignature=run.slotSignature,
                    category=inputs[1] and inputs[1].category,
                    scale1=inputs[1] and inputs[1].scale,
                    scale2=inputs[2] and inputs[2].scale,
                    scale3=inputs[3] and inputs[3].scale,
                    originalBandIndex=band.index,
                    min=band.min,
                    max=band.max,
                    originalWeight=band.rawWeight,
                    trioBandBias=band.bias,
                    effectiveWeight=band.effectiveWeight,
                    effectiveProbability=band.probability,
                    hardCap=analytic.clientScaleRules and analytic.clientScaleRules.scaleHardCap,
                    configuredDoublingOdds=analytic.clientScaleRules and analytic.clientScaleRules.doublingOdds,
                }
            end
        end
    end
    return rows
end

local function flatAnalyticAgreementExport()
    local out={}
    for runIndex,run in ipairs(state.kernelResearch.probes or {}) do
        local an=run.AnalyticClientBands
        local g=an and an.localDrawAgreement
        if g then
            out[#out+1]={
                runIndex=runIndex,
                slotSignature=run.slotSignature,
                localDrawCount=g.n,
                baseBandsMeanAbsDifference=g.bandOnlyMeanAbsDifference,
                hypothesizedDoublingMeanAbsDifference=g.hypotheticalMeanAbsDifference,
                baseBandsMaxAbsDifference=g.bandOnlyMaxAbsDifference,
                hypothesizedDoublingMaxAbsDifference=g.hypotheticalMaxAbsDifference,
            }
        end
    end
    return out
end

local function flatAnalyticTrioComparisons()
    local bySignature={}
    for idx,run in ipairs(state.kernelResearch.probes or {}) do
        local a=run.AnalyticClientBands
        local e=a and a.economicProjection
        if e and not e.error and type(run.slotSignature)=="string" and run.slotSignature~="" then
            local ins=run.inputSummary or {}
            bySignature[run.slotSignature]={
                probeIndex=idx,
                slotSignature=run.slotSignature,
                category=e.category,
                scale1=ins[1] and ins[1].scale,
                scale2=ins[2] and ins[2].scale,
                scale3=ins[3] and ins[3].scale,
                expectedOutputRate=e.expectedEarningsPerSecond,
                p10OutputRate=e.outputRateQuantiles and e.outputRateQuantiles.p10,
                medianOutputRate=e.outputRateQuantiles and e.outputRateQuantiles.p50,
                p90OutputRate=e.outputRateQuantiles and e.outputRateQuantiles.p90,
                p99OutputRate=e.outputRateQuantiles and e.outputRateQuantiles.p99,
                inputBestRate=e.inputBestEarningsPerSecond,
                inputSumRate=e.inputSumEarningsPerSecond,
                referenceIncomeTarget=e.inventoryBestEarningsPerSecond,
                probabilityAboveReferenceTarget=e.probabilityAboveInventoryBest,
                probabilityAboveInputBest=e.probabilityAboveBestInput,
                probabilityAbove2xInputBest=e.probabilityAbove2xBestInput,
                fusionPrice=run.inputFusionPrice,
                localDrawDifference=a.localDrawAgreement
                    and a.localDrawAgreement.hypotheticalMeanAbsDifference or nil,
                analysisStatus="Experimental no-mutation rate projection, using exact client bands plus hypothetical doubling.",
                usesWeight=false,
            }
        end
    end
    local options={}
    for _,v in pairs(bySignature) do options[#options+1]=v end
    local byExpected={}
    local byChance={}
    for _,v in ipairs(options) do
        byExpected[#byExpected+1]=v
        if v.probabilityAboveReferenceTarget~=nil then
            byChance[#byChance+1]=v
        end
    end
    table.sort(byExpected,function(a,b)
        if a.expectedOutputRate~=b.expectedOutputRate then
            return a.expectedOutputRate>b.expectedOutputRate
        end
        return a.slotSignature<b.slotSignature
    end)
    table.sort(byChance,function(a,b)
        if a.probabilityAboveReferenceTarget~=b.probabilityAboveReferenceTarget then
            return a.probabilityAboveReferenceTarget>b.probabilityAboveReferenceTarget
        end
        return (a.medianOutputRate or 0)>(b.medianOutputRate or 0)
    end)
    local function firstN(sorted)
        local out={}
        for i=1,math.min(10,#sorted) do out[#out+1]=sorted[i] end
        return out
    end
    return {
        note="Only trios OBSERVED in scanner slots, not all combinations in the inventory. Exploratory math requires validation. No fusion is triggered.",
        target="Absolute $/s, without using weight. Compare the SAME session benchmark across species.",
        fixedSessionTarget=state.sessionInventoryIncomeTarget,
        distinctTrioCount=#options,
        highestExpectedRate=firstN(byExpected),
        highestProbabilityAboveFixedInventoryTarget=firstN(byChance),
    }
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
            Save=moduleKeys(Save),
            AssetItems=moduleKeys(AssetItems),
            AssetEarnings=moduleKeys(AssetEarnings),
            FuseKernel=moduleKeys(FuseKernel),
            FuseMachineSignals=moduleKeys(FuseSignals),
        },
        kernelResearch=jsonSafe(state.kernelResearch),
        bandWeightFlat=flatBandWeightExport(),
        clientBandFlat=flatAnalyticBandExport(),
        analyticDrawAgreementFlat=flatAnalyticAgreementExport(),
        experimentalTrioComparisons=flatAnalyticTrioComparisons(),
        v26ResearchTargets={
            externalClientFormulaHypotheses={
                sizeBandCount=11,
                extraDoublingChance=0.01,
                scaleHardCap=150,
                sourceStatus="third-party client-derived wiki; scanner must verify against local client code",
            },
            goals={
                "Recover exact DrawAssetScale bands/weights from the loaded client.",
                "Compare BandWeightBias weights with those exact bands.",
                "Replace Monte Carlo-only tail estimates with full-distribution math when verified.",
                "Keep mutation inheritance separate until its server rule is evidenced.",
                "Calibrate predicted roulette probabilities against real FuseStarted outcomes in 20% probability bins.",
                "Test directly whether output can fall below the worst input or rise above the best/1.5x/2x thresholds.",
            },
        },
        predictorDataSources={
            petDirect={"Category","Scale","Mutations","BaseMutation","Personality"},
            petDerived={
                earningsPerSecond="AssetEarnings.CatalogRatePerSecond(decodedPet)",
                weightKg="AssetItems.WeightKg(decodedPet)",
                salePrice="AssetItems.SalePrice(decodedPet)",
                rarity="Data.Assets[Category].Rarity",
            },
            fusionLocal={
                drawScale="FuseKernel.DrawFusedScale({scale1,scale2,scale3})",
                bandBias="FuseKernel.BandWeightBias(scaleTable,bandStart,bandEnd)",
                price="FuseKernel.PriceFor({pet1,pet2,pet3})",
            },
            stillUnknown={
                "Exact RNG result before fusion",
                "Server rule/probability for output mutation",
            },
        },
        sessionStatistics=buildSessionStatistics(),
        diagnostics={
            save=jsonSafe(saveDiagnostics),
            fieldSignalEvents=state.fieldSignalEvents,
            watchFieldEvents=state.watchFieldEvents,
            observedFusionSlots=jsonSafe(state.observedFusionSlots),
            observedInventoryType=typeof(state.observedInventory),
            observedInventoryCount=(function()
                local n=0
                if type(state.observedInventory)=="table" then for _ in pairs(state.observedInventory) do n+=1 end end
                return n
            end)(),
            currentSlotCount=state.lastSlotCount,
        },
        samples=state.samples,
        events=state.events,
        notes={
            "Current Save build exposes Peek/Await/Watch/WatchFields and no Get; V2.7 reads committed FusionSlots through Peek.",
            "Input $/s prefers AssetEarnings.CatalogRatePerSecond(decodedItem).",
            "Weight prefers the game's AssetItems.WeightKg helper; raw fields are fallback.",
            "V2.7 keeps economic retention versus input sum/best input and mutation 0/3..3/3 session buckets.",
            "V2.3 established DrawFusedScale accepts a single list of exactly 3 input Scales; V2.4 records 256 full local draws per trio.",
            "V2.4 proved BandWeightBias argument 1 expects a table; V2.5 tests (scaleTable, bandStart, bandEnd).",
            "V2.6 exports BandWeightBias rows again in bandWeightFlat so individual weights never disappear behind jsonSafe max-depth.",
            "V2.6 also locates DrawAssetScale through DrawFusedScale upvalues and exports its constants/upvalues to recover the exact client size bands.",
            "V2.7 records pre-fusion roulette probabilities for below-worst/below-best/above-best/1.5x/2x/input-sum outcomes and calibrates them against real results.",
            "V2.8 uses 11 client SCALE_BANDS and their exact per-trio BandWeightBias, and compares a hypothetical doubling model with the game's DrawFusedScale samples.",
            "V2.8 projects no-mutation $/s directly using the game's category-aware CatalogRatePerSecond; kg/weight has ZERO role in optimizing trios.",
            "V2.8 stores a constant session-wide inventory $/s benchmark so different tested species can be compared using the same absolute income target.",
            "clientBandFlat and experimentalTrioComparisons are exported directly to avoid jsonSafe depth truncation.",
            "Analytic percentages are EXPERIMENTAL until double behavior and prediction calibration are validated against server results.",

            "V2.7 calibration uses the observed output Scale converted to a no-mutation rate, isolating the Scale model from unknown output-mutation effects; actual economic outcome is also stored separately.",
            "Scale-only economic projection assumes the same category and no output mutation; it is a risk baseline, not a mutation predictor.",
            "FuseKernel research runs automatically once per distinct 3-pet slot set and can also be retried with ANALISAR KERNEL.",
            "FuseKernel research uses local-only pcall probes on copied data; it never invokes Fusery remotes or consumes pets.",
            "DrawFusedScale/BandWeightBias probe results are exploratory until their successful argument shape is identified and compared with real server fusion samples.",
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
title.Size=UDim2.new(1,-150,0,42)
title.Font=Enum.Font.GothamBold
title.Text="FUSION RESEARCH SCANNER • V2.8"
title.TextSize=26
title.TextColor3=Color3.fromRGB(245,248,255)
title.TextXAlignment=Enum.TextXAlignment.Left
title.Parent=main

local sub=Instance.new("TextLabel")
sub.BackgroundTransparency=1
sub.Position=UDim2.new(0,24,0,54)
sub.Size=UDim2.new(1,-48,0,28)
sub.Font=Enum.Font.Gotham
sub.Text="DrawFusedScale • BandWeightBias • risco econômico"
sub.TextSize=16
sub.TextColor3=Color3.fromRGB(139,164,207)
sub.TextXAlignment=Enum.TextXAlignment.Left
sub.Parent=main

local minimize=makeButton(main,"—",UDim2.new(1,-116,0,16),UDim2.fromOffset(44,44))
minimize.TextSize=23
minimize.BackgroundColor3=Color3.fromRGB(35,44,61)

local close=makeButton(main,"×",UDim2.new(1,-64,0,16),UDim2.fromOffset(44,44))
close.TextSize=25
close.BackgroundColor3=Color3.fromRGB(35,44,61)

local mini=makeButton(gui,"SCAN",UDim2.new(1,-76,.5,-28),UDim2.fromOffset(56,56))
mini.Name="MinimizedButton"
mini.AnchorPoint=Vector2.new(0,0)
mini.TextSize=11
mini.BackgroundColor3=Color3.fromRGB(18,42,72)
mini.Visible=false
round(mini,28)

local body=Instance.new("Frame")
body.BackgroundColor3=Color3.fromRGB(16,34,58)
body.BorderSizePixel=0
body.Position=UDim2.new(0,24,0,92)
body.Size=UDim2.new(1,-48,1,-174)
body.Parent=main
round(body,16)

local statusScroll=Instance.new("ScrollingFrame")
statusScroll.BackgroundTransparency=1
statusScroll.BorderSizePixel=0
statusScroll.Size=UDim2.fromScale(1,1)
statusScroll.CanvasSize=UDim2.fromOffset(0,0)
statusScroll.AutomaticCanvasSize=Enum.AutomaticSize.Y
statusScroll.ScrollBarThickness=5
statusScroll.ScrollBarImageColor3=Color3.fromRGB(93,152,209)
statusScroll.ScrollingDirection=Enum.ScrollingDirection.Y
statusScroll.Parent=body

local statusLabel=Instance.new("TextLabel")
statusLabel.BackgroundTransparency=1
statusLabel.Position=UDim2.new(0,14,0,12)
statusLabel.Size=UDim2.new(1,-40,0,0)
statusLabel.AutomaticSize=Enum.AutomaticSize.Y
statusLabel.Font=Enum.Font.Code
statusLabel.TextSize=16
statusLabel.TextColor3=Color3.fromRGB(230,237,248)
statusLabel.TextXAlignment=Enum.TextXAlignment.Left
statusLabel.TextYAlignment=Enum.TextYAlignment.Top
statusLabel.TextWrapped=true
statusLabel.Parent=statusScroll

local capture=makeButton(main,"LER SLOTS",UDim2.new(0,24,1,-66),UDim2.new(.23,-8,0,44))
local kernel=makeButton(main,"ANALISAR KERNEL",UDim2.new(.25,4,1,-66),UDim2.new(.23,-8,0,44))
local export=makeButton(main,"EXPORTAR JSON",UDim2.new(.50,4,1,-66),UDim2.new(.23,-8,0,44))
local clear=makeButton(main,"LIMPAR",UDim2.new(.75,4,1,-66),UDim2.new(.23,-28,0,44))
clear.BackgroundColor3=Color3.fromRGB(35,44,61)

local dragging=false
local dragStart,startPos
main.InputBegan:Connect(function(input)
    if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
        -- Only drag by the header so touch-scrolling the data does not move the panel.
        if input.Position.Y-main.AbsolutePosition.Y>82 then return end
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

local miniDragging=false
local miniMoved=false
local miniDragStart,miniStartPos

mini.InputBegan:Connect(function(input)
    if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
        miniDragging=true
        miniMoved=false
        miniDragStart=input.Position
        miniStartPos=mini.Position
    end
end)

mini.InputEnded:Connect(function(input)
    if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
        miniDragging=false
    end
end)

conns[#conns+1]=UIS.InputChanged:Connect(function(input)
    if miniDragging and (input.UserInputType==Enum.UserInputType.MouseMovement or input.UserInputType==Enum.UserInputType.Touch) then
        local d=input.Position-miniDragStart
        if d.Magnitude>6 then miniMoved=true end
        mini.Position=UDim2.new(
            miniStartPos.X.Scale,
            miniStartPos.X.Offset+d.X,
            miniStartPos.Y.Scale,
            miniStartPos.Y.Offset+d.Y
        )
    end
end)

minimize.Activated:Connect(function()
    main.Visible=false
    mini.Visible=true
end)

mini.Activated:Connect(function()
    if miniMoved then
        miniMoved=false
        return
    end
    mini.Visible=false
    main.Visible=true
end)

capture.Activated:Connect(function()
    pollSlots()
    local snap=state.lastSlotSnapshot
    if snap then
        state.status=string.format("Leitura manual: %d/3 slots • %s",#snap.inputs,#snap.inputs==3 and "snapshot salvo" or "aguardando 3")
        if #snap.inputs==3 then state.lastThree=snap end
    end
end)

kernel.Activated:Connect(function()
    pollSlots()
    local run=runKernelResearch(state.lastThree or state.lastSlotSnapshot)
    if run.error then
        state.status="Kernel: "..tostring(run.error)
    else
        local d=run.DrawFusedScale or {}
        local p=d.economicProjection or {}
        state.status=string.format(
            "Kernel V2.8 • Draw:%s • risco:%s",
            tostring(d.confirmedShape or "não identificado"),
            tostring(p.riskLabel or "indeterminado")
        )
    end
end)

export.Activated:Connect(function()
    local ok,msg=exportData()
    state.status=ok and ("Exportado: "..tostring(msg)) or ("Falha ao exportar: "..tostring(msg))
end)

clear.Activated:Connect(function()
    table.clear(state.samples)
    table.clear(state.events)
    table.clear(state.kernelResearch.probes)
    state.kernelResearch.lastRun=nil
    state.lastKernelSlotSignature=""
    state.sessionInventoryIncomeTarget=nil
    state.status="Amostras/probes limpos • aguardando nova fusão"
end)

local function cleanup()
    state.alive=false
    mini.Visible=false
    for _,c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    for _,fn in ipairs(cleanupFns) do pcall(fn) end
    pcall(function() gui:Destroy() end)
    if _G.PSICO_FUSION_SCAN_CLEANUP==cleanup then _G.PSICO_FUSION_SCAN_CLEANUP=nil end
end
_G.PSICO_FUSION_SCAN_CLEANUP=cleanup
close.Activated:Connect(cleanup)

local function incomeLabel(n)
    n=tonumber(n)
    if not finite(n) then return "?" end
    local a=math.abs(n)
    if a>=1e12 then return string.format("%.2fT",n/1e12) end
    if a>=1e9 then return string.format("%.2fB",n/1e9) end
    if a>=1e6 then return string.format("%.2fM",n/1e6) end
    if a>=1e3 then return string.format("%.2fK",n/1e3) end
    return string.format("%.0f",n)
end

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
                    "[%d] %s | Scale %.4f | $/s %s",
                    x.slot or 0,
                    tostring(x.displayName or x.category or "?"),
                    tonumber(x.scale) or 0,
                    x.earningsPerSecond and string.format("%.0f",x.earningsPerSecond) or "?"
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
            local lm=last.inputMetrics or {}
            local mp=lm.mutation or {}
            if tonumber(lm.retainedEarningsPercent) then
                lines[#lines+1]=string.format(
                    "Retenção: %.1f%% da soma | %.1f%% do melhor input",
                    tonumber(lm.retainedEarningsPercent) or 0,
                    tonumber(lm.retainedBestInputPercent) or 0
                )
            end
            lines[#lines+1]=string.format(
                "Mutação: %s inputs -> %s",
                tostring(mp.inputMutationBucket or "?"),
                mp.outputHasMutation and table.concat(mp.outputMutations or {}, "+") or "sem mutação"
            )
            local po=last.predictionOutcome
            if po and po.observed then
                local o=po.observed.actualEconomic or {}
                lines[#lines+1]=string.format(
                    "Real: <pior %s | >melhor %s | >2x %s",
                    o.belowWorstInput and "SIM" or "não",
                    o.aboveBestInput and "SIM" or "não",
                    o.above2xBestInput and "SIM" or "não"
                )
            end
            local analyticOutcome=last.analyticPredictionOutcome
            if analyticOutcome and analyticOutcome.prediction then
                lines[#lines+1]=string.format(
                    "V2.8 previsto: >melhor %.1f%% | >2x %.1f%% • resultado real guardado",
                    100*(analyticOutcome.prediction.aboveBestInput or 0),
                    100*(analyticOutcome.prediction.above2xBestInput or 0)
                )
            end
        end
        local kr=state.kernelResearch.lastRun
        if kr then
            lines[#lines+1]=""
            if kr.error then
                lines[#lines+1]="Kernel: "..tostring(kr.error)
            else
                local d=kr.DrawFusedScale or {}
                local b=kr.BandWeightBias or {}
                local p=d.economicProjection or {}
                lines[#lines+1]="Kernel Draw: "..tostring(d.confirmedShape or "não identificado")
                lines[#lines+1]="Band Bias: "..tostring(b.inferredSignature or "não identificado")
                if d.distribution then
                    lines[#lines+1]=string.format(
                        "Draw n=%d | p10 %.4f | p50 %.4f | p90 %.4f",
                        d.distribution.n or 0,
                        d.distribution.p10 or 0,
                        d.distribution.p50 or 0,
                        d.distribution.p90 or 0
                    )
                end
                if p.riskLabel then
                    lines[#lines+1]=string.format(
                        "Risco $/s(scale): %s | spread %.2fx",
                        tostring(p.riskLabel),
                        tonumber(p.inputScaleSpreadRatio) or 0
                    )
                    lines[#lines+1]=string.format(
                        "Roleta: <pior %.0f%% | <melhor %.0f%% | >melhor %.0f%%",
                        100*(tonumber(p.probabilityBelowWorstInput) or 0),
                        100*(tonumber(p.probabilityBelowBestInput) or 0),
                        100*(tonumber(p.probabilityAboveBestInput) or 0)
                    )
                    lines[#lines+1]=string.format(
                        "Cauda boa: >1.5x %.0f%% | >2x %.0f%% | >soma %.0f%%",
                        100*(tonumber(p.probabilityAbove1_5xBestInput) or 0),
                        100*(tonumber(p.probabilityAbove2xBestInput) or 0),
                        100*(tonumber(p.probabilityAboveInputSum) or 0)
                    )
                    lines[#lines+1]=string.format(
                        "Scale: <mínimo %.0f%% | >máximo %.0f%%",
                        100*(tonumber(p.probabilityScaleBelowInputMin) or 0),
                        100*(tonumber(p.probabilityScaleAboveInputMax) or 0)
                    )
                end

                local an=kr.AnalyticClientBands
                local ae=an and an.economicProjection
                if an and an.available and ae and not ae.error then
                    lines[#lines+1]=""
                    lines[#lines+1]=string.format(
                        "V2.8 • %d faixas REAIS • $/s SEM mutação (EXPERIMENTAL)",
                        an.clientScaleRules and an.clientScaleRules.bandCount or 0
                    )
                    lines[#lines+1]=string.format(
                        "Analítico: >melhor %.1f%% | >2x %.1f%% | >soma %.1f%%",
                        100*(ae.probabilityAboveBestInput or 0),
                        100*(ae.probabilityAbove2xBestInput or 0),
                        100*(ae.probabilityAboveInputSum or 0)
                    )
                    lines[#lines+1]=string.format(
                        "$/s: p10 %s | mediana %s | p90 %s",
                        incomeLabel(ae.outputRateQuantiles and ae.outputRateQuantiles.p10),
                        incomeLabel(ae.outputRateQuantiles and ae.outputRateQuantiles.p50),
                        incomeLabel(ae.outputRateQuantiles and ae.outputRateQuantiles.p90)
                    )
                    lines[#lines+1]=string.format(
                        "$/s médio estimado: %s (cauda rara incluída)",
                        incomeLabel(ae.expectedEarningsPerSecond)
                    )
                    if ae.inventoryBestEarningsPerSecond and ae.probabilityAboveInventoryBest then
                        lines[#lines+1]=string.format(
                            "Alvo fixo %s/s: chance %.2f%%",
                            incomeLabel(ae.inventoryBestEarningsPerSecond),
                            100*ae.probabilityAboveInventoryBest
                        )
                    end
                    local agreement=an.localDrawAgreement
                    if agreement then
                        lines[#lines+1]=string.format(
                            "Diferença modelo vs 256 draws: %.1f pontos percentuais",
                            100*(agreement.hypotheticalMeanAbsDifference or 0)
                        )
                    end
                    lines[#lines+1]="Faixas/bias do cliente verificados; duplicação ainda é hipótese."
                elseif an then
                    lines[#lines+1]="Modelo analítico: "..tostring(
                        an.error or (ae and ae.error) or "indisponível"
                    )
                end
            end
        end
        statusLabel.Text=table.concat(lines,"\n")
        task.wait(.15)
    end
end)

pollSlots()

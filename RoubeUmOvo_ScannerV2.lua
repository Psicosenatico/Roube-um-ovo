--[[
PSICOSENATICO | Roube um Ovo - Egg Prediction Scanner V14
Foco: descobrir se os raros do proximo ciclo podem ser previstos antes do spawn visual.

O scanner observa:
- RE/EggWorld/FieldEggCycleCountdown
- RF/EggWorld/AskFieldEggRarityShows (consulta somente leitura)
- RE/EggWorld/FieldEggRaritiesShown
- FieldEggShifted / FieldEggBatchShifted apos o reset
- AreaEggCycle / AreaEggResetCycle / AssetLottery / EggState
- handlers ResetCountdown / RarityRevealed / RarityPresented
- decompile/getgc quando o executor disponibiliza

NAO altera ovos, sorte, ciclo, velocidade, guardioes, dinheiro ou combate.
NAO chama resetEggCycle/spawnRareEgg/globalSpawnRareEgg/globalEggLuckBoost.
]]

if _G.PSICO_ROUBE_SCANNER_CLEANUP then pcall(_G.PSICO_ROUBE_SCANNER_CLEANUP) end

local Players=game:GetService("Players")
local Workspace=game:GetService("Workspace")
local RS=game:GetService("ReplicatedStorage")
local CoreGui=game:GetService("CoreGui")
local Http=game:GetService("HttpService")
local UIS=game:GetService("UserInputService")
local LP=Players.LocalPlayer

local START_CLOCK=os.clock()
local START_UNIX=os.time()

local S={
    Alive=true,
    C={},RC={},
    Records={},
    Events={},
    CountdownEvents={},
    RevealQueries={},
    RevealEvents={},
    SpawnEvents={},
    CycleWindows={},
    CatalogRare={},
    CatalogIndex={},
    StaticModules={},
    Signals={},
    Decompile=nil,
    GC=nil,
    LastCountdownAt=nil,
    LastCycleAt=nil,
    LastRevealPayload=nil,
    LastRevealQueryClock=-1e9,
    CycleIndex=0,
    Gui=nil,
}

local AssetsData=nil
local EggState=nil
local AreaEggCycle=nil
local AreaEggResetCycle=nil
local AssetLottery=nil

local RARITY_RANK={Common=1,Uncommon=2,Rare=3,Epic=4,Legendary=5,Mythic=6,Cosmic=7,Secret=8,Eternal=9,Divine=10}
local RARE_MIN=7

local TOKENS={
    "fieldeggcyclecountdown","resetcountdown","areaeggcycle","areaeggresetcycle",
    "fieldeggraritiesshown","rarityrevealed","raritypresented","askfieldeggrarityshows",
    "rarespawn","spawnrare","globalspawnrare","global schedule","override",
    "nightlength","finalblink","cycleindex","sequence","countdown","reveal",
    "random.new","random","seed","rng","next","schedule","servertime",
    "drawcategory","drawcategoryforrarity","drawcategoryfromraritytable",
    "drawcategoryfromtable","drawmutations","drawscale","droPweight","visualodds",
    "tokenchances","pickweightedwith","luck","globaleggluckboost",
}

local function finite(v)
    return type(v)=="number" and v==v and v~=math.huge and v~=-math.huge
end

local function safeString(v)
    local ok,x=pcall(tostring,v)
    return ok and x or "?"
end

local function lower(v)
    return string.lower(safeString(v or ""))
end

local function normalize(v)
    return lower(v):gsub("[%s_%-%.:/%[%]%(%)']","")
end

local function containsToken(v)
    local q=lower(v)
    for _,token in ipairs(TOKENS) do
        if string.find(q,string.lower(token),1,true) then return true,token end
    end
    return false,nil
end

local function serverNow()
    local ok,v=pcall(function() return Workspace:GetServerTimeNow() end)
    return ok and v or nil
end

local function elapsed()
    return os.clock()-START_CLOCK
end

local function connect(sig,fn,bucket)
    local c=sig:Connect(fn)
    table.insert(bucket or S.C,c)
    return c
end

local function disconnect(c)
    pcall(function() c:Disconnect() end)
end

local function uiParent()
    local ok,h=pcall(function() if gethui then return gethui() end end)
    return (ok and h) or CoreGui
end

local function childPath(root,pathText)
    local cur=root
    for token in string.gmatch(pathText,"[^%.]+") do
        if not cur then return nil end
        cur=cur:FindFirstChild(token)
    end
    return cur
end

local function requireOptional(pathText)
    local m=childPath(RS,pathText)
    if not (m and m:IsA("ModuleScript")) then return nil,m end
    local ok,v=pcall(require,m)
    return ok and v or nil,m
end

local function findExact(className,name)
    for _,d in ipairs(RS:GetDescendants()) do
        if d.ClassName==className and d.Name==name then return d end
    end
    return nil
end

local function serialize(v,depth,seen)
    depth=depth or 0
    seen=seen or {}
    if depth>7 then return "<depth>" end
    local t=typeof(v)
    if t=="nil" or t=="boolean" or t=="string" then return v end
    if t=="number" then return finite(v) and v or safeString(v) end
    if t=="Vector3" then return {x=v.X,y=v.Y,z=v.Z,magnitude=v.Magnitude} end
    if t=="Vector2" then return {x=v.X,y=v.Y} end
    if t=="CFrame" then return {position=serialize(v.Position,depth+1,seen)} end
    if t=="Color3" then return {r=v.R,g=v.G,b=v.B} end
    if t=="Instance" then return {class=v.ClassName,name=v.Name,path=v:GetFullName()} end
    if t=="function" then return "<function> "..safeString(v) end
    if t~="table" then return safeString(v) end
    if seen[v] then return "<cycle>" end
    seen[v]=true
    local out,n={},0
    for k,x in pairs(v) do
        n=n+1
        if n>700 then out.__truncated=true break end
        local key=(type(k)=="string" or type(k)=="number") and k or safeString(k)
        out[key]=serialize(x,depth+1,seen)
    end
    seen[v]=nil
    return out
end

local function recordEvent(kind,data)
    local e={
        index=#S.Events+1,
        kind=kind,
        t=elapsed(),
        unix=os.time(),
        serverTime=serverNow(),
        data=serialize(data),
    }
    S.Events[#S.Events+1]=e
    if #S.Events>2400 then table.remove(S.Events,1) end
    return e
end

local function rarityRankFromValue(v)
    if type(v)=="number" then return v end
    if type(v)=="string" then return RARITY_RANK[v] end
    if typeof(v)=="table" then
        return tonumber(v.RarityNumber) or RARITY_RANK[v.DisplayName or v._id]
    end
    return nil
end

local function indexCatalogEntry(key,cfg)
    if typeof(cfg)~="table" then return end
    local rarity=cfg.Rarity
    local rank=rarityRankFromValue(rarity)
    if not rank then return end
    local rarityName=typeof(rarity)=="table" and (rarity.DisplayName or rarity._id) or safeString(rarity)
    local entry={
        Key=safeString(key),
        DisplayName=cfg.DisplayName or safeString(key),
        Rarity=rarityName,
        RarityNumber=rank,
        DropWeight=tonumber(cfg.DropWeight),
        VisualOdds=tonumber(cfg.VisualOdds),
        EggDisplayName=typeof(cfg.Egg)=="table" and cfg.Egg.DisplayName or nil,
    }
    S.CatalogIndex[normalize(entry.Key)]=entry
    S.CatalogIndex[normalize(entry.DisplayName)]=entry
    if entry.EggDisplayName then S.CatalogIndex[normalize(entry.EggDisplayName)]=entry end
    if rank>=RARE_MIN then S.CatalogRare[#S.CatalogRare+1]=entry end
end

local function buildCatalog()
    S.CatalogRare={}
    S.CatalogIndex={}
    AssetsData=select(1,requireOptional("Data.Assets"))
    if typeof(AssetsData)~="table" then return false end
    local seen={}
    if typeof(AssetsData.Configs)=="table" then
        for key,cfg in pairs(AssetsData.Configs) do
            if typeof(cfg)=="table" and not seen[cfg] then
                seen[cfg]=true
                indexCatalogEntry(key,cfg)
            end
        end
    end
    if #S.CatalogRare==0 and typeof(AssetsData.ByRarity)=="table" then
        for _,group in pairs(AssetsData.ByRarity) do
            if typeof(group)=="table" then
                for key,cfg in pairs(group) do
                    if typeof(cfg)=="table" and not seen[cfg] then
                        seen[cfg]=true
                        indexCatalogEntry(key,cfg)
                    end
                end
            end
        end
    end
    table.sort(S.CatalogRare,function(a,b)
        if a.RarityNumber==b.RarityNumber then return a.DisplayName<b.DisplayName end
        return a.RarityNumber>b.RarityNumber
    end)
    return true
end

local function catalogFor(category)
    if type(category)~="string" then return nil end
    return S.CatalogIndex[normalize(category)]
end

local function recordSummary(r)
    if typeof(r)~="table" then return nil end
    local cfg=catalogFor(r.AssetCategory)
    local rarity=r.Rarity
    local rank=rarityRankFromValue(rarity)
    if cfg then
        rarity=cfg.Rarity
        rank=cfg.RarityNumber
    end
    return {
        Uid=r.Uid,
        State=r.State,
        AreaId=r.AreaId,
        NestId=r.NestId,
        AssetCategory=r.AssetCategory,
        DisplayName=cfg and cfg.DisplayName or nil,
        Rarity=rarity,
        RarityNumber=rank,
        AssetScale=r.AssetScale,
        NestScale=r.NestScale,
        Mutations=serialize(r.Mutations),
        BaseMutation=r.BaseMutation,
        HasParasite=r.HasParasite,
        BoundsSize=serialize(r.BoundsSize),
    }
end

local function isRareRecord(r)
    local s=recordSummary(r)
    return s and tonumber(s.RarityNumber) and s.RarityNumber>=RARE_MIN,s
end

local function ingestRecord(r,source)
    if typeof(r)~="table" or type(r.Uid)~="string" then return false end
    if r.State=="Slot" or r.State=="Dropped" or r.State=="Carried" then
        S.Records[r.Uid]=r
        local rare,sum=isRareRecord(r)
        S.SpawnEvents[#S.SpawnEvents+1]={
            t=elapsed(),unix=os.time(),serverTime=serverNow(),
            source=source,rare=rare,record=sum,
            cycleIndex=S.CycleIndex,
        }
        if #S.SpawnEvents>1800 then table.remove(S.SpawnEvents,1) end
    else
        S.Records[r.Uid]=nil
    end
    return true
end

local function ingestTree(v,source,seen,depth)
    if typeof(v)~="table" then return 0 end
    seen=seen or {}
    depth=depth or 0
    if depth>8 or seen[v] then return 0 end
    seen[v]=true
    local count=0
    if type(v.Uid)=="string" and v.State~=nil then
        if ingestRecord(v,source) then count=1 end
    else
        local n=0
        for _,x in pairs(v) do
            n=n+1
            if n>4000 then break end
            if typeof(x)=="table" then count=count+ingestTree(x,source,seen,depth+1) end
        end
    end
    seen[v]=nil
    return count
end

local function currentRareEggs()
    local out={}
    for _,r in pairs(S.Records) do
        local rare,sum=isRareRecord(r)
        if rare and (r.State=="Slot" or r.State=="Dropped") then out[#out+1]=sum end
    end
    table.sort(out,function(a,b)
        if (a.RarityNumber or 0)==(b.RarityNumber or 0) then return safeString(a.DisplayName or a.AssetCategory)<safeString(b.DisplayName or b.AssetCategory) end
        return (a.RarityNumber or 0)>(b.RarityNumber or 0)
    end)
    return out
end

local function requestSnapshots()
    local total=0
    for _,name in ipairs({"RF/EggWorld/AskFieldEggSnapshot","RF/EggWorld/AskLiveSnapshot"}) do
        local rf=findExact("RemoteFunction",name)
        if rf then
            local ok,a,b=pcall(function() return rf:InvokeServer() end)
            if ok then
                total=total+ingestTree(a,"snapshot:"..name)
                total=total+ingestTree(b,"snapshot:"..name)
            end
        end
    end
    recordEvent("snapshot",{records=total})
    return total
end

local function collectRevealHints(v)
    local out,seen={},{}
    local interesting={
        rarity=true,raritynumber=true,assetcategory=true,displayname=true,areaid=true,
        nestid=true,uid=true,cycle=true,cycleindex=true,index=true,next=true,
        startsat=true,endsat=true,servertime=true,timestamp=true,time=true,
    }
    local function walk(x,path,depth)
        if typeof(x)~="table" or depth>6 or seen[x] then return end
        seen[x]=true
        local row={}
        local hits=0
        for k,val in pairs(x) do
            if type(k)=="string" and interesting[normalize(k)] then
                row[k]=serialize(val,1,{})
                hits=hits+1
            end
        end
        if hits>0 then
            row.__path=path
            out[#out+1]=row
        end
        if #out<220 then
            local n=0
            for k,val in pairs(x) do
                n=n+1
                if n>500 then break end
                if typeof(val)=="table" then walk(val,path.."."..safeString(k),depth+1) end
            end
        end
        seen[x]=nil
    end
    walk(v,"$",0)
    return out
end

local function queryRarityShows(reason,force)
    if not force and elapsed()-S.LastRevealQueryClock<4 then return nil end
    S.LastRevealQueryClock=elapsed()
    local rf=findExact("RemoteFunction","RF/EggWorld/AskFieldEggRarityShows")
    if not rf then
        local row={t=elapsed(),unix=os.time(),serverTime=serverNow(),reason=reason,ok=false,error="remote ausente"}
        S.RevealQueries[#S.RevealQueries+1]=row
        return row
    end
    local ok,a,b,c=pcall(function() return rf:InvokeServer() end)
    local payload=nil
    if typeof(a)=="table" then payload=a elseif typeof(b)=="table" then payload=b elseif typeof(c)=="table" then payload=c end
    local row={
        t=elapsed(),unix=os.time(),serverTime=serverNow(),reason=reason,ok=ok,
        returns={serialize(a),serialize(b),serialize(c)},
        payload=serialize(payload),
        hints=payload and collectRevealHints(payload) or {},
    }
    if not ok then row.error=safeString(a) end
    S.RevealQueries[#S.RevealQueries+1]=row
    if payload then S.LastRevealPayload=row end
    recordEvent("rarity_query",{reason=reason,ok=ok,hints=#row.hints})
    return row
end

local function extractCountdownNumber(v)
    if type(v)=="number" then return v,"$" end
    if typeof(v)~="table" then return nil,nil end
    local names={"Seconds","SecondsRemaining","Remaining","RemainingSeconds","Countdown","Duration","TimeLeft","EndsIn"}
    for _,name in ipairs(names) do
        local n=tonumber(v[name])
        if finite(n) then return n,name end
    end
    local best,bestPath=nil,nil
    local function walk(x,path,depth,seen)
        if best or typeof(x)~="table" or depth>4 or seen[x] then return end
        seen[x]=true
        for k,val in pairs(x) do
            local key=lower(k)
            if type(val)=="number" and (string.find(key,"remain",1,true) or string.find(key,"count",1,true) or string.find(key,"second",1,true) or string.find(key,"duration",1,true)) then
                best=val;bestPath=path.."."..safeString(k);break
            end
        end
        if not best then
            for k,val in pairs(x) do if typeof(val)=="table" then walk(val,path.."."..safeString(k),depth+1,seen) end end
        end
        seen[x]=nil
    end
    walk(v,"$",0,{})
    return best,bestPath
end

local function markCycle(reason,details)
    local now=serverNow()
    if S.LastCycleAt and now and now-S.LastCycleAt<45 then return false end
    S.CycleIndex=S.CycleIndex+1
    S.LastCycleAt=now or (S.LastCycleAt or 0)
    local rare=currentRareEggs()
    local row={
        index=S.CycleIndex,
        t=elapsed(),unix=os.time(),serverTime=now,
        reason=reason,
        details=serialize(details),
        rareAtBoundary=rare,
        lastRevealQuery=S.LastRevealPayload,
    }
    S.CycleWindows[#S.CycleWindows+1]=row
    recordEvent("cycle_boundary",{index=S.CycleIndex,reason=reason,rare=#rare})
    return true
end

local function maybeCycleFromBatch(payload)
    if typeof(payload)~="table" then return end
    local up=typeof(payload.UpdatedRecords)=="table" and #payload.UpdatedRecords or 0
    local rem=typeof(payload.RemovedUids)=="table" and #payload.RemovedUids or 0
    local changed=up+rem
    local now=serverNow()
    local nearCountdown=S.LastCountdownAt and now and math.abs(now-S.LastCountdownAt)<=25
    if changed>=10 and nearCountdown then
        markCycle("FieldEggBatchShifted",{updated=up,removed=rem})
    end
end

local function hookEggRemotes()
    local names={
        "RE/EggWorld/FieldEggCycleCountdown",
        "RE/EggWorld/FieldEggRaritiesShown",
        "RE/EggWorld/FieldEggShifted",
        "RE/EggWorld/FieldEggBatchShifted",
        "RE/EggWorld/FieldEggGone",
    }
    local map={}
    for _,d in ipairs(RS:GetDescendants()) do
        if d:IsA("RemoteEvent") then map[d.Name]=d end
    end

    local countdown=map[names[1]]
    if countdown then
        connect(countdown.OnClientEvent,function(payload)
            local num,path=extractCountdownNumber(payload)
            local row={t=elapsed(),unix=os.time(),serverTime=serverNow(),remaining=num,remainingPath=path,payload=serialize(payload)}
            S.CountdownEvents[#S.CountdownEvents+1]=row
            S.LastCountdownAt=row.serverTime
            recordEvent("countdown",{remaining=num,path=path,payload=payload})
            if num==nil or num<=15 then task.defer(function() if S.Alive then queryRarityShows("countdown",false) end end) end
        end,S.RC)
    end

    local revealed=map[names[2]]
    if revealed then
        connect(revealed.OnClientEvent,function(payload)
            local row={
                t=elapsed(),unix=os.time(),serverTime=serverNow(),
                payload=serialize(payload),hints=collectRevealHints(payload),
            }
            S.RevealEvents[#S.RevealEvents+1]=row
            S.LastRevealPayload=row
            recordEvent("rarities_shown",{hints=#row.hints,payload=payload})
        end,S.RC)
    end

    local shifted=map[names[3]]
    if shifted then
        connect(shifted.OnClientEvent,function(r)
            if typeof(r)=="table" then ingestRecord(r,"FieldEggShifted") end
        end,S.RC)
    end

    local batch=map[names[4]]
    if batch then
        connect(batch.OnClientEvent,function(payload)
            if typeof(payload)=="table" then
                if typeof(payload.UpdatedRecords)=="table" then
                    for _,r in ipairs(payload.UpdatedRecords) do ingestRecord(r,"FieldEggBatchShifted") end
                end
                if typeof(payload.RemovedUids)=="table" then
                    for _,uid in ipairs(payload.RemovedUids) do S.Records[uid]=nil end
                end
                recordEvent("batch_shift",{updated=typeof(payload.UpdatedRecords)=="table" and #payload.UpdatedRecords or 0,removed=typeof(payload.RemovedUids)=="table" and #payload.RemovedUids or 0})
                maybeCycleFromBatch(payload)
            end
        end,S.RC)
    end

    local gone=map[names[5]]
    if gone then
        connect(gone.OnClientEvent,function(payload)
            local uid=type(payload)=="string" and payload or (typeof(payload)=="table" and payload.Uid or nil)
            if type(uid)=="string" then S.Records[uid]=nil end
            recordEvent("egg_gone",{uid=uid,payload=payload})
        end,S.RC)
    end
end

local function fnMeta(fn,deep)
    if type(fn)~="function" then return nil end
    local out={repr=safeString(fn)}
    pcall(function()
        if debug and debug.info then
            out.name=debug.info(fn,"n")
            out.source=debug.info(fn,"s")
            local a,var=debug.info(fn,"a")
            out.arity=a;out.variadic=var
        elseif debug and debug.getinfo then
            local i=debug.getinfo(fn)
            if i then out.name=i.name;out.source=i.source;out.arity=i.nparams;out.variadic=i.isvararg end
        end
    end)
    pcall(function()
        if type(getconstants)=="function" then
            local all=getconstants(fn)
            local rel={}
            for i,v in pairs(all) do
                if type(v)=="string" then
                    if containsToken(v) then rel[i]=v end
                elseif type(v)=="number" then
                    if math.abs(v)<=1e12 then rel[i]=v end
                end
            end
            if next(rel) then out.constants=rel end
        end
    end)
    if deep then
        pcall(function()
            if type(getupvalues)=="function" then
                local ups=getupvalues(fn)
                local rel={}
                for k,v in pairs(ups) do
                    if type(v)=="string" and containsToken(v) then rel[k]=v
                    elseif type(v)=="number" and math.abs(v)<=1e15 then rel[k]=v
                    elseif typeof(v)=="table" then
                        local t,n={},0
                        for kk,vv in pairs(v) do
                            local keep=containsToken(kk)
                            if not keep and type(vv)=="string" then keep=containsToken(vv) end
                            if keep then t[safeString(kk)]=serialize(vv,2,{}) n=n+1 end
                            if n>=50 then break end
                        end
                        if next(t) then rel[k]=t end
                    elseif typeof(v)=="Instance" then
                        if containsToken(v:GetFullName()) then rel[k]=serialize(v) end
                    else
                        local tv=typeof(v)
                        if tv=="Random" then rel[k]="<Random> "..safeString(v) end
                    end
                end
                if next(rel) then out.upvalues=rel end
            end
        end)
    end
    return out
end

local function inspectModule(pathText)
    local mod,inst=requireOptional(pathText)
    local out={path=pathText,instance=inst and inst:GetFullName() or nil,loaded=typeof(mod)=="table",functions={}}
    if typeof(mod)~="table" then return out end
    for k,v in pairs(mod) do
        if type(v)=="function" then
            local q=lower(k)
            local keep=containsToken(q)
                or string.find(q,"draw",1,true)
                or string.find(q,"cycle",1,true)
                or string.find(q,"rarity",1,true)
                or string.find(q,"reset",1,true)
                or string.find(q,"night",1,true)
                or string.find(q,"blink",1,true)
                or string.find(q,"random",1,true)
            if keep then out.functions[safeString(k)]=fnMeta(v,true) end
        elseif type(v)=="number" or type(v)=="string" or type(v)=="boolean" then
            if containsToken(k) then out[safeString(k)]=v end
        end
    end
    return out
end

local function inspectSignal(name,sig)
    local out={name=name,available=typeof(sig)=="table",handlers={}}
    if typeof(sig)~="table" then return out end
    local node=rawget(sig,"_handlerListHead")
    local seen={}
    local n=0
    while typeof(node)=="table" and not seen[node] and n<60 do
        seen[node]=true
        n=n+1
        local fn=rawget(node,"_fn")
        out.handlers[#out.handlers+1]={index=n,connected=rawget(node,"Connected"),fn=fnMeta(fn,true)}
        node=rawget(node,"_next")
    end
    out.count=#out.handlers
    return out
end

local function scanSignals()
    EggState=select(1,requireOptional("Client.EggState"))
    S.Signals={}
    if typeof(EggState)=="table" then
        for _,name in ipairs({"ResetCountdown","RarityRevealed","RarityPresented","FieldRefreshed","FieldShifted"}) do
            S.Signals[name]=inspectSignal(name,EggState[name])
        end
    end
end

local function sourceSnippets(src)
    local out={}
    local lo=string.lower(src)
    for _,token0 in ipairs(TOKENS) do
        local token=string.lower(token0)
        local start=1
        while #out<150 do
            local a,b=string.find(lo,token,start,true)
            if not a then break end
            local l=math.max(1,a-1200)
            local r=math.min(#src,b+2200)
            out[#out+1]={token=token0,snippet=string.sub(src,l,r)}
            start=b+1
        end
        if #out>=150 then break end
    end
    return out
end

local function decompileTargets()
    local out={available=type(decompile)=="function",items={},totalSourceChars=0}
    if not out.available then return out end
    local targets,seen={},{}
    local function add(inst)
        if inst and not seen[inst] and (inst:IsA("ModuleScript") or inst:IsA("LocalScript")) then
            seen[inst]=true;targets[#targets+1]=inst
        end
    end
    for _,pathText in ipairs({
        "Shared.Util.AreaEggCycle",
        "Shared.Types.AreaEggResetCycle",
        "Shared.Util.AssetLottery",
        "Client.EggState",
        "Shared.Remotes",
        "Shared.Util.EggRecords",
        "CmdrClient.Commands.resetEggCycle",
        "CmdrClient.Commands.spawnRareEgg",
        "CmdrClient.Commands.globalSpawnRareEgg",
        "CmdrClient.Commands.globalEggLuckBoost",
    }) do add(childPath(RS,pathText)) end
    for _,inst in ipairs(RS:GetDescendants()) do
        if inst:IsA("ModuleScript") then
            local q=lower(inst:GetFullName())
            if (string.find(q,"areaegg",1,true) and (string.find(q,"cycle",1,true) or string.find(q,"reset",1,true) or string.find(q,"rarity",1,true)))
                or string.find(q,"assetlottery",1,true)
                or string.find(q,"rareegg",1,true) then add(inst) end
        end
    end
    local ps=LP:FindFirstChild("PlayerScripts")
    if ps then
        for _,inst in ipairs(ps:GetDescendants()) do
            if inst:IsA("LocalScript") or inst:IsA("ModuleScript") then
                local q=lower(inst:GetFullName())
                if string.find(q,"gameresettimer",1,true)
                    or string.find(q,"rareegghighlight",1,true)
                    or (string.find(q,"areaeggs",1,true) and (string.find(q,"reset",1,true) or string.find(q,"rarity",1,true))) then add(inst) end
            end
        end
    end
    local chars=0
    for _,inst in ipairs(targets) do
        if chars>1100000 then break end
        local ok,src=pcall(decompile,inst)
        if ok and type(src)=="string" and #src>0 then
            local hits=sourceSnippets(src)
            if #hits>0 then
                out.items[#out.items+1]={path=inst:GetFullName(),class=inst.ClassName,length=#src,hits=hits}
                chars=chars+#src
            end
        end
    end
    out.totalSourceChars=chars
    return out
end

local function scanGC()
    local out={available=type(getgc)=="function",hits={}}
    if not out.available then return out end
    local ok,g=pcall(getgc,true)
    if not ok or type(g)~="table" then out.error=safeString(g) return out end
    for _,v in ipairs(g) do
        if type(v)=="function" then
            local m=fnMeta(v,false)
            local q=lower((m and m.source or "").." "..(m and m.name or ""))
            local keep=string.find(q,"areaeggcycle",1,true)
                or string.find(q,"areaeggreset",1,true)
                or string.find(q,"assetlottery",1,true)
                or string.find(q,"gameresettimer",1,true)
                or string.find(q,"rareegghighlight",1,true)
                or string.find(q,"rarity",1,true) and string.find(q,"egg",1,true)
            if not keep and m and m.constants then
                for _,c in pairs(m.constants) do
                    if type(c)=="string" and containsToken(c) then keep=true break end
                end
            end
            if keep then out.hits[#out.hits+1]=fnMeta(v,true) end
            if #out.hits>=360 then break end
        end
    end
    out.count=#out.hits
    return out
end

local function scanStatic()
    AreaEggCycle=select(1,requireOptional("Shared.Util.AreaEggCycle"))
    AreaEggResetCycle=select(1,requireOptional("Shared.Types.AreaEggResetCycle"))
    AssetLottery=select(1,requireOptional("Shared.Util.AssetLottery"))
    S.StaticModules={
        inspectModule("Shared.Util.AreaEggCycle"),
        inspectModule("Shared.Types.AreaEggResetCycle"),
        inspectModule("Shared.Util.AssetLottery"),
        inspectModule("Client.EggState"),
        inspectModule("Shared.Util.EggRecords"),
    }
    scanSignals()
    S.Decompile=decompileTargets()
    S.GC=scanGC()
    recordEvent("static_scan",{
        decompile=S.Decompile and S.Decompile.available,
        decompiledItems=S.Decompile and #S.Decompile.items or 0,
        gc=S.GC and S.GC.available,
        gcHits=S.GC and #S.GC.hits or 0,
    })
end

local function cycleStats()
    local intervals={}
    for i=2,#S.CycleWindows do
        local a=S.CycleWindows[i-1].serverTime
        local b=S.CycleWindows[i].serverTime
        if finite(a) and finite(b) and b>a then intervals[#intervals+1]=b-a end
    end
    table.sort(intervals)
    local median=nil
    if #intervals>0 then
        local n=#intervals
        if n%2==1 then median=intervals[(n+1)/2] else median=(intervals[n/2]+intervals[n/2+1])/2 end
    end
    return {intervals=intervals,medianSeconds=median,count=#intervals}
end

local function summary()
    local current=currentRareEggs()
    return {
        Records=(function() local n=0 for _ in pairs(S.Records) do n=n+1 end return n end)(),
        CurrentRare=#current,
        CatalogRare=#S.CatalogRare,
        CountdownEvents=#S.CountdownEvents,
        RevealQueries=#S.RevealQueries,
        RevealEvents=#S.RevealEvents,
        SpawnEvents=#S.SpawnEvents,
        Cycles=#S.CycleWindows,
        CycleStats=cycleStats(),
        Decompile=S.Decompile and S.Decompile.available or false,
        DecompiledItems=S.Decompile and #S.Decompile.items or 0,
        GCAvailable=S.GC and S.GC.available or false,
        GCHits=S.GC and #S.GC.hits or 0,
    }
end

local function buildReport()
    return {
        Meta={
            Version="EggPredictionScannerV14",
            PlaceId=game.PlaceId,
            GameId=game.GameId,
            JobId=game.JobId,
            StartedUnix=START_UNIX,
            FinishedUnix=os.time(),
            StartedServerTime=S.Events[1] and S.Events[1].serverTime or nil,
            FinishedServerTime=serverNow(),
            PassiveExceptReadOnlyRarityQuery=true,
            RareThreshold="Cosmic+",
            Notes="Capture 2-3 resets if possible. AskFieldEggRarityShows is queried read-only; no cycle/spawn/luck admin remotes are called.",
        },
        Summary=summary(),
        CurrentRareEggs=currentRareEggs(),
        RareCatalog=S.CatalogRare,
        CountdownEvents=S.CountdownEvents,
        RevealQueries=S.RevealQueries,
        RevealEvents=S.RevealEvents,
        CycleWindows=S.CycleWindows,
        SpawnEvents=S.SpawnEvents,
        StaticModules=S.StaticModules,
        SignalHandlers=S.Signals,
        Decompiled=S.Decompile,
        GC=S.GC,
        Events=S.Events,
    }
end

local function exportReport()
    local report=buildReport()
    local ok,json=pcall(Http.JSONEncode,Http,report)
    if not ok then return false,"JSONEncode: "..safeString(json) end
    local name="Psico_RoubeUmOvo_Prediction_"..tostring(os.time())..".json"
    local wrote=false
    if writefile then wrote=pcall(writefile,name,json) end
    if setclipboard then pcall(setclipboard,json) end
    return true,name,wrote,#json
end

local function makeGui()
    local old=uiParent():FindFirstChild("PSICO_EGG_PREDICTION_SCAN_V14")
    if old then pcall(function() old:Destroy() end) end

    local gui=Instance.new("ScreenGui")
    gui.Name="PSICO_EGG_PREDICTION_SCAN_V14"
    gui.ResetOnSpawn=false
    gui.IgnoreGuiInset=false
    gui.DisplayOrder=999
    gui.Parent=uiParent()
    S.Gui=gui

    local frame=Instance.new("Frame")
    frame.Name="Main"
    frame.AnchorPoint=Vector2.new(.5,.5)
    frame.Position=UDim2.fromScale(.5,.48)
    frame.Size=UDim2.fromOffset(430,270)
    frame.BackgroundColor3=Color3.fromRGB(11,20,38)
    frame.BorderSizePixel=0
    frame.Parent=gui

    local sizeConstraint=Instance.new("UISizeConstraint")
    sizeConstraint.MinSize=Vector2.new(330,230)
    sizeConstraint.MaxSize=Vector2.new(500,310)
    sizeConstraint.Parent=frame

    local corner=Instance.new("UICorner")
    corner.CornerRadius=UDim.new(0,14)
    corner.Parent=frame

    local stroke=Instance.new("UIStroke")
    stroke.Color=Color3.fromRGB(38,91,164)
    stroke.Thickness=1
    stroke.Transparency=.2
    stroke.Parent=frame

    local title=Instance.new("TextLabel")
    title.BackgroundTransparency=1
    title.Position=UDim2.fromOffset(14,8)
    title.Size=UDim2.new(1,-70,0,28)
    title.Font=Enum.Font.GothamBold
    title.Text="PREDICTION SCAN V14"
    title.TextColor3=Color3.fromRGB(235,244,255)
    title.TextSize=16
    title.TextXAlignment=Enum.TextXAlignment.Left
    title.Parent=frame

    local sub=Instance.new("TextLabel")
    sub.BackgroundTransparency=1
    sub.Position=UDim2.fromOffset(14,35)
    sub.Size=UDim2.new(1,-28,0,24)
    sub.Font=Enum.Font.Gotham
    sub.Text="Ciclo • reveal raro • seed/RNG • spawn seguinte"
    sub.TextColor3=Color3.fromRGB(125,164,214)
    sub.TextSize=11
    sub.TextXAlignment=Enum.TextXAlignment.Left
    sub.Parent=frame

    local close=Instance.new("TextButton")
    close.BackgroundColor3=Color3.fromRGB(34,47,68)
    close.Position=UDim2.new(1,-43,0,9)
    close.Size=UDim2.fromOffset(30,28)
    close.Text="×"
    close.TextColor3=Color3.fromRGB(235,240,250)
    close.TextSize=17
    close.Font=Enum.Font.GothamBold
    close.Parent=frame
    local cc=Instance.new("UICorner");cc.CornerRadius=UDim.new(0,8);cc.Parent=close

    local status=Instance.new("TextLabel")
    status.BackgroundColor3=Color3.fromRGB(15,28,50)
    status.Position=UDim2.fromOffset(14,65)
    status.Size=UDim2.new(1,-28,0,116)
    status.BorderSizePixel=0
    status.Font=Enum.Font.Code
    status.TextColor3=Color3.fromRGB(215,229,247)
    status.TextSize=11
    status.TextWrapped=false
    status.TextXAlignment=Enum.TextXAlignment.Left
    status.TextYAlignment=Enum.TextYAlignment.Top
    status.Text="Inicializando..."
    status.Parent=frame
    local sc=Instance.new("UICorner");sc.CornerRadius=UDim.new(0,10);sc.Parent=status
    local pad=Instance.new("UIPadding");pad.PaddingLeft=UDim.new(0,10);pad.PaddingTop=UDim.new(0,8);pad.Parent=status

    local function button(text,xScale,xOffset,wScale,wOffset)
        local b=Instance.new("TextButton")
        b.BackgroundColor3=Color3.fromRGB(24,65,111)
        b.Position=UDim2.new(xScale,xOffset,1,-72)
        b.Size=UDim2.new(wScale,wOffset,0,32)
        b.BorderSizePixel=0
        b.Text=text
        b.TextColor3=Color3.fromRGB(238,246,255)
        b.TextSize=11
        b.Font=Enum.Font.GothamBold
        b.Parent=frame
        local c=Instance.new("UICorner");c.CornerRadius=UDim.new(0,9);c.Parent=b
        return b
    end

    local scanBtn=button("REFAZER LEITURA",0,14,.33,-12)
    local revealBtn=button("CONSULTAR REVEAL",.33,8,.34,-12)
    local exportBtn=button("EXPORTAR JSON",.67,2,.33,-16)

    local foot=Instance.new("TextLabel")
    foot.BackgroundTransparency=1
    foot.Position=UDim2.new(0,14,1,-34)
    foot.Size=UDim2.new(1,-28,0,22)
    foot.Font=Enum.Font.Gotham
    foot.Text="Ideal: deixe rodar por 2–3 reinícios. Não precisa pegar ovos."
    foot.TextColor3=Color3.fromRGB(125,164,214)
    foot.TextSize=10
    foot.TextXAlignment=Enum.TextXAlignment.Left
    foot.Parent=frame

    local function refreshStatus(msg)
        if not S.Alive or not status.Parent then return end
        local sum=summary()
        local last=S.CountdownEvents[#S.CountdownEvents]
        local rem=last and last.remaining
        local remText=finite(rem) and string.format("%.1fs",rem) or (last and "payload capturado" or "aguardando")
        local med=sum.CycleStats and sum.CycleStats.medianSeconds
        local cycleText=finite(med) and string.format("%.1fs",med) or "aguardando 2 ciclos"
        status.Text=table.concat({
            msg or "Gravando dados...",
            string.format("Ovos: %d | raros atuais: %d | catálogo Cosmic+: %d",sum.Records,sum.CurrentRare,sum.CatalogRare),
            string.format("Countdown: %d | último: %s",sum.CountdownEvents,remText),
            string.format("Reveal RF: %d | Reveal RE: %d",sum.RevealQueries,sum.RevealEvents),
            string.format("Ciclos detectados: %d | intervalo: %s",sum.Cycles,cycleText),
            string.format("Decompile: %s (%d) | GC: %s (%d)",sum.Decompile and "SIM" or "NÃO",sum.DecompiledItems,sum.GCAvailable and "SIM" or "NÃO",sum.GCHits),
        },"\n")
    end

    S.RefreshStatus=refreshStatus

    connect(scanBtn.Activated,function()
        scanBtn.Text="LENDO..."
        task.spawn(function()
            requestSnapshots()
            scanStatic()
            queryRarityShows("manual_scan",true)
            refreshStatus("Leitura refeita.")
            scanBtn.Text="REFAZER LEITURA"
        end)
    end)

    connect(revealBtn.Activated,function()
        revealBtn.Text="CONSULTANDO..."
        task.spawn(function()
            local row=queryRarityShows("manual",true)
            refreshStatus(row and row.ok and "Reveal consultado." or "Falha ao consultar reveal.")
            revealBtn.Text="CONSULTAR REVEAL"
        end)
    end)

    connect(exportBtn.Activated,function()
        exportBtn.Text="EXPORTANDO..."
        task.spawn(function()
            scanStatic()
            local ok,name,wrote,bytes=exportReport()
            if ok then
                refreshStatus((wrote and "Arquivo salvo: " or "JSON copiado: ")..safeString(name).." • "..tostring(bytes).." bytes")
            else
                refreshStatus("Erro exportando: "..safeString(name))
            end
            exportBtn.Text="EXPORTAR JSON"
        end)
    end)

    local dragging=false
    local dragStart,startPos
    connect(frame.InputBegan,function(input)
        if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1 then
            dragging=true;dragStart=input.Position;startPos=frame.Position
        end
    end)
    connect(UIS.InputChanged,function(input)
        if dragging and (input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseMovement) then
            local d=input.Position-dragStart
            frame.Position=UDim2.new(startPos.X.Scale,startPos.X.Offset+d.X,startPos.Y.Scale,startPos.Y.Offset+d.Y)
        end
    end)
    connect(UIS.InputEnded,function(input)
        if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1 then dragging=false end
    end)

    connect(close.Activated,function()
        if _G.PSICO_ROUBE_SCANNER_CLEANUP then _G.PSICO_ROUBE_SCANNER_CLEANUP() end
    end)

    local cam=Workspace.CurrentCamera
    local function resize()
        cam=Workspace.CurrentCamera or cam
        if not cam then return end
        local vp=cam.ViewportSize
        local targetW=math.clamp(vp.X*.58,330,430)
        local targetH=math.clamp(vp.Y*.68,230,270)
        frame.Size=UDim2.fromOffset(targetW,targetH)
    end
    resize()
    if cam then connect(cam:GetPropertyChangedSignal("ViewportSize"),resize) end
    connect(Workspace:GetPropertyChangedSignal("CurrentCamera"),function()
        resize()
    end)

    refreshStatus("Inicializando scanner...")
end

local function cleanup()
    if not S.Alive then return end
    S.Alive=false
    for _,c in ipairs(S.RC) do disconnect(c) end
    for _,c in ipairs(S.C) do disconnect(c) end
    if S.Gui then pcall(function() S.Gui:Destroy() end) end
    _G.PSICO_ROUBE_SCANNER_CLEANUP=nil
end
_G.PSICO_ROUBE_SCANNER_CLEANUP=cleanup

buildCatalog()
hookEggRemotes()
makeGui()

task.spawn(function()
    requestSnapshots()
    scanStatic()
    queryRarityShows("startup",true)
    if S.RefreshStatus then S.RefreshStatus("Leitura pronta • aguardando ciclos/reveals.") end
end)

task.spawn(function()
    while S.Alive do
        task.wait(1)
        if S.RefreshStatus then S.RefreshStatus() end
    end
end)

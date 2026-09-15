-- PSICOSENATICO | EGG CYCLE DATA PROBE V6
-- Controlled read-only predictor correlation probe.
-- Uses only replicated ModuleScripts plus synthetic/local RNG objects.
-- No remotes, hooks, debug/getgc, HTTP interception or game mutation.

local RS=game:GetService("ReplicatedStorage")
local CG=game:GetService("CoreGui")
local UIS=game:GetService("UserInputService")

local function at(root,...)
    local x=root
    for _,n in ipairs({...}) do x=x and x:FindFirstChild(n) end
    return x
end

local function req(m)
    if not m or not m:IsA("ModuleScript") then return nil,"not-found" end
    local ok,r=pcall(require,m)
    if ok then return r,nil end
    return nil,tostring(r)
end

local Lottery,lotErr=req(at(RS,"Shared","Util","AssetLottery"))
local Better,betterErr=req(at(RS,"Shared","Modules","BetterRandom"))
local SubBiome,subErr=req(at(RS,"Shared","Util","SubBiomeCycle"))
local Cycle,cycleErr=req(at(RS,"Shared","Util","AreaEggCycle"))

local AREA_ROOT=at(RS,"Data","Areas","Configs")
local AREA_NAMES={
    "Abyss Ocean","Cherry Blossom","Cosmic","Desert","Forest","Jungle",
    "Lake","Light Dark","Prehistoric","Snow","Titan Temple","Volcano"
}

-- These periods come from the earlier Axon zero-hook capture.
-- Axon rendered:
-- 5964937: Pure Jellyfish + RazorFang (Light Dark)
-- 5964938: Kraken (Abyss Ocean) + Gargoyle (Light Dark)
-- 5964940: Lava Dragon (Volcano)
-- 5964944: Cerberus (Volcano)
-- 5964947: Mosasaurus (Prehistoric)
-- 5964948: Eternal Lunar Dragon (Cosmic)
-- 5964950: Cosmic Skeleton Boss (Cosmic)
-- 5964951: Pegasus (Light Dark)
local HISTORICAL_PERIODS={5964937,5964938,5964940,5964944,5964947,5964948,5964950,5964951}

local function clean(v,d,seen,budget)
    d=d or 0
    seen=seen or {}
    budget=budget or {n=0,max=16000}
    budget.n+=1
    if budget.n>budget.max then return "<budget-limit>" end
    local t=typeof(v)
    if t=="nil" or t=="boolean" or t=="string" or t=="number" then return v end
    if t=="Instance" then
        local ok,p=pcall(function() return v:GetFullName() end)
        return {__type="Instance",class=v.ClassName,path=ok and p or tostring(v)}
    end
    if t=="function" then return "<function>" end
    if t=="thread" then return "<thread>" end
    if t=="userdata" then return tostring(v) end
    if t~="table" then return tostring(v) end
    if seen[v] then return "<cycle>" end
    if d>=7 then return "<depth-limit>" end
    seen[v]=true
    local o={}
    local n=0
    for k,z in pairs(v) do
        n+=1
        if n>900 then o["<truncated>"]="more than 900 keys" break end
        o[tostring(k)]=clean(z,d+1,seen,budget)
    end
    seen[v]=nil
    return o
end

local function packCall(label,fn,...)
    if type(fn)~="function" then return {label=label,available=false} end
    local ok,a,b,c,d=pcall(fn,...)
    if not ok then return {label=label,available=true,ok=false,error=tostring(a)} end
    return {label=label,available=true,ok=true,values=clean({a,b,c,d})}
end

local function areaConfig(name)
    local m=AREA_ROOT and AREA_ROOT:FindFirstChild(name)
    if not m or not m:IsA("ModuleScript") then return nil,"not-found" end
    local ok,r=pcall(require,m)
    if ok then return r,nil end
    return nil,tostring(r)
end

local function selectedTable(areaName,period)
    local cfg,cfgErr=areaConfig(areaName)
    local rolled=nil
    local rollErr=nil
    if SubBiome and type(SubBiome.RolledForPeriod)=="function" then
        local ok,r=pcall(SubBiome.RolledForPeriod,areaName,period)
        if ok then rolled=r else rollErr=tostring(r) end
    end
    local drop=nil
    if type(rolled)=="table" and type(rolled.DropTable)=="table" then
        drop=rolled.DropTable
    elseif type(cfg)=="table" and type(cfg.DropTable)=="table" then
        drop=cfg.DropTable
    end
    return {
        config=cfg,
        configError=cfgErr,
        rolled=rolled,
        rolledError=rollErr,
        dropTable=drop
    }
end

local function newBetter(seed)
    if not Better or type(Better.new)~="function" then return nil,"unavailable" end
    local ok,r=pcall(Better.new,seed)
    if ok then return r,nil end
    return nil,tostring(r)
end

local function lotteryTrialsFor(areaName,period,drop)
    local out={}
    if not Lottery or type(Lottery.DrawCategoryFromTable)~="function" or type(drop)~="table" then
        return out
    end

    local function add(label,...)
        out[#out+1]=packCall(label,Lottery.DrawCategoryFromTable,...)
    end

    add("Random,table",Random.new(period),drop)
    add("table,Random",drop,Random.new(period))
    add("Random,table,1",Random.new(period),drop,1)
    add("table,1,Random",drop,1,Random.new(period))
    add("table,Random,1",drop,Random.new(period),1)

    local br,brErr=newBetter(period)
    if br then
        add("BetterRandom,table",br,drop)
    else
        out[#out+1]={label="BetterRandom,table",ok=false,error=brErr}
    end

    local seq={}
    local r=Random.new(period)
    for i=1,16 do
        local t=packCall("draw"..i,Lottery.DrawCategoryFromTable,r,drop)
        seq[#seq+1]=t
        if not t.ok then break end
    end
    out[#out+1]={label="sequence Random.new(period), 16 draws",sequence=seq}
    return out
end

local function compactRolled(v)
    if type(v)~="table" then return v end
    local o={
        Id=v.Id,
        DisplayName=v.DisplayName,
        Weight=v.Weight,
        LuckRolls=v.LuckRolls,
        Pool=clean(v.Pool),
        DropTable=clean(v.DropTable)
    }
    return o
end

local function probe()
    local now=os.time()
    local currentPeriod=math.floor(now/300)
    if Cycle and type(Cycle.PeriodIndexAt)=="function" then
        local ok,p=pcall(Cycle.PeriodIndexAt,now)
        if ok and type(p)=="number" then currentPeriod=p end
    end

    local out={
        meta={
            version="EggCycleDataProbe6",
            created=now,
            placeId=tostring(game.PlaceId),
            gameId=tostring(game.GameId),
            jobId=tostring(game.JobId),
            passive=true,
            mode="predictor-correlation",
            currentPeriod=currentPeriod
        },
        errors={lottery=lotErr,better=betterErr,subBiome=subErr,cycle=cycleErr},
        historical={},
        future={},
        signatureFocus={}
    }

    for _,period in ipairs(HISTORICAL_PERIODS) do
        local rec={periodIndex=period,areas={}}
        for _,areaName in ipairs(AREA_NAMES) do
            local s=selectedTable(areaName,period)
            rec.areas[areaName]={
                rolled=compactRolled(s.rolled),
                rolledError=s.rolledError
            }
        end
        out.historical[tostring(period)]=rec
    end

    for _,spec in ipairs({
        {"Light Dark",5964937},
        {"Light Dark",5964938},
        {"Abyss Ocean",5964938},
        {"Volcano",5964940},
        {"Prehistoric",5964947},
        {"Cosmic",5964948},
        {"Light Dark",5964951}
    }) do
        local areaName,period=spec[1],spec[2]
        local s=selectedTable(areaName,period)
        local key=areaName.."@"..period
        out.signatureFocus[key]={
            area=areaName,
            periodIndex=period,
            rolled=compactRolled(s.rolled),
            dropTable=clean(s.dropTable),
            lottery=lotteryTrialsFor(areaName,period,s.dropTable)
        }
        if SubBiome then
            out.signatureFocus[key].forPeriod=packCall(
                "ForPeriod(area,period)",SubBiome.ForPeriod,areaName,period
            )
            out.signatureFocus[key].poolDropTable=packCall(
                "PoolDropTable(area,period)",SubBiome.PoolDropTable,areaName,period
            )
        end
    end

    for step=0,12 do
        local period=currentPeriod+step
        local rec={step=step,periodIndex=period,areas={}}
        for _,areaName in ipairs(AREA_NAMES) do
            local s=selectedTable(areaName,period)
            if s.rolled~=nil then
                rec.areas[areaName]=compactRolled(s.rolled)
            end
        end
        out.future[#out.future+1]=rec
    end

    return out
end

local function esc(s)
    s=tostring(s or "")
    s=s:gsub("\\","\\\\"):gsub('"','\\"'):gsub("\b","\\b"):gsub("\f","\\f")
    s=s:gsub("\n","\\n"):gsub("\r","\\r"):gsub("\t","\\t")
    s=s:gsub("[%z\1-\31]",function(c) return string.format("\\u%04x",string.byte(c)) end)
    return '"'..s..'"'
end

local function isArray(t)
    local n=0
    for k in pairs(t) do
        if type(k)~="number" or k<1 or k%1~=0 then return false,0 end
        n=math.max(n,k)
    end
    for i=1,n do if rawget(t,i)==nil then return false,0 end end
    return true,n
end

local function encode(v,seen)
    local tv=type(v)
    if tv=="nil" then return "null" end
    if tv=="boolean" then return v and "true" or "false" end
    if tv=="number" then
        if v~=v or v==math.huge or v==-math.huge then return esc(tostring(v)) end
        return tostring(v)
    end
    if tv=="string" then return esc(v) end
    if tv~="table" then return esc(tostring(v)) end
    seen=seen or {}
    if seen[v] then return esc("<cycle>") end
    seen[v]=true

    local arr,n=isArray(v)
    local parts={}
    if arr then
        for i=1,n do parts[#parts+1]=encode(v[i],seen) end
        seen[v]=nil
        return "["..table.concat(parts,",").."]"
    end

    local keys={}
    for k in pairs(v) do keys[#keys+1]=tostring(k) end
    table.sort(keys)
    for _,k in ipairs(keys) do
        parts[#parts+1]=esc(k)..":"..encode(v[k],seen)
    end
    seen[v]=nil
    return "{"..table.concat(parts,",").."}"
end

local gui=Instance.new("ScreenGui")
gui.Name="PSICO_PREDICTOR_CORRELATION_V6"
gui.ResetOnSpawn=false
gui.DisplayOrder=1406
gui.Parent=CG

local f=Instance.new("Frame")
f.AnchorPoint=Vector2.new(.5,.5)
f.Position=UDim2.fromScale(.5,.5)
f.Size=UDim2.fromOffset(460,220)
f.BackgroundColor3=Color3.fromRGB(9,18,34)
f.BorderSizePixel=0
f.Parent=gui
Instance.new("UICorner",f).CornerRadius=UDim.new(0,14)

local title=Instance.new("TextLabel")
title.BackgroundTransparency=1
title.Position=UDim2.fromOffset(14,10)
title.Size=UDim2.new(1,-28,0,28)
title.Text="PREDICTOR CORRELATION PROBE V6"
title.Font=Enum.Font.GothamBold
title.TextSize=14
title.TextColor3=Color3.new(1,1,1)
title.Parent=f

local st=Instance.new("TextLabel")
st.Position=UDim2.fromOffset(14,48)
st.Size=UDim2.new(1,-28,0,66)
st.BackgroundColor3=Color3.fromRGB(15,29,52)
st.BorderSizePixel=0
st.Text="Pronto. Cruza periodos historicos do Axon com SubBiomeCycle e sorteio local."
st.TextWrapped=true
st.Font=Enum.Font.Code
st.TextSize=11
st.TextColor3=Color3.new(1,1,1)
st.Parent=f
Instance.new("UICorner",st).CornerRadius=UDim.new(0,9)

local function btn(t,x,w)
    local b=Instance.new("TextButton")
    b.Position=UDim2.fromOffset(x,132)
    b.Size=UDim2.fromOffset(w,38)
    b.BackgroundColor3=Color3.fromRGB(31,78,132)
    b.BorderSizePixel=0
    b.Text=t
    b.TextColor3=Color3.new(1,1,1)
    b.Font=Enum.Font.GothamBold
    b.TextSize=11
    b.Parent=f
    Instance.new("UICorner",b).CornerRadius=UDim.new(0,9)
    return b
end

local cap=btn("CORRELACIONAR + EXPORTAR",14,284)
local close=btn("FECHAR",312,134)

cap.MouseButton1Click:Connect(function()
    st.Text="Calculando correlacoes locais..."
    task.defer(function()
        local ok,r=pcall(probe)
        if not ok then st.Text="Erro: "..tostring(r) return end
        local ok2,j=pcall(function() return encode(r,{}) end)
        if not ok2 then st.Text="Erro JSON: "..tostring(j) return end
        local name="Psico_PredictorCorrelation_"..os.time()..".json"
        local wrote=false
        if writefile then wrote=pcall(writefile,name,j) end
        if setclipboard then pcall(setclipboard,j) end
        st.Text=(wrote and "EXPORTADO: " or "COPIADO: ")..name.." | "..#j.." bytes"
    end)
end)

close.MouseButton1Click:Connect(function() gui:Destroy() end)

local dragging=false
local dragStart,startPos
f.InputBegan:Connect(function(i)
    if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then
        dragging=true
        dragStart=i.Position
        startPos=f.Position
    end
end)
f.InputChanged:Connect(function(i)
    if dragging and (i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch) then
        local d=i.Position-dragStart
        f.Position=UDim2.new(startPos.X.Scale,startPos.X.Offset+d.X,startPos.Y.Scale,startPos.Y.Offset+d.Y)
    end
end)
UIS.InputEnded:Connect(function(i)
    if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then
        dragging=false
    end
end)

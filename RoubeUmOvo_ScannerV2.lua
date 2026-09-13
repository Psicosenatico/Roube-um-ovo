--[[
PSICOSENATICO | Roube um Ovo - Carry Multiplier Scanner V12
Objetivo: localizar, no cliente, a origem/calculo do SpeedMultiplier ANTES de pegar o ovo.
Passivo: nao altera velocidade, ovos, guardioes, prompts, bats ou remotes.
Mantem captura de amostras reais apenas para validar a leitura.
]]

if _G.PSICO_ROUBE_SCANNER_CLEANUP then pcall(_G.PSICO_ROUBE_SCANNER_CLEANUP) end

local Players=game:GetService("Players")
local Workspace=game:GetService("Workspace")
local RS=game:GetService("ReplicatedStorage")
local CoreGui=game:GetService("CoreGui")
local Http=game:GetService("HttpService")
local UIS=game:GetService("UserInputService")
local LP=Players.LocalPlayer

local S={
    Alive=true,C={},RC={},Records={},Samples={},Gui=nil,Report=nil,
    CandidateModules={},CandidateFunctions={},SourceHits={},TableEvidence={},
}
local EggRecords

local TOKENS={
    "speedmultiplier","runbackwakedelayrequired","guarddisabled","areaeggcarry",
    "carry","weightkg","nestscale","assetscale","walkspeed","slow","multiplier",
}
local STRONG={
    "speedmultiplier","runbackwakedelayrequired","guarddisabled","areaeggcarry",
}

local function finite(v)return type(v)=="number" and v==v and v~=math.huge and v~=-math.huge end
local function str(v)local ok,x=pcall(tostring,v)return ok and x or "?" end
local function lower(v)return string.lower(str(v or "")) end
local function hasToken(v,strongOnly)
    local q=lower(v)
    local list=strongOnly and STRONG or TOKENS
    for _,t in ipairs(list)do if string.find(q,t,1,true)then return true,t end end
    return false
end
local function con(sig,fn,b)local c=sig:Connect(fn)table.insert(b or S.C,c)return c end
local function pg()
    local ok,h=pcall(function()if gethui then return gethui()end end)
    return(ok and h)or CoreGui
end
local function req(m)
    if not(m and m:IsA("ModuleScript"))then return nil end
    local ok,v=pcall(require,m)
    return ok and v or nil
end
local function path(root,p)
    local cur=root
    for token in string.gmatch(p,"[^%.]+")do
        if not cur then return nil end
        cur=cur:FindFirstChild(token)
    end
    return cur
end
local function ser(v,d,seen)
    d=d or 0;seen=seen or{}
    if d>5 then return "<depth>" end
    local t=typeof(v)
    if t=="nil"or t=="boolean"or t=="string"then return v end
    if t=="number"then return finite(v)and v or str(v)end
    if t=="Vector3"then return{x=v.X,y=v.Y,z=v.Z}end
    if t=="CFrame"then return{position=ser(v.Position)}end
    if t=="Color3"then return{r=v.R,g=v.G,b=v.B}end
    if t=="Instance"then return{class=v.ClassName,name=v.Name,path=v:GetFullName()}end
    if t=="function"then return"<function> "..str(v)end
    if t~="table"then return str(v)end
    if seen[v]then return"<cycle>"end
    seen[v]=true
    local o,n={},0
    for k,x in pairs(v)do
        n=n+1;if n>220 then o.__truncated=true break end
        o[(type(k)=="string"or type(k)=="number")and k or str(k)]=ser(x,d+1,seen)
    end
    seen[v]=nil
    return o
end

local function findExact(class,name)
    for _,d in ipairs(RS:GetDescendants())do
        if d.ClassName==class and d.Name==name then return d end
    end
end

local function eggCall(name,r)
    if type(EggRecords)~="table"or type(EggRecords[name])~="function"then return nil,false end
    local ok,v=pcall(EggRecords[name],r)
    if ok then return v,true end
    ok,v=pcall(EggRecords[name],EggRecords,r)
    return ok and v or nil,ok
end
local function eggSummary(r)
    if typeof(r)~="table"then return nil end
    local w,wok=eggCall("WeightKg",r)
    return{
        Uid=r.Uid,State=r.State,AreaId=r.AreaId,NestId=r.NestId,
        AssetCategory=r.AssetCategory,AssetScale=r.AssetScale,NestScale=r.NestScale,
        BaseMutation=r.BaseMutation,Mutations=ser(r.Mutations),
        WeightKg=(wok and finite(w))and w or nil,
    }
end
local function ingest(v,seen,d)
    if typeof(v)~="table"then return 0 end
    seen=seen or{};d=d or 0
    if d>8 or seen[v]then return 0 end
    seen[v]=true
    local n=0
    if type(v.Uid)=="string"and v.State~=nil then
        S.Records[v.Uid]=v;n=1
    else
        local c=0
        for _,x in pairs(v)do
            c=c+1;if c>3000 then break end
            if typeof(x)=="table"then n=n+ingest(x,seen,d+1)end
        end
    end
    seen[v]=nil
    return n
end
local function snapshots()
    local n=0
    for _,name in ipairs({"RF/EggWorld/AskFieldEggSnapshot","RF/EggWorld/AskLiveSnapshot"})do
        local rf=findExact("RemoteFunction",name)
        if rf then
            local ok,v=pcall(function()return rf:InvokeServer()end)
            if ok then n=n+ingest(v)end
        end
    end
    return n
end

local function currentEggs()
    local out={}
    for _,r in pairs(S.Records)do
        if r.State=="Slot"or r.State=="Dropped"then out[#out+1]=eggSummary(r)end
    end
    table.sort(out,function(a,b)
        local aw,bw=a.WeightKg or 0,b.WeightKg or 0
        return aw<bw
    end)
    return out
end

local function tableEvidence(root,label)
    if typeof(root)~="table"then return nil end
    local out,seen={},{}
    local function walk(t,p,d)
        if d>5 or seen[t]then return end
        seen[t]=true
        local c=0
        for k,v in pairs(t)do
            c=c+1;if c>350 then break end
            local ks=str(k);local np=p.."."..ks
            local hit=hasToken(ks)
            if hit then
                out[#out+1]={path=np,key=ks,value=ser(v,0,{})}
                if #out>=160 then seen[t]=nil return end
            end
            if typeof(v)=="table"and d<5 then walk(v,np,d+1)end
            if #out>=160 then break end
        end
        seen[t]=nil
    end
    walk(root,"$",0)
    return #out>0 and{label=label,hits=out}or nil
end

local function functionMeta(fn)
    if type(fn)~="function"then return nil end
    local o={repr=str(fn)}
    pcall(function()
        if debug and debug.info then
            o.name=debug.info(fn,"n")
            o.source=debug.info(fn,"s")
            local a,var=debug.info(fn,"a");o.arity=a;o.variadic=var
        elseif debug and debug.getinfo then
            local i=debug.getinfo(fn)
            if i then o.name=i.name;o.source=i.source;o.arity=i.nparams;o.variadic=i.isvararg end
        end
    end)
    pcall(function()
        if type(getconstants)=="function"then
            local c=getconstants(fn);local keep={}
            for i,v in pairs(c)do
                if type(v)=="string"and hasToken(v)then keep[i]=v end
            end
            if next(keep)then o.relevantConstants=keep end
        end
    end)
    pcall(function()
        if type(getupvalues)=="function"then
            local u=getupvalues(fn);local keep={}
            for k,v in pairs(u)do
                if type(v)=="number"then
                    if v>0 and v<=10 then keep[k]=v end
                elseif type(v)=="string"and hasToken(v)then
                    keep[k]=v
                elseif typeof(v)=="table"then
                    local t={}
                    for kk,vv in pairs(v)do
                        if hasToken(kk)then t[kk]=ser(vv,0,{})end
                    end
                    if next(t)then keep[k]=t end
                end
            end
            if next(keep)then o.relevantUpvalues=keep end
        end
    end)
    return o
end

local function scanGC()
    local out={}
    if type(getgc)~="function"then return{available=false,hits=out}end
    local ok,g=pcall(getgc,true)
    if not ok or type(g)~="table"then return{available=false,error=str(g),hits=out}end
    local checked=0
    for _,v in ipairs(g)do
        if type(v)=="function"then
            checked=checked+1
            local meta=functionMeta(v)
            local score=0
            if meta then
                if hasToken(meta.name,true)or hasToken(meta.source,true)then score=score+3
                elseif hasToken(meta.name)or hasToken(meta.source)then score=score+1 end
                if meta.relevantConstants then
                    for _,x in pairs(meta.relevantConstants)do
                        if hasToken(x,true)then score=score+4 else score=score+1 end
                    end
                end
                if meta.relevantUpvalues then score=score+1 end
            end
            if score>0 then
                meta.score=score
                out[#out+1]=meta
                if #out>=180 then break end
            end
        end
    end
    table.sort(out,function(a,b)return(a.score or 0)>(b.score or 0)end)
    return{available=true,checked=checked,hits=out}
end

local function sourceSnippets(src,tokens)
    local out={}
    local lo=string.lower(src)
    for _,tok in ipairs(tokens)do
        local start=1
        while #out<40 do
            local a,b=string.find(lo,tok,start,true)
            if not a then break end
            local l=math.max(1,a-700);local r=math.min(#src,b+1100)
            out[#out+1]={token=tok,snippet=string.sub(src,l,r)}
            start=b+1
        end
        if #out>=40 then break end
    end
    return out
end

local function candidateModuleInstances()
    local exact={
        "Shared.Modules.GuardAreas.GuardEggRetrievalComponent",
        "Client.EggState",
        "Shared.Util.EggRecords",
        "Shared.Types.AreaEggs",
        "Shared.Util.TreadmillUtil",
        "Data.Guards",
    }
    local out,seen={},{}
    for _,p in ipairs(exact)do
        local m=path(RS,p)
        if m and m:IsA("ModuleScript")and not seen[m]then seen[m]=true;out[#out+1]=m end
    end
    for _,m in ipairs(RS:GetDescendants())do
        if m:IsA("ModuleScript")and not seen[m]then
            local q=lower(m:GetFullName())
            if string.find(q,"egg",1,true)or string.find(q,"carry",1,true)or string.find(q,"guard",1,true)
                or string.find(q,"speed",1,true)or string.find(q,"weight",1,true)then
                seen[m]=true;out[#out+1]=m
                if #out>=120 then break end
            end
        end
    end
    return out
end

local function scanModules()
    local modules={}
    local sourceHits={}
    local decompAvailable=type(decompile)=="function"
    local sourceBudget=0
    for _,m in ipairs(candidateModuleInstances())do
        local rec={path=m:GetFullName()}
        local val=req(m)
        if typeof(val)=="table"then
            local ev=tableEvidence(val,rec.path)
            if ev then rec.tableHits=ev.hits end
            local funcs={}
            for k,v in pairs(val)do
                if type(v)=="function"then
                    local fm=functionMeta(v)
                    if fm and(hasToken(k)or hasToken(fm.name)or hasToken(fm.source)or fm.relevantConstants)then
                        funcs[str(k)]=fm
                    end
                end
            end
            if next(funcs)then rec.functions=funcs end
        end
        if decompAvailable and sourceBudget<500000 then
            local ok,src=pcall(decompile,m)
            if ok and type(src)=="string"and #src>0 then
                local hits=sourceSnippets(src,{"speedmultiplier","runbackwakedelayrequired","guarddisabled","weightkg","nestscale","assetscale","carry"})
                if #hits>0 then
                    rec.sourceHits=hits
                    sourceHits[#sourceHits+1]={path=rec.path,hits=hits}
                    sourceBudget=sourceBudget+math.min(#src,100000)
                end
            end
        end
        if rec.tableHits or rec.functions or rec.sourceHits then modules[#modules+1]=rec end
    end
    return{
        decompileAvailable=decompAvailable,
        moduleHits=modules,
        sourceHits=sourceHits,
        sourceBudget=sourceBudget,
    }
end

local function empirical()
    local rows={}
    for _,c in ipairs(S.Samples)do
        if finite(c.serverMultiplier)and c.egg then
            rows[#rows+1]={
                multiplier=c.serverMultiplier,
                weight=c.egg.WeightKg,
                nestScale=c.egg.NestScale,
                assetScale=c.egg.AssetScale,
                areaId=c.egg.AreaId,
                assetCategory=c.egg.AssetCategory,
            }
        end
    end
    local function fit(field)
        local xs,ys={},{}
        for _,r in ipairs(rows)do
            if finite(r[field])and finite(r.multiplier)then
                xs[#xs+1]=r[field];ys[#ys+1]=1-r.multiplier
            end
        end
        if #xs<3 then return nil end
        local sx,sy,sxx,sxy=0,0,0,0
        for i=1,#xs do sx=sx+xs[i];sy=sy+ys[i];sxx=sxx+xs[i]^2;sxy=sxy+xs[i]*ys[i]end
        local n=#xs;local den=n*sxx-sx*sx
        if math.abs(den)<1e-9 then return nil end
        local a=(n*sxy-sx*sy)/den;local b=(sy-a*sx)/n
        local se=0
        for i=1,n do local e=(a*xs[i]+b)-ys[i];se=se+e*e end
        return{n=n,penaltySlope=a,penaltyIntercept=b,rmse=math.sqrt(se/n)}
    end
    return{rows=rows,nestScaleLinear=fit("nestScale"),assetScaleLinear=fit("assetScale"),weightLinear=fit("weight")}
end

local function hookCarry()
    for _,d in ipairs(RS:GetDescendants())do
        if d:IsA("RemoteEvent")then
            if d.Name=="RE/EggWorld/FieldEggShifted"then
                con(d.OnClientEvent,function(r)
                    if typeof(r)=="table"and type(r.Uid)=="string"then S.Records[r.Uid]=r end
                end,S.RC)
            elseif d.Name=="RE/EggWorld/FieldEggBatchShifted"then
                con(d.OnClientEvent,function(p)
                    if typeof(p)=="table"and typeof(p.UpdatedRecords)=="table"then
                        for _,r in pairs(p.UpdatedRecords)do
                            if typeof(r)=="table"and type(r.Uid)=="string"then S.Records[r.Uid]=r end
                        end
                    end
                end,S.RC)
            elseif d.Name=="RE/EggWorld/FieldEggCarry"then
                con(d.OnClientEvent,function(p)
                    if typeof(p)=="table"and p.IsCarrying==true and type(p.Uid)=="string"then
                        local raw=S.Records[p.Uid]
                        S.Samples[#S.Samples+1]={
                            unix=os.time(),clock=os.clock(),uid=p.Uid,
                            serverMultiplier=tonumber(p.SpeedMultiplier),
                            payload=ser(p),egg=eggSummary(raw),
                        }
                    end
                end,S.RC)
            end
        end
    end
end

local function build()
    local sh=RS:FindFirstChild("Shared")
    local u=sh and sh:FindFirstChild("Util")
    EggRecords=req(u and u:FindFirstChild("EggRecords"))
    local n=snapshots()
    local moduleScan=scanModules()
    local gcScan=scanGC()
    S.CandidateModules=moduleScan.moduleHits or{}
    S.CandidateFunctions=gcScan.hits or{}
    S.SourceHits=moduleScan.sourceHits or{}
    S.Report={
        Meta={
            Version="CarryMultiplierScannerV12",
            PlaceId=game.PlaceId,GameId=game.GameId,JobId=game.JobId,
            StartedUnix=os.time(),
            Goal="Resolve SpeedMultiplier before pickup from client-visible data/code.",
            Passive=true,
        },
        SnapshotRecordCount=n,
        CurrentEggs=currentEggs(),
        ModuleScan=moduleScan,
        GCScan=gcScan,
        ObservedSamples=S.Samples,
        Empirical=empirical(),
    }
    return S.Report
end

local function finish()
    local r=S.Report or build()
    r.CurrentEggsAtExport=currentEggs()
    r.ObservedSamples=S.Samples
    r.Empirical=empirical()
    r.Summary={
        Records=(function()local n=0 for _ in pairs(S.Records)do n=n+1 end return n end)(),
        CurrentEggs=#r.CurrentEggsAtExport,
        Samples=#S.Samples,
        ModuleHits=#S.CandidateModules,
        FunctionHits=#S.CandidateFunctions,
        SourceHits=#S.SourceHits,
        DecompileAvailable=r.ModuleScan and r.ModuleScan.decompileAvailable or false,
    }
    r.Meta.FinishedUnix=os.time()
    return r
end

local function export()
    local ok,j=pcall(function()return Http:JSONEncode(finish())end)
    if not ok then return false,"JSONEncode: "..str(j)end
    local f="Psico_RoubeUmOvo_CarryMultiplier_"..os.time()..".json"
    if type(writefile)=="function"then
        local a,e=pcall(writefile,f,j)
        return a,a and f or str(e)
    end
    if type(setclipboard)=="function"then
        local a,e=pcall(setclipboard,j)
        return a,a and"JSON copiado"or str(e)
    end
    return false,"sem writefile/setclipboard"
end

local function corner(o,r)local c=Instance.new("UICorner")c.CornerRadius=UDim.new(0,r or 9)c.Parent=o end
local function label(p,t,y,h,z)
    local l=Instance.new("TextLabel")
    l.BackgroundTransparency=1;l.Position=UDim2.fromOffset(12,y);l.Size=UDim2.new(1,-24,0,h)
    l.Text=t;l.TextColor3=Color3.fromRGB(198,210,232);l.TextSize=z or 10
    l.Font=Enum.Font.Gotham;l.TextWrapped=true;l.TextXAlignment=Enum.TextXAlignment.Left;l.Parent=p
    return l
end
local function button(p,t,y)
    local b=Instance.new("TextButton")
    b.Size=UDim2.new(1,-24,0,31);b.Position=UDim2.new(0,12,1,y)
    b.BackgroundColor3=Color3.fromRGB(31,43,66);b.BorderSizePixel=0
    b.Text=t;b.TextColor3=Color3.fromRGB(240,245,255);b.TextSize=11;b.Font=Enum.Font.GothamMedium;b.Parent=p
    corner(b);return b
end

for _,n in ipairs({"PsicoCarryGuardScannerV10","PsicoCarryGuardScannerV11","PsicoCarryMultiplierScannerV12"})do
    local x=pg():FindFirstChild(n);if x then pcall(function()x:Destroy()end)end
end
local gui=Instance.new("ScreenGui")
gui.Name="PsicoCarryMultiplierScannerV12";gui.ResetOnSpawn=false;gui.IgnoreGuiInset=true;gui.Parent=pg();S.Gui=gui
local vp=Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize or Vector2.new(844,390)
local W=math.floor(math.clamp(vp.X*.39,294,350));local H=math.floor(math.min(244,vp.Y*.70))
local f=Instance.new("Frame")
f.AnchorPoint=Vector2.new(.5,.5);f.Position=UDim2.fromScale(.5,.5);f.Size=UDim2.fromOffset(W,H)
f.BackgroundColor3=Color3.fromRGB(14,20,32);f.BorderSizePixel=0;f.Parent=gui;corner(f,13)
local title=label(f,"CARRY MULTIPLIER SCAN V12",8,20,14);title.Font=Enum.Font.GothamBold;title.TextColor3=Color3.fromRGB(242,246,255)
local sub=label(f,"pré-pickup • fórmula • código cliente",28,16,9);sub.TextColor3=Color3.fromRGB(102,148,232)
local status=label(f,"Preparando leitura...",52,92,10)
local res=button(f,"REFAZER LEITURA", -81)
local ex=button(f,"EXPORTAR JSON", -43)
local close=Instance.new("TextButton")
close.Size=UDim2.fromOffset(28,28);close.Position=UDim2.new(1,-38,0,8);close.Text="×";close.TextColor3=Color3.new(1,1,1)
close.BackgroundColor3=Color3.fromRGB(31,43,66);close.BorderSizePixel=0;close.Parent=f;corner(close)

local function st(extra)
    local r=S.Report
    local ms=r and r.ModuleScan
    status.Text="Amostras reais: "..#S.Samples
        .."\nDecompile: "..((ms and ms.decompileAvailable)and"SIM"or"NÃO")
        .." • módulos: "..#S.CandidateModules.." • funções: "..#S.CandidateFunctions
        .."\nO scanner tenta localizar a fórmula sem pegar ovo."
        ..(#S.Samples<3 and"\nOpcional: pegue 2-3 ovos bem diferentes para validar."or"")
        ..(extra and("\n"..extra)or"")
end

con(res.MouseButton1Click,function()
    status.Text="Lendo módulos/funções..."
    task.defer(function()
        local ok,e=pcall(build)
        if ok then
            S.Report.Summary={
                Records=(function()local n=0 for _ in pairs(S.Records)do n=n+1 end return n end)(),
                CurrentEggs=#currentEggs(),Samples=#S.Samples,ModuleHits=#S.CandidateModules,
                FunctionHits=#S.CandidateFunctions,SourceHits=#S.SourceHits,
                DecompileAvailable=S.Report.ModuleScan and S.Report.ModuleScan.decompileAvailable or false,
            }
            st("leitura refeita")
        else st("erro: "..str(e))end
    end)
end)
con(ex.MouseButton1Click,function()
    ex.Text="EXPORTANDO..."
    task.defer(function()
        local ok,m=export()
        ex.Text=ok and"EXPORTADO ✓"or"FALHOU";st(m)
        task.wait(1.6);if S.Alive then ex.Text="EXPORTAR JSON"end
    end)
end)

local dragging,di,ds,fp=false,nil,nil,nil
con(f.InputBegan,function(i)
    if i.UserInputType==Enum.UserInputType.Touch or i.UserInputType==Enum.UserInputType.MouseButton1 then
        dragging=true;ds=i.Position;fp=f.Position
    end
end)
con(f.InputChanged,function(i)
    if i.UserInputType==Enum.UserInputType.Touch or i.UserInputType==Enum.UserInputType.MouseMovement then di=i end
end)
con(UIS.InputChanged,function(i)
    if dragging and i==di then
        local d=i.Position-ds
        f.Position=UDim2.new(fp.X.Scale,fp.X.Offset+d.X,fp.Y.Scale,fp.Y.Offset+d.Y)
    end
end)
con(UIS.InputEnded,function(i)
    if i.UserInputType==Enum.UserInputType.Touch or i.UserInputType==Enum.UserInputType.MouseButton1 then dragging=false end
end)

local function cleanup()
    if not S.Alive then return end
    S.Alive=false
    for _,c in ipairs(S.RC)do pcall(function()c:Disconnect()end)end
    for _,c in ipairs(S.C)do pcall(function()c:Disconnect()end)end
    _G.PSICO_ROUBE_SCANNER_CLEANUP=nil
    pcall(function()gui:Destroy()end)
end
_G.PSICO_ROUBE_SCANNER_CLEANUP=cleanup
con(close.MouseButton1Click,cleanup)
hookCarry()

task.defer(function()
    task.wait(.35)
    if S.Alive then
        status.Text="Lendo módulos/funções..."
        local ok,e=pcall(build)
        if ok then
            S.Report.Summary={
                Records=(function()local n=0 for _ in pairs(S.Records)do n=n+1 end return n end)(),
                CurrentEggs=#currentEggs(),Samples=#S.Samples,ModuleHits=#S.CandidateModules,
                FunctionHits=#S.CandidateFunctions,SourceHits=#S.SourceHits,
                DecompileAvailable=S.Report.ModuleScan and S.Report.ModuleScan.decompileAvailable or false,
            }
            st("leitura pronta")
        else st("erro: "..str(e))end
    end
end)

task.defer(function()
    while S.Alive do
        task.wait(.5)
        if S.Report then st()end
    end
end)

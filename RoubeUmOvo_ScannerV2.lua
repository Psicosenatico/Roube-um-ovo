--[[
PSICOSENATICO | Roube um Ovo - Carry Formula Scanner V13
Foco: descobrir o caminho EXATO usado no cliente para aplicar/interpretar o SpeedMultiplier
(e a logica de risco/escape do guardiao), antes de integrar ao menu.

PASSIVO:
- nao altera WalkSpeed
- nao altera ovos/guardioes
- nao dispara remotes de compra/combate
- apenas le modulos/scripts, snapshots e eventos que o cliente ja recebe
]]

if _G.PSICO_ROUBE_SCANNER_CLEANUP then pcall(_G.PSICO_ROUBE_SCANNER_CLEANUP) end

local Players=game:GetService("Players")
local Workspace=game:GetService("Workspace")
local RS=game:GetService("ReplicatedStorage")
local CoreGui=game:GetService("CoreGui")
local Http=game:GetService("HttpService")
local UIS=game:GetService("UserInputService")
local LP=Players.LocalPlayer

local S={Alive=true,C={},RC={},Records={},Samples={},Report=nil,Gui=nil}
local EggRecords=nil

local KEYWORDS={
    "speedmultiplier","setslowdowntolerance","resolveslowdowntolerance",
    "carrychanged","walkspeedgovernor","resolveplayerwalkspeedrequirement",
    "resolvegreenplayerwalkspeedrequirement","resolvecatchduration",
    "requiredspeedpower","slowdowntolerance","baseguardwalkspeed",
    "carryfieldegg","iscarryingareaegg","areaeggcarrystate",
    "runbackwakedelayrequired","guarddisabled","boundsSize","nestscale",
}

local function finite(v)return type(v)=="number"and v==v and v~=math.huge and v~=-math.huge end
local function s(v)local ok,x=pcall(tostring,v)return ok and x or"?"end
local function low(v)return string.lower(s(v or""))end
local function containsAny(v)
    local q=low(v)
    for _,k in ipairs(KEYWORDS)do if string.find(q,string.lower(k),1,true)then return true,k end end
    return false
end
local function con(sig,fn,b)local c=sig:Connect(fn)table.insert(b or S.C,c)return c end
local function pg()local ok,h=pcall(function()if gethui then return gethui()end end)return(ok and h)or CoreGui end
local function req(m)if not(m and m:IsA("ModuleScript"))then return nil end local ok,v=pcall(require,m)return ok and v or nil end
local function childPath(root,p)local cur=root for token in string.gmatch(p,"[^%.]+")do if not cur then return nil end cur=cur:FindFirstChild(token)end return cur end

local function ser(v,d,seen)
    d=d or 0;seen=seen or{}
    if d>6 then return"<depth>"end
    local t=typeof(v)
    if t=="nil"or t=="boolean"or t=="string"then return v end
    if t=="number"then return finite(v)and v or s(v)end
    if t=="Vector3"then return{x=v.X,y=v.Y,z=v.Z,magnitude=v.Magnitude}end
    if t=="CFrame"then return{position=ser(v.Position)}end
    if t=="Color3"then return{r=v.R,g=v.G,b=v.B}end
    if t=="Instance"then return{class=v.ClassName,name=v.Name,path=v:GetFullName()}end
    if t=="function"then return"<function> "..s(v)end
    if t~="table"then return s(v)end
    if seen[v]then return"<cycle>"end
    seen[v]=true
    local o,n={},0
    for k,x in pairs(v)do
        n=n+1;if n>260 then o.__truncated=true break end
        local kk=(type(k)=="string"or type(k)=="number")and k or s(k)
        o[kk]=ser(x,d+1,seen)
    end
    seen[v]=nil
    return o
end

local function findExact(class,name)
    for _,d in ipairs(RS:GetDescendants())do if d.ClassName==class and d.Name==name then return d end end
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
    local bs=typeof(r.BoundsSize)=="Vector3"and r.BoundsSize or nil
    return{
        Uid=r.Uid,State=r.State,AreaId=r.AreaId,NestId=r.NestId,
        AssetCategory=r.AssetCategory,AssetScale=r.AssetScale,NestScale=r.NestScale,
        BaseMutation=r.BaseMutation,Mutations=ser(r.Mutations),HasParasite=r.HasParasite,
        WeightKg=(wok and finite(w))and w or nil,
        BoundsSize=bs and ser(bs)or nil,
        BoundsMagnitude=bs and bs.Magnitude or nil,
    }
end
local function ingest(v,seen,d)
    if typeof(v)~="table"then return 0 end
    seen=seen or{};d=d or 0;if d>8 or seen[v]then return 0 end
    seen[v]=true
    local n=0
    if type(v.Uid)=="string"and v.State~=nil then S.Records[v.Uid]=v;n=1 else
        local c=0
        for _,x in pairs(v)do c=c+1;if c>3500 then break end;if typeof(x)=="table"then n=n+ingest(x,seen,d+1)end end
    end
    seen[v]=nil;return n
end
local function snapshots()
    local n=0
    for _,name in ipairs({"RF/EggWorld/AskFieldEggSnapshot","RF/EggWorld/AskLiveSnapshot"})do
        local rf=findExact("RemoteFunction",name)
        if rf then local ok,v=pcall(function()return rf:InvokeServer()end)if ok then n=n+ingest(v)end end
    end
    return n
end
local function currentEggs()
    local out={}
    for _,r in pairs(S.Records)do if r.State=="Slot"or r.State=="Dropped"then out[#out+1]=eggSummary(r)end end
    table.sort(out,function(a,b)return(a.BoundsMagnitude or 0)<(b.BoundsMagnitude or 0)end)
    return out
end

local function fnmeta(fn,deep)
    if type(fn)~="function"then return nil end
    local o={repr=s(fn)}
    pcall(function()
        if debug and debug.info then
            o.name=debug.info(fn,"n");o.source=debug.info(fn,"s")
            local a,var=debug.info(fn,"a");o.arity=a;o.variadic=var
        elseif debug and debug.getinfo then
            local i=debug.getinfo(fn);if i then o.name=i.name;o.source=i.source;o.arity=i.nparams;o.variadic=i.isvararg end
        end
    end)
    pcall(function()
        if type(getconstants)=="function"then
            local all=getconstants(fn);local rel={}
            for i,v in pairs(all)do
                if type(v)=="string"then
                    if containsAny(v)then rel[i]=v end
                elseif type(v)=="number"and v>=0 and v<=10 then rel[i]=v end
            end
            if next(rel)then o.constants=rel end
        end
    end)
    if deep then
        pcall(function()
            if type(getupvalues)=="function"then
                local ups=getupvalues(fn);local rel={}
                for k,v in pairs(ups)do
                    if type(v)=="string"and containsAny(v)then rel[k]=v
                    elseif type(v)=="number"and v>=0 and v<=10 then rel[k]=v
                    elseif typeof(v)=="table"then
                        local t={};local n=0
                        for kk,vv in pairs(v)do
                            if containsAny(kk)then t[s(kk)]=ser(vv,1,{}) n=n+1 end
                            if n>=25 then break end
                        end
                        if next(t)then rel[k]=t end
                    elseif typeof(v)=="Instance"then
                        local q=low(v:GetFullName())
                        if string.find(q,"guard",1,true)or string.find(q,"egg",1,true)or string.find(q,"walkspeed",1,true)then rel[k]=ser(v)end
                    end
                end
                if next(rel)then o.upvalues=rel end
            end
        end)
    end
    return o
end

local function snippets(src)
    local out,lo={},string.lower(src)
    for _,token0 in ipairs(KEYWORDS)do
        local token=string.lower(token0);local start=1
        while #out<90 do
            local a,b=string.find(lo,token,start,true);if not a then break end
            local l=math.max(1,a-950);local r=math.min(#src,b+1700)
            out[#out+1]={token=token0,snippet=string.sub(src,l,r)}
            start=b+1
        end
        if #out>=90 then break end
    end
    return out
end

local function targetInstances()
    local out,seen={},{}
    local function add(x)
        if x and not seen[x]and(x:IsA("ModuleScript")or x:IsA("LocalScript"))then seen[x]=true;out[#out+1]=x end
    end
    local exact={
        {RS,"Shared.Modules.GuardAreas.GuardEscapePrediction"},
        {RS,"Shared.Modules.GuardAreas.GuardEscapeRequirement"},
        {RS,"Shared.Modules.GuardAreas.GuardChasePolicy"},
        {RS,"Shared.Modules.GuardAreas.GuardComponent"},
        {RS,"Shared.Modules.GuardAreas.GuardEggRetrievalComponent"},
        {RS,"Shared.Utils.GuardEscape"},
        {RS,"Shared.Util.WalkSpeedGovernor"},
        {RS,"Shared.Util.TreadmillUtil"},
        {RS,"Client.EggState"},
        {RS,"Shared.Types.AreaEggs"},
    }
    for _,x in ipairs(exact)do add(childPath(x[1],x[2]))end
    local ps=LP:FindFirstChild("PlayerScripts")
    if ps then
        for _,x in ipairs(ps:GetDescendants())do
            if x:IsA("LocalScript")or x:IsA("ModuleScript")then
                local q=low(x:GetFullName())
                if string.find(q,"guardareas",1,true)or string.find(q,"walkspeed",1,true)or string.find(q,"eggstate",1,true)then add(x)end
            end
        end
    end
    return out
end

local function decompileTargets()
    local out={}
    local available=type(decompile)=="function"
    if not available then return{available=false,items=out}end
    local total=0
    for _,inst in ipairs(targetInstances())do
        local ok,src=pcall(decompile,inst)
        if ok and type(src)=="string"and#src>0 then
            local h=snippets(src)
            if #h>0 then
                out[#out+1]={path=inst:GetFullName(),class=inst.ClassName,length=#src,hits=h}
                total=total+#src
            end
        end
        if total>900000 then break end
    end
    return{available=true,totalSourceChars=total,items=out}
end

local function inspectModule(p)
    local m=childPath(RS,p);local v=req(m)
    if typeof(v)~="table"then return{path=p,loaded=false}end
    local funcs={}
    for k,f in pairs(v)do if type(f)=="function"then
        local q=low(k)
        if string.find(q,"slow",1,true)or string.find(q,"speed",1,true)or string.find(q,"walk",1,true)
            or string.find(q,"resolve",1,true)or string.find(q,"carry",1,true)or string.find(q,"catch",1,true)then
            funcs[s(k)]=fnmeta(f,true)
        end
    end end
    return{path=p,loaded=true,functions=funcs}
end

local function inspectCarrySignal()
    local m=childPath(RS,"Client.EggState");local E=req(m)
    local out={available=false,handlers={}}
    if typeof(E)~="table"then return out end
    local sig=E.CarryChanged;if typeof(sig)~="table"then return out end
    out.available=true
    local node=sig._handlerListHead;local n=0;local seen={}
    while typeof(node)=="table"and not seen[node]and n<40 do
        seen[node]=true;n=n+1
        local fn=rawget(node,"_fn")
        out.handlers[#out.handlers+1]={index=n,connected=rawget(node,"Connected"),fn=fnmeta(fn,true)}
        node=rawget(node,"_next")
    end
    out.count=#out.handlers
    return out
end

local function gcTargets()
    local out={}
    if type(getgc)~="function"then return{available=false,hits=out}end
    local ok,g=pcall(getgc,true);if not ok or type(g)~="table"then return{available=false,error=s(g),hits=out}end
    for _,v in ipairs(g)do if type(v)=="function"then
        local m=fnmeta(v,false);local q=low((m and m.source or"").." "..(m and m.name or""))
        local keep=string.find(q,"guardareas",1,true)or string.find(q,"walkspeedgovernor",1,true)or string.find(q,"guardescape",1,true)
        if not keep and m and m.constants then for _,c in pairs(m.constants)do if type(c)=="string"and containsAny(c)then keep=true break end end end
        if keep then out[#out+1]=fnmeta(v,true) end
        if #out>=260 then break end
    end end
    return{available=true,hits=out,count=#out}
end

local function empirical()
    local rows={}
    for _,x in ipairs(S.Samples)do if x.egg and finite(x.serverMultiplier)then
        rows[#rows+1]={
            multiplier=x.serverMultiplier,penalty=1-x.serverMultiplier,
            weight=x.egg.WeightKg,nestScale=x.egg.NestScale,assetScale=x.egg.AssetScale,
            boundsMagnitude=x.egg.BoundsMagnitude,areaId=x.egg.AreaId,assetCategory=x.egg.AssetCategory,
        }
    end end
    local function linear(field)
        local xs,ys={},{}
        for _,r in ipairs(rows)do if finite(r[field])then xs[#xs+1]=r[field];ys[#ys+1]=r.penalty end end
        if #xs<3 then return nil end
        local sx,sy,sxx,sxy=0,0,0,0
        for i=1,#xs do sx=sx+xs[i];sy=sy+ys[i];sxx=sxx+xs[i]^2;sxy=sxy+xs[i]*ys[i]end
        local n=#xs;local den=n*sxx-sx*sx;if math.abs(den)<1e-12 then return nil end
        local a=(n*sxy-sx*sy)/den;local b=(sy-a*sx)/n;local se=0
        for i=1,n do local e=(a*xs[i]+b)-ys[i];se=se+e*e end
        return{n=n,slope=a,intercept=b,rmse=math.sqrt(se/n)}
    end
    return{rows=rows,weight=linear("weight"),nestScale=linear("nestScale"),assetScale=linear("assetScale"),boundsMagnitude=linear("boundsMagnitude")}
end

local function hookEvents()
    for _,d in ipairs(RS:GetDescendants())do if d:IsA("RemoteEvent")then
        if d.Name=="RE/EggWorld/FieldEggShifted"then
            con(d.OnClientEvent,function(r)if typeof(r)=="table"and type(r.Uid)=="string"then S.Records[r.Uid]=r end end,S.RC)
        elseif d.Name=="RE/EggWorld/FieldEggBatchShifted"then
            con(d.OnClientEvent,function(p)if typeof(p)=="table"and typeof(p.UpdatedRecords)=="table"then for _,r in pairs(p.UpdatedRecords)do if typeof(r)=="table"and type(r.Uid)=="string"then S.Records[r.Uid]=r end end end end,S.RC)
        elseif d.Name=="RE/EggWorld/FieldEggCarry"then
            con(d.OnClientEvent,function(p)
                if typeof(p)=="table"and p.IsCarrying==true and type(p.Uid)=="string"then
                    local raw=S.Records[p.Uid]
                    S.Samples[#S.Samples+1]={unix=os.time(),uid=p.Uid,serverMultiplier=tonumber(p.SpeedMultiplier),payload=ser(p),egg=eggSummary(raw)}
                end
            end,S.RC)
        end
    end end
end

local MODULES={
    "Shared.Modules.GuardAreas.GuardEscapePrediction",
    "Shared.Modules.GuardAreas.GuardEscapeRequirement",
    "Shared.Modules.GuardAreas.GuardChasePolicy",
    "Shared.Utils.GuardEscape",
    "Shared.Util.WalkSpeedGovernor",
    "Shared.Util.TreadmillUtil",
}

local function build()
    local u=childPath(RS,"Shared.Util")
    EggRecords=req(u and u:FindFirstChild("EggRecords"))
    local n=snapshots()
    local mods={};for _,p in ipairs(MODULES)do mods[#mods+1]=inspectModule(p)end
    S.Report={
        Meta={Version="CarryFormulaScannerV13",PlaceId=game.PlaceId,GameId=game.GameId,JobId=game.JobId,StartedUnix=os.time(),Passive=true},
        SnapshotRecordCount=n,CurrentEggs=currentEggs(),ObservedSamples=S.Samples,
        CarrySignal=inspectCarrySignal(),Modules=mods,Decompiler=decompileTargets(),GC=gcTargets(),Empirical=empirical(),
    }
    return S.Report
end
local function finish()
    local r=S.Report or build();r.Meta.FinishedUnix=os.time();r.CurrentEggsAtExport=currentEggs();r.ObservedSamples=S.Samples;r.Empirical=empirical()
    r.Summary={Records=(function()local n=0 for _ in pairs(S.Records)do n=n+1 end return n end)(),Eggs=#r.CurrentEggsAtExport,Samples=#S.Samples,CarryHandlers=r.CarrySignal and r.CarrySignal.count or 0,Decompile=r.Decompiler and r.Decompiler.available or false,DecompiledItems=r.Decompiler and#r.Decompiler.items or 0,GCHits=r.GC and r.GC.count or 0}
    return r
end
local function export()
    local ok,j=pcall(function()return Http:JSONEncode(finish())end);if not ok then return false,"JSON: "..s(j)end
    local name="Psico_RoubeUmOvo_CarryFormula_"..os.time()..".json"
    if type(writefile)=="function"then local a,e=pcall(writefile,name,j)return a,a and name or s(e)end
    if type(setclipboard)=="function"then local a,e=pcall(setclipboard,j)return a,a and"JSON copiado"or s(e)end
    return false,"sem writefile/setclipboard"
end

local function corner(o,r)local c=Instance.new("UICorner")c.CornerRadius=UDim.new(0,r or 9)c.Parent=o end
local function lab(p,t,y,h,z)local l=Instance.new("TextLabel")l.BackgroundTransparency=1;l.Position=UDim2.fromOffset(12,y);l.Size=UDim2.new(1,-24,0,h);l.Text=t;l.TextColor3=Color3.fromRGB(202,213,233);l.TextSize=z or 10;l.Font=Enum.Font.Gotham;l.TextWrapped=true;l.TextXAlignment=Enum.TextXAlignment.Left;l.Parent=p;return l end
local function btn(p,t,y)local b=Instance.new("TextButton")b.Size=UDim2.new(1,-24,0,31);b.Position=UDim2.new(0,12,1,y);b.BackgroundColor3=Color3.fromRGB(31,43,66);b.BorderSizePixel=0;b.Text=t;b.TextColor3=Color3.fromRGB(242,246,255);b.TextSize=11;b.Font=Enum.Font.GothamMedium;b.Parent=p;corner(b);return b end

for _,n in ipairs({"PsicoCarryMultiplierScannerV12","PsicoCarryFormulaScannerV13"})do local x=pg():FindFirstChild(n)if x then pcall(function()x:Destroy()end)end end
local gui=Instance.new("ScreenGui")gui.Name="PsicoCarryFormulaScannerV13";gui.ResetOnSpawn=false;gui.IgnoreGuiInset=true;gui.Parent=pg();S.Gui=gui
local vp=Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize or Vector2.new(844,390)
local W=math.floor(math.clamp(vp.X*.39,300,355));local H=math.floor(math.min(252,vp.Y*.70))
local f=Instance.new("Frame")f.AnchorPoint=Vector2.new(.5,.5);f.Position=UDim2.fromScale(.5,.5);f.Size=UDim2.fromOffset(W,H);f.BackgroundColor3=Color3.fromRGB(14,20,32);f.BorderSizePixel=0;f.Parent=gui;corner(f,13)
local title=lab(f,"CARRY FORMULA SCAN V13",8,20,14);title.Font=Enum.Font.GothamBold;title.TextColor3=Color3.fromRGB(244,247,255)
local sub=lab(f,"handlers • slowdown • bounds • prediction",28,16,9);sub.TextColor3=Color3.fromRGB(101,149,233)
local status=lab(f,"Preparando leitura...",52,103,10)
local res=btn(f,"REFAZER LEITURA",-81);local ex=btn(f,"EXPORTAR JSON",-43)
local close=Instance.new("TextButton")close.Size=UDim2.fromOffset(28,28);close.Position=UDim2.new(1,-38,0,8);close.Text="×";close.TextColor3=Color3.new(1,1,1);close.BackgroundColor3=Color3.fromRGB(31,43,66);close.BorderSizePixel=0;close.Parent=f;corner(close)

local function st(extra)
    local r=S.Report;local sum=r and r.Summary
    if not sum and r then sum={CarryHandlers=r.CarrySignal and r.CarrySignal.count or 0,Decompile=r.Decompiler and r.Decompiler.available or false,DecompiledItems=r.Decompiler and#r.Decompiler.items or 0,GCHits=r.GC and r.GC.count or 0}end
    status.Text="Amostras: "..#S.Samples.." • handlers CarryChanged: "..tostring(sum and sum.CarryHandlers or 0)
        .."\nDecompile: "..tostring(sum and sum.Decompile and"SIM"or"NÃO").." • scripts úteis: "..tostring(sum and sum.DecompiledItems or 0)
        .." • GC: "..tostring(sum and sum.GCHits or 0)
        .."\nLeitura focada no slowdown/risco antes do pickup."
        ..(#S.Samples<2 and"\nOpcional: pegue 2 ovos bem diferentes para validar."or"")
        ..(extra and("\n"..extra)or"")
end
local function rebuild(msg)
    status.Text="Lendo handlers e scripts..."
    task.defer(function()local ok,e=pcall(build)if ok then local r=finish();S.Report=r;st(msg or"leitura pronta")else st("erro: "..s(e))end end)
end
con(res.MouseButton1Click,function()rebuild("leitura refeita")end)
con(ex.MouseButton1Click,function()ex.Text="EXPORTANDO...";task.defer(function()local ok,m=export();ex.Text=ok and"EXPORTADO ✓"or"FALHOU";st(m);task.wait(1.5);if S.Alive then ex.Text="EXPORTAR JSON"end end)end)

local dragging,di,ds,fp=false,nil,nil,nil
con(f.InputBegan,function(i)if i.UserInputType==Enum.UserInputType.Touch or i.UserInputType==Enum.UserInputType.MouseButton1 then dragging=true;ds=i.Position;fp=f.Position end end)
con(f.InputChanged,function(i)if i.UserInputType==Enum.UserInputType.Touch or i.UserInputType==Enum.UserInputType.MouseMovement then di=i end end)
con(UIS.InputChanged,function(i)if dragging and i==di then local d=i.Position-ds;f.Position=UDim2.new(fp.X.Scale,fp.X.Offset+d.X,fp.Y.Scale,fp.Y.Offset+d.Y)end end)
con(UIS.InputEnded,function(i)if i.UserInputType==Enum.UserInputType.Touch or i.UserInputType==Enum.UserInputType.MouseButton1 then dragging=false end end)

local function cleanup()
    if not S.Alive then return end;S.Alive=false
    for _,c in ipairs(S.RC)do pcall(function()c:Disconnect()end)end
    for _,c in ipairs(S.C)do pcall(function()c:Disconnect()end)end
    _G.PSICO_ROUBE_SCANNER_CLEANUP=nil;pcall(function()gui:Destroy()end)
end
_G.PSICO_ROUBE_SCANNER_CLEANUP=cleanup;con(close.MouseButton1Click,cleanup)
hookEvents();task.defer(function()task.wait(.35);if S.Alive then rebuild("leitura pronta")end end)
task.defer(function()while S.Alive do task.wait(.6);if S.Report then st()end end end)

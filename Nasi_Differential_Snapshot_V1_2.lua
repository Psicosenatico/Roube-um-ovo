--[[
PSICOSENATICO | NASI DIFFERENTIAL SNAPSHOT
Updated in-place: same GitHub file / same loadstring.
Zero-hook. Focused on BEFORE/AFTER state comparison, new ScreenGui trees,
and deeper snapshots of __STEALFIX / __UI / __UIX.
]]

if _G.PSICO_NASI_DIFF_CLEANUP then pcall(_G.PSICO_NASI_DIFF_CLEANUP) end

local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local LP = Players.LocalPlayer
local G = (getgenv and getgenv()) or _G
local START = os.clock()
local START_UNIX = os.time()

local CFG = {
    MaxUI = 1400,
    MaxFocusedUI = 3200,
    MaxGlobals = 900,
    MaxRelevant = 900,
    MaxAttrs = 30,
    MaxTableKeys = 70,
    MaxDeepKeys = 140,
    MaxText = 900,
    AutoSeconds = 12,
    AutoInterval = 2,
    MaxFiles = 600,
}

local KW = {"egg","rarity","rare","cycle","predict","spawn","field","lottery","eternal","divine","secret","mythic","cosmic","hour","time","nasi","nrl"}
local DEEP_GLOBALS = {__STEALFIX=true,__UI=true,__UIX=true}
local State = {alive=true,before=nil,after=nil,compare=nil,autoRuns={},autoRunning=false,gui=nil,status=nil}

local function now() return os.clock() - START end
local function safe(v) local ok,r = pcall(tostring,v); return ok and r or "?" end
local function cut(v,n) local s=safe(v); n=n or 180; return #s<=n and s or string.sub(s,1,n).."..." end
local function lower(v) return string.lower(safe(v)) end
local function interesting(v)
    local s=lower(v)
    for _,k in ipairs(KW) do if string.find(s,k,1,true) then return true end end
    return false
end
local function sensitive(k)
    k=lower(k)
    return k:find("token",1,true) or k:find("cookie",1,true) or k:find("password",1,true) or k:find("auth",1,true) or k:find("session",1,true) or k:find("key",1,true)
end
local function finite(n) return n==n and n~=math.huge and n~=-math.huge end

local function scalar(v)
    local t=typeof(v)
    if t=="string" then return cut(v,CFG.MaxText) end
    if t=="boolean" then return v end
    if t=="number" then return finite(v) and v or safe(v) end
    if t=="nil" then return nil end
    if t=="Instance" then local ok,p=pcall(function() return v:GetFullName() end); return ok and p or safe(v) end
    return safe(v)
end

local function pathOf(x)
    local ok,r=pcall(function() return x:GetFullName() end)
    return ok and r or safe(x)
end

local function attrsOf(x)
    local out={}
    local ok,a=pcall(function() return x:GetAttributes() end)
    if not ok or type(a)~="table" then return out end
    local n=0
    for k,v in pairs(a) do
        n+=1; if n>CFG.MaxAttrs then break end
        local t=typeof(v)
        if t=="string" or t=="number" or t=="boolean" then out[safe(k)]=scalar(v) end
    end
    return out
end

local function prop(out,name,fn)
    local ok,v=pcall(fn)
    if ok then out[name]=scalar(v) end
end

local function describeUI(x)
    local d={class=x.ClassName,name=cut(x.Name,180),attrs=attrsOf(x)}
    if x:IsA("GuiObject") then
        prop(d,"Visible",function() return x.Visible end)
        prop(d,"Position",function() return x.Position end)
        prop(d,"Size",function() return x.Size end)
        prop(d,"AbsolutePosition",function() return x.AbsolutePosition end)
        prop(d,"AbsoluteSize",function() return x.AbsoluteSize end)
        prop(d,"ZIndex",function() return x.ZIndex end)
        prop(d,"LayoutOrder",function() return x.LayoutOrder end)
    end
    if x:IsA("TextLabel") or x:IsA("TextButton") or x:IsA("TextBox") then
        prop(d,"Text",function() return x.Text end)
        prop(d,"TextSize",function() return x.TextSize end)
    end
    if x:IsA("ScreenGui") then
        prop(d,"Enabled",function() return x.Enabled end)
        prop(d,"DisplayOrder",function() return x.DisplayOrder end)
    end
    return d
end

local function uiRoots()
    local r,seen={},{}
    local function add(x) if x and not seen[x] then seen[x]=true; r[#r+1]=x end end
    local ok,h=pcall(function() return gethui and gethui() end)
    if ok then add(h) end
    add(CoreGui)
    add(LP and LP:FindFirstChildOfClass("PlayerGui"))
    return r
end

local function screenGuis()
    local out={}
    for _,root in ipairs(uiRoots()) do
        local ok,list=pcall(function() return root:GetChildren() end)
        if ok then
            for _,x in ipairs(list) do
                if x:IsA("ScreenGui") then out[pathOf(x)] = describeUI(x) end
            end
        end
    end
    return out
end

local function captureUI()
    local map={}; local count=0
    for _,root in ipairs(uiRoots()) do
        local ok,list=pcall(function() return root:GetDescendants() end)
        if ok then
            for _,x in ipairs(list) do
                if count>=CFG.MaxUI then break end
                if x:IsA("GuiObject") or x:IsA("ScreenGui") or x:IsA("UIListLayout") or x:IsA("UIGridLayout") or x:IsA("UICorner") then
                    map[pathOf(x)] = describeUI(x); count+=1
                end
            end
        end
        if count>=CFG.MaxUI then break end
    end
    return map
end

local function captureTree(root,maxNodes)
    local out={}; if not root then return out end
    local function add(x)
        if #out>=maxNodes then return false end
        out[#out+1]={path=pathOf(x),data=describeUI(x)}
        return true
    end
    add(root)
    local ok,list=pcall(function() return root:GetDescendants() end)
    if ok then
        for _,x in ipairs(list) do
            if #out>=maxNodes then break end
            if x:IsA("GuiObject") or x:IsA("ScreenGui") or x:IsA("UIListLayout") or x:IsA("UIGridLayout") or x:IsA("UICorner") or x:IsA("UIPadding") then add(x) end
        end
    end
    return out
end

local function compact(v,depth,maxDepth,maxKeys,seen)
    depth=depth or 0; maxDepth=maxDepth or 1; maxKeys=maxKeys or CFG.MaxTableKeys
    local t=typeof(v)
    if t=="string" or t=="number" or t=="boolean" then return {type=t,value=scalar(v)} end
    if t=="Instance" then return {type=t,path=pathOf(v),class=v.ClassName} end
    if t~="table" then return {type=t} end
    seen=seen or {}
    if seen[v] then return {type="table",cycle=true} end
    seen[v]=true
    local out={type="table",keys={}}; local n=0
    for k,x in pairs(v) do
        n+=1; if n>maxKeys then out.truncated=true; break end
        local ks=cut(k,140)
        if not sensitive(ks) then
            local xt=typeof(x)
            if depth<maxDepth and (xt=="table" or xt=="string" or xt=="number" or xt=="boolean" or xt=="Instance") then
                out.keys[ks]=compact(x,depth+1,maxDepth,maxKeys,seen)
            else
                out.keys[ks]={type=xt}
            end
        end
    end
    out.count=n; seen[v]=nil; return out
end

local function captureGlobals()
    local out={}; local count=0
    local function add(tbl,prefix)
        if type(tbl)~="table" then return end
        for k,v in pairs(tbl) do
            count+=1; if count>CFG.MaxGlobals then return end
            local raw=safe(k); local ks=prefix..raw
            if not sensitive(ks) then
                if DEEP_GLOBALS[raw] and type(v)=="table" then out[ks]=compact(v,0,2,CFG.MaxDeepKeys)
                else out[ks]=compact(v,0,1,CFG.MaxTableKeys) end
            end
        end
    end
    add(G,"G:")
    if G~=_G then add(_G,"_G:") end
    return out
end

local function findNasiGuiRefs()
    local refs={}
    local ui=rawget(G,"__UI")
    if type(ui)=="table" then
        for _,v in pairs(ui) do
            if typeof(v)=="Instance" and (v:IsA("ScreenGui") or v:IsDescendantOf(CoreGui) or (LP and LP:FindFirstChildOfClass("PlayerGui") and v:IsDescendantOf(LP.PlayerGui))) then
                refs[pathOf(v)] = v
            end
        end
    end
    return refs
end

local function captureFocusedUI(beforeScreens)
    local out={newScreenGuis={},referenced={}}
    local current=screenGuis()
    for p,_ in pairs(current) do
        if not (beforeScreens and beforeScreens[p]) then
            local found=nil
            for _,root in ipairs(uiRoots()) do
                local ok,list=pcall(function() return root:GetChildren() end)
                if ok then for _,x in ipairs(list) do if x:IsA("ScreenGui") and pathOf(x)==p then found=x; break end end end
                if found then break end
            end
            if found then out.newScreenGuis[p]=captureTree(found,CFG.MaxFocusedUI) end
        end
    end
    for p,x in pairs(findNasiGuiRefs()) do out.referenced[p]=captureTree(x,CFG.MaxFocusedUI) end
    return out
end

local function describeRelevant(x)
    local d={class=x.ClassName,name=cut(x.Name,180),attrs=attrsOf(x)}
    if x:IsA("ValueBase") then local ok,v=pcall(function() return x.Value end); if ok then d.value=scalar(v); d.valueType=typeof(v) end end
    return d
end

local function captureRelevant()
    local out={}; local count=0; local roots={RS}
    local pg=LP and LP:FindFirstChildOfClass("PlayerGui"); if pg then roots[#roots+1]=pg end
    for _,root in ipairs(roots) do
        local ok,list=pcall(function() return root:GetDescendants() end)
        if ok then
            for _,x in ipairs(list) do
                if count>=CFG.MaxRelevant then break end
                local p=pathOf(x)
                local useful=x:IsA("RemoteEvent") or x:IsA("RemoteFunction") or x:IsA("BindableEvent") or x:IsA("BindableFunction") or x:IsA("ModuleScript") or x:IsA("ValueBase")
                if useful and (interesting(p) or interesting(x.Name)) then count+=1; out[p]=describeRelevant(x) end
            end
        end
        if count>=CFG.MaxRelevant then break end
    end
    return out
end

local function captureFiles()
    local out={supported=false,items={}}
    if type(listfiles)~="function" then return out end
    out.supported=true
    local roots={"","workspace","Workspace"}; local seen={}; local count=0
    for _,root in ipairs(roots) do
        local ok,list=pcall(listfiles,root)
        if ok and type(list)=="table" then
            for _,p in ipairs(list) do
                if count>=CFG.MaxFiles then break end
                local s=safe(p)
                if not seen[s] then seen[s]=true; count+=1; out.items[s]={name=s} end
            end
        end
        if count>=CFG.MaxFiles then break end
    end
    return out
end

local function cycleHints()
    local out={PlaceId=game.PlaceId,GameId=game.GameId,JobId=game.JobId,unix=os.time()}
    local names={PeriodIndex=true,DayStartsAt=true,RareSpawns=true,FieldEggRaritiesShown=true}
    local ok,list=pcall(function() return RS:GetDescendants() end); if not ok then return out end
    for _,x in ipairs(list) do
        if names[x.Name] then
            out[x.Name]=out[x.Name] or {}
            if #out[x.Name]<12 then local r=describeRelevant(x); r.path=pathOf(x); out[x.Name][#out[x.Name]+1]=r end
        end
    end
    return out
end

local function snapshot(label,beforeScreens)
    local screens=screenGuis()
    return {label=label,t=now(),unix=os.time(),cycle=cycleHints(),screenGuis=screens,ui=captureUI(),globals=captureGlobals(),relevant=captureRelevant(),files=captureFiles(),focusedUI=captureFocusedUI(beforeScreens)}
end

local function stable(v,seen)
    local t=type(v); if t~="table" then return safe(v) end
    seen=seen or {}; if seen[v] then return "<cycle>" end; seen[v]=true
    local keys={}; for k in pairs(v) do keys[#keys+1]=safe(k) end; table.sort(keys)
    local parts={}
    for _,ks in ipairs(keys) do local found=nil; for k,val in pairs(v) do if safe(k)==ks then found=val; break end end; parts[#parts+1]=ks.."="..stable(found,seen) end
    seen[v]=nil; return "{"..table.concat(parts,"|").."}"
end

local function diffMap(a,b)
    a=a or {}; b=b or {}; local added,removed,changed={},{},{}
    for k,v in pairs(b) do if a[k]==nil then added[k]=v elseif stable(a[k])~=stable(v) then changed[k]={before=a[k],after=v} end end
    for k,v in pairs(a) do if b[k]==nil then removed[k]=v end end
    return {added=added,removed=removed,changed=changed}
end

local function diffSnap(a,b)
    return {from=a and a.label or nil,to=b and b.label or nil,t=b and b.t or now(),screenGuis=diffMap(a and a.screenGuis,b and b.screenGuis),ui=diffMap(a and a.ui,b and b.ui),globals=diffMap(a and a.globals,b and b.globals),relevant=diffMap(a and a.relevant,b and b.relevant),files=diffMap(a and a.files and a.files.items,b and b.files and b.files.items),cycleBefore=a and a.cycle or nil,cycleAfter=b and b.cycle or nil}
end

local function c(t) local n=0; for _ in pairs(t or {}) do n+=1 end; return n end
local function counts(d)
    return string.format("GUI +%d | UI +%d ~%d -%d | G +%d ~%d | Rel +%d ~%d | Files +%d",c(d.screenGuis.added),c(d.ui.added),c(d.ui.changed),c(d.ui.removed),c(d.globals.added),c(d.globals.changed),c(d.relevant.added),c(d.relevant.changed),c(d.files.added))
end
local function status(s) if State.status and State.status.Parent then State.status.Text=s end end

local function before()
    if State.autoRunning then return end
    status("Capturando ANTES...")
    task.defer(function() State.before=snapshot("before",nil); State.after=nil; State.compare=nil; State.autoRuns={}; status("ANTES capturado.\nSelecione Steal An Egg e espere carregar.\nDepois CAPTURAR DEPOIS.") end)
end

local function after()
    if State.autoRunning then return end
    if not State.before then status("Capture ANTES primeiro."); return end
    status("Capturando DEPOIS...")
    task.defer(function() State.after=snapshot("after",State.before.screenGuis); State.compare=diffSnap(State.before,State.after); status("DEPOIS capturado.\n"..counts(State.compare).."\nAgora EXPORTAR.") end)
end

local function auto()
    if State.autoRunning then return end
    State.autoRunning=true
    task.spawn(function()
        local run={started=os.time(),interval=CFG.AutoInterval,seconds=CFG.AutoSeconds,diffs={}}
        local prev=snapshot("auto_base",State.before and State.before.screenGuis or nil)
        status("ANALISE AUTOMATICA: 12s\nAbra/ative UMA opcao do Nasi agora.")
        for i=1,math.floor(CFG.AutoSeconds/CFG.AutoInterval) do
            task.wait(CFG.AutoInterval); if not State.alive then break end
            local cur=snapshot("auto_"..i,prev.screenGuis); local d=diffSnap(prev,cur); run.diffs[#run.diffs+1]=d; prev=cur
            status("ANALISE "..(i*CFG.AutoInterval).."/12s\n"..counts(d))
        end
        run.finished=os.time(); State.autoRuns[#State.autoRuns+1]=run; State.autoRunning=false; status("Analise concluida. Runs: "..#State.autoRuns.."\nPode EXPORTAR ou analisar outra opcao.")
    end)
end

local function report()
    return {Meta={Version="NasiDifferentialSnapshotV1.2-inplace-r2",StartedUnix=START_UNIX,FinishedUnix=os.time(),PlaceId=game.PlaceId,GameId=game.GameId,JobId=game.JobId,ZeroHook=true,FocusedUI=true,DeepGlobals=true,CustomJSON=true,AutoSeconds=CFG.AutoSeconds,AutoInterval=CFG.AutoInterval},Before=State.before,After=State.after,Comparison=State.compare,AutoRuns=State.autoRuns}
end

local function jesc(s)
    s=safe(s); local out={'"'}
    for i=1,#s do
        local b=string.byte(s,i)
        if b==34 then out[#out+1]='\\"' elseif b==92 then out[#out+1]='\\\\' elseif b==8 then out[#out+1]='\\b' elseif b==9 then out[#out+1]='\\t' elseif b==10 then out[#out+1]='\\n' elseif b==12 then out[#out+1]='\\f' elseif b==13 then out[#out+1]='\\r' elseif b>=32 and b<=126 then out[#out+1]=string.char(b) else out[#out+1]=string.format('\\u%04x',b) end
    end
    out[#out+1]='"'; return table.concat(out)
end

local function encode(v,seen)
    local t=type(v)
    if t=="nil" then return "null" end
    if t=="boolean" then return v and "true" or "false" end
    if t=="number" then return finite(v) and tostring(v) or jesc(safe(v)) end
    if t=="string" then return jesc(v) end
    if t~="table" then return jesc(safe(v)) end
    seen=seen or {}; if seen[v] then return jesc("<cycle>") end; seen[v]=true
    local isArray=true; local max=0; local count=0
    for k in pairs(v) do count+=1; if type(k)~="number" or k<1 or k%1~=0 then isArray=false; break end; if k>max then max=k end end
    local out={}
    if isArray and max==count then for i=1,max do out[#out+1]=encode(v[i],seen) end; seen[v]=nil; return "["..table.concat(out,",").."]" end
    for k,val in pairs(v) do out[#out+1]=jesc(safe(k))..":"..encode(val,seen) end
    table.sort(out); seen[v]=nil; return "{"..table.concat(out,",").."}"
end

local function export()
    if not State.before and #State.autoRuns==0 then status("Nada para exportar."); return end
    local ok,json=pcall(encode,report()); if not ok then status("Erro no encoder: "..cut(json,220)); return end
    local name="Psico_Nasi_Differential_V1_2_"..os.time()..".json"
    local wrote=false; if type(writefile)=="function" then wrote=pcall(writefile,name,json) end
    if type(setclipboard)=="function" then pcall(setclipboard,json) end
    status((wrote and "EXPORTADO: " or "JSON COPIADO: ")..name.."\n"..#json.." bytes | Runs: "..#State.autoRuns)
end

local function parentGui() local ok,h=pcall(function() return gethui and gethui() end); return (ok and h) or CoreGui end
local function btn(p,text,pos,size)
    local b=Instance.new("TextButton"); b.Position=pos; b.Size=size; b.BackgroundColor3=Color3.fromRGB(31,78,132); b.BorderSizePixel=0; b.Text=text; b.TextColor3=Color3.fromRGB(244,248,255); b.Font=Enum.Font.GothamBold; b.TextSize=11; b.Parent=p; Instance.new("UICorner",b).CornerRadius=UDim.new(0,9); return b
end

local function gui()
    local p=parentGui(); local old=p:FindFirstChild("PSICO_NASI_DIFF_V1_2"); if old then old:Destroy() end
    local sg=Instance.new("ScreenGui"); sg.Name="PSICO_NASI_DIFF_V1_2"; sg.ResetOnSpawn=false; sg.DisplayOrder=1200; sg.Parent=p; State.gui=sg
    local f=Instance.new("Frame"); f.AnchorPoint=Vector2.new(.5,.5); f.Position=UDim2.fromScale(.5,.5); f.Size=UDim2.fromOffset(455,300); f.BackgroundColor3=Color3.fromRGB(9,18,34); f.BorderSizePixel=0; f.Parent=sg; Instance.new("UICorner",f).CornerRadius=UDim.new(0,14)
    local t=Instance.new("TextLabel"); t.BackgroundTransparency=1; t.Position=UDim2.fromOffset(14,10); t.Size=UDim2.new(1,-28,0,28); t.Text="NASI DIFFERENTIAL SNAPSHOT • V1.2"; t.Font=Enum.Font.GothamBold; t.TextSize=14; t.TextColor3=Color3.fromRGB(238,245,255); t.TextXAlignment=Enum.TextXAlignment.Left; t.Parent=f
    local s=Instance.new("TextLabel"); s.Position=UDim2.fromOffset(14,48); s.Size=UDim2.new(1,-28,0,90); s.BackgroundColor3=Color3.fromRGB(15,29,52); s.BorderSizePixel=0; s.Text="Pronto. Comece com CAPTURAR ANTES."; s.Font=Enum.Font.Code; s.TextSize=11; s.TextColor3=Color3.fromRGB(215,229,247); s.TextWrapped=true; s.TextXAlignment=Enum.TextXAlignment.Left; s.TextYAlignment=Enum.TextYAlignment.Top; s.Parent=f; Instance.new("UICorner",s).CornerRadius=UDim.new(0,9); local pad=Instance.new("UIPadding",s); pad.PaddingLeft=UDim.new(0,8); pad.PaddingRight=UDim.new(0,8); pad.PaddingTop=UDim.new(0,7); State.status=s
    local b1=btn(f,"CAPTURAR ANTES",UDim2.fromOffset(14,150),UDim2.new(.5,-20,0,38)); local b2=btn(f,"CAPTURAR DEPOIS",UDim2.new(.5,6,0,150),UDim2.new(.5,-20,0,38)); local b3=btn(f,"INICIAR ANALISE COMPLETA",UDim2.fromOffset(14,198),UDim2.new(1,-28,0,38)); local b4=btn(f,"EXPORTAR",UDim2.fromOffset(14,246),UDim2.new(.7,-20,0,36)); local close=btn(f,"FECHAR",UDim2.new(.7,6,0,246),UDim2.new(.3,-20,0,36))
    b1.MouseButton1Click:Connect(before); b2.MouseButton1Click:Connect(after); b3.MouseButton1Click:Connect(auto); b4.MouseButton1Click:Connect(export); close.MouseButton1Click:Connect(function() State.alive=false; if State.gui then State.gui:Destroy() end end)
    local dragging=false; local dragStart,startPos
    f.InputBegan:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then dragging=true; dragStart=i.Position; startPos=f.Position end end)
    f.InputChanged:Connect(function(i) if dragging and (i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch) then local d=i.Position-dragStart; f.Position=UDim2.new(startPos.X.Scale,startPos.X.Offset+d.X,startPos.Y.Scale,startPos.Y.Offset+d.Y) end end)
    UIS.InputEnded:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then dragging=false end end)
end

_G.PSICO_NASI_DIFF_CLEANUP=function() State.alive=false; if State.gui then pcall(function() State.gui:Destroy() end) end end

gui()

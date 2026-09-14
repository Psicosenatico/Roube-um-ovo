--[[ PSICOSENATICO | NASI DIFFERENTIAL SNAPSHOT V1.1
Zero-hook. Corrige exportacao JSON convertendo todos os valores para tipos JSON-safe.
Fluxo: CAPTURAR ANTES -> carregar Steal An Egg -> CAPTURAR DEPOIS -> EXPORTAR.
ANALISE COMPLETA e opcional: 12s / 2s, guarda apenas diferencas.
]]
if _G.PSICO_NASI_DIFF_CLEANUP then pcall(_G.PSICO_NASI_DIFF_CLEANUP) end
local Players=game:GetService("Players")
local HttpService=game:GetService("HttpService")
local CoreGui=game:GetService("CoreGui")
local RS=game:GetService("ReplicatedStorage")
local UIS=game:GetService("UserInputService")
local LP=Players.LocalPlayer
local G=(getgenv and getgenv()) or _G
local START=os.clock(); local START_UNIX=os.time()
local CFG={MaxUI=1600,MaxGlobals=800,MaxRelevant=800,MaxAttrs=25,MaxTableKeys=25,MaxText=600,AutoSeconds=12,AutoInterval=2}
local KW={"egg","rarity","rare","cycle","predict","spawn","field","lottery","eternal","divine","secret","mythic","cosmic","hour","time"}
local State={alive=true,before=nil,after=nil,compare=nil,autoRuns={},autoRunning=false,gui=nil,status=nil}
local function now() return os.clock()-START end
local function safe(v)local ok,r=pcall(tostring,v);return ok and r or "?" end
local function cut(v,n)local s=safe(v);n=n or 180;return #s<=n and s or string.sub(s,1,n).."..." end
local function lower(v)return string.lower(safe(v)) end
local function interesting(v)local s=lower(v);for _,k in ipairs(KW) do if string.find(s,k,1,true) then return true end end;return false end
local function sensitive(k)k=lower(k);return k:find("token",1,true) or k:find("cookie",1,true) or k:find("password",1,true) or k:find("auth",1,true) or k:find("session",1,true) end
local function finite(n)return n==n and n~=math.huge and n~=-math.huge end
local function jsonScalar(v)
 local t=typeof(v)
 if t=="string" then return cut(v,CFG.MaxText) end
 if t=="boolean" then return v end
 if t=="number" then return finite(v) and v or safe(v) end
 if t=="nil" then return nil end
 if t=="Instance" then local ok,p=pcall(function()return v:GetFullName() end);return ok and p or safe(v) end
 return safe(v)
end
local function pathOf(x)local ok,r=pcall(function()return x:GetFullName() end);return ok and r or safe(x) end
local function attrsOf(x)
 local out={};local ok,a=pcall(function()return x:GetAttributes() end);if not ok or type(a)~="table" then return out end
 local n=0;for k,v in pairs(a) do n+=1;if n>CFG.MaxAttrs then break end;local t=typeof(v);if t=="string" or t=="number" or t=="boolean" then out[safe(k)]=jsonScalar(v) end end;return out
end
local function prop(out,x,name,fn)local ok,v=pcall(fn);if ok then out[name]=jsonScalar(v) end end
local function describeUI(x)
 local d={class=x.ClassName,name=cut(x.Name,160),attrs=attrsOf(x)}
 if x:IsA("GuiObject") then prop(d,x,"Visible",function()return x.Visible end);prop(d,x,"Position",function()return x.Position end);prop(d,x,"Size",function()return x.Size end);prop(d,x,"ZIndex",function()return x.ZIndex end) end
 if x:IsA("TextLabel") or x:IsA("TextButton") or x:IsA("TextBox") then prop(d,x,"Text",function()return x.Text end) end
 if x:IsA("ScreenGui") then prop(d,x,"Enabled",function()return x.Enabled end) end
 return d
end
local function uiRoots()
 local r,seen={},{};local function add(x)if x and not seen[x] then seen[x]=true;r[#r+1]=x end end
 local ok,h=pcall(function()return gethui and gethui() end);if ok then add(h) end;add(CoreGui);add(LP and LP:FindFirstChildOfClass("PlayerGui"));return r
end
local function captureUI()
 local map={};local count=0
 for _,root in ipairs(uiRoots()) do local ok,list=pcall(function()return root:GetDescendants() end);if ok then for _,x in ipairs(list) do if count>=CFG.MaxUI then break end;if x:IsA("GuiObject") or x:IsA("ScreenGui") or x:IsA("UIListLayout") or x:IsA("UIGridLayout") or x:IsA("UICorner") then map[pathOf(x)]=describeUI(x);count+=1 end end end;if count>=CFG.MaxUI then break end end
 return map
end
local function compact(v,depth)
 depth=depth or 0;local t=typeof(v)
 if t=="string" or t=="number" or t=="boolean" then return {type=t,value=jsonScalar(v)} end
 if t=="Instance" then return {type=t,path=pathOf(v),class=v.ClassName} end
 if t=="table" then local out={type="table",keys={}};local n=0;for k,x in pairs(v) do n+=1;if n>CFG.MaxTableKeys then out.truncated=true;break end;local ks=cut(k,120);if not sensitive(ks) then local xt=typeof(x);if depth<1 and (xt=="string" or xt=="number" or xt=="boolean" or xt=="Instance") then out.keys[ks]=compact(x,depth+1) else out.keys[ks]={type=xt} end end end;out.count=n;return out end
 return {type=t}
end
local function captureGlobals()
 local out={};local count=0;local function add(tbl,prefix)if type(tbl)~="table" then return end;for k,v in pairs(tbl) do count+=1;if count>CFG.MaxGlobals then return end;local ks=prefix..safe(k);if not sensitive(ks) then out[ks]=compact(v,0) end end end
 add(G,"G:");if G~=_G then add(_G,"_G:") end;return out
end
local function describeRelevant(x)
 local d={class=x.ClassName,name=cut(x.Name,160),attrs=attrsOf(x)}
 if x:IsA("ValueBase") then local ok,v=pcall(function()return x.Value end);if ok then d.value=jsonScalar(v);d.valueType=typeof(v) end end
 return d
end
local function captureRelevant()
 local out={};local count=0;local roots={RS};local pg=LP and LP:FindFirstChildOfClass("PlayerGui");if pg then roots[#roots+1]=pg end
 for _,root in ipairs(roots) do local ok,list=pcall(function()return root:GetDescendants() end);if ok then for _,x in ipairs(list) do if count>=CFG.MaxRelevant then break end;local p=pathOf(x);local useful=x:IsA("RemoteEvent") or x:IsA("RemoteFunction") or x:IsA("BindableEvent") or x:IsA("BindableFunction") or x:IsA("ModuleScript") or x:IsA("ValueBase");if useful and (interesting(p) or interesting(x.Name)) then count+=1;out[p]=describeRelevant(x) end end end;if count>=CFG.MaxRelevant then break end end;return out
end
local function cycleHints()
 local out={PlaceId=game.PlaceId,GameId=game.GameId,JobId=game.JobId,unix=os.time()};local names={PeriodIndex=true,DayStartsAt=true,RareSpawns=true,FieldEggRaritiesShown=true};local ok,list=pcall(function()return RS:GetDescendants() end);if not ok then return out end
 for _,x in ipairs(list) do if names[x.Name] then out[x.Name]=out[x.Name] or {};if #out[x.Name]<10 then out[x.Name][#out[x.Name]+1]=describeRelevant(x);out[x.Name][#out[x.Name]].path=pathOf(x) end end end;return out
end
local function snapshot(label)return {label=label,t=now(),unix=os.time(),cycle=cycleHints(),ui=captureUI(),globals=captureGlobals(),relevant=captureRelevant()} end
local function enc(v)local ok,s=pcall(HttpService.JSONEncode,HttpService,v);return ok and s or safe(v) end
local function diffMap(a,b)
 a=a or {};b=b or {};local added,removed,changed={},{},{}
 for k,v in pairs(b) do if a[k]==nil then added[k]=v elseif enc(a[k])~=enc(v) then changed[k]={before=a[k],after=v} end end
 for k,v in pairs(a) do if b[k]==nil then removed[k]=v end end;return {added=added,removed=removed,changed=changed}
end
local function diffSnap(a,b)return {from=a and a.label or nil,to=b and b.label or nil,t=b and b.t or now(),ui=diffMap(a and a.ui,b and b.ui),globals=diffMap(a and a.globals,b and b.globals),relevant=diffMap(a and a.relevant,b and b.relevant),cycleBefore=a and a.cycle or nil,cycleAfter=b and b.cycle or nil} end
local function c(t)local n=0;for _ in pairs(t or {}) do n+=1 end;return n end
local function counts(d)return string.format("UI +%d ~%d -%d | G +%d ~%d | Rel +%d ~%d",c(d.ui.added),c(d.ui.changed),c(d.ui.removed),c(d.globals.added),c(d.globals.changed),c(d.relevant.added),c(d.relevant.changed)) end
local function status(s)if State.status and State.status.Parent then State.status.Text=s end end
local function before()if State.autoRunning then return end;status("Capturando ANTES...");task.defer(function()State.before=snapshot("before");State.after=nil;State.compare=nil;State.autoRuns={};status("ANTES capturado.\nSelecione Steal An Egg e espere carregar.\nDepois CAPTURAR DEPOIS.") end) end
local function after()if State.autoRunning then return end;if not State.before then status("Capture ANTES primeiro.");return end;status("Capturando DEPOIS...");task.defer(function()State.after=snapshot("after");State.compare=diffSnap(State.before,State.after);status("DEPOIS capturado.\n"..counts(State.compare).."\nAgora EXPORTAR.") end) end
local function auto()
 if State.autoRunning then return end;State.autoRunning=true
 task.spawn(function()local run={started=os.time(),interval=CFG.AutoInterval,seconds=CFG.AutoSeconds,diffs={}};local prev=snapshot("auto_base");status("ANALISE AUTOMATICA: 12s\nAbra/ative UMA opcao do Nasi agora.")
  for i=1,math.floor(CFG.AutoSeconds/CFG.AutoInterval) do task.wait(CFG.AutoInterval);if not State.alive then break end;local cur=snapshot("auto_"..i);local d=diffSnap(prev,cur);run.diffs[#run.diffs+1]=d;prev=cur;status("ANALISE "..(i*CFG.AutoInterval).."/12s\n"..counts(d)) end
  run.finished=os.time();State.autoRuns[#State.autoRuns+1]=run;State.autoRunning=false;status("Analise concluida. Runs: "..#State.autoRuns.."\nPode EXPORTAR ou analisar outra opcao.") end)
end
local function report()return {Meta={Version="NasiDifferentialSnapshotV1.1",StartedUnix=START_UNIX,FinishedUnix=os.time(),PlaceId=game.PlaceId,GameId=game.GameId,JobId=game.JobId,ZeroHook=true,JSONSafe=true,AutoSeconds=CFG.AutoSeconds,AutoInterval=CFG.AutoInterval},Before=State.before,After=State.after,Comparison=State.compare,AutoRuns=State.autoRuns} end
local function export()
 if not State.before and #State.autoRuns==0 then status("Nada para exportar.");return end
 local ok,json=pcall(HttpService.JSONEncode,HttpService,report());if not ok then status("Erro JSON V1.1: "..cut(json,220));return end
 local name="Psico_Nasi_Differential_V1_1_"..os.time()..".json";local wrote=false;if type(writefile)=="function" then wrote=pcall(writefile,name,json) end;if type(setclipboard)=="function" then pcall(setclipboard,json) end;status((wrote and "EXPORTADO: " or "JSON COPIADO: ")..name.."\n"..#json.." bytes | Runs: "..#State.autoRuns)
end
local function parentGui()local ok,h=pcall(function()return gethui and gethui() end);return (ok and h) or CoreGui end
local function btn(p,text,pos,size)local b=Instance.new("TextButton");b.Position=pos;b.Size=size;b.BackgroundColor3=Color3.fromRGB(31,78,132);b.BorderSizePixel=0;b.Text=text;b.TextColor3=Color3.fromRGB(244,248,255);b.Font=Enum.Font.GothamBold;b.TextSize=11;b.Parent=p;Instance.new("UICorner",b).CornerRadius=UDim.new(0,9);return b end
local function gui()
 local p=parentGui();local old=p:FindFirstChild("PSICO_NASI_DIFF_V1_1");if old then old:Destroy() end
 local sg=Instance.new("ScreenGui");sg.Name="PSICO_NASI_DIFF_V1_1";sg.ResetOnSpawn=false;sg.DisplayOrder=1200;sg.Parent=p;State.gui=sg
 local f=Instance.new("Frame");f.AnchorPoint=Vector2.new(.5,.5);f.Position=UDim2.fromScale(.5,.5);f.Size=UDim2.fromOffset(455,300);f.BackgroundColor3=Color3.fromRGB(9,18,34);f.BorderSizePixel=0;f.Parent=sg;Instance.new("UICorner",f).CornerRadius=UDim.new(0,14)
 local t=Instance.new("TextLabel");t.BackgroundTransparency=1;t.Position=UDim2.fromOffset(14,10);t.Size=UDim2.new(1,-28,0,28);t.Text="NASI DIFFERENTIAL SNAPSHOT • V1.1";t.Font=Enum.Font.GothamBold;t.TextSize=14;t.TextColor3=Color3.fromRGB(238,245,255);t.TextXAlignment=Enum.TextXAlignment.Left;t.Parent=f
 local s=Instance.new("TextLabel");s.Position=UDim2.fromOffset(14,48);s.Size=UDim2.new(1,-28,0,90);s.BackgroundColor3=Color3.fromRGB(15,29,52);s.BorderSizePixel=0;s.Text="Pronto. Comece com CAPTURAR ANTES.";s.Font=Enum.Font.Code;s.TextSize=11;s.TextColor3=Color3.fromRGB(215,229,247);s.TextWrapped=true;s.TextXAlignment=Enum.TextXAlignment.Left;s.TextYAlignment=Enum.TextYAlignment.Top;s.Parent=f;Instance.new("UICorner",s).CornerRadius=UDim.new(0,9);local pad=Instance.new("UIPadding",s);pad.PaddingLeft=UDim.new(0,8);pad.PaddingRight=UDim.new(0,8);pad.PaddingTop=UDim.new(0,7);State.status=s
 local b1=btn(f,"CAPTURAR ANTES",UDim2.fromOffset(14,150),UDim2.new(.5,-20,0,38));local b2=btn(f,"CAPTURAR DEPOIS",UDim2.new(.5,6,0,150),UDim2.new(.5,-20,0,38));local b3=btn(f,"INICIAR ANALISE COMPLETA",UDim2.fromOffset(14,198),UDim2.new(1,-28,0,38));local b4=btn(f,"EXPORTAR",UDim2.fromOffset(14,246),UDim2.new(.7,-20,0,36));local close=btn(f,"FECHAR",UDim2.new(.7,6,0,246),UDim2.new(.3,-20,0,36))
 b1.MouseButton1Click:Connect(before);b2.MouseButton1Click:Connect(after);b3.MouseButton1Click:Connect(auto);b4.MouseButton1Click:Connect(export);close.MouseButton1Click:Connect(function()State.alive=false;if State.gui then State.gui:Destroy() end end)
 local dragging=false;local dragStart,startPos;f.InputBegan:Connect(function(i)if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then dragging=true;dragStart=i.Position;startPos=f.Position end end);f.InputChanged:Connect(function(i)if dragging and (i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch) then local d=i.Position-dragStart;f.Position=UDim2.new(startPos.X.Scale,startPos.X.Offset+d.X,startPos.Y.Scale,startPos.Y.Offset+d.Y) end end);UIS.InputEnded:Connect(function(i)if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then dragging=false end end)
end
_G.PSICO_NASI_DIFF_CLEANUP=function()State.alive=false;if State.gui then pcall(function()State.gui:Destroy() end) end end
gui()
-- PSICOSENATICO | EGG CYCLE DATA PROBE V12
-- Focused read-only TokenChances / roll semantics research.
-- No remotes invoked, no hooks, debug/getgc, HTTP interception or game mutation.
local RS=game:GetService("ReplicatedStorage")
local CG=game:GetService("CoreGui")
local UIS=game:GetService("UserInputService")
local RunService=game:GetService("RunService")
local HttpService=game:GetService("HttpService")

local function at(root,...)
 local x=root
 for _,n in ipairs({...})do x=x and x:FindFirstChild(n)end
 return x
end
local function req(m)
 if not m or not m:IsA("ModuleScript")then return nil,"not-found"end
 local ok,r=pcall(require,m);if ok then return r,nil end;return nil,tostring(r)
end

local Lottery,lotErr=req(at(RS,"Shared","Util","AssetLottery"))
local AdminBoosts,boostErr=req(at(RS,"Shared","Util","AdminBoosts"))
local Cycle,cycleErr=req(at(RS,"Shared","Util","AreaEggCycle"))
local AREA_ROOT=at(RS,"Data","Areas","Configs")
local ABYSS=req(AREA_ROOT and AREA_ROOT:FindFirstChild("Abyss Ocean"))
local TAB=type(ABYSS)=="table" and ABYSS.DropTable or nil

local VALUES={0,0.5,1,1.01,1.3,1.31,1.32,1.4,2,3,30,31,32,40,100,200}
local LUCKS={0,30,31,32,40,100,200}

local gui=Instance.new("ScreenGui");gui.Name="PSICO_TOKEN_CHANCES_V12";gui.ResetOnSpawn=false;gui.DisplayOrder=1413;gui.Parent=CG
local f=Instance.new("Frame");f.AnchorPoint=Vector2.new(.5,.5);f.Position=UDim2.fromScale(.5,.5);f.Size=UDim2.fromOffset(455,225);f.BackgroundColor3=Color3.fromRGB(9,18,34);f.BorderSizePixel=0;f.Parent=gui;Instance.new("UICorner",f).CornerRadius=UDim.new(0,14)
local title=Instance.new("TextLabel");title.BackgroundTransparency=1;title.Position=UDim2.fromOffset(14,10);title.Size=UDim2.new(1,-28,0,28);title.Text="TOKEN CHANCES V12";title.Font=Enum.Font.GothamBold;title.TextSize=14;title.TextColor3=Color3.new(1,1,1);title.Parent=f
local st=Instance.new("TextLabel");st.Position=UDim2.fromOffset(14,48);st.Size=UDim2.new(1,-28,0,72);st.BackgroundColor3=Color3.fromRGB(15,29,52);st.BorderSizePixel=0;st.Text="Pronto. Testa TokenChances como metodo e compara com RollCountFor.";st.TextWrapped=true;st.Font=Enum.Font.Code;st.TextSize=11;st.TextColor3=Color3.new(1,1,1);st.Parent=f;Instance.new("UICorner",st).CornerRadius=UDim.new(0,9)
local function btn(t,x,w)local b=Instance.new("TextButton");b.Position=UDim2.fromOffset(x,136);b.Size=UDim2.fromOffset(w,38);b.BackgroundColor3=Color3.fromRGB(31,78,132);b.BorderSizePixel=0;b.Text=t;b.TextColor3=Color3.new(1,1,1);b.Font=Enum.Font.GothamBold;b.TextSize=11;b.Parent=f;Instance.new("UICorner",b).CornerRadius=UDim.new(0,9);return b end
local cap=btn("TESTAR + EXPORTAR",14,280);local close=btn("FECHAR",308,132)
local busy=false;local cancelled=false

local function simple(v,d,seen)
 d=d or 0;seen=seen or{};local t=typeof(v)
 if t=="nil"or t=="boolean"or t=="string"or t=="number"then return v end
 if t=="Instance"then return {class=v.ClassName,path=v:GetFullName()}end
 if t=="function"then return"<function>"end
 if t~="table"then return tostring(v)end
 if seen[v]or d>=6 then return"<cycle/depth>"end
 seen[v]=true;local o={};local n=0
 for k,z in pairs(v)do n+=1;if n>400 then o["<truncated>"]=true break end;o[tostring(k)]=simple(z,d+1,seen)end
 seen[v]=nil;return o
end
local function safeCall(label,fn)
 local ok,a,b,c,d=pcall(fn)
 if not ok then return {label=label,ok=false,error=tostring(a)}end
 return {label=label,ok=true,values=simple({a,b,c,d})}
end

local function tokenTests()
 local out={}
 for i,v in ipairs(VALUES)do
  if cancelled then break end
  local rec={input=v}
  rec.colon=safeCall("Lottery:TokenChances("..tostring(v)..")",function()return Lottery:TokenChances(v)end)
  rec.dot=safeCall("Lottery.TokenChances(Lottery,"..tostring(v)..")",function()return Lottery.TokenChances(Lottery,v)end)
  out[#out+1]=rec
  st.Text=string.format("TokenChances %d/%d",i,#VALUES);if i%4==0 then RunService.Heartbeat:Wait()end
 end
 return out
end
local function rollTests()
 local out={}
 for _,luck in ipairs(LUCKS)do
  local rec={luck=luck}
  rec.rollCount=safeCall("RollCountFor("..luck..")",function()return Lottery:RollCountFor(luck)end)
  local ok,rolls=pcall(function()return Lottery:RollCountFor(luck)end)
  if ok and type(rolls)=="number"then
   rec.tokenAtRollCount=safeCall("TokenChances(rollCount)",function()return Lottery:TokenChances(rolls)end)
   rec.sampleDraw=safeCall("DrawCategoryFromTable",function()return Lottery:DrawCategoryFromTable(TAB,rolls)end)
  end
  out[#out+1]=rec
 end
 return out
end
local function equivalence()
 if type(TAB)~="table"then return {error="abyss-table-missing"}end
 local out={}
 out.colon=safeCall("colon",function()return Lottery:DrawCategoryFromTable(TAB,1)end)
 out.dot=safeCall("dot-self",function()return Lottery.DrawCategoryFromTable(Lottery,TAB,1)end)
 out.twoArgDot=safeCall("dot-no-self",function()return Lottery.DrawCategoryFromTable(TAB,1)end)
 return out
end
local function adminBoost()
 local out={}
 if type(AdminBoosts)=="table"and type(AdminBoosts.ReadMultiplier)=="function"then
  local key=AdminBoosts.EGG_SPAWN_LUCK or"EggSpawnLuck";out.key=key
  out.read=safeCall("ReadMultiplier",function()return AdminBoosts.ReadMultiplier(key)end)
 end
 return out
end
local function snapshot()
 local now=os.time();local current=(Cycle and Cycle.PeriodIndexAt and Cycle.PeriodIndexAt(now))or math.floor(now/300)
 return {meta={version="EggCycleDataProbe12",created=now,currentPeriod=current,placeId=tostring(game.PlaceId),gameId=tostring(game.GameId),jobId=tostring(game.JobId),passive=true,mode="token-chances"},errors={lottery=lotErr,adminBoosts=boostErr,cycle=cycleErr},equivalence=equivalence(),tokenChances=tokenTests(),luckMapping=rollTests(),adminBoost=adminBoost()}
end

cap.MouseButton1Click:Connect(function()
 if busy then return end;busy=true;cancelled=false;cap.Text="EXECUTANDO...";st.Text="Iniciando V12..."
 task.spawn(function()
  local ok,r=pcall(snapshot);if not ok then st.Text="Erro: "..tostring(r);busy=false;cap.Text="TESTAR + EXPORTAR";return end
  st.Text="Montando JSON...";RunService.Heartbeat:Wait()
  local ok2,j=pcall(function()return HttpService:JSONEncode(r)end);if not ok2 then st.Text="Erro JSON: "..tostring(j);busy=false;cap.Text="TESTAR + EXPORTAR";return end
  local name="Psico_TokenChances_"..os.time()..".json";local wrote=false;if writefile then wrote=pcall(writefile,name,j)end
  st.Text=(wrote and"EXPORTADO: "or"CONCLUIDO SEM WRITEFILE: ")..name.." | "..#j.." bytes";busy=false;cap.Text="TESTAR + EXPORTAR"
 end)
end)
close.MouseButton1Click:Connect(function()cancelled=true;gui:Destroy()end)
local drag=false;local ds,sp
f.InputBegan:Connect(function(i)if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then drag=true;ds=i.Position;sp=f.Position end end)
f.InputChanged:Connect(function(i)if drag and(i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch)then local d=i.Position-ds;f.Position=UDim2.new(sp.X.Scale,sp.X.Offset+d.X,sp.Y.Scale,sp.Y.Offset+d.Y)end end)
UIS.InputEnded:Connect(function(i)if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then drag=false end end)

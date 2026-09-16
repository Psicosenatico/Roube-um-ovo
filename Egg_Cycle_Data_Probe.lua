-- PSICOSENATICO | EGG CYCLE DATA PROBE V13
-- Focused read-only signature disambiguation for AssetLottery.
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
local Cycle,cycleErr=req(at(RS,"Shared","Util","AreaEggCycle"))
local AREA_ROOT=at(RS,"Data","Areas","Configs")
local ABYSS=req(AREA_ROOT and AREA_ROOT:FindFirstChild("Abyss Ocean"))
local TAB=type(ABYSS)=="table" and ABYSS.DropTable or nil
local SYN={{"A",70},{"B",25},{"C",5}}
local VALUES={0,1,1.3,1.31,1.32,1.4,2,3,30,31,32,40,100,200}

local gui=Instance.new("ScreenGui");gui.Name="PSICO_SIGNATURE_V13";gui.ResetOnSpawn=false;gui.DisplayOrder=1414;gui.Parent=CG
local f=Instance.new("Frame");f.AnchorPoint=Vector2.new(.5,.5);f.Position=UDim2.fromScale(.5,.5);f.Size=UDim2.fromOffset(455,232);f.BackgroundColor3=Color3.fromRGB(9,18,34);f.BorderSizePixel=0;f.Parent=gui;Instance.new("UICorner",f).CornerRadius=UDim.new(0,14)
local title=Instance.new("TextLabel");title.BackgroundTransparency=1;title.Position=UDim2.fromOffset(14,10);title.Size=UDim2.new(1,-28,0,28);title.Text="ASSETLOTTERY SIGNATURE V13";title.Font=Enum.Font.GothamBold;title.TextSize=14;title.TextColor3=Color3.new(1,1,1);title.Parent=f
local st=Instance.new("TextLabel");st.Position=UDim2.fromOffset(14,48);st.Size=UDim2.new(1,-28,0,80);st.BackgroundColor3=Color3.fromRGB(15,29,52);st.BorderSizePixel=0;st.Text="Pronto. Distingue chamadas staticas vs metodo e testa TokenChances(DropTable, numero).";st.TextWrapped=true;st.Font=Enum.Font.Code;st.TextSize=11;st.TextColor3=Color3.new(1,1,1);st.Parent=f;Instance.new("UICorner",st).CornerRadius=UDim.new(0,9)
local function btn(t,x,w)local b=Instance.new("TextButton");b.Position=UDim2.fromOffset(x,144);b.Size=UDim2.fromOffset(w,38);b.BackgroundColor3=Color3.fromRGB(31,78,132);b.BorderSizePixel=0;b.Text=t;b.TextColor3=Color3.new(1,1,1);b.Font=Enum.Font.GothamBold;b.TextSize=11;b.Parent=f;Instance.new("UICorner",b).CornerRadius=UDim.new(0,9);return b end
local cap=btn("TESTAR + EXPORTAR",14,280);local close=btn("FECHAR",308,132)
local busy=false;local cancelled=false;local ops=0
local function breathe(msg)ops+=1;if msg then st.Text=msg end;if ops%6==0 then RunService.Heartbeat:Wait()end end

local function simple(v,d,seen)
 d=d or 0;seen=seen or{};local t=typeof(v)
 if t=="nil"or t=="boolean"or t=="string"or t=="number"then return v end
 if t=="Instance"then return {class=v.ClassName,path=v:GetFullName()}end
 if t=="function"then return"<function>"end
 if t=="Random"then return"<Random>"end
 if t~="table"then return tostring(v)end
 if seen[v]or d>=7 then return"<cycle/depth>"end
 seen[v]=true;local o={};local n=0
 for k,z in pairs(v)do n+=1;if n>500 then o["<truncated>"]=true break end;o[tostring(k)]=simple(z,d+1,seen)end
 seen[v]=nil;return o
end
local function call(label,fn)
 local ok,a,b,c,d=pcall(fn)
 if not ok then return {label=label,ok=false,error=tostring(a)}end
 return {label=label,ok=true,values=simple({a,b,c,d})}
end

local function rollCountMatrix()
 local out={}
 for _,v in ipairs({0,1,30,31,32,40,100})do
  local r={input=v}
  r.dot1=call("RollCountFor(v)",function()return Lottery.RollCountFor(v)end)
  r.dotSelf=call("RollCountFor(Lottery,v)",function()return Lottery.RollCountFor(Lottery,v)end)
  r.colon=call("Lottery:RollCountFor(v)",function()return Lottery:RollCountFor(v)end)
  r.dotV1=call("RollCountFor(v,1)",function()return Lottery.RollCountFor(v,1)end)
  r.dot1V=call("RollCountFor(1,v)",function()return Lottery.RollCountFor(1,v)end)
  out[#out+1]=r;breathe("RollCountFor "..v)
 end
 return out
end

local function tokenMatrix()
 local out={}
 for _,v in ipairs(VALUES)do
  if cancelled then break end
  local r={input=v}
  r.abyssDot=call("TokenChances(TAB,v)",function()return Lottery.TokenChances(TAB,v)end)
  r.abyssColon=call("Lottery:TokenChances(TAB,v)",function()return Lottery:TokenChances(TAB,v)end)
  r.syntheticDot=call("TokenChances(SYN,v)",function()return Lottery.TokenChances(SYN,v)end)
  r.moduleDot=call("TokenChances(Lottery,v)",function()return Lottery.TokenChances(Lottery,v)end)
  out[#out+1]=r;breathe("TokenChances "..v)
 end
 return out
end

local function drawReceiverMatrix()
 local out={}
 local factories={
  {name="Lottery",make=function()return Lottery end},
  {name="emptyTable",make=function()return{}end},
  {name="syntheticTable",make=function()return SYN end},
  {name="Random",make=function()return Random.new(5964938)end},
  {name="string",make=function()return"x"end},
  {name="number",make=function()return123 end},
 }
 for _,e in ipairs(factories)do
  local r={first=e.name,runs={}}
  for i=1,6 do
   local first=e.make()
   local rec=call("DrawCategoryFromTable(first,TAB,1)",function()return Lottery.DrawCategoryFromTable(first,TAB,1)end)
   if typeof(first)=="Random"then rec.randomAfter=first:NextNumber()end
   r.runs[#r.runs+1]=rec
  end
  out[#out+1]=r;breathe("Draw first="..e.name)
 end
 out[#out+1]={first="colon",runs={call("Lottery:DrawCategoryFromTable(TAB,1)",function()return Lottery:DrawCategoryFromTable(TAB,1)end)}}
 out[#out+1]={first="dotNoSelf",runs={call("DrawCategoryFromTable(TAB,1)",function()return Lottery.DrawCategoryFromTable(TAB,1)end)}}
 return out
end

local function crossCheck()
 local out={}
 for _,luck in ipairs({30,31,32,40})do
  local a=call("staticRollCount",function()return Lottery.RollCountFor(luck)end)
  local b=call("methodRollCount",function()return Lottery:RollCountFor(luck)end)
  local static=a.ok and a.values and a.values["1"] or nil
  local method=b.ok and b.values and b.values["1"] or nil
  local rec={luck=luck,staticRollCount=static,methodRollCount=method}
  if type(static)=="number"then rec.tokensStatic=call("TokenChances(TAB,static)",function()return Lottery.TokenChances(TAB,static)end);rec.drawStatic=call("Draw self/TAB/static",function()return Lottery:DrawCategoryFromTable(TAB,static)end)end
  if type(method)=="number"then rec.tokensMethod=call("TokenChances(TAB,method)",function()return Lottery.TokenChances(TAB,method)end);rec.drawMethod=call("Draw self/TAB/method",function()return Lottery:DrawCategoryFromTable(TAB,method)end)end
  out[#out+1]=rec
 end
 return out
end

local function snapshot()
 local now=os.time();local current=(Cycle and Cycle.PeriodIndexAt and Cycle.PeriodIndexAt(now))or math.floor(now/300)
 return {meta={version="EggCycleDataProbe13",created=now,currentPeriod=current,placeId=tostring(game.PlaceId),gameId=tostring(game.GameId),jobId=tostring(game.JobId),passive=true,mode="signature-disambiguation"},errors={lottery=lotErr,cycle=cycleErr},rollCountMatrix=rollCountMatrix(),tokenMatrix=tokenMatrix(),drawReceiverMatrix=drawReceiverMatrix(),crossCheck=crossCheck()}
end

cap.MouseButton1Click:Connect(function()
 if busy then return end;busy=true;cancelled=false;ops=0;cap.Text="EXECUTANDO...";st.Text="Iniciando V13..."
 task.spawn(function()
  local ok,r=pcall(snapshot);if not ok then st.Text="Erro: "..tostring(r);busy=false;cap.Text="TESTAR + EXPORTAR";return end
  st.Text="Montando JSON...";RunService.Heartbeat:Wait()
  local ok2,j=pcall(function()return HttpService:JSONEncode(r)end);if not ok2 then st.Text="Erro JSON: "..tostring(j);busy=false;cap.Text="TESTAR + EXPORTAR";return end
  local name="Psico_SignatureDisambiguation_"..os.time()..".json";local wrote=false;if writefile then wrote=pcall(writefile,name,j)end
  st.Text=(wrote and"EXPORTADO: "or"CONCLUIDO SEM WRITEFILE: ")..name.." | "..#j.." bytes";busy=false;cap.Text="TESTAR + EXPORTAR"
 end)
end)
close.MouseButton1Click:Connect(function()cancelled=true;gui:Destroy()end)
local drag=false;local ds,sp
f.InputBegan:Connect(function(i)if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then drag=true;ds=i.Position;sp=f.Position end end)
f.InputChanged:Connect(function(i)if drag and(i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch)then local d=i.Position-ds;f.Position=UDim2.new(sp.X.Scale,sp.X.Offset+d.X,sp.Y.Scale,sp.Y.Offset+d.Y)end end)
UIS.InputEnded:Connect(function(i)if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then drag=false end end)
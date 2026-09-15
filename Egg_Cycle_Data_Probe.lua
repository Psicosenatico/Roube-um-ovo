-- PSICOSENATICO | EGG CYCLE DATA PROBE V9
-- Focused read-only repeatability test for AssetLottery luck semantics.
-- No remotes are invoked; no hooks, debug/getgc, HTTP interception or mutation.
local RS=game:GetService("ReplicatedStorage")
local CG=game:GetService("CoreGui")
local UIS=game:GetService("UserInputService")
local RunService=game:GetService("RunService")
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
local Area=req(at(RS,"Data","Areas","Configs","Abyss Ocean"))
local TEST_SEEDS={5964938,1789481400}
local CHANCES={0,1,30,31,32,40,100,200}
local REPEATS=12
local function simple(v,d,seen)
 d=d or 0;seen=seen or{};local t=typeof(v)
 if t=="nil"or t=="boolean"or t=="string"or t=="number"then return v end
 if t=="Instance"then return {class=v.ClassName,path=v:GetFullName()}end
 if t=="function"then return"<function>"end
 if t~="table"then return tostring(v)end
 if seen[v]or d>=5 then return"<cycle/depth>"end
 seen[v]=true;local o={};local n=0
 for k,z in pairs(v)do n+=1;if n>300 then o["<truncated>"]=true break end;o[tostring(k)]=simple(z,d+1,seen)end
 seen[v]=nil;return o
end
local function exportModule(pathParts)
 local m=at(RS,table.unpack(pathParts));local r,e=req(m)
 return {path=m and m:GetFullName()or nil,requireOk=(r~=nil),error=e,export=simple(r)}
end
local function baseline(seed)
 local vals={}
 for i=1,REPEATS do local r=Random.new(seed);vals[i]=r:NextNumber() end
 return vals
end
local function lotteryRepeats(seed,chance,tab)
 local values={};local counts={};local errors={}
 for i=1,REPEATS do
  local ok,r=pcall(Lottery.DrawCategoryFromTable,Random.new(seed),tab,chance)
  if ok then values[i]=r;counts[r]=(counts[r]or 0)+1 else values[i]="<error>";errors[#errors+1]=tostring(r)end
  if i%4==0 then RunService.Heartbeat:Wait()end
 end
 local unique=0;for _ in pairs(counts)do unique+=1 end
 return {seed=seed,chance=chance,rollCount=(Lottery.RollCountFor and Lottery.RollCountFor(chance)or nil),values=values,counts=counts,uniqueResults=unique,errors=errors}
end
local function snapshot(status)
 local now=os.time();local current=(Cycle and Cycle.PeriodIndexAt and Cycle.PeriodIndexAt(now))or math.floor(now/300)
 local out={meta={version="EggCycleDataProbe9",created=now,currentPeriod=current,placeId=tostring(game.PlaceId),gameId=tostring(game.GameId),jobId=tostring(game.JobId),passive=true,mode="repeatability-serverluck",repeats=REPEATS},errors={lottery=lotErr,cycle=cycleErr},baselineRandom={},repeatability={},luckModules={}}
 if type(Area)~="table"or type(Area.DropTable)~="table"then error("Abyss Ocean config missing")end
 if not Lottery or type(Lottery.DrawCategoryFromTable)~="function"then error("AssetLottery missing")end
 for _,seed in ipairs(TEST_SEEDS)do out.baselineRandom[tostring(seed)]=baseline(seed)end
 local total=#TEST_SEEDS*#CHANCES;local n=0
 for _,seed in ipairs(TEST_SEEDS)do
  for _,chance in ipairs(CHANCES)do n+=1;if status then status.Text=string.format("Repeatability %d/%d | seed %s | luck %s",n,total,tostring(seed),tostring(chance))end;out.repeatability[#out.repeatability+1]=lotteryRepeats(seed,chance,Area.DropTable)end
 end
 out.luckModules.ServerLuckType=exportModule({"Shared","Types","ServerLuck"})
 out.luckModules.AdminBoosts=exportModule({"Shared","Util","AdminBoosts"})
 out.luckModules.GamepassLucky=exportModule({"Data","Gamepasses","Configs","Lucky"})
 out.luckModules.ProductServerLuck=exportModule({"Data","Products","Builders","ServerLuck"})
 out.luckModules.ProductServerLuckExtension=exportModule({"Data","Products","Builders","ServerLuckExtension"})
 return out
end
local function esc(s)
 s=tostring(s or""):gsub("\\","\\\\"):gsub('"','\\"'):gsub("\b","\\b"):gsub("\f","\\f"):gsub("\n","\\n"):gsub("\r","\\r"):gsub("\t","\\t")
 s=s:gsub("[%z\1-\31]",function(c)return string.format("\\u%04x",string.byte(c))end);return'"'..s..'"'
end
local function arr(t)local n=0;for k in pairs(t)do if type(k)~="number"or k<1 or k%1~=0 then return false,0 end;n=math.max(n,k)end;for i=1,n do if rawget(t,i)==nil then return false,0 end end;return true,n end
local function enc(v,seen)
 local t=type(v);if t=="nil"then return"null"elseif t=="boolean"then return v and"true"or"false"elseif t=="number"then return tostring(v)elseif t=="string"then return esc(v)elseif t~="table"then return esc(tostring(v))end
 seen=seen or{};if seen[v]then return esc("<cycle>")end;seen[v]=true;local a,n=arr(v);local p={}
 if a then for i=1,n do p[#p+1]=enc(v[i],seen)end;seen[v]=nil;return"["..table.concat(p,",").."]"end
 local ks={};for k in pairs(v)do ks[#ks+1]=tostring(k)end;table.sort(ks);for _,k in ipairs(ks)do p[#p+1]=esc(k)..":"..enc(v[k],seen)end;seen[v]=nil;return"{"..table.concat(p,",").."}"
end
local gui=Instance.new("ScreenGui");gui.Name="PSICO_REPEATABILITY_V9";gui.ResetOnSpawn=false;gui.DisplayOrder=1410;gui.Parent=CG
local f=Instance.new("Frame");f.AnchorPoint=Vector2.new(.5,.5);f.Position=UDim2.fromScale(.5,.5);f.Size=UDim2.fromOffset(455,225);f.BackgroundColor3=Color3.fromRGB(9,18,34);f.BorderSizePixel=0;f.Parent=gui;Instance.new("UICorner",f).CornerRadius=UDim.new(0,14)
local title=Instance.new("TextLabel");title.BackgroundTransparency=1;title.Position=UDim2.fromOffset(14,10);title.Size=UDim2.new(1,-28,0,28);title.Text="LOTTERY REPEATABILITY V9";title.Font=Enum.Font.GothamBold;title.TextSize=14;title.TextColor3=Color3.new(1,1,1);title.Parent=f
local st=Instance.new("TextLabel");st.Position=UDim2.fromOffset(14,48);st.Size=UDim2.new(1,-28,0,72);st.BackgroundColor3=Color3.fromRGB(15,29,52);st.BorderSizePixel=0;st.Text="Pronto. Repete exatamente a mesma seed/luck e compara com Random.new puro.";st.TextWrapped=true;st.Font=Enum.Font.Code;st.TextSize=11;st.TextColor3=Color3.new(1,1,1);st.Parent=f;Instance.new("UICorner",st).CornerRadius=UDim.new(0,9)
local function btn(t,x,w)local b=Instance.new("TextButton");b.Position=UDim2.fromOffset(x,136);b.Size=UDim2.fromOffset(w,38);b.BackgroundColor3=Color3.fromRGB(31,78,132);b.BorderSizePixel=0;b.Text=t;b.TextColor3=Color3.new(1,1,1);b.Font=Enum.Font.GothamBold;b.TextSize=11;b.Parent=f;Instance.new("UICorner",b).CornerRadius=UDim.new(0,9);return b end
local cap=btn("TESTAR + EXPORTAR",14,280);local close=btn("FECHAR",308,132);local busy=false
cap.MouseButton1Click:Connect(function()
 if busy then return end;busy=true;cap.Text="EXECUTANDO..."
 task.spawn(function()
  local ok,r=pcall(snapshot,st);if not ok then st.Text="Erro: "..tostring(r);busy=false;cap.Text="TESTAR + EXPORTAR";return end
  st.Text="Montando JSON...";RunService.Heartbeat:Wait();local ok2,j=pcall(function()return enc(r,{})end)
  if not ok2 then st.Text="Erro JSON: "..tostring(j);busy=false;cap.Text="TESTAR + EXPORTAR";return end
  local name="Psico_Repeatability_"..os.time()..".json";local wrote=false;if writefile then wrote=pcall(writefile,name,j)end
  st.Text=(wrote and"EXPORTADO: "or"CONCLUIDO SEM WRITEFILE: ")..name.." | "..#j.." bytes";busy=false;cap.Text="TESTAR + EXPORTAR"
 end)
end)
close.MouseButton1Click:Connect(function()gui:Destroy()end)
local drag=false;local ds,sp
f.InputBegan:Connect(function(i)if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then drag=true;ds=i.Position;sp=f.Position end end)
f.InputChanged:Connect(function(i)if drag and(i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch)then local d=i.Position-ds;f.Position=UDim2.new(sp.X.Scale,sp.X.Offset+d.X,sp.Y.Scale,sp.Y.Offset+d.Y)end end)
UIS.InputEnded:Connect(function(i)if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then drag=false end end)

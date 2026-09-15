-- PSICOSENATICO | EGG CYCLE DATA PROBE V11
-- Focused read-only AssetLottery API/signature research.
-- No remotes invoked, no hooks, debug/getgc, HTTP interception or game mutation.
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
 if not m or not m:IsA("ModuleScript")then return nil,"not-found" end
 local ok,r=pcall(require,m);if ok then return r,nil end;return nil,tostring(r)
end
local Lottery,lotErr=req(at(RS,"Shared","Util","AssetLottery"))
local AdminBoosts,boostErr=req(at(RS,"Shared","Util","AdminBoosts"))
local Cycle,cycleErr=req(at(RS,"Shared","Util","AreaEggCycle"))
local AREA_ROOT=at(RS,"Data","Areas","Configs")
local ABYSS=req(AREA_ROOT and AREA_ROOT:FindFirstChild("Abyss Ocean"))
local TAB=type(ABYSS)=="table" and ABYSS.DropTable or nil
local SEED=5964938

local gui=Instance.new("ScreenGui");gui.Name="PSICO_LOTTERY_SIGNATURE_V11";gui.ResetOnSpawn=false;gui.DisplayOrder=1412;gui.Parent=CG
local f=Instance.new("Frame");f.AnchorPoint=Vector2.new(.5,.5);f.Position=UDim2.fromScale(.5,.5);f.Size=UDim2.fromOffset(455,230);f.BackgroundColor3=Color3.fromRGB(9,18,34);f.BorderSizePixel=0;f.Parent=gui;Instance.new("UICorner",f).CornerRadius=UDim.new(0,14)
local title=Instance.new("TextLabel");title.BackgroundTransparency=1;title.Position=UDim2.fromOffset(14,10);title.Size=UDim2.new(1,-28,0,28);title.Text="ASSETLOTTERY SIGNATURE V11";title.Font=Enum.Font.GothamBold;title.TextSize=14;title.TextColor3=Color3.new(1,1,1);title.Parent=f
local st=Instance.new("TextLabel");st.Position=UDim2.fromOffset(14,48);st.Size=UDim2.new(1,-28,0,78);st.BackgroundColor3=Color3.fromRGB(15,29,52);st.BorderSizePixel=0;st.Text="Pronto. Testa se o 1o argumento e self/RNG e inspeciona TokenChances com a DropTable real.";st.TextWrapped=true;st.Font=Enum.Font.Code;st.TextSize=11;st.TextColor3=Color3.new(1,1,1);st.Parent=f;Instance.new("UICorner",st).CornerRadius=UDim.new(0,9)
local function btn(t,x,w)local b=Instance.new("TextButton");b.Position=UDim2.fromOffset(x,142);b.Size=UDim2.fromOffset(w,38);b.BackgroundColor3=Color3.fromRGB(31,78,132);b.BorderSizePixel=0;b.Text=t;b.TextColor3=Color3.new(1,1,1);b.Font=Enum.Font.GothamBold;b.TextSize=11;b.Parent=f;Instance.new("UICorner",b).CornerRadius=UDim.new(0,9);return b end
local cap=btn("TESTAR + EXPORTAR",14,280);local close=btn("FECHAR",308,132)
local busy=false;local cancelled=false;local ops=0
local function breathe(msg)ops+=1;if msg then st.Text=msg end;if ops%6==0 then RunService.Heartbeat:Wait()end end

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
local function safe(label,f,...)
 if type(f)~="function"then return {label=label,available=false}end
 local ok,a,b,c=pcall(f,...)
 if ok then return {label=label,available=true,ok=true,values=simple({a,b,c})}end
 return {label=label,available=true,ok=false,error=tostring(a)}
end
local function callDraw(first,rolls)
 local ok,r=pcall(Lottery.DrawCategoryFromTable,first,TAB,rolls)
 return {ok=ok,result=ok and r or nil,error=ok and nil or tostring(r)}
end
local function repeated(label,firstFactory,rolls,n)
 local out={label=label,rolls=rolls,values={},counts={},errors={}}
 for i=1,n do
  if cancelled then break end
  local first=firstFactory and firstFactory() or nil
  local rec=callDraw(first,rolls)
  if rec.ok then out.values[#out.values+1]=rec.result;out.counts[rec.result]=(out.counts[rec.result]or 0)+1 else out.errors[#out.errors+1]=rec.error end
  if typeof(first)=="Random"then
   local a=first:NextNumber();out.rngAfter=out.rngAfter or{};out.rngAfter[#out.rngAfter+1]=a
  end
  breathe(string.format("%s %d/%d",label,i,n))
 end
 return out
end
local function signatureProbe()
 local out={}
 out[#out+1]=repeated("first=Lottery(self)",function()return Lottery end,1,8)
 out[#out+1]=repeated("first=Random.new(seed)",function()return Random.new(SEED)end,1,8)
 out[#out+1]=repeated("first=empty-table",function()return{}end,1,8)
 out[#out+1]=repeated("first=string",function()return"x"end,1,4)
 out[#out+1]=repeated("first=number",function()return123end,1,4)
 out[#out+1]=repeated("first=nil",function()return nil end,1,4)
 local ok2,r2=pcall(Lottery.DrawCategoryFromTable,TAB,1)
 out.twoArgDot={ok=ok2,result=ok2 and r2 or nil,error=ok2 and nil or tostring(r2)}
 local okc,rc=pcall(function()return Lottery:DrawCategoryFromTable(TAB,1)end)
 out.colonCall={ok=okc,result=okc and rc or nil,error=okc and nil or tostring(rc)}
 return out
end
local function tokenProbe()
 local out={}
 out[#out+1]=safe("TokenChances(TAB)",Lottery and Lottery.TokenChances,TAB)
 out[#out+1]=safe("TokenChances(Lottery,TAB)",Lottery and Lottery.TokenChances,Lottery,TAB)
 out[#out+1]=safe("TokenChances({DropTable=TAB})",Lottery and Lottery.TokenChances,{DropTable=TAB})
 return out
end
local function properRollProbe()
 local out={}
 for _,luck in ipairs({0,30,31,32,40,100})do
  local rc=safe("RollCountFor("..luck..")",Lottery and Lottery.RollCountFor,luck)
  local rolls=rc.ok and rc.values and rc.values["1"] or nil
  if rolls==nil and rc.ok and rc.values then rolls=rc.values[1]end
  local rec={luck=luck,rollCount=rolls,rollCountCall=rc}
  if type(rolls)=="number"then rec.selfStyle=repeated("luck"..luck.." self",function()return Lottery end,rolls,10)end
  out[#out+1]=rec
 end
 return out
end
local function boostProbe()
 local out={}
 if type(AdminBoosts)=="table"and type(AdminBoosts.ReadMultiplier)=="function"then
  local key=AdminBoosts.EGG_SPAWN_LUCK or"EggSpawnLuck"
  out.key=key;out.read=safe("ReadMultiplier(EggSpawnLuck)",AdminBoosts.ReadMultiplier,key)
 end
 return out
end
local function snapshot()
 local now=os.time();local current=(Cycle and Cycle.PeriodIndexAt and Cycle.PeriodIndexAt(now))or math.floor(now/300)
 local out={meta={version="EggCycleDataProbe11",created=now,currentPeriod=current,placeId=tostring(game.PlaceId),gameId=tostring(game.GameId),jobId=tostring(game.JobId),passive=true,mode="assetlottery-signature"},errors={lottery=lotErr,adminBoosts=boostErr,cycle=cycleErr},signature=signatureProbe(),tokenChances=tokenProbe(),properRolls=properRollProbe(),adminBoost=boostProbe()}
 return out
end
local function esc(s)s=tostring(s or""):gsub("\\","\\\\"):gsub('"','\\"'):gsub("\b","\\b"):gsub("\f","\\f"):gsub("\n","\\n"):gsub("\r","\\r"):gsub("\t","\\t");s=s:gsub("[%z\1-\31]",function(c)return string.format("\\u%04x",string.byte(c))end);return'"'..s..'"'end
local function arr(t)local n=0;for k in pairs(t)do if type(k)~="number"or k<1 or k%1~=0 then return false,0 end;n=math.max(n,k)end;for i=1,n do if rawget(t,i)==nil then return false,0 end end;return true,n end
local function enc(v,seen)local t=typeof(v);if t=="nil"then return"null"elseif t=="boolean"then return v and"true"or"false"elseif t=="number"then return tostring(v)elseif t=="string"then return esc(v)elseif t=="Instance"then return esc(v:GetFullName())elseif t~="table"then return esc(tostring(v))end;seen=seen or{};if seen[v]then return esc("<cycle>")end;seen[v]=true;local a,n=arr(v);local p={};if a then for i=1,n do p[#p+1]=enc(v[i],seen)end;seen[v]=nil;return"["..table.concat(p,",").."]"end;local ks={};for k in pairs(v)do ks[#ks+1]=tostring(k)end;table.sort(ks);for _,k in ipairs(ks)do p[#p+1]=esc(k)..":"..enc(v[k],seen)end;seen[v]=nil;return"{"..table.concat(p,",").."}"end
cap.MouseButton1Click:Connect(function()if busy then return end;busy=true;cancelled=false;ops=0;cap.Text="EXECUTANDO...";st.Text="Iniciando V11...";task.spawn(function()local ok,r=pcall(snapshot);if not ok then st.Text="Erro: "..tostring(r);busy=false;cap.Text="TESTAR + EXPORTAR";return end;st.Text="Montando JSON...";RunService.Heartbeat:Wait();local ok2,j=pcall(function()return enc(r,{})end);if not ok2 then st.Text="Erro JSON: "..tostring(j);busy=false;cap.Text="TESTAR + EXPORTAR";return end;local name="Psico_LotterySignature_"..os.time()..".json";local wrote=false;if writefile then wrote=pcall(writefile,name,j)end;st.Text=(wrote and"EXPORTADO: "or"CONCLUIDO SEM WRITEFILE: ")..name.." | "..#j.." bytes";busy=false;cap.Text="TESTAR + EXPORTAR"end)end)
close.MouseButton1Click:Connect(function()cancelled=true;gui:Destroy()end)
local drag=false;local ds,sp
f.InputBegan:Connect(function(i)if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then drag=true;ds=i.Position;sp=f.Position end end)
f.InputChanged:Connect(function(i)if drag and(i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch)then local d=i.Position-ds;f.Position=UDim2.new(sp.X.Scale,sp.X.Offset+d.X,sp.Y.Scale,sp.Y.Offset+d.Y)end end)
UIS.InputEnded:Connect(function(i)if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then drag=false end end)

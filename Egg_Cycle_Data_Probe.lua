-- PSICOSENATICO | EGG CYCLE DATA PROBE V5
-- Controlled read-only signature probe for replicated utility modules.
-- Calls only local utility functions with synthetic/local data. No remotes, hooks, debug/getgc, HTTP interception or game mutation.

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
 local ok,r=pcall(require,m);if ok then return r,nil end;return nil,tostring(r)
end

local Lottery,lotErr=req(at(RS,"Shared","Util","AssetLottery"))
local Better,betterErr=req(at(RS,"Shared","Modules","BetterRandom"))
local Positional,posErr=req(at(RS,"UserGenerated","IO","Crypto","PositionalRandom"))
local Randoms,randomsErr=req(at(RS,"UserGenerated","Randoms"))
local Xor,xorErr=req(at(RS,"UserGenerated","Randoms","Xorshift128"))
local SubBiome,subErr=req(at(RS,"Shared","Util","SubBiomeCycle"))
local Cycle,cycleErr=req(at(RS,"Shared","Util","AreaEggCycle"))
local Areas,areasErr=req(at(RS,"Data","Areas"))

local function clean(v,d,seen,budget)
 d=d or 0;seen=seen or{};budget=budget or{n=0,max=8000};budget.n+=1
 if budget.n>budget.max then return "<budget-limit>" end
 local t=typeof(v)
 if t=="nil" or t=="boolean" or t=="string" or t=="number" then return v end
 if t=="Instance" then return {__type="Instance",class=v.ClassName,path=v:GetFullName()} end
 if t=="function" then return "<function>" end
 if t=="thread" then return "<thread>" end
 if t=="userdata" then return tostring(v) end
 if t~="table" then return tostring(v) end
 if seen[v] then return "<cycle>" end
 if d>=6 then return "<depth-limit>" end
 seen[v]=true;local o={};local n=0
 for k,z in pairs(v)do n+=1;if n>300 then o["<truncated>"]=true break end;o[tostring(k)]=clean(z,d+1,seen,budget)end
 seen[v]=nil;return o
end

local function trial(label,fn)
 local ok,a,b,c,d=pcall(fn)
 local out={label=label,ok=ok}
 if ok then out.values=clean({a,b,c,d}) else out.error=tostring(a) end
 return out
end
local function add(list,label,fn) list[#list+1]=trial(label,fn) end

local function probe()
 local now=os.time();local period=math.floor(now/300)
 if Cycle and type(Cycle.PeriodIndexAt)=="function" then local ok,p=pcall(Cycle.PeriodIndexAt,now);if ok and type(p)=="number" then period=p end end
 local out={meta={version="EggCycleDataProbe5",created=now,placeId=tostring(game.PlaceId),gameId=tostring(game.GameId),jobId=tostring(game.JobId),passive=true,mode="controlled-signature-probe",periodIndex=period},errors={lottery=lotErr,betterRandom=betterErr,positional=posErr,randoms=randomsErr,xorshift=xorErr,subBiome=subErr,cycle=cycleErr,areas=areasErr},exports={Lottery=clean(Lottery),BetterRandom=clean(Better),PositionalRandom=clean(Positional),Randoms=clean(Randoms),Xorshift128=clean(Xor),SubBiomeCycle=clean(SubBiome)},trials={betterRandom={},positional={},xorshift={},subBiome={},lottery={}}}

 local rbx=Random.new(123456)
 local br=nil
 if Better and type(Better.new)=="function" then
  local t=trial("BetterRandom.new(123456)",function() return Better.new(123456) end);out.trials.betterRandom[#out.trials.betterRandom+1]=t
  if t.ok then local ok,obj=pcall(Better.new,123456);if ok then br=obj end end
 end
 if br then
  add(out.trials.betterRandom,"br:number()",function() return br:number() end)
  add(out.trials.betterRandom,"br:integer(1,100)",function() return br:integer(1,100) end)
  add(out.trials.betterRandom,"br:boolean()",function() return br:boolean() end)
 end

 if Positional then
  for _,n in ipairs({0,1,2,17,12345}) do
   if type(Positional.Mix)=="function" then add(out.trials.positional,"Mix(period,"..n..")",function() return Positional.Mix(period,n) end) end
  end
  if type(Positional.DoubleFromInt64)=="function" then add(out.trials.positional,"DoubleFromInt64(period)",function() return Positional.DoubleFromInt64(period) end) end
 end

 if Randoms and type(Randoms.Xorshift128)=="function" then add(out.trials.xorshift,"Randoms.Xorshift128(period)",function() return Randoms.Xorshift128(period) end) end
 if Xor and type(Xor.new)=="function" then add(out.trials.xorshift,"Xorshift128.new(period)",function() return Xor.new(period) end) end

 local light=nil
 if Areas and type(Areas)=="table" and type(Areas.Directory)=="table" then light=Areas.Directory["Light Dark"] end
 if SubBiome then
  if type(SubBiome.RolledForPeriod)=="function" then
   add(out.trials.subBiome,"RolledForPeriod(light,period)",function() return SubBiome.RolledForPeriod(light,period) end)
   add(out.trials.subBiome,"RolledForPeriod(period,light)",function() return SubBiome.RolledForPeriod(period,light) end)
   add(out.trials.subBiome,"RolledForPeriod('Light Dark',period)",function() return SubBiome.RolledForPeriod("Light Dark",period) end)
  end
  if type(SubBiome.ForPeriod)=="function" then
   add(out.trials.subBiome,"ForPeriod(light,period)",function() return SubBiome.ForPeriod(light,period) end)
   add(out.trials.subBiome,"ForPeriod(period,light)",function() return SubBiome.ForPeriod(period,light) end)
  end
 end

 local pair={{"A",100},{"B",0}}
 local pair2={{"A",1},{"B",1}}
 local map={A=100,B=0}
 if Lottery and type(Lottery.DrawCategoryFromTable)=="function" then
  add(out.trials.lottery,"DrawCategoryFromTable(pair)",function() return Lottery.DrawCategoryFromTable(pair) end)
  add(out.trials.lottery,"DrawCategoryFromTable(pair,Random)",function() return Lottery.DrawCategoryFromTable(pair,rbx) end)
  add(out.trials.lottery,"DrawCategoryFromTable(Random,pair)",function() return Lottery.DrawCategoryFromTable(rbx,pair) end)
  if br then
   add(out.trials.lottery,"DrawCategoryFromTable(pair,BetterRandom)",function() return Lottery.DrawCategoryFromTable(pair,br) end)
   add(out.trials.lottery,"DrawCategoryFromTable(BetterRandom,pair)",function() return Lottery.DrawCategoryFromTable(br,pair) end)
  end
  add(out.trials.lottery,"DrawCategoryFromTable(pair,123456)",function() return Lottery.DrawCategoryFromTable(pair,123456) end)
  add(out.trials.lottery,"DrawCategoryFromTable(123456,pair)",function() return Lottery.DrawCategoryFromTable(123456,pair) end)
  add(out.trials.lottery,"DrawCategoryFromTable(map)",function() return Lottery.DrawCategoryFromTable(map) end)
  add(out.trials.lottery,"DrawCategoryFromTable(pair2,Random)",function() return Lottery.DrawCategoryFromTable(pair2,Random.new(123456)) end)
 end
 if Lottery and type(Lottery.DrawCategoryFromRarityTable)=="function" then
  add(out.trials.lottery,"DrawCategoryFromRarityTable(pair,Random)",function() return Lottery.DrawCategoryFromRarityTable(pair,Random.new(123456)) end)
  add(out.trials.lottery,"DrawCategoryFromRarityTable(Random,pair)",function() return Lottery.DrawCategoryFromRarityTable(Random.new(123456),pair) end)
 end
 return out
end

local function esc(s)
 s=tostring(s or ""):gsub("\\","\\\\"):gsub('"','\\"'):gsub("\b","\\b"):gsub("\f","\\f"):gsub("\n","\\n"):gsub("\r","\\r"):gsub("\t","\\t")
 s=s:gsub("[%z\1-\31]",function(c)return string.format("\\u%04x",string.byte(c))end);return '"'..s..'"'
end
local function isarr(t)local n=0;for k in pairs(t)do if type(k)~="number" or k<1 or k%1~=0 then return false,0 end;n=math.max(n,k)end;for i=1,n do if rawget(t,i)==nil then return false,0 end end;return true,n end
local function enc(v,seen)
 local t=type(v);if t=="nil"then return"null"elseif t=="boolean"then return v and"true"or"false"elseif t=="number"then if v~=v or v==math.huge or v==-math.huge then return esc(tostring(v))end;return tostring(v)elseif t=="string"then return esc(v)elseif t~="table"then return esc(tostring(v))end
 seen=seen or{};if seen[v]then return esc("<cycle>")end;seen[v]=true;local a,n=isarr(v);local p={}
 if a then for i=1,n do p[#p+1]=enc(v[i],seen)end;seen[v]=nil;return"["..table.concat(p,",").."]"end
 local ks={};for k in pairs(v)do ks[#ks+1]=tostring(k)end;table.sort(ks);for _,k in ipairs(ks)do p[#p+1]=esc(k)..":"..enc(v[k],seen)end;seen[v]=nil;return"{"..table.concat(p,",").."}"
end

local gui=Instance.new("ScreenGui");gui.Name="PSICO_SIGNATURE_PROBE_V5";gui.ResetOnSpawn=false;gui.DisplayOrder=1405;gui.Parent=CG
local f=Instance.new("Frame");f.AnchorPoint=Vector2.new(.5,.5);f.Position=UDim2.fromScale(.5,.5);f.Size=UDim2.fromOffset(455,220);f.BackgroundColor3=Color3.fromRGB(9,18,34);f.BorderSizePixel=0;f.Parent=gui;Instance.new("UICorner",f).CornerRadius=UDim.new(0,14)
local title=Instance.new("TextLabel");title.BackgroundTransparency=1;title.Position=UDim2.fromOffset(14,10);title.Size=UDim2.new(1,-28,0,28);title.Text="LOTTERY / RNG SIGNATURE PROBE V5";title.Font=Enum.Font.GothamBold;title.TextSize=14;title.TextColor3=Color3.new(1,1,1);title.Parent=f
local st=Instance.new("TextLabel");st.Position=UDim2.fromOffset(14,48);st.Size=UDim2.new(1,-28,0,68);st.BackgroundColor3=Color3.fromRGB(15,29,52);st.BorderSizePixel=0;st.Text="Pronto. Testes controlados apenas com dados locais/sinteticos; nenhuma chamada de Remote.";st.TextWrapped=true;st.Font=Enum.Font.Code;st.TextSize=11;st.TextColor3=Color3.new(1,1,1);st.Parent=f;Instance.new("UICorner",st).CornerRadius=UDim.new(0,9)
local function btn(t,x,w)local b=Instance.new("TextButton");b.Position=UDim2.fromOffset(x,132);b.Size=UDim2.fromOffset(w,38);b.BackgroundColor3=Color3.fromRGB(31,78,132);b.BorderSizePixel=0;b.Text=t;b.TextColor3=Color3.new(1,1,1);b.Font=Enum.Font.GothamBold;b.TextSize=11;b.Parent=f;Instance.new("UICorner",b).CornerRadius=UDim.new(0,9);return b end
local cap=btn("TESTAR + EXPORTAR",14,280);local close=btn("FECHAR",308,132)
cap.MouseButton1Click:Connect(function()st.Text="Executando testes locais controlados...";task.defer(function()local ok,r=pcall(probe);if not ok then st.Text="Erro: "..tostring(r)return end;local ok2,j=pcall(function()return enc(r,{})end);if not ok2 then st.Text="Erro JSON: "..tostring(j)return end;local name="Psico_LotterySignatures_"..os.time()..".json";local wrote=false;if writefile then wrote=pcall(writefile,name,j)end;if setclipboard then pcall(setclipboard,j)end;st.Text=(wrote and"EXPORTADO: "or"COPIADO: ")..name.." | "..#j.." bytes"end)end)
close.MouseButton1Click:Connect(function()gui:Destroy()end)
local drag=false;local ds,sp
f.InputBegan:Connect(function(i)if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then drag=true;ds=i.Position;sp=f.Position end end)
f.InputChanged:Connect(function(i)if drag and(i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch)then local d=i.Position-ds;f.Position=UDim2.new(sp.X.Scale,sp.X.Offset+d.X,sp.Y.Scale,sp.Y.Offset+d.Y)end end)
UIS.InputEnded:Connect(function(i)if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then drag=false end end)

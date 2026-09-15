-- PSICOSENATICO | EGG CYCLE DATA PROBE V10
-- Focused read-only RNG-state and roll-count semantics research.
-- No remotes invoked, no hooks, debug/getgc, HTTP interception or mutation.
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

local SEEDS={5964938,1789481400}
local LUCK_LABELS={30,31,32,40}
local TEST_ROLLS={1,1.3,1.31,1.32,1.4,2,3,30}
local REPEATS=24
local EPS=1e-12

local gui=Instance.new("ScreenGui");gui.Name="PSICO_RNG_STATE_V10";gui.ResetOnSpawn=false;gui.DisplayOrder=1411;gui.Parent=CG
local f=Instance.new("Frame");f.AnchorPoint=Vector2.new(.5,.5);f.Position=UDim2.fromScale(.5,.5);f.Size=UDim2.fromOffset(455,235);f.BackgroundColor3=Color3.fromRGB(9,18,34);f.BorderSizePixel=0;f.Parent=gui;Instance.new("UICorner",f).CornerRadius=UDim.new(0,14)
local title=Instance.new("TextLabel");title.BackgroundTransparency=1;title.Position=UDim2.fromOffset(14,10);title.Size=UDim2.new(1,-28,0,28);title.Text="RNG STATE + ROLL SEMANTICS V10";title.Font=Enum.Font.GothamBold;title.TextSize=14;title.TextColor3=Color3.new(1,1,1);title.Parent=f
local st=Instance.new("TextLabel");st.Position=UDim2.fromOffset(14,48);st.Size=UDim2.new(1,-28,0,82);st.BackgroundColor3=Color3.fromRGB(15,29,52);st.BorderSizePixel=0;st.Text="Pronto. Mede consumo do Random passado ao AssetLottery e testa 1.30/1.31/1.32/1.40 rolls.";st.TextWrapped=true;st.Font=Enum.Font.Code;st.TextSize=11;st.TextColor3=Color3.new(1,1,1);st.Parent=f;Instance.new("UICorner",st).CornerRadius=UDim.new(0,9)
local function btn(t,x,w)local b=Instance.new("TextButton");b.Position=UDim2.fromOffset(x,148);b.Size=UDim2.fromOffset(w,38);b.BackgroundColor3=Color3.fromRGB(31,78,132);b.BorderSizePixel=0;b.Text=t;b.TextColor3=Color3.new(1,1,1);b.Font=Enum.Font.GothamBold;b.TextSize=11;b.Parent=f;Instance.new("UICorner",b).CornerRadius=UDim.new(0,9);return b end
local cap=btn("TESTAR + EXPORTAR",14,280);local close=btn("FECHAR",308,132)

local function areaCfg(name)
 local r=req(AREA_ROOT and AREA_ROOT:FindFirstChild(name));return r
end
local ABYSS=areaCfg("Abyss Ocean")
local TAB=type(ABYSS)=="table" and ABYSS.DropTable or nil
local busy=false
local cancelled=false
local ops=0
local function breathe(msg)
 ops+=1;if msg then st.Text=msg end
 if ops%8==0 then RunService.Heartbeat:Wait() end
end
local function near(a,b)return type(a)=="number" and type(b)=="number" and math.abs(a-b)<=EPS end
local function baseline(seed,n)
 local r=Random.new(seed);local out={}
 for i=1,n do out[i]=r:NextNumber()end
 return out
end
local function findIndex(seq,v)
 for i,x in ipairs(seq)do if near(x,v)then return i end end
 return nil
end
local function rngStateProbe(seed,rolls)
 local base=baseline(seed,32);local out={seed=seed,rolls=rolls,runs={}}
 for i=1,8 do
  if cancelled then break end
  local rng=Random.new(seed)
  local ok,res=pcall(Lottery.DrawCategoryFromTable,rng,TAB,rolls)
  local a1=rng:NextNumber();local a2=rng:NextNumber()
  out.runs[#out.runs+1]={ok=ok,result=ok and res or nil,error=ok and nil or tostring(res),after1=a1,after2=a2,after1BaselineIndex=findIndex(base,a1),after2BaselineIndex=findIndex(base,a2)}
  breathe(string.format("RNG seed %s rolls %.2f run %d/8",tostring(seed),rolls,i))
 end
 out.baselineFirst8={base[1],base[2],base[3],base[4],base[5],base[6],base[7],base[8]}
 return out
end
local function distribution(seed,rolls,repeats)
 local counts={};local errs={};local values={}
 for i=1,repeats do
  if cancelled then break end
  local ok,r=pcall(Lottery.DrawCategoryFromTable,Random.new(seed),TAB,rolls)
  if ok then counts[r]=(counts[r]or 0)+1;values[#values+1]=r else errs[#errs+1]=tostring(r) end
  breathe(string.format("Distribuicao rolls %.2f: %d/%d",rolls,i,repeats))
 end
 return {seed=seed,rolls=rolls,repeats=repeats,counts=counts,errors=errs,values=values}
end
local function safe(label,f,...)
 if type(f)~="function"then return {label=label,available=false}end
 local ok,a,b,c=pcall(f,...)
 return ok and {label=label,available=true,ok=true,values={a,b,c}} or {label=label,available=true,ok=false,error=tostring(a)}
end
local function luckSemantics()
 local out={}
 for _,luck in ipairs(LUCK_LABELS)do
  local rc=safe("RollCountFor("..luck..")",Lottery and Lottery.RollCountFor,luck)
  local rolls=rc.ok and rc.values and rc.values[1] or nil
  local rec={luck=luck,rollCount=rolls,rollCountCall=rc}
  if type(rolls)=="number" then rec.sample=distribution(5964938,rolls,REPEATS) end
  out[#out+1]=rec
 end
 return out
end
local function adminBoostProbe()
 local out={exports={}}
 if type(AdminBoosts)=="table" then
  for k,v in pairs(AdminBoosts)do out.exports[tostring(k)]=type(v)=="function" and "<function>" or tostring(v) end
  if type(AdminBoosts.ReadMultiplier)=="function" then
   local key=AdminBoosts.EGG_SPAWN_LUCK or "EggSpawnLuck"
   out.readMultiplier={
    safe("ReadMultiplier(key)",AdminBoosts.ReadMultiplier,key),
    safe("ReadMultiplier(LocalPlayer,key)",AdminBoosts.ReadMultiplier,game:GetService("Players").LocalPlayer,key),
    safe("ReadMultiplier(key,LocalPlayer)",AdminBoosts.ReadMultiplier,key,game:GetService("Players").LocalPlayer)
   }
  end
 end
 return out
end
local function snapshot()
 local now=os.time();local current=(Cycle and Cycle.PeriodIndexAt and Cycle.PeriodIndexAt(now))or math.floor(now/300)
 local out={meta={version="EggCycleDataProbe10",created=now,currentPeriod=current,placeId=tostring(game.PlaceId),gameId=tostring(game.GameId),jobId=tostring(game.JobId),passive=true,mode="rng-state-roll-semantics",repeats=REPEATS},errors={lottery=lotErr,adminBoosts=boostErr,cycle=cycleErr},rngState={},rollDistributions={},luckSemantics={},adminBoosts={}}
 if not Lottery or type(Lottery.DrawCategoryFromTable)~="function" or type(TAB)~="table" then out.error="missing-lottery-or-abyss-table" return out end
 for _,seed in ipairs(SEEDS)do
  for _,rolls in ipairs({1,1.3,2,30})do out.rngState[#out.rngState+1]=rngStateProbe(seed,rolls)end
 end
 for _,rolls in ipairs(TEST_ROLLS)do out.rollDistributions[#out.rollDistributions+1]=distribution(5964938,rolls,REPEATS)end
 out.luckSemantics=luckSemantics();out.adminBoosts=adminBoostProbe()
 return out
end

local function esc(s)
 s=tostring(s or""):gsub("\\","\\\\"):gsub('"','\\"'):gsub("\b","\\b"):gsub("\f","\\f"):gsub("\n","\\n"):gsub("\r","\\r"):gsub("\t","\\t")
 s=s:gsub("[%z\1-\31]",function(c)return string.format("\\u%04x",string.byte(c))end);return'"'..s..'"'
end
local function arr(t)local n=0;for k in pairs(t)do if type(k)~="number"or k<1 or k%1~=0 then return false,0 end;n=math.max(n,k)end;for i=1,n do if rawget(t,i)==nil then return false,0 end end;return true,n end
local function enc(v,seen)
 local t=typeof(v)
 if t=="nil"then return"null"elseif t=="boolean"then return v and"true"or"false"elseif t=="number"then return tostring(v)elseif t=="string"then return esc(v)elseif t=="Instance"then return esc(v:GetFullName())elseif t~="table"then return esc(tostring(v))end
 seen=seen or{};if seen[v]then return esc("<cycle>")end;seen[v]=true;local a,n=arr(v);local p={}
 if a then for i=1,n do p[#p+1]=enc(v[i],seen)end;seen[v]=nil;return"["..table.concat(p,",").."]"end
 local ks={};for k in pairs(v)do ks[#ks+1]=tostring(k)end;table.sort(ks);for _,k in ipairs(ks)do p[#p+1]=esc(k)..":"..enc(v[k],seen)end;seen[v]=nil;return"{"..table.concat(p,",").."}"
end

cap.MouseButton1Click:Connect(function()
 if busy then return end;busy=true;cancelled=false;ops=0;cap.Text="EXECUTANDO...";st.Text="Iniciando V10..."
 task.spawn(function()
  local ok,r=pcall(snapshot);if not ok then st.Text="Erro: "..tostring(r);busy=false;cap.Text="TESTAR + EXPORTAR";return end
  st.Text="Montando JSON...";RunService.Heartbeat:Wait()
  local ok2,j=pcall(function()return enc(r,{})end);if not ok2 then st.Text="Erro JSON: "..tostring(j);busy=false;cap.Text="TESTAR + EXPORTAR";return end
  local name="Psico_RNGState_"..os.time()..".json";local wrote=false;if writefile then wrote=pcall(writefile,name,j)end
  st.Text=(wrote and"EXPORTADO: "or"CONCLUIDO SEM WRITEFILE: ")..name.." | "..#j.." bytes";busy=false;cap.Text="TESTAR + EXPORTAR"
 end)
end)
close.MouseButton1Click:Connect(function()cancelled=true;gui:Destroy()end)
local drag=false;local ds,sp
f.InputBegan:Connect(function(i)if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then drag=true;ds=i.Position;sp=f.Position end end)
f.InputChanged:Connect(function(i)if drag and(i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch)then local d=i.Position-ds;f.Position=UDim2.new(sp.X.Scale,sp.X.Offset+d.X,sp.Y.Scale,sp.Y.Offset+d.Y)end end)
UIS.InputEnded:Connect(function(i)if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then drag=false end end)

-- PSICOSENATICO | EGG CYCLE DATA PROBE V7.1 MOBILE SAFE
-- Incremental read-only deterministic predictor research.
-- Uses replicated ModuleScripts and local Random objects only.
-- No remotes, hooks, debug/getgc, HTTP interception or game mutation.

local RS=game:GetService("ReplicatedStorage")
local CG=game:GetService("CoreGui")
local UIS=game:GetService("UserInputService")
local RunService=game:GetService("RunService")

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
local SubBiome,subErr=req(at(RS,"Shared","Util","SubBiomeCycle"))
local Cycle,cycleErr=req(at(RS,"Shared","Util","AreaEggCycle"))
local AREA_ROOT=at(RS,"Data","Areas","Configs")
local ASSET_ROOT=at(RS,"Data","Assets","Configs")

local KNOWN={
 {period=5964937,area="Light Dark",targets={"Jellyfish","RazorFang"},axon={"Pure Jellyfish","RazorFang"}},
 {period=5964938,area="Abyss Ocean",targets={"Kraken"},axon={"Kraken"}},
 {period=5964938,area="Light Dark",targets={"Dark Gargoyle"},axon={"Gargoyle"}},
 {period=5964940,area="Volcano",targets={"Dragon"},axon={"Lava Dragon"}},
 {period=5964944,area="Volcano",targets={"Cerberus"},axon={"Cerberus"}},
 {period=5964947,area="Prehistoric",targets={"Mosasaurus"},axon={"Mosasaurus"}},
 {period=5964948,area="Cosmic",targets={"Eternal Lunar Dragon"},axon={"Eternal Lunar Dragon"}},
 {period=5964950,area="Cosmic",targets={"Alien Skeleton Boss"},axon={"Cosmic Skeleton Boss"}},
 {period=5964951,area="Light Dark",targets={"Pegasus"},axon={"Pegasus"}},
}
local LUCKS={1,2,4,8,16,32,64,128,256}
local SEQ_LIMIT=48
local YIELD_EVERY=6

local gui=Instance.new("ScreenGui");gui.Name="PSICO_PREDICTOR_SWEEP_V71";gui.ResetOnSpawn=false;gui.DisplayOrder=1408;gui.Parent=CG
local f=Instance.new("Frame");f.AnchorPoint=Vector2.new(.5,.5);f.Position=UDim2.fromScale(.5,.5);f.Size=UDim2.fromOffset(455,230);f.BackgroundColor3=Color3.fromRGB(9,18,34);f.BorderSizePixel=0;f.Parent=gui;Instance.new("UICorner",f).CornerRadius=UDim.new(0,14)
local title=Instance.new("TextLabel");title.BackgroundTransparency=1;title.Position=UDim2.fromOffset(14,10);title.Size=UDim2.new(1,-28,0,28);title.Text="PREDICTOR SWEEP V7.1 - MOBILE SAFE";title.Font=Enum.Font.GothamBold;title.TextSize=14;title.TextColor3=Color3.new(1,1,1);title.Parent=f
local st=Instance.new("TextLabel");st.Position=UDim2.fromOffset(14,48);st.Size=UDim2.new(1,-28,0,78);st.BackgroundColor3=Color3.fromRGB(15,29,52);st.BorderSizePixel=0;st.Text="Pronto. Trabalho dividido em blocos para nao congelar o celular.";st.TextWrapped=true;st.Font=Enum.Font.Code;st.TextSize=11;st.TextColor3=Color3.new(1,1,1);st.Parent=f;Instance.new("UICorner",st).CornerRadius=UDim.new(0,9)
local function btn(t,x,w)local b=Instance.new("TextButton");b.Position=UDim2.fromOffset(x,142);b.Size=UDim2.fromOffset(w,38);b.BackgroundColor3=Color3.fromRGB(31,78,132);b.BorderSizePixel=0;b.Text=t;b.TextColor3=Color3.new(1,1,1);b.Font=Enum.Font.GothamBold;b.TextSize=11;b.Parent=f;Instance.new("UICorner",b).CornerRadius=UDim.new(0,9);return b end
local cap=btn("TESTAR + EXPORTAR",14,280);local close=btn("FECHAR",308,132)

local cancelled=false
local busy=false
local ops=0
local function breathe(msg)
 ops+=1
 if msg then st.Text=msg end
 if ops%YIELD_EVERY==0 then RunService.Heartbeat:Wait() end
end

local function areaCfg(name)
 local m=AREA_ROOT and AREA_ROOT:FindFirstChild(name)
 local r=req(m);return r
end
local function assetInfo(id)
 local m=ASSET_ROOT and ASSET_ROOT:FindFirstChild(id)
 local r=req(m)
 if type(r)=="table" then return {id=id,displayName=r.DisplayName,rarity=r.Rarity and r.Rarity.DisplayName,visualOdds=r.VisualOdds,dropWeight=r.DropWeight} end
 return {id=id,missing=true}
end
local function contains(list,v)
 for _,x in ipairs(list)do if x==v then return true end end
 return false
end
local function effectiveTable(rec,cfg)
 if rec.area=="Light Dark" and SubBiome and type(SubBiome.RolledForPeriod)=="function" then
  local ok,r=pcall(SubBiome.RolledForPeriod,rec.area,rec.period)
  if ok and type(r)=="table" and type(r.DropTable)=="table" then return r.DropTable,{id=r.Id,displayName=r.DisplayName} end
  return cfg.DropTable,{error=ok and"no-table"or tostring(r)}
 end
 return cfg.DropTable,nil
end
local function targetPresence(tab,targets)
 local out={}
 for _,id in ipairs(targets)do out[id]=false end
 for _,p in ipairs(tab or{})do if out[p[1]]~=nil then out[p[1]]=true end end
 return out
end

local function drawOnce(seed,tab,luck)
 local ok,r=pcall(Lottery.DrawCategoryFromTable,Random.new(seed),tab,luck)
 return {ok=ok,value=ok and r or nil,error=ok and nil or tostring(r)}
end
local function sequence(seed,tab,targets,label,progressBase,progressTotal)
 local rng=Random.new(seed);local first16={};local hits={}
 for i=1,SEQ_LIMIT do
  if cancelled then return {cancelled=true} end
  local ok,r=pcall(Lottery.DrawCategoryFromTable,rng,tab,1)
  if not ok then return {ok=false,error=tostring(r),seed=seed,label=label} end
  if i<=16 then first16[#first16+1]=r end
  if contains(targets,r)then hits[#hits+1]={index=i,value=r} end
  breathe(string.format("Sequencia %s: %d/%d | etapa %d/%d",label,i,SEQ_LIMIT,progressBase,progressTotal))
 end
 return {ok=true,seed=seed,label=label,first16=first16,hits=hits}
end

local function sweep(rec,index,total)
 local cfg=areaCfg(rec.area)
 local out={periodIndex=rec.period,area=rec.area,axon=rec.axon,targets=rec.targets,assets={}}
 for _,id in ipairs(rec.targets)do out.assets[#out.assets+1]=assetInfo(id) end
 if type(cfg)~="table" or type(cfg.DropTable)~="table" then out.error="area-config-missing" return out end
 local tab,sub=effectiveTable(rec,cfg);out.subBiome=sub;out.targetPresence=targetPresence(tab,rec.targets)
 out.luckSweep={}
 for _,seedRec in ipairs({{label="period",value=rec.period},{label="periodStart",value=rec.period*300}})do
  local row={seedLabel=seedRec.label,seed=seedRec.value,results={}}
  for _,luck in ipairs(LUCKS)do
   if cancelled then out.cancelled=true return out end
   local r=drawOnce(seedRec.value,tab,luck);r.luck=luck;r.target=r.ok and contains(rec.targets,r.value)or false
   row.results[#row.results+1]=r
   breathe(string.format("Teste %d/%d | %s luck %d",index,total,rec.area,luck))
  end
  out.luckSweep[#out.luckSweep+1]=row
 end
 out.sequences={
  sequence(rec.period,tab,rec.targets,"period",index,total),
  sequence(rec.period*300,tab,rec.targets,"periodStart",index,total)
 }
 return out
end

local function snapshot()
 local now=os.time();local current=(Cycle and Cycle.PeriodIndexAt and Cycle.PeriodIndexAt(now))or math.floor(now/300)
 local out={meta={version="EggCycleDataProbe7.1",created=now,currentPeriod=current,placeId=tostring(game.PlaceId),gameId=tostring(game.GameId),jobId=tostring(game.JobId),passive=true,mode="mobile-safe-deterministic-sweep",sequenceLimit=SEQ_LIMIT,lucks=LUCKS},errors={lottery=lotErr,subBiome=subErr,cycle=cycleErr},known={}}
 for i,r in ipairs(KNOWN)do
  if cancelled then out.cancelled=true break end
  st.Text=string.format("Analisando alvo %d/%d: %s",i,#KNOWN,r.area)
  out.known[i]=sweep(r,i,#KNOWN)
  RunService.Heartbeat:Wait()
 end
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

cap.MouseButton1Click:Connect(function()
 if busy then return end
 busy=true;cancelled=false;ops=0;cap.Text="EXECUTANDO..."
 task.spawn(function()
  local ok,r=pcall(snapshot)
  if not ok then st.Text="Erro: "..tostring(r);busy=false;cap.Text="TESTAR + EXPORTAR";return end
  st.Text="Montando JSON...";RunService.Heartbeat:Wait()
  local ok2,j=pcall(function()return enc(r,{})end)
  if not ok2 then st.Text="Erro JSON: "..tostring(j);busy=false;cap.Text="TESTAR + EXPORTAR";return end
  local name="Psico_DeterministicSweep_"..os.time()..".json";local wrote=false
  if writefile then wrote=pcall(writefile,name,j)end
  -- Clipboard is intentionally skipped on mobile-safe mode; large JSON clipboard copies can freeze executors.
  st.Text=(wrote and"EXPORTADO: "or"CONCLUIDO SEM WRITEFILE: ")..name.." | "..#j.." bytes"
  busy=false;cap.Text="TESTAR + EXPORTAR"
 end)
end)
close.MouseButton1Click:Connect(function()cancelled=true;gui:Destroy()end)

local drag=false;local ds,sp
f.InputBegan:Connect(function(i)if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then drag=true;ds=i.Position;sp=f.Position end end)
f.InputChanged:Connect(function(i)if drag and(i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch)then local d=i.Position-ds;f.Position=UDim2.new(sp.X.Scale,sp.X.Offset+d.X,sp.Y.Scale,sp.Y.Offset+d.Y)end end)
UIS.InputEnded:Connect(function(i)if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then drag=false end end)

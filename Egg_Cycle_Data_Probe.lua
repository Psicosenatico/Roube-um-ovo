-- PSICOSENATICO | EGG CYCLE DATA PROBE V7
-- Controlled read-only predictor research.
-- Uses only replicated ModuleScripts and local synthetic RNGs.
-- No remotes, hooks, debug/getgc, HTTP interception or game mutation.

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
 local ok,r=pcall(require,m); if ok then return r,nil end; return nil,tostring(r)
end

local Lottery,lotErr=req(at(RS,"Shared","Util","AssetLottery"))
local SubBiome,subErr=req(at(RS,"Shared","Util","SubBiomeCycle"))
local Cycle,cycleErr=req(at(RS,"Shared","Util","AreaEggCycle"))
local GenerateSeed,seedErr=req(at(RS,"UserGenerated","IO","Crypto","GenerateSeed"))
local Positional,posErr=req(at(RS,"UserGenerated","IO","Crypto","PositionalRandom"))
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
local LUCKS={1,2,3,4,5,8,10,12,16,20,24,32,40,48,64,96,128,192,256}

local function clean(v,d,seen,budget)
 d=d or 0; seen=seen or {}; budget=budget or {n=0,max=12000}; budget.n+=1
 if budget.n>budget.max then return "<budget-limit>" end
 local t=typeof(v)
 if t=="nil" or t=="boolean" or t=="string" or t=="number" then return v end
 if t=="Instance" then return {__type="Instance",class=v.ClassName,path=v:GetFullName()} end
 if t=="function" then return "<function>" end
 if t~="table" then return tostring(v) end
 if seen[v] then return "<cycle>" end
 if d>=6 then return "<depth-limit>" end
 seen[v]=true; local o={}; local n=0
 for k,z in pairs(v) do n+=1; if n>700 then o["<truncated>"]=true break end; o[tostring(k)]=clean(z,d+1,seen,budget) end
 seen[v]=nil; return o
end

local function safe(label,f,...)
 if type(f)~="function" then return {label=label,available=false} end
 local ok,a,b,c=pcall(f,...)
 if not ok then return {label=label,available=true,ok=false,error=tostring(a)} end
 return {label=label,available=true,ok=true,values=clean({a,b,c})}
end

local function areaCfg(name)
 local m=AREA_ROOT and AREA_ROOT:FindFirstChild(name)
 local r=req(m); return r
end
local function assetDisplay(id)
 local m=ASSET_ROOT and ASSET_ROOT:FindFirstChild(id)
 local r=req(m)
 if type(r)=="table" then return {id=id,DisplayName=r.DisplayName,Rarity=r.Rarity and r.Rarity.DisplayName,DropWeight=r.DropWeight,VisualOdds=r.VisualOdds} end
 return {id=id,missing=true}
end
local function contains(list,v)
 for _,x in ipairs(list) do if x==v then return true end end
 return false
end
local function draw(rng,tab,luck)
 return Lottery.DrawCategoryFromTable(rng,tab,luck)
end

local function probeSeed(period,area)
 local out={}
 if type(GenerateSeed)=="function" then
  local trials={{"number",period},{"string",tostring(period)}}
  for _,x in ipairs(trials) do
   local ok,r=pcall(GenerateSeed,x[2]); local rec={label="GenerateSeed("..x[1]..")",ok=ok}
   if ok then
    rec.value=clean(r)
    if Positional then
     rec.double=safe("DoubleFromInt64(seed)",Positional.DoubleFromInt64,r)
     rec.mixSelf=safe("Mix(seed,seed)",Positional.Mix,r,r)
    end
   else rec.error=tostring(r) end
   out[#out+1]=rec
  end
  for _,args in ipairs({{"area,period",area,period},{"period,area",period,area}}) do
   local ok,r=pcall(GenerateSeed,args[2],args[3]); out[#out+1]={label="GenerateSeed("..args[1]..")",ok=ok,value=ok and clean(r) or nil,error=ok and nil or tostring(r)}
  end
 end
 return out
end

local function sequence(tab,seed,limit,targetSet)
 local rng=Random.new(seed); local first32={}; local hits={}; local counts={}
 for i=1,limit do
  local ok,r=pcall(draw,rng,tab,1)
  if not ok then return {ok=false,error=tostring(r),seed=seed} end
  counts[r]=(counts[r] or 0)+1
  if i<=32 then first32[#first32+1]=r end
  if contains(targetSet,r) then hits[#hits+1]={index=i,value=r} end
 end
 return {ok=true,seed=seed,first32=first32,hits=hits,counts=counts}
end

local function sweep(rec)
 local cfg=areaCfg(rec.area)
 local out={periodIndex=rec.period,area=rec.area,axon=rec.axon,targets=rec.targets,assetMappings={}}
 for _,id in ipairs(rec.targets) do out.assetMappings[#out.assetMappings+1]=assetDisplay(id) end
 if type(cfg)~="table" then out.error="area-config-missing" return out end
 local base=cfg.DropTable
 local rolled=nil
 if rec.area=="Light Dark" and SubBiome and type(SubBiome.RolledForPeriod)=="function" then
  local ok,r=pcall(SubBiome.RolledForPeriod,rec.area,rec.period); if ok then rolled=r; out.subBiome=clean(r) else out.subBiomeError=tostring(r) end
 end
 local effective=(type(rolled)=="table" and rolled.DropTable) or base
 out.baseDropTable=clean(base); out.effectiveDropTable=clean(effective)
 out.targetPresence={}
 for _,id in ipairs(rec.targets) do
  local b,e=false,false
  for _,p in ipairs(base or {}) do if p[1]==id then b=true end end
  for _,p in ipairs(effective or {}) do if p[1]==id then e=true end end
  out.targetPresence[id]={base=b,effective=e}
 end
 out.luckSweep={}
 if Lottery and type(Lottery.DrawCategoryFromTable)=="function" and type(effective)=="table" then
  local seeds={{label="period",value=rec.period},{label="periodStart",value=rec.period*300}}
  for _,s in ipairs(seeds) do
   local row={seedLabel=s.label,seed=s.value,results={}}
   for _,luck in ipairs(LUCKS) do
    local ok,r=pcall(draw,Random.new(s.value),effective,luck)
    row.results[#row.results+1]={luck=luck,ok=ok,value=ok and r or nil,error=ok and nil or tostring(r),target=ok and contains(rec.targets,r) or false}
   end
   out.luckSweep[#out.luckSweep+1]=row
  end
  out.sequences={sequence(effective,rec.period,128,rec.targets),sequence(effective,rec.period*300,128,rec.targets)}
 end
 out.seedProbe=probeSeed(rec.period,rec.area)
 return out
end

local function rollCountProbe()
 local out={}
 if not Lottery or type(Lottery.RollCountFor)~="function" then return out end
 for _,v in ipairs({0,0.5,1,2,3,5,10,20,50,100,250}) do out[#out+1]=safe("RollCountFor("..tostring(v)..")",Lottery.RollCountFor,v) end
 return out
end

local function snapshot()
 local now=os.time(); local current=Cycle and Cycle.PeriodIndexAt and Cycle.PeriodIndexAt(now) or math.floor(now/300)
 local out={meta={version="EggCycleDataProbe7",created=now,currentPeriod=current,placeId=tostring(game.PlaceId),gameId=tostring(game.GameId),jobId=tostring(game.JobId),passive=true,mode="deterministic-lottery-sweep"},errors={lottery=lotErr,subBiome=subErr,cycle=cycleErr,generateSeed=seedErr,positional=posErr},rollCount=rollCountProbe(),known={}}
 for i,r in ipairs(KNOWN) do out.known[i]=sweep(r) end
 return out
end

local function esc(s)
 s=tostring(s or ""):gsub("\\","\\\\"):gsub('"','\\"'):gsub("\b","\\b"):gsub("\f","\\f"):gsub("\n","\\n"):gsub("\r","\\r"):gsub("\t","\\t")
 s=s:gsub("[%z\1-\31]",function(c)return string.format("\\u%04x",string.byte(c))end); return '"'..s..'"'
end
local function arr(t)local n=0;for k in pairs(t)do if type(k)~="number" or k<1 or k%1~=0 then return false,0 end;n=math.max(n,k)end;for i=1,n do if rawget(t,i)==nil then return false,0 end end;return true,n end
local function enc(v,seen)
 local t=type(v); if t=="nil"then return"null"elseif t=="boolean"then return v and"true"or"false"elseif t=="number"then return tostring(v)elseif t=="string"then return esc(v)elseif t~="table"then return esc(tostring(v))end
 seen=seen or{};if seen[v]then return esc("<cycle>")end;seen[v]=true;local a,n=arr(v);local p={}
 if a then for i=1,n do p[#p+1]=enc(v[i],seen)end;seen[v]=nil;return"["..table.concat(p,",").."]"end
 local ks={};for k in pairs(v)do ks[#ks+1]=tostring(k)end;table.sort(ks);for _,k in ipairs(ks)do p[#p+1]=esc(k)..":"..enc(v[k],seen)end;seen[v]=nil;return"{"..table.concat(p,",").."}"
end

local gui=Instance.new("ScreenGui");gui.Name="PSICO_PREDICTOR_SWEEP_V7";gui.ResetOnSpawn=false;gui.DisplayOrder=1407;gui.Parent=CG
local f=Instance.new("Frame");f.AnchorPoint=Vector2.new(.5,.5);f.Position=UDim2.fromScale(.5,.5);f.Size=UDim2.fromOffset(455,220);f.BackgroundColor3=Color3.fromRGB(9,18,34);f.BorderSizePixel=0;f.Parent=gui;Instance.new("UICorner",f).CornerRadius=UDim.new(0,14)
local title=Instance.new("TextLabel");title.BackgroundTransparency=1;title.Position=UDim2.fromOffset(14,10);title.Size=UDim2.new(1,-28,0,28);title.Text="PREDICTOR DETERMINISTIC SWEEP V7";title.Font=Enum.Font.GothamBold;title.TextSize=14;title.TextColor3=Color3.new(1,1,1);title.Parent=f
local st=Instance.new("TextLabel");st.Position=UDim2.fromOffset(14,48);st.Size=UDim2.new(1,-28,0,68);st.BackgroundColor3=Color3.fromRGB(15,29,52);st.BorderSizePixel=0;st.Text="Pronto. Testa assinatura confirmada, luck/rolls, sequencias e seeds locais contra periodos historicos do Axon.";st.TextWrapped=true;st.Font=Enum.Font.Code;st.TextSize=11;st.TextColor3=Color3.new(1,1,1);st.Parent=f;Instance.new("UICorner",st).CornerRadius=UDim.new(0,9)
local function btn(t,x,w)local b=Instance.new("TextButton");b.Position=UDim2.fromOffset(x,132);b.Size=UDim2.fromOffset(w,38);b.BackgroundColor3=Color3.fromRGB(31,78,132);b.BorderSizePixel=0;b.Text=t;b.TextColor3=Color3.new(1,1,1);b.Font=Enum.Font.GothamBold;b.TextSize=11;b.Parent=f;Instance.new("UICorner",b).CornerRadius=UDim.new(0,9);return b end
local cap=btn("TESTAR + EXPORTAR",14,280);local close=btn("FECHAR",308,132)
cap.MouseButton1Click:Connect(function()st.Text="Executando sweep local...";task.defer(function()local ok,r=pcall(snapshot);if not ok then st.Text="Erro: "..tostring(r)return end;local ok2,j=pcall(function()return enc(r,{})end);if not ok2 then st.Text="Erro JSON: "..tostring(j)return end;local name="Psico_DeterministicSweep_"..os.time()..".json";local wrote=false;if writefile then wrote=pcall(writefile,name,j)end;if setclipboard then pcall(setclipboard,j)end;st.Text=(wrote and"EXPORTADO: "or"COPIADO: ")..name.." | "..#j.." bytes"end)end)
close.MouseButton1Click:Connect(function()gui:Destroy()end)
local drag=false;local ds,sp
f.InputBegan:Connect(function(i)if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then drag=true;ds=i.Position;sp=f.Position end end)
f.InputChanged:Connect(function(i)if drag and(i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch)then local d=i.Position-ds;f.Position=UDim2.new(sp.X.Scale,sp.X.Offset+d.X,sp.Y.Scale,sp.Y.Offset+d.Y)end end)
UIS.InputEnded:Connect(function(i)if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then drag=false end end)

-- PSICOSENATICO | EGG CYCLE DATA PROBE V8
-- Focused read-only test: Axon chance labels vs AssetLottery luck semantics.
-- Also inventories replicated luck/boost state. No remotes, hooks, debug/getgc or mutation.

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
local SubBiome,subErr=req(at(RS,"Shared","Util","SubBiomeCycle"))
local Cycle,cycleErr=req(at(RS,"Shared","Util","AreaEggCycle"))
local AREA_ROOT=at(RS,"Data","Areas","Configs")

local KNOWN={
 {period=5964937,area="Light Dark",target="Jellyfish",axon="Pure Jellyfish",chance=40},
 {period=5964937,area="Light Dark",target="RazorFang",axon="RazorFang",chance=31},
 {period=5964938,area="Abyss Ocean",target="Kraken",axon="Kraken",chance=32},
 {period=5964938,area="Light Dark",target="Dark Gargoyle",axon="Gargoyle",chance=40},
 {period=5964940,area="Volcano",target="Dragon",axon="Lava Dragon",chance=30},
 {period=5964944,area="Volcano",target="Cerberus",axon="Cerberus",chance=32},
 {period=5964947,area="Prehistoric",target="Mosasaurus",axon="Mosasaurus",chance=32},
 {period=5964948,area="Cosmic",target="Eternal Lunar Dragon",axon="Eternal Lunar Dragon",chance=30},
 {period=5964950,area="Cosmic",target="Alien Skeleton Boss",axon="Cosmic Skeleton Boss",chance=31},
 {period=5964951,area="Light Dark",target="Pegasus",axon="Pegasus",chance=30},
}
local ROLL_VALUES={0,0.5,1,2,4,8,16,30,31,32,40,64,128,256}

local function simple(v,d,seen)
 d=d or 0;seen=seen or{}
 local t=typeof(v)
 if t=="nil" or t=="boolean" or t=="string" or t=="number" then return v end
 if t=="Instance" then return {class=v.ClassName,path=v:GetFullName()} end
 if t=="function" then return "<function>" end
 if t~="table" then return tostring(v) end
 if seen[v] or d>=4 then return "<cycle/depth>" end
 seen[v]=true;local o={};local n=0
 for k,z in pairs(v)do n+=1;if n>200 then o["<truncated>"]=true break end;o[tostring(k)]=simple(z,d+1,seen)end
 seen[v]=nil;return o
end
local function safe(label,f,...)
 if type(f)~="function" then return {label=label,available=false} end
 local ok,a,b,c=pcall(f,...)
 if not ok then return {label=label,available=true,ok=false,error=tostring(a)} end
 return {label=label,available=true,ok=true,values=simple({a,b,c})}
end
local function areaCfg(name)
 local r=req(AREA_ROOT and AREA_ROOT:FindFirstChild(name));return r
end
local function effective(rec,cfg)
 if rec.area=="Light Dark" and SubBiome and type(SubBiome.RolledForPeriod)=="function" then
  local ok,r=pcall(SubBiome.RolledForPeriod,rec.area,rec.period)
  if ok and type(r)=="table" and type(r.DropTable)=="table" then return r.DropTable,{id=r.Id,displayName=r.DisplayName} end
 end
 return cfg and cfg.DropTable,nil
end
local function has(tab,id)
 for _,p in ipairs(tab or{})do if p[1]==id then return true end end
 return false
end
local function exactChance(rec)
 local cfg=areaCfg(rec.area);local tab,sub=effective(rec,cfg)
 local out={periodIndex=rec.period,area=rec.area,target=rec.target,axon=rec.axon,axonChance=rec.chance,subBiome=sub,targetPresent=has(tab,rec.target)}
 if type(tab)~="table" or not Lottery or type(Lottery.DrawCategoryFromTable)~="function" then out.error="missing-table-or-lottery" return out end
 for _,seedRec in ipairs({{label="period",value=rec.period},{label="periodStart",value=rec.period*300}})do
  local t=safe(seedRec.label.." chance="..rec.chance,Lottery.DrawCategoryFromTable,Random.new(seedRec.value),tab,rec.chance)
  local value=t.ok and t.values and t.values["1"] or nil
  t.seed=seedRec.value;t.result=value;t.matchesTarget=(value==rec.target)
  if t.values then t.values=nil end
  out[seedRec.label]=t
 end
 return out
end
local function rollCount()
 local out={}
 for _,v in ipairs(ROLL_VALUES)do out[#out+1]=safe("RollCountFor("..tostring(v)..")",Lottery and Lottery.RollCountFor,v) end
 return out
end
local function tokenChanceTests()
 local out={}
 if not Lottery then return out end
 out[#out+1]=safe("TokenChances()",Lottery.TokenChances)
 for _,v in ipairs({1,30,31,32,40,128})do
  out[#out+1]=safe("TokenChances("..v..")",Lottery.TokenChances,v)
 end
 return out
end
local function relevantReplicated()
 local out={}
 local words={"luck","boost","fieldegg","rareegg","rollcount"}
 for _,x in ipairs(RS:GetDescendants())do
  local p=string.lower(x:GetFullName());local hit=false
  for _,w in ipairs(words)do if string.find(p,w,1,true)then hit=true break end end
  if hit then
   local r={path=x:GetFullName(),class=x.ClassName,name=x.Name,attributes=simple(x:GetAttributes())}
   if x:IsA("ValueBase")then r.value=simple(x.Value) end
   out[#out+1]=r
   if #out>=250 then break end
  end
 end
 return out
end
local function commandExports()
 local out={}
 for _,name in ipairs({"globalEggLuckBoost","spawnRareEgg","globalSpawnRareEgg"})do
  local m=at(RS,"CmdrClient","Commands",name)
  local r,e=req(m);out[name]={path=m and m:GetFullName() or nil,requireOk=(r~=nil),error=e,export=simple(r)}
 end
 return out
end
local function snapshot()
 local now=os.time();local current=(Cycle and Cycle.PeriodIndexAt and Cycle.PeriodIndexAt(now))or math.floor(now/300)
 local out={meta={version="EggCycleDataProbe8",created=now,currentPeriod=current,placeId=tostring(game.PlaceId),gameId=tostring(game.GameId),jobId=tostring(game.JobId),passive=true,mode="chance-semantics"},errors={lottery=lotErr,subBiome=subErr,cycle=cycleErr},rollCount=rollCount(),tokenChances=tokenChanceTests(),known={},replicatedLuck=relevantReplicated(),commandExports=commandExports()}
 for i,r in ipairs(KNOWN)do out.known[i]=exactChance(r) end
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

local gui=Instance.new("ScreenGui");gui.Name="PSICO_CHANCE_SEMANTICS_V8";gui.ResetOnSpawn=false;gui.DisplayOrder=1409;gui.Parent=CG
local f=Instance.new("Frame");f.AnchorPoint=Vector2.new(.5,.5);f.Position=UDim2.fromScale(.5,.5);f.Size=UDim2.fromOffset(455,220);f.BackgroundColor3=Color3.fromRGB(9,18,34);f.BorderSizePixel=0;f.Parent=gui;Instance.new("UICorner",f).CornerRadius=UDim.new(0,14)
local title=Instance.new("TextLabel");title.BackgroundTransparency=1;title.Position=UDim2.fromOffset(14,10);title.Size=UDim2.new(1,-28,0,28);title.Text="AXON CHANCE SEMANTICS V8";title.Font=Enum.Font.GothamBold;title.TextSize=14;title.TextColor3=Color3.new(1,1,1);title.Parent=f
local st=Instance.new("TextLabel");st.Position=UDim2.fromOffset(14,48);st.Size=UDim2.new(1,-28,0,70);st.BackgroundColor3=Color3.fromRGB(15,29,52);st.BorderSizePixel=0;st.Text="Pronto. Teste curto: chance 30/31/32/40, RollCountFor e estado Luck replicado.";st.TextWrapped=true;st.Font=Enum.Font.Code;st.TextSize=11;st.TextColor3=Color3.new(1,1,1);st.Parent=f;Instance.new("UICorner",st).CornerRadius=UDim.new(0,9)
local function btn(t,x,w)local b=Instance.new("TextButton");b.Position=UDim2.fromOffset(x,134);b.Size=UDim2.fromOffset(w,38);b.BackgroundColor3=Color3.fromRGB(31,78,132);b.BorderSizePixel=0;b.Text=t;b.TextColor3=Color3.new(1,1,1);b.Font=Enum.Font.GothamBold;b.TextSize=11;b.Parent=f;Instance.new("UICorner",b).CornerRadius=UDim.new(0,9);return b end
local cap=btn("TESTAR + EXPORTAR",14,280);local close=btn("FECHAR",308,132)
local busy=false
cap.MouseButton1Click:Connect(function()
 if busy then return end;busy=true;cap.Text="EXECUTANDO...";st.Text="Executando teste curto..."
 task.spawn(function()
  local ok,r=pcall(snapshot);if not ok then st.Text="Erro: "..tostring(r);busy=false;cap.Text="TESTAR + EXPORTAR";return end
  local ok2,j=pcall(function()return enc(r,{})end);if not ok2 then st.Text="Erro JSON: "..tostring(j);busy=false;cap.Text="TESTAR + EXPORTAR";return end
  local name="Psico_ChanceSemantics_"..os.time()..".json";local wrote=false;if writefile then wrote=pcall(writefile,name,j)end
  st.Text=(wrote and"EXPORTADO: "or"CONCLUIDO SEM WRITEFILE: ")..name.." | "..#j.." bytes";busy=false;cap.Text="TESTAR + EXPORTAR"
 end)
end)
close.MouseButton1Click:Connect(function()gui:Destroy()end)
local drag=false;local ds,sp
f.InputBegan:Connect(function(i)if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then drag=true;ds=i.Position;sp=f.Position end end)
f.InputChanged:Connect(function(i)if drag and(i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch)then local d=i.Position-ds;f.Position=UDim2.new(sp.X.Scale,sp.X.Offset+d.X,sp.Y.Scale,sp.Y.Offset+d.Y)end end)
UIS.InputEnded:Connect(function(i)if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then drag=false end end)

-- PSICOSENATICO | EGG CYCLE DATA PROBE V4
-- Read-only inspection of selected replicated ModuleScript exports.
-- No function calls from inspected modules, no remotes, hooks, debug/getgc, HTTP interception or game mutation.

local RS=game:GetService("ReplicatedStorage")
local CG=game:GetService("CoreGui")
local UIS=game:GetService("UserInputService")

local TARGETS={
 "ReplicatedStorage.Shared.Util.AssetLottery",
 "ReplicatedStorage.Shared.Modules.BetterRandom",
 "ReplicatedStorage.UserGenerated.IO.Crypto.GenerateSeed",
 "ReplicatedStorage.UserGenerated.IO.Crypto.PositionalRandom",
 "ReplicatedStorage.UserGenerated.Randoms",
 "ReplicatedStorage.UserGenerated.Randoms.Base",
 "ReplicatedStorage.UserGenerated.Randoms.ISAAC",
 "ReplicatedStorage.UserGenerated.Randoms.Xorshift128",
 "ReplicatedStorage.Shared.Util.AssetRollScaleWeights",
 "ReplicatedStorage.Shared.Util.AssetItems",
 "ReplicatedStorage.Shared.Util.SubBiomeCycle",
 "ReplicatedStorage.Shared.Util.AreaEggCycle",
 "ReplicatedStorage.Data.Assets",
 "ReplicatedStorage.Data.Rarity"
}

local function resolve(p)
 local cur=game
 for part in string.gmatch(p,"[^%.]+") do
  if part=="ReplicatedStorage" then cur=RS else cur=cur and cur:FindFirstChild(part) end
  if not cur then return nil end
 end
 return cur
end

local function clean(v,d,seen,budget)
 d=d or 0;seen=seen or{};budget=budget or{n=0,max=20000};budget.n+=1
 if budget.n>budget.max then return "<budget-limit>" end
 local t=typeof(v)
 if t=="nil" or t=="boolean" or t=="string" or t=="number" then return v end
 if t=="Instance" then return {__type="Instance",class=v.ClassName,path=v:GetFullName()} end
 if t=="function" then return "<function>" end
 if t=="thread" then return "<thread>" end
 if t=="userdata" then return tostring(v) end
 if t~="table" then return tostring(v) end
 if seen[v] then return "<cycle>" end
 if d>=8 then return "<depth-limit>" end
 seen[v]=true;local o={};local n=0
 for k,z in pairs(v)do n+=1;if n>1000 then o["<truncated>"]="more than 1000 keys" break end;o[tostring(k)]=clean(z,d+1,seen,budget)end
 seen[v]=nil;return o
end

local function inspectModule(p)
 local m=resolve(p)
 if not m then return {path=p,found=false} end
 local out={path=p,found=true,class=m.ClassName,name=m.Name,attributes=clean(m:GetAttributes())}
 if not m:IsA("ModuleScript") then return out end
 local ok,res=pcall(require,m)
 out.requireOk=ok
 if ok then out.returnType=typeof(res);out.export=clean(res) else out.error=tostring(res) end
 return out
end

local function snapshot()
 local out={meta={version="EggCycleDataProbe4",created=os.time(),placeId=tostring(game.PlaceId),gameId=tostring(game.GameId),jobId=tostring(game.JobId),passive=true,mode="module-export-inspection"},targets={}}
 for _,p in ipairs(TARGETS)do out.targets[p]=inspectModule(p) end
 return out
end

local function esc(s)
 s=tostring(s or ""):gsub("\\","\\\\"):gsub('"','\\"'):gsub("\b","\\b"):gsub("\f","\\f"):gsub("\n","\\n"):gsub("\r","\\r"):gsub("\t","\\t")
 s=s:gsub("[%z\1-\31]",function(c)return string.format("\\u%04x",string.byte(c))end)
 return '"'..s..'"'
end
local function isarr(t)
 local n=0;for k in pairs(t)do if type(k)~="number" or k<1 or k%1~=0 then return false,0 end;n=math.max(n,k)end
 for i=1,n do if rawget(t,i)==nil then return false,0 end end;return true,n
end
local function enc(v,seen)
 local t=type(v)
 if t=="nil" then return"null" elseif t=="boolean" then return v and"true"or"false" elseif t=="number" then return tostring(v) elseif t=="string" then return esc(v) elseif t~="table" then return esc(tostring(v)) end
 seen=seen or{};if seen[v]then return esc("<cycle>")end;seen[v]=true
 local a,n=isarr(v);local p={}
 if a then for i=1,n do p[#p+1]=enc(v[i],seen)end;seen[v]=nil;return"["..table.concat(p,",").."]"end
 local ks={};for k in pairs(v)do ks[#ks+1]=tostring(k)end;table.sort(ks)
 for _,k in ipairs(ks)do p[#p+1]=esc(k)..":"..enc(v[k],seen)end
 seen[v]=nil;return"{"..table.concat(p,",").."}"
end

local gui=Instance.new("ScreenGui");gui.Name="PSICO_LOTTERY_EXPORTS";gui.ResetOnSpawn=false;gui.DisplayOrder=1404;gui.Parent=CG
local f=Instance.new("Frame");f.AnchorPoint=Vector2.new(.5,.5);f.Position=UDim2.fromScale(.5,.5);f.Size=UDim2.fromOffset(450,215);f.BackgroundColor3=Color3.fromRGB(9,18,34);f.BorderSizePixel=0;f.Parent=gui;Instance.new("UICorner",f).CornerRadius=UDim.new(0,14)
local title=Instance.new("TextLabel");title.BackgroundTransparency=1;title.Position=UDim2.fromOffset(14,10);title.Size=UDim2.new(1,-28,0,28);title.Text="LOTTERY / RNG EXPORT PROBE V4";title.Font=Enum.Font.GothamBold;title.TextSize=14;title.TextColor3=Color3.new(1,1,1);title.Parent=f
local st=Instance.new("TextLabel");st.Position=UDim2.fromOffset(14,48);st.Size=UDim2.new(1,-28,0,64);st.BackgroundColor3=Color3.fromRGB(15,29,52);st.BorderSizePixel=0;st.Text="Pronto. Requer os modulos selecionados e registra apenas seus exports; nao chama as funcoes exportadas.";st.TextWrapped=true;st.Font=Enum.Font.Code;st.TextSize=11;st.TextColor3=Color3.new(1,1,1);st.Parent=f;Instance.new("UICorner",st).CornerRadius=UDim.new(0,9)
local function btn(t,x,w)local b=Instance.new("TextButton");b.Position=UDim2.fromOffset(x,128);b.Size=UDim2.fromOffset(w,38);b.BackgroundColor3=Color3.fromRGB(31,78,132);b.BorderSizePixel=0;b.Text=t;b.TextColor3=Color3.new(1,1,1);b.Font=Enum.Font.GothamBold;b.TextSize=11;b.Parent=f;Instance.new("UICorner",b).CornerRadius=UDim.new(0,9);return b end
local cap=btn("INSPECIONAR + EXPORTAR",14,278);local close=btn("FECHAR",306,130)
cap.MouseButton1Click:Connect(function()
 st.Text="Lendo exports dos modulos replicados..."
 task.defer(function()
  local ok,r=pcall(snapshot);if not ok then st.Text="Erro: "..tostring(r)return end
  local ok2,j=pcall(function()return enc(r,{})end);if not ok2 then st.Text="Erro JSON: "..tostring(j)return end
  local name="Psico_LotteryExports_"..os.time()..".json";local wrote=false
  if writefile then wrote=pcall(writefile,name,j)end;if setclipboard then pcall(setclipboard,j)end
  st.Text=(wrote and"EXPORTADO: "or"COPIADO: ")..name.." | "..#j.." bytes"
 end)
end)
close.MouseButton1Click:Connect(function()gui:Destroy()end)
local drag=false;local ds,sp
f.InputBegan:Connect(function(i)if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then drag=true;ds=i.Position;sp=f.Position end end)
f.InputChanged:Connect(function(i)if drag and(i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch)then local d=i.Position-ds;f.Position=UDim2.new(sp.X.Scale,sp.X.Offset+d.X,sp.Y.Scale,sp.Y.Offset+d.Y)end end)
UIS.InputEnded:Connect(function(i)if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then drag=false end end)

-- PSICOSENATICO | EGG CYCLE DATA PROBE V2
-- Passive/read-only cycle research. No hooks, debug/getgc, HTTP interception or game mutation.

local RS=game:GetService("ReplicatedStorage")
local CG=game:GetService("CoreGui")
local UIS=game:GetService("UserInputService")

local function path(root,...)
 local x=root
 for _,n in ipairs({...}) do x=x and x:FindFirstChild(n) end
 return x
end

local cycleMod=path(RS,"Shared","Util","AreaEggCycle")
local slotMod=path(RS,"Shared","Util","AreaEggSlotIdentity")
local recordsMod=path(RS,"Shared","Util","EggRecords")

local function req(m)
 if not m or not m:IsA("ModuleScript") then return nil,"not-found" end
 local ok,r=pcall(require,m); if ok then return r,nil end; return nil,tostring(r)
end
local Cycle,cycleErr=req(cycleMod)
local Slot,slotErr=req(slotMod)
local Records,recordsErr=req(recordsMod)

local function clean(v,d,seen)
 d=d or 0; seen=seen or {}
 local t=typeof(v)
 if t=="nil" or t=="boolean" or t=="string" or t=="number" then return v end
 if t=="Instance" then return {class=v.ClassName,path=v:GetFullName()} end
 if t=="function" then return "<function>" end
 if t~="table" then return tostring(v) end
 if seen[v] then return "<cycle>" end
 if d>=6 then return "<depth-limit>" end
 seen[v]=true; local o={}; local n=0
 for k,x in pairs(v) do n+=1; if n>500 then o["<truncated>"]=true break end; o[tostring(k)]=clean(x,d+1,seen) end
 seen[v]=nil; return o
end

local function call(tbl,name,...)
 local f=tbl and tbl[name]
 if type(f)~="function" then return {available=false} end
 local ok,a,b,c,d=pcall(f,...)
 if not ok then return {available=true,ok=false,error=tostring(a)} end
 return {available=true,ok=true,values=clean({a,b,c,d})}
end

local function probe()
 local now=os.time()
 local out={meta={version="EggCycleDataProbe2",created=now,placeId=tostring(game.PlaceId),gameId=tostring(game.GameId),jobId=tostring(game.JobId),passive=true},errors={cycle=cycleErr,slot=slotErr,records=recordsErr},cycleConstants=clean(Cycle),samples={},slotModule=clean(Slot),recordsModule=clean(Records)}
 local names={"PeriodIndexAt","ActivePeriodIndexAt","NextResetTime","SecondsUntilReset"}
 for step=0,24 do
  local t=now+step*300
  local s={step=step,time=t,etaSeconds=step*300,calls={}}
  for _,name in ipairs(names) do s.calls[name]=call(Cycle,name,t) end
  local p=s.calls.PeriodIndexAt
  if p.ok and p.values then
   local idx=p.values["1"] or p.values[1]
   if idx~=nil then s.periodIndex=idx; s.periodStart=call(Cycle,"PeriodStartTime",idx) end
  end
  out.samples[#out.samples+1]=s
 end
 return out
end

local function esc(s)
 s=tostring(s or ""):gsub("\\","\\\\"):gsub('"','\\"'):gsub("\b","\\b"):gsub("\f","\\f"):gsub("\n","\\n"):gsub("\r","\\r"):gsub("\t","\\t")
 s=s:gsub("[%z\1-\31]",function(c)return string.format("\\u%04x",string.byte(c))end)
 return '"'..s..'"'
end
local function arr(t)
 local n=0; for k in pairs(t) do if type(k)~="number" or k<1 or k%1~=0 then return false,0 end; n=math.max(n,k) end
 for i=1,n do if rawget(t,i)==nil then return false,0 end end; return true,n
end
local function enc(v,seen)
 local t=type(v); if t=="nil" then return "null" elseif t=="boolean" then return v and "true" or "false" elseif t=="number" then return tostring(v) elseif t=="string" then return esc(v) elseif t~="table" then return esc(tostring(v)) end
 seen=seen or {}; if seen[v] then return esc("<cycle>") end; seen[v]=true
 local a,n=arr(v); local p={}
 if a then for i=1,n do p[#p+1]=enc(v[i],seen) end; seen[v]=nil; return "["..table.concat(p,",").."]" end
 local ks={}; for k in pairs(v) do ks[#ks+1]=tostring(k) end; table.sort(ks)
 for _,k in ipairs(ks) do p[#p+1]=esc(k)..":"..enc(v[k],seen) end; seen[v]=nil; return "{"..table.concat(p,",").."}"
end

local gui=Instance.new("ScreenGui"); gui.Name="PSICO_EGG_CYCLE_PROBE_V2"; gui.ResetOnSpawn=false; gui.DisplayOrder=1402; gui.Parent=CG
local f=Instance.new("Frame"); f.AnchorPoint=Vector2.new(.5,.5); f.Position=UDim2.fromScale(.5,.5); f.Size=UDim2.fromOffset(440,210); f.BackgroundColor3=Color3.fromRGB(9,18,34); f.BorderSizePixel=0; f.Parent=gui; Instance.new("UICorner",f).CornerRadius=UDim.new(0,14)
local title=Instance.new("TextLabel"); title.BackgroundTransparency=1; title.Position=UDim2.fromOffset(14,10); title.Size=UDim2.new(1,-28,0,28); title.Text="EGG CYCLE DATA PROBE V2"; title.Font=Enum.Font.GothamBold; title.TextSize=14; title.TextColor3=Color3.new(1,1,1); title.Parent=f
local st=Instance.new("TextLabel"); st.Position=UDim2.fromOffset(14,48); st.Size=UDim2.new(1,-28,0,62); st.BackgroundColor3=Color3.fromRGB(15,29,52); st.BorderSizePixel=0; st.Text="Pronto. Amostra agora ate +2h em passos de 5 minutos."; st.TextWrapped=true; st.Font=Enum.Font.Code; st.TextSize=11; st.TextColor3=Color3.new(1,1,1); st.Parent=f; Instance.new("UICorner",st).CornerRadius=UDim.new(0,9)
local function btn(txt,x,w) local b=Instance.new("TextButton"); b.Position=UDim2.fromOffset(x,124); b.Size=UDim2.fromOffset(w,38); b.BackgroundColor3=Color3.fromRGB(31,78,132); b.BorderSizePixel=0; b.Text=txt; b.TextColor3=Color3.new(1,1,1); b.Font=Enum.Font.GothamBold; b.TextSize=11; b.Parent=f; Instance.new("UICorner",b).CornerRadius=UDim.new(0,9); return b end
local cap=btn("AMOSTRAR + EXPORTAR",14,270); local close=btn("FECHAR",298,128)
cap.MouseButton1Click:Connect(function() st.Text="Calculando funcoes read-only..."; task.defer(function() local ok,r=pcall(probe); if not ok then st.Text="Erro: "..tostring(r) return end; local ok2,j=pcall(function()return enc(r,{})end); if not ok2 then st.Text="Erro JSON: "..tostring(j) return end; local name="Psico_EggCycleFunctions_"..os.time()..".json"; local wrote=false; if writefile then wrote=pcall(writefile,name,j) end; if setclipboard then pcall(setclipboard,j) end; st.Text=(wrote and "EXPORTADO: " or "COPIADO: ")..name.." | "..#j.." bytes" end) end)
close.MouseButton1Click:Connect(function()gui:Destroy()end)
local drag=false; local ds,sp
f.InputBegan:Connect(function(i)if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then drag=true;ds=i.Position;sp=f.Position end end)
f.InputChanged:Connect(function(i)if drag and (i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch) then local d=i.Position-ds;f.Position=UDim2.new(sp.X.Scale,sp.X.Offset+d.X,sp.Y.Scale,sp.Y.Offset+d.Y)end end)
UIS.InputEnded:Connect(function(i)if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then drag=false end end)

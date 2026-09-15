-- PSICOSENATICO | EGG CYCLE DATA PROBE V3
-- Passive ModuleScript discovery only. No require, hooks, remotes, debug/getgc or mutation.
local RS=game:GetService("ReplicatedStorage")
local CG=game:GetService("CoreGui")
local UIS=game:GetService("UserInputService")
local WORDS={"lottery","draw","weighted","random","rng","asset","egg","spawn","rarity","cycle","slot","area","chance","seed"}
local function low(s)return string.lower(tostring(s or ""))end
local function matched(s)
 s=low(s); local m={}
 for _,w in ipairs(WORDS)do if string.find(s,w,1,true)then m[#m+1]=w end end
 return m
end
local function scan()
 local out={meta={version="EggCycleDataProbe3",created=os.time(),placeId=tostring(game.PlaceId),gameId=tostring(game.GameId),jobId=tostring(game.JobId),passive=true,mode="module-discovery"},keywords=WORDS,matches={},allModuleCount=0}
 for _,x in ipairs(RS:GetDescendants())do
  if x:IsA("ModuleScript")then
   out.allModuleCount+=1
   local full=x:GetFullName(); local m=matched(full)
   if #m>0 then out.matches[#out.matches+1]={name=x.Name,path=full,matches=m,attributes=x:GetAttributes()} end
  end
 end
 table.sort(out.matches,function(a,b)return a.path<b.path end)
 return out
end
local function esc(s)
 s=tostring(s or ""):gsub("\\","\\\\"):gsub('"','\\"'):gsub("\b","\\b"):gsub("\f","\\f"):gsub("\n","\\n"):gsub("\r","\\r"):gsub("\t","\\t")
 s=s:gsub("[%z\1-\31]",function(c)return string.format("\\u%04x",string.byte(c))end); return '"'..s..'"'
end
local function isarr(t)local n=0;for k in pairs(t)do if type(k)~="number" or k<1 or k%1~=0 then return false,0 end;n=math.max(n,k)end;for i=1,n do if rawget(t,i)==nil then return false,0 end end;return true,n end
local function clean(v,d,seen)
 d=d or 0;seen=seen or {};local t=typeof(v)
 if t=="nil" or t=="boolean" or t=="string" or t=="number" then return v end
 if t=="Instance" then return v:GetFullName() end
 if t~="table" then return tostring(v) end
 if seen[v] or d>5 then return "<cycle/depth>" end;seen[v]=true;local o={};for k,z in pairs(v)do o[tostring(k)]=clean(z,d+1,seen)end;seen[v]=nil;return o
end
local function enc(v,seen)
 v=clean(v);local t=type(v);if t=="nil"then return"null"elseif t=="boolean"then return v and"true"or"false"elseif t=="number"then return tostring(v)elseif t=="string"then return esc(v)end
 seen=seen or{};if seen[v]then return esc("<cycle>")end;seen[v]=true;local a,n=isarr(v);local p={}
 if a then for i=1,n do p[#p+1]=enc(v[i],seen)end;seen[v]=nil;return"["..table.concat(p,",").."]"end
 local ks={};for k in pairs(v)do ks[#ks+1]=tostring(k)end;table.sort(ks);for _,k in ipairs(ks)do p[#p+1]=esc(k)..":"..enc(v[k],seen)end;seen[v]=nil;return"{"..table.concat(p,",").."}"
end
local gui=Instance.new("ScreenGui");gui.Name="PSICO_MODULE_DISCOVERY";gui.ResetOnSpawn=false;gui.DisplayOrder=1403;gui.Parent=CG
local f=Instance.new("Frame");f.AnchorPoint=Vector2.new(.5,.5);f.Position=UDim2.fromScale(.5,.5);f.Size=UDim2.fromOffset(440,210);f.BackgroundColor3=Color3.fromRGB(9,18,34);f.BorderSizePixel=0;f.Parent=gui;Instance.new("UICorner",f).CornerRadius=UDim.new(0,14)
local title=Instance.new("TextLabel");title.BackgroundTransparency=1;title.Position=UDim2.fromOffset(14,10);title.Size=UDim2.new(1,-28,0,28);title.Text="MODULE DISCOVERY V3";title.Font=Enum.Font.GothamBold;title.TextSize=14;title.TextColor3=Color3.new(1,1,1);title.Parent=f
local st=Instance.new("TextLabel");st.Position=UDim2.fromOffset(14,48);st.Size=UDim2.new(1,-28,0,62);st.BackgroundColor3=Color3.fromRGB(15,29,52);st.BorderSizePixel=0;st.Text="Pronto. Apenas enumera nomes/caminhos de ModuleScripts replicados.";st.TextWrapped=true;st.Font=Enum.Font.Code;st.TextSize=11;st.TextColor3=Color3.new(1,1,1);st.Parent=f;Instance.new("UICorner",st).CornerRadius=UDim.new(0,9)
local function btn(t,x,w)local b=Instance.new("TextButton");b.Position=UDim2.fromOffset(x,124);b.Size=UDim2.fromOffset(w,38);b.BackgroundColor3=Color3.fromRGB(31,78,132);b.BorderSizePixel=0;b.Text=t;b.TextColor3=Color3.new(1,1,1);b.Font=Enum.Font.GothamBold;b.TextSize=11;b.Parent=f;Instance.new("UICorner",b).CornerRadius=UDim.new(0,9);return b end
local cap=btn("LOCALIZAR + EXPORTAR",14,270);local close=btn("FECHAR",298,128)
cap.MouseButton1Click:Connect(function()st.Text="Enumerando ModuleScripts...";task.defer(function()local ok,r=pcall(scan);if not ok then st.Text="Erro: "..tostring(r)return end;local ok2,j=pcall(function()return enc(r,{})end);if not ok2 then st.Text="Erro JSON: "..tostring(j)return end;local name="Psico_ModuleDiscovery_"..os.time()..".json";local wrote=false;if writefile then wrote=pcall(writefile,name,j)end;if setclipboard then pcall(setclipboard,j)end;st.Text=(wrote and"EXPORTADO: "or"COPIADO: ")..name.." | "..#r.matches.." candidatos"end)end)
close.MouseButton1Click:Connect(function()gui:Destroy()end)
local drag=false;local ds,sp
f.InputBegan:Connect(function(i)if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then drag=true;ds=i.Position;sp=f.Position end end)
f.InputChanged:Connect(function(i)if drag and(i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch)then local d=i.Position-ds;f.Position=UDim2.new(sp.X.Scale,sp.X.Offset+d.X,sp.Y.Scale,sp.Y.Offset+d.Y)end end)
UIS.InputEnded:Connect(function(i)if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then drag=false end end)

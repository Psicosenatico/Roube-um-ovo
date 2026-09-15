-- PSICOSENATICO | AXON PREDICTOR SCANNER
-- Passive / zero-hook. Observes UI and replicated state only.

local Players=game:GetService("Players")
local CoreGui=game:GetService("CoreGui")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local UserInputService=game:GetService("UserInputService")
local player=Players.LocalPlayer
local state={base=nil,predictor=nil,refresh=nil,gui=nil,status=nil}
local keywords={"predict","forecast","upcoming","spawn","egg","pet","rarity","rare","secret","eternal","divine","mythic","cosmic","area","chance","refresh","period","daystart","server"}
local function lower(s)return string.lower(tostring(s or ""))end
local function interesting(s)s=lower(s) for _,k in ipairs(keywords)do if string.find(s,k,1,true)then return true end end return false end
local function pathOf(x)local ok,r=pcall(function()return x:GetFullName()end)return ok and r or tostring(x)end
local function safeText(x)local ok,r=pcall(function()return x.Text end)return ok and r or nil end
local function captureUI()
 local out={} local roots={CoreGui} local pg=player and player:FindFirstChildOfClass("PlayerGui") if pg then table.insert(roots,pg)end
 for _,root in ipairs(roots)do local ok,list=pcall(function()return root:GetDescendants()end) if ok then for _,x in ipairs(list)do
  if x:IsA("TextLabel")or x:IsA("TextButton")or x:IsA("TextBox")then local text=safeText(x)local p=pathOf(x) if text and text~="" and(interesting(text)or interesting(p))then out[p]={class=x.ClassName,text=tostring(text),visible=x.Visible==true}end
  elseif x:IsA("ScreenGui")then local p=pathOf(x) out[p]={class="ScreenGui",enabled=x.Enabled==true,displayOrder=tonumber(x.DisplayOrder)or 0}end
 end end end return out
end
local function captureRelevant()
 local out={} local ok,list=pcall(function()return ReplicatedStorage:GetDescendants()end) if not ok then return out end
 for _,x in ipairs(list)do local useful=x:IsA("RemoteEvent")or x:IsA("RemoteFunction")or x:IsA("ModuleScript")or x:IsA("ValueBase") if useful then local p=pathOf(x) if interesting(p)or interesting(x.Name)then local item={class=x.ClassName,name=tostring(x.Name)} if x:IsA("ValueBase")then pcall(function()item.value=tostring(x.Value)end)end out[p]=item end end end return out
end
local function snapshot(label)return{label=label,unix=os.time(),placeId=tostring(game.PlaceId),gameId=tostring(game.GameId),jobId=tostring(game.JobId),ui=captureUI(),relevant=captureRelevant()}end
local function scalar(v)local t=type(v) if t=="nil"then return "null"elseif t=="boolean"then return v and "true"or"false"elseif t=="number"then if v~=v or v==math.huge or v==-math.huge then return "null"end return tostring(v)end end
local function esc(s)
 s=tostring(s or "") s=s:gsub("\\","\\\\"):gsub('"','\\"'):gsub("\b","\\b"):gsub("\f","\\f"):gsub("\n","\\n"):gsub("\r","\\r"):gsub("\t","\\t")
 s=s:gsub("[%z\1-\31]",function(c)return string.format("\\u%04x",string.byte(c))end) return '"'..s..'"'
end
local function isArray(t)local n=0 for k in pairs(t)do if type(k)~="number"or k<1 or k%1~=0 then return false,0 end if k>n then n=k end end for i=1,n do if rawget(t,i)==nil then return false,0 end end return true,n end
local function encode(v,seen)
 local tv=type(v) local s=scalar(v) if s then return s end if tv=="string"then return esc(v)end if tv~="table"then return esc(tostring(v))end
 seen=seen or{} if seen[v]then return esc("<cycle>")end seen[v]=true local arr,n=isArray(v)local parts={}
 if arr then for i=1,n do parts[#parts+1]=encode(v[i],seen)end seen[v]=nil return"["..table.concat(parts,",").."]"end
 local keys={} for k in pairs(v)do keys[#keys+1]=tostring(k)end table.sort(keys) local used={}
 for _,sk in ipairs(keys)do for k,val in pairs(v)do if tostring(k)==sk and not used[k]then used[k]=true parts[#parts+1]=esc(sk)..":"..encode(val,seen) break end end end
 seen[v]=nil return"{"..table.concat(parts,",").."}"
end
local function stable(v)return encode(v,{})end
local function diffMap(a,b)
 a=a or{} b=b or{} local added,removed,changed={},{},{} for k,v in pairs(b)do if a[k]==nil then added[k]=v elseif stable(a[k])~=stable(v)then changed[k]={before=a[k],after=v}end end for k,v in pairs(a)do if b[k]==nil then removed[k]=v end end return{added=added,removed=removed,changed=changed}
end
local function report()return{meta={version="AxonPredictorScanner",exportFix="custom-json",zeroHook=true,created=os.time()},base=state.base,predictor=state.predictor,refresh=state.refresh,predictorDiff=(state.base and state.predictor)and{ui=diffMap(state.base.ui,state.predictor.ui),relevant=diffMap(state.base.relevant,state.predictor.relevant)}or nil,refreshDiff=(state.predictor and state.refresh)and{ui=diffMap(state.predictor.ui,state.refresh.ui),relevant=diffMap(state.predictor.relevant,state.refresh.relevant)}or nil}end
local function setStatus(s)if state.status and state.status.Parent then state.status.Text=s end end
local function captureBase()setStatus("Capturando BASE...")task.defer(function()state.base=snapshot("base")state.predictor=nil state.refresh=nil setStatus("BASE capturada. Carregue o Axon e abra Egg Predictor.")end)end
local function capturePredictor()if not state.base then setStatus("Capture BASE primeiro.")return end setStatus("Capturando PREDICTOR...")task.defer(function()state.predictor=snapshot("predictor")setStatus("PREDICTOR capturado. Agora use Refresh Predictions.")end)end
local function captureRefresh()if not state.predictor then setStatus("Capture PREDICTOR primeiro.")return end setStatus("Capturando REFRESH...")task.defer(function()state.refresh=snapshot("refresh")setStatus("REFRESH capturado. Pode EXPORTAR.")end)end
local function exportData()
 if not state.base then setStatus("Nada para exportar.")return end local ok,json=pcall(function()return encode(report(),{})end) if not ok then setStatus("Erro export: "..tostring(json))return end
 local name="Psico_Axon_Predictor_"..os.time()..".json" local wrote=false if writefile then wrote=pcall(writefile,name,json)end if setclipboard then pcall(setclipboard,json)end setStatus((wrote and"EXPORTADO: "or"JSON COPIADO: ")..name.." | "..#json.." bytes")
end
local sg=Instance.new("ScreenGui")sg.Name="PSICO_AXON_PRED_SCANNER"sg.ResetOnSpawn=false sg.DisplayOrder=1400 sg.Parent=CoreGui state.gui=sg
local frame=Instance.new("Frame")frame.AnchorPoint=Vector2.new(.5,.5)frame.Position=UDim2.fromScale(.5,.5)frame.Size=UDim2.fromOffset(470,285)frame.BackgroundColor3=Color3.fromRGB(9,18,34)frame.BorderSizePixel=0 frame.Parent=sg Instance.new("UICorner",frame).CornerRadius=UDim.new(0,14)
local title=Instance.new("TextLabel")title.BackgroundTransparency=1 title.Position=UDim2.fromOffset(14,10)title.Size=UDim2.new(1,-28,0,28)title.Text="AXON PREDICTOR SCANNER • ZERO-HOOK"title.Font=Enum.Font.GothamBold title.TextSize=14 title.TextColor3=Color3.fromRGB(238,245,255)title.TextXAlignment=Enum.TextXAlignment.Left title.Parent=frame
local status=Instance.new("TextLabel")status.Position=UDim2.fromOffset(14,48)status.Size=UDim2.new(1,-28,0,78)status.BackgroundColor3=Color3.fromRGB(15,29,52)status.BorderSizePixel=0 status.Text="Pronto. Comece com CAPTURAR BASE."status.Font=Enum.Font.Code status.TextSize=11 status.TextColor3=Color3.fromRGB(215,229,247)status.TextWrapped=true status.Parent=frame Instance.new("UICorner",status).CornerRadius=UDim.new(0,9)state.status=status
local function button(text,x,y,w)local b=Instance.new("TextButton")b.Position=UDim2.fromOffset(x,y)b.Size=UDim2.fromOffset(w,38)b.BackgroundColor3=Color3.fromRGB(31,78,132)b.BorderSizePixel=0 b.Text=text b.TextColor3=Color3.fromRGB(244,248,255)b.Font=Enum.Font.GothamBold b.TextSize=11 b.Parent=frame Instance.new("UICorner",b).CornerRadius=UDim.new(0,9)return b end
local b1=button("CAPTURAR BASE",14,140,210)local b2=button("CAPTURAR PREDICTOR",246,140,210)local b3=button("CAPTURAR REFRESH",14,188,210)local b4=button("EXPORTAR",246,188,210)local close=button("FECHAR",14,236,442)
b1.MouseButton1Click:Connect(captureBase)b2.MouseButton1Click:Connect(capturePredictor)b3.MouseButton1Click:Connect(captureRefresh)b4.MouseButton1Click:Connect(exportData)close.MouseButton1Click:Connect(function()sg:Destroy()end)
local dragging=false local dragStart,startPos frame.InputBegan:Connect(function(i)if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then dragging=true dragStart=i.Position startPos=frame.Position end end)frame.InputChanged:Connect(function(i)if dragging and(i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch)then local d=i.Position-dragStart frame.Position=UDim2.new(startPos.X.Scale,startPos.X.Offset+d.X,startPos.Y.Scale,startPos.Y.Offset+d.Y)end end)UserInputService.InputEnded:Connect(function(i)if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then dragging=false end end)

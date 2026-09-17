-- PSICOSENATICO | Egg Equip Scanner V1.2
-- Scanner leve para comparar ANTES/DEPOIS ao equipar manualmente UM ovo.
-- Sem __namecall, hookfunction, getgc ou decompile.

if _G.PSICO_EGG_EQUIP_SCAN_CLEANUP then pcall(_G.PSICO_EGG_EQUIP_SCAN_CLEANUP) end

local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local CoreGui=game:GetService('CoreGui')
local Http=game:GetService('HttpService')
local UIS=game:GetService('UserInputService')
local Camera=workspace.CurrentCamera
local LP=Players.LocalPlayer
local C={}
local S={before=nil,after=nil,events={},started=os.time()}

local function uiParent()
 local ok,h=pcall(function() return gethui and gethui() end)
 return (ok and h) or CoreGui
end
local function val(v)
 local t=typeof(v)
 if t=='nil' or t=='boolean' or t=='string' or t=='number' then return v end
 if t=='Instance' then return {class=v.ClassName,name=v.Name,path=v:GetFullName()} end
 if t=='Vector3' then return {x=v.X,y=v.Y,z=v.Z} end
 return tostring(v)
end
local function attrs(x)
 local out={};local ok,a=pcall(function() return x:GetAttributes() end)
 if ok then for k,v in pairs(a) do out[k]=val(v) end end
 return out
end
local function children(x,depth)
 local out={};if not x or depth>2 then return out end
 for _,d in ipairs(x:GetChildren()) do
  local r={name=d.Name,class=d.ClassName,attrs=attrs(d)}
  if d:IsA('ValueBase') then pcall(function() r.value=val(d.Value) end) end
  if depth<2 and #d:GetChildren()>0 then r.children=children(d,depth+1) end
  out[#out+1]=r
 end
 return out
end
local function toolRow(t,where)
 local r={where=where,name=t.Name,class=t.ClassName,attrs=attrs(t),children=children(t,0)}
 pcall(function() r.tooltip=t.ToolTip end)
 pcall(function() r.textureId=t.TextureId end)
 pcall(function() r.canBeDropped=t.CanBeDropped end)
 return r
end
local function tools()
 local out={}
 for _,box in ipairs({{LP:FindFirstChildOfClass('Backpack'),'Backpack'},{LP.Character,'Character'}}) do
  if box[1] then
   for _,x in ipairs(box[1]:GetChildren()) do if x:IsA('Tool') then out[#out+1]=toolRow(x,box[2]) end end
  end
 end
 return out
end
local function remotes()
 local out={}
 for _,d in ipairs(RS:GetDescendants()) do
  if d:IsA('RemoteEvent') or d:IsA('RemoteFunction') then
   local q=string.lower(d:GetFullName())
   if q:find('egg',1,true) or q:find('equip',1,true) or q:find('inventory',1,true) or q:find('carry',1,true) or q:find('tool',1,true) then
    out[#out+1]={name=d.Name,class=d.ClassName,path=d:GetFullName(),attrs=attrs(d)}
   end
  end
 end
 return out
end
local function eggInventory()
 local out={ok=false,count=0,records={}}
 local shared=RS:FindFirstChild('Shared');local m=shared and shared:FindFirstChild('Save')
 if not(m and m:IsA('ModuleScript')) then return out end
 local ok,sv=pcall(require,m);if not(ok and type(sv)=='table' and type(sv.Get)=='function') then return out end
 local ok2,data=pcall(sv.Get);if not(ok2 and type(data)=='table') then return out end
 local inv=data.EggInventory;out.ok=true
 if type(inv)=='table' then
  for k,r in pairs(inv) do
   out.count+=1
   if type(r)=='table' then
    local z={key=tostring(k)}
    for _,n in ipairs({'Uid','UID','Id','ID','AssetCategory','Rarity','Weight','WeightKg','AssetScale','State','AreaId','NestId','Pet','PetName','DisplayName'}) do
     if r[n]~=nil then z[n]=val(r[n]) end
    end
    out.records[#out.records+1]=z
   end
  end
 end
 return out
end
local function snap(label)
 return {label=label,unix=os.time(),tools=tools(),eggInventory=eggInventory(),relevantRemotes=remotes()}
end
local function event(kind,x)
 S.events[#S.events+1]={t=os.clock(),unix=os.time(),kind=kind,item=x and toolRow(x,x.Parent==LP.Character and 'Character' or 'Backpack') or nil}
end
local function watch(container)
 if not container then return end
 C[#C+1]=container.ChildAdded:Connect(function(x) if x:IsA('Tool') then event('ToolAdded',x) end end)
 C[#C+1]=container.ChildRemoved:Connect(function(x) if x:IsA('Tool') then event('ToolRemoved',x) end end)
end
watch(LP:FindFirstChildOfClass('Backpack'));if LP.Character then watch(LP.Character) end
C[#C+1]=LP.CharacterAdded:Connect(function(ch) watch(ch) end)

local function corner(o,r)local c=Instance.new('UICorner');c.CornerRadius=UDim.new(0,r or 12);c.Parent=o end
local gui=Instance.new('ScreenGui');gui.Name='PsicoEggEquipScanner';gui.ResetOnSpawn=false;gui.IgnoreGuiInset=false;gui.Parent=uiParent()

local vp=Camera and Camera.ViewportSize or Vector2.new(1280,720)
local W=math.floor(math.clamp(vp.X*0.58,520,820))
local H=math.floor(math.clamp(vp.Y*0.62,320,470))
local main=Instance.new('Frame');main.Name='Main';main.AnchorPoint=Vector2.new(.5,.5);main.Position=UDim2.fromScale(.5,.5);main.Size=UDim2.fromOffset(W,H);main.BackgroundColor3=Color3.fromRGB(9,19,36);main.BorderSizePixel=0;main.Parent=gui;corner(main,18)

local header=Instance.new('Frame');header.Name='Header';header.BackgroundTransparency=1;header.Position=UDim2.fromOffset(16,8);header.Size=UDim2.new(1,-32,0,42);header.Active=true;header.Parent=main
local title=Instance.new('TextLabel');title.BackgroundTransparency=1;title.Size=UDim2.new(1,-56,1,0);title.Font=Enum.Font.GothamBold;title.Text='EGG EQUIP SCANNER • V1.2';title.TextSize=22;title.TextColor3=Color3.new(1,1,1);title.TextXAlignment=Enum.TextXAlignment.Left;title.Parent=header
local close=Instance.new('TextButton');close.AnchorPoint=Vector2.new(1,0);close.Position=UDim2.new(1,0,0,0);close.Size=UDim2.fromOffset(42,38);close.BackgroundColor3=Color3.fromRGB(31,43,62);close.BorderSizePixel=0;close.Text='×';close.TextSize=24;close.Font=Enum.Font.GothamBold;close.TextColor3=Color3.new(1,1,1);close.Parent=header;corner(close,11)

local status=Instance.new('TextLabel');status.Position=UDim2.fromOffset(18,58);status.Size=UDim2.new(1,-36,0,96);status.BackgroundColor3=Color3.fromRGB(16,34,58);status.BorderSizePixel=0;status.TextColor3=Color3.fromRGB(220,230,245);status.Font=Enum.Font.Code;status.TextSize=15;status.TextWrapped=true;status.TextXAlignment=Enum.TextXAlignment.Left;status.TextYAlignment=Enum.TextYAlignment.Top;status.Text='1) CAPTURAR ANTES\n2) Equipe manualmente UM ovo\n3) CAPTURAR DEPOIS → EXPORTAR JSON';status.Parent=main;corner(status,12)
local sp=Instance.new('UIPadding');sp.PaddingTop=UDim.new(0,12);sp.PaddingLeft=UDim.new(0,14);sp.PaddingRight=UDim.new(0,14);sp.Parent=status

local btnArea=Instance.new('Frame');btnArea.BackgroundTransparency=1;btnArea.Position=UDim2.fromOffset(18,166);btnArea.Size=UDim2.new(1,-36,1,-182);btnArea.Parent=main
local function mkButton(txt,x,y,w,h,fn)
 local b=Instance.new('TextButton');b.Position=UDim2.new(x,0,y,0);b.Size=UDim2.new(w,-5,h,-5);b.BackgroundColor3=Color3.fromRGB(42,91,151);b.BorderSizePixel=0;b.Text=txt;b.TextColor3=Color3.new(1,1,1);b.Font=Enum.Font.GothamBold;b.TextSize=16;b.Parent=btnArea;corner(b,12);C[#C+1]=b.Activated:Connect(fn);return b
end
mkButton('CAPTURAR ANTES',0,0,.5,.5,function()
 S.before=snap('before');S.events={};status.Text='ANTES capturado. Agora equipe manualmente UM ovo e depois toque CAPTURAR DEPOIS.'
end)
mkButton('CAPTURAR DEPOIS',.5,0,.5,.5,function()
 S.after=snap('after');status.Text='DEPOIS capturado. Eventos de Tool: '..#S.events..'. Agora EXPORTAR JSON.'
end)
mkButton('EXPORTAR JSON',0,.5,.72,.5,function()
 local payload={scanner='Psico Egg Equip Scanner V1.2',placeId=game.PlaceId,gameId=game.GameId,started=S.started,before=S.before,after=S.after,events=S.events}
 local ok,json=pcall(function() return Http:JSONEncode(payload) end)
 if not ok then status.Text='Erro JSON: '..tostring(json);return end
 local name='Psico_EggEquip_'..os.time()..'.json'
 if writefile then
  local ok2,e=pcall(writefile,name,json);status.Text=ok2 and('Exportado: '..name)or('writefile falhou: '..tostring(e))
 elseif setclipboard then pcall(setclipboard,json);status.Text='JSON copiado para clipboard.'
 else status.Text='Executor sem writefile/setclipboard.' end
end)
mkButton('FECHAR',.72,.5,.28,.5,function() if _G.PSICO_EGG_EQUIP_SCAN_CLEANUP then _G.PSICO_EGG_EQUIP_SCAN_CLEANUP() end end)

-- Drag pelo cabeçalho, com mouse ou touch.
local dragging=false;local dragStart,startPos,dragInput
C[#C+1]=header.InputBegan:Connect(function(input)
 if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
  dragging=true;dragStart=input.Position;startPos=main.Position;dragInput=input
 end
end)
C[#C+1]=UIS.InputChanged:Connect(function(input)
 if not dragging then return end
 if input.UserInputType==Enum.UserInputType.MouseMovement or input.UserInputType==Enum.UserInputType.Touch then
  local d=input.Position-dragStart
  main.Position=UDim2.new(startPos.X.Scale,startPos.X.Offset+d.X,startPos.Y.Scale,startPos.Y.Offset+d.Y)
 end
end)
C[#C+1]=UIS.InputEnded:Connect(function(input)
 if input==dragInput or input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then dragging=false end
end)
C[#C+1]=close.Activated:Connect(function() if _G.PSICO_EGG_EQUIP_SCAN_CLEANUP then _G.PSICO_EGG_EQUIP_SCAN_CLEANUP() end end)

_G.PSICO_EGG_EQUIP_SCAN_CLEANUP=function()
 for _,c in ipairs(C) do pcall(function() c:Disconnect() end) end
 pcall(function() gui:Destroy() end)
 _G.PSICO_EGG_EQUIP_SCAN_CLEANUP=nil
end
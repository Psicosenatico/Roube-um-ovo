-- PSICOSENATICO | Egg Equip Scanner V1
-- Captura diferencial leve: antes/depois de equipar manualmente UM ovo.
-- Nao usa __namecall, hookfunction, getgc, decompile ou interceptacao global.

if _G.PSICO_EGG_EQUIP_SCAN_CLEANUP then pcall(_G.PSICO_EGG_EQUIP_SCAN_CLEANUP) end

local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local CoreGui=game:GetService('CoreGui')
local Http=game:GetService('HttpService')
local LP=Players.LocalPlayer
local C={}
local S={before=nil,after=nil,events={},started=os.time(),connections={}}

local function parent()
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
 local o={}; local ok,a=pcall(function() return x:GetAttributes() end)
 if ok then for k,v in pairs(a) do o[k]=val(v) end end
 return o
end
local function children(x,depth)
 local out={}; if not x or depth>2 then return out end
 for _,d in ipairs(x:GetChildren()) do
  local row={name=d.Name,class=d.ClassName,attrs=attrs(d)}
  if d:IsA('ValueBase') then pcall(function() row.value=val(d.Value) end) end
  if depth<2 and #d:GetChildren()>0 then row.children=children(d,depth+1) end
  out[#out+1]=row
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
 local bp=LP:FindFirstChildOfClass('Backpack')
 local ch=LP.Character
 for _,box in ipairs({{bp,'Backpack'},{ch,'Character'}}) do
  if box[1] then for _,x in ipairs(box[1]:GetChildren()) do if x:IsA('Tool') then out[#out+1]=toolRow(x,box[2]) end end end
 end
 return out
end
local function remotes()
 local out={}
 for _,d in ipairs(RS:GetDescendants()) do
  if d:IsA('RemoteEvent') or d:IsA('RemoteFunction') then
   local q=string.lower(d:GetFullName())
   if q:find('egg',1,true) or q:find('equip',1,true) or q:find('inventory',1,true) or q:find('carry',1,true) or q:find('tool',1,true) or q:find('hotbar',1,true) then
    out[#out+1]={name=d.Name,class=d.ClassName,path=d:GetFullName(),attrs=attrs(d)}
   end
  end
 end
 return out
end
local function eggInventory()
 local out={ok=false}
 local m=RS:FindFirstChild('Shared') and RS.Shared:FindFirstChild('Save')
 if m and m:IsA('ModuleScript') then
  local ok,sv=pcall(require,m)
  if ok and type(sv)=='table' and type(sv.Get)=='function' then
   local ok2,data=pcall(sv.Get)
   if ok2 and type(data)=='table' then
    local inv=data.EggInventory
    out.ok=true;out.count=0;out.records={}
    if type(inv)=='table' then
     for k,r in pairs(inv) do
      out.count=out.count+1
      if type(r)=='table' then
       local z={key=tostring(k)}
       for _,n in ipairs({'Uid','UID','Id','ID','AssetCategory','Rarity','Weight','WeightKg','AssetScale','State','AreaId','NestId','Pet','PetName','DisplayName'}) do if r[n]~=nil then z[n]=val(r[n]) end end
       out.records[#out.records+1]=z
      end
     end
    end
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
watch(LP:FindFirstChildOfClass('Backpack')); if LP.Character then watch(LP.Character) end
C[#C+1]=LP.CharacterAdded:Connect(function(ch) watch(ch) end)

local gui=Instance.new('ScreenGui');gui.Name='PsicoEggEquipScanner';gui.ResetOnSpawn=false;gui.Parent=parent()
local f=Instance.new('Frame');f.Size=UDim2.fromScale(.72,.66);f.Position=UDim2.fromScale(.14,.16);f.BackgroundColor3=Color3.fromRGB(10,20,38);f.BorderSizePixel=0;f.Parent=gui;Instance.new('UICorner',f).CornerRadius=UDim.new(0,18)
local title=Instance.new('TextLabel');title.Size=UDim2.new(1,-40,0,55);title.Position=UDim2.fromOffset(20,12);title.BackgroundTransparency=1;title.Text='EGG EQUIP SCANNER • V1';title.TextColor3=Color3.new(1,1,1);title.Font=Enum.Font.GothamBold;title.TextScaled=true;title.TextXAlignment=Enum.TextXAlignment.Left;title.Parent=f
local status=Instance.new('TextLabel');status.Size=UDim2.new(1,-40,0,100);status.Position=UDim2.fromOffset(20,78);status.BackgroundColor3=Color3.fromRGB(16,34,58);status.TextColor3=Color3.fromRGB(220,230,245);status.Font=Enum.Font.Code;status.TextSize=18;status.TextWrapped=true;status.Text='1) CAPTURAR ANTES\n2) Equipe manualmente UM ovo pelo inventario do jogo\n3) CAPTURAR DEPOIS e EXPORTAR';status.Parent=f;Instance.new('UICorner',status).CornerRadius=UDim.new(0,12)
local function button(text,x,y,w,fn)
 local b=Instance.new('TextButton');b.Size=UDim2.new(w,-10,0,58);b.Position=UDim2.new(x,10,y,0);b.BackgroundColor3=Color3.fromRGB(42,91,151);b.TextColor3=Color3.new(1,1,1);b.Font=Enum.Font.GothamBold;b.TextSize=18;b.Text=text;b.Parent=f;Instance.new('UICorner',b).CornerRadius=UDim.new(0,12);b.MouseButton1Click:Connect(fn);return b
end
button('CAPTURAR ANTES',0,0.52,.5,function() S.before=snap('before');S.events={};status.Text='ANTES capturado. Agora equipe manualmente UM ovo e depois toque CAPTURAR DEPOIS.' end)
button('CAPTURAR DEPOIS',.5,0.52,.5,function() S.after=snap('after');status.Text='DEPOIS capturado. Eventos Tool: '..#S.events..'. Agora EXPORTAR JSON.' end)
button('EXPORTAR JSON',0,0.75,.72,function()
 local payload={scanner='Psico Egg Equip Scanner V1',placeId=game.PlaceId,gameId=game.GameId,started=S.started,before=S.before,after=S.after,events=S.events}
 local ok,json=pcall(function() return Http:JSONEncode(payload) end)
 if not ok then status.Text='Erro JSON: '..tostring(json);return end
 local name='Psico_EggEquip_'..os.time()..'.json'
 if writefile then local ok2,e=pcall(writefile,name,json);status.Text=ok2 and ('Exportado: '..name) or ('writefile falhou: '..tostring(e))
 elseif setclipboard then pcall(setclipboard,json);status.Text='JSON copiado para clipboard.' else status.Text='Executor sem writefile/setclipboard.' end
end)
button('FECHAR',.72,0.75,.28,function() if _G.PSICO_EGG_EQUIP_SCAN_CLEANUP then _G.PSICO_EGG_EQUIP_SCAN_CLEANUP() end end)
_G.PSICO_EGG_EQUIP_SCAN_CLEANUP=function() for _,c in ipairs(C) do pcall(function() c:Disconnect() end) end;pcall(function() gui:Destroy() end);_G.PSICO_EGG_EQUIP_SCAN_CLEANUP=nil end
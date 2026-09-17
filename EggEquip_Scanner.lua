-- PSICOSENATICO | Egg Equip Scanner V1.1 UI FIX
-- Mantém a lógica do scanner V1 e corrige apenas a interface/mobile/drag.

loadstring(game:HttpGet('https://raw.githubusercontent.com/Psicosenatico/Roube-um-ovo/d0630034da8d8a29f87bce51b5fb743b49e8acad/EggEquip_Scanner.lua'))()

task.wait()
local UIS=game:GetService('UserInputService')
local CoreGui=game:GetService('CoreGui')
local function uiParent()
 local ok,h=pcall(function() return gethui and gethui() end)
 return (ok and h) or CoreGui
end
local gui=uiParent():FindFirstChild('PsicoEggEquipScanner')
if not gui then return end
local main=gui:FindFirstChildWhichIsA('Frame')
if not main then return end

main.AnchorPoint=Vector2.new(.5,.5)
main.Position=UDim2.fromScale(.5,.5)
main.Size=UDim2.fromScale(.78,.72)
main.ClipsDescendants=true
local lim=Instance.new('UISizeConstraint')
lim.MinSize=Vector2.new(560,320)
lim.MaxSize=Vector2.new(900,450)
lim.Parent=main

local title,status,buttons=nil,nil,{}
for _,d in ipairs(main:GetChildren()) do
 if d:IsA('TextLabel') then
  if d.Text:find('EGG EQUIP SCANNER',1,true) then title=d else status=status or d end
 elseif d:IsA('TextButton') then
  buttons[d.Text]=d
 end
end

if title then
 title.Text='EGG EQUIP SCANNER • V1.1'
 title.TextScaled=false
 title.TextSize=24
 title.Position=UDim2.fromOffset(20,10)
 title.Size=UDim2.new(1,-40,0,34)
end
if status then
 status.Position=UDim2.fromOffset(20,58)
 status.Size=UDim2.new(1,-40,0,118)
 status.TextSize=15
 status.TextWrapped=true
 status.TextXAlignment=Enum.TextXAlignment.Left
 status.TextYAlignment=Enum.TextYAlignment.Top
 local pad=Instance.new('UIPadding')
 pad.PaddingTop=UDim.new(0,12);pad.PaddingLeft=UDim.new(0,14);pad.PaddingRight=UDim.new(0,14);pad.Parent=status
end

local function place(name,x,y,w,h)
 local b=buttons[name]
 if not b then return end
 b.Position=UDim2.new(x,0,y,0)
 b.Size=UDim2.new(w,-6,h,-6)
 b.TextSize=16
end
place('CAPTURAR ANTES',.03,.49,.47,.20)
place('CAPTURAR DEPOIS',.50,.49,.47,.20)
place('EXPORTAR JSON',.03,.70,.65,.20)
place('FECHAR',.69,.70,.28,.20)

-- Arraste pelo cabeçalho/título (mouse e touch).
local dragArea=title or main
local dragging=false
local dragInput,dragStart,startPos
local extra={}
extra[#extra+1]=dragArea.InputBegan:Connect(function(input)
 if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
  dragging=true;dragStart=input.Position;startPos=main.Position
 end
end)
extra[#extra+1]=dragArea.InputChanged:Connect(function(input)
 if input.UserInputType==Enum.UserInputType.MouseMovement or input.UserInputType==Enum.UserInputType.Touch then dragInput=input end
end)
extra[#extra+1]=UIS.InputChanged:Connect(function(input)
 if dragging and input==dragInput then
  local delta=input.Position-dragStart
  main.Position=UDim2.new(startPos.X.Scale,startPos.X.Offset+delta.X,startPos.Y.Scale,startPos.Y.Offset+delta.Y)
 end
end)
extra[#extra+1]=UIS.InputEnded:Connect(function(input)
 if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then dragging=false end
end)

local oldCleanup=_G.PSICO_EGG_EQUIP_SCAN_CLEANUP
_G.PSICO_EGG_EQUIP_SCAN_CLEANUP=function()
 for _,c in ipairs(extra) do pcall(function() c:Disconnect() end) end
 if oldCleanup then pcall(oldCleanup) end
end
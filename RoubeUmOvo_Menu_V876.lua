-- PSICOSENATICO V8.7.6 - inventory tab loader fix
-- Base menu is loaded first; inventory module is injected only after the base UI anchors exist.
local HttpService=game:GetService('HttpService')
local CoreGui=game:GetService('CoreGui')
local cb=tostring(os.time())..'_'..tostring(math.random(100000,999999))
local BASE='https://raw.githubusercontent.com/Psicosenatico/Roube-um-ovo/main/'
local function run(path)
 local src=game:HttpGet(BASE..path..'?cb='..cb)
 local fn,err=loadstring(src);if not fn then error(path..' compile: '..tostring(err))end
 local ok,e=pcall(fn);if not ok then error(path..' runtime: '..tostring(e))end
end
local function uiRoot()local ok,h=pcall(function()return gethui and gethui()end);return(ok and h)or CoreGui end
local function findMain()
 for _,g in ipairs(uiRoot():GetChildren())do
  if g:IsA('ScreenGui')and g.Name:find('PsicoRoubeUmOvo',1,true)==1 then local m=g:FindFirstChild('Main');if m then return m end end
 end
end
local function hasText(main,s)
 if not main then return false end
 for _,d in ipairs(main:GetDescendants())do if(d:IsA('TextButton')or d:IsA('TextLabel'))and d.Text==s then return true end end
 return false
end
run('RoubeUmOvo_Menu.lua')
local main
for _=1,60 do main=findMain();if main and hasText(main,'FUNÇÕES')and hasText(main,'FILTROS ESP')and hasText(main,'Raridade mínima')then break end;task.wait(.05)end
if not main then error('V8.7.6: base UI not ready')end
-- The previous wrapper could execute Inventory V6 before the base page finished constructing.
-- Retry once after cleanup if injection fails or the tab is absent.
local ok,err=pcall(function()run('InventoryEggPanel_V6.lua')end)
task.wait(.15)
main=findMain()
if(not ok)or not hasText(main,'OVOS INVENTÁRIO')then
 if _G.PSICO_INVENTORY_PANEL_CLEANUP then pcall(_G.PSICO_INVENTORY_PANEL_CLEANUP)end
 task.wait(.15)
 run('InventoryEggPanel_V6.lua')
 task.wait(.15);main=findMain()
end
if not hasText(main,'OVOS INVENTÁRIO')then error('V8.7.6: inventory module loaded but OVOS INVENTÁRIO tab was not created')end
for _,d in ipairs(main:GetDescendants())do if d:IsA('TextLabel')and d.Text:find('V8.',1,true)==1 then d.Text='V8.7.6 • INVENTORY TAB FIX';break end end
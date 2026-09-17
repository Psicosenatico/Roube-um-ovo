-- PSICOSENATICO V8.7.7 - definitive inventory anchor fix
local CoreGui=game:GetService('CoreGui')
local cb=tostring(os.time())..'_'..tostring(math.random(100000,999999))
local BASE='https://raw.githubusercontent.com/Psicosenatico/Roube-um-ovo/main/'
local function run(path)
 local src=game:HttpGet(BASE..path..'?cb='..cb)
 local fn,err=loadstring(src);if not fn then error(path..' compile: '..tostring(err))end
 local ok,e=pcall(fn);if not ok then error(path..' runtime: '..tostring(e))end
end
local function root()local ok,h=pcall(function()return gethui and gethui()end);return(ok and h)or CoreGui end
local function main()
 for _,g in ipairs(root():GetChildren())do if g:IsA('ScreenGui')and g.Name:find('PsicoRoubeUmOvo',1,true)==1 then local m=g:FindFirstChild('Main');if m then return m end end end
end
local function findText(m,predicate)
 if not m then return nil end
 for _,d in ipairs(m:GetDescendants())do if(d:IsA('TextButton')or d:IsA('TextLabel'))and predicate(d.Text)then return d end end
end
run('RoubeUmOvo_Menu.lua')
local m
for _=1,80 do m=main();if m and findText(m,function(t)return t=='FUNÇÕES'end)and findText(m,function(t)return t=='FILTROS ESP'end)then break end;task.wait(.05)end
if not m then error('V8.7.7 base UI unavailable')end
-- Inventory V5 expected two spaces before ON/OFF, while the current base menu renders one.
-- Normalize only during module construction, then restore the exact visible caption.
local egg=findText(m,function(t)return t:find('ESP',1,true)and t:find('Ovos',1,true)and(t:find('ON',1,true)or t:find('OFF',1,true))end)
local original=egg and egg.Text
if egg then
 if original:find('OFF',1,true)then egg.Text='ESP • Ovos  OFF'else egg.Text='ESP • Ovos  ON'end
end
local ok,err=pcall(function()run('InventoryEggPanel_V6.lua')end)
if egg and original then egg.Text=original end
if not ok then error('V8.7.7 inventory: '..tostring(err))end
task.wait(.15);m=main()
local tab=findText(m,function(t)return t=='OVOS INVENTÁRIO'end)
if not tab then error('V8.7.7 inventory tab verification failed')end
local version=findText(m,function(t)return t:find('V8.',1,true)==1 end)
if version then version.Text='V8.7.7 • INVENTORY RESTORED' end
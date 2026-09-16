-- PSICOSENATICO V8.7.2
local cb=tostring(os.time())..'_'..tostring(math.random(100000,999999))
local function run(path)
 local src=game:HttpGet('https://raw.githubusercontent.com/Psicosenatico/Roube-um-ovo/main/'..path..'?cb='..cb)
 local fn,err=loadstring(src);if not fn then error('[PSICO] '..path..' compile: '..tostring(err))end
 local ok,e=pcall(fn);if not ok then error('[PSICO] '..path..' runtime: '..tostring(e))end
end
run('RoubeUmOvo_Menu.lua')
run('InventoryEggPanel_V3.lua')
task.defer(function()
 task.wait(.2)
 local root=(gethui and gethui())or game:GetService('CoreGui')
 for _,g in ipairs(root:GetChildren())do if g:IsA('ScreenGui')and g.Name:find('PsicoRoubeUmOvo',1,true)==1 then local m=g:FindFirstChild('Main');if m then for _,d in ipairs(m:GetDescendants())do if d:IsA('TextLabel')and d.Text:find('V8.',1,true)==1 then d.Text='V8.7.2 • EGG INVENTORY V3';return end end end end end
end)
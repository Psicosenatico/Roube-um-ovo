-- PSICOSENATICO V8.7.4
local cb=tostring(os.time())..'_'..tostring(math.random(100000,999999))

local function patchInventory(src)
    local oldRead="for key, r in pairs(inv) do\n        if type(r) == 'table' then\n            local c = tostring(cat(r) or '?')"
    local newRead="for key, r in pairs(inv) do\n        if type(r) == 'table' and not (rv(r, 'Placement') ~= nil and rv(r, 'Placement') ~= false) then\n            local c = tostring(cat(r) or '?')"
    local nRead
    src,nRead=src:gsub(oldRead,newRead,1)
    if nRead~=1 then error('Inventory placement filter patch failed') end

    local oldEquip="local function equipRecord(key, rec)\n    local uid = tostring(key or rv(rec, 'UID') or '')"
    local newEquip="local function equipRecord(key, rec)\n    local liveData = Save and call(Save, 'Get')\n    local liveInv = type(liveData) == 'table' and liveData.EggInventory\n    local liveRec = type(liveInv) == 'table' and (liveInv[key] or liveInv[tostring(key)]) or rec\n    if type(liveRec) == 'table' and rv(liveRec, 'Placement') ~= nil and rv(liveRec, 'Placement') ~= false then\n        return false, 'Este ovo já está colocado na base'\n    end\n    rec = liveRec or rec\n    local uid = tostring(key or rv(rec, 'UID') or '')"
    local nEquip
    src,nEquip=src:gsub(oldEquip,newEquip,1)
    if nEquip~=1 then error('Inventory placed-equip guard patch failed') end
    return src
end

local function run(path)
    local src=game:HttpGet('https://raw.githubusercontent.com/Psicosenatico/Roube-um-ovo/main/'..path..'?cb='..cb)
    if path=='InventoryEggPanel_V5.lua' then src=patchInventory(src) end
    local fn,err=loadstring(src)
    if not fn then error(path..' compile: '..tostring(err)) end
    local ok,e=pcall(fn)
    if not ok then error(path..' runtime: '..tostring(e)) end
end

run('RoubeUmOvo_Menu.lua')
run('InventoryEggPanel_V5.lua')

task.defer(function()
    task.wait(.2)
    local root=(function()
        local ok,h=pcall(function()return gethui and gethui()end)
        return(ok and h)or game:GetService('CoreGui')
    end)()
    for _,g in ipairs(root:GetChildren())do
        if g:IsA('ScreenGui')and g.Name:find('PsicoRoubeUmOvo',1,true)==1 then
            local m=g:FindFirstChild('Main')
            if m then
                for _,d in ipairs(m:GetDescendants())do
                    if d:IsA('TextLabel')and d.Text:find('V8.',1,true)==1 then
                        d.Text='V8.7.4 • INVENTORY COMPACT'
                        return
                    end
                end
            end
        end
    end
end)
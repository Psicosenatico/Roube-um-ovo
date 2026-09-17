-- PSICOSENATICO V8.7.4
local cb=tostring(os.time())..'_'..tostring(math.random(100000,999999))

local function replacePlainOnce(src,old,new,label)
    local a,b=src:find(old,1,true)
    if not a then error(label..' patch failed') end
    return src:sub(1,a-1)..new..src:sub(b+1)
end

local function patchInventory(src)
    local oldRead="for key, r in pairs(inv) do\n        if type(r) == 'table' then\n            local c = tostring(cat(r) or '?')"
    local newRead="for key, r in pairs(inv) do\n        if type(r) == 'table' and not (rv(r, 'Placement') ~= nil and rv(r, 'Placement') ~= false) then\n            local c = tostring(cat(r) or '?')"
    src=replacePlainOnce(src,oldRead,newRead,'Inventory placement filter')

    local oldEquip="local function equipRecord(key, rec)\n    local uid = tostring(key or rv(rec, 'UID') or '')"
    local newEquip="local function equipRecord(key, rec)\n    local liveData = Save and call(Save, 'Get')\n    local liveInv = type(liveData) == 'table' and liveData.EggInventory\n    local liveRec = type(liveInv) == 'table' and (liveInv[key] or liveInv[tostring(key)]) or rec\n    if type(liveRec) == 'table' and rv(liveRec, 'Placement') ~= nil and rv(liveRec, 'Placement') ~= false then\n        return false, 'Este ovo já está colocado na base'\n    end\n    rec = liveRec or rec\n    local uid = tostring(key or rv(rec, 'UID') or '')"
    src=replacePlainOnce(src,oldEquip,newEquip,'Inventory placed-equip guard')

    local oldSync="conn(tab.Activated, show)\nconn(refresh.Activated, render)\nconn(sort.Activated, function()"
    local newSync="conn(tab.Activated, show)\nconn(refresh.Activated, render)\n\nlocal _psicoPlacementSig = ''\nlocal function _psicoInventorySignature()\n    local sd = Save and call(Save, 'Get')\n    local inv = type(sd) == 'table' and sd.EggInventory\n    if type(inv) ~= 'table' then return '' end\n    local keys = {}\n    for key, rec in pairs(inv) do\n        if type(rec) == 'table' and not (rv(rec, 'Placement') ~= nil and rv(rec, 'Placement') ~= false) then\n            keys[#keys + 1] = tostring(key)\n        end\n    end\n    table.sort(keys)\n    return table.concat(keys, '|')\nend\n\ntask.spawn(function()\n    while page.Parent do\n        task.wait(.75)\n        if page.Visible then\n            local sig = _psicoInventorySignature()\n            if _psicoPlacementSig ~= '' and sig ~= _psicoPlacementSig then\n                render()\n            end\n            _psicoPlacementSig = sig\n        end\n    end\nend)\n\nconn(sort.Activated, function()"
    src=replacePlainOnce(src,oldSync,newSync,'Inventory placement autosync')
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
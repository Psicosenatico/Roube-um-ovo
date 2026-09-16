-- PSICOSENATICO | Roube um Ovo - Precision Menu V8.4.6
-- Minimal render-layer fix after full audit:
-- base V8.3 renders through gethui() when available, while the inventory ESP
-- modules hard-coded CoreGui. We patch ONLY that parent assignment at load time.

loadstring(game:HttpGet("https://raw.githubusercontent.com/Psicosenatico/Roube-um-ovo/main/RoubeUmOvo_Menu.lua"))()

local function runInventoryModule(url)
    local src=game:HttpGet(url)
    local replacement=[[overlayGui.Parent=(function()
        local ok,h=pcall(function() if gethui then return gethui() end end)
        return (ok and h) or CoreGui
    end)()]]
    src=src:gsub("overlayGui%.Parent=CoreGui",replacement,1)
    local fn,err=loadstring(src)
    if not fn then
        warn("[PSICO Inventory ESP] compile error: "..tostring(err))
        return
    end
    fn()
end

runInventoryModule("https://raw.githubusercontent.com/Psicosenatico/Roube-um-ovo/main/InventoryEggESP_V5.lua")
runInventoryModule("https://raw.githubusercontent.com/Psicosenatico/Roube-um-ovo/main/InventoryHotbarESP_Addon_V1.lua")

task.defer(function()
    task.wait(.6)
    local roots={game:GetService("CoreGui")}
    local ok,h=pcall(function() if gethui then return gethui() end end)
    if ok and h then roots[#roots+1]=h end
    for _,root in ipairs(roots) do
        for _,d in ipairs(root:GetDescendants()) do
            if d:IsA("TextLabel") and (d.Text:find("V8.4.4",1,true)==1 or d.Text:find("V8.4.5",1,true)==1) then
                d.Text="V8.4.6 • INVENTORY ESP RENDER FIX"
                return
            end
        end
    end
end)

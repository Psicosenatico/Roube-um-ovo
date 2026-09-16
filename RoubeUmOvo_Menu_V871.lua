-- PSICOSENATICO | Roube um Ovo - Precision Menu V8.7.1
-- Fixes the single syntax typo found in InventoryEggPanel_V2 before compilation.
-- If V2 cannot compile/run, falls back to the known-working InventoryEggPanel_V1.

local function uiRoot()
    local ok,h=pcall(function() if gethui then return gethui() end end)
    if ok and h then return h end
    return game:GetService("CoreGui")
end

local function setSubtitle(text)
    task.defer(function()
        task.wait(.15)
        local root=uiRoot()
        for _,g in ipairs(root:GetChildren()) do
            if g:IsA("ScreenGui") and g.Name:find("PsicoRoubeUmOvo",1,true)==1 then
                local main=g:FindFirstChild("Main")
                if main then
                    for _,d in ipairs(main:GetDescendants()) do
                        if d:IsA("TextLabel") and (d.Text:find("V8.",1,true)==1 or d.Text:find("INVENTORY",1,true)) then
                            d.Text=text
                            return
                        end
                    end
                end
            end
        end
    end)
end

local cb=tostring(os.time()).."_"..tostring(math.random(100000,999999))

-- Stable base first.
local baseUrl="https://raw.githubusercontent.com/Psicosenatico/Roube-um-ovo/main/RoubeUmOvo_Menu.lua?cb="..cb
local baseSrc=game:HttpGet(baseUrl)
local baseFn,baseErr=loadstring(baseSrc)
if not baseFn then error("[PSICO V8.7.1] Base compile error: "..tostring(baseErr)) end
baseFn()

local function loadInventoryV2()
    local url="https://raw.githubusercontent.com/Psicosenatico/Roube-um-ovo/main/InventoryEggPanel_V2.lua?cb="..cb
    local src=game:HttpGet(url)
    -- Concrete syntax bug found during review:
    --   local out={},seen={}
    -- must be:
    --   local out,seen={},{}
    src=src:gsub("local out=%{%},seen=%{%}","local out,seen={},{}")
    local fn,compileErr=loadstring(src)
    if not fn then return false,"compile: "..tostring(compileErr) end
    local ok,runErr=pcall(fn)
    if not ok then return false,"runtime: "..tostring(runErr) end
    return true
end

local ok,err=loadInventoryV2()
if ok then
    setSubtitle("V8.7.1 • INVENTORY V2")
else
    warn("[PSICO V8.7.1] Inventory V2 failed: "..tostring(err))
    local fallbackUrl="https://raw.githubusercontent.com/Psicosenatico/Roube-um-ovo/main/InventoryEggPanel_V1.lua?cb="..cb
    local fallbackSrc=game:HttpGet(fallbackUrl)
    local fallbackFn,fallbackErr=loadstring(fallbackSrc)
    if fallbackFn then
        local fok,ferr=pcall(fallbackFn)
        if fok then
            setSubtitle("V8.7.1 • INVENTORY FALLBACK")
        else
            setSubtitle("V8.7.1 • INVENTORY ERROR")
            warn("[PSICO V8.7.1] Fallback runtime error: "..tostring(ferr))
        end
    else
        setSubtitle("V8.7.1 • INVENTORY ERROR")
        warn("[PSICO V8.7.1] Fallback compile error: "..tostring(fallbackErr))
    end
end

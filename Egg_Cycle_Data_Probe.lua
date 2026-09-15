-- PSICOSENATICO | EGG CYCLE DATA PROBE
-- Passive/local-data research helper.
-- Reads only selected ModuleScripts already replicated to the client.
-- Does NOT hook remotes/functions, intercept HTTP, use debug/getgc, or mutate game state.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CoreGui = game:GetService("CoreGui")
local UserInputService = game:GetService("UserInputService")

local TARGETS = {
    "ReplicatedStorage.Data.AreaEggResetCycle",
    "ReplicatedStorage.Shared.Util.AreaEggCycle",
    "ReplicatedStorage.Shared.Util.AreaEggSlotIdentity",
    "ReplicatedStorage.Shared.Util.EggRecords",
    "ReplicatedStorage.Data.Rarity",
    "ReplicatedStorage.Data.Areas",
}

local AREA_CONFIG_ROOT = "ReplicatedStorage.Data.Areas.Configs"

local function resolve(path)
    local cur = game
    local first = true
    for part in string.gmatch(path, "[^%.]+") do
        if first and part == "ReplicatedStorage" then
            cur = ReplicatedStorage
        elseif first then
            cur = game:FindFirstChild(part)
        else
            cur = cur and cur:FindFirstChild(part)
        end
        first = false
        if not cur then return nil end
    end
    return cur
end

local function safeKey(k)
    local t = typeof(k)
    if t=="string" or t=="number" or t=="boolean" then return tostring(k) end
    if t=="Instance" then
        local ok,p=pcall(function() return k:GetFullName() end)
        return ok and p or tostring(k)
    end
    return "<"..t..">"
end

local function sanitize(v, depth, seen, budget)
    depth = depth or 0
    seen = seen or {}
    budget = budget or {n=0, max=12000}
    budget.n += 1
    if budget.n > budget.max then return "<budget-limit>" end
    local t = typeof(v)
    if t=="nil" or t=="boolean" or t=="string" or t=="number" then
        if t=="number" and (v~=v or v==math.huge or v==-math.huge) then return tostring(v) end
        return v
    end
    if t=="Instance" then
        local ok,p=pcall(function() return v:GetFullName() end)
        return {__type="Instance", path=ok and p or tostring(v), class=v.ClassName}
    end
    if t=="function" then return "<function>" end
    if t=="thread" then return "<thread>" end
    if t=="userdata" then return tostring(v) end
    if t~="table" then return tostring(v) end
    if seen[v] then return "<cycle>" end
    if depth >= 8 then return "<depth-limit>" end
    seen[v]=true
    local out={}
    local count=0
    for k,val in pairs(v) do
        count += 1
        if count > 800 then out["<truncated>"]="more than 800 keys" break end
        out[safeKey(k)] = sanitize(val, depth+1, seen, budget)
    end
    seen[v]=nil
    return out
end

local function inspectModule(mod)
    local item={path=mod:GetFullName(),name=mod.Name,class=mod.ClassName,attributes=sanitize(mod:GetAttributes())}
    local ok,res=pcall(require,mod)
    item.requireOk=ok
    if ok then item.returnType=typeof(res); item.data=sanitize(res) else item.error=tostring(res) end
    return item
end

local function inspectAreaConfigs()
    local root=resolve(AREA_CONFIG_ROOT)
    local out={}
    if not root then return out end
    for _,x in ipairs(root:GetChildren()) do
        if x:IsA("ModuleScript") then out[x.Name]=inspectModule(x) end
    end
    return out
end

local function snapshot()
    local out={meta={version="EggCycleDataProbe1",created=os.time(),placeId=tostring(game.PlaceId),gameId=tostring(game.GameId),jobId=tostring(game.JobId),passive=true},modules={},areaConfigs=inspectAreaConfigs()}
    for _,path in ipairs(TARGETS) do
        local x=resolve(path)
        if x and x:IsA("ModuleScript") then out.modules[path]=inspectModule(x) else out.modules[path]={path=path,found=false} end
    end
    return out
end

local function esc(s)
    s=tostring(s or "")
    s=s:gsub("\\","\\\\"):gsub('"','\\"'):gsub("\b","\\b"):gsub("\f","\\f"):gsub("\n","\\n"):gsub("\r","\\r"):gsub("\t","\\t")
    s=s:gsub("[%z\1-\31]",function(c) return string.format("\\u%04x",string.byte(c)) end)
    return '"'..s..'"'
end

local function isArray(t)
    local n=0
    for k in pairs(t) do if type(k)~="number" or k<1 or k%1~=0 then return false,0 end n=math.max(n,k) end
    for i=1,n do if rawget(t,i)==nil then return false,0 end end
    return true,n
end

local function encode(v,seen)
    local tv=type(v)
    if tv=="nil" then return "null" end
    if tv=="boolean" then return v and "true" or "false" end
    if tv=="number" then if v~=v or v==math.huge or v==-math.huge then return esc(tostring(v)) end return tostring(v) end
    if tv=="string" then return esc(v) end
    if tv~="table" then return esc(tostring(v)) end
    seen=seen or {}
    if seen[v] then return esc("<cycle>") end
    seen[v]=true
    local arr,n=isArray(v)
    local parts={}
    if arr then
        for i=1,n do parts[#parts+1]=encode(v[i],seen) end
        seen[v]=nil
        return "["..table.concat(parts,",").."]"
    end
    local keys={}
    for k in pairs(v) do keys[#keys+1]=tostring(k) end
    table.sort(keys)
    for _,k in ipairs(keys) do parts[#parts+1]=esc(k)..":"..encode(v[k],seen) end
    seen[v]=nil
    return "{"..table.concat(parts,",").."}"
end

local sg=Instance.new("ScreenGui")
sg.Name="PSICO_EGG_CYCLE_DATA_PROBE"; sg.ResetOnSpawn=false; sg.DisplayOrder=1401; sg.Parent=CoreGui
local frame=Instance.new("Frame")
frame.AnchorPoint=Vector2.new(.5,.5); frame.Position=UDim2.fromScale(.5,.5); frame.Size=UDim2.fromOffset(430,205); frame.BackgroundColor3=Color3.fromRGB(9,18,34); frame.BorderSizePixel=0; frame.Parent=sg
Instance.new("UICorner",frame).CornerRadius=UDim.new(0,14)
local title=Instance.new("TextLabel")
title.BackgroundTransparency=1; title.Position=UDim2.fromOffset(14,10); title.Size=UDim2.new(1,-28,0,28); title.Text="EGG CYCLE DATA PROBE"; title.Font=Enum.Font.GothamBold; title.TextSize=14; title.TextColor3=Color3.fromRGB(238,245,255); title.Parent=frame
local status=Instance.new("TextLabel")
status.Position=UDim2.fromOffset(14,48); status.Size=UDim2.new(1,-28,0,60); status.BackgroundColor3=Color3.fromRGB(15,29,52); status.BorderSizePixel=0; status.Text="Pronto. Captura apenas dados retornados por módulos replicados."; status.TextWrapped=true; status.Font=Enum.Font.Code; status.TextSize=11; status.TextColor3=Color3.fromRGB(215,229,247); status.Parent=frame
Instance.new("UICorner",status).CornerRadius=UDim.new(0,9)
local function button(text,x,y,w)
    local b=Instance.new("TextButton"); b.Position=UDim2.fromOffset(x,y); b.Size=UDim2.fromOffset(w,38); b.BackgroundColor3=Color3.fromRGB(31,78,132); b.BorderSizePixel=0; b.Text=text; b.TextColor3=Color3.fromRGB(244,248,255); b.Font=Enum.Font.GothamBold; b.TextSize=11; b.Parent=frame; Instance.new("UICorner",b).CornerRadius=UDim.new(0,9); return b
end
local capture=button("CAPTURAR + EXPORTAR",14,122,255)
local close=button("FECHAR",283,122,133)
capture.MouseButton1Click:Connect(function()
    status.Text="Lendo módulos replicados..."
    task.defer(function()
        local ok,data=pcall(snapshot)
        if not ok then status.Text="Erro: "..tostring(data) return end
        local ok2,json=pcall(function() return encode(data,{}) end)
        if not ok2 then status.Text="Erro JSON: "..tostring(json) return end
        local name="Psico_EggCycleData_"..os.time()..".json"
        local wrote=false
        if writefile then wrote=pcall(writefile,name,json) end
        if setclipboard then pcall(setclipboard,json) end
        status.Text=(wrote and "EXPORTADO: " or "COPIADO: ")..name.." | "..#json.." bytes"
    end)
end)
close.MouseButton1Click:Connect(function() sg:Destroy() end)
local dragging=false
local dragStart,startPos
frame.InputBegan:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then dragging=true; dragStart=i.Position; startPos=frame.Position end end)
frame.InputChanged:Connect(function(i) if dragging and (i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch) then local d=i.Position-dragStart; frame.Position=UDim2.new(startPos.X.Scale,startPos.X.Offset+d.X,startPos.Y.Scale,startPos.Y.Offset+d.Y) end end)
UserInputService.InputEnded:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then dragging=false end end)

-- PSICOSENATICO | AXON PREDICTOR TRACE V2.4
-- Zero-hook / passive observation.
-- Reads Axon predictor UI and listens to replicated RemoteEvents with OnClientEvent only.
-- Does NOT invoke remotes, hook functions, use debug/getgc, intercept HTTP, or mutate game state.

local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local PERIOD_SECONDS = 300
local MAX_EVENTS = 500
local MAX_OBSERVATIONS = 350

local state = {
    running = false,
    closed = false,
    startedAt = nil,
    status = nil,
    gui = nil,
    lastFingerprint = nil,
    lastCards = {},
    observations = {},
    changes = {},
    history = {},
    events = {},
    reveals = {},
    validations = {},
    refreshLog = {},
    uiSnapshots = {},
    shiftedByPeriod = {},
    panelVisibilityLog = {},
    panelVisibleNow = nil,
    lastPanelVisibleAt = nil,
    lastPredictorEvidenceAt = nil,
    hiddenCardClock = {},
    hiddenObservations = {},
    hiddenFingerprint = nil,
    refreshClicks = 0,
    scans = 0,
    remoteConnections = {},
    attachedRemotes = setmetatable({}, {__mode = "k"}),
    attachedRefreshButtons = setmetatable({}, {__mode = "k"}),
    lastCheckpoint = 0,
}

local rarities = {
    basic=true, common=true, uncommon=true, rare=true, superrare=true, epic=true,
    legendary=true, mythic=true, mythical=true, cosmic=true, secret=true,
    eternal=true, divine=true, exotic=true, celestial=true, superior=true,
    titan=true, exclusive=true, limited=true, lightdark=true, ["brainrotgod"]=true,
}

local function nowUnix()
    local ok, value = pcall(function()
        return Workspace:GetServerTimeNow()
    end)
    if ok and type(value) == "number" and value > 1000000000 then
        return value
    end
    return os.time()
end

local function periodAt(t)
    return math.floor((tonumber(t) or nowUnix()) / PERIOD_SECONDS)
end

local function pathOf(x)
    local ok, value = pcall(function() return x:GetFullName() end)
    return ok and value or tostring(x)
end

local function lower(v)
    return string.lower(tostring(v or ""))
end

local function trim(s)
    s = tostring(s or "")
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function textOf(x)
    if not (x:IsA("TextLabel") or x:IsA("TextButton") or x:IsA("TextBox")) then
        return nil
    end
    local ok, value = pcall(function() return x.Text end)
    if not ok then return nil end
    value = trim(value)
    return value ~= "" and value or nil
end

local function visibleOf(x)
    if not x:IsA("GuiObject") then return true end
    local ok, value = pcall(function() return x.Visible end)
    return ok and value ~= false
end

local function actuallyVisible(x)
    local cur = x
    while cur do
        if cur:IsA("GuiObject") then
            local ok, v = pcall(function() return cur.Visible end)
            if ok and v == false then return false end
        elseif cur:IsA("ScreenGui") then
            local ok, enabled = pcall(function() return cur.Enabled end)
            if ok and enabled == false then return false end
        end
        cur = cur.Parent
        if cur == CoreGui then break end
        local pg = player and player:FindFirstChildOfClass("PlayerGui")
        if pg and cur == pg then break end
    end
    return true
end

local function safeAttributes(x)
    local out = {}
    local ok, attrs = pcall(function() return x:GetAttributes() end)
    if ok and type(attrs) == "table" then
        for k, v in pairs(attrs) do
            local t = typeof(v)
            if t == "string" or t == "number" or t == "boolean" then
                out[tostring(k)] = v
            else
                out[tostring(k)] = tostring(v)
            end
        end
    end
    return out
end

local function sanitize(v, depth, seen)
    depth = depth or 0
    seen = seen or {}
    local t = typeof(v)
    if t == "nil" or t == "boolean" or t == "string" or t == "number" then
        return v
    end
    if t == "Instance" then
        return {class=v.ClassName, name=v.Name, path=pathOf(v), attributes=safeAttributes(v)}
    end
    if t == "Vector3" or t == "Vector2" or t == "CFrame" or t == "Color3"
        or t == "UDim2" or t == "UDim" or t == "EnumItem" then
        return tostring(v)
    end
    if t ~= "table" then
        return tostring(v)
    end
    if seen[v] then return "<cycle>" end
    if depth >= 7 then return "<depth-limit>" end
    seen[v] = true
    local out = {}
    local count = 0
    for k, value in pairs(v) do
        count += 1
        if count > 350 then
            out["<truncated>"] = true
            break
        end
        out[tostring(k)] = sanitize(value, depth + 1, seen)
    end
    seen[v] = nil
    return out
end

local function parseEtaSeconds(text)
    local s = lower(trim(text))
    if not string.find(s, "in ", 1, true) then return nil end
    local h = tonumber(s:match("(%d+)%s*h")) or 0
    local m = tonumber(s:match("(%d+)%s*m")) or 0
    local sec = tonumber(s:match("(%d+)%s*s")) or 0
    local total = h * 3600 + m * 60 + sec
    if total <= 0 and not s:match("0%s*s") then return nil end
    return total
end

local function parseRarityArea(text)
    local a, b = trim(text):match("^([^/]+)%s*/%s*(.+)$")
    if not a or not b then return nil, nil end
    local key = lower(a):gsub("%s+", "")
    if rarities[key] then
        return trim(a), trim(b)
    end
    return nil, nil
end

local function parseChance(text)
    local n = tostring(text or ""):match("(%d+)%s*%%")
    return n and tonumber(n) or nil
end

local genericPhrases = {
    "egg predictor", "refresh predictions", "upcoming spawns", "forecast",
    "search pet", "rarities", "next egg change", "eggs change every",
    "shared estimates", "not guaranteed", "announcements use",
    "shown", "area", "show", "predictor",
}

local function isGenericText(text)
    local s = lower(trim(text))
    if s == "" then return true end
    if parseEtaSeconds(text) ~= nil then return true end
    if parseChance(text) ~= nil then return true end
    local r = parseRarityArea(text)
    if r then return true end
    for _, phrase in ipairs(genericPhrases) do
        if string.find(s, phrase, 1, true) then return true end
    end
    if s == "day" or s == "night" or s == "event" then return true end
    return false
end

local function rootCandidates()
    local roots = {}
    local containers = {CoreGui}
    local pg = player and player:FindFirstChildOfClass("PlayerGui")
    if pg then containers[#containers+1] = pg end

    for _, container in ipairs(containers) do
        for _, top in ipairs(container:GetChildren()) do
            local score = 0
            local ok, desc = pcall(function() return top:GetDescendants() end)
            if ok then
                local checked = 0
                for _, d in ipairs(desc) do
                    if d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox") then
                        local tx = textOf(d)
                        local s = lower(tx)
                        if s == "egg predictor" then score += 7 end
                        if string.find(s, "refresh predictions", 1, true) then score += 6 end
                        if string.find(s, "upcoming spawns", 1, true) then score += 5 end
                        if string.find(s, "axon hub", 1, true) then score += 5 end
                    end
                    checked += 1
                    if checked >= 2600 then break end
                end
            end
            if score >= 6 then
                roots[#roots+1] = top
            end
        end
    end
    return roots
end

local function collectTexts(node, maxCount)
    local out = {}
    local seenText = {}
    maxCount = maxCount or 40
    if textOf(node) and actuallyVisible(node) then
        local tx = textOf(node)
        seenText[tx] = true
        out[#out+1] = {text=tx, path=pathOf(node), class=node.ClassName}
    end
    local ok, desc = pcall(function() return node:GetDescendants() end)
    if ok then
        for _, d in ipairs(desc) do
            if #out >= maxCount then break end
            if (d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox")) and actuallyVisible(d) then
                local tx = textOf(d)
                if tx and not seenText[tx] then
                    seenText[tx] = true
                    out[#out+1] = {text=tx, path=pathOf(d), class=d.ClassName}
                end
            end
        end
    end
    return out
end

local function collectTextsAny(node, maxCount)
    local out = {}
    local seenText = {}
    maxCount = maxCount or 40
    local ntx = textOf(node)
    if ntx and visibleOf(node) then
        seenText[ntx] = true
        out[#out+1] = {text=ntx, path=pathOf(node), class=node.ClassName}
    end
    local ok, desc = pcall(function() return node:GetDescendants() end)
    if ok then
        for _, d in ipairs(desc) do
            if #out >= maxCount then break end
            if (d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox")) and visibleOf(d) then
                local tx = textOf(d)
                if tx and not seenText[tx] then
                    seenText[tx] = true
                    out[#out+1] = {text=tx, path=pathOf(d), class=d.ClassName}
                end
            end
        end
    end
    return out
end

local function cardScore(texts)
    local score = 0
    local hasEta, hasChance, hasRA = false, false, false
    for _, item in ipairs(texts) do
        if parseEtaSeconds(item.text) ~= nil then hasEta = true end
        if parseChance(item.text) ~= nil then hasChance = true end
        local r = parseRarityArea(item.text)
        if r then hasRA = true end
    end
    if hasEta then score += 4 end
    if hasChance then score += 2 end
    if hasRA then score += 4 end
    if #texts >= 3 and #texts <= 14 then score += 2 end
    return score
end

local function chooseCardAncestor(label, root)
    local best, bestTexts, bestScore = nil, nil, -1
    local node = label.Parent
    local depth = 0
    while node and node ~= root.Parent and depth < 7 do
        local texts = collectTexts(node, 24)
        local score = cardScore(texts)
        if score > bestScore then
            best, bestTexts, bestScore = node, texts, score
        end
        if score >= 10 and #texts <= 12 then
            return node, texts
        end
        if node == root then break end
        node = node.Parent
        depth += 1
    end
    if bestScore >= 8 then return best, bestTexts end
    return nil, nil
end

local function derivePet(texts)
    local candidates = {}
    for _, item in ipairs(texts) do
        local tx = trim(item.text)
        if #tx >= 2 and #tx <= 64 and not isGenericText(tx) then
            candidates[#candidates+1] = tx
        end
    end
    table.sort(candidates, function(a,b)
        local aWords = select(2, a:gsub("%s+", " ")) + 1
        local bWords = select(2, b:gsub("%s+", " ")) + 1
        if aWords ~= bWords then return aWords > bWords end
        return #a > #b
    end)
    return candidates[1], candidates
end

local function parseCard(label, root, capturedAt)
    local eta = parseEtaSeconds(textOf(label))
    if eta == nil then return nil end

    local ancestor, texts = chooseCardAncestor(label, root)
    if not ancestor or not texts then return nil end

    local rarity, area, chance
    for _, item in ipairs(texts) do
        if not rarity then
            local r, a = parseRarityArea(item.text)
            if r then rarity, area = r, a end
        end
        if not chance then chance = parseChance(item.text) end
    end
    if not rarity or not area then return nil end

    local pet, candidates = derivePet(texts)
    if not pet then pet = "<unparsed>" end

    local targetUnix = capturedAt + eta
    local targetPeriod = periodAt(targetUnix)
    local rawTexts = {}
    for _, item in ipairs(texts) do rawTexts[#rawTexts+1] = item.text end

    return {
        pet = pet,
        petCandidates = candidates,
        rarity = rarity,
        area = area,
        chance = chance,
        etaSeconds = eta,
        etaText = textOf(label),
        capturedAt = capturedAt,
        targetUnix = targetUnix,
        targetPeriod = targetPeriod,
        cardPath = pathOf(ancestor),
        etaPath = pathOf(label),
        texts = rawTexts,
    }
end

local function chooseCardAncestorAny(label, root)
    local best, bestTexts, bestScore = nil, nil, -1
    local node = label.Parent
    local depth = 0
    while node and node ~= root.Parent and depth < 7 do
        local texts = collectTextsAny(node, 24)
        local score = cardScore(texts)
        if score > bestScore then
            best, bestTexts, bestScore = node, texts, score
        end
        if score >= 10 and #texts <= 12 then
            return node, texts
        end
        if node == root then break end
        node = node.Parent
        depth += 1
    end
    if bestScore >= 8 then return best, bestTexts end
    return nil, nil
end

local function parseCardAny(label, root, capturedAt)
    local eta = parseEtaSeconds(textOf(label))
    if eta == nil then return nil end
    local ancestor, texts = chooseCardAncestorAny(label, root)
    if not ancestor or not texts then return nil end
    local rarity, area, chance
    for _, item in ipairs(texts) do
        if not rarity then
            local r, a = parseRarityArea(item.text)
            if r then rarity, area = r, a end
        end
        if not chance then chance = parseChance(item.text) end
    end
    if not rarity or not area then return nil end
    local pet, candidates = derivePet(texts)
    if not pet then pet = "<unparsed>" end
    local targetUnix = capturedAt + eta
    local rawTexts = {}
    for _, item in ipairs(texts) do rawTexts[#rawTexts+1] = item.text end
    return {
        pet=pet, petCandidates=candidates, rarity=rarity, area=area, chance=chance,
        etaSeconds=eta, etaText=textOf(label), capturedAt=capturedAt,
        targetUnix=targetUnix, targetPeriod=periodAt(targetUnix),
        cardPath=pathOf(ancestor), etaPath=pathOf(label), texts=rawTexts,
        sourceVisible=actuallyVisible(label),
    }
end

local function isPredictorCardDescendant(x)
    local cur = x
    for _=1,8 do
        if not cur then break end
        local n = lower(cur.Name)
        if string.find(n, "predictorpetcard", 1, true) then return true end
        cur = cur.Parent
    end
    return false
end

local function collectStatusTexts(root)
    local out = {}
    local ok, desc = pcall(function() return root:GetDescendants() end)
    if not ok then return out end
    for _, d in ipairs(desc) do
        if (d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox")) and actuallyVisible(d) then
            local tx = textOf(d)
            local s = lower(tx)
            if tx and (
                string.find(s, "shown", 1, true)
                or string.find(s, "shared estimates", 1, true)
                or string.find(s, "next egg change", 1, true)
                or string.find(s, "eggs change every", 1, true)
            ) then
                out[#out+1] = tx
            end
        end
    end
    return out
end

local function cardIdentity(card)
    return table.concat({
        tostring(card.targetPeriod or "?"),
        lower(card.area),
        lower(card.pet),
        lower(card.rarity),
        tostring(card.chance or "?")
    }, "|")
end

local function logicalSlot(card)
    return table.concat({
        tostring(card.targetPeriod or "?"),
        lower(card.area)
    }, "|")
end

local function sortedCardFingerprint(cards)
    local parts = {}
    for _, card in ipairs(cards) do parts[#parts+1] = cardIdentity(card) end
    table.sort(parts)
    return table.concat(parts, "\n")
end

local function mapCards(cards)
    local out = {}
    for _, card in ipairs(cards) do
        local slot = logicalSlot(card)
        out[slot] = out[slot] or {}
        out[slot][cardIdentity(card)] = card
    end
    return out
end

local function addBounded(list, value, max)
    list[#list+1] = value
    if #list > max then table.remove(list, 1) end
end

local function updateHistory(cards, capturedAt)
    for _, card in ipairs(cards) do
        local id = cardIdentity(card)
        local rec = state.history[id]
        if not rec then
            rec = {
                id=id, pet=card.pet, rarity=card.rarity, area=card.area,
                chance=card.chance, targetPeriod=card.targetPeriod,
                targetUnix=card.targetUnix, firstSeen=capturedAt,
                lastSeen=capturedAt, seenCount=0,
                firstEta=card.etaSeconds, lastEta=card.etaSeconds,
                rawTexts=card.texts,
                lastEvidenceMode=card.evidenceMode or "visible",
            }
            state.history[id] = rec
        end
        rec.lastSeen = capturedAt
        rec.seenCount += 1
        rec.lastEta = card.etaSeconds
        rec.lastEvidenceMode = card.evidenceMode or rec.lastEvidenceMode or "visible"
        if card.evidenceMode == "visible" then rec.lastVisibleSeen = capturedAt end
        if card.evidenceMode == "hidden-live" then rec.lastHiddenLiveSeen = capturedAt end
    end
end

local function hiddenClockSignature(card)
    return table.concat({
        lower(card.pet), lower(card.area), lower(card.rarity), tostring(card.chance or "?")
    }, "|")
end

local function assessHiddenClock(card, capturedAt)
    local key = card.cardPath
    local sig = hiddenClockSignature(card)
    local prev = state.hiddenCardClock[key]
    local live = false
    local etaDrop, elapsed = nil, nil
    if prev and prev.signature == sig then
        elapsed = capturedAt - prev.unix
        etaDrop = (prev.eta or card.etaSeconds) - card.etaSeconds
        if elapsed >= 0.7 and etaDrop and etaDrop > 0 then
            local tolerance = math.max(3.5, elapsed * 0.45)
            if math.abs(etaDrop - elapsed) <= tolerance then
                live = true
            end
        elseif prev.live and elapsed and elapsed <= 3.2 and etaDrop == 0 then
            live = true
        end
    end
    state.hiddenCardClock[key] = {
        signature=sig, eta=card.etaSeconds, unix=capturedAt, live=live,
        targetPeriod=card.targetPeriod,
    }
    return live, etaDrop, elapsed
end

local function compareCards(before, after, capturedAt, reason)
    local a = mapCards(before or {})
    local b = mapCards(after or {})
    local slots = {}
    for k in pairs(a) do slots[k] = true end
    for k in pairs(b) do slots[k] = true end

    for slot in pairs(slots) do
        local av = a[slot] or {}
        local bv = b[slot] or {}
        local added, removed = {}, {}
        for id, card in pairs(bv) do if not av[id] then added[#added+1] = card end end
        for id, card in pairs(av) do if not bv[id] then removed[#removed+1] = card end end
        if #added > 0 or #removed > 0 then
            addBounded(state.changes, {
                unix=capturedAt, period=periodAt(capturedAt), reason=reason,
                slot=slot, added=added, removed=removed
            }, MAX_OBSERVATIONS)
        end
    end
end

local function predictorPanelVisible(statuses, cards)
    if #cards > 0 then return true end
    for _, tx in ipairs(statuses or {}) do
        local s = lower(tx)
        if string.find(s, "upcoming spawns", 1, true)
            or string.find(s, "next egg change", 1, true)
            or string.find(s, "shared estimates", 1, true) then
            return true
        end
    end
    return false
end

local function notePanelVisibility(visible, capturedAt)
    if visible then state.lastPanelVisibleAt = capturedAt end
    if state.panelVisibleNow == visible then return end
    state.panelVisibleNow = visible
    addBounded(state.panelVisibilityLog, {
        unix=capturedAt,
        currentPeriod=periodAt(capturedAt),
        visible=visible,
    }, 120)
end

local function visibleTextsForRoots(roots, limit)
    local out, seen = {}, {}
    limit = limit or 220
    for _, root in ipairs(roots or {}) do
        local ok, desc = pcall(function() return root:GetDescendants() end)
        if ok then
            for _, d in ipairs(desc) do
                if #out >= limit then break end
                if (d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox")) and actuallyVisible(d) then
                    local tx = textOf(d)
                    if tx and not seen[tx] then
                        seen[tx] = true
                        out[#out+1] = tx
                    end
                end
            end
        end
        if #out >= limit then break end
    end
    return out
end

local function scanPredictor(reason)
    local capturedAt = nowUnix()
    local roots = rootCandidates()
    local cards, hiddenCards, statuses = {}, {}, {}
    local seenVisiblePath, seenHiddenPath = {}, {}

    for _, root in ipairs(roots) do
        local rootStatuses = collectStatusTexts(root)
        for _, s in ipairs(rootStatuses) do statuses[#statuses+1] = s end

        local ok, desc = pcall(function() return root:GetDescendants() end)
        if ok then
            for _, d in ipairs(desc) do
                if d:IsA("TextLabel") or d:IsA("TextButton") then
                    local tx = textOf(d)
                    if tx and parseEtaSeconds(tx) ~= nil and isPredictorCardDescendant(d) then
                        if actuallyVisible(d) then
                            local card = parseCard(d, root, capturedAt)
                            if card and not seenVisiblePath[card.cardPath] then
                                seenVisiblePath[card.cardPath] = true
                                card.evidenceMode = "visible"
                                cards[#cards+1] = card
                                state.hiddenCardClock[card.cardPath] = {
                                    signature=hiddenClockSignature(card), eta=card.etaSeconds,
                                    unix=capturedAt, live=true, targetPeriod=card.targetPeriod,
                                }
                            end
                        else
                            local card = parseCardAny(d, root, capturedAt)
                            if card and not seenHiddenPath[card.cardPath] then
                                seenHiddenPath[card.cardPath] = true
                                local live, etaDrop, elapsed = assessHiddenClock(card, capturedAt)
                                card.etaLive = live
                                card.etaDrop = etaDrop
                                card.elapsedSincePrior = elapsed
                                card.evidenceMode = live and "hidden-live" or "hidden-stale"
                                hiddenCards[#hiddenCards+1] = card
                            end
                        end
                    end
                end
            end
        end
    end

    local function sortCards(list)
        table.sort(list, function(a,b)
            if a.targetPeriod ~= b.targetPeriod then return a.targetPeriod < b.targetPeriod end
            if a.area ~= b.area then return a.area < b.area end
            return a.pet < b.pet
        end)
    end
    sortCards(cards)
    sortCards(hiddenCards)

    state.scans += 1
    local panelVisible = predictorPanelVisible(statuses, cards)
    notePanelVisibility(panelVisible, capturedAt)

    local evidenceCards = {}
    if #cards > 0 then
        for _, card in ipairs(cards) do evidenceCards[#evidenceCards+1] = card end
        state.lastPredictorEvidenceAt = capturedAt
    else
        local hiddenLiveCount = 0
        for _, card in ipairs(hiddenCards) do
            if card.etaLive then
                hiddenLiveCount += 1
                evidenceCards[#evidenceCards+1] = card
            end
        end
        if hiddenLiveCount > 0 then state.lastPredictorEvidenceAt = capturedAt end
    end

    if #evidenceCards > 0 then
        updateHistory(evidenceCards, capturedAt)
        local fingerprint = sortedCardFingerprint(evidenceCards)
        if fingerprint ~= state.lastFingerprint then
            compareCards(state.lastCards, evidenceCards, capturedAt, reason or "scan")
            addBounded(state.observations, {
                unix=capturedAt, currentPeriod=periodAt(capturedAt),
                reason=reason or "scan", cards=evidenceCards,
                statusTexts=statuses, rootCount=#roots,
                predictorPanelVisible=panelVisible,
                evidenceMode=(#cards > 0) and "visible" or "hidden-live",
            }, MAX_OBSERVATIONS)
            state.lastFingerprint = fingerprint
            state.lastCards = evidenceCards
        end
    end

    local hiddenFpParts = {}
    for _, card in ipairs(hiddenCards) do
        hiddenFpParts[#hiddenFpParts+1] = table.concat({
            cardIdentity(card), tostring(card.etaLive), tostring(card.etaText)
        }, "|")
    end
    table.sort(hiddenFpParts)
    local hiddenFp = table.concat(hiddenFpParts, "\n")
    if hiddenFp ~= state.hiddenFingerprint and #hiddenCards > 0 then
        state.hiddenFingerprint = hiddenFp
        addBounded(state.hiddenObservations, {
            unix=capturedAt, currentPeriod=periodAt(capturedAt),
            cards=hiddenCards,
        }, 120)
    end

    if reason == "manual-snapshot" then
        addBounded(state.uiSnapshots, {
            unix=capturedAt, currentPeriod=periodAt(capturedAt),
            predictorPanelVisible=panelVisible, rootCount=#roots,
            texts=visibleTextsForRoots(roots, 220),
            hiddenPredictorCards=hiddenCards,
        }, 40)
    end

    if state.status and state.status.Parent then
        local mode = #cards > 0 and "VISÍVEL" or (#evidenceCards > 0 and "OCULTO+ATIVO" or "SEM EVIDÊNCIA")
        state.status.Text = string.format(
            "TRACE %s | período %d | %d previsões | %d mudanças | %d reveals | scans %d",
            mode, periodAt(capturedAt), #state.lastCards, #state.changes, #state.reveals, state.scans
        )
    end
    return state.lastCards, panelVisible
end

local function findField(value, wanted, depth, seen)
    depth = depth or 0
    seen = seen or {}
    if depth > 7 or type(value) ~= "table" or seen[value] then return nil end
    seen[value] = true
    for k, v in pairs(value) do
        if lower(k) == lower(wanted) then
            seen[value] = nil
            return v
        end
        if type(v) == "table" then
            local found = findField(v, wanted, depth + 1, seen)
            if found ~= nil then
                seen[value] = nil
                return found
            end
        end
    end
    seen[value] = nil
    return nil
end

local function forecastsForPeriod(period)
    local out = {}
    for _, rec in pairs(state.history) do
        if rec.targetPeriod == period then
            out[#out+1] = rec
        end
    end
    table.sort(out, function(a,b)
        if a.area ~= b.area then return a.area < b.area end
        return a.pet < b.pet
    end)
    return out
end

local function normName(v)
    return lower(v):gsub("[^%w]", "")
end

local petAliases = {
    trex="tyrannosaurusrex",
    tyrannosaurusrex="tyrannosaurusrex",
    gargoyle="darkgargoyle",
    darkgargoyle="darkgargoyle",
    cosmicskeletonboss="alienskeletonboss",
    alienskeletonboss="alienskeletonboss",
    gorillaking="kingkong",
    kingkong="kingkong",
    purejellyfish="jellyfish",
    jellyfish="jellyfish",
    lavadragon="dragon",
    dragon="dragon",
}

local function canonPet(v)
    local n = normName(v)
    return petAliases[n] or n
end

local function canonArea(v)
    local n = normName(v)
    if n == "angels" or n == "demons" or n == "lightdark" or n == "angelsdemons" then
        return "lightdark"
    end
    return n
end

local function parseRareSpawn(spawn)
    if type(spawn) ~= "table" then return nil end
    local msg = tostring(spawn.Message or "")
    local rarity = tostring(spawn.RarityId or "")
    local inside = msg:match("<font[^>]*>(.-)</font>") or ""
    inside = inside:gsub("^%s+", ""):gsub("%s+$", "")
    inside = inside:gsub("%s+Egg$", "")
    if rarity ~= "" then
        local prefix = "^"..rarity:gsub("(%W)","%%%1").."%s+"
        inside = inside:gsub(prefix, "")
    end
    local area = msg:match("spawned in%s+<font[^>]*>(.-)</font>") or ""
    return {
        pet=inside,
        rarity=rarity,
        area=area,
        uid=spawn.EggUid,
        message=msg,
    }
end

local function actualRareList(rawRareSpawns)
    local out = {}
    if type(rawRareSpawns) ~= "table" then return out end
    for _, spawn in pairs(rawRareSpawns) do
        local parsed = parseRareSpawn(spawn)
        if parsed and parsed.pet ~= "" then out[#out+1] = parsed end
    end
    return out
end

local function validatePeriod(period, rawRareSpawns, revealUnix)
    local predictions = forecastsForPeriod(period)
    local actual = actualRareList(rawRareSpawns)
    local matchedActual = {}
    local hits, misses = {}, {}

    for _, pred in ipairs(predictions) do
        local matchIndex = nil
        for i, act in ipairs(actual) do
            if not matchedActual[i]
                and canonPet(pred.pet) == canonPet(act.pet)
                and canonArea(pred.area) == canonArea(act.area) then
                matchIndex = i
                break
            end
        end
        if matchIndex then
            matchedActual[matchIndex] = true
            hits[#hits+1] = {prediction=pred, actual=actual[matchIndex]}
        else
            misses[#misses+1] = pred
        end
    end

    local unpredicted = {}
    for i, act in ipairs(actual) do
        if not matchedActual[i] then unpredicted[#unpredicted+1] = act end
    end

    local boundary = period * PERIOD_SECONDS
    local evidenceGap = nil
    if type(state.lastPredictorEvidenceAt) == "number" then
        evidenceGap = math.max(0, boundary - state.lastPredictorEvidenceAt)
    end
    local coverageAtTarget = evidenceGap ~= nil and evidenceGap <= 20

    local confirmed, unverified = {}, {}
    for _, pred in ipairs(predictions) do
        if type(pred.lastSeen) == "number" and pred.lastSeen >= boundary - 20
            and (pred.lastEvidenceMode == "visible" or pred.lastEvidenceMode == "hidden-live") then
            confirmed[#confirmed+1] = pred
        else
            unverified[#unverified+1] = pred
        end
    end

    local confirmedIds = {}
    for _, pred in ipairs(confirmed) do confirmedIds[pred.id] = true end
    local confirmedMisses, confirmedHits = {}, {}
    if coverageAtTarget then
        for _, hit in ipairs(hits) do
            if hit.prediction and confirmedIds[hit.prediction.id] then
                confirmedHits[#confirmedHits+1] = hit
            end
        end
        for _, miss in ipairs(misses) do
            if confirmedIds[miss.id] then confirmedMisses[#confirmedMisses+1] = miss end
        end
    end

    local nearbyMatches = {}
    for _, act in ipairs(actual) do
        local matches = {}
        for _, rec in pairs(state.history) do
            local offset = period - rec.targetPeriod
            if math.abs(offset) <= 12
                and canonPet(rec.pet) == canonPet(act.pet)
                and canonArea(rec.area) == canonArea(act.area) then
                matches[#matches+1] = {
                    prediction=rec,
                    periodOffset=offset,
                    minutesOffset=offset * 5,
                }
            end
        end
        table.sort(matches, function(a,b)
            return math.abs(a.periodOffset) < math.abs(b.periodOffset)
        end)
        nearbyMatches[#nearbyMatches+1] = {actual=act, matches=matches}
    end

    return {
        unix=revealUnix,
        periodIndex=period,
        predictedCount=#predictions,
        actualRareCount=#actual,
        exactHitCount=#hits,
        predictions=predictions,
        actual=actual,
        exactHits=hits,
        misses=misses,
        unpredictedActual=unpredicted,
        coverageAtTarget=coverageAtTarget,
        coverageGapSeconds=evidenceGap,
        lastPredictorEvidenceAt=state.lastPredictorEvidenceAt,
        confirmedAtTarget=confirmed,
        confirmedAtTargetCount=#confirmed,
        unverifiedBecauseNoLiveEvidence=unverified,
        confirmedExactHits=confirmedHits,
        confirmedExactHitCount=#confirmedHits,
        confirmedMisses=confirmedMisses,
        nearbyPeriodMatches=nearbyMatches,
        validationStatus=coverageAtTarget and "covered" or "insufficient-predictor-evidence",
    }
end

local function compactShift(raw)
    if type(raw) ~= "table" then return nil end
    return {
        uid=raw.Uid,
        area=raw.AreaId,
        asset=raw.AssetCategory,
        nest=raw.NestId,
        version=raw.Version,
        mutations=sanitize(raw.Mutations),
    }
end

local function captureRemoteEvent(remote, ...)
    local capturedAt = nowUnix()
    local rawArgs = table.pack(...)
    local argsForSearch = {}
    local safeArgs = {}
    for i = 1, rawArgs.n do
        argsForSearch[i] = rawArgs[i]
        safeArgs[i] = sanitize(rawArgs[i])
    end

    local p = findField(argsForSearch, "PeriodIndex")
    if type(p) ~= "number" then p = periodAt(capturedAt) end

    local eventLower = lower(remote.Name)
    if string.find(eventLower, "fieldeggshifted", 1, true)
        and not string.find(eventLower, "batch", 1, true) then
        local first = rawArgs[1]
        local compact = compactShift(first)
        if compact and compact.uid then
            local bucket = state.shiftedByPeriod[tostring(p)]
            if not bucket then
                bucket = {periodIndex=p, firstSeen=capturedAt, lastSeen=capturedAt, byUid={}}
                state.shiftedByPeriod[tostring(p)] = bucket
            end
            bucket.lastSeen = capturedAt
            bucket.byUid[tostring(compact.uid)] = compact
        end
        return
    end

    local record = {
        unix=capturedAt,
        currentPeriod=periodAt(capturedAt),
        event=remote.Name,
        path=pathOf(remote),
        periodIndex=p,
        args=safeArgs,
        forecastCandidates=forecastsForPeriod(p),
    }
    addBounded(state.events, record, MAX_EVENTS)

    if string.find(eventLower, "raritiesshown", 1, true) then
        local rareSpawns = findField(argsForSearch, "RareSpawns")
        local dayStartsAt = findField(argsForSearch, "DayStartsAt")
        local validation = validatePeriod(p, rareSpawns, capturedAt)
        local reveal = {
            unix=capturedAt,
            periodIndex=p,
            dayStartsAt=type(dayStartsAt)=="number" and dayStartsAt or nil,
            rareSpawns=sanitize(rareSpawns),
            forecastCandidates=forecastsForPeriod(p),
            validation=validation,
            rawArgs=safeArgs,
        }
        addBounded(state.reveals, reveal, 120)
        addBounded(state.validations, validation, 120)
    end
end

local watchedRemoteNames = {
    ["RE/EggWorld/FieldEggRaritiesShown"] = true,
    ["RE/EggWorld/FieldEggBatchShifted"] = true,
    ["RE/EggWorld/FieldEggShifted"] = true,
    ["RE/EggWorld/FieldEggCycleCountdown"] = true,
    ["FieldEggRaritiesShown"] = true,
    ["FieldEggBatchShifted"] = true,
    ["FieldEggShifted"] = true,
    ["FieldEggCycleCountdown"] = true,
}

local function shouldWatchRemote(x)
    if not x:IsA("RemoteEvent") then return false end
    if watchedRemoteNames[x.Name] then return true end
    local p = pathOf(x)
    for name in pairs(watchedRemoteNames) do
        if string.find(p, name, 1, true) then return true end
    end
    return false
end

local function attachRemote(x)
    if not shouldWatchRemote(x) or state.attachedRemotes[x] then return end
    state.attachedRemotes[x] = true
    local conn = x.OnClientEvent:Connect(function(...)
        captureRemoteEvent(x, ...)
    end)
    state.remoteConnections[#state.remoteConnections+1] = conn
end

local function attachExistingRemotes()
    local ok, desc = pcall(function() return ReplicatedStorage:GetDescendants() end)
    if not ok then return end
    for _, x in ipairs(desc) do attachRemote(x) end
end

local function attachRefreshButtons()
    for _, root in ipairs(rootCandidates()) do
        local ok, desc = pcall(function() return root:GetDescendants() end)
        if ok then
            for _, d in ipairs(desc) do
                if d:IsA("TextButton") and not state.attachedRefreshButtons[d] then
                    local tx = lower(textOf(d))
                    if tx and string.find(tx, "refresh predictions", 1, true) then
                        state.attachedRefreshButtons[d] = true
                        d.MouseButton1Click:Connect(function()
                            state.refreshClicks += 1
                            local entry = {
                                unix=nowUnix(),
                                currentPeriod=periodAt(nowUnix()),
                                index=state.refreshClicks,
                                before=sanitize(state.lastCards),
                            }
                            addBounded(state.refreshLog, entry, 80)
                            task.delay(0.35, function()
                                if state.running and not state.closed then
                                    local cards, visible = scanPredictor("refresh+0.35s")
                                    entry.after035=sanitize(cards)
                                    entry.visible035=visible
                                end
                            end)
                            task.delay(1.25, function()
                                if state.running and not state.closed then
                                    local cards, visible = scanPredictor("refresh+1.25s")
                                    entry.after125=sanitize(cards)
                                    entry.visible125=visible
                                end
                            end)
                        end)
                    end
                end
            end
        end
    end
end

local function report()
    local history = {}
    for _, rec in pairs(state.history) do history[#history+1] = rec end
    table.sort(history, function(a,b)
        if a.targetPeriod ~= b.targetPeriod then return a.targetPeriod < b.targetPeriod end
        if a.area ~= b.area then return a.area < b.area end
        return a.pet < b.pet
    end)

    return {
        meta={
            version="AxonPredictorTraceV2.4",
            zeroHook=true,
            passive=true,
            created=nowUnix(),
            startedAt=state.startedAt,
            placeId=tostring(game.PlaceId),
            gameId=tostring(game.GameId),
            jobId=tostring(game.JobId),
            periodSeconds=PERIOD_SECONDS,
            note="Axon UI forecast history + passive EggWorld RemoteEvent observation only; no remote invocation."
        },
        stats={
            scans=state.scans,
            refreshClicks=state.refreshClicks,
            observations=#state.observations,
            changes=#state.changes,
            events=#state.events,
            reveals=#state.reveals,
            validations=#state.validations,
            refreshLog=#state.refreshLog,
            panelVisibilityTransitions=#state.panelVisibilityLog,
            hiddenObservations=#state.hiddenObservations,
            history=#history,
        },
        currentPredictions=state.lastCards,
        observations=state.observations,
        changes=state.changes,
        predictionHistory=history,
        events=state.events,
        reveals=state.reveals,
        validations=state.validations,
        refreshLog=state.refreshLog,
        uiSnapshots=state.uiSnapshots,
        shiftedByPeriod=state.shiftedByPeriod,
        panelVisibilityLog=state.panelVisibilityLog,
        lastPanelVisibleAt=state.lastPanelVisibleAt,
        lastPredictorEvidenceAt=state.lastPredictorEvidenceAt,
        hiddenObservations=state.hiddenObservations,
    }
end

local function encodeReport()
    return HttpService:JSONEncode(report())
end

local function checkpoint()
    if not writefile then return false end
    local ok, json = pcall(encodeReport)
    if not ok then return false end
    return pcall(writefile, "Psico_Axon_PredictorTrace_Live.json", json)
end

local function exportData()
    if state.status and state.status.Parent then state.status.Text = "Exportando trace..." end
    local ok, json = pcall(encodeReport)
    if not ok then
        if state.status and state.status.Parent then state.status.Text = "Erro JSON: "..tostring(json) end
        return
    end
    local name = "Psico_Axon_PredictorTrace_"..tostring(math.floor(nowUnix()))..".json"
    local wrote = false
    if writefile then wrote = pcall(writefile, name, json) end
    if not wrote and setclipboard then pcall(setclipboard, json) end
    if state.status and state.status.Parent then
        state.status.Text = (wrote and "EXPORTADO: " or "JSON COPIADO: ")..name.." | "..#json.." bytes"
    end
end

local function startTrace()
    if state.running then
        if state.status and state.status.Parent then state.status.Text = "Trace já está ativo." end
        return
    end
    state.running = true
    state.startedAt = nowUnix()
    attachExistingRemotes()
    scanPredictor("start")
    attachRefreshButtons()

    task.spawn(function()
        while state.running and not state.closed and state.gui and state.gui.Parent do
            attachRefreshButtons()
            scanPredictor("poll")
            local t = nowUnix()
            if t - state.lastCheckpoint >= 30 then
                state.lastCheckpoint = t
                checkpoint()
            end
            task.wait(2)
        end
    end)
end

local sg = Instance.new("ScreenGui")
sg.Name = "PSICO_AXON_PREDICTOR_TRACE_V2_4"
sg.ResetOnSpawn = false
sg.DisplayOrder = 1405
sg.Parent = CoreGui
state.gui = sg

local frame = Instance.new("Frame")
frame.AnchorPoint = Vector2.new(.5,.5)
frame.Position = UDim2.fromScale(.5,.5)
frame.Size = UDim2.fromOffset(485,300)
frame.BackgroundColor3 = Color3.fromRGB(9,18,34)
frame.BorderSizePixel = 0
frame.Parent = sg
Instance.new("UICorner", frame).CornerRadius = UDim.new(0,14)

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Position = UDim2.fromOffset(14,10)
title.Size = UDim2.new(1,-76,0,28)
title.Text = "AXON PREDICTOR TRACE V2.4 - ZERO-HOOK"
title.Font = Enum.Font.GothamBold
title.TextSize = 13
title.TextColor3 = Color3.fromRGB(238,245,255)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = frame

local minimize = Instance.new("TextButton")
minimize.AnchorPoint = Vector2.new(1,0)
minimize.Position = UDim2.new(1,-14,0,10)
minimize.Size = UDim2.fromOffset(34,28)
minimize.BackgroundColor3 = Color3.fromRGB(23,50,86)
minimize.BorderSizePixel = 0
minimize.Text = "—"
minimize.TextColor3 = Color3.fromRGB(244,248,255)
minimize.Font = Enum.Font.GothamBold
minimize.TextSize = 16
minimize.Parent = frame
Instance.new("UICorner", minimize).CornerRadius = UDim.new(0,8)

local restore = Instance.new("TextButton")
restore.AnchorPoint = Vector2.new(1,0)
restore.Position = UDim2.new(1,-16,0,90)
restore.Size = UDim2.fromOffset(48,48)
restore.BackgroundColor3 = Color3.fromRGB(9,18,34)
restore.BorderSizePixel = 0
restore.Text = "AX"
restore.TextColor3 = Color3.fromRGB(244,248,255)
restore.Font = Enum.Font.GothamBold
restore.TextSize = 12
restore.Visible = false
restore.Parent = sg
Instance.new("UICorner", restore).CornerRadius = UDim.new(1,0)

minimize.MouseButton1Click:Connect(function()
    frame.Visible = false
    restore.Visible = true
end)

restore.MouseButton1Click:Connect(function()
    restore.Visible = false
    frame.Visible = true
end)

local status = Instance.new("TextLabel")
status.Position = UDim2.fromOffset(14,48)
status.Size = UDim2.new(1,-28,0,90)
status.BackgroundColor3 = Color3.fromRGB(15,29,52)
status.BorderSizePixel = 0
status.Text = "Pronto. Abra o Egg Predictor do Axon e pressione INICIAR TRACE."
status.Font = Enum.Font.Code
status.TextSize = 11
status.TextColor3 = Color3.fromRGB(215,229,247)
status.TextWrapped = true
status.Parent = frame
Instance.new("UICorner", status).CornerRadius = UDim.new(0,9)
state.status = status

local function button(text,x,y,w)
    local b = Instance.new("TextButton")
    b.Position = UDim2.fromOffset(x,y)
    b.Size = UDim2.fromOffset(w,38)
    b.BackgroundColor3 = Color3.fromRGB(31,78,132)
    b.BorderSizePixel = 0
    b.Text = text
    b.TextColor3 = Color3.fromRGB(244,248,255)
    b.Font = Enum.Font.GothamBold
    b.TextSize = 11
    b.Parent = frame
    Instance.new("UICorner", b).CornerRadius = UDim.new(0,9)
    return b
end

local bStart = button("INICIAR TRACE",14,154,218)
local bSnap = button("SNAPSHOT AGORA",253,154,218)
local bExport = button("EXPORTAR",14,202,218)
local bClose = button("FECHAR",253,202,218)

bStart.MouseButton1Click:Connect(startTrace)
bSnap.MouseButton1Click:Connect(function()
    scanPredictor("manual-snapshot")
    checkpoint()
end)
bExport.MouseButton1Click:Connect(exportData)
bClose.MouseButton1Click:Connect(function()
    checkpoint()
    state.running = false
    state.closed = true
    for _, conn in ipairs(state.remoteConnections) do
        pcall(function() conn:Disconnect() end)
    end
    sg:Destroy()
end)

ReplicatedStorage.DescendantAdded:Connect(function(x)
    if not state.closed then attachRemote(x) end
end)

local dragging = false
local dragStart, startPos
frame.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = i.Position
        startPos = frame.Position
    end
end)
frame.InputChanged:Connect(function(i)
    if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
        local d = i.Position - dragStart
        frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
    end
end)
UserInputService.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
        dragging = false
    end
end)

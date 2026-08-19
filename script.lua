--[[
    ONECLICK GAG2 - REBUILD 2026-08-19
    External config only: getgenv().Config

    Design goals:
      * Core farming is driven by the game's SharedModules.Networking API.
      * Garden.CollectFruit follows the public open-source GAG2 implementation.
      * Other actions are enabled only when the corresponding packet/path is
        actually present at runtime; no fake counter-only "success".
      * Shop loops read live ReplicatedStorage.StockValues before purchasing.
      * Tool-based actions (watering/sprinklers/egg/pack/crate) use real Tool:Activate().
      * UI/prompt fallbacks only act on visible/real in-game prompts or buttons.
      * Every subsystem exposes a capability/status line so a patch cannot silently no-op.

    This source intentionally does NOT define a user configuration table.
]]

repeat task.wait() until game:IsLoaded()

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local TeleportService = game:GetService("TeleportService")
local VirtualUser = game:GetService("VirtualUser")
local VirtualInputManager = game:GetService("VirtualInputManager")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local CoreGui = game:GetService("CoreGui")
local HttpService = game:GetService("HttpService")
local StatsService = game:GetService("Stats")

local LP = Players.LocalPlayer
repeat task.wait() until LP
repeat task.wait() until LP.Character or LP.CharacterAdded:Wait()

local ENV = (getgenv and getgenv()) or _G
local Config = ENV.Config

if type(Config) ~= "table" then
    warn("[OneClick GAG2] getgenv().Config is missing. Put config above loader.")
    return
end

-- Kill an older copy cleanly.
if ENV.__ONECLICK_GAG2_REBUILD and type(ENV.__ONECLICK_GAG2_REBUILD.Stop) == "function" then
    pcall(ENV.__ONECLICK_GAG2_REBUILD.Stop)
end

local Controller = {}
ENV.__ONECLICK_GAG2_REBUILD = Controller
local Alive = true
local BUILD = "V4-SELLGUARD-2026-08-19-R1"
ENV.__ONECLICK_GAG2_BUILD = BUILD

--==============================================================
-- CONFIG HELPERS
--==============================================================
local function C(...)
    local cur = Config
    for i = 1, select("#", ...) do
        if type(cur) ~= "table" then return nil end
        cur = rawget(cur, select(i, ...))
    end
    return cur
end

local function enabled(...)
    return C(...) == true
end

local function num(default, ...)
    local v = tonumber(C(...))
    if v == nil then return default end
    return v
end

local function str(default, ...)
    local v = C(...)
    if type(v) == "string" then return v end
    return default
end

local function norm(s)
    s = tostring(s or ""):lower()
    s = s:gsub("’", "'")
    s = s:gsub("[^%w]", "")
    return s
end

local function tableAllows(tbl, name, default)
    if type(tbl) ~= "table" then return default == true end
    if tbl[name] ~= nil then return tbl[name] == true end
    local n = norm(name)
    for k, v in pairs(tbl) do
        if type(k) == "string" and type(v) == "boolean" and norm(k) == n then
            return v
        end
    end
    return default == true
end

local function inList(tbl, name)
    if type(tbl) ~= "table" then return false end
    local n = norm(name)
    for k, v in pairs(tbl) do
        if type(k) == "number" and norm(v) == n then return true end
        if type(k) == "string" and norm(k) == n and (v == true or type(v) == "number" or type(v) == "string" or type(v) == "table") then
            return true
        end
    end
    return false
end

local function firstNonNil(...)
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if v ~= nil then return v end
    end
end

--==============================================================
-- STATE / STATUS
--==============================================================
local State = {
    Started = os.clock(),
    LastAction = "Booting",
    LastError = "",
    Harvested = 0,
    Planted = 0,
    Sold = 0,
    SeedsBought = 0,
    GearsBought = 0,
    CratesBought = 0,
    PetsTamed = 0,
    ToolsUsed = 0,
    EventSeeds = 0,
    Expands = 0,
    MailClaims = 0,
    CardClaims = 0,
    NetworkReady = false,
    PlotReady = false,
    Capabilities = {},
    PacketPaths = {},
    Verified = {},
    Signatures = {},
    Attempts = {},
    NextSignature = {},
    ConsecutiveFail = {},
    LastAttempt = {},
    LastSuccess = {},
    LastFailure = {},
    PacketMethods = {},
    Earned = 0,
    Unsupported = {
        MAIL_SEND = true,
        AUCTION = true,
        ECLIPSE_MERGE = true,
    },
    EventStatus = {
        Baker = false,
        HarvestMoon = false,
        Werewolf = false,
    },
    BootstrapStatus = "CHECKING",
    LastSell = 0,
    LastWebhook = 0,
    SellUrgent = false,
    SellReason = "",
    SellFailures = 0,
    LastFullSignal = 0,
}

local function log(msg)
    State.LastAction = tostring(msg)
    if enabled("Debug", "Console") then
        print("[OneClick GAG2]", msg)
    end
end

local function errlog(where, e)
    State.LastError = tostring(where) .. ": " .. tostring(e)
    warn("[OneClick GAG2] " .. State.LastError)
end

local WebhookQueue = {}
local function queueWebhook(kind, data)
    WebhookQueue[#WebhookQueue+1] = {Kind=kind, Data=data or {}, At=os.clock()}
end

--==============================================================
-- NETWORKING: STRICT RUNTIME CAPABILITY RESOLUTION
--==============================================================
local Networking
do
    local mod
    local shared = RS:FindFirstChild("SharedModules") or RS:WaitForChild("SharedModules", 30)
    if shared then mod = shared:FindFirstChild("Networking") or shared:WaitForChild("Networking", 15) end
    if not mod then
        for _, d in ipairs(RS:GetDescendants()) do
            if d:IsA("ModuleScript") and d.Name == "Networking" then
                mod = d
                break
            end
        end
    end

    if mod then
        local ok, res = pcall(require, mod)
        if ok and type(res) == "table" then
            Networking = res
            State.NetworkReady = true
        else
            errlog("require Networking", res)
        end
    else
        errlog("Networking", "ModuleScript not found")
    end
end

local function getPath(root, path)
    local cur = root
    for token in tostring(path):gmatch("[^%.]+") do
        if type(cur) ~= "table" then return nil end
        cur = rawget(cur, token)
        if cur == nil then return nil end
    end
    return cur
end

local function packet(path)
    if type(Networking) ~= "table" then return nil end
    local p = getPath(Networking, path)
    if type(p) == "table" and (type(p.Fire) == "function" or type(p.Invoke) == "function") then
        return p
    end
    return nil
end

local function packetMethod(p, preferInvoke)
    if type(p) ~= "table" then return nil end
    if preferInvoke and type(p.Invoke) == "function" then return "Invoke" end
    if type(p.Fire) == "function" then return "Fire" end
    if type(p.Invoke) == "function" then return "Invoke" end
    return nil
end

local function resolve(capName, paths, preferInvoke)
    for _, pth in ipairs(paths) do
        local p = packet(pth)
        if p then
            State.Capabilities[capName] = true
            State.PacketPaths[capName] = pth
            State.PacketMethods[capName] = packetMethod(p, preferInvoke)
            return p
        end
    end
    State.Capabilities[capName] = false
    State.PacketPaths[capName] = "MISSING"
    State.PacketMethods[capName] = "MISSING"
    return nil
end

local function callPacket(p, preferInvoke, ...)
    local method = packetMethod(p, preferInvoke)
    if not method then return false, nil end
    local args = table.pack(...)
    local ok, res = pcall(function()
        return p[method](p, table.unpack(args, 1, args.n))
    end)
    if not ok then return false, res end
    return true, res
end

local function fire(p, ...)
    return callPacket(p, false, ...)
end

local function query(p, ...)
    return callPacket(p, true, ...)
end

local function waitUntil(predicate, timeout, step)
    local deadline = os.clock() + (timeout or 0.8)
    step = step or 0.05
    repeat
        local ok, result = pcall(predicate)
        if ok and result then return true end
        task.wait(step)
    until os.clock() >= deadline or not Alive
    local ok, result = pcall(predicate)
    return ok and result == true
end

-- Safer adaptive call:
-- * a previously verified signature is reused;
-- * otherwise only ONE candidate signature is tested per loop.
-- This avoids one failed verification causing 5-6 duplicate purchases/plants.
local function adaptiveFire(capName, pkt, variants, verify, verifyTimeout)
    if not pkt or type(variants) ~= "table" or #variants == 0 then
        return false
    end

    State.Attempts[capName] = (State.Attempts[capName] or 0) + 1
    State.LastAttempt[capName] = os.clock()

    local remembered = tonumber(State.Signatures[capName])
    local i
    if remembered and variants[remembered] then
        i = remembered
    else
        local nextI = tonumber(State.NextSignature[capName]) or 1
        if nextI < 1 or nextI > #variants then nextI = 1 end
        i = nextI
        State.NextSignature[capName] = (i % #variants) + 1
    end

    local args = variants[i]
    if type(args) == "function" then
        local okBuild, built = pcall(args)
        if okBuild then args = built else args = nil end
    end
    if type(args) ~= "table" then
        State.LastFailure[capName] = os.clock()
        return false
    end

    local ok = fire(pkt, table.unpack(args, 1, args.n or #args))
    if ok and waitUntil(verify, verifyTimeout or 1.2, 0.06) then
        State.Signatures[capName] = i
        State.Verified[capName] = true
        State.ConsecutiveFail[capName] = 0
        State.LastSuccess[capName] = os.clock()
        return true
    end

    State.ConsecutiveFail[capName] = (State.ConsecutiveFail[capName] or 0) + 1
    State.LastFailure[capName] = os.clock()

    -- If a signature used to work and then fails repeatedly after a game patch,
    -- release it so discovery can rotate again. Do not clear VERIFIED after a
    -- single no-op/lag spike.
    if remembered and State.ConsecutiveFail[capName] >= 3 then
        State.Signatures[capName] = nil
        State.Verified[capName] = false
        State.NextSignature[capName] = 1
    end
    return false
end

-- Verified from public open-source GAG2 harvest.
local P_CollectFruit = resolve("HARVEST", {
    "Garden.CollectFruit",
})

-- Runtime-resolved exact names used by current public GAG2 automation.
local P_PlantSeed = resolve("PLANT", {
    "Plant.PlantSeed",
    "Garden.PlantSeed",
})
local P_PreviewSellAll = resolve("SELL_PREVIEW", {
    "NPCS.PreviewSellAll",
    "NPCs.PreviewSellAll",
    "Sell.PreviewSellAll",
}, true)
local P_SellAll = resolve("SELL", {
    "NPCS.SellAll",
    "NPCs.SellAll",
    "Sell.SellAll",
})
local P_PurchaseSeed = resolve("BUY_SEED", {
    "SeedShop.PurchaseSeed",
    "Shop.PurchaseSeed",
})
local P_PurchaseGear = resolve("BUY_GEAR", {
    "GearShop.PurchaseGear",
    "Shop.PurchaseGear",
})
local P_PurchaseCrate = resolve("BUY_CRATE", {
    "CrateShop.PurchaseCrate",
    "PropShop.PurchaseCrate",
    "PropsShop.PurchaseCrate",
})
local P_WildPetTame = resolve("TAME_PET", {
    "Pets.WildPetTame",
    "Pets.TameWildPet",
})
local P_GetEquippedPets = resolve("GET_EQUIPPED_PETS", {
    "Pets.GetEquippedPets",
}, true)
local P_GetPets = resolve("GET_PETS", {
    "Pets.GetPets",
    "Pets.GetOwnedPets",
    "Pets.GetInventoryPets",
}, true)
local P_EquipPet = resolve("EQUIP_PET", {
    "Pets.EquipPet",
    "Pets.Equip",
})
local P_UnequipPet = resolve("UNEQUIP_PET", {
    "Pets.UnequipPet",
    "Pets.Unequip",
})
local P_SellPet = resolve("SELL_PET", {
    "Pets.SellPet",
    "Pets.Sell",
})
local P_BuyPetSlot = resolve("BUY_PET_SLOT", {
    "Pets.BuyPetSlot",
    "Pets.PurchasePetSlot",
    "PetShop.BuyPetSlot",
})
local P_ClaimMailbox = resolve("MAILBOX", {
    "Mailbox.ClaimAll",
    "Mail.ClaimAll",
    "Mailbox.ClaimAllMail",
})
local P_ClaimGifts = resolve("GIFTS", {
    "Gifts.ClaimAll",
    "Mailbox.ClaimAllGifts",
})
local P_RedeemCode = resolve("CODES", {
    "Codes.RedeemCode",
    "Code.RedeemCode",
})
local P_StealBegin = resolve("STEAL_BEGIN", {
    "Steal.BeginSteal",
})
local P_StealComplete = resolve("STEAL_COMPLETE", {
    "Steal.CompleteSteal",
})
local P_ShoveSwing = resolve("SHOVEL_SWING", {
    "Shovel.SwingShovel",
})
local P_ShoveHit = resolve("SHOVEL_HIT", {
    "Shovel.HitPlayer",
})

-- Optional debug dump: this does not fire anything.
local function dumpPacketPaths()
    if not enabled("Debug", "Dump Network Paths") or type(Networking) ~= "table" then return end
    local seen = {}
    local rows = {}
    local function walk(t, path, depth)
        if type(t) ~= "table" or seen[t] or depth > 7 then return end
        seen[t] = true
        if type(rawget(t, "Fire")) == "function" or type(rawget(t, "Invoke")) == "function" then
            local methods = {}
            if type(rawget(t, "Fire")) == "function" then methods[#methods+1] = "Fire" end
            if type(rawget(t, "Invoke")) == "function" then methods[#methods+1] = "Invoke" end
            rows[#rows+1] = path .. " [" .. table.concat(methods, "/") .. "]"
            return
        end
        for k, v in pairs(t) do
            if type(k) == "string" and type(v) == "table" then
                walk(v, path == "" and k or (path .. "." .. k), depth + 1)
            end
        end
    end
    pcall(walk, Networking, "", 0)
    table.sort(rows)
    print("[OneClick GAG2] ===== NETWORK PACKETS =====")
    for _, pth in ipairs(rows) do print(pth) end
end
dumpPacketPaths()

--==============================================================
-- CHARACTER / MOVEMENT
--==============================================================
local function char()
    return LP.Character
end
local function hum()
    local c = char()
    return c and c:FindFirstChildOfClass("Humanoid")
end
local function hrp()
    local c = char()
    return c and c:FindFirstChild("HumanoidRootPart")
end
local function backpack()
    return LP:FindFirstChildOfClass("Backpack")
end

local MoveLock = {owner=nil, since=0}
local function acquire(owner, timeout)
    timeout = timeout or 3
    local started = os.clock()
    while Alive do
        if not MoveLock.owner or MoveLock.owner == owner or os.clock() - MoveLock.since > 20 then
            MoveLock.owner = owner
            MoveLock.since = os.clock()
            return true
        end
        if os.clock() - started > timeout then return false end
        task.wait(0.05)
    end
    return false
end
local function release(owner)
    if MoveLock.owner == owner then
        MoveLock.owner = nil
        MoveLock.since = 0
    end
end

local function moveToCF(cf, owner)
    local root = hrp()
    if not root or not cf then return false end
    local method = str("Tween", "General", "Movement Method")
    local speed = math.max(40, num(180, "General", "Tween Speed"))
    if method == "Teleport" then
        root.CFrame = cf
        return true
    end
    local dist = (root.Position - cf.Position).Magnitude
    if dist < 3 then
        root.CFrame = cf
        return true
    end
    local tw = TweenService:Create(root, TweenInfo.new(dist/speed, Enum.EasingStyle.Linear), {CFrame=cf})
    tw:Play()
    local t0 = os.clock()
    while Alive and tw.PlaybackState == Enum.PlaybackState.Playing and os.clock()-t0 < math.max(3, dist/speed+3) do
        task.wait(0.05)
    end
    pcall(function() tw:Cancel() end)
    return true
end

--==============================================================
-- PLOT / INVENTORY
--==============================================================
local CachedPlot
local function ownerMatches(inst)
    if not inst then return false end
    local uid = firstNonNil(inst:GetAttribute("OwnerUserId"), inst:GetAttribute("UserId"))
    if tonumber(uid) == LP.UserId then return true end
    local owner = inst:GetAttribute("Owner")
    if owner then
        local x = tostring(owner):lower()
        if x == LP.Name:lower() or x == LP.DisplayName:lower() or x:find(LP.Name:lower(), 1, true) then
            return true
        end
    end
    return false
end

local function getPlot()
    if CachedPlot and CachedPlot.Parent then return CachedPlot end

    local gardenRoots={}
    local seenRoots={}
    local function addRoot(x)
        if x and not seenRoots[x] then
            seenRoots[x]=true
            gardenRoots[#gardenRoots+1]=x
        end
    end

    addRoot(workspace:FindFirstChild("Gardens"))
    addRoot(workspace:FindFirstChild("FallGardens"))
    addRoot(workspace:FindFirstChild("GardenPlots"))
    addRoot(workspace:FindFirstChild("Plots"))

    -- Current worlds/events sometimes nest the plot container under Map/World.
    for _, d in ipairs(workspace:GetDescendants()) do
        if d:IsA("Folder") or d:IsA("Model") then
            local n=norm(d.Name)
            if n=="gardens" or n=="fallgardens" or n=="gardenplots" then
                addRoot(d)
            end
        end
        if #gardenRoots>=8 then break end
    end

    local plotId = LP:GetAttribute("PlotId")
    for _, gardens in ipairs(gardenRoots) do
        if plotId ~= nil then
            local p = gardens:FindFirstChild("Plot" .. tostring(plotId))
                or gardens:FindFirstChild(tostring(plotId))
            if p then
                CachedPlot=p
                State.PlotReady=true
                return p
            end
        end
        for _, p in ipairs(gardens:GetChildren()) do
            if ownerMatches(p) then
                CachedPlot=p
                State.PlotReady=true
                return p
            end
            if plotId~=nil then
                local pid=firstNonNil(p:GetAttribute("PlotId"),p:GetAttribute("GardenId"),p:GetAttribute("Id"))
                if pid~=nil and tostring(pid)==tostring(plotId) then
                    CachedPlot=p
                    State.PlotReady=true
                    return p
                end
            end
        end
    end

    for _, area in ipairs(CollectionService:GetTagged("PlantArea")) do
        local m = area:FindFirstAncestorWhichIsA("Model")
        local cur = m
        while cur and cur ~= workspace do
            if ownerMatches(cur) then CachedPlot = cur; State.PlotReady = true; return cur end
            if plotId~=nil then
                local pid=firstNonNil(cur:GetAttribute("PlotId"),cur:GetAttribute("GardenId"),cur:GetAttribute("Id"))
                if pid~=nil and tostring(pid)==tostring(plotId) then
                    CachedPlot=cur
                    State.PlotReady=true
                    return cur
                end
            end
            cur = cur.Parent
        end
    end
    State.PlotReady = false
    return nil
end

local function getPlantsFolder()
    local p = getPlot()
    return p and p:FindFirstChild("Plants")
end

local function plantSeedName(m)
    return firstNonNil(
        m:GetAttribute("CorePartName"),
        m:GetAttribute("SeedName"),
        m:GetAttribute("Fruit"),
        m:GetAttribute("PlantName"),
        m.Name:match("^%d+_(.+)$")
    )
end

local function plantId(m)
    local v = firstNonNil(m:GetAttribute("PlantId"), m.Name:match("^(%d+)_"))
    if type(v) == "string" then return tonumber(v) or v end
    return v
end

local function fruitId(m)
    return firstNonNil(m:GetAttribute("FruitId"), m.Name:match("^%d+_%d+_(.+)$"), "")
end

local function readWeight(inst)
    for _, k in ipairs({"Weight","Kg","KG","WeightKG","WeightKg","Mass"}) do
        local v = tonumber(inst:GetAttribute(k))
        if v then return v end
    end
    for _, d in ipairs(inst:GetDescendants()) do
        if d:IsA("NumberValue") and (norm(d.Name) == "weight" or norm(d.Name) == "kg") then
            return tonumber(d.Value) or 0
        end
    end
    return 0
end

local function readMutation(inst)
    for _, k in ipairs({"Mutation","MutationName","Variant"}) do
        local v = inst:GetAttribute(k)
        if type(v) == "string" and v ~= "" then return v end
    end
    local muts = inst:FindFirstChild("Mutations")
    if muts then
        local names = {}
        for _, d in ipairs(muts:GetChildren()) do
            names[#names+1] = d.Name
        end
        return table.concat(names, ",")
    end
    return ""
end

local function scanTools()
    local out = {}
    local function scan(c)
        if not c then return end
        for _, t in ipairs(c:GetChildren()) do
            if t:IsA("Tool") then out[#out+1] = t end
        end
    end
    scan(backpack())
    scan(char())
    return out
end

local function toolName(t)
    return tostring(firstNonNil(t:GetAttribute("SeedTool"), t:GetAttribute("GearName"), t:GetAttribute("ItemName"), t.Name))
end

local function countTool(name)
    local target = norm(name)
    local n = 0
    for _, t in ipairs(scanTools()) do
        if norm(toolName(t)) == target or norm(t.Name) == target or norm(t.Name:gsub("%s+[Ss]eed$","")) == target then
            n += tonumber(t:GetAttribute("Count")) or tonumber(t:GetAttribute("Amount")) or 1
        end
    end
    return n
end

local function findTool(name)
    local target = norm(name)
    for _, t in ipairs(scanTools()) do
        if norm(toolName(t)) == target or norm(t.Name) == target or norm(t.Name:gsub("%s+[Ss]eed$","")) == target then
            return t
        end
    end
end

local function countInventoryItem(name)
    local target = norm(name)
    local total = countTool(name)

    -- Some builds mirror stack counts in Data/Inventory instead of creating
    -- one Tool per item. Only count explicit name/ItemName matches.
    local data = LP:FindFirstChild("Data")
    if data then
        for _, d in ipairs(data:GetDescendants()) do
            if d:IsA("ValueBase") and tonumber(d.Value) then
                local itemName = firstNonNil(d:GetAttribute("ItemName"), d:GetAttribute("SeedName"), d.Name)
                if norm(itemName) == target then
                    total = math.max(total, tonumber(d.Value) or 0)
                end
            end
        end
    end
    return total
end

local function fruitToolInfo(t)
    if not t or not t:IsA("Tool") then return false, nil end
    if t:GetAttribute("SeedTool") ~= nil then return false, nil end
    if t:GetAttribute("GearName") ~= nil then return false, nil end

    local itemType = tostring(firstNonNil(t:GetAttribute("ItemType"), t:GetAttribute("Type"), ""))
    if itemType ~= "" then
        local nt = norm(itemType)
        if nt:find("seed",1,true) or nt:find("gear",1,true) or nt:find("egg",1,true) or nt:find("crate",1,true) then
            return false, nil
        end
        if nt:find("fruit",1,true) or nt:find("plant",1,true) or nt:find("crop",1,true) then
            return true, tonumber(t:GetAttribute("Count") or t:GetAttribute("Amount")) or 1
        end
    end

    if t:GetAttribute("FruitName") ~= nil
        or t:GetAttribute("FruitId") ~= nil
        or t:GetAttribute("Weight") ~= nil
        or t:GetAttribute("Kg") ~= nil
        or t:GetAttribute("KG") ~= nil then
        return true, tonumber(t:GetAttribute("Count") or t:GetAttribute("Amount")) or 1
    end

    -- Harvested fruit tools commonly include a weight in their display name.
    local n = tostring(t.Name)
    if n:lower():find("kg",1,true) then
        return true, tonumber(t:GetAttribute("Count") or t:GetAttribute("Amount")) or 1
    end
    return false, nil
end

local function countFruitInventory()
    local n = 0
    for _, t in ipairs(scanTools()) do
        local isFruit, amount = fruitToolInfo(t)
        if isFruit then n += amount or 1 end
    end
    for _, key in ipairs({"FruitCount","Fruits","BackpackFruitCount"}) do
        local a = LP:GetAttribute(key)
        if type(a) == "number" then n = math.max(n, a) end
    end
    return n
end

local FruitCapacityCache = {At=0, Value=nil}

local function getFruitCapacity()
    if os.clock() - FruitCapacityCache.At < 0.75 then
        return FruitCapacityCache.Value
    end
    FruitCapacityCache.At = os.clock()

    local best = nil
    local function consider(v)
        v = tonumber(v)
        if v and v > 0 and v < 100000 then
            if not best or v > best then best = v end
        end
    end

    -- Attributes used by several GAG2 builds.
    for _, key in ipairs({
        "FruitCapacity","MaxFruit","FruitCap","BackpackCapacity",
        "InventoryCapacity","MaxInventory","MaxBackpack"
    }) do
        consider(LP:GetAttribute(key))
    end

    -- Some builds keep capacity in Data/leaderstats values rather than attributes.
    local function scanValues(root)
        if not root then return end
        for _, d in ipairs(root:GetDescendants()) do
            if d:IsA("ValueBase") and tonumber(d.Value) then
                local n = norm(d.Name)
                if n == "fruitcapacity" or n == "maxfruit" or n == "fruitcap"
                    or n == "backpackcapacity" or n == "inventorycapacity"
                    or n == "maxinventory" or n == "maxbackpack" then
                    consider(d.Value)
                end
            end
        end
    end
    scanValues(LP:FindFirstChild("Data"))
    scanValues(LP:FindFirstChild("leaderstats"))

    -- Last reliable source: parse visible backpack/inventory counters like 83 / 100.
    local pg = LP:FindFirstChildOfClass("PlayerGui")
    if pg then
        for _, d in ipairs(pg:GetDescendants()) do
            if (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Visible then
                local text = tostring(d.Text or "")
                local current, cap = text:match("(%d+)%s*/%s*(%d+)")
                if current and cap then
                    local context = norm(d.Name .. " " .. text)
                    local cur = d.Parent
                    for _ = 1, 5 do
                        if not cur then break end
                        context ..= norm(cur.Name)
                        cur = cur.Parent
                    end
                    if context:find("fruit",1,true)
                        or context:find("backpack",1,true)
                        or context:find("inventory",1,true)
                        or context:find("bag",1,true) then
                        consider(cap)
                    end
                end
            end
        end
    end

    -- Explicit user fallback only. Do NOT reuse "Max Plant Fruit": that is garden size.
    local fallback = tonumber(C("Auto Sell","Fallback Fruit Capacity"))
    if not best and fallback and fallback > 0 then best = fallback end

    FruitCapacityCache.Value = best
    return best
end

local SellGuard = {
    ForceUntil = 0,
    Selling = false,
    Reason = "",
    LastSignal = 0,
    LastFallback = 0,
    RemoteFailStreak = 0,
}

local function sellConfigEnabled()
    local sc = C("Auto Sell")
    return type(sc) == "table" and sc["Enable"] == true
end

local function fullTextDetected(text)
    if not sellConfigEnabled() or C("Auto Sell","Full Text Detect") == false then return false end
    local n = norm(text)
    if n == "" or not n:find("full",1,true) then return false end
    return n:find("inventory",1,true)
        or n:find("backpack",1,true)
        or n:find("bag",1,true)
        or n:find("storage",1,true)
        or n:find("fruit",1,true)
        or n:find("capacity",1,true)
end

local function signalInventoryFull(reason)
    if not sellConfigEnabled() or C("Auto Sell","Sell On Full") == false then return end
    local now = os.clock()
    SellGuard.ForceUntil = math.max(SellGuard.ForceUntil, now + 15)
    SellGuard.Reason = tostring(reason or "inventory full")
    State.SellUrgent = true
    State.SellReason = SellGuard.Reason
    State.LastFullSignal = now

    -- Avoid spamming console/UI while the game repeats its "full" notification.
    if now - SellGuard.LastSignal > 1.5 then
        SellGuard.LastSignal = now
        log("Inventory full -> emergency sell")
    end
end

local function clearSellGuard()
    SellGuard.ForceUntil = 0
    SellGuard.Selling = false
    SellGuard.Reason = ""
    SellGuard.RemoteFailStreak = 0
    State.SellUrgent = false
    State.SellReason = ""
    State.SellFailures = 0
end

local function sellInventoryNumbers()
    local preview = nil
    -- sellPreview is declared later; this helper only uses locally detectable state.
    local count = countFruitInventory()
    local cap = getFruitCapacity()
    return count, cap, preview
end

local function isSellUrgent()
    if not sellConfigEnabled() then return false end
    local now = os.clock()
    if now < SellGuard.ForceUntil then return true end

    local count, cap = sellInventoryNumbers()
    if cap and cap > 0 then
        local emergencyPct = tonumber(C("Auto Sell","Emergency Percent")) or 92
        if count >= math.max(1, math.floor(cap * emergencyPct / 100)) then
            signalInventoryFull("capacity " .. tostring(count) .. "/" .. tostring(cap))
            return true
        end
    end
    return false
end

local function pauseHarvestForSell()
    if C("Auto Sell","Pause Harvest When Full") == false then return false end
    return SellGuard.Selling or isSellUrgent()
end

-- Listen to the game's real "inventory/backpack full" notification.
local FullTextConnections = {}
local function watchFullTextObject(obj)
    if not obj or not (obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox")) then return end
    local function check()
        if fullTextDetected(obj.Text) then
            signalInventoryFull("game full notification")
        end
    end
    check()
    FullTextConnections[#FullTextConnections+1] = obj:GetPropertyChangedSignal("Text"):Connect(check)
end

task.spawn(function()
    local pg = LP:WaitForChild("PlayerGui", 15)
    if not pg then return end
    for _, d in ipairs(pg:GetDescendants()) do
        watchFullTextObject(d)
    end
    FullTextConnections[#FullTextConnections+1] = pg.DescendantAdded:Connect(function(d)
        watchFullTextObject(d)
    end)
end)

-- Capacity monitor catches full state even if the notification UI was suppressed.
task.spawn(function()
    while Alive do
        if sellConfigEnabled() then
            local count, cap = sellInventoryNumbers()
            if cap and count >= cap then
                signalInventoryFull("backpack full " .. tostring(count) .. "/" .. tostring(cap))
            end
        end
        task.wait(0.12)
    end
end)

local PlantScanCache = {At = 0, List = {}, FullScanAt = 0}

local function plantBelongsToMe(model)
    if not model then return false end
    local plot = getPlot()
    if plot and model:IsDescendantOf(plot) then return true end

    local cur = model
    for _ = 1, 8 do
        if not cur or cur == workspace then break end
        if ownerMatches(cur) then return true end
        cur = cur.Parent
    end

    -- Some current GAG2 builds keep plant models outside the plot model.
    -- Match their plot id when it exists.
    local myPlotId = LP:GetAttribute("PlotId")
    if myPlotId ~= nil then
        for _, key in ipairs({"PlotId","GardenId","Plot"}) do
            local v = model:GetAttribute(key)
            if v ~= nil and tostring(v) == tostring(myPlotId) then return true end
        end
    end
    return false
end

local function discoverOwnPlants(force)
    if not force and os.clock() - PlantScanCache.At < 0.75 then
        return PlantScanCache.List
    end

    local out, seen = {}, {}
    local function add(model)
        if not model or not model:IsA("Model") then return end
        local pid = plantId(model)
        if pid == nil then return end

        -- Walk upward while the parent represents the same PlantId so a fruit
        -- model is not counted as a separate plant.
        local canonical = model
        local cur = model.Parent
        for _ = 1, 5 do
            if not cur or not cur:IsA("Model") then break end
            local parentPid = plantId(cur)
            if parentPid ~= nil and tostring(parentPid) == tostring(pid) then
                canonical = cur
                cur = cur.Parent
            else
                break
            end
        end

        local key = tostring(pid)
        if seen[key] then return end
        if plantBelongsToMe(canonical) then
            seen[key] = true
            out[#out+1] = canonical
        end
    end

    local plot = getPlot()
    local f = getPlantsFolder()
    if f then
        for _, p in ipairs(f:GetChildren()) do add(p) end
    elseif plot then
        -- Some builds no longer keep a direct Plants folder.
        for _, d in ipairs(plot:GetDescendants()) do
            if d:IsA("Model") and d:GetAttribute("PlantId") ~= nil then add(d) end
        end
    end

    -- Public GAG2 harvest sources rely on HarvestPrompt-tagged fruit/plant objects.
    for _, prompt in ipairs(CollectionService:GetTagged("HarvestPrompt")) do
        if prompt and prompt.Parent and prompt:IsDescendantOf(workspace) then
            local cur = prompt.Parent
            for _ = 1, 6 do
                if not cur then break end
                if cur:IsA("Model") and plantId(cur) ~= nil then
                    add(cur)
                    break
                end
                cur = cur.Parent
            end
        end
    end

    -- Last-resort world scan is expensive on mobile, so throttle it heavily.
    if #out == 0 and (force or os.clock() - PlantScanCache.FullScanAt > 5) then
        PlantScanCache.FullScanAt = os.clock()
        for _, d in ipairs(workspace:GetDescendants()) do
            if d:IsA("Model") and d:GetAttribute("PlantId") ~= nil then add(d) end
        end
    end

    PlantScanCache.At = os.clock()
    PlantScanCache.List = out
    return out
end

local function countPlantsBySeed()
    local counts = {}
    for _, p in ipairs(discoverOwnPlants()) do
        local n = plantSeedName(p)
        if n then counts[norm(n)] = (counts[norm(n)] or 0) + 1 end
    end
    return counts
end

local function totalPlantCount()
    return #discoverOwnPlants()
end

local function getCurrency()
    local values={}

    local function record(name,value)
        local n=tonumber(value)
        if n==nil then return end
        local key=norm(name)
        if values[key]==nil then values[key]={value=n,name=tostring(name)} end
    end

    local ls=LP:FindFirstChild("leaderstats")
    if ls then
        for _,v in ipairs(ls:GetChildren()) do
            if v:IsA("ValueBase") then
                local n=norm(v.Name)
                if n=="sheckles" or n=="sheckle" or n=="leaves" or n=="leaf"
                    or n=="money" or n=="cash" or n=="coins" then
                    record(v.Name,v.Value)
                end
            end
        end
    end

    for _,name in ipairs({"Sheckles","Sheckle","Leaves","Leaf","Money","Cash","Coins"}) do
        record(name,LP:GetAttribute(name))
    end

    local data=LP:FindFirstChild("Data")
    if data then
        for _,d in ipairs(data:GetDescendants()) do
            if d:IsA("ValueBase") and tonumber(d.Value)~=nil then
                local n=norm(d.Name)
                if n=="sheckles" or n=="sheckle" or n=="leaves" or n=="leaf"
                    or n=="money" or n=="cash" or n=="coins" then
                    record(d.Name,d.Value)
                end
            end
        end
    end

    local worldText=""
    for _,key in ipairs({"World","CurrentWorld","Zone","Map"}) do
        local v=LP:GetAttribute(key)
        if v~=nil then worldText=worldText.." "..tostring(v) end
    end
    local fall=norm(worldText):find("fall",1,true)~=nil

    local order = fall
        and {"leaves","leaf","sheckles","sheckle","money","cash","coins"}
        or {"sheckles","sheckle","money","cash","coins","leaves","leaf"}

    -- Prefer the current world's currency if it is present. If world metadata
    -- is absent/stale and that value is zero, prefer another positive currency.
    local first
    for _,key in ipairs(order) do
        if values[key] then
            if not first then first=values[key] end
            if values[key].value>0 then
                return values[key].value, values[key].name
            end
            if (fall and (key=="leaves" or key=="leaf"))
                or (not fall and (key=="sheckles" or key=="sheckle")) then
                first=values[key]
            end
        end
    end

    if first then return first.value,first.name end
    return 0,"?"
end
--==============================================================
-- HARVEST
--==============================================================
local function harvestAllowed(seed, fruit)
    local hcfg = C("Harvest")
    if type(hcfg) == "table" then
        local filter = hcfg["Fruit"]
        if type(filter) == "table" and next(filter) ~= nil and not tableAllows(filter, seed, false) then
            return false
        end

        local minKg = tonumber(hcfg["Min KG"]) or 0
        if minKg > 0 and readWeight(fruit) < minKg then return false end

        local mutation = readMutation(fruit)
        local skip = hcfg["Skip Mutation"]
        if mutation ~= "" and type(skip) == "table" then
            for k,v in pairs(skip) do
                local name = type(k)=="string" and k or v
                if v == true or type(k)=="number" then
                    if norm(mutation):find(norm(name),1,true) then return false end
                end
            end
        end

        local only = hcfg["Mutation"]
        if type(only) == "table" and next(only) ~= nil then
            local matched = false
            for k,v in pairs(only) do
                local name = type(k)=="string" and k or v
                if v == true or type(k)=="number" then
                    if norm(mutation):find(norm(name),1,true) then matched = true break end
                end
            end
            if not matched then return false end
        end
    end

    local mutatedOnly = C("Collect Plant If Mutated")
    if type(mutatedOnly) == "table" and inList(mutatedOnly, seed) and readMutation(fruit) == "" then
        return false
    end

    local targetKg = C("Wait Plant Reach Target KG")
    if type(targetKg) == "table" then
        for k,v in pairs(targetKg) do
            if norm(k)==norm(seed) and tonumber(v) and readWeight(fruit) < tonumber(v) then
                return false
            end
        end
    end
    return true
end

local HarvestDebounce = {}

local function harvestTargetKey(plant, target)
    return tostring(plantId(plant)) .. "|" .. tostring(fruitId(target)) .. "|" .. tostring(target)
end

local function targetStillCollectable(target)
    if not target or not target.Parent then return false end
    local prompt = target:FindFirstChildWhichIsA("ProximityPrompt", true)
    if prompt and prompt.Name == "HarvestPrompt" then
        return prompt.Enabled ~= false
    end
    -- When fruit instances are replicated directly, disappearance is the
    -- strongest signal. If the instance is still here, keep waiting.
    return true
end

local function buildHarvestTargets(plant)
    local out, seen = {}, {}
    local function add(x)
        if x and not seen[x] then
            seen[x] = true
            out[#out+1] = x
        end
    end

    local fruits = plant:FindFirstChild("Fruits")
    if fruits then
        for _, fruit in ipairs(fruits:GetChildren()) do add(fruit) end
    end

    for _, prompt in ipairs(CollectionService:GetTagged("HarvestPrompt")) do
        if prompt and prompt.Parent and prompt:IsDescendantOf(plant) then
            local cur = prompt.Parent
            local candidate = nil
            for _ = 1, 4 do
                if not cur or cur == plant then break end
                if cur:IsA("Model") and (
                    cur:GetAttribute("FruitId") ~= nil
                    or cur:GetAttribute("CorePartName") ~= nil
                    or cur:GetAttribute("SeedName") ~= nil
                ) then
                    candidate = cur
                    break
                end
                cur = cur.Parent
            end
            add(candidate or prompt.Parent)
        end
    end

    if #out == 0 then add(plant) end
    return out
end

local function harvestOnce()
    if not enabled("Harvest","Enable") or not P_CollectFruit then return end
    if pauseHarvestForSell() then return end
    local delay = math.max(0.02, num(0.08, "Harvest","Delay"))
    local plants = discoverOwnPlants(false)
    if #plants == 0 then
        return
    end

    for _, plant in ipairs(plants) do
        if not Alive or not enabled("Harvest","Enable") or pauseHarvestForSell() then break end
        if not plant.Parent then continue end

        local seed = plantSeedName(plant)
        local pid = plantId(plant)
        if seed and pid ~= nil then
            for _, target in ipairs(buildHarvestTargets(plant)) do
                if pauseHarvestForSell() then break end
                if not Alive or not target or not target.Parent then continue end
                local key = harvestTargetKey(plant, target)
                if HarvestDebounce[key] and os.clock() - HarvestDebounce[key] < 1.0 then continue end
                if not harvestAllowed(seed, target) then continue end

                HarvestDebounce[key] = os.clock()
                local fid = fruitId(target)
                local beforeParent = target.Parent
                local beforePlantCount = totalPlantCount()
                local beforeFruitCount = 0
                local ff = plant:FindFirstChild("Fruits")
                if ff then beforeFruitCount = #ff:GetChildren() end
                local prompt = target:FindFirstChildWhichIsA("ProximityPrompt", true)

                local function verify()
                    if not target.Parent then return true end
                    if prompt and (not prompt.Parent or prompt.Enabled == false) then return true end
                    local nowF = plant.Parent and plant:FindFirstChild("Fruits")
                    if ff and nowF and #nowF:GetChildren() < beforeFruitCount then return true end
                    if plant.Parent == nil and beforePlantCount > totalPlantCount() then return true end
                    return false
                end

                -- Public open-source GAG2 harvest uses exactly:
                -- Garden.CollectFruit:Fire(PlantId, FruitId)
                local variants = {
                    table.pack(pid, fid),
                }

                if adaptiveFire("HARVEST", P_CollectFruit, variants, verify, 1.25) then
                    PlantScanCache.At = 0
                    State.Harvested += 1
                    log("Harvest verified: " .. tostring(seed))
                    task.wait(delay)
                end
            end
        end
    end

    for k,t in pairs(HarvestDebounce) do
        if os.clock()-t > 8 then HarvestDebounce[k]=nil end
    end
end

task.spawn(function()
    while Alive do
        local ok,e = pcall(harvestOnce)
        if not ok then errlog("Harvest",e) end
        task.wait(math.max(0.08, num(0.15,"Harvest","Loop Delay")))
    end
end)

--==============================================================
-- PLANT
--==============================================================
local function seedTools()
    local list = {}
    for _, t in ipairs(scanTools()) do
        local seed = t:GetAttribute("SeedTool")
        if seed or norm(t.Name):find("seed",1,true) then
            seed = tostring(seed or t.Name:gsub("%s+[Ss]eed$",""))
            list[#list+1] = {tool=t, seed=seed}
        end
    end
    return list
end

local function totalSeedInventory()
    local n=0
    for _,item in ipairs(seedTools()) do
        n += tonumber(item.tool:GetAttribute("Count") or item.tool:GetAttribute("Amount")) or 1
    end
    return n
end

local function getPlantAreas(plot)
    local out = {}
    for _, a in ipairs(CollectionService:GetTagged("PlantArea")) do
        if a:IsA("BasePart") and plot and a:IsDescendantOf(plot) then out[#out+1]=a end
    end
    if #out == 0 and plot then
        for _, d in ipairs(plot:GetDescendants()) do
            if d:IsA("BasePart") and (norm(d.Name):find("plantarea",1,true) or d:GetAttribute("PlantArea")==true) then
                out[#out+1]=d
            end
        end
    end
    return out
end

local function occupiedPositions()
    local pts = {}
    for _, p in ipairs(discoverOwnPlants()) do
        local ok,cf = pcall(function() return p:GetPivot() end)
        if ok then pts[#pts+1] = cf.Position end
    end
    return pts
end

local function plantPositions(maxNeeded)
    local plot = getPlot()
    if not plot then return {} end
    local areas = getPlantAreas(plot)
    local out = {}
    local gap = math.max(1.2, num(2.5,"Plant Seed","Gap"))
    local existing = occupiedPositions()

    local function clear(p)
        for _, q in ipairs(existing) do
            local dx,dz=p.X-q.X,p.Z-q.Z
            if dx*dx+dz*dz < (gap*0.8)^2 then return false end
        end
        for _, q in ipairs(out) do
            local dx,dz=p.X-q.X,p.Z-q.Z
            if dx*dx+dz*dz < (gap*0.8)^2 then return false end
        end
        return true
    end

    for _, area in ipairs(areas) do
        local sx,sz=area.Size.X,area.Size.Z
        for x=-sx/2+gap/2, sx/2-gap/2, gap do
            for z=-sz/2+gap/2, sz/2-gap/2, gap do
                local p=(area.CFrame*CFrame.new(x,area.Size.Y/2+0.05,z)).Position
                if clear(p) then
                    out[#out+1]=p
                    if #out>=maxNeeded then return out end
                end
            end
        end
    end
    return out
end

local function plantTargetFor(seed)
    local amounts = C("Plant Seed","Amount")
    if type(amounts)=="table" then
        for k,v in pairs(amounts) do
            if norm(k)==norm(seed) and tonumber(v) then return tonumber(v) end
        end
    end
    return math.huge
end

local function plantOnce()
    if not enabled("Plant Seed","Enable") or not P_PlantSeed then return end
    local maxPlants = num(200, "Max Plant Fruit")
    if totalPlantCount() >= maxPlants then return end

    local allowed = C("Plant Seed","Seed")
    local counts = countPlantsBySeed()
    local tools = seedTools()
    if #tools == 0 then
        return
    end

    local maxSlots = math.max(0, maxPlants-totalPlantCount())
    local positions = plantPositions(math.min(maxSlots, 100))
    if #positions == 0 then
        return
    end

    local idx = 1
    local h = hum()

    for _, item in ipairs(tools) do
        if idx>#positions or not Alive then break end
        local seed=item.seed
        if tableAllows(allowed,seed,false) then
            local current=counts[norm(seed)] or 0
            local target=plantTargetFor(seed)
            local available=tonumber(item.tool:GetAttribute("Count")) or countTool(seed)
            if available <= 0 then available = 1 end
            local need=math.min(available, math.max(0,target-current))
            if target==math.huge then need=available end

            if need>0 then
                if h then pcall(function() h:EquipTool(item.tool) end) end
                for _=1,need do
                    if idx>#positions or totalPlantCount()>=maxPlants or not item.tool.Parent then break end

                    local pos = positions[idx]
                    idx += 1
                    local beforePlants = totalPlantCount()
                    local beforeSeed = countTool(seed)

                    local function verify()
                        PlantScanCache.At = 0
                        if totalPlantCount() > beforePlants then return true end
                        if beforeSeed > 0 and countTool(seed) < beforeSeed then return true end
                        return false
                    end

                    local variants = {
                        table.pack(pos, seed, item.tool),
                        table.pack(seed, pos, item.tool),
                        table.pack(pos, seed),
                        table.pack(seed, pos),
                        table.pack(item.tool, pos),
                        table.pack({Position=pos, Seed=seed, Tool=item.tool}),
                    }

                    if adaptiveFire("PLANT", P_PlantSeed, variants, verify, 1.2) then
                        PlantScanCache.At = 0
                        State.Planted+=1
                        counts[norm(seed)]=(counts[norm(seed)] or 0)+1
                        log("Plant verified: "..seed)
                        task.wait(math.max(0.05,num(0.12,"Plant Seed","Interval")))
                    else
                        log("Plant signature failed: "..seed)
                        -- Do not burn through every inventory item if the call
                        -- shape changed in an update.
                        break
                    end
                end
            end
        end
    end
end

task.spawn(function()
    while Alive do
        local ok,e=pcall(plantOnce)
        if not ok then errlog("Plant",e) end
        task.wait(math.max(0.35,num(0.8,"Plant Seed","Loop Delay")))
    end
end)

--==============================================================
-- SELL
--==============================================================
local SellPreviewCache = {At = 0, Value = nil}

local function sellPreview(force)
    if not P_PreviewSellAll then return nil end
    if not force and os.clock() - SellPreviewCache.At < 0.35 then
        return SellPreviewCache.Value
    end
    SellPreviewCache.At = os.clock()
    local ok,res=query(P_PreviewSellAll)
    if ok and type(res)=="table" then
        SellPreviewCache.Value = res
        return res
    end
    SellPreviewCache.Value = nil
    return nil
end

local function sellSnapshot()
    local cash,currency=getCurrency()
    local preview=sellPreview(true)
    local previewCount=preview and tonumber(firstNonNil(preview.FruitCount,preview.Count,preview.ItemCount))
    local previewValue=preview and tonumber(firstNonNil(preview.Value,preview.Sheckles,preview.Price,preview.TotalValue))
    return {
        cash=cash,
        currency=currency,
        fruit=countFruitInventory(),
        previewCount=previewCount,
        previewValue=previewValue,
    }
end

local function snapshotSold(before)
    SellPreviewCache.At=0
    FruitCapacityCache.At=0
    local after=sellSnapshot()
    if before.currency~="?" and after.currency==before.currency and after.cash>before.cash then return true,after end
    if after.fruit < before.fruit then return true,after end
    if before.previewCount and after.previewCount and after.previewCount < before.previewCount then return true,after end
    return false,after
end

local function currentSellCountAndValue()
    local preview=sellPreview()
    local count=preview and tonumber(firstNonNil(preview.FruitCount,preview.Count,preview.ItemCount)) or countFruitInventory()
    local value=preview and tonumber(firstNonNil(preview.Value,preview.Sheckles,preview.Price,preview.TotalValue)) or nil
    return count,value
end

local function shouldSell()
    local sc=C("Auto Sell")
    if type(sc)~="table" or sc["Enable"]~=true then return false end

    if isSellUrgent() then return true end

    local count,value=currentSellCountAndValue()
    if count <= 0 then return false end

    -- Independent safety threshold. This prevents ever reaching "full" when
    -- the current game build does not expose a backpack-capacity value.
    local safeCount=tonumber(sc["Safe Fruit Count"]) or 0
    if safeCount>0 and count>=safeCount then
        SellGuard.Reason="safe fruit count"
        return true
    end

    local mode=tostring(sc["Mode"] or "InventoryPercent")
    if mode=="Timer" then
        return os.clock()-State.LastSell >= (tonumber(sc["IntervalSec"]) or 60)
    elseif mode=="Value" then
        return value and value >= (tonumber(sc["MinValue"]) or math.huge)
    else
        local cap=getFruitCapacity()
        if cap and cap>0 then
            local pct=tonumber(sc["InventoryPercent"]) or 75
            return count>=math.max(1,math.floor(cap*pct/100))
        end

        -- Unknown capacity: rely on Safe Fruit Count/full notification instead
        -- of incorrectly treating garden Max Plant Fruit as backpack capacity.
        return false
    end
end

local function sellVerifyFrom(before)
    return function()
        local ok = snapshotSold(before)
        return ok
    end
end

local function rawClickButton(btn)
    if not btn or not btn.Parent or not btn.Visible then return false end
    if firesignal then
        local ok=pcall(function() firesignal(btn.Activated) end)
        if ok then return true end
    end
    local pos,size=btn.AbsolutePosition,btn.AbsoluteSize
    if size.X<=0 or size.Y<=0 then return false end
    local x,y=math.floor(pos.X+size.X/2),math.floor(pos.Y+size.Y/2)
    return pcall(function()
        VirtualInputManager:SendMouseButtonEvent(x,y,0,true,game,0)
        task.wait(0.04)
        VirtualInputManager:SendMouseButtonEvent(x,y,0,false,game,0)
    end)
end

local function findSellAllButton()
    local pg=LP:FindFirstChildOfClass("PlayerGui")
    if not pg then return nil end
    local best,bestScore=nil,-1
    for _,d in ipairs(pg:GetDescendants()) do
        if d:IsA("TextButton") and d.Visible then
            local text=norm(d.Text.." "..d.Name)
            local score=0
            if text:find("sellall",1,true) then score+=100 end
            if text=="sell" or text:find("sellfruit",1,true) then score+=50 end

            local cur=d.Parent
            for _=1,5 do
                if not cur then break end
                local n=norm(cur.Name)
                if n:find("sell",1,true) then score+=20 end
                if n:find("steven",1,true) then score+=30 end
                cur=cur.Parent
            end
            if score>bestScore and score>=50 then
                best,bestScore=d,score
            end
        end
    end
    return best
end

local function findSellPrompt()
    local configured=C("Auto Sell","NPC Names")
    local best,bestScore=nil,-1
    for _,d in ipairs(workspace:GetDescendants()) do
        if d:IsA("ProximityPrompt") and d.Enabled then
            local text=norm((d.ActionText or "").." "..(d.ObjectText or "").." "..d.Name.." "..(d.Parent and d.Parent.Name or ""))
            local score=0
            if text:find("sellall",1,true) then score+=100 end
            if text:find("sell",1,true) then score+=45 end
            if text:find("steven",1,true) then score+=50 end

            if type(configured)=="table" then
                for _,name in ipairs(configured) do
                    if type(name)=="string" and name~="" and text:find(norm(name),1,true) then
                        score+=35
                    end
                end
            end

            if score>bestScore and score>=45 then
                best,bestScore=d,score
            end
        end
    end
    return best
end

local function promptCF(prompt)
    if not prompt or not prompt.Parent then return nil end
    local p=prompt.Parent
    if p:IsA("BasePart") then return p.CFrame end
    if p:IsA("Model") then
        local ok,cf=pcall(function() return p:GetPivot() end)
        if ok then return cf end
    end
    local part=p:FindFirstChildWhichIsA("BasePart",true)
    return part and part.CFrame or nil
end

local function rawUseSellPrompt(prompt)
    if not prompt or not prompt.Parent then return false end
    if fireproximityprompt then
        local ok=pcall(fireproximityprompt,prompt)
        if ok then return true end
    end
    return pcall(function()
        prompt:InputHoldBegin()
        task.wait(math.max(0.05,tonumber(prompt.HoldDuration) or 0))
        prompt:InputHoldEnd()
    end)
end

local function npcSellFallback(before)
    if C("Auto Sell","NPC Fallback")==false then return false end
    local cooldown=math.max(0.5,tonumber(C("Auto Sell","Fallback Cooldown")) or 1.25)
    if os.clock()-SellGuard.LastFallback<cooldown then return false end
    SellGuard.LastFallback=os.clock()

    if not acquire("EmergencySell",1.5) then return false end
    local root=hrp()
    local saved=root and root.CFrame
    local verified=false

    local function check()
        local ok=snapshotSold(before)
        return ok
    end

    -- Sometimes the sell dialogue is already open.
    local button=findSellAllButton()
    if button then
        rawClickButton(button)
        verified=waitUntil(check,1.0,0.05)
    end

    local prompt
    if not verified then
        prompt=findSellPrompt()
        if prompt then
            local cf=promptCF(prompt)
            if cf then moveToCF(cf*CFrame.new(0,2.5,2),"EmergencySell") end
            rawUseSellPrompt(prompt)
            task.wait(0.18)

            -- While physically at Steven/Sell NPC, retry the verified remote first.
            if P_SellAll then
                local variants={table.pack(),table.pack("All"),table.pack(true)}
                verified=adaptiveFire("SELL",P_SellAll,variants,check,0.9)
            end

            -- If the NPC opened a dialogue, click its real Sell All button.
            if not verified then
                button=findSellAllButton()
                if button then
                    rawClickButton(button)
                    verified=waitUntil(check,1.1,0.05)
                end
            end

            -- Some sell prompts perform the sale directly.
            if not verified then
                verified=waitUntil(check,0.45,0.05)
            end
        end
    end

    root=hrp()
    if root and saved then
        pcall(function() root.CFrame=saved end)
    end
    release("EmergencySell")
    return verified
end

task.spawn(function()
    while Alive do
        if sellConfigEnabled() then
            local count=currentSellCountAndValue()

            -- If another system already cleared the bag, release emergency state.
            if State.SellUrgent and count<=0 then
                clearSellGuard()
            end

            if shouldSell() then
                SellGuard.Selling=true
                local before=sellSnapshot()
                local didSell=false

                if P_SellAll then
                    local variants={
                        table.pack(),
                        table.pack("All"),
                        table.pack(true),
                    }
                    didSell=adaptiveFire("SELL",P_SellAll,variants,sellVerifyFrom(before),0.95)
                end

                if not didSell then
                    SellGuard.RemoteFailStreak+=1
                    State.SellFailures=SellGuard.RemoteFailStreak
                    didSell=npcSellFallback(before)
                end

                if didSell then
                    task.wait(0.08)
                    local _,after=snapshotSold(before)
                    local gain=0
                    if before.currency~="?" and after.currency==before.currency then
                        gain=math.max(0,after.cash-before.cash)
                    end
                    State.Earned+=gain
                    State.Sold+=1
                    State.LastSell=os.clock()
                    SellPreviewCache.At=0
                    FruitCapacityCache.At=0
                    clearSellGuard()
                    log("Sell verified"..(gain>0 and (" +$"..tostring(math.floor(gain))) or ""))
                else
                    SellGuard.Selling=false

                    local remaining=currentSellCountAndValue()
                    if SellGuard.RemoteFailStreak>=2 and remaining>0 then
                        -- A normal threshold sale that fails twice becomes urgent.
                        -- This stops harvesting BEFORE the backpack can reach hard-full.
                        SellGuard.ForceUntil=math.max(SellGuard.ForceUntil,os.clock()+5)
                        SellGuard.Reason=SellGuard.Reason~="" and SellGuard.Reason or "sell retry guard"
                        State.SellUrgent=true
                        State.SellReason=SellGuard.Reason
                    end

                    if isSellUrgent() then
                        -- Keep harvest paused until a sale succeeds, but do not flood
                        -- the server with attempts: Retry Delay controls the loop.
                        SellGuard.ForceUntil=math.max(SellGuard.ForceUntil,os.clock()+3)
                        if os.clock()-SellGuard.LastSignal>2 then
                            SellGuard.LastSignal=os.clock()
                            log("Backpack full; retrying sell")
                        end
                    end
                end
            else
                SellGuard.Selling=false
            end
        else
            clearSellGuard()
        end

        local urgent=isSellUrgent()
        task.wait(urgent
            and math.max(0.15,tonumber(C("Auto Sell","Retry Delay")) or 0.25)
            or 0.45)
    end
end)

--==============================================================
-- LIVE STOCK + SHOP BUYING
--==============================================================
local function stockRoot()
    return RS:FindFirstChild("StockValues") or RS:FindFirstChild("StockValues",true)
end

local function shopFolder(names)
    local root=stockRoot()
    if not root then return nil end
    for _,n in ipairs(names) do
        local f=root:FindFirstChild(n)
        if f then return f:FindFirstChild("Items") or f end
    end
    for _, d in ipairs(root:GetDescendants()) do
        for _, n in ipairs(names) do
            if norm(d.Name) == norm(n) then
                return d:FindFirstChild("Items") or d
            end
        end
    end
    return nil
end

local function stockEntries(folder)
    local out={}
    if not folder then return out end
    for _,v in ipairs(folder:GetChildren()) do
        local amount
        if v:IsA("ValueBase") then amount=tonumber(v.Value)
        else amount=tonumber(v:GetAttribute("Stock") or v:GetAttribute("Amount")) end
        if amount and amount>0 then out[#out+1]={name=v.Name,amount=amount,obj=v} end
    end
    return out
end

local function configItemLimit(section,item)
    local limits=C(section,"Max Owned")
    if type(limits)=="table" then
        for k,v in pairs(limits) do
            if norm(k)==norm(item) and tonumber(v) then return tonumber(v) end
        end
    end
    return math.huge
end

local function readStockAmount(obj)
    if not obj or not obj.Parent then return nil end
    if obj:IsA("ValueBase") then return tonumber(obj.Value) end
    return tonumber(obj:GetAttribute("Stock") or obj:GetAttribute("Amount"))
end

local function sortedSelected(section, entries, itemKey)
    local allow=C(section,itemKey)
    local pri=C(section,"Priority")
    local out={}
    for _,e in ipairs(entries) do
        if tableAllows(allow,e.name,false) then out[#out+1]=e end
    end
    table.sort(out,function(a,b)
        local pa,pb=999999,999999
        if type(pri)=="table" then
            for k,v in pairs(pri) do
                if norm(k)==norm(a.name) then pa=tonumber(v) or pa end
                if norm(k)==norm(b.name) then pb=tonumber(v) or pb end
            end
        end
        return pa<pb
    end)
    return out
end

local function buyShop(section,itemKey,folders,pkt,counterKey)
    if not enabled(section,"Enable") or not pkt then return end

    local money,currencyName=getCurrency()
    local reserve=num(0,section,"Reserve")
    if currencyName ~= "?" and money<=reserve then return end

    local folder = shopFolder(folders)
    local entries=sortedSelected(section,stockEntries(folder),itemKey)
    if #entries == 0 then return end

    local maxCycle=math.max(1,num(10,section,"Max Per Cycle"))
    local bought=0

    for _,e in ipairs(entries) do
        if bought>=maxCycle then break end
        local owned=countInventoryItem(e.name)
        local lim=configItemLimit(section,e.name)
        local n=math.min(e.amount, maxCycle-bought, math.max(0,lim-owned))

        for _=1,n do
            local nowMoney,nowCurrency=getCurrency()
            if nowCurrency ~= "?" and nowMoney<=reserve then break end

            local beforeOwned=countInventoryItem(e.name)
            local beforeMoney=nowMoney
            local beforeStock=readStockAmount(e.obj)

            local function verify()
                local afterOwned=countInventoryItem(e.name)
                if afterOwned>beforeOwned then return true end

                -- If this executor/game build does not mirror the item into
                -- Backpack/Data immediately, require BOTH money and live stock
                -- to decrease. Money-only verification produced false positives
                -- when another shop loop spent currency at the same time.
                local afterMoney,afterCurrency=getCurrency()
                local afterStock=readStockAmount(e.obj)
                if beforeStock and afterStock
                    and nowCurrency ~= "?" and afterCurrency == nowCurrency
                    and afterMoney < beforeMoney and afterStock < beforeStock then
                    return true
                end
                return false
            end

            local capName = section=="Buy Seed" and "BUY_SEED"
                or section=="Buy Gear" and "BUY_GEAR"
                or section=="Crate" and "BUY_CRATE"
                or section

            local variants = {
                table.pack(e.name),
                table.pack(e.name, 1),
                table.pack(e.obj),
                table.pack({Name=e.name, Amount=1}),
                table.pack({Item=e.name, Amount=1}),
            }

            if adaptiveFire(capName,pkt,variants,verify,1.0) then
                State[counterKey]+=1
                bought+=1
                log(section.." verified: "..e.name)
                task.wait(math.max(0.08,num(0.15,section,"Interval")))
            else
                -- Stop on this item; don't spam a stale signature.
                break
            end
        end
    end
end

task.spawn(function()
    while Alive do
        local ok,e=pcall(buyShop,"Buy Seed","Seed",{"SeedShop","Seeds"},P_PurchaseSeed,"SeedsBought")
        if not ok then errlog("Buy Seed",e) end
        task.wait(math.max(0.8,num(2,"Buy Seed","Loop Delay")))
    end
end)

task.spawn(function()
    while Alive do
        local ok,e=pcall(buyShop,"Buy Gear","Gear",{"GearShop","Gears"},P_PurchaseGear,"GearsBought")
        if not ok then errlog("Buy Gear",e) end
        task.wait(math.max(1,num(2.5,"Buy Gear","Loop Delay")))
    end
end)

task.spawn(function()
    while Alive do
        local ok,e=pcall(buyShop,"Crate","Crate",{"CrateShop","PropShop","PropsShop","Props"},P_PurchaseCrate,"CratesBought")
        if not ok then errlog("Buy Crate",e) end
        task.wait(math.max(1,num(3,"Crate","Loop Delay")))
    end
end)

--==============================================================
-- TOOL USE: WATER / SPRINKLER / EGGS / PACKS / CRATES
--==============================================================
local LastToolUse={}

local function toolStackAmount(t)
    if not t or not t.Parent then return 0 end
    return tonumber(t:GetAttribute("Count") or t:GetAttribute("Amount") or t:GetAttribute("Uses")) or 1
end

local function equipActivate(t)
    if not t or not t.Parent then return false end
    local h=hum()
    if not h then return false end
    pcall(function() h:EquipTool(t) end)
    task.wait(0.08)
    local ok=pcall(function() t:Activate() end)
    if ok then
        State.ToolsUsed+=1
        LastToolUse[t]=os.clock()
    end
    return ok
end

local function activateConsumableVerified(t, timeout)
    if not t or not t.Parent then return false end
    local beforeParent=t.Parent
    local beforeAmount=toolStackAmount(t)
    local beforeName=toolName(t)
    if not equipActivate(t) then return false end
    return waitUntil(function()
        if not t.Parent then return true end
        if toolStackAmount(t) < beforeAmount then return true end
        if countInventoryItem(beforeName) < beforeAmount then return true end
        return false
    end, timeout or 1.5, 0.08)
end

local function toolAllowedByConfig(t)
    local n=toolName(t)
    local ln=norm(n)
    if ln:find("egg",1,true) then
        return enabled("Egg","Open") and tableAllows(C("Egg","Egg"),n,false)
    elseif ln:find("seedpack",1,true) or ln:find("harvestpack",1,true) then
        return enabled("Seed Pack","Open") and tableAllows(C("Seed Pack","Pack"),n,false)
    elseif ln:find("crate",1,true) or ln:find("chest",1,true) then
        return enabled("Crate","Open") and tableAllows(C("Crate","Open List"),n,false)
    end
    return false
end

task.spawn(function()
    while Alive do
        for _,t in ipairs(scanTools()) do
            if toolAllowedByConfig(t) then
                if not LastToolUse[t] or os.clock()-LastToolUse[t]>1.5 then
                    if acquire("OpenTool",1) then
                        local n=t.Name
                        if activateConsumableVerified(t,1.8) then
                            log("Open verified: "..n)
                        end
                        release("OpenTool")
                    end
                end
            end
        end
        task.wait(0.7)
    end
end)

local function getPlotCenter()
    local p=getPlot()
    if not p then return nil end
    local ok,cf=pcall(function() return p:GetPivot() end)
    return ok and cf.Position or nil
end

local function useGearLoop(section, keywords)
    task.spawn(function()
        while Alive do
            if enabled(section,"Enable") then
                local list=C(section,"Gear")
                for _,t in ipairs(scanTools()) do
                    local n=toolName(t)
                    local lower=norm(n)
                    local isType=false
                    for _,k in ipairs(keywords) do if lower:find(norm(k),1,true) then isType=true break end end
                    if isType and (type(list)~="table" or next(list)==nil or tableAllows(list,n,false)) then
                        if acquire(section,1) then
                            local root=hrp()
                            local saved=root and root.CFrame
                            local center=getPlotCenter()
                            if root and center then root.CFrame=CFrame.new(center+Vector3.new(0,3,0)) end
                            if equipActivate(t) then log(section.." activated: "..n) end
                            if root and saved then root.CFrame=saved end
                            release(section)
                            task.wait(math.max(0.5,num(3,section,"Interval")))
                        end
                    end
                end
            end
            task.wait(1)
        end
    end)
end

useGearLoop("Auto Water", {"WateringCan"})
useGearLoop("Auto Sprinkler", {"Sprinkler"})

task.spawn(function()
    while Alive do
        if enabled("Event","Cornucopia","Auto Use") then
            local t=findTool("Cornucopia")
            if t and acquire("Cornucopia",1) then
                if activateConsumableVerified(t,1.5) then
                    log("Cornucopia verified")
                elseif t.Parent then
                    log("Cornucopia activated / effect not verified")
                end
                release("Cornucopia")
                task.wait(2)
            end
        end
        local harp=C("Event","Harp")
        if type(harp)=="table" and harp["Enable"]==true then
            local cash=getCurrency()
            if cash >= (tonumber(harp["Min Currency"]) or 0) then
                local t=findTool("Harp")
                if t and acquire("Harp",1) then
                    if equipActivate(t) then log("Harp activated") end
                    release("Harp")
                    task.wait(math.max(2,tonumber(harp["Interval"]) or 5))
                end
            end
        end
        task.wait(1)
    end
end)

--==============================================================
-- PET TAME / BUY
--==============================================================
local function wildPetFolder()
    local map=workspace:FindFirstChild("Map")
    if map then
        local f=map:FindFirstChild("WildPetRef") or map:FindFirstChild("WildPets")
        if f then return f end
    end
    for _,d in ipairs(workspace:GetDescendants()) do
        if d:IsA("Folder") and (d.Name=="WildPetRef" or d.Name=="WildPets") then return d end
    end
end

local rarityRank={Common=1,Uncommon=2,Rare=3,Epic=4,Legendary=5,Mythic=6,Mythical=6,Super=7,Divine=8,Prismatic=9,Secret=10}
local function petName(ref)
    return tostring(firstNonNil(ref:GetAttribute("PetName"),ref:GetAttribute("Species"),ref:GetAttribute("Name"),ref.Name))
end
local function petVariant(ref)
    local rainbow=ref:GetAttribute("Rainbow")==true or norm(ref:GetAttribute("Mutation"))=="rainbow"
    local size=tostring(firstNonNil(ref:GetAttribute("SizeVariant"),ref:GetAttribute("Size"),"Normal"))
    return size,rainbow
end

local function petEnabled(name)
    return tableAllows(C("Pet","Auto Buy","Pet"),name,false)
end

local function bestWildPet()
    local f=wildPetFolder()
    if not f then return nil end
    local best,bscore
    local maxPrice=num(math.huge,"Pet","Auto Buy","Max Price")
    for _,ref in ipairs(f:GetChildren()) do
        if ref:IsA("BasePart") or ref:IsA("Model") then
            local owner=tonumber(firstNonNil(ref:GetAttribute("OwnerUserId"),ref:GetAttribute("UserId"),0)) or 0
            local name=petName(ref)
            local price=tonumber(firstNonNil(ref:GetAttribute("Price"),ref:GetAttribute("Cost"),0)) or 0
            if owner==0 and petEnabled(name) and price<=maxPrice and price<=getCurrency() then
                local rarity=tostring(firstNonNil(ref:GetAttribute("Rarity"),"Common"))
                local sz,rainbow=petVariant(ref)
                local score=(rarityRank[rarity] or 0)*100
                if sz=="Big" then score+=20 elseif sz=="Mega" then score+=40 elseif sz=="Huge" then score+=30 end
                if rainbow then score+=25 end
                if not best or score>bscore then best,bscore=ref,score end
            end
        end
    end
    return best
end

local function refCF(ref)
    if ref:IsA("BasePart") then return ref.CFrame end
    local ok,cf=pcall(function() return ref:GetPivot() end)
    return ok and cf or nil
end

task.spawn(function()
    while Alive do
        if enabled("Pet","Auto Buy","Enable") and P_WildPetTame then
            local ref=bestWildPet()
            if ref and acquire("PetTame",2) then
                local root=hrp()
                local saved=root and root.CFrame
                local cf=refCF(ref)
                if cf then moveToCF(cf*CFrame.new(0,3,3),"PetTame") end

                local function ownedNow()
                    if not ref.Parent then return false end
                    return tonumber(firstNonNil(ref:GetAttribute("OwnerUserId"),ref:GetAttribute("UserId"),0)) == LP.UserId
                end

                local petId=firstNonNil(
                    ref:GetAttribute("PetId"),
                    ref:GetAttribute("PetID"),
                    ref:GetAttribute("Id"),
                    ref:GetAttribute("ID")
                )
                local name=petName(ref)
                local clean={table.pack(ref)}
                if petId ~= nil then clean[#clean+1]=table.pack(petId) end
                clean[#clean+1]=table.pack(name)
                clean[#clean+1]=table.pack({Pet=ref, PetId=petId, PetName=name})

                if adaptiveFire("TAME_PET",P_WildPetTame,clean,ownedNow,1.5) then
                    PetCache.At=0
                    State.PetsTamed+=1
                    queueWebhook("RarePet",{Name=name, Price=tonumber(ref:GetAttribute("Price") or ref:GetAttribute("Cost") or 0) or 0, Rarity=tostring(ref:GetAttribute("Rarity") or "")})
                    log("Tame verified: "..name)
                else
                    log("Tame signature failed: "..name)
                end

                root=hrp()
                if root and saved then root.CFrame=saved end
                release("PetTame")
            end
        end
        task.wait(math.max(0.4,num(1,"Pet","Auto Buy","Interval")))
    end
end)

-- Pet inventory/equip adapter: operates only if current game exposes the packets.
local function petIdFromEntry(p)
    if type(p)~="table" then return nil end
    return firstNonNil(p.Id,p.ID,p.PetId,p.PetID,p.UUID,p.Uuid,p.Guid,p.GUID)
end
local function petSpeciesFromEntry(p)
    if type(p)~="table" then return "" end
    return tostring(firstNonNil(p.Name,p.PetName,p.Species,p.Type,""))
end

local PetCache={At=0,Data=nil}
local EquippedCache={At=0,Data=nil}

local function getPetTable(force)
    if not P_GetPets then return nil end
    if not force and os.clock()-PetCache.At<1.5 then return PetCache.Data end
    PetCache.At=os.clock()
    local ok,res=query(P_GetPets)
    if ok and type(res)=="table" then
        PetCache.Data=res
        return res
    end
    return PetCache.Data
end

local function getEquippedTable(force)
    if not P_GetEquippedPets then return nil end
    if not force and os.clock()-EquippedCache.At<1.0 then return EquippedCache.Data end
    EquippedCache.At=os.clock()
    local ok,res=query(P_GetEquippedPets)
    if ok and type(res)=="table" then
        EquippedCache.Data=res
        return res
    end
    return EquippedCache.Data
end

local function tableContainsPetId(tbl,id)
    if type(tbl)~="table" or id==nil then return false end
    local sid=tostring(id)
    for _,v in pairs(tbl) do
        if type(v)=="table" then
            local vid=petIdFromEntry(v)
            if vid~=nil and tostring(vid)==sid then return true end
        elseif tostring(v)==sid then
            return true
        end
    end
    return false
end

local function petNightNow()
    local v=RS:FindFirstChild("Night")
    if v and v:IsA("BoolValue") then return v.Value end
    return Lighting.ClockTime>=18 or Lighting.ClockTime<6
end

local function managePets()
    local useNight = enabled("Pet","Equip At Night","Enable") and petNightNow()
    local normalEnabled = enabled("Pet","Auto Equip","Enable")
    if not useNight and not normalEnabled then return end

    -- Real-only: equipping is only attempted if current game exposes both
    -- inventory and equipped-pet query adapters so success can be checked.
    if not (P_GetPets and P_EquipPet and P_GetEquippedPets) then return end

    local pets=getPetTable(true)
    if type(pets)~="table" then return end
    local desired = useNight and C("Pet","Equip At Night","Pet") or C("Pet","Auto Equip","Pet")
    if type(desired)~="table" then return end

    local candidates={}
    for _,p in pairs(pets) do
        if type(p)=="table" then
            local name=petSpeciesFromEntry(p)
            local cfg
            for k,v in pairs(desired) do
                if norm(k)==norm(name) then cfg=v break end
            end
            if type(cfg)=="table" then
                candidates[#candidates+1]={
                    p=p,
                    name=name,
                    priority=tonumber(cfg.Priority) or 999,
                    amount=tonumber(cfg.Amount) or 1
                }
            end
        end
    end
    table.sort(candidates,function(a,b) return a.priority<b.priority end)

    local equipped=getEquippedTable(true) or {}
    local speciesUsed={}
    local totalEquipped=0

    for _,v in pairs(equipped) do
        totalEquipped+=1
        if type(v)=="table" then
            local n=norm(petSpeciesFromEntry(v))
            if n~="" then speciesUsed[n]=(speciesUsed[n] or 0)+1 end
        end
    end

    local maxSlots=num(6,"Pet","Max Slots")
    for _,e in ipairs(candidates) do
        if totalEquipped>=maxSlots then break end
        local key=norm(e.name)
        local already=speciesUsed[key] or 0
        if already<e.amount then
            local id=petIdFromEntry(e.p)
            if id and not tableContainsPetId(equipped,id) then
                local beforeCount=totalEquipped
                local variants={
                    table.pack(id),
                    table.pack(e.p),
                    table.pack({PetId=id}),
                }
                local function verify()
                    EquippedCache.At=0
                    local after=getEquippedTable(true)
                    if tableContainsPetId(after,id) then return true end
                    if type(after)=="table" then
                        local n=0
                        for _ in pairs(after) do n+=1 end
                        if n>beforeCount then return true end
                    end
                    return false
                end
                if adaptiveFire("EQUIP_PET",P_EquipPet,variants,verify,1.2) then
                    equipped=getEquippedTable(true) or equipped
                    speciesUsed[key]=already+1
                    totalEquipped+=1
                    log("Equip pet verified: "..e.name)
                end
            end
        end
    end
end

task.spawn(function()
    while Alive do
        local ok,e=pcall(managePets)
        if not ok then errlog("Pet Equip",e) end
        task.wait(4)
    end
end)

local function countPetSpecies(pets)
    local counts={}
    if type(pets)~="table" then return counts end
    for _,p in pairs(pets) do
        if type(p)=="table" then
            local n=norm(petSpeciesFromEntry(p))
            if n~="" then counts[n]=(counts[n] or 0)+1 end
        end
    end
    return counts
end

task.spawn(function()
    while Alive do
        if enabled("Pet","Auto Sell","Enable") and P_GetPets and P_SellPet then
            local ok,e=pcall(function()
                local pets=getPetTable(true)
                if type(pets)~="table" then return end
                local counts=countPetSpecies(pets)
                local sellList=C("Pet","Auto Sell","Pet")
                local keepList=C("Pet","Auto Sell","Keep")
                for _,p in pairs(pets) do
                    if type(p)=="table" then
                        local name=petSpeciesFromEntry(p)
                        if tableAllows(sellList,name,false) then
                            local keep=0
                            if type(keepList)=="table" then
                                for k,v in pairs(keepList) do
                                    if norm(k)==norm(name) then keep=tonumber(v) or 0 break end
                                end
                            end
                            local key=norm(name)
                            if (counts[key] or 0)>keep then
                                local id=petIdFromEntry(p)
                                if id then
                                    local before=counts[key] or 0
                                    local fired=fire(P_SellPet,id)
                                    if fired then
                                        task.wait(0.25)
                                        PetCache.At=0
                                        local afterPets=getPetTable(true)
                                        local afterCounts=countPetSpecies(afterPets)
                                        if (afterCounts[key] or before)<before then
                                            counts=afterCounts
                                            log("Sold pet: "..name)
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end)
            if not ok then errlog("Pet Sell",e) end
        end
        task.wait(5)
    end
end)

local function petSlotCount()
    return tonumber(firstNonNil(
        LP:GetAttribute("PetSlots"),
        LP:GetAttribute("MaxPets"),
        LP:GetAttribute("PetCapacity"),
        0
    )) or 0
end

task.spawn(function()
    while Alive do
        if enabled("Buy Slot Pet") and P_BuyPetSlot then
            local max=num(6,"Pet","Max Slots")
            local current=petSlotCount()
            if current>0 and current<max then
                local variants={
                    table.pack(),
                    table.pack(1),
                    table.pack(current+1),
                }
                local function verify()
                    return petSlotCount()>current
                end
                if adaptiveFire("BUY_PET_SLOT",P_BuyPetSlot,variants,verify,1.5) then
                    log("Pet slot verified: "..petSlotCount())
                end
                task.wait(2)
            end
        end
        task.wait(5)
    end
end)

--==============================================================
-- EXPAND PLOT / REAL PROMPTS
--==============================================================
local PromptDebounce={}

local function plotAreaCount()
    local plot=getPlot()
    if not plot then return 0 end
    local n=0
    for _,a in ipairs(CollectionService:GetTagged("PlantArea")) do
        if a:IsDescendantOf(plot) then n+=1 end
    end
    if n==0 then
        for _,d in ipairs(plot:GetDescendants()) do
            if d:IsA("BasePart") and (norm(d.Name):find("plantarea",1,true) or d:GetAttribute("PlantArea")==true) then
                n+=1
            end
        end
    end
    return n
end

local function promptText(p)
    return norm((p.ActionText or "").." "..(p.ObjectText or "").." "..p.Name.." "..(p.Parent and p.Parent.Name or ""))
end
local function usePrompt(p)
    if not p or not p.Parent then return false end
    if fireproximityprompt then
        local ok=pcall(fireproximityprompt,p)
        if ok then return true end
    end
    local root=hrp()
    local saved=root and root.CFrame
    local parent=p.Parent
    local cf
    if parent:IsA("BasePart") then cf=parent.CFrame
    elseif parent:IsA("Model") then pcall(function() cf=parent:GetPivot() end) end
    if root and cf then root.CFrame=cf*CFrame.new(0,2,0) end
    local ok=pcall(function()
        p:InputHoldBegin()
        task.wait(math.max(0.05,p.HoldDuration))
        p:InputHoldEnd()
    end)
    if root and saved then root.CFrame=saved end
    return ok
end

task.spawn(function()
    while Alive do
        if enabled("Buy Expand Plot") then
            local limit=num(math.huge,"Expand Limit")
            if State.Expands<limit then
                for _,d in ipairs(workspace:GetDescendants()) do
                    if d:IsA("ProximityPrompt") then
                        local tx=promptText(d)
                        if tx:find("expand",1,true) or tx:find("unlockplot",1,true) then
                            local k=tostring(d)
                            if not PromptDebounce[k] or os.clock()-PromptDebounce[k]>8 then
                                PromptDebounce[k]=os.clock()
                                local beforeAreas=plotAreaCount()
                                local beforePromptParent=d.Parent
                                local beforeEnabled=d.Enabled
                                if usePrompt(d) then
                                    local verified=waitUntil(function()
                                        if not d.Parent then return true end
                                        if beforeEnabled and d.Enabled==false then return true end
                                        if plotAreaCount()>beforeAreas then return true end
                                        return false
                                    end,1.8,0.1)
                                    if verified then
                                        State.Expands+=1
                                        log("Expand plot verified")
                                    else
                                        log("Expand interaction / not verified")
                                    end
                                    task.wait(1)
                                end
                                break
                            end
                        end
                    end
                end
            end
        end
        task.wait(3)
    end
end)

--==============================================================
-- EVENT/DROPPED SEED COLLECTION
--==============================================================
local function isWantedDrop(inst)
    local n=norm(inst.Name.." "..tostring(inst:GetAttribute("SeedName") or "").." "..tostring(inst:GetAttribute("ItemName") or ""))
    local cfg=C("Event","Collect Seed","Seed")
    if type(cfg)=="table" then
        for k,v in pairs(cfg) do
            local name=type(k)=="string" and k or v
            if (v==true or type(k)=="number") and n:find(norm(name),1,true) then return true end
        end
    end
    return false
end

local function touchOrPrompt(inst)
    if not inst or not inst.Parent then return false end

    local itemName=tostring(firstNonNil(
        inst:GetAttribute("SeedName"),
        inst:GetAttribute("ItemName"),
        inst:GetAttribute("Name"),
        inst.Name
    ))
    local beforeOwned=countInventoryItem(itemName)
    local beforeTools=#scanTools()
    local prompt=inst:FindFirstChildWhichIsA("ProximityPrompt",true)

    local interacted=false
    if prompt then
        interacted=usePrompt(prompt)
    else
        local part=inst:IsA("BasePart") and inst or inst:FindFirstChildWhichIsA("BasePart",true)
        local root=hrp()
        if part and root then
            root.CFrame=part.CFrame*CFrame.new(0,2,0)
            if firetouchinterest then
                interacted=pcall(function()
                    firetouchinterest(root,part,0)
                    task.wait()
                    firetouchinterest(root,part,1)
                end)
            else
                -- Physical overlap may still collect when the player is moved onto it.
                interacted=true
            end
        end
    end

    if not interacted then return false end

    return waitUntil(function()
        if not inst.Parent then return true end
        if prompt and (not prompt.Parent or not prompt.Enabled) then return true end
        if countInventoryItem(itemName)>beforeOwned then return true end
        if #scanTools()>beforeTools then return true end
        return false
    end,1.5,0.08)
end

task.spawn(function()
    while Alive do
        if enabled("Event","Collect Seed","Enable") or enabled("Seed Pack","Collect") then
            local candidates={}
            local seen={}
            local function addCandidate(d)
                if not d or seen[d] then return end
                if not (d:IsA("Model") or d:IsA("BasePart")) then return end
                if isWantedDrop(d) or (enabled("Seed Pack","Collect") and norm(d.Name):find("seedpack",1,true)) then
                    seen[d]=true
                    candidates[#candidates+1]=d
                end
            end

            -- Fast paths first.
            for _,tag in ipairs({"DroppedSeed","EventSeed","SeedPack","DroppedItem"}) do
                for _,d in ipairs(CollectionService:GetTagged(tag)) do addCandidate(d) end
            end
            local map=workspace:FindFirstChild("Map")
            if map then
                for _,folderName in ipairs({"DroppedSeeds","EventSeeds","SeedDrops","SeedPackSpawnServerLocations","SeedSpawnServerLocations"}) do
                    local f=map:FindFirstChild(folderName,true)
                    if f then
                        for _,d in ipairs(f:GetChildren()) do addCandidate(d) end
                    end
                end
            end

            -- Fallback scan only when the fast paths found nothing.
            if #candidates==0 then
                for _,d in ipairs(workspace:GetDescendants()) do
                    addCandidate(d)
                    if #candidates>=100 then break end
                end
            end
            for _,d in ipairs(candidates) do
                if not Alive then break end
                if acquire("DropCollect",1) then
                    local root=hrp()
                    local saved=root and root.CFrame
                    if touchOrPrompt(d) then
                        State.EventSeeds+=1
                        queueWebhook("RareSeed",{Name=d.Name})
                        log("Collected drop: "..d.Name)
                    end
                    root=hrp()
                    if root and saved then root.CFrame=saved end
                    release("DropCollect")
                    task.wait(0.15)
                end
            end
        end
        task.wait(2.5)
    end
end)

--==============================================================
-- MAILBOX / GIFTS / CODES
--==============================================================
local function visibleButtonContains(words, ancestorWord)
    local pg=LP:FindFirstChildOfClass("PlayerGui")
    if not pg then return nil end
    for _,d in ipairs(pg:GetDescendants()) do
        if d:IsA("TextButton") and d.Visible then
            local tx=norm(d.Text.." "..d.Name)
            local good=true
            for _,w in ipairs(words) do if not tx:find(norm(w),1,true) then good=false break end end
            if good then
                if ancestorWord then
                    local cur=d.Parent
                    local found=false
                    for _=1,6 do
                        if not cur then break end
                        if norm(cur.Name):find(norm(ancestorWord),1,true) then found=true break end
                        cur=cur.Parent
                    end
                    if not found then continue end
                end
                return d
            end
        end
    end
end

local function clickButton(b)
    if not b or not b.Visible then return false end
    if firesignal then
        local ok=pcall(function() firesignal(b.Activated) end)
        if ok then return true end
    end
    local pos,size=b.AbsolutePosition,b.AbsoluteSize
    if size.X>0 and size.Y>0 then
        local x,y=pos.X+size.X/2,pos.Y+size.Y/2
        return pcall(function()
            VirtualInputManager:SendMouseButtonEvent(x,y,0,true,game,0)
            task.wait(0.04)
            VirtualInputManager:SendMouseButtonEvent(x,y,0,false,game,0)
        end)
    end
    return false
end

local function mailboxCount()
    for _,key in ipairs({"MailCount","MailboxCount","InboxCount","UnclaimedMail","UnclaimedGifts"}) do
        local a=LP:GetAttribute(key)
        if type(a)=="number" then return a end
    end
    local data=LP:FindFirstChild("Data")
    if data then
        for _,d in ipairs(data:GetDescendants()) do
            if d:IsA("ValueBase") and tonumber(d.Value) then
                local n=norm(d.Name)
                if n=="mailcount" or n=="mailboxcount" or n=="inboxcount" or n=="unclaimedmail" or n=="unclaimedgifts" then
                    return tonumber(d.Value)
                end
            end
        end
    end
    return nil
end

task.spawn(function()
    while Alive do
        if enabled("Mailbox","Auto Claim") then
            local b=visibleButtonContains({"claim","all"},"mail")
            if b then
                local beforeCount=mailboxCount()
                local clicked=clickButton(b)
                if clicked and waitUntil(function()
                    local now=mailboxCount()
                    if beforeCount~=nil and now~=nil and now<beforeCount then return true end
                    return not b.Parent or not b.Visible or not b.Active
                end,1.5,0.1) then
                    State.MailClaims+=1
                    State.Verified.MAILBOX=true
                    State.LastSuccess.MAILBOX=os.clock()
                    log("Mailbox claim verified")
                end
            elseif P_ClaimMailbox then
                local beforeCount=mailboxCount()
                -- Do not call a packet blindly if there is no observable mailbox
                -- state to verify. This prevents farm/shop changes from being
                -- mistaken for a successful mail claim.
                if beforeCount and beforeCount>0 then
                    local variants={table.pack(),table.pack(true),table.pack("All")}
                    local function verify()
                        local now=mailboxCount()
                        return now~=nil and now<beforeCount
                    end
                    if adaptiveFire("MAILBOX",P_ClaimMailbox,variants,verify,1.5) then
                        State.MailClaims+=1
                        log("Mailbox packet verified")
                    end
                end
            end
        end

        if enabled("Mailbox","Claim Gifts") and P_ClaimGifts then
            local beforeCount=mailboxCount()
            if beforeCount and beforeCount>0 then
                adaptiveFire("GIFTS",P_ClaimGifts,{table.pack(),table.pack(true)},function()
                    local now=mailboxCount()
                    return now~=nil and now<beforeCount
                end,1.2)
            end
        end
        task.wait(8)
    end
end)

local redeemed={}
task.spawn(function()
    while Alive do
        if enabled("Codes","Enable") and P_RedeemCode then
            local list=C("Codes","Code")
            if type(list)=="table" then
                for _,code in ipairs(list) do
                    if type(code)=="string" and code~="" and not redeemed[code] then
                        local ok=fire(P_RedeemCode,code)
                        if ok then
                            -- A packet call returning without error is not proof that
                            -- a code was accepted (expired/used codes may no-op).
                            -- Mark locally as submitted to avoid spam, but never call
                            -- it "verified" without observable reward state.
                            redeemed[code]=true
                            log("Code submitted / unverified: "..code)
                        end
                        task.wait(0.5)
                    end
                end
            end
        end
        task.wait(10)
    end
end)

-- Fresh-account/bootstrap watchdog. It does not invent rewards; it only reports
-- whether the account has a path to start farming.
task.spawn(function()
    local lastMessage=""
    while Alive do
        if C("Bootstrap","Enable")~=false then
            local cash,currency=getCurrency()
            local seeds=totalSeedInventory()
            local plants=totalPlantCount()
            local msg
            if seeds>0 or plants>0 or cash>0 then
                msg="READY"
            elseif enabled("Codes","Enable") and P_RedeemCode then
                msg="WAITING CODE REWARD"
            elseif enabled("Buy Seed","Enable") and P_PurchaseSeed and currency~="?" then
                msg="WAITING CURRENCY"
            else
                msg="BLOCKED: NO SEED/CURRENCY"
            end
            State.BootstrapStatus=msg
            if msg~=lastMessage and enabled("Debug","Console") then
                print("[OneClick GAG2] Bootstrap: "..msg)
                lastMessage=msg
            end
        else
            State.BootstrapStatus="OFF"
        end
        task.wait(2)
    end
end)

--==============================================================
-- GARDEN CARDS / PILGRIM / BAKER / WORLD STATUS
--==============================================================
local function isFallWorld()
    for _,key in ipairs({"World","CurrentWorld","Zone","Map"}) do
        local v=LP:GetAttribute(key)
        if v and norm(v):find("fall",1,true) then return true end
    end
    return workspace:FindFirstChild("FallHarvest")~=nil or workspace:FindFirstChild("Fall Harvest")~=nil
end

local function isNight()
    local v=RS:FindFirstChild("Night")
    if v and v:IsA("BoolValue") then return v.Value end
    return Lighting.ClockTime>=18 or Lighting.ClockTime<6
end

local EventScanCache={At=0,Baker=false,HarvestMoon=false,Werewolf=false}

local function scanEventStatus(force)
    if not force and os.clock()-EventScanCache.At<2.5 then
        return EventScanCache
    end
    EventScanCache.At=os.clock()

    local baker=false
    local moon=false
    local were=false

    -- Prefer explicit replicated boolean/value state.
    for _,root in ipairs({RS,workspace}) do
        for _,name in ipairs({"HarvestMoon","Harvest Moon","HarvestMoonActive"}) do
            local v=root:FindFirstChild(name,true)
            if v then
                if v:IsA("BoolValue") then
                    if v.Value then moon=true end
                elseif root==workspace then
                    moon=true
                end
            end
        end
    end

    -- Baker presence should be detected in the live world, not ReplicatedStorage
    -- templates, otherwise the UI can say ACTIVE permanently.
    for _,d in ipairs(workspace:GetDescendants()) do
        local n=norm(d.Name)
        if not baker and n:find("baker",1,true) then baker=true end
        if not were and n:find("werewolf",1,true) then were=true end
        if baker and were then break end
    end

    for _,key in ipairs({"Werewolf","IsWerewolf","WereWolf","IsWereWolf"}) do
        local a=LP:GetAttribute(key)
        if type(a)=="boolean" and a then were=true end
        local c=char()
        if c then
            local b=c:GetAttribute(key)
            if type(b)=="boolean" and b then were=true end
        end
    end

    EventScanCache.Baker=baker
    EventScanCache.HarvestMoon=moon
    EventScanCache.Werewolf=were
    return EventScanCache
end

local function harvestMoonActive()
    return scanEventStatus().HarvestMoon
end

local function bakerPresent()
    return scanEventStatus().Baker
end

local function werewolfActive()
    return scanEventStatus().Werewolf
end

task.spawn(function()
    local last={
        Baker=bakerPresent(),
        HarvestMoon=harvestMoonActive(),
        Werewolf=werewolfActive(),
    }
    State.EventStatus=last
    while Alive do
        local now={
            Baker=bakerPresent(),
            HarvestMoon=harvestMoonActive(),
            Werewolf=werewolfActive(),
        }
        State.EventStatus=now

        if now.Baker~=last.Baker and enabled("Event","Baker","Notify") then
            queueWebhook("WorldEvent",{Name="Baker",Active=now.Baker})
            log("Baker: "..(now.Baker and "ACTIVE" or "OFF"))
        end
        if now.HarvestMoon~=last.HarvestMoon and enabled("Event","Harvest Moon","Notify") then
            queueWebhook("WorldEvent",{Name="Harvest Moon",Active=now.HarvestMoon})
            log("Harvest Moon: "..(now.HarvestMoon and "ACTIVE" or "OFF"))
        end
        if now.Werewolf~=last.Werewolf and enabled("Event","Werewolf Night","Notify") then
            queueWebhook("WorldEvent",{Name="Werewolf",Active=now.Werewolf})
            log("Werewolf: "..(now.Werewolf and "ACTIVE" or "OFF"))
        end
        last=now
        task.wait(3)
    end
end)

task.spawn(function()
    while Alive do
        if enabled("Event","Garden Cards","Free Daily") then
            local b=visibleButtonContains({"free"},"card") or visibleButtonContains({"free"},"garden")
            if b and not norm(b.Text):find("robux",1,true) and not norm(b.Text):find("r$",1,true) then
                local beforeText=tostring(b.Text)
                if clickButton(b) and waitUntil(function()
                    return not b.Parent or not b.Visible or tostring(b.Text)~=beforeText
                end,1.5,0.1) then
                    State.CardClaims+=1
                    log("Garden Card FREE verified")
                end
            end
        end
        if enabled("Event","Pilgrim","Auto Claim") and isFallWorld() then
            local b=visibleButtonContains({"claim"},"pilgrim") or visibleButtonContains({"claim"},"cornucopia")
            if b then
                local before=tostring(b.Text)
                if clickButton(b) and waitUntil(function()
                    return not b.Parent or not b.Visible or tostring(b.Text)~=before
                end,1.5,0.1) then
                    log("Pilgrim claim verified")
                end
            end
        end
        task.wait(5)
    end
end)

-- World travel: interacts with actual Ethan/world UI only.
task.spawn(function()
    while Alive do
        local worldCfg=C("World")
        if type(worldCfg)=="table" and worldCfg["Auto Travel"]==true then
            local target=tostring(worldCfg["Target"] or "Main")
            local need=(target=="FallHarvest" and not isFallWorld()) or (target=="Main" and isFallWorld())
            if need then
                local desired=target=="FallHarvest" and "fallharvest" or "gardenvalley"
                local b=visibleButtonContains({desired=="fallharvest" and "fall" or "garden"},"world")
                if b then
                    if clickButton(b) and waitUntil(function()
                        return (target=="FallHarvest" and isFallWorld()) or (target=="Main" and not isFallWorld())
                    end,10,0.25) then
                        CachedPlot=nil
                        PlantScanCache.At=0
                        log("World travel verified: "..target)
                    else
                        log("World travel clicked / not verified")
                    end
                    task.wait(2)
                else
                    for _,d in ipairs(workspace:GetDescendants()) do
                        if d:IsA("ProximityPrompt") then
                            local tx=promptText(d)
                            if tx:find("ethan",1,true) or tx:find("explorer",1,true) or tx:find("fallharvest",1,true) then
                                usePrompt(d)
                                task.wait(1)
                                break
                            end
                        end
                    end
                end
            end
        end
        task.wait(6)
    end
end)

--==============================================================
-- NIGHT STEAL - NORMAL GAME INTERACTION (NOT INSTANT-STEAL BYPASS)
--==============================================================
task.spawn(function()
    while Alive do
        if enabled("Steal","Enable") and isNight() then
            local maxCount=num(10,"Steal","Limit")
            local done=0
            for _,p in ipairs(CollectionService:GetTagged("StealPrompt")) do
                if done>=maxCount then break end
                if p:IsA("ProximityPrompt") and p.Parent and p:IsDescendantOf(workspace) then
                    local model=p.Parent:FindFirstAncestorWhichIsA("Model")
                    if model and not model:IsDescendantOf(getPlot() or LP) then
                        local seed=plantSeedName(model) or model.Name
                        local kg=readWeight(model)
                        local minKg=num(0,"Steal","Min KG")
                        local mutation=readMutation(model)
                        local mutationCfg=C("Steal","Mutation")
                        local mutationOk=true
                        if type(mutationCfg)=="table" and next(mutationCfg)~=nil then
                            mutationOk=false
                            for k,v in pairs(mutationCfg) do
                                local wanted=type(k)=="string" and k or v
                                if (v==true or type(k)=="number") and norm(mutation):find(norm(wanted),1,true) then
                                    mutationOk=true
                                    break
                                end
                            end
                        end
                        if kg>=minKg and mutationOk and tableAllows(C("Steal","Fruit"),seed,true) then
                            if acquire("Steal",1) then
                                local root=hrp(); local saved=root and root.CFrame
                                local cf
                                pcall(function() cf=model:GetPivot() end)
                                if cf then moveToCF(cf*CFrame.new(0,3,2),"Steal") end
                                if usePrompt(p) then log("Steal attempt: "..seed); done+=1 end
                                root=hrp(); if root and saved then root.CFrame=saved end
                                release("Steal")
                            end
                        end
                    end
                end
            end
        end
        task.wait(0.7)
    end
end)

--==============================================================
-- ANTI STEAL - only when current game exposes the shovel packets
--==============================================================
local function findShovel()
    for _,t in ipairs(scanTools()) do
        local n=norm(toolName(t))
        if n:find("shovel",1,true) then return t end
    end
end

local function intrudersInMyGarden()
    local out={}
    local plotId=LP:GetAttribute("PlotId")
    local zone=RS:FindFirstChild("GardenZoneData")
    if plotId==nil or not zone then return out end
    for _,p in ipairs(Players:GetPlayers()) do
        if p~=LP then
            local z=zone:FindFirstChild(p.Name)
            if z and z:IsA("ValueBase") and tostring(z.Value)==tostring(plotId) then
                local c=p.Character
                local r=c and c:FindFirstChild("HumanoidRootPart")
                if r then out[#out+1]=p end
            end
        end
    end
    return out
end

task.spawn(function()
    while Alive do
        if enabled("Anti Steal","Enable") and isNight() and P_ShoveSwing and P_ShoveHit then
            local shovel=findShovel()
            local intruders=intrudersInMyGarden()
            if shovel and #intruders>0 and acquire("AntiSteal",1) then
                local h=hum()
                if h then pcall(function() h:EquipTool(shovel) end) end
                for _,p in ipairs(intruders) do
                    if not Alive or not enabled("Anti Steal","Enable") then break end
                    local r=p.Character and p.Character:FindFirstChild("HumanoidRootPart")
                    local root=hrp()
                    if r and root then
                        local before=(r.Position-root.Position).Magnitude
                        fire(P_ShoveSwing)
                        fire(P_ShoveHit,p.UserId)
                        task.wait(0.55)
                        local r2=p.Character and p.Character:FindFirstChild("HumanoidRootPart")
                        if r2 and (r2.Position-root.Position).Magnitude>before+2 then
                            log("Anti Steal verified: "..p.Name)
                        else
                            log("Anti Steal attempted: "..p.Name)
                        end
                    end
                end
                release("AntiSteal")
            end
        end
        task.wait(0.35)
    end
end)

--==============================================================
-- WEBHOOK
--==============================================================
local requestFn = firstNonNil(
    rawget(ENV,"request"),
    rawget(ENV,"http_request"),
    syn and syn.request,
    http and http.request
)

local function postWebhook(title,description,fields,ping)
    local w=C("Webhook")
    if type(w)~="table" or w["Enable"]~=true then return false end
    local url=w["URL"]
    if type(url)~="string" or url=="" or type(requestFn)~="function" then return false end
    local content=""
    local did=tostring(w["DiscordId"] or "")
    if ping and did~="" then content="<@"..did..">" end
    local payload={
        username=tostring(w["Username"] or "OneClick GAG2"),
        content=content,
        embeds={{title=title,description=description,fields=fields or {},timestamp=os.date("!%Y-%m-%dT%H:%M:%SZ")}}
    }
    local ok=pcall(function()
        requestFn({
            Url=url,
            Method="POST",
            Headers={["Content-Type"]="application/json"},
            Body=HttpService:JSONEncode(payload),
        })
    end)
    return ok
end

task.spawn(function()
    local lastNight=isNight()
    while Alive do
        local wc=C("Webhook")
        if type(wc)=="table" and wc["Enable"]==true then
            local nowNight=isNight()
            if nowNight~=lastNight and wc["World Event"]==true then
                postWebhook("World Event",nowNight and "Night started" or "Day started",nil,false)
                lastNight=nowNight
            end

            while #WebhookQueue>0 do
                local ev=table.remove(WebhookQueue,1)
                if ev.Kind=="RarePet" and wc["OnRarePet"]==true then
                    local d=ev.Data or {}
                    local minPrice=tonumber(wc["PetMinPrice"]) or 0
                    local rarityOk=true
                    if type(wc["PetRarity"])=="table" and tostring(d.Rarity or "")~="" then
                        rarityOk=tableAllows(wc["PetRarity"],tostring(d.Rarity),false)
                    end
                    if (tonumber(d.Price) or 0)>=minPrice and rarityOk then
                        postWebhook("Pet Tamed",tostring(d.Name or "Pet"),{
                            {name="Rarity",value=tostring(d.Rarity or "?"),inline=true},
                            {name="Price",value=tostring(math.floor(tonumber(d.Price) or 0)),inline=true},
                        },true)
                    end
                elseif ev.Kind=="RareSeed" and wc["OnRareSeed"]==true then
                    local name=tostring((ev.Data or {}).Name or "Seed")
                    if norm(name):find("gold",1,true) or norm(name):find("rainbow",1,true) or norm(name):find("mega",1,true) then
                        postWebhook("Rare Seed Collected",name,nil,true)
                    end
                elseif ev.Kind=="WorldEvent" and wc["World Event"]==true then
                    local d=ev.Data or {}
                    postWebhook("World Event",tostring(d.Name or "Event")..": "..(d.Active and "ACTIVE" or "OFF"),nil,false)
                end
            end

            local interval=(tonumber(wc["ProfileIntervalMin"]) or 30)*60
            if wc["ProfileReport"]==true and os.clock()-State.LastWebhook>=interval then
                local cash,currency=getCurrency()
                postWebhook("OneClick GAG2 Profile",
                    "Current automation report",
                    {
                        {name="Currency",value=tostring(math.floor(cash)).." "..currency,inline=true},
                        {name="Plants",value=tostring(totalPlantCount()),inline=true},
                        {name="Harvested",value=tostring(State.Harvested),inline=true},
                        {name="Planted",value=tostring(State.Planted),inline=true},
                        {name="Pets Tamed",value=tostring(State.PetsTamed),inline=true},
                    },false)
                State.LastWebhook=os.clock()
            end
        else
            table.clear(WebhookQueue)
        end
        task.wait(1)
    end
end)

--==============================================================
-- PERFORMANCE / ANTI-AFK / REJOIN / RAM
--==============================================================
if setfpscap then
    pcall(setfpscap, math.max(1,num(30,"General","FPS")))
end
if C("General","3D Rendering")==false then
    pcall(function() RunService:Set3dRenderingEnabled(false) end)
end

LP.Idled:Connect(function()
    if Alive and C("General","Anti AFK")~=false then
        pcall(function()
            VirtualUser:CaptureController()
            VirtualUser:Button2Down(Vector2.new(),workspace.CurrentCamera.CFrame)
            task.wait(0.05)
            VirtualUser:Button2Up(Vector2.new(),workspace.CurrentCamera.CFrame)
        end)
    end
end)

task.spawn(function()
    while Alive do
        local limit=num(0,"General","RAM Kick MB")
        if limit>0 then
            local mb=collectgarbage("count")/1024
            pcall(function()
                local mem=StatsService:GetTotalMemoryUsageMb()
                if tonumber(mem) then mb=mem end
            end)
            if mb>=limit then
                LP:Kick("OneClick GAG2 RAM limit: "..math.floor(mb).."MB")
                break
            end
        end
        task.wait(5)
    end
end)

task.spawn(function()
    while Alive do
        if enabled("General","Auto Rejoin") then
            pcall(function()
                local prompt=CoreGui:FindFirstChild("RobloxPromptGui")
                local overlay=prompt and prompt:FindFirstChild("promptOverlay")
                if overlay then
                    for _,d in ipairs(overlay:GetChildren()) do
                        if norm(d.Name):find("errorprompt",1,true) or norm(d.Name):find("disconnect",1,true) then
                            TeleportService:Teleport(game.PlaceId,LP)
                            task.wait(8)
                        end
                    end
                end
            end)
        end
        task.wait(2)
    end
end)

--==============================================================
-- STATUS UI - matches the supplied OneClick reference layout
--==============================================================
local GUI
if C("UI","Enable")~=false then
    local parent=LP:FindFirstChildOfClass("PlayerGui")
    pcall(function()
        if gethui then
            local h=gethui()
            if h then parent=h end
        end
    end)
    if not parent then parent=CoreGui end
    local old=parent and parent:FindFirstChild("OneClickGAG2Rebuild")
    if old then old:Destroy() end

    GUI=Instance.new("ScreenGui")
    GUI.Name="OneClickGAG2Rebuild"
    GUI.ResetOnSpawn=false
    GUI.IgnoreGuiInset=true
    GUI.ZIndexBehavior=Enum.ZIndexBehavior.Sibling
    GUI.Parent=parent

    local main=Instance.new("Frame")
    main.Name="Main"
    main.AnchorPoint=Vector2.new(.5,.5)
    main.Position=UDim2.fromScale(.5,.5)
    main.Size=UDim2.fromOffset(620,650)
    main.BackgroundColor3=Color3.fromRGB(16,17,22)
    main.BorderSizePixel=0
    main.ClipsDescendants=true
    main.Parent=GUI
    Instance.new("UICorner",main).CornerRadius=UDim.new(0,14)
    local st=Instance.new("UIStroke",main)
    st.Color=Color3.fromRGB(56,127,83)
    st.Thickness=2

    local header=Instance.new("Frame")
    header.Name="Header"
    header.Size=UDim2.new(1,0,0,46)
    header.BackgroundColor3=Color3.fromRGB(31,75,50)
    header.BorderSizePixel=0
    header.Parent=main
    Instance.new("UICorner",header).CornerRadius=UDim.new(0,14)
    local fix=Instance.new("Frame",header)
    fix.Position=UDim2.new(0,0,1,-15)
    fix.Size=UDim2.new(1,0,0,15)
    fix.BackgroundColor3=header.BackgroundColor3
    fix.BorderSizePixel=0

    local title=Instance.new("TextLabel")
    title.BackgroundTransparency=1
    title.Position=UDim2.fromOffset(12,0)
    title.Size=UDim2.new(1,-250,1,0)
    title.Font=Enum.Font.GothamBold
    title.TextSize=18
    title.TextColor3=Color3.fromRGB(239,242,239)
    title.TextXAlignment=Enum.TextXAlignment.Left
    title.Text=tostring(C("UI","Title") or "OneClick GAG2 | discord.gg/chuoiihub")
    title.Parent=header

    local function headButton(text,x,width,onColor)
        local b=Instance.new("TextButton")
        b.AnchorPoint=Vector2.new(1,.5)
        b.Position=UDim2.new(1,x,.5,0)
        b.Size=UDim2.fromOffset(width,29)
        b.BackgroundColor3=onColor
        b.BorderSizePixel=0
        b.AutoButtonColor=false
        b.Font=Enum.Font.GothamBold
        b.TextSize=13
        b.TextColor3=Color3.new(1,1,1)
        b.Text=text
        b.Parent=header
        Instance.new("UICorner",b).CornerRadius=UDim.new(0,8)
        return b
    end

    local bgBtn=headButton("BG ON",-125,76,Color3.fromRGB(60,130,80))
    local renderBtn=headButton("3D ON",-48,78,Color3.fromRGB(60,130,80))
    local minimize=Instance.new("TextButton")
    minimize.AnchorPoint=Vector2.new(1,.5)
    minimize.Position=UDim2.new(1,-7,.5,0)
    minimize.Size=UDim2.fromOffset(26,28)
    minimize.BackgroundTransparency=1
    minimize.Font=Enum.Font.GothamBold
    minimize.TextSize=20
    minimize.TextColor3=Color3.new(1,1,1)
    minimize.Text="−"
    minimize.Parent=header

    local body=Instance.new("ScrollingFrame")
    body.Name="Body"
    body.Position=UDim2.fromOffset(0,46)
    body.Size=UDim2.new(1,0,1,-46)
    body.BackgroundColor3=Color3.fromRGB(16,17,22)
    body.BorderSizePixel=0
    body.ScrollBarThickness=4
    body.ScrollBarImageColor3=Color3.fromRGB(71,174,108)
    body.AutomaticCanvasSize=Enum.AutomaticSize.Y
    body.CanvasSize=UDim2.new()
    body.ScrollingDirection=Enum.ScrollingDirection.Y
    body.Parent=main

    local pad=Instance.new("UIPadding",body)
    pad.PaddingLeft=UDim.new(0,12)
    pad.PaddingRight=UDim.new(0,12)
    pad.PaddingTop=UDim.new(0,8)
    pad.PaddingBottom=UDim.new(0,10)

    local layout=Instance.new("UIListLayout",body)
    layout.SortOrder=Enum.SortOrder.LayoutOrder
    layout.Padding=UDim.new(0,0)

    local Labels={}
    local green=Color3.fromRGB(71,174,108)
    local normal=Color3.fromRGB(185,185,190)

    local function addLine(key,text,section)
        local l=Instance.new("TextLabel")
        l.Name=key
        l.BackgroundTransparency=1
        l.Size=UDim2.new(1,-4,0,27)
        l.Font=section and Enum.Font.GothamBold or Enum.Font.Code
        l.TextSize=section and 17 or 18
        l.TextColor3=section and green or normal
        l.TextXAlignment=Enum.TextXAlignment.Left
        l.TextYAlignment=Enum.TextYAlignment.Center
        l.Text=text or ""
        l.TextWrapped=false
        l.Parent=body
        Labels[key]=l
        return l
    end

    addLine("Fruit","Fruit: ? / ?",false)
    addLine("Pets","Pets: ?",false)
    addLine("Seeds","Seeds: ?",false)
    addLine("Plot","Plot: ?",false)

    addLine("Garden","───GARDEN───",true)
    addLine("Plants","Plants: 0 / ?",false)
    addLine("Sprinklers","Sprinklers: 0",false)
    addLine("Decaying","Decaying: 0",false)

    addLine("Session","───SESSION───",true)
    addLine("Uptime","Uptime: 00:00:00",false)
    addLine("Earned","Earned: ?",false)
    addLine("Rate","Rate: ?",false)
    addLine("Harvested","Harvested: 0",false)
    addLine("Planted","Planted: 0",false)
    addLine("Sold","Sold: 0 times",false)
    addLine("SeedBuy","Seeds Bought: 0",false)
    addLine("GearBuy","Gears Bought: 0",false)
    addLine("CrateBuy","Crates Bought: 0",false)
    addLine("PetTame","Pets Tamed: 0",false)
    addLine("Drops","Event Drops: 0",false)

    addLine("Events","───EVENT───",true)
    addLine("DayNight","Day/Night: ?",false)
    addLine("Baker","Baker: ?",false)
    addLine("Moon","Harvest Moon: ?",false)
    addLine("Werewolf","Werewolf: ?",false)
    addLine("Cards","Garden Cards: 0",false)

    addLine("Runtime","───RUNTIME───",true)
    addLine("Build","Build: "..BUILD,false)
    addLine("Network","Network: checking...",false)
    addLine("Bootstrap","Bootstrap: checking...",false)
    addLine("CodesCap","Codes: checking...",false)
    addLine("HarvestCap","Harvest: checking...",false)
    addLine("PlantCap","Plant: checking...",false)
    addLine("SellCap","Sell: checking...",false)
    addLine("SellGuard","Sell Guard: checking...",false)
    addLine("SeedShopCap","Buy Seed: checking...",false)
    addLine("GearShopCap","Buy Gear: checking...",false)
    addLine("CrateShopCap","Buy Crate: checking...",false)
    addLine("PetCap","Pet: checking...",false)
    addLine("PetSlotCap","Pet Slot: checking...",false)
    addLine("AntiStealCap","Anti Steal: checking...",false)
    addLine("MailCap","Mailbox: checking...",false)
    addLine("ExtraCap","Mail Send: UNSUPPORTED | Auction: UNSUPPORTED",false)
    addLine("EclipseCap","Eclipse Merge: UNSUPPORTED",false)

    addLine("Status","───STATUS───",true)
    addLine("Last","Last: Starting...",false)
    addLine("Error","Error: none",false)

    local function fmt(n)
        n=tonumber(n)
        if not n then return "?" end
        local a=math.abs(n)
        if a>=1e12 then return string.format("%.2fT",n/1e12) end
        if a>=1e9 then return string.format("%.2fB",n/1e9) end
        if a>=1e6 then return string.format("%.2fM",n/1e6) end
        if a>=1e3 then return string.format("%.1fK",n/1e3) end
        return tostring(math.floor(n+.5))
    end
    local function fmtTime(sec)
        sec=math.max(0,math.floor(sec or 0))
        return string.format("%02d:%02d:%02d",math.floor(sec/3600),math.floor((sec%3600)/60),sec%60)
    end
    local function ownedPetCount()
        local n=0
        local f=wildPetFolder()
        if f then
            for _,p in ipairs(f:GetChildren()) do
                if tonumber(firstNonNil(p:GetAttribute("OwnerUserId"),p:GetAttribute("UserId"),0))==LP.UserId then n+=1 end
            end
        end
        local pets=getPetTable()
        if type(pets)=="table" then
            local x=0
            for _,p in pairs(pets) do if type(p)=="table" then x+=1 end end
            if x>n then n=x end
        end
        return n
    end
    local function countNamedInPlot(word)
        local plot=getPlot()
        if not plot then return 0 end
        local n=0
        for _,d in ipairs(plot:GetDescendants()) do
            if norm(d.Name):find(norm(word),1,true) then n+=1 end
        end
        return n
    end
    local function readyFruitCount()
        local preview=sellPreview()
        if type(preview)=="table" then
            local n=tonumber(firstNonNil(preview.FruitCount,preview.Count,preview.ItemCount))
            if n~=nil then return n end
        end
        return countFruitInventory()
    end

    local function countDecaying()
        local n=0
        for _,plant in ipairs(discoverOwnPlants()) do
            local counted=false
            for _,d in ipairs(plant:GetDescendants()) do
                local decay=tonumber(d:GetAttribute("DecayAlpha") or d:GetAttribute("Decay"))
                if decay and decay>0 then counted=true break end
            end
            if counted then n+=1 end
        end
        return n
    end
    local function runtimeStatus(cap)
        if not State.Capabilities[cap] then return "MISSING" end
        local method=State.PacketMethods[cap]
        if State.Verified[cap]==true then
            local sig=State.Signatures[cap]
            return (sig and ("VERIFIED S"..sig) or "VERIFIED") .. (method and (" / "..method) or "")
        end
        if (State.Attempts[cap] or 0)>0 then
            local nextSig=State.NextSignature[cap] or 1
            return "FOUND / TRY S"..tostring(nextSig)..(method and (" / "..method) or "")
        end
        return "FOUND / WAIT"..(method and (" / "..method) or "")
    end

    local bgOn = C("UI","Background") ~= false
    local renderOn=true
    pcall(function()
        renderOn = true
    end)

    local function applyBg()
        main.BackgroundTransparency=bgOn and 0 or 1
        body.BackgroundTransparency=bgOn and 0 or 1
        bgBtn.Text=bgOn and "BG ON" or "BG OFF"
        bgBtn.BackgroundColor3=bgOn and Color3.fromRGB(60,130,80) or Color3.fromRGB(120,50,50)
    end
    local function applyRender()
        pcall(function() RunService:Set3dRenderingEnabled(renderOn) end)
        renderBtn.Text=renderOn and "3D ON" or "3D OFF"
        renderBtn.BackgroundColor3=renderOn and Color3.fromRGB(60,130,80) or Color3.fromRGB(120,50,50)
    end
    if C("General","3D Rendering")==false then renderOn=false end
    applyBg()
    applyRender()

    bgBtn.MouseButton1Click:Connect(function()
        bgOn=not bgOn
        applyBg()
    end)
    renderBtn.MouseButton1Click:Connect(function()
        renderOn=not renderOn
        applyRender()
    end)

    local minimized=false
    local fullSize=main.Size
    minimize.MouseButton1Click:Connect(function()
        minimized=not minimized
        body.Visible=not minimized
        if minimized then
            main.Size=UDim2.fromOffset(620,46)
            minimize.Text="+"
        else
            main.Size=fullSize
            minimize.Text="−"
        end
    end)

    local scale=Instance.new("UIScale",main)
    local function resize()
        local cam=workspace.CurrentCamera
        if not cam then return end
        local vp=cam.ViewportSize
        scale.Scale=math.clamp(math.min(vp.X/700,vp.Y/730),.55,1.15)
    end
    resize()
    if workspace.CurrentCamera then
        workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(resize)
    end

    task.spawn(function()
        while Alive and GUI.Parent do
            local cash,currency=getCurrency()
            local fruit=readyFruitCount()
            local cap=getFruitCapacity()
            local elapsed=os.clock()-State.Started
            local earned=State.Earned
            local rate=elapsed>0 and earned/elapsed or 0

            Labels.Fruit.Text="Fruit: "..fmt(fruit).." / "..(cap and fmt(cap) or "?")
            Labels.Pets.Text="Pets: "..fmt(ownedPetCount()).." / "..fmt(firstNonNil(LP:GetAttribute("PetSlots"),LP:GetAttribute("MaxPets"),C("Pet","Max Slots")))
            Labels.Seeds.Text="Seeds: "..fmt(totalSeedInventory()).." total"
            Labels.Plot.Text="Plot: "..tostring(LP:GetAttribute("PlotId") or "?").." | "..(isFallWorld() and "Fall Harvest" or "Garden Valley")

            Labels.Plants.Text="Plants: "..fmt(totalPlantCount()).." / "..fmt(Config["Max Plant Fruit"])
            Labels.Sprinklers.Text="Sprinklers: "..fmt(countNamedInPlot("Sprinkler"))
            Labels.Decaying.Text="Decaying: "..fmt(countDecaying())

            Labels.Uptime.Text="Uptime: "..fmtTime(elapsed)
            Labels.Earned.Text="Earned: $"..fmt(earned)
            Labels.Rate.Text="Rate: $"..fmt(rate).."/s"
            Labels.Harvested.Text="Harvested: "..fmt(State.Harvested)
            Labels.Planted.Text="Planted: "..fmt(State.Planted)
            Labels.Sold.Text="Sold: "..fmt(State.Sold).." times"
            Labels.SeedBuy.Text="Seeds Bought: "..fmt(State.SeedsBought)
            Labels.GearBuy.Text="Gears Bought: "..fmt(State.GearsBought)
            Labels.CrateBuy.Text="Crates Bought: "..fmt(State.CratesBought)
            Labels.PetTame.Text="Pets Tamed: "..fmt(State.PetsTamed)
            Labels.Drops.Text="Event Drops: "..fmt(State.EventSeeds)

            Labels.DayNight.Text="Day/Night: "..(isNight() and "NIGHT" or "DAY").." | "..(isFallWorld() and "Fall Harvest" or "Garden Valley")
            Labels.Baker.Text="Baker: "..(State.EventStatus.Baker and "ACTIVE" or "OFF")
            Labels.Moon.Text="Harvest Moon: "..(State.EventStatus.HarvestMoon and "ACTIVE" or "OFF")
            Labels.Werewolf.Text="Werewolf: "..(State.EventStatus.Werewolf and "ACTIVE" or "OFF")
            Labels.Cards.Text="Garden Cards: "..fmt(State.CardClaims)

            Labels.Network.Text="Network: "..(State.NetworkReady and "READY" or "FAILED").." | Plot: "..(getPlot() and "READY" or "SEARCHING")
            Labels.Bootstrap.Text="Bootstrap: "..tostring(State.BootstrapStatus or "CHECKING")
            Labels.CodesCap.Text="Codes: "..runtimeStatus("CODES")
            Labels.HarvestCap.Text="Harvest: "..runtimeStatus("HARVEST")
            Labels.PlantCap.Text="Plant: "..runtimeStatus("PLANT")
            Labels.SellCap.Text="Sell: "..runtimeStatus("SELL")
            local sgState = SellGuard.Selling and "SELLING"
                or (isSellUrgent() and "FULL / URGENT" or "READY")
            Labels.SellGuard.Text="Sell Guard: "..sgState
                ..(SellGuard.Reason~="" and (" | "..SellGuard.Reason) or "")
                ..(State.SellFailures>0 and (" | fail "..tostring(State.SellFailures)) or "")
            Labels.SeedShopCap.Text="Buy Seed: "..runtimeStatus("BUY_SEED")
            Labels.GearShopCap.Text="Buy Gear: "..runtimeStatus("BUY_GEAR")
            Labels.CrateShopCap.Text="Buy Crate: "..runtimeStatus("BUY_CRATE")
            Labels.PetCap.Text="Pet: Tame "..runtimeStatus("TAME_PET").." | Equip "..runtimeStatus("EQUIP_PET")
            Labels.PetSlotCap.Text="Pet Slot: "..runtimeStatus("BUY_PET_SLOT")
            local antiStealReady=State.Capabilities["SHOVEL_SWING"] and State.Capabilities["SHOVEL_HIT"]
            Labels.AntiStealCap.Text="Anti Steal: "..(antiStealReady and "FOUND" or "MISSING")
            Labels.MailCap.Text="Mailbox: "..runtimeStatus("MAILBOX")

            Labels.Last.Text="Last: "..tostring(State.LastAction)
            Labels.Error.Text="Error: "..(State.LastError~="" and State.LastError or "none")
            task.wait(.5)
        end
    end)
end

--==============================================================
-- STARTUP DIAGNOSTICS
--==============================================================
task.spawn(function()
    local timeout=os.clock()+30
    while Alive and not getPlot() and os.clock()<timeout do task.wait(.5) end
    if not getPlot() then
        errlog("Plot","Player plot not found after 30s")
    end
    if not State.NetworkReady then
        errlog("Core","Networking unavailable: farming cannot run")
    else
        local missing={}
        for _,n in ipairs({"HARVEST","PLANT","SELL","BUY_SEED","BUY_GEAR","TAME_PET"}) do
            if not State.Capabilities[n] then missing[#missing+1]=n end
        end
        if #missing>0 then
            warn("[OneClick GAG2] Missing current packet adapters: "..table.concat(missing,", "))
            warn("[OneClick GAG2] Enable Config.Debug['Dump Network Paths'] and send console output to map changed packet names.")
        end
    end
    log("Ready | "..BUILD)
end)

LP.CharacterAdded:Connect(function()
    task.wait(1)
    MoveLock.owner=nil
    CachedPlot=nil
    PlantScanCache.At=0
    PlantScanCache.List={}
    PetCache.At=0
    PetCache.Data=nil
    EquippedCache.At=0
    EquippedCache.Data=nil
end)

Controller.Stop=function()
    Alive=false
    MoveLock.owner=nil
    for _,conn in ipairs(FullTextConnections) do
        pcall(function() conn:Disconnect() end)
    end
    table.clear(FullTextConnections)
    pcall(function() RunService:Set3dRenderingEnabled(true) end)
    if GUI then pcall(function() GUI:Destroy() end) end
end

print("[OneClick GAG2] loaded | "..BUILD)

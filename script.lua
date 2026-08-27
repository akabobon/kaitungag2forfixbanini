--[[
    OneclickGAG2 STANDALONE — 2026-08-27
    =====================================
    External config:
        getgenv().Config = { ... }

    This build intentionally does NOT load the old obfuscated OneclickGAG2.
    The goal is one engine only, so no duplicate farm/shop/mail loops compete.

    Publicly grounded runtime contracts used here:
      - ReplicatedStorage.SharedModules.Networking
      - ReplicatedStorage.SharedModules.Packet.RemoteEvent
      - Plant: Networking.Plant.PlantSeed:Fire(hitPos, seedName, tool)
      - Harvest: Networking.Garden.CollectFruit:Fire(plantId, fruitId)
      - Water: Networking.WateringCan.UseWateringCan:Fire(hitPos, canName, tool)
      - Sprinkler: Networking.Place.PlaceSprinkler:Fire(hitPos, sprinklerName, tool, plotId)
      - Sell: Networking.NPCS.SellAll / SellFruit / UseDailyDealAll
      - Mail: Networking.Mailbox.SendBatch:Fire(userId, items, note)
      - Known packet fallbacks are used only where publicly scanner-verified.

    Current event coverage:
      - Fall Harvest standalone world
      - Muffin Bake / Baker event
      - Wheat / Sugar Cane / Sprinkle Sprout
      - Chicken / Sugar Bunny / Chocolate Lab / Fat Cat / Muffin Man
      - Sugar Egg / Goodie Bag / Sugar Crate exchange rewards
      - Fall Maple crops, Syrup gear, Magic Mail, Fall crates
      - Dynamic live shop catalog sync so later item additions can appear without a hardcoded rewrite.
]]

-- ============================================================
-- BUILD / SERVICES
-- ============================================================
local BUILD = "ONECLICK_GAG2_STANDALONE_2026_08_27_V6_CLEAN_CONFIG"

repeat task.wait() until game:IsLoaded()

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local VirtualUser = game:GetService("VirtualUser")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")

local LocalPlayer = Players.LocalPlayer
local ENV = (getgenv and getgenv()) or _G

-- ============================================================
-- SESSION GUARD
-- ============================================================
ENV.__ONECLICK_GAG2_SESSION = (ENV.__ONECLICK_GAG2_SESSION or 0) + 1
local SESSION = ENV.__ONECLICK_GAG2_SESSION

local function Alive()
    return ENV.__ONECLICK_GAG2_SESSION == SESSION
end

-- ============================================================
-- CONFIG
-- ============================================================
local Config = ENV.Config
if type(Config) ~= "table" then
    -- Backward compatibility with older personal configs.
    Config = ENV.UserConfig or ENV.GAG2
end
if type(Config) ~= "table" then
    error("[OneclickGAG2] Missing getgenv().Config. Load the external config first.")
end

ENV.Config = Config

-- ============================================================
-- GROUPED CONFIG ADAPTER (V4)
-- Keeps the external config compact by grouping related features.
-- Internally converts grouped settings back to the engine's V3 layout.
-- ============================================================
local function _cfgTable(parent, key)
    if type(parent) ~= "table" then return nil end
    local value = parent[key]
    return type(value) == "table" and value or nil
end

local function _ensureCfgTable(parent, key)
    local value = parent[key]
    if type(value) ~= "table" then
        value = {}
        parent[key] = value
    end
    return value
end

local function _copyScalar(dst, src, key)
    if type(src) == "table" and src[key] ~= nil then
        dst[key] = src[key]
    end
end

local function _mergeBoolMap(dst, src)
    if type(dst) ~= "table" or type(src) ~= "table" then return end
    for key, value in pairs(src) do
        if type(value) == "boolean" then
            dst[key] = value
        end
    end
end

local GeneralGroup = _cfgTable(Config, "General")
if GeneralGroup then
    _copyScalar(Config, GeneralGroup, "Max Plant Fruit")
    _copyScalar(Config, GeneralGroup, "Buy Expand Plot")
    _copyScalar(Config, GeneralGroup, "Buy Slot Pet")
    if GeneralGroup["UpgradeCheckDelay"] ~= nil then
        Config["Upgrade Check Delay"] = GeneralGroup["UpgradeCheckDelay"]
    end
end

local FarmGroup = _cfgTable(Config, "Farm")
if FarmGroup then
    local plantGroup = _cfgTable(FarmGroup, "Plant")
    if plantGroup then
        local target = _ensureCfgTable(Config, "Plant Seed")
        _copyScalar(target, plantGroup, "Enable")
        _copyScalar(target, plantGroup, "CycleDelay")
        _copyScalar(target, plantGroup, "PerSeedDelay")
        _copyScalar(target, plantGroup, "MaxPerCycle")
        local seedMap = _ensureCfgTable(target, "Seed")
        _mergeBoolMap(seedMap, _cfgTable(plantGroup, "Main"))
        _mergeBoolMap(seedMap, _cfgTable(plantGroup, "Main Shop"))
        _mergeBoolMap(seedMap, _cfgTable(plantGroup, "Fall Harvest"))
        _mergeBoolMap(seedMap, _cfgTable(plantGroup, "Muffin Bake"))
        _mergeBoolMap(seedMap, _cfgTable(plantGroup, "Special / Limited"))
        _mergeBoolMap(seedMap, _cfgTable(plantGroup, "Seed"))
    end

    local harvestGroup = _cfgTable(FarmGroup, "Harvest")
    if harvestGroup then
        Config["Auto Harvest"] = harvestGroup
    end

    local waterGroup = _cfgTable(FarmGroup, "Water")
    if waterGroup then
        Config["Auto Water"] = waterGroup
    end

    local sprinklerGroup = _cfgTable(FarmGroup, "Sprinkler")
    if sprinklerGroup then
        Config["Auto Sprinkler"] = sprinklerGroup
    end

    local sellGroup = _cfgTable(FarmGroup, "Sell")
    if sellGroup then
        -- One Sell block is intentionally shared by Main + Fall Harvest.
        Config["Auto Sell"] = sellGroup
    end

    local collectSeedPackGroup = _cfgTable(FarmGroup, "Collect Seed Packs")
    if collectSeedPackGroup then
        Config["Collect Seed Packs"] = collectSeedPackGroup
    end
end

local fallTarget = _ensureCfgTable(Config, "Fall Harvest")

local ShopGroup = _cfgTable(Config, "Shop")
if ShopGroup then
    if ShopGroup["CycleDelay"] ~= nil then
        Config["Shop Cycle Delay"] = ShopGroup["CycleDelay"]
    end
    if ShopGroup["StockSyncDelay"] ~= nil then
        Config["Shop Stock Sync Delay"] = ShopGroup["StockSyncDelay"]
    end

    local seedShop = _cfgTable(ShopGroup, "Seed")
    if seedShop then
        local target = _ensureCfgTable(Config, "Buy Seed")
        _copyScalar(target, seedShop, "All Current Stock")
        _copyScalar(target, seedShop, "QuantityPerCycle")
        _copyScalar(target, seedShop, "PerItemDelay")
        local worlds = _cfgTable(seedShop, "World")
        if worlds then
            if worlds["Main"] ~= nil then target["Enable"] = worlds["Main"] end
            if worlds["Fall Harvest"] ~= nil then
                fallTarget["Auto Buy Seed"] = worlds["Fall Harvest"]
            end
        else
            _copyScalar(target, seedShop, "Enable")
        end
        local itemMap = _ensureCfgTable(target, "Seed")
        _mergeBoolMap(itemMap, _cfgTable(seedShop, "Main"))
        _mergeBoolMap(itemMap, _cfgTable(seedShop, "Main Shop"))
        _mergeBoolMap(itemMap, _cfgTable(seedShop, "Fall Harvest"))
        _mergeBoolMap(itemMap, _cfgTable(seedShop, "Muffin Bake"))
        _mergeBoolMap(itemMap, _cfgTable(seedShop, "Special / Limited"))
        _mergeBoolMap(itemMap, _cfgTable(seedShop, "Seed"))
    end

    local gearShop = _cfgTable(ShopGroup, "Gear")
    if gearShop then
        local target = _ensureCfgTable(Config, "Buy Gear")
        _copyScalar(target, gearShop, "All Current Stock")
        _copyScalar(target, gearShop, "QuantityPerCycle")
        _copyScalar(target, gearShop, "PerItemDelay")
        local worlds = _cfgTable(gearShop, "World")
        if worlds then
            if worlds["Main"] ~= nil then target["Enable"] = worlds["Main"] end
            if worlds["Fall Harvest"] ~= nil then
                fallTarget["Auto Buy Gear"] = worlds["Fall Harvest"]
            end
        else
            _copyScalar(target, gearShop, "Enable")
        end
        local itemMap = _ensureCfgTable(target, "Gear")
        _mergeBoolMap(itemMap, _cfgTable(gearShop, "Main"))
        _mergeBoolMap(itemMap, _cfgTable(gearShop, "Main Shop"))
        _mergeBoolMap(itemMap, _cfgTable(gearShop, "Fall Harvest"))
        _mergeBoolMap(itemMap, _cfgTable(gearShop, "Other / Exclusive"))
        _mergeBoolMap(itemMap, _cfgTable(gearShop, "Gear"))
    end

    local crateShop = _cfgTable(ShopGroup, "Crate")
    if crateShop then
        local target = _ensureCfgTable(Config, "Buy Crate")
        _copyScalar(target, crateShop, "All Current Stock")
        _copyScalar(target, crateShop, "QuantityPerCycle")
        _copyScalar(target, crateShop, "PerItemDelay")
        local worlds = _cfgTable(crateShop, "World")
        if worlds then
            if worlds["Main"] ~= nil then target["Enable"] = worlds["Main"] end
            if worlds["Fall Harvest"] ~= nil then
                fallTarget["Auto Buy Crate"] = worlds["Fall Harvest"]
            end
        else
            _copyScalar(target, crateShop, "Enable")
        end
        local itemMap = _ensureCfgTable(target, "Crate")
        _mergeBoolMap(itemMap, _cfgTable(crateShop, "Main"))
        _mergeBoolMap(itemMap, _cfgTable(crateShop, "Main Shop"))
        _mergeBoolMap(itemMap, _cfgTable(crateShop, "Fall Harvest"))
        _mergeBoolMap(itemMap, _cfgTable(crateShop, "Crate"))

        if crateShop["Auto Open"] ~= nil then
            local autoCrate = _ensureCfgTable(Config, "Auto Crate")
            autoCrate["Open"] = crateShop["Auto Open"]
        end

        local crateOpen = _cfgTable(crateShop, "Open")
        if crateOpen then
            local autoCrate = _ensureCfgTable(Config, "Auto Crate")
            if crateOpen["Enable"] ~= nil then autoCrate["Open"] = crateOpen["Enable"] end
            _copyScalar(autoCrate, crateOpen, "Delay")
            local openMap = _ensureCfgTable(autoCrate, "Crate")
            _mergeBoolMap(openMap, _cfgTable(crateOpen, "Main"))
            _mergeBoolMap(openMap, _cfgTable(crateOpen, "Main Shop"))
            _mergeBoolMap(openMap, _cfgTable(crateOpen, "Fall Harvest"))
            _mergeBoolMap(openMap, _cfgTable(crateOpen, "Muffin Bake"))
            _mergeBoolMap(openMap, _cfgTable(crateOpen, "Event Rewards"))
            _mergeBoolMap(openMap, _cfgTable(crateOpen, "Crate"))
        end
    end
end

local PetGroup = _cfgTable(Config, "Pet")
if PetGroup then
    if PetGroup["Auto Open Egg"] ~= nil then
        local autoEgg = _ensureCfgTable(Config, "Auto Egg")
        autoEgg["Open"] = PetGroup["Auto Open Egg"]
    end

    local eggGroup = _cfgTable(PetGroup, "Egg")
    if eggGroup then
        local autoEgg = _ensureCfgTable(Config, "Auto Egg")
        if eggGroup["Enable"] ~= nil then autoEgg["Open"] = eggGroup["Enable"] end
        _copyScalar(autoEgg, eggGroup, "Delay")
        local eggMap = _ensureCfgTable(autoEgg, "Egg")
        _mergeBoolMap(eggMap, _cfgTable(eggGroup, "Main"))
        _mergeBoolMap(eggMap, _cfgTable(eggGroup, "Fall Harvest"))
        _mergeBoolMap(eggMap, _cfgTable(eggGroup, "Muffin Bake"))
        _mergeBoolMap(eggMap, _cfgTable(eggGroup, "Egg"))
    end
end

local EventsGroup = _cfgTable(Config, "Events")
if EventsGroup then
    local fallEvent = _cfgTable(EventsGroup, "Fall Harvest")
    if fallEvent then
        _copyScalar(fallTarget, fallEvent, "Enable")
        local magic = _cfgTable(fallEvent, "Magic Mail")
        if magic then
            fallTarget["Magic Mail"] = magic
        end
    end

    local muffinEvent = _cfgTable(EventsGroup, "Muffin Bake")
    if muffinEvent then
        Config["Muffin Bake"] = muffinEvent
    end
end

local function EnsureTable(parent, key)
    local value = parent[key]
    if type(value) ~= "table" then
        value = {}
        parent[key] = value
    end
    return value
end

local function SetDefault(tbl, key, value)
    if tbl[key] == nil then
        tbl[key] = value
    end
end

local function Normalize(text)
    return tostring(text or "")
        :lower()
        :gsub("[%s_%-%.'\"%(%)]", "")
        :gsub("[^%w]", "")
end

local function Contains(text, needle)
    local a = Normalize(text)
    local b = Normalize(needle)
    return b ~= "" and string.find(a, b, 1, true) ~= nil
end

local function MapEnabled(map, name)
    if type(map) ~= "table" then
        return false
    end
    if map[name] ~= nil then
        return map[name] == true
    end
    local target = Normalize(name)
    for key, value in pairs(map) do
        if value == true and Normalize(key) == target then
            return true
        end
    end
    return false
end

local function AnyEnabled(map)
    if type(map) ~= "table" then return false end
    for _, enabled in pairs(map) do
        if enabled == true then return true end
    end
    return false
end

local function AddMissing(map, names, default)
    if type(map) ~= "table" then
        return
    end
    for _, name in ipairs(names) do
        if map[name] == nil then
            map[name] = default
        end
    end
end

local function Log(...)
    pcall(function()
        print("[OneclickGAG2]", ...)
    end)
end

local function DebugLog(...)
    local utility = Config["Utility"]
    if type(utility) == "table" and utility["Debug"] == true then
        Log(...)
    end
end

-- ============================================================
-- CURRENT CATALOGS
-- ============================================================
local MAIN_SEEDS = {
    "Carrot", "Strawberry", "Blueberry", "Tulip", "Tomato", "Apple", "Bamboo",
    "Corn", "Cactus", "Pineapple", "Mushroom", "Green Bean", "Banana", "Grape",
    "Coconut", "Mango", "Dragon Fruit", "Acorn", "Cherry", "Sunflower",
    "Fire Fern", "Venus Fly Trap", "Pomegranate", "Poison Apple", "Venom Spitter",
    "Moon Bloom", "Sun Bloom", "Dragon's Breath", "Star Fruit", "Hypnobloom",
}

local FALL_SEEDS = {
    "Maple Carrot", "Maple Strawberry", "Maple Blueberry", "Maple Tulip",
    "Maple Tomato", "Maple Apple", "Maple Bamboo", "Maple Corn", "Maple Cactus",
    "Maple Pineapple", "Maple Mushroom", "Maple Green Bean", "Maple Banana",
    "Maple Grape", "Maple Coconut", "Maple Mango", "Maple Dragon Fruit",
    "Maple Acorn", "Maple Cherry", "Maple Sunflower", "Maple Venus Fly Trap",
    "Maple Pomegranate", "Maple Poison Apple", "Maple Venom Spitter",
    "Potato", "Honeysuckle", "Jandel's Beanstalk", "Peach", "Amber Cranberry",
    "Conifer Cone Sapling",
}

local LIMITED_OR_UNCERTAIN_SEEDS = {
    -- Gacha / special / limited / inventory-only candidates.
    "Baby Cactus", "Horned Melon", "Glow Mushroom", "Poison Ivy", "Ghost Pepper",
    "Rocket Pop",
    "Gold", "Gold Seed",
    "Rainbow", "Rainbow Seed",
    "Mega", "Mega Seed",

    -- Fall packs / special crops that may not appear in the ordinary SeedShop.
    "Romanesco", "Plum", "Cinnamon Stick", "Conifer Cone",
    "Atlantic Giant Pumpkin",
}

local MUFFIN_SEEDS = {
    "Wheat", "Sugar Cane", "Sprinkle Sprout",
}

local MAIN_GEARS = {
    "Common Watering Can", "Super Watering Can",
    "Common Sprinkler", "Uncommon Sprinkler", "Rare Sprinkler",
    "Legendary Sprinkler", "Super Sprinkler",
    "Sign", "Megaphone", "Wheelbarrow", "Strawberry Sniper", "Trowel",
    "Speed Mushroom", "Jump Mushroom", "Shrink Mushroom", "Supersize Mushroom",
    "Invisibility Mushroom", "Gnome", "Teleporter", "Basic Pot", "Flashbang",
    "Player Magnet", "Grappling Hook", "Legendary Pet Teleporter",
    "Mythic Pet Teleporter", "Super Pet Teleporter",
}

local FALL_GEARS = {
    "Syrup Sprinkler", "Super Syrup Sprinkler",
    "Syrup Watering Can", "Super Syrup Watering Can",
    "Rare Magic Mail", "Legendary Magic Mail", "Super Magic Mail",
}

local LIMITED_OR_UNCERTAIN_GEARS = {
    -- Robux / special / datamined / limited items kept opt-in.
    "Power Hose", "Freeze Ray", "Rainbow Carpet", "Vine Wrapper",
    "Door Crowbar", "Lantern", "Rake", "Crowbar", "Shovel", "Build",
    "Harp", "Wind Staff", "Bull Horn", "Insta-Bake",
}

local MUFFIN_OUTPUTS = {
    "Blueberry Muffin", "Pumpkin Muffin", "Carrot Muffin", "Rainbow Muffin",
}

local ALL_PETS = {
    -- Main / current map pool and special pets
    "Bunny", "Frog", "Owl", "Deer", "Turtle", "Robin", "Bee", "Butterfly",
    "Monkey", "Golden Dragonfly", "Unicorn", "Bear", "Bald Eagle", "Firefly",
    "Raccoon", "Ice Serpent", "Black Dragon",

    -- Fall Harvest
    "Dog", "Turkey", "Hedgehog", "Squirrel", "Swan", "Wolf", "Fox",
    "Shadow Dragon", "Jandel Monkey",

    -- Other August / limited names retained as opt-in catalog entries
    "Scarecrow", "Jackalope", "Red Panda", "Kitsune",

    -- Muffin Bake
    "Chicken", "Sugar Bunny", "Chocolate Lab", "Fat Cat", "Muffin Man",
}

local PET_ALIASES = {
    ["Ice Serpent"] = "IceSerpent",
    ["Golden Dragonfly"] = "GoldenDragonfly",
    ["Black Dragon"] = "BlackDragon",
    ["Shadow Dragon"] = "ShadowDragon",
    ["Jandel Monkey"] = "JandelMonkey",
    ["Sugar Bunny"] = "SugarBunny",
    ["Chocolate Lab"] = "ChocolateLab",
    ["Fat Cat"] = "FatCat",
    ["Muffin Man"] = "MuffinMan",
    ["Red Panda"] = "RedPanda",
}

local MAIN_CRATES = {
    "Arch Crate", "Bear Trap Crate", "Bench Crate", "Bridge Crate",
    "Conveyor Crate", "Fence Crate", "Ladder Crate", "Light Crate",
    "Owner Door Crate", "Picture Frame Crate", "Roleplay Crate",
    "Seesaw Crate", "Sign Crate", "Spring Crate", "Teleporter Pad Crate",
}

-- Public game-data source lists these as Fall shop crates.
local FALL_BUYABLE_CRATES = {
    "Lantern Crate", "Fall Cosmetic Crate", "Cobblestone Crate",
    "Fall Structure Crate", "Rake Crate",
}

-- Rewards / special acquisition; do not treat as shop-buy targets.
local EVENT_REWARD_ITEMS = {
    "Cornucopia", "Admin Chest", "Goodie Bag", "Sugar Crate", "Sugar Egg",
}

local MAIN_EGGS = {
    "Common Egg", "Big Egg", "Mega Egg", "Rainbow Egg",
}

local FALL_EGGS = {
    "Fall Common Egg", "Fall Big Egg", "Fall Mega Egg", "Fall Rainbow Egg",
}

local MUFFIN_EGGS = {
    "Sugar Egg",
}

local SEED_PACKS = {
    "Common Seed Pack", "Uncommon Seed Pack", "Rare Seed Pack", "Epic Seed Pack",
    "Legendary Seed Pack", "Mythic Seed Pack", "Secret Seed Pack",
    "Fall Common Seed Pack", "Fall Uncommon Seed Pack", "Fall Rare Seed Pack",
    "Fall Epic Seed Pack", "Fall Legendary Seed Pack", "Fall Mythic Seed Pack",
    "Fall Secret Seed Pack", "Harvest Seed Pack",
}

local MUFFIN_PETS = {
    "Chicken", "Sugar Bunny", "Chocolate Lab", "Fat Cat", "Muffin Man",
}

local ACTIVE_CODE_CANDIDATES = {
    "FREESEED",
    "WATERYOPLANTS",
    "REMEMBERTODRINKWATER",
    "TEAMGREENBEAN",
}

local FALL_HARVEST_PLACE_IDS = {
    [126987765280960] = true,
}

local MUFFIN_EXCHANGE = {
    ["Blueberry Muffin"] = {
        Cost = 3,
        Rewards = {["Goodie Bag"] = 3},
    },
    ["Pumpkin Muffin"] = {
        Cost = 4,
        Rewards = {["Sugar Egg"] = 2},
    },
    ["Carrot Muffin"] = {
        Cost = 3,
        Rewards = {["Sugar Crate"] = 3},
    },
    ["Rainbow Muffin"] = {
        Cost = 1,
        Rewards = {
            ["Sugar Egg"] = 9,
            ["Goodie Bag"] = 9,
            ["Sugar Crate"] = 9,
        },
    },
}

-- ============================================================
-- CONFIG NORMALIZATION
-- ============================================================
SetDefault(Config, "Max Plant Fruit", 200)
if Config["Buy Expand Plot"] == nil then Config["Buy Expand Plot"] = true end
if Config["Buy Slot Pet"] == nil then Config["Buy Slot Pet"] = true end

local PetCfg = EnsureTable(Config, "Pet")
local PetBuyCfg = EnsureTable(PetCfg, "Auto Buy")
SetDefault(PetBuyCfg, "Enable", true)
SetDefault(PetBuyCfg, "Delay", 1.2)
SetDefault(PetBuyCfg, "InteractDelay", 0.25)
local PetBuyMap = EnsureTable(PetBuyCfg, "Pet")
local PetFinderCfg = EnsureTable(PetCfg, "Finder")
SetDefault(PetFinderCfg, "Enable", false)
SetDefault(PetFinderCfg, "Move To Pet", false)
SetDefault(PetFinderCfg, "Delay", 1.5)
SetDefault(PetFinderCfg, "InteractDelay", 0.25)
local PetFinderMap = EnsureTable(PetFinderCfg, "Pet")

local MailCfg = EnsureTable(Config, "Mail")
SetDefault(MailCfg, "Enable", false)
SetDefault(MailCfg, "Username", "")
SetDefault(MailCfg, "Note", "auto-shipped from main")
SetDefault(MailCfg, "IntervalSec", 2.0)
SetDefault(MailCfg, "BatchSize", 20)
SetDefault(MailCfg, "Stop When Empty", true)
local MailPet = EnsureTable(MailCfg, "Pet")
local MailSeed = EnsureTable(MailCfg, "Seed")
local MailGear = EnsureTable(MailCfg, "Gear")
local MailCrate = EnsureTable(MailCfg, "Crate")
local MailSeedPack = EnsureTable(MailCfg, "Seed Pack")
local MailFruit = EnsureTable(MailCfg, "Fruit")

local PlantCfg = EnsureTable(Config, "Plant Seed")
SetDefault(PlantCfg, "Enable", true)
SetDefault(PlantCfg, "CycleDelay", 0.6)
SetDefault(PlantCfg, "PerSeedDelay", 0.25)
SetDefault(PlantCfg, "MaxPerCycle", 40)
local PlantMap = EnsureTable(PlantCfg, "Seed")

local BuySeedCfg = EnsureTable(Config, "Buy Seed")
SetDefault(BuySeedCfg, "Enable", true)
SetDefault(BuySeedCfg, "All Current Stock", false)
SetDefault(BuySeedCfg, "QuantityPerCycle", 1)
SetDefault(BuySeedCfg, "PerItemDelay", 0.06)
local BuySeedMap = EnsureTable(BuySeedCfg, "Seed")

local BuyGearCfg = EnsureTable(Config, "Buy Gear")
SetDefault(BuyGearCfg, "Enable", false)
SetDefault(BuyGearCfg, "All Current Stock", false)
SetDefault(BuyGearCfg, "QuantityPerCycle", 1)
SetDefault(BuyGearCfg, "PerItemDelay", 0.06)
local BuyGearMap = EnsureTable(BuyGearCfg, "Gear")

local BuyCrateCfg = EnsureTable(Config, "Buy Crate")
SetDefault(BuyCrateCfg, "Enable", false)
SetDefault(BuyCrateCfg, "All Current Stock", false)
SetDefault(BuyCrateCfg, "QuantityPerCycle", 1)
SetDefault(BuyCrateCfg, "PerItemDelay", 0.06)
local BuyCrateMap = EnsureTable(BuyCrateCfg, "Crate")

local WaterCfg = EnsureTable(Config, "Auto Water")
SetDefault(WaterCfg, "Enable", false)
SetDefault(WaterCfg, "Delay", 4.0)
SetDefault(WaterCfg, "PerPlantDelay", 0.08)
local WaterTools = EnsureTable(WaterCfg, "Tools")

local SprinklerCfg = EnsureTable(Config, "Auto Sprinkler")
SetDefault(SprinklerCfg, "Enable", false)
SetDefault(SprinklerCfg, "Delay", 15.0)
SetDefault(SprinklerCfg, "PerPlacementDelay", 0.7)
SetDefault(SprinklerCfg, "MaxPerCycle", 3)
SetDefault(SprinklerCfg, "TargetCoverage", 0.95)
local SprinklerTools = EnsureTable(SprinklerCfg, "Tools")

local HarvestCfg = EnsureTable(Config, "Auto Harvest")
SetDefault(HarvestCfg, "Enable", false)
SetDefault(HarvestCfg, "Delay", 1.0)
SetDefault(HarvestCfg, "PerFruitDelay", 0.04)
SetDefault(HarvestCfg, "MaxPerCycle", 200)
local HarvestSkipMutation = EnsureTable(HarvestCfg, "Skip Mutation")

local SellCfg = EnsureTable(Config, "Auto Sell")
SetDefault(SellCfg, "Enable", false)
SetDefault(SellCfg, "Delay", 3.0)
SetDefault(SellCfg, "Use Daily Deal", false)
SetDefault(SellCfg, "Keep Mutated", true)
SetDefault(SellCfg, "PerFruitDelay", 0.05)

local AutoCrateCfg = EnsureTable(Config, "Auto Crate")
SetDefault(AutoCrateCfg, "Open", false)
SetDefault(AutoCrateCfg, "Delay", 8.0)
local AutoCrateMap = EnsureTable(AutoCrateCfg, "Crate")

local AutoEggCfg = EnsureTable(Config, "Auto Egg")
SetDefault(AutoEggCfg, "Open", false)
SetDefault(AutoEggCfg, "Delay", 5.0)
local AutoEggMap = EnsureTable(AutoEggCfg, "Egg")

local FallCfg = EnsureTable(Config, "Fall Harvest")
SetDefault(FallCfg, "Enable", true)
SetDefault(FallCfg, "Auto Buy Seed", false)
SetDefault(FallCfg, "Auto Buy Gear", false)
SetDefault(FallCfg, "Auto Buy Crate", false)

local MagicMailCfg = EnsureTable(FallCfg, "Magic Mail")
SetDefault(MagicMailCfg, "Auto Use", false)
SetDefault(MagicMailCfg, "Delay", 5.0)
local MagicMailTools = EnsureTable(MagicMailCfg, "Tools")

local MuffinCfg = EnsureTable(Config, "Muffin Bake")
SetDefault(MuffinCfg, "Enable", true)
SetDefault(MuffinCfg, "Auto Buy Ingredients", false)
SetDefault(MuffinCfg, "Auto Claim Ready Oven", false)
SetDefault(MuffinCfg, "Auto Baker Prompt", false)
SetDefault(MuffinCfg, "Auto Exchange Prompt", false)
SetDefault(MuffinCfg, "IngredientBuyDelay", 0.08)
SetDefault(MuffinCfg, "PromptDelay", 2.0)
local MuffinIngredient = EnsureTable(MuffinCfg, "Ingredient")
local MuffinReward = EnsureTable(MuffinCfg, "Reward")

local CollectSeedPackCfg = EnsureTable(Config, "Collect Seed Packs")
SetDefault(CollectSeedPackCfg, "Enable", false)
SetDefault(CollectSeedPackCfg, "Delay", 0.5)
SetDefault(CollectSeedPackCfg, "PerItemDelay", 0.08)
SetDefault(CollectSeedPackCfg, "Move To Drop", false)
SetDefault(CollectSeedPackCfg, "MaxPerCycle", 30)
local CollectSeedPackBlacklist = EnsureTable(CollectSeedPackCfg, "Blacklist")

SetDefault(Config, "Shop Cycle Delay", 0.8)
SetDefault(Config, "Shop Stock Sync Delay", 15.0)
SetDefault(Config, "Upgrade Check Delay", 5.0)

local UtilityCfg = EnsureTable(Config, "Utility")
SetDefault(UtilityCfg, "Anti AFK", true)
SetDefault(UtilityCfg, "Auto Accept Gifts", false)
SetDefault(UtilityCfg, "Full Bright", false)
SetDefault(UtilityCfg, "No Fog", false)
SetDefault(UtilityCfg, "Auto Rejoin On Teleport Fail", false)
SetDefault(UtilityCfg, "Auto Redeem Codes", true)
SetDefault(UtilityCfg, "Show Status HUD", false)
SetDefault(UtilityCfg, "FPS Cap", 0)
SetDefault(UtilityCfg, "RAM Guard MB", 0)
SetDefault(UtilityCfg, "Debug", false)
local UtilityCodes = EnsureTable(UtilityCfg, "Codes")

local DynamicCfg = EnsureTable(Config, "Dynamic Catalog")
SetDefault(DynamicCfg, "Enable", true)
SetDefault(DynamicCfg, "Sync Seed Shop", true)
SetDefault(DynamicCfg, "Sync Gear Shop", true)
SetDefault(DynamicCfg, "Sync Crate Shop", true)

local WebhookCfg = EnsureTable(Config, "Webhook")
SetDefault(WebhookCfg, "Enable", false)
SetDefault(WebhookCfg, "URL", "")
SetDefault(WebhookCfg, "Username", "OneClick GAG2")

AddMissing(PlantMap, MAIN_SEEDS, true)
AddMissing(BuySeedMap, MAIN_SEEDS, true)
AddMissing(PlantMap, FALL_SEEDS, false)
AddMissing(BuySeedMap, FALL_SEEDS, false)
AddMissing(PlantMap, MUFFIN_SEEDS, false)
AddMissing(BuySeedMap, MUFFIN_SEEDS, false)
AddMissing(PlantMap, LIMITED_OR_UNCERTAIN_SEEDS, false)
AddMissing(BuySeedMap, LIMITED_OR_UNCERTAIN_SEEDS, false)

AddMissing(BuyGearMap, MAIN_GEARS, true)
AddMissing(BuyGearMap, FALL_GEARS, false)
AddMissing(BuyGearMap, LIMITED_OR_UNCERTAIN_GEARS, false)

AddMissing(BuyCrateMap, MAIN_CRATES, false)
AddMissing(BuyCrateMap, FALL_BUYABLE_CRATES, false)

AddMissing(AutoCrateMap, MAIN_CRATES, false)
AddMissing(AutoCrateMap, FALL_BUYABLE_CRATES, false)
AddMissing(AutoCrateMap, EVENT_REWARD_ITEMS, false)

AddMissing(AutoEggMap, MAIN_EGGS, false)
AddMissing(AutoEggMap, FALL_EGGS, false)
AddMissing(AutoEggMap, MUFFIN_EGGS, false)

AddMissing(PetBuyMap, ALL_PETS, false)
AddMissing(PetFinderMap, ALL_PETS, false)
AddMissing(MailPet, ALL_PETS, false)
AddMissing(MailSeed, MAIN_SEEDS, false)
AddMissing(MailSeed, FALL_SEEDS, false)
AddMissing(MailSeed, MUFFIN_SEEDS, false)
AddMissing(MailSeed, LIMITED_OR_UNCERTAIN_SEEDS, false)
AddMissing(MailGear, MAIN_GEARS, false)
AddMissing(MailGear, FALL_GEARS, false)
AddMissing(MailGear, LIMITED_OR_UNCERTAIN_GEARS, false)
AddMissing(MailCrate, MAIN_CRATES, false)
AddMissing(MailCrate, FALL_BUYABLE_CRATES, false)
AddMissing(MailCrate, EVENT_REWARD_ITEMS, false)

AddMissing(MailFruit, MAIN_SEEDS, false)
AddMissing(MailFruit, FALL_SEEDS, false)
AddMissing(MailFruit, MUFFIN_SEEDS, false)
AddMissing(MailFruit, LIMITED_OR_UNCERTAIN_SEEDS, false)
AddMissing(MailSeedPack, SEED_PACKS, false)

AddMissing(WaterTools, {
    "Common Watering Can", "Super Watering Can",
    "Syrup Watering Can", "Super Syrup Watering Can",
}, true)
AddMissing(SprinklerTools, {
    "Common Sprinkler", "Uncommon Sprinkler", "Rare Sprinkler",
    "Legendary Sprinkler", "Super Sprinkler",
    "Syrup Sprinkler", "Super Syrup Sprinkler",
}, true)
AddMissing(MagicMailTools, {
    "Rare Magic Mail", "Legendary Magic Mail", "Super Magic Mail",
}, true)
if MuffinIngredient["Wheat"] == nil then MuffinIngredient["Wheat"] = true end
if MuffinIngredient["Sugar Cane"] == nil then MuffinIngredient["Sugar Cane"] = true end
if MuffinIngredient["Chicken"] == nil then MuffinIngredient["Chicken"] = false end
AddMissing(MuffinIngredient, {"Wheat", "Sugar Cane", "Chicken"}, false)
AddMissing(MuffinReward, {"Goodie Bag", "Sugar Crate", "Sugar Egg"}, true)
AddMissing(UtilityCodes, ACTIVE_CODE_CANDIDATES, true)

-- ============================================================
-- PLAYER / CHARACTER HELPERS
-- ============================================================
local function Character()
    return LocalPlayer.Character
end

local function Humanoid()
    local char = Character()
    return char and char:FindFirstChildOfClass("Humanoid")
end

local function Root()
    local char = Character()
    return char and char:FindFirstChild("HumanoidRootPart")
end

local function EquipTool(tool)
    if not tool or not tool.Parent then
        return false
    end
    local char = Character()
    local hum = Humanoid()
    if not char or not hum then
        return false
    end
    if tool.Parent == char then
        return true
    end
    local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
    if tool.Parent ~= backpack then
        return false
    end
    local ok = pcall(function()
        hum:EquipTool(tool)
    end)
    task.wait(0.12)
    return ok and tool.Parent == char
end

local function ToolContainers()
    local result = {}
    local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
    local char = Character()
    if backpack then table.insert(result, backpack) end
    if char then table.insert(result, char) end
    return result
end

-- ============================================================
-- NETWORKING / PACKET
-- ============================================================
local Networking = nil
local PacketRemote = nil

local PACKET = {
    PlantSeed = 9,
    PlaceSprinkler = 20,
    PurchaseSeed = 120,
    PurchaseCrate = 122,
    EquipGear = 126, -- known as equip; intentionally NOT used as purchase fallback
    OpenCrate = 130,
    OpenEgg = 139,
    ReplicateOpenEgg = 140,
    SellFruit = 167,
    LikeGarden = 221,
    MailboxClaim = 281,
}

local function RefreshNetworking()
    if Networking then
        return Networking
    end
    pcall(function()
        local shared = ReplicatedStorage:FindFirstChild("SharedModules")
        local mod = shared and shared:FindFirstChild("Networking")
        if mod then
            Networking = require(mod)
        end
    end)
    return Networking
end

local function RefreshPacket()
    if PacketRemote and PacketRemote.Parent then
        return PacketRemote
    end
    local shared = ReplicatedStorage:FindFirstChild("SharedModules")
    local packet = shared and shared:FindFirstChild("Packet")
    PacketRemote = packet and packet:FindFirstChild("RemoteEvent")
    return PacketRemote
end

local function PacketFire(id, ...)
    local remote = RefreshPacket()
    if not remote then
        return false
    end
    return pcall(function()
        remote:FireServer(id, ...)
    end)
end

local function ReadPath(root, path)
    local node = root
    for part in string.gmatch(path, "[^%.]+") do
        if type(node) ~= "table" then
            return nil
        end
        local ok, value = pcall(function()
            return rawget(node, part) or node[part]
        end)
        if not ok or value == nil then
            return nil
        end
        node = value
    end
    return node
end

local function FireEndpoint(endpoint, ...)
    if type(endpoint) ~= "table" then
        return false, nil, nil, nil
    end

    local fire = rawget(endpoint, "Fire")
    if type(fire) == "function" then
        local ok, a, b, c = pcall(fire, endpoint, ...)
        return ok, a, b, c
    end

    local invoke = rawget(endpoint, "Invoke")
    if type(invoke) == "function" then
        local ok, a, b, c = pcall(invoke, endpoint, ...)
        return ok, a, b, c
    end

    return false, nil, nil, nil
end

local function TryPaths(paths, ...)
    local net = RefreshNetworking()
    if type(net) ~= "table" then
        return false, nil
    end

    for _, path in ipairs(paths) do
        local endpoint = ReadPath(net, path)
        if endpoint then
            local ok = FireEndpoint(endpoint, ...)
            if ok then
                return true, path
            end
        end
    end

    return false, nil
end

local function DynamicPurchase(sectionHints, itemName, quantity)
    quantity = quantity or 1
    local net = RefreshNetworking()
    if type(net) ~= "table" then
        return false, nil
    end

    for sectionName, section in pairs(net) do
        if type(section) == "table" then
            local sectionMatches = false
            for _, hint in ipairs(sectionHints) do
                if Contains(sectionName, hint) then
                    sectionMatches = true
                    break
                end
            end

            if sectionMatches then
                for endpointName, endpoint in pairs(section) do
                    local n = Normalize(endpointName)
                    if string.find(n, "purchase", 1, true)
                        or string.find(n, "buy", 1, true) then
                        local ok = FireEndpoint(endpoint, itemName, quantity)
                        if ok then
                            return true, tostring(sectionName) .. "." .. tostring(endpointName)
                        end
                    end
                end
            end
        end
    end

    return false, nil
end

local function DynamicRedeem(code)
    local net = RefreshNetworking()
    if type(net) ~= "table" then
        return false, nil
    end

    for sectionName, section in pairs(net) do
        if type(section) == "table" and Contains(sectionName, "code") then
            for endpointName, endpoint in pairs(section) do
                local n = Normalize(endpointName)
                if string.find(n, "redeem", 1, true)
                    or string.find(n, "claim", 1, true) then
                    local ok = FireEndpoint(endpoint, code)
                    if ok then
                        return true, tostring(sectionName) .. "." .. tostring(endpointName)
                    end
                end
            end
        end
    end

    return false, nil
end

-- ============================================================
-- STOCK / SHOP
-- ============================================================
local function StockRoot()
    return ReplicatedStorage:FindFirstChild("StockValues")
end

local function ShopItems(shopName)
    local root = StockRoot()
    local shop = root and root:FindFirstChild(shopName)
    return shop and (shop:FindFirstChild("Items") or shop) or nil
end

local function ListShop(shopName)
    local items = ShopItems(shopName)
    local result = {}
    if not items then
        return result
    end
    for _, child in ipairs(items:GetChildren()) do
        table.insert(result, child.Name)
    end
    table.sort(result)
    return result
end

local function Stock(shopName, itemName)
    local items = ShopItems(shopName)
    local obj = items and items:FindFirstChild(itemName)
    if not obj then
        return nil
    end
    local ok, value = pcall(function()
        return obj.Value
    end)
    if ok and type(value) == "number" then
        return value
    end
    local attr = obj:GetAttribute("Stock")
    if type(attr) == "number" then
        return attr
    end
    return nil
end

local function FindBakerItems()
    local root = StockRoot()
    if not root then
        return nil, nil
    end

    for _, shop in ipairs(root:GetChildren()) do
        local n = Normalize(shop.Name)
        if string.find(n, "ingredient", 1, true)
            or string.find(n, "baker", 1, true)
            or string.find(n, "muffin", 1, true)
            or string.find(n, "baking", 1, true) then
            return shop:FindFirstChild("Items") or shop, shop.Name
        end
    end

    return nil, nil
end

local function SyncCatalog()
    if DynamicCfg["Enable"] ~= true then
        return
    end

    if DynamicCfg["Sync Seed Shop"] == true then
        for _, name in ipairs(ListShop("SeedShop")) do
            if BuySeedMap[name] == nil then BuySeedMap[name] = false end
            if PlantMap[name] == nil then PlantMap[name] = false end
            if MailSeed[name] == nil then MailSeed[name] = false end
        end
    end

    if DynamicCfg["Sync Gear Shop"] == true then
        for _, name in ipairs(ListShop("GearShop")) do
            if BuyGearMap[name] == nil then BuyGearMap[name] = false end
            if MailGear[name] == nil then MailGear[name] = false end
        end
    end

    if DynamicCfg["Sync Crate Shop"] == true then
        for _, name in ipairs(ListShop("CrateShop")) do
            if BuyCrateMap[name] == nil then BuyCrateMap[name] = false end
            if MailCrate[name] == nil then MailCrate[name] = false end
        end
    end

    local baker = FindBakerItems()
    if baker then
        for _, child in ipairs(baker:GetChildren()) do
            if MuffinIngredient[child.Name] == nil then
                MuffinIngredient[child.Name] = false
            end
        end
    end
end

-- ============================================================
-- PURCHASE ADAPTERS
-- ============================================================
local function BuySeed(name, quantity)
    quantity = quantity or 1

    local ok, path = TryPaths({
        "SeedShop.Purchase",
        "SeedShop.BuySeed",
        "SeedShop.PurchaseSeed",
    }, name, quantity)

    if ok then
        return true, path
    end

    ok, path = DynamicPurchase({"seedshop", "seed"}, name, quantity)
    if ok then
        return true, path
    end

    if PacketFire(PACKET.PurchaseSeed, name, quantity) then
        return true, "Packet:" .. tostring(PACKET.PurchaseSeed)
    end

    return false, nil
end

local function BuyGear(name, quantity)
    quantity = quantity or 1

    local ok, path = TryPaths({
        "GearShop.Purchase",
        "GearShop.BuyGear",
        "GearShop.PurchaseGear",
    }, name, quantity)

    if ok then
        return true, path
    end

    -- Packet 126 is EquipGear, not a proven purchase packet.
    return DynamicPurchase({"gearshop", "gear"}, name, quantity)
end

local function BuyCrate(name, quantity)
    quantity = quantity or 1

    local ok, path = TryPaths({
        "CrateShop.Purchase",
        "CrateShop.BuyCrate",
        "CrateShop.PurchaseCrate",
    }, name, quantity)

    if ok then
        return true, path
    end

    ok, path = DynamicPurchase({"crateshop", "crate"}, name, quantity)
    if ok then
        return true, path
    end

    if PacketFire(PACKET.PurchaseCrate, name, quantity) then
        return true, "Packet:" .. tostring(PACKET.PurchaseCrate)
    end

    return false, nil
end

local function BuyBakerItem(name, quantity)
    quantity = quantity or 1

    local ok, path = TryPaths({
        "IngredientShop.Purchase",
        "IngredientShop.Buy",
        "BakerShop.Purchase",
        "BakerShop.Buy",
        "MuffinShop.Purchase",
        "MuffinShop.Buy",
        "BakingShop.Purchase",
        "BakingShop.Buy",
    }, name, quantity)

    if ok then
        return true, path
    end

    return DynamicPurchase({"ingredient", "baker", "muffin", "baking"}, name, quantity)
end

-- ============================================================
-- PLOT HELPERS
-- ============================================================
local function PlotId()
    local value = LocalPlayer:GetAttribute("PlotId")
    if type(value) == "number" then
        return value
    end
    if type(value) == "string" then
        return tonumber(value:match("%d+"))
    end
    return nil
end

local function GetMyPlot()
    local gardens = Workspace:FindFirstChild("Gardens")
        or Workspace:FindFirstChild("Plots")
        or Workspace:FindFirstChild("PlayerPlots")

    if not gardens then
        return nil
    end

    local id = PlotId()
    if id then
        local direct = gardens:FindFirstChild("Plot" .. tostring(id))
        if direct then
            return direct
        end
    end

    for _, plot in ipairs(gardens:GetChildren()) do
        local ownerId = plot:GetAttribute("OwnerUserId")
            or plot:GetAttribute("UserId")
            or plot:GetAttribute("OwnerId")

        if tonumber(ownerId) == LocalPlayer.UserId then
            return plot
        end

        local ownerObj = plot:FindFirstChild("Owner") or plot:FindFirstChild("Player")
        if ownerObj then
            local ok, ownerValue = pcall(function()
                return ownerObj.Value
            end)
            if ok and (ownerValue == LocalPlayer.Name or tonumber(ownerValue) == LocalPlayer.UserId) then
                return plot
            end
        end

        if plot.Name == LocalPlayer.Name then
            return plot
        end
    end

    return nil
end

local function GetPlantsFolder()
    local plot = GetMyPlot()
    return plot and plot:FindFirstChild("Plants") or nil
end

local function IsFallHarvest()
    return FALL_HARVEST_PLACE_IDS[game.PlaceId] == true
end

-- ============================================================
-- PROMPTS
-- ============================================================
local function FirePrompt(prompt)
    if not prompt or not prompt:IsA("ProximityPrompt") or not prompt.Parent then
        return false
    end

    if fireproximityprompt then
        return pcall(fireproximityprompt, prompt)
    end

    return pcall(function()
        prompt:InputHoldBegin()
        task.wait((prompt.HoldDuration or 0) + 0.05)
        prompt:InputHoldEnd()
    end)
end

local function PromptText(prompt)
    local parts = {prompt.Name, prompt.ActionText, prompt.ObjectText}
    local node = prompt.Parent
    for _ = 1, 5 do
        if not node then break end
        table.insert(parts, node.Name)
        node = node.Parent
    end
    return table.concat(parts, " ")
end

local function FindPrompts(predicate, root)
    root = root or Workspace
    local result = {}
    for _, obj in ipairs(root:GetDescendants()) do
        if obj:IsA("ProximityPrompt") then
            local ok, keep = pcall(predicate, obj, PromptText(obj))
            if ok and keep then
                table.insert(result, obj)
            end
        end
    end
    return result
end

-- ============================================================
-- PLOT EXPANSION / PET SLOT BEST-EFFORT
-- ============================================================
local function ExpandPlotOnce()
    if Config["Buy Expand Plot"] ~= true then
        return false
    end

    local plot = GetMyPlot()
    if not plot then
        return false
    end

    local prompts = FindPrompts(function(_, text)
        local n = Normalize(text)
        return string.find(n, "expand", 1, true)
            and (
                string.find(n, "plot", 1, true)
                or string.find(n, "garden", 1, true)
                or string.find(n, "land", 1, true)
            )
    end, plot)

    if prompts[1] then
        return FirePrompt(prompts[1])
    end

    return false
end

local function BuyPetSlotOnce()
    if Config["Buy Slot Pet"] ~= true then
        return false
    end

    local plot = GetMyPlot()
    local searchRoot = plot or Workspace

    local prompts = FindPrompts(function(_, text)
        local n = Normalize(text)
        local pet = string.find(n, "pet", 1, true)
        local slot = string.find(n, "slot", 1, true)
            or string.find(n, "equip", 1, true)
        local upgrade = string.find(n, "upgrade", 1, true)
            or string.find(n, "buy", 1, true)
            or string.find(n, "unlock", 1, true)
        return pet and slot and upgrade
    end, searchRoot)

    if prompts[1] then
        return FirePrompt(prompts[1])
    end

    return false
end

-- ============================================================
-- PLANT ENGINE
-- ============================================================
local function PlantAreas()
    local plot = GetMyPlot()
    if not plot then
        return {}
    end

    local areas = {}
    for _, part in ipairs(CollectionService:GetTagged("PlantArea")) do
        if part:IsA("BasePart") and part:IsDescendantOf(plot) then
            table.insert(areas, part)
        end
    end

    if #areas == 0 then
        for _, part in ipairs(plot:GetDescendants()) do
            if part:IsA("BasePart") and Contains(part.Name, "plantarea") then
                table.insert(areas, part)
            end
        end
    end

    return areas
end

local function ExistingPlantXZ()
    local result = {}
    local plants = GetPlantsFolder()
    if not plants then
        return result
    end

    for _, plant in ipairs(plants:GetChildren()) do
        if plant:IsA("Model") then
            local x = plant:GetAttribute("PosX")
            local z = plant:GetAttribute("PosZ")
            if type(x) == "number" and type(z) == "number" then
                table.insert(result, Vector2.new(x, z))
            else
                local ok, pivot = pcall(function()
                    return plant:GetPivot()
                end)
                if ok and pivot then
                    table.insert(result, Vector2.new(pivot.Position.X, pivot.Position.Z))
                end
            end
        end
    end

    return result
end

local function TooCloseXZ(x, z, occupied, distance)
    local d2 = distance * distance
    for _, point in ipairs(occupied) do
        local dx = x - point.X
        local dz = z - point.Y
        if dx * dx + dz * dz < d2 then
            return true
        end
    end
    return false
end

local function PlantPositions(limit)
    limit = math.max(1, tonumber(limit) or 40)
    local occupied = ExistingPlantXZ()
    local positions = {}

    for _, area in ipairs(PlantAreas()) do
        local halfX = area.Size.X / 2
        local halfZ = area.Size.Z / 2
        local step = 1.65
        local margin = 0.6

        local lx = -halfX + margin
        while lx <= halfX - margin and #positions < limit do
            local lz = -halfZ + margin
            while lz <= halfZ - margin and #positions < limit do
                local world = area.CFrame:PointToWorldSpace(
                    Vector3.new(lx, area.Size.Y / 2, lz)
                )
                if not TooCloseXZ(world.X, world.Z, occupied, 1.5) then
                    table.insert(positions, world)
                    table.insert(occupied, Vector2.new(world.X, world.Z))
                end
                lz = lz + step
            end
            lx = lx + step
        end

        if #positions >= limit then
            break
        end
    end

    return positions
end

local function ResolveSeedName(tool)
    if not tool or not tool:IsA("Tool") then
        return nil
    end

    local value = tool:GetAttribute("SeedTool")
        or tool:GetAttribute("SeedName")

    if type(value) == "string" and value ~= "" then
        return value
    end

    local name = tool.Name
    if name:sub(-5) == " Seed" then
        name = name:sub(1, -6)
    end
    return name
end

local function NextSeedTool()
    for _, container in ipairs(ToolContainers()) do
        for _, tool in ipairs(container:GetChildren()) do
            if tool:IsA("Tool") then
                local seedName = ResolveSeedName(tool)
                if seedName and MapEnabled(PlantMap, seedName) then
                    return tool, seedName
                end
            end
        end
    end
    return nil, nil
end

local function PlantFire(tool, seedName, hitPos)
    if not tool or not seedName or typeof(hitPos) ~= "Vector3" then
        return false
    end

    local net = RefreshNetworking()
    if net and net.Plant and net.Plant.PlantSeed then
        local ok = pcall(function()
            net.Plant.PlantSeed:Fire(hitPos, seedName, tool)
        end)
        if ok then
            return true
        end
    end

    return PacketFire(PACKET.PlantSeed, hitPos, seedName, tool)
end

local function PlantCycle()
    if PlantCfg["Enable"] ~= true then
        return 0
    end

    local maxPerCycle = math.max(1, tonumber(PlantCfg["MaxPerCycle"]) or 40)
    local positions = PlantPositions(maxPerCycle)
    local planted = 0

    for _, position in ipairs(positions) do
        if not Alive() or PlantCfg["Enable"] ~= true then
            break
        end

        local tool, seedName = NextSeedTool()
        if not tool then
            break
        end

        if PlantFire(tool, seedName, position) then
            planted = planted + 1
        end

        task.wait(math.max(tonumber(PlantCfg["PerSeedDelay"]) or 0.25, 0.05))
    end

    return planted
end

-- ============================================================
-- HARVEST
-- ============================================================
local function MutationOf(obj)
    if not obj then return "" end
    return tostring(obj:GetAttribute("Mutation") or "")
end

local function HarvestCycle()
    if HarvestCfg["Enable"] ~= true then
        return 0
    end

    local plot = GetMyPlot()
    if not plot then
        return 0
    end

    local harvested = 0
    local maxPerCycle = math.max(1, tonumber(HarvestCfg["MaxPerCycle"]) or 200)
    local net = RefreshNetworking()

    -- Respect the live bag cap when the game exposes it.
    local currentFruitCount = tonumber(LocalPlayer:GetAttribute("FruitCount")) or 0
    local liveCap = tonumber(LocalPlayer:GetAttribute("MaxFruitCapacity"))
    local configuredCap = tonumber(Config["Max Plant Fruit"]) or 200
    local remainingCapacity = math.max((liveCap or configuredCap) - currentFruitCount, 0)
    if remainingCapacity <= 0 then
        return 0
    end

    for _, prompt in ipairs(CollectionService:GetTagged("HarvestPrompt")) do
        if not Alive()
            or HarvestCfg["Enable"] ~= true
            or harvested >= remainingCapacity
            or harvested >= maxPerCycle then
            break
        end

        if prompt.Enabled
            and not prompt:GetAttribute("Collected")
            and prompt:IsDescendantOf(plot) then

            local part = prompt.Parent
            local fruit = part and part.Parent
            if fruit and fruit:IsA("Model") then
                local mutation = MutationOf(fruit)
                if not MapEnabled(HarvestSkipMutation, mutation) then
                    local fired = false

                    if net and net.Garden and net.Garden.CollectFruit then
                        local plantId = fruit:GetAttribute("PlantId")
                        local fruitId = fruit:GetAttribute("FruitId")
                        local ok = pcall(function()
                            net.Garden.CollectFruit:Fire(plantId, fruitId or "")
                        end)
                        fired = ok
                    end

                    if not fired then
                        fired = FirePrompt(prompt)
                    end

                    if fired then
                        harvested = harvested + 1
                        task.wait(math.max(tonumber(HarvestCfg["PerFruitDelay"]) or 0.04, 0.02))
                    end
                end
            end
        end
    end

    return harvested
end

-- ============================================================
-- AUTO WATER
-- ============================================================
local function WaterTool()
    for _, container in ipairs(ToolContainers()) do
        for _, tool in ipairs(container:GetChildren()) do
            if tool:IsA("Tool") then
                local value = tool:GetAttribute("WateringCan")
                    or tool:GetAttribute("WateringCanName")
                local name = nil
                if value ~= nil then
                    name = (type(value) == "string" and value ~= "") and value or tool.Name
                elseif Contains(tool.Name, "wateringcan") then
                    name = tool.Name
                end

                if name and MapEnabled(WaterTools, name) then
                    return tool, name
                end
            end
        end
    end
    return nil, nil
end

local function PlantPosition(plant)
    if not plant or not plant:IsA("Model") then
        return nil
    end
    if plant.PrimaryPart then
        return plant.PrimaryPart.Position
    end
    local ok, pivot = pcall(function()
        return plant:GetPivot()
    end)
    if ok and pivot then
        return pivot.Position
    end
    for _, child in ipairs(plant:GetDescendants()) do
        if child:IsA("BasePart") then
            return child.Position
        end
    end
    return nil
end

local function WaterCycle()
    if WaterCfg["Enable"] ~= true then
        return 0
    end

    local net = RefreshNetworking()
    if not net
        or not net.WateringCan
        or not net.WateringCan.UseWateringCan then
        return 0
    end

    local tool, canName = WaterTool()
    if not tool or not canName then
        return 0
    end

    EquipTool(tool)

    local plants = GetPlantsFolder()
    if not plants then
        return 0
    end

    local watered = 0
    for _, plant in ipairs(plants:GetChildren()) do
        if not Alive() or WaterCfg["Enable"] ~= true then
            break
        end

        if plant:IsA("Model") then
            local needsWater = plant:GetAttribute("NeedsWater")
            local waterLevel = plant:GetAttribute("WaterLevel")
            local skip = (needsWater == false)
                or (type(waterLevel) == "number" and waterLevel >= 1)

            if not skip then
                local pos = PlantPosition(plant)
                if pos then
                    if tool.Parent ~= Character() then
                        local newTool, newName = WaterTool()
                        if not newTool then
                            break
                        end
                        tool, canName = newTool, newName
                        EquipTool(tool)
                    end

                    local ok = pcall(function()
                        net.WateringCan.UseWateringCan:Fire(
                            Vector3.new(pos.X, pos.Y - 0.3, pos.Z),
                            canName,
                            tool
                        )
                    end)

                    if ok then
                        watered = watered + 1
                    end

                    task.wait(math.max(tonumber(WaterCfg["PerPlantDelay"]) or 0.08, 0.05))
                end
            end
        end
    end

    return watered
end

-- ============================================================
-- AUTO SPRINKLER
-- ============================================================
local SPRINKLER_RADIUS = {
    ["Common Sprinkler"] = 20,
    ["Uncommon Sprinkler"] = 25,
    ["Rare Sprinkler"] = 30,
    ["Legendary Sprinkler"] = 40,
    ["Super Sprinkler"] = 55,
    ["Syrup Sprinkler"] = 20,
    ["Super Syrup Sprinkler"] = 55,
}

local function SprinklerTool()
    for _, container in ipairs(ToolContainers()) do
        for _, tool in ipairs(container:GetChildren()) do
            if tool:IsA("Tool") then
                local value = tool:GetAttribute("Sprinkler")
                    or tool:GetAttribute("SprinklerName")
                local name = nil
                if value ~= nil then
                    name = (type(value) == "string" and value ~= "") and value or tool.Name
                elseif Contains(tool.Name, "sprinkler") then
                    name = tool.Name
                end

                if name and MapEnabled(SprinklerTools, name) then
                    return tool, name
                end
            end
        end
    end
    return nil, nil
end

local function ExistingSprinklers()
    local plot = GetMyPlot()
    local positions = {}
    if not plot then
        return positions
    end

    local folder = plot:FindFirstChild("Sprinklers")
    local items = folder and folder:GetChildren() or plot:GetDescendants()

    for _, model in ipairs(items) do
        if model:IsA("Model") then
            local sprinklerId = model:GetAttribute("SprinklerId")
            local sprinklerName = model:GetAttribute("SprinklerName")
            if sprinklerId ~= nil
                or sprinklerName ~= nil
                or SPRINKLER_RADIUS[model.Name] then

                local ok, pivot = pcall(function()
                    return model:GetPivot()
                end)
                if ok and pivot then
                    table.insert(positions, Vector2.new(pivot.Position.X, pivot.Position.Z))
                end
            end
        end
    end

    return positions
end

local function SurfacePoint(x, z, areas)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Include
    params.FilterDescendantsInstances = areas

    local hit = Workspace:Raycast(
        Vector3.new(x, 1000, z),
        Vector3.new(0, -2000, 0),
        params
    )

    if hit then
        return hit.Position
    end

    local nearest = nil
    local nearestDist = math.huge
    for _, area in ipairs(areas) do
        local dx = x - area.Position.X
        local dz = z - area.Position.Z
        local dist = dx * dx + dz * dz
        if dist < nearestDist then
            nearestDist = dist
            nearest = area
        end
    end

    if nearest then
        return Vector3.new(
            x,
            nearest.Position.Y + nearest.Size.Y / 2,
            z
        )
    end

    return nil
end

local function PointCovered(point, sprinklers, radius)
    local r2 = radius * radius
    for _, sprinkler in ipairs(sprinklers) do
        local dx = point.X - sprinkler.X
        local dz = point.Y - sprinkler.Y
        if dx * dx + dz * dz <= r2 then
            return true
        end
    end
    return false
end

local function SprinklerCycle()
    if SprinklerCfg["Enable"] ~= true then
        return false
    end

    local areas = PlantAreas()
    if #areas == 0 then
        return false
    end

    local tool, name = SprinklerTool()
    if not tool or not name then
        return false
    end

    local radius = SPRINKLER_RADIUS[name] or 20
    local existing = ExistingSprinklers()

    local candidates = {}
    local step = math.max(math.floor(radius * 0.75), 6)

    for _, area in ipairs(areas) do
        local halfX = area.Size.X / 2
        local halfZ = area.Size.Z / 2

        local lx = -halfX + 1
        while lx <= halfX - 1 do
            local lz = -halfZ + 1
            while lz <= halfZ - 1 do
                local world = area.CFrame:PointToWorldSpace(
                    Vector3.new(lx, area.Size.Y / 2, lz)
                )
                table.insert(candidates, Vector2.new(world.X, world.Z))
                lz = lz + step
            end
            lx = lx + step
        end
    end

    if #candidates == 0 then
        return false
    end

    local targetCoverage = math.clamp(
        tonumber(SprinklerCfg["TargetCoverage"]) or 0.95,
        0,
        1
    )
    local maxPerCycle = math.max(1, tonumber(SprinklerCfg["MaxPerCycle"]) or 3)
    local placed = 0

    local function coverageNow()
        local covered = 0
        for _, point in ipairs(candidates) do
            if PointCovered(point, existing, radius) then
                covered = covered + 1
            end
        end
        return covered / #candidates
    end

    if coverageNow() >= targetCoverage then
        return true
    end

    for _, point in ipairs(candidates) do
        if not Alive()
            or SprinklerCfg["Enable"] ~= true
            or placed >= maxPerCycle
            or coverageNow() >= targetCoverage then
            break
        end

        if not PointCovered(point, existing, radius) then
            local currentTool, currentName = SprinklerTool()
            if not currentTool or not currentName then
                break
            end

            tool, name = currentTool, currentName
            radius = SPRINKLER_RADIUS[name] or radius
            EquipTool(tool)

            local hitPos = SurfacePoint(point.X, point.Y, areas)
            local plotId = PlotId()
            if not plotId then
                local plot = GetMyPlot()
                plotId = plot and tonumber(plot.Name:match("%d+")) or nil
            end

            if hitPos and plotId then
                local fired = false
                local net = RefreshNetworking()

                if net and net.Place and net.Place.PlaceSprinkler then
                    fired = pcall(function()
                        net.Place.PlaceSprinkler:Fire(hitPos, name, tool, plotId)
                    end)
                end

                if not fired then
                    fired = PacketFire(PACKET.PlaceSprinkler, hitPos, name, tool, plotId)
                end

                if fired then
                    placed = placed + 1
                    table.insert(existing, Vector2.new(point.X, point.Y))
                    task.wait(math.max(
                        tonumber(SprinklerCfg["PerPlacementDelay"]) or 0.7,
                        0.25
                    ))
                end
            end
        end
    end

    return placed > 0 or coverageNow() >= targetCoverage
end

-- ============================================================
-- SELL
-- ============================================================
local function ShouldKeepMutation(mutation)
    mutation = tostring(mutation or "")
    if mutation == "" or mutation == "None" then
        return false
    end

    local keep = SellCfg["Keep Mutated"]

    -- Backward compatibility:
    -- true  = keep every mutation
    -- false = keep none
    if type(keep) == "boolean" then
        return keep
    end

    -- New config:
    -- ["Keep Mutated"] = { ["Gold"] = true, ["Frozen"] = false, ... }
    if type(keep) == "table" then
        return keep[mutation] == true
    end

    return false
end

local function HasKeepMutationRules()
    local keep = SellCfg["Keep Mutated"]
    if keep == true then
        return true
    end
    if type(keep) == "table" then
        for _, enabled in pairs(keep) do
            if enabled == true then
                return true
            end
        end
    end
    return false
end

local function SellCycle()
    if SellCfg["Enable"] ~= true then
        return false
    end

    local net = RefreshNetworking()
    if not net or not net.NPCS then
        return false
    end

    local selectiveKeep = HasKeepMutationRules()

    -- Daily Deal sells in bulk. Skip it whenever mutation protection is active
    -- so a protected mutated fruit cannot be sold accidentally.
    if not selectiveKeep
        and SellCfg["Use Daily Deal"] == true
        and net.NPCS.CheckDailyDeal
        and net.NPCS.UseDailyDealAll then

        pcall(function()
            net.NPCS.CheckDailyDeal:Fire()
        end)

        local ok, result = pcall(function()
            return net.NPCS.UseDailyDealAll:Fire()
        end)

        if ok and result and result.Success then
            return true
        end
    end

    if not selectiveKeep and net.NPCS.SellAll then
        local ok = pcall(function()
            net.NPCS.SellAll:Fire()
        end)
        return ok
    end

    if net.NPCS.SellFruit then
        local any = false

        for _, container in ipairs(ToolContainers()) do
            for _, tool in ipairs(container:GetChildren()) do
                if tool:IsA("Tool")
                    and (
                        tool:GetAttribute("HarvestedFruit")
                        or tool:GetAttribute("FruitName")
                    ) then

                    local mutation = MutationOf(tool)

                    if not ShouldKeepMutation(mutation) then
                        local id = tool:GetAttribute("Id")
                        if id then
                            local ok = pcall(function()
                                net.NPCS.SellFruit:Fire(id)
                            end)
                            any = any or ok
                            task.wait(math.max(tonumber(SellCfg["PerFruitDelay"]) or 0.05, 0.02))
                        end
                    end
                end
            end
        end

        return any
    end

    return false
end

-- ============================================================
-- CRATE / EGG
-- ============================================================
local function OpenCrateOnce()
    if AutoCrateCfg["Open"] ~= true then
        return false
    end

    local filtered = AnyEnabled(AutoCrateMap)

    for _, container in ipairs(ToolContainers()) do
        for _, tool in ipairs(container:GetChildren()) do
            if tool:IsA("Tool") then
                local crateName = tool:GetAttribute("Crate")
                if crateName and (not filtered or MapEnabled(AutoCrateMap, crateName)) then
                    local net = RefreshNetworking()
                    if net and net.Crate and net.Crate.OpenCrate then
                        local ok = pcall(function()
                            net.Crate.OpenCrate:Fire(crateName)
                        end)
                        if ok then
                            return true
                        end
                    end

                    if PacketFire(PACKET.OpenCrate, crateName) then
                        return true
                    end
                end
            end
        end
    end

    return false
end

local function OpenEggOnce()
    if AutoEggCfg["Open"] ~= true then
        return false
    end

    local filtered = AnyEnabled(AutoEggMap)
    local prompts = FindPrompts(function(prompt, text)
        local n = Normalize(text)
        local isEgg = string.find(n, "egg", 1, true)
        local action = string.find(n, "open", 1, true)
            or string.find(n, "hatch", 1, true)

        if not (isEgg and action) then
            return false
        end

        if not filtered then
            return true
        end

        local combined = tostring(prompt.ObjectText or "") .. " " .. tostring(text or "")
        for eggName, enabled in pairs(AutoEggMap) do
            if enabled == true and Contains(combined, eggName) then
                return true
            end
        end

        return false
    end)

    if prompts[1] and FirePrompt(prompts[1]) then
        return true
    end

    if not filtered then
        return PacketFire(PACKET.OpenEgg)
    end

    return false
end

-- ============================================================
-- PET AUTO BUY / FINDER
-- ============================================================
local function WildPetRoot()
    local map = Workspace:FindFirstChild("Map")
    return map and map:FindFirstChild("WildPetRef") or nil
end

local function PetName(obj)
    if not obj then return nil end
    return obj:GetAttribute("Pet")
        or obj:GetAttribute("Species")
        or obj:GetAttribute("PetSpecies")
        or obj:GetAttribute("PetName")
        or obj.Name
end

local function PetSelected(map, name)
    if MapEnabled(map, name) then
        return true
    end
    local alias = PET_ALIASES[name]
    if alias and MapEnabled(map, alias) then
        return true
    end
    for display, compact in pairs(PET_ALIASES) do
        if Normalize(name) == Normalize(compact) and MapEnabled(map, display) then
            return true
        end
    end
    return false
end

local function FindSelectedWildPet(selection)
    local root = WildPetRoot()
    if not root then
        return nil
    end

    local hrp = Root()
    local best = nil
    local bestDistance = math.huge

    for _, part in ipairs(root:GetChildren()) do
        if part:IsA("BasePart") then
            local owner = tonumber(part:GetAttribute("OwnerUserId")) or 0
            if owner == 0 then
                local name = PetName(part)
                if name and PetSelected(selection, name) then
                    local distance = hrp and (part.Position - hrp.Position).Magnitude or 0
                    if distance < bestDistance then
                        bestDistance = distance
                        best = part
                    end
                end
            end
        end
    end

    return best
end

local function InteractWildPet(part, allowMove, interactionDelay)
    if not part then
        return false
    end

    local prompt = part:FindFirstChildWhichIsA("ProximityPrompt", true)
    if prompt and FirePrompt(prompt) then
        return true
    end

    if allowMove == true then
        local hrp = Root()
        if hrp then
            pcall(function()
                hrp.CFrame = CFrame.new(part.Position + Vector3.new(0, 4, 0))
            end)
            local waitTime = math.max(
                tonumber(interactionDelay) or 0.25,
                0.05
            )
            task.wait(waitTime)
            prompt = part:FindFirstChildWhichIsA("ProximityPrompt", true)
            if prompt then
                return FirePrompt(prompt)
            end
        end
    end

    return false
end

local function PetAutoBuyCycle()
    if PetBuyCfg["Enable"] ~= true then
        return false
    end

    local pet = FindSelectedWildPet(PetBuyMap)
    if not pet then
        return false
    end

    return InteractWildPet(pet, true, PetBuyCfg["InteractDelay"])
end

local function PetFinderCycle()
    if PetFinderCfg["Enable"] ~= true then
        return false
    end

    local pet = FindSelectedWildPet(PetFinderMap)
    if not pet then
        return false
    end

    return InteractWildPet(pet, PetFinderCfg["Move To Pet"] == true, PetFinderCfg["InteractDelay"])
end


-- ============================================================
-- SEED PACK / TURKEY DROP COLLECTION
-- ============================================================
local function DropPart(instance)
    if not instance then return nil end
    if instance:IsA("BasePart") then return instance end
    if instance:IsA("Model") then
        return instance.PrimaryPart
            or instance:FindFirstChildWhichIsA("BasePart", true)
    end
    return instance:FindFirstChildWhichIsA("BasePart", true)
end

local function IsSeedPackDrop(instance)
    if not instance then return false end

    local name = Normalize(instance.Name)
    if string.find(name, "seedpack", 1, true)
        or string.find(name, "turkeydrop", 1, true) then
        return true
    end

    local ok, isSeedPack = pcall(function()
        return instance:GetAttribute("SeedPack")
            or instance:GetAttribute("IsSeedPack")
            or instance:GetAttribute("TurkeyDrop")
    end)

    return ok and isSeedPack ~= nil and isSeedPack ~= false
end

local function CollectSeedPackCycle()
    if CollectSeedPackCfg["Enable"] ~= true then
        return 0
    end

    local maxPerCycle = math.max(
        1,
        tonumber(CollectSeedPackCfg["MaxPerCycle"]) or 30
    )
    local collected = 0
    local hrp = Root()

    local candidates = {}
    for _, child in ipairs(Workspace:GetChildren()) do
        if IsSeedPackDrop(child) then
            table.insert(candidates, child)
        else
            local folderName = Normalize(child.Name)
            if string.find(folderName, "drop", 1, true)
                or string.find(folderName, "pickup", 1, true)
                or string.find(folderName, "seedpack", 1, true) then
                for _, desc in ipairs(child:GetDescendants()) do
                    if IsSeedPackDrop(desc) then
                        table.insert(candidates, desc)
                    end
                end
            end
        end
    end

    for _, drop in ipairs(candidates) do
        if not Alive()
            or CollectSeedPackCfg["Enable"] ~= true
            or collected >= maxPerCycle then
            break
        end

        local blocked = false
        for name, enabled in pairs(CollectSeedPackBlacklist) do
            if enabled == true and Contains(drop.Name, name) then
                blocked = true
                break
            end
        end

        if not blocked then
            local prompt = drop:FindFirstChildWhichIsA("ProximityPrompt", true)
            local success = false

            if prompt then
                success = FirePrompt(prompt)
            end

            local part = DropPart(drop)
            if not success and part and hrp and firetouchinterest then
                success = pcall(function()
                    firetouchinterest(hrp, part, 0)
                    task.wait()
                    firetouchinterest(hrp, part, 1)
                end)
            end

            if not success
                and part
                and hrp
                and CollectSeedPackCfg["Move To Drop"] == true then

                pcall(function()
                    hrp.CFrame = CFrame.new(part.Position + Vector3.new(0, 3, 0))
                end)
                task.wait(0.12)

                prompt = drop:FindFirstChildWhichIsA("ProximityPrompt", true)
                if prompt then
                    success = FirePrompt(prompt)
                end
            end

            if success then
                collected = collected + 1
                task.wait(math.max(
                    tonumber(CollectSeedPackCfg["PerItemDelay"]) or 0.08,
                    0.03
                ))
            end
        end
    end

    return collected
end

-- ============================================================
-- MAIL
-- ============================================================
local MAIL_ATTRS = {
    HarvestedFruits = {"FruitName", "HarvestedFruit"},
    Seeds = {"SeedTool", "SeedName"},
    Pets = {"Pet", "PetSpecies", "PetName"},
    Sprinklers = {"Sprinkler", "SprinklerName"},
    WateringCans = {"WateringCan", "WateringCanName"},
    Mushrooms = {"Mushroom"},
    Gnomes = {"Gnome"},
    Raccoons = {"Raccoon"},
    Crates = {"Crate"},
    SeedPacks = {"SeedPack"},
    Trowels = {"Trowel"},
    Props = {"Prop"},
    EmptyPots = {"EmptyPot", "Pot"},
}

local function GiftCategory(tool)
    if not tool or not tool:IsA("Tool") then
        return nil, nil
    end

    for category, attrs in pairs(MAIL_ATTRS) do
        for _, attr in ipairs(attrs) do
            local value = tool:GetAttribute(attr)
            if value ~= nil then
                local name = (
                    type(value) == "string" and value ~= ""
                ) and value or tool.Name
                return category, name
            end
        end
    end

    return nil, nil
end

local function MailSelected(category, name)
    if category == "Pets" then
        return MapEnabled(MailPet, name)
    elseif category == "Seeds" then
        return MapEnabled(MailSeed, name)
    elseif category == "HarvestedFruits" then
        return MapEnabled(MailFruit, name)
    elseif category == "Crates" then
        return MapEnabled(MailCrate, name)
    elseif category == "SeedPacks" then
        return MapEnabled(MailSeedPack, name)
    end

    return MapEnabled(MailGear, name)
end

local function MailBatch(maxCount)
    maxCount = math.max(1, math.min(tonumber(maxCount) or 20, 20))
    local batch = {}
    local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
    if not backpack then
        return batch
    end

    for _, tool in ipairs(backpack:GetChildren()) do
        if #batch >= maxCount then
            break
        end

        if tool:IsA("Tool") then
            local category, name = GiftCategory(tool)
            if category and name and MailSelected(category, name) then
                table.insert(batch, {
                    Category = category,
                    ItemKey = name,
                    Count = 1,
                })
            end
        end
    end

    return batch
end

local function UserIdFromName(name)
    if type(name) ~= "string" or name == "" then
        return nil
    end

    local numeric = tonumber(name)
    if numeric and numeric > 0 then
        return numeric
    end

    for _, player in ipairs(Players:GetPlayers()) do
        if player.Name == name or player.DisplayName == name then
            return player.UserId
        end
    end

    local ok, userId = pcall(function()
        return Players:GetUserIdFromNameAsync(name)
    end)
    return ok and userId or nil
end

local function SendMail(userId, batch, note)
    local net = RefreshNetworking()
    if not net
        or not net.Mailbox
        or not net.Mailbox.SendBatch then
        return false, "Mailbox.SendBatch unavailable"
    end

    local ok, result, message = pcall(function()
        return net.Mailbox.SendBatch:Fire(userId, batch, note or "")
    end)

    if not ok then
        return false, tostring(result)
    end
    if result == true then
        return true, message or "Sent"
    end
    return false, message or "Could not send"
end

local function ClaimGiftOnce()
    if UtilityCfg["Auto Accept Gifts"] ~= true then
        return false
    end

    local plot = GetMyPlot()
    if not plot then
        return false
    end

    local signs = plot:FindFirstChild("Signs")
    local mailbox = signs and signs:FindFirstChild("GreyMailBox")
    local prompt = mailbox and mailbox:FindFirstChild("MailboxPrompt", true)
    return prompt and FirePrompt(prompt) or false
end

-- ============================================================
-- FALL MAGIC MAIL (SAFE BEST-EFFORT)
-- ============================================================
-- Public sources confirm Magic Mail is the Fall->Main transfer mechanic,
-- but no current public source exposes a stable Networking argument contract.
-- Therefore this engine does not invent a packet. When explicitly enabled it
-- equips a selected Magic Mail tool and only activates a matching in-world
-- transfer/mail prompt. If no matching prompt exists, it does nothing.
local function MagicMailTool()
    for _, container in ipairs(ToolContainers()) do
        for _, tool in ipairs(container:GetChildren()) do
            if tool:IsA("Tool")
                and MapEnabled(MagicMailTools, tool.Name)
                and Contains(tool.Name, "magicmail") then
                return tool
            end
        end
    end
    return nil
end

local function MagicMailCycle()
    if MagicMailCfg["Auto Use"] ~= true or not IsFallHarvest() then
        return false
    end

    local tool = MagicMailTool()
    if not tool then
        return false
    end

    EquipTool(tool)

    local prompts = FindPrompts(function(_, text)
        local n = Normalize(text)
        local mail = string.find(n, "mail", 1, true)
            or string.find(n, "transfer", 1, true)
            or string.find(n, "send", 1, true)
        local world = string.find(n, "main", 1, true)
            or string.find(n, "gardenvalley", 1, true)
            or string.find(n, "transfer", 1, true)
        return mail and world
    end)

    if prompts[1] then
        return FirePrompt(prompts[1])
    end

    return false
end

-- ============================================================
-- MUFFIN BAKE / BAKER
-- ============================================================
local function BuyBakerCycle()
    if MuffinCfg["Enable"] ~= true
        or MuffinCfg["Auto Buy Ingredients"] ~= true
        or not IsFallHarvest() then
        return 0
    end

    local folder = FindBakerItems()
    if not folder then
        return 0
    end

    local count = 0
    for _, child in ipairs(folder:GetChildren()) do
        local name = child.Name
        if MapEnabled(MuffinIngredient, name) then
            local stock = nil
            local ok, value = pcall(function()
                return child.Value
            end)
            if ok and type(value) == "number" then
                stock = value
            else
                stock = child:GetAttribute("Stock")
            end

            if stock == nil or stock > 0 then
                local purchased = BuyBakerItem(name, 1)
                if purchased then
                    count = count + 1
                end
                task.wait(math.max(tonumber(MuffinCfg["IngredientBuyDelay"]) or 0.08, 0.03))
            end
        end
    end

    return count
end

local function MuffinPromptCycle()
    if MuffinCfg["Enable"] ~= true or not IsFallHarvest() then
        return false
    end

    if MuffinCfg["Auto Claim Ready Oven"] == true then
        local prompts = FindPrompts(function(_, text)
            local n = Normalize(text)
            local oven = string.find(n, "oven", 1, true)
                or string.find(n, "muffin", 1, true)
            local claim = string.find(n, "claim", 1, true)
                or string.find(n, "collect", 1, true)
                or string.find(n, "take", 1, true)
                or string.find(n, "pickup", 1, true)
            return oven and claim
        end)
        if prompts[1] and FirePrompt(prompts[1]) then
            return true
        end
    end

    if MuffinCfg["Auto Exchange Prompt"] == true then
        local prompts = FindPrompts(function(_, text)
            local n = Normalize(text)
            local exchange = string.find(n, "exchange", 1, true)
                or string.find(n, "trade", 1, true)
            local baker = string.find(n, "muffin", 1, true)
                or string.find(n, "baker", 1, true)
            return exchange and baker
        end)
        if prompts[1] and FirePrompt(prompts[1]) then
            return true
        end
    end

    if MuffinCfg["Auto Baker Prompt"] == true then
        local prompts = FindPrompts(function(_, text)
            local n = Normalize(text)
            return string.find(n, "baker", 1, true)
                or string.find(n, "muffin", 1, true)
                or string.find(n, "ingredient", 1, true)
        end)
        if prompts[1] then
            return FirePrompt(prompts[1])
        end
    end

    return false
end

-- ============================================================
-- SHOP CYCLES
-- ============================================================
local function BuySelected(shopName, cfg, map, buyer)
    if cfg["Enable"] ~= true then
        return 0
    end

    local count = 0
    local quantity = math.max(1, tonumber(cfg["QuantityPerCycle"]) or 1)

    for _, name in ipairs(ListShop(shopName)) do
        if cfg["All Current Stock"] == true or MapEnabled(map, name) then
            local stock = Stock(shopName, name)
            if stock and stock > 0 then
                local ok = buyer(name, math.min(quantity, stock))
                if ok then
                    count = count + 1
                end
                task.wait(math.max(tonumber(cfg["PerItemDelay"]) or 0.06, 0.03))
            end
        end
    end

    return count
end

local function ShopCycle()
    local inFall = IsFallHarvest() and FallCfg["Enable"] == true

    local seedEnabled = BuySeedCfg["Enable"] == true
        or (inFall and FallCfg["Auto Buy Seed"] == true)
    local gearEnabled = BuyGearCfg["Enable"] == true
        or (inFall and FallCfg["Auto Buy Gear"] == true)
    local crateEnabled = BuyCrateCfg["Enable"] == true
        or (inFall and FallCfg["Auto Buy Crate"] == true)

    local seedShadow = {
        ["Enable"] = seedEnabled,
        ["All Current Stock"] = BuySeedCfg["All Current Stock"],
        ["QuantityPerCycle"] = BuySeedCfg["QuantityPerCycle"],
        ["PerItemDelay"] = BuySeedCfg["PerItemDelay"],
    }
    local gearShadow = {
        ["Enable"] = gearEnabled,
        ["All Current Stock"] = BuyGearCfg["All Current Stock"],
        ["QuantityPerCycle"] = BuyGearCfg["QuantityPerCycle"],
        ["PerItemDelay"] = BuyGearCfg["PerItemDelay"],
    }
    local crateShadow = {
        ["Enable"] = crateEnabled,
        ["All Current Stock"] = BuyCrateCfg["All Current Stock"],
        ["QuantityPerCycle"] = BuyCrateCfg["QuantityPerCycle"],
        ["PerItemDelay"] = BuyCrateCfg["PerItemDelay"],
    }

    local seedCount = BuySelected("SeedShop", seedShadow, BuySeedMap, BuySeed)
    local gearCount = BuySelected("GearShop", gearShadow, BuyGearMap, BuyGear)
    local crateCount = BuySelected("CrateShop", crateShadow, BuyCrateMap, BuyCrate)

    return seedCount, gearCount, crateCount
end

-- ============================================================
-- CODES
-- ============================================================
local RedeemedThisSession = {}

local function RedeemCodesOnce()
    if UtilityCfg["Auto Redeem Codes"] ~= true then
        return 0
    end

    local count = 0
    for code, enabled in pairs(UtilityCodes) do
        if enabled == true and not RedeemedThisSession[code] then
            local ok, path = DynamicRedeem(code)
            RedeemedThisSession[code] = true
            if ok then
                count = count + 1
                DebugLog("Redeem", code, "via", path)
            end
            task.wait(0.1)
        end
    end
    return count
end

-- ============================================================
-- VISUAL / WEBHOOK
-- ============================================================
local DEFAULT_LIGHT = {
    Brightness = Lighting.Brightness,
    Ambient = Lighting.Ambient,
    OutdoorAmbient = Lighting.OutdoorAmbient,
    FogStart = Lighting.FogStart,
    FogEnd = Lighting.FogEnd,
}

local function UtilityVisual()
    if UtilityCfg["Full Bright"] == true then
        Lighting.Brightness = 5
        Lighting.Ambient = Color3.fromRGB(255, 255, 255)
        Lighting.OutdoorAmbient = Color3.fromRGB(255, 255, 255)
    else
        Lighting.Brightness = DEFAULT_LIGHT.Brightness
        Lighting.Ambient = DEFAULT_LIGHT.Ambient
        Lighting.OutdoorAmbient = DEFAULT_LIGHT.OutdoorAmbient
    end

    if UtilityCfg["No Fog"] == true then
        Lighting.FogStart = 100000
        Lighting.FogEnd = 100000
    else
        Lighting.FogStart = DEFAULT_LIGHT.FogStart
        Lighting.FogEnd = DEFAULT_LIGHT.FogEnd
    end
end

local function RequestFunction()
    return (syn and syn.request)
        or http_request
        or request
        or (http and http.request)
end

local function Webhook(title, description)
    if WebhookCfg["Enable"] ~= true
        or type(WebhookCfg["URL"]) ~= "string"
        or WebhookCfg["URL"] == "" then
        return false
    end

    local req = RequestFunction()
    if type(req) ~= "function" then
        return false
    end

    return pcall(req, {
        Url = WebhookCfg["URL"],
        Method = "POST",
        Headers = {["Content-Type"] = "application/json"},
        Body = HttpService:JSONEncode({
            username = WebhookCfg["Username"] or "OneClick GAG2",
            embeds = {{
                title = tostring(title or BUILD),
                description = tostring(description or ""),
                footer = {text = BUILD},
            }},
        }),
    })
end

-- ============================================================
-- RUNTIME PERFORMANCE GUARD
-- ============================================================
local function ApplyPerformanceSettings()
    local fps = tonumber(UtilityCfg["FPS Cap"]) or 0
    if fps > 0 and type(setfpscap) == "function" then
        pcall(setfpscap, math.max(5, math.floor(fps)))
    end
end

-- ============================================================
-- OPTIONAL LIGHTWEIGHT HUD
-- ============================================================
local Status = {
    StartedAt = os.time(),
    Plants = 0,
    Harvested = 0,
    Watered = 0,
    ShopBuys = 0,
    MailSent = 0,
    Last = "Starting",
}

local StatusGui = nil
local StatusLabel = nil

local function BuildStatusHud()
    if UtilityCfg["Show Status HUD"] ~= true then
        return
    end

    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if not playerGui then
        return
    end

    local old = playerGui:FindFirstChild("OneclickGAG2_Status")
    if old then old:Destroy() end

    local gui = Instance.new("ScreenGui")
    gui.Name = "OneclickGAG2_Status"
    gui.ResetOnSpawn = false
    gui.Parent = playerGui

    local frame = Instance.new("Frame")
    frame.Size = UDim2.fromOffset(260, 126)
    frame.Position = UDim2.new(0, 12, 0, 90)
    frame.BackgroundColor3 = Color3.fromRGB(15, 23, 20)
    frame.BorderSizePixel = 0
    frame.Parent = gui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = frame

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -12, 1, -12)
    label.Position = UDim2.fromOffset(6, 6)
    label.BackgroundTransparency = 1
    label.TextColor3 = Color3.fromRGB(210, 240, 220)
    label.Font = Enum.Font.Code
    label.TextSize = 12
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextYAlignment = Enum.TextYAlignment.Top
    label.Parent = frame

    StatusGui = gui
    StatusLabel = label
end

local function UpdateStatusHud()
    if not StatusLabel then
        return
    end

    StatusLabel.Text = string.format(
        "%s\nWorld: %s\nPlant:%d  Harvest:%d\nWater:%d  Shop:%d  Mail:%d\nLast: %s",
        BUILD,
        IsFallHarvest() and "Fall Harvest" or "Main",
        Status.Plants,
        Status.Harvested,
        Status.Watered,
        Status.ShopBuys,
        Status.MailSent,
        tostring(Status.Last)
    )
end

-- ============================================================
-- RUNTIME REPORT
-- ============================================================
local function ScanNetworking()
    local result = {}
    local net = RefreshNetworking()
    if type(net) ~= "table" then
        return result
    end

    for sectionName, section in pairs(net) do
        if type(section) == "table" then
            local entry = {
                Section = tostring(sectionName),
                Endpoints = {},
            }

            for endpointName, endpoint in pairs(section) do
                if type(endpoint) == "table" then
                    local fire = rawget(endpoint, "Fire")
                    local invoke = rawget(endpoint, "Invoke")
                    if type(fire) == "function" or type(invoke) == "function" then
                        table.insert(entry.Endpoints, tostring(endpointName))
                    end
                end
            end

            table.sort(entry.Endpoints)
            table.insert(result, entry)
        end
    end

    table.sort(result, function(a, b)
        return a.Section < b.Section
    end)

    return result
end

local function RuntimeReport()
    local baker, bakerName = FindBakerItems()
    local bakerItems = {}
    if baker then
        for _, child in ipairs(baker:GetChildren()) do
            table.insert(bakerItems, child.Name)
        end
        table.sort(bakerItems)
    end

    return {
        Build = BUILD,
        PlaceId = game.PlaceId,
        IsFallHarvest = IsFallHarvest(),
        Networking = RefreshNetworking() ~= nil,
        PacketRemote = RefreshPacket() ~= nil,
        PlotId = PlotId(),
        SeedShop = ListShop("SeedShop"),
        GearShop = ListShop("GearShop"),
        CrateShop = ListShop("CrateShop"),
        BakerShop = bakerName,
        BakerItems = bakerItems,
        NetworkingTree = ScanNetworking(),
        MuffinExchange = MUFFIN_EXCHANGE,
        CurrentCodeCandidates = ACTIVE_CODE_CANDIDATES,
    }
end

local function PrintReport()
    local report = RuntimeReport()
    Log("Build", report.Build)
    Log("PlaceId", report.PlaceId, "Fall", report.IsFallHarvest)
    Log("Networking", report.Networking, "Packet", report.PacketRemote)
    Log("PlotId", report.PlotId)
    Log("SeedShop", table.concat(report.SeedShop, ", "))
    Log("GearShop", table.concat(report.GearShop, ", "))
    Log("CrateShop", table.concat(report.CrateShop, ", "))
    if report.BakerShop then
        Log("BakerShop", report.BakerShop, table.concat(report.BakerItems, ", "))
    end

    if UtilityCfg["Debug"] == true then
        for _, section in ipairs(report.NetworkingTree) do
            Log(
                "NET",
                section.Section,
                #section.Endpoints > 0 and table.concat(section.Endpoints, ", ") or "(no direct endpoint)"
            )
        end
    end
end

-- ============================================================
-- LOOPS
-- ============================================================
BuildStatusHud()
pcall(ApplyPerformanceSettings)

task.spawn(function()
    local attempts = 0
    while Alive() and attempts < 30 do
        attempts = attempts + 1
        RefreshNetworking()
        RefreshPacket()
        if Networking and PacketRemote then
            break
        end
        task.wait(1)
    end

    pcall(SyncCatalog)
    pcall(RedeemCodesOnce)

    if UtilityCfg["Debug"] == true then
        PrintReport()
    end
end)

task.spawn(function()
    while Alive() do
        local delay = math.max(tonumber(PlantCfg["CycleDelay"]) or 0.6, 0.2)
        task.wait(delay)
        if PlantCfg["Enable"] == true then
            local ok, count = pcall(PlantCycle)
            if ok and count and count > 0 then
                Status.Plants = Status.Plants + count
                Status.Last = "Plant +" .. tostring(count)
            end
        end
    end
end)

task.spawn(function()
    while Alive() do
        task.wait(math.max(tonumber(HarvestCfg["Delay"]) or 1, 0.2))
        if HarvestCfg["Enable"] == true then
            local ok, count = pcall(HarvestCycle)
            if ok and count and count > 0 then
                Status.Harvested = Status.Harvested + count
                Status.Last = "Harvest +" .. tostring(count)
            end
        end
    end
end)

task.spawn(function()
    while Alive() do
        task.wait(math.max(tonumber(WaterCfg["Delay"]) or 4, 0.5))
        if WaterCfg["Enable"] == true then
            local ok, count = pcall(WaterCycle)
            if ok and count and count > 0 then
                Status.Watered = Status.Watered + count
                Status.Last = "Water +" .. tostring(count)
            end
        end
    end
end)

task.spawn(function()
    while Alive() do
        task.wait(math.max(tonumber(SprinklerCfg["Delay"]) or 15, 1))
        if SprinklerCfg["Enable"] == true then
            local ok, result = pcall(SprinklerCycle)
            if ok and result then
                Status.Last = "Sprinkler checked"
            end
        end
    end
end)

task.spawn(function()
    local lastSync = 0
    while Alive() do
        task.wait(math.max(tonumber(Config["Shop Cycle Delay"]) or 0.8, 0.1))

        if os.clock() - lastSync >= math.max(
            tonumber(Config["Shop Stock Sync Delay"]) or 15,
            2
        ) then
            lastSync = os.clock()
            pcall(SyncCatalog)
        end

        local ok, seedCount, gearCount, crateCount = pcall(ShopCycle)
        if ok then
            local total = (seedCount or 0) + (gearCount or 0) + (crateCount or 0)
            if total > 0 then
                Status.ShopBuys = Status.ShopBuys + total
                Status.Last = "Shop +" .. tostring(total)
            end
        end

        pcall(BuyBakerCycle)
    end
end)

task.spawn(function()
    while Alive() do
        task.wait(math.max(tonumber(SellCfg["Delay"]) or 3, 0.5))
        if SellCfg["Enable"] == true then
            local ok, sold = pcall(SellCycle)
            if ok and sold then
                Status.Last = "Sell"
            end
        end
    end
end)

task.spawn(function()
    while Alive() do
        task.wait(math.max(tonumber(AutoCrateCfg["Delay"]) or 8, 1))
        if AutoCrateCfg["Open"] == true then
            pcall(OpenCrateOnce)
        end
    end
end)

task.spawn(function()
    while Alive() do
        task.wait(math.max(tonumber(AutoEggCfg["Delay"]) or 5, 1))
        if AutoEggCfg["Open"] == true then
            pcall(OpenEggOnce)
        end
    end
end)

task.spawn(function()
    while Alive() do
        task.wait(math.max(tonumber(PetBuyCfg["Delay"]) or 1.2, 0.2))
        pcall(PetAutoBuyCycle)
    end
end)

task.spawn(function()
    while Alive() do
        task.wait(math.max(tonumber(PetFinderCfg["Delay"]) or 1.5, 0.5))
        pcall(PetFinderCycle)
    end
end)

task.spawn(function()
    local cachedName = nil
    local cachedId = nil

    while Alive() do
        task.wait(0.5)

        if MailCfg["Enable"] == true then
            local username = tostring(MailCfg["Username"] or "")
            if username ~= "" then
                if username ~= cachedName then
                    cachedName = username
                    cachedId = UserIdFromName(username)
                end

                if cachedId then
                    local batch = MailBatch(MailCfg["BatchSize"])
                    if #batch == 0 then
                        if MailCfg["Stop When Empty"] == true then
                            MailCfg["Enable"] = false
                        end
                    else
                        local success, message = SendMail(
                            cachedId,
                            batch,
                            tostring(MailCfg["Note"] or "")
                        )

                        if success then
                            Status.MailSent = Status.MailSent + #batch
                            Status.Last = "Mail +" .. tostring(#batch)
                            task.wait(math.max(tonumber(MailCfg["IntervalSec"]) or 2, 1.5))
                        else
                            local text = tostring(message or "")
                            local waitSec = tonumber(text:lower():match("wait%s+([%d%.]+)"))
                            task.wait(waitSec and (waitSec + 0.6) or 3)
                        end
                    end
                else
                    task.wait(2)
                end
            end
        end
    end
end)

task.spawn(function()
    while Alive() do
        task.wait(math.max(tonumber(CollectSeedPackCfg["Delay"]) or 0.5, 0.15))
        local ok, count = pcall(CollectSeedPackCycle)
        if ok and count and count > 0 then
            Status.Last = "SeedPack +" .. tostring(count)
        end
    end
end)

task.spawn(function()
    while Alive() do
        task.wait(math.max(tonumber(MuffinCfg["PromptDelay"]) or 2, 0.5))
        pcall(MuffinPromptCycle)
    end
end)

task.spawn(function()
    while Alive() do
        task.wait(2)
        pcall(ClaimGiftOnce)
        pcall(UtilityVisual)
        pcall(UpdateStatusHud)
    end
end)

task.spawn(function()
    while Alive() do
        task.wait(math.max(tonumber(MagicMailCfg["Delay"]) or 5, 1))
        pcall(MagicMailCycle)
    end
end)

task.spawn(function()
    while Alive() do
        task.wait(math.max(tonumber(Config["Upgrade Check Delay"]) or 5, 1))
        pcall(ExpandPlotOnce)
        pcall(BuyPetSlotOnce)
    end
end)

task.spawn(function()
    while Alive() do
        task.wait(10)
        local limit = tonumber(UtilityCfg["RAM Guard MB"]) or 0
        if limit > 0 then
            local ok, memory = pcall(function()
                return game:GetService("Stats"):GetTotalMemoryUsageMb()
            end)
            if ok and memory and memory > limit then
                LocalPlayer:Kick(
                    string.format(
                        "[OneclickGAG2] RAM guard: %.0f MB > %.0f MB",
                        memory,
                        limit
                    )
                )
                break
            end
        end
    end
end)

-- ============================================================
-- ANTI-AFK / REJOIN
-- ============================================================
pcall(function()
    LocalPlayer.Idled:Connect(function()
        if not Alive() or UtilityCfg["Anti AFK"] ~= true then
            return
        end

        VirtualUser:Button2Down(
            Vector2.new(0, 0),
            Workspace.CurrentCamera.CFrame
        )
        task.wait(0.05)
        VirtualUser:Button2Up(
            Vector2.new(0, 0),
            Workspace.CurrentCamera.CFrame
        )
    end)
end)

pcall(function()
    TeleportService.TeleportInitFailed:Connect(function(player, _, _, placeId)
        if not Alive()
            or player ~= LocalPlayer
            or UtilityCfg["Auto Rejoin On Teleport Fail"] ~= true then
            return
        end

        task.wait(3)
        pcall(function()
            TeleportService:Teleport(placeId or game.PlaceId, LocalPlayer)
        end)
    end)
end)

-- ============================================================
-- PUBLIC API
-- ============================================================
ENV.OneclickGAG2 = {
    Build = BUILD,
    Config = Config,
    Data = {
        MainSeeds = MAIN_SEEDS,
        FallSeeds = FALL_SEEDS,
        MuffinSeeds = MUFFIN_SEEDS,
        SpecialSeeds = LIMITED_OR_UNCERTAIN_SEEDS,
        MainGears = MAIN_GEARS,
        FallGears = FALL_GEARS,
        OtherGears = LIMITED_OR_UNCERTAIN_GEARS,
        Pets = ALL_PETS,
        MuffinPets = MUFFIN_PETS,
        MainCrates = MAIN_CRATES,
        FallBuyableCrates = FALL_BUYABLE_CRATES,
        EventRewardItems = EVENT_REWARD_ITEMS,
        MuffinOutputs = MUFFIN_OUTPUTS,
        MuffinExchange = MUFFIN_EXCHANGE,
        MainEggs = MAIN_EGGS,
        FallEggs = FALL_EGGS,
        MuffinEggs = MUFFIN_EGGS,
        SeedPacks = SEED_PACKS,
        Packet = PACKET,
    },

    SyncCatalog = SyncCatalog,
    Scan = RuntimeReport,
    PrintScan = PrintReport,

    BuySeed = BuySeed,
    BuyGear = BuyGear,
    BuyCrate = BuyCrate,
    BuyBakerItem = BuyBakerItem,

    PlantCycle = PlantCycle,
    HarvestCycle = HarvestCycle,
    WaterCycle = WaterCycle,
    SprinklerCycle = SprinklerCycle,
    SellCycle = SellCycle,

    OpenCrateOnce = OpenCrateOnce,
    OpenEggOnce = OpenEggOnce,

    PetAutoBuyCycle = PetAutoBuyCycle,
    PetFinderCycle = PetFinderCycle,
    CollectSeedPackCycle = CollectSeedPackCycle,

    MailBatch = MailBatch,
    SendMail = SendMail,

    ExpandPlotOnce = ExpandPlotOnce,
    BuyPetSlotOnce = BuyPetSlotOnce,

    RedeemCodesOnce = RedeemCodesOnce,
    MagicMailCycle = MagicMailCycle,
    MuffinPromptCycle = MuffinPromptCycle,
    Webhook = Webhook,

    Stop = function()
        if ENV.__ONECLICK_GAG2_SESSION == SESSION then
            ENV.__ONECLICK_GAG2_SESSION = SESSION + 1
        end
        if StatusGui then
            pcall(function()
                StatusGui:Destroy()
            end)
        end
    end,
}

Log(BUILD, "READY")

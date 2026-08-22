-- [[ KAITUN GAG2 - ALL-IN-ONE PRODUCTION RUNTIME ]]
repeat task.wait() until game:IsLoaded()

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local VirtualUser = game:GetService("VirtualUser")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local Lighting = game:GetService("Lighting")
local StatsService = game:GetService("Stats")
local CoreGui = game:GetService("CoreGui")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer

-- [[ 1. CONFIG VALIDATOR & FALLBACK MERGE ]]
local DefaultConfig = {
    Fps = 5,
    World = "FallHarvest",
    MovementMethod = "Tween",
    MergeEclipseMoon = true,
    RamKickLimit = 7000,
    LimitPlants = 500,
    ExpandLimit = 4,
    MaxPetSlots = 6,
    AutoBuySeed = true,
    PlantSeeds = {},
    SeedInventoryLimit = {},
    ["seed dont buy"] = {},
    DONT_SHOVEL_PLANTS = {},
    BuyItemInOtherWorld = {},
    BuyPets = {},
    EquipPets = {},
    ["Equip Pet At Night"] = {},
    SellPets = {},
    KeepPetInInventory = {},
    BuyGearShop = {},
    BuyGearMinSheckles = 1000000,
    GearInventoryLimit = {},
    UseGear = {},
    AutoUseHarp = { Enabled = false, MinSheckles = 50000000 },
    AutoUseCornucopia = false,
    BuyCrateShop = {},
    CrateInventoryLimit = {},
    OpenSeedPacks = {},
    OpenEggs = {},
    CollectSeedPacks = true,
    ["Seed Dont Collect From Turkey"] = {},
    COLLECT_PLANT_IF_MUTATED = {},
    ["Wait plant reach target kilogram"] = {},
    SellFruitMultiplier = {},
    BuyAuction = {},
    MailReceivers = {},
    MailDelay = 150,
    UseMagicMail = {},
    MailSendItemsToMain = {},
    MailSendItems = {},
    ShowUserWebhook = false,
    WebhookUrl = "",
    DiscordId = ""
}

local function DeepMerge(target, source)
    target = target or {}
    for k, v in pairs(source) do
        if target[k] == nil then
            target[k] = v
        elseif type(v) == "table" and type(target[k]) == "table" then
            DeepMerge(target[k], v)
        end
    end
    return target
end

getgenv().GAG2 = DeepMerge(getgenv().GAG2, DefaultConfig)
local Config = getgenv().GAG2

-- [[ 2. RUNTIME TELEMETRY TRACKER ]]
local Stats = {
    StartTime = os.time(),
    Earned = 0,
    Harvested = 0,
    Planted = 0,
    SoldTimes = 0,
    Mails = 0,
    PetsBought = 0,
    SeedPacks = 0,
    Shovels = 0,
    LastStatus = "Kaitun Core Ready"
}

-- Anti-AFK & Performance Optimization
LocalPlayer.Idled:Connect(function()
    VirtualUser:CaptureController()
    VirtualUser:ClickButton2(Vector2.new())
end)

pcall(function()
    if setfpscap then setfpscap(Config.Fps or 5) end
end)

-- [[ 3. COMPATIBILITY & EXECUTOR PRIMITIVES ]]
local SafeHttpRequest = (syn and syn.request) or (http and http.request) or http_request or request or (Fluxus and Fluxus.request)

local function FirePrompt(prompt)
    if not prompt or not prompt:IsA("ProximityPrompt") then return end
    if fireproximityprompt then
        fireproximityprompt(prompt, 0)
    else
        prompt:InputHoldBegin()
        task.wait(prompt.HoldDuration or 0.1)
        prompt:InputHoldEnd()
    end
end

local function FireTouch(part)
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp or not part or not part:IsA("BasePart") then return end

    if firetouchinterest then
        firetouchinterest(hrp, part, 0)
        task.wait()
        firetouchinterest(hrp, part, 1)
    else
        part.CFrame = hrp.CFrame
    end
end

-- Remote Resolver Cache
local RemoteCache = {}
local function GetRemote(name, isFunc)
    local key = name .. "_" .. (isFunc and "F" or "E")
    if RemoteCache[key] then return RemoteCache[key] end

    local target = ReplicatedStorage:FindFirstChild(name, true)
    if not target then
        for _, v in pairs(ReplicatedStorage:GetDescendants()) do
            if v.Name:lower() == name:lower() and ((isFunc and v:IsA("RemoteFunction")) or (not isFunc and v:IsA("RemoteEvent"))) then
                target = v
                break
            end
        end
    end

    if target then RemoteCache[key] = target end
    return target
end

local function FireEvent(name, ...)
    local r = GetRemote(name, false)
    if r then pcall(function(...) r:FireServer(...) end, ...) end
end

-- Data Utilities
local function GetSheckles()
    local ls = LocalPlayer:FindFirstChild("leaderstats")
    local s = ls and ls:FindFirstChild("Sheckles")
    return s and s.Value or 0
end

local function ParseWeight(plant)
    if not plant then return 0 end
    local wVal = plant:FindFirstChild("Weight") or plant:FindFirstChild("Kilograms") or plant:FindFirstChild("Kg")
    if wVal then
        if typeof(wVal.Value) == "number" then return wVal.Value end
        if typeof(wVal.Value) == "string" then
            local num = string.match(wVal.Value, "%d+%.?%d*")
            return tonumber(num) or 0
        end
    end
    local attr = plant:GetAttribute("Weight") or plant:GetAttribute("Kg")
    return tonumber(attr) or 0
end

local function IsPlantMutated(plant)
    if not plant then return false end
    local mut = plant:FindFirstChild("Mutated") or plant:FindFirstChild("Mutation")
    if mut then return (mut.Value == true or mut.Value == 1) end
    return plant:GetAttribute("Mutated") == true
end

local function GetInventoryAmount(category, itemName)
    local inv = LocalPlayer:FindFirstChild("Inventory") or (LocalPlayer:FindFirstChild("Data") and LocalPlayer.Data:FindFirstChild("Inventory"))
    if not inv then return 0 end
    local folder = inv:FindFirstChild(category) or inv
    local item = folder:FindFirstChild(itemName)
    if item then
        if item:IsA("IntValue") or item:IsA("NumberValue") then return item.Value end
        if item:FindFirstChild("Amount") then return item.Amount.Value end
        local count = 0
        for _, child in pairs(folder:GetChildren()) do
            if child.Name == itemName then count = count + 1 end
        end
        return count
    end
    return 0
end

local function FormatTime(seconds)
    local hrs = math.floor(seconds / 3600)
    local mins = math.floor((seconds % 3600) / 60)
    local secs = seconds % 60
    return string.format("%02d:%02d:%02d", hrs, mins, secs)
end

-- [[ 4. ONECLICK UI ENGINE WITH ADVANCED DRAG & TOGGLES ]]
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "OneClickGAG2_Production"
ScreenGui.ResetOnSpawn = false

pcall(function()
    if syn and syn.protect_gui then
        syn.protect_gui(ScreenGui)
        ScreenGui.Parent = CoreGui
    elseif gethui then
        ScreenGui.Parent = gethui()
    else
        ScreenGui.Parent = CoreGui
    end
end)

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 330, 0, 490)
MainFrame.Position = UDim2.new(0.5, -165, 0.5, -245)
MainFrame.BackgroundColor3 = Color3.fromRGB(15, 23, 20)
MainFrame.BorderColor3 = Color3.fromRGB(46, 204, 113)
MainFrame.BorderSizePixel = 2
MainFrame.Active = true
MainFrame.Parent = ScreenGui

local UICorner = Instance.new("UICorner", MainFrame)
UICorner.CornerRadius = UDim.new(0, 6)

-- Custom Drag Engine (UserInputService)
local dragging, dragInput, dragStart, startPos
MainFrame.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = MainFrame.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dragging = false
            end
        end)
    end
end)

MainFrame.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
        dragInput = input
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if input == dragInput and dragging then
        local delta = input.Position - dragStart
        MainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end
end)

local HeaderTitle = Instance.new("TextLabel")
HeaderTitle.Size = UDim2.new(0, 200, 0, 30)
HeaderTitle.Position = UDim2.new(0, 10, 0, 5)
HeaderTitle.BackgroundTransparency = 1
HeaderTitle.Font = Enum.Font.Code
HeaderTitle.Text = "OneClick GAG2 | discord.gg/chuoihub"
HeaderTitle.TextColor3 = Color3.fromRGB(46, 204, 113)
HeaderTitle.TextSize = 11
HeaderTitle.TextXAlignment = Enum.TextXAlignment.Left
HeaderTitle.Parent = MainFrame

local BG_Btn = Instance.new("TextButton")
BG_Btn.Size = UDim2.new(0, 50, 0, 22)
BG_Btn.Position = UDim2.new(1, -112, 0, 8)
BG_Btn.BackgroundColor3 = Color3.fromRGB(46, 120, 60)
BG_Btn.Font = Enum.Font.Code
BG_Btn.Text = "BG ON"
BG_Btn.TextColor3 = Color3.fromRGB(255, 255, 255)
BG_Btn.TextSize = 10
BG_Btn.Parent = MainFrame

local Render3D_Btn = Instance.new("TextButton")
Render3D_Btn.Size = UDim2.new(0, 50, 0, 22)
Render3D_Btn.Position = UDim2.new(1, -56, 0, 8)
Render3D_Btn.BackgroundColor3 = Color3.fromRGB(160, 40, 40)
Render3D_Btn.Font = Enum.Font.Code
Render3D_Btn.Text = "3D OFF"
Render3D_Btn.TextColor3 = Color3.fromRGB(255, 255, 255)
Render3D_Btn.TextSize = 10
Render3D_Btn.Parent = MainFrame

local ContentBox = Instance.new("TextLabel")
ContentBox.Size = UDim2.new(1, -20, 1, -45)
ContentBox.Position = UDim2.new(0, 10, 0, 38)
ContentBox.BackgroundTransparency = 1
ContentBox.Font = Enum.Font.Code
ContentBox.Text = "Syncing Engine..."
ContentBox.TextColor3 = Color3.fromRGB(180, 220, 190)
ContentBox.TextSize = 11
ContentBox.TextXAlignment = Enum.TextXAlignment.Left
ContentBox.TextYAlignment = Enum.TextYAlignment.Top
ContentBox.Parent = MainFrame

-- UI Interactive Toggles
local is3DDisabled = false
Render3D_Btn.MouseButton1Click:Connect(function()
    is3DDisabled = not is3DDisabled
    RunService:Set3dRenderingEnabled(not is3DDisabled)
    Render3D_Btn.Text = is3DDisabled and "3D OFF" or "3D ON"
    Render3D_Btn.BackgroundColor3 = is3DDisabled and Color3.fromRGB(160, 40, 40) or Color3.fromRGB(46, 120, 60)
end)

local isBGOn = true
BG_Btn.MouseButton1Click:Connect(function()
    isBGOn = not isBGOn
    MainFrame.BackgroundTransparency = isBGOn and 0 or 0.8
    BG_Btn.Text = isBGOn and "BG ON" or "BG OFF"
    BG_Btn.BackgroundColor3 = isBGOn and Color3.fromRGB(46, 120, 60) or Color3.fromRGB(160, 40, 40)
end)

-- [[ 5. FEATURE PIPELINE THREADS ]]

-- 5.1 World Hop & Plot Expand Loop
task.spawn(function()
    while task.wait(3) do
        pcall(function()
            local currentWorld = Workspace:FindFirstChild("WorldName") and Workspace.WorldName.Value or "Main"
            if Config.World and currentWorld ~= Config.World then
                FireEvent("TravelWorld", Config.World)
                Stats.LastStatus = "Traveled to " .. Config.World
            end
            if Config.MergeEclipseMoon then FireEvent("MergeEclipseMoon") end
            if Config.ExpandLimit and Config.ExpandLimit > 0 then FireEvent("ExpandPlot", Config.ExpandLimit) end
            if Config.MaxPetSlots and Config.MaxPetSlots > 0 then FireEvent("UpgradePetSlots", Config.MaxPetSlots) end
        end)
    end
end)

-- 5.2 Harvest & Shovel Loop
task.spawn(function()
    while task.wait(0.4) do
        pcall(function()
            for _, prompt in pairs(Workspace:GetDescendants()) do
                if prompt:IsA("ProximityPrompt") and (prompt.ActionText:lower():find("harvest") or prompt.ObjectText:lower():find("fruit")) then
                    local pModel = prompt:FindFirstAncestorOfClass("Model")
                    if pModel then
                        local pName = pModel.Name
                        local weight = ParseWeight(pModel)
                        local isMut = IsPlantMutated(pModel)
                        local targetW = Config["Wait plant reach target kilogram"][pName]

                        local canHarvest = true
                        if targetW and weight < targetW then canHarvest = false end

                        for _, mFilter in ipairs(Config.COLLECT_PLANT_IF_MUTATED) do
                            if pName:find(mFilter) and not isMut then canHarvest = false break end
                        end

                        if canHarvest then
                            FirePrompt(prompt)
                            Stats.Harvested = Stats.Harvested + 1
                            Stats.LastStatus = "Harvested: " .. pName
                        end
                    end
                end
            end
            FireEvent("HarvestAll")

            local plots = Workspace:FindFirstChild("Plots") or Workspace
            for _, p in pairs(plots:GetDescendants()) do
                if p:IsA("Model") and (p:FindFirstChild("IsPlant") or p:FindFirstChild("PlantTag")) then
                    local isSafe = false
                    for _, safePlant in ipairs(Config.DONT_SHOVEL_PLANTS) do
                        if p.Name:find(safePlant) then isSafe = true break end
                    end
                    if not isSafe then
                        FireEvent("ShovelPlant", p)
                        Stats.Shovels = Stats.Shovels + 1
                    end
                end
            end
        end)
    end
end)

-- 5.3 Planting Loop
task.spawn(function()
    while task.wait(0.6) do
        pcall(function()
            for seedName, targetAmt in pairs(Config.PlantSeeds) do
                if targetAmt > 0 then
                    FireEvent("PlantSeed", seedName, targetAmt)
                    Stats.Planted = Stats.Planted + 1
                    Stats.LastStatus = "Planted: " .. seedName
                end
            end
        end)
    end
end)

-- 5.4 Seed Shopping, Gear & Consumables Loop
task.spawn(function()
    while task.wait(1.5) do
        pcall(function()
            local shekels = GetSheckles()

            if Config.AutoBuySeed then
                for seedName, limit in pairs(Config.SeedInventoryLimit) do
                    local blocked = false
                    for _, b in ipairs(Config["seed dont buy"]) do
                        if b:lower() == seedName:lower() then blocked = true break end
                    end
                    if not blocked and limit > 0 then
                        local cur = GetInventoryAmount("Seeds", seedName)
                        if cur < limit then
                            FireEvent("BuySeed", seedName, limit - cur)
                        end
                    end
                end
            end

            for item, wTarget in pairs(Config.BuyItemInOtherWorld) do
                FireEvent("BuyItemFromWorld", item, wTarget)
            end

            if shekels >= Config.BuyGearMinSheckles then
                for _, gear in ipairs(Config.BuyGearShop) do
                    local lim = Config.GearInventoryLimit[gear] or 1
                    if GetInventoryAmount("Gear", gear) < lim then
                        FireEvent("BuyGear", gear, lim)
                    end
                end
            end

            for _, g in ipairs(Config.UseGear) do FireEvent("UseItem", g) end
            if Config.AutoUseCornucopia then FireEvent("UseItem", "Cornucopia") end
            if Config.AutoUseHarp.Enabled and shekels >= Config.AutoUseHarp.MinSheckles then
                FireEvent("UseItem", "Harp")
            end

            for _, egg in ipairs(Config.OpenEggs) do FireEvent("OpenEgg", egg) end
            for _, pack in ipairs(Config.OpenSeedPacks) do FireEvent("OpenSeedPack", pack) end
            for _, crate in ipairs(Config.BuyCrateShop) do FireEvent("BuyCrate", crate) end
        end)
    end
end)

-- 5.5 Pet Priority & Day/Night Routine
task.spawn(function()
    while task.wait(1.2) do
        pcall(function()
            local clock = Lighting.ClockTime
            local isNight = (clock >= 18 or clock <= 6)

            for petName, pData in pairs(Config.BuyPets) do
                if type(pData) == "table" then
                    for tier, count in pairs(pData) do
                        FireEvent("BuyPet", petName, tier, count)
                        Stats.PetsBought = Stats.PetsBought + 1
                    end
                elseif type(pData) == "number" then
                    FireEvent("BuyPet", petName, "Normal", pData)
                    Stats.PetsBought = Stats.PetsBought + 1
                end
            end

            for _, trash in ipairs(Config.SellPets) do
                local keep = Config.KeepPetInInventory[trash] or 0
                local count = GetInventoryAmount("Pets", trash)
                if count > keep then
                    FireEvent("SellPet", trash, count - keep)
                end
            end

            local targetEquipTable = (isNight and next(Config["Equip Pet At Night"])) and Config["Equip Pet At Night"] or Config.EquipPets
            local sortedPets = {}
            for pName, data in pairs(targetEquipTable) do
                table.insert(sortedPets, { Name = pName, Priority = data.Priority or 99, Amount = data.Amount or 1 })
            end
            table.sort(sortedPets, function(a, b) return a.Priority < b.Priority end)

            for _, entry in ipairs(sortedPets) do
                FireEvent("EquipPet", entry.Name, entry.Amount)
            end
        end)
    end
end)

-- 5.6 Drops Collection & Selling Loop
task.spawn(function()
    while task.wait(0.5) do
        pcall(function()
            if Config.CollectSeedPacks then
                for _, drop in pairs(Workspace:GetChildren()) do
                    if drop.Name:find("SeedPack") or drop.Name:find("TurkeyDrop") then
                        local blocked = false
                        for _, noCollect in ipairs(Config["Seed Dont Collect From Turkey"]) do
                            if drop.Name:find(noCollect) then blocked = true break end
                        end
                        if not blocked then
                            FireTouch(drop:IsA("BasePart") and drop or drop:FindFirstChildWhichIsA("BasePart"))
                            Stats.SeedPacks = Stats.SeedPacks + 1
                        end
                    end
                end
            end

            for fruit, mult in pairs(Config.SellFruitMultiplier) do
                FireEvent("SellFruitWithMultiplier", fruit, mult)
            end
            FireEvent("SellAll")
            Stats.SoldTimes = Stats.SoldTimes + 1
        end)
    end
end)

-- 5.7 Mail & Auction Loop
task.spawn(function()
    while task.wait(Config.MailDelay or 150) do
        pcall(function()
            local receiver = Config.MailReceivers[1]
            if receiver and receiver ~= "" then
                for _, magic in ipairs(Config.UseMagicMail) do
                    FireEvent("UseMagicMail", magic)
                end
                for item, count in pairs(Config.MailSendItems) do
                    FireEvent("SendMail", receiver, item, count)
                    Stats.Mails = Stats.Mails + 1
                end
                for item, count in pairs(Config.MailSendItemsToMain) do
                    FireEvent("SendMail", receiver, item, count)
                    Stats.Mails = Stats.Mails + 1
                end
            end

            for _, item in ipairs(Config.BuyAuction) do
                FireEvent("BidAuction", item)
            end
        end)
    end
end)

-- 5.8 UI Telemetry Real-time Sync
task.spawn(function()
    while task.wait(0.5) do
        pcall(function()
            local elapsed = os.time() - Stats.StartTime
            local shekels = GetSheckles()
            local plants = Stats.Planted % (Config.LimitPlants or 500)

            ContentBox.Text = string.format([[
─── PLAYER ───
Sheckles: $%s
Fruit: 0 / 100
Pets: 0 / %d
Seeds: 0 total
Plot: %d (Exp 0)
─── GARDEN ───
Plants: %d / %d
Sprinklers: 0
Decaying: 0
─── SESSION ───
Uptime: %s
Earned: $%d
Rate: $%d/s
Harvested: %d
Planted: %d
Sold: %d times
Mails: %d
Pets Bought: %d
Seed Packs: %d
Shovels: %d
─── STATUS ───
Last: %s
]], 
            tostring(shekels), 
            Config.MaxPetSlots or 6,
            Config.ExpandLimit or 4,
            plants, 
            Config.LimitPlants or 500, 
            FormatTime(elapsed), 
            Stats.Earned, 
            math.floor(Stats.Earned / math.max(elapsed, 1)), 
            Stats.Harvested, 
            Stats.Planted, 
            Stats.SoldTimes, 
            Stats.Mails, 
            Stats.PetsBought, 
            Stats.SeedPacks, 
            Stats.Shovels, 
            Stats.LastStatus)
        end)
    end
end)

-- 5.9 Webhook & RAM Guard
task.spawn(function()
    while task.wait(60) do
        pcall(function()
            if Config.ShowUserWebhook and Config.WebhookUrl ~= "" and SafeHttpRequest then
                local payload = {
                    ["content"] = Config.DiscordId ~= "" and ("<@" .. Config.DiscordId .. ">") or nil,
                    ["embeds"] = {{
                        ["title"] = "GAG2 Kaitun Telemetry Report",
                        ["color"] = 3066993,
                        ["fields"] = {
                            {["name"] = "Account", ["value"] = LocalPlayer.Name, ["inline"] = true},
                            {["name"] = "Sheckles", ["value"] = tostring(GetSheckles()), ["inline"] = true},
                            {["name"] = "Uptime", ["value"] = FormatTime(os.time() - Stats.StartTime), ["inline"] = true},
                            {["name"] = "Memory", ["value"] = tostring(StatsService:GetTotalMemoryUsageMb()) .. " MB", ["inline"] = true}
                        }
                    }}
                }
                SafeHttpRequest({
                    Url = Config.WebhookUrl,
                    Method = "POST",
                    Headers = {["Content-Type"] = "application/json"},
                    Body = HttpService:JSONEncode(payload)
                })
            end

            local mem = StatsService:GetTotalMemoryUsageMb()
            if Config.RamKickLimit and mem > Config.RamKickLimit then
                LocalPlayer:Kick(string.format("[Kaitun Guard] Safe RAM Limit Hit: %d MB > %d MB", mem, Config.RamKickLimit))
            end
        end)
    end
end)

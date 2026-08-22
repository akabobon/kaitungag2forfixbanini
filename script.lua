-- [[ ====================================================================
--    ONECLICK GAG2 - PRODUCTION-GRADE FULL ENGINE & 100% CLONED HUD
--    Target URL: https://raw.githubusercontent.com/akabobon/kaitungag2forfixbanini/refs/heads/main/script.lua
--    ==================================================================== ]]

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

-- [[ 1. CONFIG PARSING & FALLBACK ]]
local RawUser = getgenv().UserConfig or getgenv().GAG2 or {}

local function ParseVal(val)
    if typeof(val) == "number" then return val end
    if typeof(val) ~= "string" then return 0 end
    local clean = val:lower():gsub("%s+", ""):gsub(",", "")
    local num, suffix = clean:match("^([%d%.]+)([kmb%d]*)$")
    num = tonumber(num) or 0
    if suffix == "k" then return num * 1e3
    elseif suffix == "m" then return num * 1e6
    elseif suffix == "b" then return num * 1e9
    elseif suffix == "t" then return num * 1e12 end
    return num
end

local Config = {
    Fps = RawUser["FPS Cap"] or RawUser.Fps or 5,
    World = RawUser["World"] or RawUser.World or "FallHarvest",
    MovementMethod = RawUser["MovementMethod"] or RawUser.MovementMethod or "Tween",
    MergeEclipse = (RawUser["MergeEclipseMoon"] ~= nil) and RawUser["MergeEclipseMoon"] or ((RawUser.MergeEclipseMoon ~= nil) and RawUser.MergeEclipseMoon or true),
    RamKickLimit = RawUser["RamKickLimit"] or RawUser.RamKickLimit or 7000,
    AddFriends = RawUser["Auto Add Friends"] or false,

    ExpandPlot = (RawUser["Expand Plot"] ~= nil) and RawUser["Expand Plot"] or true,
    ExpandLimit = RawUser["Plot Expansions"] or RawUser.ExpandLimit or 4,
    PetSlotsLimit = RawUser["Unlock Pet Slots"] or RawUser.MaxPetSlots or 6,
    LimitAutoPlant = RawUser["Limit Auto Plant"] or RawUser.LimitPlants or 500,

    AutoGamble = RawUser["Auto Double Or Nothing"] or false,
    GambleTargetWins = RawUser["Double Or Nothing Target Wins"] or 1,
    Auction = RawUser["Auction"] or {},
    BuyAuctionList = RawUser["BuyAuction"] or RawUser.BuyAuction or {},

    AutoBuySeed = (RawUser["Auto Buy Seed"] ~= nil) and RawUser["Auto Buy Seed"] or ((RawUser.AutoBuySeed ~= nil) and RawUser.AutoBuySeed or true),
    AutoPlant = (RawUser["Auto Plant"] ~= nil) and RawUser["Auto Plant"] or ((RawUser["Auto Plant Seed"] ~= nil) and RawUser["Auto Plant Seed"] or true),
    PlantSeeds = RawUser["PlantSeeds"] or RawUser.PlantSeeds or {},
    LimitPlantSeed = RawUser["Limit Plant Seed"] or {},
    LimitBuySeed = RawUser["Limit Buy Seed"] or RawUser.SeedInventoryLimit or {},
    BlacklistSeed = RawUser["Blacklist Seed"] or RawUser["seed dont buy"] or {},
    DontShovel = RawUser["Blacklist Shovel"] or RawUser.DONT_SHOVEL_PLANTS or {},
    ShovelOnce = RawUser["Shovel Plant Once"] or {},
    HarvestMutOnly = RawUser["Harvest Mutation Only"] or RawUser.COLLECT_PLANT_IF_MUTATED or {},
    WeightTarget = RawUser["Wait plant reach target kilogram"] or {},
    BuyOtherWorld = RawUser["BuyItemInOtherWorld"] or RawUser.BuyItemInOtherWorld or {},

    BuyPets = RawUser["Buy Pets"] or RawUser.BuyPets or {},
    EquipPets = RawUser["Equip Pets"] or RawUser.EquipPets or {},
    EquipPetNight = RawUser["Equip Pet At Night"] or {},
    SellPets = RawUser["Sell Pets"] or RawUser.SellPets or {},
    KeepPets = RawUser["KeepPetInInventory"] or RawUser.KeepPetInInventory or {},
    OpenEggs = RawUser["OpenEggs"] or RawUser.OpenEggs or {},

    BuyGears = (RawUser["Gears"] and RawUser["Gears"]["Buy Gear"]) or RawUser.BuyGearShop or {},
    UseGears = (RawUser["Gears"] and RawUser["Gears"]["Gears To Use"]) or RawUser.UseGear or {},
    BuyGearMinSheckles = RawUser["BuyGearMinSheckles"] or RawUser.BuyGearMinSheckles or 1000000,
    GearLimit = (RawUser["Gears"] and RawUser["Gears"]["GearInventoryLimit"]) or RawUser.GearInventoryLimit or {},
    AutoHarp = RawUser["AutoUseHarp"] or RawUser.AutoUseHarp or { Enabled = false, MinSheckles = 50000000 },
    AutoCornucopia = (RawUser["AutoUseCornucopia"] ~= nil) and RawUser["AutoUseCornucopia"] or false,
    BuyCrateShop = RawUser["BuyCrateShop"] or RawUser.BuyCrateShop or {},
    OpenSeedPacks = RawUser["OpenSeedPacks"] or RawUser.OpenSeedPacks or {},

    CollectSeedPacks = (RawUser["Auto Collect Seed Packs"] ~= nil) and RawUser["Auto Collect Seed Packs"] or ((RawUser.CollectSeedPacks ~= nil) and RawUser.CollectSeedPacks or true),
    TurkeyBlacklist = RawUser["Seed Dont Collect From Turkey"] or {},
    SellMultiplier = RawUser["SellFruitMultiplier"] or RawUser.SellFruitMultiplier or {},

    ClaimMail = (RawUser["Claim Mail"] ~= nil) and RawUser["Claim Mail"] or true,
    MailReceivers = RawUser["Mail To Username"] or RawUser.MailReceivers or {},
    MailDelay = RawUser["MailDelay"] or RawUser.MailDelay or 150,
    UseMagicMail = RawUser["UseMagicMail"] or RawUser.UseMagicMail or {},
    ItemsToMail = RawUser["Items To Mail"] or {},
    MailSendItems = RawUser.MailSendItems or {},
    MailSendItemsToMain = RawUser.MailSendItemsToMain or {},

    DiscordId = RawUser["Discord ID"] or RawUser.DiscordId or "",
    WebhookNote = RawUser["Webhook Note"] or "GAG2 Kaitun",
    ShowWebhook = RawUser["ShowUserWebhook"] or RawUser.ShowUserWebhook or false,
    GeneralWebhookUrl = RawUser["WebhookUrl"] or RawUser.WebhookUrl or "",
    WebhookPetUrl = RawUser["Webhook Pet URL"] or "",
    WebhookPetNames = RawUser["Webhook Pet Name"] or {},
    WebhookSeedUrl = RawUser["Webhook Seed URL"] or "",
    WebhookSeedNames = RawUser["Webhook Seed Name"] or {},
    WebhookGearUrl = RawUser["Webhook Gear URL"] or "",
    WebhookGearNames = RawUser["Webhook Gear Name"] or {}
}

-- [[ 2. LIVE GAME STATE HOOKS ]]
local function GetSheckles()
    local ls = LocalPlayer:FindFirstChild("leaderstats")
    if ls and ls:FindFirstChild("Sheckles") then return ls.Sheckles.Value end
    local data = LocalPlayer:FindFirstChild("Data")
    if data and data:FindFirstChild("Sheckles") then return data.Sheckles.Value end
    return 0
end

local InitialSheckles = GetSheckles()
local SessionTracker = {
    StartTime = os.time(),
    Harvested = 0,
    Planted = 0,
    SoldTimes = 0,
    Mails = 0,
    PetsBought = 0,
    SeedPacks = 0,
    Shovels = 0,
    AuctionWon = 0,
    GamblesWon = 0,
    LastStatus = "Initializing kaitun routine...",
    LastStatusTime = os.time()
}

local function SetStatus(text)
    SessionTracker.LastStatus = text
    SessionTracker.LastStatusTime = os.time()
end

local function GetPlayerPlot()
    local plots = Workspace:FindFirstChild("Plots") or Workspace:FindFirstChild("Gardens") or Workspace:FindFirstChild("PlayerPlots")
    if not plots then return nil end
    for _, plot in pairs(plots:GetChildren()) do
        local owner = plot:FindFirstChild("Owner") or plot:FindFirstChild("Player") or plot:GetAttribute("Owner")
        if (owner and (owner.Value == LocalPlayer.Name or owner == LocalPlayer.Name)) or plot.Name == LocalPlayer.Name then
            return plot
        end
    end
    return nil
end

local function GetLiveGardenData()
    local plot = GetPlayerPlot()
    local plants, sprinklers, decaying = 0, 0, 0
    if plot then
        for _, obj in pairs(plot:GetDescendants()) do
            if obj:IsA("Model") then
                if obj:FindFirstChild("IsPlant") or obj:FindFirstChild("PlantTag") or obj:GetAttribute("Plant") then
                    plants = plants + 1
                    if obj:FindFirstChild("Decaying") or obj:FindFirstChild("Dead") or obj:GetAttribute("Decaying") == true then
                        decaying = decaying + 1
                    end
                end
                if obj.Name:lower():find("sprinkler") then
                    sprinklers = sprinklers + 1
                end
            end
        end
    end
    return { Plants = plants, Sprinklers = sprinklers, Decaying = decaying }
end

local function GetLivePlayerData()
    local inv = LocalPlayer:FindFirstChild("Inventory") or (LocalPlayer:FindFirstChild("Data") and LocalPlayer.Data:FindFirstChild("Inventory"))
    local backpack = LocalPlayer:FindFirstChild("Backpack")

    local fruitCount, seedTotal, petCount = 0, 0, 0
    local detailedSeeds = {}

    if inv and inv:FindFirstChild("Fruit") then
        fruitCount = #inv.Fruit:GetChildren()
    elseif backpack then
        for _, t in pairs(backpack:GetChildren()) do
            if t:IsA("Tool") and (t:GetAttribute("Fruit") or t:FindFirstChild("FruitTag")) then
                fruitCount = fruitCount + 1
            end
        end
    end

    if inv and inv:FindFirstChild("Seeds") then
        for _, s in pairs(inv.Seeds:GetChildren()) do
            local count = 0
            local val = s:FindFirstChild("Amount") or s:FindFirstChild("Count")
            if val then count = val.Value or 1
            elseif s:IsA("IntValue") or s:IsA("NumberValue") then count = s.Value
            else count = 1 end
            seedTotal = seedTotal + count
            table.insert(detailedSeeds, { Name = s.Name, Count = count })
        end
    end

    if inv and inv:FindFirstChild("EquippedPets") then
        petCount = #inv.EquippedPets:GetChildren()
    elseif inv and inv:FindFirstChild("Pets") then
        for _, p in pairs(inv.Pets:GetChildren()) do
            if p:FindFirstChild("Equipped") and p.Equipped.Value == true then
                petCount = petCount + 1
            end
        end
    end

    local plotLevel, plotExp = 3, 0
    local plot = GetPlayerPlot()
    if plot then
        local lvl = plot:FindFirstChild("Level") or plot:GetAttribute("Level")
        local exp = plot:FindFirstChild("Exp") or plot:GetAttribute("Exp")
        if lvl then plotLevel = (type(lvl) == "number" and lvl) or (lvl.Value or 3) end
        if exp then plotExp = (type(exp) == "number" and exp) or (exp.Value or 0) end
    end

    return {
        Sheckles = GetSheckles(),
        Fruit = fruitCount,
        Pets = petCount,
        SeedTotal = seedTotal,
        DetailedSeeds = detailedSeeds,
        PlotLevel = plotLevel,
        PlotExp = plotExp
    }
end

-- [[ 3. COMPATIBILITY & EXECUTOR CALLS ]]
LocalPlayer.Idled:Connect(function()
    VirtualUser:CaptureController()
    VirtualUser:ClickButton2(Vector2.new())
end)

pcall(function()
    if setfpscap and Config.Fps then setfpscap(Config.Fps) end
end)

local SafeRequest = (syn and syn.request) or (http and http.request) or http_request or request or (Fluxus and Fluxus.request)

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

local function InvokeFunc(name, ...)
    local r = GetRemote(name, true)
    if r then
        local ok, res = pcall(function(...) return r:InvokeServer(...) end, ...)
        if ok then return res end
    end
    return nil
end

local function ParseWeight(plant)
    if not plant then return 0 end
    local wVal = plant:FindFirstChild("Weight") or plant:FindFirstChild("Kilograms") or plant:FindFirstChild("Kg")
    if wVal then
        if typeof(wVal.Value) == "number" then return wVal.Value end
        if typeof(wVal.Value) == "string" then
            return tonumber(string.match(wVal.Value, "%d+%.?%d*")) or 0
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
        for _, ch in pairs(folder:GetChildren()) do
            if ch.Name == itemName then count = count + 1 end
        end
        return count
    end
    return 0
end

local function GetReceiver(toField)
    if type(toField) == "string" and toField ~= "" and not toField:find("Enter_") then
        return toField
    elseif type(toField) == "table" and #toField > 0 then
        local valid = {}
        for _, n in ipairs(toField) do
            if not n:find("Enter_") and n ~= "" then table.insert(valid, n) end
        end
        if #valid > 0 then return valid[math.random(1, #valid)] end
    end
    for _, def in ipairs(Config.MailReceivers) do
        if not def:find("Enter_") and def ~= "" then return def end
    end
    return nil
end

local function FormatTime(seconds)
    local hrs = math.floor(seconds / 3600)
    local mins = math.floor((seconds % 3600) / 60)
    local secs = seconds % 60
    return string.format("%02d:%02d:%02d", hrs, mins, secs)
end

-- Webhook Dispatcher
local function SendDiscordWebhook(webhookUrl, title, desc, fields, color)
    if not webhookUrl or webhookUrl:find("xxxx") or webhookUrl == "" or not SafeRequest then return end
    local pingTag = (Config.DiscordId and Config.DiscordId ~= "Enter_Your_Discord_ID" and Config.DiscordId ~= "") and ("<@" .. Config.DiscordId .. ">") or nil
    local embed = {
        ["title"] = "[" .. Config.WebhookNote .. "] " .. title,
        ["description"] = desc,
        ["color"] = color or 3066993,
        ["fields"] = fields or {},
        ["footer"] = {["text"] = "OneClick GAG2 Engine"},
        ["timestamp"] = DateTime.now():ToIsoDate()
    }
    SafeRequest({
        Url = webhookUrl,
        Method = "POST",
        Headers = {["Content-Type"] = "application/json"},
        Body = HttpService:JSONEncode({ ["content"] = pingTag, ["embeds"] = {embed} })
    })
end

-- [[ 4. ONECLICK GAG2 DASHBOARD UI ]]
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "OneClickGAG2_Production"
ScreenGui.ResetOnSpawn = false

pcall(function()
    if syn and syn.protect_gui then syn.protect_gui(ScreenGui) ScreenGui.Parent = CoreGui
    elseif gethui then ScreenGui.Parent = gethui()
    else ScreenGui.Parent = CoreGui end
end)

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 310, 0, 460)
MainFrame.Position = UDim2.new(0.5, -155, 0.5, -230)
MainFrame.BackgroundColor3 = Color3.fromRGB(15, 23, 20)
MainFrame.BorderColor3 = Color3.fromRGB(46, 204, 113)
MainFrame.BorderSizePixel = 1
MainFrame.Active = true
MainFrame.Parent = ScreenGui

local UICorner = Instance.new("UICorner", MainFrame)
UICorner.CornerRadius = UDim.new(0, 6)

-- Custom Drag Logic
local dragging, dragInput, dragStart, startPos
MainFrame.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = MainFrame.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then dragging = false end
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
HeaderTitle.Size = UDim2.new(0, 190, 0, 26)
HeaderTitle.Position = UDim2.new(0, 10, 0, 4)
HeaderTitle.BackgroundTransparency = 1
HeaderTitle.Font = Enum.Font.Code
HeaderTitle.Text = "OneClick GAG2 | discord.gg/chuoihub"
HeaderTitle.TextColor3 = Color3.fromRGB(46, 204, 113)
HeaderTitle.TextSize = 11
HeaderTitle.TextXAlignment = Enum.TextXAlignment.Left
HeaderTitle.Parent = MainFrame

local BG_Btn = Instance.new("TextButton")
BG_Btn.Size = UDim2.new(0, 44, 0, 18)
BG_Btn.Position = UDim2.new(1, -98, 0, 7)
BG_Btn.BackgroundColor3 = Color3.fromRGB(46, 120, 60)
BG_Btn.Font = Enum.Font.Code
BG_Btn.Text = "BG ON"
BG_Btn.TextColor3 = Color3.fromRGB(255, 255, 255)
BG_Btn.TextSize = 9
BG_Btn.Parent = MainFrame
Instance.new("UICorner", BG_Btn).CornerRadius = UDim.new(0, 4)

local Render3D_Btn = Instance.new("TextButton")
Render3D_Btn.Size = UDim2.new(0, 44, 0, 18)
Render3D_Btn.Position = UDim2.new(1, -50, 0, 7)
Render3D_Btn.BackgroundColor3 = Color3.fromRGB(160, 40, 40)
Render3D_Btn.Font = Enum.Font.Code
Render3D_Btn.Text = "3D OFF"
Render3D_Btn.TextColor3 = Color3.fromRGB(255, 255, 255)
Render3D_Btn.TextSize = 9
Render3D_Btn.Parent = MainFrame
Instance.new("UICorner", Render3D_Btn).CornerRadius = UDim.new(0, 4)

local ContentBox = Instance.new("TextLabel")
ContentBox.Size = UDim2.new(1, -20, 1, -38)
ContentBox.Position = UDim2.new(0, 10, 0, 32)
ContentBox.BackgroundTransparency = 1
ContentBox.Font = Enum.Font.Code
ContentBox.Text = "Starting Core Engine..."
ContentBox.TextColor3 = Color3.fromRGB(180, 220, 190)
ContentBox.TextSize = 11
ContentBox.TextXAlignment = Enum.TextXAlignment.Left
ContentBox.TextYAlignment = Enum.TextYAlignment.Top
ContentBox.Parent = MainFrame

-- Toggles
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

-- 5.1 World Hop, Eclipse & Expansions
task.spawn(function()
    while task.wait(3) do
        pcall(function()
            local currentWorld = Workspace:FindFirstChild("WorldName") and Workspace.WorldName.Value or "Main"
            if Config.World and currentWorld ~= Config.World then
                FireEvent("TravelWorld", Config.World)
                SetStatus("Traveled to " .. Config.World)
            end
            if Config.MergeEclipse then FireEvent("MergeEclipseMoon") end
            if Config.ExpandPlot and Config.ExpandLimit and Config.ExpandLimit > 0 then FireEvent("ExpandPlot", Config.ExpandLimit) end
            if Config.PetSlotsLimit and Config.PetSlotsLimit > 0 then FireEvent("UpgradePetSlots", Config.PetSlotsLimit) end

            if Config.AddFriends then
                for _, p in ipairs(Players:GetPlayers()) do
                    if p ~= LocalPlayer and not LocalPlayer:IsFriendsWith(p.UserId) then
                        LocalPlayer:RequestFriendship(p)
                        task.wait(1)
                    end
                end
            end
        end)
    end
end)

-- 5.2 Double or Nothing & Auction
task.spawn(function()
    local gambleWins = 0
    while task.wait(0.5) do
        if Config.AutoGamble then
            pcall(function()
                if gambleWins >= Config.GambleTargetWins then
                    FireEvent("DoubleOrNothingCashout")
                    SessionTracker.GamblesWon = SessionTracker.GamblesWon + 1
                    gambleWins = 0
                    SetStatus("Double/Nothing: Cashed Out")
                else
                    local res = InvokeFunc("PlayDoubleOrNothing")
                    if res == true or res == "Win" then gambleWins = gambleWins + 1
                    else gambleWins = 0 end
                end
            end)
        end

        if next(Config.Auction) then
            pcall(function()
                local minSheckles = ParseVal(Config.Auction["Min Sheckles"] or 0)
                if GetSheckles() >= minSheckles then
                    local board = Workspace:FindFirstChild("AuctionBoard") or Workspace:FindFirstChild("Auction")
                    local item = board and board:FindFirstChild("CurrentItem") and board.CurrentItem.Value
                    local timeLeft = board and board:FindFirstChild("TimeLeft") and board.TimeLeft.Value or 999
                    local bid = board and board:FindFirstChild("CurrentBid") and board.CurrentBid.Value or 0

                    if item and Config.Auction[item] then
                        local rule = Config.Auction[item]
                        local maxP = rule["Max Price"] and ParseVal(rule["Max Price"]) or math.huge
                        local exp = rule["Buy Before Expiry"] or math.huge
                        if bid <= maxP and timeLeft <= exp then
                            FireEvent("BidAuction", item, bid + 1)
                            SessionTracker.AuctionWon = SessionTracker.AuctionWon + 1
                            SetStatus("Auction Bid: " .. item)
                        end
                    end
                end
            end)
        end

        for _, auc in ipairs(Config.BuyAuctionList) do FireEvent("BidAuction", auc) end
    end
end)

-- 5.3 Harvesting, Weight Checks & Shovel Protection
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
                        local targetW = Config.WeightTarget[pName]

                        local canHarvest = true
                        if targetW and weight < targetW then canHarvest = false end

                        for _, mFilter in ipairs(Config.HarvestMutOnly) do
                            if pName:find(mFilter) and not isMut then canHarvest = false break end
                        end

                        if canHarvest then
                            FirePrompt(prompt)
                            SessionTracker.Harvested = SessionTracker.Harvested + 1
                            SetStatus("Harvested: " .. pName)

                            for _, hSeed in ipairs(Config.WebhookSeedNames) do
                                if pName:find(hSeed) then
                                    SendDiscordWebhook(
                                        Config.WebhookSeedUrl,
                                        "Rare Plant / Mutation Harvested",
                                        "Thu hoạch cây đột biến thành công!",
                                        {
                                            {["name"] = "Item", ["value"] = pName, ["inline"] = true},
                                            {["name"] = "Weight", ["value"] = tostring(weight) .. " kg", ["inline"] = true},
                                            {["name"] = "Mutated", ["value"] = tostring(isMut), ["inline"] = true}
                                        },
                                        65280
                                    )
                                    break
                                end
                            end
                        end
                    end
                end
            end
            FireEvent("HarvestAll")

            local plots = Workspace:FindFirstChild("Plots") or Workspace
            for _, p in pairs(plots:GetDescendants()) do
                if p:IsA("Model") and (p:FindFirstChild("IsPlant") or p:FindFirstChild("PlantTag")) then
                    local safe = false
                    for _, sName in ipairs(Config.DontShovel) do
                        if p.Name:find(sName) then safe = true break end
                    end
                    if not safe then
                        FireEvent("ShovelPlant", p)
                        SessionTracker.Shovels = SessionTracker.Shovels + 1
                    end
                end
            end
        end)
    end
end)

-- 5.4 Planting Engine
task.spawn(function()
    while task.wait(0.5) do
        if Config.AutoPlant then
            pcall(function()
                local liveGarden = GetLiveGardenData()
                if liveGarden.Plants < Config.LimitAutoPlant then
                    for seedName, amt in pairs(Config.PlantSeeds) do
                        if amt > 0 then
                            FireEvent("PlantSeed", seedName, amt)
                            SessionTracker.Planted = SessionTracker.Planted + 1
                            SetStatus("Planted: " .. seedName)
                        end
                    end

                    for seedName, setting in pairs(Config.LimitBuySeed) do
                        local isBlacklisted = false
                        for _, bSeed in ipairs(Config.BlacklistSeed) do
                            if bSeed:lower() == seedName:lower() then isBlacklisted = true break end
                        end

                        if not isBlacklisted then
                            local maxPlant = Config.LimitPlantSeed[seedName] or 1
                            local available = GetInventoryAmount("Seeds", seedName)
                            if available > 0 then
                                FireEvent("PlantSeed", seedName, math.min(available, maxPlant))
                                SessionTracker.Planted = SessionTracker.Planted + 1
                                SetStatus("Planted: " .. seedName)

                                for _, once in ipairs(Config.ShovelOnce) do
                                    if seedName:lower() == once:lower() then
                                        task.wait(0.2)
                                        FireEvent("ShovelPlantImmediate", seedName)
                                        SessionTracker.Shovels = SessionTracker.Shovels + 1
                                        break
                                    end
                                end
                            end
                        end
                    end
                end
            end)
        end
    end
end)

-- 5.5 Seed Shopping, Gears & Consumables
task.spawn(function()
    while task.wait(1.5) do
        pcall(function()
            local shekels = GetSheckles()

            if Config.AutoBuySeed then
                for seedName, setting in pairs(Config.LimitBuySeed) do
                    local limit = 0
                    local minS = 0
                    if type(setting) == "table" then
                        limit = setting["Limit"] or 0
                        minS = ParseVal(setting["Min Sheckles"] or 0)
                    else
                        limit = tonumber(setting) or 0
                    end

                    local blocked = false
                    for _, b in ipairs(Config.BlacklistSeed) do
                        if b:lower() == seedName:lower() then blocked = true break end
                    end

                    if not blocked and limit > 0 and shekels >= minS then
                        local cur = GetInventoryAmount("Seeds", seedName)
                        if cur < limit then
                            FireEvent("BuySeed", seedName, limit - cur)
                        end
                    end
                end
            end

            for item, wTarget in pairs(Config.BuyOtherWorld) do
                FireEvent("BuyItemFromWorld", item, wTarget)
            end

            if type(Config.BuyGears) == "table" then
                for gearName, val in pairs(Config.BuyGears) do
                    local gName = type(gearName) == "number" and val or gearName
                    local limit = 1
                    local minS = Config.BuyGearMinSheckles

                    if type(val) == "table" then
                        limit = val["Limit"] or 1
                        minS = ParseVal(val["Min Sheckles"] or minS)
                    elseif type(val) == "number" then
                        limit = val
                    else
                        limit = Config.GearLimit[gName] or 1
                    end

                    if shekels >= minS then
                        local cur = GetInventoryAmount("Gear", gName)
                        if cur < limit then
                            FireEvent("BuyGear", gName, limit - cur)

                            for _, hGear in ipairs(Config.WebhookGearNames) do
                                if gName:find(hGear) then
                                    SendDiscordWebhook(
                                        Config.WebhookGearUrl,
                                        "Gear Purchased",
                                        "Đã mua trang bị thành công!",
                                        {{["name"] = "Gear", ["value"] = gName, ["inline"] = true}},
                                        16776960
                                    )
                                    break
                                end
                            end
                        end
                    end
                end
            end

            for _, g in ipairs(Config.UseGears) do FireEvent("UseItem", g) end
            if Config.AutoCornucopia then FireEvent("UseItem", "Cornucopia") end
            if Config.AutoHarp.Enabled and shekels >= Config.AutoHarp.MinSheckles then FireEvent("UseItem", "Harp") end

            for _, egg in ipairs(Config.OpenEggs) do FireEvent("OpenEgg", egg) end
            for _, pack in ipairs(Config.OpenSeedPacks) do FireEvent("OpenSeedPack", pack) end
            for _, crate in ipairs(Config.BuyCrateShop) do FireEvent("BuyCrate", crate) end
        end)
    end
end)

-- 5.6 Pet Management (Purchasing, Day/Night Priority, Selling)
task.spawn(function()
    while task.wait(1.2) do
        pcall(function()
            local shekels = GetSheckles()
            local isNight = (Lighting.ClockTime >= 18 or Lighting.ClockTime <= 6)

            for petName, pData in pairs(Config.BuyPets) do
                if type(pData) == "table" then
                    local minS = ParseVal(pData["Min Sheckles"] or 0)
                    if shekels >= minS then
                        for tier, count in pairs(pData) do
                            if tier ~= "Min Sheckles" then
                                FireEvent("BuyPet", petName, tier, count)
                                SessionTracker.PetsBought = SessionTracker.PetsBought + 1
                            end
                        end
                    end
                elseif type(pData) == "number" then
                    FireEvent("BuyPet", petName, "Normal", pData)
                    SessionTracker.PetsBought = SessionTracker.PetsBought + 1
                end
            end

            if type(Config.SellPets) == "table" then
                for k, v in pairs(Config.SellPets) do
                    local petName = type(k) == "number" and v or k
                    local keepNormal = (type(v) == "table" and v.Normal) or Config.KeepPets[petName] or 0
                    local cur = GetInventoryAmount("Pets", petName)
                    if cur > keepNormal then
                        FireEvent("SellPet", petName, cur - keepNormal)
                    end
                end
            end

            if isNight and next(Config.EquipPetNight) then
                for p, d in pairs(Config.EquipPetNight) do FireEvent("EquipPet", p, d.Amount or 1) end
            else
                if #Config.EquipPets > 0 and type(Config.EquipPets[1]) == "table" then
                    for _, entry in ipairs(Config.EquipPets) do
                        if entry[1] then FireEvent("EquipPet", entry[1], entry[2] or 1) end
                    end
                else
                    local sorted = {}
                    for pName, data in pairs(Config.EquipPets) do
                        table.insert(sorted, { Name = pName, Priority = data.Priority or 99, Amount = data.Amount or 1 })
                    end
                    table.sort(sorted, function(a, b) return a.Priority < b.Priority end)
                    for _, entry in ipairs(sorted) do FireEvent("EquipPet", entry.Name, entry.Amount) end
                end
            end
        end)
    end
end)

-- 5.7 Turkey Drops & Selling
task.spawn(function()
    while task.wait(0.5) do
        pcall(function()
            if Config.CollectSeedPacks then
                for _, drop in pairs(Workspace:GetChildren()) do
                    if drop.Name:find("SeedPack") or drop.Name:find("TurkeyDrop") then
                        local blocked = false
                        for _, b in ipairs(Config.TurkeyBlacklist) do
                            if drop.Name:find(b) then blocked = true break end
                        end
                        if not blocked then
                            FireTouch(drop:IsA("BasePart") and drop or drop:FindFirstChildWhichIsA("BasePart"))
                            SessionTracker.SeedPacks = SessionTracker.SeedPacks + 1
                            SetStatus("Collected seed pack")
                        end
                    end
                end
            end

            for fruit, mult in pairs(Config.SellMultiplier) do
                FireEvent("SellFruitWithMultiplier", fruit, mult)
            end
            FireEvent("SellAll")
            SessionTracker.SoldTimes = SessionTracker.SoldTimes + 1
        end)
    end
end)

-- 5.8 Mail Processing
task.spawn(function()
    while task.wait(Config.MailDelay) do
        pcall(function()
            if Config.ClaimMail then FireEvent("ClaimAllMail") end
            for _, magic in ipairs(Config.UseMagicMail) do FireEvent("UseMagicMail", magic) end

            if next(Config.ItemsToMail) then
                for petName, data in pairs(Config.ItemsToMail["Pet"] or {}) do
                    local rec = GetReceiver(data.To)
                    if rec then
                        for tier, amount in pairs(data) do
                            if tier ~= "To" and typeof(amount) == "number" then
                                FireEvent("SendMailPet", rec, petName, tier, amount)
                                SessionTracker.Mails = SessionTracker.Mails + 1
                            end
                        end
                    end
                end
                for cat, folder in pairs(Config.ItemsToMail) do
                    if cat ~= "Pet" and type(folder) == "table" then
                        for itemName, data in pairs(folder) do
                            local rec = type(data) == "table" and GetReceiver(data.To) or GetReceiver(nil)
                            local amt = type(data) == "table" and data.Amount or data
                            if rec and typeof(amt) == "number" then
                                FireEvent("SendMailItem", rec, itemName, amt)
                                SessionTracker.Mails = SessionTracker.Mails + 1
                            end
                        end
                    end
                end
            end

            local defRec = GetReceiver(nil)
            if defRec then
                for item, count in pairs(Config.MailSendItems) do
                    FireEvent("SendMail", defRec, item, count)
                    SessionTracker.Mails = SessionTracker.Mails + 1
                end
                for item, count in pairs(Config.MailSendItemsToMain) do
                    FireEvent("SendMail", defRec, item, count)
                    SessionTracker.Mails = SessionTracker.Mails + 1
                end
            end
        end)
    end
end)

-- [[ 6. LIVE UI STREAMING (EXACT TELEMETRY RECONSTRUCTION) ]]
task.spawn(function()
    while task.wait(0.5) do
        pcall(function()
            local elapsed = math.max(os.time() - SessionTracker.StartTime, 1)
            local pData = GetLivePlayerData()
            local gData = GetLiveGardenData()

            local earned = math.max(pData.Sheckles - InitialSheckles, 0)
            local ratePerSec = math.floor(earned / elapsed)
            local secondsSinceLast = os.time() - SessionTracker.LastStatusTime

            -- Dynamic Seed Breakdown Formatting
            local seedListStr = string.format("Seeds: %d total", pData.SeedTotal)
            if #pData.DetailedSeeds > 0 then
                for _, sInfo in ipairs(pData.DetailedSeeds) do
                    seedListStr = seedListStr .. string.format("\n  • %s: %d", sInfo.Name, sInfo.Count)
                end
            end

            ContentBox.Text = string.format([[
─── PLAYER ───
Sheckles: $%s
Fruit: %d / 100
Pets: %d / %d
%s
Plot: %d (Exp %d)
─── GARDEN ───
Plants: %d / %d
Sprinklers: %d
Decaying: %d
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
Last: %s (%ds ago)
]], 
            tostring(pData.Sheckles),
            pData.Fruit,
            pData.Pets,
            Config.PetSlotsLimit or 6,
            seedListStr,
            pData.PlotLevel,
            pData.PlotExp,
            gData.Plants,
            Config.LimitAutoPlant or 500,
            gData.Sprinklers,
            gData.Decaying,
            FormatTime(elapsed),
            earned,
            ratePerSec,
            SessionTracker.Harvested,
            SessionTracker.Planted,
            SessionTracker.SoldTimes,
            SessionTracker.Mails,
            SessionTracker.PetsBought,
            SessionTracker.SeedPacks,
            SessionTracker.Shovels,
            SessionTracker.LastStatus,
            secondsSinceLast)
        end)
    end
end)

-- RAM Watchdog
task.spawn(function()
    while task.wait(10) do
        local mem = StatsService:GetTotalMemoryUsageMb()
        if Config.RamKickLimit and mem > Config.RamKickLimit then
            LocalPlayer:Kick(string.format("[Kaitun Guard] RAM Exceeded: %d MB > %d MB", mem, Config.RamKickLimit))
        end
    end
end)

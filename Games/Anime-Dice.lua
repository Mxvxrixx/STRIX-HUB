-- ==============================================================================
-- 0. PREVIOUS INSTANCE CLEANUP
-- ==============================================================================
if getgenv().STRIX_HUB_CLEANUP then
    pcall(getgenv().STRIX_HUB_CLEANUP)
    task.wait(0.2)
end

-- Destroy previous Maclib / mobile GUIs if any exist
pcall(function()
    local searchLocations = {
        (gethui and gethui()) or game:GetService("CoreGui"),
        game:GetService("CoreGui"):FindFirstChild("RobloxGui"),
        game:GetService("Players").LocalPlayer and game:GetService("Players").LocalPlayer:FindFirstChild("PlayerGui")
    }
    for _, loc in ipairs(searchLocations) do
        if loc then
            for _, child in ipairs(loc:GetChildren()) do
                if child:IsA("ScreenGui") and (child:FindFirstChild("Base") or child.Name == "STRIX_MOBILE_TOGGLE") then
                    pcall(function() child:Destroy() end)
                end
            end
        end
    end
end)

getgenv().STRIX_HUB_LOADED = true

-- ==============================================================================
-- 1. SERVICES & GAME REFERENCES
-- ==============================================================================
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer

-- Framework References
local Framework = ReplicatedStorage:WaitForChild("Framework")
local Network = ReplicatedStorage:WaitForChild("Network")

local DataController = require(Framework.Features.Data.DataController)
local UIReferences = require(Framework.Features.UI.UIReferences)
local Upgrades = require(Framework.Features.Upgrades.Upgrades)
local TreeStructure = require(Framework.Features.Upgrades.TreeStructure)
local Rebirths = require(Framework.Features.Rebirth.Rebirths)
local DiceModule = require(Framework.Features.Rolling.Dice)
local QuestConfig = require(Framework.Features.Quests.QuestConfig)
local DailyRewardConfig = require(Framework.Features.Rewards.DailyRewardConfig)
local PlotConfig = require(Framework.Features.Plot.PlotConfig)
local RollController = require(Framework.Features.Rolling.RollController)
local HUDController = require(Framework.Features.UI.HUDController)
local EntryRegistry = require(Framework.Features.Inventory.EntryRegistry)
local UnitUtil = require(Framework.Features.Inventory.Kinds.Unit.UnitUtil)
local NumberFormatter = require(ReplicatedStorage.Packages.NumberFormatter)
local BoostConfig = (function()
    local ok, mod = pcall(function()
        return require(Framework.Features.Inventory.Kinds.Boost.BoostConfig)
    end)
    return ok and mod or nil
end)()
local TowerController = (function()
    local ok, mod = pcall(function()
        return require(Framework.Features.Towers.TowerController)
    end)
    return ok and mod or nil
end)()

-- Game Remotes
local SetAutoRollRE = Network.RollService.RE.SetAutoRoll
local EquipBestPlotRE = Network.PlotService.RE.EquipBest
local CollectBalanceRE = Network.PlotService.RE.CollectBalance
local LevelUpSlotRE = Network.PlotService.RE.LevelUpSlot
local UpdateAutoSellRE = Network.SellService.RE.UpdateAutoSell
local RebirthRE = Network.RebirthService.RE.Rebirth
local BuyUpgradeRE = Network.RE.BuyUpgrade
local BuyDiceRE = Network.DiceShopService.RE.BuyDice
local EquipDiceRE = Network.DiceShopService.RE.EquipDice
local ClaimQuestRE = Network.QuestService.RE.Claim
local ClaimDailyRE = Network.DailyRewardService.RE.Claim
local RedeemCodeRE = Network.CodesService.RE.RedeemCode
local UseSpinRE = Network.SpinService.RE.Use
local UseBoostRE = (Network:FindFirstChild("BoostService") and Network.BoostService:FindFirstChild("RE") and Network.BoostService.RE:FindFirstChild("Use"))
    or (Network:FindFirstChild("PotionService") and Network.PotionService:FindFirstChild("RE") and Network.PotionService.RE:FindFirstChild("Use"))

-- Tower Remotes
local CancelTowerRF = Network:FindFirstChild("Towers") and Network.Towers:FindFirstChild("RF") and Network.Towers.RF:FindFirstChild("CancelTower")
local SetAutoTowerRE = Network:FindFirstChild("Towers") and Network.Towers:FindFirstChild("RE") and Network.Towers.RE:FindFirstChild("SetAutoTower")
local EquipBestTowerTeamRE = Network:FindFirstChild("Towers") and Network.Towers:FindFirstChild("RE") and Network.Towers.RE:FindFirstChild("EquipBestTowerTeam")

-- ==============================================================================
-- 2. STATE CONFIGURATION
-- ==============================================================================
local initialAutoSell = (DataController.AutoSell and DataController.AutoSell()) or 0
local initialAutoRoll = (DataController.AutoRoll and DataController.AutoRoll() == true) or false

local Config = {
    -- Roll & Spins
    AutoRoll = initialAutoRoll,
    AutoHideRoll = false,
    RollDelay = 0.5,
    AutoBuyDice = false,
    AutoEquipBestDice = false,
    AutoUseSpins = false,
    AutoUsePotions = false,
    SelectedPotionTypes = { "Coin", "Luck", "Damage" },

    -- Farm & Plot
    AutoCollect = false,
    AutoEquipBest = false,
    AutoSell = initialAutoSell > 0,
    AutoSellAmount = initialAutoSell,
    AutoUpgradePlot = false,
    PlotTargetLevel = 1,

    -- Progression
    AutoRebirth = false,
    AutoUpgrades = false,
    AutoClaimQuests = false,
    AutoClaimDaily = false,

    -- Towers
    AutoTower = false,
    SelectedTower = "Dragon Tower",
    AutoEquipBestTowerTeam = true,
    AutoHideTowerScreen = false,

    -- UI Settings & Window
    MenuKeybind = Enum.KeyCode.RightControl,
    WindowWidth = 1000,
    WindowHeight = 650,
    AcrylicBlur = false,
    ShowUserInfo = true,
    MobileToggle = true,
    AutoSave = true
}

-- ------------------------------------------------------------------------------
-- CONFIG STORAGE SYSTEM (WORKSPACE / STRIX HUB / <MapName> / <Account>)
-- ------------------------------------------------------------------------------
local RootFolder = "STRIX HUB"
local MapName = "Anime Dice"
local MapFolder = RootFolder .. "/" .. MapName

-- Running Account Identifiers (Username & UserId)
local AccountName = (LocalPlayer and LocalPlayer.Name) or "default"
local AccountUserId = (LocalPlayer and tostring(LocalPlayer.UserId)) or "0"

-- Account-specific Config Files (Named strictly as Account / Character Username)
local ConfigFileJSON = MapFolder .. "/" .. AccountName .. ".json"
local ConfigFileUserIdJSON = MapFolder .. "/" .. AccountUserId .. ".json"

local UIControls = {}
local isApplyingConfig = false
local saveDebounceThread = nil

local function EnsureConfigFolder()
    if makefolder and isfolder then
        pcall(function()
            if not isfolder(RootFolder) then
                makefolder(RootFolder)
            end
            if not isfolder(MapFolder) then
                makefolder(MapFolder)
            end
        end)
    end
end

local function SerializeConfig()
    local serialized = {}
    for k, v in pairs(Config) do
        if k == "AutoUsePotions" or k == "AutoTower" then
            -- Transient features: never saved as true; user must enable manually each session
            serialized[k] = false
        elseif k == "MenuKeybind" then
            if typeof(v) == "EnumItem" then
                serialized[k] = v.Name
            else
                serialized[k] = tostring(v)
            end
        elseif typeof(v) ~= "function" and typeof(v) ~= "Instance" then
            serialized[k] = v
        end
    end
    serialized.AutoUsePotions = false
    serialized.AutoTower = false
    return serialized
end

local function SaveConfig(silent)
    if not (writefile and isfolder) then
        return false, "Executor filesystem functions not available"
    end

    local success, err = pcall(function()
        EnsureConfigFolder()
        local data = SerializeConfig()
        local json = HttpService:JSONEncode(data)
        -- Save strictly as character / account name .json
        writefile(ConfigFileJSON, json)
    end)

    if success then
        if not silent then
            print("[STRIX HUB] Config saved successfully for [" .. AccountName .. "] to Workspace/" .. ConfigFileJSON)
        end
        return true
    else
        warn("[STRIX HUB] Failed to save config: " .. tostring(err))
        return false, err
    end
end

local function RequestSaveConfig()
    if isApplyingConfig then return end
    if Config.AutoSave == false then return end
    if saveDebounceThread then
        task.cancel(saveDebounceThread)
        saveDebounceThread = nil
    end
    saveDebounceThread = task.delay(0.5, function()
        SaveConfig(true)
        saveDebounceThread = nil
    end)
end

local function LoadConfig()
    if not (readfile and isfile) then
        return false, "Executor readfile not available"
    end

    local filePathToRead = nil
    -- 1. Check account file by Username / Character Name
    if isfile(ConfigFileJSON) then
        filePathToRead = ConfigFileJSON
    elseif isfile(MapFolder .. "/" .. AccountName) then
        filePathToRead = MapFolder .. "/" .. AccountName
    -- 2. Check account file by UserId
    elseif isfile(ConfigFileUserIdJSON) then
        filePathToRead = ConfigFileUserIdJSON
    elseif isfile(MapFolder .. "/" .. AccountUserId) then
        filePathToRead = MapFolder .. "/" .. AccountUserId
    -- 3. Check legacy shared configs
    elseif isfile(MapFolder .. "/config.json") then
        filePathToRead = MapFolder .. "/config.json"
    elseif isfile(MapFolder .. "/config") then
        filePathToRead = MapFolder .. "/config"
    elseif isfile(MapFolder .. "/animedice.json") then
        filePathToRead = MapFolder .. "/animedice.json"
    elseif isfile(RootFolder .. "/animedice.json") then
        filePathToRead = RootFolder .. "/animedice.json"
    elseif isfile(RootFolder .. "/animedice") then
        filePathToRead = RootFolder .. "/animedice"
    end

    if not filePathToRead then
        return false, "No config file found"
    end

    local success, result = pcall(function()
        local content = readfile(filePathToRead)
        if not content or content == "" then return nil end
        return HttpService:JSONDecode(content)
    end)

    if success and type(result) == "table" then
        for k, v in pairs(result) do
            if k == "AutoUsePotions" or k == "AutoTower" then
                -- Never restore transient automation from config file; user must enable manually
                Config[k] = false
            elseif Config[k] ~= nil then
                if k == "MenuKeybind" and typeof(v) == "string" then
                    local enumKey = Enum.KeyCode[v]
                    if enumKey then
                        Config.MenuKeybind = enumKey
                    end
                else
                    Config[k] = v
                end
            end
        end
        Config.AutoUsePotions = false
        Config.AutoTower = false
        print("[STRIX HUB] Config loaded from Workspace/" .. filePathToRead)
        return true, result
    else
        warn("[STRIX HUB] Failed to load config or invalid JSON: " .. tostring(result))
        return false, result
    end
end

-- ==============================================================================
-- 3. CORE LOGIC ENGINE (STRIX API)
-- ==============================================================================
local Strix = {
    Config = Config,
    Util = {},
    Roll = {},
    Farm = {},
    Tower = {},
    Progression = {},
    Stats = {},
    Engine = {}
}
getgenv().Strix = Strix

-- ------------------------------------------------------------------------------
-- Utilities
-- ------------------------------------------------------------------------------
function Strix.Util.FormatComma(n)
    if not n then return "0" end
    local num = tonumber(n)
    if not num then return tostring(n) end
    local formatted = string.format("%.0f", num)
    local k
    while true do
        formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1,%2")
        if k == 0 then break end
    end
    return formatted
end

function Strix.Util.FormatCompact(n)
    if not n then return "0" end
    local num = tonumber(n) or 0
    if NumberFormatter and NumberFormatter.FormatCompact then
        local s, res = pcall(function()
            return string.upper(NumberFormatter.FormatCompact(num))
        end)
        if s and res then return res end
    end
    if num >= 1e12 then return string.format("%.2fT", num / 1e12) end
    if num >= 1e9 then return string.format("%.2fB", num / 1e9) end
    if num >= 1e6 then return string.format("%.2fM", num / 1e6) end
    if num >= 1e3 then return string.format("%.2fK", num / 1e3) end
    return tostring(num)
end

function Strix.Util.ParseThreshold(text)
    if not text or text == "" then return 0 end
    local clean = tostring(text):gsub(",", ""):gsub("%s+", "")
    local num = tonumber(clean)
    if not num and NumberFormatter and NumberFormatter.ParseCompact then
        pcall(function()
            num = NumberFormatter.ParseCompact(clean)
        end)
    end
    return num or 0
end

-- ------------------------------------------------------------------------------
-- Roll Logic
-- ------------------------------------------------------------------------------
local function setHideRollNative(enable)
    pcall(function()
        local hiddenRoll = UIReferences.Root.Rolling.Options.HiddenRoll
        local conns = getconnections(hiddenRoll.Activated)
        for _, c in ipairs(conns) do
            if c.Function then
                local ups = getupvalues(c.Function)
                local stateObj = ups and ups[1]
                if typeof(stateObj) == "function" and stateObj() ~= enable then
                    stateObj(enable)
                    return
                end
            end
        end
    end)
    if enable then
        pcall(function()
            if UIReferences.Root.Rolling.Frame then
                UIReferences.Root.Rolling.Frame.Visible = false
            end
        end)
    end
end

function Strix.Roll.SetAutoRoll(enabled)
    Config.AutoRoll = (enabled == true)
    pcall(function()
        SetAutoRollRE:FireServer(Config.AutoRoll)
    end)
end

function Strix.Roll.SetHideRoll(enabled)
    Config.AutoHideRoll = (enabled == true)
    setHideRollNative(Config.AutoHideRoll)
end

function Strix.Roll.SetDelay(delaySeconds)
    Config.RollDelay = math.clamp(tonumber(delaySeconds) or 0.5, 0.1, 10.0)
end

function Strix.Roll.SetAutoBuyDice(enabled)
    Config.AutoBuyDice = (enabled == true)
end

function Strix.Roll.SetAutoEquipBestDice(enabled)
    Config.AutoEquipBestDice = (enabled == true)
end

function Strix.Roll.BuyBestAvailableDice()
    local currentMoney = DataController.Money() or 0
    local allDice = DiceModule.GetAll()
    local sortedDice = {}
    for diceName, diceData in pairs(allDice) do
        if diceData.price then
            table.insert(sortedDice, {
                name = diceName,
                price = diceData.price,
                luck = diceData.luck or 0
            })
        end
    end
    table.sort(sortedDice, function(a, b) return a.price < b.price end)

    for _, dice in ipairs(sortedDice) do
        local owned = false
        pcall(function()
            owned = DataController.OwnedDice[dice.name]() == true
        end)
        if not owned and currentMoney >= dice.price then
            BuyDiceRE:FireServer(dice.name)
            return dice.name
        end
    end
    return nil
end

function Strix.Roll.EquipBestOwnedDice()
    local allDice = DiceModule.GetAll()
    local bestDiceName = nil
    local highestLuck = -1
    for diceName, diceData in pairs(allDice) do
        local owned = false
        pcall(function()
            owned = DataController.OwnedDice[diceName]() == true
        end)
        if owned and diceData.luck and diceData.luck > highestLuck then
            highestLuck = diceData.luck
            bestDiceName = diceName
        end
    end
    if bestDiceName and DataController.Dice() ~= bestDiceName then
        EquipDiceRE:FireServer(bestDiceName)
        return bestDiceName
    end
    return nil
end

function Strix.Roll.SetAutoUseSpins(enabled)
    Config.AutoUseSpins = (enabled == true)
end

local isConsumingPotions = false

local function GetItemPotionCategory(itemName)
    if not itemName or type(itemName) ~= "string" then return nil end
    local lower = string.lower(itemName)

    -- Ignore non-potions
    if string.find(lower, "spin") or string.find(lower, "token") or string.find(lower, "reroll") or string.find(lower, "ticket") or string.find(lower, "cape") or string.find(lower, "vest") or string.find(lower, "hair") then
        return nil
    end

    -- 1. Check against BoostConfig metadata if available
    if BoostConfig and BoostConfig.entries and BoostConfig.entries[itemName] then
        local entry = BoostConfig.entries[itemName]
        if entry.buffs then
            if entry.buffs["Money Multiplier"] then return "Coin" end
            if entry.buffs["Luck"] then return "Luck" end
            if entry.buffs["Damage Multiplier"] then return "Damage" end
            if entry.buffs["Roll Duration"] then return "Speed" end
        end
    end

    -- 2. Fallback pattern matching
    -- Coin / Money / Income
    if string.find(lower, "income") or string.find(lower, "coin") or string.find(lower, "money") or string.find(lower, "cash") then
        return "Coin"
    end

    -- Luck
    if string.find(lower, "luck") then
        return "Luck"
    end

    -- Damage / Power
    if string.find(lower, "damage") or string.find(lower, "dmg") or string.find(lower, "strength") or string.find(lower, "power") then
        return "Damage"
    end

    -- Speed
    if string.find(lower, "speed") then
        return "Speed"
    end

    return nil
end

local function IsPotionCategorySelected(category)
    if not category then return false end
    local catLower = string.lower(category)
    local selected = Config.SelectedPotionTypes
    if type(selected) ~= "table" then return false end

    for k, v in pairs(selected) do
        if type(k) == "string" and string.lower(k) == catLower and v == true then
            return true
        elseif type(v) == "string" and string.lower(v) == catLower then
            return true
        end
    end
    return false
end

function Strix.Roll.SetAutoUsePotions(enabled)
    Config.AutoUsePotions = (enabled == true)
end

function Strix.Roll.SetSelectedPotionTypes(types)
    local list = {}
    if type(types) == "table" then
        for k, v in pairs(types) do
            if type(k) == "string" and v == true then
                table.insert(list, k)
            elseif type(v) == "string" then
                table.insert(list, v)
            end
        end
    end
    Config.SelectedPotionTypes = list
end

function Strix.Roll.ConsumeSelectedPotions(force)
    if isConsumingPotions then return 0 end
    local remote = UseBoostRE
        or (Network:FindFirstChild("BoostService") and Network.BoostService:FindFirstChild("RE") and Network.BoostService.RE:FindFirstChild("Use"))
        or (Network:FindFirstChild("PotionService") and Network.PotionService:FindFirstChild("RE") and Network.PotionService.RE:FindFirstChild("Use"))
    if not remote then return 0 end

    isConsumingPotions = true
    local totalUsed = 0

    pcall(function()
        local inv = (DataController.Inventory and DataController.Inventory()) or {}
        local queue = {}

        for _, item in pairs(inv) do
            if item and item.name then
                local cat = GetItemPotionCategory(item.name)
                if cat and IsPotionCategorySelected(cat) then
                    local count = tonumber(item.amount) or 1
                    if count > 0 then
                        table.insert(queue, { name = item.name, amount = count, category = cat })
                    end
                end
            end
        end

        for _, target in ipairs(queue) do
            for _ = 1, target.amount do
                if not Config.AutoUsePotions and not force then break end
                pcall(function()
                    remote:FireServer(target.name)
                end)
                totalUsed = totalUsed + 1
                task.wait(0.04)
            end
            if not Config.AutoUsePotions and not force then break end
        end
    end)

    isConsumingPotions = false

    if totalUsed > 0 then
        print(("[STRIX HUB] Consumed ALL %d potion(s) in inventory!"):format(totalUsed))
    end
    return totalUsed
end

-- ------------------------------------------------------------------------------
-- Farm & Plot Logic
-- ------------------------------------------------------------------------------
function Strix.Farm.SetAutoCollect(enabled)
    Config.AutoCollect = (enabled == true)
end

function Strix.Farm.SetAutoEquipBest(enabled)
    Config.AutoEquipBest = (enabled == true)
end

function Strix.Farm.SetAutoSellThreshold(amount)
    local num = Strix.Util.ParseThreshold(amount)
    Config.AutoSellAmount = num
    Config.AutoSell = (num > 0)
    pcall(function()
        UpdateAutoSellRE:FireServer(num)
    end)
end

function Strix.Farm.GetSlotUnit(slot)
    local slotsMap = (type(DataController.Slots) == "function" and DataController.Slots())
        or (type(DataController.Slots) == "table" and getmetatable(DataController.Slots) and DataController.Slots())
        or DataController.Slots
    if not (type(slotsMap) == "table") then return nil end
    local slotData = slotsMap[tostring(slot)] or slotsMap[slot]
    if not (slotData and slotData.unitId) then return nil end

    local invMap = (type(DataController.Inventory) == "function" and DataController.Inventory())
        or (type(DataController.Inventory) == "table" and getmetatable(DataController.Inventory) and DataController.Inventory())
        or DataController.Inventory
    if not (type(invMap) == "table") then return nil end
    local unit = invMap[slotData.unitId]
    if not unit then return nil end

    local curLevel = (unit.attributes and unit.attributes.level) or 1
    local price = UnitUtil and UnitUtil.GetLevelPrice and UnitUtil.GetLevelPrice(unit.name, unit.attributes)

    return {
        UnitId = slotData.unitId,
        Name = unit.name,
        Level = curLevel,
        Price = price
    }
end

function Strix.Farm.SetAutoUpgradePlot(enabled)
    Config.AutoUpgradePlot = (enabled == true)
end

function Strix.Farm.SetPlotTargetLevel(targetLevel)
    local num = tonumber(tostring(targetLevel):match("%d+"))
    if num and num > 0 then
        Config.PlotTargetLevel = num
    end
end

function Strix.Farm.InstantCollectAll()
    local playerRebirth = DataController.Rebirth() or 0
    for slot = 1, 20 do
        local req = PlotConfig.GetSlotRebirthRequirement(slot)
        if req <= playerRebirth then
            CollectBalanceRE:FireServer(slot)
        end
    end
end

function Strix.Farm.InstantEquipBest()
    pcall(function()
        EquipBestPlotRE:FireServer()
    end)
end

function Strix.Farm.InstantUpgradeAll(overrideTargetLv)
    local targetLv = tonumber(overrideTargetLv) or tonumber(Config.PlotTargetLevel) or 1
    local maxSlots = (PlotConfig.GetMaxSlots and PlotConfig.GetMaxSlots()) or 18
    local rebirth = DataController.Rebirth() or 0

    for slot = 1, maxSlots do
        local req = PlotConfig.GetSlotRebirthRequirement(slot)
        if req <= rebirth then
            while getgenv().STRIX_HUB_LOADED do
                local currentMoney = DataController.Money() or 0
                local u = Strix.Farm.GetSlotUnit(slot)
                if not u then break end
                if u.Level >= targetLv then break end
                if not u.Price or currentMoney < u.Price then break end
                LevelUpSlotRE:FireServer(slot)
                task.wait(0.25)
            end
        end
    end
end

-- ------------------------------------------------------------------------------
-- Progression Logic
-- ------------------------------------------------------------------------------
function Strix.Progression.SetAutoRebirth(enabled)
    Config.AutoRebirth = (enabled == true)
end

function Strix.Progression.SetAutoUpgrades(enabled)
    Config.AutoUpgrades = (enabled == true)
end

function Strix.Progression.SetAutoClaimQuests(enabled)
    Config.AutoClaimQuests = (enabled == true)
end

function Strix.Progression.SetAutoClaimDaily(enabled)
    Config.AutoClaimDaily = (enabled == true)
end

function Strix.Progression.InstantClaimQuests()
    for _, tab in ipairs({"Daily", "Weekly"}) do
        local period = QuestConfig.Periods[tab]
        local qData = DataController.Quests[tab]()
        if period and qData then
            for _, quest in ipairs(period.quests) do
                local prog = qData.progress[quest.id] or 0
                local claimed = (qData.claimed[quest.id] == true)
                if not claimed and prog >= quest.target then
                    ClaimQuestRE:FireServer(tab, quest.id, qData.expiresAt)
                    task.wait(0.15)
                end
            end
        end
    end
end

local KnownPromoCodes = {
    "RELEASE", "UPDATE1", "UPDATE2", "UPDATE3",
    "1KCCU", "5KCCU", "10KCCU", "20KCCU", "30KCCU", "40KCCU",
    "100KLIKES", "UPDATE4", "250KLIKES", "UPDATE5", "400KLIKES",
    "UPDATE6", "UPDATE7"
}

function Strix.Progression.GetAllCodes()
    local codes = {}
    pcall(function()
        local CodesConfig = require(Framework.Features.Codes.CodesConfig)
        for c, _ in pairs(CodesConfig) do
            if type(c) == "string" and c ~= "Codes" and c ~= "Durations" then
                table.insert(codes, c)
            end
        end
    end)
    if #codes == 0 then
        codes = table.clone(KnownPromoCodes)
    end
    return codes
end

function Strix.Progression.RedeemAllCodes()
    local allCodes = Strix.Progression.GetAllCodes()
    local totalRedeemed = 0

    for pass = 1, 3 do
        local redeemedList = (DataController.RedeemedCodes and DataController.RedeemedCodes()) or {}
        local toRedeem = {}

        for _, code in ipairs(allCodes) do
            if not redeemedList[code] then
                table.insert(toRedeem, code)
            end
        end

        if #toRedeem == 0 then
            break
        end

        for _, code in ipairs(toRedeem) do
            pcall(function()
                RedeemCodeRE:FireServer(code)
            end)
            totalRedeemed = totalRedeemed + 1
            task.wait(0.35)
        end

        task.wait(0.5)
    end

    print(("[STRIX HUB] Redeemed %d codes total!"):format(totalRedeemed))
    return totalRedeemed
end

-- ------------------------------------------------------------------------------
-- Tower Logic
-- ------------------------------------------------------------------------------
local function GetTowerControllerHooks()
    local Hidden = UIReferences and UIReferences.Root and UIReferences.Root.Tower and UIReferences.Root.Tower:FindFirstChild("Hidden")
    if not Hidden or not getconnections then return nil end
    local conns = getconnections(Hidden.Activated)
    for _, c in ipairs(conns) do
        if c.Function and getupvalues then
            local ups = getupvalues(c.Function)
            if typeof(ups[1]) == "boolean" and typeof(ups[2]) == "function" and typeof(ups[3]) == "boolean" then
                return {
                    connection = c,
                    func = c.Function,
                    getActive = function()
                        local ok, val = pcall(getupvalue, c.Function, 1)
                        return ok and (val == true)
                    end,
                    setHidden = ups[2],
                    getHidden = function()
                        local ok, val = pcall(getupvalue, c.Function, 3)
                        return ok and (val == true)
                    end
                }
            end
        end
    end
    return nil
end

function Strix.Tower.IsActive()
    local hooks = GetTowerControllerHooks()
    if hooks and hooks.getActive then
        return hooks.getActive()
    end
    if not UIReferences or not UIReferences.Root or not UIReferences.Root.Tower then return false end
    local towerRoot = UIReferences.Root.Tower
    local screen = towerRoot:FindFirstChild("Screen")
    local hidden = towerRoot:FindFirstChild("Hidden")
    if screen and screen.Visible == true then return true end
    if hidden and hidden.Visible == true and hidden:FindFirstChild("Label") then
        local txt = hidden.Label.Text
        if txt and string.match(txt, "Floor") then
            return true
        end
    end
    return false
end

function Strix.Tower.IsHidden()
    local hooks = GetTowerControllerHooks()
    if hooks and hooks.getHidden then
        return hooks.getHidden()
    end
    local towerRoot = UIReferences and UIReferences.Root and UIReferences.Root.Tower
    if not towerRoot then return false end
    local screen = towerRoot:FindFirstChild("Screen")
    local hidden = towerRoot:FindFirstChild("Hidden")
    return (hidden and hidden.Visible == true) and (not screen or screen.Visible == false)
end

function Strix.Tower.SetAutoTower(enabled)
    Config.AutoTower = (enabled == true)
end

function Strix.Tower.SetSelectedTower(name)
    if name and type(name) == "string" then
        Config.SelectedTower = name
    end
end

function Strix.Tower.SetAutoEquipBest(enabled)
    Config.AutoEquipBestTowerTeam = (enabled == true)
end

function Strix.Tower.SetAutoHideScreen(enabled)
    Config.AutoHideTowerScreen = (enabled == true)
end

function Strix.Tower.EquipBestTeam()
    pcall(function()
        if EquipBestTowerTeamRE then
            EquipBestTowerTeamRE:FireServer()
        end
    end)
end

function Strix.Tower.SetBattleScreenHidden(hide)
    pcall(function()
        local isActive = Strix.Tower.IsActive()
        local towerRoot = UIReferences and UIReferences.Root and UIReferences.Root.Tower
        if not towerRoot then return end
        local screen = towerRoot:FindFirstChild("Screen")
        local bg = towerRoot:FindFirstChild("Background")
        local hiddenBtn = towerRoot:FindFirstChild("Hidden")

        -- If not active in tower at all, cleanly hide tower elements and show player HUD
        if not isActive then
            if screen then screen.Visible = false end
            if bg then bg.Visible = false end
            if hiddenBtn then hiddenBtn.Visible = false end
            if HUDController and HUDController.showAll then
                HUDController.showAll("inTower")
            end
            return
        end

        -- Player IS in tower: use game's native setTowerHidden logic
        local hooks = GetTowerControllerHooks()
        if hooks and hooks.setHidden then
            local curHidden = hooks.getHidden and hooks.getHidden()
            if curHidden ~= (hide == true) then
                hooks.setHidden(hide == true)
            end
            return
        end

        -- Fallback if native function unavailable
        if hide then
            if screen then screen.Visible = false end
            if bg then bg.Visible = false end
            if HUDController and HUDController.showAll then
                HUDController.showAll("inTower")
            end
            if hiddenBtn then
                hiddenBtn.Visible = true
                if hiddenBtn:FindFirstChild("Label") and screen and screen:FindFirstChild("Floor") then
                    hiddenBtn.Label.Text = screen.Floor.Text
                end
            end
        else
            if screen then screen.Visible = true end
            if bg then
                bg.Visible = true
                bg.BackgroundTransparency = 0.5
            end
            if HUDController and HUDController.hideAll then
                HUDController.hideAll("inTower")
            end
            if hiddenBtn then
                hiddenBtn.Visible = true
                if hiddenBtn:FindFirstChild("Label") then
                    hiddenBtn.Label.Text = "Hide"
                end
            end
        end
    end)
end

function Strix.Tower.Start(towerName)
    local target = towerName or Config.SelectedTower or "Dragon Tower"
    pcall(function()
        if Config.AutoEquipBestTowerTeam and EquipBestTowerTeamRE then
            EquipBestTowerTeamRE:FireServer()
            task.wait(0.2)
        end
        if TowerController and TowerController.startTower then
            TowerController.startTower(target)
        end
        if SetAutoTowerRE then
            SetAutoTowerRE:FireServer(target)
        end
        if Config.AutoHideTowerScreen then
            task.delay(0.5, function()
                if Strix.Tower.IsActive() and Config.AutoHideTowerScreen then
                    Strix.Tower.SetBattleScreenHidden(true)
                end
            end)
        end
    end)
end

function Strix.Tower.Cancel()
    pcall(function()
        if CancelTowerRF then
            CancelTowerRF:InvokeServer()
        end
        if SetAutoTowerRE then
            SetAutoTowerRE:FireServer(false)
        end
        if HUDController and HUDController.showAll then
            HUDController.showAll("inTower")
        end
        local towerRoot = UIReferences and UIReferences.Root and UIReferences.Root.Tower
        if towerRoot then
            if towerRoot:FindFirstChild("Hidden") then towerRoot.Hidden.Visible = false end
            if towerRoot:FindFirstChild("Screen") then towerRoot.Screen.Visible = false end
            if towerRoot:FindFirstChild("Background") then towerRoot.Background.Visible = false end
        end
    end)
end

function Strix.Tower.GetCurrentFloor()
    local ok, text = pcall(function()
        local towerRoot = UIReferences and UIReferences.Root and UIReferences.Root.Tower
        if not towerRoot then return nil end
        if towerRoot:FindFirstChild("Screen") and towerRoot.Screen:FindFirstChild("Floor") and towerRoot.Screen.Floor.Text ~= "" then
            return towerRoot.Screen.Floor.Text
        end
        if towerRoot:FindFirstChild("Hidden") and towerRoot.Hidden:FindFirstChild("Label") and towerRoot.Hidden.Label.Text ~= "" and towerRoot.Hidden.Label.Text ~= "Hide" then
            return towerRoot.Hidden.Label.Text
        end
        return nil
    end)
    return ok and text or nil
end

-- ------------------------------------------------------------------------------
-- Stats & Data
-- ------------------------------------------------------------------------------
function Strix.Stats.GetSnapshot()
    local money = (DataController.Money and DataController.Money()) or 0
    local rebirth = (DataController.Rebirth and DataController.Rebirth()) or 0
    local dice = (DataController.Dice and DataController.Dice()) or "None"
    local rolls = (DataController.Rolls and DataController.Rolls()) or 0
    local autoSell = (DataController.AutoSell and DataController.AutoSell()) or 0

    return {
        Money = money,
        MoneyFormatted = Strix.Util.FormatComma(money),
        MoneyCompact = Strix.Util.FormatCompact(money),
        Rebirth = rebirth,
        RebirthFormatted = Strix.Util.FormatComma(rebirth),
        Dice = tostring(dice),
        Rolls = rolls,
        RollsFormatted = Strix.Util.FormatComma(rolls),
        AutoSell = autoSell,
        AutoSellFormatted = Strix.Util.FormatComma(autoSell),
        AutoSellCompact = Strix.Util.FormatCompact(autoSell)
    }
end

-- ------------------------------------------------------------------------------
-- Engine Lifecycle
-- ------------------------------------------------------------------------------
function Strix.Engine.StopAll()
    for k, _ in pairs(Config) do
        if type(Config[k]) == "boolean" then
            Config[k] = false
        end
    end
    pcall(function()
        SetAutoRollRE:FireServer(false)
        setHideRollNative(false)
        if CancelTowerRF then CancelTowerRF:InvokeServer() end
        if SetAutoTowerRE then SetAutoTowerRE:FireServer(false) end
    end)
end

function Strix.Engine.Cleanup()
    if getgenv().STRIX_CORE == Strix or getgenv().STRIX_CORE == nil then
        getgenv().STRIX_HUB_LOADED = false
        getgenv().STRIX_CORE = nil
    end
    if getgenv().STRIX_ANTI_AFK_STATE then
        getgenv().STRIX_ANTI_AFK_STATE.IsActive = false
    end
    if getgenv().STRIX_ANTI_AFK_CONN then
        pcall(function()
            getgenv().STRIX_ANTI_AFK_CONN:Disconnect()
        end)
        getgenv().STRIX_ANTI_AFK_CONN = nil
    end
    if getgenv().STRIX_MOBILE_GUI then
        pcall(function()
            getgenv().STRIX_MOBILE_GUI:Destroy()
        end)
        getgenv().STRIX_MOBILE_GUI = nil
    end
    Strix.Engine.StopAll()
end

-- Register globals
getgenv().STRIX_HUB_CLEANUP = Strix.Engine.Cleanup
getgenv().STRIX_CORE = Strix

-- ==============================================================================
-- 4. BACKGROUND AUTOMATION WORKERS
-- ==============================================================================

-- 0. Anti-AFK Worker (Infinite Yield Core Standard: Universal PC & Mobile)
local AntiAfkState = {
    Pulses = 0,
    LastPulse = os.time(),
    IsActive = true
}
getgenv().STRIX_ANTI_AFK_STATE = AntiAfkState

-- Neutralize all default CoreScript kick listeners (Infinite Yield Standard)
if getconnections then
    for _, c in getconnections(LocalPlayer.Idled) do
        pcall(function() c:Disable() end)
        pcall(function() c:Disconnect() end)
    end
end

-- Disconnect previous instance if exists
pcall(function()
    if getgenv().STRIX_ANTI_AFK_CONN then
        getgenv().STRIX_ANTI_AFK_CONN:Disconnect()
        getgenv().STRIX_ANTI_AFK_CONN = nil
    end
end)

-- Connect Idled event via VirtualInputManager mouse click simulation (Infinite Yield Standard)
getgenv().STRIX_ANTI_AFK_CONN = LocalPlayer.Idled:Connect(function()
    local VirtualInputManager = Instance.new("VirtualInputManager")
    VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 0)
    VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 0)
    VirtualInputManager:Destroy()

    AntiAfkState.Pulses = AntiAfkState.Pulses + 1
    AntiAfkState.LastPulse = os.time()
end)

Strix.AntiAfk = {
    State = AntiAfkState,
    Connection = getgenv().STRIX_ANTI_AFK_CONN
}

-- 1. Auto Roll Loop
task.spawn(function()
    while getgenv().STRIX_HUB_LOADED do
        if Config.AutoRoll then
            pcall(function()
                if DataController.AutoRoll and DataController.AutoRoll() ~= true then
                    SetAutoRollRE:FireServer(true)
                end
            end)
            task.wait(1.0)
        else
            task.wait(0.5)
        end
    end
end)

-- 2. Auto Hide Roll Hook
task.spawn(function()
    while getgenv().STRIX_HUB_LOADED do
        if Config.AutoHideRoll then
            setHideRollNative(true)
        end
        task.wait(0.5)
    end
end)

-- 3. Auto Equip Best Plot Loop (Every 10s)
task.spawn(function()
    while getgenv().STRIX_HUB_LOADED do
        if Config.AutoEquipBest then
            pcall(function()
                EquipBestPlotRE:FireServer()
            end)
            task.wait(10.0)
        else
            task.wait(0.5)
        end
    end
end)

-- 4. Auto Collect Plot Balance Loop (Every 10s)
task.spawn(function()
    while getgenv().STRIX_HUB_LOADED do
        if Config.AutoCollect then
            pcall(function()
                local playerRebirth = DataController.Rebirth() or 0
                for slot = 1, 20 do
                    local req = PlotConfig.GetSlotRebirthRequirement(slot)
                    if req <= playerRebirth then
                        CollectBalanceRE:FireServer(slot)
                    end
                end
            end)
            task.wait(10.0)
        else
            task.wait(0.5)
        end
    end
end)

-- 5. Auto Upgrade Plot Units Loop (Starts from slot 1 first)
task.spawn(function()
    while getgenv().STRIX_HUB_LOADED do
        if Config.AutoUpgradePlot then
            pcall(function()
                local targetLv = tonumber(Config.PlotTargetLevel) or 1
                local currentMoney = DataController.Money() or 0
                local rebirth = DataController.Rebirth() or 0
                local maxSlots = (PlotConfig.GetMaxSlots and PlotConfig.GetMaxSlots()) or 18

                for slot = 1, maxSlots do
                    if not Config.AutoUpgradePlot then break end
                    local req = PlotConfig.GetSlotRebirthRequirement(slot)
                    if req <= rebirth then
                        local u = Strix.Farm.GetSlotUnit(slot)
                        if u and u.Level < targetLv then
                            if u.Price and currentMoney >= u.Price then
                                LevelUpSlotRE:FireServer(slot)
                                task.wait(0.25)
                            end
                            -- Focus and finish the earliest slot first before moving to later slots
                            break
                        end
                    end
                end
            end)
            task.wait(0.3)
        else
            task.wait(0.5)
        end
    end
end)

-- 6. Auto Rebirth Loop (Checks money >= next cost)
task.spawn(function()
    while getgenv().STRIX_HUB_LOADED do
        if Config.AutoRebirth then
            pcall(function()
                local currentRebirth = DataController.Rebirth() or 0
                local nextRebirth = Rebirths.GetNext(currentRebirth)
                if nextRebirth and nextRebirth.cost then
                    local currentMoney = DataController.Money() or 0
                    if currentMoney >= nextRebirth.cost then
                        RebirthRE:FireServer()
                    end
                end
            end)
            task.wait(2.5)
        else
            task.wait(0.5)
        end
    end
end)

-- 7. Auto Upgrades Tree Loop (Cheapest available upgrade first)
task.spawn(function()
    while getgenv().STRIX_HUB_LOADED do
        if Config.AutoUpgrades then
            pcall(function()
                local currentMoney = DataController.Money()
                if not currentMoney or currentMoney <= 0 then return end

                local available = {}
                local visited = {}

                local function scanTree(nodeName)
                    if visited[nodeName] then return end
                    visited[nodeName] = true

                    local children = TreeStructure.GetChildren(nodeName)
                    for _, child in ipairs(children) do
                        local owned = false
                        pcall(function()
                            owned = DataController.Upgrades[child]() == true
                        end)
                        if owned then
                            scanTree(child)
                        else
                            local upgradeData = Upgrades[child]
                            if upgradeData and upgradeData.price then
                                table.insert(available, {
                                    name = child,
                                    price = upgradeData.price
                                })
                            end
                        end
                    end
                end

                scanTree("Start")
                table.sort(available, function(a, b) return a.price < b.price end)

                for _, upg in ipairs(available) do
                    if not Config.AutoUpgrades then break end
                    currentMoney = DataController.Money()
                    if currentMoney >= upg.price then
                        BuyUpgradeRE:FireServer(upg.name)
                        task.wait(0.2)
                    end
                end
            end)
            task.wait(2.0)
        else
            task.wait(0.5)
        end
    end
end)

-- 8. Auto Buy Dice Shop Loop
task.spawn(function()
    while getgenv().STRIX_HUB_LOADED do
        if Config.AutoBuyDice then
            pcall(function()
                Strix.Roll.BuyBestAvailableDice()
            end)
            task.wait(3.0)
        else
            task.wait(0.5)
        end
    end
end)

-- 9. Auto Equip Best Dice Loop
task.spawn(function()
    while getgenv().STRIX_HUB_LOADED do
        if Config.AutoEquipBestDice then
            pcall(function()
                Strix.Roll.EquipBestOwnedDice()
            end)
            task.wait(2.0)
        else
            task.wait(0.5)
        end
    end
end)

-- 10. Auto Claim Quests Loop
task.spawn(function()
    while getgenv().STRIX_HUB_LOADED do
        if Config.AutoClaimQuests then
            pcall(function()
                Strix.Progression.InstantClaimQuests()
            end)
            task.wait(5.0)
        else
            task.wait(0.5)
        end
    end
end)

-- 11. Auto Claim Daily Loop
task.spawn(function()
    while getgenv().STRIX_HUB_LOADED do
        if Config.AutoClaimDaily then
            pcall(function()
                local lastClaim = DataController.LastDailyRewardClaim()
                local cooldown = DailyRewardConfig.Cooldown or 82800
                local now = os.time()
                if lastClaim == 0 or (now - lastClaim) >= cooldown then
                    ClaimDailyRE:FireServer()
                end
            end)
            task.wait(10.0)
        else
            task.wait(0.5)
        end
    end
end)

-- 12. Auto Use Spins Loop (Every 5s)
task.spawn(function()
    while getgenv().STRIX_HUB_LOADED do
        if Config.AutoUseSpins then
            pcall(function()
                local inv = (DataController.Inventory and DataController.Inventory()) or {}
                for _, item in pairs(inv) do
                    if not Config.AutoUseSpins then break end
                    if item.name == "Lucky Spin" or item.name == "Jackpot Spin" then
                        UseSpinRE:FireServer(item.name)
                        task.wait(0.1)
                    end
                end
            end)
            task.wait(5.0)
        else
            task.wait(1.0)
        end
    end
end)

-- 13. Auto Use Potions Loop (Consumes ALL matching potions in inventory continuously)
task.spawn(function()
    while getgenv().STRIX_HUB_LOADED do
        if Config.AutoUsePotions then
            pcall(function()
                Strix.Roll.ConsumeSelectedPotions(false)
            end)
            task.wait(2.0)
        else
            task.wait(0.5)
        end
    end
end)

-- 14. Auto Tower Worker Loop (Continuous Loop / Farm)
task.spawn(function()
    while getgenv().STRIX_HUB_LOADED do
        if Config.AutoTower then
            pcall(function()
                local active = Strix.Tower.IsActive()
                if not active then
                    if HUDController and HUDController.showAll then
                        HUDController.showAll("inTower")
                    end
                    local towerRoot = UIReferences and UIReferences.Root and UIReferences.Root.Tower
                    if towerRoot then
                        if towerRoot:FindFirstChild("Hidden") then towerRoot.Hidden.Visible = false end
                        if towerRoot:FindFirstChild("Screen") then towerRoot.Screen.Visible = false end
                        if towerRoot:FindFirstChild("Background") then towerRoot.Background.Visible = false end
                    end
                    task.wait(1.5)
                    if Config.AutoTower and not Strix.Tower.IsActive() then
                        Strix.Tower.Start(Config.SelectedTower)
                    end
                else
                    if Config.AutoHideTowerScreen then
                        if not Strix.Tower.IsHidden() then
                            Strix.Tower.SetBattleScreenHidden(true)
                        end
                    else
                        if Strix.Tower.IsHidden() then
                            Strix.Tower.SetBattleScreenHidden(false)
                        end
                    end
                end
            end)
            task.wait(1.5)
        else
            pcall(function()
                if not Strix.Tower.IsActive() then
                    if HUDController and HUDController.showAll then
                        HUDController.showAll("inTower")
                    end
                    local towerRoot = UIReferences and UIReferences.Root and UIReferences.Root.Tower
                    if towerRoot then
                        if towerRoot:FindFirstChild("Hidden") then towerRoot.Hidden.Visible = false end
                        if towerRoot:FindFirstChild("Screen") then towerRoot.Screen.Visible = false end
                        if towerRoot:FindFirstChild("Background") then towerRoot.Background.Visible = false end
                    end
                end
            end)
            task.wait(1.0)
        end
    end
end)

-- ==============================================================================
-- 5. MACLIB UI SETUP
-- ==============================================================================
local function ApplyConfigToUI()
    isApplyingConfig = true
    local function safe(fn) pcall(fn) end

    -- Always enforce transient states to false
    Config.AutoUsePotions = false
    Config.AutoTower = false

    -- Batch update standard toggle controls: { name, setter, defaultTrue }
    local toggleConfigs = {
        { "AutoRoll", Strix.Roll and Strix.Roll.SetAutoRoll },
        { "AutoHideRoll", Strix.Roll and Strix.Roll.SetHideRoll },
        { "AutoBuyDice", Strix.Roll and Strix.Roll.SetAutoBuyDice },
        { "AutoEquipBestDice", Strix.Roll and Strix.Roll.SetAutoEquipBestDice },
        { "AutoUseSpins", Strix.Roll and Strix.Roll.SetAutoUseSpins },
        { "AutoUsePotions", Strix.Roll and Strix.Roll.SetAutoUsePotions },
        { "AutoCollect", Strix.Farm and Strix.Farm.SetAutoCollect },
        { "AutoEquipBest", Strix.Farm and Strix.Farm.SetAutoEquipBest },
        { "AutoUpgradePlot", Strix.Farm and Strix.Farm.SetAutoUpgradePlot },
        { "AutoRebirth", Strix.Progression and Strix.Progression.SetAutoRebirth },
        { "AutoUpgrades", Strix.Progression and Strix.Progression.SetAutoUpgrades },
        { "AutoClaimQuests", Strix.Progression and Strix.Progression.SetAutoClaimQuests },
        { "AutoClaimDaily", Strix.Progression and Strix.Progression.SetAutoClaimDaily },
        { "AutoTower", Strix.Tower and Strix.Tower.SetAutoTower },
        { "AutoEquipBestTowerTeam", Strix.Tower and Strix.Tower.SetAutoEquipBest, true },
        { "AutoHideTowerScreen", Strix.Tower and Strix.Tower.SetAutoHideScreen },
        { "AcrylicBlur", function(v) if Window and Window.SetAcrylicBlurState then Window:SetAcrylicBlurState(v == true) end end },
        { "ShowUserInfo", function(v) if Window and Window.SetUserInfoState then Window:SetUserInfoState(v ~= false) end end, true },
        { "MobileToggle", function(v) if getgenv().STRIX_MOBILE_GUI then getgenv().STRIX_MOBILE_GUI.Enabled = (v ~= false) end end, true },
        { "AutoSave", nil, true }
    }

    for _, cfg in ipairs(toggleConfigs) do
        local name, setter, defaultTrue = cfg[1], cfg[2], cfg[3]
        local isEnabled
        if name == "AutoUsePotions" or name == "AutoTower" then
            isEnabled = false
        elseif defaultTrue then
            isEnabled = (Config[name] ~= false)
        else
            isEnabled = (Config[name] == true)
        end
        safe(function()
            local ctrl = UIControls[name]
            if ctrl and ctrl.UpdateState then ctrl:UpdateState(isEnabled) end
            if setter then setter(isEnabled) end
        end)
    end

    -- Specific Inputs, Dropdowns, Sliders, and Keybinds
    safe(function()
        if UIControls.RollDelay and UIControls.RollDelay.UpdateValue and Config.RollDelay then
            UIControls.RollDelay:UpdateValue(Config.RollDelay)
        end
        if Strix.Roll and Strix.Roll.SetDelay and Config.RollDelay then
            Strix.Roll.SetDelay(Config.RollDelay)
        end
    end)

    safe(function()
        if UIControls.SelectedPotionTypes and UIControls.SelectedPotionTypes.UpdateSelection and Config.SelectedPotionTypes then
            UIControls.SelectedPotionTypes:UpdateSelection(Config.SelectedPotionTypes)
        end
        if Strix.Roll and Strix.Roll.SetSelectedPotionTypes then
            Strix.Roll.SetSelectedPotionTypes(Config.SelectedPotionTypes)
        end
    end)

    safe(function()
        local amt = Config.AutoSellAmount or 0
        if UIControls.InputAutoSell and UIControls.InputAutoSell.UpdateText then
            UIControls.InputAutoSell:UpdateText(amt > 0 and Strix.Util.FormatComma(amt) or "0")
        end
        if Strix.Farm and Strix.Farm.SetAutoSellThreshold then
            Strix.Farm.SetAutoSellThreshold(amt)
        end
    end)

    safe(function()
        local lv = Config.PlotTargetLevel or 1
        if UIControls.InputPlotTargetLevel and UIControls.InputPlotTargetLevel.UpdateText then
            UIControls.InputPlotTargetLevel:UpdateText(tostring(lv))
        end
        if Strix.Farm and Strix.Farm.SetPlotTargetLevel then
            Strix.Farm.SetPlotTargetLevel(lv)
        end
    end)

    safe(function()
        if UIControls.SelectedTower and UIControls.SelectedTower.UpdateSelection and Config.SelectedTower then
            UIControls.SelectedTower:UpdateSelection(Config.SelectedTower)
        end
        if Strix.Tower and Strix.Tower.SetSelectedTower then
            Strix.Tower.SetSelectedTower(Config.SelectedTower)
        end
    end)

    safe(function()
        if UIControls.MenuKeybind and UIControls.MenuKeybind.Bind and Config.MenuKeybind then
            UIControls.MenuKeybind:Bind(Config.MenuKeybind)
        end
        if Window and Window.SetKeybind and Config.MenuKeybind then
            Window:SetKeybind(Config.MenuKeybind)
        end
    end)

    safe(function()
        local w = tonumber(Config.WindowWidth) or 1000
        local h = tonumber(Config.WindowHeight) or 650
        if MacBaseFrame then MacBaseFrame.Size = UDim2.fromOffset(w, h) end
        if UIControls.WindowWidth and UIControls.WindowWidth.UpdateValue then UIControls.WindowWidth:UpdateValue(w) end
        if UIControls.WindowHeight and UIControls.WindowHeight.UpdateValue then UIControls.WindowHeight:UpdateValue(h) end
    end)

    isApplyingConfig = false
end

Strix.ConfigManager = {
    Save = SaveConfig,
    Load = LoadConfig,
    RequestSave = RequestSaveConfig,
    Apply = ApplyConfigToUI
}

-- Load saved config if available before constructing UI
LoadConfig()
if isfile and not isfile(ConfigFileJSON) and not isfile(ConfigFileUserIdJSON) then
    SaveConfig(true)
end

local camInit = workspace.CurrentCamera
local vpInit = camInit and camInit.ViewportSize or Vector2.new(1920, 1080)
local isMobileDevice = UserInputService.TouchEnabled or (vpInit.Y < 600)

local defaultWinWidth = isMobileDevice and 780 or (tonumber(Config.WindowWidth) or 1000)
local defaultWinHeight = isMobileDevice and 500 or (tonumber(Config.WindowHeight) or 650)

local MacLib = loadstring(game:HttpGet("https://github.com/biggaboy212/Maclib/releases/latest/download/maclib.txt"))()

local Window = MacLib:Window({
    Title = "STRIX HUB",
    Subtitle = "Anime Dice | BY STRIXZY",
    Size = UDim2.fromOffset(defaultWinWidth, defaultWinHeight),
    DragStyle = 1,
    DisabledWindowControls = {},
    ShowUserInfo = (Config.ShowUserInfo ~= false),
    Keybind = Config.MenuKeybind or Enum.KeyCode.RightControl,
    AcrylicBlur = (Config.AcrylicBlur == true),
})

-- Disable notifications completely
Window:SetNotificationsState(false)

-- Hook Window Unload
if Window.onUnloaded then
    Window.onUnloaded(function()
        Strix.Engine.Cleanup()
    end)
end

-- Override Maclib's Dialog to neutralize the broken CanvasGroup reparenting bug & execute exit directly
Window.Dialog = function(self, dialogSettings)
    if dialogSettings and dialogSettings.Buttons then
        for _, btn in ipairs(dialogSettings.Buttons) do
            if btn.Name == "Confirm" and btn.Callback then
                task.spawn(btn.Callback)
                break
            end
        end
    end
    return {
        UpdateTitle = function() end,
        UpdateDescription = function() end,
        Cancel = function() end,
    }
end

local MacBaseFrame = nil
local SliderWinWidth = nil
local SliderWinHeight = nil
local ApplyResponsiveWindow = nil

-- ==============================================================================
-- MOBILE FLOATING TOGGLE BUTTON
-- ==============================================================================
local function CreateMobileToggleButton()
    if getgenv().STRIX_MOBILE_GUI then
        pcall(function()
            getgenv().STRIX_MOBILE_GUI:Destroy()
        end)
        getgenv().STRIX_MOBILE_GUI = nil
    end

    local h = (gethui and gethui()) or game:GetService("CoreGui")
    local mobileGui = Instance.new("ScreenGui")
    mobileGui.Name = "STRIX_MOBILE_TOGGLE"
    mobileGui.ResetOnSpawn = false
    mobileGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    pcall(function()
        mobileGui.DisplayOrder = 999999
    end)

    pcall(function()
        mobileGui.Parent = h
    end)
    if not mobileGui.Parent then
        mobileGui.Parent = LocalPlayer:WaitForChild("PlayerGui")
    end

    getgenv().STRIX_MOBILE_GUI = mobileGui

    -- Floating Button Frame
    local buttonFrame = Instance.new("ImageButton")
    buttonFrame.Name = "FloatingButton"
    buttonFrame.Size = UDim2.fromOffset(46, 46)
    buttonFrame.Position = UDim2.new(0, 15, 0, 140)
    buttonFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
    buttonFrame.BackgroundTransparency = 0.15
    buttonFrame.BorderSizePixel = 0
    buttonFrame.AutoButtonColor = false
    buttonFrame.ZIndex = 1000
    buttonFrame.Active = true
    buttonFrame.Parent = mobileGui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 14)
    corner.Parent = buttonFrame

    local stroke = Instance.new("UIStroke")
    stroke.Name = "BorderStroke"
    stroke.Color = Color3.fromRGB(0, 170, 255)
    stroke.Thickness = 1.4
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Parent = buttonFrame

    -- Inner Icon
    local icon = Instance.new("ImageLabel")
    icon.Name = "Icon"
    icon.Size = UDim2.fromOffset(26, 26)
    icon.Position = UDim2.new(0.5, 0, 0.5, 0)
    icon.AnchorPoint = Vector2.new(0.5, 0.5)
    icon.BackgroundTransparency = 1
    icon.Image = "rbxassetid://10709782230"
    icon.ImageColor3 = Color3.fromRGB(255, 255, 255)
    icon.ZIndex = 1001
    icon.Parent = buttonFrame

    -- Status Glow Dot
    local statusDot = Instance.new("Frame")
    statusDot.Name = "StatusDot"
    statusDot.Size = UDim2.fromOffset(8, 8)
    statusDot.Position = UDim2.new(1, -5, 0, 5)
    statusDot.AnchorPoint = Vector2.new(1, 0)
    statusDot.BackgroundColor3 = Color3.fromRGB(0, 230, 130)
    statusDot.BorderSizePixel = 0
    statusDot.ZIndex = 1002
    statusDot.Parent = buttonFrame

    local dotCorner = Instance.new("UICorner")
    dotCorner.CornerRadius = UDim.new(1, 0)
    dotCorner.Parent = statusDot

    local dotStroke = Instance.new("UIStroke")
    dotStroke.Color = Color3.fromRGB(20, 20, 24)
    dotStroke.Thickness = 1.2
    dotStroke.Parent = statusDot

    local function UpdateVisuals(isOpen)
        if isOpen then
            stroke.Color = Color3.fromRGB(0, 170, 255)
            statusDot.BackgroundColor3 = Color3.fromRGB(0, 230, 130)
            icon.ImageColor3 = Color3.fromRGB(255, 255, 255)
            icon.ImageTransparency = 0
        else
            stroke.Color = Color3.fromRGB(65, 65, 75)
            statusDot.BackgroundColor3 = Color3.fromRGB(255, 80, 80)
            icon.ImageColor3 = Color3.fromRGB(180, 180, 190)
            icon.ImageTransparency = 0.2
        end
    end

    UpdateVisuals(Window:GetState())

    -- Keep visuals synced whenever state changes
    task.spawn(function()
        while getgenv().STRIX_HUB_LOADED and mobileGui and mobileGui.Parent do
            local curState = false
            if Window and Window.GetState then
                curState = Window:GetState()
            elseif MacBaseFrame then
                curState = MacBaseFrame.Visible
            end
            UpdateVisuals(curState)
            task.wait(0.25)
        end
    end)

    -- Toggle handler
    local function ToggleUI()
        local currentState = true
        if Window and Window.GetState then
            currentState = Window:GetState()
        elseif MacBaseFrame then
            currentState = MacBaseFrame.Visible
        end
        local newState = not currentState

        -- Micro bounce animation
        local tweenIn = TweenService:Create(buttonFrame, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            Size = UDim2.fromOffset(40, 40)
        })
        local tweenOut = TweenService:Create(buttonFrame, TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
            Size = UDim2.fromOffset(46, 46)
        })
        tweenIn:Play()
        tweenIn.Completed:Connect(function()
            tweenOut:Play()
        end)

        if Window and Window.SetState then
            Window:SetState(newState)
        elseif MacBaseFrame then
            MacBaseFrame.Visible = newState
        end
        UpdateVisuals(newState)
    end

    local lastToggleTime = 0
    local function SafeToggle()
        local now = tick()
        if now - lastToggleTime < 0.35 then return end
        lastToggleTime = now
        ToggleUI()
    end

    -- Touch and Mouse Dragging
    local isDragging = false
    local dragStart = nil
    local startPos = nil
    local hasMoved = false

    buttonFrame.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            isDragging = true
            dragStart = input.Position
            startPos = buttonFrame.Position
            hasMoved = false
        end
    end)

    buttonFrame.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            isDragging = false
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if isDragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            if dragStart and startPos then
                local delta = input.Position - dragStart
                if delta.Magnitude > 8 then
                    hasMoved = true
                end

                if hasMoved then
                    local cam = workspace.CurrentCamera
                    local viewSize = cam and cam.ViewportSize or Vector2.new(1920, 1080)
                    local targetX = math.clamp(startPos.X.Offset + delta.X, 5, math.max(5, viewSize.X - 52))
                    local targetY = math.clamp(startPos.Y.Offset + delta.Y, 5, math.max(5, viewSize.Y - 52))

                    buttonFrame.Position = UDim2.new(0, targetX, 0, targetY)
                end
            end
        end
    end)

    buttonFrame.Activated:Connect(function()
        if not hasMoved then
            SafeToggle()
        end
    end)

    if Config.MobileToggle == false then
        mobileGui.Enabled = false
    end

    return mobileGui
end

CreateMobileToggleButton()

-- -- Hook Direct Red Button (Exit), Maximize, and Dynamic Resizing Handle
ApplyResponsiveWindow = function(targetBase)
    if not targetBase then return end
    local baseUIScale = targetBase:FindFirstChild("BaseUIScale")
    local cam = workspace.CurrentCamera
    local vp = cam and cam.ViewportSize or Vector2.new(1920, 1080)
    local isMobile = UserInputService.TouchEnabled or (vp.Y < 600)

    if isMobile then
        local baseW = 780
        local baseH = 500
        local scaleY = (vp.Y * 0.84) / baseH
        local scaleX = (vp.X * 0.92) / baseW
        local finalScale = math.clamp(math.min(scaleX, scaleY), 0.45, 0.85)

        if baseUIScale then
            baseUIScale.Scale = finalScale
        end
        targetBase.Size = UDim2.fromOffset(baseW, baseH)
        targetBase.Position = UDim2.fromScale(0.5, 0.5)
    else
        if baseUIScale then
            baseUIScale.Scale = 1.0
        end
        local w = tonumber(Config.WindowWidth) or 1000
        local h = tonumber(Config.WindowHeight) or 650
        targetBase.Size = UDim2.fromOffset(w, h)
    end
end

task.spawn(function()
    task.wait(0.2)
    pcall(function()
        local h = (gethui and gethui()) or game:GetService("CoreGui")
        local base = nil
        local screenGui = nil
        for _, child in ipairs(h:GetChildren()) do
            if child:IsA("ScreenGui") then
                local b = child:FindFirstChild("Base")
                if b and b:FindFirstChild("Sidebar") then
                    base = b
                    screenGui = child
                    break
                end
            end
        end
        if not base and LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui") then
            for _, child in ipairs(LocalPlayer.PlayerGui:GetChildren()) do
                if child:IsA("ScreenGui") then
                    local b = child:FindFirstChild("Base")
                    if b and b:FindFirstChild("Sidebar") then
                        base = b
                        screenGui = child
                        break
                    end
                end
            end
        end

        if base then
            MacBaseFrame = base
            ApplyResponsiveWindow(base)

            local cam = workspace.CurrentCamera
            if cam then
                cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
                    if MacBaseFrame then
                        ApplyResponsiveWindow(MacBaseFrame)
                    end
                end)
            end

            local content = base:FindFirstChild("Content")
            local sidebar = base:FindFirstChild("Sidebar")
            local exitBtn = base:FindFirstChild("Exit", true)

            if screenGui then
                screenGui.Destroying:Connect(function()
                    if getgenv().STRIX_CORE == Strix then
                        Strix.Engine.Cleanup()
                    end
                end)
            end

            if exitBtn and exitBtn:IsA("TextButton") then
                -- Replace exitBtn with a fresh clone to completely detach Maclib's internal broken Dialog listener
                local parent = exitBtn.Parent
                local cleanExit = exitBtn:Clone()
                cleanExit.Name = "ExitClean"
                cleanExit.LayoutOrder = exitBtn.LayoutOrder
                cleanExit.Parent = parent
                pcall(function()
                    exitBtn:Destroy()
                end)

                local exited = false
                local function doExit()
                    if exited then return end
                    exited = true
                    pcall(function()
                        Strix.Engine.Cleanup()
                    end)
                    pcall(function()
                        Window:Unload()
                    end)
                    pcall(function()
                        if screenGui and screenGui.Parent then
                            screenGui:Destroy()
                        end
                    end)
                end

                cleanExit.MouseButton1Click:Connect(doExit)
                cleanExit.Activated:Connect(doExit)
            end

            -- Keep content size synced with dynamic base resizing
            base:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
                if content and sidebar then
                    content.Size = UDim2.new(0, base.AbsoluteSize.X - sidebar.AbsoluteSize.X, 1, 0)
                end
            end)

            -- Green Button (Maximize / Restore)
            local maxBtn = base:FindFirstChild("Maximize", true)
            if maxBtn and maxBtn:IsA("TextButton") then
                local isMax = false
                local defaultSize = UDim2.fromOffset(1000, 650)
                maxBtn.MouseButton1Click:Connect(function()
                    isMax = not isMax
                    local tInfo = TweenInfo.new(0.25, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
                    local camCurr = workspace.CurrentCamera
                    local vpCurr = camCurr and camCurr.ViewportSize or Vector2.new(1920, 1080)
                    local isMobCurr = UserInputService.TouchEnabled or (vpCurr.Y < 600)

                    if isMobCurr then
                        local baseUIScale = base:FindFirstChild("BaseUIScale")
                        if baseUIScale then
                            baseUIScale.Scale = isMax and 0.85 or math.clamp(math.min((vpCurr.X * 0.92) / 780, (vpCurr.Y * 0.84) / 500), 0.45, 0.85)
                        end
                    else
                        if isMax then
                            local targetW, targetH = 1180, 750
                            Config.WindowWidth = targetW
                            Config.WindowHeight = targetH
                            TweenService:Create(base, tInfo, {
                                Size = UDim2.fromOffset(targetW, targetH)
                            }):Play()
                            pcall(function()
                                if SliderWinWidth then SliderWinWidth:UpdateValue(targetW) end
                                if SliderWinHeight then SliderWinHeight:UpdateValue(targetH) end
                            end)
                        else
                            Config.WindowWidth = 1000
                            Config.WindowHeight = 650
                            TweenService:Create(base, tInfo, {
                                Size = defaultSize
                            }):Play()
                            pcall(function()
                                if SliderWinWidth then SliderWinWidth:UpdateValue(1000) end
                                if SliderWinHeight then SliderWinHeight:UpdateValue(650) end
                            end)
                        end
                        RequestSaveConfig()
                    end
                end)
            end

            -- Bottom-Right Corner Resize Grip Handle
            local oldGrip = base:FindFirstChild("StrixResizeHandle")
            if oldGrip then oldGrip:Destroy() end

            local resizeHandle = Instance.new("TextButton")
            resizeHandle.Name = "StrixResizeHandle"
            resizeHandle.Size = UDim2.fromOffset(24, 24)
            resizeHandle.AnchorPoint = Vector2.new(1, 1)
            resizeHandle.Position = UDim2.new(1, 0, 1, 0)
            resizeHandle.BackgroundTransparency = 1
            resizeHandle.Text = ""
            resizeHandle.ZIndex = 100
            resizeHandle.Parent = base

            local gripIcon = Instance.new("ImageLabel")
            gripIcon.Name = "GripIcon"
            gripIcon.Size = UDim2.fromOffset(13, 13)
            gripIcon.AnchorPoint = Vector2.new(1, 1)
            gripIcon.Position = UDim2.new(1, -4, 1, -4)
            gripIcon.BackgroundTransparency = 1
            gripIcon.Image = "rbxassetid://10734898934" -- lucide-move-diagonal-2
            gripIcon.ImageTransparency = 0.5
            gripIcon.ImageColor3 = Color3.fromRGB(180, 180, 180)
            gripIcon.ZIndex = 101
            gripIcon.Parent = resizeHandle

            resizeHandle.MouseEnter:Connect(function()
                gripIcon.ImageTransparency = 0.1
                gripIcon.ImageColor3 = Color3.fromRGB(255, 255, 255)
            end)
            resizeHandle.MouseLeave:Connect(function()
                gripIcon.ImageTransparency = 0.5
                gripIcon.ImageColor3 = Color3.fromRGB(180, 180, 180)
            end)

            local isResizing = false
            local startMouse = Vector2.zero
            local startBaseW = 1000
            local startBaseH = 650
            local startBasePos = UDim2.new(0.5, 0, 0.5, 0)
            local currentScale = 1.0

            local function getEffectiveScale()
                local s = base:FindFirstChild("BaseUIScale")
                if s and s:IsA("UIScale") and s.Scale > 0.05 then
                    return s.Scale
                end
                return 1.0
            end

            resizeHandle.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                    isResizing = true
                    startMouse = UserInputService:GetMouseLocation()
                    startBaseW = base.Size.X.Offset
                    startBaseH = base.Size.Y.Offset
                    startBasePos = base.Position
                    currentScale = getEffectiveScale()
                end
            end)

            UserInputService.InputEnded:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                    if isResizing then
                        isResizing = false
                        Config.WindowWidth = math.floor(base.Size.X.Offset)
                        Config.WindowHeight = math.floor(base.Size.Y.Offset)
                        RequestSaveConfig()
                    end
                end
            end)

            UserInputService.InputChanged:Connect(function(input)
                if isResizing and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
                    local curMouse = UserInputService:GetMouseLocation()
                    local screenDelta = curMouse - startMouse

                    local scale = (currentScale > 0.05) and currentScale or 1.0
                    local unscaledDeltaX = screenDelta.X / scale
                    local unscaledDeltaY = screenDelta.Y / scale

                    local newW = math.clamp(startBaseW + unscaledDeltaX, 550, 1400)
                    local newH = math.clamp(startBaseH + unscaledDeltaY, 380, 950)

                    local actualUnscaledDeltaX = newW - startBaseW
                    local actualUnscaledDeltaY = newH - startBaseH

                    local actualScreenDeltaX = actualUnscaledDeltaX * scale
                    local actualScreenDeltaY = actualUnscaledDeltaY * scale

                    base.Size = UDim2.fromOffset(math.floor(newW), math.floor(newH))
                    base.Position = UDim2.new(
                        startBasePos.X.Scale,
                        startBasePos.X.Offset + (actualScreenDeltaX * 0.5),
                        startBasePos.Y.Scale,
                        startBasePos.Y.Offset + (actualScreenDeltaY * 0.5)
                    )

                    pcall(function()
                        if SliderWinWidth then SliderWinWidth:UpdateValue(math.floor(newW)) end
                        if SliderWinHeight then SliderWinHeight:UpdateValue(math.floor(newH)) end
                    end)
                end
            end)
        end
    end)
end)

-- ==============================================================================
-- 6. TABS & SECTIONS SETUP
-- ==============================================================================
local TabGroup = Window:TabGroup()

local Tabs = {
    Roll = TabGroup:Tab({ Name = "Auto", Image = "rbxassetid://10709782230" }),
    Farm = TabGroup:Tab({ Name = "Home", Image = "rbxassetid://10723407389" }),
    Tower = TabGroup:Tab({ Name = "Towers", Image = "rbxassetid://10734975692" }),
    Prog = TabGroup:Tab({ Name = "Progression", Image = "rbxassetid://10747363465" }),
    Stats = TabGroup:Tab({ Name = "Stats & Info", Image = "rbxassetid://10709773755" }),
    Setting = TabGroup:Tab({ Name = "Setting", Image = "rbxassetid://10734950309" })
}

-- ------------------------------------------------------------------------------
-- 1. TAB: AUTO
-- ------------------------------------------------------------------------------
local RollLeft = Tabs.Roll:Section({ Side = "Left" })
local RollRight = Tabs.Roll:Section({ Side = "Right" })

RollLeft:Header({ Text = "Dice" })

UIControls.AutoRoll = RollLeft:Toggle({
    Name = "Auto Roll",
    Default = Config.AutoRoll,
    Callback = function(v)
        Strix.Roll.SetAutoRoll(v)
        RequestSaveConfig()
    end
}, "Toggle_AutoRoll")

-- Native 2-Way Sync with Game's RollController (Safe Identity 8 Polling)
task.spawn(function()
    while getgenv().STRIX_HUB_LOADED do
        task.wait(0.4)
        pcall(function()
            if DataController and DataController.AutoRoll then
                local isAuto = (DataController.AutoRoll() == true)
                if Config.AutoRoll ~= isAuto then
                    Config.AutoRoll = isAuto
                    if UIControls.AutoRoll and UIControls.AutoRoll.UpdateState then
                        UIControls.AutoRoll:UpdateState(isAuto)
                    end
                end
            end
        end)
    end
end)

UIControls.AutoHideRoll = RollLeft:Toggle({
    Name = "Auto Hide Roll Animation",
    Default = Config.AutoHideRoll,
    Callback = function(v)
        Strix.Roll.SetHideRoll(v)
        RequestSaveConfig()
    end
}, "Toggle_AutoHideRoll")

UIControls.RollDelay = RollLeft:Slider({
    Name = "Roll Speed / Delay",
    Minimum = 0.1,
    Maximum = 5.0,
    Default = Config.RollDelay,
    Precision = 1,
    Suffix = "s",
    Callback = function(v)
        Strix.Roll.SetDelay(v)
        RequestSaveConfig()
    end
}, "Slider_RollDelay")

RollLeft:Divider()
RollLeft:Header({ Text = "Auto Spins & Potions" })

UIControls.AutoUseSpins = RollLeft:Toggle({
    Name = "Auto Spins (Lucky & Jackpot)",
    Default = Config.AutoUseSpins,
    Callback = function(v)
        Strix.Roll.SetAutoUseSpins(v)
        RequestSaveConfig()
    end
}, "Toggle_AutoUseSpins")

UIControls.AutoUsePotions = RollLeft:Toggle({
    Name = "Auto Use Potions (Boosts)",
    Default = false,
    Callback = function(v)
        Strix.Roll.SetAutoUsePotions(v)
        -- Transient feature: intentionally not saved to config
    end
}, "Toggle_AutoUsePotions")

UIControls.SelectedPotionTypes = RollLeft:Dropdown({
    Name = "Select Potion Types",
    Multi = true,
    Options = { "Coin", "Luck", "Damage", "Speed" },
    Default = Config.SelectedPotionTypes or { "Coin", "Luck", "Damage" },
    Callback = function(selected)
        local list = {}
        if type(selected) == "table" then
            for k, v in pairs(selected) do
                if type(k) == "string" and v == true then
                    table.insert(list, k)
                elseif type(v) == "string" then
                    table.insert(list, v)
                end
            end
        end
        Strix.Roll.SetSelectedPotionTypes(list)
        RequestSaveConfig()
    end
}, "Dropdown_PotionTypes")

RollLeft:Button({
    Name = "Use All Selected Potions Now",
    Callback = function()
        task.spawn(function()
            Strix.Roll.ConsumeSelectedPotions(true)
        end)
    end
}, "Btn_UsePotionsOnce")

RollRight:Header({ Text = "Shop & Equipment" })

UIControls.AutoBuyDice = RollRight:Toggle({
    Name = "Auto Buy Dice Shop",
    Default = Config.AutoBuyDice,
    Callback = function(v)
        Strix.Roll.SetAutoBuyDice(v)
        RequestSaveConfig()
    end
}, "Toggle_AutoBuyDice")

UIControls.AutoEquipBestDice = RollRight:Toggle({
    Name = "Auto Equip Best Dice",
    Default = Config.AutoEquipBestDice,
    Callback = function(v)
        Strix.Roll.SetAutoEquipBestDice(v)
        RequestSaveConfig()
    end
}, "Toggle_AutoEquipBestDice")

-- ------------------------------------------------------------------------------
-- 2. TAB: HOME
-- ------------------------------------------------------------------------------
local FarmLeft = Tabs.Farm:Section({ Side = "Left" })
local FarmRight = Tabs.Farm:Section({ Side = "Right" })

FarmLeft:Header({ Text = "Plot" })

UIControls.AutoCollect = FarmLeft:Toggle({
    Name = "Auto Collect",
    Default = Config.AutoCollect,
    Callback = function(v)
        Strix.Farm.SetAutoCollect(v)
        RequestSaveConfig()
    end
}, "Toggle_AutoCollect")

UIControls.AutoEquipBest = FarmLeft:Toggle({
    Name = "Auto Equip Best",
    Default = Config.AutoEquipBest,
    Callback = function(v)
        Strix.Farm.SetAutoEquipBest(v)
        RequestSaveConfig()
    end
}, "Toggle_AutoEquipBest")

local initialSellText = (Config.AutoSellAmount and Config.AutoSellAmount > 0)
    and Strix.Util.FormatComma(Config.AutoSellAmount) or "0"

UIControls.InputAutoSell = FarmLeft:Input({
    Name = "Auto Sell (Threshold)",
    Default = initialSellText,
    Placeholder = "e.g. 7000, 10k, 200,000",
    Callback = function(val)
        Strix.Farm.SetAutoSellThreshold(val)
        RequestSaveConfig()
    end
}, "Input_AutoSell")

FarmLeft:Divider()

FarmLeft:Button({
    Name = "Instant Collect All Plot",
    Callback = function()
        Strix.Farm.InstantCollectAll()
    end
}, "Btn_InstantCollect")

FarmLeft:Button({
    Name = "Instant Equip Best Plot",
    Callback = function()
        Strix.Farm.InstantEquipBest()
    end
}, "Btn_InstantEquip")

FarmRight:Header({ Text = "Plot Upgrades" })

UIControls.AutoUpgradePlot = FarmRight:Toggle({
    Name = "Auto Upgrade Plot",
    Default = Config.AutoUpgradePlot,
    Callback = function(v)
        Strix.Farm.SetAutoUpgradePlot(v)
        RequestSaveConfig()
    end
}, "Toggle_AutoUpgradePlot")

UIControls.InputPlotTargetLevel = FarmRight:Input({
    Name = "Plot Target Level",
    Default = tostring(Config.PlotTargetLevel or 1),
    Placeholder = "e.g. 10, 25, 50",
    Callback = function(val)
        Strix.Farm.SetPlotTargetLevel(val)
        RequestSaveConfig()
    end
}, "Input_PlotTargetLevel")

FarmRight:Button({
    Name = "Instant Upgrade Plot (All to Target)",
    Callback = function()
        task.spawn(function()
            Strix.Farm.InstantUpgradeAll()
        end)
    end
}, "Btn_InstantUpgradePlot")

-- ------------------------------------------------------------------------------
-- 3. TAB: TOWERS
-- ------------------------------------------------------------------------------
local TowerLeft = Tabs.Tower:Section({ Side = "Left" })
local TowerRight = Tabs.Tower:Section({ Side = "Right" })

TowerLeft:Header({ Text = "Auto Tower" })

UIControls.AutoTower = TowerLeft:Toggle({
    Name = "Auto Tower",
    Default = false,
    Callback = function(v)
        Strix.Tower.SetAutoTower(v)
        if not v and not Strix.Tower.IsActive() then
            if HUDController and HUDController.showAll then
                HUDController.showAll("inTower")
            end
            local towerRoot = UIReferences and UIReferences.Root and UIReferences.Root.Tower
            if towerRoot then
                if towerRoot:FindFirstChild("Hidden") then towerRoot.Hidden.Visible = false end
                if towerRoot:FindFirstChild("Screen") then towerRoot.Screen.Visible = false end
                if towerRoot:FindFirstChild("Background") then towerRoot.Background.Visible = false end
            end
        end
        -- Transient feature: intentionally not saved to config
    end
}, "Toggle_AutoTower")

local towerOptions = {
    "Dragon Tower",
    "Cursed Tower",
    "Pirate Tower",
    "Hidden Leaf Tower",
    "Slayer Tower",
    "Shadow Tower",
    "Infinity Tower"
}

UIControls.SelectedTower = TowerLeft:Dropdown({
    Name = "Select Tower to Farm",
    Multi = false,
    Options = towerOptions,
    Default = Config.SelectedTower or "Dragon Tower",
    Callback = function(chosen)
        local name = type(chosen) == "table" and chosen[1] or chosen
        if name then
            Strix.Tower.SetSelectedTower(name)
            RequestSaveConfig()
        end
    end
}, "Dropdown_SelectedTower")

UIControls.AutoEquipBestTowerTeam = TowerLeft:Toggle({
    Name = "Auto Equip Best Team",
    Default = Config.AutoEquipBestTowerTeam ~= false,
    Callback = function(v)
        Strix.Tower.SetAutoEquipBest(v)
        RequestSaveConfig()
    end
}, "Toggle_AutoEquipBestTowerTeam")

UIControls.AutoHideTowerScreen = TowerLeft:Toggle({
    Name = "Auto Hide Tower",
    Default = Config.AutoHideTowerScreen == true,
    Callback = function(v)
        Strix.Tower.SetAutoHideScreen(v)
        Strix.Tower.SetBattleScreenHidden(v)
        RequestSaveConfig()
    end
}, "Toggle_AutoHideTowerScreen")

TowerRight:Header({ Text = "Manual Actions" })

TowerRight:Button({
    Name = "Start Selected Tower Now",
    Callback = function()
        Strix.Tower.Start(Config.SelectedTower)
    end
}, "Btn_StartTower")

TowerRight:Button({
    Name = "Cancel / Exit Current Tower",
    Callback = function()
        Strix.Tower.Cancel()
    end
}, "Btn_CancelTower")

TowerRight:Button({
    Name = "Equip Best Team Now",
    Callback = function()
        Strix.Tower.EquipBestTeam()
    end
}, "Btn_EquipBestTeam")

TowerRight:Divider()
TowerRight:Header({ Text = "Live Tower Status" })

local TowerStatusParagraph = TowerRight:Paragraph({
    Header = "Tower Battle Status",
    Body = "• State: Idle\n• Active Floor: None\n• Target: " .. tostring(Config.SelectedTower or "Dragon Tower")
}, "Para_TowerStatus")

-- Live Polling for Tower Status Paragraph
task.spawn(function()
    while getgenv().STRIX_HUB_LOADED do
        task.wait(1.0)
        pcall(function()
            if TowerStatusParagraph and TowerStatusParagraph.UpdateBody then
                local active = Strix.Tower.IsActive()
                local floorText = Strix.Tower.GetCurrentFloor() or (active and "Battling..." or "None")
                local stateText = active and "Battling (In Tower)" or "Idle (In Lobby)"
                TowerStatusParagraph:UpdateBody(string.format(
                    "• State: %s\n• Active Floor: %s\n• Target: %s\n• Auto-Loop: %s",
                    stateText,
                    floorText,
                    tostring(Config.SelectedTower or "Dragon Tower"),
                    Config.AutoTower and "Active" or "Disabled"
                ))
            end
        end)
    end
end)

-- ------------------------------------------------------------------------------
-- 4. TAB: PROGRESSION
-- ------------------------------------------------------------------------------
local ProgLeft = Tabs.Prog:Section({ Side = "Left" })
local ProgRight = Tabs.Prog:Section({ Side = "Right" })

ProgLeft:Header({ Text = "Upgrades & Rebirth" })

UIControls.AutoRebirth = ProgLeft:Toggle({
    Name = "Auto Rebirth",
    Default = Config.AutoRebirth,
    Callback = function(v)
        Strix.Progression.SetAutoRebirth(v)
        RequestSaveConfig()
    end
}, "Toggle_AutoRebirth")

UIControls.AutoUpgrades = ProgLeft:Toggle({
    Name = "Auto Upgrades",
    Default = Config.AutoUpgrades,
    Callback = function(v)
        Strix.Progression.SetAutoUpgrades(v)
        RequestSaveConfig()
    end
}, "Toggle_AutoUpgrades")

ProgRight:Header({ Text = "Rewards & Quests" })

UIControls.AutoClaimQuests = ProgRight:Toggle({
    Name = "Auto Claim Quests (Daily/Weekly)",
    Default = Config.AutoClaimQuests,
    Callback = function(v)
        Strix.Progression.SetAutoClaimQuests(v)
        RequestSaveConfig()
    end
}, "Toggle_AutoClaimQuests")

UIControls.AutoClaimDaily = ProgRight:Toggle({
    Name = "Auto Claim Daily Reward",
    Default = Config.AutoClaimDaily,
    Callback = function(v)
        Strix.Progression.SetAutoClaimDaily(v)
        RequestSaveConfig()
    end
}, "Toggle_AutoClaimDaily")

ProgRight:Divider()

ProgRight:Button({
    Name = "🎁 Auto Redeem All Codes",
    Callback = function()
        task.spawn(function()
            Strix.Progression.RedeemAllCodes()
        end)
    end
}, "Btn_RedeemAllCodes")

-- ------------------------------------------------------------------------------
-- 5. TAB: STATS & INFO
-- ------------------------------------------------------------------------------
local StatsLeft = Tabs.Stats:Section({ Side = "Left" })

StatsLeft:Header({ Text = "Live Player Overview" })

local StatParagraph = StatsLeft:Paragraph({
    Header = "Player Data",
    Body = "กำลังโหลดข้อมูล..."
}, "Para_PlayerStats")

-- Dynamic Real-time Stat Refresh Loop
task.spawn(function()
    while getgenv().STRIX_HUB_LOADED do
        local snap = Strix.Stats.GetSnapshot()
        local autoSellText = (snap.AutoSell > 0)
            and (snap.AutoSellFormatted .. " (" .. snap.AutoSellCompact .. ")")
            or "Disabled (0)"

        pcall(function()
            StatParagraph:UpdateHeader("Player Status (" .. snap.Dice .. ")")
            StatParagraph:UpdateBody(
                "• Money: $" .. snap.MoneyFormatted .. " [" .. snap.MoneyCompact .. "]\n" ..
                "• Rebirth: " .. snap.RebirthFormatted .. "\n" ..
                "• Equipped Dice: " .. snap.Dice .. "\n" ..
                "• Total Rolls: " .. snap.RollsFormatted .. "\n" ..
                "• Auto Sell Limit: " .. autoSellText
            )
        end)
        task.wait(1.5)
    end
end)

-- ------------------------------------------------------------------------------
-- 6. TAB: SETTING
-- ------------------------------------------------------------------------------
local SettingLeft = Tabs.Setting:Section({ Side = "Left" })
local SettingRight = Tabs.Setting:Section({ Side = "Right" })

SettingLeft:Header({ Text = "Menu Keybind" })

UIControls.MenuKeybind = SettingLeft:Keybind({
    Name = "Toggle Menu Key",
    Default = Config.MenuKeybind,
    onBinded = function(newKey)
        if typeof(newKey) == "EnumItem" then
            Config.MenuKeybind = newKey
            Window:SetKeybind(newKey)
            RequestSaveConfig()
        end
    end
}, "Keybind_ToggleMenu")

SettingLeft:Divider()

SettingLeft:Button({
    Name = "Hide / Minimize UI Now",
    Callback = function()
        Window:SetState(false)
    end
}, "Btn_HideUI")

SettingLeft:Divider()

SettingLeft:Header({ Text = "Configuration (Save / Load)" })

local ConfigStatusParagraph = SettingLeft:Paragraph({
    Header = "Profile: " .. AccountName .. " (" .. AccountUserId .. ")",
    Body = "• File: Workspace/" .. ConfigFileJSON .. "\n• Status: Ready & Loaded\n• Anti-AFK: Always Active (Auto)"
}, "Para_ConfigStatus")

UIControls.AutoSave = SettingLeft:Toggle({
    Name = "Auto Save Config",
    Default = Config.AutoSave ~= false,
    Callback = function(v)
        Config.AutoSave = v
        if v then
            SaveConfig(false)
            if ConfigStatusParagraph and ConfigStatusParagraph.UpdateBody then
                ConfigStatusParagraph:UpdateBody("• File: Workspace/" .. ConfigFileJSON .. "\n• Status: Auto-save Enabled (Saved)")
            end
        else
            if ConfigStatusParagraph and ConfigStatusParagraph.UpdateBody then
                ConfigStatusParagraph:UpdateBody("• File: Workspace/" .. ConfigFileJSON .. "\n• Status: Auto-save Disabled")
            end
        end
    end
}, "Toggle_AutoSave")

SettingLeft:Button({
    Name = "Save Config Now",
    Callback = function()
        local ok, err = SaveConfig(false)
        if ConfigStatusParagraph and ConfigStatusParagraph.UpdateBody then
            if ok then
                ConfigStatusParagraph:UpdateBody("• File: Workspace/" .. ConfigFileJSON .. "\n• Status: Saved Manually Just Now!")
            else
                ConfigStatusParagraph:UpdateBody("• File: Workspace/" .. ConfigFileJSON .. "\n• Status: Save Failed: " .. tostring(err))
            end
        end
    end
}, "Btn_SaveConfigNow")

SettingLeft:Button({
    Name = "Reload Config from File",
    Callback = function()
        local ok, err = LoadConfig()
        if ok then
            ApplyConfigToUI()
            if ConfigStatusParagraph and ConfigStatusParagraph.UpdateBody then
                ConfigStatusParagraph:UpdateBody("• File: Workspace/" .. ConfigFileJSON .. "\n• Status: Reloaded & Applied Successfully!")
            end
        else
            if ConfigStatusParagraph and ConfigStatusParagraph.UpdateBody then
                ConfigStatusParagraph:UpdateBody("• File: Workspace/" .. ConfigFileJSON .. "\n• Status: Reload Failed: " .. tostring(err))
            end
        end
    end
}, "Btn_ReloadConfig")

SettingRight:Header({ Text = "UI Options" })

UIControls.AcrylicBlur = SettingRight:Toggle({
    Name = "Acrylic Blur",
    Default = Window:GetAcrylicBlurState(),
    Callback = function(bool)
        Window:SetAcrylicBlurState(bool)
        Config.AcrylicBlur = bool
        RequestSaveConfig()
    end
}, "Toggle_AcrylicBlur")

UIControls.ShowUserInfo = SettingRight:Toggle({
    Name = "Show User Info",
    Default = Window:GetUserInfoState(),
    Callback = function(bool)
        Window:SetUserInfoState(bool)
        Config.ShowUserInfo = bool
        RequestSaveConfig()
    end
}, "Toggle_UserInfo")

UIControls.MobileToggle = SettingRight:Toggle({
    Name = "Mobile Toggle Button",
    Default = Config.MobileToggle ~= false,
    Callback = function(bool)
        Config.MobileToggle = bool
        if getgenv().STRIX_MOBILE_GUI then
            getgenv().STRIX_MOBILE_GUI.Enabled = bool
        end
        RequestSaveConfig()
    end
}, "Toggle_MobileToggleBtn")

SettingRight:Divider()

SettingRight:Header({ Text = "Window Sizing" })

SliderWinWidth = SettingRight:Slider({
    Name = "Window Width",
    Minimum = 550,
    Maximum = 1400,
    Default = defaultWinWidth,
    Precision = 0,
    DisplayMethod = "Value",
    onInputComplete = function(w)
        if MacBaseFrame then
            MacBaseFrame.Size = UDim2.fromOffset(w, MacBaseFrame.Size.Y.Offset)
            Config.WindowWidth = math.floor(w)
            RequestSaveConfig()
        end
    end,
    Callback = function(w)
    end
}, "Slider_WinWidth")
UIControls.WindowWidth = SliderWinWidth

SliderWinHeight = SettingRight:Slider({
    Name = "Window Height",
    Minimum = 380,
    Maximum = 950,
    Default = defaultWinHeight,
    Precision = 0,
    DisplayMethod = "Value",
    onInputComplete = function(h)
        if MacBaseFrame then
            MacBaseFrame.Size = UDim2.fromOffset(MacBaseFrame.Size.X.Offset, h)
            Config.WindowHeight = math.floor(h)
            RequestSaveConfig()
        end
    end,
    Callback = function(h)
    end
}, "Slider_WinHeight")
UIControls.WindowHeight = SliderWinHeight

SettingRight:Button({
    Name = "Fit Screen (Mobile Responsive)",
    Callback = function()
        if MacBaseFrame and ApplyResponsiveWindow then
            ApplyResponsiveWindow(MacBaseFrame)
        end
    end
}, "Btn_FitMobileScreen")

SettingRight:Button({
    Name = "Compact Size (800 x 550)",
    Callback = function()
        if MacBaseFrame then
            MacBaseFrame.Size = UDim2.fromOffset(800, 550)
            MacBaseFrame.Position = UDim2.fromScale(0.5, 0.5)
            Config.WindowWidth = 800
            Config.WindowHeight = 550
            RequestSaveConfig()
            pcall(function()
                if SliderWinWidth then SliderWinWidth:UpdateValue(800) end
                if SliderWinHeight then SliderWinHeight:UpdateValue(550) end
            end)
        end
    end
}, "Btn_CompactWinSize")

SettingRight:Button({
    Name = "Reset Default Size (1000 x 650)",
    Callback = function()
        if MacBaseFrame then
            MacBaseFrame.Size = UDim2.fromOffset(1000, 650)
            MacBaseFrame.Position = UDim2.fromScale(0.5, 0.5)
            Config.WindowWidth = 1000
            Config.WindowHeight = 650
            RequestSaveConfig()
            pcall(function()
                if SliderWinWidth then SliderWinWidth:UpdateValue(1000) end
                if SliderWinHeight then SliderWinHeight:UpdateValue(650) end
            end)
        end
    end
}, "Btn_ResetWinSize")

print("[STRIX HUB] Single-File Standalone Maclib Edition Loaded!")
print("[STRIX HUB] Anti-AFK is automatically active (No toggle required).")

task.wait(10) 
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
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer

-- Place Identification
local LOBBY_PLACE_ID = 117949143041402
local LOBBY_ALT_PLACE_ID = 110388679506690
local GAMEPLAY_PLACE_ID = 107610426295102
local BATTLE_PLACE_ID = GAMEPLAY_PLACE_ID
local isLobby = (game.PlaceId == LOBBY_PLACE_ID or game.PlaceId == LOBBY_ALT_PLACE_ID)
local isBattlePlace = not isLobby
if isLobby then
    getgenv().STRIX_LOBBY_SHOP_BUY_DONE = false
end

-- Remotes & Networking (Safe non-blocking lookups)
local Remotes = ReplicatedStorage:FindFirstChild("Remotes") or ReplicatedStorage:WaitForChild("Remotes", 3)
local function SafeGetRemote(name)
    if not Remotes then return nil end
    local r = Remotes:FindFirstChild(name)
    if not r and not isBattlePlace then
        r = Remotes:WaitForChild(name, 0.5)
    end
    return r
end

local MatchmakingAction = SafeGetRemote("MatchmakingAction")
local TeleportRequest = SafeGetRemote("TeleportRequest")
local UpdateLobbySettings = SafeGetRemote("UpdateLobbySettings")
local RequestJoinLobby = SafeGetRemote("RequestJoinLobby")
local LeaveLobbyEvent = SafeGetRemote("LeaveLobbyEvent")
local GetChallengeData = SafeGetRemote("GetChallengeData")
local RedeemCode = SafeGetRemote("RedeemCode")
local ClaimLevelReward = SafeGetRemote("ClaimLevelReward")
local ClaimUnitIndexReward = SafeGetRemote("ClaimUnitIndexReward")
local BuyItem = SafeGetRemote("BuyItem")
local SummonRequest = SafeGetRemote("SummonRequest")
local GetBannerInfo = SafeGetRemote("GetBannerInfo")
local VoteStartRequest = SafeGetRemote("VoteStartRequest")
local ToggleAutoplay = SafeGetRemote("ToggleAutoplay")
local UpdateSetting = SafeGetRemote("UpdateSetting")

-- Game Events (Safe non-blocking lookups)
local GameEvents = ReplicatedStorage:FindFirstChild("GameEvents") or (not isBattlePlace and ReplicatedStorage:WaitForChild("GameEvents", 2))
local function SafeGetGameEvent(name)
    if not GameEvents then
        GameEvents = ReplicatedStorage:FindFirstChild("GameEvents")
    end
    if not GameEvents then return nil end
    local r = GameEvents:FindFirstChild(name)
    if not r and not isBattlePlace then
        r = GameEvents:WaitForChild(name, 0.5)
    end
    return r
end

local UseUltimateEvent = SafeGetGameEvent("UseUltimateEvent")
local ToggleBehaviorModeRequest = SafeGetGameEvent("ToggleBehaviorModeRequest")
local AFKRejoinRequest = SafeGetGameEvent("AFKRejoinRequest")

-- Game Modules
local Modules = ReplicatedStorage:FindFirstChild("Modules") or ReplicatedStorage:WaitForChild("Modules", 3)
local PlayModule = (function()
    local ok, res = pcall(function()
        return require(Modules.PlayingModule.PlayModule)
    end)
    return ok and res or nil
end)()

local UnitConfig = (function()
    local ok, res = pcall(function()
        return require(Modules.UnitConfig)
    end)
    return ok and res or nil
end)()

local MapConfig = (function()
    local ok, res = pcall(function()
        return require(Modules.PlayingModule.MapConfig)
    end)
    return ok and res or nil
end)()

local ShopConfig = (function()
    local ok, res = pcall(function()
        return require(Modules.ShopModule.ShopConfig)
    end)
    return ok and res or nil
end)()

local ShopModule = (function()
    local ok, res = pcall(function()
        return require(Modules.ShopModule)
    end)
    return ok and res or nil
end)()

local GemsShopModule = (function()
    local ok, res = pcall(function()
        return require(Modules.GemsShopModule)
    end)
    return ok and res or nil
end)()

local RedeemConfig = (function()
    local ok, res = pcall(function()
        return require(Modules.RedeemCodeModule.RedeemConfig)
    end)
    return ok and res or nil
end)()

local LevelItemConfig = (function()
    local ok, res = pcall(function()
        return require(Modules.LevelMileStoneModule.LevelItemConfig)
    end)
    return ok and res or nil
end)()

-- Active Codes Database
local ActiveCodes = {
    "THANKSFOR10KCCU",
    "THANKSFOR9000CCU",
    "THANKSFOR8000CCU",
    "THANKSFOR3MVISIT",
    "THANKSFOR2MVISIT",
    "THANKSFOR1MVITS",
    "THANKSFOR20KMEMBERDISCORD",
    "CC1"
}

-- Milestone Level List
local MilestoneLevels = {5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60, 65, 70, 75, 80, 85, 90, 95, 100}

-- Shop Items Database
local ShopItemList = {
    "Fruit_1", "Fruit_2", "RareShard", "EpicShard", "LegendShard",
    "MythicShard", "MysteriousShard", "Trait", "StatRerollAll", "StatReroll", "MysteryCapsule"
}

local StageUnlockHelper = (function()
    local ok, res = pcall(function()
        return require(Modules.PlayingModule.StageUnlockHelper)
    end)
    return ok and res or nil
end)()

-- ------------------------------------------------------------------------------
-- Dedicated Mode Databases & Stage / Difficulty Rules
-- ------------------------------------------------------------------------------
local StoryDatabase = {
    ["Namek World"] = { Name = "Namek World", Mode = "Story", MapToCreate = "GreenForest", TotalStages = 5, Difficulties = { "Normal", "Hard", "Nightmare" } },
    ["Kirigakure Village"] = { Name = "Kirigakure Village", Mode = "Story", MapToCreate = "KirigakureVillage", TotalStages = 5, Difficulties = { "Normal", "Hard", "Nightmare" } },
    ["Cursed Mall"] = { Name = "Cursed Mall", Mode = "Story", MapToCreate = "CursedMall", TotalStages = 5, Difficulties = { "Normal", "Hard", "Nightmare" } },
    ["Valhalla Arena"] = { Name = "Valhalla Arena", Mode = "Story", MapToCreate = "ValhallaArena", TotalStages = 5, Difficulties = { "Normal", "Hard", "Nightmare" } },
}
local StoryMapOptions = { "Namek World", "Kirigakure Village", "Cursed Mall", "Valhalla Arena" }
local StoryStageOptions = { "1", "2", "3", "4", "5" }

local MysteriosDatabase = {
    ["Namek World"] = { Name = "Namek World", Mode = "Mysterios", MapToCreate = "GreenForestMyterious", TotalStages = 3, Difficulties = { "Normal", "Hard", "Nightmare" } },
    ["Kirigakure Village"] = { Name = "Kirigakure Village", Mode = "Mysterios", MapToCreate = "KirigakureVillageMyterious", TotalStages = 3, Difficulties = { "Normal", "Hard", "Nightmare" } },
    ["Cursed Mall"] = { Name = "Cursed Mall", Mode = "Mysterios", MapToCreate = "CursedMallMyterious", TotalStages = 3, Difficulties = { "Normal", "Hard", "Nightmare" } },
    ["Valhalla Arena"] = { Name = "Valhalla Arena", Mode = "Mysterios", MapToCreate = "ValhallaArenaMyterious", TotalStages = 3, Difficulties = { "Normal", "Hard", "Nightmare" } },
}
local MysteriosMapOptions = { "Namek World", "Kirigakure Village", "Cursed Mall", "Valhalla Arena" }
local MysteriosStageOptions = { "1", "2", "3" }

local RaidsDatabase = {
    ["Alabasta Arc"] = { Name = "Alabasta Arc", Mode = "Raids", MapToCreate = "AlabastaArc", TotalStages = 3, Difficulties = { "Normal", "Hard", "Nightmare" } },
    ["Scepter Tower"] = { Name = "Scepter Tower", Mode = "Raids", MapToCreate = "ScepterTower", TotalStages = 3, Difficulties = { "Normal", "Hard", "Nightmare" } },
}
local RaidsMapOptions = { "Alabasta Arc", "Scepter Tower" }
local RaidsStageOptions = { "1", "2", "3" }

local BossDatabase = {
    ["Tokyo Jujutsu High"] = { Name = "Tokyo Jujutsu High (Event)", Mode = "Event", MapToCreate = "CursedAcademy", TotalStages = 1, Difficulties = { "Normal", "Hard", "Nightmare" } },
}
local BossMapOptions = { "Tokyo Jujutsu High" }
local BossStageOptions = { "1" }
local BossDifficultyOptions = { "Normal", "Hard", "Nightmare" }
local StandardDifficultyOptions = { "Normal", "Hard", "Nightmare" }

-- ==============================================================================
-- 2. STATE CONFIGURATION (CENTRAL CONFIG SCHEMA)
-- ==============================================================================
local Config = {
    -- 1. Story Mode
    AutoCreateStory = false,
    StoryMap = "Namek World",
    StoryStage = "1",
    StoryDifficulty = "Normal",

    -- 2. Mysterios Mode
    AutoCreateMysterios = false,
    MysteriosMap = "Namek World",
    MysteriosStage = "1",
    MysteriosDifficulty = "Normal",

    -- 3. Raids Mode
    AutoCreateRaids = false,
    RaidsMap = "Alabasta Arc",
    RaidsStage = "1",
    RaidsDifficulty = "Normal",

    -- 4. Boss Event Mode
    AutoCreateBoss = false,
    BossMap = "Tokyo Jujutsu High",
    BossStage = "1",
    BossDifficulty = "Normal",

    -- General Matchmaking Start
    AutoStartMatch = false,

    -- Codes
    AutoRedeemCodes = false,

    -- Challenges
    AutoCreateChallenge = false,
    AutoStartChallenge = false,
    SelectedChallenges = { "Weekly" },
    AutoLeaveChallenge = true,
    AutoLeaveOnChallengeReset = true,

    -- Level Rewards
    AutoClaimLevelRewards = false,

    -- Unit Index
    AutoClaimUnitIndex = false,

    -- Shop (Gold / Gems)
    AutoBuyGoldShop = false,
    SelectedGoldItems = {},
    AutoBuyGemsShop = false,
    SelectedGemsItems = {},

    -- Summon
    AutoSummon = false,
    SummonCount = "10x", -- "1x", "10x"
    SummonDelay = 1.5,

    -- In-Game Automation (Replay / Next / Voting Start / Autoplay / Ultimate / Defend)
    AutoVoteStart = true,
    AutoRetry = true,
    AutoNext = true,
    AutoAutoplay = true,
    AutoUltimateSkill = true,
    AutoDefendMoneyUnits = true,

    -- System & UI Settings
    AntiAfkActive = true,
    MenuKeybind = Enum.KeyCode.RightControl,
    WindowWidth = 1000,
    WindowHeight = 650,
    AcrylicBlur = false,
    ShowUserInfo = true,
    MobileToggle = true,
    AutoSave = true
}

-- ==============================================================================
-- 3. CONFIG STORAGE SYSTEM (WORKSPACE / STRIX HUB / <MapName> / <Account>)
-- ==============================================================================
local RootFolder = "STRIX HUB"
local MapName = "Anime Mysterious"
local MapFolder = RootFolder .. "/" .. MapName

-- Running Account Identifiers
local AccountName = (LocalPlayer and LocalPlayer.Name) or "default"
local AccountUserId = (LocalPlayer and tostring(LocalPlayer.UserId)) or "0"

-- Account-specific Config Files
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
        -- Transient features forced to false on serialization
        if k == "AutoSummon" then
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
    serialized.AutoSummon = false
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
        writefile(ConfigFileJSON, json)
        if ConfigFileUserIdJSON and ConfigFileUserIdJSON ~= ConfigFileJSON then
            pcall(function() writefile(ConfigFileUserIdJSON, json) end)
        end
    end)

    if success then
        return true
    else
        return false, err
    end
end

local function RequestSaveConfig(immediate)
    if isApplyingConfig then return end
    if Config.AutoSave == false then return end
    if saveDebounceThread then
        task.cancel(saveDebounceThread)
        saveDebounceThread = nil
    end
    if immediate then
        SaveConfig(true)
        return
    end
    saveDebounceThread = task.delay(0.2, function()
        SaveConfig(true)
        saveDebounceThread = nil
    end)
end

local function LoadConfig()
    if not (readfile and isfile) then
        return false, "Executor readfile not available"
    end

    local filePathToRead = nil
    -- 1. Check account file by Username
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
    elseif isfile(RootFolder .. "/animemysterious.json") then
        filePathToRead = RootFolder .. "/animemysterious.json"
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
            if k == "AutoSummon" then
                Config[k] = false
            elseif Config[k] ~= nil then
                if k == "MenuKeybind" and typeof(v) == "string" then
                    local enumKey = Enum.KeyCode[v]
                    if enumKey then
                        Config.MenuKeybind = enumKey
                    end
                elseif k == "StoryStage" or k == "MysteriosStage" or k == "RaidsStage" or k == "BossStage" then
                    Config[k] = tostring(v)
                else
                    Config[k] = v
                end
            end
        end
        if result.SelectedChallenges and type(result.SelectedChallenges) == "table" then
            Config.SelectedChallenges = result.SelectedChallenges
        elseif result.SelectedChallengeTab then
            if result.SelectedChallengeTab == "All" then
                Config.SelectedChallenges = { "Weekly", "Daily", "Regular" }
            else
                Config.SelectedChallenges = { tostring(result.SelectedChallengeTab) }
            end
        end

        if result.SelectedGoldItems and type(result.SelectedGoldItems) == "table" then
            Config.SelectedGoldItems = result.SelectedGoldItems
        elseif result.SelectedGoldItem and type(result.SelectedGoldItem) == "string" and result.SelectedGoldItem ~= "All Items" then
            Config.SelectedGoldItems = { result.SelectedGoldItem }
        else
            Config.SelectedGoldItems = Config.SelectedGoldItems or {}
        end

        if result.SelectedGemsItems and type(result.SelectedGemsItems) == "table" then
            Config.SelectedGemsItems = result.SelectedGemsItems
        elseif result.SelectedGemsItem and type(result.SelectedGemsItem) == "string" and result.SelectedGemsItem ~= "All Items" then
            Config.SelectedGemsItems = { result.SelectedGemsItem }
        else
            Config.SelectedGemsItems = Config.SelectedGemsItems or {}
        end
        Config.AutoSummon = false
        return true, result
    else
        return false, result
    end
end

-- ==============================================================================
-- 4. CORE LOGIC ENGINE (STRIX API)
-- ==============================================================================
local Strix = {
    Config = Config,
    Matchmaking = {},
    Challenges = {},
    Progression = {},
    Shop = {},
    Summon = {},
    Battle = {},
    Engine = {}
}
getgenv().Strix = Strix

-- Helper: Get Player Replica Data safely
function Strix.GetReplicaData()
    if PlayModule and PlayModule.Replica and PlayModule.Replica.Data then
        return PlayModule.Replica.Data
    end
    -- Fallback: Check ReplicaController
    local ok, rc = pcall(function()
        return require(ReplicatedStorage.ReplicaLib.ReplicatedStorage.ReplicaController)
    end)
    if ok and rc and rc._replicas then
        for _, rep in pairs(rc._replicas) do
            if rep.Class == "PlayerData" and rep.Data then
                return rep.Data
            end
        end
    end
    return nil
end

-- ------------------------------------------------------------------------------
-- 1, 2, 3: Matchmaking Engine (Story / Mysterious / Raids / Boss Event)
-- ------------------------------------------------------------------------------
function Strix.Matchmaking.ValidateMapAndStage(mapToCreate, stageNum, mode)
    local repData = Strix.GetReplicaData()
    local cleared = (repData and repData.ClearedStages) or {}
    local clearedC = (repData and repData.ClearedChallenges) or {}

    if not StageUnlockHelper then
        return true, "Unlocked"
    end

    local isMapUnlocked, mapErr = StageUnlockHelper.IsMapUnlocked(mapToCreate, cleared, mode)
    if not isMapUnlocked then
        return false, tostring(mapErr or "Map Locked")
    end

    local isStageUnlocked, stageErr = StageUnlockHelper.IsStageUnlocked(mapToCreate, tonumber(stageNum) or 1, cleared, clearedC, mode)
    if not isStageUnlocked then
        return false, tostring(stageErr or "Stage Locked")
    end

    return true, "Unlocked"
end

function Strix.Matchmaking.GetHighestUnlockedStage(mapToCreate, totalStages, mode)
    local highest = 1
    local total = totalStages or 1
    for s = 1, total do
        local ok = Strix.Matchmaking.ValidateMapAndStage(mapToCreate, s, mode)
        if ok then
            highest = s
        else
            break
        end
    end
    return highest
end

function Strix.Matchmaking.IsRoomCreated()
    if isBattlePlace then return false end
    local playGUI = LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui") and LocalPlayer.PlayerGui:FindFirstChild("PlayGUI")
    local pf = playGUI and playGUI:FindFirstChild("PlayFrame")
    if pf and pf.Visible then return true end
    if PlayModule and PlayModule.isHost == true then return true end
    return false
end

function Strix.Matchmaking.StartCurrentRoom()
    local started = false
    pcall(function()
        local playGUI = LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui") and LocalPlayer.PlayerGui:FindFirstChild("PlayGUI")
        local pf = playGUI and playGUI:FindFirstChild("PlayFrame")
        local playBtn = pf and pf:FindFirstChild("ContainerBtn") and pf.ContainerBtn:FindFirstChild("PlayBtn")
        if playBtn and playBtn.Visible and playBtn.Interactable then
            if firesignal then
                firesignal(playBtn.MouseButton1Click)
                started = true
            else
                for _, c in ipairs(getconnections(playBtn.MouseButton1Click)) do
                    c:Fire()
                    started = true
                end
            end
        end
    end)
    return started
end

function Strix.Matchmaking.CreateMatchDirect(entry, stageNum, difficulty)
    if not entry then return false, "No entry" end
    local total = entry.TotalStages or 1
    local clampedStage = math.clamp(tonumber(stageNum) or 1, 1, total)
    local stageStr = tostring(clampedStage)
    local diff = difficulty or "Normal"

    -- 0. Check if room is already created
    if Strix.Matchmaking.IsRoomCreated() then
        pcall(function()
            UpdateLobbySettings:FireServer(entry.Name, stageStr, {}, diff, entry.MapToCreate, entry.Mode)
        end)
        return true, "Room already created"
    end

    -- 1. Validate unlock
    local isUnlocked, reason = Strix.Matchmaking.ValidateMapAndStage(entry.MapToCreate, stageStr, entry.Mode)
    if not isUnlocked then
        return false, reason
    end

    -- 2. Request Lobby Creation if not already host
    pcall(function()
        if not (PlayModule and PlayModule.isHost == true) then
            return RequestJoinLobby:InvokeServer("Create")
        end
    end)

    -- 3. Open Target Map & Select Stage/Difficulty in Client UI
    pcall(function()
        if PlayModule and PlayModule.OpenTargetMap then
            PlayModule.OpenTargetMap(entry.Mode, entry.MapToCreate, tonumber(stageStr) or stageStr, diff)
        end
    end)

    task.wait(0.25)

    -- 4. Select Difficulty button in SelectPlayer UI (Normal / Hard / Nightmare)
    pcall(function()
        local playGUI = LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui") and LocalPlayer.PlayerGui:FindFirstChild("PlayGUI")
        local sp = playGUI and playGUI:FindFirstChild("SelectPlayer")
        local sdf = sp and sp:FindFirstChild("ShowDetailsFrame")
        local modeFrame = sdf and sdf:FindFirstChild("Mode")
        local diffBtn = modeFrame and modeFrame:FindFirstChild(diff .. "Btn")
        if diffBtn and diffBtn.Visible then
            if firesignal then
                firesignal(diffBtn.MouseButton1Click)
            else
                for _, c in ipairs(getconnections(diffBtn.MouseButton1Click)) do
                    c:Fire()
                end
            end
        end
    end)

    task.wait(0.2)

    -- 5. Click the green "Create" button on SelectPlayer to enter the game lobby room (PlayFrame)
    local enteredPlayFrame = false
    pcall(function()
        local playGUI = LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui") and LocalPlayer.PlayerGui:FindFirstChild("PlayGUI")
        local sp = playGUI and playGUI:FindFirstChild("SelectPlayer")
        local createBtn = sp and sp:FindFirstChild("CreateBtn")
        if createBtn and createBtn.Visible then
            if firesignal then
                firesignal(createBtn.MouseButton1Click)
                enteredPlayFrame = true
            else
                for _, c in ipairs(getconnections(createBtn.MouseButton1Click)) do
                    c:Fire()
                    enteredPlayFrame = true
                end
            end
        end
    end)

    -- 6. Direct sync to guarantee PlayFrame is opened and lobby settings match
    pcall(function()
        if not enteredPlayFrame and PlayModule and PlayModule.OpenPlayFrame then
            PlayModule.OpenPlayFrame()
        end
        UpdateLobbySettings:FireServer(entry.Name, stageStr, {}, diff, entry.MapToCreate, entry.Mode)
    end)

    return true
end

function Strix.Matchmaking.StartMatchDirect(entry, stageNum, difficulty)
    if not entry then return false, "No entry" end
    local total = entry.TotalStages or 1
    local clampedStage = math.clamp(tonumber(stageNum) or 1, 1, total)
    local stageStr = tostring(clampedStage)
    local diff = difficulty or "Normal"

    -- Validate unlock before teleporting
    local isUnlocked, reason = Strix.Matchmaking.ValidateMapAndStage(entry.MapToCreate, stageStr, entry.Mode)
    if not isUnlocked then
        return false, reason
    end

    -- 1. Click in-game PlayBtn in PlayFrame if present
    Strix.Matchmaking.StartCurrentRoom()

    -- 2. Direct Teleport Request to Battle / Gameplay Place
    pcall(function()
        TeleportRequest:FireServer(BATTLE_PLACE_ID, entry.Mode, entry.MapToCreate, stageStr, diff)
    end)
    pcall(function()
        TeleportRequest:FireServer(97246719761307, entry.Mode, entry.MapToCreate, stageStr, diff)
    end)

    return true
end

function Strix.Matchmaking.CreateStoryMatch()
    local entry = StoryDatabase[Config.StoryMap] or StoryDatabase["Namek World"]
    return Strix.Matchmaking.CreateMatchDirect(entry, Config.StoryStage, Config.StoryDifficulty)
end

function Strix.Matchmaking.CreateMysteriosMatch()
    local entry = MysteriosDatabase[Config.MysteriosMap] or MysteriosDatabase["Namek World"]
    return Strix.Matchmaking.CreateMatchDirect(entry, Config.MysteriosStage, Config.MysteriosDifficulty)
end

function Strix.Matchmaking.CreateRaidsMatch()
    local entry = RaidsDatabase[Config.RaidsMap] or RaidsDatabase["Alabasta Arc"]
    return Strix.Matchmaking.CreateMatchDirect(entry, Config.RaidsStage, Config.RaidsDifficulty)
end

function Strix.Matchmaking.CreateBossMatch()
    local entry = BossDatabase[Config.BossMap] or BossDatabase["Tokyo Jujutsu High"]
    return Strix.Matchmaking.CreateMatchDirect(entry, Config.BossStage or "1", Config.BossDifficulty or "Normal")
end

function Strix.Matchmaking.CancelMatch()
    pcall(function()
        MatchmakingAction:InvokeServer("Cancel")
        LeaveLobbyEvent:FireServer()
    end)
    pcall(function()
        local playGUI = LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui") and LocalPlayer.PlayerGui:FindFirstChild("PlayGUI")
        local pf = playGUI and playGUI:FindFirstChild("PlayFrame")
        local cancelBtn = pf and pf:FindFirstChild("ContainerBtn") and pf.ContainerBtn:FindFirstChild("CancelBtn")
        if cancelBtn and cancelBtn.Visible then
            if firesignal then
                firesignal(cancelBtn.MouseButton1Click)
            else
                for _, c in ipairs(getconnections(cancelBtn.MouseButton1Click)) do c:Fire() end
            end
        end
    end)
    pcall(function()
        if PlayModule and PlayModule.CloseModule then
            PlayModule.CloseModule()
        end
    end)
end

-- ------------------------------------------------------------------------------
-- 5: Challenges Engine (Weekly / Daily / Regular)
-- ------------------------------------------------------------------------------
function Strix.Challenges.FetchData()
    local ok, res = pcall(function()
        return GetChallengeData:InvokeServer()
    end)
    if ok and type(res) == "table" then
        return res
    end
    return nil
end

function Strix.Challenges.CheckAvailability(tabName)
    local challengeData = Strix.Challenges.FetchData()
    if not challengeData or not challengeData[tabName] then
        return false, 0, "No Data", "Unknown", "1"
    end
    local repData = Strix.GetReplicaData()
    local cInfo = challengeData[tabName]
    local period = cInfo.PeriodIndex or 0
    local cleared = (repData and repData.ClearedChallenges and repData.ClearedChallenges[tabName]) or 0
    local isAvailable = (period > cleared)
    return isAvailable, cInfo.TimeLeft or 0, isAvailable and "Available" or "Cleared / Cooldown", cInfo.MapName or cInfo.MapToCreate, cInfo.StageName or "1"
end

function Strix.Challenges.GetSortedToRun()
    local selected = Config.SelectedChallenges or {}
    if type(selected) == "string" then
        selected = { selected }
    end
    local hasWeekly = false
    local hasDaily = false
    local hasRegular = false
    for _, name in pairs(selected) do
        if name == "Weekly" then hasWeekly = true
        elseif name == "Daily" then hasDaily = true
        elseif name == "Regular" then hasRegular = true
        elseif name == "All" then
            hasWeekly = true
            hasDaily = true
            hasRegular = true
        end
    end
    local ordered = {}
    if hasWeekly then table.insert(ordered, "Weekly") end
    if hasDaily then table.insert(ordered, "Daily") end
    if hasRegular then table.insert(ordered, "Regular") end
    return ordered
end

function Strix.Challenges.GetFirstAvailable()
    if not Config.AutoCreateChallenge then return nil end
    local ordered = Strix.Challenges.GetSortedToRun()
    for _, tab in ipairs(ordered) do
        local isAvail = Strix.Challenges.CheckAvailability(tab)
        if isAvail then
            return tab
        end
    end
    return nil
end

function Strix.Challenges.CreateAndStart(tabName)
    local challengeData = Strix.Challenges.FetchData()
    if not challengeData or not challengeData[tabName] then
        return false, "Challenge data unavailable"
    end

    local repData = Strix.GetReplicaData()
    local cInfo = challengeData[tabName]
    local period = cInfo.PeriodIndex or 0
    local cleared = (repData and repData.ClearedChallenges and repData.ClearedChallenges[tabName]) or 0

    if period <= cleared then
        return false, "Challenge already cleared / on cooldown"
    end

    local mapTitle = tabName .. " Challenge"
    local modeTitle = tabName .. "Challenge"
    local stageName = tostring(cInfo.StageName or "1")
    local rewards = { Items = {} }

    if cInfo.Rewards then
        for _, r in ipairs(cInfo.Rewards) do
            if r.Id == "Coins" then
                rewards.Coins = r.Amount
            elseif r.Id == "Gems" then
                rewards.Gems = r.Amount
            else
                table.insert(rewards.Items, { Chance = 100, Id = r.Id, Count = r.Amount })
            end
        end
    end

    -- Create and set lobby
    if not Strix.Matchmaking.IsRoomCreated() then
        pcall(function()
            RequestJoinLobby:InvokeServer("Create")
        end)
    end
    pcall(function()
        UpdateLobbySettings:FireServer(mapTitle, stageName, rewards, "Nightmare", cInfo.MapToCreate, modeTitle)
    end)

    task.wait(0.4)

    -- Flag current match as challenge
    getgenv().STRIX_IS_CHALLENGE_MATCH = true
    pcall(function()
        if queue_on_teleport then
            queue_on_teleport("getgenv().STRIX_IS_CHALLENGE_MATCH = true")
        end
    end)

    -- Start via PlayBtn if room is created
    Strix.Matchmaking.StartCurrentRoom()

    -- Teleport to match
    pcall(function()
        TeleportRequest:FireServer(BATTLE_PLACE_ID, modeTitle, cInfo.MapToCreate, stageName, "Nightmare")
    end)
    pcall(function()
        TeleportRequest:FireServer(97246719761307, modeTitle, cInfo.MapToCreate, stageName, "Nightmare")
    end)
    return true
end

function Strix.Battle.LeaveMatch()
    pcall(function()
        local eg = LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui") and LocalPlayer.PlayerGui:FindFirstChild("EndGame")
        if eg then
            for _, d in ipairs(eg:GetDescendants()) do
                if d:IsA("GuiButton") and d.Visible then
                    local n = d.Name:lower()
                    if n:find("lobby") or n:find("leave") or n:find("exit") or n:find("back") then
                        if firesignal then
                            firesignal(d.MouseButton1Click)
                        else
                            for _, c in ipairs(getconnections(d.MouseButton1Click)) do c:Fire() end
                        end
                    end
                end
            end
        end
    end)

    pcall(function()
        local ge = ReplicatedStorage:FindFirstChild("GameEvents")
        local leaveReq = ge and ge:FindFirstChild("LeaveGameRequest")
        if leaveReq then
            leaveReq:FireServer()
        end
    end)

    pcall(function()
        local pg = LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui")
        if pg then
            for _, g in ipairs(pg:GetChildren()) do
                if g:IsA("ScreenGui") then
                    for _, d in ipairs(g:GetDescendants()) do
                        if d:IsA("GuiButton") and d.Visible then
                            local n = d.Name:lower()
                            if n == "leavebtn" or n == "lobbybtn" or n == "exitbtn" or n == "leavebutton" then
                                if firesignal then
                                    firesignal(d.MouseButton1Click)
                                else
                                    for _, c in ipairs(getconnections(d.MouseButton1Click)) do c:Fire() end
                                end
                            end
                        end
                    end
                end
            end
        end
    end)

    task.wait(1.0)

    getgenv().STRIX_LOBBY_SHOP_BUY_DONE = false
    pcall(function()
        local TeleportService = game:GetService("TeleportService")
        TeleportService:Teleport(LOBBY_PLACE_ID, LocalPlayer)
    end)
end

function Strix.Challenges.HandleAutoLeave()
    if not (isBattlePlace or game.PlaceId ~= LOBBY_PLACE_ID) then return end

    local isChallenge = (getgenv().STRIX_IS_CHALLENGE_MATCH == true)
    if not isChallenge then
        pcall(function()
            local si = LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui") and LocalPlayer.PlayerGui:FindFirstChild("StageInfo")
            if si then
                for _, d in ipairs(si:GetDescendants()) do
                    if d:IsA("TextLabel") and d.Text:lower():find("challenge") then
                        isChallenge = true
                        getgenv().STRIX_IS_CHALLENGE_MATCH = true
                        break
                    end
                end
            end
        end)
    end

    local pendingResetLeave = (getgenv().STRIX_PENDING_CHALLENGE_RESET_LEAVE == true)
    local shouldLeaveChallenge = (isChallenge and Config.AutoLeaveChallenge == true)

    if not (pendingResetLeave or shouldLeaveChallenge) then
        return
    end

    local matchEnded = false
    pcall(function()
        if LocalPlayer:GetAttribute("GameEnded") or LocalPlayer:GetAttribute("GameOver") or LocalPlayer:GetAttribute("Victory") or LocalPlayer:GetAttribute("Defeat") then
            matchEnded = true
        end
        local eg = LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui") and LocalPlayer.PlayerGui:FindFirstChild("EndGame")
        if eg and eg.Enabled ~= false then
            local frame = eg:FindFirstChild("EndGameFrame") or eg:FindFirstChildWhichIsA("Frame")
            if frame and frame.Visible then
                matchEnded = true
            end
        end
    end)

    if matchEnded and not getgenv().STRIX_LEAVING_CHALLENGE then
        getgenv().STRIX_LEAVING_CHALLENGE = true
        getgenv().STRIX_PENDING_CHALLENGE_RESET_LEAVE = false
        task.spawn(function()
            task.wait(2.5)
            Strix.Battle.LeaveMatch()
            task.wait(5.0)
            getgenv().STRIX_LEAVING_CHALLENGE = false
        end)
    end
end

local lastChallengeResetCycle = nil
function Strix.Challenges.CheckChallengeResetLeave()
    if not Config.AutoLeaveOnChallengeReset then return end
    if not (isBattlePlace or game.PlaceId ~= LOBBY_PLACE_ID) then return end

    local now = os.time()
    local d = os.date("*t", now)
    local currentCycle = math.floor(now / 1800)

    if (d.min == 0 or d.min == 30) and d.sec < 50 then
        if lastChallengeResetCycle ~= currentCycle then
            lastChallengeResetCycle = currentCycle
            getgenv().STRIX_PENDING_CHALLENGE_RESET_LEAVE = true
        end
    end
end

-- ------------------------------------------------------------------------------
-- 4, 6, 7: Progression Engine (Codes, Level Rewards, Unit Index)
-- ------------------------------------------------------------------------------
function Strix.Progression.RedeemAllCodes()
    local count = 0
    for _, code in ipairs(ActiveCodes) do
        pcall(function()
            local ok = RedeemCode:InvokeServer(code)
            if ok then
                count = count + 1
            end
        end)
        task.wait(0.25)
    end
    return count
end

function Strix.Progression.RedeemSingleCode(code)
    if not code or code == "" then return false end
    local ok, res = pcall(function()
        return RedeemCode:InvokeServer(code)
    end)
    return ok and res
end

function Strix.Progression.ClaimAllLevelRewards()
    local repData = Strix.GetReplicaData()
    local playerLvl = (repData and repData.PlayerLevel) or 1
    local claimed = (repData and repData.ClaimedLevelRewards) or {}

    local claimedCount = 0
    for _, lvl in ipairs(MilestoneLevels) do
        if lvl <= playerLvl and not claimed[tostring(lvl)] then
            local ok, res = pcall(function()
                return ClaimLevelReward:InvokeServer(lvl)
            end)
            if ok and res then
                claimedCount = claimedCount + 1
            end
            task.wait(0.2)
        end
    end
    return claimedCount
end

function Strix.Progression.ClaimUnitIndex()
    local ok, res1, res2 = pcall(function()
        return ClaimUnitIndexReward:InvokeServer("All")
    end)
    return ok and res1, res2
end

-- ------------------------------------------------------------------------------
-- 8: Shop Engine (Gold & Gems Shop)
-- ------------------------------------------------------------------------------
local ShopMaxStock = {
    Fruit_1 = 10,
    Fruit_2 = 5,
    RareShard = 10,
    EpicShard = 7,
    LegendShard = 5,
    MythicShard = 3,
    MysteriousShard = 1,
    Trait = 3,
    StatRerollAll = 10,
    StatReroll = 10,
    MysteryCapsule = 50,
}

local function GetShopMod(currency)
    if currency == "Gems" then
        if not GemsShopModule then
            pcall(function() GemsShopModule = require(Modules.GemsShopModule) end)
        end
        return GemsShopModule
    else
        if not ShopModule then
            pcall(function() ShopModule = require(Modules.ShopModule) end)
        end
        return ShopModule
    end
end

local function GetItemMaxStock(itemId, currency)
    if ShopConfig then
        local list = (currency == "Gems") and ShopConfig.GemsShopItems or ShopConfig.GoldShopItems
        if list then
            for _, item in ipairs(list) do
                if item.ID == itemId then
                    return item.MaxStock or 1
                end
            end
        end
    end
    return ShopMaxStock[itemId] or 1
end

function Strix.Shop.GetStockLeft(itemId, currency)
    local curr = (currency == "Gems") and "Gems" or "Coins"
    local maxStock = GetItemMaxStock(itemId, curr)
    local mod = GetShopMod(curr)
    if mod and mod.GetStockLeft then
        local ok, left = pcall(function()
            return mod:GetStockLeft(itemId, maxStock)
        end)
        if ok and type(left) == "number" then
            return math.max(0, left)
        end
    end
    return maxStock
end

function Strix.Shop.BuyItemMax(itemId, currency)
    local curr = (currency == "Gems") and "Gems" or "Coins"
    if not BuyItem then
        BuyItem = SafeGetRemote("BuyItem") or (Remotes and Remotes:FindFirstChild("BuyItem"))
    end
    if not BuyItem then return false, "BuyItem remote unavailable" end

    local stockLeft = Strix.Shop.GetStockLeft(itemId, curr)
    if stockLeft <= 0 then
        return false, "Item Out of Stock"
    end

    -- Attempt batch buy of entire remaining stock in one invoke
    local ok, res1, res2 = pcall(function()
        return BuyItem:InvokeServer(itemId, stockLeft, curr)
    end)

    if ok and (res1 == true or type(res1) == "table") then
        return true, res2
    end

    -- Sequential 1-by-1 buy fallback until depleted or rejected
    local bought = 0
    for _ = 1, stockLeft do
        local ok1, r1 = pcall(function()
            return BuyItem:InvokeServer(itemId, 1, curr)
        end)
        if not ok1 then break end
        if r1 == false then break end
        bought = bought + 1
        task.wait(0.12)
    end
    return (bought > 0), (bought > 0 and "Completed" or res2)
end

function Strix.Shop.BuyBatch(itemList, currency)
    local curr = (currency == "Gems") and "Gems" or "Coins"
    if type(itemList) ~= "table" then return end
    for _, id in ipairs(itemList) do
        if type(id) == "string" and id ~= "" and id ~= "All Items" then
            pcall(function()
                Strix.Shop.BuyItemMax(id, curr)
            end)
            task.wait(0.15)
        end
    end
end

local isAutoBuyingShop = false
function Strix.Shop.PerformLobbyAutoBuy()
    if isBattlePlace then return end
    if isAutoBuyingShop then return end
    isAutoBuyingShop = true
    pcall(function()
        if Config.AutoBuyGoldShop and Config.SelectedGoldItems and #Config.SelectedGoldItems > 0 then
            Strix.Shop.BuyBatch(Config.SelectedGoldItems, "Coins")
        end
        if Config.AutoBuyGemsShop and Config.SelectedGemsItems and #Config.SelectedGemsItems > 0 then
            Strix.Shop.BuyBatch(Config.SelectedGemsItems, "Gems")
        end
    end)
    isAutoBuyingShop = false
end

function Strix.Shop.BuyItem(itemId, amount, currency)
    local amt = tonumber(amount) or 1
    local curr = (currency == "Gems") and "Gems" or "Coins"
    local ok, res1, res2 = pcall(function()
        return BuyItem:InvokeServer(itemId, amt, curr)
    end)
    return ok and res1, res2
end

-- ------------------------------------------------------------------------------
-- 9: Summon Engine
-- ------------------------------------------------------------------------------
function Strix.Summon.PerformSummon(count)
    local amt = (count == "1x" or count == 1) and 1 or 10
    local autoSell = {
        Common = false,
        Rare = false,
        Epic = false,
        Legendary = false,
        Rare_Shiny = false,
        Epic_Shiny = false,
        Legendary_Shiny = false
    }
    local ok, res1, res2 = pcall(function()
        return SummonRequest:InvokeServer(amt, autoSell)
    end)
    return ok and res1, res2
end

-- ------------------------------------------------------------------------------
-- 10: Battle & Runtime Automation Engine
-- ------------------------------------------------------------------------------
local function UpdateGameToggleUI(frame, state)
    if not frame then return end
    local slider = frame:FindFirstChild("Slider")
    local ball = slider and slider:FindFirstChild("Ball")
    if slider and ball then
        local onPos = UDim2.new(0.68, 0, ball.Position.Y.Scale, ball.Position.Y.Offset)
        local offPos = UDim2.new(0.08, 0, ball.Position.Y.Scale, ball.Position.Y.Offset)
        local onBallColor = Color3.fromHex("#4ef499")
        local offBallColor = Color3.fromHex("#ffffff")
        local onSliderColor = Color3.fromHex("#1d5937")
        local offSliderColor = Color3.fromHex("#6c6c6c")

        ball.Position = state and onPos or offPos
        ball.BackgroundColor3 = state and onBallColor or offBallColor
        slider.BackgroundColor3 = state and onSliderColor or offSliderColor
    end
end

function Strix.Battle.SetGameSetting(settingKey, state)
    pcall(function()
        local sm = require(ReplicatedStorage.Modules.SettingModule)
        if sm and sm.SettingsState then
            sm.SettingsState[settingKey] = (state == true)
            if sm.ApplySettingEffect then
                sm:ApplySettingEffect(settingKey, state == true)
            end
            if sm.UI and sm.UI.Toggle and sm.UI.Toggle[settingKey] then
                UpdateGameToggleUI(sm.UI.Toggle[settingKey], state == true)
            end
        end
    end)
    pcall(function()
        if UpdateSetting then
            UpdateSetting:FireServer(settingKey, state == true)
        end
    end)
end

function Strix.Battle.SyncSettings()
    local allowNextRetry = not (getgenv().STRIX_PENDING_CHALLENGE_RESET_LEAVE == true or (getgenv().STRIX_IS_CHALLENGE_MATCH == true and Config.AutoLeaveChallenge == true))
    Strix.Battle.SetGameSetting("AutoVoteStart", Config.AutoVoteStart == true)
    Strix.Battle.SetGameSetting("AutoRetry", allowNextRetry and (Config.AutoRetry == true) or false)
    Strix.Battle.SetGameSetting("AutoNext", allowNextRetry and (Config.AutoNext == true) or false)
    Strix.Battle.SetGameSetting("Autoplay", Config.AutoAutoplay == true)
end

function Strix.Battle.HandleRuntimeVoteStart()
    -- 1. Direct Remote Event
    pcall(function()
        VoteStartRequest:FireServer()
    end)

    -- 2. Click in-game VoteButton if frame is displayed
    pcall(function()
        local mainGui = LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui") and LocalPlayer.PlayerGui:FindFirstChild("Main")
        if mainGui then
            local voteFrame = mainGui:FindFirstChild("VoteStartFrame")
            if voteFrame and voteFrame.Visible then
                local voteBtn = voteFrame:FindFirstChild("VoteButton")
                if voteBtn and voteBtn:IsA("GuiButton") and voteBtn.Visible then
                    firesignal(voteBtn.MouseButton1Click)
                end
            end
        end
    end)
end

function Strix.Battle.HandleRuntimeAutoplay()
    pcall(function()
        local isAuto = LocalPlayer and LocalPlayer:GetAttribute("AutoPlay")
        if not isAuto then
            ToggleAutoplay:FireServer(true)
        end
    end)
end

local function GetPlayerFolder()
    for _, ch in ipairs(workspace:GetChildren()) do
        if ch:IsA("Folder") or ch:IsA("Model") then
            local pf = ch:FindFirstChild("PlayerFolder")
            if pf then return pf end
        end
    end
    return nil
end

local function IsMyUnit(unit)
    if not (unit and unit:IsA("Model")) then return false end
    local ownerId = unit:GetAttribute("OwnerID") or unit:GetAttribute("OwnerId") or unit:GetAttribute("UserId")
    if ownerId then return tonumber(ownerId) == LocalPlayer.UserId end
    local owner = unit:GetAttribute("Owner") or unit:GetAttribute("Player")
    if owner then return owner == LocalPlayer.Name end
    return true
end

local function GetSimulatedTime()
    return workspace:GetAttribute("SimulatedTime") or os.clock()
end

local last_ultimate_use = {}
local function CanUseUltimate(unit)
    if not UnitConfig or not IsMyUnit(unit) then return false end
    local unit_id = unit:GetAttribute("UnitId")
    if not unit_id then return false end
    local data = UnitConfig.GetUnitData(unit_id)
    if not data or not data.UltimateCooldown then return false end
    if (unit:GetAttribute("UpgradeLevel") or 0) < (data.MaxUpgradeLevel or 5) then return false end
    local next_ultimate = unit:GetAttribute("NextUltimate") or 0
    return GetSimulatedTime() >= next_ultimate
end

function Strix.Battle.HandleAutoUltimateSkill()
    pcall(function()
        local folder = GetPlayerFolder()
        local ultEvent = SafeGetGameEvent("UseUltimateEvent") or (GameEvents and GameEvents:FindFirstChild("UseUltimateEvent"))
        if not folder or not ultEvent then return end

        local used_ids = {}
        for _, unit in ipairs(folder:GetChildren()) do
            local unit_id = unit:GetAttribute("UnitId")
            if not unit_id or used_ids[unit_id] or not CanUseUltimate(unit) then continue end

            local now = os.clock()
            if now - (last_ultimate_use[unit_id] or 0) < 0.5 then continue end

            used_ids[unit_id] = true
            last_ultimate_use[unit_id] = now
            ultEvent:FireServer(unit)
        end
    end)
end

local last_defend_toggle = {}
local function IsMoneyUnit(unit)
    if not UnitConfig then return false end
    local unit_id = unit:GetAttribute("UnitId")
    if not unit_id then return false end

    local data = UnitConfig.GetUnitData(unit_id)
    if not data then return false end

    local display_name = data.DisplayName or unit:GetAttribute("DisplayName")
    return type(display_name) == "string" and display_name:find("(Yen)", 1, true) ~= nil
end

function Strix.Battle.HandleAutoDefendMoneyUnits()
    pcall(function()
        local folder = GetPlayerFolder()
        local toggleRemote = SafeGetGameEvent("ToggleBehaviorModeRequest") or (GameEvents and GameEvents:FindFirstChild("ToggleBehaviorModeRequest"))
        if not folder or not toggleRemote then return end

        for _, unit in ipairs(folder:GetChildren()) do
            if not IsMyUnit(unit) or not IsMoneyUnit(unit) then continue end
            if unit:GetAttribute("BehaviorMode") == "Defend" then continue end

            -- Prevent toggle spam before replication
            local now = os.clock()
            if now - (last_defend_toggle[unit] or 0) < 3 then continue end
            last_defend_toggle[unit] = now

            toggleRemote:FireServer(unit)
        end
    end)
end

-- ------------------------------------------------------------------------------
-- Lifecycle Engine
-- ------------------------------------------------------------------------------
function Strix.Engine.StopAll()
    Config.AutoSummon = false
end

function Strix.Engine.Cleanup()
    if saveDebounceThread then
        task.cancel(saveDebounceThread)
        saveDebounceThread = nil
        pcall(function() SaveConfig(true) end)
    end
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

-- Register Global Hooks
getgenv().STRIX_HUB_CLEANUP = Strix.Engine.Cleanup
getgenv().STRIX_CORE = Strix

-- ==============================================================================
-- 5. BACKGROUND AUTOMATION WORKERS
-- ==============================================================================

-- 0. Anti-AFK Worker (Infinite Yield Universal + AntiAFKController & Rejoin Metamethod Hook)
local function DisableGameAfk()
    -- บล็อกคำสั่ง rejoin ที่ client จะส่งไปเซิร์ฟเวอร์
    pcall(function()
        local game_events = ReplicatedStorage:FindFirstChild("GameEvents")
        local rejoin_remote = game_events and game_events:FindFirstChild("AFKRejoinRequest")

        if rejoin_remote and hookmetamethod and getnamecallmethod then
            local wrap = newcclosure or function(f) return f end
            local oldNamecall
            oldNamecall = hookmetamethod(game, "__namecall", wrap(function(self, ...)
                if self == rejoin_remote and getnamecallmethod() == "FireServer" then
                    return
                end
                return oldNamecall(self, ...)
            end))
        end
    end)

    -- ปิดสคริปต์ที่นับเวลา 18 นาที
    pcall(function()
        local player_scripts = LocalPlayer:FindFirstChild("PlayerScripts") or LocalPlayer:WaitForChild("PlayerScripts", 3)
        if player_scripts then
            local controller = player_scripts:FindFirstChild("AntiAFKController")
            if controller then
                controller.Disabled = true
                controller:Destroy()
            end
            player_scripts.ChildAdded:Connect(function(child)
                if child.Name == "AntiAFKController" then
                    pcall(function()
                        child.Disabled = true
                        child:Destroy()
                    end)
                end
            end)
        end
    end)
end
pcall(DisableGameAfk)

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

-- Connect Idled event via VirtualInputManager mouse click simulation (Infinite Yield Standard: Automatic)
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
    Connection = getgenv().STRIX_ANTI_AFK_CONN,
    DisableGameAfk = DisableGameAfk
}

-- 1. Auto Matchmaking & Challenges Worker Loop (Challenges Priority: Weekly > Daily > Regular)
task.spawn(function()
    while getgenv().STRIX_HUB_LOADED do
        if not isBattlePlace then
            pcall(function()
                -- PRIORITY 0: Lobby Auto Buy Shop (Must finish before matchmaking / room creation)
                local hasShopEnabled = (Config.AutoBuyGoldShop and Config.SelectedGoldItems and #Config.SelectedGoldItems > 0)
                    or (Config.AutoBuyGemsShop and Config.SelectedGemsItems and #Config.SelectedGemsItems > 0)

                if hasShopEnabled and not getgenv().STRIX_LOBBY_SHOP_BUY_DONE then
                    getgenv().STRIX_LOBBY_SHOP_BUY_DONE = true
                    task.wait(1.0)
                    Strix.Shop.PerformLobbyAutoBuy()
                    task.wait(0.5)
                end

                -- PRIORITY 1: Check Auto Challenges first (Weekly > Daily > Regular)
                if Config.AutoCreateChallenge then
                    local targetChallenge = Strix.Challenges.GetFirstAvailable()
                    if targetChallenge then
                        if not Strix.Matchmaking.IsRoomCreated() then
                            Strix.Challenges.CreateAndStart(targetChallenge)
                            task.wait(4.0)
                            return
                        else
                            Strix.Matchmaking.StartCurrentRoom()
                            task.wait(3.0)
                            return
                        end
                    end
                end

                -- PRIORITY 2: Standard Auto Create (Story / Mysterios / Raids / Boss) & Auto Start Match
                local anyCreate = (Config.AutoCreateStory or Config.AutoCreateMysterios or Config.AutoCreateRaids or Config.AutoCreateBoss)
                if anyCreate or Config.AutoStartMatch then
                    local targetEntry = nil
                    local targetStage = "1"
                    local targetDiff = "Normal"

                    if Config.AutoCreateStory then
                        targetEntry = StoryDatabase[Config.StoryMap] or StoryDatabase["Namek World"]
                        targetStage = Config.StoryStage or "1"
                        targetDiff = Config.StoryDifficulty or "Normal"
                    elseif Config.AutoCreateMysterios then
                        targetEntry = MysteriosDatabase[Config.MysteriosMap] or MysteriosDatabase["Namek World"]
                        targetStage = Config.MysteriosStage or "1"
                        targetDiff = Config.MysteriosDifficulty or "Normal"
                    elseif Config.AutoCreateRaids then
                        targetEntry = RaidsDatabase[Config.RaidsMap] or RaidsDatabase["Alabasta Arc"]
                        targetStage = Config.RaidsStage or "1"
                        targetDiff = Config.RaidsDifficulty or "Normal"
                    elseif Config.AutoCreateBoss then
                        targetEntry = BossDatabase[Config.BossMap] or BossDatabase["Tokyo Jujutsu High"]
                        targetStage = Config.BossStage or "1"
                        targetDiff = Config.BossDifficulty or "Normal"
                    end

                    if Strix.Matchmaking.IsRoomCreated() then
                        -- Room is already created! Do NOT cancel or recreate!
                        if Config.AutoStartMatch then
                            Strix.Matchmaking.StartCurrentRoom()
                            if targetEntry then
                                Strix.Matchmaking.StartMatchDirect(targetEntry, targetStage, targetDiff)
                            end
                            task.wait(3.0)
                        else
                            task.wait(2.0)
                        end
                    elseif targetEntry then
                        local okCreate = Strix.Matchmaking.CreateMatchDirect(targetEntry, targetStage, targetDiff)
                        task.wait(1.5)
                        if okCreate and Config.AutoStartMatch then
                            Strix.Matchmaking.StartCurrentRoom()
                            Strix.Matchmaking.StartMatchDirect(targetEntry, targetStage, targetDiff)
                            task.wait(3.0)
                        end
                    end
                end
            end)
            task.wait(3.5)
        else
            task.wait(1.0)
        end
    end
end)

-- 2. In-Game Battle Automation Worker Loop
task.spawn(function()
    while getgenv().STRIX_HUB_LOADED do
        pcall(function()
            -- Continuous Settings Sync
            Strix.Battle.SyncSettings()

            -- Runtime Battle Invocations
            if Config.AutoVoteStart then
                Strix.Battle.HandleRuntimeVoteStart()
            end
            if Config.AutoAutoplay then
                Strix.Battle.HandleRuntimeAutoplay()
            end

            -- Auto Ultimate / Skill
            if Config.AutoUltimateSkill then
                Strix.Battle.HandleAutoUltimateSkill()
            end

            -- Auto Defend (Money Units only)
            if Config.AutoDefendMoneyUnits then
                Strix.Battle.HandleAutoDefendMoneyUnits()
            end

            -- Auto Leave When Challenge Reset (xx:00 & xx:30)
            if Config.AutoLeaveOnChallengeReset then
                Strix.Challenges.CheckChallengeResetLeave()
            end

            -- Auto Leave Challenge or Pending Reset Leave when match ends
            if isBattlePlace and (Config.AutoLeaveChallenge or getgenv().STRIX_PENDING_CHALLENGE_RESET_LEAVE) then
                Strix.Challenges.HandleAutoLeave()
            end
        end)
        task.wait(0.5)
    end
end)

-- 4. Progression Rewards & Codes Worker Loop
task.spawn(function()
    while getgenv().STRIX_HUB_LOADED do
        pcall(function()
            if Config.AutoRedeemCodes then
                Strix.Progression.RedeemAllCodes()
                -- Run codes periodically every 120s
                task.wait(120.0)
            end
        end)
        task.wait(5.0)
    end
end)

task.spawn(function()
    while getgenv().STRIX_HUB_LOADED do
        pcall(function()
            if Config.AutoClaimLevelRewards then
                Strix.Progression.ClaimAllLevelRewards()
            end
            if Config.AutoClaimUnitIndex then
                Strix.Progression.ClaimUnitIndex()
            end
        end)
        task.wait(15.0)
    end
end)

-- 5. Auto Shop Buy Worker Loop
task.spawn(function()
    while getgenv().STRIX_HUB_LOADED do
        if not isBattlePlace and (Config.AutoBuyGoldShop or Config.AutoBuyGemsShop) then
            pcall(function()
                Strix.Shop.PerformLobbyAutoBuy()
            end)
            task.wait(5.0)
        else
            task.wait(2.0)
        end
    end
end)

-- 6. Auto Summon Worker Loop
task.spawn(function()
    while getgenv().STRIX_HUB_LOADED do
        if not isBattlePlace and Config.AutoSummon then
            pcall(function()
                Strix.Summon.PerformSummon(Config.SummonCount)
            end)
            task.wait(tonumber(Config.SummonDelay) or 1.5)
        else
            task.wait(0.5)
        end
    end
end)

-- ==============================================================================
-- 6. MACLIB UI SETUP & BUG OVERRIDES
-- ==============================================================================
local function ApplyConfigToUI()
    isApplyingConfig = true
    local function safe(fn) pcall(fn) end

    -- Always enforce transient states to false
    Config.AutoSummon = false

    -- Batch update standard toggle controls
    local toggleConfigs = {
        { "AutoCreateStory", nil },
        { "AutoCreateMysterios", nil },
        { "AutoCreateRaids", nil },
        { "AutoCreateBoss", nil },
        { "AutoStartMatch", nil },
        { "AutoCreateChallenge", nil },
        { "AutoStartChallenge", nil },
        { "AutoLeaveChallenge", nil, true },
        { "AutoLeaveOnChallengeReset", nil, true },
        { "AutoVoteStart", nil, true },
        { "AutoRetry", nil, true },
        { "AutoNext", nil, true },
        { "AutoAutoplay", nil, true },
        { "AutoUltimateSkill", nil, true },
        { "AutoDefendMoneyUnits", nil, true },
        { "AutoRedeemCodes", nil },
        { "AutoClaimLevelRewards", nil },
        { "AutoClaimUnitIndex", nil },
        { "AutoBuyGoldShop", nil },
        { "AutoBuyGemsShop", nil },
        { "AutoSummon", nil },
        { "AcrylicBlur", function(v) if Window and Window.SetAcrylicBlurState then Window:SetAcrylicBlurState(v == true) end end },
        { "ShowUserInfo", function(v) if Window and Window.SetUserInfoState then Window:SetUserInfoState(v ~= false) end end, true },
        { "MobileToggle", function(v) if getgenv().STRIX_MOBILE_GUI then getgenv().STRIX_MOBILE_GUI.Enabled = (v ~= false) end end, true },
        { "AutoSave", nil, true }
    }

    for _, cfg in ipairs(toggleConfigs) do
        local name, setter, defaultTrue = cfg[1], cfg[2], cfg[3]
        local isEnabled
        if name == "AutoSummon" then
            isEnabled = false
        elseif defaultTrue then
            isEnabled = (Config[name] ~= false)
        else
            isEnabled = (Config[name] == true)
        end

        Config[name] = isEnabled
        if setter then safe(function() setter(isEnabled) end) end
        if UIControls[name] and UIControls[name].UpdateState then
            safe(function() UIControls[name]:UpdateState(isEnabled) end)
        end
    end
    safe(function() Strix.Battle.SyncSettings() end)

    -- Update dropdowns and inputs individually with safe pcalls
    local function safeUpdateDropdown(control, val)
        if control and control.UpdateSelection and val ~= nil then
            pcall(function()
                if type(val) == "table" then
                    local arr = {}
                    local seen = {}
                    for k, v in pairs(val) do
                        local opt = nil
                        if v == true and type(k) == "string" and k ~= "" then
                            opt = k
                        elseif type(v) == "string" and v ~= "" then
                            opt = v
                        end
                        if opt and not seen[opt] then
                            seen[opt] = true
                            table.insert(arr, opt)
                        end
                    end
                    control:UpdateSelection(arr)
                else
                    control:UpdateSelection(val)
                end
            end)
        end
    end

    -- Story
    safeUpdateDropdown(UIControls.StoryMap, Config.StoryMap)
    safeUpdateDropdown(UIControls.StoryStage, tostring(Config.StoryStage))
    safeUpdateDropdown(UIControls.StoryDifficulty, Config.StoryDifficulty)

    -- Mysterios
    safeUpdateDropdown(UIControls.MysteriosMap, Config.MysteriosMap)
    safeUpdateDropdown(UIControls.MysteriosStage, tostring(Config.MysteriosStage))
    safeUpdateDropdown(UIControls.MysteriosDifficulty, Config.MysteriosDifficulty)

    -- Raids
    safeUpdateDropdown(UIControls.RaidsMap, Config.RaidsMap)
    safeUpdateDropdown(UIControls.RaidsStage, tostring(Config.RaidsStage))
    safeUpdateDropdown(UIControls.RaidsDifficulty, Config.RaidsDifficulty)

    -- Boss Event
    safeUpdateDropdown(UIControls.BossMap, Config.BossMap)
    safeUpdateDropdown(UIControls.BossStage, tostring(Config.BossStage))
    safeUpdateDropdown(UIControls.BossDifficulty, Config.BossDifficulty)

    -- Challenges & Others
    safeUpdateDropdown(UIControls.SelectedChallengeTab, Config.SelectedChallenges or { "Weekly" })
    safeUpdateDropdown(UIControls.SummonCount, Config.SummonCount)
    safeUpdateDropdown(UIControls.SelectedGoldItems, Config.SelectedGoldItems or {})
    safeUpdateDropdown(UIControls.SelectedGemsItems, Config.SelectedGemsItems or {})

    if UIControls.SummonDelay and UIControls.SummonDelay.UpdateValue and Config.SummonDelay then
        pcall(function() UIControls.SummonDelay:UpdateValue(Config.SummonDelay) end)
    end
    if UIControls.MenuKeybind and UIControls.MenuKeybind.Bind and Config.MenuKeybind then
        pcall(function() UIControls.MenuKeybind:Bind(Config.MenuKeybind) end)
    end

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

-- Device & Window Detection
local camInit = workspace.CurrentCamera
local vpInit = camInit and camInit.ViewportSize or Vector2.new(1920, 1080)
local isMobileDevice = UserInputService.TouchEnabled or (vpInit.Y < 600)

local defaultWinWidth = isMobileDevice and 780 or (tonumber(Config.WindowWidth) or 1000)
local defaultWinHeight = isMobileDevice and 500 or (tonumber(Config.WindowHeight) or 650)

-- Load & Patch Maclib Library (Fixes Dropdown selection display & state memory)
local rawMaclibSource = game:HttpGet("https://github.com/biggaboy212/Maclib/releases/latest/download/maclib.txt")

-- Patch 1: Prevent Toggle(option, false) from clearing the active single-select value
if rawMaclibSource:find("Selected = {}\r\n\t\t\t\t\t\t\tend") then
    rawMaclibSource = rawMaclibSource:gsub("Selected = {}\r\n\t\t\t\t\t\t\tend", "if Selected[1] == optionName then Selected = {} end\r\n\t\t\t\t\t\t\tend", 1)
elseif rawMaclibSource:find("Selected = {}\n\t\t\t\t\t\t\tend") then
    rawMaclibSource = rawMaclibSource:gsub("Selected = {}\n\t\t\t\t\t\t\tend", "if Selected[1] == optionName then Selected = {} end\n\t\t\t\t\t\t\tend", 1)
end

-- Patch 2: Allow Dropdown Settings.Default to match string option values, numbers, or tables
local replDefault = "isSelected = (DropdownFunctions.Settings.Default == i or DropdownFunctions.Settings.Default == v or (type(DropdownFunctions.Settings.Default) == 'table' and DropdownFunctions.Settings.Default[1] == v)) and true or false"
rawMaclibSource = rawMaclibSource:gsub("isSelected = %(DropdownFunctions%.Settings%.Default == i%) and true or false", replDefault)

local MacLib = loadstring(rawMaclibSource)()

local Window = MacLib:Window({
    Title = "STRIX HUB",
    Subtitle = "Anime Mysterious | BY STRIXZY",
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
-- 7. MOBILE FLOATING TOGGLE BUTTON
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

    task.spawn(function()
        while getgenv().STRIX_HUB_LOADED and mobileGui and mobileGui.Parent do
            local curState = false
            if Window and Window.GetState then
                curState = Window:GetState()
            elseif MacBaseFrame then
                curState = MacBaseFrame.Visible
            end
            UpdateVisuals(curState)
            task.wait(0.3)
        end
    end)

    local function ToggleUI()
        local currentState = false
        if Window and Window.GetState then
            currentState = Window:GetState()
        elseif MacBaseFrame then
            currentState = MacBaseFrame.Visible
        end
        local newState = not currentState
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

-- Responsive Sizing Engine
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

-- Find and Hook Maclib Base Frame & Clean Exit Button
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
                -- Replace exitBtn with a fresh clone to completely detach Maclib's broken Dialog listener
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
-- 8. TABS & SECTIONS SETUP
-- ==============================================================================
local TabGroup = Window:TabGroup()

local Tabs = {
    Battle = TabGroup:Tab({ Name = "Auto Create", Image = "rbxassetid://10709782230" }),
    Challenge = TabGroup:Tab({ Name = "Challenges", Image = "rbxassetid://10734975692" }),
    Gameplay = TabGroup:Tab({ Name = "Gameplay", Image = "rbxassetid://10723345518" }),
    Progression = TabGroup:Tab({ Name = "Rewards", Image = "rbxassetid://10747363465" }),
    Shop = TabGroup:Tab({ Name = "Summon & Shop", Image = "rbxassetid://10723407389" }),
    Settings = TabGroup:Tab({ Name = "Settings", Image = "rbxassetid://10734950309" })
}

-- ------------------------------------------------------------------------------
-- TAB 1: BATTLE & MATCHMAKING
-- ------------------------------------------------------------------------------
local BattleLeft = Tabs.Battle:Section({ Side = "Left" })
local BattleRight = Tabs.Battle:Section({ Side = "Right" })

-- Left Side: Story Mode & Mysterios Mode
BattleLeft:Header({ Text = "Story Mode" })

UIControls.AutoCreateStory = BattleLeft:Toggle({
    Name = "Auto Create Story",
    Default = (Config.AutoCreateStory == true),
    Callback = function(v)
        Config.AutoCreateStory = v
        if v then
            Config.AutoCreateMysterios = false
            Config.AutoCreateRaids = false
            Config.AutoCreateBoss = false
            if UIControls.AutoCreateMysterios and UIControls.AutoCreateMysterios.UpdateState then UIControls.AutoCreateMysterios:UpdateState(false) end
            if UIControls.AutoCreateRaids and UIControls.AutoCreateRaids.UpdateState then UIControls.AutoCreateRaids:UpdateState(false) end
            if UIControls.AutoCreateBoss and UIControls.AutoCreateBoss.UpdateState then UIControls.AutoCreateBoss:UpdateState(false) end
        end
        RequestSaveConfig()
    end
}, "Toggle_AutoCreateStory")

UIControls.StoryMap = BattleLeft:Dropdown({
    Name = "Select Story Map",
    Multi = false,
    Required = true,
    Options = StoryMapOptions,
    Default = Config.StoryMap or "Namek World",
    Callback = function(chosen)
        local val = type(chosen) == "table" and chosen[1] or chosen
        if val then
            Config.StoryMap = val
            local entry = StoryDatabase[val]
            if entry then
                if tonumber(Config.StoryStage) > entry.TotalStages then
                    Config.StoryStage = tostring(entry.TotalStages)
                    if UIControls.StoryStage and UIControls.StoryStage.UpdateSelection then
                        UIControls.StoryStage:UpdateSelection(Config.StoryStage)
                    end
                end
                local ok, reason = Strix.Matchmaking.ValidateMapAndStage(entry.MapToCreate, Config.StoryStage, "Story")
                local highest = Strix.Matchmaking.GetHighestUnlockedStage(entry.MapToCreate, entry.TotalStages, "Story")
            end
            RequestSaveConfig()
        end
    end
}, "Dropdown_StoryMap")

UIControls.StoryStage = BattleLeft:Dropdown({
    Name = "Select Story Stage",
    Multi = false,
    Required = true,
    Options = StoryStageOptions,
    Default = tostring(Config.StoryStage or "1"),
    Callback = function(chosen)
        local val = type(chosen) == "table" and chosen[1] or chosen
        if val then
            Config.StoryStage = tostring(val)
            local entry = StoryDatabase[Config.StoryMap] or StoryDatabase["Namek World"]
            local ok, reason = Strix.Matchmaking.ValidateMapAndStage(entry.MapToCreate, val, "Story")
            RequestSaveConfig()
        end
    end
}, "Dropdown_StoryStage")

UIControls.StoryDifficulty = BattleLeft:Dropdown({
    Name = "Select Story Difficulty",
    Multi = false,
    Required = true,
    Options = StandardDifficultyOptions,
    Default = Config.StoryDifficulty or "Normal",
    Callback = function(chosen)
        local val = type(chosen) == "table" and chosen[1] or chosen
        if val then
            Config.StoryDifficulty = val
            RequestSaveConfig()
        end
    end
}, "Dropdown_StoryDifficulty")

BattleLeft:Button({
    Name = "Create Story",
    Callback = function()
        Strix.Matchmaking.CreateStoryMatch()
    end
}, "Btn_CreateStoryLobby")


BattleLeft:Divider()

-- Mysterios Mode
BattleLeft:Header({ Text = "Mysterios" })

UIControls.AutoCreateMysterios = BattleLeft:Toggle({
    Name = "Auto Create Mysterios",
    Default = (Config.AutoCreateMysterios == true),
    Callback = function(v)
        Config.AutoCreateMysterios = v
        if v then
            Config.AutoCreateStory = false
            Config.AutoCreateRaids = false
            Config.AutoCreateBoss = false
            if UIControls.AutoCreateStory and UIControls.AutoCreateStory.UpdateState then UIControls.AutoCreateStory:UpdateState(false) end
            if UIControls.AutoCreateRaids and UIControls.AutoCreateRaids.UpdateState then UIControls.AutoCreateRaids:UpdateState(false) end
            if UIControls.AutoCreateBoss and UIControls.AutoCreateBoss.UpdateState then UIControls.AutoCreateBoss:UpdateState(false) end
        end
        RequestSaveConfig()
    end
}, "Toggle_AutoCreateMysterios")

UIControls.MysteriosMap = BattleLeft:Dropdown({
    Name = "Select Mysterios Map",
    Multi = false,
    Required = true,
    Options = MysteriosMapOptions,
    Default = Config.MysteriosMap or "Namek World",
    Callback = function(chosen)
        local val = type(chosen) == "table" and chosen[1] or chosen
        if val then
            Config.MysteriosMap = val
            local entry = MysteriosDatabase[val]
            if entry then
                if tonumber(Config.MysteriosStage) > entry.TotalStages then
                    Config.MysteriosStage = tostring(entry.TotalStages)
                    if UIControls.MysteriosStage and UIControls.MysteriosStage.UpdateSelection then
                        UIControls.MysteriosStage:UpdateSelection(Config.MysteriosStage)
                    end
                end
                local ok, reason = Strix.Matchmaking.ValidateMapAndStage(entry.MapToCreate, Config.MysteriosStage, "Mysterios")
                local highest = Strix.Matchmaking.GetHighestUnlockedStage(entry.MapToCreate, entry.TotalStages, "Mysterios")
            end
            RequestSaveConfig()
        end
    end
}, "Dropdown_MysteriosMap")

UIControls.MysteriosStage = BattleLeft:Dropdown({
    Name = "Select Mysterios Stage",
    Multi = false,
    Required = true,
    Options = MysteriosStageOptions,
    Default = tostring(Config.MysteriosStage or "1"),
    Callback = function(chosen)
        local val = type(chosen) == "table" and chosen[1] or chosen
        if val then
            Config.MysteriosStage = tostring(val)
            local entry = MysteriosDatabase[Config.MysteriosMap] or MysteriosDatabase["Namek World"]
            local ok, reason = Strix.Matchmaking.ValidateMapAndStage(entry.MapToCreate, val, "Mysterios")
            RequestSaveConfig()
        end
    end
}, "Dropdown_MysteriosStage")

UIControls.MysteriosDifficulty = BattleLeft:Dropdown({
    Name = "Select Mysterios Difficulty",
    Multi = false,
    Required = true,
    Options = StandardDifficultyOptions,
    Default = Config.MysteriosDifficulty or "Normal",
    Callback = function(chosen)
        local val = type(chosen) == "table" and chosen[1] or chosen
        if val then
            Config.MysteriosDifficulty = val
            RequestSaveConfig()
        end
    end
}, "Dropdown_MysteriosDifficulty")

BattleLeft:Button({
    Name = "Create Mysterios",
    Callback = function()
        Strix.Matchmaking.CreateMysteriosMatch()
    end
}, "Btn_CreateMysteriosLobby")


-- Right Side: Raids Mode, Boss Event, and In-Game Automation
BattleRight:Header({ Text = "Raids Mode" })

UIControls.AutoCreateRaids = BattleRight:Toggle({
    Name = "Auto Create Raids",
    Default = (Config.AutoCreateRaids == true),
    Callback = function(v)
        Config.AutoCreateRaids = v
        if v then
            Config.AutoCreateStory = false
            Config.AutoCreateMysterios = false
            Config.AutoCreateBoss = false
            if UIControls.AutoCreateStory and UIControls.AutoCreateStory.UpdateState then UIControls.AutoCreateStory:UpdateState(false) end
            if UIControls.AutoCreateMysterios and UIControls.AutoCreateMysterios.UpdateState then UIControls.AutoCreateMysterios:UpdateState(false) end
            if UIControls.AutoCreateBoss and UIControls.AutoCreateBoss.UpdateState then UIControls.AutoCreateBoss:UpdateState(false) end
        end
        RequestSaveConfig()
    end
}, "Toggle_AutoCreateRaids")

UIControls.RaidsMap = BattleRight:Dropdown({
    Name = "Select Raids Map",
    Multi = false,
    Required = true,
    Options = RaidsMapOptions,
    Default = Config.RaidsMap or "Alabasta Arc",
    Callback = function(chosen)
        local val = type(chosen) == "table" and chosen[1] or chosen
        if val then
            Config.RaidsMap = val
            local entry = RaidsDatabase[val]
            if entry then
                if tonumber(Config.RaidsStage) > entry.TotalStages then
                    Config.RaidsStage = tostring(entry.TotalStages)
                    if UIControls.RaidsStage and UIControls.RaidsStage.UpdateSelection then
                        UIControls.RaidsStage:UpdateSelection(Config.RaidsStage)
                    end
                end
                local ok, reason = Strix.Matchmaking.ValidateMapAndStage(entry.MapToCreate, Config.RaidsStage, "Raids")
                local highest = Strix.Matchmaking.GetHighestUnlockedStage(entry.MapToCreate, entry.TotalStages, "Raids")
            end
            RequestSaveConfig()
        end
    end
}, "Dropdown_RaidsMap")

UIControls.RaidsStage = BattleRight:Dropdown({
    Name = "Select Raids Stage",
    Multi = false,
    Required = true,
    Options = RaidsStageOptions,
    Default = tostring(Config.RaidsStage or "1"),
    Callback = function(chosen)
        local val = type(chosen) == "table" and chosen[1] or chosen
        if val then
            Config.RaidsStage = tostring(val)
            local entry = RaidsDatabase[Config.RaidsMap] or RaidsDatabase["Alabasta Arc"]
            local ok, reason = Strix.Matchmaking.ValidateMapAndStage(entry.MapToCreate, val, "Raids")
            RequestSaveConfig()
        end
    end
}, "Dropdown_RaidsStage")

UIControls.RaidsDifficulty = BattleRight:Dropdown({
    Name = "Select Raids Difficulty",
    Multi = false,
    Required = true,
    Options = StandardDifficultyOptions,
    Default = Config.RaidsDifficulty or "Normal",
    Callback = function(chosen)
        local val = type(chosen) == "table" and chosen[1] or chosen
        if val then
            Config.RaidsDifficulty = val
            RequestSaveConfig()
        end
    end
}, "Dropdown_RaidsDifficulty")

BattleRight:Button({
    Name = "Create Raids",
    Callback = function()
        Strix.Matchmaking.CreateRaidsMatch()
    end
}, "Btn_CreateRaidsLobby")


BattleRight:Divider()

-- Boss Event Mode
BattleRight:Header({ Text = "Boss Event" })

UIControls.AutoCreateBoss = BattleRight:Toggle({
    Name = "Auto Create Boss Event",
    Default = (Config.AutoCreateBoss == true),
    Callback = function(v)
        Config.AutoCreateBoss = v
        if v then
            Config.AutoCreateStory = false
            Config.AutoCreateMysterios = false
            Config.AutoCreateRaids = false
            if UIControls.AutoCreateStory and UIControls.AutoCreateStory.UpdateState then UIControls.AutoCreateStory:UpdateState(false) end
            if UIControls.AutoCreateMysterios and UIControls.AutoCreateMysterios.UpdateState then UIControls.AutoCreateMysterios:UpdateState(false) end
            if UIControls.AutoCreateRaids and UIControls.AutoCreateRaids.UpdateState then UIControls.AutoCreateRaids:UpdateState(false) end
        end
        RequestSaveConfig()
    end
}, "Toggle_AutoCreateBoss")

UIControls.BossMap = BattleRight:Dropdown({
    Name = "Select Boss Map",
    Multi = false,
    Required = true,
    Options = BossMapOptions,
    Default = Config.BossMap or "Tokyo Jujutsu High",
    Callback = function(chosen)
        local val = type(chosen) == "table" and chosen[1] or chosen
        if val then
            Config.BossMap = val
            local entry = BossDatabase[val]
            if entry then
                local ok, reason = Strix.Matchmaking.ValidateMapAndStage(entry.MapToCreate, "1", "Event")
            end
            RequestSaveConfig()
        end
    end
}, "Dropdown_BossMap")

UIControls.BossStage = BattleRight:Dropdown({
    Name = "Select Boss Stage",
    Multi = false,
    Required = true,
    Options = BossStageOptions,
    Default = tostring(Config.BossStage or "1"),
    Callback = function(chosen)
        local val = type(chosen) == "table" and chosen[1] or chosen
        if val then
            Config.BossStage = tostring(val)
            RequestSaveConfig()
        end
    end
}, "Dropdown_BossStage")

UIControls.BossDifficulty = BattleRight:Dropdown({
    Name = "Select Boss Difficulty",
    Multi = false,
    Required = true,
    Options = BossDifficultyOptions,
    Default = Config.BossDifficulty or "Normal",
    Callback = function(chosen)
        local val = type(chosen) == "table" and chosen[1] or chosen
        if val then
            Config.BossDifficulty = val
            RequestSaveConfig()
        end
    end
}, "Dropdown_BossDifficulty")

BattleRight:Button({
    Name = "Create Boss Event",
    Callback = function()
        Strix.Matchmaking.CreateBossMatch()
    end
}, "Btn_CreateBossEvent")


BattleRight:Divider()

BattleRight:Header({ Text = "Match Start" })

UIControls.AutoStartMatch = BattleRight:Toggle({
    Name = "Auto Start Match",
    Default = Config.AutoStartMatch,
    Callback = function(v)
        Config.AutoStartMatch = v
        RequestSaveConfig()
    end
}, "Toggle_AutoStartMatch")

-- ------------------------------------------------------------------------------
-- TAB 2: CHALLENGES
-- ------------------------------------------------------------------------------
local ChallengeLeft = Tabs.Challenge:Section({ Side = "Left" })
local ChallengeRight = Tabs.Challenge:Section({ Side = "Right" })

ChallengeLeft:Header({ Text = "Challenge" })

UIControls.SelectedChallengeTab = ChallengeLeft:Dropdown({
    Name = "Target Challenge",
    Multi = true,
    Required = false,
    Options = { "Weekly", "Daily", "Regular" },
    Default = Config.SelectedChallenges or { "Weekly" },
    Callback = function(chosen)
        local list = {}
        if type(chosen) == "table" then
            for k, v in pairs(chosen) do
                if v == true then
                    table.insert(list, k)
                elseif type(v) == "string" then
                    table.insert(list, v)
                end
            end
        elseif type(chosen) == "string" and chosen ~= "" then
            table.insert(list, chosen)
        end
        Config.SelectedChallenges = list
        RequestSaveConfig()
    end
}, "Dropdown_SelectedChallengeTab")

UIControls.AutoCreateChallenge = ChallengeLeft:Toggle({
    Name = "Auto Challenges",
    Default = (Config.AutoCreateChallenge == true),
    Callback = function(v)
        Config.AutoCreateChallenge = v
        RequestSaveConfig()
    end
}, "Toggle_AutoCreateChallenge")

ChallengeRight:Header({ Text = "Match Settings" })

UIControls.AutoLeaveChallenge = ChallengeRight:Toggle({
    Name = "Auto Leave Challenge",
    Default = (Config.AutoLeaveChallenge ~= false),
    Callback = function(v)
        Config.AutoLeaveChallenge = v
        RequestSaveConfig()
    end
}, "Toggle_AutoLeaveChallenge")

UIControls.AutoLeaveOnChallengeReset = ChallengeRight:Toggle({
    Name = "Auto Leave When Challenge Reset",
    Default = (Config.AutoLeaveOnChallengeReset ~= false),
    Callback = function(v)
        Config.AutoLeaveOnChallengeReset = v
        RequestSaveConfig()
    end
}, "Toggle_AutoLeaveOnChallengeReset")

-- ------------------------------------------------------------------------------
-- TAB 3: GAMEPLAY (IN-GAME AUTOMATION)
-- ------------------------------------------------------------------------------
local GameLeft = Tabs.Gameplay:Section({ Side = "Left" })

GameLeft:Header({ Text = "Gameplay Settings" })

UIControls.AutoVoteStart = GameLeft:Toggle({
    Name = "Auto Vote Start",
    Default = (Config.AutoVoteStart ~= false),
    Callback = function(v)
        Config.AutoVoteStart = v
        Strix.Battle.SetGameSetting("AutoVoteStart", v)
        RequestSaveConfig()
    end
}, "Toggle_AutoVoteStart")

UIControls.AutoRetry = GameLeft:Toggle({
    Name = "Auto Replay",
    Default = (Config.AutoRetry ~= false),
    Callback = function(v)
        Config.AutoRetry = v
        Strix.Battle.SetGameSetting("AutoRetry", v)
        RequestSaveConfig()
    end
}, "Toggle_AutoRetry")

UIControls.AutoNext = GameLeft:Toggle({
    Name = "Auto Next",
    Default = (Config.AutoNext ~= false),
    Callback = function(v)
        Config.AutoNext = v
        Strix.Battle.SetGameSetting("AutoNext", v)
        RequestSaveConfig()
    end
}, "Toggle_AutoNext")

UIControls.AutoAutoplay = GameLeft:Toggle({
    Name = "Auto Play",
    Default = (Config.AutoAutoplay ~= false),
    Callback = function(v)
        Config.AutoAutoplay = v
        Strix.Battle.SetGameSetting("Autoplay", v)
        RequestSaveConfig()
    end
}, "Toggle_AutoAutoplay")

UIControls.AutoUltimateSkill = GameLeft:Toggle({
    Name = "Auto Ultimate / Skill",
    Default = (Config.AutoUltimateSkill ~= false),
    Callback = function(v)
        Config.AutoUltimateSkill = v
        RequestSaveConfig()
    end
}, "Toggle_AutoUltimateSkill")

UIControls.AutoDefendMoneyUnits = GameLeft:Toggle({
    Name = "Auto Defend (Money Units)",
    Default = (Config.AutoDefendMoneyUnits ~= false),
    Callback = function(v)
        Config.AutoDefendMoneyUnits = v
        RequestSaveConfig()
    end
}, "Toggle_AutoDefendMoneyUnits")

-- ------------------------------------------------------------------------------
-- TAB 4: REWARDS & CODES
-- ------------------------------------------------------------------------------
local ProgLeft = Tabs.Progression:Section({ Side = "Left" })
local ProgRight = Tabs.Progression:Section({ Side = "Right" })

ProgLeft:Header({ Text = "Code Redemption" })

UIControls.AutoRedeemCodes = ProgLeft:Toggle({
    Name = "Auto Redeem Active Codes",
    Default = Config.AutoRedeemCodes,
    Callback = function(v)
        Config.AutoRedeemCodes = v
        RequestSaveConfig()
    end
}, "Toggle_AutoRedeemCodes")

ProgLeft:Button({
    Name = "Redeem All Active Codes Now",
    Callback = function()
        task.spawn(function()
            Strix.Progression.RedeemAllCodes()
        end)
    end
}, "Btn_RedeemAllCodes")


ProgRight:Header({ Text = "Level & Unit Index Rewards" })

UIControls.AutoClaimLevelRewards = ProgRight:Toggle({
    Name = "Auto Claim Level Rewards",
    Default = Config.AutoClaimLevelRewards,
    Callback = function(v)
        Config.AutoClaimLevelRewards = v
        RequestSaveConfig()
    end
}, "Toggle_AutoClaimLevelRewards")

ProgRight:Button({
    Name = "Claim All Level Rewards Now",
    Callback = function()
        task.spawn(function()
            Strix.Progression.ClaimAllLevelRewards()
        end)
    end
}, "Btn_ClaimLevelRewards")

ProgRight:Divider()

UIControls.AutoClaimUnitIndex = ProgRight:Toggle({
    Name = "Auto Claim Unit Index Rewards",
    Default = Config.AutoClaimUnitIndex,
    Callback = function(v)
        Config.AutoClaimUnitIndex = v
        RequestSaveConfig()
    end
}, "Toggle_AutoClaimUnitIndex")

ProgRight:Button({
    Name = "Claim All Unit Index Rewards Now",
    Callback = function()
        task.spawn(function()
            Strix.Progression.ClaimUnitIndex()
        end)
    end
}, "Btn_ClaimUnitIndex")

-- ------------------------------------------------------------------------------
-- TAB 5: SUMMON & SHOP
-- ------------------------------------------------------------------------------
local ShopLeft = Tabs.Shop:Section({ Side = "Left" })
local ShopRight = Tabs.Shop:Section({ Side = "Right" })

ShopLeft:Header({ Text = "Auto Summon Engine" })

UIControls.AutoSummon = ShopLeft:Toggle({
    Name = "Auto Summon",
    Default = false,
    Callback = function(v)
        Config.AutoSummon = v
    end
}, "Toggle_AutoSummon")

UIControls.SummonCount = ShopLeft:Dropdown({
    Name = "Summon Amount",
    Multi = false,
    Required = true,
    Options = { "1x", "10x" },
    Default = Config.SummonCount or "10x",
    Callback = function(chosen)
        local val = type(chosen) == "table" and chosen[1] or chosen
        if val then
            Config.SummonCount = val
            RequestSaveConfig()
        end
    end
}, "Dropdown_SummonCount")

UIControls.SummonDelay = ShopLeft:Slider({
    Name = "Summon Interval Delay",
    Minimum = 0.5,
    Maximum = 5.0,
    Default = Config.SummonDelay or 1.5,
    Precision = 1,
    Suffix = "s",
    Callback = function(v)
        Config.SummonDelay = v
        RequestSaveConfig()
    end
}, "Slider_SummonDelay")


ShopLeft:Button({
    Name = "Perform 10x Summon Once",
    Callback = function()
        Strix.Summon.PerformSummon("10x")
    end
}, "Btn_SummonOnce")

-- Shop Right: Gold & Gems Shop
ShopRight:Header({ Text = "Gold Shop Automation" })

local function normalizeItemList(tbl)
    local list = {}
    local seen = {}
    if type(tbl) == "table" then
        for k, v in pairs(tbl) do
            local item = nil
            if v == true and type(k) == "string" and k ~= "" then
                item = k
            elseif type(v) == "string" and v ~= "" then
                item = v
            end
            if item and not seen[item] then
                seen[item] = true
                table.insert(list, item)
            end
        end
    elseif type(tbl) == "string" and tbl ~= "" then
        table.insert(list, tbl)
    end
    return list
end

UIControls.AutoBuyGoldShop = ShopRight:Toggle({
    Name = "Auto Buy Gold Shop",
    Default = (Config.AutoBuyGoldShop == true),
    Callback = function(v)
        Config.AutoBuyGoldShop = (v == true)
        RequestSaveConfig(true)
    end
}, "Toggle_AutoBuyGoldShop")

local ShopItemOptions = {}
for _, item in ipairs(ShopItemList) do
    table.insert(ShopItemOptions, item)
end

UIControls.SelectedGoldItems = ShopRight:Dropdown({
    Name = "Select Gold Items",
    Multi = true,
    Required = false,
    Options = ShopItemOptions,
    Default = normalizeItemList(Config.SelectedGoldItems),
    Callback = function(chosen)
        Config.SelectedGoldItems = normalizeItemList(chosen)
        RequestSaveConfig(true)
    end
}, "Dropdown_SelectedGoldItems")

ShopRight:Button({
    Name = "Buy Selected Gold Item(s) Now",
    Callback = function()
        task.spawn(function()
            if Config.SelectedGoldItems and #Config.SelectedGoldItems > 0 then
                Strix.Shop.BuyBatch(Config.SelectedGoldItems, "Coins")
            end
        end)
    end
}, "Btn_BuyGoldItem")

ShopRight:Divider()
ShopRight:Header({ Text = "Gems Shop Automation" })

UIControls.AutoBuyGemsShop = ShopRight:Toggle({
    Name = "Auto Buy Gems Shop",
    Default = (Config.AutoBuyGemsShop == true),
    Callback = function(v)
        Config.AutoBuyGemsShop = (v == true)
        RequestSaveConfig(true)
    end
}, "Toggle_AutoBuyGemsShop")

UIControls.SelectedGemsItems = ShopRight:Dropdown({
    Name = "Select Gems Items",
    Multi = true,
    Required = false,
    Options = ShopItemOptions,
    Default = normalizeItemList(Config.SelectedGemsItems),
    Callback = function(chosen)
        Config.SelectedGemsItems = normalizeItemList(chosen)
        RequestSaveConfig(true)
    end
}, "Dropdown_SelectedGemsItems")

ShopRight:Button({
    Name = "Buy Selected Gems Item(s) Now",
    Callback = function()
        task.spawn(function()
            if Config.SelectedGemsItems and #Config.SelectedGemsItems > 0 then
                Strix.Shop.BuyBatch(Config.SelectedGemsItems, "Gems")
            end
        end)
    end
}, "Btn_BuyGemsItem")

-- ------------------------------------------------------------------------------
-- TAB 6: SETTINGS
-- ------------------------------------------------------------------------------
local SetLeft = Tabs.Settings:Section({ Side = "Left" })
local SetRight = Tabs.Settings:Section({ Side = "Right" })

SetLeft:Header({ Text = "Interface Controls" })

UIControls.AcrylicBlur = SetLeft:Toggle({
    Name = "Acrylic Blur Background",
    Default = Config.AcrylicBlur,
    Callback = function(v)
        Config.AcrylicBlur = v
        if Window and Window.SetAcrylicBlurState then
            Window:SetAcrylicBlurState(v)
        end
        RequestSaveConfig()
    end
}, "Toggle_AcrylicBlur")

UIControls.ShowUserInfo = SetLeft:Toggle({
    Name = "Show User Information",
    Default = (Config.ShowUserInfo ~= false),
    Callback = function(v)
        Config.ShowUserInfo = v
        if Window and Window.SetUserInfoState then
            Window:SetUserInfoState(v)
        end
        RequestSaveConfig()
    end
}, "Toggle_ShowUserInfo")

UIControls.MobileToggle = SetLeft:Toggle({
    Name = "Mobile Floating Button",
    Default = (Config.MobileToggle ~= false),
    Callback = function(v)
        Config.MobileToggle = v
        if getgenv().STRIX_MOBILE_GUI then
            getgenv().STRIX_MOBILE_GUI.Enabled = v
        end
        RequestSaveConfig()
    end
}, "Toggle_MobileToggle")

UIControls.MenuKeybind = SetLeft:Keybind({
    Name = "Open / Close Keybind",
    Default = Config.MenuKeybind or Enum.KeyCode.RightControl,
    Callback = function(key)
        Config.MenuKeybind = key
        if Window and Window.SetKeybind then
            Window:SetKeybind(key)
        end
        RequestSaveConfig()
    end
}, "Keybind_MenuKeybind")

SetRight:Header({ Text = "Window Sizing" })

SliderWinWidth = SetRight:Slider({
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

SliderWinHeight = SetRight:Slider({
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

SetRight:Button({
    Name = "Fit Screen (Mobile Responsive)",
    Callback = function()
        if MacBaseFrame and ApplyResponsiveWindow then
            ApplyResponsiveWindow(MacBaseFrame)
        end
    end
}, "Btn_FitMobileScreen")

SetRight:Button({
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

SetRight:Button({
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

SetLeft:Divider()
SetLeft:Header({ Text = "Configuration Storage" })

UIControls.AutoSave = SetLeft:Toggle({
    Name = "Auto Save Changes",
    Default = (Config.AutoSave ~= false),
    Callback = function(v)
        Config.AutoSave = v
    end
}, "Toggle_AutoSave")

SetLeft:Button({
    Name = "Save Config Now",
    Callback = function()
        SaveConfig(false)
    end
}, "Btn_SaveConfig")

SetLeft:Button({
    Name = "Reload Config From File",
    Callback = function()
        LoadConfig()
        ApplyConfigToUI()
    end
}, "Btn_ReloadConfig")

SetRight:Divider()
SetRight:Header({ Text = "Hub Management" })

SetRight:Button({
    Name = "Unload STRIX HUB",
    Callback = function()
        Strix.Engine.Cleanup()
        if Window and Window.Unload then
            Window:Unload()
        end
    end
}, "Btn_UnloadHub")

-- ==============================================================================
-- 9. INITIALIZE & APPLY CONFIG TO UI
-- ==============================================================================
ApplyConfigToUI()
task.spawn(function()
    task.wait(0.15)
    pcall(function()
        if isBattlePlace and Tabs.Gameplay then
            Tabs.Gameplay:Select()
        else
            Tabs.Battle:Select()
        end
    end)
end)

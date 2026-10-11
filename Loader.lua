-- ==============================================================================
--  STRIX HUB - Universal Multi-Game Loader
-- ==============================================================================

-- ==============================================================================
-- 0. Auto-Execute & Game Load Verification (แก้ปัญหา Auto Execute ไม่ติด)
-- ==============================================================================
if not game:IsLoaded() then
    repeat task.wait(0.2) until game:IsLoaded()
end

-- รอจนกว่า PlaceId จะถูกเซ็ตจริง (ตอน Auto Execute ช่วงแรก game.PlaceId จะเป็น 0)
while not game.PlaceId or game.PlaceId == 0 do
    task.wait(0.2)
end

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
while not LocalPlayer do
    task.wait(0.2)
    LocalPlayer = Players.LocalPlayer
end

if not LocalPlayer:FindFirstChild("PlayerGui") then
    LocalPlayer:WaitForChild("PlayerGui", 20)
end

-- ==============================================================================
-- 1. Notification Helper
-- ==============================================================================
local StarterGui = game:GetService("StarterGui")
local function Notify(title, text, duration)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = title or "STRIX HUB",
            Text = text or "",
            Duration = duration or 5
        })
    end)
end

-- ==============================================================================
-- 2. Repository Configuration
-- ==============================================================================
local GITHUB_USER   = "Mxvxrixx"
local GITHUB_REPO   = "STRIX-HUB"
local GITHUB_BRANCH = "main"

local BASE_URL = string.format(
    "https://raw.githubusercontent.com/%s/%s/%s/",
    GITHUB_USER,
    GITHUB_REPO,
    GITHUB_BRANCH
)

-- ==============================================================================
-- 3. Game Database (จับคู่ตาม PlaceId)
-- ==============================================================================
local Games = {
    ["Anime Dice"] = {
        ScriptPath = "Games/Anime-Dice.lua",
        PlaceIds   = { 113290951185459 },
    },

    ["Anime Mysterious"] = {
        ScriptPath = "Games/Anime-Mysterious.lua",
        PlaceIds   = {
            117949143041402, -- Lobby
            107610426295102, -- Gameplay
            110388679506690, -- Lobby Alt
        },
    },
}

-- ==============================================================================
-- 4. Game Detection Logic
-- ==============================================================================
local currentPlaceId = game.PlaceId

local matchedGameName = nil
local targetScriptPath = nil

for name, data in pairs(Games) do
    if data.PlaceIds then
        for _, id in ipairs(data.PlaceIds) do
            if id == currentPlaceId then
                matchedGameName = name
                targetScriptPath = data.ScriptPath
                break
            end
        end
    end

    if matchedGameName then
        break
    end
end

-- ==============================================================================
-- 5. Execution
-- ==============================================================================
if matchedGameName and targetScriptPath then
    Notify("STRIX HUB", "กำลังโหลดสคริปต์: " .. matchedGameName .. "...", 3)

    -- ใส่ ?t= เพื่อป้องกัน Executor แคชสคริปต์เก่า
    local scriptUrl = BASE_URL .. targetScriptPath .. "?t=" .. tick()
    print("[STRIX HUB] Fetching: " .. scriptUrl)

    local success, scriptContent = false, nil
    for attempt = 1, 3 do
        success, scriptContent = pcall(function()
            return game:HttpGet(scriptUrl)
        end)
        if success and scriptContent and #scriptContent > 0 then
            break
        end
        task.wait(0.5)
    end

    if success and scriptContent and #scriptContent > 0 then
        local runSuccess, runError = pcall(function()
            local loadedFunction, compileError = loadstring(scriptContent)
            if not loadedFunction then
                error("Compile Error: " .. tostring(compileError))
            end
            loadedFunction()
        end)

        if not runSuccess then
            warn("[STRIX HUB] Runtime Error: " .. tostring(runError))
            Notify("STRIX HUB Error", "เกิดข้อผิดพลาดขณะรันสคริปต์ ตรวจสอบ F9 Console", 6)
        end
    else
        warn("[STRIX HUB] Failed to download script from: " .. scriptUrl)
        Notify("STRIX HUB Error", "ไม่สามารถดาวน์โหลดสคริปต์ได้ ตรวจสอบ URL หรืออินเทอร์เน็ต", 6)
    end
else
    local notSupportedMsg = string.format("ไม่รองรับเกมนี้ (PlaceId: %d)", currentPlaceId)
    warn("[STRIX HUB] " .. notSupportedMsg)
    Notify("STRIX HUB", notSupportedMsg, 6)
end

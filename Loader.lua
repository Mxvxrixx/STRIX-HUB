-- ==============================================================================
--  STRIX HUB - Universal Multi-Game Loader
-- ==============================================================================
task.wait(5) 
-- 1. Wait for game to fully load
if not game:IsLoaded() then
    game.Loaded:Wait()
end

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
    "https://raw.githubusercontent.com/%s/%s/refs/heads/%s/",
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
        PlaceIds   = { 117949143041402 },
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

    local scriptUrl = BASE_URL .. targetScriptPath
    print("[STRIX HUB] Fetching: " .. scriptUrl)

    local success, scriptContent = pcall(function()
        return game:HttpGet(scriptUrl)
    end)

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
    -- กรณีเกมยังไม่รองรับ
    local notSupportedMsg = string.format("ไม่รองรับเกมนี้ (PlaceId: %d)", currentPlaceId)
    warn("[STRIX HUB] " .. notSupportedMsg)
    Notify("STRIX HUB", notSupportedMsg, 6)
end

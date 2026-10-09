-- STRIX HUB Universal Loader
local PlaceId = game.PlaceId
local GameId = game.GameId

local BaseURL = "https://raw.githubusercontent.com/<ชื่อผู้ใช้>/<ชื่อRepo>/refs/heads/main/Games/"

-- รายการเกมที่รองรับ (ใส่ PlaceId หรือ GameId)
local SupportedGames = {
    -- [PlaceId หรือ GameId] = "ชื่อไฟล์สคริปต์",
    
    -- ตัวอย่างเกม Anime Dice
    [1234567890] = "Anime-Dice.lua",
    
    -- ตัวอย่างเกม Anime Mysterious
    [9876543210] = "Anime-Mysterious.lua",
}

-- ค้นหาว่าตรงกับ PlaceId หรือ GameId ไหน
local scriptFile = SupportedGames[PlaceId] or SupportedGames[GameId]

if scriptFile then
    local fullUrl = BaseURL .. scriptFile
    loadstring(game:HttpGet(fullUrl))()
else
    -- แจ้งเตือนเมื่อไม่รองรับเกมนี้
    local msg = "STRIX HUB: ไม่รองรับเกมนี้ (PlaceId: " .. tostring(PlaceId) .. " | GameId: " .. tostring(GameId) .. ")"
    warn(msg)
    
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", {
            Title = "STRIX HUB",
            Text = "เกมนี้ยังไม่เปิดให้บริการ!",
            Duration = 5
        })
    end)
end

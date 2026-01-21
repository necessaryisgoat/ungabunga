-- UngaBunga.lua (Retail 12.0.0 / 120000)
-- Minimal bouncing "unga bunga" text that appears at random intervals.
-- Includes Blizzard Settings panel integration (Esc -> Options -> AddOns).

local ADDON_NAME = ...

-- -----------------------------
-- Saved Variables + Defaults
-- -----------------------------
UngaBungaDB = UngaBungaDB or {}

local DEFAULTS = {
    enabled = true,
    text = "unga bunga",
    durationSeconds = 120,       -- ~2 minutes
    meanIntervalSeconds = 720,   -- average ~12 minutes between spawns (~5/hour)
    speedPixelsPerSec = 70,      -- slow drift speed
    fontSize = 12,               -- fairly small
    clampIntervals = true,       -- keep spawns within a sane range
    clampMinSeconds = 120,       -- 2 min
    clampMaxSeconds = 1800,      -- 30 min
}

local function ApplyDefaults()
    for k, v in pairs(DEFAULTS) do
        if UngaBungaDB[k] == nil then
            UngaBungaDB[k] = v
        end
    end
end

-- -----------------------------
-- Main Frame
-- -----------------------------
local UB = CreateFrame("Frame", "UngaBungaFrame", UIParent)
UB:Hide()

UB.active = false
UB.vx, UB.vy = 0, 0
UB.x, UB.y = 0, 0
UB.endTime = 0
UB.nextTimer = nil
UB.category = nil

UB:SetFrameStrata("HIGH")
UB:SetClampedToScreen(true)

-- Create the text
local fs = UB:CreateFontString(nil, "OVERLAY")
fs:SetJustifyH("CENTER")
fs:SetJustifyV("MIDDLE")
fs:SetPoint("CENTER", UB, "CENTER", 0, 0)

local function UpdateTextAppearance()
    local fontSize = UngaBungaDB.fontSize or DEFAULTS.fontSize
    local text = UngaBungaDB.text or DEFAULTS.text

    -- IMPORTANT: SetFont must happen BEFORE SetText
    local fontPath = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
    fs:SetFont(fontPath, fontSize, "OUTLINE")
    fs:SetText(text)

    local w = fs:GetStringWidth()
    local h = fs:GetStringHeight()
    UB:SetSize(math.max(1, w + 6), math.max(1, h + 6))
end


-- -----------------------------
-- Random Helpers
-- -----------------------------

-- Exponential distribution (Poisson process):
-- interval = -ln(U) * mean
local function RandomExponential(meanSeconds)
    local u = math.random()
    if u < 0.000001 then u = 0.000001 end -- avoid ln(0)
    return -math.log(u) * meanSeconds
end

local function GetScreenBounds()
    local sw = UIParent:GetWidth() or 0
    local sh = UIParent:GetHeight() or 0
    local fw = UB:GetWidth() or 1
    local fh = UB:GetHeight() or 1
    return sw, sh, fw, fh
end

local function PlaceRandomlyOnScreen()
    local sw, sh, fw, fh = GetScreenBounds()
    if sw <= 0 or sh <= 0 then
        UB.x, UB.y = 200, 200
        return
    end

    UB.x = math.random() * math.max(1, (sw - fw))
    UB.y = math.random() * math.max(1, (sh - fh))
end

local function SetRandomVelocity()
    local speed = UngaBungaDB.speedPixelsPerSec or DEFAULTS.speedPixelsPerSec
    local angle = math.random() * (2 * math.pi)
    UB.vx = math.cos(angle) * speed
    UB.vy = math.sin(angle) * speed
end

-- -----------------------------
-- Scheduling
-- -----------------------------
local function CancelNextSpawnTimer()
    if UB.nextTimer and UB.nextTimer.Cancel then
        UB.nextTimer:Cancel()
    end
    UB.nextTimer = nil
end

local function ScheduleNextSpawn()
    CancelNextSpawnTimer()

    if not UngaBungaDB.enabled then
        return
    end

    local mean = UngaBungaDB.meanIntervalSeconds or DEFAULTS.meanIntervalSeconds
    local interval = RandomExponential(mean)

    if UngaBungaDB.clampIntervals then
        local minS = UngaBungaDB.clampMinSeconds or DEFAULTS.clampMinSeconds
        local maxS = UngaBungaDB.clampMaxSeconds or DEFAULTS.clampMaxSeconds
        interval = math.max(minS, math.min(interval, maxS))
    end

    UB.nextTimer = C_Timer.NewTimer(interval, function()
        -- Only spawn if not already active and still enabled
        if UngaBungaDB.enabled and not UB.active then
            UB:Start()
        else
            -- Try again later if something prevented spawning
            ScheduleNextSpawn()
        end
    end)
end

-- -----------------------------
-- Motion / Bounce
-- -----------------------------
function UB:Stop()
    UB.active = false
    UB:Hide()
    UB:SetScript("OnUpdate", nil)

    -- After finishing, schedule next random event
    ScheduleNextSpawn()
end

function UB:Start()
    if not UngaBungaDB.enabled then return end
    if UB.active then return end

    UB.active = true

    UpdateTextAppearance()
    PlaceRandomlyOnScreen()
    SetRandomVelocity()

    UB:ClearAllPoints()
    UB:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", UB.x, UB.y)
    UB:Show()

    local duration = UngaBungaDB.durationSeconds or DEFAULTS.durationSeconds
    UB.endTime = GetTime() + duration

    UB:SetScript("OnUpdate", function(_, elapsed)
        if GetTime() >= UB.endTime then
            UB:Stop()
            return
        end

        local sw, sh, fw, fh = GetScreenBounds()

        UB.x = UB.x + UB.vx * elapsed
        UB.y = UB.y + UB.vy * elapsed

        -- Bounce off edges
        if UB.x <= 0 then
            UB.x = 0
            UB.vx = -UB.vx
        elseif UB.x >= (sw - fw) then
            UB.x = math.max(0, sw - fw)
            UB.vx = -UB.vx
        end

        if UB.y <= 0 then
            UB.y = 0
            UB.vy = -UB.vy
        elseif UB.y >= (sh - fh) then
            UB.y = math.max(0, sh - fh)
            UB.vy = -UB.vy
        end

        UB:ClearAllPoints()
        UB:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", UB.x, UB.y)
    end)
end

-- -----------------------------
-- Settings Panel (Built-in UI)
-- -----------------------------
local function CreateCheckbox(parent, label, tooltip)
    local cb = CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate")
    cb.Text:SetText(label)
    if tooltip then
        cb.tooltipText = tooltip
    end
    return cb
end

local function CreateSlider(parent, label, minV, maxV, step, tooltip)
    local slider = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
    slider:SetMinMaxValues(minV, maxV)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)

    slider.Text:SetText(label)
    slider.Low:SetText(tostring(minV))
    slider.High:SetText(tostring(maxV))

    if tooltip then
        slider.tooltipText = tooltip
    end

    return slider
end

local function SetupOptionsPanel()
    local panel = CreateFrame("Frame")
    panel.name = "UngaBunga"

    -- Title
    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("UngaBunga")

    local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    subtitle:SetText("Random bouncing \"unga bunga\" text. Minimal. Silly. Perfect.")

    -- Enable checkbox
    local enabledCB = CreateCheckbox(panel, "Enable", "Toggles whether the text can appear at all.")
    enabledCB:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -12)

    -- Font size slider
    local fontSlider = CreateSlider(panel, "Font size", 8, 24, 1, "How small/large the text is.")
    fontSlider:SetPoint("TOPLEFT", enabledCB, "BOTTOMLEFT", 0, -24)
    fontSlider:SetWidth(260)

    -- Speed slider
    local speedSlider = CreateSlider(panel, "Speed (px/sec)", 20, 200, 5, "How fast the text moves across the screen.")
    speedSlider:SetPoint("TOPLEFT", fontSlider, "BOTTOMLEFT", 0, -42)
    speedSlider:SetWidth(260)

    -- Duration slider
    local durationSlider = CreateSlider(panel, "Duration (seconds)", 30, 300, 5, "How long each appearance lasts.")
    durationSlider:SetPoint("TOPLEFT", speedSlider, "BOTTOMLEFT", 0, -42)
    durationSlider:SetWidth(260)

    -- Mean interval slider (minutes)
    local intervalSlider = CreateSlider(panel, "Average interval (minutes)", 3, 30, 1,
        "Average time between spawns. Actual timing is random, not fixed.")
    intervalSlider:SetPoint("TOPLEFT", durationSlider, "BOTTOMLEFT", 0, -42)
    intervalSlider:SetWidth(260)

    -- Clamp checkbox
    local clampCB = CreateCheckbox(panel, "Clamp intervals (recommended)",
        "Keeps randomness, but prevents extremely short/long gaps.")
    clampCB:SetPoint("TOPLEFT", intervalSlider, "BOTTOMLEFT", 0, -22)

    -- Test button
    local testBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    testBtn:SetSize(120, 22)
    testBtn:SetPoint("TOPLEFT", clampCB, "BOTTOMLEFT", 0, -16)
    testBtn:SetText("Test spawn")

    local stopBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    stopBtn:SetSize(120, 22)
    stopBtn:SetPoint("LEFT", testBtn, "RIGHT", 10, 0)
    stopBtn:SetText("Stop now")

    -- Helper label showing current computed mean
    local info = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    info:SetPoint("TOPLEFT", testBtn, "BOTTOMLEFT", 0, -10)
    info:SetText("")

    local function RefreshControls()
        enabledCB:SetChecked(UngaBungaDB.enabled)

        fontSlider:SetValue(UngaBungaDB.fontSize)
        speedSlider:SetValue(UngaBungaDB.speedPixelsPerSec)
        durationSlider:SetValue(UngaBungaDB.durationSeconds)
        intervalSlider:SetValue(math.floor((UngaBungaDB.meanIntervalSeconds or 60) / 60))

        clampCB:SetChecked(UngaBungaDB.clampIntervals)

        local mins = (UngaBungaDB.meanIntervalSeconds or DEFAULTS.meanIntervalSeconds) / 60
        local perHour = 60 / mins
        info:SetText(string.format("Roughly %.1f spawns/hour on average (still random).", perHour))
    end

    enabledCB:SetScript("OnClick", function(self)
        UngaBungaDB.enabled = self:GetChecked() and true or false

        if not UngaBungaDB.enabled then
            CancelNextSpawnTimer()
            if UB.active then UB:Stop() end
        else
            ScheduleNextSpawn()
        end
    end)

    fontSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value + 0.5)
        UngaBungaDB.fontSize = value
        UpdateTextAppearance()
    end)

    speedSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value + 0.5)
        UngaBungaDB.speedPixelsPerSec = value
    end)

    durationSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value + 0.5)
        UngaBungaDB.durationSeconds = value
    end)

    intervalSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value + 0.5)
        UngaBungaDB.meanIntervalSeconds = value * 60
        RefreshControls()
        ScheduleNextSpawn()
    end)

    clampCB:SetScript("OnClick", function(self)
        UngaBungaDB.clampIntervals = self:GetChecked() and true or false
        ScheduleNextSpawn()
    end)

    testBtn:SetScript("OnClick", function()
        -- Spawn immediately (still respects enabled)
        if UngaBungaDB.enabled then
            UB:Start()
        end
    end)

    stopBtn:SetScript("OnClick", function()
        if UB.active then
            UB:Stop()
        end
    end)

    panel:SetScript("OnShow", function()
        RefreshControls()
    end)

    -- Register into modern Settings UI
    local category = Settings.RegisterCanvasLayoutCategory(panel, "UngaBunga")
    Settings.RegisterAddOnCategory(category)

    UB.category = category
    UB.categoryID = category:GetID()  -- numeric ID for Settings.OpenToCategory

end

-- -----------------------------
-- Slash Commands
-- -----------------------------
SLASH_UNGABUNGA1 = "/ungabunga"
SLASH_UNGABUNGA2 = "/ub"

SlashCmdList["UNGABUNGA"] = function(msg)
    msg = (msg or ""):lower()

    if msg == "test" then
        UB:Start()
        return
    end

    if msg == "toggle" then
        UngaBungaDB.enabled = not UngaBungaDB.enabled
        if not UngaBungaDB.enabled then
            CancelNextSpawnTimer()
            if UB.active then UB:Stop() end
            print("|cff00ff00UngaBunga:|r Disabled")
        else
            ScheduleNextSpawn()
            print("|cff00ff00UngaBunga:|r Enabled")
        end
        return
    end

    -- Open settings category
    if UB.categoryID and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(UB.categoryID)
    else
        print("|cff00ff00UngaBunga:|r Settings not ready yet.")
    end
end

-- -----------------------------
-- Boot
-- -----------------------------
UB:RegisterEvent("PLAYER_LOGIN")
UB:SetScript("OnEvent", function()
    ApplyDefaults()
    UpdateTextAppearance()
    SetupOptionsPanel()

    -- WoW does not allow math.randomseed() – RNG is already seeded by the client.
    -- Burn a few values (harmless).
    math.random(); math.random(); math.random()

    ScheduleNextSpawn()
end)

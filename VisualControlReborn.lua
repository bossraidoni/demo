--!nocheck
--[[
    VISUAL CONTROL REBORN
    Premium client-side visual, atmosphere, weather, camera, and personal-audio suite.

    Version: 4.0.0
    Environment: Roblox client / executor-injected LocalScript
    Keybind: = (configurable) toggles the application.
    Search: Ctrl+K while the application is visible.

    This file is a complete, self-contained distribution artifact. It does not
    require ModuleScripts, remote code, external packages, or game-owned objects.

    Design principles:
      * Never modify gameplay, hitboxes, movement, combat, replication, or other players.
      * Never modify game-owned sounds, SoundGroups, or global SoundService effects.
      * Snapshot and restore every environment property Visual Control touches.
      * Keep environmental raycasts throttled, bounded, and quality-controlled.
      * Treat all visual systems as supported Roblox approximations, not GPU shaders.
]]

--============================================================
-- 01 / SERVICES AND ENVIRONMENT
--============================================================

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")

if not RunService:IsClient() then
    return
end

local Player = Players.LocalPlayer
if not Player then
    return
end

local PlayerGui = Player:WaitForChild("PlayerGui", 20)
if not PlayerGui then
    return
end

local APP_NAME = "Visual Control Reborn"
local VERSION = "4.0.0"
local PREFIX = "VisualControlReborn_"
local LEGACY_PREFIX = "VisualControl_"
local STEP_NAME = PREFIX .. "Engine"
local GLOBAL_KEY = PREFIX .. "Controller"
local CONFIG_FILE = "VisualControlReborn_v4.json"

local KEYCODE_NONE = Enum.KeyCode.None
if not KEYCODE_NONE then
    pcall(function()
        KEYCODE_NONE = Enum.KeyCode["Unknown"]
    end)
end

--============================================================
-- 02 / EXECUTOR COMPATIBILITY
--============================================================

local function captureDirectGlobal(name)
    local value = nil
    if name == "getcustomasset" then
        pcall(function() value = getcustomasset end)
    elseif name == "writefile" then
        pcall(function() value = writefile end)
    elseif name == "readfile" then
        pcall(function() value = readfile end)
    elseif name == "isfile" then
        pcall(function() value = isfile end)
    elseif name == "delfile" then
        pcall(function() value = delfile end)
    elseif name == "setclipboard" then
        pcall(function() value = setclipboard end)
    end
    if type(value) == "function" then
        return value
    end
    return nil
end

local function getExecutorFunction(name)
    local direct = captureDirectGlobal(name)
    if direct then
        return direct
    end

    local ok, value = pcall(function()
        return _G[name]
    end)
    if ok and type(value) == "function" then
        return value
    end

    ok, value = pcall(function()
        local envGetter = getgenv
        if type(envGetter) == "function" then
            local env = envGetter()
            if type(env) == "table" then
                return env[name]
            end
        end
    end)
    if ok and type(value) == "function" then
        return value
    end

    ok, value = pcall(function()
        local envGetter = getfenv
        if type(envGetter) == "function" then
            local env = envGetter(0)
            if type(env) == "table" then
                return env[name]
            end
        end
    end)
    if ok and type(value) == "function" then
        return value
    end

    return nil
end

local GetCustomAsset = getExecutorFunction("getcustomasset")
local WriteFile = getExecutorFunction("writefile")
local ReadFile = getExecutorFunction("readfile")
local IsFile = getExecutorFunction("isfile")
local DelFile = getExecutorFunction("delfile")
local SetClipboard = getExecutorFunction("setclipboard")
local PersistenceAvailable = type(WriteFile) == "function"
    and type(ReadFile) == "function"
    and type(IsFile) == "function"

--============================================================
-- 03 / UTILITIES
--============================================================

local function clamp(value, minimum, maximum)
    if value < minimum then return minimum end
    if value > maximum then return maximum end
    return value
end

local function clamp01(value)
    return clamp(value, 0, 1)
end

local function lerp(a, b, alpha)
    return a + (b - a) * alpha
end

local function invLerp(a, b, value)
    if math.abs(b - a) < 0.000001 then
        return 0
    end
    return clamp01((value - a) / (b - a))
end

local function expLerp(current, target, speed, dt)
    return current + (target - current) * (1 - math.exp(-speed * dt))
end

local function lerpColor(a, b, alpha)
    return a:Lerp(b, clamp01(alpha))
end

local function safeRead(object, property)
    if not object then return nil end
    local ok, value = pcall(function()
        return object[property]
    end)
    if ok then
        return value
    end
    return nil
end

local function safeWrite(object, property, value)
    if not object or value == nil then return false end
    local ok = pcall(function()
        object[property] = value
    end)
    return ok
end

local function copyTable(source)
    local result = {}
    for key, value in pairs(source) do
        result[key] = value
    end
    return result
end

local function roundToStep(value, step)
    if not step or step <= 0 then return value end
    return math.floor(value / step + 0.5) * step
end

local function isFiniteNumber(value)
    return type(value) == "number"
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
end

local function formatClock(seconds)
    if not isFiniteNumber(seconds) or seconds < 0 then
        seconds = 0
    end
    local total = math.floor(seconds + 0.5)
    local hours = math.floor(total / 3600)
    local minutes = math.floor((total % 3600) / 60)
    local remainder = total % 60
    if hours > 0 then
        return string.format("%d:%02d:%02d", hours, minutes, remainder)
    end
    return string.format("%d:%02d", minutes, remainder)
end

local function formatDecimal(value, decimals)
    return string.format("%." .. tostring(decimals or 2) .. "f", value)
end

local function timeOfDayLabel(hour)
    hour = clamp(hour or 0, 0, 24)
    local whole = math.floor(hour)
    local minutes = math.floor((hour - whole) * 60 + 0.5)
    if minutes >= 60 then
        whole = (whole + 1) % 24
        minutes = 0
    end
    whole = whole % 24
    return string.format("%02d:%02d", whole, minutes)
end

local function keyDisplayName(name)
    if name == "Equals" then
        return "="
    elseif name == "Minus" then
        return "-"
    elseif name == "LeftBracket" then
        return "["
    elseif name == "RightBracket" then
        return "]"
    elseif name == "Semicolon" then
        return ";"
    elseif name == "Quote" then
        return "'"
    elseif name == "Comma" then
        return ","
    elseif name == "Period" then
        return "."
    elseif name == "Slash" then
        return "/"
    elseif name == "BackSlash" then
        return "\\"
    end
    return tostring(name)
end

local function colorToHex(color)
    local ok, hex = pcall(function()
        return color:ToHex()
    end)
    if ok then
        return hex
    end
    return "FFFFFF"
end

local function hexToColor(hex)
    if type(hex) ~= "string" then return nil end
    hex = hex:gsub("#", ""):gsub("%s", "")
    if #hex ~= 6 or hex:match("%X") then
        return nil
    end
    local ok, color = pcall(function()
        return Color3.fromHex(hex)
    end)
    if ok then
        return color
    end
    return nil
end

local function basename(path)
    local name = tostring(path):match("([^/\\]+)$")
    if name and #name > 0 then
        return name
    end
    return tostring(path)
end

local function shortSource(source, maximum)
    maximum = maximum or 46
    source = tostring(source or "")
    if #source <= maximum then
        return source
    end
    return "..." .. source:sub(#source - maximum + 4)
end

local function safeTween(instance, duration, properties)
    if not instance then return nil end
    local ok, tween = pcall(function()
        return TweenService:Create(
            instance,
            TweenInfo.new(duration, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
            properties
        )
    end)
    if ok and tween then
        tween:Play()
        return tween
    end
    return nil
end

local function safeCall(fn, ...)
    if type(fn) ~= "function" then return false end
    local ok, result = pcall(fn, ...)
    if ok then
        return true, result
    end
    return false, result
end

--============================================================
-- 04 / SIGNALS AND MOTION
--============================================================

local Signal = {}
Signal.__index = Signal

function Signal.new()
    return setmetatable({
        _handlers = {},
        _firing = false,
    }, Signal)
end

function Signal:Connect(callback)
    if type(callback) ~= "function" then
        return { Disconnect = function() end }
    end
    local handler = {
        callback = callback,
        connected = true,
    }
    table.insert(self._handlers, handler)
    local signal = self
    return {
        Disconnect = function()
            if not handler.connected then return end
            handler.connected = false
            for index = #signal._handlers, 1, -1 do
                if signal._handlers[index] == handler then
                    table.remove(signal._handlers, index)
                    break
                end
            end
        end,
    }
end

function Signal:Fire(...)
    local count = #self._handlers
    for index = 1, count do
        local handler = self._handlers[index]
        if handler and handler.connected then
            local ok, err = pcall(handler.callback, ...)
            if not ok then
                warn("[Visual Control Reborn] Signal handler error: " .. tostring(err))
            end
        end
    end
end

function Signal:Clear()
    self._handlers = {}
end

local Motion = {
    Reduced = false,
    Fast = 0.12,
    Normal = 0.22,
    Slow = 0.36,
}

function Motion.Duration(value)
    if Motion.Reduced then
        return 0.001
    end
    return value or Motion.Normal
end

function Motion.Tween(instance, properties, duration, style, direction)
    if not instance then return nil end
    local tween = TweenService:Create(
        instance,
        TweenInfo.new(
            Motion.Duration(duration),
            style or Enum.EasingStyle.Quint,
            direction or Enum.EasingDirection.Out
        ),
        properties
    )
    tween:Play()
    return tween
end

function Motion.Cancel(instance)
    if not instance then return end
    TweenService:Create(
        instance,
        TweenInfo.new(0),
        {}
    ):Play()
end

local Events = {
    ControlChanged = Signal.new(),
    EnvironmentChanged = Signal.new(),
    WeatherChanged = Signal.new(),
    AudioChanged = Signal.new(),
    PresetsChanged = Signal.new(),
    PageChanged = Signal.new(),
    VisibilityChanged = Signal.new(),
}

local NotifyExternal = nil
local function Notify(title, message, kind, duration)
    if NotifyExternal then
        NotifyExternal(title, message, kind, duration)
    end
end

--============================================================
-- 05 / SETTINGS DEFAULTS
--============================================================

local DEFAULT_SETTINGS = {
    -- Master graphics
    effectsEnabled = true,

    -- Owned post-processing
    bloom = 0.28,
    bloomSize = 24,
    bloomThreshold = 1.0,
    contrast = 0.12,
    brightness = 0.02,
    saturation = 0.08,
    tint = Color3.fromRGB(255, 255, 255),
    sunRaysEnabled = false,
    sunRaysIntensity = 0.045,
    vignetteEnabled = false,
    vignetteStrength = 0.22,

    -- Camera / depth of field
    fovEnabled = false,
    fov = 70,
    dofEnabled = false,
    dofFocus = 80,
    dofRadius = 24,
    dofFar = 0.12,
    dofNear = 0.05,

    -- Lighting
    timeOverride = false,
    clockTime = 14,
    adaptiveExposure = true,
    adaptationSpeed = 1.0,
    autoGrade = true,
    gradingStrength = 1.0,
    enhancedLighting = true,
    exposureBias = 0,

    -- Atmosphere and clouds
    atmosphereEnabled = true,
    atmosphereDensity = 0.24,
    atmosphereHaze = 0.8,
    atmosphereGlare = 0,
    atmosphereColor = Color3.fromRGB(199, 213, 225),
    weatherResponsive = true,
    cloudsEnabled = true,
    cloudCover = 0.18,
    cloudDensity = 0.28,
    cloudColor = Color3.fromRGB(238, 240, 247),

    -- Weather
    weather = "Clear",
    weatherIntensity = 1.0,
    windEnabled = true,
    shelterDetection = true,
    lightningEnabled = false,
    lightningIntensity = 0.5,

    -- Personal audio
    audioVolume = 0.50,
    audioLoop = true,
    indoorMuffling = true,
    indoorReverb = true,
    muffleStrength = 0.72,
    reverbStrength = 0.42,

    -- Runtime / appearance preferences
    quality = "Balanced",
    uiAccent = "Aurora",
    reducedMotion = false,
    tooltips = true,
    quickDock = true,
    rememberSettings = true,
    sidebarCollapsed = false,
    keybindName = "Equals",
}

local S = copyTable(DEFAULT_SETTINGS)

local Runtime = {
    Closed = false,
    CleanupStarted = false,
    Compare = false,
    Visible = true,
    Minimized = false,
    CapturingKey = false,
    ApplyingPreset = false,
}

local Controller = {}

local ActivePreset = "Natural"
local CustomPresets = {}
local Favorites = {}
local LastPresetError = nil

--============================================================
-- 06 / CURATED PRESETS
--============================================================

local PRESET_KEYS = {
    "effectsEnabled",
    "bloom", "bloomSize", "bloomThreshold", "contrast", "brightness",
    "saturation", "tint", "sunRaysEnabled", "sunRaysIntensity",
    "vignetteEnabled", "vignetteStrength",
    "fovEnabled", "fov", "dofEnabled", "dofFocus", "dofRadius",
    "dofFar", "dofNear",
    "timeOverride", "clockTime", "adaptiveExposure", "adaptationSpeed",
    "autoGrade", "gradingStrength", "enhancedLighting", "exposureBias",
    "atmosphereEnabled", "atmosphereDensity", "atmosphereHaze",
    "atmosphereGlare", "atmosphereColor", "weatherResponsive",
    "cloudsEnabled", "cloudCover", "cloudDensity", "cloudColor",
    "weather", "weatherIntensity", "windEnabled", "shelterDetection",
    "lightningEnabled", "lightningIntensity",
}

local function presetBaseValues()
    local values = {}
    for _, key in ipairs(PRESET_KEYS) do
        values[key] = DEFAULT_SETTINGS[key]
    end
    return values
end

local function makePreset(name, tag, description, topColor, bottomColor, overrides)
    local values = presetBaseValues()
    if overrides then
        for key, value in pairs(overrides) do
            if values[key] ~= nil then
                values[key] = value
            end
        end
    end
    return {
        name = name,
        tag = tag,
        description = description,
        thumbnailTop = topColor,
        thumbnailBottom = bottomColor,
        values = values,
        builtin = true,
    }
end

local BuiltinPresets = {}
local PresetOrder = {}

local function registerPreset(preset)
    BuiltinPresets[preset.name] = preset
    table.insert(PresetOrder, preset.name)
end

registerPreset(makePreset(
    "Natural",
    "BALANCED",
    "A clean, restrained grade that preserves the game's intended look while adding depth and atmosphere.",
    Color3.fromRGB(71, 104, 119),
    Color3.fromRGB(174, 195, 190),
    {
        bloom = 0.20,
        bloomSize = 22,
        bloomThreshold = 1.05,
        contrast = 0.08,
        brightness = 0.015,
        saturation = 0.06,
        tint = Color3.fromRGB(255, 255, 255),
        atmosphereDensity = 0.22,
        atmosphereHaze = 0.65,
        atmosphereColor = Color3.fromRGB(199, 213, 225),
        cloudCover = 0.18,
        cloudDensity = 0.28,
        timeOverride = false,
        weather = "Clear",
        weatherIntensity = 1.0,
    }
))

registerPreset(makePreset(
    "Cinematic",
    "CINEMATIC",
    "A warm late-afternoon grade with controlled contrast, shallow focus, subtle rays, and a soft vignette.",
    Color3.fromRGB(30, 43, 57),
    Color3.fromRGB(204, 141, 96),
    {
        bloom = 0.36,
        bloomSize = 28,
        bloomThreshold = 0.92,
        contrast = 0.20,
        brightness = -0.01,
        saturation = -0.04,
        tint = Color3.fromRGB(255, 237, 219),
        sunRaysEnabled = true,
        sunRaysIntensity = 0.065,
        vignetteEnabled = true,
        vignetteStrength = 0.28,
        timeOverride = true,
        clockTime = 17.2,
        adaptiveExposure = true,
        adaptationSpeed = 0.9,
        autoGrade = true,
        gradingStrength = 1.1,
        enhancedLighting = true,
        exposureBias = -0.04,
        atmosphereDensity = 0.30,
        atmosphereHaze = 1.15,
        atmosphereGlare = 0.04,
        atmosphereColor = Color3.fromRGB(225, 203, 183),
        cloudCover = 0.30,
        cloudDensity = 0.34,
        cloudColor = Color3.fromRGB(243, 229, 216),
        dofEnabled = true,
        dofFocus = 72,
        dofRadius = 18,
        dofFar = 0.18,
        dofNear = 0.04,
        fovEnabled = false,
        weather = "Clear",
    }
))

registerPreset(makePreset(
    "Vibrant",
    "VIBRANT",
    "A crisp, energetic look with richer color, cleaner highlights, and a bright but controlled sky.",
    Color3.fromRGB(25, 94, 129),
    Color3.fromRGB(108, 225, 195),
    {
        bloom = 0.28,
        bloomSize = 24,
        bloomThreshold = 1.0,
        contrast = 0.16,
        brightness = 0.035,
        saturation = 0.28,
        tint = Color3.fromRGB(247, 255, 250),
        atmosphereDensity = 0.19,
        atmosphereHaze = 0.52,
        atmosphereGlare = 0.02,
        atmosphereColor = Color3.fromRGB(190, 225, 238),
        cloudCover = 0.14,
        cloudDensity = 0.24,
        cloudColor = Color3.fromRGB(249, 251, 255),
        timeOverride = false,
        weather = "Clear",
        autoGrade = true,
        gradingStrength = 0.85,
    }
))

registerPreset(makePreset(
    "Golden Hour",
    "WARM",
    "Low, warm sun, glowing haze, and amber cloud light for a calm end-of-day atmosphere.",
    Color3.fromRGB(143, 70, 44),
    Color3.fromRGB(244, 196, 117),
    {
        bloom = 0.42,
        bloomSize = 30,
        bloomThreshold = 0.88,
        contrast = 0.14,
        brightness = 0.02,
        saturation = 0.16,
        tint = Color3.fromRGB(255, 223, 188),
        sunRaysEnabled = true,
        sunRaysIntensity = 0.08,
        vignetteEnabled = true,
        vignetteStrength = 0.18,
        timeOverride = true,
        clockTime = 18.15,
        adaptiveExposure = true,
        adaptationSpeed = 1.15,
        autoGrade = true,
        gradingStrength = 1.2,
        enhancedLighting = true,
        atmosphereDensity = 0.32,
        atmosphereHaze = 1.55,
        atmosphereGlare = 0.06,
        atmosphereColor = Color3.fromRGB(241, 202, 165),
        cloudCover = 0.34,
        cloudDensity = 0.38,
        cloudColor = Color3.fromRGB(255, 218, 184),
        weather = "Clear",
    }
))

registerPreset(makePreset(
    "Overcast",
    "SOFT",
    "A cool, diffused overcast study with dense cloud cover, lifted shadows, and muted color.",
    Color3.fromRGB(73, 82, 91),
    Color3.fromRGB(172, 180, 186),
    {
        bloom = 0.18,
        bloomSize = 26,
        bloomThreshold = 1.15,
        contrast = 0.05,
        brightness = 0.02,
        saturation = -0.08,
        tint = Color3.fromRGB(224, 232, 239),
        atmosphereDensity = 0.38,
        atmosphereHaze = 1.8,
        atmosphereGlare = 0,
        atmosphereColor = Color3.fromRGB(196, 206, 214),
        cloudsEnabled = true,
        cloudCover = 0.84,
        cloudDensity = 0.68,
        cloudColor = Color3.fromRGB(185, 193, 201),
        timeOverride = false,
        weather = "Overcast",
        weatherIntensity = 1.0,
        autoGrade = true,
        gradingStrength = 1.15,
    }
))

registerPreset(makePreset(
    "Rainy",
    "MOODY",
    "Rain, layered shelter-aware precipitation, cool storm haze, and a restrained cinematic grade.",
    Color3.fromRGB(22, 39, 52),
    Color3.fromRGB(91, 129, 154),
    {
        bloom = 0.22,
        bloomSize = 26,
        bloomThreshold = 1.02,
        contrast = 0.16,
        brightness = -0.005,
        saturation = -0.06,
        tint = Color3.fromRGB(218, 235, 245),
        vignetteEnabled = true,
        vignetteStrength = 0.16,
        timeOverride = false,
        adaptiveExposure = true,
        adaptationSpeed = 1.1,
        autoGrade = true,
        gradingStrength = 1.25,
        enhancedLighting = true,
        atmosphereDensity = 0.40,
        atmosphereHaze = 1.7,
        atmosphereGlare = 0,
        atmosphereColor = Color3.fromRGB(171, 190, 204),
        cloudCover = 0.88,
        cloudDensity = 0.74,
        cloudColor = Color3.fromRGB(132, 146, 160),
        weather = "Rain",
        weatherIntensity = 1.15,
        windEnabled = true,
        shelterDetection = true,
        lightningEnabled = false,
    }
))

registerPreset(makePreset(
    "Midnight",
    "NIGHT",
    "A deep blue night grade with lifted practical highlights, low ambient fill, and quiet contrast.",
    Color3.fromRGB(8, 14, 30),
    Color3.fromRGB(53, 78, 116),
    {
        bloom = 0.34,
        bloomSize = 26,
        bloomThreshold = 0.82,
        contrast = 0.18,
        brightness = 0.045,
        saturation = -0.02,
        tint = Color3.fromRGB(198, 216, 255),
        vignetteEnabled = true,
        vignetteStrength = 0.22,
        timeOverride = true,
        clockTime = 0,
        adaptiveExposure = true,
        adaptationSpeed = 1.35,
        autoGrade = true,
        gradingStrength = 0.9,
        enhancedLighting = true,
        exposureBias = 0.12,
        atmosphereDensity = 0.30,
        atmosphereHaze = 0.9,
        atmosphereGlare = 0.015,
        atmosphereColor = Color3.fromRGB(149, 172, 208),
        cloudCover = 0.24,
        cloudDensity = 0.30,
        cloudColor = Color3.fromRGB(164, 181, 209),
        weather = "Clear",
        weatherIntensity = 1.0,
    }
))

registerPreset(makePreset(
    "Dreamlike",
    "ETHEREAL",
    "Soft bloom, pastel haze, lifted shadows, and gentle depth of field for a deliberately unreal mood.",
    Color3.fromRGB(76, 54, 105),
    Color3.fromRGB(226, 177, 207),
    {
        bloom = 0.62,
        bloomSize = 34,
        bloomThreshold = 0.72,
        contrast = -0.04,
        brightness = 0.055,
        saturation = 0.18,
        tint = Color3.fromRGB(255, 224, 244),
        sunRaysEnabled = true,
        sunRaysIntensity = 0.035,
        vignetteEnabled = true,
        vignetteStrength = 0.12,
        timeOverride = true,
        clockTime = 7.1,
        adaptiveExposure = true,
        adaptationSpeed = 0.75,
        autoGrade = true,
        gradingStrength = 0.8,
        enhancedLighting = true,
        atmosphereDensity = 0.38,
        atmosphereHaze = 2.0,
        atmosphereGlare = 0.05,
        atmosphereColor = Color3.fromRGB(231, 203, 226),
        cloudCover = 0.46,
        cloudDensity = 0.42,
        cloudColor = Color3.fromRGB(244, 224, 240),
        dofEnabled = true,
        dofFocus = 58,
        dofRadius = 12,
        dofFar = 0.28,
        dofNear = 0.08,
        weather = "Clear",
    }
))

--============================================================
-- 07 / OPTIONAL LOCAL PERSISTENCE
--============================================================

local Storage = {
    Available = PersistenceAvailable,
    LastError = nil,
    LastSavedAt = 0,
    LoadError = nil,
    SavePending = false,
    SaveDirty = false,
}

local function encodePreset(preset)
    local values = {}
    local colors = {}
    for key, value in pairs(preset.values or {}) do
        if typeof(value) == "Color3" then
            colors[key] = colorToHex(value)
        elseif type(value) == "number" or type(value) == "boolean" or type(value) == "string" then
            values[key] = value
        end
    end
    return {
        name = preset.name,
        tag = preset.tag or "CUSTOM",
        description = preset.description or "",
        thumbnailTop = typeof(preset.thumbnailTop) == "Color3"
            and colorToHex(preset.thumbnailTop) or nil,
        thumbnailBottom = typeof(preset.thumbnailBottom) == "Color3"
            and colorToHex(preset.thumbnailBottom) or nil,
        values = values,
        colors = colors,
    }
end

local function decodePreset(data)
    if type(data) ~= "table" or type(data.name) ~= "string" then
        return nil
    end
    local name = data.name:sub(1, 28)
    if #name < 1 or name:lower() == "custom" or BuiltinPresets[name] then
        return nil
    end
    for builtinName in pairs(BuiltinPresets) do
        if builtinName:lower() == name:lower() then
            return nil
        end
    end
    local values = presetBaseValues()
    local storedValues = type(data.values) == "table" and data.values or {}
    local storedColors = type(data.colors) == "table" and data.colors or {}
    for _, key in ipairs(PRESET_KEYS) do
        local default = DEFAULT_SETTINGS[key]
        if typeof(default) == "Color3" then
            local parsed = hexToColor(storedColors[key])
            if parsed then
                values[key] = parsed
            end
        else
            local value = storedValues[key]
            if type(value) == type(default) then
                if type(value) == "number" and not isFiniteNumber(value) then
                    value = default
                end
                values[key] = value
            end
        end
    end
    local top = hexToColor(data.thumbnailTop) or Color3.fromRGB(62, 83, 98)
    local bottom = hexToColor(data.thumbnailBottom) or Color3.fromRGB(125, 207, 187)
    return {
        name = name,
        tag = "CUSTOM",
        description = type(data.description) == "string"
            and data.description:sub(1, 180) or "Custom visual preset.",
        thumbnailTop = top,
        thumbnailBottom = bottom,
        values = values,
        builtin = false,
    }
end

local function serializeSettings()
    local settings = {}
    local colors = {}
    for key, value in pairs(S) do
        if typeof(value) == "Color3" then
            colors[key] = colorToHex(value)
        elseif type(value) == "number" or type(value) == "boolean" or type(value) == "string" then
            settings[key] = value
        end
    end
    return settings, colors
end

local function savePreferences(force, silent)
    if not Storage.Available then
        return false, "Local filesystem APIs are unavailable."
    end
    if not force and not S.rememberSettings then
        return false, "Preference saving is disabled."
    end
    if Runtime.Closed then
        return false, "Application is closing."
    end

    local settings, colors = serializeSettings()
    local presets = {}
    for _, preset in ipairs(CustomPresets) do
        table.insert(presets, encodePreset(preset))
    end

    local payload = {
        schema = 4,
        version = VERSION,
        savedAt = os.time(),
        settings = settings,
        colors = colors,
        activePreset = ActivePreset,
        favorites = Favorites,
        customPresets = presets,
    }

    local okEncode, encoded = pcall(function()
        return HttpService:JSONEncode(payload)
    end)
    if not okEncode then
        Storage.LastError = tostring(encoded)
        if not silent then
            Notify("Preferences", "Could not encode saved settings.", "error")
        end
        return false, Storage.LastError
    end

    local okWrite, writeError = pcall(WriteFile, CONFIG_FILE, encoded)
    if not okWrite then
        Storage.LastError = tostring(writeError)
        if not silent then
            Notify("Preferences", "Could not write the local settings file.", "error")
        end
        return false, Storage.LastError
    end

    Storage.LastError = nil
    Storage.LastSavedAt = os.clock()
    return true
end

local function loadPreferences()
    if not Storage.Available then
        return false, "Local filesystem APIs are unavailable."
    end

    local okExists, exists = pcall(IsFile, CONFIG_FILE)
    if not okExists or not exists then
        return false, nil
    end

    local okRead, encoded = pcall(ReadFile, CONFIG_FILE)
    if not okRead or type(encoded) ~= "string" or #encoded == 0 then
        Storage.LoadError = "Could not read the saved preferences file."
        return false, Storage.LoadError
    end

    local okDecode, data = pcall(function()
        return HttpService:JSONDecode(encoded)
    end)
    if not okDecode or type(data) ~= "table" then
        Storage.LoadError = "Saved preferences are not valid JSON."
        return false, Storage.LoadError
    end

    local settings = type(data.settings) == "table" and data.settings or {}
    local colors = type(data.colors) == "table" and data.colors or {}

    for key, default in pairs(DEFAULT_SETTINGS) do
        if typeof(default) == "Color3" then
            local parsed = hexToColor(colors[key])
            if parsed then
                S[key] = parsed
            end
        elseif type(default) == "number" then
            local value = settings[key]
            if isFiniteNumber(value) then
                S[key] = value
            end
        elseif type(default) == "boolean" then
            if type(settings[key]) == "boolean" then
                S[key] = settings[key]
            end
        elseif type(default) == "string" then
            if type(settings[key]) == "string" then
                S[key] = settings[key]
            end
        end
    end

    if S.weather ~= "Clear"
        and S.weather ~= "Overcast"
        and S.weather ~= "Rain"
        and S.weather ~= "Snow"
        and S.weather ~= "Fog" then
        S.weather = "Clear"
    end

    if S.quality ~= "Low" and S.quality ~= "Balanced" and S.quality ~= "High" then
        S.quality = "Balanced"
    end

    if type(S.uiAccent) ~= "string" then
        S.uiAccent = "Aurora"
    end

    if type(S.keybindName) ~= "string" then
        S.keybindName = "Equals"
    else
        local okKey, keyCode = pcall(function()
            return Enum.KeyCode[S.keybindName]
        end)
        if not okKey or not keyCode or keyCode == KEYCODE_NONE then
            S.keybindName = "Equals"
        end
    end

    S.clockTime = clamp(S.clockTime, 0, 24)
    S.weatherIntensity = clamp(S.weatherIntensity, 0.2, 2)
    S.audioVolume = clamp(S.audioVolume, 0, 1)
    S.fov = clamp(S.fov, 40, 120)

    CustomPresets = {}
    if type(data.customPresets) == "table" then
        for _, presetData in ipairs(data.customPresets) do
            local preset = decodePreset(presetData)
            if preset then
                local duplicate = false
                for _, existing in ipairs(CustomPresets) do
                    if existing.name:lower() == preset.name:lower() then
                        duplicate = true
                        break
                    end
                end
                if not duplicate then
                    table.insert(CustomPresets, preset)
                end
            end
        end
    end

    Favorites = {}
    if type(data.favorites) == "table" then
        for _, id in ipairs(data.favorites) do
            if type(id) == "string" and #id <= 64 and #Favorites < 8 then
                local duplicate = false
                for _, existing in ipairs(Favorites) do
                    if existing == id then
                        duplicate = true
                        break
                    end
                end
                if not duplicate then
                    table.insert(Favorites, id)
                end
            end
        end
    end

    if type(data.activePreset) == "string" then
        if BuiltinPresets[data.activePreset] then
            ActivePreset = data.activePreset
        else
            local found = false
            for _, preset in ipairs(CustomPresets) do
                if preset.name == data.activePreset then
                    found = true
                    break
                end
            end
            ActivePreset = found and data.activePreset or "Custom"
        end
    end

    return true
end

local function scheduleSave()
    if not Storage.Available or not S.rememberSettings or Runtime.Closed then
        return
    end
    Storage.SaveDirty = true
    if Storage.SavePending then
        return
    end
    Storage.SavePending = true
    task.delay(0.9, function()
        Storage.SavePending = false
        if Storage.SaveDirty and not Runtime.Closed then
            Storage.SaveDirty = false
            savePreferences(false, true)
        end
    end)
end

--============================================================
-- 08 / ACCENT THEME
--============================================================

local ACCENTS = {
    Aurora = {
        color = Color3.fromRGB(105, 226, 196),
        hover = Color3.fromRGB(139, 241, 215),
        ink = Color3.fromRGB(6, 22, 19),
    },
    Ion = {
        color = Color3.fromRGB(124, 164, 255),
        hover = Color3.fromRGB(158, 190, 255),
        ink = Color3.fromRGB(7, 14, 32),
    },
    Ember = {
        color = Color3.fromRGB(255, 183, 106),
        hover = Color3.fromRGB(255, 205, 149),
        ink = Color3.fromRGB(32, 18, 6),
    },
    Orchid = {
        color = Color3.fromRGB(198, 155, 255),
        hover = Color3.fromRGB(218, 186, 255),
        ink = Color3.fromRGB(20, 10, 34),
    },
    Rose = {
        color = Color3.fromRGB(255, 145, 168),
        hover = Color3.fromRGB(255, 178, 195),
        ink = Color3.fromRGB(34, 8, 16),
    },
    Glacier = {
        color = Color3.fromRGB(137, 225, 255),
        hover = Color3.fromRGB(174, 238, 255),
        ink = Color3.fromRGB(4, 20, 28),
    },
}

local ACCENT_ORDER = { "Aurora", "Ion", "Ember", "Orchid", "Rose", "Glacier" }

local Theme = {
    Background = Color3.fromRGB(9, 11, 15),
    Window = Color3.fromRGB(15, 18, 24),
    Header = Color3.fromRGB(12, 15, 20),
    Sidebar = Color3.fromRGB(10, 12, 17),
    Card = Color3.fromRGB(21, 25, 33),
    CardRaised = Color3.fromRGB(25, 30, 39),
    CardHover = Color3.fromRGB(30, 36, 46),
    Track = Color3.fromRGB(40, 47, 59),
    Border = Color3.fromRGB(42, 50, 63),
    BorderSoft = Color3.fromRGB(29, 35, 45),
    Text = Color3.fromRGB(233, 238, 246),
    TextSecondary = Color3.fromRGB(154, 165, 182),
    TextMuted = Color3.fromRGB(101, 112, 130),
    Danger = Color3.fromRGB(255, 112, 132),
    Warning = Color3.fromRGB(242, 198, 116),
    Success = Color3.fromRGB(111, 227, 161),
    Info = Color3.fromRGB(126, 186, 255),
    White = Color3.fromRGB(255, 255, 255),
    Black = Color3.fromRGB(0, 0, 0),
    AccentName = "Aurora",
    Accent = ACCENTS.Aurora.color,
    AccentHover = ACCENTS.Aurora.hover,
    AccentInk = ACCENTS.Aurora.ink,
    _bindings = {},
}

function Theme.SetAccent(name, fire)
    local palette = ACCENTS[name]
    if not palette then
        name = "Aurora"
        palette = ACCENTS.Aurora
    end
    Theme.AccentName = name
    Theme.Accent = palette.color
    Theme.AccentHover = palette.hover
    Theme.AccentInk = palette.ink
    if fire == false then
        return
    end
    for _, entry in ipairs(Theme._bindings) do
        pcall(entry.callback)
    end
end

function Theme.Bind(callback, owner)
    if type(callback) ~= "function" then return end
    local entry = {
        callback = callback,
        owner = owner,
    }
    table.insert(Theme._bindings, entry)
    if owner then
        local connection = nil
        connection = owner.Destroying:Connect(function()
            for index = #Theme._bindings, 1, -1 do
                if Theme._bindings[index] == entry then
                    table.remove(Theme._bindings, index)
                    break
                end
            end
            if connection then
                pcall(function() connection:Disconnect() end)
            end
        end)
    end
    pcall(callback)
end

function Theme.ClearBindings()
    Theme._bindings = {}
end

--============================================================
-- 09 / PREVIOUS INSTANCE CLEANUP
--============================================================

local function destroyNamed(parent, name)
    if not parent then return end
    local object = parent:FindFirstChild(name)
    if object then
        pcall(function() object:Destroy() end)
    end
end

local function cleanupPreviousInstallation()
    local previous = nil
    pcall(function()
        previous = _G[GLOBAL_KEY]
    end)
    if type(previous) == "table" and type(previous.Cleanup) == "function" then
        pcall(previous.Cleanup)
    end

    for _, step in ipairs({
        STEP_NAME,
        LEGACY_PREFIX .. "V3_Engine",
        LEGACY_PREFIX .. "Time",
        LEGACY_PREFIX .. "Weather",
    }) do
        pcall(function()
            RunService:UnbindFromRenderStep(step)
        end)
    end

    for _, name in ipairs({
        PREFIX .. "GUI",
        PREFIX .. "Overlay",
        LEGACY_PREFIX .. "GUI",
    }) do
        destroyNamed(PlayerGui, name)
    end

    for _, name in ipairs({
        PREFIX .. "Bloom",
        PREFIX .. "Color",
        PREFIX .. "Rays",
        PREFIX .. "DOF",
        LEGACY_PREFIX .. "Bloom",
        LEGACY_PREFIX .. "Color",
        LEGACY_PREFIX .. "Rays",
        PREFIX .. "Atmosphere",
        LEGACY_PREFIX .. "Atmosphere",
    }) do
        destroyNamed(Lighting, name)
    end

    local cleanupTerrain = Workspace.Terrain
    if cleanupTerrain then
        for _, name in ipairs({
            PREFIX .. "Clouds",
            LEGACY_PREFIX .. "Clouds",
        }) do
            destroyNamed(cleanupTerrain, name)
        end
    end

    for _, name in ipairs({
        PREFIX .. "Weather",
        PREFIX .. "Particles",
        LEGACY_PREFIX .. "Particles",
    }) do
        destroyNamed(Workspace, name)
    end

    for _, name in ipairs({
        PREFIX .. "Audio",
        PREFIX .. "AudioFolder",
        LEGACY_PREFIX .. "Audio",
    }) do
        destroyNamed(SoundService, name)
    end
end

cleanupPreviousInstallation()

--============================================================
-- 10 / ORIGINAL ENVIRONMENT SNAPSHOTS
--============================================================

local Original = {
    ClockTime = Lighting.ClockTime,
    FogStart = Lighting.FogStart,
    FogEnd = Lighting.FogEnd,
    FogColor = Lighting.FogColor,
    ExposureCompensation = safeRead(Lighting, "ExposureCompensation"),
    Ambient = safeRead(Lighting, "Ambient"),
    OutdoorAmbient = safeRead(Lighting, "OutdoorAmbient"),
    EnvironmentDiffuseScale = safeRead(Lighting, "EnvironmentDiffuseScale"),
    EnvironmentSpecularScale = safeRead(Lighting, "EnvironmentSpecularScale"),
}

local ExistingAtmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
local AtmosphereOriginal = nil

local function snapshotAtmosphere(object)
    if not object then return nil end
    return {
        Density = safeRead(object, "Density"),
        Haze = safeRead(object, "Haze"),
        Glare = safeRead(object, "Glare"),
        Color = safeRead(object, "Color"),
        Decay = safeRead(object, "Decay"),
        Offset = safeRead(object, "Offset"),
    }
end

if ExistingAtmosphere then
    AtmosphereOriginal = snapshotAtmosphere(ExistingAtmosphere)
end

local Terrain = Workspace.Terrain
local ExistingClouds = Terrain and Terrain:FindFirstChildOfClass("Clouds") or nil
local CloudOriginal = nil

local function snapshotClouds(object)
    if not object then return nil end
    return {
        Enabled = safeRead(object, "Enabled"),
        Cover = safeRead(object, "Cover"),
        Density = safeRead(object, "Density"),
        Color = safeRead(object, "Color"),
    }
end

if ExistingClouds then
    CloudOriginal = snapshotClouds(ExistingClouds)
end

local function restoreAtmosphereSnapshot(object, snapshot)
    if not object or not snapshot then return end
    for key, value in pairs(snapshot) do
        safeWrite(object, key, value)
    end
end

local function restoreCloudSnapshot(object, snapshot)
    if not object or not snapshot then return end
    for key, value in pairs(snapshot) do
        safeWrite(object, key, value)
    end
end

local function restoreLightingCore()
    safeWrite(Lighting, "ExposureCompensation", Original.ExposureCompensation)
    safeWrite(Lighting, "Ambient", Original.Ambient)
    safeWrite(Lighting, "OutdoorAmbient", Original.OutdoorAmbient)
    safeWrite(Lighting, "EnvironmentDiffuseScale", Original.EnvironmentDiffuseScale)
    safeWrite(Lighting, "EnvironmentSpecularScale", Original.EnvironmentSpecularScale)
    Lighting.FogStart = Original.FogStart
    Lighting.FogEnd = Original.FogEnd
    Lighting.FogColor = Original.FogColor
end

--============================================================
-- 11 / LOAD OPTIONAL PREFERENCES
--============================================================

local preferencesLoaded, preferencesMessage = loadPreferences()
if not preferencesLoaded and preferencesMessage and Storage.Available then
    Storage.LoadError = preferencesMessage
end

Theme.SetAccent(S.uiAccent, false)
S.uiAccent = Theme.AccentName
Motion.Reduced = S.reducedMotion == true

if not Storage.Available then
    S.rememberSettings = false
end

if not preferencesLoaded then
    local natural = BuiltinPresets.Natural
    if natural then
        for _, key in ipairs(PRESET_KEYS) do
            S[key] = natural.values[key]
        end
        ActivePreset = "Natural"
    end
end

--============================================================
-- 12 / QUALITY PROFILES AND RUNTIME METRICS
--============================================================

local QUALITY_PROFILES = {
    Low = {
        label = "Low",
        environmentInterval = 0.32,
        atmosphereInterval = 0.12,
        rainRate = 0.42,
        snowRate = 0.48,
        cameraRays = 3,
        description = "Fewer raycasts and lighter precipitation. Best for competitive play.",
    },
    Balanced = {
        label = "Balanced",
        environmentInterval = 0.17,
        atmosphereInterval = 0.08,
        rainRate = 1.0,
        snowRate = 1.0,
        cameraRays = 5,
        description = "Recommended. Smooth visuals with controlled background work.",
    },
    High = {
        label = "High",
        environmentInterval = 0.10,
        atmosphereInterval = 0.055,
        rainRate = 1.35,
        snowRate = 1.28,
        cameraRays = 5,
        description = "Denser precipitation and faster environmental response.",
    },
}

local function getQualityProfile()
    return QUALITY_PROFILES[S.quality] or QUALITY_PROFILES.Balanced
end

local Metrics = {
    FPS = 60,
    FrameMs = 16.7,
    SmoothedFPS = 60,
    SessionStart = os.clock(),
    LastFrameAt = os.clock(),
    EnvironmentScans = 0,
    EnvironmentRate = 1 / QUALITY_PROFILES.Balanced.environmentInterval,
    EffectCount = 0,
    EstimatedParticles = 0,
    TotalFrames = 0,
}

function Metrics.Update(dt)
    Metrics.TotalFrames += 1
    if dt > 0 then
        local instantFPS = 1 / dt
        Metrics.FPS = instantFPS
        Metrics.SmoothedFPS = expLerp(Metrics.SmoothedFPS, instantFPS, 4.5, dt)
        Metrics.FrameMs = expLerp(Metrics.FrameMs, dt * 1000, 4.5, dt)
    end
    Metrics.LastFrameAt = os.clock()
    Metrics.EnvironmentRate = 1 / getQualityProfile().environmentInterval
end

--============================================================
-- 13 / ENVIRONMENT DETECTOR
--============================================================

local Environment = {
    Roof = 0,
    Wall = 0,
    CameraRoof = 0,
    RoomSize = 0.4,
    Indoor = 0,
    Outdoor = 1,
    Shelter = 1,
    Classification = "Scanning",
    LastClassification = nil,
    LastScanAt = 0,
    ScanCount = 0,
}

local RayParams = RaycastParams.new()
RayParams.FilterType = Enum.RaycastFilterType.Exclude
RayParams.IgnoreWater = true
RayParams.RespectCanCollide = true

local CEILING_OFFSETS = {
    Vector3.zero,
    Vector3.new(3.5, 0, 0),
    Vector3.new(-3.5, 0, 0),
    Vector3.new(0, 0, 3.5),
    Vector3.new(0, 0, -3.5),
}

local CAMERA_CEILING_OFFSETS = {
    Vector3.zero,
    Vector3.new(3, 0, 0),
    Vector3.new(-3, 0, 0),
    Vector3.new(0, 0, 3),
    Vector3.new(0, 0, -3),
}

local WALL_DIRECTIONS = {
    Vector3.new(1, 0, 0),
    Vector3.new(-1, 0, 0),
    Vector3.new(0, 0, 1),
    Vector3.new(0, 0, -1),
    Vector3.new(0.707, 0, 0.707),
    Vector3.new(-0.707, 0, 0.707),
    Vector3.new(0.707, 0, -0.707),
    Vector3.new(-0.707, 0, -0.707),
}

local RoofTarget = 0
local WallTarget = 0
local CameraRoofTarget = 0
local RoomSizeTarget = 0.4
local IndoorTarget = 0
local ScanAccumulator = 0
local ClassificationCandidate = nil
local ClassificationCandidateTime = 0

local function classifyEnvironment()
    local roof = Environment.Roof
    local wall = Environment.Wall
    local cameraRoof = Environment.CameraRoof
    local room = Environment.RoomSize

    if roof < 0.12 and wall < 0.12 and cameraRoof < 0.12 then
        return "Open air"
    end
    if roof > 0.55 and wall > 0.72 and room < 0.34 then
        return "Tunnel / cave"
    end
    if roof > 0.72 and wall > 0.62 then
        return "Deep interior"
    end
    if roof > 0.50 and wall > 0.40 then
        return "Indoor room"
    end
    if roof > 0.22 or cameraRoof > 0.40 then
        return "Sheltered"
    end
    if wall > 0.20 or roof > 0.10 then
        return "Partially covered"
    end
    return "Open air"
end

local function sampleEnvironment()
    local character = Player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    local profile = getQualityProfile()

    local filter = {}
    if character then
        table.insert(filter, character)
    end
    if Runtime.WeatherPart then
        table.insert(filter, Runtime.WeatherPart)
    end
    RayParams.FilterDescendantsInstances = filter

    local roofHits = 0
    local wallHits = 0
    local wallDistance = 0

    if root then
        local origin = root.Position + Vector3.new(0, 2, 0)
        for _, offset in ipairs(CEILING_OFFSETS) do
            local result = Workspace:Raycast(origin + offset, Vector3.new(0, 26, 0), RayParams)
            if result then
                roofHits += 1
            end
        end

        for _, direction in ipairs(WALL_DIRECTIONS) do
            local result = Workspace:Raycast(origin, direction * 18, RayParams)
            if result then
                wallHits += 1
                wallDistance += result.Distance
            end
        end
    end

    local camera = Workspace.CurrentCamera
    local cameraRoofHits = 0
    local cameraRayCount = 0
    if camera then
        local cameraOrigin = camera.CFrame.Position + Vector3.new(0, 0.8, 0)
        cameraRayCount = math.clamp(profile.cameraRays or 5, 1, #CAMERA_CEILING_OFFSETS)
        for index = 1, cameraRayCount do
            local result = Workspace:Raycast(
                cameraOrigin + CAMERA_CEILING_OFFSETS[index],
                Vector3.new(0, 30, 0),
                RayParams
            )
            if result then
                cameraRoofHits += 1
            end
        end
    end

    RoofTarget = root and (roofHits / #CEILING_OFFSETS) or 0
    WallTarget = root and (wallHits / #WALL_DIRECTIONS) or 0
    CameraRoofTarget = cameraRayCount > 0 and (cameraRoofHits / cameraRayCount) or 0
    RoomSizeTarget = wallHits > 0
        and clamp01((wallDistance / wallHits) / 18)
        or 0.62

    IndoorTarget = clamp01(
        RoofTarget * 0.48
        + WallTarget * 0.34
        + RoofTarget * WallTarget * 0.12
        + CameraRoofTarget * 0.06
    )

    Environment.LastScanAt = os.clock()
    Environment.ScanCount += 1
    Metrics.EnvironmentScans = Environment.ScanCount
end

function Environment.Update(dt)
    local profile = getQualityProfile()
    ScanAccumulator += dt
    if ScanAccumulator >= profile.environmentInterval then
        ScanAccumulator = 0
        sampleEnvironment()
    end

    Environment.Roof = expLerp(Environment.Roof, RoofTarget, 2.8, dt)
    Environment.Wall = expLerp(Environment.Wall, WallTarget, 2.6, dt)
    Environment.CameraRoof = expLerp(Environment.CameraRoof, CameraRoofTarget, 3.0, dt)
    Environment.RoomSize = expLerp(Environment.RoomSize, RoomSizeTarget, 2.0, dt)
    Environment.Indoor = expLerp(Environment.Indoor, IndoorTarget, 2.5, dt)
    Environment.Outdoor = 1 - Environment.Indoor
    Environment.Shelter = clamp01(
        1 - (Environment.CameraRoof * 0.65 + Environment.Roof * 0.35)
    )

    local candidate = classifyEnvironment()
    if Environment.Classification == "Scanning" then
        Environment.Classification = candidate
        Events.EnvironmentChanged:Fire(Environment)
    elseif candidate ~= Environment.Classification then
        if candidate ~= ClassificationCandidate then
            ClassificationCandidate = candidate
            ClassificationCandidateTime = 0
        end
        ClassificationCandidateTime += dt
        if ClassificationCandidateTime >= 0.55 then
            Environment.LastClassification = Environment.Classification
            Environment.Classification = candidate
            ClassificationCandidate = nil
            ClassificationCandidateTime = 0
            Events.EnvironmentChanged:Fire(Environment)
        end
    else
        ClassificationCandidate = nil
        ClassificationCandidateTime = 0
    end
end

function Environment.Reset()
    RoofTarget = 0
    WallTarget = 0
    CameraRoofTarget = 0
    RoomSizeTarget = 0.4
    IndoorTarget = 0
    Environment.Roof = 0
    Environment.Wall = 0
    Environment.CameraRoof = 0
    Environment.RoomSize = 0.4
    Environment.Indoor = 0
    Environment.Outdoor = 1
    Environment.Shelter = 1
end

--============================================================
-- 14 / SCREEN OVERLAY (VIGNETTE + LIGHTNING)
--============================================================

local Overlay = {
    Gui = nil,
    VignetteEdges = {},
    FlashFrame = nil,
    VignetteEnabled = false,
    VignetteStrength = 0,
    FlashToken = 0,
}

local function createOverlayGui()
    local gui = Instance.new("ScreenGui")
    gui.Name = PREFIX .. "Overlay"
    gui.IgnoreGuiInset = true
    gui.ResetOnSpawn = false
    gui.DisplayOrder = 20
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.Parent = PlayerGui
    Overlay.Gui = gui

    local function makeEdge(name, position, size, rotation)
        local frame = Instance.new("Frame")
        frame.Name = name
        frame.Position = position
        frame.Size = size
        frame.BackgroundColor3 = Color3.new(0, 0, 0)
        frame.BackgroundTransparency = 1
        frame.BorderSizePixel = 0
        frame.Active = false
        frame.ZIndex = 2
        local gradient = Instance.new("UIGradient")
        gradient.Rotation = rotation
        gradient.Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0),
            NumberSequenceKeypoint.new(0.55, 0.55),
            NumberSequenceKeypoint.new(1, 1),
        })
        gradient.Parent = frame
        frame.Parent = gui
        table.insert(Overlay.VignetteEdges, frame)
        return frame
    end

    makeEdge(
        "VignetteTop",
        UDim2.fromScale(0, 0),
        UDim2.fromScale(1, 0.22),
        90
    )
    makeEdge(
        "VignetteBottom",
        UDim2.fromScale(0, 0.78),
        UDim2.fromScale(1, 0.22),
        270
    )
    makeEdge(
        "VignetteLeft",
        UDim2.fromScale(0, 0),
        UDim2.fromScale(0.17, 1),
        0
    )
    makeEdge(
        "VignetteRight",
        UDim2.fromScale(0.83, 0),
        UDim2.fromScale(0.17, 1),
        180
    )

    local flash = Instance.new("Frame")
    flash.Name = "LightningFlash"
    flash.Size = UDim2.fromScale(1, 1)
    flash.BackgroundColor3 = Color3.fromRGB(221, 234, 255)
    flash.BackgroundTransparency = 1
    flash.BorderSizePixel = 0
    flash.Visible = false
    flash.Active = false
    flash.ZIndex = 10
    flash.Parent = gui
    Overlay.FlashFrame = flash
end

createOverlayGui()

function Overlay.SetVignette(enabled, strength)
    strength = clamp01(strength or 0)
    if Overlay.VignetteEnabled == enabled and math.abs(Overlay.VignetteStrength - strength) < 0.002 then
        return
    end
    Overlay.VignetteEnabled = enabled
    Overlay.VignetteStrength = strength
    local target = enabled and (1 - strength * 0.65) or 1
    for _, edge in ipairs(Overlay.VignetteEdges) do
        if edge.Parent then
            Motion.Tween(edge, { BackgroundTransparency = target }, 0.28)
        end
    end
end

function Overlay.Flash(strength)
    if Runtime.Closed or S.reducedMotion or not Overlay.FlashFrame then
        return
    end
    strength = clamp(strength or 0.5, 0.1, 1)
    Overlay.FlashToken += 1
    local token = Overlay.FlashToken
    local flash = Overlay.FlashFrame
    flash.Visible = true
    flash.BackgroundTransparency = 1

    Motion.Tween(flash, {
        BackgroundTransparency = 1 - (0.105 * strength),
    }, 0.035)

    task.delay(0.055, function()
        if token ~= Overlay.FlashToken or not flash.Parent then return end
        Motion.Tween(flash, { BackgroundTransparency = 0.955 }, 0.07)
    end)

    task.delay(0.13, function()
        if token ~= Overlay.FlashToken or not flash.Parent then return end
        Motion.Tween(flash, {
            BackgroundTransparency = 1 - (0.045 * strength),
        }, 0.06)
    end)

    task.delay(0.27, function()
        if token ~= Overlay.FlashToken or not flash.Parent then return end
        Motion.Tween(flash, { BackgroundTransparency = 1 }, 0.28)
        task.delay(0.30, function()
            if token == Overlay.FlashToken and flash.Parent then
                flash.Visible = false
            end
        end)
    end)
end

function Overlay.CancelFlash()
    Overlay.FlashToken += 1
    if Overlay.FlashFrame then
        Overlay.FlashFrame.BackgroundTransparency = 1
        Overlay.FlashFrame.Visible = false
    end
end

function Overlay.Destroy()
    Overlay.CancelFlash()
    if Overlay.Gui then
        Overlay.Gui:Destroy()
        Overlay.Gui = nil
    end
end

--============================================================
-- 15 / WEATHER ENGINE
--============================================================

local WEATHER_CONDITIONS = { "Rain", "Snow", "Fog", "Overcast" }

local Weather = {
    Part = nil,
    Rain = nil,
    Snow = nil,
    Mix = {
        Rain = 0,
        Snow = 0,
        Fog = 0,
        Overcast = 0,
    },
    Restored = true,
    LightningTimer = 12,
}

local function createWeatherEmitterPart()
    local part = Instance.new("Part")
    part.Name = PREFIX .. "Weather"
    part.Size = Vector3.new(170, 2, 170)
    part.Transparency = 1
    part.Anchored = true
    part.CanCollide = false
    part.CanTouch = false
    part.CanQuery = false
    part.CastShadow = false
    part.Massless = true
    part.Locked = true
    part.Parent = Workspace
    Weather.Part = part
    Runtime.WeatherPart = part

    local rain = Instance.new("ParticleEmitter")
    rain.Name = "Rain"
    rain.Texture = "rbxasset://textures/particles/rain_main.dds"
    rain.Rate = 0
    rain.Enabled = false
    rain.Lifetime = NumberRange.new(0.95, 1.55)
    rain.Speed = NumberRange.new(88, 118)
    rain.SpreadAngle = Vector2.new(3, 3)
    rain.EmissionDirection = Enum.NormalId.Bottom
    rain.Shape = Enum.ParticleEmitterShape.Box
    rain.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
    rain.Size = NumberSequence.new(0.28)
    rain.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.08),
        NumberSequenceKeypoint.new(0.72, 0.24),
        NumberSequenceKeypoint.new(1, 0.58),
    })
    rain.Color = ColorSequence.new(Color3.fromRGB(199, 225, 241))
    rain.LightInfluence = 0.35
    rain.LightEmission = 0.28
    rain.ZOffset = 0.05
    rain.Drag = 0
    rain.Acceleration = Vector3.new(0, -22, 0)
    rain.Orientation = Enum.ParticleOrientation.VelocityParallel
    rain.Parent = part
    Weather.Rain = rain

    local snow = Instance.new("ParticleEmitter")
    snow.Name = "Snow"
    snow.Texture = "rbxasset://textures/particles/sparkles_main.dds"
    snow.Rate = 0
    snow.Enabled = false
    snow.Lifetime = NumberRange.new(4.5, 8.0)
    snow.Speed = NumberRange.new(6, 12)
    snow.SpreadAngle = Vector2.new(16, 16)
    snow.EmissionDirection = Enum.NormalId.Bottom
    snow.Shape = Enum.ParticleEmitterShape.Box
    snow.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
    snow.Size = NumberSequence.new(0.24)
    snow.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.10),
        NumberSequenceKeypoint.new(0.80, 0.32),
        NumberSequenceKeypoint.new(1, 0.70),
    })
    snow.Color = ColorSequence.new(Color3.fromRGB(239, 247, 255))
    snow.LightInfluence = 0.28
    snow.LightEmission = 0.18
    snow.ZOffset = 0.05
    snow.Drag = 0.65
    snow.Acceleration = Vector3.new(0, -2.5, 0)
    snow.Rotation = NumberRange.new(0, 360)
    snow.RotSpeed = NumberRange.new(-26, 26)
    snow.Orientation = Enum.ParticleOrientation.FacingCameraWorldUp
    snow.Parent = part
    Weather.Snow = snow
end

createWeatherEmitterPart()

function Weather.GetMix()
    return Weather.Mix
end

function Weather.GetCloudiness()
    local mix = Weather.Mix
    return clamp01(math.max(
        mix.Rain,
        mix.Snow * 0.82,
        mix.Fog * 0.50,
        mix.Overcast
    ))
end

function Weather.GetEstimatedParticles()
    if not Weather.Rain or not Weather.Snow then
        return 0
    end
    local rainLife = (Weather.Rain.Lifetime.Min + Weather.Rain.Lifetime.Max) * 0.5
    local snowLife = (Weather.Snow.Lifetime.Min + Weather.Snow.Lifetime.Max) * 0.5
    return Weather.Rain.Rate * rainLife + Weather.Snow.Rate * snowLife
end

local function restoreWeatherFog()
    Lighting.FogStart = Original.FogStart
    Lighting.FogEnd = Original.FogEnd
    Lighting.FogColor = Original.FogColor
end

local function setEmitterRates(rainRate, snowRate)
    if not Weather.Rain or not Weather.Snow then return end
    Weather.Rain.Rate = math.clamp(rainRate, 0, 4200)
    Weather.Snow.Rate = math.clamp(snowRate, 0, 700)
    Weather.Rain.Enabled = Weather.Rain.Rate > 0.1
    Weather.Snow.Enabled = Weather.Snow.Rate > 0.1
end

function Weather.Update(dt)
    local active = S.effectsEnabled and not Runtime.Compare and not Runtime.Closed

    if not active then
        if not Weather.Restored then
            setEmitterRates(0, 0)
            if Weather.Rain then Weather.Rain:Clear() end
            if Weather.Snow then Weather.Snow:Clear() end
            restoreWeatherFog()
            Weather.Restored = true
            Overlay.CancelFlash()
        end
        Metrics.EstimatedParticles = 0
        return
    end

    if S.reducedMotion and Overlay.FlashFrame and Overlay.FlashFrame.Visible then
        Overlay.CancelFlash()
    end

    Weather.Restored = false
    local profile = getQualityProfile()
    for _, name in ipairs(WEATHER_CONDITIONS) do
        local target = S.weather == name and S.weatherIntensity or 0
        Weather.Mix[name] = expLerp(Weather.Mix[name], target, 1.15, dt)
    end

    local camera = Workspace.CurrentCamera
    if camera and Weather.Part then
        Weather.Part.CFrame = CFrame.new(
            camera.CFrame.Position + Vector3.new(0, 30, 0)
        )
    end

    local t = os.clock()
    local windX = 0
    local windZ = 0
    if S.windEnabled then
        windX = math.sin(t * 0.23) * 9 + math.sin(t * 0.07 + 0.8) * 5
        windZ = math.cos(t * 0.19 + 0.4) * 7 + math.sin(t * 0.051) * 3
    end

    if Weather.Rain then
        Weather.Rain.Acceleration = Vector3.new(windX * 2.2, -24, windZ * 2.2)
    end
    if Weather.Snow then
        Weather.Snow.Acceleration = Vector3.new(windX * 0.46, -2.5, windZ * 0.46)
    end

    local cover = clamp01(
        Environment.CameraRoof * 0.65 + Environment.Roof * 0.35
    )
    local shelter = 1
    if S.shelterDetection then
        shelter = clamp((1 - cover) ^ 1.25, 0, 1)
    end

    local rainTarget = 1200 * Weather.Mix.Rain * profile.rainRate * shelter
    local snowTarget = 170 * Weather.Mix.Snow * profile.snowRate * shelter
    setEmitterRates(rainTarget, snowTarget)

    local fogMix = clamp01(
        Weather.Mix.Fog
        + Weather.Mix.Rain * 0.18
        + Weather.Mix.Snow * 0.12
        + Weather.Mix.Overcast * 0.08
    )
    local denseFogEnd = math.min(
        Original.FogEnd,
        math.max(110, 720 - (S.weatherIntensity - 1) * 150)
    )
    local fogTargetEnd = Original.FogEnd
        + (denseFogEnd - Original.FogEnd) * fogMix
    local fogTargetStart = Original.FogStart * (1 - 0.65 * fogMix)

    Lighting.FogStart = expLerp(Lighting.FogStart, fogTargetStart, 1.8, dt)
    Lighting.FogEnd = expLerp(Lighting.FogEnd, fogTargetEnd, 1.6, dt)
    Lighting.FogColor = lerpColor(
        Lighting.FogColor,
        lerpColor(Original.FogColor, Color3.fromRGB(154, 178, 193), fogMix),
        1 - math.exp(-1.7 * dt)
    )

    if S.lightningEnabled
        and not S.reducedMotion
        and Weather.Mix.Rain > 0.38
        and not Runtime.Compare then
        Weather.LightningTimer -= dt
        if Weather.LightningTimer <= 0 then
            Weather.LightningTimer = 10 + math.random() * 12
            Overlay.Flash(S.lightningIntensity)
        end
    else
        Weather.LightningTimer = math.max(Weather.LightningTimer, 5)
    end

    Metrics.EstimatedParticles = Weather.GetEstimatedParticles()
end

function Weather.Restore()
    setEmitterRates(0, 0)
    if Weather.Rain then Weather.Rain:Clear() end
    if Weather.Snow then Weather.Snow:Clear() end
    restoreWeatherFog()
    Weather.Mix.Rain = 0
    Weather.Mix.Snow = 0
    Weather.Mix.Fog = 0
    Weather.Mix.Overcast = 0
    Weather.Restored = true
end

function Weather.Destroy()
    Weather.Restore()
    if Weather.Part then
        Weather.Part:Destroy()
        Weather.Part = nil
        Runtime.WeatherPart = nil
    end
end

--============================================================
-- 16 / GRAPHICS ENGINE
--============================================================

local Graphics = {
    Bloom = nil,
    ColorCorrection = nil,
    SunRays = nil,
    DepthOfField = nil,
}

local function createOwnedEffect(className, name)
    local object = Instance.new(className)
    object.Name = PREFIX .. name
    object.Parent = Lighting
    return object
end

Graphics.Bloom = createOwnedEffect("BloomEffect", "Bloom")
Graphics.Bloom.Intensity = S.bloom
Graphics.Bloom.Size = S.bloomSize
Graphics.Bloom.Threshold = S.bloomThreshold
Graphics.Bloom.Enabled = S.effectsEnabled

Graphics.ColorCorrection = createOwnedEffect("ColorCorrectionEffect", "Color")
Graphics.ColorCorrection.Contrast = S.contrast
Graphics.ColorCorrection.Brightness = S.brightness
Graphics.ColorCorrection.Saturation = S.saturation
Graphics.ColorCorrection.TintColor = S.tint
Graphics.ColorCorrection.Enabled = S.effectsEnabled

Graphics.SunRays = createOwnedEffect("SunRaysEffect", "Rays")
Graphics.SunRays.Intensity = 0.04
Graphics.SunRays.Spread = 0.82
Graphics.SunRays.Enabled = false

Graphics.DepthOfField = createOwnedEffect("DepthOfFieldEffect", "DOF")
Graphics.DepthOfField.FocusDistance = S.dofFocus
Graphics.DepthOfField.InFocusRadius = S.dofRadius
Graphics.DepthOfField.FarIntensity = S.dofFar
Graphics.DepthOfField.NearIntensity = S.dofNear
Graphics.DepthOfField.Enabled = false

local function solarFactors(hour)
    hour = clamp(hour or 0, 0, 24)
    local day = clamp01(math.sin(((hour - 6) / 12) * math.pi))
    local warm = math.max(
        0,
        1 - math.abs(hour - 6.6) / 2.5,
        1 - math.abs(hour - 18.0) / 2.5
    )
    return day, clamp01(warm)
end

function Graphics.Update(dt)
    local allowed = S.effectsEnabled and not Runtime.Compare and not Runtime.Closed
    if not allowed then
        Graphics.Bloom.Enabled = false
        Graphics.ColorCorrection.Enabled = false
        Graphics.SunRays.Enabled = false
        Graphics.DepthOfField.Enabled = false
        Overlay.SetVignette(false, S.vignetteStrength)
        Metrics.EffectCount = 0
        return
    end

    local hour = S.timeOverride and S.clockTime or Lighting.ClockTime
    local day, warm = solarFactors(hour)
    local mix = Weather.GetMix()
    local rain = clamp01(mix.Rain)
    local snow = clamp01(mix.Snow)
    local fog = clamp01(mix.Fog)
    local overcast = clamp01(mix.Overcast)
    local cloudiness = Weather.GetCloudiness()
    local gradeStrength = S.autoGrade and S.gradingStrength or 0

    local tint = S.tint
    local gradingBrightness = 0
    local gradingSaturation = 0
    if S.autoGrade then
        tint = lerpColor(tint, Color3.fromRGB(255, 219, 191), warm * 0.24 * gradeStrength)
        tint = lerpColor(tint, Color3.fromRGB(196, 214, 235), rain * 0.18 * gradeStrength)
        tint = lerpColor(tint, Color3.fromRGB(219, 234, 255), snow * 0.15 * gradeStrength)
        tint = lerpColor(tint, Color3.fromRGB(203, 220, 232), fog * 0.20 * gradeStrength)
        tint = lerpColor(tint, Color3.fromRGB(204, 216, 228), overcast * 0.16 * gradeStrength)
        gradingBrightness = (
            -0.045 * rain
            - 0.025 * fog
            - 0.032 * overcast
        ) * gradeStrength
        gradingSaturation = (
            -0.075 * rain
            - 0.075 * fog
            - 0.055 * overcast
        ) * gradeStrength
    end

    local colorAlpha = 1 - math.exp(-2.2 * dt)
    Graphics.ColorCorrection.TintColor = lerpColor(
        Graphics.ColorCorrection.TintColor,
        tint,
        colorAlpha
    )
    Graphics.ColorCorrection.Brightness = expLerp(
        Graphics.ColorCorrection.Brightness,
        S.brightness + gradingBrightness,
        2.2,
        dt
    )
    Graphics.ColorCorrection.Contrast = expLerp(
        Graphics.ColorCorrection.Contrast,
        S.contrast,
        3.2,
        dt
    )
    Graphics.ColorCorrection.Saturation = expLerp(
        Graphics.ColorCorrection.Saturation,
        S.saturation + gradingSaturation,
        2.2,
        dt
    )

    Graphics.Bloom.Intensity = expLerp(
        Graphics.Bloom.Intensity,
        S.bloom,
        2.8,
        dt
    )
    Graphics.Bloom.Size = expLerp(Graphics.Bloom.Size, S.bloomSize, 2.6, dt)
    Graphics.Bloom.Threshold = expLerp(
        Graphics.Bloom.Threshold,
        S.bloomThreshold,
        2.6,
        dt
    )

    local rayTarget = S.sunRaysEnabled
        and (S.sunRaysIntensity * day * (1 - 0.68 * cloudiness))
        or 0
    Graphics.SunRays.Intensity = expLerp(
        Graphics.SunRays.Intensity,
        rayTarget,
        2.2,
        dt
    )

    Graphics.DepthOfField.FocusDistance = expLerp(
        Graphics.DepthOfField.FocusDistance,
        S.dofFocus,
        2.8,
        dt
    )
    Graphics.DepthOfField.InFocusRadius = expLerp(
        Graphics.DepthOfField.InFocusRadius,
        S.dofRadius,
        2.8,
        dt
    )
    Graphics.DepthOfField.FarIntensity = expLerp(
        Graphics.DepthOfField.FarIntensity,
        S.dofFar,
        2.8,
        dt
    )
    Graphics.DepthOfField.NearIntensity = expLerp(
        Graphics.DepthOfField.NearIntensity,
        S.dofNear,
        2.8,
        dt
    )

    Graphics.Bloom.Enabled = true
    Graphics.ColorCorrection.Enabled = true
    Graphics.SunRays.Enabled = S.sunRaysEnabled
    Graphics.DepthOfField.Enabled = S.dofEnabled
    Overlay.SetVignette(S.vignetteEnabled, S.vignetteStrength)

    local count = 2
    if S.sunRaysEnabled then count += 1 end
    if S.dofEnabled then count += 1 end
    if S.vignetteEnabled then count += 1 end
    if S.atmosphereEnabled then count += 1 end
    if S.cloudsEnabled then count += 1 end
    if S.weather ~= "Clear" then count += 1 end
    Metrics.EffectCount = count
end

function Graphics.Destroy()
    if Graphics.Bloom then Graphics.Bloom:Destroy() end
    if Graphics.ColorCorrection then Graphics.ColorCorrection:Destroy() end
    if Graphics.SunRays then Graphics.SunRays:Destroy() end
    if Graphics.DepthOfField then Graphics.DepthOfField:Destroy() end
end

--============================================================
-- 17 / LIGHTING MANAGER
--============================================================

local LightingManager = {
    TimeApplied = false,
    ExposureApplied = false,
    EnhancedApplied = false,
}

local function restoreExposure()
    safeWrite(Lighting, "ExposureCompensation", Original.ExposureCompensation)
end

local function restoreEnhancedLighting()
    safeWrite(Lighting, "Ambient", Original.Ambient)
    safeWrite(Lighting, "OutdoorAmbient", Original.OutdoorAmbient)
    safeWrite(Lighting, "EnvironmentDiffuseScale", Original.EnvironmentDiffuseScale)
    safeWrite(Lighting, "EnvironmentSpecularScale", Original.EnvironmentSpecularScale)
end

function LightingManager.Update(dt)
    local allowed = S.effectsEnabled and not Runtime.Compare and not Runtime.Closed

    if not allowed then
        if LightingManager.TimeApplied then
            Lighting.ClockTime = Original.ClockTime
            LightingManager.TimeApplied = false
        end
        if LightingManager.ExposureApplied then
            restoreExposure()
            LightingManager.ExposureApplied = false
        end
        if LightingManager.EnhancedApplied then
            restoreEnhancedLighting()
            LightingManager.EnhancedApplied = false
        end
        return
    end

    if S.timeOverride then
        Lighting.ClockTime = S.clockTime
        LightingManager.TimeApplied = true
    elseif LightingManager.TimeApplied then
        Lighting.ClockTime = Original.ClockTime
        LightingManager.TimeApplied = false
    end

    local hour = S.timeOverride and S.clockTime or Lighting.ClockTime
    local day = solarFactors(hour)
    local mix = Weather.GetMix()
    local rain = clamp01(mix.Rain)
    local fog = clamp01(mix.Fog)
    local overcast = clamp01(mix.Overcast)
    local cloudiness = Weather.GetCloudiness()

    if Original.ExposureCompensation ~= nil then
        local target
        if S.adaptiveExposure then
            target = Original.ExposureCompensation
                + 0.27 * Environment.Indoor
                - 0.10 * day * (1 - cloudiness)
                + 0.10 * rain
                + 0.04 * fog
                + 0.025 * overcast
                + S.exposureBias
            target = clamp(target, -5, 5)
        else
            target = clamp(
                Original.ExposureCompensation + S.exposureBias,
                -5,
                5
            )
        end
        local speed = S.adaptiveExposure and (0.8 * S.adaptationSpeed) or 6
        safeWrite(Lighting, "ExposureCompensation", expLerp(
            safeRead(Lighting, "ExposureCompensation") or target,
            target,
            speed,
            dt
        ))
        LightingManager.ExposureApplied = true
    end

    if S.enhancedLighting then
        if Original.EnvironmentDiffuseScale ~= nil then
            local target = math.max(
                Original.EnvironmentDiffuseScale,
                0.28 + 0.12 * day * (1 - cloudiness)
            )
            safeWrite(Lighting, "EnvironmentDiffuseScale", expLerp(
                safeRead(Lighting, "EnvironmentDiffuseScale") or target,
                target,
                1.4,
                dt
            ))
        end
        if Original.EnvironmentSpecularScale ~= nil then
            local target = math.max(
                Original.EnvironmentSpecularScale,
                0.46 + 0.16 * day * (1 - cloudiness)
            )
            safeWrite(Lighting, "EnvironmentSpecularScale", expLerp(
                safeRead(Lighting, "EnvironmentSpecularScale") or target,
                target,
                1.4,
                dt
            ))
        end
        if Original.Ambient ~= nil then
            local desired = lerpColor(
                Original.Ambient,
                Color3.fromRGB(113, 129, 151),
                0.09 + 0.055 * rain + 0.035 * overcast
            )
            safeWrite(Lighting, "Ambient", lerpColor(
                safeRead(Lighting, "Ambient") or desired,
                desired,
                1 - math.exp(-1.5 * dt)
            ))
        end
        if Original.OutdoorAmbient ~= nil then
            local _, warm = solarFactors(hour)
            local desired = lerpColor(
                Original.OutdoorAmbient,
                Color3.fromRGB(190, 177, 161),
                warm * 0.12
            )
            desired = lerpColor(
                desired,
                Color3.fromRGB(142, 161, 188),
                rain * 0.12 + overcast * 0.07
            )
            safeWrite(Lighting, "OutdoorAmbient", lerpColor(
                safeRead(Lighting, "OutdoorAmbient") or desired,
                desired,
                1 - math.exp(-1.5 * dt)
            ))
        end
        LightingManager.EnhancedApplied = true
    elseif LightingManager.EnhancedApplied then
        restoreEnhancedLighting()
        LightingManager.EnhancedApplied = false
    end
end

function LightingManager.Restore()
    if LightingManager.TimeApplied then
        Lighting.ClockTime = Original.ClockTime
        LightingManager.TimeApplied = false
    end
    restoreExposure()
    restoreEnhancedLighting()
    LightingManager.ExposureApplied = false
    LightingManager.EnhancedApplied = false
end

--============================================================
-- 18 / ATMOSPHERE AND CLOUD MANAGER
--============================================================

local AtmosphereManager = {
    Atmosphere = nil,
    AtmosphereOwned = false,
    AtmosphereApplied = false,
    AtmosphereAvailable = true,
    Clouds = nil,
    CloudsOwned = false,
    CloudsApplied = false,
    CloudsAvailable = Terrain ~= nil,
    UpdateAccumulator = 0,
    WarnedAtmosphere = false,
    WarnedClouds = false,
}

local function configureOwnedAtmosphere(object)
    object.Density = clamp(S.atmosphereDensity, 0, 1)
    object.Haze = clamp(S.atmosphereHaze, 0, 10)
    object.Glare = clamp(S.atmosphereGlare, 0, 10)
    object.Color = S.atmosphereColor
    object.Decay = Color3.fromRGB(106, 119, 140)
    object.Offset = 0
end

local function ensureAtmosphere()
    local current = AtmosphereManager.Atmosphere
    if current and current.Parent then
        return current
    end

    local existing = Lighting:FindFirstChildOfClass("Atmosphere")
    if existing then
        AtmosphereManager.Atmosphere = existing
        AtmosphereManager.AtmosphereOwned = false
        if not AtmosphereOriginal then
            AtmosphereOriginal = snapshotAtmosphere(existing)
        end
        return existing
    end

    if not AtmosphereManager.AtmosphereAvailable then
        return nil
    end

    local ok, object = pcall(function()
        return Instance.new("Atmosphere")
    end)
    if not ok or not object then
        AtmosphereManager.AtmosphereAvailable = false
        if not AtmosphereManager.WarnedAtmosphere then
            AtmosphereManager.WarnedAtmosphere = true
            Notify(
                "Atmosphere",
                "The Atmosphere class could not be created in this environment.",
                "warning"
            )
        end
        return nil
    end

    object.Name = PREFIX .. "Atmosphere"
    configureOwnedAtmosphere(object)
    object.Parent = Lighting
    AtmosphereManager.Atmosphere = object
    AtmosphereManager.AtmosphereOwned = true
    return object
end

local function ensureClouds()
    if not Terrain then
        AtmosphereManager.CloudsAvailable = false
        return nil
    end
    local current = AtmosphereManager.Clouds
    if current and current.Parent then
        return current
    end

    local existing = Terrain:FindFirstChildOfClass("Clouds")
    if existing then
        AtmosphereManager.Clouds = existing
        AtmosphereManager.CloudsOwned = false
        if not CloudOriginal then
            CloudOriginal = snapshotClouds(existing)
        end
        return existing
    end

    if not AtmosphereManager.CloudsAvailable then
        return nil
    end

    local ok, object = pcall(function()
        return Instance.new("Clouds")
    end)
    if not ok or not object then
        AtmosphereManager.CloudsAvailable = false
        if not AtmosphereManager.WarnedClouds then
            AtmosphereManager.WarnedClouds = true
            Notify(
                "Clouds",
                "Dynamic Clouds could not be created in this environment.",
                "warning"
            )
        end
        return nil
    end

    object.Name = PREFIX .. "Clouds"
    object.Enabled = true
    object.Cover = clamp(S.cloudCover, 0, 1)
    object.Density = clamp(S.cloudDensity, 0, 1)
    object.Color = S.cloudColor
    object.Parent = Terrain
    AtmosphereManager.Clouds = object
    AtmosphereManager.CloudsOwned = true
    return object
end

local function restoreAtmosphereManaged()
    local object = AtmosphereManager.Atmosphere
    if AtmosphereManager.AtmosphereOwned then
        if object then object:Destroy() end
        AtmosphereManager.Atmosphere = nil
    elseif object and object.Parent and AtmosphereOriginal then
        restoreAtmosphereSnapshot(object, AtmosphereOriginal)
        AtmosphereManager.Atmosphere = nil
    end
    AtmosphereManager.AtmosphereOwned = false
    AtmosphereManager.AtmosphereApplied = false
end

local function restoreCloudsManaged()
    local object = AtmosphereManager.Clouds
    if AtmosphereManager.CloudsOwned then
        if object then object:Destroy() end
        AtmosphereManager.Clouds = nil
    elseif object and object.Parent and CloudOriginal then
        restoreCloudSnapshot(object, CloudOriginal)
        AtmosphereManager.Clouds = nil
    end
    AtmosphereManager.CloudsOwned = false
    AtmosphereManager.CloudsApplied = false
end

function AtmosphereManager.Update(dt)
    local allowed = S.effectsEnabled and not Runtime.Compare and not Runtime.Closed

    if not allowed or not S.atmosphereEnabled then
        if AtmosphereManager.AtmosphereApplied then
            restoreAtmosphereManaged()
        end
    end
    if not allowed or not S.cloudsEnabled then
        if AtmosphereManager.CloudsApplied then
            restoreCloudsManaged()
        end
    end
    if not allowed then
        return
    end
    if not S.atmosphereEnabled and not S.cloudsEnabled then
        return
    end

    AtmosphereManager.UpdateAccumulator += dt
    local interval = getQualityProfile().atmosphereInterval
    if AtmosphereManager.UpdateAccumulator < interval then
        return
    end
    local step = AtmosphereManager.UpdateAccumulator
    AtmosphereManager.UpdateAccumulator = 0

    local mix = Weather.GetMix()
    local rain = clamp01(mix.Rain)
    local snow = clamp01(mix.Snow)
    local fog = clamp01(mix.Fog)
    local overcast = clamp01(mix.Overcast)
    local hour = S.timeOverride and S.clockTime or Lighting.ClockTime
    local day, warm = solarFactors(hour)
    local cloudiness = Weather.GetCloudiness()
    local weatherStrength = S.weatherResponsive and 1 or 0

    if S.atmosphereEnabled then
        local atmosphere = ensureAtmosphere()
        if atmosphere then
            local targetDensity = S.atmosphereDensity
            local targetHaze = S.atmosphereHaze
            local targetGlare = S.atmosphereGlare
            local targetColor = S.atmosphereColor

            if weatherStrength > 0 then
                targetDensity = targetDensity
                    + 0.075 * rain
                    + 0.035 * snow
                    + 0.20 * fog
                    + 0.10 * overcast
                targetHaze = targetHaze
                    + 0.75 * rain
                    + 0.40 * snow
                    + 1.75 * fog
                    + 0.90 * overcast
                targetGlare = targetGlare
                    + (0.22 * day + 0.11 * warm) * (1 - 0.70 * cloudiness)
                targetColor = lerpColor(
                    targetColor,
                    Color3.fromRGB(235, 199, 170),
                    warm * 0.20
                )
                targetColor = lerpColor(
                    targetColor,
                    Color3.fromRGB(166, 186, 207),
                    rain * 0.27 + fog * 0.14 + overcast * 0.18
                )
            end

            atmosphere.Density = expLerp(
                atmosphere.Density,
                clamp(targetDensity, 0, 1),
                0.9,
                step
            )
            atmosphere.Haze = expLerp(
                atmosphere.Haze,
                clamp(targetHaze, 0, 10),
                0.9,
                step
            )
            atmosphere.Glare = expLerp(
                atmosphere.Glare,
                clamp(targetGlare, 0, 10),
                0.9,
                step
            )
            atmosphere.Color = lerpColor(
                atmosphere.Color,
                targetColor,
                1 - math.exp(-0.9 * step)
            )
            AtmosphereManager.AtmosphereApplied = true
        end
    end

    if S.cloudsEnabled then
        local clouds = ensureClouds()
        if clouds then
            local storm = S.weatherResponsive
                and clamp01(math.max(rain, snow * 0.82, fog * 0.52, overcast))
                or 0
            local coverTarget = clamp(
                S.cloudCover + (0.92 - S.cloudCover) * storm,
                0,
                1
            )
            local densityTarget = clamp(
                S.cloudDensity + (0.82 - S.cloudDensity) * storm,
                0,
                1
            )
            local cloudColorTarget = S.cloudColor
            if S.weatherResponsive then
                cloudColorTarget = lerpColor(
                    cloudColorTarget,
                    Color3.fromRGB(126, 140, 156),
                    rain * 0.58 + overcast * 0.34
                )
                cloudColorTarget = lerpColor(
                    cloudColorTarget,
                    Color3.fromRGB(216, 229, 242),
                    snow * 0.56
                )
            end
            clouds.Cover = expLerp(clouds.Cover, coverTarget, 0.55, step)
            clouds.Density = expLerp(clouds.Density, densityTarget, 0.55, step)
            clouds.Color = lerpColor(
                clouds.Color,
                cloudColorTarget,
                1 - math.exp(-0.55 * step)
            )
            clouds.Enabled = true
            AtmosphereManager.CloudsApplied = true
        end
    end
end

function AtmosphereManager.GetStatus()
    return {
        AtmosphereOwned = AtmosphereManager.AtmosphereOwned,
        AtmosphereActive = AtmosphereManager.AtmosphereApplied,
        AtmosphereAvailable = AtmosphereManager.AtmosphereAvailable,
        CloudsOwned = AtmosphereManager.CloudsOwned,
        CloudsActive = AtmosphereManager.CloudsApplied,
        CloudsAvailable = AtmosphereManager.CloudsAvailable,
    }
end

function AtmosphereManager.Restore()
    restoreAtmosphereManaged()
    restoreCloudsManaged()
    if ExistingAtmosphere and ExistingAtmosphere.Parent and AtmosphereOriginal then
        restoreAtmosphereSnapshot(ExistingAtmosphere, AtmosphereOriginal)
    end
    if ExistingClouds and ExistingClouds.Parent and CloudOriginal then
        restoreCloudSnapshot(ExistingClouds, CloudOriginal)
    end
end

--============================================================
-- 19 / PERSONAL AUDIO ENGINE
--============================================================

local AudioManager = {
    Folder = nil,
    Sound = nil,
    EQ = nil,
    Reverb = nil,
    Queue = {},
    QueueIndex = nil,
    LoadingToken = 0,
    Connections = {},
    Status = "Idle",
    Error = nil,
    Title = "No track loaded",
    Source = nil,
    Loading = false,
}

local function audioConnect(signal, callback)
    local connection = signal:Connect(callback)
    table.insert(AudioManager.Connections, connection)
    return connection
end

local function buildAudioInstances()
    local folder = Instance.new("Folder")
    folder.Name = PREFIX .. "AudioFolder"
    folder.Parent = SoundService
    AudioManager.Folder = folder

    local sound = Instance.new("Sound")
    sound.Name = PREFIX .. "Audio"
    sound.Volume = S.audioVolume
    sound.Looped = S.audioLoop
    sound.Parent = folder
    AudioManager.Sound = sound

    local eq = Instance.new("EqualizerSoundEffect")
    eq.Name = PREFIX .. "IndoorEQ"
    eq.LowGain = 0
    eq.MidGain = 0
    eq.HighGain = 0
    eq.Parent = sound
    AudioManager.EQ = eq

    local reverb = Instance.new("ReverbSoundEffect")
    reverb.Name = PREFIX .. "IndoorReverb"
    reverb.DryLevel = 0
    reverb.WetLevel = -80
    reverb.Density = 0.75
    reverb.Diffusion = 0.8
    reverb.DecayTime = 0.8
    reverb.Parent = sound
    AudioManager.Reverb = reverb

    audioConnect(sound.Loaded, function()
        if not AudioManager.Sound then return end
        AudioManager.Loading = false
        AudioManager.Error = nil
        AudioManager.Status = sound.IsPlaying and "Playing" or "Paused"
        Events.AudioChanged:Fire()
    end)

    audioConnect(sound.Ended, function()
        if not AudioManager.Sound then return end
        if AudioManager.Loading then return end
        AudioManager.Status = "Ended"
        Events.AudioChanged:Fire()
        if not S.audioLoop and #AudioManager.Queue > 0 then
            task.defer(function()
                AudioManager.Next()
            end)
        end
    end)

end

buildAudioInstances()

local function resolveAudioSource(source)
    source = tostring(source or ""):match("^%s*(.-)%s*$")
    if source == "" then
        return nil, nil, "Enter a local audio path or Roblox audio asset ID."
    end

    local lower = source:lower()
    local isLocal = lower:match("%.mp3$")
        or lower:match("%.wav$")
        or lower:match("%.ogg$")
        or lower:match("%.flac$")
        or lower:match("%.m4a$")
        or lower:match("%.aac$")

    if isLocal then
        if type(GetCustomAsset) ~= "function" then
            return nil, nil, "getcustomasset is unavailable in this execution environment."
        end
        local ok, asset = pcall(GetCustomAsset, source)
        if not ok or type(asset) ~= "string" or #asset == 0 then
            return nil, nil, "The local audio file could not be registered: " .. tostring(asset)
        end
        return asset, basename(source), nil
    end

    local id = source:match("rbxassetid://(%d+)")
        or source:match("^%s*(%d+)%s*$")
        or source:match("[?&]id=(%d+)")
    if not id then
        return nil, nil, "Invalid source. Use a local audio file path or a Roblox audio asset ID."
    end
    return "rbxassetid://" .. id, "Roblox audio #" .. id, nil
end

function AudioManager.NotifyChanged()
    Events.AudioChanged:Fire()
end

function AudioManager.PlaySource(source, queueIndex)
    local asset, title, err = resolveAudioSource(source)
    if not asset then
        AudioManager.Error = err
        AudioManager.Status = "Error"
        AudioManager.Loading = false
        Events.AudioChanged:Fire()
        return false, err
    end

    local sound = AudioManager.Sound
    if not sound then
        return false, "Audio engine is unavailable."
    end

    pcall(function() sound:Stop() end)
    AudioManager.LoadingToken += 1
    local token = AudioManager.LoadingToken
    AudioManager.Source = source
    AudioManager.Title = title
    AudioManager.Error = nil
    AudioManager.Loading = true
    AudioManager.Status = "Loading"
    AudioManager.QueueIndex = queueIndex
    sound.SoundId = asset
    sound.Volume = S.audioVolume
    sound.Looped = S.audioLoop
    sound.TimePosition = 0
    Events.AudioChanged:Fire()

    local ok, playError = pcall(function()
        sound:Play()
    end)
    if not ok then
        AudioManager.Loading = false
        AudioManager.Status = "Error"
        AudioManager.Error = tostring(playError)
        Events.AudioChanged:Fire()
        return false, AudioManager.Error
    end

    if sound.IsLoaded or sound.TimeLength > 0 then
        AudioManager.Loading = false
        AudioManager.Status = sound.IsPlaying and "Playing" or "Paused"
        Events.AudioChanged:Fire()
    end

    task.delay(8, function()
        if token ~= AudioManager.LoadingToken then return end
        if not AudioManager.Loading or not AudioManager.Sound then return end
        local sound = AudioManager.Sound
        if sound.TimeLength <= 0 and not sound.IsLoaded and not sound.IsPlaying then
            AudioManager.Loading = false
            AudioManager.Status = "Error"
            AudioManager.Error = "The asset is taking too long to load. It may be private, invalid, or unavailable."
            Events.AudioChanged:Fire()
        elseif AudioManager.Loading then
            AudioManager.Loading = false
            AudioManager.Status = sound.IsPlaying and "Playing" or "Paused"
            Events.AudioChanged:Fire()
        end
    end)

    return true
end

function AudioManager.Stop()
    local sound = AudioManager.Sound
    if not sound then return end
    pcall(function()
        sound:Stop()
        sound.TimePosition = 0
    end)
    AudioManager.LoadingToken += 1
    AudioManager.Loading = false
    AudioManager.Status = "Stopped"
    AudioManager.Error = nil
    Events.AudioChanged:Fire()
end

function AudioManager.TogglePlay()
    local sound = AudioManager.Sound
    if not sound or sound.SoundId == "" then
        return false, "No track is loaded."
    end
    if sound.IsPlaying then
        pcall(function() sound:Pause() end)
        AudioManager.Status = "Paused"
        Events.AudioChanged:Fire()
        return true
    end
    if sound.TimeLength > 0 and sound.TimePosition >= sound.TimeLength - 0.05 then
        sound.TimePosition = 0
    end
    local ok, err = pcall(function()
        sound:Resume()
    end)
    if not ok then
        local okPlay, playErr = pcall(function()
            sound:Play()
        end)
        if not okPlay then
            AudioManager.Error = tostring(playErr)
            AudioManager.Status = "Error"
            Events.AudioChanged:Fire()
            return false, AudioManager.Error
        end
    end
    AudioManager.Status = "Playing"
    Events.AudioChanged:Fire()
    return true
end

function AudioManager.Seek(seconds)
    local sound = AudioManager.Sound
    if not sound then return end
    local duration = sound.TimeLength
    if duration <= 0 then return end
    sound.TimePosition = clamp(seconds, 0, duration)
    Events.AudioChanged:Fire()
end

function AudioManager.SetVolume(value)
    S.audioVolume = clamp01(value)
    if AudioManager.Sound then
        AudioManager.Sound.Volume = S.audioVolume
    end
    Events.AudioChanged:Fire()
end

function AudioManager.SetLoop(value)
    S.audioLoop = value == true
    if AudioManager.Sound then
        AudioManager.Sound.Looped = S.audioLoop
    end
    Events.AudioChanged:Fire()
end

function AudioManager.AddToQueue(source)
    if #AudioManager.Queue >= 40 then
        return false, "The queue is limited to 40 tracks."
    end
    local asset, title, err = resolveAudioSource(source)
    if not asset then
        return false, err
    end
    table.insert(AudioManager.Queue, {
        source = source,
        asset = asset,
        title = title,
    })
    Events.AudioChanged:Fire()
    return true, title
end

function AudioManager.RemoveQueueAt(index)
    if not AudioManager.Queue[index] then return end
    table.remove(AudioManager.Queue, index)
    if AudioManager.QueueIndex then
        if index < AudioManager.QueueIndex then
            AudioManager.QueueIndex -= 1
        elseif index == AudioManager.QueueIndex then
            AudioManager.QueueIndex = nil
        end
    end
    Events.AudioChanged:Fire()
end

function AudioManager.ClearQueue()
    AudioManager.Queue = {}
    AudioManager.QueueIndex = nil
    Events.AudioChanged:Fire()
end

function AudioManager.PlayQueueIndex(index)
    local entry = AudioManager.Queue[index]
    if not entry then
        return false, "No queue entry at that position."
    end
    return AudioManager.PlaySource(entry.source, index)
end

function AudioManager.Next()
    if #AudioManager.Queue == 0 then
        return false, "The queue is empty."
    end
    local nextIndex = (AudioManager.QueueIndex or 0) + 1
    if nextIndex > #AudioManager.Queue then
        nextIndex = 1
    end
    return AudioManager.PlayQueueIndex(nextIndex)
end

function AudioManager.Previous()
    if #AudioManager.Queue == 0 then
        return false, "The queue is empty."
    end
    local previousIndex = (AudioManager.QueueIndex or 1) - 1
    if previousIndex < 1 then
        previousIndex = #AudioManager.Queue
    end
    return AudioManager.PlayQueueIndex(previousIndex)
end

function AudioManager.Update(dt)
    if not AudioManager.Sound or not AudioManager.EQ or not AudioManager.Reverb then
        return
    end

    local indoor = clamp01(Environment.Indoor)
    local wall = clamp01(Environment.Wall)
    local roomFactor = clamp01(indoor * (0.30 + wall * 0.70))
    local muffle = S.indoorMuffling and indoor * S.muffleStrength or 0
    local highTarget = -18 * muffle
    local midTarget = -5 * muffle
    local lowTarget = -1.25 * muffle

    AudioManager.EQ.HighGain = expLerp(
        AudioManager.EQ.HighGain,
        highTarget,
        3.0,
        dt
    )
    AudioManager.EQ.MidGain = expLerp(
        AudioManager.EQ.MidGain,
        midTarget,
        3.0,
        dt
    )
    AudioManager.EQ.LowGain = expLerp(
        AudioManager.EQ.LowGain,
        lowTarget,
        3.0,
        dt
    )

    local reverbFactor = S.indoorReverb
        and roomFactor * S.reverbStrength
        or 0
    local wetTarget = -80 + 54 * reverbFactor
    AudioManager.Reverb.WetLevel = expLerp(
        AudioManager.Reverb.WetLevel,
        wetTarget,
        2.6,
        dt
    )
    AudioManager.Reverb.DecayTime = expLerp(
        AudioManager.Reverb.DecayTime,
        clamp(0.55 + Environment.RoomSize * 2.1, 0.4, 2.8),
        2.0,
        dt
    )
end

function AudioManager.GetQueue()
    return AudioManager.Queue
end

function AudioManager.GetQueueIndex()
    return AudioManager.QueueIndex
end

function AudioManager.GetPosition()
    if not AudioManager.Sound then return 0 end
    return AudioManager.Sound.TimePosition or 0
end

function AudioManager.GetDuration()
    if not AudioManager.Sound then return 0 end
    return AudioManager.Sound.TimeLength or 0
end

function AudioManager.IsPlaying()
    return AudioManager.Sound and AudioManager.Sound.IsPlaying or false
end

function AudioManager.Destroy()
    for _, connection in ipairs(AudioManager.Connections) do
        pcall(function() connection:Disconnect() end)
    end
    AudioManager.Connections = {}
    if AudioManager.Sound then
        pcall(function() AudioManager.Sound:Stop() end)
    end
    if AudioManager.Folder then
        AudioManager.Folder:Destroy()
        AudioManager.Folder = nil
        AudioManager.Sound = nil
        AudioManager.EQ = nil
        AudioManager.Reverb = nil
    end
end

--============================================================
-- 20 / CAMERA MANAGER
--============================================================

local CameraManager = {
    Entries = {},
    CurrentCamera = nil,
}

local function cameraEntry(camera)
    for _, entry in ipairs(CameraManager.Entries) do
        if entry.camera == camera then
            return entry
        end
    end
    local entry = {
        camera = camera,
        fieldOfView = camera.FieldOfView,
    }
    table.insert(CameraManager.Entries, entry)
    return entry
end

function CameraManager.Restore()
    for _, entry in ipairs(CameraManager.Entries) do
        local camera = entry.camera
        if camera and camera.Parent then
            pcall(function()
                camera.FieldOfView = entry.fieldOfView
            end)
        end
    end
    CameraManager.Entries = {}
end

function CameraManager.Update(dt)
    local camera = Workspace.CurrentCamera
    if CameraManager.CurrentCamera ~= camera then
        CameraManager.Restore()
        CameraManager.CurrentCamera = camera
    end

    local allowed = S.effectsEnabled and not Runtime.Compare and not Runtime.Closed
    if not allowed or not S.fovEnabled or not camera then
        if #CameraManager.Entries > 0 then
            CameraManager.Restore()
        end
        return
    end

    local entry = cameraEntry(camera)
    local target = clamp(S.fov, 40, 120)
    camera.FieldOfView = expLerp(camera.FieldOfView, target, 5.0, dt)
    entry.fieldOfView = entry.fieldOfView or camera.FieldOfView
end

--============================================================
-- 21 / CONTROL DEFINITIONS
--============================================================

local Controls = {}
local ControlOrder = {}

local function defaultFormat(value, def)
    local decimals = def.decimals or 2
    return string.format("%." .. tostring(decimals) .. "f", value)
end

local function coerceControlValue(def, value)
    if def.kind == "slider" then
        local number = tonumber(value)
        if not isFiniteNumber(number) then
            number = def:Get()
        end
        if def.min and def.max then
            number = clamp(number, def.min, def.max)
        end
        if def.step then
            number = roundToStep(number, def.step)
        end
        if def.decimals then
            local multiplier = 10 ^ def.decimals
            number = math.floor(number * multiplier + 0.5) / multiplier
        end
        return number
    elseif def.kind == "toggle" then
        return value == true
    elseif def.kind == "color" then
        if typeof(value) == "Color3" then
            return value
        end
        return def:Get()
    elseif def.kind == "select" then
        for _, option in ipairs(def.options or {}) do
            if option == value then
                return value
            end
        end
        return def:Get()
    end
    return value
end

local function makeControl(def)
    def._bindings = {}
    def.get = def.get or function()
        return S[def.key]
    end
    def.setter = def.setter or function(value)
        S[def.key] = value
    end
    def.format = def.format or function(value)
        return defaultFormat(value, def)
    end

    function def:Get()
        return self.get()
    end

    function def:Set(value, silent)
        local coerced = coerceControlValue(self, value)
        self.setter(coerced)
        for binding in pairs(self._bindings) do
            pcall(binding, self:Get())
        end
        if not silent then
            Events.ControlChanged:Fire(self)
        end
    end

    function def:Refresh()
        local value = self:Get()
        for binding in pairs(self._bindings) do
            pcall(binding, value)
        end
    end

    function def:Bind(callback)
        if type(callback) ~= "function" then
            return { Disconnect = function() end }
        end
        self._bindings[callback] = true
        pcall(callback, self:Get())
        return {
            Disconnect = function()
                self._bindings[callback] = nil
            end,
        }
    end

    function def:IsVisible()
        if self.visibleIf then
            local ok, result = pcall(self.visibleIf)
            return ok and result == true
        end
        return true
    end

    function def:IsDisabled()
        if self.disabledIf then
            local ok, result = pcall(self.disabledIf)
            return ok and result == true
        end
        return false
    end

    Controls[def.id] = def
    table.insert(ControlOrder, def)
    return def
end

local function sliderControl(id, page, title, description, key, minimum, maximum, step, decimals, options)
    options = options or {}
    return makeControl({
        id = id,
        kind = "slider",
        page = page,
        title = title,
        description = description,
        key = key,
        min = minimum,
        max = maximum,
        step = step,
        decimals = decimals,
        format = options.format,
        visibleIf = options.visibleIf,
        affectsPreset = options.affectsPreset ~= false,
        setter = options.setter,
        keywords = options.keywords,
    })
end

local function toggleControl(id, page, title, description, key, options)
    options = options or {}
    return makeControl({
        id = id,
        kind = "toggle",
        page = page,
        title = title,
        description = description,
        key = key,
        visibleIf = options.visibleIf,
        disabledIf = options.disabledIf,
        affectsPreset = options.affectsPreset ~= false,
        setter = options.setter,
        keywords = options.keywords,
    })
end

local function colorControl(id, page, title, description, key, options)
    options = options or {}
    return makeControl({
        id = id,
        kind = "color",
        page = page,
        title = title,
        description = description,
        key = key,
        visibleIf = options.visibleIf,
        affectsPreset = options.affectsPreset ~= false,
        keywords = options.keywords,
    })
end

local function selectControl(id, page, title, description, key, options, controlOptions)
    controlOptions = controlOptions or {}
    return makeControl({
        id = id,
        kind = "select",
        page = page,
        title = title,
        description = description,
        key = key,
        options = options,
        visibleIf = controlOptions.visibleIf,
        affectsPreset = controlOptions.affectsPreset ~= false,
        setter = controlOptions.setter,
        keywords = controlOptions.keywords,
    })
end

-- Graphics ----------------------------------------------------

toggleControl(
    "fx.master",
    "Graphics",
    "Master visual engine",
    "Instantly bypass or restore every visual enhancement owned by Visual Control. Gameplay and game audio are never changed.",
    "effectsEnabled",
    { keywords = "disable bypass enable compare effects" }
)

sliderControl(
    "fx.bloom",
    "Graphics",
    "Bloom intensity",
    "Strength of the glow around bright areas. Higher values create a softer, more cinematic image.",
    "bloom",
    0, 1.5, 0.01, 2,
    { keywords = "glow light halo" }
)

sliderControl(
    "fx.bloomSize",
    "Graphics",
    "Bloom spread",
    "Controls how widely bloom spreads from bright highlights.",
    "bloomSize",
    8, 48, 1, 0,
    { keywords = "glow radius spread" }
)

sliderControl(
    "fx.bloomThreshold",
    "Graphics",
    "Bloom threshold",
    "Brightness required before an area begins to bloom.",
    "bloomThreshold",
    0.5, 2, 0.01, 2,
    { keywords = "glow cutoff" }
)

sliderControl(
    "fx.contrast",
    "Graphics",
    "Contrast",
    "Separates dark and bright tones. Negative values flatten the image.",
    "contrast",
    -0.5, 0.5, 0.01, 2,
    { format = function(value) return string.format("%+.2f", value) end }
)

sliderControl(
    "fx.brightness",
    "Graphics",
    "Image brightness",
    "Adds or removes brightness through Visual Control's own color correction.",
    "brightness",
    -0.2, 0.2, 0.005, 3,
    { format = function(value) return string.format("%+.3f", value) end }
)

sliderControl(
    "fx.saturation",
    "Graphics",
    "Saturation",
    "Adjusts color richness independently of the game's own post-processing.",
    "saturation",
    -0.5, 0.5, 0.01, 2,
    { format = function(value) return string.format("%+.2f", value) end }
)

colorControl(
    "fx.tint",
    "Graphics",
    "Color tint",
    "A global tint applied by Visual Control's owned ColorCorrection effect.",
    "tint",
    { keywords = "color grade white balance temperature" }
)

toggleControl(
    "fx.sunRays",
    "Graphics",
    "Sun rays",
    "Creates subtle visible light rays around the sun. Automatically weakens in cloudy weather.",
    "sunRaysEnabled",
    { keywords = "god rays sunlight" }
)

sliderControl(
    "fx.sunRaysIntensity",
    "Graphics",
    "Sun ray intensity",
    "Maximum sun-ray strength in clear daylight.",
    "sunRaysIntensity",
    0, 0.2, 0.005, 3,
    {
        visibleIf = function() return S.sunRaysEnabled end,
        keywords = "god rays strength",
    }
)

toggleControl(
    "fx.vignette",
    "Graphics",
    "Screen vignette",
    "A subtle, non-interactive edge darkening overlay. It never blocks input.",
    "vignetteEnabled",
    { keywords = "edge dark cinematic" }
)

sliderControl(
    "fx.vignetteStrength",
    "Graphics",
    "Vignette strength",
    "Controls how much the screen edges are darkened.",
    "vignetteStrength",
    0, 0.7, 0.01, 2,
    { visibleIf = function() return S.vignetteEnabled end }
)

-- Camera ------------------------------------------------------

toggleControl(
    "camera.fovEnabled",
    "Camera",
    "Field of view override",
    "Overrides the client camera FOV. The original camera FOV is restored when disabled or when the application exits.",
    "fovEnabled",
    { keywords = "fov lens camera zoom" }
)

sliderControl(
    "camera.fov",
    "Camera",
    "Field of view",
    "A wider view shows more of the scene; a narrower view feels more cinematic.",
    "fov",
    40, 120, 1, 0,
    {
        visibleIf = function() return S.fovEnabled end,
        format = function(value) return string.format("%.0f°", value) end,
        keywords = "fov camera zoom",
    }
)

toggleControl(
    "camera.dofEnabled",
    "Camera",
    "Depth of field",
    "Blurs distant or close geometry to suggest a camera lens. This is a visual effect and does not change gameplay.",
    "dofEnabled",
    { keywords = "dof blur focus cinematic" }
)

sliderControl(
    "camera.dofFocus",
    "Camera",
    "Focus distance",
    "Approximate distance in studs that remains sharp.",
    "dofFocus",
    5, 300, 1, 0,
    {
        visibleIf = function() return S.dofEnabled end,
        format = function(value) return string.format("%.0f st", value) end,
        keywords = "dof focus distance",
    }
)

sliderControl(
    "camera.dofRadius",
    "Camera",
    "In-focus radius",
    "The size of the sharp region around the focus distance.",
    "dofRadius",
    2, 100, 1, 0,
    {
        visibleIf = function() return S.dofEnabled end,
        format = function(value) return string.format("%.0f st", value) end,
    }
)

sliderControl(
    "camera.dofFar",
    "Camera",
    "Far blur intensity",
    "Blur strength beyond the in-focus region.",
    "dofFar",
    0, 1, 0.01, 2,
    { visibleIf = function() return S.dofEnabled end }
)

sliderControl(
    "camera.dofNear",
    "Camera",
    "Near blur intensity",
    "Blur strength between the camera and the in-focus region.",
    "dofNear",
    0, 1, 0.01, 2,
    { visibleIf = function() return S.dofEnabled end }
)

-- Lighting ----------------------------------------------------

toggleControl(
    "lighting.timeOverride",
    "Lighting",
    "Time of day override",
    "Locks the local lighting clock to your selected time. Disabling it restores the original time snapshot.",
    "timeOverride",
    { keywords = "clock time day night" }
)

sliderControl(
    "lighting.clockTime",
    "Lighting",
    "Time of day",
    "Selected local clock time. Enable the override above to apply it.",
    "clockTime",
    0, 24, 0.1, 1,
    {
        format = function(value) return timeOfDayLabel(value) end,
        keywords = "clock hour sunrise sunset",
    }
)

toggleControl(
    "lighting.adaptiveExposure",
    "Lighting",
    "Adaptive eye exposure",
    "Heuristically adjusts local exposure as you move between bright, sheltered, and enclosed spaces. This does not read the framebuffer.",
    "adaptiveExposure",
    { keywords = "eye adaptation exposure darkness" }
)

sliderControl(
    "lighting.adaptationSpeed",
    "Lighting",
    "Adaptation speed",
    "How quickly eye adaptation responds to environmental changes.",
    "adaptationSpeed",
    0.2, 3, 0.05, 2,
    {
        visibleIf = function() return S.adaptiveExposure end,
        format = function(value) return string.format("%.2fx", value) end,
    }
)

sliderControl(
    "lighting.exposureBias",
    "Lighting",
    "Exposure bias",
    "A permanent local exposure offset applied on top of the original Lighting exposure.",
    "exposureBias",
    -1, 1, 0.01, 2,
    {
        format = function(value) return string.format("%+.2f", value) end,
        keywords = "brightness exposure",
    }
)

toggleControl(
    "lighting.autoGrade",
    "Lighting",
    "Weather color grading",
    "Blends the image toward warm, cool, stormy, or overcast tones based on time and weather.",
    "autoGrade",
    { keywords = "color grade weather time" }
)

sliderControl(
    "lighting.gradingStrength",
    "Lighting",
    "Grading strength",
    "Scales the automatic time-and-weather color response.",
    "gradingStrength",
    0, 1.5, 0.05, 2,
    {
        visibleIf = function() return S.autoGrade end,
        format = function(value) return string.format("%.2fx", value) end,
    }
)

toggleControl(
    "lighting.enhanced",
    "Lighting",
    "Enhanced environment light",
    "Gently lifts local diffuse and specular environment light while preserving the original values for restoration.",
    "enhancedLighting",
    { keywords = "ambient environment light illumination" }
)

-- Atmosphere --------------------------------------------------

toggleControl(
    "atmos.enabled",
    "Atmosphere",
    "Atmospheric scattering",
    "Uses Roblox Atmosphere to add depth, haze, and aerial perspective. Existing game atmosphere values are snapshotted and restored.",
    "atmosphereEnabled",
    { keywords = "atmosphere haze depth aerial" }
)

sliderControl(
    "atmos.density",
    "Atmosphere",
    "Atmosphere density",
    "Base particulate density before weather response.",
    "atmosphereDensity",
    0, 1, 0.01, 2,
    { visibleIf = function() return S.atmosphereEnabled end }
)

sliderControl(
    "atmos.haze",
    "Atmosphere",
    "Atmosphere haze",
    "Adds a soft veil to distant geometry.",
    "atmosphereHaze",
    0, 5, 0.05, 2,
    { visibleIf = function() return S.atmosphereEnabled end }
)

sliderControl(
    "atmos.glare",
    "Atmosphere",
    "Atmosphere glare",
    "Controls the glow around the sun and bright atmosphere regions.",
    "atmosphereGlare",
    0, 1, 0.01, 2,
    { visibleIf = function() return S.atmosphereEnabled end }
)

colorControl(
    "atmos.color",
    "Atmosphere",
    "Atmosphere color",
    "The base color used by the local Atmosphere object.",
    "atmosphereColor",
    {
        visibleIf = function() return S.atmosphereEnabled end,
        keywords = "atmosphere sky haze color",
    }
)

toggleControl(
    "atmos.weatherResponsive",
    "Atmosphere",
    "Weather-responsive atmosphere",
    "Adds extra haze and density during rain, snow, fog, and overcast conditions.",
    "weatherResponsive",
    {
        visibleIf = function() return S.atmosphereEnabled end,
        keywords = "weather atmosphere responsive",
    }
)

toggleControl(
    "clouds.enabled",
    "Atmosphere",
    "Dynamic clouds",
    "Enables Roblox's dynamic cloud layer. Existing Clouds objects are snapshotted and restored.",
    "cloudsEnabled",
    { keywords = "cloud sky coverage" }
)

sliderControl(
    "clouds.cover",
    "Atmosphere",
    "Cloud cover",
    "The base amount of sky covered by clouds.",
    "cloudCover",
    0, 1, 0.01, 2,
    { visibleIf = function() return S.cloudsEnabled end }
)

sliderControl(
    "clouds.density",
    "Atmosphere",
    "Cloud density",
    "The base particulate density of the cloud layer.",
    "cloudDensity",
    0, 1, 0.01, 2,
    { visibleIf = function() return S.cloudsEnabled end }
)

colorControl(
    "clouds.color",
    "Atmosphere",
    "Cloud color",
    "The base material color of the cloud layer.",
    "cloudColor",
    {
        visibleIf = function() return S.cloudsEnabled end,
        keywords = "cloud color",
    }
)

-- Weather -----------------------------------------------------

sliderControl(
    "weather.intensity",
    "Weather",
    "Weather intensity",
    "Scales precipitation density, haze, cloud response, and lightning timing.",
    "weatherIntensity",
    0.2, 2, 0.05, 2,
    {
        format = function(value) return string.format("%.2fx", value) end,
        keywords = "rain snow fog storm intensity",
    }
)

toggleControl(
    "weather.wind",
    "Weather",
    "Wind-driven precipitation",
    "Adds slowly varying local wind to Visual Control's rain and snow particles only.",
    "windEnabled",
    { keywords = "wind rain snow drift" }
)

toggleControl(
    "weather.shelter",
    "Weather",
    "Shelter-aware precipitation",
    "Gradually reduces local rain and snow when overhead geometry covers the character or camera.",
    "shelterDetection",
    { keywords = "rain shelter cover indoor" }
)

toggleControl(
    "weather.lightning",
    "Weather",
    "Lightning flashes",
    "Adds rare, low-intensity visual flashes during rain. Disabled by default and suppressed when reduced motion is enabled.",
    "lightningEnabled",
    { keywords = "lightning storm flash thunder" }
)

sliderControl(
    "weather.lightningIntensity",
    "Weather",
    "Lightning intensity",
    "Maximum brightness of the optional lightning flash overlay.",
    "lightningIntensity",
    0.1, 1, 0.05, 2,
    {
        visibleIf = function() return S.lightningEnabled end,
        format = function(value) return string.format("%.2f", value) end,
    }
)

-- Audio -------------------------------------------------------

sliderControl(
    "audio.volume",
    "Audio",
    "Music volume",
    "Volume of the Visual Control personal audio player only.",
    "audioVolume",
    0, 1, 0.01, 2,
    {
        setter = function(value)
            AudioManager.SetVolume(value)
        end,
        format = function(value) return string.format("%.0f%%", value * 100) end,
        affectsPreset = false,
        keywords = "volume music sound",
    }
)

toggleControl(
    "audio.loop",
    "Audio",
    "Loop current track",
    "Repeats the current personal audio track instead of advancing to the next queue entry.",
    "audioLoop",
    {
        setter = function(value)
            AudioManager.SetLoop(value)
        end,
        affectsPreset = false,
        keywords = "loop repeat music",
    }
)

toggleControl(
    "audio.muffling",
    "Audio",
    "Indoor music muffling",
    "Reduces high-frequency detail in the personal music player as you enter sheltered or enclosed spaces. No game audio is affected.",
    "indoorMuffling",
    { affectsPreset = false, keywords = "equalizer indoor muffled" }
)

toggleControl(
    "audio.reverb",
    "Audio",
    "Indoor music reverb",
    "Adds subtle enclosure-driven reverb to the personal music player only.",
    "indoorReverb",
    { affectsPreset = false, keywords = "reverb room acoustics" }
)

sliderControl(
    "audio.muffleStrength",
    "Audio",
    "Muffle strength",
    "Maximum equalizer attenuation in fully enclosed spaces.",
    "muffleStrength",
    0, 1, 0.01, 2,
    {
        visibleIf = function() return S.indoorMuffling end,
        affectsPreset = false,
    }
)

sliderControl(
    "audio.reverbStrength",
    "Audio",
    "Reverb strength",
    "Maximum wet-signal level for enclosed spaces.",
    "reverbStrength",
    0, 1, 0.01, 2,
    {
        visibleIf = function() return S.indoorReverb end,
        affectsPreset = false,
    }
)

-- Performance -------------------------------------------------

selectControl(
    "performance.quality",
    "Performance",
    "Quality profile",
    "Balances raycast frequency and precipitation density. Balanced is recommended.",
    "quality",
    { "Low", "Balanced", "High" },
    {
        affectsPreset = false,
        keywords = "quality performance low balanced high fps",
    }
)

-- Interface preferences --------------------------------------

toggleControl(
    "ui.reducedMotion",
    "Settings",
    "Reduced motion",
    "Shortens interface transitions and suppresses automatic lightning flashes.",
    "reducedMotion",
    {
        setter = function(value)
            S.reducedMotion = value
            Motion.Reduced = value
        end,
        affectsPreset = false,
        keywords = "accessibility animation motion",
    }
)

toggleControl(
    "ui.tooltips",
    "Settings",
    "Interface tooltips",
    "Shows helpful descriptions when hovering over controls and icon buttons.",
    "tooltips",
    {
        setter = function(value)
            S.tooltips = value
        end,
        affectsPreset = false,
        keywords = "help hints hover",
    }
)

toggleControl(
    "ui.quickDock",
    "Settings",
    "Quick dock",
    "Shows a compact dock at the bottom-right while the full application is hidden. If disabled, the configured keybind is the only way to reopen the window.",
    "quickDock",
    {
        setter = function(value)
            S.quickDock = value
        end,
        affectsPreset = false,
        keywords = "quick overlay dock minimize",
    }
)

toggleControl(
    "ui.rememberSettings",
    "Settings",
    "Remember preferences",
    "Stores visual settings, custom presets, favorites, and appearance choices using the executor's local filesystem APIs when available.",
    "rememberSettings",
    {
        disabledIf = function()
            return not Storage.Available
        end,
        affectsPreset = false,
        keywords = "save persistence config remember",
    }
)

for _, def in ipairs(ControlOrder) do
    if def.key and S[def.key] ~= nil then
        S[def.key] = coerceControlValue(def, S[def.key])
    end
end

local function findControl(id)
    return Controls[id]
end

local function isFavorite(id)
    for _, value in ipairs(Favorites) do
        if value == id then
            return true
        end
    end
    return false
end

--============================================================
-- 22 / INTERFACE FOUNDATION
--============================================================

local UI = {}
local Layout = {
    Scale = 1,
    BaseWidth = 1120,
    BaseHeight = 700,
    Collapsed = false,
    ForcedCollapse = false,
}
local Connections = {}
local Pages = {}
local NavItems = {}
local CurrentPage = "Dashboard"
local CurrentModal = nil
local CurrentDropdown = nil
local PageGeneration = 0
local PressedButtons = {}

local function connect(signal, callback)
    local connection = signal:Connect(callback)
    table.insert(Connections, connection)
    return connection
end

local function connectOwner(owner, signal, callback)
    local connection = signal:Connect(callback)
    local destroying = nil
    destroying = owner.Destroying:Connect(function()
        if connection then
            pcall(function() connection:Disconnect() end)
        end
        if destroying then
            pcall(function() destroying:Disconnect() end)
        end
    end)
    return connection
end

local function round(object, radius)
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, radius)
    corner.Parent = object
    return corner
end

local function addStroke(object, color, thickness, transparency)
    local stroke = Instance.new("UIStroke")
    stroke.Color = color or Theme.Border
    stroke.Thickness = thickness or 1
    stroke.Transparency = transparency or 0
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Parent = object
    return stroke
end

local function addPadding(object, left, right, top, bottom)
    local padding = Instance.new("UIPadding")
    padding.PaddingLeft = UDim.new(0, left or 0)
    padding.PaddingRight = UDim.new(0, right or 0)
    padding.PaddingTop = UDim.new(0, top or 0)
    padding.PaddingBottom = UDim.new(0, bottom or 0)
    padding.Parent = object
    return padding
end

local function addVerticalList(object, gap, horizontalAlignment)
    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Vertical
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0, gap or 0)
    layout.HorizontalAlignment = horizontalAlignment or Enum.HorizontalAlignment.Left
    layout.Parent = object
    return layout
end

local function clearGuiChildren(parent)
    if not parent then return end
    for _, child in ipairs(parent:GetChildren()) do
        if child:IsA("GuiObject") then
            child:Destroy()
        end
    end
end

local function addHorizontalList(object, gap, verticalAlignment)
    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Horizontal
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0, gap or 0)
    layout.VerticalAlignment = verticalAlignment or Enum.VerticalAlignment.Center
    layout.Parent = object
    return layout
end

local function createText(parent, text, size, color, font)
    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.BorderSizePixel = 0
    label.Text = text or ""
    label.TextColor3 = color or Theme.Text
    label.Font = font or Enum.Font.Gotham
    label.TextSize = size or 12
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextYAlignment = Enum.TextYAlignment.Center
    label.TextWrapped = false
    label.Parent = parent
    return label
end

local function createCanvas(parent, name)
    local canvas = Instance.new("CanvasGroup")
    canvas.Name = name or "Canvas"
    canvas.BackgroundTransparency = 1
    canvas.BorderSizePixel = 0
    canvas.Parent = parent
    return canvas
end

local Gui = Instance.new("ScreenGui")
Gui.Name = PREFIX .. "GUI"
Gui.IgnoreGuiInset = true
Gui.ResetOnSpawn = false
Gui.DisplayOrder = 100
Gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
Gui.Parent = PlayerGui

local WindowRoot = createCanvas(Gui, "WindowRoot")
WindowRoot.AnchorPoint = Vector2.new(0, 0)
WindowRoot.Position = UDim2.fromOffset(0, 0)
WindowRoot.Size = UDim2.fromOffset(1120, 700)
WindowRoot.ZIndex = 10
WindowRoot.GroupTransparency = 1

local WindowScale = Instance.new("UIScale")
WindowScale.Name = "ResponsiveScale"
WindowScale.Scale = 1
WindowScale.Parent = WindowRoot

local function createShadowLayer(name, yOffset, transparency, radius)
    local shadow = Instance.new("Frame")
    shadow.Name = name
    shadow.Position = UDim2.fromOffset(0, yOffset)
    shadow.Size = UDim2.fromScale(1, 1)
    shadow.BackgroundColor3 = Theme.Black
    shadow.BackgroundTransparency = transparency
    shadow.BorderSizePixel = 0
    shadow.ZIndex = 0
    shadow.Parent = WindowRoot
    round(shadow, radius)
    return shadow
end

createShadowLayer("ShadowFar", 18, 0.88, 18)
createShadowLayer("ShadowMid", 10, 0.76, 16)
createShadowLayer("ShadowNear", 4, 0.64, 15)

local Main = Instance.new("Frame")
Main.Name = "Main"
Main.Size = UDim2.fromScale(1, 1)
Main.BackgroundColor3 = Theme.Window
Main.BackgroundTransparency = 0
Main.BorderSizePixel = 0
Main.ClipsDescendants = true
Main.Active = true
Main.ZIndex = 2
Main.Parent = WindowRoot
round(Main, 14)
addStroke(Main, Theme.Border, 1, 0.25)

local ModalHost = Instance.new("Frame")
ModalHost.Name = "ModalHost"
ModalHost.Size = UDim2.fromScale(1, 1)
ModalHost.BackgroundTransparency = 1
ModalHost.BorderSizePixel = 0
ModalHost.Visible = false
ModalHost.ZIndex = 6000
ModalHost.Parent = WindowRoot

local PopupHost = Instance.new("Frame")
PopupHost.Name = "PopupHost"
PopupHost.Size = UDim2.fromScale(1, 1)
PopupHost.BackgroundTransparency = 1
PopupHost.BorderSizePixel = 0
PopupHost.Visible = false
PopupHost.ZIndex = 5000
PopupHost.Parent = WindowRoot

local Tooltip = {
    Label = nil,
    Enabled = S.tooltips,
    Token = 0,
}

do
    local label = Instance.new("TextLabel")
    label.Name = "Tooltip"
    label.BackgroundColor3 = Theme.CardRaised
    label.BackgroundTransparency = 0.02
    label.BorderSizePixel = 0
    label.Size = UDim2.fromOffset(252, 0)
    label.AutomaticSize = Enum.AutomaticSize.Y
    label.Position = UDim2.fromOffset(-1000, -1000)
    label.TextColor3 = Theme.Text
    label.Font = Enum.Font.Gotham
    label.TextSize = 11
    label.TextWrapped = true
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextYAlignment = Enum.TextYAlignment.Top
    label.Visible = false
    label.ZIndex = 9000
    label.Active = false
    label.Parent = Gui
    round(label, 7)
    addStroke(label, Theme.Border, 1, 0.15)
    addPadding(label, 10, 10, 8, 8)
    Tooltip.Label = label
end

function Tooltip.Hide()
    Tooltip.Token += 1
    if Tooltip.Label then
        Tooltip.Label.Visible = false
    end
end

function Tooltip.Show(text)
    if not Tooltip.Enabled or not text or text == "" or Runtime.Closed or not Runtime.Visible then
        return
    end
    local label = Tooltip.Label
    if not label then return end
    local mouse = UserInputService:GetMouseLocation()
    local viewport = Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize
        or Vector2.new(1280, 720)
    local width = math.min(252, math.max(150, viewport.X - 24))
    label.Size = UDim2.fromOffset(width, 0)
    label.Text = text
    local estimatedHeight = math.max(28, 16 + math.ceil(#text / 36) * 14)
    local x = mouse.X + 16
    local y = mouse.Y + 18
    if x + width > viewport.X - 10 then
        x = mouse.X - width - 14
    end
    if y + estimatedHeight > viewport.Y - 10 then
        y = mouse.Y - estimatedHeight - 12
    end
    label.Position = UDim2.fromOffset(x, y)
    label.Visible = true
end

function Tooltip.SetEnabled(enabled)
    Tooltip.Enabled = enabled == true
    if not Tooltip.Enabled then
        Tooltip.Hide()
    end
end

local function cancelKeyCaptureUI()
    if not Runtime.CapturingKey then return end
    Runtime.CapturingKey = false
    local refs = UI.SettingsRefs
    if refs and refs.KeybindButton then
        refs.KeybindButton.Text = "Change"
    end
    if refs and refs.KeybindValue then
        refs.KeybindValue.Text = keyDisplayName(S.keybindName)
    end
end

function Tooltip.Attach(object, text)
    if not object or not text then return end
    connectOwner(object, object.MouseEnter, function()
        if not Tooltip.Enabled or not Runtime.Visible then return end
        Tooltip.Token += 1
        local token = Tooltip.Token
        task.delay(0.55, function()
            if token ~= Tooltip.Token or not object.Parent then return end
            local resolved = type(text) == "function" and text() or text
            Tooltip.Show(resolved)
        end)
    end)
    connectOwner(object, object.MouseLeave, function()
        Tooltip.Hide()
    end)
end

--============================================================
-- 23 / CORE UI COMPONENTS
--============================================================

local Pointer = {
    Active = nil,
}

function Pointer.Begin(onMove, onEnd)
    if Pointer.Active and Pointer.Active.onEnd then
        pcall(Pointer.Active.onEnd)
    end
    Pointer.Active = {
        onMove = onMove,
        onEnd = onEnd,
    }
end

function Pointer.Cancel(notify)
    if not Pointer.Active then return end
    local active = Pointer.Active
    Pointer.Active = nil
    if notify and active.onEnd then
        pcall(active.onEnd)
    end
end

connect(UserInputService.InputChanged, function(input)
    if not Pointer.Active then return end
    if input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch then
        if Pointer.Active.onMove then
            pcall(Pointer.Active.onMove, input)
        end
    end
end)

connect(UserInputService.InputEnded, function(input)
    if input.UserInputType ~= Enum.UserInputType.MouseButton1
        and input.UserInputType ~= Enum.UserInputType.Touch then
        return
    end
    Pointer.Cancel(true)
    for button in pairs(PressedButtons) do
        local scale = button:FindFirstChildOfClass("UIScale")
        if scale then
            Motion.Tween(scale, { Scale = 1 }, 0.14)
        end
        PressedButtons[button] = nil
    end
end)

local function iconShape(parent, x, y, width, height, color, rotation, cornerRadius, strokeThickness)
    local shape = Instance.new("Frame")
    shape.AnchorPoint = Vector2.new(0.5, 0.5)
    shape.Position = UDim2.fromOffset(x, y)
    shape.Size = UDim2.fromOffset(width, height)
    shape.BackgroundColor3 = color
    shape.BorderSizePixel = 0
    shape.Rotation = rotation or 0
    shape.Active = false
    shape.Parent = parent
    if strokeThickness then
        shape.BackgroundTransparency = 1
        local stroke = addStroke(shape, color, strokeThickness, 0)
        if cornerRadius then
            round(shape, cornerRadius)
        end
        return shape, stroke
    end
    if cornerRadius then
        round(shape, cornerRadius)
    end
    return shape, nil
end

function UI.Icon(name, size, color, parent)
    size = size or 18
    color = color or Theme.TextSecondary
    local wrapper = Instance.new("Frame")
    wrapper.Name = "Icon_" .. tostring(name)
    wrapper.Size = UDim2.fromOffset(size, size)
    wrapper.BackgroundTransparency = 1
    wrapper.BorderSizePixel = 0
    wrapper.Active = false
    wrapper.Parent = parent

    local canvas = Instance.new("Frame")
    canvas.Size = UDim2.fromOffset(18, 18)
    canvas.BackgroundTransparency = 1
    canvas.BorderSizePixel = 0
    canvas.Active = false
    canvas.Parent = wrapper
    local scale = Instance.new("UIScale")
    scale.Scale = size / 18
    scale.Parent = canvas

    local shapes = {}
    local strokes = {}

    local function rect(x, y, width, height, rotation, cornerRadius)
        local shape, stroke = iconShape(
            canvas, x, y, width, height, color, rotation, cornerRadius, nil
        )
        table.insert(shapes, shape)
        return shape
    end

    local function ring(x, y, width, height, thickness)
        local shape, stroke = iconShape(
            canvas, x, y, width, height, color, 0, math.floor(math.min(width, height) / 2), thickness
        )
        table.insert(shapes, shape)
        table.insert(strokes, stroke)
        return shape
    end

    if name == "dashboard" then
        rect(4.5, 4.5, 6.5, 6.5, 0, 2)
        rect(13.5, 4.5, 6.5, 6.5, 0, 2)
        rect(4.5, 13.5, 6.5, 6.5, 0, 2)
        rect(13.5, 13.5, 6.5, 6.5, 0, 2)
    elseif name == "graphics" then
        for index, y in ipairs({ 4.5, 9, 13.5 }) do
            rect(9, y, 14, 1.4, 0, 1)
        end
        rect(12, 4.5, 3.8, 3.8, 0, 2)
        rect(5.5, 9, 3.8, 3.8, 0, 2)
        rect(10.5, 13.5, 3.8, 3.8, 0, 2)
    elseif name == "lighting" then
        ring(9, 9, 8.5, 8.5, 1.5)
        for index = 1, 8 do
            local angle = (index / 8) * math.pi * 2
            local distance = 7.2
            rect(
                9 + math.cos(angle) * distance,
                9 + math.sin(angle) * distance,
                1.4,
                2.6,
                math.deg(angle) + 90,
                1
            )
        end
    elseif name == "atmosphere" then
        rect(9, 5, 13, 1.3, 0, 1)
        rect(9, 9, 16, 1.3, 0, 1)
        rect(9, 13, 10, 1.3, 0, 1)
        rect(14.5, 5, 2, 2, 0, 1)
        rect(3.5, 9, 2, 2, 0, 1)
        rect(12, 13, 2, 2, 0, 1)
    elseif name == "weather" then
        rect(9, 11.5, 13, 3.2, 0, 2)
        rect(6.5, 9.5, 5.5, 5.5, 0, 3)
        rect(10.5, 8.5, 6.5, 6.5, 0, 3)
        rect(13.5, 10.5, 4.5, 4.5, 0, 2)
        rect(6, 16, 1.2, 2.2, 14, 1)
        rect(10, 16, 1.2, 2.2, 14, 1)
        rect(14, 16, 1.2, 2.2, 14, 1)
    elseif name == "camera" then
        rect(9, 10, 14.5, 9.5, 0, 2.5)
        rect(9, 4.2, 5, 2.2, 0, 1)
        ring(9, 10, 5.5, 5.5, 1.3)
        rect(14.8, 7.2, 1.5, 1.5, 0, 1)
    elseif name == "audio" then
        rect(3, 12, 2, 5, 0, 1)
        rect(7, 8.5, 2, 12, 0, 1)
        rect(11, 5.5, 2, 18, 0, 1)
        rect(15, 10, 2, 9, 0, 1)
    elseif name == "presets" then
        rect(8, 9.5, 8, 8, 45, 1)
        rect(14, 4.5, 3.2, 3.2, 45, 1)
        rect(4.5, 4.5, 1.6, 1.6, 0, 1)
    elseif name == "performance" then
        ring(9, 9.5, 12, 12, 1.5)
        rect(10.8, 7.2, 5.2, 1.4, -38, 1)
        rect(9, 9.5, 1.8, 1.8, 0, 1)
    elseif name == "settings" then
        rect(9, 4.5, 14, 1.4, 0, 1)
        rect(9, 9, 14, 1.4, 0, 1)
        rect(9, 13.5, 14, 1.4, 0, 1)
        rect(6, 4.5, 3.8, 3.8, 0, 2)
        rect(12, 9, 3.8, 3.8, 0, 2)
        rect(8, 13.5, 3.8, 3.8, 0, 2)
    elseif name == "search" then
        ring(8, 8, 9, 9, 1.5)
        rect(13.6, 13.6, 5, 1.5, 45, 1)
    elseif name == "close" then
        rect(9, 9, 11, 1.5, 45, 1)
        rect(9, 9, 11, 1.5, -45, 1)
    elseif name == "minimize" then
        rect(9, 9, 10, 1.5, 0, 1)
    elseif name == "restore" then
        rect(9, 9, 9, 1.5, 0, 1)
        rect(9, 9, 1.5, 9, 0, 1)
    elseif name == "chevron" then
        rect(7, 7, 5, 1.4, 45, 1)
        rect(7, 11, 5, 1.4, -45, 1)
    elseif name == "compare" then
        ring(9, 9, 11, 11, 1.5)
        rect(9, 9, 1.5, 8, 0, 1)
    elseif name == "lightning" then
        rect(10, 5.5, 1.6, 5, 28, 1)
        rect(8.2, 10.2, 4.2, 1.5, 15, 1)
        rect(8, 12.6, 1.6, 5, 28, 1)
    elseif name == "queue" then
        rect(9, 5, 12, 1.4, 0, 1)
        rect(9, 9, 12, 1.4, 0, 1)
        rect(9, 13, 12, 1.4, 0, 1)
        rect(3.5, 5, 1.8, 1.8, 0, 1)
        rect(3.5, 9, 1.8, 1.8, 0, 1)
        rect(3.5, 13, 1.8, 1.8, 0, 1)
    elseif name == "check" then
        rect(6.5, 9, 5, 1.5, 45, 1)
        rect(10.5, 11, 8, 1.5, -45, 1)
    end

    local iconObject = {
        Frame = wrapper,
        SetColor = function(newColor)
            for _, shape in ipairs(shapes) do
                shape.BackgroundColor3 = newColor
            end
            for _, stroke in ipairs(strokes) do
                if stroke then
                    stroke.Color = newColor
                end
            end
        end,
    }
    return iconObject
end

function UI.Glyph(parent, text, size, color, font)
    local label = createText(parent, text, size or 14, color or Theme.Text, font or Enum.Font.GothamBold)
    label.TextXAlignment = Enum.TextXAlignment.Center
    label.TextYAlignment = Enum.TextYAlignment.Center
    return label
end

local function styleButton(button, variant)
    local definitions = {
        primary = {
            base = Theme.Accent,
            hover = Theme.AccentHover,
            text = Theme.AccentInk,
            stroke = Theme.Accent,
            strokeTransparency = 0.55,
        },
        secondary = {
            base = Theme.CardRaised,
            hover = Theme.CardHover,
            text = Theme.Text,
            stroke = Theme.Border,
            strokeTransparency = 0.25,
        },
        ghost = {
            base = Color3.fromRGB(21, 25, 33),
            hover = Theme.CardHover,
            text = Theme.TextSecondary,
            stroke = Theme.BorderSoft,
            strokeTransparency = 0.55,
        },
        danger = {
            base = Color3.fromRGB(48, 25, 32),
            hover = Color3.fromRGB(63, 32, 41),
            text = Theme.Danger,
            stroke = Color3.fromRGB(92, 45, 58),
            strokeTransparency = 0.2,
        },
    }
    local definition = definitions[variant or "secondary"] or definitions.secondary
    button.BackgroundColor3 = definition.base
    button.TextColor3 = definition.text
    local stroke = addStroke(button, definition.stroke, 1, definition.strokeTransparency)
    local hovering = false

    local function applyColors()
        local base = definition.base
        local hover = definition.hover
        if variant == "primary" then
            base = Theme.Accent
            hover = Theme.AccentHover
            button.TextColor3 = Theme.AccentInk
            stroke.Color = Theme.Accent
        end
        button.BackgroundColor3 = hovering and hover or base
    end

    if variant == "primary" then
        Theme.Bind(applyColors, button)
    end

    connectOwner(button, button.MouseEnter, function()
        hovering = true
        Motion.Tween(button, { BackgroundColor3 = definition.hover }, 0.12)
        if variant == "primary" then
            Motion.Tween(button, { BackgroundColor3 = Theme.AccentHover }, 0.12)
            Motion.Tween(stroke, { Transparency = 0.2 }, 0.12)
        else
            Motion.Tween(stroke, { Transparency = 0.05 }, 0.12)
        end
    end)
    connectOwner(button, button.MouseLeave, function()
        hovering = false
        local base = variant == "primary" and Theme.Accent or definition.base
        Motion.Tween(button, { BackgroundColor3 = base }, 0.16)
        Motion.Tween(stroke, { Transparency = definition.strokeTransparency }, 0.16)
    end)

    local pressScale = Instance.new("UIScale")
    pressScale.Scale = 1
    pressScale.Parent = button

    connectOwner(button, button.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            PressedButtons[button] = true
            Motion.Tween(pressScale, { Scale = 0.965 }, 0.08)
        end
    end)
    connectOwner(button, button.InputEnded, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            PressedButtons[button] = nil
            Motion.Tween(pressScale, { Scale = 1 }, 0.14)
        end
    end)
    connectOwner(button, button.Destroying, function()
        PressedButtons[button] = nil
    end)
end

function UI.Button(parent, config)
    config = config or {}
    local button = Instance.new("TextButton")
    button.Name = config.name or "Button"
    button.Size = config.size or UDim2.fromOffset(120, 34)
    button.BackgroundColor3 = Theme.CardRaised
    button.BorderSizePixel = 0
    button.AutoButtonColor = false
    button.Text = config.text or ""
    button.TextColor3 = Theme.Text
    button.Font = config.font or Enum.Font.GothamMedium
    button.TextSize = config.textSize or 11
    button.TextTruncate = Enum.TextTruncate.AtEnd
    button.TextWrapped = false
    button.ZIndex = config.zIndex or 2
    button.Parent = parent
    round(button, config.radius or 8)
    styleButton(button, config.variant or "secondary")
    if config.tooltip then
        Tooltip.Attach(button, config.tooltip)
    end
    if config.onClick then
        connectOwner(button, button.MouseButton1Click, config.onClick)
    end
    return button
end

function UI.IconButton(parent, config)
    config = config or {}
    local button = UI.Button(parent, {
        name = config.name or "IconButton",
        size = config.size or UDim2.fromOffset(32, 32),
        text = "",
        variant = config.variant or "ghost",
        radius = config.radius or 8,
        zIndex = config.zIndex,
        tooltip = config.tooltip,
        onClick = config.onClick,
    })
    local iconSize = config.iconSize or 16
    local icon = UI.Icon(
        config.icon or "settings",
        iconSize,
        config.color or Theme.TextSecondary,
        button
    )
    icon.Frame.Position = UDim2.new(0.5, -iconSize / 2, 0.5, -iconSize / 2)
    icon.Frame.ZIndex = 3
    button:SetAttribute("IconName", config.icon or "settings")
    return button, icon
end

function UI.GlyphButton(parent, config)
    config = config or {}
    local button = UI.Button(parent, {
        name = config.name or "GlyphButton",
        size = config.size or UDim2.fromOffset(32, 32),
        text = "",
        variant = config.variant or "ghost",
        radius = config.radius or 8,
        zIndex = config.zIndex,
        tooltip = config.tooltip,
        onClick = config.onClick,
    })
    local glyph = UI.Glyph(
        button,
        config.glyph or "•",
        config.glyphSize or 16,
        config.color or Theme.TextSecondary
    )
    glyph.Size = UDim2.fromScale(1, 1)
    glyph.BackgroundTransparency = 1
    glyph.ZIndex = 3
    return button, glyph
end

function UI.TextField(parent, config)
    config = config or {}
    local box = Instance.new("TextBox")
    box.Name = config.name or "TextField"
    box.Size = config.size or UDim2.new(1, 0, 0, 36)
    box.BackgroundColor3 = Theme.CardRaised
    box.BorderSizePixel = 0
    box.Text = config.text or ""
    box.PlaceholderText = config.placeholder or ""
    box.PlaceholderColor3 = Theme.TextMuted
    box.TextColor3 = Theme.Text
    box.Font = config.font or Enum.Font.Gotham
    box.TextSize = config.textSize or 11
    box.TextXAlignment = config.textXAlignment or Enum.TextXAlignment.Left
    box.ClearTextOnFocus = false
    box.ZIndex = config.zIndex or 2
    box.Parent = parent
    round(box, config.radius or 8)
    local stroke = addStroke(box, Theme.Border, 1, 0.35)
    addPadding(box, 11, 11, 0, 0)
    connectOwner(box, box.Focused, function()
        Motion.Tween(stroke, { Color = Theme.Accent, Transparency = 0.1 }, 0.14)
    end)
    connectOwner(box, box.FocusLost, function()
        Motion.Tween(stroke, { Color = Theme.Border, Transparency = 0.35 }, 0.16)
    end)
    if config.tooltip then
        Tooltip.Attach(box, config.tooltip)
    end
    return box
end

function UI.Card(parent, title, description, options)
    options = options or {}
    local card = Instance.new("Frame")
    card.Name = options.name or "Card"
    card.Size = UDim2.new(1, 0, 0, 0)
    card.AutomaticSize = Enum.AutomaticSize.Y
    card.BackgroundColor3 = Theme.Card
    card.BorderSizePixel = 0
    card.ClipsDescendants = false
    card.ZIndex = options.zIndex or 2
    card.Parent = parent
    round(card, options.radius or 12)
    addStroke(card, Theme.BorderSoft, 1, 0.15)
    addPadding(card, 16, 16, 15, 16)
    addVerticalList(card, 8)

    local gradient = Instance.new("UIGradient")
    gradient.Rotation = 90
    gradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Theme.CardRaised),
        ColorSequenceKeypoint.new(1, Theme.Card),
    })
    gradient.Parent = card

    if title then
        local header = Instance.new("Frame")
        header.Size = UDim2.new(1, 0, 0, 20)
        header.BackgroundTransparency = 1
        header.LayoutOrder = 1
        header.Parent = card

        local titleLabel = createText(
            header,
            title,
            13,
            Theme.Text,
            Enum.Font.GothamBold
        )
        titleLabel.Size = UDim2.new(1, options.badge and -90 or 0, 1, 0)
        titleLabel.TextTruncate = Enum.TextTruncate.AtEnd

        if options.badge then
            local badge = createText(
                header,
                options.badge,
                9,
                Theme.TextMuted,
                Enum.Font.GothamBold
            )
            badge.Size = UDim2.fromOffset(80, 20)
            badge.Position = UDim2.new(1, -80, 0, 0)
            badge.TextXAlignment = Enum.TextXAlignment.Right
        end
    end

    if description and description ~= "" then
        local descriptionLabel = createText(
            card,
            description,
            10.5,
            Theme.TextSecondary,
            Enum.Font.Gotham
        )
        descriptionLabel.Size = UDim2.new(1, 0, 0, 0)
        descriptionLabel.AutomaticSize = Enum.AutomaticSize.Y
        descriptionLabel.TextWrapped = true
        descriptionLabel.TextYAlignment = Enum.TextYAlignment.Top
        descriptionLabel.LayoutOrder = 2
    end

    local body = Instance.new("Frame")
    body.Name = "Body"
    body.Size = UDim2.new(1, 0, 0, 0)
    body.AutomaticSize = Enum.AutomaticSize.Y
    body.BackgroundTransparency = 1
    body.BorderSizePixel = 0
    body.LayoutOrder = 3
    body.Parent = card
    addVerticalList(body, 2)

    return card, body
end

function UI.SectionLabel(parent, text)
    local label = createText(
        parent,
        text,
        10,
        Theme.TextMuted,
        Enum.Font.GothamBold
    )
    label.Size = UDim2.new(1, 0, 0, 18)
    label.TextYAlignment = Enum.TextYAlignment.Bottom
    return label
end

function UI.Grid(parent, options)
    options = options or {}
    local grid = Instance.new("UIGridLayout")
    grid.Name = "ResponsiveGrid"
    grid.FillDirection = Enum.FillDirection.Horizontal
    grid.SortOrder = Enum.SortOrder.LayoutOrder
    grid.HorizontalAlignment = Enum.HorizontalAlignment.Left
    grid.VerticalAlignment = Enum.VerticalAlignment.Top
    grid.CellPadding = UDim2.fromOffset(options.gap or 10, options.gap or 10)
    grid.CellSize = UDim2.new(1, 0, 0, options.cellHeight or 100)
    grid.Parent = parent
    parent.Size = UDim2.new(1, 0, 0, 0)

    local controller = {
        LastWidth = -1,
        LastChildCount = -1,
    }

    function controller.Refresh(force)
        if not parent.Parent then
            return
        end
        local width = parent.AbsoluteSize.X
        if width <= 0 then
            width = 1
        end
        local childCount = 0
        for _, child in ipairs(parent:GetChildren()) do
            if child:IsA("GuiObject") then
                childCount += 1
            end
        end
        if not force
            and math.abs(width - controller.LastWidth) < 0.5
            and childCount == controller.LastChildCount then
            return
        end
        controller.LastWidth = width
        controller.LastChildCount = childCount
        local gap = options.gap or 10
        local minimum = options.minimumWidth or 160
        local maximumColumns = options.maximumColumns or 3
        local columns = math.floor((width + gap) / (minimum + gap))
        columns = clamp(columns, 1, maximumColumns)
        local childOrder = 0
        for _, child in ipairs(parent:GetChildren()) do
            if child:IsA("GuiObject") then
                childOrder += 1
                child.LayoutOrder = childOrder
            end
        end
        local rows = math.max(1, math.ceil(childCount / columns))
        grid.CellSize = UDim2.new(
            1 / columns,
            -(gap * (columns - 1)) / columns,
            0,
            options.cellHeight or 100
        )
        parent.Size = UDim2.new(
            1, 0, 0,
            rows * (options.cellHeight or 100) + (rows - 1) * gap
        )
    end

    connectOwner(parent, parent:GetPropertyChangedSignal("AbsoluteSize"), function()
        controller.Refresh()
    end)
    connectOwner(parent, parent.ChildAdded, function()
        task.defer(function()
            controller.Refresh(true)
        end)
    end)
    connectOwner(parent, parent.ChildRemoved, function()
        task.defer(function()
            controller.Refresh(true)
        end)
    end)
    task.defer(controller.Refresh)
    return controller
end

function UI.Segmented(parent, options, selectedValue, onSelect)
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, 0, 0, 34)
    frame.BackgroundColor3 = Theme.Background
    frame.BorderSizePixel = 0
    frame.Parent = parent
    round(frame, 8)
    addStroke(frame, Theme.BorderSoft, 1, 0.4)
    addPadding(frame, 3, 3, 3, 3)
    local layout = addHorizontalList(frame, 3)

    local selected = selectedValue
    local buttons = {}
    local controller = {}

    local function refresh()
        for value, entry in pairs(buttons) do
            local isSelected = value == selected
            entry.button.BackgroundColor3 = isSelected and Theme.CardHover or Theme.Background
            entry.label.TextColor3 = isSelected and Theme.Text or Theme.TextMuted
            entry.label.Font = isSelected and Enum.Font.GothamBold or Enum.Font.Gotham
        end
    end

    for index, option in ipairs(options) do
        local button = Instance.new("TextButton")
        button.Size = UDim2.new(1 / #options, -2, 1, 0)
        button.BackgroundColor3 = Theme.Background
        button.BorderSizePixel = 0
        button.AutoButtonColor = false
        button.Text = ""
        button.LayoutOrder = index
        button.Parent = frame
        round(button, 6)
        local label = createText(
            button,
            option.label,
            10,
            Theme.TextMuted,
            Enum.Font.Gotham
        )
        label.Size = UDim2.fromScale(1, 1)
        label.TextXAlignment = Enum.TextXAlignment.Center
        connect(button.MouseEnter, function()
            if selected ~= option.value then
                Motion.Tween(button, { BackgroundColor3 = Theme.Card }, 0.12)
            end
        end)
        connect(button.MouseLeave, function()
            if selected ~= option.value then
                Motion.Tween(button, { BackgroundColor3 = Theme.Background }, 0.12)
            end
        end)
        connect(button.MouseButton1Click, function()
            selected = option.value
            refresh()
            if onSelect then
                onSelect(option.value)
            end
        end)
        buttons[option.value] = { button = button, label = label }
    end

    function controller.SetValue(value)
        selected = value
        refresh()
    end

    function controller.GetValue()
        return selected
    end

    refresh()
    return controller
end

local function toggleFavorite(id)
    if not Controls[id] then return end
    if isFavorite(id) then
        for index = #Favorites, 1, -1 do
            if Favorites[index] == id then
                table.remove(Favorites, index)
                break
            end
        end
        Notify("Dashboard", "Control unpinned.", "info", 2.2)
    else
        if #Favorites >= 8 then
            Notify(
                "Dashboard",
                "Up to 8 controls can be pinned. Unpin one first.",
                "warning"
            )
            return
        end
        table.insert(Favorites, id)
        Notify("Dashboard", "Control pinned to the dashboard.", "success", 2.2)
    end
    Events.PresetsChanged:Fire()
    scheduleSave()
end

function UI.PinButton(parent, control, position, size)
    local button = Instance.new("TextButton")
    button.Name = "PinButton"
    button.Size = size or UDim2.fromOffset(22, 22)
    button.Position = position or UDim2.new(1, -24, 0, 0)
    button.BackgroundTransparency = 1
    button.BorderSizePixel = 0
    button.AutoButtonColor = false
    button.Text = ""
    button.ZIndex = 4
    button.Parent = parent

    local glyph = UI.Glyph(button, "☆", 14, Theme.TextMuted)
    glyph.Size = UDim2.fromScale(1, 1)
    glyph.BackgroundTransparency = 1

    local function refresh()
        local pinned = isFavorite(control.id)
        glyph.Text = pinned and "★" or "☆"
        glyph.TextColor3 = pinned and Theme.Accent or Theme.TextMuted
    end

    Theme.Bind(refresh, button)
    connect(button.MouseEnter, function()
        glyph.TextColor3 = Theme.Accent
    end)
    connect(button.MouseLeave, refresh)
    connect(button.MouseButton1Click, function()
        toggleFavorite(control.id)
        refresh()
    end)
    Tooltip.Attach(
        button,
        function()
            return isFavorite(control.id)
                and "Remove this control from the dashboard"
                or "Pin this control to the dashboard"
        end
    )
    refresh()
    return button
end

local function createSwitch(parent, control)
    local switch = Instance.new("TextButton")
    switch.Name = "Switch"
    switch.Size = UDim2.fromOffset(38, 22)
    switch.BackgroundColor3 = Theme.Track
    switch.BorderSizePixel = 0
    switch.AutoButtonColor = false
    switch.Text = ""
    switch.Parent = parent
    round(switch, 11)
    local stroke = addStroke(switch, Theme.Border, 1, 0.45)

    local knob = Instance.new("Frame")
    knob.Size = UDim2.fromOffset(16, 16)
    knob.Position = UDim2.fromOffset(3, 3)
    knob.BackgroundColor3 = Theme.TextSecondary
    knob.BorderSizePixel = 0
    knob.ZIndex = 3
    knob.Parent = switch
    round(knob, 8)

    local function refresh()
        local value = control:Get() == true
        local disabled = control:IsDisabled()
        local onColor = disabled and Theme.Track or Theme.Accent
        Motion.Tween(switch, {
            BackgroundColor3 = value and onColor or Theme.Track,
        }, 0.18)
        Motion.Tween(knob, {
            Position = value
                and UDim2.fromOffset(19, 3)
                or UDim2.fromOffset(3, 3),
            BackgroundColor3 = value
                and Theme.AccentInk
                or (disabled and Theme.TextMuted or Theme.TextSecondary),
        }, 0.18)
        switch.BackgroundTransparency = disabled and 0.55 or 0
        knob.BackgroundTransparency = disabled and 0.4 or 0
        stroke.Transparency = disabled and 0.65 or 0.45
    end

    Theme.Bind(refresh, switch)
    control:Bind(refresh)
    connect(switch.MouseButton1Click, function()
        if control:IsDisabled() then
            return
        end
        control:Set(not control:Get())
    end)
    Tooltip.Attach(
        switch,
        function()
            if control:IsDisabled() then
                return "Unavailable in this execution environment"
            end
            return "Click to toggle " .. control.title
        end
    )
    refresh()
    return switch, refresh
end

function UI.ToggleRow(parent, control)
    local row = Instance.new("Frame")
    row.Name = control.id
    row.Size = UDim2.new(1, 0, 0, 50)
    row.BackgroundColor3 = Theme.Accent
    row.BackgroundTransparency = 1
    row.BorderSizePixel = 0
    row.LayoutOrder = control.order or 1
    row.Parent = parent
    round(row, 8)
    control.row = row

    local label = createText(
        row,
        control.title,
        12,
        Theme.Text,
        Enum.Font.GothamMedium
    )
    label.Size = UDim2.new(1, -118, 1, 0)
    label.TextTruncate = Enum.TextTruncate.AtEnd
    Tooltip.Attach(label, control.description)

    local switch = createSwitch(row, control)
    switch.Position = UDim2.new(1, -70, 0, 14)
    UI.PinButton(row, control, UDim2.new(1, -26, 0, 14))

    local function refreshDisabled()
        local disabled = control:IsDisabled()
        label.TextColor3 = disabled and Theme.TextMuted or Theme.Text
    end
    control:Bind(refreshDisabled)
    refreshDisabled()
    return row
end

local function parseNumericText(text)
    local numeric = tostring(text):match("[-+]?%d*%.?%d+")
    if not numeric then return nil end
    local value = tonumber(numeric)
    if not isFiniteNumber(value) then return nil end
    return value
end

function UI.SliderRow(parent, control)
    local row = Instance.new("Frame")
    row.Name = control.id
    row.Size = UDim2.new(1, 0, 0, 62)
    row.BackgroundColor3 = Theme.Accent
    row.BackgroundTransparency = 1
    row.BorderSizePixel = 0
    row.LayoutOrder = control.order or 1
    row.Parent = parent
    round(row, 8)
    control.row = row

    local title = createText(
        row,
        control.title,
        12,
        Theme.Text,
        Enum.Font.GothamMedium
    )
    title.Size = UDim2.new(1, -168, 0, 20)
    title.TextTruncate = Enum.TextTruncate.AtEnd
    Tooltip.Attach(title, control.description)

    local valueBox = Instance.new("TextBox")
    valueBox.Name = "Value"
    valueBox.Size = UDim2.fromOffset(68, 20)
    valueBox.Position = UDim2.new(1, -96, 0, 0)
    valueBox.BackgroundTransparency = 1
    valueBox.BorderSizePixel = 0
    valueBox.Text = control.format(control:Get())
    valueBox.TextColor3 = Theme.TextSecondary
    valueBox.Font = Enum.Font.Code
    valueBox.TextSize = 10
    valueBox.TextXAlignment = Enum.TextXAlignment.Right
    valueBox.ClearTextOnFocus = false
    valueBox.ZIndex = 4
    valueBox.Parent = row

    UI.PinButton(row, control, UDim2.new(1, -26, 0, 0))

    local track = Instance.new("TextButton")
    track.Name = "Track"
    track.Size = UDim2.new(1, 0, 0, 20)
    track.Position = UDim2.fromOffset(0, 30)
    track.BackgroundTransparency = 1
    track.BorderSizePixel = 0
    track.AutoButtonColor = false
    track.Text = ""
    track.ZIndex = 2
    track.Parent = row

    local trackBackground = Instance.new("Frame")
    trackBackground.Size = UDim2.new(1, 0, 0, 6)
    trackBackground.Position = UDim2.new(0, 0, 0.5, -3)
    trackBackground.BackgroundColor3 = Theme.Track
    trackBackground.BorderSizePixel = 0
    trackBackground.Parent = track
    round(trackBackground, 3)

    local fill = Instance.new("Frame")
    fill.Size = UDim2.new(0, 0, 1, 0)
    fill.BackgroundColor3 = Theme.Accent
    fill.BorderSizePixel = 0
    fill.ZIndex = 3
    fill.Parent = trackBackground
    round(fill, 3)

    local knob = Instance.new("Frame")
    knob.AnchorPoint = Vector2.new(0.5, 0.5)
    knob.Size = UDim2.fromOffset(14, 14)
    knob.Position = UDim2.new(0, 0, 0.5, 0)
    knob.BackgroundColor3 = Theme.Text
    knob.BorderSizePixel = 0
    knob.ZIndex = 5
    knob.Parent = track
    round(knob, 7)
    local knobStroke = addStroke(knob, Theme.Background, 2, 0)

    local dragging = false
    local function refresh(value)
        local alpha = invLerp(control.min, control.max, value)
        if dragging then
            fill.Size = UDim2.new(alpha, 0, 1, 0)
            knob.Position = UDim2.new(alpha, 0, 0.5, 0)
        else
            Motion.Tween(fill, { Size = UDim2.new(alpha, 0, 1, 0) }, 0.16)
            Motion.Tween(knob, { Position = UDim2.new(alpha, 0, 0.5, 0) }, 0.16)
        end
        if not valueBox:IsFocused() then
            valueBox.Text = control.format(value)
        end
    end

    Theme.Bind(function()
        fill.BackgroundColor3 = Theme.Accent
        knobStroke.Color = Theme.Background
    end, fill)
    control:Bind(refresh)

    local function setFromScreenX(x)
        local absoluteX = track.AbsolutePosition.X
        local width = math.max(1, track.AbsoluteSize.X)
        local alpha = clamp01((x - absoluteX) / width)
        local value = lerp(control.min, control.max, alpha)
        control:Set(value)
    end

    connect(track.InputBegan, function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1
            and input.UserInputType ~= Enum.UserInputType.Touch then
            return
        end
        if control:IsDisabled() then return end
        dragging = true
        setFromScreenX(input.Position.X)
        Pointer.Begin(function(moveInput)
            setFromScreenX(moveInput.Position.X)
        end, function()
            dragging = false
            control:Refresh()
        end)
    end)

    connect(valueBox.Focused, function()
        valueBox.Text = tostring(control:Get())
        valueBox:CaptureFocus()
    end)
    connect(valueBox.FocusLost, function()
        local value = parseNumericText(valueBox.Text)
        if value then
            control:Set(value)
        end
        valueBox.Text = control.format(control:Get())
    end)

    refresh(control:Get())
    return row
end

function UI.ColorRow(parent, control)
    local row = Instance.new("Frame")
    row.Name = control.id
    row.Size = UDim2.new(1, 0, 0, 48)
    row.BackgroundColor3 = Theme.Accent
    row.BackgroundTransparency = 1
    row.BorderSizePixel = 0
    row.LayoutOrder = control.order or 1
    row.Parent = parent
    round(row, 8)
    control.row = row

    local title = createText(
        row,
        control.title,
        12,
        Theme.Text,
        Enum.Font.GothamMedium
    )
    title.Size = UDim2.new(1, -140, 1, 0)
    title.TextTruncate = Enum.TextTruncate.AtEnd
    Tooltip.Attach(title, control.description)

    local swatch = Instance.new("TextButton")
    swatch.Name = "Swatch"
    swatch.Size = UDim2.fromOffset(52, 26)
    swatch.Position = UDim2.new(1, -90, 0, 11)
    swatch.BackgroundColor3 = control:Get()
    swatch.BorderSizePixel = 0
    swatch.AutoButtonColor = false
    swatch.Text = ""
    swatch.ZIndex = 4
    swatch.Parent = row
    round(swatch, 7)
    addStroke(swatch, Theme.Border, 1, 0.1)

    UI.PinButton(row, control, UDim2.new(1, -26, 0, 13))

    local function refresh(value)
        swatch.BackgroundColor3 = value
    end
    control:Bind(refresh)

    connect(swatch.MouseButton1Click, function()
        UI.OpenColorPicker(control.title, control:Get(), function(color)
            control:Set(color)
        end)
    end)
    Tooltip.Attach(swatch, "Open the color picker")

    refresh(control:Get())
    return row
end

function UI.SelectRow(parent, control)
    local row = Instance.new("Frame")
    row.Name = control.id
    row.Size = UDim2.new(1, 0, 0, 54)
    row.BackgroundColor3 = Theme.Accent
    row.BackgroundTransparency = 1
    row.BorderSizePixel = 0
    row.LayoutOrder = control.order or 1
    row.Parent = parent
    round(row, 8)
    control.row = row

    local title = createText(
        row,
        control.title,
        12,
        Theme.Text,
        Enum.Font.GothamMedium
    )
    title.Size = UDim2.new(1, -222, 1, 0)
    title.TextTruncate = Enum.TextTruncate.AtEnd
    Tooltip.Attach(title, control.description)

    local selectButton = UI.Button(row, {
        name = "Select",
        size = UDim2.fromOffset(150, 32),
        text = tostring(control:Get()),
        variant = "secondary",
        textSize = 10,
    })
    selectButton.Position = UDim2.new(1, -194, 0, 11)
    UI.PinButton(row, control, UDim2.new(1, -26, 0, 16))

    local function refresh(value)
        selectButton.Text = tostring(value)
    end
    control:Bind(refresh)

    connect(selectButton.MouseButton1Click, function()
        UI.OpenDropdown(
            selectButton,
            control.options,
            control:Get(),
            function(value)
                control:Set(value)
            end,
            150
        )
    end)

    refresh(control:Get())
    return row
end

function UI.ButtonRow(parent, buttons, height)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, height or 34)
    row.BackgroundTransparency = 1
    row.BorderSizePixel = 0
    row.Parent = parent
    addHorizontalList(row, 6)
    local result = {}
    for index, definition in ipairs(buttons) do
        local button = UI.Button(row, {
            size = UDim2.new(1 / #buttons, -((#buttons - 1) * 6) / #buttons, 1, 0),
            text = definition.text or definition[1] or "",
            variant = definition.variant or definition[2] or "secondary",
            tooltip = definition.tooltip,
            onClick = definition.onClick or definition[3],
            textSize = definition.textSize or 10,
        })
        button.LayoutOrder = index
        table.insert(result, button)
    end
    return row, result
end

function UI.NormalizeLayout(parent)
    if not parent then return end
    local order = 0
    for _, child in ipairs(parent:GetChildren()) do
        if child:IsA("GuiObject") then
            order += 1
            child.LayoutOrder = order
            UI.NormalizeLayout(child)
        end
    end
end

function UI.AddControl(parent, control)
    if not control then return nil end
    if control.kind == "toggle" then
        return UI.ToggleRow(parent, control)
    elseif control.kind == "slider" then
        return UI.SliderRow(parent, control)
    elseif control.kind == "color" then
        return UI.ColorRow(parent, control)
    elseif control.kind == "select" then
        return UI.SelectRow(parent, control)
    end
    return nil
end

function UI.MeterRow(parent, labelText)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 34)
    row.BackgroundTransparency = 1
    row.BorderSizePixel = 0
    row.Parent = parent

    local label = createText(row, labelText, 10.5, Theme.TextSecondary)
    label.Size = UDim2.new(1, -90, 0, 16)
    label.TextTruncate = Enum.TextTruncate.AtEnd

    local value = createText(
        row,
        "—",
        10.5,
        Theme.Text,
        Enum.Font.Code
    )
    value.Size = UDim2.fromOffset(90, 16)
    value.Position = UDim2.new(1, -90, 0, 0)
    value.TextXAlignment = Enum.TextXAlignment.Right

    local track = Instance.new("Frame")
    track.Size = UDim2.new(1, 0, 0, 4)
    track.Position = UDim2.fromOffset(0, 24)
    track.BackgroundColor3 = Theme.Track
    track.BorderSizePixel = 0
    track.Parent = row
    round(track, 2)

    local fill = Instance.new("Frame")
    fill.Size = UDim2.new(0, 0, 1, 0)
    fill.BackgroundColor3 = Theme.Accent
    fill.BorderSizePixel = 0
    fill.Parent = track
    round(fill, 2)
    Theme.Bind(function()
        fill.BackgroundColor3 = Theme.Accent
    end, fill)

    local controller = {
        Label = label,
        Value = value,
        Fill = fill,
    }

    function controller.Set(text, fraction, color)
        value.Text = text
        if color then
            value.TextColor3 = color
        else
            value.TextColor3 = Theme.Text
        end
        Motion.Tween(fill, {
            Size = UDim2.new(clamp01(fraction or 0), 0, 1, 0),
        }, 0.28)
    end

    return row, controller
end

--============================================================
-- 24 / TOASTS AND MODALS
--============================================================

local ToastHost = Instance.new("Frame")
ToastHost.Name = "ToastHost"
ToastHost.AnchorPoint = Vector2.new(0, 1)
ToastHost.Position = UDim2.new(0, 18, 1, -18)
ToastHost.Size = UDim2.fromOffset(334, 0)
ToastHost.AutomaticSize = Enum.AutomaticSize.Y
ToastHost.BackgroundTransparency = 1
ToastHost.BorderSizePixel = 0
ToastHost.ZIndex = 9500
ToastHost.Parent = Gui
addVerticalList(ToastHost, 8)

local ToastList = {}
local ToastCounter = 0

local function removeToast(toast)
    for index = #ToastList, 1, -1 do
        if ToastList[index] == toast then
            table.remove(ToastList, index)
            break
        end
    end
    if toast.Parent then
        Motion.Tween(toast, { GroupTransparency = 1 }, 0.18)
        task.delay(0.20, function()
            if toast.Parent then toast:Destroy() end
        end)
    end
end

local function notifyUI(title, message, kind, duration)
    if Runtime.Closed or not ToastHost.Parent then return end
    kind = kind or "info"
    local color = Theme.Info
    if kind == "success" then
        color = Theme.Success
    elseif kind == "warning" then
        color = Theme.Warning
    elseif kind == "error" then
        color = Theme.Danger
    end

    if #ToastList >= 4 then
        removeToast(ToastList[1])
    end

    local toast = createCanvas(ToastHost, "Toast")
    toast.Size = UDim2.new(1, 0, 0, 0)
    toast.AutomaticSize = Enum.AutomaticSize.Y
    toast.BackgroundColor3 = Theme.CardRaised
    toast.BackgroundTransparency = 0
    toast.GroupTransparency = 1
    toast.Active = true
    toast.ZIndex = 9501
    round(toast, 9)
    addStroke(toast, Theme.Border, 1, 0.2)
    addPadding(toast, 13, 30, 10, 10)
    addVerticalList(toast, 3)

    local heading = Instance.new("Frame")
    heading.Size = UDim2.new(1, 0, 0, 17)
    heading.BackgroundTransparency = 1
    heading.Parent = toast

    local dot = Instance.new("Frame")
    dot.Size = UDim2.fromOffset(6, 6)
    dot.Position = UDim2.new(0, 0, 0.5, -3)
    dot.BackgroundColor3 = color
    dot.BorderSizePixel = 0
    dot.Parent = heading
    round(dot, 3)

    local titleLabel = createText(
        heading,
        title or "Visual Control",
        10.5,
        Theme.Text,
        Enum.Font.GothamBold
    )
    titleLabel.Size = UDim2.new(1, -40, 1, 0)
    titleLabel.Position = UDim2.fromOffset(13, 0)
    titleLabel.TextTruncate = Enum.TextTruncate.AtEnd

    local close = UI.GlyphButton(heading, {
        glyph = "×",
        glyphSize = 14,
        size = UDim2.fromOffset(22, 22),
        variant = "ghost",
        tooltip = "Dismiss notification",
        onClick = function()
            removeToast(toast)
        end,
    })
    close.BackgroundTransparency = 1
    close.Position = UDim2.new(1, -22, 0, -3)
    close.ZIndex = 9503

    local messageLabel = createText(
        toast,
        message or "",
        10,
        Theme.TextSecondary,
        Enum.Font.Gotham
    )
    messageLabel.Size = UDim2.new(1, 0, 0, 0)
    messageLabel.AutomaticSize = Enum.AutomaticSize.Y
    messageLabel.TextWrapped = true
    messageLabel.TextYAlignment = Enum.TextYAlignment.Top
    UI.NormalizeLayout(toast)
    ToastCounter += 1
    toast.LayoutOrder = ToastCounter

    table.insert(ToastList, toast)
    Motion.Tween(toast, { GroupTransparency = 0 }, 0.22)
    task.delay(duration or 3.8, function()
        removeToast(toast)
    end)
end

NotifyExternal = notifyUI

local function closeModal(instant)
    if not CurrentModal then return end
    local modal = CurrentModal
    CurrentModal = nil
    if modal.OnClose then
        pcall(modal.OnClose)
    end
    if instant or Motion.Reduced then
        if modal.Backdrop then modal.Backdrop:Destroy() end
        if modal.Panel then modal.Panel:Destroy() end
        ModalHost.Visible = false
        return
    end
    if modal.Backdrop then
        Motion.Tween(modal.Backdrop, { BackgroundTransparency = 1 }, 0.18)
    end
    if modal.Panel then
        Motion.Tween(modal.Panel, { GroupTransparency = 1 }, 0.16)
    end
    task.delay(0.19, function()
        if Runtime.Closed then return end
        if modal.Backdrop then modal.Backdrop:Destroy() end
        if modal.Panel then modal.Panel:Destroy() end
        if not CurrentModal then
            ModalHost.Visible = false
        end
    end)
end

function UI.CloseModal()
    closeModal(false)
end

function UI.Modal(config)
    config = config or {}
    cancelKeyCaptureUI()
    Tooltip.Hide()
    closeModal(true)

    ModalHost.Visible = true
    ModalHost.ZIndex = 6000

    local backdrop = Instance.new("TextButton")
    backdrop.Name = "ModalBackdrop"
    backdrop.Size = UDim2.fromScale(1, 1)
    backdrop.BackgroundColor3 = Theme.Black
    backdrop.BackgroundTransparency = 1
    backdrop.BorderSizePixel = 0
    backdrop.AutoButtonColor = false
    backdrop.Text = ""
    backdrop.ZIndex = 6001
    backdrop.Parent = ModalHost
    if config.dismissible ~= false then
        connectOwner(backdrop, backdrop.MouseButton1Click, function()
            closeModal(false)
        end)
    end

    local modalWidth = math.min(
        config.width or 520,
        math.max(300, (Layout.BaseWidth or 1120) - 32)
    )
    local panel = createCanvas(ModalHost, "ModalPanel")
    panel.AnchorPoint = Vector2.new(0.5, 0.5)
    panel.Position = UDim2.fromScale(0.5, 0.5)
    panel.Size = UDim2.fromOffset(modalWidth, 0)
    panel.AutomaticSize = Enum.AutomaticSize.Y
    panel.BackgroundColor3 = Theme.Window
    panel.BackgroundTransparency = 0
    panel.GroupTransparency = 1
    panel.Active = true
    panel.ZIndex = 6002
    round(panel, 14)
    addStroke(panel, Theme.Border, 1, 0.15)
    addPadding(panel, 20, 20, 18, 18)
    addVerticalList(panel, 12)
    local panelScale = Instance.new("UIScale")
    panelScale.Scale = 0.96
    panelScale.Parent = panel

    local header = Instance.new("Frame")
    header.Size = UDim2.new(1, 0, 0, 42)
    header.BackgroundTransparency = 1
    header.Parent = panel

    local title = createText(
        header,
        config.title or "Visual Control",
        16,
        Theme.Text,
        Enum.Font.GothamBold
    )
    title.Size = UDim2.new(1, -38, 0, 22)
    title.TextTruncate = Enum.TextTruncate.AtEnd

    if config.subtitle and config.subtitle ~= "" then
        local subtitle = createText(
            header,
            config.subtitle,
            10,
            Theme.TextSecondary
        )
        subtitle.Size = UDim2.new(1, -38, 0, 18)
        subtitle.Position = UDim2.fromOffset(0, 23)
        subtitle.TextTruncate = Enum.TextTruncate.AtEnd
    end

    local close = UI.GlyphButton(header, {
        glyph = "×",
        glyphSize = 16,
        size = UDim2.fromOffset(28, 28),
        variant = "ghost",
        tooltip = "Close",
        onClick = function()
            closeModal(false)
        end,
    })
    close.Position = UDim2.new(1, -28, 0, 0)

    local body = Instance.new("Frame")
    body.Name = "ModalBody"
    body.Size = UDim2.new(1, 0, 0, config.bodyHeight or 0)
    body.AutomaticSize = config.bodyHeight and Enum.AutomaticSize.None
        or Enum.AutomaticSize.Y
    body.BackgroundTransparency = 1
    body.BorderSizePixel = 0
    body.Parent = panel
    addVerticalList(body, 8)

    local footer = nil
    if config.actions and #config.actions > 0 then
        footer = Instance.new("Frame")
        footer.Size = UDim2.new(1, 0, 0, 34)
        footer.BackgroundTransparency = 1
        footer.Parent = panel
        addHorizontalList(footer, 7)
        for index, action in ipairs(config.actions) do
            local button = UI.Button(footer, {
                size = UDim2.new(1 / #config.actions, -((#config.actions - 1) * 7) / #config.actions, 1, 0),
                text = action.text,
                variant = action.variant or "secondary",
                tooltip = action.tooltip,
                onClick = action.onClick,
            })
            button.LayoutOrder = index
        end
    end

    local modal = {
        Backdrop = backdrop,
        Panel = panel,
        Body = body,
        Footer = footer,
        Title = title,
        Close = function()
            closeModal(false)
        end,
        OnClose = config.onClose,
    }
    CurrentModal = modal

    if config.build then
        pcall(config.build, body, modal)
    end
    UI.NormalizeLayout(panel)

    Motion.Tween(backdrop, { BackgroundTransparency = 0.58 }, 0.20)
    Motion.Tween(panel, { GroupTransparency = 0 }, 0.22)
    Motion.Tween(panelScale, { Scale = 1 }, 0.26)

    if config.onOpen then
        task.defer(function()
            if not Runtime.Closed then
                pcall(config.onOpen, modal)
            end
        end)
    end
    return modal
end

function UI.Confirm(config)
    return UI.Modal({
        title = config.title or "Confirm action",
        subtitle = config.subtitle,
        width = config.width or 420,
        dismissible = config.dismissible,
        build = function(body)
            local label = createText(
                body,
                config.message or "",
                11,
                Theme.TextSecondary
            )
            label.Size = UDim2.new(1, 0, 0, 0)
            label.AutomaticSize = Enum.AutomaticSize.Y
            label.TextWrapped = true
            label.TextYAlignment = Enum.TextYAlignment.Top
        end,
        actions = {
            {
                text = config.cancelText or "Cancel",
                variant = "secondary",
                onClick = function()
                    closeModal(false)
                    if config.onCancel then config.onCancel() end
                end,
            },
            {
                text = config.confirmText or "Confirm",
                variant = config.danger and "danger" or "primary",
                onClick = function()
                    closeModal(false)
                    if config.onConfirm then config.onConfirm() end
                end,
            },
        },
    })
end

local COLOR_SWATCHES = {
    Color3.fromRGB(255, 255, 255),
    Color3.fromRGB(236, 239, 244),
    Color3.fromRGB(255, 227, 196),
    Color3.fromRGB(255, 208, 166),
    Color3.fromRGB(244, 184, 148),
    Color3.fromRGB(233, 151, 137),
    Color3.fromRGB(255, 190, 208),
    Color3.fromRGB(232, 150, 201),
    Color3.fromRGB(202, 154, 255),
    Color3.fromRGB(168, 152, 255),
    Color3.fromRGB(125, 170, 255),
    Color3.fromRGB(137, 220, 255),
    Color3.fromRGB(169, 241, 236),
    Color3.fromRGB(135, 231, 198),
    Color3.fromRGB(183, 230, 153),
    Color3.fromRGB(235, 232, 151),
    Color3.fromRGB(243, 198, 116),
    Color3.fromRGB(207, 159, 109),
    Color3.fromRGB(177, 190, 203),
    Color3.fromRGB(126, 140, 158),
    Color3.fromRGB(92, 105, 124),
    Color3.fromRGB(63, 74, 91),
    Color3.fromRGB(31, 38, 49),
    Color3.fromRGB(0, 0, 0),
}

function UI.OpenColorPicker(title, initialColor, onApply)
    local chosen = initialColor
    local hexBox
    local preview

    local modal = UI.Modal({
        title = title or "Choose color",
        subtitle = "Pick a swatch or enter a six-digit hex value.",
        width = 470,
        build = function(body)
            local grid = Instance.new("Frame")
            grid.Size = UDim2.new(1, 0, 0, 0)
            grid.BackgroundTransparency = 1
            grid.Parent = body
            UI.Grid(grid, {
                minimumWidth = 40,
                maximumColumns = 8,
                cellHeight = 32,
                gap = 6,
            })

            local swatchButtons = {}
            local swatchStrokes = {}
            local function refreshSelection()
                for color, button in pairs(swatchButtons) do
                    local selected = color == chosen
                    local stroke = swatchStrokes[color]
                    if stroke then
                        stroke.Transparency = selected and 0 or 0.55
                        stroke.Color = selected and Theme.Text or Theme.Border
                    end
                end
            end

            for index, color in ipairs(COLOR_SWATCHES) do
                local button = Instance.new("TextButton")
                button.Size = UDim2.fromOffset(48, 32)
                button.BackgroundColor3 = color
                button.BorderSizePixel = 0
                button.AutoButtonColor = false
                button.Text = ""
                button.LayoutOrder = index
                button.Parent = grid
                round(button, 6)
                local stroke = addStroke(button, Theme.Border, 1, 0.55)
                swatchStrokes[color] = stroke
                swatchButtons[color] = button
                connectOwner(button, button.MouseButton1Click, function()
                    chosen = color
                    preview.BackgroundColor3 = color
                    hexBox.Text = colorToHex(color)
                    refreshSelection()
                end)
            end

            local customRow = Instance.new("Frame")
            customRow.Size = UDim2.new(1, 0, 0, 38)
            customRow.BackgroundTransparency = 1
            customRow.Parent = body

            preview = Instance.new("Frame")
            preview.Size = UDim2.fromOffset(38, 38)
            preview.BackgroundColor3 = chosen
            preview.BorderSizePixel = 0
            preview.Parent = customRow
            round(preview, 8)
            addStroke(preview, Theme.Border, 1, 0.1)

            hexBox = UI.TextField(customRow, {
                size = UDim2.new(1, -46, 1, 0),
                text = colorToHex(chosen),
                placeholder = "RRGGBB",
                name = "HexColor",
            })
            hexBox.Position = UDim2.fromOffset(46, 0)
            hexBox.TextXAlignment = Enum.TextXAlignment.Left

            local function updateFromHex()
                local parsed = hexToColor(hexBox.Text)
                if parsed then
                    chosen = parsed
                    preview.BackgroundColor3 = parsed
                    refreshSelection()
                else
                    hexBox.Text = colorToHex(chosen)
                end
            end
            connectOwner(hexBox, hexBox.FocusLost, updateFromHex)
            refreshSelection()
        end,
        actions = {
            {
                text = "Cancel",
                variant = "secondary",
                onClick = function()
                    closeModal(false)
                end,
            },
            {
                text = "Apply color",
                variant = "primary",
                onClick = function()
                    local parsed = hexToColor(hexBox.Text)
                    if parsed then
                        chosen = parsed
                    end
                    closeModal(false)
                    if onApply then
                        onApply(chosen)
                    end
                end,
            },
        },
    })
    return modal
end

--============================================================
-- 25 / DROPDOWNS
--============================================================

local function closeDropdown()
    if not CurrentDropdown then return end
    local dropdown = CurrentDropdown
    CurrentDropdown = nil
    if dropdown.Catcher then dropdown.Catcher:Destroy() end
    if dropdown.Menu then dropdown.Menu:Destroy() end
    if not CurrentModal then
        PopupHost.Visible = false
    end
end

function UI.OpenDropdown(anchor, options, currentValue, onSelect, width)
    cancelKeyCaptureUI()
    Tooltip.Hide()
    closeDropdown()
    PopupHost.Visible = true
    PopupHost.ZIndex = 5000
    width = width or 160

    local catcher = Instance.new("TextButton")
    catcher.Name = "DropdownCatcher"
    catcher.Size = UDim2.fromScale(1, 1)
    catcher.BackgroundTransparency = 1
    catcher.BorderSizePixel = 0
    catcher.AutoButtonColor = false
    catcher.Text = ""
    catcher.ZIndex = 5001
    catcher.Parent = PopupHost
    connectOwner(catcher, catcher.MouseButton1Click, closeDropdown)

    local menu = createCanvas(PopupHost, "DropdownMenu")
    menu.ZIndex = 5002
    menu.BackgroundColor3 = Theme.CardRaised
    menu.BackgroundTransparency = 0
    menu.GroupTransparency = 1
    menu.Active = true
    menu.ClipsDescendants = true
    round(menu, 9)
    addStroke(menu, Theme.Border, 1, 0.15)
    addPadding(menu, 5, 5, 5, 5)
    addVerticalList(menu, 2)
    local menuScale = Instance.new("UIScale")
    menuScale.Scale = 0.97
    menuScale.Parent = menu

    local scale = Layout and Layout.Scale or 1
    local rootAbs = WindowRoot.AbsolutePosition
    local localX = (anchor.AbsolutePosition.X - rootAbs.X) / scale
    local localY = (anchor.AbsolutePosition.Y - rootAbs.Y) / scale
        + anchor.AbsoluteSize.Y / scale + 4
    local baseWidth = Layout and Layout.BaseWidth or 1120
    local baseHeight = Layout and Layout.BaseHeight or 700
    local height = #options * 32 + (#options - 1) * 2 + 10
    localX = clamp(localX, 10, baseWidth - width - 10)
    if localY + height > baseHeight - 10 then
        localY = (anchor.AbsolutePosition.Y - rootAbs.Y) / scale
            - height - 4
    end
    localY = math.max(10, localY)
    menu.Position = UDim2.fromOffset(localX, localY)
    menu.Size = UDim2.fromOffset(width, height)

    for index, option in ipairs(options) do
        local selected = option == currentValue
        local item = Instance.new("TextButton")
        item.Size = UDim2.new(1, 0, 0, 32)
        item.BackgroundColor3 = selected and Theme.CardHover or Theme.CardRaised
        item.BackgroundTransparency = selected and 0 or 1
        item.BorderSizePixel = 0
        item.AutoButtonColor = false
        item.Text = ""
        item.LayoutOrder = index
        item.Parent = menu
        round(item, 6)
        local label = createText(
            item,
            tostring(option),
            10.5,
            selected and Theme.Text or Theme.TextSecondary,
            selected and Enum.Font.GothamBold or Enum.Font.Gotham
        )
        label.Size = UDim2.new(1, -30, 1, 0)
        label.Position = UDim2.fromOffset(10, 0)
        label.TextTruncate = Enum.TextTruncate.AtEnd
        if selected then
            local check = UI.Icon("check", 12, Theme.Accent, item)
            check.Frame.Position = UDim2.new(1, -22, 0.5, -6)
        end
        connectOwner(item, item.MouseEnter, function()
            Motion.Tween(item, {
                BackgroundColor3 = Theme.CardHover,
                BackgroundTransparency = 0,
            }, 0.10)
        end)
        connectOwner(item, item.MouseLeave, function()
            if not selected then
                Motion.Tween(item, {
                    BackgroundColor3 = Theme.CardRaised,
                    BackgroundTransparency = 1,
                }, 0.10)
            end
        end)
        connectOwner(item, item.MouseButton1Click, function()
            closeDropdown()
            if onSelect then
                onSelect(option)
            end
        end)
    end

    CurrentDropdown = {
        Catcher = catcher,
        Menu = menu,
    }
    Motion.Tween(menu, { GroupTransparency = 0 }, 0.16)
    Motion.Tween(menuScale, { Scale = 1 }, 0.18)
end

--============================================================
-- 26 / APPLICATION SHELL
--============================================================

local Header = Instance.new("Frame")
Header.Name = "Header"
Header.Size = UDim2.new(1, 0, 0, 64)
Header.BackgroundColor3 = Theme.Header
Header.BorderSizePixel = 0
Header.ZIndex = 4
Header.Parent = Main

local headerGradient = Instance.new("UIGradient")
headerGradient.Rotation = 90
headerGradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(18, 22, 29)),
    ColorSequenceKeypoint.new(1, Theme.Header),
})
headerGradient.Parent = Header

local headerBorder = Instance.new("Frame")
headerBorder.Size = UDim2.new(1, 0, 0, 1)
headerBorder.Position = UDim2.new(0, 0, 1, -1)
headerBorder.BackgroundColor3 = Theme.BorderSoft
headerBorder.BorderSizePixel = 0
headerBorder.ZIndex = 5
headerBorder.Parent = Header

local LogoArea = Instance.new("Frame")
LogoArea.Name = "LogoArea"
LogoArea.Size = UDim2.fromOffset(224, 64)
LogoArea.BackgroundTransparency = 1
LogoArea.BorderSizePixel = 0
LogoArea.ZIndex = 6
LogoArea.Parent = Header

local LogoBadge = Instance.new("Frame")
LogoBadge.Size = UDim2.fromOffset(32, 32)
LogoBadge.Position = UDim2.fromOffset(16, 16)
LogoBadge.BackgroundColor3 = Theme.Accent
LogoBadge.BorderSizePixel = 0
LogoBadge.ZIndex = 7
LogoBadge.Parent = LogoArea
round(LogoBadge, 9)
addStroke(LogoBadge, Theme.AccentHover, 1, 0.55)
local logoGradient = Instance.new("UIGradient")
logoGradient.Rotation = 135
logoGradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Theme.AccentHover),
    ColorSequenceKeypoint.new(1, Theme.Accent),
})
logoGradient.Parent = LogoBadge
local logoLetter = createText(
    LogoBadge,
    "V",
    18,
    Theme.AccentInk,
    Enum.Font.GothamBold
)
logoLetter.Size = UDim2.fromScale(1, 1)
logoLetter.TextXAlignment = Enum.TextXAlignment.Center
logoLetter.ZIndex = 8

Theme.Bind(function()
    logoGradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Theme.AccentHover),
        ColorSequenceKeypoint.new(1, Theme.Accent),
    })
    logoLetter.TextColor3 = Theme.AccentInk
    local stroke = LogoBadge:FindFirstChildOfClass("UIStroke")
    if stroke then stroke.Color = Theme.AccentHover end
end)

local AppTitle = createText(
    LogoArea,
    "VISUAL CONTROL",
    12,
    Theme.Text,
    Enum.Font.GothamBold
)
AppTitle.Size = UDim2.fromOffset(160, 16)
AppTitle.Position = UDim2.fromOffset(57, 16)

local AppSubtitle = createText(
    LogoArea,
    "REBORN  /  v" .. VERSION,
    8.5,
    Theme.TextMuted,
    Enum.Font.GothamMedium
)
AppSubtitle.Size = UDim2.fromOffset(160, 14)
AppSubtitle.Position = UDim2.fromOffset(57, 32)

local DragRegion = Instance.new("Frame")
DragRegion.Name = "DragRegion"
DragRegion.Position = UDim2.fromOffset(224, 0)
DragRegion.Size = UDim2.new(1, -404, 1, 0)
DragRegion.BackgroundTransparency = 1
DragRegion.BorderSizePixel = 0
DragRegion.Active = true
DragRegion.ZIndex = 6
DragRegion.Parent = Header

local HeaderActions = Instance.new("Frame")
HeaderActions.Name = "HeaderActions"
HeaderActions.AnchorPoint = Vector2.new(1, 0)
HeaderActions.Position = UDim2.new(1, -14, 0, 0)
HeaderActions.Size = UDim2.fromOffset(180, 64)
HeaderActions.BackgroundTransparency = 1
HeaderActions.BorderSizePixel = 0
HeaderActions.ZIndex = 7
HeaderActions.Parent = Header
local headerActionsLayout = addHorizontalList(HeaderActions, 4)
headerActionsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right

local SearchButton = UI.IconButton(HeaderActions, {
    name = "SearchButton",
    icon = "search",
    iconSize = 16,
    size = UDim2.fromOffset(32, 32),
    tooltip = "Search settings (Ctrl+K)",
    onClick = function()
        if UI.OpenSearch then UI.OpenSearch() end
    end,
})
SearchButton.LayoutOrder = 1

local CompareButton, CompareIcon = UI.IconButton(HeaderActions, {
    name = "CompareButton",
    icon = "compare",
    iconSize = 17,
    size = UDim2.fromOffset(32, 32),
    tooltip = "Hold to compare original rendering",
})
CompareButton.LayoutOrder = 2

local HeaderDivider = Instance.new("Frame")
HeaderDivider.Size = UDim2.fromOffset(1, 22)
HeaderDivider.BackgroundColor3 = Theme.Border
HeaderDivider.BorderSizePixel = 0
HeaderDivider.LayoutOrder = 3
HeaderDivider.Parent = HeaderActions

local MinimizeButton, MinimizeGlyph = UI.GlyphButton(HeaderActions, {
    name = "MinimizeButton",
    glyph = "−",
    glyphSize = 18,
    size = UDim2.fromOffset(32, 32),
    tooltip = "Minimize",
    onClick = function()
        Layout.SetMinimized(not Runtime.Minimized)
    end,
})
MinimizeButton.LayoutOrder = 4

local HideButton = UI.IconButton(HeaderActions, {
    name = "HideButton",
    icon = "close",
    iconSize = 15,
    size = UDim2.fromOffset(32, 32),
    tooltip = "Hide window (=)",
    onClick = function()
        if UI.Hide then UI.Hide() end
    end,
})
HideButton.LayoutOrder = 5

local Body = Instance.new("Frame")
Body.Name = "Body"
Body.Position = UDim2.fromOffset(0, 64)
Body.Size = UDim2.new(1, 0, 1, -64)
Body.BackgroundColor3 = Theme.Window
Body.BorderSizePixel = 0
Body.ZIndex = 3
Body.Parent = Main

local Sidebar = Instance.new("Frame")
Sidebar.Name = "Sidebar"
Sidebar.Size = UDim2.fromOffset(214, 1)
Sidebar.BackgroundColor3 = Theme.Sidebar
Sidebar.BorderSizePixel = 0
Sidebar.ZIndex = 4
Sidebar.Parent = Body

local sidebarBorder = Instance.new("Frame")
sidebarBorder.Size = UDim2.new(0, 1, 1, 0)
sidebarBorder.Position = UDim2.new(1, -1, 0, 0)
sidebarBorder.BackgroundColor3 = Theme.BorderSoft
sidebarBorder.BorderSizePixel = 0
sidebarBorder.ZIndex = 5
sidebarBorder.Parent = Sidebar

local ContentArea = Instance.new("Frame")
ContentArea.Name = "ContentArea"
ContentArea.Position = UDim2.fromOffset(214, 0)
ContentArea.Size = UDim2.new(1, -214, 1, 0)
ContentArea.BackgroundColor3 = Theme.Window
ContentArea.BorderSizePixel = 0
ContentArea.ZIndex = 3
ContentArea.Parent = Body

local PageHost = Instance.new("Frame")
PageHost.Name = "PageHost"
PageHost.Size = UDim2.fromScale(1, 1)
PageHost.BackgroundTransparency = 1
PageHost.BorderSizePixel = 0
PageHost.ZIndex = 4
PageHost.Parent = ContentArea

local SidebarNav = Instance.new("ScrollingFrame")
SidebarNav.Name = "SidebarNav"
SidebarNav.Position = UDim2.fromOffset(0, 6)
SidebarNav.Size = UDim2.new(1, 0, 1, -62)
SidebarNav.BackgroundTransparency = 1
SidebarNav.BorderSizePixel = 0
SidebarNav.ScrollBarThickness = 2
SidebarNav.ScrollBarImageColor3 = Theme.Track
SidebarNav.ScrollBarImageTransparency = 0.5
SidebarNav.CanvasSize = UDim2.fromOffset(0, 0)
SidebarNav.AutomaticCanvasSize = Enum.AutomaticSize.Y
SidebarNav.ScrollingDirection = Enum.ScrollingDirection.Y
SidebarNav.ElasticBehavior = Enum.ElasticBehavior.Never
SidebarNav.ZIndex = 5
SidebarNav.Parent = Sidebar
addPadding(SidebarNav, 10, 10, 2, 12)
addVerticalList(SidebarNav, 2)

local SidebarFooter = Instance.new("Frame")
SidebarFooter.Name = "SidebarFooter"
SidebarFooter.AnchorPoint = Vector2.new(0, 1)
SidebarFooter.Position = UDim2.new(0, 0, 1, 0)
SidebarFooter.Size = UDim2.new(1, 0, 0, 56)
SidebarFooter.BackgroundColor3 = Theme.Sidebar
SidebarFooter.BorderSizePixel = 0
SidebarFooter.ZIndex = 6
SidebarFooter.Parent = Sidebar

local footerBorder = Instance.new("Frame")
footerBorder.Size = UDim2.new(1, 0, 0, 1)
footerBorder.BackgroundColor3 = Theme.BorderSoft
footerBorder.BorderSizePixel = 0
footerBorder.ZIndex = 7
footerBorder.Parent = SidebarFooter

local SidebarEnvDot = Instance.new("Frame")
SidebarEnvDot.Size = UDim2.fromOffset(6, 6)
SidebarEnvDot.Position = UDim2.fromOffset(16, 25)
SidebarEnvDot.BackgroundColor3 = Theme.Accent
SidebarEnvDot.BorderSizePixel = 0
SidebarEnvDot.ZIndex = 8
SidebarEnvDot.Parent = SidebarFooter
round(SidebarEnvDot, 3)
Theme.Bind(function()
    SidebarEnvDot.BackgroundColor3 = Theme.Accent
end)

local SidebarEnvLabel = createText(
    SidebarFooter,
    "Environment: scanning",
    9.5,
    Theme.TextMuted,
    Enum.Font.Gotham
)
SidebarEnvLabel.Size = UDim2.new(1, -92, 0, 20)
SidebarEnvLabel.Position = UDim2.fromOffset(28, 18)
SidebarEnvLabel.TextTruncate = Enum.TextTruncate.AtEnd

local CollapseButton, CollapseGlyph = UI.GlyphButton(SidebarFooter, {
    name = "CollapseButton",
    glyph = "«",
    glyphSize = 15,
    size = UDim2.fromOffset(26, 26),
    tooltip = "Collapse or expand the sidebar",
    onClick = function()
        if Layout.ForcedCollapse then
            Notify(
                "Sidebar",
                "The sidebar auto-collapses when the window is narrow.",
                "info",
                2.6
            )
            return
        end
        S.sidebarCollapsed = not S.sidebarCollapsed
        Layout.SetCollapsed(S.sidebarCollapsed, true)
        scheduleSave()
    end,
})
CollapseButton.Position = UDim2.new(1, -36, 0, 15)
CollapseButton.ZIndex = 9

local NAV_SECTIONS = {
    {
        label = "OVERVIEW",
        items = {
            { id = "Dashboard", icon = "dashboard" },
        },
    },
    {
        label = "VISUALS",
        items = {
            { id = "Graphics", icon = "graphics" },
            { id = "Lighting", icon = "lighting" },
            { id = "Atmosphere", icon = "atmosphere" },
            { id = "Weather", icon = "weather" },
            { id = "Camera", icon = "camera" },
        },
    },
    {
        label = "LIBRARY",
        items = {
            { id = "Presets", icon = "presets" },
        },
    },
    {
        label = "SYSTEM",
        items = {
            { id = "Audio", icon = "audio" },
            { id = "Performance", icon = "performance" },
            { id = "Settings", icon = "settings" },
        },
    },
}

Layout.SectionLabels = {}
Layout.NavLabels = {}
Layout.NavIcons = {}

for _, section in ipairs(NAV_SECTIONS) do
    local sectionLabel = createText(
        SidebarNav,
        section.label,
        8.5,
        Theme.TextMuted,
        Enum.Font.GothamBold
    )
    sectionLabel.Size = UDim2.new(1, 0, 0, 24)
    sectionLabel.Position = UDim2.fromOffset(10, 0)
    sectionLabel.TextYAlignment = Enum.TextYAlignment.Bottom
    table.insert(Layout.SectionLabels, sectionLabel)

    for _, item in ipairs(section.items) do
        local button = Instance.new("TextButton")
        button.Name = item.id .. "Nav"
        button.Size = UDim2.new(1, 0, 0, 36)
        button.BackgroundColor3 = Theme.Card
        button.BackgroundTransparency = 1
        button.BorderSizePixel = 0
        button.AutoButtonColor = false
        button.Text = ""
        button.ZIndex = 7
        button.Parent = SidebarNav
        round(button, 7)

        local indicator = Instance.new("Frame")
        indicator.Size = UDim2.fromOffset(2, 15)
        indicator.Position = UDim2.fromOffset(0, 10)
        indicator.BackgroundColor3 = Theme.Accent
        indicator.BorderSizePixel = 0
        indicator.Visible = false
        indicator.ZIndex = 9
        indicator.Parent = button
        round(indicator, 1)
        Theme.Bind(function()
            indicator.BackgroundColor3 = Theme.Accent
        end, indicator)

        local icon = UI.Icon(item.icon, 18, Theme.TextSecondary, button)
        icon.Frame.Position = UDim2.fromOffset(12, 9)
        icon.Frame.ZIndex = 8

        local label = createText(
            button,
            item.id,
            11.5,
            Theme.TextSecondary,
            Enum.Font.GothamMedium
        )
        label.Size = UDim2.new(1, -50, 1, 0)
        label.Position = UDim2.fromOffset(42, 0)
        label.TextTruncate = Enum.TextTruncate.AtEnd
        label.ZIndex = 8

        local navEntry = {
            id = item.id,
            button = button,
            label = label,
            icon = icon,
            indicator = indicator,
        }

        function navEntry.Update()
            local active = CurrentPage == item.id
            button.BackgroundTransparency = active and 0 or 1
            button.BackgroundColor3 = Theme.Card
            indicator.Visible = active
            label.TextColor3 = active and Theme.Text or Theme.TextSecondary
            icon.SetColor(active and Theme.Accent or Theme.TextSecondary)
        end

        Theme.Bind(navEntry.Update, button)

        connect(button.MouseEnter, function()
            if CurrentPage ~= item.id then
                button.BackgroundTransparency = 0.45
                button.BackgroundColor3 = Theme.CardHover
            end
        end)
        connect(button.MouseLeave, function()
            if CurrentPage ~= item.id then
                button.BackgroundTransparency = 1
            end
        end)
        connect(button.MouseButton1Click, function()
            if UI.Navigate then
                UI.Navigate(item.id)
            end
        end)
        Tooltip.Attach(button, item.id)

        NavItems[item.id] = navEntry
        table.insert(Layout.NavLabels, label)
        table.insert(Layout.NavIcons, icon)
    end
end

--============================================================
-- 27 / WINDOW AND SIDEBAR BEHAVIOR
--============================================================

Layout.UserTopLeft = nil
Layout.LastViewport = nil

local function updateCollapseButton()
    CollapseGlyph.Text = Layout.Collapsed and "»" or "«"
end

function Layout.SetCollapsed(collapsed, animate)
    collapsed = collapsed == true
    if Layout.Collapsed == collapsed and animate ~= false then
        updateCollapseButton()
        return
    end
    Layout.Collapsed = collapsed
    local width = collapsed and 68 or 214
    local targetSidebar = UDim2.fromOffset(width, 1)
    local targetContentPosition = UDim2.fromOffset(width, 0)
    local targetContentSize = UDim2.new(1, -width, 1, 0)

    if animate == false or Motion.Reduced then
        Sidebar.Size = targetSidebar
        ContentArea.Position = targetContentPosition
        ContentArea.Size = targetContentSize
        for _, label in ipairs(Layout.NavLabels) do
            label.Visible = not collapsed
            label.TextTransparency = collapsed and 1 or 0
        end
        for _, label in ipairs(Layout.SectionLabels) do
            label.Visible = not collapsed
            label.TextTransparency = collapsed and 1 or 0
            label.Size = UDim2.new(1, 0, 0, collapsed and 0 or 24)
        end
        for _, icon in ipairs(Layout.NavIcons) do
            icon.Frame.Position = collapsed
                and UDim2.fromOffset(15, 9)
                or UDim2.fromOffset(12, 9)
        end
        SidebarEnvLabel.Visible = not collapsed
        SidebarEnvLabel.TextTransparency = collapsed and 1 or 0
        SidebarEnvLabel.Size = UDim2.new(1, collapsed and -24 or -92, 0, 20)
        SidebarEnvDot.Position = collapsed
            and UDim2.fromOffset(16, 25)
            or UDim2.fromOffset(16, 25)
        updateCollapseButton()
        return
    end

    Motion.Tween(Sidebar, { Size = targetSidebar }, 0.26)
    Motion.Tween(ContentArea, {
        Position = targetContentPosition,
        Size = targetContentSize,
    }, 0.26)
    for _, label in ipairs(Layout.NavLabels) do
        if not collapsed then
            label.Visible = true
        end
        Motion.Tween(label, { TextTransparency = collapsed and 1 or 0 }, 0.18)
    end
    if collapsed then
        task.delay(0.19, function()
            if Runtime.Closed then return end
            if Layout.Collapsed then
                for _, label in ipairs(Layout.NavLabels) do
                    label.Visible = false
                end
            end
        end)
    end
    for _, label in ipairs(Layout.SectionLabels) do
        if collapsed then
            Motion.Tween(label, {
                TextTransparency = 1,
                Size = UDim2.new(1, 0, 0, 0),
            }, 0.18)
        else
            label.Visible = true
            label.Size = UDim2.new(1, 0, 0, 24)
            Motion.Tween(label, { TextTransparency = 0 }, 0.18)
        end
    end
    for _, icon in ipairs(Layout.NavIcons) do
        Motion.Tween(icon.Frame, {
            Position = collapsed
                and UDim2.fromOffset(15, 9)
                or UDim2.fromOffset(12, 9),
        }, 0.24)
    end
    if not collapsed then
        SidebarEnvLabel.Visible = true
    end
    SidebarEnvLabel.Size = UDim2.new(1, collapsed and -24 or -92, 0, 20)
    Motion.Tween(SidebarEnvLabel, {
        TextTransparency = collapsed and 1 or 0,
    }, 0.18)
    if collapsed then
        task.delay(0.19, function()
            if Runtime.Closed then return end
            if Layout.Collapsed then
                SidebarEnvLabel.Visible = false
            end
        end)
    end
    updateCollapseButton()
end

function Layout.ClampWindow()
    local camera = Workspace.CurrentCamera
    if not camera then return end
    local viewport = camera.ViewportSize
    local size = WindowRoot.AbsoluteSize
    local position = WindowRoot.AbsolutePosition
    local maximumX = math.max(8, viewport.X - size.X - 8)
    local maximumY = math.max(8, viewport.Y - size.Y - 8)
    local x = clamp(position.X, 8, maximumX)
    local y = clamp(position.Y, 8, maximumY)
    WindowRoot.Position = UDim2.fromOffset(x, y)
    Layout.UserTopLeft = Vector2.new(x, y)
end

function Layout.UpdateViewport(force)
    local camera = Workspace.CurrentCamera
    if not camera then return end
    local viewport = camera.ViewportSize
    if not force and Layout.LastViewport
        and math.abs(viewport.X - Layout.LastViewport.X) < 1
        and math.abs(viewport.Y - Layout.LastViewport.Y) < 1 then
        return
    end
    Layout.LastViewport = viewport

    local scale = clamp(
        math.min(viewport.X / 1280, viewport.Y / 820),
        0.55,
        1.15
    )
    local margin = 16
    local maximumWidth = viewport.X / scale - margin * 2
    local maximumHeight = viewport.Y / scale - margin * 2
    local baseWidth = math.min(1120, maximumWidth)
    local baseHeight = math.min(700, maximumHeight)
    if baseWidth < 460 then
        baseWidth = math.max(360, maximumWidth)
    end
    if baseHeight < 320 then
        baseHeight = math.max(240, maximumHeight)
    end

    Layout.Scale = scale
    Layout.BaseWidth = baseWidth
    Layout.BaseHeight = baseHeight
    WindowScale.Scale = scale
    WindowRoot.Size = UDim2.fromOffset(
        baseWidth,
        Runtime.Minimized and 64 or baseHeight
    )

    local previousTopLeft = Layout.UserTopLeft
    local topLeftX
    local topLeftY
    if previousTopLeft then
        topLeftX = previousTopLeft.X
        topLeftY = previousTopLeft.Y
    else
        topLeftX = (viewport.X - baseWidth * scale) * 0.5
        topLeftY = (viewport.Y - (Runtime.Minimized and 64 or baseHeight) * scale) * 0.5
    end

    local pixelWidth = baseWidth * scale
    local pixelHeight = (Runtime.Minimized and 64 or baseHeight) * scale
    topLeftX = clamp(topLeftX, 8, math.max(8, viewport.X - pixelWidth - 8))
    topLeftY = clamp(topLeftY, 8, math.max(8, viewport.Y - pixelHeight - 8))
    WindowRoot.Position = UDim2.fromOffset(topLeftX, topLeftY)
    Layout.UserTopLeft = Vector2.new(topLeftX, topLeftY)

    local forced = baseWidth < 820
    Layout.ForcedCollapse = forced
    local effectiveCollapsed = forced or S.sidebarCollapsed
    if effectiveCollapsed ~= Layout.Collapsed then
        Layout.SetCollapsed(effectiveCollapsed, false)
    else
        updateCollapseButton()
    end

    if ToastHost then
        ToastHost.Size = UDim2.fromOffset(
            math.min(334, viewport.X - 36),
            0
        )
    end
end

function Layout.SetMinimized(minimized)
    minimized = minimized == true
    if Runtime.Minimized == minimized then return end
    cancelKeyCaptureUI()
    closeModal(true)
    closeDropdown()
    Pointer.Cancel(true)
    Tooltip.Hide()
    Runtime.Minimized = minimized
    Body.Visible = not minimized
    MinimizeGlyph.Text = minimized and "+" or "−"
    local current = WindowRoot.AbsolutePosition
    local targetHeight = minimized and 64 or Layout.BaseHeight
    WindowRoot.Position = UDim2.fromOffset(current.X, current.Y)
    Motion.Tween(WindowRoot, {
        Size = UDim2.fromOffset(Layout.BaseWidth, targetHeight),
    }, 0.28)
    task.delay(Motion.Reduced and 0.01 or 0.29, function()
        Layout.ClampWindow()
    end)
    Tooltip.Hide()
end

function UI.BindCompareHold(button, icon)
    if not button then return end
    local function begin()
        if Runtime.Compare then return end
        Runtime.Compare = true
        Overlay.CancelFlash()
        button.BackgroundColor3 = Theme.Accent
        button.BackgroundTransparency = 0.12
        button.TextColor3 = Theme.AccentInk
        if icon then icon.SetColor(Theme.AccentInk) end
    end
    local function finish()
        if not Runtime.Compare then return end
        Runtime.Compare = false
        button.BackgroundColor3 = Color3.fromRGB(21, 25, 33)
        button.BackgroundTransparency = 0
        button.TextColor3 = Theme.TextSecondary
        if icon then icon.SetColor(Theme.TextSecondary) end
    end
    connectOwner(button, button.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            begin()
            Pointer.Begin(nil, finish)
        end
    end)
    connectOwner(button, button.Destroying, finish)
end

UI.BindCompareHold(CompareButton, CompareIcon)

connect(DragRegion.InputBegan, function(input)
    if input.UserInputType ~= Enum.UserInputType.MouseButton1
        and input.UserInputType ~= Enum.UserInputType.Touch then
        return
    end
    local startInput = input.Position
    local startPosition = WindowRoot.AbsolutePosition
    local viewport = Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize
        or Vector2.new(1280, 720)
    Pointer.Begin(function(moveInput)
        local delta = moveInput.Position - startInput
        local size = WindowRoot.AbsoluteSize
        local x = clamp(
            startPosition.X + delta.X,
            8,
            math.max(8, viewport.X - size.X - 8)
        )
        local y = clamp(
            startPosition.Y + delta.Y,
            8,
            math.max(8, viewport.Y - size.Y - 8)
        )
        WindowRoot.Position = UDim2.fromOffset(x, y)
        Layout.UserTopLeft = Vector2.new(x, y)
    end, function()
        Layout.ClampWindow()
    end)
end)

--============================================================
-- 28 / PAGES AND NAVIGATION
--============================================================

local function newScope()
    local scope = {
        Connections = {},
        Objects = {},
    }
    function scope:Connect(signal, callback)
        local connection = signal:Connect(callback)
        table.insert(self.Connections, connection)
        return connection
    end
    function scope:AddConnection(connection)
        if connection then
            table.insert(self.Connections, connection)
        end
        return connection
    end
    function scope:AddObject(object)
        if object then
            table.insert(self.Objects, object)
        end
        return object
    end
    function scope:Destroy()
        for _, connection in ipairs(self.Connections) do
            pcall(function() connection:Disconnect() end)
        end
        self.Connections = {}
        for _, object in ipairs(self.Objects) do
            if object and object.Parent then
                pcall(function() object:Destroy() end)
            end
        end
        self.Objects = {}
    end
    return scope
end

function UI.CreatePage(id, title, subtitle, badgeText)
    local page = createCanvas(PageHost, id .. "Page")
    page.Size = UDim2.fromScale(1, 1)
    page.BackgroundTransparency = 1
    page.GroupTransparency = 1
    page.Visible = false
    page.ClipsDescendants = true
    page.ZIndex = 1

    local pageHeader = Instance.new("Frame")
    pageHeader.Name = "PageHeader"
    pageHeader.Size = UDim2.new(1, 0, 0, 80)
    pageHeader.BackgroundTransparency = 1
    pageHeader.BorderSizePixel = 0
    pageHeader.ZIndex = 2
    pageHeader.Parent = page

    local accent = Instance.new("Frame")
    accent.Size = UDim2.fromOffset(3, 18)
    accent.Position = UDim2.fromOffset(24, 17)
    accent.BackgroundColor3 = Theme.Accent
    accent.BorderSizePixel = 0
    accent.ZIndex = 3
    accent.Parent = pageHeader
    round(accent, 2)
    Theme.Bind(function()
        accent.BackgroundColor3 = Theme.Accent
    end)

    local titleLabel = createText(
        pageHeader,
        title,
        21,
        Theme.Text,
        Enum.Font.GothamBold
    )
    titleLabel.Size = UDim2.new(1, -190, 0, 30)
    titleLabel.Position = UDim2.fromOffset(36, 10)
    titleLabel.TextTruncate = Enum.TextTruncate.AtEnd

    local subtitleLabel = createText(
        pageHeader,
        subtitle or "",
        10.5,
        Theme.TextSecondary,
        Enum.Font.Gotham
    )
    subtitleLabel.Size = UDim2.new(1, -190, 0, 20)
    subtitleLabel.Position = UDim2.fromOffset(36, 43)
    subtitleLabel.TextTruncate = Enum.TextTruncate.AtEnd

    local badgeLabel = nil
    local badgeDot = nil
    if badgeText and badgeText ~= "" then
        local badge = Instance.new("Frame")
        badge.AnchorPoint = Vector2.new(1, 0)
        badge.Position = UDim2.new(1, -24, 0, 28)
        badge.Size = UDim2.fromOffset(112, 24)
        badge.BackgroundColor3 = Theme.Card
        badge.BackgroundTransparency = 0.15
        badge.BorderSizePixel = 0
        badge.ZIndex = 3
        badge.Parent = pageHeader
        round(badge, 12)
        addStroke(badge, Theme.BorderSoft, 1, 0.35)

        badgeDot = Instance.new("Frame")
        badgeDot.Size = UDim2.fromOffset(5, 5)
        badgeDot.Position = UDim2.fromOffset(12, 9)
        badgeDot.BackgroundColor3 = Theme.Accent
        badgeDot.BorderSizePixel = 0
        badgeDot.ZIndex = 4
        badgeDot.Parent = badge
        round(badgeDot, 3)
        Theme.Bind(function()
            badgeDot.BackgroundColor3 = Theme.Accent
        end)

        badgeLabel = createText(
            badge,
            badgeText,
            8.5,
            Theme.TextSecondary,
            Enum.Font.GothamBold
        )
        badgeLabel.Size = UDim2.new(1, -30, 1, 0)
        badgeLabel.Position = UDim2.fromOffset(22, 0)
        badgeLabel.TextXAlignment = Enum.TextXAlignment.Center
        badgeLabel.ZIndex = 4
    end

    local scroll = Instance.new("ScrollingFrame")
    scroll.Name = "PageScroll"
    scroll.Position = UDim2.fromOffset(0, 80)
    scroll.Size = UDim2.new(1, 0, 1, -80)
    scroll.BackgroundTransparency = 1
    scroll.BorderSizePixel = 0
    scroll.ScrollBarThickness = 3
    scroll.ScrollBarImageColor3 = Theme.Track
    scroll.ScrollBarImageTransparency = 0.2
    scroll.CanvasSize = UDim2.fromOffset(0, 0)
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scroll.ScrollingDirection = Enum.ScrollingDirection.Y
    scroll.ElasticBehavior = Enum.ElasticBehavior.Never
    scroll.ZIndex = 2
    scroll.Parent = page

    local content = Instance.new("Frame")
    content.Name = "PageContent"
    content.Size = UDim2.new(1, 0, 0, 0)
    content.AutomaticSize = Enum.AutomaticSize.Y
    content.BackgroundTransparency = 1
    content.BorderSizePixel = 0
    content.ZIndex = 3
    content.Parent = scroll
    addPadding(content, 24, 24, 4, 30)
    addVerticalList(content, 12)

    Pages[id] = {
        Page = page,
        Header = pageHeader,
        Scroll = scroll,
        Content = content,
        Title = titleLabel,
        Subtitle = subtitleLabel,
        Badge = badgeLabel,
        BadgeDot = badgeDot,
    }
    return page, content, scroll, Pages[id]
end

function UI.Navigate(id, force)
    local target = Pages[id]
    if not target then return end
    if CurrentPage == id and not force then
        return
    end
    if id ~= "Settings" then
        cancelKeyCaptureUI()
    end
    local previousId = CurrentPage
    local previous = Pages[previousId]
    if previous == target and not force then return end

    PageGeneration += 1
    local generation = PageGeneration
    closeDropdown()
    Tooltip.Hide()

    if previous and previous ~= target then
        previous.Page.ZIndex = 1
    end

    CurrentPage = id
    target.Page.Visible = true
    target.Page.ZIndex = 2
    target.Page.Position = UDim2.fromOffset(8, 0)
    target.Page.GroupTransparency = 1

    for _, entry in pairs(NavItems) do
        entry.Update()
    end

    if previous and previous ~= target then
        if Motion.Reduced then
            previous.Page.GroupTransparency = 1
            previous.Page.Visible = false
        else
            Motion.Tween(previous.Page, { GroupTransparency = 1 }, 0.16)
            Motion.Tween(previous.Page, { Position = UDim2.fromOffset(-8, 0) }, 0.16)
        end
    end

    if Motion.Reduced then
        target.Page.GroupTransparency = 0
        target.Page.Position = UDim2.fromOffset(0, 0)
    else
        Motion.Tween(target.Page, { GroupTransparency = 0 }, 0.22)
        Motion.Tween(target.Page, { Position = UDim2.fromOffset(0, 0) }, 0.24)
    end

    task.delay(Motion.Reduced and 0.01 or 0.26, function()
        if Runtime.Closed or generation ~= PageGeneration then return end
        if previous and previous ~= target and CurrentPage ~= previousId then
            previous.Page.Visible = false
            previous.Page.Position = UDim2.fromOffset(0, 0)
        end
    end)

    if target.OnShown then
        pcall(target.OnShown)
    end
    if UI.RefreshConditional then
        UI.RefreshConditional()
    end
    Events.PageChanged:Fire(id)
end

function UI.CloseTopLayer()
    if CurrentDropdown then
        closeDropdown()
        return true
    end
    if CurrentModal then
        closeModal(false)
        return true
    end
    return false
end

function UI.PulseControl(control)
    if not control then return end
    if control.page and CurrentPage ~= control.page then
        UI.Navigate(control.page)
    end
    task.delay(0.24, function()
        local row = control.row
        if not row or not row.Parent then return end
        row.BackgroundTransparency = 0.86
        row.BackgroundColor3 = Theme.Accent
        Motion.Tween(row, { BackgroundTransparency = 1 }, 0.85)
    end)
end

function UI.RefreshConditional()
    for _, control in ipairs(ControlOrder) do
        if control.row and control.row.Parent then
            control.row.Visible = control:IsVisible()
        end
    end
end

--============================================================
-- 29 / DASHBOARD
--============================================================

;(function()
local dashPage, dashContent, dashScroll, dashMeta = UI.CreatePage(
    "Dashboard",
    "Dashboard",
    "A live overview of your visual environment, active systems, and personal audio.",
    "LIVE"
)

local Hero = Instance.new("Frame")
Hero.Name = "Hero"
Hero.Size = UDim2.new(1, 0, 0, 170)
Hero.BackgroundColor3 = Color3.fromRGB(19, 25, 33)
Hero.BorderSizePixel = 0
Hero.ClipsDescendants = true
Hero.ZIndex = 2
Hero.Parent = dashContent
round(Hero, 14)
addStroke(Hero, Theme.Border, 1, 0.28)

local heroGradient = Instance.new("UIGradient")
heroGradient.Rotation = 20
heroGradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(26, 34, 44)),
    ColorSequenceKeypoint.new(0.58, Color3.fromRGB(16, 21, 28)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(12, 16, 22)),
})
heroGradient.Parent = Hero

local heroGlow = Instance.new("Frame")
heroGlow.AnchorPoint = Vector2.new(0.5, 0.5)
heroGlow.Position = UDim2.new(0.86, 0, 0.20, 0)
heroGlow.Size = UDim2.fromOffset(260, 260)
heroGlow.BackgroundColor3 = Theme.Accent
heroGlow.BackgroundTransparency = 0.90
heroGlow.BorderSizePixel = 0
heroGlow.ZIndex = 1
heroGlow.Parent = Hero
round(heroGlow, 130)
Theme.Bind(function()
    heroGlow.BackgroundColor3 = Theme.Accent
end)

local heroGlowSmall = Instance.new("Frame")
heroGlowSmall.AnchorPoint = Vector2.new(0.5, 0.5)
heroGlowSmall.Position = UDim2.new(0.93, 0, 0.80, 0)
heroGlowSmall.Size = UDim2.fromOffset(110, 110)
heroGlowSmall.BackgroundColor3 = Theme.Info
heroGlowSmall.BackgroundTransparency = 0.92
heroGlowSmall.BorderSizePixel = 0
heroGlowSmall.ZIndex = 1
heroGlowSmall.Parent = Hero
round(heroGlowSmall, 55)

local heroKicker = createText(
    Hero,
    "VISUAL CONTROL REBORN",
    8.5,
    Theme.Accent,
    Enum.Font.GothamBold
)
heroKicker.Size = UDim2.fromOffset(260, 16)
heroKicker.Position = UDim2.fromOffset(20, 18)
heroKicker.ZIndex = 3
Theme.Bind(function()
    heroKicker.TextColor3 = Theme.Accent
end)

local heroTitle = createText(
    Hero,
    "Your world, reimagined.",
    24,
    Theme.Text,
    Enum.Font.GothamBold
)
heroTitle.Size = UDim2.new(1, -270, 0, 34)
heroTitle.Position = UDim2.fromOffset(20, 36)
heroTitle.TextTruncate = Enum.TextTruncate.AtEnd
heroTitle.ZIndex = 3

local heroSubtitle = createText(
    Hero,
    "Client-side atmosphere and image control with zero gameplay impact.",
    10.5,
    Theme.TextSecondary,
    Enum.Font.Gotham
)
heroSubtitle.Size = UDim2.new(1, -270, 0, 20)
heroSubtitle.Position = UDim2.fromOffset(20, 72)
heroSubtitle.TextTruncate = Enum.TextTruncate.AtEnd
heroSubtitle.ZIndex = 3

local HeroStatus = Instance.new("Frame")
HeroStatus.AnchorPoint = Vector2.new(1, 0)
HeroStatus.Position = UDim2.new(1, -20, 0, 20)
HeroStatus.Size = UDim2.fromOffset(210, 96)
HeroStatus.BackgroundColor3 = Color3.fromRGB(11, 15, 20)
HeroStatus.BackgroundTransparency = 0.18
HeroStatus.BorderSizePixel = 0
HeroStatus.ZIndex = 3
HeroStatus.Parent = Hero
round(HeroStatus, 11)
addStroke(HeroStatus, Theme.Border, 1, 0.35)

local heroStatusLabel = createText(
    HeroStatus,
    "ACTIVE PRESET",
    8,
    Theme.TextMuted,
    Enum.Font.GothamBold
)
heroStatusLabel.Size = UDim2.new(1, -24, 0, 16)
heroStatusLabel.Position = UDim2.fromOffset(12, 10)

local heroPresetName = createText(
    HeroStatus,
    ActivePreset,
    17,
    Theme.Text,
    Enum.Font.GothamBold
)
heroPresetName.Size = UDim2.new(1, -24, 0, 24)
heroPresetName.Position = UDim2.fromOffset(12, 29)
heroPresetName.TextTruncate = Enum.TextTruncate.AtEnd

local heroEnvironment = createText(
    HeroStatus,
    "Environment: scanning",
    9.5,
    Theme.TextSecondary,
    Enum.Font.Gotham
)
heroEnvironment.Size = UDim2.new(1, -24, 0, 18)
heroEnvironment.Position = UDim2.fromOffset(12, 56)
heroEnvironment.TextTruncate = Enum.TextTruncate.AtEnd

local heroMiniStatus = createText(
    HeroStatus,
    "Weather: Clear",
    9,
    Theme.TextMuted,
    Enum.Font.Gotham
)
heroMiniStatus.Size = UDim2.new(1, -24, 0, 16)
heroMiniStatus.Position = UDim2.fromOffset(12, 73)
heroMiniStatus.TextTruncate = Enum.TextTruncate.AtEnd

local heroButtonRow = Instance.new("Frame")
heroButtonRow.Position = UDim2.fromOffset(20, 120)
heroButtonRow.Size = UDim2.new(1, -40, 0, 32)
heroButtonRow.BackgroundTransparency = 1
heroButtonRow.BorderSizePixel = 0
heroButtonRow.ZIndex = 4
heroButtonRow.Parent = Hero
addHorizontalList(heroButtonRow, 6)

local heroBrowse = UI.Button(heroButtonRow, {
    text = "Browse presets",
    variant = "primary",
    size = UDim2.new(1 / 3, -4, 1, 0),
    textSize = 10,
    onClick = function()
        UI.Navigate("Presets")
    end,
})
heroBrowse.LayoutOrder = 1

local heroWeather = UI.Button(heroButtonRow, {
    text = "Cycle weather",
    variant = "secondary",
    size = UDim2.new(1 / 3, -4, 1, 0),
    textSize = 10,
    onClick = function()
        if UI.CycleWeather then UI.CycleWeather() end
    end,
})
heroWeather.LayoutOrder = 2

local heroCompare = UI.Button(heroButtonRow, {
    text = "Hold to compare",
    variant = "ghost",
    size = UDim2.new(1 / 3, -4, 1, 0),
    textSize = 10,
    tooltip = "Hold to temporarily restore the original rendering",
})
heroCompare.LayoutOrder = 3
UI.BindCompareHold(heroCompare)

local function updateHeroResponsive()
    HeroStatus.Visible = Hero.AbsoluteSize.X >= 650
    heroTitle.Size = HeroStatus.Visible
        and UDim2.new(1, -270, 0, 34)
        or UDim2.new(1, -40, 0, 34)
    heroSubtitle.Size = heroTitle.Size
end
connect(Hero:GetPropertyChangedSignal("AbsoluteSize"), updateHeroResponsive)
task.defer(updateHeroResponsive)

local metricsGrid = Instance.new("Frame")
metricsGrid.Name = "MetricsGrid"
metricsGrid.BackgroundTransparency = 1
metricsGrid.BorderSizePixel = 0
metricsGrid.Parent = dashContent
UI.Grid(metricsGrid, {
    minimumWidth = 180,
    maximumColumns = 3,
    cellHeight = 106,
    gap = 10,
})

local function dashboardMetric(parent, title, accentColor)
    local card = Instance.new("Frame")
    card.BackgroundColor3 = Theme.Card
    card.BorderSizePixel = 0
    card.ZIndex = 2
    card.Parent = parent
    round(card, 11)
    addStroke(card, Theme.BorderSoft, 1, 0.2)
    addPadding(card, 14, 14, 12, 12)

    local label = createText(
        card,
        title,
        8.5,
        Theme.TextMuted,
        Enum.Font.GothamBold
    )
    label.Size = UDim2.new(1, 0, 0, 15)

    local value = createText(
        card,
        "—",
        18,
        Theme.Text,
        Enum.Font.GothamBold
    )
    value.Size = UDim2.new(1, 0, 0, 27)
    value.Position = UDim2.fromOffset(0, 17)
    value.TextTruncate = Enum.TextTruncate.AtEnd

    local detail = createText(
        card,
        "Waiting for data",
        9,
        Theme.TextSecondary,
        Enum.Font.Gotham
    )
    detail.Size = UDim2.new(1, 0, 0, 16)
    detail.Position = UDim2.fromOffset(0, 45)
    detail.TextTruncate = Enum.TextTruncate.AtEnd

    local track = Instance.new("Frame")
    track.Position = UDim2.fromOffset(0, 76)
    track.Size = UDim2.new(1, 0, 0, 4)
    track.BackgroundColor3 = Theme.Track
    track.BorderSizePixel = 0
    track.Parent = card
    round(track, 2)

    local fill = Instance.new("Frame")
    fill.Size = UDim2.new(0, 0, 1, 0)
    fill.BackgroundColor3 = accentColor
    fill.BorderSizePixel = 0
    fill.Parent = track
    round(fill, 2)

    return {
        Card = card,
        Value = value,
        Detail = detail,
        Fill = fill,
    }
end

local dashEnvironmentMetric = dashboardMetric(metricsGrid, "ENVIRONMENT", Theme.Accent)
local dashPerformanceMetric = dashboardMetric(metricsGrid, "PERFORMANCE", Theme.Info)
local dashWeatherMetric = dashboardMetric(metricsGrid, "CONDITION", Theme.Warning)

local quickCard, quickBody = UI.Card(
    dashContent,
    "Quick actions",
    "Change the atmosphere without leaving the dashboard."
)
local quickGrid = Instance.new("Frame")
quickGrid.Size = UDim2.new(1, 0, 0, 0)
quickGrid.BackgroundTransparency = 1
quickGrid.BorderSizePixel = 0
quickGrid.Parent = quickBody
UI.Grid(quickGrid, {
    minimumWidth = 145,
    maximumColumns = 4,
    cellHeight = 34,
    gap = 7,
})

local dashQuickPlay
local quickButtons = {
    {
        text = "Next preset",
        variant = "secondary",
        onClick = function()
            if UI.CyclePreset then UI.CyclePreset() end
        end,
    },
    {
        text = "Cycle weather",
        variant = "secondary",
        onClick = function()
            if UI.CycleWeather then UI.CycleWeather() end
        end,
    },
    {
        text = "Play music",
        variant = "secondary",
        onClick = function()
            local ok, err = AudioManager.TogglePlay()
            if not ok and err then
                Notify("Audio", err, "warning", 2.5)
            end
        end,
    },
    {
        text = "Open settings",
        variant = "ghost",
        onClick = function()
            UI.Navigate("Settings")
        end,
    },
}
for _, definition in ipairs(quickButtons) do
    local button = UI.Button(quickGrid, {
        text = definition.text,
        variant = definition.variant,
        size = UDim2.new(1, 0, 0, 34),
        textSize = 10,
        onClick = definition.onClick,
    })
    if definition.text == "Play music" then
        dashQuickPlay = button
    end
end

local systemsCard, systemsBody = UI.Card(
    dashContent,
    "Active systems",
    "Each system owns only its own resources and can be bypassed independently."
)

local dashSystemRows = {}
local function dashboardSystemRow(title, iconName, page)
    local row = Instance.new("TextButton")
    row.Size = UDim2.new(1, 0, 0, 38)
    row.BackgroundColor3 = Theme.Card
    row.BackgroundTransparency = 1
    row.BorderSizePixel = 0
    row.AutoButtonColor = false
    row.Text = ""
    row.Parent = systemsBody
    round(row, 7)

    local icon = UI.Icon(iconName, 14, Theme.TextMuted, row)
    icon.Frame.Position = UDim2.fromOffset(4, 12)

    local label = createText(
        row,
        title,
        11,
        Theme.TextSecondary,
        Enum.Font.GothamMedium
    )
    label.Size = UDim2.new(1, -160, 1, 0)
    label.Position = UDim2.fromOffset(27, 0)

    local value = createText(
        row,
        "—",
        9.5,
        Theme.TextMuted,
        Enum.Font.Code
    )
    value.Size = UDim2.new(0, 106, 1, 0)
    value.Position = UDim2.new(1, -128, 0, 0)
    value.TextXAlignment = Enum.TextXAlignment.Right
    value.TextTruncate = Enum.TextTruncate.AtEnd

    local dot = Instance.new("Frame")
    dot.Size = UDim2.fromOffset(5, 5)
    dot.Position = UDim2.new(1, -15, 0.5, -2)
    dot.BackgroundColor3 = Theme.TextMuted
    dot.BorderSizePixel = 0
    dot.Parent = row
    round(dot, 3)

    connect(row.MouseEnter, function()
        Motion.Tween(row, { BackgroundTransparency = 0.55 }, 0.12)
    end)
    connect(row.MouseLeave, function()
        Motion.Tween(row, { BackgroundTransparency = 1 }, 0.14)
    end)
    connect(row.MouseButton1Click, function()
        UI.Navigate(page)
    end)
    Tooltip.Attach(row, "Open " .. page)

    local entry = {
        Value = value,
        Dot = dot,
        Icon = icon,
        Label = label,
    }
    dashSystemRows[page] = entry
    return entry
end

dashboardSystemRow("Graphics engine", "graphics", "Graphics")
dashboardSystemRow("Atmosphere & clouds", "atmosphere", "Atmosphere")
dashboardSystemRow("Weather engine", "weather", "Weather")
dashboardSystemRow("Environment sensing", "dashboard", "Performance")
dashboardSystemRow("Personal audio", "audio", "Audio")

local pinnedCard, pinnedBody = UI.Card(
    dashContent,
    "Pinned controls",
    "Use the star beside any setting to pin it here."
)
local pinnedContainer = Instance.new("Frame")
pinnedContainer.Name = "PinnedContainer"
pinnedContainer.Size = UDim2.new(1, 0, 0, 0)
pinnedContainer.AutomaticSize = Enum.AutomaticSize.Y
pinnedContainer.BackgroundTransparency = 1
pinnedContainer.BorderSizePixel = 0
pinnedContainer.Parent = pinnedBody
addVerticalList(pinnedContainer, 2)

local pinnedScope = nil
local function rebuildPinnedControls()
    if pinnedScope then
        pinnedScope:Destroy()
    end
    pinnedScope = newScope()
    clearGuiChildren(pinnedContainer)

    if #Favorites == 0 then
        local empty = createText(
            pinnedContainer,
            "No controls pinned yet.",
            10.5,
            Theme.TextSecondary,
            Enum.Font.Gotham
        )
        empty.Size = UDim2.new(1, 0, 0, 22)
        empty.AutomaticSize = Enum.AutomaticSize.Y
        empty.TextWrapped = true
        empty.LayoutOrder = 1
        pinnedScope:AddObject(empty)

        local browse = UI.Button(pinnedContainer, {
            text = "Browse graphics controls",
            variant = "secondary",
            size = UDim2.new(0, 176, 0, 32),
            textSize = 10,
            onClick = function()
                UI.Navigate("Graphics")
            end,
        })
        browse.LayoutOrder = 2
        pinnedScope:AddObject(browse)
        return
    end

    for index, id in ipairs(Favorites) do
        local control = Controls[id]
        if control then
            local row = Instance.new("Frame")
            row.Size = UDim2.new(1, 0, 0, 42)
            row.BackgroundTransparency = 1
            row.BorderSizePixel = 0
            row.LayoutOrder = index
            row.Parent = pinnedContainer
            pinnedScope:AddObject(row)

            local title = Instance.new("TextButton")
            title.Size = UDim2.new(1, -118, 1, 0)
            title.BackgroundTransparency = 1
            title.BorderSizePixel = 0
            title.AutoButtonColor = false
            title.Text = ""
            title.TextXAlignment = Enum.TextXAlignment.Left
            title.Parent = row
            local titleLabel = createText(
                title,
                control.title,
                11,
                Theme.Text,
                Enum.Font.GothamMedium
            )
            titleLabel.Size = UDim2.fromScale(1, 1)
            titleLabel.TextTruncate = Enum.TextTruncate.AtEnd
            pinnedScope:Connect(title.MouseButton1Click, function()
                UI.PulseControl(control)
            end)
            Tooltip.Attach(title, control.description)

            if control.kind == "toggle" then
                local switch = Instance.new("TextButton")
                switch.Size = UDim2.fromOffset(36, 20)
                switch.Position = UDim2.new(1, -36, 0.5, -10)
                switch.BackgroundColor3 = Theme.Track
                switch.BorderSizePixel = 0
                switch.AutoButtonColor = false
                switch.Text = ""
                switch.Parent = row
                round(switch, 10)
                local knob = Instance.new("Frame")
                knob.Size = UDim2.fromOffset(14, 14)
                knob.Position = UDim2.fromOffset(3, 3)
                knob.BackgroundColor3 = Theme.TextSecondary
                knob.BorderSizePixel = 0
                knob.Parent = switch
                round(knob, 7)

                local function refresh()
                    local value = control:Get() == true
                    Motion.Tween(switch, {
                        BackgroundColor3 = value and Theme.Accent or Theme.Track,
                    }, 0.16)
                    Motion.Tween(knob, {
                        Position = value
                            and UDim2.fromOffset(19, 3)
                            or UDim2.fromOffset(3, 3),
                        BackgroundColor3 = value and Theme.AccentInk or Theme.TextSecondary,
                    }, 0.16)
                end
                pinnedScope:AddConnection(control:Bind(refresh))
                pinnedScope:Connect(switch.MouseButton1Click, function()
                    if not control:IsDisabled() then
                        control:Set(not control:Get())
                    end
                end)
            elseif control.kind == "slider" then
                local valueLabel = createText(
                    row,
                    control.format(control:Get()),
                    9,
                    Theme.TextSecondary,
                    Enum.Font.Code
                )
                valueLabel.Size = UDim2.fromOffset(68, 20)
                valueLabel.Position = UDim2.new(1, -108, 0.5, -10)
                valueLabel.TextXAlignment = Enum.TextXAlignment.Right
                pinnedScope:AddObject(valueLabel)

                local minus = UI.GlyphButton(row, {
                    glyph = "−",
                    glyphSize = 13,
                    size = UDim2.fromOffset(22, 22),
                    variant = "secondary",
                    onClick = function()
                        control:Set(control:Get() - (control.step or 0.01))
                    end,
                })
                minus.Position = UDim2.new(1, -58, 0.5, -11)
                pinnedScope:AddObject(minus)

                local plus = UI.GlyphButton(row, {
                    glyph = "+",
                    glyphSize = 13,
                    size = UDim2.fromOffset(22, 22),
                    variant = "secondary",
                    onClick = function()
                        control:Set(control:Get() + (control.step or 0.01))
                    end,
                })
                plus.Position = UDim2.new(1, -34, 0.5, -11)
                pinnedScope:AddObject(plus)

                pinnedScope:AddConnection(control:Bind(function(value)
                    valueLabel.Text = control.format(value)
                end))
            elseif control.kind == "color" then
                local swatch = Instance.new("TextButton")
                swatch.Size = UDim2.fromOffset(46, 24)
                swatch.Position = UDim2.new(1, -46, 0.5, -12)
                swatch.BackgroundColor3 = control:Get()
                swatch.BorderSizePixel = 0
                swatch.AutoButtonColor = false
                swatch.Text = ""
                swatch.Parent = row
                round(swatch, 6)
                addStroke(swatch, Theme.Border, 1, 0.1)
                pinnedScope:AddObject(swatch)
                pinnedScope:AddConnection(control:Bind(function(value)
                    swatch.BackgroundColor3 = value
                end))
                pinnedScope:Connect(swatch.MouseButton1Click, function()
                    UI.OpenColorPicker(control.title, control:Get(), function(color)
                        control:Set(color)
                    end)
                end)
            elseif control.kind == "select" then
                local selectButton = UI.Button(row, {
                    text = tostring(control:Get()),
                    variant = "secondary",
                    size = UDim2.fromOffset(104, 26),
                    textSize = 9,
                })
                selectButton.Position = UDim2.new(1, -104, 0.5, -13)
                pinnedScope:AddObject(selectButton)
                pinnedScope:AddConnection(control:Bind(function(newValue)
                    selectButton.Text = tostring(newValue)
                end))
                pinnedScope:Connect(selectButton.MouseButton1Click, function()
                    UI.OpenDropdown(
                        selectButton,
                        control.options,
                        control:Get(),
                        function(value)
                            control:Set(value)
                        end,
                        120
                    )
                end)
            else
                local value = createText(
                    row,
                    tostring(control:Get()),
                    9,
                    Theme.TextSecondary,
                    Enum.Font.Code
                )
                value.Size = UDim2.fromOffset(100, 20)
                value.Position = UDim2.new(1, -100, 0.5, -10)
                value.TextXAlignment = Enum.TextXAlignment.Right
                pinnedScope:AddObject(value)
                pinnedScope:AddConnection(control:Bind(function(newValue)
                    value.Text = tostring(newValue)
                end))
            end

            if index < #Favorites then
                local divider = Instance.new("Frame")
                divider.Size = UDim2.new(1, 0, 0, 1)
                divider.Position = UDim2.new(0, 0, 1, 0)
                divider.BackgroundColor3 = Theme.BorderSoft
                divider.BackgroundTransparency = 0.4
                divider.BorderSizePixel = 0
                divider.Parent = row
                pinnedScope:AddObject(divider)
            end
        end
    end
end

dashMeta.OnShown = rebuildPinnedControls

local function updateDashboard()
    heroPresetName.Text = ActivePreset
    heroEnvironment.Text = "Environment: " .. Environment.Classification
    heroMiniStatus.Text = "Weather: " .. S.weather
        .. "  ·  " .. string.format("%.2fx", S.weatherIntensity)
    dashMeta.Badge.Text = timeOfDayLabel(
        S.timeOverride and S.clockTime or Lighting.ClockTime
    ) .. "  ·  LIVE"

    dashEnvironmentMetric.Value.Text = Environment.Classification
    dashEnvironmentMetric.Detail.Text = string.format(
        "Shelter %d%%  ·  Room %d%%",
        math.floor(Environment.Shelter * 100 + 0.5),
        math.floor(Environment.RoomSize * 100 + 0.5)
    )
    Motion.Tween(dashEnvironmentMetric.Fill, {
        Size = UDim2.new(clamp01(Environment.Indoor), 0, 1, 0),
    }, 0.3)

    dashPerformanceMetric.Value.Text = string.format(
        "%.0f FPS",
        Metrics.SmoothedFPS
    )
    dashPerformanceMetric.Detail.Text = string.format(
        "%.1f ms  ·  %s profile",
        Metrics.FrameMs,
        S.quality
    )
    Motion.Tween(dashPerformanceMetric.Fill, {
        Size = UDim2.new(clamp01(Metrics.SmoothedFPS / 120), 0, 1, 0),
    }, 0.3)

    dashWeatherMetric.Value.Text = S.weather
    dashWeatherMetric.Detail.Text = string.format(
        "%d particles est.  ·  %.2fx",
        math.floor(Metrics.EstimatedParticles + 0.5),
        S.weatherIntensity
    )
    local weatherFraction = S.weather == "Clear"
        and 0.04
        or clamp01(S.weatherIntensity / 2)
    Motion.Tween(dashWeatherMetric.Fill, {
        Size = UDim2.new(weatherFraction, 0, 1, 0),
    }, 0.3)

    local graphicsRow = dashSystemRows.Graphics
    if graphicsRow then
        graphicsRow.Value.Text = S.effectsEnabled and "Active" or "Bypassed"
        graphicsRow.Dot.BackgroundColor3 = S.effectsEnabled
            and Theme.Success or Theme.TextMuted
        graphicsRow.Icon.SetColor(S.effectsEnabled and Theme.Accent or Theme.TextMuted)
    end
    local atmosphereRow = dashSystemRows.Atmosphere
    if atmosphereRow then
        atmosphereRow.Value.Text = S.atmosphereEnabled and "Atmosphere on" or "Off"
        atmosphereRow.Dot.BackgroundColor3 = S.atmosphereEnabled
            and Theme.Success or Theme.TextMuted
        atmosphereRow.Icon.SetColor(S.atmosphereEnabled and Theme.Accent or Theme.TextMuted)
    end
    local weatherRow = dashSystemRows.Weather
    if weatherRow then
        weatherRow.Value.Text = S.weather
        weatherRow.Dot.BackgroundColor3 = S.weather == "Clear"
            and Theme.TextMuted or Theme.Warning
        weatherRow.Icon.SetColor(S.weather == "Clear" and Theme.TextMuted or Theme.Warning)
    end
    local environmentRow = dashSystemRows.Performance
    if environmentRow then
        environmentRow.Value.Text = Environment.Classification
        environmentRow.Dot.BackgroundColor3 = Theme.Info
        environmentRow.Icon.SetColor(Theme.Info)
    end
    local audioRow = dashSystemRows.Audio
    if audioRow then
        local playing = AudioManager.IsPlaying()
        local status = playing and "Playing"
            or (AudioManager.Status == "Paused" and "Paused" or "Idle")
        audioRow.Value.Text = status
        audioRow.Dot.BackgroundColor3 = playing
            and Theme.Success or Theme.TextMuted
        audioRow.Icon.SetColor(playing and Theme.Accent or Theme.TextMuted)
    end

    if dashQuickPlay then
        dashQuickPlay.Text = AudioManager.IsPlaying()
            and "Pause music"
            or "Play music"
    end
end

UI.RefreshDashboard = updateDashboard
dashMeta.OnShown = function()
    rebuildPinnedControls()
    updateDashboard()
end
end)()

--============================================================
-- 30 / GRAPHICS PAGE
--============================================================

;(function()
function UI.CollapsibleCard(parent, title, description, defaultOpen)
    local card = Instance.new("Frame")
    card.Size = UDim2.new(1, 0, 0, 0)
    card.AutomaticSize = Enum.AutomaticSize.Y
    card.BackgroundColor3 = Theme.Card
    card.BorderSizePixel = 0
    card.ClipsDescendants = false
    card.ZIndex = 2
    card.Parent = parent
    round(card, 12)
    addStroke(card, Theme.BorderSoft, 1, 0.15)
    addPadding(card, 16, 16, 13, 15)
    addVerticalList(card, 8)

    local header = Instance.new("TextButton")
    header.Size = UDim2.new(1, 0, 0, 26)
    header.BackgroundTransparency = 1
    header.BorderSizePixel = 0
    header.AutoButtonColor = false
    header.Text = ""
    header.ZIndex = 3
    header.Parent = card

    local titleLabel = createText(
        header,
        title,
        13,
        Theme.Text,
        Enum.Font.GothamBold
    )
    titleLabel.Size = UDim2.new(1, -30, 1, 0)
    titleLabel.TextTruncate = Enum.TextTruncate.AtEnd

    local chevron = UI.Glyph(
        header,
        defaultOpen == false and "▾" or "▴",
        12,
        Theme.TextMuted
    )
    chevron.Size = UDim2.fromOffset(24, 26)
    chevron.Position = UDim2.new(1, -24, 0, 0)
    chevron.BackgroundTransparency = 1

    local descriptionLabel = nil
    if description and description ~= "" then
        descriptionLabel = createText(
            card,
            description,
            10,
            Theme.TextSecondary,
            Enum.Font.Gotham
        )
        descriptionLabel.Size = UDim2.new(1, 0, 0, 0)
        descriptionLabel.AutomaticSize = Enum.AutomaticSize.Y
        descriptionLabel.TextWrapped = true
        descriptionLabel.TextYAlignment = Enum.TextYAlignment.Top
    end

    local body = createCanvas(card, "CollapsibleBody")
    body.Size = UDim2.new(1, 0, 0, 0)
    body.AutomaticSize = Enum.AutomaticSize.Y
    body.GroupTransparency = 0
    body.ZIndex = 3
    addVerticalList(body, 2)

    local open = defaultOpen ~= false
    body.Visible = open
    chevron.Text = open and "▴" or "▾"

    local function toggle()
        open = not open
        chevron.Text = open and "▴" or "▾"
        if open then
            body.Visible = true
            body.GroupTransparency = 1
            Motion.Tween(body, { GroupTransparency = 0 }, 0.20)
        else
            if Motion.Reduced then
                body.Visible = false
            else
                Motion.Tween(body, { GroupTransparency = 1 }, 0.14)
                task.delay(0.15, function()
                    if not open and body.Parent then
                        body.Visible = false
                    end
                end)
            end
        end
    end

    connectOwner(header, header.MouseButton1Click, toggle)
    Tooltip.Attach(header, "Expand or collapse this group")
    return card, body
end

local graphicsPage, graphicsContent, graphicsScroll, graphicsMeta = UI.CreatePage(
    "Graphics",
    "Graphics",
    "Owned post-processing, color grading, bloom, and screen finishing.",
    "POST FX"
)

local graphicsEngineCard, graphicsEngineBody = UI.Card(
    graphicsContent,
    "Visual engine",
    "Visual Control creates its own post-processing effects. Existing game effects are never modified."
)
UI.AddControl(graphicsEngineBody, Controls["fx.master"])

local graphicsCompare = UI.Button(graphicsEngineBody, {
    text = "Hold to compare original",
    variant = "ghost",
    size = UDim2.new(1, 0, 0, 32),
    textSize = 10,
    tooltip = "Temporarily bypass every Visual Control visual enhancement",
})
UI.BindCompareHold(graphicsCompare)

local graphicsNote = createText(
    graphicsEngineBody,
    "Comparison restores the exact environment snapshot taken before Visual Control changed anything.",
    9.5,
    Theme.TextMuted,
    Enum.Font.Gotham
)
graphicsNote.Size = UDim2.new(1, 0, 0, 0)
graphicsNote.AutomaticSize = Enum.AutomaticSize.Y
graphicsNote.TextWrapped = true
graphicsNote.TextYAlignment = Enum.TextYAlignment.Top

local toneCard, toneBody = UI.Card(
    graphicsContent,
    "Color & tone",
    "Balance contrast, image brightness, saturation, and a global tint."
)
UI.AddControl(toneBody, Controls["fx.contrast"])
UI.AddControl(toneBody, Controls["fx.brightness"])
UI.AddControl(toneBody, Controls["fx.saturation"])
UI.AddControl(toneBody, Controls["fx.tint"])

local bloomCard, bloomBody = UI.Card(
    graphicsContent,
    "Bloom & sunlight",
    "Shape the glow of bright highlights and add subtle sun rays."
)
UI.AddControl(bloomBody, Controls["fx.bloom"])
UI.AddControl(bloomBody, Controls["fx.sunRays"])
UI.AddControl(bloomBody, Controls["fx.sunRaysIntensity"])

local advancedBloom, advancedBloomBody = UI.CollapsibleCard(
    graphicsContent,
    "Advanced bloom shaping",
    "Fine-tune spread and the brightness threshold that starts the bloom effect.",
    true
)
UI.AddControl(advancedBloomBody, Controls["fx.bloomSize"])
UI.AddControl(advancedBloomBody, Controls["fx.bloomThreshold"])

local vignetteCard, vignetteBody = UI.Card(
    graphicsContent,
    "Screen finishing",
    "A subtle edge vignette rendered as a non-interactive overlay above the game view."
)
UI.AddControl(vignetteBody, Controls["fx.vignette"])
UI.AddControl(vignetteBody, Controls["fx.vignetteStrength"])
end)()

--============================================================
-- 31 / LIGHTING PAGE
--============================================================

;(function()
local lightingPage, lightingContent, lightingScroll, lightingMeta = UI.CreatePage(
    "Lighting",
    "Lighting",
    "Local time, eye adaptation, weather grading, and environment illumination.",
    "REALTIME"
)

local timeCard, timeBody = UI.Card(
    lightingContent,
    "Time of day",
    "Lock a local time or jump to a curated lighting moment. The original clock time is restored when the override is disabled."
)
UI.AddControl(timeBody, Controls["lighting.timeOverride"])

local timeSegmented
timeSegmented = UI.Segmented(
    timeBody,
    {
        { label = "Dawn", value = 6.0 },
        { label = "Noon", value = 14.0 },
        { label = "Golden", value = 18.1 },
        { label = "Midnight", value = 0.0 },
    },
    S.clockTime,
    function(value)
        if not S.timeOverride then
            Controls["lighting.timeOverride"]:Set(true)
        end
        Controls["lighting.clockTime"]:Set(value)
        timeSegmented.SetValue(value)
    end
)
UI.AddControl(timeBody, Controls["lighting.clockTime"])

local timeNote = createText(
    timeBody,
    "The time slider previews a value even when the override is off.",
    9.5,
    Theme.TextMuted,
    Enum.Font.Gotham
)
timeNote.Size = UDim2.new(1, 0, 0, 0)
timeNote.AutomaticSize = Enum.AutomaticSize.Y
timeNote.TextWrapped = true
timeNote.TextYAlignment = Enum.TextYAlignment.Top

local exposureCard, exposureBody = UI.Card(
    lightingContent,
    "Adaptive exposure",
    "A heuristic eye-adaptation model based on time, weather, shelter, and enclosure. It does not read framebuffer luminance."
)
UI.AddControl(exposureBody, Controls["lighting.adaptiveExposure"])
UI.AddControl(exposureBody, Controls["lighting.adaptationSpeed"])
UI.AddControl(exposureBody, Controls["lighting.exposureBias"])

local gradingCard, gradingBody = UI.Card(
    lightingContent,
    "Color grading",
    "Coordinate time-of-day warmth, overcast coolness, storm desaturation, and enhanced local illumination."
)
UI.AddControl(gradingBody, Controls["lighting.autoGrade"])
UI.AddControl(gradingBody, Controls["lighting.gradingStrength"])
UI.AddControl(gradingBody, Controls["lighting.enhanced"])

local lightingInfo = createText(
    gradingBody,
    "Environment lighting changes are local to this client and are restored when the engine is bypassed or unloaded.",
    9.5,
    Theme.TextMuted,
    Enum.Font.Gotham
)
lightingInfo.Size = UDim2.new(1, 0, 0, 0)
lightingInfo.AutomaticSize = Enum.AutomaticSize.Y
lightingInfo.TextWrapped = true
lightingInfo.TextYAlignment = Enum.TextYAlignment.Top

UI.RefreshLightingPage = function()
    if not timeSegmented then return end
    local matched = false
    for _, value in ipairs({ 6.0, 14.0, 18.1, 0.0 }) do
        if math.abs(value - S.clockTime) < 0.05 then
            matched = true
            timeSegmented.SetValue(value)
            break
        end
    end
    if not matched then
        timeSegmented.SetValue(nil)
    end
end

connect(Events.ControlChanged, function(control)
    if control.id == "lighting.clockTime" then
        UI.RefreshLightingPage()
    end
end)
end)()

--============================================================
-- 32 / ATMOSPHERE PAGE
--============================================================

;(function()
local atmospherePage, atmosphereContent, atmosphereScroll, atmosphereMeta = UI.CreatePage(
    "Atmosphere",
    "Atmosphere",
    "Aerial perspective, atmospheric scattering, and dynamic cloud layers.",
    "ENVIRONMENT"
)

local atmosphereCard, atmosphereBody = UI.Card(
    atmosphereContent,
    "Atmospheric scattering",
    "Adds depth and aerial perspective through Roblox Atmosphere. Existing game-owned values are snapshotted before editing."
)
UI.AddControl(atmosphereBody, Controls["atmos.enabled"])
UI.AddControl(atmosphereBody, Controls["atmos.density"])
UI.AddControl(atmosphereBody, Controls["atmos.haze"])
UI.AddControl(atmosphereBody, Controls["atmos.glare"])
UI.AddControl(atmosphereBody, Controls["atmos.color"])
UI.AddControl(atmosphereBody, Controls["atmos.weatherResponsive"])

local cloudCard, cloudBody = UI.Card(
    atmosphereContent,
    "Dynamic clouds",
    "Control cloud cover, density, and material color. The layer responds to storm, snow, fog, and overcast conditions."
)
UI.AddControl(cloudBody, Controls["clouds.enabled"])
UI.AddControl(cloudBody, Controls["clouds.cover"])
UI.AddControl(cloudBody, Controls["clouds.density"])
UI.AddControl(cloudBody, Controls["clouds.color"])

local atmosphereStatusCard, atmosphereStatusBody = UI.Card(
    atmosphereContent,
    "Environment objects",
    "Visual Control reuses existing objects when possible and creates clearly named owned objects only when needed."
)

local function statusLine(parent, labelText)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 28)
    row.BackgroundTransparency = 1
    row.BorderSizePixel = 0
    row.Parent = parent
    local label = createText(row, labelText, 10.5, Theme.TextSecondary)
    label.Size = UDim2.new(1, -170, 1, 0)
    local value = createText(
        row,
        "Checking…",
        9.5,
        Theme.TextMuted,
        Enum.Font.Code
    )
    value.Size = UDim2.new(0, 160, 1, 0)
    value.Position = UDim2.new(1, -160, 0, 0)
    value.TextXAlignment = Enum.TextXAlignment.Right
    value.TextTruncate = Enum.TextTruncate.AtEnd
    return value
end

local atmosphereObjectStatus = statusLine(atmosphereStatusBody, "Atmosphere object")
local cloudObjectStatus = statusLine(atmosphereStatusBody, "Clouds object")
local atmosphereWeatherStatus = statusLine(atmosphereStatusBody, "Weather response")

local function updateAtmosphereStatus()
    local status = AtmosphereManager.GetStatus()
    if not status.AtmosphereAvailable then
        atmosphereObjectStatus.Text = "Unavailable"
        atmosphereObjectStatus.TextColor3 = Theme.Warning
    elseif not S.atmosphereEnabled then
        atmosphereObjectStatus.Text = "Disabled"
        atmosphereObjectStatus.TextColor3 = Theme.TextMuted
    elseif status.AtmosphereOwned then
        atmosphereObjectStatus.Text = "Owned + active"
        atmosphereObjectStatus.TextColor3 = Theme.Success
    else
        atmosphereObjectStatus.Text = "Game object reused"
        atmosphereObjectStatus.TextColor3 = Theme.Info
    end

    if not status.CloudsAvailable then
        cloudObjectStatus.Text = "Unavailable"
        cloudObjectStatus.TextColor3 = Theme.Warning
    elseif not S.cloudsEnabled then
        cloudObjectStatus.Text = "Disabled"
        cloudObjectStatus.TextColor3 = Theme.TextMuted
    elseif status.CloudsOwned then
        cloudObjectStatus.Text = "Owned + active"
        cloudObjectStatus.TextColor3 = Theme.Success
    else
        cloudObjectStatus.Text = "Game object reused"
        cloudObjectStatus.TextColor3 = Theme.Info
    end

    atmosphereWeatherStatus.Text = S.weatherResponsive
        and "Weather-linked"
        or "Static base"
    atmosphereWeatherStatus.TextColor3 = S.weatherResponsive
        and Theme.Accent
        or Theme.TextMuted
end

UI.RefreshAtmosphereStatus = updateAtmosphereStatus
atmosphereMeta.OnShown = updateAtmosphereStatus
end)()

--============================================================
-- 33 / WEATHER PAGE
--============================================================

;(function()
local weatherPage, weatherContent, weatherScroll, weatherMeta = UI.CreatePage(
    "Weather",
    "Weather",
    "Camera-relative precipitation, atmospheric fog, shelter detection, and storm response.",
    "CLIENT"
)

local weatherConditionsCard, weatherConditionsBody = UI.Card(
    weatherContent,
    "Conditions",
    "Weather transitions smoothly. Selecting a condition changes only local Visual Control systems."
)
local weatherGrid = Instance.new("Frame")
weatherGrid.Size = UDim2.new(1, 0, 0, 0)
weatherGrid.BackgroundTransparency = 1
weatherGrid.BorderSizePixel = 0
weatherGrid.Parent = weatherConditionsBody
UI.Grid(weatherGrid, {
    minimumWidth = 128,
    maximumColumns = 3,
    cellHeight = 82,
    gap = 8,
})

local WEATHER_DEFINITIONS = {
    {
        name = "Clear",
        icon = "lighting",
        description = "Clean skies",
    },
    {
        name = "Overcast",
        icon = "atmosphere",
        description = "Diffused light",
    },
    {
        name = "Rain",
        icon = "weather",
        description = "Rain + shelter",
    },
    {
        name = "Snow",
        icon = "weather",
        description = "Drifting flakes",
    },
    {
        name = "Fog",
        icon = "atmosphere",
        description = "Dense haze",
    },
}

local weatherCards = {}
local function refreshWeatherCards()
    for name, entry in pairs(weatherCards) do
        local selected = S.weather == name
        entry.Button.BackgroundColor3 = selected and Theme.CardHover or Theme.Card
        entry.Button.BackgroundTransparency = selected and 0 or 0.12
        entry.Stroke.Color = selected and Theme.Accent or Theme.BorderSoft
        entry.Stroke.Transparency = selected and 0.1 or 0.35
        entry.Icon.SetColor(selected and Theme.Accent or Theme.TextSecondary)
        entry.Label.TextColor3 = selected and Theme.Text or Theme.TextSecondary
        entry.Dot.BackgroundColor3 = selected and Theme.Accent or Theme.TextMuted
    end
end

local function chooseWeather(name)
    if S.weather == name then return end
    S.weather = name
    ActivePreset = "Custom"
    refreshWeatherCards()
    if UI.RefreshPresetIndicators then
        UI.RefreshPresetIndicators()
    end
    scheduleSave()
    Notify(
        "Weather",
        name .. " selected. Conditions will transition smoothly.",
        "info",
        2.8
    )
end

for _, definition in ipairs(WEATHER_DEFINITIONS) do
    local button = Instance.new("TextButton")
    button.Name = definition.name .. "WeatherCard"
    button.BackgroundColor3 = Theme.Card
    button.BackgroundTransparency = 0.12
    button.BorderSizePixel = 0
    button.AutoButtonColor = false
    button.Text = ""
    button.Parent = weatherGrid
    round(button, 10)
    local stroke = addStroke(button, Theme.BorderSoft, 1, 0.35)

    local icon = UI.Icon(
        definition.icon,
        15,
        Theme.TextSecondary,
        button
    )
    icon.Frame.Position = UDim2.fromOffset(10, 10)

    local dot = Instance.new("Frame")
    dot.Size = UDim2.fromOffset(5, 5)
    dot.Position = UDim2.new(1, -15, 0, 15)
    dot.BackgroundColor3 = Theme.TextMuted
    dot.BorderSizePixel = 0
    dot.Parent = button
    round(dot, 3)

    local label = createText(
        button,
        definition.name,
        12,
        Theme.TextSecondary,
        Enum.Font.GothamBold
    )
    label.Size = UDim2.new(1, -20, 0, 20)
    label.Position = UDim2.fromOffset(10, 34)
    label.TextTruncate = Enum.TextTruncate.AtEnd

    local description = createText(
        button,
        definition.description,
        9,
        Theme.TextMuted,
        Enum.Font.Gotham
    )
    description.Size = UDim2.new(1, -20, 0, 16)
    description.Position = UDim2.fromOffset(10, 53)
    description.TextTruncate = Enum.TextTruncate.AtEnd

    weatherCards[definition.name] = {
        Button = button,
        Stroke = stroke,
        Icon = icon,
        Label = label,
        Dot = dot,
    }

    connect(button.MouseEnter, function()
        if S.weather ~= definition.name then
            Motion.Tween(button, { BackgroundColor3 = Theme.CardHover }, 0.12)
        end
    end)
    connect(button.MouseLeave, function()
        if S.weather ~= definition.name then
            Motion.Tween(button, { BackgroundColor3 = Theme.Card }, 0.14)
        end
    end)
    connect(button.MouseButton1Click, function()
        chooseWeather(definition.name)
    end)
end
refreshWeatherCards()

local weatherControlsCard, weatherControlsBody = UI.Card(
    weatherContent,
    "Intensity & motion",
    "Shelter detection gradually reduces precipitation under roofs and inside enclosed spaces."
)
UI.AddControl(weatherControlsBody, Controls["weather.intensity"])
UI.AddControl(weatherControlsBody, Controls["weather.wind"])
UI.AddControl(weatherControlsBody, Controls["weather.shelter"])

local stormCard, stormBody = UI.Card(
    weatherContent,
    "Storm response",
    "Optional low-intensity lightning is visual only. It never affects combat or gameplay and is suppressed when reduced motion is enabled."
)
UI.AddControl(stormBody, Controls["weather.lightning"])
UI.AddControl(stormBody, Controls["weather.lightningIntensity"])

local weatherDiagnosticsCard, weatherDiagnosticsBody = UI.Card(
    weatherContent,
    "Live precipitation",
    "These values describe Visual Control's own emitters and environment estimates."
)
local weatherMetrics = {}
local rainRow, rainMetric = UI.MeterRow(weatherDiagnosticsBody, "Rain emission")
local snowRow, snowMetric = UI.MeterRow(weatherDiagnosticsBody, "Snow emission")
local shelterRow, shelterMetric = UI.MeterRow(weatherDiagnosticsBody, "Shelter response")
local cameraRow, cameraMetric = UI.MeterRow(weatherDiagnosticsBody, "Camera coverage")
weatherMetrics.Rain = rainMetric
weatherMetrics.Snow = snowMetric
weatherMetrics.Shelter = shelterMetric
weatherMetrics.Camera = cameraMetric

local function updateWeatherDiagnostics()
    local rainRate = Weather.Rain and Weather.Rain.Rate or 0
    local snowRate = Weather.Snow and Weather.Snow.Rate or 0
    weatherMetrics.Rain.Set(
        string.format("%d /s", math.floor(rainRate + 0.5)),
        clamp01(rainRate / 2400),
        rainRate > 0 and Theme.Info or Theme.TextMuted
    )
    weatherMetrics.Snow.Set(
        string.format("%d /s", math.floor(snowRate + 0.5)),
        clamp01(snowRate / 420),
        snowRate > 0 and Theme.Info or Theme.TextMuted
    )
    weatherMetrics.Shelter.Set(
        string.format("%d%%", math.floor(Environment.Shelter * 100 + 0.5)),
        Environment.Shelter,
        Theme.Accent
    )
    weatherMetrics.Camera.Set(
        string.format("%d%%", math.floor(Environment.CameraRoof * 100 + 0.5)),
        Environment.CameraRoof,
        Environment.CameraRoof > 0.2 and Theme.Warning or Theme.TextMuted
    )
end

UI.SetWeather = chooseWeather
UI.RefreshWeatherPage = function()
    refreshWeatherCards()
    updateWeatherDiagnostics()
end
weatherMeta.OnShown = UI.RefreshWeatherPage
end)()

--============================================================
-- 34 / CAMERA PAGE
--============================================================

;(function()
local cameraPage, cameraContent, cameraScroll, cameraMeta = UI.CreatePage(
    "Camera",
    "Camera",
    "Client-side field of view and cinematic depth of field.",
    "LENS"
)

local fovCard, fovBody = UI.Card(
    cameraContent,
    "Field of view",
    "Overrides the local camera FOV only. Original values are restored when disabled, when the camera changes, or when Visual Control unloads."
)
UI.AddControl(fovBody, Controls["camera.fovEnabled"])
UI.AddControl(fovBody, Controls["camera.fov"])

local dofCard, dofBody = UI.Card(
    cameraContent,
    "Cinematic depth of field",
    "Blur is created by Visual Control's own DepthOfFieldEffect. Focus distance is measured in studs."
)
UI.AddControl(dofBody, Controls["camera.dofEnabled"])

local dofSegmented
dofSegmented = UI.Segmented(
    dofBody,
    {
        { label = "Subtle", value = "Subtle" },
        { label = "Cinematic", value = "Cinematic" },
        { label = "Dreamy", value = "Dreamy" },
    },
    nil,
    function(value)
        if not S.dofEnabled then
            Controls["camera.dofEnabled"]:Set(true)
        end
        if value == "Subtle" then
            Controls["camera.dofFocus"]:Set(80)
            Controls["camera.dofRadius"]:Set(30)
            Controls["camera.dofFar"]:Set(0.08)
            Controls["camera.dofNear"]:Set(0.02)
        elseif value == "Cinematic" then
            Controls["camera.dofFocus"]:Set(72)
            Controls["camera.dofRadius"]:Set(18)
            Controls["camera.dofFar"]:Set(0.18)
            Controls["camera.dofNear"]:Set(0.04)
        elseif value == "Dreamy" then
            Controls["camera.dofFocus"]:Set(58)
            Controls["camera.dofRadius"]:Set(12)
            Controls["camera.dofFar"]:Set(0.28)
            Controls["camera.dofNear"]:Set(0.08)
        end
        dofSegmented.SetValue(value)
    end
)

UI.AddControl(dofBody, Controls["camera.dofFocus"])
UI.AddControl(dofBody, Controls["camera.dofRadius"])
UI.AddControl(dofBody, Controls["camera.dofFar"])
UI.AddControl(dofBody, Controls["camera.dofNear"])

local cameraNote = createText(
    cameraContent,
    "Camera effects are visual only. They do not alter movement, aiming, hit detection, or network behavior.",
    9.5,
    Theme.TextMuted,
    Enum.Font.Gotham
)
cameraNote.Size = UDim2.new(1, 0, 0, 0)
cameraNote.AutomaticSize = Enum.AutomaticSize.Y
cameraNote.TextWrapped = true
cameraNote.TextYAlignment = Enum.TextYAlignment.Top
end)()

--============================================================
-- 35 / AUDIO PAGE
--============================================================

;(function()
local audioPage, audioContent, audioScroll, audioMeta = UI.CreatePage(
    "Audio",
    "Audio",
    "A personal music player with enclosure-aware processing. Game audio is never touched.",
    "ISOLATED"
)

local audioNowCard, audioNowBody = UI.Card(
    audioContent,
    "Now playing",
    "Visual Control processes only its own Sound instance. Titles come from file names or asset IDs; no metadata is invented.",
    { badge = "PRIVATE" }
)

local nowPlayingHeader = Instance.new("Frame")
nowPlayingHeader.Size = UDim2.new(1, 0, 0, 46)
nowPlayingHeader.BackgroundTransparency = 1
nowPlayingHeader.BorderSizePixel = 0
nowPlayingHeader.Parent = audioNowBody

local audioBarsFrame = Instance.new("Frame")
audioBarsFrame.Size = UDim2.fromOffset(38, 36)
audioBarsFrame.Position = UDim2.fromOffset(0, 4)
audioBarsFrame.BackgroundTransparency = 1
audioBarsFrame.BorderSizePixel = 0
audioBarsFrame.Parent = nowPlayingHeader
local audioBars = {}
for index = 1, 4 do
    local bar = Instance.new("Frame")
    bar.AnchorPoint = Vector2.new(0.5, 1)
    bar.Position = UDim2.new(0, 4 + (index - 1) * 9, 1, 0)
    bar.Size = UDim2.fromOffset(3, 4)
    bar.BackgroundColor3 = Theme.Accent
    bar.BorderSizePixel = 0
    bar.Parent = audioBarsFrame
    round(bar, 1.5)
    table.insert(audioBars, bar)
end
Theme.Bind(function()
    for _, bar in ipairs(audioBars) do
        bar.BackgroundColor3 = Theme.Accent
    end
end)

local audioTitle = createText(
    nowPlayingHeader,
    "No track loaded",
    16,
    Theme.Text,
    Enum.Font.GothamBold
)
audioTitle.Size = UDim2.new(1, -210, 0, 23)
audioTitle.Position = UDim2.fromOffset(50, 0)
audioTitle.TextTruncate = Enum.TextTruncate.AtEnd

local audioSubtitle = createText(
    nowPlayingHeader,
    "Load a Roblox asset or local audio file to begin.",
    9.5,
    Theme.TextSecondary,
    Enum.Font.Gotham
)
audioSubtitle.Size = UDim2.new(1, -210, 0, 17)
audioSubtitle.Position = UDim2.fromOffset(50, 23)
audioSubtitle.TextTruncate = Enum.TextTruncate.AtEnd

local audioStatusPill = Instance.new("Frame")
audioStatusPill.AnchorPoint = Vector2.new(1, 0)
audioStatusPill.Position = UDim2.new(1, 0, 0, 5)
audioStatusPill.Size = UDim2.fromOffset(148, 24)
audioStatusPill.BackgroundColor3 = Theme.Background
audioStatusPill.BackgroundTransparency = 0.1
audioStatusPill.BorderSizePixel = 0
audioStatusPill.Parent = nowPlayingHeader
round(audioStatusPill, 12)
addStroke(audioStatusPill, Theme.BorderSoft, 1, 0.35)

local audioStatusDot = Instance.new("Frame")
audioStatusDot.Size = UDim2.fromOffset(5, 5)
audioStatusDot.Position = UDim2.fromOffset(12, 9)
audioStatusDot.BackgroundColor3 = Theme.TextMuted
audioStatusDot.BorderSizePixel = 0
audioStatusDot.Parent = audioStatusPill
round(audioStatusDot, 3)

local audioStatusLabel = createText(
    audioStatusPill,
    "Idle",
    8.5,
    Theme.TextSecondary,
    Enum.Font.GothamBold
)
audioStatusLabel.Size = UDim2.new(1, -26, 1, 0)
audioStatusLabel.Position = UDim2.fromOffset(22, 0)
audioStatusLabel.TextXAlignment = Enum.TextXAlignment.Center
audioStatusLabel.TextTruncate = Enum.TextTruncate.AtEnd

local audioErrorLabel = createText(
    audioNowBody,
    "",
    9.5,
    Theme.Danger,
    Enum.Font.Gotham
)
audioErrorLabel.Size = UDim2.new(1, 0, 0, 0)
audioErrorLabel.AutomaticSize = Enum.AutomaticSize.Y
audioErrorLabel.TextWrapped = true
audioErrorLabel.TextYAlignment = Enum.TextYAlignment.Top
audioErrorLabel.Visible = false

local progressFrame = Instance.new("Frame")
progressFrame.Size = UDim2.new(1, 0, 0, 36)
progressFrame.BackgroundTransparency = 1
progressFrame.BorderSizePixel = 0
progressFrame.Parent = audioNowBody

local seekTrack = Instance.new("TextButton")
seekTrack.Size = UDim2.new(1, 0, 0, 18)
seekTrack.Position = UDim2.fromOffset(0, 2)
seekTrack.BackgroundTransparency = 1
seekTrack.BorderSizePixel = 0
seekTrack.AutoButtonColor = false
seekTrack.Text = ""
seekTrack.Parent = progressFrame

local seekBackground = Instance.new("Frame")
seekBackground.Size = UDim2.new(1, 0, 0, 5)
seekBackground.Position = UDim2.new(0, 0, 0.5, -2.5)
seekBackground.BackgroundColor3 = Theme.Track
seekBackground.BorderSizePixel = 0
seekBackground.Parent = seekTrack
round(seekBackground, 2.5)

local seekFill = Instance.new("Frame")
seekFill.Size = UDim2.new(0, 0, 1, 0)
seekFill.BackgroundColor3 = Theme.Accent
seekFill.BorderSizePixel = 0
seekFill.Parent = seekBackground
round(seekFill, 2.5)
Theme.Bind(function()
    seekFill.BackgroundColor3 = Theme.Accent
end)

local seekKnob = Instance.new("Frame")
seekKnob.AnchorPoint = Vector2.new(0.5, 0.5)
seekKnob.Size = UDim2.fromOffset(11, 11)
seekKnob.Position = UDim2.new(0, 0, 0.5, 0)
seekKnob.BackgroundColor3 = Theme.Text
seekKnob.BorderSizePixel = 0
seekKnob.Parent = seekTrack
round(seekKnob, 5.5)
addStroke(seekKnob, Theme.Background, 2, 0)

local audioTimeCurrent = createText(
    progressFrame,
    "0:00",
    9,
    Theme.TextMuted,
    Enum.Font.Code
)
audioTimeCurrent.Size = UDim2.fromOffset(80, 15)
audioTimeCurrent.Position = UDim2.fromOffset(0, 21)

local audioTimeDuration = createText(
    progressFrame,
    "0:00",
    9,
    Theme.TextMuted,
    Enum.Font.Code
)
audioTimeDuration.Size = UDim2.fromOffset(80, 15)
audioTimeDuration.Position = UDim2.new(1, -80, 0, 21)
audioTimeDuration.TextXAlignment = Enum.TextXAlignment.Right

local seeking = false
local seekFraction = 0
local pendingSeek = 0

local function setSeekFraction(fraction)
    seekFraction = clamp01(fraction)
    seekFill.Size = UDim2.new(seekFraction, 0, 1, 0)
    seekKnob.Position = UDim2.new(seekFraction, 0, 0.5, 0)
end

connect(seekTrack.InputBegan, function(input)
    if input.UserInputType ~= Enum.UserInputType.MouseButton1
        and input.UserInputType ~= Enum.UserInputType.Touch then
        return
    end
    local duration = AudioManager.GetDuration()
    if duration <= 0 then return end
    seeking = true
    local function updateFromX(x)
        local alpha = clamp01((x - seekTrack.AbsolutePosition.X) / math.max(1, seekTrack.AbsoluteSize.X))
        setSeekFraction(alpha)
        pendingSeek = alpha * duration
        audioTimeCurrent.Text = formatClock(pendingSeek)
    end
    updateFromX(input.Position.X)
    Pointer.Begin(function(moveInput)
        updateFromX(moveInput.Position.X)
    end, function()
        seeking = false
        AudioManager.Seek(pendingSeek)
    end)
end)

local transport = Instance.new("Frame")
transport.Size = UDim2.new(1, 0, 0, 38)
transport.BackgroundTransparency = 1
transport.BorderSizePixel = 0
transport.Parent = audioNowBody
addHorizontalList(transport, 7, Enum.VerticalAlignment.Center)

local audioPrev = UI.GlyphButton(transport, {
    glyph = "‹",
    glyphSize = 21,
    size = UDim2.fromOffset(34, 34),
    tooltip = "Previous queue track",
    onClick = function()
        AudioManager.Previous()
    end,
})
audioPrev.LayoutOrder = 1

local audioPlay, audioPlayGlyph = UI.GlyphButton(transport, {
    glyph = "▶",
    glyphSize = 15,
    size = UDim2.fromOffset(46, 34),
    variant = "primary",
    tooltip = "Play or pause personal music",
    onClick = function()
        local ok, err = AudioManager.TogglePlay()
        if not ok and err then
            Notify("Audio", err, "warning", 2.5)
        end
    end,
})
audioPlay.LayoutOrder = 2

local audioStop = UI.GlyphButton(transport, {
    glyph = "■",
    glyphSize = 12,
    size = UDim2.fromOffset(34, 34),
    tooltip = "Stop personal music",
    onClick = function()
        AudioManager.Stop()
    end,
})
audioStop.LayoutOrder = 3

local audioNext = UI.GlyphButton(transport, {
    glyph = "›",
    glyphSize = 21,
    size = UDim2.fromOffset(34, 34),
    tooltip = "Next queue track",
    onClick = function()
        AudioManager.Next()
    end,
})
audioNext.LayoutOrder = 4

local audioQueueShortcut = UI.Button(transport, {
    text = "Queue",
    variant = "ghost",
    size = UDim2.fromOffset(70, 34),
    textSize = 9.5,
    onClick = function()
        if audioScroll then
            audioScroll.CanvasPosition = Vector2.new(0, audioScroll.CanvasPosition.Y + 260)
        end
    end,
})
audioQueueShortcut.LayoutOrder = 5

local audioSourceCard, audioSourceBody = UI.Card(
    audioContent,
    "Load a track",
    "Roblox asset IDs and supported local files are accepted. Local playback requires the executor's getcustomasset function."
)

local audioSourceInput = UI.TextField(audioSourceBody, {
    placeholder = "rbxassetid://1234567890  or  C:\\Music\\track.mp3",
    tooltip = "Enter a Roblox audio asset ID or a local audio file path",
})

local rebuildAudioQueue

local audioSourceButtons = UI.ButtonRow(audioSourceBody, {
    {
        text = "Play now",
        variant = "primary",
        onClick = function()
            local ok, err = AudioManager.PlaySource(audioSourceInput.Text)
            if not ok and err then
                Notify("Audio", err, "error")
            end
        end,
    },
    {
        text = "Add to queue",
        variant = "secondary",
        onClick = function()
            local ok, message = AudioManager.AddToQueue(audioSourceInput.Text)
            if ok then
                Notify("Audio", "Added " .. tostring(message) .. " to the queue.", "success", 2.5)
                rebuildAudioQueue()
            else
                Notify("Audio", message or "Could not add the track.", "error")
            end
        end,
    },
})

local sourceSupport = createText(
    audioSourceBody,
    type(GetCustomAsset) == "function"
        and "Local audio: available through getcustomasset."
        or "Local audio: unavailable. Roblox asset IDs still work.",
    9.5,
    type(GetCustomAsset) == "function" and Theme.TextMuted or Theme.Warning,
    Enum.Font.Gotham
)
sourceSupport.Size = UDim2.new(1, 0, 0, 0)
sourceSupport.AutomaticSize = Enum.AutomaticSize.Y
sourceSupport.TextWrapped = true
sourceSupport.TextYAlignment = Enum.TextYAlignment.Top

local audioPlaybackCard, audioPlaybackBody = UI.Card(
    audioContent,
    "Playback",
    "Volume and looping apply to Visual Control's personal Sound only."
)
UI.AddControl(audioPlaybackBody, Controls["audio.volume"])
UI.AddControl(audioPlaybackBody, Controls["audio.loop"])

local audioAcousticsCard, audioAcousticsBody = UI.Card(
    audioContent,
    "Indoor acoustics",
    "Equalizer and reverb effects are children of the Visual Control Sound instance. No SoundGroup or global effect is modified."
)
UI.AddControl(audioAcousticsBody, Controls["audio.muffling"])
UI.AddControl(audioAcousticsBody, Controls["audio.muffleStrength"])
UI.AddControl(audioAcousticsBody, Controls["audio.reverb"])
UI.AddControl(audioAcousticsBody, Controls["audio.reverbStrength"])

local audioAcousticStatus = createText(
    audioAcousticsBody,
    "Acoustic state: dry",
    9.5,
    Theme.TextMuted,
    Enum.Font.Gotham
)
audioAcousticStatus.Size = UDim2.new(1, 0, 0, 0)
audioAcousticStatus.AutomaticSize = Enum.AutomaticSize.Y
audioAcousticStatus.TextWrapped = true
audioAcousticStatus.TextYAlignment = Enum.TextYAlignment.Top

local audioQueueCard, audioQueueBody = UI.Card(
    audioContent,
    "Playback queue",
    "Queue entries are session-only. Local paths are resolved when each entry is played."
)
local audioQueueContainer = Instance.new("Frame")
audioQueueContainer.Size = UDim2.new(1, 0, 0, 0)
audioQueueContainer.AutomaticSize = Enum.AutomaticSize.Y
audioQueueContainer.BackgroundTransparency = 1
audioQueueContainer.BorderSizePixel = 0
audioQueueContainer.Parent = audioQueueBody
addVerticalList(audioQueueContainer, 2)

local audioQueueScope = nil
local audioQueueSignature = ""
local audioQueueBuilt = false

local function audioQueueSignatureNow()
    local parts = { tostring(#AudioManager.GetQueue()), tostring(AudioManager.GetQueueIndex() or 0) }
    for _, entry in ipairs(AudioManager.GetQueue()) do
        table.insert(parts, entry.title .. "|" .. entry.source)
    end
    return table.concat(parts, ";")
end

rebuildAudioQueue = function()
    if Runtime.Closed then return end
    local signature = audioQueueSignatureNow()
    if signature == audioQueueSignature and audioQueueBuilt then
        return
    end
    audioQueueSignature = signature
    audioQueueBuilt = true
    if audioQueueScope then
        audioQueueScope:Destroy()
    end
    audioQueueScope = newScope()
    clearGuiChildren(audioQueueContainer)

    local queue = AudioManager.GetQueue()
    if #queue == 0 then
        local placeholder = createText(
            audioQueueContainer,
            "The queue is empty. Add a track from the field above.",
            10,
            Theme.TextMuted,
            Enum.Font.Gotham
        )
        placeholder.Name = "QueuePlaceholder"
        placeholder.Size = UDim2.new(1, 0, 0, 0)
        placeholder.AutomaticSize = Enum.AutomaticSize.Y
        placeholder.TextWrapped = true
        placeholder.TextYAlignment = Enum.TextYAlignment.Top
        audioQueueScope:AddObject(placeholder)
        return
    end

    local currentIndex = AudioManager.GetQueueIndex()
    for index, entry in ipairs(queue) do
        local row = Instance.new("TextButton")
        row.Name = "QueueEntry" .. index
        row.Size = UDim2.new(1, 0, 0, 42)
        row.BackgroundColor3 = index == currentIndex and Theme.CardHover or Theme.Card
        row.BackgroundTransparency = index == currentIndex and 0 or 1
        row.BorderSizePixel = 0
        row.AutoButtonColor = false
        row.Text = ""
        row.Parent = audioQueueContainer
        round(row, 7)
        audioQueueScope:AddObject(row)

        local dot = Instance.new("Frame")
        dot.Size = UDim2.fromOffset(4, 4)
        dot.Position = UDim2.fromOffset(5, 19)
        dot.BackgroundColor3 = index == currentIndex and Theme.Accent or Theme.TextMuted
        dot.BorderSizePixel = 0
        dot.Parent = row
        round(dot, 2)

        local title = createText(
            row,
            entry.title,
            10.5,
            index == currentIndex and Theme.Text or Theme.TextSecondary,
            Enum.Font.GothamMedium
        )
        title.Size = UDim2.new(1, -105, 0, 20)
        title.Position = UDim2.fromOffset(15, 3)
        title.TextTruncate = Enum.TextTruncate.AtEnd

        local source = createText(
            row,
            shortSource(entry.source, 54),
            8,
            Theme.TextMuted,
            Enum.Font.Gotham
        )
        source.Size = UDim2.new(1, -105, 0, 14)
        source.Position = UDim2.fromOffset(15, 22)
        source.TextTruncate = Enum.TextTruncate.AtEnd

        local play = UI.GlyphButton(row, {
            glyph = "▶",
            glyphSize = 11,
            size = UDim2.fromOffset(26, 26),
            variant = "ghost",
            tooltip = "Play this queue entry",
            onClick = function()
                AudioManager.PlayQueueIndex(index)
            end,
        })
        play.Position = UDim2.new(1, -60, 0, 8)
        audioQueueScope:AddObject(play)

        local remove = UI.GlyphButton(row, {
            glyph = "×",
            glyphSize = 13,
            size = UDim2.fromOffset(26, 26),
            variant = "ghost",
            tooltip = "Remove from queue",
            onClick = function()
                AudioManager.RemoveQueueAt(index)
            end,
        })
        remove.Position = UDim2.new(1, -31, 0, 8)
        audioQueueScope:AddObject(remove)

        audioQueueScope:Connect(row.MouseButton1Click, function()
            AudioManager.PlayQueueIndex(index)
        end)
    end

    local clear = UI.Button(audioQueueContainer, {
        text = "Clear queue",
        variant = "danger",
        size = UDim2.new(0, 100, 0, 28),
        textSize = 9.5,
        onClick = function()
            AudioManager.ClearQueue()
        end,
    })
    audioQueueScope:AddObject(clear)
    UI.NormalizeLayout(audioQueueContainer)
end

local lastAudioError = nil
local function updateAudioStatusPill()
    local playing = AudioManager.IsPlaying()
    local status = AudioManager.Loading and "Loading"
        or (AudioManager.Error and "Error")
        or (playing and "Playing")
        or AudioManager.Status
    local color = Theme.TextMuted
    if status == "Playing" then
        color = Theme.Success
    elseif status == "Paused" then
        color = Theme.Warning
    elseif status == "Loading" then
        color = Theme.Info
    elseif status == "Error" then
        color = Theme.Danger
    end
    audioStatusLabel.Text = status
    audioStatusDot.BackgroundColor3 = color
    audioStatusPill.BackgroundColor3 = color
    audioStatusPill.BackgroundTransparency = 0.91
    audioPlayGlyph.Text = playing and "II" or "▶"
    audioTitle.Text = AudioManager.Title or "No track loaded"
    audioSubtitle.Text = AudioManager.Source
        and shortSource(AudioManager.Source, 74)
        or "Load a Roblox asset or local audio file to begin."
    audioErrorLabel.Text = AudioManager.Error or ""
    audioErrorLabel.Visible = AudioManager.Error ~= nil and AudioManager.Error ~= ""
    audioTimeDuration.Text = formatClock(AudioManager.GetDuration())
    if not seeking then
        audioTimeCurrent.Text = formatClock(AudioManager.GetPosition())
    end
end

local function refreshAudioProgress()
    local duration = AudioManager.GetDuration()
    if not seeking then
        local fraction = duration > 0 and (AudioManager.GetPosition() / duration) or 0
        setSeekFraction(fraction)
        audioTimeCurrent.Text = formatClock(AudioManager.GetPosition())
        audioTimeDuration.Text = formatClock(duration)
    end
    local indoor = Environment.Indoor
    local acoustic
    if indoor < 0.18 then
        acoustic = "dry / open air"
    elseif indoor < 0.48 then
        acoustic = "sheltered / light filtering"
    elseif indoor < 0.75 then
        acoustic = "indoor / moderate filtering"
    else
        acoustic = "enclosed / strong filtering"
    end
    audioAcousticStatus.Text = string.format(
        "Acoustic state: %s  ·  indoor %d%%  ·  room %d%%",
        acoustic,
        math.floor(indoor * 100 + 0.5),
        math.floor(Environment.RoomSize * 100 + 0.5)
    )
end

local function updateAudioBars()
    local playing = AudioManager.IsPlaying()
    local time = os.clock()
    for index, bar in ipairs(audioBars) do
        local height = playing
            and (5 + (math.sin(time * 4.2 + index * 1.7) * 0.5 + 0.5) * 21)
            or 4
        Motion.Tween(bar, {
            Size = UDim2.fromOffset(3, height),
            BackgroundTransparency = playing and 0 or 0.45,
        }, 0.20)
    end
end

UI.RefreshAudioPage = function()
    updateAudioStatusPill()
    refreshAudioProgress()
    updateAudioBars()
    rebuildAudioQueue()
end

connect(Events.AudioChanged, function()
    updateAudioStatusPill()
    refreshAudioProgress()
    updateAudioBars()
    rebuildAudioQueue()
    if AudioManager.Error and AudioManager.Error ~= lastAudioError then
        lastAudioError = AudioManager.Error
        Notify("Audio", AudioManager.Error, "error", 4.5)
    elseif not AudioManager.Error then
        lastAudioError = nil
    end
end)

audioMeta.OnShown = function()
    UI.RefreshAudioPage()
end
end)()

--============================================================
-- 36 / PRESETS PAGE
--============================================================

;(function()
local function findPresetByName(name)
    if BuiltinPresets[name] then
        return BuiltinPresets[name]
    end
    for _, preset in ipairs(CustomPresets) do
        if preset.name == name then
            return preset
        end
    end
    return nil
end

local function captureCurrentPresetValues()
    local values = {}
    for _, key in ipairs(PRESET_KEYS) do
        values[key] = S[key]
    end
    return values
end

local function applyPresetByName(name, silent)
    local preset = findPresetByName(name)
    if not preset then
        return false, "Preset not found."
    end
    Runtime.ApplyingPreset = true
    for _, key in ipairs(PRESET_KEYS) do
        if preset.values[key] ~= nil then
            S[key] = preset.values[key]
        end
    end
    Runtime.ApplyingPreset = false
    ActivePreset = name
    if UI.SyncFromState then
        UI.SyncFromState()
    else
        for _, control in ipairs(ControlOrder) do
            control:Refresh()
        end
        UI.RefreshConditional()
    end
    if UI.RefreshWeatherPage then
        UI.RefreshWeatherPage()
    end
    if UI.RefreshPresetIndicators then
        UI.RefreshPresetIndicators()
    end
    scheduleSave()
    if not silent then
        Notify("Preset applied", name, "success", 2.8)
    end
    return true
end

UI.ApplyPreset = applyPresetByName

local presetPage, presetContent, presetScroll, presetMeta = UI.CreatePage(
    "Presets",
    "Presets",
    "Curated visual experiences, plus custom looks captured from your current settings.",
    #PresetOrder .. " BUILT-IN"
)

local currentLookCard, currentLookBody = UI.Card(
    presetContent,
    "Current look",
    "Presets coordinate time, weather, atmosphere, clouds, post-processing, and camera effects as one visual experience."
)

local currentLookRow = Instance.new("Frame")
currentLookRow.Size = UDim2.new(1, 0, 0, 46)
currentLookRow.BackgroundTransparency = 1
currentLookRow.BorderSizePixel = 0
currentLookRow.Parent = currentLookBody

local currentPresetName = createText(
    currentLookRow,
    ActivePreset,
    20,
    Theme.Text,
    Enum.Font.GothamBold
)
currentPresetName.Size = UDim2.new(1, -150, 0, 28)
currentPresetName.Position = UDim2.fromOffset(0, 0)
currentPresetName.TextTruncate = Enum.TextTruncate.AtEnd

local currentPresetTag = createText(
    currentLookRow,
    "ACTIVE LOOK",
    8.5,
    Theme.Accent,
    Enum.Font.GothamBold
)
currentPresetTag.Size = UDim2.fromOffset(140, 18)
currentPresetTag.Position = UDim2.new(1, -140, 0, 5)
currentPresetTag.TextXAlignment = Enum.TextXAlignment.Right
Theme.Bind(function()
    currentPresetTag.TextColor3 = Theme.Accent
end)

local currentPresetDescription = createText(
    currentLookBody,
    "",
    10,
    Theme.TextSecondary,
    Enum.Font.Gotham
)
currentPresetDescription.Size = UDim2.new(1, 0, 0, 0)
currentPresetDescription.AutomaticSize = Enum.AutomaticSize.Y
currentPresetDescription.TextWrapped = true
currentPresetDescription.TextYAlignment = Enum.TextYAlignment.Top

local presetSummary = createText(
    currentLookBody,
    "",
    9,
    Theme.TextMuted,
    Enum.Font.Code
)
presetSummary.Size = UDim2.new(1, 0, 0, 0)
presetSummary.AutomaticSize = Enum.AutomaticSize.Y
presetSummary.TextWrapped = true
presetSummary.TextYAlignment = Enum.TextYAlignment.Top

UI.ButtonRow(currentLookBody, {
    {
        text = "Save current look",
        variant = "primary",
        onClick = function()
            UI.OpenSaveCustomPreset()
        end,
    },
    {
        text = "Reset to Natural",
        variant = "secondary",
        onClick = function()
            applyPresetByName("Natural")
        end,
    },
})

local builtinLabel = UI.SectionLabel(presetContent, "BUILT-IN PRESETS")

local builtinGrid = Instance.new("Frame")
builtinGrid.Name = "BuiltinPresets"
builtinGrid.BackgroundTransparency = 1
builtinGrid.BorderSizePixel = 0
builtinGrid.Parent = presetContent
UI.Grid(builtinGrid, {
    minimumWidth = 235,
    maximumColumns = 3,
    cellHeight = 216,
    gap = 10,
})

local presetCards = {}
local rebuildCustomPresetCards

local function presetSummaryLines(preset)
    local values = preset.values
    return string.format(
        "Time %s  ·  Weather %s\nBloom %.2f  ·  Contrast %+.2f  ·  Saturation %+.2f\nDOF %s  ·  Atmosphere %s  ·  Clouds %s",
        values.timeOverride and timeOfDayLabel(values.clockTime) or "live",
        values.weather,
        values.bloom,
        values.contrast,
        values.saturation,
        values.dofEnabled and "on" or "off",
        values.atmosphereEnabled and "on" or "off",
        values.cloudsEnabled and "on" or "off"
    )
end

function UI.OpenPresetDetails(preset)
    UI.Modal({
        title = preset.name,
        subtitle = preset.builtin and "Built-in visual preset" or "Custom visual preset",
        width = 520,
        build = function(body)
            local description = createText(
                body,
                preset.description or "",
                11,
                Theme.TextSecondary,
                Enum.Font.Gotham
            )
            description.Size = UDim2.new(1, 0, 0, 0)
            description.AutomaticSize = Enum.AutomaticSize.Y
            description.TextWrapped = true
            description.TextYAlignment = Enum.TextYAlignment.Top

            local details = createText(
                body,
                presetSummaryLines(preset),
                9.5,
                Theme.TextMuted,
                Enum.Font.Code
            )
            details.Size = UDim2.new(1, 0, 0, 0)
            details.AutomaticSize = Enum.AutomaticSize.Y
            details.TextWrapped = true
            details.TextYAlignment = Enum.TextYAlignment.Top
        end,
        actions = {
            {
                text = "Close",
                variant = "secondary",
                onClick = function()
                    closeModal(false)
                end,
            },
            {
                text = "Apply preset",
                variant = "primary",
                onClick = function()
                    closeModal(false)
                    applyPresetByName(preset.name)
                end,
            },
        },
    })
end

local function makePresetThumbnail(parent, preset, height)
    local thumbnail = Instance.new("Frame")
    thumbnail.Size = UDim2.new(1, 0, 0, height)
    thumbnail.BackgroundColor3 = preset.thumbnailTop
    thumbnail.BorderSizePixel = 0
    thumbnail.ClipsDescendants = true
    thumbnail.Parent = parent

    local gradient = Instance.new("UIGradient")
    gradient.Rotation = 24
    gradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, preset.thumbnailTop),
        ColorSequenceKeypoint.new(1, preset.thumbnailBottom),
    })
    gradient.Parent = thumbnail

    local glow = Instance.new("Frame")
    glow.AnchorPoint = Vector2.new(0.5, 0.5)
    glow.Position = UDim2.new(0.86, 0, 0.10, 0)
    glow.Size = UDim2.fromOffset(130, 130)
    glow.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    glow.BackgroundTransparency = 0.88
    glow.BorderSizePixel = 0
    glow.Parent = thumbnail
    round(glow, 65)

    local tag = createText(
        thumbnail,
        preset.tag or "PRESET",
        8,
        Color3.fromRGB(255, 255, 255),
        Enum.Font.GothamBold
    )
    tag.Size = UDim2.fromOffset(120, 16)
    tag.Position = UDim2.fromOffset(12, 9)
    tag.TextTransparency = 0.16

    local name = createText(
        thumbnail,
        preset.name,
        16,
        Color3.fromRGB(255, 255, 255),
        Enum.Font.GothamBold
    )
    name.Size = UDim2.new(1, -24, 0, 24)
    name.Position = UDim2.new(0, 12, 1, -31)
    name.TextTruncate = Enum.TextTruncate.AtEnd
    return thumbnail
end

local function createPresetCard(parent, preset, custom)
    local card = Instance.new("Frame")
    card.Name = preset.name
    card.BackgroundColor3 = Theme.Card
    card.BorderSizePixel = 0
    card.ClipsDescendants = true
    card.Parent = parent
    round(card, 12)
    local stroke = addStroke(card, Theme.BorderSoft, 1, 0.2)

    makePresetThumbnail(card, preset, 82)

    local selectedCheck = Instance.new("Frame")
    selectedCheck.AnchorPoint = Vector2.new(1, 0)
    selectedCheck.Position = UDim2.new(1, -10, 0, 10)
    selectedCheck.Size = UDim2.fromOffset(18, 18)
    selectedCheck.BackgroundColor3 = Theme.Accent
    selectedCheck.BackgroundTransparency = 0.08
    selectedCheck.BorderSizePixel = 0
    selectedCheck.Visible = false
    selectedCheck.Parent = card
    round(selectedCheck, 9)
    local check = UI.Glyph(
        selectedCheck,
        "✓",
        10,
        Theme.AccentInk
    )
    check.Size = UDim2.fromScale(1, 1)
    check.BackgroundTransparency = 1
    Theme.Bind(function()
        selectedCheck.BackgroundColor3 = Theme.Accent
        check.TextColor3 = Theme.AccentInk
    end, selectedCheck)

    local body = Instance.new("Frame")
    body.Position = UDim2.fromOffset(12, 91)
    body.Size = UDim2.new(1, -24, 0, 112)
    body.BackgroundTransparency = 1
    body.BorderSizePixel = 0
    body.Parent = card

    local description = createText(
        body,
        preset.description or "",
        9.5,
        Theme.TextSecondary,
        Enum.Font.Gotham
    )
    description.Size = UDim2.new(1, 0, 0, 34)
    description.TextWrapped = true
    description.TextYAlignment = Enum.TextYAlignment.Top

    local actions = Instance.new("Frame")
    actions.Position = UDim2.fromOffset(0, 78)
    actions.Size = UDim2.new(1, 0, 0, 30)
    actions.BackgroundTransparency = 1
    actions.BorderSizePixel = 0
    actions.Parent = body
    addHorizontalList(actions, 5)

    local apply = UI.Button(actions, {
        text = "Apply",
        variant = "primary",
        size = UDim2.new(1, -67, 1, 0),
        textSize = 9.5,
        onClick = function()
            applyPresetByName(preset.name)
        end,
    })
    apply.LayoutOrder = 1

    local details = UI.Button(actions, {
        text = custom and "Edit" or "Details",
        variant = "secondary",
        size = UDim2.fromOffset(62, 30),
        textSize = 9.5,
        onClick = function()
            if custom then
                UI.OpenRenameCustomPreset(preset)
            else
                UI.OpenPresetDetails(preset)
            end
        end,
    })
    details.LayoutOrder = 2

    if custom then
        local delete = UI.GlyphButton(card, {
            glyph = "×",
            glyphSize = 13,
            size = UDim2.fromOffset(24, 24),
            variant = "ghost",
            tooltip = "Delete this custom preset",
            onClick = function()
                UI.Confirm({
                    title = "Delete custom preset?",
                    message = "Delete \"" .. preset.name .. "\" permanently? This cannot be undone.",
                    confirmText = "Delete",
                    danger = true,
                    onConfirm = function()
                        for index = #CustomPresets, 1, -1 do
                            if CustomPresets[index] == preset then
                                table.remove(CustomPresets, index)
                                break
                            end
                        end
                        if ActivePreset == preset.name then
                            ActivePreset = "Custom"
                        end
                        if rebuildCustomPresetCards then
                            rebuildCustomPresetCards()
                        end
                        if UI.RefreshPresetIndicators then
                            UI.RefreshPresetIndicators()
                        end
                        scheduleSave()
                        Notify("Presets", "Custom preset deleted.", "info", 2.5)
                    end,
                })
            end,
        })
        delete.AnchorPoint = Vector2.new(1, 0)
        delete.Position = UDim2.new(1, -38, 0, 10)
        delete.ZIndex = 5
    end

    presetCards[preset.name] = {
        Card = card,
        Stroke = stroke,
        Check = selectedCheck,
        Preset = preset,
        Custom = custom,
    }
    return card
end

for _, name in ipairs(PresetOrder) do
    createPresetCard(builtinGrid, BuiltinPresets[name], false)
end

local customHeader = Instance.new("Frame")
customHeader.Size = UDim2.new(1, 0, 0, 28)
customHeader.BackgroundTransparency = 1
customHeader.BorderSizePixel = 0
customHeader.Parent = presetContent

local customLabel = UI.SectionLabel(customHeader, "YOUR PRESETS")
customLabel.Size = UDim2.new(1, -130, 1, 0)

local customCreate = UI.Button(customHeader, {
    text = "+ Create",
    variant = "secondary",
    size = UDim2.fromOffset(96, 26),
    textSize = 9.5,
    onClick = function()
        UI.OpenSaveCustomPreset()
    end,
})
customCreate.AnchorPoint = Vector2.new(1, 0)
customCreate.Position = UDim2.new(1, 0, 0, 1)

local customGrid = Instance.new("Frame")
customGrid.Name = "CustomPresets"
customGrid.BackgroundTransparency = 1
customGrid.BorderSizePixel = 0
customGrid.Parent = presetContent
UI.Grid(customGrid, {
    minimumWidth = 235,
    maximumColumns = 3,
    cellHeight = 216,
    gap = 10,
})

local customScope = nil
rebuildCustomPresetCards = function()
    if Runtime.Closed then return end
    if customScope then
        customScope:Destroy()
    end
    customScope = newScope()
    for _, child in ipairs(customGrid:GetChildren()) do
        if child:IsA("GuiObject") then
            child:Destroy()
        end
    end
    local stalePresetNames = {}
    for name, entry in pairs(presetCards) do
        if entry.Custom then
            table.insert(stalePresetNames, name)
        end
    end
    for _, name in ipairs(stalePresetNames) do
        presetCards[name] = nil
    end

    if #CustomPresets == 0 then
        local placeholder = Instance.new("Frame")
        placeholder.BackgroundColor3 = Theme.Card
        placeholder.BackgroundTransparency = 0.1
        placeholder.BorderSizePixel = 0
        placeholder.Parent = customGrid
        round(placeholder, 12)
        addStroke(placeholder, Theme.BorderSoft, 1, 0.3)
        addPadding(placeholder, 16, 16, 16, 16)

        local text = createText(
            placeholder,
            "No custom presets yet.",
            13,
            Theme.Text,
            Enum.Font.GothamBold
        )
        text.Size = UDim2.new(1, 0, 0, 22)

        local description = createText(
            placeholder,
            "Capture the current time, weather, atmosphere, grading, and camera settings as a reusable look.",
            9.5,
            Theme.TextSecondary,
            Enum.Font.Gotham
        )
        description.Size = UDim2.new(1, 0, 0, 44)
        description.Position = UDim2.fromOffset(0, 27)
        description.TextWrapped = true
        description.TextYAlignment = Enum.TextYAlignment.Top

        local create = UI.Button(placeholder, {
            text = "Save current look",
            variant = "primary",
            size = UDim2.new(0, 142, 0, 30),
            textSize = 9.5,
            onClick = function()
                UI.OpenSaveCustomPreset()
            end,
        })
        create.Position = UDim2.fromOffset(0, 78)
        customScope:AddObject(placeholder)
        return
    end

    for _, preset in ipairs(CustomPresets) do
        local card = createPresetCard(customGrid, preset, true)
        customScope:AddObject(card)
    end
end

function UI.OpenSaveCustomPreset()
    local nameBox
    UI.Modal({
        title = "Save custom preset",
        subtitle = "Capture the current visual, atmosphere, weather, and camera state.",
        width = 460,
        build = function(body)
            local label = createText(
                body,
                "Preset name",
                10,
                Theme.TextSecondary,
                Enum.Font.GothamMedium
            )
            label.Size = UDim2.new(1, 0, 0, 18)
            nameBox = UI.TextField(body, {
                placeholder = "My custom look",
                size = UDim2.new(1, 0, 0, 36),
            })
            local note = createText(
                body,
                "Names are limited to 24 characters and must be unique.",
                9,
                Theme.TextMuted,
                Enum.Font.Gotham
            )
            note.Size = UDim2.new(1, 0, 0, 0)
            note.AutomaticSize = Enum.AutomaticSize.Y
            note.TextWrapped = true
        end,
        onOpen = function()
            if nameBox then nameBox:CaptureFocus() end
        end,
        actions = {
            {
                text = "Cancel",
                variant = "secondary",
                onClick = function()
                    closeModal(false)
                end,
            },
            {
                text = "Save preset",
                variant = "primary",
                onClick = function()
                    local name = nameBox and nameBox.Text:match("^%s*(.-)%s*$") or ""
                    if #name < 1 then
                        Notify("Presets", "Enter a preset name.", "warning")
                        return
                    end
                    if #name > 24 then
                        Notify("Presets", "Preset names are limited to 24 characters.", "warning")
                        return
                    end
                    local builtinConflict = name:lower() == "custom"
                    for builtinName in pairs(BuiltinPresets) do
                        if builtinName:lower() == name:lower() then
                            builtinConflict = true
                            break
                        end
                    end
                    if builtinConflict then
                        Notify("Presets", "That name is reserved or belongs to a built-in preset.", "warning")
                        return
                    end
                    for _, existing in ipairs(CustomPresets) do
                        if existing.name:lower() == name:lower() then
                            Notify("Presets", "A custom preset with that name already exists.", "warning")
                            return
                        end
                    end
                    local preset = {
                        name = name,
                        tag = "CUSTOM",
                        description = "Custom look captured from the current settings.",
                        thumbnailTop = Color3.fromRGB(45, 57, 73),
                        thumbnailBottom = Theme.Accent,
                        values = captureCurrentPresetValues(),
                        builtin = false,
                    }
                    table.insert(CustomPresets, preset)
                    ActivePreset = name
                    closeModal(false)
                    rebuildCustomPresetCards()
                    UI.RefreshPresetIndicators()
                    scheduleSave()
                    Notify("Presets", "Saved custom preset \"" .. name .. "\".", "success")
                end,
            },
        },
    })
end

function UI.OpenRenameCustomPreset(preset)
    local nameBox
    UI.Modal({
        title = "Rename custom preset",
        subtitle = preset.name,
        width = 430,
        build = function(body)
            nameBox = UI.TextField(body, {
                placeholder = "Preset name",
                text = preset.name,
                size = UDim2.new(1, 0, 0, 36),
            })
        end,
        onOpen = function()
            if nameBox then nameBox:CaptureFocus() end
        end,
        actions = {
            {
                text = "Cancel",
                variant = "secondary",
                onClick = function()
                    closeModal(false)
                end,
            },
            {
                text = "Rename",
                variant = "primary",
                onClick = function()
                    local name = nameBox and nameBox.Text:match("^%s*(.-)%s*$") or ""
                    if #name < 1 or #name > 24 then
                        Notify("Presets", "Use a name between 1 and 24 characters.", "warning")
                        return
                    end
                    local builtinConflict = name:lower() == "custom"
                    for builtinName in pairs(BuiltinPresets) do
                        if builtinName:lower() == name:lower() then
                            builtinConflict = true
                            break
                        end
                    end
                    if builtinConflict then
                        Notify("Presets", "That name is reserved or belongs to a built-in preset.", "warning")
                        return
                    end
                    for _, existing in ipairs(CustomPresets) do
                        if existing ~= preset and existing.name:lower() == name:lower() then
                            Notify("Presets", "Another custom preset already uses that name.", "warning")
                            return
                        end
                    end
                    local oldName = preset.name
                    preset.name = name
                    if ActivePreset == oldName then
                        ActivePreset = name
                    end
                    closeModal(false)
                    rebuildCustomPresetCards()
                    UI.RefreshPresetIndicators()
                    scheduleSave()
                    Notify("Presets", "Custom preset renamed.", "success", 2.5)
                end,
            },
        },
    })
end

function UI.RefreshPresetIndicators()
    local preset = findPresetByName(ActivePreset)
    currentPresetName.Text = ActivePreset
    if preset then
        currentPresetDescription.Text = preset.description or ""
        presetSummary.Text = presetSummaryLines(preset)
    else
        currentPresetDescription.Text = "Custom settings based on your current adjustments. Save the look to reuse it later."
        presetSummary.Text = string.format(
            "Time %s  ·  Weather %s\nBloom %.2f  ·  Contrast %+.2f  ·  Saturation %+.2f",
            S.timeOverride and timeOfDayLabel(S.clockTime) or "live",
            S.weather,
            S.bloom,
            S.contrast,
            S.saturation
        )
    end

    for name, entry in pairs(presetCards) do
        local selected = name == ActivePreset
        entry.Stroke.Color = selected and Theme.Accent or Theme.BorderSoft
        entry.Stroke.Transparency = selected and 0.05 or 0.2
        entry.Check.Visible = selected
    end
end

local function cycleWeatherCondition()
    local order = { "Clear", "Overcast", "Rain", "Snow", "Fog" }
    local current = 0
    for index, value in ipairs(order) do
        if value == S.weather then
            current = index
            break
        end
    end
    local nextValue = order[(current % #order) + 1]
    if UI.SetWeather then
        UI.SetWeather(nextValue)
    else
        S.weather = nextValue
        ActivePreset = "Custom"
        if UI.RefreshWeatherPage then UI.RefreshWeatherPage() end
        if UI.RefreshPresetIndicators then UI.RefreshPresetIndicators() end
        scheduleSave()
    end
end

function UI.CycleWeather()
    cycleWeatherCondition()
end

function UI.CyclePreset()
    local currentIndex = 0
    for index, name in ipairs(PresetOrder) do
        if name == ActivePreset then
            currentIndex = index
            break
        end
    end
    local nextName = PresetOrder[(currentIndex % #PresetOrder) + 1]
    applyPresetByName(nextName)
end

presetMeta.OnShown = function()
    rebuildCustomPresetCards()
    UI.RefreshPresetIndicators()
end

task.defer(function()
    rebuildCustomPresetCards()
    UI.RefreshPresetIndicators()
end)
end)()

--============================================================
-- 37 / PERFORMANCE PAGE
--============================================================

;(function()
local performancePage, performanceContent, performanceScroll, performanceMeta = UI.CreatePage(
    "Performance",
    "Performance",
    "Quality profiles, live application metrics, and diagnostics.",
    "DIAGNOSTICS"
)

local qualityCard, qualityBody = UI.Card(
    performanceContent,
    "Quality profile",
    "Quality controls raycast frequency and precipitation density. Visual post-processing remains available in every profile."
)
UI.AddControl(qualityBody, Controls["performance.quality"])

local qualityDescription = createText(
    qualityBody,
    QUALITY_PROFILES[S.quality].description,
    9.5,
    Theme.TextMuted,
    Enum.Font.Gotham
)
qualityDescription.Size = UDim2.new(1, 0, 0, 0)
qualityDescription.AutomaticSize = Enum.AutomaticSize.Y
qualityDescription.TextWrapped = true
qualityDescription.TextYAlignment = Enum.TextYAlignment.Top

local qualityFacts = createText(
    qualityBody,
    string.format(
        "Environment scan every %.2fs  ·  Rain density %.2fx  ·  Snow density %.2fx",
        1 / QUALITY_PROFILES[S.quality].environmentInterval,
        QUALITY_PROFILES[S.quality].rainRate,
        QUALITY_PROFILES[S.quality].snowRate
    ),
    9,
    Theme.TextMuted,
    Enum.Font.Code
)
qualityFacts.Size = UDim2.new(1, 0, 0, 0)
qualityFacts.AutomaticSize = Enum.AutomaticSize.Y
qualityFacts.TextWrapped = true
qualityFacts.TextYAlignment = Enum.TextYAlignment.Top

local performanceMetricsCard, performanceMetricsBody = UI.Card(
    performanceContent,
    "Live application metrics",
    "These values are measured by Visual Control. They are not GPU-level engine profiling data."
)

local fpsRow, fpsMetric = UI.MeterRow(performanceMetricsBody, "Smoothed frame rate")
local frameRow, frameMetric = UI.MeterRow(performanceMetricsBody, "Frame time")
local scanRow, scanMetric = UI.MeterRow(performanceMetricsBody, "Environment scans / second")
local particleRow, particleMetric = UI.MeterRow(performanceMetricsBody, "Estimated precipitation particles")
local effectRow, effectMetric = UI.MeterRow(performanceMetricsBody, "Active owned visual systems")

local performanceButtons = UI.ButtonRow(performanceMetricsBody, {
    {
        text = "Reset metrics",
        variant = "secondary",
        onClick = function()
            Metrics.SmoothedFPS = 60
            Metrics.FrameMs = 16.7
            Metrics.SessionStart = os.clock()
            Notify("Performance", "Smoothed metrics reset.", "info", 2.3)
        end,
    },
    {
        text = "Open performance guide",
        variant = "ghost",
        onClick = function()
            Notify(
                "Performance",
                "Low uses fewer raycasts and lighter precipitation. Balanced is recommended for most games. High increases density and response speed.",
                "info",
                6.5
            )
        end,
    },
})

local diagnosticsCard, diagnosticsBody = UI.Card(
    performanceContent,
    "Diagnostics",
    "A compact view of the systems and capabilities available in this execution environment."
)

local diagnosticLabels = {}
local function diagnosticRow(parent, labelText)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 24)
    row.BackgroundTransparency = 1
    row.BorderSizePixel = 0
    row.Parent = parent

    local label = createText(row, labelText, 10, Theme.TextSecondary)
    label.Size = UDim2.new(1, -190, 1, 0)
    label.TextTruncate = Enum.TextTruncate.AtEnd

    local value = createText(
        row,
        "—",
        9,
        Theme.TextMuted,
        Enum.Font.Code
    )
    value.Size = UDim2.new(0, 180, 1, 0)
    value.Position = UDim2.new(1, -180, 0, 0)
    value.TextXAlignment = Enum.TextXAlignment.Right
    value.TextTruncate = Enum.TextTruncate.AtEnd
    return value
end

diagnosticLabels.Preset = diagnosticRow(diagnosticsBody, "Active preset")
diagnosticLabels.Environment = diagnosticRow(diagnosticsBody, "Environment")
diagnosticLabels.Weather = diagnosticRow(diagnosticsBody, "Weather")
diagnosticLabels.Shelter = diagnosticRow(diagnosticsBody, "Shelter / room estimate")
diagnosticLabels.Storage = diagnosticRow(diagnosticsBody, "Preference storage")
diagnosticLabels.LocalAudio = diagnosticRow(diagnosticsBody, "Local audio support")
diagnosticLabels.Clipboard = diagnosticRow(diagnosticsBody, "Diagnostics clipboard")
diagnosticLabels.Session = diagnosticRow(diagnosticsBody, "Session uptime")

local diagnosticsButtons = UI.ButtonRow(diagnosticsBody, {
    {
        text = "Copy diagnostics",
        variant = "primary",
        onClick = function()
            if type(SetClipboard) ~= "function" then
                Notify("Diagnostics", "setclipboard is unavailable in this environment.", "warning")
                return
            end
            local status = AtmosphereManager.GetStatus()
            local text = table.concat({
                APP_NAME .. " " .. VERSION,
                "Quality: " .. S.quality,
                "Active preset: " .. ActivePreset,
                "Environment: " .. Environment.Classification,
                "Shelter: " .. string.format("%.2f", Environment.Shelter),
                "Indoor: " .. string.format("%.2f", Environment.Indoor),
                "Room size: " .. string.format("%.2f", Environment.RoomSize),
                "Weather: " .. S.weather .. " @ " .. string.format("%.2f", S.weatherIntensity),
                "Effects: " .. (S.effectsEnabled and "on" or "off"),
                "Atmosphere: " .. (status.AtmosphereOwned and "owned" or (status.AtmosphereAvailable and "available" or "unavailable")),
                "Clouds: " .. (status.CloudsOwned and "owned" or (status.CloudsAvailable and "available" or "unavailable")),
                "Audio: " .. AudioManager.Status .. " / " .. (AudioManager.IsPlaying() and "playing" or "not playing"),
                "Smoothed FPS: " .. string.format("%.1f", Metrics.SmoothedFPS),
                "Frame time: " .. string.format("%.2f ms", Metrics.FrameMs),
                "Environment scans: " .. tostring(Metrics.EnvironmentScans),
                "Storage: " .. (Storage.Available and "available" or "unavailable"),
                "getcustomasset: " .. (type(GetCustomAsset) == "function" and "available" or "unavailable"),
            }, "\n")
            local ok = pcall(SetClipboard, text)
            if ok then
                Notify("Diagnostics", "Diagnostics copied to the clipboard.", "success", 2.5)
            else
                Notify("Diagnostics", "Could not write to the clipboard.", "error")
            end
        end,
    },
    {
        text = "Show storage path",
        variant = "ghost",
        onClick = function()
            Notify("Storage", CONFIG_FILE, "info", 3.2)
        end,
    },
})

local performanceNote = createText(
    performanceContent,
    "Visual Control never reports simulated GPU timings. All metrics above are measured inside this script.",
    9.5,
    Theme.TextMuted,
    Enum.Font.Gotham
)
performanceNote.Size = UDim2.new(1, 0, 0, 0)
performanceNote.AutomaticSize = Enum.AutomaticSize.Y
performanceNote.TextWrapped = true
performanceNote.TextYAlignment = Enum.TextYAlignment.Top

local function updatePerformancePage()
    local profile = QUALITY_PROFILES[S.quality]
    qualityDescription.Text = profile.description
    qualityFacts.Text = string.format(
        "Environment scan every %.2fs  ·  Rain density %.2fx  ·  Snow density %.2fx",
        1 / profile.environmentInterval,
        profile.rainRate,
        profile.snowRate
    )

    fpsMetric.Set(
        string.format("%.1f fps", Metrics.SmoothedFPS),
        clamp01(Metrics.SmoothedFPS / 120),
        Metrics.SmoothedFPS >= 45 and Theme.Success
            or (Metrics.SmoothedFPS >= 25 and Theme.Warning or Theme.Danger)
    )
    frameMetric.Set(
        string.format("%.2f ms", Metrics.FrameMs),
        1 - clamp01(Metrics.FrameMs / 33),
        Metrics.FrameMs <= 22 and Theme.Success
            or (Metrics.FrameMs <= 40 and Theme.Warning or Theme.Danger)
    )
    scanMetric.Set(
        string.format("%.2f /s", Metrics.EnvironmentRate),
        clamp01(Metrics.EnvironmentRate / 10),
        Theme.Info
    )
    particleMetric.Set(
        tostring(math.floor(Metrics.EstimatedParticles + 0.5)),
        clamp01(Metrics.EstimatedParticles / 3600),
        Theme.Info
    )
    effectMetric.Set(
        tostring(Metrics.EffectCount),
        clamp01(Metrics.EffectCount / 8),
        Theme.Accent
    )

    diagnosticLabels.Preset.Text = ActivePreset
    diagnosticLabels.Environment.Text = Environment.Classification
    diagnosticLabels.Weather.Text = S.weather
    diagnosticLabels.Shelter.Text = string.format(
        "%d%% / %d%%",
        math.floor(Environment.Shelter * 100 + 0.5),
        math.floor(Environment.RoomSize * 100 + 0.5)
    )
    diagnosticLabels.Storage.Text = Storage.Available
        and (S.rememberSettings and "enabled" or "available / disabled")
        or "unavailable"
    diagnosticLabels.LocalAudio.Text = type(GetCustomAsset) == "function"
        and "getcustomasset available"
        or "asset IDs only"
    diagnosticLabels.Clipboard.Text = type(SetClipboard) == "function"
        and "available"
        or "unavailable"
    diagnosticLabels.Session.Text = formatClock(os.clock() - Metrics.SessionStart)
end

UI.RefreshPerformance = updatePerformancePage
performanceMeta.OnShown = updatePerformancePage
end)()

--============================================================
-- 38 / SETTINGS PAGE
--============================================================

;(function()
local settingsPage, settingsContent, settingsScroll, settingsMeta = UI.CreatePage(
    "Settings",
    "Settings",
    "Appearance, accessibility, keyboard shortcuts, persistence, and application lifecycle.",
    "SYSTEM"
)

local appearanceCard, appearanceBody = UI.Card(
    settingsContent,
    "Appearance",
    "Choose a restrained accent color and tune interface motion and guidance."
)

local accentRow = Instance.new("Frame")
accentRow.Size = UDim2.new(1, 0, 0, 78)
accentRow.BackgroundTransparency = 1
accentRow.BorderSizePixel = 0
accentRow.Parent = appearanceBody

local accentTitle = createText(
    accentRow,
    "Accent color",
    12,
    Theme.Text,
    Enum.Font.GothamMedium
)
accentTitle.Size = UDim2.new(1, 0, 0, 20)
Tooltip.Attach(accentTitle, "Changes the interface accent color without affecting the game.")

local accentSwatches = Instance.new("Frame")
accentSwatches.AnchorPoint = Vector2.new(0, 0)
accentSwatches.Position = UDim2.fromOffset(0, 28)
accentSwatches.Size = UDim2.new(1, 0, 0, 26)
accentSwatches.BackgroundTransparency = 1
accentSwatches.BorderSizePixel = 0
accentSwatches.Parent = accentRow
addHorizontalList(accentSwatches, 6)

local accentButtons = {}
local accentStrokes = {}
local function refreshAccentButtons()
    for name, button in pairs(accentButtons) do
        local selected = Theme.AccentName == name
        local stroke = accentStrokes[name]
        if stroke then
            stroke.Transparency = selected and 0 or 0.55
            stroke.Color = selected and Theme.Text or Theme.Border
        end
    end
end

for _, name in ipairs(ACCENT_ORDER) do
    local palette = ACCENTS[name]
    local button = Instance.new("TextButton")
    button.Size = UDim2.fromOffset(26, 26)
    button.BackgroundColor3 = palette.color
    button.BorderSizePixel = 0
    button.AutoButtonColor = false
    button.Text = ""
    button.Parent = accentSwatches
    round(button, 7)
    local stroke = addStroke(button, Theme.Border, 1, 0.55)
    accentStrokes[name] = stroke
    accentButtons[name] = button
    connect(button.MouseButton1Click, function()
        S.uiAccent = name
        Theme.SetAccent(name)
        refreshAccentButtons()
        scheduleSave()
        Notify("Appearance", "Accent set to " .. name .. ".", "info", 2.2)
    end)
    Tooltip.Attach(button, name .. " accent")
end
refreshAccentButtons()

UI.AddControl(appearanceBody, Controls["ui.reducedMotion"])
UI.AddControl(appearanceBody, Controls["ui.tooltips"])
UI.AddControl(appearanceBody, Controls["ui.quickDock"])

local keyboardCard, keyboardBody = UI.Card(
    settingsContent,
    "Keyboard & search",
    "The application can be hidden or shown at any time with its keybind."
)

local keybindRow = Instance.new("Frame")
keybindRow.Size = UDim2.new(1, 0, 0, 46)
keybindRow.BackgroundTransparency = 1
keybindRow.BorderSizePixel = 0
keybindRow.Parent = keyboardBody

local keybindLabel = createText(
    keybindRow,
    "Show / hide keybind",
    12,
    Theme.Text,
    Enum.Font.GothamMedium
)
keybindLabel.Size = UDim2.new(1, -180, 1, 0)
Tooltip.Attach(keybindLabel, "The key used to show or hide Visual Control. Click Change, then press a key.")

local keybindValue = createText(
    keybindRow,
    keyDisplayName(S.keybindName),
    10,
    Theme.TextSecondary,
    Enum.Font.Code
)
keybindValue.Size = UDim2.fromOffset(74, 22)
keybindValue.Position = UDim2.new(1, -178, 0.5, -11)
keybindValue.TextXAlignment = Enum.TextXAlignment.Center

local keybindButton
keybindButton = UI.Button(keybindRow, {
    text = "Change",
    variant = "secondary",
    size = UDim2.fromOffset(86, 30),
    textSize = 9.5,
    onClick = function()
        Runtime.CapturingKey = true
        keybindButton.Text = "Press a key…"
        keybindValue.Text = "…"
        Notify("Keybind", "Press a key to assign, or Escape to cancel.", "info", 3)
    end,
})
keybindButton.Position = UDim2.new(1, -96, 0.5, -15)

local searchRow = createText(
    keyboardBody,
    "Ctrl+K opens global settings search while the application is visible.",
    9.5,
    Theme.TextMuted,
    Enum.Font.Gotham
)
searchRow.Size = UDim2.new(1, 0, 0, 0)
searchRow.AutomaticSize = Enum.AutomaticSize.Y
searchRow.TextWrapped = true
searchRow.TextYAlignment = Enum.TextYAlignment.Top

local persistenceCard, persistenceBody = UI.Card(
    settingsContent,
    "Persistence",
    "Saved data uses the executor's local filesystem APIs when available. No data is uploaded."
)
UI.AddControl(persistenceBody, Controls["ui.rememberSettings"])

local persistenceStatus = createText(
    persistenceBody,
    "",
    9.5,
    Theme.TextMuted,
    Enum.Font.Gotham
)
persistenceStatus.Size = UDim2.new(1, 0, 0, 0)
persistenceStatus.AutomaticSize = Enum.AutomaticSize.Y
persistenceStatus.TextWrapped = true
persistenceStatus.TextYAlignment = Enum.TextYAlignment.Top

local persistenceButtons = UI.ButtonRow(persistenceBody, {
    {
        text = "Save now",
        variant = "secondary",
        onClick = function()
            if not Storage.Available then
                Notify("Storage", "Filesystem APIs are unavailable.", "warning")
                return
            end
            local ok = savePreferences(true, false)
            if ok then
                Notify("Storage", "Preferences saved.", "success", 2.3)
            end
        end,
    },
    {
        text = "Clear saved data",
        variant = "danger",
        onClick = function()
            if not Storage.Available or type(DelFile) ~= "function" then
                Notify("Storage", "Deleting saved data is unavailable.", "warning")
                return
            end
            UI.Confirm({
                title = "Clear saved data?",
                message = "Delete the local Visual Control preferences file? Settings and custom presets stored in the file will be removed.",
                confirmText = "Delete file",
                danger = true,
                onConfirm = function()
                    local ok, err = pcall(DelFile, CONFIG_FILE)
                    if ok then
                        Notify("Storage", "Saved preferences deleted.", "success", 2.5)
                    else
                        Notify("Storage", "Could not delete saved data: " .. tostring(err), "error")
                    end
                end,
            })
        end,
    },
})

local lifecycleCard, lifecycleBody = UI.Card(
    settingsContent,
    "Application lifecycle",
    "Visual Control can be hidden, minimized, or fully unloaded. Unloading restores every original environment value it snapshotted."
)
local lifecycleButtons = UI.ButtonRow(lifecycleBody, {
    {
        text = "Hide window",
        variant = "secondary",
        onClick = function()
            if UI.Hide then UI.Hide() end
        end,
    },
    {
        text = "Unload & restore",
        variant = "danger",
        onClick = function()
            UI.Confirm({
                title = "Unload Visual Control?",
                message = "This stops the personal audio player, removes Visual Control effects, and restores the original Lighting, Atmosphere, Clouds, camera FOV, and fog values. Saved preferences remain.",
                confirmText = "Unload & restore",
                danger = true,
                onConfirm = function()
                    if Controller and Controller.Cleanup then
                        task.defer(Controller.Cleanup)
                    end
                end,
            })
        end,
    },
})

local aboutCard, aboutBody = UI.Card(
    settingsContent,
    "About",
    "A self-contained client-side visual environment suite."
)
local function aboutContent()
    return string.format(
        "%s  ·  v%s\nSelf-contained Luau distribution. No remote code loading. No gameplay or game-audio modifications.\n\nShow / hide keybind: %s\nSearch shortcut: Ctrl+K\n\nClient-side visual approximations only. Visual Control does not implement GPU shaders, true ray tracing, or framebuffer analysis.",
        APP_NAME,
        VERSION,
        keyDisplayName(S.keybindName)
    )
end

local aboutText = createText(
    aboutBody,
    aboutContent(),
    9.5,
    Theme.TextSecondary,
    Enum.Font.Gotham
)
aboutText.Size = UDim2.new(1, 0, 0, 0)
aboutText.AutomaticSize = Enum.AutomaticSize.Y
aboutText.TextWrapped = true
aboutText.TextYAlignment = Enum.TextYAlignment.Top

UI.SettingsRefs = {
    KeybindButton = keybindButton,
    KeybindValue = keybindValue,
    AboutText = aboutText,
}

local function updateSettingsPage()
    refreshAccentButtons()
    aboutText.Text = aboutContent()
    if not Runtime.CapturingKey then
        keybindValue.Text = keyDisplayName(S.keybindName)
        keybindButton.Text = "Change"
    end
    if Storage.Available then
        if S.rememberSettings then
            persistenceStatus.Text = "Preference saving is enabled. File: " .. CONFIG_FILE
            persistenceStatus.TextColor3 = Theme.TextMuted
        else
            persistenceStatus.Text = "Preference saving is disabled. File: " .. CONFIG_FILE
            persistenceStatus.TextColor3 = Theme.Warning
        end
        if Storage.LoadError then
            persistenceStatus.Text = persistenceStatus.Text .. "\nLoad error: " .. Storage.LoadError
            persistenceStatus.TextColor3 = Theme.Danger
        end
        if Storage.LastError then
            persistenceStatus.Text = persistenceStatus.Text .. "\nLast error: " .. Storage.LastError
            persistenceStatus.TextColor3 = Theme.Danger
        end
    else
        persistenceStatus.Text = "Filesystem APIs are unavailable. Settings are session-only."
        persistenceStatus.TextColor3 = Theme.Warning
    end
end

UI.RefreshSettingsPage = updateSettingsPage
settingsMeta.OnShown = updateSettingsPage
end)()

--============================================================
-- 39 / QUICK DOCK AND WINDOW VISIBILITY
--============================================================

;(function()
local Dock = createCanvas(Gui, "QuickDock")
Dock.AnchorPoint = Vector2.new(1, 1)
Dock.Position = UDim2.new(1, -18, 1, -18)
Dock.Size = UDim2.fromOffset(330, 60)
Dock.BackgroundColor3 = Theme.Window
Dock.BackgroundTransparency = 0.03
Dock.GroupTransparency = 1
Dock.Visible = false
Dock.Active = true
Dock.ZIndex = 30
round(Dock, 13)
addStroke(Dock, Theme.Border, 1, 0.2)

local dockScale = Instance.new("UIScale")
dockScale.Scale = 1
dockScale.Parent = Dock

local dockShadow = Instance.new("Frame")
dockShadow.Position = UDim2.fromOffset(0, 6)
dockShadow.Size = UDim2.fromScale(1, 1)
dockShadow.BackgroundColor3 = Theme.Black
dockShadow.BackgroundTransparency = 0.78
dockShadow.BorderSizePixel = 0
dockShadow.ZIndex = 0
dockShadow.Parent = Dock
round(dockShadow, 13)

local dockLogo = Instance.new("Frame")
dockLogo.Size = UDim2.fromOffset(30, 30)
dockLogo.Position = UDim2.fromOffset(12, 15)
dockLogo.BackgroundColor3 = Theme.Accent
dockLogo.BorderSizePixel = 0
dockLogo.ZIndex = 2
dockLogo.Parent = Dock
round(dockLogo, 8)
local dockLogoGradient = Instance.new("UIGradient")
dockLogoGradient.Rotation = 135
dockLogoGradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Theme.AccentHover),
    ColorSequenceKeypoint.new(1, Theme.Accent),
})
dockLogoGradient.Parent = dockLogo
local dockLogoText = UI.Glyph(dockLogo, "V", 15, Theme.AccentInk)
dockLogoText.Size = UDim2.fromScale(1, 1)
dockLogoText.BackgroundTransparency = 1
dockLogoText.ZIndex = 3
Theme.Bind(function()
    dockLogoGradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Theme.AccentHover),
        ColorSequenceKeypoint.new(1, Theme.Accent),
    })
    dockLogoText.TextColor3 = Theme.AccentInk
end, dockLogo)

local dockTitle = createText(
    Dock,
    "VISUAL CONTROL",
    9,
    Theme.Text,
    Enum.Font.GothamBold
)
dockTitle.Size = UDim2.fromOffset(132, 14)
dockTitle.Position = UDim2.fromOffset(50, 10)
dockTitle.ZIndex = 2

local dockSubtitle = createText(
    Dock,
    "Natural  ·  Clear",
    8.5,
    Theme.TextMuted,
    Enum.Font.Gotham
)
dockSubtitle.Size = UDim2.fromOffset(140, 14)
dockSubtitle.Position = UDim2.fromOffset(50, 25)
dockSubtitle.TextTruncate = Enum.TextTruncate.AtEnd
dockSubtitle.ZIndex = 2

local dockWeather = createText(
    Dock,
    "Open air",
    8,
    Theme.TextMuted,
    Enum.Font.Gotham
)
dockWeather.Size = UDim2.fromOffset(140, 12)
dockWeather.Position = UDim2.fromOffset(50, 38)
dockWeather.TextTruncate = Enum.TextTruncate.AtEnd
dockWeather.ZIndex = 2

local dockActions = Instance.new("Frame")
dockActions.AnchorPoint = Vector2.new(1, 0.5)
dockActions.Position = UDim2.new(1, -10, 0.5, 0)
dockActions.Size = UDim2.fromOffset(126, 32)
dockActions.BackgroundTransparency = 1
dockActions.BorderSizePixel = 0
dockActions.ZIndex = 2
dockActions.Parent = Dock
addHorizontalList(dockActions, 3)

local dockPresetButton = UI.IconButton(dockActions, {
    icon = "presets",
    iconSize = 14,
    size = UDim2.fromOffset(28, 28),
    tooltip = "Apply the next visual preset",
    onClick = function()
        UI.CyclePreset()
    end,
})
dockPresetButton.LayoutOrder = 1

local dockWeatherButton = UI.IconButton(dockActions, {
    icon = "weather",
    iconSize = 14,
    size = UDim2.fromOffset(28, 28),
    tooltip = "Cycle weather",
    onClick = function()
        UI.CycleWeather()
    end,
})
dockWeatherButton.LayoutOrder = 2

local dockPlay, dockPlayGlyph = UI.GlyphButton(dockActions, {
    glyph = "▶",
    glyphSize = 12,
    size = UDim2.fromOffset(28, 28),
    tooltip = "Play or pause personal music",
    onClick = function()
        local ok, err = AudioManager.TogglePlay()
        if not ok and err then
            Notify("Audio", err, "warning", 2.5)
        end
    end,
})
dockPlay.LayoutOrder = 3

local dockOpen = UI.IconButton(dockActions, {
    icon = "dashboard",
    iconSize = 14,
    size = UDim2.fromOffset(28, 28),
    tooltip = "Open Visual Control",
    onClick = function()
        UI.Show()
    end,
})
dockOpen.LayoutOrder = 4
UI.NormalizeLayout(dockActions)

local function updateQuickDock()
    dockSubtitle.Text = ActivePreset .. "  ·  " .. S.weather
    dockWeather.Text = Environment.Classification
    dockPlayGlyph.Text = AudioManager.IsPlaying() and "II" or "▶"
    local viewport = Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize
        or Vector2.new(1280, 720)
    dockScale.Scale = clamp((viewport.X - 24) / 330, 0.50, 1)
end

function UI.UpdateQuickDock()
    updateQuickDock()
end

local function showDock()
    if not S.quickDock or Runtime.Closed then
        Dock.Visible = false
        return
    end
    updateQuickDock()
    if Dock.Visible and Dock.GroupTransparency < 0.05 then
        return
    end
    Dock.Visible = true
    Dock.GroupTransparency = 1
    Motion.Tween(Dock, { GroupTransparency = 0 }, 0.24)
end

local function hideDock()
    if not Dock.Visible then return end
    if Motion.Reduced then
        Dock.Visible = false
        return
    end
    Motion.Tween(Dock, { GroupTransparency = 1 }, 0.16)
    task.delay(0.18, function()
        if Runtime.Closed then return end
        if Runtime.Visible or not S.quickDock then
            Dock.Visible = false
        end
    end)
end

local function setWindowVisible(visible, immediate)
    visible = visible == true
    if Runtime.Closed then return end
    if Runtime.Visible == visible and not immediate then
        return
    end
    Runtime.Visible = visible

    if visible then
        hideDock()
        WindowRoot.Visible = true
        Layout.UpdateViewport(true)
        if Runtime.Minimized then
            Layout.SetMinimized(false)
        end
        if immediate or Motion.Reduced then
            WindowRoot.GroupTransparency = 0
        else
            WindowRoot.GroupTransparency = 1
            Motion.Tween(WindowRoot, { GroupTransparency = 0 }, 0.22)
        end
        Tooltip.SetEnabled(S.tooltips)
        Events.VisibilityChanged:Fire(true)
    else
        cancelKeyCaptureUI()
        closeModal(true)
        closeDropdown()
        Tooltip.Hide()
        Pointer.Cancel(true)
        Runtime.Compare = false
        if immediate or Motion.Reduced then
            WindowRoot.Visible = false
            WindowRoot.GroupTransparency = 1
        else
            Motion.Tween(WindowRoot, { GroupTransparency = 1 }, 0.18)
            task.delay(0.19, function()
                if Runtime.Closed then return end
                if not Runtime.Visible then
                    WindowRoot.Visible = false
                end
            end)
        end
        showDock()
        Events.VisibilityChanged:Fire(false)
    end
end

function UI.Hide()
    setWindowVisible(false, false)
end

function UI.Show()
    setWindowVisible(true, false)
end

function UI.ToggleVisible()
    setWindowVisible(not Runtime.Visible, false)
end

function UI.RefreshDockVisibility()
    if Runtime.Visible then
        hideDock()
    elseif S.quickDock then
        showDock()
    else
        hideDock()
    end
end
end)()

--============================================================
-- 40 / SETTINGS SEARCH
--============================================================

;(function()
local function buildSearchIndex()
    local entries = {}
    for id, pageData in pairs(Pages) do
        table.insert(entries, {
            kind = "page",
            page = id,
            title = pageData.Title.Text,
            description = pageData.Subtitle.Text,
            search = (id .. " " .. pageData.Subtitle.Text):lower(),
        })
    end
    for _, control in ipairs(ControlOrder) do
        table.insert(entries, {
            kind = "control",
            page = control.page,
            control = control,
            title = control.title,
            description = control.description,
            search = table.concat({
                control.title or "",
                control.description or "",
                control.page or "",
                control.keywords or "",
            }, " "):lower(),
        })
    end
    for _, preset in pairs(BuiltinPresets) do
        table.insert(entries, {
            kind = "preset",
            page = "Presets",
            preset = preset,
            title = preset.name,
            description = preset.description,
            search = (preset.name .. " " .. preset.description .. " preset"):lower(),
        })
    end
    for _, preset in ipairs(CustomPresets) do
        table.insert(entries, {
            kind = "preset",
            page = "Presets",
            preset = preset,
            title = preset.name,
            description = preset.description or "Custom visual preset.",
            search = (preset.name .. " custom preset"):lower(),
        })
    end
    for _, weatherName in ipairs({ "Clear", "Overcast", "Rain", "Snow", "Fog" }) do
        table.insert(entries, {
            kind = "weather",
            page = "Weather",
            title = weatherName .. " weather",
            description = "Open the Weather page and choose " .. weatherName .. ".",
            search = (weatherName .. " weather condition precipitation"):lower(),
        })
    end
    return entries
end

local SearchEntries = nil

function UI.OpenSearch()
    if not Runtime.Visible then
        UI.Show()
    end
    if Runtime.Minimized then
        Layout.SetMinimized(false)
    end
    if CurrentDropdown then
        closeDropdown()
    end
    SearchEntries = buildSearchIndex()
    local resultsScope = nil
    local searchBox
    local resultsFrame

    local function refreshResults(query)
        if resultsScope then resultsScope:Destroy() end
        resultsScope = newScope()
        clearGuiChildren(resultsFrame)
        query = tostring(query or ""):lower():match("^%s*(.-)%s*$")
        local scored = {}
        for _, entry in ipairs(SearchEntries) do
            local score = nil
            local titleLower = entry.title:lower()
            if query == "" then
                score = entry.kind == "page" and 2 or 8
            elseif titleLower == query then
                score = 1
            elseif titleLower:sub(1, #query) == query then
                score = 2
            elseif titleLower:find(query, 1, true) then
                score = 3
            elseif entry.search:find(query, 1, true) then
                score = 4
            end
            if score then
                table.insert(scored, { entry = entry, score = score })
            end
        end
        table.sort(scored, function(a, b)
            if a.score == b.score then
                return a.entry.title < b.entry.title
            end
            return a.score < b.score
        end)

        if #scored == 0 then
            local emptyLabel = createText(
                resultsFrame,
                "No matching settings.",
                10.5,
                Theme.TextMuted,
                Enum.Font.Gotham
            )
            emptyLabel.Size = UDim2.new(1, 0, 0, 40)
            emptyLabel.TextXAlignment = Enum.TextXAlignment.Center
            resultsScope:AddObject(emptyLabel)
            return
        end

        local count = math.min(#scored, 14)
        for index = 1, count do
            local item = scored[index]
            local entry = item.entry
            local row = Instance.new("TextButton")
            row.Size = UDim2.new(1, 0, 0, 46)
            row.BackgroundColor3 = Theme.Card
            row.BackgroundTransparency = 0.1
            row.BorderSizePixel = 0
            row.AutoButtonColor = false
            row.Text = ""
            row.LayoutOrder = index
            row.Parent = resultsFrame
            round(row, 8)
            resultsScope:AddObject(row)

            local iconName = entry.kind == "page" and "dashboard"
                or entry.kind == "preset" and "presets"
                or entry.kind == "weather" and "weather"
                or "settings"
            local icon = UI.Icon(iconName, 14, Theme.TextMuted, row)
            icon.Frame.Position = UDim2.fromOffset(12, 16)

            local title = createText(
                row,
                entry.title,
                11,
                Theme.Text,
                Enum.Font.GothamMedium
            )
            title.Size = UDim2.new(1, -150, 0, 20)
            title.Position = UDim2.fromOffset(34, 5)
            title.TextTruncate = Enum.TextTruncate.AtEnd

            local description = createText(
                row,
                entry.description or "",
                8.5,
                Theme.TextMuted,
                Enum.Font.Gotham
            )
            description.Size = UDim2.new(1, -150, 0, 16)
            description.Position = UDim2.fromOffset(34, 24)
            description.TextTruncate = Enum.TextTruncate.AtEnd

            local pageTag = createText(
                row,
                entry.page,
                8,
                Theme.TextMuted,
                Enum.Font.Code
            )
            pageTag.Size = UDim2.fromOffset(100, 16)
            pageTag.Position = UDim2.new(1, -112, 0, 15)
            pageTag.TextXAlignment = Enum.TextXAlignment.Right

            resultsScope:Connect(row.MouseEnter, function()
                Motion.Tween(row, {
                    BackgroundColor3 = Theme.CardHover,
                    BackgroundTransparency = 0,
                }, 0.10)
            end)
            resultsScope:Connect(row.MouseLeave, function()
                Motion.Tween(row, {
                    BackgroundColor3 = Theme.Card,
                    BackgroundTransparency = 0.1,
                }, 0.12)
            end)
            resultsScope:Connect(row.MouseButton1Click, function()
                closeModal(false)
                if entry.kind == "control" and entry.control then
                    UI.PulseControl(entry.control)
                elseif entry.kind == "preset" and entry.preset then
                    UI.Navigate("Presets")
                    task.delay(0.20, function()
                        if not Runtime.Closed then
                            UI.OpenPresetDetails(entry.preset)
                        end
                    end)
                else
                    UI.Navigate(entry.page)
                end
            end)
        end
    end

    UI.Modal({
        title = "Search settings",
        subtitle = "Find controls, pages, presets, and weather conditions.",
        width = 620,
        bodyHeight = 408,
        dismissible = true,
        build = function(body)
            searchBox = UI.TextField(body, {
                placeholder = "Search bloom, exposure, rain, preset…",
                size = UDim2.new(1, 0, 0, 38),
                name = "SearchBox",
            })
            connectOwner(searchBox, searchBox.TextChanged, function()
                refreshResults(searchBox.Text)
            end)

            resultsFrame = Instance.new("ScrollingFrame")
            resultsFrame.Size = UDim2.new(1, 0, 0, 354)
            resultsFrame.BackgroundTransparency = 1
            resultsFrame.BorderSizePixel = 0
            resultsFrame.ScrollBarThickness = 3
            resultsFrame.ScrollBarImageColor3 = Theme.Track
            resultsFrame.CanvasSize = UDim2.fromOffset(0, 0)
            resultsFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
            resultsFrame.ScrollingDirection = Enum.ScrollingDirection.Y
            resultsFrame.Parent = body
            addVerticalList(resultsFrame, 4)

            refreshResults("")
        end,
        onOpen = function()
            task.defer(function()
                if not Runtime.Closed and searchBox and searchBox.Parent then
                    searchBox:CaptureFocus()
                end
            end)
        end,
        onClose = function()
            if resultsScope then
                resultsScope:Destroy()
                resultsScope = nil
            end
        end,
    })
end
end)()

--============================================================
-- 41 / STATE SYNCHRONIZATION
--============================================================

;(function()
function UI.SyncFromState()
    for _, control in ipairs(ControlOrder) do
        control:Refresh()
    end
    UI.RefreshConditional()
    Tooltip.SetEnabled(S.tooltips)
    if UI.RefreshWeatherPage then UI.RefreshWeatherPage() end
    if UI.RefreshLightingPage then UI.RefreshLightingPage() end
    if UI.RefreshPresetIndicators then UI.RefreshPresetIndicators() end
    if UI.RefreshAtmosphereStatus then UI.RefreshAtmosphereStatus() end
    if UI.RefreshPerformance then UI.RefreshPerformance() end
    if UI.RefreshSettingsPage then UI.RefreshSettingsPage() end
    if UI.RefreshAudioPage then UI.RefreshAudioPage() end
    if UI.RefreshDashboard then UI.RefreshDashboard() end
    if UI.UpdateQuickDock then UI.UpdateQuickDock() end
    if UI.RefreshDockVisibility then UI.RefreshDockVisibility() end
end

connect(Events.ControlChanged, function(control)
    if not Runtime.ApplyingPreset and control.affectsPreset then
        ActivePreset = "Custom"
        if UI.RefreshPresetIndicators then
            UI.RefreshPresetIndicators()
        end
    end

    if control.id == "ui.tooltips" then
        Tooltip.SetEnabled(S.tooltips)
    elseif control.id == "ui.reducedMotion" then
        if S.reducedMotion then
            Overlay.CancelFlash()
        end
    elseif control.id == "ui.quickDock" then
        UI.RefreshDockVisibility()
    elseif control.id == "ui.rememberSettings" then
        if S.rememberSettings then
            scheduleSave()
        else
            savePreferences(true, true)
        end
    elseif control.id == "performance.quality" then
        Notify(
            "Performance",
            "Quality profile set to " .. S.quality .. ".",
            "info",
            2.4
        )
    end

    UI.RefreshConditional()
    if CurrentPage == "Dashboard" and UI.RefreshDashboard then
        UI.RefreshDashboard()
    elseif CurrentPage == "Weather" and UI.RefreshWeatherPage then
        UI.RefreshWeatherPage()
    elseif CurrentPage == "Performance" and UI.RefreshPerformance then
        UI.RefreshPerformance()
    elseif CurrentPage == "Atmosphere" and UI.RefreshAtmosphereStatus then
        UI.RefreshAtmosphereStatus()
    elseif CurrentPage == "Audio" and UI.RefreshAudioPage then
        UI.RefreshAudioPage()
    elseif CurrentPage == "Settings" and UI.RefreshSettingsPage then
        UI.RefreshSettingsPage()
    elseif CurrentPage == "Presets" and UI.RefreshPresetIndicators then
        UI.RefreshPresetIndicators()
    end
    if UI.UpdateQuickDock then UI.UpdateQuickDock() end
    scheduleSave()
end)
end)()

--============================================================
-- 42 / LIVE INTERFACE REFRESH
--============================================================

;(function()
function UI.RefreshLive()
    if Runtime.Closed or Runtime.CleanupStarted then return end
    if not Runtime.Visible then
        if UI.UpdateQuickDock then UI.UpdateQuickDock() end
        return
    end
    Layout.UpdateViewport()
    SidebarEnvLabel.Text = Environment.Classification

    if Pages.Graphics and Pages.Graphics.Badge then
        Pages.Graphics.Badge.Text = Runtime.Compare and "COMPARE"
            or (S.effectsEnabled and "ACTIVE" or "BYPASSED")
    end
    if Pages.Lighting and Pages.Lighting.Badge then
        Pages.Lighting.Badge.Text = timeOfDayLabel(
            S.timeOverride and S.clockTime or Lighting.ClockTime
        )
    end
    if Pages.Atmosphere and Pages.Atmosphere.Badge then
        Pages.Atmosphere.Badge.Text = (S.atmosphereEnabled or S.cloudsEnabled)
            and "ENABLED" or "OFF"
    end
    if Pages.Weather and Pages.Weather.Badge then
        Pages.Weather.Badge.Text = string.upper(S.weather)
    end
    if Pages.Camera and Pages.Camera.Badge then
        Pages.Camera.Badge.Text = (S.fovEnabled or S.dofEnabled)
            and "ACTIVE" or "STANDBY"
    end
    if Pages.Audio and Pages.Audio.Badge then
        Pages.Audio.Badge.Text = AudioManager.Loading and "LOADING"
            or (AudioManager.IsPlaying() and "PLAYING"
                or (AudioManager.Status == "Paused" and "PAUSED" or "IDLE"))
    end
    if Pages.Performance and Pages.Performance.Badge then
        Pages.Performance.Badge.Text = string.format("%.0f FPS", Metrics.SmoothedFPS)
    end
    if Pages.Presets and Pages.Presets.Badge then
        Pages.Presets.Badge.Text = #CustomPresets > 0
            and (#CustomPresets .. " CUSTOM")
            or (#PresetOrder .. " BUILT-IN")
    end
    if Pages.Settings and Pages.Settings.Badge then
        Pages.Settings.Badge.Text = "v" .. VERSION
    end

    if CurrentPage == "Dashboard" then
        UI.RefreshDashboard()
    elseif CurrentPage == "Weather" then
        UI.RefreshWeatherPage()
    elseif CurrentPage == "Performance" then
        UI.RefreshPerformance()
    elseif CurrentPage == "Atmosphere" then
        UI.RefreshAtmosphereStatus()
    elseif CurrentPage == "Audio" then
        UI.RefreshAudioPage()
    elseif CurrentPage == "Settings" then
        UI.RefreshSettingsPage()
    end

    if UI.UpdateQuickDock then UI.UpdateQuickDock() end
end
end)()

--============================================================
-- 43 / INPUT, KEYBIND, AND SEARCH SHORTCUT
--============================================================

;(function()
local settingsRefs = UI.SettingsRefs

local function getKeybind()
    local ok, keyCode = pcall(function()
        return Enum.KeyCode[S.keybindName]
    end)
    if ok and keyCode and keyCode ~= KEYCODE_NONE then
        return keyCode
    end
    return Enum.KeyCode.Equals
end

local function finishKeyCapture(cancelled)
    Runtime.CapturingKey = false
    if settingsRefs and settingsRefs.KeybindButton then
        settingsRefs.KeybindButton.Text = "Change"
    end
    if settingsRefs and settingsRefs.KeybindValue then
        settingsRefs.KeybindValue.Text = keyDisplayName(S.keybindName)
    end
    if cancelled then
        Notify("Keybind", "Key assignment cancelled.", "info", 2.2)
    else
        Notify("Keybind", "Show / hide keybind set to " .. keyDisplayName(S.keybindName) .. ".", "success", 2.6)
    end
end

connect(UserInputService.InputBegan, function(input, gameProcessed)
    if Runtime.Closed or Runtime.CleanupStarted then return end

    if Runtime.CapturingKey then
        if UserInputService:GetFocusedTextBox() then
            cancelKeyCaptureUI()
            return
        end
        if input.UserInputType ~= Enum.UserInputType.Keyboard then
            return
        end
        if input.KeyCode == KEYCODE_NONE then
            return
        end
        if input.KeyCode == Enum.KeyCode.Escape then
            finishKeyCapture(true)
            return
        end
        S.keybindName = input.KeyCode.Name
        finishKeyCapture(false)
        scheduleSave()
        return
    end

    if input.KeyCode == Enum.KeyCode.Escape then
        if UI.CloseTopLayer() then
            return
        end
    end

    if not Runtime.Visible then
        if not gameProcessed and input.KeyCode == getKeybind() then
            UI.Show()
            return
        end
    end

    if gameProcessed then
        return
    end

    local focusedTextBox = UserInputService:GetFocusedTextBox()
    if focusedTextBox then
        return
    end

    if input.KeyCode == Enum.KeyCode.K
        and (input:IsKeyDown(Enum.KeyCode.LeftControl)
            or input:IsKeyDown(Enum.KeyCode.RightControl))
        and Runtime.Visible
        and not CurrentModal then
        UI.OpenSearch()
        return
    end

    if input.KeyCode == getKeybind() then
        UI.ToggleVisible()
    end
end)
end)()

--============================================================
-- 44 / BOOT SPLASH
--============================================================

;(function()
local Splash = createCanvas(Main, "BootSplash")
Splash.Size = UDim2.fromScale(1, 1)
Splash.BackgroundColor3 = Theme.Window
Splash.BackgroundTransparency = 0
Splash.GroupTransparency = 0
Splash.ZIndex = 8000
Splash.Active = true
round(Splash, 14)

local splashGlow = Instance.new("Frame")
splashGlow.AnchorPoint = Vector2.new(0.5, 0.5)
splashGlow.Position = UDim2.new(0.5, 0, 0.45, 0)
splashGlow.Size = UDim2.fromOffset(300, 300)
splashGlow.BackgroundColor3 = Theme.Accent
splashGlow.BackgroundTransparency = 0.94
splashGlow.BorderSizePixel = 0
splashGlow.ZIndex = 8001
splashGlow.Parent = Splash
round(splashGlow, 150)
Theme.Bind(function()
    splashGlow.BackgroundColor3 = Theme.Accent
end, splashGlow)

local splashLogo = Instance.new("Frame")
splashLogo.AnchorPoint = Vector2.new(0.5, 0.5)
splashLogo.Position = UDim2.new(0.5, 0, 0.5, -36)
splashLogo.Size = UDim2.fromOffset(46, 46)
splashLogo.BackgroundColor3 = Theme.Accent
splashLogo.BorderSizePixel = 0
splashLogo.ZIndex = 8002
splashLogo.Parent = Splash
round(splashLogo, 13)
local splashGradient = Instance.new("UIGradient")
splashGradient.Rotation = 135
splashGradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Theme.AccentHover),
    ColorSequenceKeypoint.new(1, Theme.Accent),
})
splashGradient.Parent = splashLogo
local splashLetter = UI.Glyph(splashLogo, "V", 24, Theme.AccentInk)
splashLetter.Size = UDim2.fromScale(1, 1)
splashLetter.BackgroundTransparency = 1
splashLetter.ZIndex = 8003

local splashTitle = createText(
    Splash,
    "VISUAL CONTROL REBORN",
    16,
    Theme.Text,
    Enum.Font.GothamBold
)
splashTitle.AnchorPoint = Vector2.new(0.5, 0.5)
splashTitle.Position = UDim2.new(0.5, 0, 0.5, 18)
splashTitle.Size = UDim2.fromOffset(320, 24)
splashTitle.TextXAlignment = Enum.TextXAlignment.Center
splashTitle.ZIndex = 8002

local splashSubtitle = createText(
    Splash,
    "INITIALIZING VISUAL ENGINE",
    8.5,
    Theme.TextMuted,
    Enum.Font.GothamBold
)
splashSubtitle.AnchorPoint = Vector2.new(0.5, 0.5)
splashSubtitle.Position = UDim2.new(0.5, 0, 0.5, 40)
splashSubtitle.Size = UDim2.fromOffset(320, 16)
splashSubtitle.TextXAlignment = Enum.TextXAlignment.Center
splashSubtitle.ZIndex = 8002

local splashTrack = Instance.new("Frame")
splashTrack.AnchorPoint = Vector2.new(0.5, 0.5)
splashTrack.Position = UDim2.new(0.5, 0, 0.5, 72)
splashTrack.Size = UDim2.fromOffset(220, 3)
splashTrack.BackgroundColor3 = Theme.Track
splashTrack.BorderSizePixel = 0
splashTrack.ZIndex = 8002
splashTrack.Parent = Splash
round(splashTrack, 1.5)

local splashFill = Instance.new("Frame")
splashFill.Size = UDim2.new(0, 0, 1, 0)
splashFill.BackgroundColor3 = Theme.Accent
splashFill.BorderSizePixel = 0
splashFill.ZIndex = 8003
splashFill.Parent = splashTrack
round(splashFill, 1.5)
Theme.Bind(function()
    splashFill.BackgroundColor3 = Theme.Accent
end, splashFill)

Motion.Tween(splashFill, {
    Size = UDim2.new(1, 0, 1, 0),
}, 0.72, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

task.delay(Motion.Reduced and 0.18 or 0.86, function()
    if not Splash.Parent then return end
    Motion.Tween(Splash, { GroupTransparency = 1 }, 0.30)
    task.delay(0.34, function()
        if Splash.Parent then Splash:Destroy() end
    end)
end)
end)()

--============================================================
-- 45 / INITIALIZATION
--============================================================

;(function()
Runtime.Visible = true
Runtime.Minimized = false
WindowRoot.Visible = true
WindowRoot.GroupTransparency = 0
UI.NormalizeLayout(PageHost)
UI.NormalizeLayout(SidebarNav)
UI.NormalizeLayout(HeaderActions)
UI.NormalizeLayout(ToastHost)
Layout.UpdateViewport(true)
UI.Navigate("Dashboard", true)
UI.SyncFromState()
UI.RefreshLive()
UI.RefreshDockVisibility()
Tooltip.SetEnabled(S.tooltips)
UI.UpdateQuickDock()

local UIRefreshAccumulator = 0

local function updateFrame(dt)
    if Runtime.Closed or Runtime.CleanupStarted then return end
    dt = math.clamp(dt, 0, 0.1)

    Metrics.Update(dt)
    Environment.Update(dt)
    Weather.Update(dt)
    Graphics.Update(dt)
    LightingManager.Update(dt)
    AtmosphereManager.Update(dt)
    AudioManager.Update(dt)
    CameraManager.Update(dt)

    UIRefreshAccumulator += dt
    if UIRefreshAccumulator >= 0.20 then
        UIRefreshAccumulator = 0
        UI.RefreshLive()
    end
end

RunService:BindToRenderStep(STEP_NAME, Enum.RenderPriority.Last.Value, updateFrame)
end)()

--============================================================
-- 46 / CLEANUP
--============================================================

local function cleanup()
    if Runtime.Closed or Runtime.CleanupStarted then return end
    Runtime.CleanupStarted = true

    if Storage.Available and S.rememberSettings then
        savePreferences(true, true)
    end

    Runtime.Closed = true
    Runtime.Visible = false
    Runtime.Compare = false
    Pointer.Cancel(false)
    Tooltip.Hide()
    NotifyExternal = nil

    pcall(function()
        RunService:UnbindFromRenderStep(STEP_NAME)
    end)

    for _, connection in ipairs(Connections) do
        pcall(function() connection:Disconnect() end)
    end
    Connections = {}

    closeModal(true)
    closeDropdown()

    LightingManager.Restore()
    restoreLightingCore()
    CameraManager.Restore()
    Weather.Destroy()
    AtmosphereManager.Restore()
    Overlay.Destroy()
    Graphics.Destroy()
    AudioManager.Destroy()

    for _, signal in pairs(Events) do
        if typeof(signal) == "table" and signal.Clear then
            pcall(function() signal:Clear() end)
        end
    end

    Theme.ClearBindings()
    for _, control in ipairs(ControlOrder) do
        control._bindings = {}
    end

    if Gui then
        Gui:Destroy()
    end

    if Controller then
        Controller.Cleanup = nil
    end
    pcall(function()
        if _G[GLOBAL_KEY] == Controller then
            _G[GLOBAL_KEY] = nil
        end
    end)

    print("[Visual Control Reborn] Unloaded and restored original environment values.")
end

Controller.Cleanup = cleanup

pcall(function()
    _G[GLOBAL_KEY] = Controller
end)

if Gui then
    Gui.Destroying:Connect(function()
        if not Runtime.Closed then
            cleanup()
        end
    end)
end

print(
    "[Visual Control Reborn] v" .. VERSION .. " loaded. Press "
    .. keyDisplayName(S.keybindName) .. " to show or hide the interface."
)
print("[Visual Control Reborn] Personal audio effects apply only to VisualControlReborn_Audio.")

--============================================================
-- END OF FILE
--============================================================

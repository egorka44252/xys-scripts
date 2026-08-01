--[[
    Xys Nova v10.0
    • Music engine rewrite (cache, load wait, reliable play/stop)
    • AutoExec after rejoin (queue_on_teleport)
    • Menu Dim global fix kept
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")
local SoundService = game:GetService("SoundService")
local Stats = game:GetService("Stats")

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")
local Camera = Workspace.CurrentCamera

-- prevent double inject
if getgenv().XysNovaLoaded then
    warn("[Xys Nova] already loaded")
    return
end
getgenv().XysNovaLoaded = true

for _, n in ipairs({"XysNova", "XysNovaMarker", "XysNovaHUD"}) do
    local o = PlayerGui:FindFirstChild(n) or Workspace:FindFirstChild(n)
    if o then o:Destroy() end
end
for _, n in ipairs({"XysNovaContrast", "XysNovaBlur"}) do
    local o = Lighting:FindFirstChild(n)
    if o then o:Destroy() end
end
pcall(function()
    local s = SoundService:FindFirstChild("XysNovaMusic")
    if s then s:Destroy() end
end)

----------------------------------------------------------------
-- CONFIG URLS
----------------------------------------------------------------
local REPO = "egorka44252/xys-scripts"
local FON_API = "https://api.github.com/repos/" .. REPO .. "/contents/fon"
local MUSIC_API = "https://api.github.com/repos/" .. REPO .. "/contents/music"
local ROOT_API = "https://api.github.com/repos/" .. REPO .. "/contents/"
local RAW_BASE = "https://raw.githubusercontent.com/" .. REPO .. "/main/"
local PRESETS_URL = RAW_BASE .. "bg-presets.json"
local PRESETS_FILE = "xys_bg_presets.json"
local CONFIG_FILE = "xys_nova_config.json"
-- put your full script raw URL here for AutoExec after rejoin
local SCRIPT_URL = RAW_BASE .. "xys-nova.lua"

local WIN_W, WIN_H = 820, 560
local TITLE_H, FOOTER_H, SIDE_W = 48, 34, 58
local CORNER = 16

local function defaultPreset()
    return { stretchX = 100, stretchY = 100, offsetX = 0, offsetY = 0 }
end
local BgPresets = {}

local State = {
    open = true, page = "Home",
    freecam = false, crosshair = false, contrast = false,
    observer = nil,
    cameraSpeed = 48,
    fov = math.floor(Camera.FieldOfView + 0.5),
    windowOpacity = 12, cardOpacity = 18, blurSize = 10,
    menuDim = 40,
    bgName = "none",
    bgStretchX = 100, bgStretchY = 100, bgOffsetX = 0, bgOffsetY = 0,
    flingPower = 500, flingMode = "Both",
    walkFling = false, spamFling = false, flingTarget = nil,
    musicName = "none", musicVolume = 50, musicPlaying = false,
    hudEnabled = true, hudShowFps = true, hudShowPing = true,
    hudPosX = 12, hudPosY = 12, hudSize = 14,
    autoexec = false,
    binds = {
        Menu = "RightShift", Freecam = "F", Marker = "M",
        Crosshair = "H", Hud = "P",
    },
}
local Connections = {}
local function connect(sig, fn)
    local c = sig:Connect(fn)
    table.insert(Connections, c)
    return c
end

local C = {
    bg = Color3.fromRGB(10, 10, 14), panel = Color3.fromRGB(16, 16, 22),
    card = Color3.fromRGB(24, 24, 32), card2 = Color3.fromRGB(32, 32, 42),
    border = Color3.fromRGB(45, 45, 60), accent = Color3.fromRGB(130, 86, 255),
    text = Color3.fromRGB(240, 240, 248), muted = Color3.fromRGB(140, 140, 160),
    green = Color3.fromRGB(80, 200, 120), red = Color3.fromRGB(255, 90, 100),
    orange = Color3.fromRGB(255, 160, 60),
}

local function new(cls, props, parent)
    local i = Instance.new(cls)
    for k, v in pairs(props or {}) do i[k] = v end
    i.Parent = parent
    return i
end
local function tween(obj, t, props, style)
    local a = TweenService:Create(obj, TweenInfo.new(t, style or Enum.EasingStyle.Quint, Enum.EasingDirection.Out), props)
    a:Play()
    return a
end
local function corner(p, r) return new("UICorner", { CornerRadius = UDim.new(0, r or CORNER) }, p) end
local function stroke(p, col, tr, th)
    return new("UIStroke", { Color = col or C.border, Transparency = tr or 0.35, Thickness = th or 1 }, p)
end

----------------------------------------------------------------
-- SAVE / LOAD
----------------------------------------------------------------
local function getPreset(name)
    if not name or name == "none" then return defaultPreset() end
    if not BgPresets[name] then BgPresets[name] = defaultPreset() end
    return BgPresets[name]
end
local function writeCurrentToPreset()
    if not State.bgName or State.bgName == "none" then return end
    BgPresets[State.bgName] = {
        stretchX = State.bgStretchX, stretchY = State.bgStretchY,
        offsetX = State.bgOffsetX, offsetY = State.bgOffsetY,
    }
end
local function applyPresetToState(name)
    local p = getPreset(name)
    State.bgStretchX = p.stretchX or 100
    State.bgStretchY = p.stretchY or 100
    State.bgOffsetX = p.offsetX or 0
    State.bgOffsetY = p.offsetY or 0
end
local function savePresetsLocal()
    writeCurrentToPreset()
    if not writefile then return false end
    return pcall(function() writefile(PRESETS_FILE, HttpService:JSONEncode(BgPresets)) end)
end
local function loadPresetsLocal()
    if not (isfile and readfile) then return false end
    local ok, data = pcall(function()
        if isfile(PRESETS_FILE) then return HttpService:JSONDecode(readfile(PRESETS_FILE)) end
    end)
    if ok and type(data) == "table" then
        for k, v in pairs(data) do if type(v) == "table" then BgPresets[k] = v end end
        return true
    end
    return false
end
local function loadPresetsGitHub()
    local ok, body = pcall(function() return game:HttpGet(PRESETS_URL) end)
    if not ok or not body or body:find("404") then return false end
    local ok2, data = pcall(HttpService.JSONDecode, HttpService, body)
    if ok2 and type(data) == "table" then
        for k, v in pairs(data) do if type(v) == "table" then BgPresets[k] = v end end
        return true
    end
    return false
end
local function exportConfig()
    writeCurrentToPreset()
    return {
        windowOpacity = State.windowOpacity, cardOpacity = State.cardOpacity,
        blurSize = State.blurSize, menuDim = State.menuDim, bgName = State.bgName,
        cameraSpeed = State.cameraSpeed, flingPower = State.flingPower,
        musicName = State.musicName, musicVolume = State.musicVolume,
        hudEnabled = State.hudEnabled, hudShowFps = State.hudShowFps,
        hudShowPing = State.hudShowPing, hudPosX = State.hudPosX,
        hudPosY = State.hudPosY, hudSize = State.hudSize,
        autoexec = State.autoexec, binds = State.binds,
    }
end
local function applyConfig(cfg)
    if type(cfg) ~= "table" then return end
    for _, k in ipairs({
        "windowOpacity","cardOpacity","blurSize","menuDim","bgName","cameraSpeed",
        "flingPower","musicName","musicVolume","hudEnabled","hudShowFps","hudShowPing",
        "hudPosX","hudPosY","hudSize","autoexec"
    }) do
        if cfg[k] ~= nil then State[k] = cfg[k] end
    end
    if type(cfg.binds) == "table" then
        for k, v in pairs(cfg.binds) do State.binds[k] = v end
    end
end
local function saveConfigLocal()
    if not writefile then return false end
    return pcall(function() writefile(CONFIG_FILE, HttpService:JSONEncode(exportConfig())) end)
end
local function loadConfigLocal()
    if not (isfile and readfile) then return false end
    local ok, data = pcall(function()
        if isfile(CONFIG_FILE) then return HttpService:JSONDecode(readfile(CONFIG_FILE)) end
    end)
    if ok and data then applyConfig(data) return true end
    return false
end

loadPresetsGitHub()
loadPresetsLocal()
loadConfigLocal()
if State.bgName and State.bgName ~= "none" then applyPresetToState(State.bgName) end

----------------------------------------------------------------
-- AUTOEXEC (rejoin inject)
----------------------------------------------------------------
local function buildAutoExecPayload()
    -- bootstrap: re-download main script after teleport
    return string.format([[
        if getgenv().XysNovaLoaded then return end
        local ok, err = pcall(function()
            loadstring(game:HttpGet(%q))()
        end)
        if not ok then warn("[Xys Nova AutoExec]", err) end
    ]], SCRIPT_URL)
end

local function applyAutoExec(on)
    State.autoexec = on
    if not queue_on_teleport then
        return false, "queue_on_teleport not supported by this executor"
    end
    if on then
        queue_on_teleport(buildAutoExecPayload())
        return true, "queued for next join/teleport"
    else
        -- cannot fully clear queue on all executors; re-queue empty no-op
        pcall(function() queue_on_teleport("do end") end)
        return true, "disabled (empty queue)"
    end
end

-- if was enabled last session, re-register on load
if State.autoexec then
    pcall(function() applyAutoExec(true) end)
end

----------------------------------------------------------------
-- CATALOGS
----------------------------------------------------------------
local BgCatalog, MusicCatalog = {}, {}
local function isImageName(name)
    local n = string.lower(name or "")
    return n:match("%.png$") or n:match("%.jpe?g$") or n:match("%.webp$")
end
local function isAudioName(name)
    local n = string.lower(name or "")
    return n:match("%.mp3$") or n:match("%.ogg$") or n:match("%.wav$") or n:match("%.flac$") or n:match("%.m4a$")
end

local function fetchList(api, filterFn)
    local list = {}
    local function absorb(jsonStr)
        local ok, data = pcall(HttpService.JSONDecode, HttpService, jsonStr)
        if not ok or type(data) ~= "table" then return end
        if data.type == "file" then data = { data } end
        for _, item in ipairs(data) do
            if type(item) == "table" and item.type == "file" and item.name and filterFn(item.name) then
                table.insert(list, {
                    name = item.name,
                    path = item.path or item.name,
                    url = item.download_url or (RAW_BASE .. (item.path or item.name)),
                })
            end
        end
    end
    local ok, body = pcall(function() return game:HttpGet(api) end)
    if ok and body and not tostring(body):find('"Not Found"') and not tostring(body):find("rate limit") then
        absorb(body)
    end
    table.sort(list, function(a, b) return a.name:lower() < b.name:lower() end)
    return list
end

local function fetchBackgroundList()
    local list = fetchList(FON_API, isImageName)
    if #list == 0 then list = fetchList(ROOT_API, isImageName) end
    BgCatalog = list
    for _, e in ipairs(list) do
        if not BgPresets[e.name] then BgPresets[e.name] = defaultPreset() end
    end
    return list
end

local function fetchMusicList()
    MusicCatalog = fetchList(MUSIC_API, isAudioName)
    return MusicCatalog
end

----------------------------------------------------------------
-- MUSIC ENGINE (rewritten)
----------------------------------------------------------------
local Music = {
    sound = nil,
    cache = {},      -- name -> asset id string
    loading = false,
    spinConn = nil,
    vinyl = nil,
    statusCb = nil,  -- function(text)
}

local function setMusicStatus(t)
    if Music.statusCb then Music.statusCb(t) end
end

local function stopSpin()
    if Music.spinConn then
        Music.spinConn:Disconnect()
        Music.spinConn = nil
    end
end

local function startSpin()
    stopSpin()
    if not Music.vinyl then return end
    local ang = Music.vinyl.Rotation or 0
    Music.spinConn = RunService.RenderStepped:Connect(function(dt)
        if not State.musicPlaying then return end
        ang = (ang + dt * 100) % 360
        Music.vinyl.Rotation = ang
    end)
end

local function resolveTrackUrl(name)
    for _, e in ipairs(MusicCatalog) do
        if e.name == name then return e.url end
    end
    return RAW_BASE .. "music/" .. name
end

local function loadTrackAsset(name)
    if Music.cache[name] then
        return Music.cache[name]
    end
    local url = resolveTrackUrl(name)
    local ok, result = pcall(function()
        local data = game:HttpGet(url)
        if type(data) ~= "string" or #data < 500 then
            error("file too small or empty")
        end
        local fname = "xys_music_" .. name:gsub("[^%w%.%-]", "_")
        if not writefile then error("writefile missing") end
        writefile(fname, data)
        local asset
        if getcustomasset then
            asset = getcustomasset(fname)
        elseif getsynasset then
            asset = getsynasset(fname)
        else
            error("getcustomasset missing")
        end
        if not asset or asset == "" then error("empty asset") end
        return asset
    end)
    if ok and result then
        Music.cache[name] = result
        return result
    end
    return nil, result
end

local function destroySound()
    if Music.sound then
        pcall(function()
            Music.sound:Stop()
            Music.sound:Destroy()
        end)
        Music.sound = nil
    end
end

local function stopMusic()
    State.musicPlaying = false
    stopSpin()
    if Music.sound then
        pcall(function() Music.sound:Stop() end)
    end
    setMusicStatus("Stopped")
end

local function playMusic(name)
    if Music.loading then
        setMusicStatus("Already loading...")
        return false
    end
    if not name or name == "none" then
        setMusicStatus("No track selected")
        return false
    end

    Music.loading = true
    setMusicStatus("Loading...")

    task.spawn(function()
        local asset, err = loadTrackAsset(name)
        if not asset then
            Music.loading = false
            setMusicStatus("Error: " .. tostring(err):sub(1, 40))
            return
        end

        destroySound()
        local s = Instance.new("Sound")
        s.Name = "XysNovaMusic"
        s.SoundId = asset
        s.Volume = math.clamp((State.musicVolume or 50) / 100, 0, 1)
        s.Looped = true
        s.Parent = SoundService
        Music.sound = s

        -- wait until loaded (max 15s)
        local t0 = os.clock()
        while not s.IsLoaded and os.clock() - t0 < 15 do
            task.wait(0.1)
        end

        if not s.IsLoaded then
            Music.loading = false
            setMusicStatus("Load timeout")
            destroySound()
            return
        end

        local playOk, playErr = pcall(function() s:Play() end)
        Music.loading = false
        if not playOk then
            setMusicStatus("Play failed")
            warn("[Xys Music]", playErr)
            return
        end

        State.musicPlaying = true
        State.musicName = name
        startSpin()
        setMusicStatus("Playing · " .. name)
    end)
    return true
end

local function setMusicVolume(v)
    State.musicVolume = v
    if Music.sound then
        Music.sound.Volume = math.clamp(v / 100, 0, 1)
    end
end

local function togglePlayStop()
    if State.musicPlaying then
        stopMusic()
        return false
    end
    return playMusic(State.musicName)
end

----------------------------------------------------------------
-- FLING / FREECAM (compact)
----------------------------------------------------------------
local Fling = { walkConn = nil, spamConn = nil }
local function getHRP(plr)
    local char = plr and plr.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end
local function applyFling(hrp, power, mode)
    if not hrp then return end
    power = power or State.flingPower
    mode = mode or State.flingMode
    local dir = Vector3.new((math.random()-0.5)*2, math.random()*0.5+0.5, (math.random()-0.5)*2).Unit
    pcall(function()
        if mode == "Velocity" or mode == "Both" then hrp.AssemblyLinearVelocity = dir * power * 10 end
        if mode == "Angular" or mode == "Both" then
            hrp.AssemblyAngularVelocity = Vector3.new(math.random(-1,1), math.random(-1,1), math.random(-1,1)).Unit * power * 20
        end
    end)
end
local function flingPlayer(plr, power)
    local hrp = getHRP(plr)
    if not hrp then return false end
    power = power or State.flingPower
    pcall(function()
        local bv = Instance.new("BodyVelocity")
        bv.MaxForce = Vector3.new(9e9, 9e9, 9e9)
        bv.Velocity = Vector3.new((math.random()-0.5)*power*20, math.random()*power*10+power*5, (math.random()-0.5)*power*20)
        bv.Parent = hrp
        local bav = Instance.new("BodyAngularVelocity")
        bav.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
        bav.AngularVelocity = Vector3.new(math.random(-power,power), math.random(-power,power), math.random(-power,power))
        bav.Parent = hrp
        task.delay(0.35, function() if bv then bv:Destroy() end if bav then bav:Destroy() end end)
    end)
    applyFling(hrp, power, State.flingMode)
    return true
end
local function flingAll()
    local n = 0
    for _, p in ipairs(Players:GetPlayers()) do if p ~= Player and flingPlayer(p) then n += 1 end end
    return n
end
local function flingNearest()
    local my = getHRP(Player)
    if not my then return nil end
    local best, bestD = nil, 1e9
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= Player then
            local h = getHRP(p)
            if h then
                local d = (h.Position - my.Position).Magnitude
                if d < bestD then best, bestD = p, d end
            end
        end
    end
    if best then flingPlayer(best) end
    return best
end
local function setWalkFling(on)
    State.walkFling = on
    if Fling.walkConn then Fling.walkConn:Disconnect() Fling.walkConn = nil end
    if not on then return end
    Fling.walkConn = RunService.Heartbeat:Connect(function()
        local my = getHRP(Player)
        if not my then return end
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= Player then
                local h = getHRP(p)
                if h and (h.Position - my.Position).Magnitude < 5 then applyFling(h) end
            end
        end
    end)
end
local function setSpamFling(on)
    State.spamFling = on
    if Fling.spamConn then Fling.spamConn:Disconnect() Fling.spamConn = nil end
    if not on then return end
    Fling.spamConn = RunService.Heartbeat:Connect(function()
        if State.flingTarget then applyFling(getHRP(State.flingTarget)) end
    end)
end

local Freecam = { conn = nil, root = nil, yaw = 0, pitch = 0 }
local function setFreecam(on)
    local char = Player.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if on then
        if State.freecam or not root then return State.freecam end
        State.freecam = true
        Freecam.root = root
        local look = Camera.CFrame.LookVector
        Freecam.yaw = math.atan2(-look.X, -look.Z)
        Freecam.pitch = math.asin(math.clamp(look.Y, -1, 1))
        root.Anchored = true
        Camera.CameraType = Enum.CameraType.Scriptable
        UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
        Freecam.conn = RunService.RenderStepped:Connect(function(dt)
            if not State.freecam then return end
            local d = UserInputService:GetMouseDelta()
            Freecam.yaw -= d.X * 0.003
            Freecam.pitch = math.clamp(Freecam.pitch - d.Y * 0.003, -1.45, 1.45)
            local rot = CFrame.Angles(0, Freecam.yaw, 0) * CFrame.Angles(Freecam.pitch, 0, 0)
            local move = Vector3.zero
            if UserInputService:IsKeyDown(Enum.KeyCode.W) then move += rot.LookVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.S) then move -= rot.LookVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.A) then move -= rot.RightVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.D) then move += rot.RightVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.Space) then move += Vector3.yAxis end
            if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then move -= Vector3.yAxis end
            local mul = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) and 2.25 or 1
            local pos = Camera.CFrame.Position
            if move.Magnitude > 0 then pos += move.Unit * State.cameraSpeed * mul * dt end
            Camera.CFrame = CFrame.new(pos) * rot
        end)
    else
        State.freecam = false
        if Freecam.conn then Freecam.conn:Disconnect() Freecam.conn = nil end
        if Freecam.root and Freecam.root.Parent then
            Freecam.root.Anchored = false
            Freecam.root.AssemblyLinearVelocity = Vector3.zero
        end
        Freecam.root = nil
        Camera.CameraType = Enum.CameraType.Custom
        if hum then Camera.CameraSubject = hum end
        UserInputService.MouseBehavior = Enum.MouseBehavior.Default
    end
    return true
end

local function setObserver(target)
    setFreecam(false)
    if target then
        local hum = target.Character and target.Character:FindFirstChildOfClass("Humanoid")
        if not hum then return false end
        State.observer = target
        Camera.CameraSubject = hum
    else
        State.observer = nil
        local hum = Player.Character and Player.Character:FindFirstChildOfClass("Humanoid")
        if hum then Camera.CameraSubject = hum end
    end
    return true
end

local MarkerPart
local function markPosition()
    local root = Player.Character and Player.Character:FindFirstChild("HumanoidRootPart")
    if not root then return nil end
    if MarkerPart then MarkerPart:Destroy() end
    MarkerPart = new("Part", {
        Name = "XysNovaMarker", Size = Vector3.new(0.4, 5, 0.4),
        CFrame = CFrame.new(root.Position + Vector3.new(0, 2.5, 0)),
        Anchored = true, CanCollide = false, Material = Enum.Material.Neon, Color = C.accent, Transparency = 0.1,
    }, Workspace)
    return root.Position
end

local ContrastFx
local function setContrast(on)
    State.contrast = on
    if on then
        ContrastFx = new("ColorCorrectionEffect", { Name = "XysNovaContrast", Contrast = 0.12, Saturation = 0.06 }, Lighting)
    elseif ContrastFx then ContrastFx:Destroy() ContrastFx = nil end
end

local BlurFx
local function applyBlur(enabled)
    if enabled and State.blurSize > 0 then
        if not BlurFx then BlurFx = new("BlurEffect", { Name = "XysNovaBlur", Size = 0 }, Lighting) end
        tween(BlurFx, 0.25, { Size = State.blurSize })
    elseif BlurFx then tween(BlurFx, 0.2, { Size = 0 }) end
end

----------------------------------------------------------------
-- HUD
----------------------------------------------------------------
local HudGui = new("ScreenGui", {
    Name = "XysNovaHUD", IgnoreGuiInset = true, ResetOnSpawn = false, DisplayOrder = 100,
}, PlayerGui)
local HudLabel = new("TextLabel", {
    Size = UDim2.fromOffset(220, 48),
    Position = UDim2.fromOffset(State.hudPosX, State.hudPosY),
    BackgroundTransparency = 1, Text = "", TextColor3 = Color3.new(1,1,1),
    Font = Enum.Font.GothamBold, TextSize = State.hudSize,
    TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
    TextStrokeTransparency = 0.4, TextStrokeColor3 = Color3.new(0,0,0),
    Visible = State.hudEnabled, ZIndex = 50,
}, HudGui)
local function applyHudLayout()
    HudLabel.Position = UDim2.fromOffset(State.hudPosX, State.hudPosY)
    HudLabel.TextSize = State.hudSize
    HudLabel.Visible = State.hudEnabled
end
local fpsCounter = 0
connect(RunService.RenderStepped, function() fpsCounter += 1 end)
task.spawn(function()
    while HudGui.Parent do
        task.wait(0.5)
        local fps = fpsCounter * 2
        fpsCounter = 0
        local ping = 0
        pcall(function()
            local item = Stats.Network.ServerStatsItem["Data Ping"]
            if item then ping = tonumber(item:GetValueString():match("%d+")) or 0 end
        end)
        local parts = {}
        if State.hudShowFps then table.insert(parts, "FPS " .. fps) end
        if State.hudShowPing then table.insert(parts, "Ping " .. ping .. "ms") end
        HudLabel.Text = table.concat(parts, "\n")
        applyHudLayout()
    end
end)

----------------------------------------------------------------
-- GUI SHELL
----------------------------------------------------------------
local Gui = new("ScreenGui", {
    Name = "XysNova", IgnoreGuiInset = true, ResetOnSpawn = false,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, PlayerGui)

local Main = new("Frame", {
    Size = UDim2.fromOffset(0, 0), Position = UDim2.fromScale(0.5, 0.5),
    AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = C.bg,
    BackgroundTransparency = 1, BorderSizePixel = 0, ClipsDescendants = true,
}, Gui)
corner(Main, CORNER)
stroke(Main, C.accent, 0.4, 1.5)

local BgImage = new("ImageLabel", {
    Size = UDim2.fromScale(1, 1), Position = UDim2.fromScale(0.5, 0.5),
    AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1,
    BorderSizePixel = 0, ScaleType = Enum.ScaleType.Stretch, ImageTransparency = 1, ZIndex = 1,
}, Main)
local BgDim = new("Frame", {
    Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(0,0,0),
    BackgroundTransparency = 1 - (State.menuDim / 100), BorderSizePixel = 0, ZIndex = 2,
}, Main)

local SliderSync = {}
local function applyBgTransform()
    BgImage.Size = UDim2.fromScale((State.bgStretchX or 100)/100, (State.bgStretchY or 100)/100)
    BgImage.Position = UDim2.new(0.5+(State.bgOffsetX or 0)/100, 0, 0.5+(State.bgOffsetY or 0)/100, 0)
end
local function applyMenuDim()
    BgDim.BackgroundTransparency = math.clamp(1 - (State.menuDim / 100), 0.05, 1)
end

local function loadBgAsset(url, cacheName)
    local ok, asset = pcall(function()
        local data = game:HttpGet(url)
        if not data or #data < 200 then return nil end
        local file = "xys_bg_" .. (cacheName or "tmp"):gsub("[^%w%.%-]", "_")
        if writefile then writefile(file, data) end
        if getcustomasset then return getcustomasset(file) end
        if getsynasset then return getsynasset(file) end
        return nil
    end)
    return ok and asset or nil
end

local function applyBackgroundByName(name)
    writeCurrentToPreset()
    savePresetsLocal()
    local savedDim = State.menuDim
    State.bgName = name or "none"
    if not name or name == "none" then
        BgImage.Image = ""
        tween(BgImage, 0.25, { ImageTransparency = 1 })
        State.menuDim = savedDim
        applyMenuDim()
        return
    end
    applyPresetToState(name)
    State.menuDim = savedDim
    applyBgTransform()
    applyMenuDim()
    for _, sync in pairs(SliderSync) do if type(sync) == "function" then sync() end end
    local entry
    for _, e in ipairs(BgCatalog) do if e.name == name then entry = e break end end
    local url = entry and entry.url or (RAW_BASE .. name)
    task.spawn(function()
        local asset = loadBgAsset(url, name)
        if asset then
            BgImage.Image = asset
            applyBgTransform()
            tween(BgImage, 0.35, { ImageTransparency = 0.12 })
        end
    end)
end
applyMenuDim()
applyBgTransform()

local TitleBar = new("Frame", {
    Size = UDim2.new(1, 0, 0, TITLE_H), BackgroundColor3 = C.panel,
    BackgroundTransparency = 0.2, BorderSizePixel = 0, ZIndex = 10,
}, Main)
local LogoDot = new("Frame", {
    Size = UDim2.fromOffset(10, 10), Position = UDim2.fromOffset(18, 19),
    BackgroundColor3 = C.accent, BorderSizePixel = 0, ZIndex = 11,
}, TitleBar)
corner(LogoDot, 5)
new("TextLabel", {
    Size = UDim2.fromOffset(130, TITLE_H), Position = UDim2.fromOffset(36, 0),
    BackgroundTransparency = 1, Text = "Xys  Nova", TextColor3 = C.text,
    Font = Enum.Font.GothamBold, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 11,
}, TitleBar)
new("TextLabel", {
    Size = UDim2.fromOffset(40, TITLE_H), Position = UDim2.fromOffset(140, 0),
    BackgroundTransparency = 1, Text = "v10", TextColor3 = C.accent,
    Font = Enum.Font.GothamMedium, TextSize = 11, ZIndex = 11,
}, TitleBar)

local CloseBtn = new("TextButton", {
    Size = UDim2.fromOffset(28, 28), Position = UDim2.new(1, -40, 0.5, -14),
    BackgroundColor3 = C.card2, Text = "×", TextColor3 = C.muted,
    Font = Enum.Font.GothamBold, TextSize = 16, AutoButtonColor = false, ZIndex = 11,
}, TitleBar)
corner(CloseBtn, 8)

local Sidebar = new("Frame", {
    Size = UDim2.new(0, SIDE_W, 1, -(TITLE_H + FOOTER_H)),
    Position = UDim2.fromOffset(0, TITLE_H),
    BackgroundColor3 = C.panel, BackgroundTransparency = 0.25, BorderSizePixel = 0, ZIndex = 10,
}, Main)
local NavList = new("Frame", {
    Size = UDim2.new(1, 0, 1, -16), Position = UDim2.fromOffset(0, 10),
    BackgroundTransparency = 1, ZIndex = 11,
}, Sidebar)
new("UIListLayout", {
    Padding = UDim.new(0, 6), HorizontalAlignment = Enum.HorizontalAlignment.Center,
    SortOrder = Enum.SortOrder.LayoutOrder,
}, NavList)

local Content = new("Frame", {
    Size = UDim2.new(1, -SIDE_W, 1, -(TITLE_H + FOOTER_H)),
    Position = UDim2.fromOffset(SIDE_W, TITLE_H),
    BackgroundTransparency = 1, ClipsDescendants = true, ZIndex = 10,
}, Main)

local Pages, NavBtns, CardRefs = {}, {}, {}
local function makePage(name)
    local p = new("ScrollingFrame", {
        Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0,
        ScrollBarThickness = 3, ScrollBarImageColor3 = C.accent,
        AutomaticCanvasSize = Enum.AutomaticSize.Y, Visible = false, ZIndex = 10,
    }, Content)
    new("UIPadding", {
        PaddingTop = UDim.new(0, 14), PaddingBottom = UDim.new(0, 16),
        PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14),
    }, p)
    new("UIListLayout", { Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder }, p)
    Pages[name] = p
    return p
end
local function selectPage(name)
    for n, p in pairs(Pages) do p.Visible = n == name end
    State.page = name
    for n, b in pairs(NavBtns) do
        local on = n == name
        tween(b.bg, 0.15, { BackgroundColor3 = on and C.card2 or C.panel })
        tween(b.icon, 0.15, { TextColor3 = on and C.accent or C.muted })
        b.ind.Visible = on
    end
end
local function makeNav(name, icon, order)
    local b = new("TextButton", {
        Size = UDim2.fromOffset(42, 42), BackgroundColor3 = C.panel,
        BackgroundTransparency = 0.3, Text = "", AutoButtonColor = false,
        LayoutOrder = order, ZIndex = 11,
    }, NavList)
    corner(b, 11)
    local ind = new("Frame", {
        Size = UDim2.fromOffset(3, 18), Position = UDim2.fromOffset(0, 12),
        BackgroundColor3 = C.accent, BorderSizePixel = 0, Visible = false, ZIndex = 12,
    }, b)
    corner(ind, 2)
    local ic = new("TextLabel", {
        Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = icon,
        TextColor3 = C.muted, Font = Enum.Font.GothamBold, TextSize = 16, ZIndex = 12,
    }, b)
    NavBtns[name] = { bg = b, icon = ic, ind = ind }
    b.MouseButton1Click:Connect(function() selectPage(name) end)
end

local Footer = new("Frame", {
    Size = UDim2.new(1, 0, 0, FOOTER_H), Position = UDim2.new(0, 0, 1, -FOOTER_H),
    BackgroundColor3 = C.panel, BackgroundTransparency = 0.2, BorderSizePixel = 0, ZIndex = 10,
}, Main)
local FooterTxt = new("TextLabel", {
    Size = UDim2.new(1, -20, 1, 0), Position = UDim2.fromOffset(14, 0),
    BackgroundTransparency = 1, Text = "FPS --", TextColor3 = C.muted,
    Font = Enum.Font.Gotham, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 11,
}, Footer)

local ToastHolder = new("Frame", {
    Size = UDim2.new(0, 260, 1, 0), Position = UDim2.new(1, -280, 0, 16), BackgroundTransparency = 1,
}, Gui)
new("UIListLayout", { Padding = UDim.new(0, 8) }, ToastHolder)
local function toast(title, msg)
    local t = new("Frame", {
        Size = UDim2.new(1, 0, 0, 0), BackgroundColor3 = C.card, BorderSizePixel = 0, ClipsDescendants = true,
    }, ToastHolder)
    corner(t, 10)
    stroke(t, C.accent, 0.35, 1)
    new("TextLabel", {
        Size = UDim2.new(1, -16, 0, 18), Position = UDim2.fromOffset(12, 8),
        BackgroundTransparency = 1, Text = title, TextColor3 = C.accent,
        Font = Enum.Font.GothamBold, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left,
    }, t)
    new("TextLabel", {
        Size = UDim2.new(1, -16, 0, 18), Position = UDim2.fromOffset(12, 28),
        BackgroundTransparency = 1, Text = msg, TextColor3 = C.muted,
        Font = Enum.Font.Gotham, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left,
    }, t)
    tween(t, 0.3, { Size = UDim2.new(1, 0, 0, 54) }, Enum.EasingStyle.Back)
    task.delay(2.2, function()
        tween(t, 0.2, { Size = UDim2.new(1, 0, 0, 0) })
        task.delay(0.25, t.Destroy, t)
    end)
end

local function card(parent, h)
    local f = new("Frame", {
        Size = UDim2.new(1, 0, 0, h or 64),
        BackgroundColor3 = C.card, BackgroundTransparency = State.cardOpacity / 100,
        BorderSizePixel = 0, ZIndex = 11,
    }, parent)
    corner(f, 10)
    stroke(f, C.border, 0.4, 1)
    table.insert(CardRefs, f)
    return f
end
local function label(parent, props, color)
    local l = new("TextLabel", props, parent)
    l.TextColor3 = color or C.text
    l.ZIndex = 12
    return l
end
local function btn(parent, text, fn, primary, color)
    local b = new("TextButton", {
        Size = UDim2.fromOffset(100, 32),
        BackgroundColor3 = color or (primary and C.accent or C.card2),
        Text = text, TextColor3 = Color3.new(1,1,1),
        Font = Enum.Font.GothamBold, TextSize = 11, AutoButtonColor = false, ZIndex = 12,
    }, parent)
    corner(b, 8)
    b.MouseButton1Click:Connect(fn)
    return b
end
local function toggle(parent, title, desc, get, set)
    local row = card(parent, 68)
    label(row, {
        Size = UDim2.new(1, -70, 0, 20), Position = UDim2.fromOffset(14, 14),
        BackgroundTransparency = 1, Text = title, Font = Enum.Font.GothamBold, TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, C.text)
    label(row, {
        Size = UDim2.new(1, -70, 0, 16), Position = UDim2.fromOffset(14, 38),
        BackgroundTransparency = 1, Text = desc, Font = Enum.Font.Gotham, TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, C.muted)
    local track = new("Frame", {
        Size = UDim2.fromOffset(42, 24), Position = UDim2.new(1, -56, 0.5, -12),
        BackgroundColor3 = C.card2, BorderSizePixel = 0, ZIndex = 12,
    }, row)
    corner(track, 12)
    local knob = new("Frame", {
        Size = UDim2.fromOffset(18, 18), Position = UDim2.fromOffset(3, 3),
        BackgroundColor3 = Color3.new(1,1,1), BorderSizePixel = 0, ZIndex = 13,
    }, track)
    corner(knob, 9)
    local on = get()
    local function paint()
        tween(knob, 0.15, { Position = on and UDim2.new(1, -21, 0.5, -9) or UDim2.fromOffset(3, 3) })
        tween(track, 0.15, { BackgroundColor3 = on and C.accent or C.card2 })
    end
    paint()
    new("TextButton", { Size = UDim2.fromScale(1,1), BackgroundTransparency = 1, Text = "", ZIndex = 14 }, track)
        .MouseButton1Click:Connect(function() on = not on set(on) paint() end)
    return function(v) on = v paint() end -- external sync
end

local function slider(parent, title, minV, maxV, get, set, suffix, syncKey, savePreset)
    local row = card(parent, 78)
    label(row, {
        Size = UDim2.new(1, -70, 0, 18), Position = UDim2.fromOffset(14, 12),
        BackgroundTransparency = 1, Text = title, Font = Enum.Font.GothamBold, TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, C.text)
    local valL = label(row, {
        Size = UDim2.fromOffset(56, 18), Position = UDim2.new(1, -66, 0, 12),
        BackgroundTransparency = 1, Text = tostring(get()) .. (suffix or ""),
        Font = Enum.Font.GothamBold, TextSize = 12,
    }, C.accent)
    local bar = new("Frame", {
        Size = UDim2.new(1, -28, 0, 8), Position = UDim2.fromOffset(14, 48),
        BackgroundColor3 = C.card2, BorderSizePixel = 0, ZIndex = 12,
    }, row)
    corner(bar, 4)
    local fill = new("Frame", {
        Size = UDim2.new(math.clamp((get()-minV)/math.max(maxV-minV,1), 0, 1), 0, 1, 0),
        BackgroundColor3 = C.accent, BorderSizePixel = 0, ZIndex = 13,
    }, bar)
    corner(fill, 4)
    local hit = new("TextButton", {
        Size = UDim2.new(1, 0, 1, 20), Position = UDim2.fromOffset(0, -6),
        BackgroundTransparency = 1, Text = "", ZIndex = 14,
    }, bar)
    local drag = false
    local function upd(x)
        local r = math.clamp(x / math.max(bar.AbsoluteSize.X, 1), 0, 1)
        local v = math.floor(minV + r * (maxV - minV) + 0.5)
        set(v)
        fill.Size = UDim2.new(r, 0, 1, 0)
        valL.Text = tostring(v) .. (suffix or "")
        if savePreset then writeCurrentToPreset() savePresetsLocal() end
    end
    local function syncFromState()
        local v = get()
        local r = math.clamp((v - minV) / math.max(maxV - minV, 1), 0, 1)
        fill.Size = UDim2.new(r, 0, 1, 0)
        valL.Text = tostring(v) .. (suffix or "")
    end
    if syncKey then SliderSync[syncKey] = syncFromState end
    hit.MouseButton1Down:Connect(function() drag = true end)
    connect(UserInputService.InputEnded, function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 then drag = false end
    end)
    connect(UserInputService.InputChanged, function(i)
        if drag and i.UserInputType == Enum.UserInputType.MouseMovement then
            upd(i.Position.X - bar.AbsolutePosition.X)
        end
    end)
end

local function applyCardOpacity()
    for _, f in ipairs(CardRefs) do
        if f and f.Parent then f.BackgroundTransparency = State.cardOpacity / 100 end
    end
end
local function applyWindowOpacity()
    if State.open then Main.BackgroundTransparency = State.windowOpacity / 100 end
end

local function makeDropdown(parent, title, getLabel, onSelect, getOptions)
    local wrap = card(parent, 56)
    label(wrap, {
        Size = UDim2.new(0.35, 0, 1, 0), Position = UDim2.fromOffset(14, 0),
        BackgroundTransparency = 1, Text = title, Font = Enum.Font.GothamBold, TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, C.text)
    local trigger = new("TextButton", {
        Size = UDim2.new(0.58, -16, 0, 32), Position = UDim2.new(0.38, 0, 0.5, -16),
        BackgroundColor3 = C.card2, Text = "", AutoButtonColor = false, ZIndex = 12,
    }, wrap)
    corner(trigger, 8)
    stroke(trigger, C.border, 0.4, 1)
    local trigLabel = new("TextLabel", {
        Size = UDim2.new(1, -28, 1, 0), Position = UDim2.fromOffset(10, 0),
        BackgroundTransparency = 1, Text = getLabel(), TextColor3 = C.text,
        Font = Enum.Font.GothamMedium, TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 13,
    }, trigger)
    new("TextLabel", {
        Size = UDim2.fromOffset(20, 32), Position = UDim2.new(1, -22, 0, 0),
        BackgroundTransparency = 1, Text = "▾", TextColor3 = C.muted,
        Font = Enum.Font.GothamBold, TextSize = 12, ZIndex = 13,
    }, trigger)
    local open, drop = false, nil
    local function closeDrop()
        open = false
        if drop then drop:Destroy() drop = nil end
    end
    trigger.MouseButton1Click:Connect(function()
        if open then closeDrop() return end
        open = true
        local opts = getOptions()
        local h = math.min(8 + math.max(#opts, 1) * 34, 220)
        drop = new("Frame", {
            Size = UDim2.fromOffset(math.max(trigger.AbsoluteSize.X, 160), h),
            Position = UDim2.fromOffset(
                trigger.AbsolutePosition.X - Main.AbsolutePosition.X,
                trigger.AbsolutePosition.Y - Main.AbsolutePosition.Y + 36
            ),
            BackgroundColor3 = C.panel, BorderSizePixel = 0, ZIndex = 100,
        }, Main)
        corner(drop, 10)
        stroke(drop, C.accent, 0.35, 1)
        local scroll = new("ScrollingFrame", {
            Size = UDim2.new(1, -6, 1, -6), Position = UDim2.fromOffset(3, 3),
            BackgroundTransparency = 1, BorderSizePixel = 0,
            ScrollBarThickness = 3, ScrollBarImageColor3 = C.accent,
            CanvasSize = UDim2.new(0, 0, 0, math.max(#opts, 1) * 34), ZIndex = 101,
        }, drop)
        new("UIListLayout", { Padding = UDim.new(0, 2) }, scroll)
        if #opts == 0 then
            new("TextLabel", {
                Size = UDim2.new(1, -4, 0, 32), BackgroundTransparency = 1,
                Text = "  (empty)", TextColor3 = C.muted, Font = Enum.Font.Gotham, TextSize = 11,
                TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 102,
            }, scroll)
        end
        for _, opt in ipairs(opts) do
            local item = new("TextButton", {
                Size = UDim2.new(1, -4, 0, 32), BackgroundColor3 = C.panel,
                Text = "  " .. opt.label, TextColor3 = C.text,
                Font = Enum.Font.GothamMedium, TextSize = 11,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextTruncate = Enum.TextTruncate.AtEnd, AutoButtonColor = false, ZIndex = 102,
            }, scroll)
            corner(item, 6)
            item.MouseButton1Click:Connect(function()
                onSelect(opt)
                trigLabel.Text = getLabel()
                closeDrop()
            end)
        end
    end)
    return { refresh = function() trigLabel.Text = getLabel() end }
end

----------------------------------------------------------------
-- PAGES
----------------------------------------------------------------
makeNav("Home", "◆", 1)
makeNav("Camera", "◎", 2)
makeNav("Visual", "◌", 3)
makeNav("Fling", "⚡", 4)
makeNav("Music", "♪", 5)
makeNav("Watch", "◉", 6)
makeNav("HUD", "▤", 7)
makeNav("Keys", "⌘", 8)
makeNav("Settings", "⚙", 9)

local Home = makePage("Home")
do
    local hero = card(Home, 88)
    label(hero, {
        Size = UDim2.new(1, -28, 0, 24), Position = UDim2.fromOffset(16, 16),
        BackgroundTransparency = 1, Text = "Welcome back", Font = Enum.Font.GothamBlack, TextSize = 18,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, C.text)
    local quick = card(Home, 72)
    local q1 = btn(quick, "Freecam", function()
        setFreecam(not State.freecam)
        toast("Freecam", State.freecam and "ON" or "OFF")
    end, true)
    q1.Position = UDim2.fromOffset(16, 20)
    local q2 = btn(quick, "Fling All", function() toast("Fling", tostring(flingAll())) end, false, C.orange)
    q2.Position = UDim2.fromOffset(128, 20)
end

local CameraPage = makePage("Camera")
toggle(CameraPage, "Free Camera", "WASD + mouse", function() return State.freecam end, function(v) setFreecam(v) end)
slider(CameraPage, "Camera Speed", 15, 120, function() return State.cameraSpeed end, function(v) State.cameraSpeed = v end, "")
slider(CameraPage, "FOV", 50, 120, function() return State.fov end, function(v) State.fov = v Camera.FieldOfView = v end, "°")

local VisualPage = makePage("Visual")
local CrosshairFrame
toggle(VisualPage, "Crosshair", "Center", function() return State.crosshair end, function(v)
    State.crosshair = v if CrosshairFrame then CrosshairFrame.Visible = v end
end)
toggle(VisualPage, "Contrast", "Boost", function() return State.contrast end, function(v) setContrast(v) end)
CrosshairFrame = new("Frame", {
    Size = UDim2.fromOffset(18, 18), Position = UDim2.fromScale(0.5, 0.5),
    AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, Visible = false,
}, Gui)
new("Frame", { Size = UDim2.new(1,0,0,2), Position = UDim2.new(0,0,0.5,-1), BackgroundColor3 = C.accent, BorderSizePixel = 0 }, CrosshairFrame)
new("Frame", { Size = UDim2.new(0,2,1,0), Position = UDim2.new(0.5,-1,0,0), BackgroundColor3 = C.accent, BorderSizePixel = 0 }, CrosshairFrame)

local FlingPage = makePage("Fling")
slider(FlingPage, "Fling Power", 50, 2000, function() return State.flingPower end, function(v) State.flingPower = v end, "")
toggle(FlingPage, "Walk Fling", "Touch", function() return State.walkFling end, function(v) setWalkFling(v) end)
toggle(FlingPage, "Spam Target", "Loop", function() return State.spamFling end, function(v) setSpamFling(v) end)
do
    local a = card(FlingPage, 70)
    local b1 = btn(a, "Fling All", function() toast("Fling", tostring(flingAll())) end, false, C.orange)
    b1.Position = UDim2.fromOffset(14, 19)
    local b2 = btn(a, "Nearest", function()
        local t = flingNearest()
        toast("Fling", t and t.DisplayName or "None")
    end, true)
    b2.Position = UDim2.fromOffset(126, 19)
end

----------------------------------------------------------------
-- MUSIC PAGE (rewritten UX)
----------------------------------------------------------------
local MusicPage = makePage("Music")
local PlayBtnRef, TrackLabel, StatusLabel
do
    local playerCard = card(MusicPage, 170)
    local vinyl = new("Frame", {
        Size = UDim2.fromOffset(100, 100), Position = UDim2.fromOffset(20, 35),
        BackgroundColor3 = Color3.fromRGB(18, 18, 26), BorderSizePixel = 0, ZIndex = 12,
    }, playerCard)
    corner(vinyl, 50)
    stroke(vinyl, C.accent, 0.25, 2)
    local disc = new("Frame", {
        Size = UDim2.fromOffset(36, 36), Position = UDim2.fromOffset(32, 32),
        BackgroundColor3 = C.accent, BorderSizePixel = 0, ZIndex = 13,
    }, vinyl)
    corner(disc, 18)
    local hole = new("Frame", {
        Size = UDim2.fromOffset(10, 10), Position = UDim2.fromOffset(13, 13),
        BackgroundColor3 = C.bg, BorderSizePixel = 0, ZIndex = 14,
    }, disc)
    corner(hole, 5)
    Music.vinyl = vinyl

    TrackLabel = label(playerCard, {
        Size = UDim2.new(1, -140, 0, 20), Position = UDim2.fromOffset(140, 40),
        BackgroundTransparency = 1,
        Text = State.musicName == "none" and "No track" or State.musicName,
        Font = Enum.Font.GothamBold, TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
    }, C.text)

    StatusLabel = label(playerCard, {
        Size = UDim2.new(1, -140, 0, 16), Position = UDim2.fromOffset(140, 62),
        BackgroundTransparency = 1, Text = "Stopped",
        Font = Enum.Font.Gotham, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left,
    }, C.muted)
    Music.statusCb = function(t)
        if StatusLabel then StatusLabel.Text = t end
    end

    PlayBtnRef = btn(playerCard, "▶ Play", function()
        if Music.loading then
            toast("Music", "Wait — loading")
            return
        end
        if State.musicPlaying then
            stopMusic()
            PlayBtnRef.Text = "▶ Play"
            toast("Music", "Stopped")
        else
            if State.musicName == "none" then
                toast("Music", "Pick a track first")
                return
            end
            PlayBtnRef.Text = "… Load"
            playMusic(State.musicName)
            task.spawn(function()
                while Music.loading do task.wait(0.1) end
                PlayBtnRef.Text = State.musicPlaying and "■ Stop" or "▶ Play"
            end)
        end
    end, true)
    PlayBtnRef.Position = UDim2.fromOffset(140, 100)
    PlayBtnRef.Size = UDim2.fromOffset(120, 36)

    slider(MusicPage, "Volume", 0, 100, function() return State.musicVolume end, function(v)
        setMusicVolume(v)
    end, "%")

    local MusicDropdown = makeDropdown(
        MusicPage, "Track",
        function() return State.musicName == "none" and "None" or State.musicName end,
        function(opt)
            local wasPlaying = State.musicPlaying
            stopMusic()
            State.musicName = opt.id
            TrackLabel.Text = opt.id == "none" and "No track" or opt.label
            PlayBtnRef.Text = "▶ Play"
            if wasPlaying and opt.id ~= "none" then
                PlayBtnRef.Text = "… Load"
                playMusic(opt.id)
                task.spawn(function()
                    while Music.loading do task.wait(0.1) end
                    PlayBtnRef.Text = State.musicPlaying and "■ Stop" or "▶ Play"
                end)
            end
            toast("Music", opt.label)
        end,
        function()
            local opts = { { id = "none", label = "None" } }
            for _, e in ipairs(MusicCatalog) do
                table.insert(opts, { id = e.name, label = e.name })
            end
            return opts
        end
    )

    local refreshRow = card(MusicPage, 48)
    label(refreshRow, {
        Size = UDim2.new(1, -100, 1, 0), Position = UDim2.fromOffset(14, 0),
        BackgroundTransparency = 1, Text = "Reload tracks from /music",
        Font = Enum.Font.Gotham, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left,
    }, C.muted)
    local rb = btn(refreshRow, "Refresh", function()
        task.spawn(function()
            setMusicStatus("Refreshing list...")
            fetchMusicList()
            if MusicDropdown then MusicDropdown.refresh() end
            setMusicStatus(#MusicCatalog == 0 and "No tracks in /music" or (#MusicCatalog .. " tracks"))
            toast("Music", #MusicCatalog .. " tracks")
        end)
    end, true)
    rb.Size = UDim2.fromOffset(80, 28)
    rb.Position = UDim2.new(1, -94, 0.5, -14)

    local tip = card(MusicPage, 56)
    label(tip, {
        Size = UDim2.new(1, -28, 1, 0), Position = UDim2.fromOffset(14, 0),
        BackgroundTransparency = 1,
        Text = "Put .mp3/.ogg in github.com/.../music  ·  cache after first play",
        Font = Enum.Font.Gotham, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true,
    }, C.muted)
end

----------------------------------------------------------------
-- HUD PAGE
----------------------------------------------------------------
local HudPage = makePage("HUD")
do
    toggle(HudPage, "Show HUD", "On screen when menu closed", function() return State.hudEnabled end, function(v)
        State.hudEnabled = v applyHudLayout()
    end)
    toggle(HudPage, "Show FPS", "", function() return State.hudShowFps end, function(v) State.hudShowFps = v end)
    toggle(HudPage, "Show Ping", "", function() return State.hudShowPing end, function(v) State.hudShowPing = v end)
    slider(HudPage, "Position X", 0, 800, function() return State.hudPosX end, function(v)
        State.hudPosX = v applyHudLayout()
    end, "px")
    slider(HudPage, "Position Y", 0, 600, function() return State.hudPosY end, function(v)
        State.hudPosY = v applyHudLayout()
    end, "px")
    slider(HudPage, "Text Size", 10, 32, function() return State.hudSize end, function(v)
        State.hudSize = v applyHudLayout()
    end, "px")
end

local WatchPage = makePage("Watch")
do
    local list = new("Frame", { Size = UDim2.new(1,0,0,0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1 }, WatchPage)
    new("UIListLayout", { Padding = UDim.new(0, 8) }, list)
    local function rebuild()
        for _, c in ipairs(list:GetChildren()) do if c:IsA("Frame") then c:Destroy() end end
        local any = false
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= Player then
                any = true
                local row = card(list, 56)
                label(row, {
                    Size = UDim2.new(1, -120, 1, 0), Position = UDim2.fromOffset(14, 0),
                    BackgroundTransparency = 1, Text = plr.DisplayName, Font = Enum.Font.GothamBold, TextSize = 13,
                    TextXAlignment = Enum.TextXAlignment.Left,
                }, C.text)
                local b = btn(row, "Watch", function() setObserver(plr) end, true)
                b.Position = UDim2.new(1, -114, 0.5, -16)
            end
        end
        if not any then
            local empty = card(list, 56)
            label(empty, {
                Size = UDim2.new(1, -28, 1, 0), Position = UDim2.fromOffset(14, 0),
                BackgroundTransparency = 1, Text = "No other players", Font = Enum.Font.Gotham, TextSize = 12,
                TextXAlignment = Enum.TextXAlignment.Left,
            }, C.muted)
        end
    end
    rebuild()
    connect(Players.PlayerAdded, rebuild)
    connect(Players.PlayerRemoving, rebuild)
end

local KeysPage = makePage("Keys")
local KeyLabels, Rebinding, AwaitTxt = {}, nil, nil
do
    local info = card(KeysPage, 48)
    AwaitTxt = label(info, {
        Size = UDim2.new(1, -28, 1, 0), Position = UDim2.fromOffset(14, 0),
        BackgroundTransparency = 1, Text = "Change → press key", Font = Enum.Font.Gotham, TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, C.muted)
    for id, title in pairs({
        Menu = "Menu", Freecam = "Freecam", Marker = "Marker",
        Crosshair = "Crosshair", Hud = "HUD Toggle",
    }) do
        local row = card(KeysPage, 56)
        label(row, {
            Size = UDim2.new(1, -160, 1, 0), Position = UDim2.fromOffset(14, 0),
            BackgroundTransparency = 1, Text = title, Font = Enum.Font.GothamBold, TextSize = 13,
            TextXAlignment = Enum.TextXAlignment.Left,
        }, C.text)
        local key = new("TextLabel", {
            Size = UDim2.fromOffset(70, 26), Position = UDim2.new(1, -156, 0.5, -13),
            BackgroundColor3 = C.card2, Text = State.binds[id] or "?", TextColor3 = C.accent,
            Font = Enum.Font.GothamBold, TextSize = 10, ZIndex = 12,
        }, row)
        corner(key, 7)
        KeyLabels[id] = key
        local ch = btn(row, "Change", function()
            Rebinding = id
            AwaitTxt.Text = "Press key for " .. title
            AwaitTxt.TextColor3 = C.accent
        end, false)
        ch.Size = UDim2.fromOffset(70, 26)
        ch.Position = UDim2.new(1, -78, 0.5, -13)
    end
end

----------------------------------------------------------------
-- SETTINGS + AUTOEXEC
----------------------------------------------------------------
local SettingsPage = makePage("Settings")
local BgDropdown
do
    -- AutoExec first
    toggle(SettingsPage, "AutoExec", "Inject after rejoin / teleport", function() return State.autoexec end, function(v)
        local ok, msg = applyAutoExec(v)
        saveConfigLocal()
        if ok then
            toast("AutoExec", v and "ON — next join" or "OFF")
        else
            State.autoexec = false
            toast("AutoExec", tostring(msg))
        end
    end)
    local aeTip = card(SettingsPage, 64)
    label(aeTip, {
        Size = UDim2.new(1, -28, 1, 0), Position = UDim2.fromOffset(14, 0),
        BackgroundTransparency = 1,
        Text = "Needs queue_on_teleport. Upload script as xys-nova.lua on GitHub (SCRIPT_URL).",
        Font = Enum.Font.Gotham, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true,
    }, C.muted)

    slider(SettingsPage, "Window Transparency", 0, 40, function() return State.windowOpacity end, function(v)
        State.windowOpacity = v applyWindowOpacity()
    end, "%")
    slider(SettingsPage, "Card Transparency", 0, 50, function() return State.cardOpacity end, function(v)
        State.cardOpacity = v applyCardOpacity()
    end, "%")
    slider(SettingsPage, "Menu Dim", 0, 90, function() return State.menuDim end, function(v)
        State.menuDim = v applyMenuDim()
    end, "%", "dim")
    slider(SettingsPage, "World Blur", 0, 24, function() return State.blurSize end, function(v)
        State.blurSize = v if State.open then applyBlur(true) end
    end, "")

    BgDropdown = makeDropdown(
        SettingsPage, "Background",
        function() return State.bgName == "none" and "None" or State.bgName end,
        function(opt)
            applyBackgroundByName(opt.id)
            toast("Background", opt.label)
        end,
        function()
            local opts = { { id = "none", label = "None" } }
            for _, e in ipairs(BgCatalog) do table.insert(opts, { id = e.name, label = e.name }) end
            return opts
        end
    )

    local refreshRow = card(SettingsPage, 48)
    label(refreshRow, {
        Size = UDim2.new(1, -100, 1, 0), Position = UDim2.fromOffset(14, 0),
        BackgroundTransparency = 1, Text = "Reload /fon images",
        Font = Enum.Font.Gotham, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left,
    }, C.muted)
    local rb = btn(refreshRow, "Refresh", function()
        task.spawn(function()
            fetchBackgroundList()
            if BgDropdown then BgDropdown.refresh() end
            toast("BG", #BgCatalog .. " files")
        end)
    end, true)
    rb.Size = UDim2.fromOffset(80, 28)
    rb.Position = UDim2.new(1, -94, 0.5, -14)

    label(card(SettingsPage, 36), {
        Size = UDim2.new(1, -28, 1, 0), Position = UDim2.fromOffset(14, 0),
        BackgroundTransparency = 1, Text = "Per-image transform",
        Font = Enum.Font.GothamBold, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left,
    }, C.accent)
    slider(SettingsPage, "Stretch X", 20, 300, function() return State.bgStretchX end, function(v)
        State.bgStretchX = v applyBgTransform()
    end, "%", "sx", true)
    slider(SettingsPage, "Stretch Y", 20, 300, function() return State.bgStretchY end, function(v)
        State.bgStretchY = v applyBgTransform()
    end, "%", "sy", true)
    slider(SettingsPage, "Offset X", -80, 80, function() return State.bgOffsetX end, function(v)
        State.bgOffsetX = v applyBgTransform()
    end, "%", "ox", true)
    slider(SettingsPage, "Offset Y", -80, 80, function() return State.bgOffsetY end, function(v)
        State.bgOffsetY = v applyBgTransform()
    end, "%", "oy", true)

    local saveCard = card(SettingsPage, 72)
    local saveBtn = btn(saveCard, "Save All", function()
        writeCurrentToPreset()
        toast("Save", (savePresetsLocal() or saveConfigLocal()) and "OK" or "No writefile")
    end, true)
    saveBtn.Position = UDim2.fromOffset(14, 20)
    saveBtn.Size = UDim2.fromOffset(90, 28)
end

task.spawn(function()
    fetchBackgroundList()
    fetchMusicList()
    if BgDropdown then BgDropdown.refresh() end
    applyBackgroundByName(State.bgName)
end)

selectPage("Home")

----------------------------------------------------------------
-- OPEN / INPUT
----------------------------------------------------------------
local function setMenu(vis)
    State.open = vis
    if vis then
        Main.Visible = true
        Main.Size = UDim2.fromOffset(WIN_W - 80, WIN_H - 60)
        Main.BackgroundTransparency = 1
        tween(Main, 0.35, {
            Size = UDim2.fromOffset(WIN_W, WIN_H),
            BackgroundTransparency = State.windowOpacity / 100,
        }, Enum.EasingStyle.Back)
        applyBlur(true)
    else
        writeCurrentToPreset()
        savePresetsLocal()
        saveConfigLocal()
        tween(Main, 0.2, {
            Size = UDim2.fromOffset(WIN_W - 80, WIN_H - 60),
            BackgroundTransparency = 1,
        })
        applyBlur(false)
        task.delay(0.22, function() if not State.open then Main.Visible = false end end)
    end
end
CloseBtn.MouseButton1Click:Connect(function() setMenu(false) end)

local dragging, dragStart, startPos
TitleBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        if input.Position.X >= CloseBtn.AbsolutePosition.X - 4 then return end
        dragging, dragStart, startPos = true, input.Position, Main.Position
    end
end)
TitleBar.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
end)
connect(UserInputService.InputChanged, function(input)
    if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
        local d = input.Position - dragStart
        Main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
    end
end)

local function matchBind(input, name)
    local code = Enum.KeyCode[State.binds[name]]
    return code and input.KeyCode == code
end

connect(UserInputService.InputBegan, function(input, gp)
    if gp or UserInputService:GetFocusedTextBox() then return end
    if Rebinding then
        if input.KeyCode ~= Enum.KeyCode.Unknown then
            State.binds[Rebinding] = input.KeyCode.Name
            if KeyLabels[Rebinding] then KeyLabels[Rebinding].Text = input.KeyCode.Name end
            AwaitTxt.Text = "Change → press key"
            AwaitTxt.TextColor3 = C.muted
            Rebinding = nil
            saveConfigLocal()
        end
        return
    end
    if matchBind(input, "Menu") then setMenu(not State.open)
    elseif matchBind(input, "Freecam") then setFreecam(not State.freecam)
    elseif matchBind(input, "Marker") then markPosition()
    elseif matchBind(input, "Crosshair") then
        State.crosshair = not State.crosshair
        CrosshairFrame.Visible = State.crosshair
    elseif matchBind(input, "Hud") then
        State.hudEnabled = not State.hudEnabled
        applyHudLayout()
        toast("HUD", State.hudEnabled and "ON" or "OFF")
    end
end)

local frames = 0
connect(RunService.RenderStepped, function() frames += 1 end)
task.spawn(function()
    while Gui.Parent do
        task.wait(1)
        local fps = frames
        frames = 0
        FooterTxt.Text = string.format("FPS %d  ·  %d players", fps, #Players:GetPlayers())
    end
end)

task.delay(0.05, function() setMenu(true) end)
toast("Xys Nova", "v10 · Music rewrite + AutoExec")
print("Xys Nova v10.0")
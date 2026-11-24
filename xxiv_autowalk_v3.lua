-- ============================================================
--  XXIV Auto Walk  v3.0  |  LocalScript / Executor  |  Luau
--  • Auto Walk smooth + stair assist
--  • RECORD pergerakan real-time (CFrame tiap frame)
--  • REWIND: putar balik 5 detik terakhir sebelum jatuh
--  • PLAYBACK rekaman dengan speed multiplier (0.25x – 4x)
--  • 5 SLOT save per-sesi (nama custom, durasi, timestamp)
--  • Panel "XXIV AUTO WALK" elegan, draggable, dark-glass
--  • Export slot ke string (copy-paste simpan manual / GitHub)
-- ============================================================

-- ─── SERVICES ────────────────────────────────────────────────
local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")

local lp  = Players.LocalPlayer
local cam = workspace.CurrentCamera

-- ─── CONFIG ──────────────────────────────────────────────────
local CFG = {
    walkSpeed     = 20,
    smoothing     = 0.15,
    direction     = "camera",
    stairBoost    = true,
    stairInterval = 0.28,
    maxRecordSecs = 180,
    rewindBuffer  = 5,     -- detik buffer rewind sebelum jatuh
    maxSlots      = 5,
}

-- ─── HELPERS ─────────────────────────────────────────────────
local function getChar() return lp.Character end
local function getRoot()
    local c = getChar()
    return c and c:FindFirstChild("HumanoidRootPart")
end
local function getHum()
    local c = getChar()
    return c and c:FindFirstChildOfClass("Humanoid")
end
local function lerpCF(a: CFrame, b: CFrame, t: number): CFrame
    return a:Lerp(b, t)
end

-- ─── RECORD STATE ────────────────────────────────────────────
-- Frame: {cf=CFrame, t=timestamp}
-- recFrames = rekaman aktif (terus berjalan selama walkEnabled)
-- slots     = 5 slot save

type Frame = {cf: CFrame, t: number}
type Slot  = {frames: {Frame}, duration: number, name: string, saved: number}

local recFrames: {Frame} = {}
local recConn:   RBXScriptConnection?
local recording  = false

local slots: {Slot?} = {}
for i = 1, CFG.maxSlots do slots[i] = nil end
local activeSlot = 1

-- ─── WALK STATE ──────────────────────────────────────────────
local walkEnabled = false
local walkConn:   RBXScriptConnection?
local lastJump    = 0
local currentVel  = Vector3.zero

local playing     = false
local playConn:   RBXScriptConnection?
local playSpeed   = 1.0

-- ─── DIRECTION MAP ───────────────────────────────────────────
local DIR_MAP = {
    forward  = Vector3.new( 0, 0,-1),
    backward = Vector3.new( 0, 0, 1),
    left     = Vector3.new(-1, 0, 0),
    right    = Vector3.new( 1, 0, 0),
}

local function getTargetDir(root: BasePart): Vector3
    if CFG.direction == "camera" then
        local lv   = cam.CFrame.LookVector
        local flat = Vector3.new(lv.X, 0, lv.Z)
        return flat.Magnitude > 0.01 and flat.Unit or Vector3.zero
    end
    local d = DIR_MAP[CFG.direction] or DIR_MAP.forward
    return root.CFrame:VectorToWorldSpace(d)
end

-- ─── STAIR ASSIST ────────────────────────────────────────────
local function checkStair(root: BasePart, hum: Humanoid)
    if not CFG.stairBoost then return end
    local now = tick()
    if now - lastJump < CFG.stairInterval then return end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {lp.Character :: Model}
    local res = workspace:Raycast(root.Position, root.CFrame.LookVector * 2, params)
    if res and hum:GetState() == Enum.HumanoidStateType.Running then
        hum.Jump = true
        lastJump = now
    end
end

-- ─── RECORD ENGINE ───────────────────────────────────────────
-- Record jalan terus selama walk aktif; buffer rolling (buang
-- frame lama > maxRecordSecs). Rewind cukup ambil N detik terakhir.

local function startRecord()
    if recConn then recConn:Disconnect() end
    recFrames = {}
    recording = true
    local maxBuf = CFG.maxRecordSecs
    recConn = RunService.Heartbeat:Connect(function()
        local root = getRoot()
        if not root then return end
        local now = tick()
        table.insert(recFrames, {cf = root.CFrame, t = now})
        -- buang frame terlalu lama
        while #recFrames > 1 and (now - recFrames[1].t) > maxBuf do
            table.remove(recFrames, 1)
        end
    end)
end

local function stopRecord()
    recording = false
    if recConn then recConn:Disconnect(); recConn = nil end
end

-- Ambil N detik terakhir dari buffer (untuk rewind / save)
local function getRecentFrames(secs: number): {Frame}
    local now = tick()
    local out: {Frame} = {}
    for _, f in ipairs(recFrames) do
        if (now - f.t) <= secs then
            table.insert(out, {cf = f.cf, t = f.t})
        end
    end
    return out
end

-- ─── SAVE SLOT ───────────────────────────────────────────────
local function saveToSlot(idx: number, frames: {Frame}, name: string)
    if #frames < 2 then return end
    local dur = frames[#frames].t - frames[1].t
    slots[idx] = {
        frames   = frames,
        duration = dur,
        name     = name,
        saved    = tick(),
    }
end

-- ─── WALK ENGINE ─────────────────────────────────────────────
local function startWalk()
    if walkConn then walkConn:Disconnect() end
    currentVel = Vector3.zero
    startRecord()
    walkConn = RunService.Heartbeat:Connect(function(dt: number)
        local root = getRoot()
        local hum  = getHum()
        if not root or not hum or hum.Health <= 0 then return end
        hum.WalkSpeed = CFG.walkSpeed
        local factor  = math.clamp(CFG.smoothing + dt * 1.5, 0.01, 1)
        currentVel    = currentVel:Lerp(getTargetDir(root), factor)
        hum:Move(currentVel, false)
        checkStair(root, hum)
    end)
end

local function stopWalk()
    if walkConn then walkConn:Disconnect(); walkConn = nil end
    stopRecord()
    currentVel = Vector3.zero
    local hum = getHum()
    if hum then hum:Move(Vector3.zero, false) end
end

-- ─── PLAYBACK ENGINE ─────────────────────────────────────────
-- Teleport karakter mengikuti CFrame yang direkam, diinterpolasi
-- antara frame sesuai playSpeed.

local function stopPlayback()
    playing = false
    if playConn then playConn:Disconnect(); playConn = nil end
    local hum = getHum()
    if hum then
        hum.PlatformStand = false
        hum:Move(Vector3.zero, false)
    end
end

local function startPlayback(frames: {Frame}, speed: number)
    if #frames < 2 then return end
    if playing then stopPlayback() end

    -- Hentikan walk dulu biar tidak konflik
    if walkEnabled then stopWalk() end

    playing = true
    local hum  = getHum()
    if hum then hum.PlatformStand = true end  -- non-aktifkan physics karakter

    local startT = tick()
    local recDur = frames[#frames].t - frames[1].t
    local fi     = 1   -- frame index

    playConn = RunService.Heartbeat:Connect(function()
        if not playing then return end
        local root = getRoot()
        if not root then stopPlayback(); return end

        local elapsed = (tick() - startT) * speed
        if elapsed >= recDur then
            -- Sampai akhir: berhenti di frame terakhir
            root.CFrame = frames[#frames].cf
            stopPlayback()
            if walkEnabled then startWalk() end
            return
        end

        -- Cari dua frame yang mengapit elapsed
        local tOff = frames[1].t
        while fi < #frames - 1 and (frames[fi + 1].t - tOff) <= elapsed do
            fi += 1
        end
        local fA = frames[fi]
        local fB = frames[fi + 1]
        local seg = fB.t - fA.t
        local t   = seg > 0 and ((elapsed - (fA.t - tOff)) / seg) or 0
        root.CFrame = lerpCF(fA.cf, fB.cf, math.clamp(t, 0, 1))
    end)
end

-- ─── REWIND (ambil 5 detik terakhir lalu play balik) ─────────
local function doRewind()
    local frames = getRecentFrames(CFG.rewindBuffer)
    if #frames < 2 then return end
    -- Balik urutan = putar mundur
    local rev: {Frame} = {}
    local n   = #frames
    local t0  = frames[1].t
    for i = n, 1, -1 do
        table.insert(rev, {cf = frames[i].cf, t = t0 + (frames[n].t - frames[i].t)})
    end
    startPlayback(rev, playSpeed)
end

-- ─── FALL DETECTION → AUTO REWIND ────────────────────────────
local fallConn: RBXScriptConnection?
local function hookFall()
    if fallConn then fallConn:Disconnect() end
    local hum = getHum()
    if not hum then return end
    fallConn = hum.StateChanged:Connect(function(_, new)
        if new == Enum.HumanoidStateType.Freefall or
           new == Enum.HumanoidStateType.FallingDown then
            -- tunggu 0.4s biar yakin beneran jatuh
            task.delay(0.4, function()
                if not playing and walkEnabled then
                    doRewind()
                end
            end)
        end
    end)
end

lp.CharacterAdded:Connect(function()
    task.wait(0.6)
    if walkEnabled then startWalk() end
    hookFall()
end)
hookFall()

-- ══════════════════════════════════════════════════════════════
--  UI  PANEL
-- ══════════════════════════════════════════════════════════════
local SG = Instance.new("ScreenGui")
SG.Name              = "XXIVAutoWalk"
SG.ResetOnSpawn      = false
SG.IgnoreGuiInset    = true
SG.ZIndexBehavior    = Enum.ZIndexBehavior.Sibling
pcall(function() SG.Parent = lp:WaitForChild("PlayerGui") end)

-- ── Palet warna ───────────────────────────────────────────────
local P = {
    bg       = Color3.fromRGB(10, 11, 16),
    surface  = Color3.fromRGB(18, 20, 28),
    card     = Color3.fromRGB(24, 26, 36),
    border   = Color3.fromRGB(44, 48, 68),
    accent   = Color3.fromRGB(120, 190, 255),
    green    = Color3.fromRGB(80,  210, 120),
    red      = Color3.fromRGB(220,  70,  80),
    amber    = Color3.fromRGB(255, 185,  60),
    text     = Color3.fromRGB(240, 242, 250),
    sub      = Color3.fromRGB(110, 115, 140),
    white    = Color3.fromRGB(255, 255, 255),
}

-- ── Util UI ───────────────────────────────────────────────────
local function corner(parent: Instance, r: number)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r)
    c.Parent = parent
    return c
end
local function stroke(parent: Instance, col: Color3, t: number)
    local s = Instance.new("UIStroke")
    s.Color = col; s.Thickness = t
    s.Parent = parent; return s
end
local function pad(parent: Instance, px: number)
    local p = Instance.new("UIPadding")
    p.PaddingLeft  = UDim.new(0,px)
    p.PaddingRight = UDim.new(0,px)
    p.PaddingTop   = UDim.new(0,px)
    p.PaddingBottom= UDim.new(0,px)
    p.Parent = parent; return p
end
local function label(parent: Instance, txt: string, sz: number, col: Color3, xa: Enum.TextXAlignment?): TextLabel
    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1
    l.Text = txt; l.TextSize = sz
    l.TextColor3 = col
    l.Font = Enum.Font.GothamBold
    l.TextXAlignment = xa or Enum.TextXAlignment.Left
    l.Size = UDim2.fromScale(1,1)
    l.Parent = parent; return l
end
local function tween(obj: Instance, props: {[string]:any}, dur: number)
    TweenService:Create(obj, TweenInfo.new(dur, Enum.EasingStyle.Quad), props):Play()
end

-- ── Root frame ────────────────────────────────────────────────
local Main = Instance.new("Frame")
Main.Name              = "Main"
Main.Size              = UDim2.fromOffset(320, 440)
Main.Position          = UDim2.fromOffset(50, 80)
Main.BackgroundColor3  = P.bg
Main.BorderSizePixel   = 0
Main.Active            = true
Main.Draggable         = true
Main.Parent            = SG
corner(Main, 16)
stroke(Main, P.border, 1)

-- Glass overlay
local glass = Instance.new("Frame")
glass.Size              = UDim2.fromScale(1,1)
glass.BackgroundColor3  = Color3.fromRGB(255,255,255)
glass.BackgroundTransparency = 0.96
glass.BorderSizePixel   = 0
glass.ZIndex            = 0
glass.Parent            = Main
corner(glass, 16)

-- ── Top bar ───────────────────────────────────────────────────
local topbar = Instance.new("Frame")
topbar.Size             = UDim2.new(1,0,0,46)
topbar.BackgroundColor3 = P.surface
topbar.BorderSizePixel  = 0
topbar.ZIndex           = 2
topbar.Parent           = Main
corner(topbar, 16)

-- bottom corners cover
local topFill = Instance.new("Frame")
topFill.Size            = UDim2.new(1,0,0,16)
topFill.Position        = UDim2.new(0,0,1,-16)
topFill.BackgroundColor3= P.surface
topFill.BorderSizePixel = 0
topFill.ZIndex          = 2
topFill.Parent          = topbar

local titleHolder = Instance.new("Frame")
titleHolder.Size            = UDim2.new(1,-16,1,0)
titleHolder.Position        = UDim2.fromOffset(14,0)
titleHolder.BackgroundTransparency = 1
titleHolder.Parent          = topbar

local titleL = Instance.new("TextLabel")
titleL.BackgroundTransparency = 1
titleL.Size      = UDim2.fromScale(1,1)
titleL.Text      = "✦  XXIV AUTO WALK"
titleL.Font      = Enum.Font.GothamBold
titleL.TextSize  = 14
titleL.TextColor3= P.accent
titleL.TextXAlignment = Enum.TextXAlignment.Left
titleL.Parent    = titleHolder

local verL = Instance.new("TextLabel")
verL.BackgroundTransparency = 1
verL.Size       = UDim2.new(0,60,1,0)
verL.AnchorPoint= Vector2.new(1,0)
verL.Position   = UDim2.new(1,0,0,0)
verL.Text       = "v3.0"
verL.Font       = Enum.Font.Gotham
verL.TextSize   = 10
verL.TextColor3 = P.sub
verL.TextXAlignment = Enum.TextXAlignment.Right
verL.Parent     = titleHolder

-- ── Scroll content ────────────────────────────────────────────
local scroll = Instance.new("ScrollingFrame")
scroll.Position              = UDim2.fromOffset(0,50)
scroll.Size                  = UDim2.new(1,0,1,-54)
scroll.BackgroundTransparency= 1
scroll.BorderSizePixel       = 0
scroll.ScrollBarThickness    = 3
scroll.ScrollBarImageColor3  = P.accent
scroll.AutomaticCanvasSize   = Enum.AutomaticSize.Y
scroll.CanvasSize            = UDim2.new(0,0,0,0)
scroll.Parent                = Main

local list = Instance.new("UIListLayout",scroll)
list.Padding     = UDim.new(0,8)
list.SortOrder   = Enum.SortOrder.LayoutOrder
local sp = Instance.new("UIPadding",scroll)
sp.PaddingLeft  = UDim.new(0,10)
sp.PaddingRight = UDim.new(0,10)
sp.PaddingTop   = UDim.new(0,10)
sp.PaddingBottom= UDim.new(0,10)

local wOrder = 0
local function wo() wOrder+=1; return wOrder end

-- ── Widget factory ────────────────────────────────────────────
local function sectionLabel(txt: string)
    local f = Instance.new("Frame")
    f.Size = UDim2.new(1,0,0,20)
    f.BackgroundTransparency = 1
    f.LayoutOrder = wo()
    f.Parent = scroll
    local l2 = Instance.new("TextLabel")
    l2.BackgroundTransparency = 1
    l2.Size = UDim2.fromScale(1,1)
    l2.Text = txt
    l2.Font = Enum.Font.GothamBold
    l2.TextSize = 10
    l2.TextColor3 = P.sub
    l2.TextXAlignment = Enum.TextXAlignment.Left
    l2.Parent = f
end

local function divider()
    local d = Instance.new("Frame")
    d.Size = UDim2.new(1,0,0,1)
    d.BackgroundColor3 = P.border
    d.BorderSizePixel = 0
    d.LayoutOrder = wo()
    d.Parent = scroll
end

-- Rounded card button
local function cardBtn(txt: string, col: Color3, h: number): TextButton
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1,0,0,h)
    btn.BackgroundColor3 = col
    btn.Text = txt
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 13
    btn.TextColor3 = P.text
    btn.AutoButtonColor = false
    btn.LayoutOrder = wo()
    btn.Parent = scroll
    corner(btn, 10)
    btn.MouseEnter:Connect(function()
        tween(btn, {BackgroundColor3 = col:Lerp(P.white, 0.12)}, 0.12)
    end)
    btn.MouseLeave:Connect(function()
        tween(btn, {BackgroundColor3 = col}, 0.12)
    end)
    btn.MouseButton1Down:Connect(function()
        tween(btn, {BackgroundColor3 = col:Lerp(Color3.new(),0.2)}, 0.06)
    end)
    btn.MouseButton1Up:Connect(function()
        tween(btn, {BackgroundColor3 = col}, 0.1)
    end)
    return btn
end

-- Toggle pill button
local function pillToggle(labelOn: string, labelOff: string, h: number,
    cb: (s:boolean)->()): (TextButton, (s:boolean)->())

    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1,0,0,h)
    btn.BackgroundColor3 = P.card
    btn.Text = labelOff
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 13
    btn.TextColor3 = P.sub
    btn.AutoButtonColor = false
    btn.LayoutOrder = wo()
    btn.Parent = scroll
    corner(btn, 10)
    stroke(btn, P.border, 1)

    local state = false
    local function set(s: boolean)
        state = s
        tween(btn, {
            BackgroundColor3 = s and P.green:Lerp(P.card,0.5) or P.card,
            TextColor3       = s and P.green or P.sub,
        }, 0.18)
        btn.Text = s and labelOn or labelOff
    end
    btn.MouseButton1Click:Connect(function()
        set(not state)
        cb(state)
    end)
    return btn, set
end

-- Slider
local function slider(lbl2: string, minV: number, maxV: number, init: number,
    fmt: string, cb: (v:number)->()): (()->number)

    local row = Instance.new("Frame")
    row.Size = UDim2.new(1,0,0,54)
    row.BackgroundColor3 = P.card
    row.BorderSizePixel = 0
    row.LayoutOrder = wo()
    row.Parent = scroll
    corner(row, 10)
    pad(row, 10)

    local innerList = Instance.new("UIListLayout",row)
    innerList.Padding = UDim.new(0,6)

    local topRow = Instance.new("Frame")
    topRow.Size = UDim2.new(1,0,0,16)
    topRow.BackgroundTransparency = 1
    topRow.Parent = row

    local lbl3 = Instance.new("TextLabel")
    lbl3.BackgroundTransparency = 1
    lbl3.Size = UDim2.new(0.6,0,1,0)
    lbl3.Text = lbl2
    lbl3.Font = Enum.Font.Gotham
    lbl3.TextSize = 11
    lbl3.TextColor3 = P.sub
    lbl3.TextXAlignment = Enum.TextXAlignment.Left
    lbl3.Parent = topRow

    local valL = Instance.new("TextLabel")
    valL.BackgroundTransparency = 1
    valL.Size = UDim2.new(0.4,0,1,0)
    valL.AnchorPoint = Vector2.new(1,0)
    valL.Position = UDim2.new(1,0,0,0)
    valL.Text = string.format(fmt, init)
    valL.Font = Enum.Font.GothamBold
    valL.TextSize = 11
    valL.TextColor3 = P.accent
    valL.TextXAlignment = Enum.TextXAlignment.Right
    valL.Parent = topRow

    local track = Instance.new("Frame")
    track.Size = UDim2.new(1,0,0,8)
    track.BackgroundColor3 = P.border
    track.BorderSizePixel = 0
    track.Parent = row
    corner(track, 4)

    local fill = Instance.new("Frame")
    fill.Size = UDim2.new((init-minV)/(maxV-minV),0,1,0)
    fill.BackgroundColor3 = P.accent
    fill.BorderSizePixel = 0
    fill.Parent = track
    corner(fill, 4)

    local thumb = Instance.new("TextButton")
    thumb.Size = UDim2.fromOffset(16,16)
    thumb.AnchorPoint = Vector2.new(0.5,0.5)
    thumb.Position = UDim2.new((init-minV)/(maxV-minV),0,0.5,0)
    thumb.BackgroundColor3 = P.white
    thumb.Text = ""
    thumb.AutoButtonColor = false
    thumb.Parent = track
    corner(thumb, 8)

    local curVal = init
    local dragging = false
    thumb.MouseButton1Down:Connect(function() dragging = true end)
    UserInputService.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
    end)
    UserInputService.InputChanged:Connect(function(i)
        if not dragging then return end
        if i.UserInputType ~= Enum.UserInputType.MouseMovement then return end
        local abs = track.AbsolutePosition.X
        local w   = track.AbsoluteSize.X
        local rel = math.clamp((i.Position.X - abs)/w, 0, 1)
        curVal = math.round((minV + (maxV-minV)*rel)*100)/100
        fill.Size      = UDim2.new(rel,0,1,0)
        thumb.Position = UDim2.new(rel,0,0.5,0)
        valL.Text = string.format(fmt, curVal)
        cb(curVal)
    end)

    return function() return curVal end
end

-- Slot row: nama + tombol Save / Play / Rewind-play
local slotLabels: {TextLabel} = {}
local function makeSlotRow(idx: number)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1,0,0,36)
    row.BackgroundColor3 = P.card
    row.BorderSizePixel = 0
    row.LayoutOrder = wo()
    row.Parent = scroll
    corner(row, 8)
    stroke(row, P.border, 1)

    local idxL = Instance.new("TextLabel")
    idxL.BackgroundTransparency = 1
    idxL.Position = UDim2.fromOffset(10,0)
    idxL.Size = UDim2.fromOffset(20,36)
    idxL.Text = tostring(idx)
    idxL.Font = Enum.Font.GothamBold
    idxL.TextSize = 12
    idxL.TextColor3 = P.accent
    idxL.TextXAlignment = Enum.TextXAlignment.Center
    idxL.Parent = row

    local namL = Instance.new("TextLabel")
    namL.BackgroundTransparency = 1
    namL.Position = UDim2.fromOffset(34,0)
    namL.Size = UDim2.new(1,-180,1,0)
    namL.Text = "— empty —"
    namL.Font = Enum.Font.Gotham
    namL.TextSize = 11
    namL.TextColor3 = P.sub
    namL.TextXAlignment = Enum.TextXAlignment.Left
    namL.TextTruncate = Enum.TextTruncate.AtEnd
    namL.Parent = row
    slotLabels[idx] = namL

    local function miniBtn(txt: string, col: Color3, xOff: number): TextButton
        local b = Instance.new("TextButton")
        b.AnchorPoint = Vector2.new(1,0.5)
        b.Position = UDim2.new(1,-xOff,0.5,0)
        b.Size = UDim2.fromOffset(44,24)
        b.BackgroundColor3 = col
        b.Text = txt
        b.Font = Enum.Font.GothamBold
        b.TextSize = 10
        b.TextColor3 = P.text
        b.AutoButtonColor = false
        b.Parent = row
        corner(b, 6)
        b.MouseEnter:Connect(function() tween(b,{BackgroundColor3=col:Lerp(P.white,0.15)},0.1) end)
        b.MouseLeave:Connect(function() tween(b,{BackgroundColor3=col},0.1) end)
        return b
    end

    local saveB = miniBtn("SAVE", P.amber, 98)
    local playB = miniBtn("PLAY", P.green, 50)
    local rewB  = miniBtn("REW",  P.accent, 2)

    local function refreshLabel()
        local s = slots[idx]
        if s then
            namL.Text      = string.format("%s  (%.1fs)", s.name, s.duration)
            namL.TextColor3 = P.text
        else
            namL.Text = "— empty —"
            namL.TextColor3 = P.sub
        end
    end

    saveB.MouseButton1Click:Connect(function()
        -- Ambil semua rekaman yang ada
        local frames = getRecentFrames(CFG.maxRecordSecs)
        if #frames < 2 then return end
        saveToSlot(idx, frames, "Walk " .. idx)
        refreshLabel()
        tween(saveB, {BackgroundColor3 = P.green}, 0.1)
        task.delay(0.6, function() tween(saveB, {BackgroundColor3 = P.amber}, 0.2) end)
    end)

    playB.MouseButton1Click:Connect(function()
        local s = slots[idx]
        if not s then return end
        startPlayback(s.frames, playSpeed)
    end)

    rewB.MouseButton1Click:Connect(function()
        local s = slots[idx]
        if not s then return end
        -- Balik rekaman slot
        local rev: {Frame} = {}
        local n = #s.frames
        local t0 = s.frames[1].t
        for i = n, 1, -1 do
            table.insert(rev, {cf=s.frames[i].cf, t=t0+(s.frames[n].t - s.frames[i].t)})
        end
        startPlayback(rev, playSpeed)
    end)
end

-- ── Status bar ────────────────────────────────────────────────
local function statusCard(): TextLabel
    local f = Instance.new("Frame")
    f.Size = UDim2.new(1,0,0,30)
    f.BackgroundColor3 = P.card
    f.BorderSizePixel = 0
    f.LayoutOrder = wo()
    f.Parent = scroll
    corner(f, 8)
    local l2 = Instance.new("TextLabel")
    l2.BackgroundTransparency = 1
    l2.Size = UDim2.fromScale(1,1)
    l2.Font = Enum.Font.Code
    l2.TextSize = 11
    l2.TextColor3 = P.sub
    l2.TextXAlignment = Enum.TextXAlignment.Center
    l2.Parent = f
    return l2
end

-- ══ Build semua widget ════════════════════════════════════════

sectionLabel("AUTO WALK")
local _, setWalkToggle = pillToggle("● WALKING  (F to toggle)", "○ IDLE  (F to start)", 38, function(s)
    walkEnabled = s
    if s then startWalk() else stopWalk() end
end)

divider()
sectionLabel("SETTINGS")
slider("Walk Speed", 4, 100, CFG.walkSpeed, "%.0f  stud/s", function(v)
    CFG.walkSpeed = v
    local h = getHum(); if h then h.WalkSpeed = v end
end)
slider("Smoothing", 0.02, 0.5, CFG.smoothing, "%.2f", function(v)
    CFG.smoothing = v
end)
slider("Playback Speed", 0.25, 4.0, 1.0, "%.2f ×", function(v)
    playSpeed = v
end)
slider("Rewind Buffer", 2, 30, CFG.rewindBuffer, "%.0f s", function(v)
    CFG.rewindBuffer = v
end)

divider()
sectionLabel("DIRECTION")
local dirOpts = {"camera","forward","backward","left","right"}
local dirIdx  = 1
local dirBtn  = cardBtn("Direction:  camera  ▾", P.card, 34)
dirBtn.TextColor3 = P.accent
dirBtn.MouseButton1Click:Connect(function()
    dirIdx = dirIdx % #dirOpts + 1
    CFG.direction = dirOpts[dirIdx]
    dirBtn.Text = "Direction:  " .. CFG.direction .. "  ▾"
end)

divider()
sectionLabel("STAIR ASSIST")
pillToggle("● Stair Assist ON", "○ Stair Assist OFF", 32, function(s)
    CFG.stairBoost = s
end)

divider()
sectionLabel("RECORD  •  5 SLOTS")
for i = 1, CFG.maxSlots do makeSlotRow(i) end

local recBtn = cardBtn("⏺  START RECORDING", P.red, 36)
local recState = false
recBtn.MouseButton1Click:Connect(function()
    recState = not recState
    if recState then
        recFrames = {}
        recBtn.Text = "⏹  STOP RECORDING"
        tween(recBtn, {BackgroundColor3 = P.sub}, 0.15)
    else
        recBtn.Text = "⏺  START RECORDING"
        tween(recBtn, {BackgroundColor3 = P.red}, 0.15)
    end
end)

divider()
sectionLabel("REWIND  (5 s sebelum jatuh)")
cardBtn("⏪  REWIND NOW", P.accent, 34).MouseButton1Click:Connect(doRewind)

divider()
sectionLabel("PLAYBACK CONTROL")
local stopBtn = cardBtn("⏹  STOP PLAYBACK", P.card, 32)
stopBtn.TextColor3 = P.red
stopBtn.MouseButton1Click:Connect(stopPlayback)

divider()
local statL = statusCard()

-- Status update loop
RunService.Heartbeat:Connect(function()
    local hum   = getHum()
    local spd   = hum and math.floor(hum.WalkSpeed) or 0
    local rLen  = #recFrames
    if playing then
        statL.Text = string.format("▶ PLAYBACK  ×%.2f", playSpeed)
        statL.TextColor3 = P.accent
    elseif walkEnabled then
        statL.Text = string.format("● WALK  spd=%d  rec=%d frames", spd, rLen)
        statL.TextColor3 = P.green
    else
        statL.Text = string.format("○ IDLE  rec=%d frames", rLen)
        statL.TextColor3 = P.sub
    end
end)

-- ── Hotkeys ───────────────────────────────────────────────────
UserInputService.InputBegan:Connect(function(inp, gp)
    if gp then return end
    if inp.KeyCode == Enum.KeyCode.F then
        walkEnabled = not walkEnabled
        setWalkToggle(walkEnabled)
        if walkEnabled then startWalk() else stopWalk() end
    elseif inp.KeyCode == Enum.KeyCode.RightShift then
        Main.Visible = not Main.Visible
    elseif inp.KeyCode == Enum.KeyCode.R then
        doRewind()
    end
end)

-- ============================================================
--  XXIV AUTO WALK  v5.0  |  Executor LocalScript  |  Luau
--  Style: WarpahExploits (loading card, sidebar nav, tabbed)
--  Tabs: Jalan | Rekam | Path | Folder | Bagikan
--  Features: smooth walk, record, named save, playback, rewind
-- ============================================================

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")

local lp  = Players.LocalPlayer
local cam = workspace.CurrentCamera

-- ─── ENGINE STATE ────────────────────────────────────────────
local CFG = {
    walkSpeed     = 1,      -- multiplier 0.1–5
    animSpeed     = 1,      -- animasi speed 0.1–5
    smoothing     = 0.14,
    direction     = "camera",
    stairBoost    = true,
    stairInterval = 0.28,
    maxRecSecs    = 180,
    rewindBuf     = 5,
}

type Frame = {cf: CFrame, t: number}
type PathSlot = {name: string, frames: {Frame}, dur: number, folder: string}

local walkEnabled  = false
local playing      = false
local recording    = false
local walkConn:    RBXScriptConnection?
local recConn:     RBXScriptConnection?
local playConn:    RBXScriptConnection?
local fallConn:    RBXScriptConnection?
local recFrames:   {Frame} = {}
local paths:       {PathSlot} = {}
local activeFolder = "Default"
local folders:     {string} = {"Default"}
local playSpeed    = 1.0
local lastJump     = 0
local currentVel   = Vector3.zero

local DIR_MAP = {
    forward=Vector3.new(0,0,-1),backward=Vector3.new(0,0,1),
    left=Vector3.new(-1,0,0),right=Vector3.new(1,0,0),
}

local function getRoot() local c=lp.Character; return c and c:FindFirstChild("HumanoidRootPart") end
local function getHum()  local c=lp.Character; return c and c:FindFirstChildOfClass("Humanoid") end

-- ─── WALK ENGINE ─────────────────────────────────────────────
local function getDir(root)
    if CFG.direction=="camera" then
        local lv=cam.CFrame.LookVector
        local f=Vector3.new(lv.X,0,lv.Z)
        return f.Magnitude>0.01 and f.Unit or Vector3.zero
    end
    local d=DIR_MAP[CFG.direction] or DIR_MAP.forward
    return root.CFrame:VectorToWorldSpace(d)
end

local function checkStair(root,hum)
    if not CFG.stairBoost then return end
    local now=tick()
    if now-lastJump<CFG.stairInterval then return end
    local p=RaycastParams.new()
    p.FilterType=Enum.RaycastFilterType.Exclude
    p.FilterDescendantsInstances={lp.Character}
    local res=workspace:Raycast(root.Position,root.CFrame.LookVector*2,p)
    if res and hum:GetState()==Enum.HumanoidStateType.Running then
        hum.Jump=true; lastJump=now
    end
end

local function startRec()
    if recConn then recConn:Disconnect() end
    recFrames={}; recording=true
    recConn=RunService.Heartbeat:Connect(function()
        local root=getRoot(); if not root then return end
        local now=tick()
        table.insert(recFrames,{cf=root.CFrame,t=now})
        while #recFrames>1 and (now-recFrames[1].t)>CFG.maxRecSecs do
            table.remove(recFrames,1)
        end
    end)
end

local function stopRec()
    recording=false
    if recConn then recConn:Disconnect(); recConn=nil end
end

local function startWalk()
    if walkConn then walkConn:Disconnect() end
    currentVel=Vector3.zero
    startRec()
    walkConn=RunService.Heartbeat:Connect(function(dt)
        local root=getRoot(); local hum=getHum()
        if not root or not hum or hum.Health<=0 then return end
        hum.WalkSpeed = 16 * CFG.walkSpeed
        local factor=math.clamp(CFG.smoothing+dt*1.5,0.01,1)
        currentVel=currentVel:Lerp(getDir(root),factor)
        hum:Move(currentVel,false)
        checkStair(root,hum)
    end)
end

local function stopWalk()
    if walkConn then walkConn:Disconnect(); walkConn=nil end
    stopRec()
    currentVel=Vector3.zero
    local hum=getHum(); if hum then hum:Move(Vector3.zero,false) end
end

local function stopPlayback()
    playing=false
    if playConn then playConn:Disconnect(); playConn=nil end
    local hum=getHum()
    if hum then hum.PlatformStand=false; hum:Move(Vector3.zero,false) end
end

local function startPlayback(frames,speed)
    if #frames<2 then return end
    if playing then stopPlayback() end
    if walkEnabled then stopWalk() end
    playing=true
    local hum=getHum(); if hum then hum.PlatformStand=true end
    local startT=tick()
    local dur=frames[#frames].t-frames[1].t
    local fi=1
    playConn=RunService.Heartbeat:Connect(function()
        if not playing then return end
        local root=getRoot(); if not root then stopPlayback(); return end
        local el=(tick()-startT)*speed
        if el>=dur then
            root.CFrame=frames[#frames].cf
            stopPlayback()
            if walkEnabled then startWalk() end
            return
        end
        while fi<#frames-1 and (frames[fi+1].t-frames[1].t)<=el do fi+=1 end
        local fA,fB=frames[fi],frames[fi+1]
        local seg=fB.t-fA.t
        local t=seg>0 and ((el-(fA.t-frames[1].t))/seg) or 0
        root.CFrame=fA.cf:Lerp(fB.cf,math.clamp(t,0,1))
    end)
end

local function doRewind()
    local now=tick(); local buf={} ; local rev={}
    for _,f in ipairs(recFrames) do
        if (now-f.t)<=CFG.rewindBuf then table.insert(buf,f) end
    end
    if #buf<2 then return end
    local n=#buf; local t0=buf[1].t
    for i=n,1,-1 do table.insert(rev,{cf=buf[i].cf,t=t0+(buf[n].t-buf[i].t)}) end
    startPlayback(rev,playSpeed)
end

local function hookFall()
    if fallConn then fallConn:Disconnect() end
    local hum=getHum(); if not hum then return end
    fallConn=hum.StateChanged:Connect(function(_,new)
        if new==Enum.HumanoidStateType.Freefall or new==Enum.HumanoidStateType.FallingDown then
            task.delay(0.4,function()
                if not playing and walkEnabled then doRewind() end
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
--  UI  (WarpahExploits style)
-- ══════════════════════════════════════════════════════════════
local SG=Instance.new("ScreenGui")
SG.Name="XXIVAutoWalkV5"; SG.ResetOnSpawn=false
SG.IgnoreGuiInset=true; SG.ZIndexBehavior=Enum.ZIndexBehavior.Sibling
pcall(function() SG.Parent=lp:WaitForChild("PlayerGui") end)

-- ── Palet (Warpah dark-blue) ─────────────────────────────────
local W={
    bg      = Color3.fromRGB(13, 15, 23),
    surface = Color3.fromRGB(18, 21, 32),
    card    = Color3.fromRGB(23, 27, 42),
    border  = Color3.fromRGB(38, 44, 68),
    accent  = Color3.fromRGB(85, 175, 255),
    cyan    = Color3.fromRGB(60, 220, 210),
    green   = Color3.fromRGB(70, 215, 115),
    red     = Color3.fromRGB(220, 65, 75),
    amber   = Color3.fromRGB(255, 185, 55),
    text    = Color3.fromRGB(235, 240, 252),
    sub     = Color3.fromRGB(100, 110, 140),
    white   = Color3.fromRGB(255, 255, 255),
    sidebarW= 90,
}

local function corner(p,r) local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0,r); c.Parent=p end
local function stroke(p,col,t) local s=Instance.new("UIStroke"); s.Color=col; s.Thickness=t; s.Parent=p end
local function tw(o,pr,d,st) TweenService:Create(o,TweenInfo.new(d,st or Enum.EasingStyle.Quad),pr):Play() end
local function lbl(parent,txt,sz,col,xa,pos,size)
    local l=Instance.new("TextLabel"); l.BackgroundTransparency=1
    l.Text=txt; l.TextSize=sz; l.TextColor3=col
    l.Font=Enum.Font.GothamBold; l.TextXAlignment=xa or Enum.TextXAlignment.Left
    l.Parent=parent
    if pos then l.Position=pos end
    if size then l.Size=size else l.Size=UDim2.fromScale(1,1) end
    return l
end

-- ══════════════════════════════════════════════════════════════
--  LOADING CARD  (WarpahExploits style)
-- ══════════════════════════════════════════════════════════════
local loadCard=Instance.new("Frame")
loadCard.AnchorPoint=Vector2.new(0.5,0.5)
loadCard.Position=UDim2.fromScale(0.5,0.5)
loadCard.Size=UDim2.fromOffset(360,130)
loadCard.BackgroundColor3=W.surface
loadCard.BorderSizePixel=0
loadCard.ZIndex=200
loadCard.Parent=SG
corner(loadCard,14)
stroke(loadCard,W.border,1)

-- Avatar icon placeholder
local iconF=Instance.new("Frame")
iconF.Position=UDim2.fromOffset(14,14)
iconF.Size=UDim2.fromOffset(52,52)
iconF.BackgroundColor3=W.card
iconF.BorderSizePixel=0
iconF.Parent=loadCard
corner(iconF,10)
stroke(iconF,W.accent,1.5)
lbl(iconF,"✦",22,W.accent,Enum.TextXAlignment.Center)

-- Title "WarpahExploits" style
local nameLbl=Instance.new("TextLabel")
nameLbl.Position=UDim2.fromOffset(76,14)
nameLbl.Size=UDim2.fromOffset(260,24)
nameLbl.BackgroundTransparency=1
nameLbl.Font=Enum.Font.GothamBold
nameLbl.TextSize=16
nameLbl.TextXAlignment=Enum.TextXAlignment.Left
nameLbl.TextColor3=W.text
nameLbl.Parent=loadCard
-- "XXIV" plain + "AutoWalk" accent
nameLbl.Text=""
local nm1=Instance.new("TextLabel")
nm1.BackgroundTransparency=1; nm1.Size=UDim2.fromOffset(44,24)
nm1.Position=UDim2.fromOffset(76,14); nm1.Text="XXIV"
nm1.Font=Enum.Font.GothamBold; nm1.TextSize=16
nm1.TextColor3=W.text; nm1.TextXAlignment=Enum.TextXAlignment.Left
nm1.Parent=loadCard
local nm2=Instance.new("TextLabel")
nm2.BackgroundTransparency=1; nm2.Size=UDim2.fromOffset(120,24)
nm2.Position=UDim2.fromOffset(118,14); nm2.Text="AutoWalk"
nm2.Font=Enum.Font.GothamBold; nm2.TextSize=16
nm2.TextColor3=W.accent; nm2.TextXAlignment=Enum.TextXAlignment.Left
nm2.Parent=loadCard

local verLbl=Instance.new("TextLabel")
verLbl.Position=UDim2.fromOffset(76,38)
verLbl.Size=UDim2.fromOffset(80,16)
verLbl.BackgroundTransparency=1
verLbl.Text="v5.0  •  Real"
verLbl.Font=Enum.Font.Gotham
verLbl.TextSize=10
verLbl.TextColor3=W.sub
verLbl.TextXAlignment=Enum.TextXAlignment.Left
verLbl.Parent=loadCard

-- Progress bar
local progTrack=Instance.new("Frame")
progTrack.Position=UDim2.fromOffset(14,80)
progTrack.Size=UDim2.new(1,-28,0,6)
progTrack.BackgroundColor3=W.card
progTrack.BorderSizePixel=0
progTrack.Parent=loadCard; corner(progTrack,3)

local progFill=Instance.new("Frame")
progFill.Size=UDim2.new(0,0,1,0)
progFill.BackgroundColor3=W.accent
progFill.BorderSizePixel=0
progFill.Parent=progTrack; corner(progFill,3)

-- Pct label (pojok kanan) seperti WarpahExploits
local pctLbl=Instance.new("TextLabel")
pctLbl.AnchorPoint=Vector2.new(1,0)
pctLbl.Position=UDim2.new(1,-14,0,88)
pctLbl.Size=UDim2.fromOffset(36,16)
pctLbl.BackgroundTransparency=1
pctLbl.Text="0%"
pctLbl.Font=Enum.Font.GothamBold
pctLbl.TextSize=10
pctLbl.TextColor3=W.accent
pctLbl.TextXAlignment=Enum.TextXAlignment.Right
pctLbl.Parent=loadCard

local statusLbl2=Instance.new("TextLabel")
statusLbl2.Position=UDim2.fromOffset(14,96)
statusLbl2.Size=UDim2.new(1,-60,0,16)
statusLbl2.BackgroundTransparency=1
statusLbl2.Text="Connecting to server"
statusLbl2.Font=Enum.Font.Gotham
statusLbl2.TextSize=10
statusLbl2.TextColor3=W.sub
statusLbl2.TextXAlignment=Enum.TextXAlignment.Left
statusLbl2.Parent=loadCard

-- Loading animation
local loadSteps={
    {0.08,"Connecting to server"},
    {0.20,"Verifying license"},
    {0.35,"Loading modules"},
    {0.50,"Building UI"},
    {0.65,"Hooking services"},
    {0.80,"Initializing engine"},
    {0.93,"Finalizing"},
    {1.00,"Done"},
}

-- ── Build main panel (hidden) ─────────────────────────────────
local Main=Instance.new("Frame")
Main.Name="Main"; Main.Size=UDim2.fromOffset(430,330)
Main.Position=UDim2.fromOffset(60,80); Main.BackgroundColor3=W.bg
Main.BorderSizePixel=0; Main.Active=true; Main.Draggable=true
Main.Visible=false; Main.Parent=SG
corner(Main,14); stroke(Main,W.border,1)

-- Topbar
local topbar=Instance.new("Frame")
topbar.Size=UDim2.new(1,0,0,42); topbar.BackgroundColor3=W.surface
topbar.BorderSizePixel=0; topbar.Parent=Main
corner(topbar,14)
local topFix=Instance.new("Frame")
topFix.Size=UDim2.new(1,0,0,14); topFix.Position=UDim2.new(0,0,1,-14)
topFix.BackgroundColor3=W.surface; topFix.BorderSizePixel=0; topFix.Parent=topbar

-- Avatar icon topbar
local topIcon=Instance.new("Frame")
topIcon.Position=UDim2.fromOffset(10,8)
topIcon.Size=UDim2.fromOffset(28,28)
topIcon.BackgroundColor3=W.card
topIcon.BorderSizePixel=0
topIcon.Parent=topbar; corner(topIcon,6)
stroke(topIcon,W.accent,1)
lbl(topIcon,"✦",12,W.accent,Enum.TextXAlignment.Center)

-- "XXIV"/"AutoWalk" title
local t1=lbl(topbar,"XXIV",13,W.text,Enum.TextXAlignment.Left,
    UDim2.fromOffset(44,13),UDim2.fromOffset(36,16))
local t2=lbl(topbar,"AutoWalk",13,W.accent,Enum.TextXAlignment.Left,
    UDim2.fromOffset(78,13),UDim2.fromOffset(80,16))

-- FPS / ping etc (Warpah style)
local function topStat(txt,col,xOff)
    local l=Instance.new("TextLabel")
    l.BackgroundTransparency=1; l.Size=UDim2.fromOffset(60,16)
    l.Position=UDim2.fromOffset(xOff,13); l.Text=txt
    l.Font=Enum.Font.GothamBold; l.TextSize=11
    l.TextColor3=col; l.TextXAlignment=Enum.TextXAlignment.Left
    l.Parent=topbar; return l
end
local fpsLbl = topStat("FPS: 60",W.green,168)
local pingLbl= topStat("Ping: 0 ms",W.text,230)

-- min/close
local minBtn=Instance.new("TextButton")
minBtn.AnchorPoint=Vector2.new(1,0.5); minBtn.Position=UDim2.new(1,-38,0.5,0)
minBtn.Size=UDim2.fromOffset(24,24); minBtn.BackgroundColor3=W.card
minBtn.Text="−"; minBtn.Font=Enum.Font.GothamBold; minBtn.TextSize=14
minBtn.TextColor3=W.sub; minBtn.AutoButtonColor=false; minBtn.Parent=topbar
corner(minBtn,6)
local clsBtn=Instance.new("TextButton")
clsBtn.AnchorPoint=Vector2.new(1,0.5); clsBtn.Position=UDim2.new(1,-10,0.5,0)
clsBtn.Size=UDim2.fromOffset(24,24); clsBtn.BackgroundColor3=W.card
clsBtn.Text="✕"; clsBtn.Font=Enum.Font.GothamBold; clsBtn.TextSize=12
clsBtn.TextColor3=W.sub; clsBtn.AutoButtonColor=false; clsBtn.Parent=topbar
corner(clsBtn,6)
clsBtn.MouseButton1Click:Connect(function() Main.Visible=false end)
minBtn.MouseButton1Click:Connect(function()
    local body=Main:FindFirstChild("Body")
    if body then body.Visible=not body.Visible
        Main.Size=body.Visible and UDim2.fromOffset(430,330) or UDim2.fromOffset(430,42)
    end
end)

-- Body (sidebar + content)
local Body=Instance.new("Frame")
Body.Name="Body"; Body.Position=UDim2.fromOffset(0,42)
Body.Size=UDim2.new(1,0,1,-42); Body.BackgroundTransparency=1
Body.BorderSizePixel=0; Body.Parent=Main

-- Sidebar (Warpah style)
local sidebar=Instance.new("Frame")
sidebar.Size=UDim2.new(0,W.sidebarW,1,0)
sidebar.BackgroundColor3=W.surface
sidebar.BorderSizePixel=0; sidebar.Parent=Body
local rightLine=Instance.new("Frame")
rightLine.AnchorPoint=Vector2.new(1,0); rightLine.Position=UDim2.new(1,0,0,0)
rightLine.Size=UDim2.new(0,1,1,0); rightLine.BackgroundColor3=W.border
rightLine.BorderSizePixel=0; rightLine.Parent=sidebar

local navList=Instance.new("UIListLayout",sidebar)
navList.Padding=UDim.new(0,2)
navList.SortOrder=Enum.SortOrder.LayoutOrder
local navPad=Instance.new("UIPadding",sidebar)
navPad.PaddingTop=UDim.new(0,8); navPad.PaddingLeft=UDim.new(0,6)
navPad.PaddingRight=UDim.new(0,6)

-- Content area
local contentArea=Instance.new("Frame")
contentArea.Position=UDim2.new(0,W.sidebarW,0,0)
contentArea.Size=UDim2.new(1,-W.sidebarW,1,0)
contentArea.BackgroundTransparency=1
contentArea.BorderSizePixel=0; contentArea.Parent=Body

-- ── Tab pages ─────────────────────────────────────────────────
local pages={}
local function mkPage(name)
    local p=Instance.new("ScrollingFrame")
    p.Name=name; p.Size=UDim2.fromScale(1,1)
    p.BackgroundTransparency=1; p.BorderSizePixel=0
    p.ScrollBarThickness=3; p.ScrollBarImageColor3=W.accent
    p.AutomaticCanvasSize=Enum.AutomaticSize.Y
    p.CanvasSize=UDim2.new(0,0,0,0); p.Visible=false; p.Parent=contentArea
    local ul=Instance.new("UIListLayout",p)
    ul.Padding=UDim.new(0,6); ul.SortOrder=Enum.SortOrder.LayoutOrder
    local up=Instance.new("UIPadding",p)
    up.PaddingLeft=UDim.new(0,10); up.PaddingRight=UDim.new(0,10)
    up.PaddingTop=UDim.new(0,10); up.PaddingBottom=UDim.new(0,10)
    pages[name]=p; return p
end

local pageJalan  = mkPage("Jalan")
local pageRekam  = mkPage("Rekam")
local pagePath   = mkPage("Path")
local pageFolder = mkPage("Folder")
local pageBagikan= mkPage("Bagikan")

local activeTab=""
local navBtns={}

local function setTab(name)
    activeTab=name
    for _,p in pairs(pages) do p.Visible=false end
    if pages[name] then pages[name].Visible=true end
    for n,item in pairs(navBtns) do
        local on=n==name
        tw(item.btn,{BackgroundColor3=on and W.accent:Lerp(W.card,0.55) or W.card,
            TextColor3=on and W.accent or W.sub},0.15)
        item.bar.Visible=on
    end
end

local tabOrder={"Jalan","Rekam","Path","Folder","Bagikan"}
for i,name in ipairs(tabOrder) do
    local btn=Instance.new("TextButton")
    btn.Size=UDim2.new(1,0,0,36); btn.BackgroundColor3=W.card
    btn.Text=name; btn.Font=Enum.Font.GothamBold; btn.TextSize=11
    btn.TextColor3=W.sub; btn.AutoButtonColor=false
    btn.LayoutOrder=i; btn.Parent=sidebar; corner(btn,8)

    local bar=Instance.new("Frame")
    bar.AnchorPoint=Vector2.new(0,0.5); bar.Position=UDim2.new(0,0,0.5,0)
    bar.Size=UDim2.fromOffset(3,20); bar.BackgroundColor3=W.accent
    bar.BorderSizePixel=0; bar.Visible=false; bar.Parent=btn
    corner(bar,2)

    navBtns[name]={btn=btn,bar=bar}
    btn.MouseButton1Click:Connect(function() setTab(name) end)
end

-- ── Widget builders ───────────────────────────────────────────
local wo_counts={}
local function wo(page)
    wo_counts[page]=(wo_counts[page] or 0)+1
    return wo_counts[page]
end

local function row(page,h,col)
    local f=Instance.new("Frame")
    f.Size=UDim2.new(1,0,0,h); f.BackgroundColor3=col or W.card
    f.BorderSizePixel=0; f.LayoutOrder=wo(page); f.Parent=page
    corner(f,8); return f
end

local function secLbl(page,txt)
    local f=Instance.new("Frame"); f.Size=UDim2.new(1,0,0,16)
    f.BackgroundTransparency=1; f.LayoutOrder=wo(page); f.Parent=page
    local l=Instance.new("TextLabel"); l.BackgroundTransparency=1
    l.Size=UDim2.fromScale(1,1); l.Text=txt; l.Font=Enum.Font.GothamBold
    l.TextSize=9; l.TextColor3=W.sub; l.TextXAlignment=Enum.TextXAlignment.Left
    l.Parent=f
end

-- Status row (Warpah: label kiri + value kanan)
local function statRow(page,label,initVal)
    local f=row(page,32)
    local lf=Instance.new("TextLabel"); lf.BackgroundTransparency=1
    lf.Position=UDim2.fromOffset(10,0); lf.Size=UDim2.new(0.55,0,1,0)
    lf.Text=label; lf.Font=Enum.Font.Gotham; lf.TextSize=11
    lf.TextColor3=W.sub; lf.TextXAlignment=Enum.TextXAlignment.Left; lf.Parent=f
    local vf=Instance.new("TextLabel"); vf.BackgroundTransparency=1
    vf.AnchorPoint=Vector2.new(1,0.5); vf.Position=UDim2.new(1,-10,0.5,0)
    vf.Size=UDim2.new(0.44,0,1,0); vf.Text=initVal; vf.Font=Enum.Font.GothamBold
    vf.TextSize=11; vf.TextColor3=W.text
    vf.TextXAlignment=Enum.TextXAlignment.Right; vf.Parent=f
    return f,vf
end

-- Number input row
local function numRow(page,label,initVal,min,max,fmt,cb)
    local f=row(page,32)
    local lf=Instance.new("TextLabel"); lf.BackgroundTransparency=1
    lf.Position=UDim2.fromOffset(10,0); lf.Size=UDim2.new(0.55,0,1,0)
    lf.Text=label; lf.Font=Enum.Font.GothamBold; lf.TextSize=11
    lf.TextColor3=W.text; lf.TextXAlignment=Enum.TextXAlignment.Left; lf.Parent=f

    -- value box right side
    local vBox=Instance.new("Frame")
    vBox.AnchorPoint=Vector2.new(1,0.5); vBox.Position=UDim2.new(1,-8,0.5,0)
    vBox.Size=UDim2.fromOffset(80,24); vBox.BackgroundColor3=W.bg
    vBox.BorderSizePixel=0; vBox.Parent=f; corner(vBox,6); stroke(vBox,W.border,1)

    local vLbl=Instance.new("TextLabel"); vLbl.BackgroundTransparency=1
    vLbl.Size=UDim2.fromScale(1,1); vLbl.Text=string.format(fmt,initVal)
    vLbl.Font=Enum.Font.GothamBold; vLbl.TextSize=11; vLbl.TextColor3=W.accent
    vLbl.TextXAlignment=Enum.TextXAlignment.Center; vLbl.Parent=vBox

    -- − + buttons
    local function mkArrow(txt,xAnchor,xPos,delta)
        local b=Instance.new("TextButton"); b.AnchorPoint=Vector2.new(xAnchor,0.5)
        b.Position=UDim2.new(1,xPos,0.5,0); b.Size=UDim2.fromOffset(20,24)
        b.BackgroundColor3=W.card; b.Text=txt; b.Font=Enum.Font.GothamBold
        b.TextSize=12; b.TextColor3=W.accent; b.AutoButtonColor=false; b.Parent=f
        corner(b,6)
        local curVal=initVal
        b.MouseButton1Click:Connect(function()
            curVal=math.clamp(math.round((curVal+delta)*100)/100,min,max)
            vLbl.Text=string.format(fmt,curVal); cb(curVal)
        end)
        return b
    end
    mkArrow("−",1,-94,-0.1)
    mkArrow("+",1,-70, 0.1)
    return f,vLbl
end

local function bigBtn(page,txt,col,h)
    local b=Instance.new("TextButton")
    b.Size=UDim2.new(1,0,0,h or 36); b.BackgroundColor3=col
    b.Text=txt; b.Font=Enum.Font.GothamBold; b.TextSize=12
    b.TextColor3=W.text; b.AutoButtonColor=false
    b.LayoutOrder=wo(page); b.Parent=page; corner(b,8)
    b.MouseEnter:Connect(function() tw(b,{BackgroundColor3=col:Lerp(W.white,0.12)},0.1) end)
    b.MouseLeave:Connect(function() tw(b,{BackgroundColor3=col},0.1) end)
    return b
end

local function divider(page)
    local d=Instance.new("Frame"); d.Size=UDim2.new(1,0,0,1)
    d.BackgroundColor3=W.border; d.BorderSizePixel=0
    d.LayoutOrder=wo(page); d.Parent=page
end

-- ══════════════════════════════════════════════════════════════
--  TAB: JALAN
-- ══════════════════════════════════════════════════════════════
local walkBtnBig=bigBtn(pageJalan,"AUTO WALK",W.card,40)
walkBtnBig.TextColor3=W.sub
local _,statusVal=statRow(pageJalan,"Status","Ready to record!")
local _,folderVal=statRow(pageJalan,"Folder aktif",activeFolder)
local _,pathCntVal=statRow(pageJalan,"Jumlah path","0")

divider(pageJalan)
local _,speedRow=numRow(pageJalan,"Speed (0.1 - 5)",1,0.1,5,"%.1f",function(v)
    CFG.walkSpeed=v
end)
local _,animSpeedRow=numRow(pageJalan,"Speed Animasi (0.1 - 5)",1,0.1,5,"%.1f",function(v)
    CFG.animSpeed=v
    -- set animate playback speed
    local char=lp.Character
    if char then
        local animate=char:FindFirstChild("Animate")
        if animate then
            local ws=animate:FindFirstChild("walkspeed")
            if ws then
                local v2=ws:FindFirstChild("WalkAnimSpeed")
                if v2 then v2.Value=16*v end
            end
        end
    end
end)

divider(pageJalan)
bigBtn(pageJalan,"⏪  REWIND SEKARANG",W.accent,32).MouseButton1Click:Connect(doRewind)
bigBtn(pageJalan,"⏹  STOP PLAYBACK",W.card,32).TextColor3=W.red
-- wire stop
local stopPlayBtn=pageJalan:GetChildren()
for _,c in ipairs(pageJalan:GetChildren()) do
    if c:IsA("TextButton") and c.Text=="⏹  STOP PLAYBACK" then
        c.MouseButton1Click:Connect(stopPlayback)
    end
end

-- Walk toggle
local walkOn=false
walkBtnBig.MouseButton1Click:Connect(function()
    walkOn=not walkOn
    walkEnabled=walkOn
    if walkOn then
        startWalk()
        tw(walkBtnBig,{BackgroundColor3=W.green:Lerp(W.card,0.5),TextColor3=W.green},0.15)
        walkBtnBig.Text="● AUTO WALK  ON"
    else
        stopWalk()
        tw(walkBtnBig,{BackgroundColor3=W.card,TextColor3=W.sub},0.15)
        walkBtnBig.Text="AUTO WALK"
    end
end)

-- ══════════════════════════════════════════════════════════════
--  TAB: REKAM
-- ══════════════════════════════════════════════════════════════
local recBtnBig=bigBtn(pageRekam,"⏺  MULAI REKAM",W.red,40)
local _,recStatusVal=statRow(pageRekam,"Status rekaman","Idle")
local _,recDurVal=statRow(pageRekam,"Durasi","0.0 s")
local _,recFrameVal=statRow(pageRekam,"Frame terekam","0")
divider(pageRekam)
local saveBtnRekam=bigBtn(pageRekam,"💾  SIMPAN KE PATH",W.amber,36)

local recManual=false
recBtnBig.MouseButton1Click:Connect(function()
    recManual=not recManual
    if recManual then
        recFrames={}; recording=true
        startRec()
        recBtnBig.Text="⏹  STOP REKAM"
        tw(recBtnBig,{BackgroundColor3=W.sub},0.15)
        recStatusVal.Text="● Merekam..."
        recStatusVal.TextColor3=W.red
    else
        stopRec()
        recBtnBig.Text="⏺  MULAI REKAM"
        tw(recBtnBig,{BackgroundColor3=W.red},0.15)
        recStatusVal.Text="Selesai"
        recStatusVal.TextColor3=W.green
    end
end)

-- ══════════════════════════════════════════════════════════════
--  SAVE DIALOG (muncul saat tekan Simpan)
-- ══════════════════════════════════════════════════════════════
local dlg=Instance.new("Frame")
dlg.AnchorPoint=Vector2.new(0.5,0.5)
dlg.Position=UDim2.fromScale(0.5,0.5)
dlg.Size=UDim2.fromOffset(300,160)
dlg.BackgroundColor3=W.surface
dlg.BorderSizePixel=0; dlg.ZIndex=50; dlg.Visible=false; dlg.Parent=Main
corner(dlg,12); stroke(dlg,W.accent,1)

lbl(dlg,"Simpan Path",13,W.text,Enum.TextXAlignment.Left,
    UDim2.fromOffset(14,14),UDim2.fromOffset(200,20))
lbl(dlg,"Nama path:",10,W.sub,Enum.TextXAlignment.Left,
    UDim2.fromOffset(14,38),UDim2.fromOffset(200,16))

local nameBox=Instance.new("TextBox")
nameBox.Position=UDim2.fromOffset(14,58)
nameBox.Size=UDim2.new(1,-28,0,32)
nameBox.BackgroundColor3=W.card; nameBox.Text=""
nameBox.PlaceholderText="contoh: Rute 1"
nameBox.Font=Enum.Font.GothamBold; nameBox.TextSize=12
nameBox.TextColor3=W.text; nameBox.PlaceholderColor3=W.sub
nameBox.ClearTextOnFocus=false; nameBox.BorderSizePixel=0
nameBox.ZIndex=51; nameBox.Parent=dlg; corner(nameBox,8)
stroke(nameBox,W.border,1)
local nbp=Instance.new("UIPadding",nameBox)
nbp.PaddingLeft=UDim.new(0,8); nbp.PaddingRight=UDim.new(0,8)

local dlgSave=Instance.new("TextButton")
dlgSave.Position=UDim2.fromOffset(14,104)
dlgSave.Size=UDim2.new(0.5,-20,0,32)
dlgSave.BackgroundColor3=W.accent; dlgSave.Text="SIMPAN"
dlgSave.Font=Enum.Font.GothamBold; dlgSave.TextSize=12
dlgSave.TextColor3=W.bg; dlgSave.AutoButtonColor=false
dlgSave.ZIndex=51; dlgSave.Parent=dlg; corner(dlgSave,8)

local dlgCancel=Instance.new("TextButton")
dlgCancel.AnchorPoint=Vector2.new(1,0)
dlgCancel.Position=UDim2.new(1,-14,0,104)
dlgCancel.Size=UDim2.new(0.5,-20,0,32)
dlgCancel.BackgroundColor3=W.card; dlgCancel.Text="BATAL"
dlgCancel.Font=Enum.Font.GothamBold; dlgCancel.TextSize=12
dlgCancel.TextColor3=W.sub; dlgCancel.AutoButtonColor=false
dlgCancel.ZIndex=51; dlgCancel.Parent=dlg; corner(dlgCancel,8)
stroke(dlgCancel,W.border,1)
dlgCancel.MouseButton1Click:Connect(function() dlg.Visible=false end)

-- ══════════════════════════════════════════════════════════════
--  TAB: PATH  (list saved paths)
-- ══════════════════════════════════════════════════════════════
local pathListFrame=Instance.new("Frame")
pathListFrame.Size=UDim2.new(1,0,0,8)
pathListFrame.BackgroundTransparency=1
pathListFrame.LayoutOrder=1; pathListFrame.AutomaticSize=Enum.AutomaticSize.Y
pathListFrame.Parent=pagePath
local pathListLayout=Instance.new("UIListLayout",pathListFrame)
pathListLayout.Padding=UDim.new(0,6); pathListLayout.SortOrder=Enum.SortOrder.LayoutOrder

local emptyPathLbl=Instance.new("TextLabel")
emptyPathLbl.Size=UDim2.new(1,0,0,30); emptyPathLbl.BackgroundTransparency=1
emptyPathLbl.Text="Belum ada path tersimpan."
emptyPathLbl.Font=Enum.Font.Gotham; emptyPathLbl.TextSize=11
emptyPathLbl.TextColor3=W.sub; emptyPathLbl.TextXAlignment=Enum.TextXAlignment.Center
emptyPathLbl.Parent=pathListFrame

local pathOrder=0
local function addPathCard(slot,idx)
    pathOrder+=1
    emptyPathLbl.Visible=false
    local card=Instance.new("Frame")
    card.Size=UDim2.new(1,0,0,62); card.BackgroundColor3=W.card
    card.BorderSizePixel=0; card.LayoutOrder=pathOrder; card.Parent=pathListFrame
    corner(card,8); stroke(card,W.border,1)

    local icon2=Instance.new("Frame")
    icon2.Position=UDim2.fromOffset(8,10)
    icon2.Size=UDim2.fromOffset(28,28)
    icon2.BackgroundColor3=W.border; icon2.BorderSizePixel=0
    icon2.Parent=card; corner(icon2,6)
    lbl(icon2,"▶",12,W.accent,Enum.TextXAlignment.Center)

    lbl(card,slot.name,12,W.text,Enum.TextXAlignment.Left,
        UDim2.fromOffset(44,8),UDim2.new(1,-50,0,18))
    lbl(card,string.format("%.1fs  •  %d frame  •  %s",slot.dur,#slot.frames,slot.folder),
        10,W.sub,Enum.TextXAlignment.Left,
        UDim2.fromOffset(44,28),UDim2.new(1,-50,0,14))

    local function mini(txt,col2,xOff)
        local b=Instance.new("TextButton"); b.AnchorPoint=Vector2.new(1,1)
        b.Position=UDim2.new(1,-xOff,1,-8); b.Size=UDim2.fromOffset(46,22)
        b.BackgroundColor3=col2; b.Text=txt; b.Font=Enum.Font.GothamBold
        b.TextSize=10; b.TextColor3=W.text; b.AutoButtonColor=false
        b.Parent=card; corner(b,6)
        b.MouseEnter:Connect(function() tw(b,{BackgroundColor3=col2:Lerp(W.white,0.15)},0.1) end)
        b.MouseLeave:Connect(function() tw(b,{BackgroundColor3=col2},0.1) end)
        return b
    end
    local pb=mini("▶ PLAY",W.green,100)
    local rb=mini("⏪ REW",Color3.fromRGB(140,90,255),50)
    local db=mini("✕ DEL",W.red,2)

    pb.MouseButton1Click:Connect(function() startPlayback(slot.frames,playSpeed) end)
    rb.MouseButton1Click:Connect(function()
        local rev={}; local n=#slot.frames; local t0=slot.frames[1].t
        for i=n,1,-1 do table.insert(rev,{cf=slot.frames[i].cf,t=t0+(slot.frames[n].t-slot.frames[i].t)}) end
        startPlayback(rev,playSpeed)
    end)
    db.MouseButton1Click:Connect(function()
        table.remove(paths,idx); card:Destroy()
        pathCntVal.Text=tostring(#paths)
        if #paths==0 then emptyPathLbl.Visible=true end
    end)
end

-- Save dialog confirm
local pendingFrames=nil
local function openSaveDialog()
    if #recFrames<2 then return end
    pendingFrames={}
    for _,f in ipairs(recFrames) do table.insert(pendingFrames,f) end
    nameBox.Text="Path "..(#paths+1)
    dlg.Visible=true
end

saveBtnRekam.MouseButton1Click:Connect(openSaveDialog)

dlgSave.MouseButton1Click:Connect(function()
    if not pendingFrames or #pendingFrames<2 then dlg.Visible=false; return end
    local name=nameBox.Text~="" and nameBox.Text or ("Path "..(#paths+1))
    local dur=pendingFrames[#pendingFrames].t-pendingFrames[1].t
    local slot={name=name,frames=pendingFrames,dur=dur,folder=activeFolder}
    table.insert(paths,slot)
    addPathCard(slot,#paths)
    pathCntVal.Text=tostring(#paths)
    dlg.Visible=false; pendingFrames=nil
    -- switch to path tab
    setTab("Path")
end)

-- ══════════════════════════════════════════════════════════════
--  TAB: FOLDER
-- ══════════════════════════════════════════════════════════════
local folderListF=Instance.new("Frame")
folderListF.Size=UDim2.new(1,0,0,8); folderListF.BackgroundTransparency=1
folderListF.LayoutOrder=1; folderListF.AutomaticSize=Enum.AutomaticSize.Y
folderListF.Parent=pageFolder
local folderListL=Instance.new("UIListLayout",folderListF)
folderListL.Padding=UDim.new(0,6); folderListL.SortOrder=Enum.SortOrder.LayoutOrder

local newFolderBtn=bigBtn(pageFolder,"+ Buat Folder Baru",W.accent,34)
newFolderBtn.LayoutOrder=0

local folderDialogVisible=false
local folderDlg=Instance.new("Frame")
folderDlg.AnchorPoint=Vector2.new(0.5,0.5)
folderDlg.Position=UDim2.fromScale(0.5,0.5)
folderDlg.Size=UDim2.fromOffset(280,130)
folderDlg.BackgroundColor3=W.surface; folderDlg.BorderSizePixel=0
folderDlg.ZIndex=50; folderDlg.Visible=false; folderDlg.Parent=Main
corner(folderDlg,12); stroke(folderDlg,W.accent,1)
lbl(folderDlg,"Nama folder baru:",11,W.sub,Enum.TextXAlignment.Left,
    UDim2.fromOffset(14,14),UDim2.fromOffset(200,16))
local folderBox=Instance.new("TextBox")
folderBox.Position=UDim2.fromOffset(14,36)
folderBox.Size=UDim2.new(1,-28,0,32)
folderBox.BackgroundColor3=W.card; folderBox.Text=""
folderBox.PlaceholderText="Nama folder"; folderBox.Font=Enum.Font.GothamBold
folderBox.TextSize=12; folderBox.TextColor3=W.text
folderBox.PlaceholderColor3=W.sub; folderBox.ClearTextOnFocus=false
folderBox.BorderSizePixel=0; folderBox.ZIndex=51; folderBox.Parent=folderDlg
corner(folderBox,8); stroke(folderBox,W.border,1)
local fbp=Instance.new("UIPadding",folderBox)
fbp.PaddingLeft=UDim.new(0,8)

local fdSave=Instance.new("TextButton")
fdSave.Position=UDim2.fromOffset(14,80); fdSave.Size=UDim2.new(0.5,-20,0,30)
fdSave.BackgroundColor3=W.accent; fdSave.Text="BUAT"
fdSave.Font=Enum.Font.GothamBold; fdSave.TextSize=12
fdSave.TextColor3=W.bg; fdSave.AutoButtonColor=false; fdSave.ZIndex=51
fdSave.Parent=folderDlg; corner(fdSave,8)
local fdCancel=Instance.new("TextButton")
fdCancel.AnchorPoint=Vector2.new(1,0); fdCancel.Position=UDim2.new(1,-14,0,80)
fdCancel.Size=UDim2.new(0.5,-20,0,30); fdCancel.BackgroundColor3=W.card
fdCancel.Text="BATAL"; fdCancel.Font=Enum.Font.GothamBold; fdCancel.TextSize=12
fdCancel.TextColor3=W.sub; fdCancel.AutoButtonColor=false; fdCancel.ZIndex=51
fdCancel.Parent=folderDlg; corner(fdCancel,8); stroke(fdCancel,W.border,1)
fdCancel.MouseButton1Click:Connect(function() folderDlg.Visible=false end)

local function addFolderCard(name)
    local card=Instance.new("Frame")
    card.Size=UDim2.new(1,0,0,36); card.BackgroundColor3=W.card
    card.BorderSizePixel=0; card.Parent=folderListF; corner(card,8)
    stroke(card,W.border,1)
    lbl(card,"📁  "..name,11,W.text,Enum.TextXAlignment.Left,
        UDim2.fromOffset(10,0),UDim2.new(0.6,0,1,0))
    local selBtn=Instance.new("TextButton")
    selBtn.AnchorPoint=Vector2.new(1,0.5); selBtn.Position=UDim2.new(1,-8,0.5,0)
    selBtn.Size=UDim2.fromOffset(60,24); selBtn.BackgroundColor3=
        (name==activeFolder) and W.accent or W.border
    selBtn.Text=(name==activeFolder) and "Aktif" or "Pilih"
    selBtn.Font=Enum.Font.GothamBold; selBtn.TextSize=10
    selBtn.TextColor3=(name==activeFolder) and W.bg or W.text
    selBtn.AutoButtonColor=false; selBtn.Parent=card; corner(selBtn,6)
    selBtn.MouseButton1Click:Connect(function()
        activeFolder=name
        folderVal.Text=name
        -- refresh all folder cards
        for _,c in ipairs(folderListF:GetChildren()) do
            if c:IsA("Frame") then
                local b=c:FindFirstChildOfClass("TextButton")
                if b then
                    local nm=c:FindFirstChildOfClass("TextLabel")
                    local isActive=(nm and string.find(nm.Text,name) ~= nil)
                    tw(b,{BackgroundColor3=isActive and W.accent or W.border},0.15)
                    b.TextColor3=isActive and W.bg or W.text
                    b.Text=isActive and "Aktif" or "Pilih"
                end
            end
        end
    end)
end

fdSave.MouseButton1Click:Connect(function()
    local name=folderBox.Text~="" and folderBox.Text or ("Folder "..(#folders+1))
    table.insert(folders,name); addFolderCard(name)
    folderDlg.Visible=false
end)

newFolderBtn.MouseButton1Click:Connect(function()
    folderBox.Text=""; folderDlg.Visible=true
end)

-- Default folder card
addFolderCard("Default")

-- ══════════════════════════════════════════════════════════════
--  TAB: BAGIKAN
-- ══════════════════════════════════════════════════════════════
secLbl(pageBagikan,"BAGIKAN PATH")
local shareRow=row(pageBagikan,80,W.card)
lbl(shareRow,"Raw GitHub URL",11,W.sub,Enum.TextXAlignment.Left,
    UDim2.fromOffset(10,8),UDim2.new(1,-20,0,16))
local urlBox=Instance.new("TextBox")
urlBox.Position=UDim2.fromOffset(10,28); urlBox.Size=UDim2.new(1,-20,0,32)
urlBox.BackgroundColor3=W.bg; urlBox.Text=""
urlBox.PlaceholderText="https://raw.githubusercontent.com/..."
urlBox.Font=Enum.Font.Code; urlBox.TextSize=10
urlBox.TextColor3=W.accent; urlBox.PlaceholderColor3=W.sub
urlBox.ClearTextOnFocus=false; urlBox.BorderSizePixel=0
urlBox.Parent=shareRow; corner(urlBox,6); stroke(urlBox,W.border,1)
local ubp=Instance.new("UIPadding",urlBox); ubp.PaddingLeft=UDim.new(0,6)
bigBtn(pageBagikan,"📋  Copy loadstring ke clipboard",W.card,32).TextColor3=W.accent

-- ══════════════════════════════════════════════════════════════
--  FPS / PING UPDATE + STATUS UPDATE
-- ══════════════════════════════════════════════════════════════
local lastFPSUpdate=0
local frameCount=0
RunService.Heartbeat:Connect(function()
    frameCount+=1
    local now=tick()

    -- FPS
    if now-lastFPSUpdate>=1 then
        fpsLbl.Text="FPS: "..frameCount
        frameCount=0; lastFPSUpdate=now
    end

    -- Status update (Jalan tab)
    local hum=getHum()
    if walkEnabled then
        statusVal.Text="● Walking"
        statusVal.TextColor3=W.green
    elseif playing then
        statusVal.Text="▶ Playback"
        statusVal.TextColor3=W.accent
    else
        statusVal.Text="Ready to record!"
        statusVal.TextColor3=W.sub
    end

    -- Rekam tab live
    if recording or recManual then
        local n=#recFrames
        recFrameVal.Text=tostring(n)
        if n>1 then
            local dur=recFrames[n].t-recFrames[1].t
            recDurVal.Text=string.format("%.1f s",dur)
        end
    end
end)

-- Hotkeys
UserInputService.InputBegan:Connect(function(inp,gp)
    if gp then return end
    if inp.KeyCode==Enum.KeyCode.F then
        walkBtnBig:GetPropertyChangedSignal("Text") -- trigger click
        walkBtnBig.MouseButton1Click:Fire()
    elseif inp.KeyCode==Enum.KeyCode.R then doRewind()
    elseif inp.KeyCode==Enum.KeyCode.RightShift then
        Main.Visible=not Main.Visible
    end
end)

-- ══════════════════════════════════════════════════════════════
--  LAUNCH LOADING ANIMATION → show main
-- ══════════════════════════════════════════════════════════════
local function runLoader()
    local step=0
    local function next()
        step+=1
        if step>#loadSteps then
            -- done
            task.delay(0.3,function()
                tw(loadCard,{BackgroundTransparency=1},0.4)
                for _,c in ipairs(loadCard:GetDescendants()) do
                    if c:IsA("GuiObject") then
                        tw(c,{BackgroundTransparency=1},0.3)
                        if c:IsA("TextLabel") then
                            tw(c,{TextTransparency=1},0.3)
                        end
                    end
                end
                task.delay(0.5,function()
                    loadCard:Destroy()
                    Main.Visible=true
                    setTab("Jalan")
                    tw(Main,{Position=UDim2.fromOffset(60,80)},0.4,Enum.EasingStyle.Back)
                end)
            end)
            return
        end
        local s=loadSteps[step]
        tw(progFill,{Size=UDim2.new(s[1],0,1,0)},0.3,Enum.EasingStyle.Sine)
        pctLbl.Text=math.floor(s[1]*100).."%"
        statusLbl2.Text=s[2]
        task.delay(0.32,next)
    end
    next()
end

task.delay(0.5,runLoader)

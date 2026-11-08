--[[
  Rice & Mango -> Farm & Trunk Macro (v21 watchdog)
  อัปเดต:
   1) โลโก้: ย้ายไปอยู่เลเยอร์หน้าสุด (นอกกรอบ UI) + โหลดสำรอง rbxthumb + มีสัญลักษณ์สำรองถ้าโหลดไม่ได้
   2) กด MAX ก่อน Confirm จริงจัง: รอให้ปุ่มโผล่ -> กดแล้วตรวจผล -> ถ้าไม่ติดจะใส่ตัวเลขลงช่องจำนวนเอง
   3) พื้นหลัง UI ใหม่: ไล่สีหลายชั้น มีเงา แสงสะท้อนด้านบน เงาด้านล่าง ขอบใน เปลี่ยนสีตามโหมดฟาร์ม
]]

local Players = game:GetService("Players")
local VIM = game:GetService("VirtualInputManager")
local UIS = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local ContentProvider = game:GetService("ContentProvider")

local LP = Players.LocalPlayer
local PG = LP:WaitForChild("PlayerGui")

local LOGO_ID    = "rbxassetid://76441169372717"
local LOGO_THUMB = "rbxthumb://type=Asset&id=76441169372717&w=420&h=420"

local MODES = {
	Rice = {
		NAME            = "RICE FARM",
		TITLE_IMAGE     = "rbxassetid://88785356794457",
		ITEM            = "Rice",
		ICON            = "rbxassetid://100600116558646",
		MAX_COUNT       = 60,
		FROM            = "Inventory",
		USE_MAX         = true,
		FARM_PATH       = { "Systems", "Farm", "Rice", "Prompt", "Farm" },
		SPAWN_FOLDER    = { "Systems", "Farm", "Rice", "Prompt", "Spawn" },
		PRIMARY_COLOR   = Color3.fromRGB(0, 200, 255),
		SECONDARY_COLOR = Color3.fromRGB(40, 90, 255),
		ACCENT_COLOR    = Color3.fromRGB(170, 240, 255),
		BG_COLORS       = { Color3.fromRGB(110, 225, 255), Color3.fromRGB(40, 150, 255), Color3.fromRGB(35, 80, 225) },
		RUN_COLOR       = Color3.fromRGB(0, 255, 170),
		IDLE_GRADIENT   = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(0, 170, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(40, 80, 220)),
		}),
	},
	Mango = {
		NAME            = "MANGO FARM",
		TITLE_IMAGE     = "rbxassetid://76426104107133",
		ITEM            = "Mango",
		ICON            = "rbxassetid://124088933252520",
		MAX_COUNT       = 60,
		FROM            = "Inventory",
		USE_MAX         = true,
		FARM_PATH       = { "Systems", "Farm", "Mango", "Prompt", "Farm" },
		SPAWN_FOLDER    = { "Systems", "Farm", "Mango", "Prompt", "Spawn" },
		PRIMARY_COLOR   = Color3.fromRGB(255, 170, 0),
		SECONDARY_COLOR = Color3.fromRGB(255, 90, 0),
		ACCENT_COLOR    = Color3.fromRGB(255, 230, 150),
		BG_COLORS       = { Color3.fromRGB(255, 214, 60), Color3.fromRGB(255, 154, 25), Color3.fromRGB(235, 90, 12) },
		RUN_COLOR       = Color3.fromRGB(255, 220, 0),
		IDLE_GRADIENT   = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 170, 0)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(220, 70, 0)),
		}),
	}
}

local currentModeKey = "Rice"
local CONFIG = MODES[currentModeKey]

local SETTINGS = {
	LOOP_DELAY      = 0.1,
	FARM_WAIT       = 3,
	FAIL_LIMIT      = 5,
	AUTO_OPEN       = true,
	AUTO_RUN        = true,   -- กดปุ่มวิ่ง (PlayerGui.Button.Run) อัตโนมัติ
	TRUNK_TEXT      = "TRUNK",
	WALK_TIMEOUT    = 90,
	PROMPT_TRIES    = 3,
	SWAY_MIN        = 3.5,
	SWAY_MAX        = 8.5,
}

local running = false
local lastKnown = nil
local temporarilyDisabled = {}
local rng = Random.new()

local function child(obj, ...)
	for _, n in ipairs({ ... }) do
		if not obj then return nil end
		obj = obj:FindFirstChild(n)
	end
	return obj
end

local function refs()
	local group = child(PG, "Car_Storage", "Group")
	local main = child(group, "Main")
	local menu = child(main, "Menu")
	local mm = menu and child(menu, "Main")
	return {
		group = group,
		main = main,
		itemName = mm and child(mm, "ItemName"),
		max = mm and child(mm, "Function", "Max"),
		confirm = mm and child(mm, "Button", "Confirm"),
		cancel = mm and child(mm, "Button", "Cancel"),
	}
end

local function numFrom(text)
	return tonumber(tostring(text):match("%d+"))
end

local function isShown(o)
	if not o then return false end
	while o and o:IsA("GuiObject") do
		if not o.Visible then return false end
		o = o.Parent
	end
	return true
end

local function restoreAllBlockedGuis()
	for o, _ in pairs(temporarilyDisabled) do
		if o and o.Parent then
			pcall(function() o.Active = true end)
		end
		temporarilyDisabled[o] = nil
	end
end

local function clearStuckBlur()
	local g = child(PG, "Car_Storage", "Group")
	if g and g.Visible then return end
	local function unblur(parent)
		if not parent then return end
		for _, fx in ipairs(parent:GetChildren()) do
			if fx:IsA("BlurEffect") and fx.Size > 0 then
				pcall(function() fx.Size = 0 end)
			end
		end
	end
	unblur(Lighting)
	unblur(workspace.CurrentCamera)
end

-- ===================================================== ตรวจโหมดฟาร์มที่ใกล้ที่สุดอัตโนมัติ
local function autoDetectNearestMode()
	local char = LP.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local ricePart = child(workspace, table.unpack(MODES.Rice.FARM_PATH))
	local mangoPart = child(workspace, table.unpack(MODES.Mango.FARM_PATH))

	local riceDist = ricePart and (hrp.Position - (ricePart:IsA("BasePart") and ricePart.Position or ricePart:GetPivot().Position)).Magnitude or math.huge
	local mangoDist = mangoPart and (hrp.Position - (mangoPart:IsA("BasePart") and mangoPart.Position or mangoPart:GetPivot().Position)).Magnitude or math.huge

	local nearest = (mangoDist < riceDist) and "Mango" or "Rice"
	if nearest ~= currentModeKey then
		currentModeKey = nearest
		CONFIG = MODES[currentModeKey]
	end
end

-- ===================================================== นับไอเทม
local function countFromInventory()
	local sf = child(PG, "Inventory", "Group", "Frame", "ScrollingFrame")
	if not sf then return nil end
	local slot = sf:FindFirstChild(CONFIG.ITEM)
	if not slot then return 0 end
	local items = slot:FindFirstChild("items")
	if items and items.Text ~= "" then
		local n = numFrom(items.Text)
		if n then return n end
	end
	for _, d in ipairs(slot:GetDescendants()) do
		if d:IsA("TextLabel") or d:IsA("TextButton") then
			local t = d.Text
			if t:match("^%s*%d+%s*|%s*%d+%s*$") or t:match("^%s*[xX]?%d+%s*$") then
				return numFrom(t)
			end
		end
	end
	return nil
end

local function countFromTools()
	local total, found = 0, false
	local function scan(container)
		if not container then return end
		for _, t in ipairs(container:GetChildren()) do
			if t:IsA("Tool") and t.Name == CONFIG.ITEM then
				found = true
				total += numFrom(t.Name) or 1
			end
		end
	end
	scan(LP:FindFirstChild("Backpack"))
	scan(LP.Character)
	return found and total or nil
end

local function countFromStorageGui()
	local r = refs()
	if not (r.group and r.group.Visible) then return nil end
	local slot = child(r.main, "Scrolling", CONFIG.FROM, "Scrolling", CONFIG.ITEM)
	if not slot then return 0 end
	local lbl = child(slot, "Holder", "items") or child(slot, "items")
	if lbl and lbl.Text ~= "" then return numFrom(lbl.Text) or 0 end
	return 0
end

local function getItemCount()
	local sources = {
		{ "Inventory", countFromInventory },
		{ "Tool", countFromTools },
		{ "Trunk GUI", countFromStorageGui },
	}
	for _, s in ipairs(sources) do
		local ok, n = pcall(s[2])
		if ok and n then
			lastKnown = n
			return n, s[1]
		end
	end
	return nil, "-"
end

-- ===================================================== UI หลัก
local parentGui = (gethui and gethui()) or PG
local old = parentGui:FindFirstChild("RiceMacroUI")
if old then old:Destroy() end

local BG = Color3.fromRGB(7, 11, 22)

local gui = Instance.new("ScreenGui")
gui.Name = "RiceMacroUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 99999
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = parentGui

local function corner(p, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = p
	return c
end

local function dynamicGradient(parent)
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0,    CONFIG.PRIMARY_COLOR),
		ColorSequenceKeypoint.new(0.35, CONFIG.SECONDARY_COLOR),
		ColorSequenceKeypoint.new(0.7,  CONFIG.ACCENT_COLOR),
		ColorSequenceKeypoint.new(1,    CONFIG.PRIMARY_COLOR),
	})
	g.Parent = parent
	return g
end

local function makeLabel(parent, x, y, w, h, size, font, color, text)
	local l = Instance.new("TextLabel")
	l.Size = UDim2.new(w, 0, 0, h)
	l.Position = UDim2.fromOffset(x, y)
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextColor3 = color
	l.Font = font
	l.TextSize = size
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Parent = parent
	return l
end

local root = Instance.new("Frame")
root.Size = UDim2.fromOffset(250, 122)
root.Position = UDim2.new(1, -260, 0, 40)
root.BackgroundTransparency = 1
root.Parent = gui

-- เงาตกพื้น (ให้ UI ลอยขึ้นมา)
local shadow = Instance.new("Frame")
shadow.Size = UDim2.new(1, 8, 1, 8)
shadow.Position = UDim2.fromOffset(-4, 4)
shadow.BackgroundColor3 = Color3.new(0, 0, 0)
shadow.BackgroundTransparency = 0.55
shadow.BorderSizePixel = 0
shadow.Active = false
shadow.ZIndex = 0
shadow.Parent = root
local shadowCorner = corner(shadow, 18)

local glow = Instance.new("Frame")
glow.Size = UDim2.new(1, 12, 1, 12)
glow.Position = UDim2.fromOffset(-6, -6)
glow.BackgroundColor3 = Color3.new(1, 1, 1)
glow.BackgroundTransparency = 0.8
glow.BorderSizePixel = 0
glow.Active = false
glow.ZIndex = 1
glow.Parent = root
local glowCorner = corner(glow, 20)
local glowGrad = dynamicGradient(glow)

local frame = Instance.new("Frame")
frame.Size = UDim2.fromScale(1, 1)
frame.BackgroundColor3 = Color3.new(1, 1, 1)
frame.BorderSizePixel = 0
frame.Active = true
frame.ClipsDescendants = true
frame.ZIndex = 2
frame.Parent = root
local frameCorner = corner(frame, 14)

-- พื้นหลังไล่สีหลายชั้น (ปรับสีตามโหมดใน updateThemeVisuals)
local bgGrad = Instance.new("UIGradient")
bgGrad.Rotation = 58
bgGrad.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0,    Color3.fromRGB(40, 70, 140)),
	ColorSequenceKeypoint.new(0.45, BG),
	ColorSequenceKeypoint.new(1,    Color3.fromRGB(12, 20, 50)),
})
bgGrad.Parent = frame

-- แสงสีธีมจากมุมซ้ายบน
local tint = Instance.new("Frame")
tint.Size = UDim2.fromScale(1, 1)
tint.BackgroundColor3 = CONFIG.PRIMARY_COLOR
tint.BorderSizePixel = 0
tint.Active = false
tint.Parent = frame
corner(tint, 14)
local tintGrad = Instance.new("UIGradient")
tintGrad.Rotation = 35
tintGrad.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0,    0.6),
	NumberSequenceKeypoint.new(0.5,  0.92),
	NumberSequenceKeypoint.new(1,    1),
})
tintGrad.Parent = tint

-- แสงสีรองจากมุมขวาล่าง (ทำให้พื้นไล่สีสองฝั่ง)
local aurora = Instance.new("Frame")
aurora.Size = UDim2.fromScale(1, 1)
aurora.BackgroundColor3 = CONFIG.SECONDARY_COLOR
aurora.BorderSizePixel = 0
aurora.Active = false
aurora.Parent = frame
corner(aurora, 14)
local auroraGrad = Instance.new("UIGradient")
auroraGrad.Rotation = 215
auroraGrad.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0,    0.62),
	NumberSequenceKeypoint.new(0.55, 0.93),
	NumberSequenceKeypoint.new(1,    1),
})
auroraGrad.Parent = aurora

-- แสงวิ่งผ่านทแยง (shine)
local sweep = Instance.new("Frame")
sweep.Size = UDim2.new(0, 46, 1.8, 0)
sweep.AnchorPoint = Vector2.new(0.5, 0.5)
sweep.Position = UDim2.new(0, -60, 0.5, 0)
sweep.Rotation = 22
sweep.BackgroundColor3 = Color3.new(1, 1, 1)
sweep.BorderSizePixel = 0
sweep.Active = false
sweep.Parent = frame
local sweepGrad = Instance.new("UIGradient")
sweepGrad.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0,   1),
	NumberSequenceKeypoint.new(0.5, 0.88),
	NumberSequenceKeypoint.new(1,   1),
})
sweepGrad.Parent = sweep

-- แสงสะท้อนด้านบน (glass)
local gloss = Instance.new("Frame")
gloss.Size = UDim2.new(1, 0, 0.5, 0)
gloss.BackgroundColor3 = Color3.new(1, 1, 1)
gloss.BorderSizePixel = 0
gloss.Active = false
gloss.Parent = frame
corner(gloss, 14)
local glossGrad = Instance.new("UIGradient")
glossGrad.Rotation = 90
glossGrad.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.8),
	NumberSequenceKeypoint.new(1, 1),
})
glossGrad.Parent = gloss

-- เงาด้านล่างบางๆ ให้มีมิติ
local bottomShade = Instance.new("Frame")
bottomShade.Size = UDim2.new(1, 0, 0.4, 0)
bottomShade.Position = UDim2.fromScale(0, 0.6)
bottomShade.BackgroundColor3 = Color3.new(0, 0, 0)
bottomShade.BorderSizePixel = 0
bottomShade.Active = false
bottomShade.Parent = frame
corner(bottomShade, 14)
local shadeGrad = Instance.new("UIGradient")
shadeGrad.Rotation = 90
shadeGrad.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(1, 0.8),
})
shadeGrad.Parent = bottomShade

-- ขอบในบางๆ
local innerRim = Instance.new("Frame")
innerRim.Size = UDim2.new(1, -6, 1, -6)
innerRim.Position = UDim2.fromOffset(3, 3)
innerRim.BackgroundTransparency = 1
innerRim.BorderSizePixel = 0
innerRim.Active = false
innerRim.Parent = frame
corner(innerRim, 11)
local rimStroke = Instance.new("UIStroke")
rimStroke.Thickness = 1
rimStroke.Color = Color3.new(1, 1, 1)
rimStroke.Transparency = 0.85
rimStroke.Parent = innerRim

local stroke = Instance.new("UIStroke")
stroke.Thickness = 2
stroke.Color = Color3.new(1, 1, 1)
stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
stroke.Parent = frame
local strokeGrad = dynamicGradient(stroke)

-- ลากด้วยเมาส์/ทัช
do
	local dragging, startInput, startPos
	frame.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			dragging, startInput, startPos = true, i.Position, root.Position
			i.Changed:Connect(function()
				if i.UserInputState == Enum.UserInputState.End then dragging = false end
			end)
		end
	end)
	UIS.InputChanged:Connect(function(i)
		if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
			local d = i.Position - startInput
			root.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
		end
	end)
end

local resolved = {}
local function resolveImage(id)
	if resolved[id] then return resolved[id] end
	local out = id
	pcall(function()
		local objs = game:GetObjects(id) -- ถ้าเป็นไอดี Decal จะดึงไอดีรูปจริงออกมา
		for _, o in ipairs(objs or {}) do
			if (o:IsA("Decal") or o:IsA("Texture")) and o.Texture ~= "" then out = o.Texture end
			pcall(function() o:Destroy() end)
		end
	end)
	resolved[id] = out
	return out
end

-- ===================================================== โลโก้ (ชิดมุมซ้ายบน แตะเพื่อสลับข้าง)
local logoBox = Instance.new("Frame")
logoBox.Size = UDim2.fromOffset(70, 39)
logoBox.Position = UDim2.fromOffset(3, 0)
logoBox.BackgroundTransparency = 1
logoBox.BorderSizePixel = 0
logoBox.Active = false
logoBox.ZIndex = 50
logoBox.Parent = root

local logoImg = Instance.new("ImageLabel")
logoImg.Size = UDim2.fromScale(1, 1)
logoImg.BackgroundTransparency = 1
logoImg.BorderSizePixel = 0
logoImg.Image = LOGO_ID
logoImg.ImageTransparency = 0
logoImg.ImageColor3 = Color3.new(1, 1, 1)
logoImg.ScaleType = Enum.ScaleType.Fit
logoImg.ZIndex = 51
logoImg.Parent = logoBox

-- ประกายวิ่งผ่านโลโก้ (ไล่สีเลื่อนไปมา)
local logoGrad = Instance.new("UIGradient")
logoGrad.Rotation = 20
logoGrad.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0,    Color3.fromRGB(205, 205, 205)),
	ColorSequenceKeypoint.new(0.45, Color3.fromRGB(255, 255, 255)),
	ColorSequenceKeypoint.new(0.55, Color3.fromRGB(255, 255, 255)),
	ColorSequenceKeypoint.new(1,    Color3.fromRGB(205, 205, 205)),
})
logoGrad.Parent = logoImg

local logoScale = Instance.new("UIScale")
logoScale.Parent = logoBox

-- ปุ่มโปร่งใสให้แตะที่โลโก้
local logoHit = Instance.new("TextButton")
logoHit.Size = UDim2.fromScale(1, 1)
logoHit.BackgroundTransparency = 1
logoHit.Text = ""
logoHit.AutoButtonColor = false
logoHit.ZIndex = 60
logoHit.Parent = logoBox

local logoFallback = Instance.new("TextLabel")
logoFallback.Size = UDim2.fromScale(1, 1)
logoFallback.BackgroundTransparency = 1
logoFallback.Text = "◆ FARM"
logoFallback.TextColor3 = CONFIG.ACCENT_COLOR
logoFallback.Font = Enum.Font.GothamBold
logoFallback.TextSize = 12
logoFallback.TextXAlignment = Enum.TextXAlignment.Left
logoFallback.Visible = false
logoFallback.ZIndex = 52
logoFallback.Parent = logoBox

task.spawn(function()
	local function waitLoaded(t)
		local t0 = os.clock()
		while os.clock() - t0 < t do
			if logoImg.IsLoaded then return true end
			task.wait(0.1)
		end
		return logoImg.IsLoaded
	end
	local real = resolveImage(LOGO_ID)
	if real ~= LOGO_ID then logoImg.Image = real end
	pcall(function() ContentProvider:PreloadAsync({ logoImg }) end)
	if waitLoaded(2) then return end
	logoImg.Image = LOGO_THUMB
	if waitLoaded(4) then return end
	logoFallback.Visible = true
end)

local titleLbl = makeLabel(frame, 112, 5, 1, 14, 10, Enum.Font.GothamBold, CONFIG.ACCENT_COLOR, "")

-- รูปชื่อฟาร์ม (แทนข้อความ) วางที่เลเยอร์หน้าสุดเหมือนโลโก้
local titleImg = Instance.new("ImageLabel")
titleImg.Size = UDim2.fromOffset(104, 37)
titleImg.Position = UDim2.fromOffset(80, 1)
titleImg.BackgroundTransparency = 1
titleImg.BorderSizePixel = 0
titleImg.ScaleType = Enum.ScaleType.Fit
titleImg.ZIndex = 53
titleImg.Active = false
titleImg.Parent = root

local function thumbOf(id)
	local n = tostring(id):match("%d+")
	return "rbxthumb://type=Asset&id=" .. n .. "&w=420&h=420"
end

local titleToken = 0
local function loadTitleImage()
	titleToken += 1
	local my = titleToken
	local img = CONFIG.TITLE_IMAGE
	titleLbl.Text = ""
	titleImg.Image = img
	task.spawn(function()
		local real = resolveImage(img)
		if my ~= titleToken then return end
		titleImg.Image = real
		local function waitLoaded(t)
			local t0 = os.clock()
			while os.clock() - t0 < t do
				if my ~= titleToken then return true end
				if titleImg.IsLoaded then return true end
				task.wait(0.1)
			end
			return titleImg.IsLoaded
		end
		pcall(function() ContentProvider:PreloadAsync({ titleImg }) end)
		if waitLoaded(2) then return end
		titleImg.Image = thumbOf(img) -- สำรอง: thumbnail
		if waitLoaded(4) then return end
		if my == titleToken then titleLbl.Text = CONFIG.NAME end -- สำรองสุดท้าย
	end)
end
loadTitleImage()

-- ให้รูปแสดง/ซ่อนตามโลโก้ (โหมดย่อจะซ่อนทั้งคู่)
titleImg.Visible = logoBox.Visible
logoBox:GetPropertyChangedSignal("Visible"):Connect(function()
	titleImg.Visible = logoBox.Visible
end)

local titleScale = Instance.new("UIScale")
titleScale.Parent = titleImg

-- ตำแหน่งสองข้าง: โลโก้ชิดซ้าย <-> โลโก้ไปขวา (ป้ายมาแทนที่ซ้าย)
local HEADER = {
	left  = { logo = UDim2.fromOffset(3, 0),   title = UDim2.fromOffset(80, 1) },
	right = { logo = UDim2.fromOffset(114, 0), title = UDim2.fromOffset(4, 1) },
}
local headerSide = "left"
local swapping = false

local function placeHeader(side, animate)
	local p = HEADER[side]
	if not animate then
		logoBox.Position = p.logo
		titleImg.Position = p.title
		return
	end
	local ti = TweenInfo.new(0.55, Enum.EasingStyle.Quint, Enum.EasingDirection.InOut)
	TweenService:Create(logoBox, ti, { Position = p.logo }):Play()
	TweenService:Create(titleImg, ti, { Position = p.title }):Play()
end

-- ประกาย + วงกระเพื่อม ตรงจุดที่กำหนด (พิกัดใน root)
local function burst(cx, cy, count)
	local cols = { Color3.fromRGB(255, 232, 130), Color3.new(1, 1, 1), CONFIG.ACCENT_COLOR }

	local ring = Instance.new("Frame")
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromOffset(cx, cy)
	ring.Size = UDim2.fromOffset(10, 10)
	ring.BackgroundTransparency = 1
	ring.BorderSizePixel = 0
	ring.Active = false
	ring.ZIndex = 70
	ring.Parent = root
	corner(ring, 100)
	local rs = Instance.new("UIStroke")
	rs.Thickness = 2.5
	rs.Color = Color3.fromRGB(255, 232, 130)
	rs.Parent = ring
	TweenService:Create(ring, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = UDim2.fromOffset(74, 74) }):Play()
	TweenService:Create(rs, TweenInfo.new(0.5), { Transparency = 1, Thickness = 0.5 }):Play()
	task.delay(0.55, function() ring:Destroy() end)

	for _ = 1, count or 8 do
		local d = Instance.new("Frame")
		local sz = rng:NextInteger(3, 6)
		d.AnchorPoint = Vector2.new(0.5, 0.5)
		d.Size = UDim2.fromOffset(sz, sz)
		d.Position = UDim2.fromOffset(cx, cy)
		d.BackgroundColor3 = cols[rng:NextInteger(1, #cols)]
		d.BorderSizePixel = 0
		d.Rotation = rng:NextInteger(0, 90)
		d.Active = false
		d.ZIndex = 71
		d.Parent = root
		corner(d, 2)
		local ang = rng:NextNumber(0, math.pi * 2)
		local dist = rng:NextNumber(22, 46)
		local dur = rng:NextNumber(0.4, 0.7)
		TweenService:Create(d, TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.fromOffset(cx + math.cos(ang) * dist, cy + math.sin(ang) * dist),
			BackgroundTransparency = 1,
			Rotation = d.Rotation + 180,
		}):Play()
		task.delay(dur + 0.05, function() d:Destroy() end)
	end
end

local function swapHeader()
	if swapping or not logoBox.Visible then return end
	swapping = true
	local dir = (headerSide == "left") and 1 or -1
	headerSide = (headerSide == "left") and "right" or "left"

	local from = logoBox.Position
	burst(from.X.Offset + 35, from.Y.Offset + 19, 7)

	-- โลโก้: เด้งใหญ่ + เอียงตามทิศ แล้วเด้งกลับ
	TweenService:Create(logoScale, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1.28 }):Play()
	TweenService:Create(logoBox, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Rotation = dir * 12 }):Play()
	task.delay(0.22, function()
		TweenService:Create(logoScale, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		TweenService:Create(logoBox, TweenInfo.new(0.5, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), { Rotation = 0 }):Play()
	end)

	-- ป้ายฟาร์ม: ย่อ+จาง ระหว่างสลับ แล้วเด้งกลับ
	TweenService:Create(titleScale, TweenInfo.new(0.22, Enum.EasingStyle.Quad), { Scale = 0.86 }):Play()
	TweenService:Create(titleImg, TweenInfo.new(0.22, Enum.EasingStyle.Quad), { ImageTransparency = 0.45 }):Play()
	task.delay(0.28, function()
		TweenService:Create(titleScale, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		TweenService:Create(titleImg, TweenInfo.new(0.3, Enum.EasingStyle.Quad), { ImageTransparency = 0 }):Play()
	end)

	placeHeader(headerSide, true)

	task.delay(0.5, function()
		local to = logoBox.Position
		burst(to.X.Offset + 35, to.Y.Offset + 19, 5)
	end)
	task.delay(0.65, function() swapping = false end)
end

logoHit.Activated:Connect(swapHeader)

-- ===================================================== ปุ่มกลมแบบกระจก (ปิด / ย่อ)
local function roundGlassButton(sizePx, c1, c2, strokeCol)
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(sizePx, sizePx)
	b.BackgroundColor3 = Color3.new(1, 1, 1)
	b.BorderSizePixel = 0
	b.Text = ""
	b.AutoButtonColor = false
	b.ZIndex = 5
	b.Parent = frame

	local cr = Instance.new("UICorner")
	cr.CornerRadius = UDim.new(1, 0)
	cr.Parent = b

	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Color = ColorSequence.new(c1, c2)
	g.Parent = b

	local st = Instance.new("UIStroke")
	st.Thickness = 1.2
	st.Color = strokeCol
	st.Transparency = 0.15
	st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	st.Parent = b

	local gl = Instance.new("Frame")
	gl.Size = UDim2.new(0.76, 0, 0.42, 0)
	gl.Position = UDim2.fromScale(0.12, 0.07)
	gl.BackgroundColor3 = Color3.new(1, 1, 1)
	gl.BorderSizePixel = 0
	gl.Active = false
	gl.ZIndex = 6
	gl.Parent = b
	local gc = Instance.new("UICorner")
	gc.CornerRadius = UDim.new(1, 0)
	gc.Parent = gl
	local gg = Instance.new("UIGradient")
	gg.Rotation = 90
	gg.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.45),
		NumberSequenceKeypoint.new(1, 1),
	})
	gg.Parent = gl

	b.MouseEnter:Connect(function()
		TweenService:Create(st, TweenInfo.new(0.15), { Thickness = 2, Transparency = 0 }):Play()
	end)
	b.MouseLeave:Connect(function()
		TweenService:Create(st, TweenInfo.new(0.15), { Thickness = 1.2, Transparency = 0.15 }):Play()
	end)
	return b, g, st
end

local function iconBar(parent, w, h, rot, color)
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(0.5, 0.5)
	f.Size = UDim2.fromOffset(w, h)
	f.Rotation = rot
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.Active = false
	f.ZIndex = 7
	f.Parent = parent
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(1, 0)
	c.Parent = f
	return f
end

local function iconBox(parent, color)
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(0.5, 0.5)
	f.Size = UDim2.fromOffset(8, 8)
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.Active = false
	f.Visible = false
	f.ZIndex = 7
	f.Parent = parent
	corner(f, 2)
	local s = Instance.new("UIStroke")
	s.Thickness = 1.5
	s.Color = color
	s.Parent = f
	return f, s
end

-- ปุ่มปิด: แดงไล่สี + กากบาทวาดด้วยเส้น
local closeBtn = roundGlassButton(20, Color3.fromRGB(255, 110, 110), Color3.fromRGB(170, 20, 45), Color3.fromRGB(255, 175, 175))
iconBar(closeBtn, 10, 2, 45, Color3.new(1, 1, 1))
iconBar(closeBtn, 10, 2, -45, Color3.new(1, 1, 1))

-- ปุ่มย่อ: สีตามธีม + ไอคอนเปลี่ยนตามโหมด
local minBtn, minGrad, minStroke = roundGlassButton(20,
	CONFIG.PRIMARY_COLOR:Lerp(BG, 0.35), CONFIG.SECONDARY_COLOR:Lerp(BG, 0.25), CONFIG.ACCENT_COLOR)
local minBar = iconBar(minBtn, 9, 2, 0, CONFIG.ACCENT_COLOR)
local minBoxA, minBoxAS = iconBox(minBtn, CONFIG.ACCENT_COLOR)
local minBoxB, minBoxBS = iconBox(minBtn, CONFIG.ACCENT_COLOR)

local function setMinIcon(mode)
	minBar.Visible = (mode == 0)
	minBoxA.Visible = (mode ~= 0)
	minBoxB.Visible = (mode == 2)
	if mode == 1 then
		minBoxA.Size = UDim2.fromOffset(8, 8)
		minBoxA.Position = UDim2.fromScale(0.5, 0.5)
	elseif mode == 2 then
		minBoxA.Size = UDim2.fromOffset(6, 6)
		minBoxA.Position = UDim2.new(0.5, -2, 0.5, 2)
		minBoxB.Size = UDim2.fromOffset(6, 6)
		minBoxB.Position = UDim2.new(0.5, 2, 0.5, -2)
	end
end
setMinIcon(0)

local line = Instance.new("Frame")
line.Size = UDim2.new(1, -28, 0, 1)
line.Position = UDim2.fromOffset(14, 39)
line.BackgroundColor3 = Color3.new(1, 1, 1)
line.BorderSizePixel = 0
line.Parent = frame
local lineGrad = dynamicGradient(line)

-- เหรียญกลมไล่สี (ไอคอนอยู่กลาง ขอบหมุนวน)
local medal = Instance.new("Frame")
medal.Size = UDim2.fromOffset(50, 50)
medal.Position = UDim2.fromOffset(12, 48)
medal.BackgroundColor3 = Color3.new(0, 0, 0)
medal.BackgroundTransparency = 0.4
medal.BorderSizePixel = 0
medal.Active = false
medal.Parent = frame
corner(medal, 25)
local medalStroke = Instance.new("UIStroke")
medalStroke.Thickness = 2.2
medalStroke.Color = Color3.new(1, 1, 1)
medalStroke.Parent = medal
local medalGrad = dynamicGradient(medalStroke)

local itemIcon = Instance.new("ImageLabel")
itemIcon.Size = UDim2.fromOffset(34, 34)
itemIcon.Position = UDim2.fromOffset(20, 56)
itemIcon.BackgroundTransparency = 1
itemIcon.Image = CONFIG.ICON
itemIcon.ScaleType = Enum.ScaleType.Fit
itemIcon.ZIndex = 2
itemIcon.Parent = frame

local captionLbl = makeLabel(frame, 70, 48, 1, 14, 11, Enum.Font.GothamBold, CONFIG.ACCENT_COLOR, "จำนวน")
captionLbl.Size = UDim2.fromOffset(90, 14)
captionLbl.TextTransparency = 0.1

local countLbl = makeLabel(frame, 70, 60, 1, 28, 24, Enum.Font.GothamBold, CONFIG.PRIMARY_COLOR, "?/" .. CONFIG.MAX_COUNT)
countLbl.Size = UDim2.fromOffset(90, 28)

local barBack = Instance.new("Frame")
barBack.Size = UDim2.fromOffset(88, 7)
barBack.Position = UDim2.fromOffset(70, 92)
barBack.BackgroundColor3 = Color3.fromRGB(18, 30, 60)
barBack.BorderSizePixel = 0
barBack.Parent = frame
corner(barBack, 3)

local barFill = Instance.new("Frame")
barFill.Size = UDim2.fromScale(0, 1)
barFill.BackgroundColor3 = Color3.new(1, 1, 1)
barFill.BorderSizePixel = 0
barFill.Parent = barBack
corner(barFill, 3)
local barGrad = dynamicGradient(barFill)

local btnBack = Instance.new("Frame")
btnBack.Size = UDim2.fromOffset(76, 44)
btnBack.Position = UDim2.fromOffset(162, 50)
btnBack.BackgroundColor3 = Color3.new(1, 1, 1)
btnBack.BorderSizePixel = 0
btnBack.Active = false
btnBack.Parent = frame
local btnCorner = corner(btnBack, 12)
local btnGrad = Instance.new("UIGradient")
btnGrad.Parent = btnBack
local btnStroke = Instance.new("UIStroke")
btnStroke.Thickness = 1.5
btnStroke.Color = CONFIG.ACCENT_COLOR
btnStroke.Transparency = 0.2
btnStroke.Parent = btnBack

-- ลูกเล่นปุ่ม START: กระจกด้านบน + แสงวิ่ง + แฟลชตอนกด
btnBack.ClipsDescendants = true

local btnGloss = Instance.new("Frame")
btnGloss.Size = UDim2.new(1, 0, 0.5, 0)
btnGloss.BackgroundColor3 = Color3.new(1, 1, 1)
btnGloss.BorderSizePixel = 0
btnGloss.Active = false
btnGloss.Parent = btnBack
local btnGlossGrad = Instance.new("UIGradient")
btnGlossGrad.Rotation = 90
btnGlossGrad.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.6),
	NumberSequenceKeypoint.new(1, 1),
})
btnGlossGrad.Parent = btnGloss

local btnShine = Instance.new("Frame")
btnShine.Size = UDim2.new(0, 24, 2.2, 0)
btnShine.AnchorPoint = Vector2.new(0.5, 0.5)
btnShine.Rotation = 20
btnShine.Position = UDim2.new(-0.2, 0, 0.5, 0)
btnShine.BackgroundColor3 = Color3.new(1, 1, 1)
btnShine.BorderSizePixel = 0
btnShine.Active = false
btnShine.Parent = btnBack
local btnShineGrad = Instance.new("UIGradient")
btnShineGrad.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0,   1),
	NumberSequenceKeypoint.new(0.5, 0.55),
	NumberSequenceKeypoint.new(1,   1),
})
btnShineGrad.Parent = btnShine

local btnFlash = Instance.new("Frame")
btnFlash.Size = UDim2.fromScale(1, 1)
btnFlash.BackgroundColor3 = Color3.new(1, 1, 1)
btnFlash.BackgroundTransparency = 1
btnFlash.BorderSizePixel = 0
btnFlash.Active = false
btnFlash.Parent = btnBack

local toggle = Instance.new("TextButton")
toggle.Size = UDim2.fromScale(1, 1)
toggle.BackgroundTransparency = 1
toggle.Text = "START"
toggle.TextColor3 = Color3.new(1, 1, 1)
toggle.Font = Enum.Font.GothamBold
toggle.TextSize = 14
toggle.AutoButtonColor = false
toggle.TextStrokeColor3 = Color3.fromRGB(60, 20, 0)
toggle.TextStrokeTransparency = 0.5
toggle.TextWrapped = true
toggle.Font = Enum.Font.GothamBlack
toggle.Parent = btnBack

local togglePad = Instance.new("UIPadding")
togglePad.PaddingBottom = UDim.new(0, 4)
togglePad.Parent = toggle

-- ไอคอนกลม: สามเหลี่ยมเพลย์ (วาดเอง) / สี่เหลี่ยมสต็อป + ขอบหมุน
local playHolder = Instance.new("Frame")
playHolder.Size = UDim2.fromOffset(24, 24)
playHolder.AnchorPoint = Vector2.new(0.5, 0)
playHolder.Position = UDim2.new(0.5, 0, 0, 4)
playHolder.BackgroundColor3 = Color3.new(1, 1, 1)
playHolder.BackgroundTransparency = 0.75
playHolder.BorderSizePixel = 0
playHolder.Active = false
playHolder.ZIndex = 3
playHolder.Parent = btnBack
corner(playHolder, 12)
local playStroke = Instance.new("UIStroke")
playStroke.Thickness = 1.6
playStroke.Color = Color3.new(1, 1, 1)
playStroke.Transparency = 0.3
playStroke.Parent = playHolder
local playRing = Instance.new("UIGradient")
playRing.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0,   Color3.new(1, 1, 1)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 232, 130)),
	ColorSequenceKeypoint.new(1,   Color3.new(1, 1, 1)),
})
playRing.Parent = playStroke

-- สามเหลี่ยม = มุมสี่เหลี่ยมที่หมุน 45° ถูกตัดครึ่งด้วยกรอบ
local triClip = Instance.new("Frame")
triClip.Size = UDim2.fromOffset(6, 12)
triClip.AnchorPoint = Vector2.new(0.5, 0.5)
triClip.Position = UDim2.new(0.5, 1, 0.5, 0)
triClip.BackgroundTransparency = 1
triClip.BorderSizePixel = 0
triClip.ClipsDescendants = true
triClip.Active = false
triClip.ZIndex = 4
triClip.Parent = playHolder
local triDiamond = Instance.new("Frame")
triDiamond.Size = UDim2.fromOffset(8.5, 8.5)
triDiamond.AnchorPoint = Vector2.new(0.5, 0.5)
triDiamond.Position = UDim2.new(0, 0, 0.5, 0)
triDiamond.Rotation = 45
triDiamond.BackgroundColor3 = Color3.new(1, 1, 1)
triDiamond.BorderSizePixel = 0
triDiamond.Active = false
triDiamond.ZIndex = 4
triDiamond.Parent = triClip
corner(triDiamond, 1)

local stopSq = Instance.new("Frame")
stopSq.Size = UDim2.fromOffset(9, 9)
stopSq.AnchorPoint = Vector2.new(0.5, 0.5)
stopSq.Position = UDim2.fromScale(0.5, 0.5)
stopSq.BackgroundColor3 = Color3.new(1, 1, 1)
stopSq.BorderSizePixel = 0
stopSq.Active = false
stopSq.Visible = false
stopSq.ZIndex = 4
stopSq.Parent = playHolder
corner(stopSq, 2)

local btnScale = Instance.new("UIScale")
btnScale.Parent = btnBack

local statusLbl = makeLabel(frame, 162, 98, 0, 14, 10, Enum.Font.GothamBold, Color3.new(1, 1, 1), "● พร้อม")
statusLbl.Size = UDim2.fromOffset(76, 14)
statusLbl.TextXAlignment = Enum.TextXAlignment.Center

toggle.MouseButton1Down:Connect(function()
	TweenService:Create(btnFlash, TweenInfo.new(0.08), { BackgroundTransparency = 0.55 }):Play()
	TweenService:Create(btnScale, TweenInfo.new(0.08, Enum.EasingStyle.Quad), { Scale = 0.9 }):Play()
	-- วงกระเพื่อมจากไอคอน
	if playHolder.Visible then
		local rp = Instance.new("Frame")
		rp.AnchorPoint = Vector2.new(0.5, 0.5)
		rp.Position = UDim2.new(0.5, 0, 0, 16)
		rp.Size = UDim2.fromOffset(10, 10)
		rp.BackgroundColor3 = Color3.new(1, 1, 1)
		rp.BackgroundTransparency = 0.35
		rp.BorderSizePixel = 0
		rp.Active = false
		rp.ZIndex = 2
		rp.Parent = btnBack
		corner(rp, 100)
		TweenService:Create(rp, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = UDim2.fromOffset(110, 110), BackgroundTransparency = 1 }):Play()
		task.delay(0.55, function() rp:Destroy() end)
	end
end)
local function releaseFlash()
	TweenService:Create(btnFlash, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
	TweenService:Create(btnScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end
toggle.MouseButton1Up:Connect(releaseFlash)
toggle.MouseLeave:Connect(releaseFlash)

-- ===================================================== หน้าต่างยืนยันก่อนลบ UI
-- วางไว้ใน gui (เต็มจอ) ไม่ใช่ใน frame -> ย่อ UI อยู่ก็ไม่โดนตัด/ไม่บัค
local confirmOpen = false

local function showConfirmDialog()
	if confirmOpen then return end
	confirmOpen = true

	local white, dark = Color3.new(1, 1, 1), Color3.new(0, 0, 0)
	local S, A = CONFIG.SECONDARY_COLOR, CONFIG.ACCENT_COLOR

	local dim = Instance.new("TextButton") -- ฉากมืดเต็มจอ + กันกดทะลุ
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Color3.fromRGB(4, 6, 14)
	dim.BackgroundTransparency = 1
	dim.AutoButtonColor = false
	dim.Text = ""
	dim.ZIndex = 200
	dim.Parent = gui
	TweenService:Create(dim, TweenInfo.new(0.2), { BackgroundTransparency = 0.4 }):Play()

	local card = Instance.new("Frame")
	card.Size = UDim2.fromOffset(280, 150)
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.BackgroundColor3 = white
	card.BorderSizePixel = 0
	card.Active = true
	card.ClipsDescendants = true
	card.ZIndex = 201
	card.Parent = dim
	corner(card, 18)

	local cScale = Instance.new("UIScale")
	cScale.Scale = 0.75
	cScale.Parent = card
	local fit = math.clamp((gui.AbsoluteSize.X - 24) / 280, 0.6, 1)
	TweenService:Create(cScale, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = fit }):Play()

	-- พื้นการ์ดไล่สี
	local cGrad = Instance.new("UIGradient")
	cGrad.Rotation = 60
	cGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0,    S:Lerp(dark, 0.45)),
		ColorSequenceKeypoint.new(0.5,  Color3.fromRGB(16, 20, 40)),
		ColorSequenceKeypoint.new(1,    S:Lerp(dark, 0.7)),
	})
	cGrad.Parent = card

	-- แสงด้านบนการ์ด
	local topGlow = Instance.new("Frame")
	topGlow.Size = UDim2.new(1, 0, 0, 60)
	topGlow.BackgroundColor3 = Color3.fromRGB(255, 90, 90)
	topGlow.BorderSizePixel = 0
	topGlow.Active = false
	topGlow.ZIndex = 202
	topGlow.Parent = card
	local tgg = Instance.new("UIGradient")
	tgg.Rotation = 90
	tgg.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.7),
		NumberSequenceKeypoint.new(1, 1),
	})
	tgg.Parent = topGlow

	-- ขอบไล่สีหมุนวน
	local cStroke = Instance.new("UIStroke")
	cStroke.Thickness = 2.5
	cStroke.Color = white
	cStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	cStroke.Parent = card
	local sGrad = Instance.new("UIGradient")
	sGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0,    Color3.fromRGB(255, 70, 70)),
		ColorSequenceKeypoint.new(0.35, Color3.fromRGB(255, 190, 90)),
		ColorSequenceKeypoint.new(0.7,  A),
		ColorSequenceKeypoint.new(1,    Color3.fromRGB(255, 70, 70)),
	})
	sGrad.Parent = cStroke

	-- ไอคอนเตือน
	local warn_ = Instance.new("Frame")
	warn_.Size = UDim2.fromOffset(40, 40)
	warn_.Position = UDim2.fromOffset(18, 18)
	warn_.BackgroundColor3 = white
	warn_.BorderSizePixel = 0
	warn_.ZIndex = 203
	warn_.Parent = card
	corner(warn_, 20)
	local wg = Instance.new("UIGradient")
	wg.Rotation = 90
	wg.Color = ColorSequence.new(Color3.fromRGB(255, 120, 100), Color3.fromRGB(190, 25, 50))
	wg.Parent = warn_
	local ws = Instance.new("UIStroke")
	ws.Thickness = 1.5
	ws.Color = white
	ws.Transparency = 0.4
	ws.Parent = warn_
	local wt = Instance.new("TextLabel")
	wt.Size = UDim2.fromScale(1, 1)
	wt.BackgroundTransparency = 1
	wt.Text = "!"
	wt.TextColor3 = white
	wt.Font = Enum.Font.GothamBlack
	wt.TextSize = 24
	wt.ZIndex = 204
	wt.Parent = warn_

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -86, 0, 22)
	title.Position = UDim2.fromOffset(70, 18)
	title.BackgroundTransparency = 1
	title.Text = "ลบ UI ทั้งหมด?"
	title.TextColor3 = white
	title.Font = Enum.Font.GothamBold
	title.TextSize = 17
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.ZIndex = 203
	title.Parent = card

	local sub = Instance.new("TextLabel")
	sub.Size = UDim2.new(1, -86, 0, 34)
	sub.Position = UDim2.fromOffset(70, 42)
	sub.BackgroundTransparency = 1
	sub.Text = "สคริปต์จะหยุดทำงาน\nและ UI จะหายไปทันที"
	sub.TextColor3 = Color3.fromRGB(205, 215, 235)
	sub.Font = Enum.Font.Gotham
	sub.TextSize = 12
	sub.TextXAlignment = Enum.TextXAlignment.Left
	sub.TextYAlignment = Enum.TextYAlignment.Top
	sub.ZIndex = 203
	sub.Parent = card

	-- ปุ่มไล่สี (กระจกด้านบน)
	local function fancyBtn(text, c1, c2, pos, size)
		local f = Instance.new("Frame")
		f.Size = size
		f.Position = pos
		f.BackgroundColor3 = white
		f.BorderSizePixel = 0
		f.ClipsDescendants = true
		f.ZIndex = 203
		f.Parent = card
		corner(f, 12)
		local g = Instance.new("UIGradient")
		g.Rotation = 90
		g.Color = ColorSequence.new(c1, c2)
		g.Parent = f
		local st = Instance.new("UIStroke")
		st.Thickness = 1.5
		st.Color = white
		st.Transparency = 0.5
		st.Parent = f
		local gl = Instance.new("Frame")
		gl.Size = UDim2.new(1, 0, 0.5, 0)
		gl.BackgroundColor3 = white
		gl.BorderSizePixel = 0
		gl.Active = false
		gl.ZIndex = 204
		gl.Parent = f
		local glg = Instance.new("UIGradient")
		glg.Rotation = 90
		glg.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.6),
			NumberSequenceKeypoint.new(1, 1),
		})
		glg.Parent = gl
		local b = Instance.new("TextButton")
		b.Size = UDim2.fromScale(1, 1)
		b.BackgroundTransparency = 1
		b.Text = text
		b.TextColor3 = white
		b.Font = Enum.Font.GothamBold
		b.TextSize = 14
		b.AutoButtonColor = false
		b.ZIndex = 205
		b.Parent = f
		b.MouseButton1Down:Connect(function()
			TweenService:Create(f, TweenInfo.new(0.08), { BackgroundTransparency = 0.3 }):Play()
		end)
		local function up()
			TweenService:Create(f, TweenInfo.new(0.2), { BackgroundTransparency = 0 }):Play()
		end
		b.MouseButton1Up:Connect(up)
		b.MouseLeave:Connect(up)
		return b
	end

	local noBtn = fancyBtn("ยกเลิก",
		Color3.fromRGB(80, 110, 190), Color3.fromRGB(28, 44, 100),
		UDim2.new(0, 18, 1, -58), UDim2.new(0.5, -23, 0, 40))
	local yesBtn = fancyBtn("ลบทั้งหมด",
		Color3.fromRGB(255, 95, 95), Color3.fromRGB(175, 20, 45),
		UDim2.new(0.5, 5, 1, -58), UDim2.new(0.5, -23, 0, 40))

	local conn
	conn = RunService.Heartbeat:Connect(function()
		if not card.Parent then
			conn:Disconnect()
			return
		end
		local t = os.clock()
		sGrad.Rotation = (t * 120) % 360
		cGrad.Offset = Vector2.new(0.1 * math.sin(t * 0.8), 0.1 * math.cos(t * 0.6))
	end)

	local function closeDialog()
		if conn then conn:Disconnect() end
		confirmOpen = false
		dim:Destroy()
	end

	noBtn.Activated:Connect(closeDialog)
	dim.Activated:Connect(closeDialog) -- แตะนอกการ์ด = ยกเลิก

	yesBtn.Activated:Connect(function()
		if conn then conn:Disconnect() end
		running = false
		restoreAllBlockedGuis()
		clearStuckBlur()
		pcall(function() gui:Destroy() end)
	end)
end

closeBtn.Activated:Connect(showConfirmDialog)

local function updateThemeVisuals()
	local dark = Color3.new(0, 0, 0)
	local white = Color3.new(1, 1, 1)
	local outline = CONFIG.SECONDARY_COLOR:Lerp(dark, 0.5)
	local bgc = CONFIG.BG_COLORS

	loadTitleImage()
	titleLbl.TextColor3 = white
	titleLbl.TextStrokeColor3 = outline
	titleLbl.TextStrokeTransparency = 0.45
	countLbl.TextStrokeColor3 = outline
	countLbl.TextStrokeTransparency = 0.4
	itemIcon.Image = CONFIG.ICON
	logoFallback.TextColor3 = white
	captionLbl.TextColor3 = CONFIG.ACCENT_COLOR
	captionLbl.TextStrokeColor3 = outline
	captionLbl.TextStrokeTransparency = 0.5
	medal.BackgroundColor3 = outline

	local ring = ColorSequence.new({
		ColorSequenceKeypoint.new(0,    white),
		ColorSequenceKeypoint.new(0.35, CONFIG.ACCENT_COLOR),
		ColorSequenceKeypoint.new(0.7,  CONFIG.PRIMARY_COLOR),
		ColorSequenceKeypoint.new(1,    white),
	})
	strokeGrad.Color = ring
	medalGrad.Color = ring
	glowGrad.Color = ring
	lineGrad.Color = ColorSequence.new(white, CONFIG.ACCENT_COLOR)
	line.BackgroundTransparency = 0.35
	barGrad.Color = ColorSequence.new(white, CONFIG.ACCENT_COLOR)
	barBack.BackgroundColor3 = outline
	barBack.BackgroundTransparency = 0.45

	-- พื้นหลังสว่าง: บนเหลือง -> กลางส้ม -> ล่างส้มเข้ม (ไม่มีสีดำ)
	bgGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0,    bgc[1]),
		ColorSequenceKeypoint.new(0.5,  bgc[2]),
		ColorSequenceKeypoint.new(1,    bgc[3]),
	})
	tint.BackgroundColor3 = CONFIG.ACCENT_COLOR
	aurora.BackgroundColor3 = CONFIG.SECONDARY_COLOR
	bottomShade.BackgroundColor3 = outline
	rimStroke.Color = white

	-- ปุ่มย่อ
	minGrad.Color = ColorSequence.new(CONFIG.SECONDARY_COLOR:Lerp(white, 0.2), CONFIG.SECONDARY_COLOR:Lerp(dark, 0.2))
	minStroke.Color = white
	minBar.BackgroundColor3 = white
	minBoxAS.Color = white
	minBoxBS.Color = white
end

local uiMode = 0

local function setToggleVisual(on)
	if uiMode == 2 then
		toggle.Text = on and "⚡ ON" or "⚡ OFF"
	elseif uiMode == 0 then
		toggle.Text = on and "STOP" or "START"
	else
		toggle.Text = on and "■  STOP" or "▶  START"
	end
	toggle.TextYAlignment = (uiMode == 0) and Enum.TextYAlignment.Bottom or Enum.TextYAlignment.Center
	togglePad.PaddingBottom = UDim.new(0, uiMode == 0 and 4 or 0)
	playHolder.Visible = (uiMode == 0)
	triClip.Visible = not on
	stopSq.Visible = on
	statusLbl.Text = on and "● ทำงานอยู่" or "● พร้อม"
	statusLbl.TextColor3 = on and Color3.fromRGB(130, 255, 170) or CONFIG.ACCENT_COLOR
	local dark = Color3.new(0, 0, 0)
	local S, P = CONFIG.SECONDARY_COLOR, CONFIG.PRIMARY_COLOR
	if on then
		btnGrad.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0,    Color3.fromRGB(10, 120, 70)),
			ColorSequenceKeypoint.new(0.35, Color3.fromRGB(40, 205, 115)),
			ColorSequenceKeypoint.new(0.65, Color3.fromRGB(150, 255, 175)),
			ColorSequenceKeypoint.new(1,    Color3.fromRGB(10, 120, 70)),
		})
	else
		btnGrad.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0,    S:Lerp(dark, 0.4)),
			ColorSequenceKeypoint.new(0.35, S),
			ColorSequenceKeypoint.new(0.65, P:Lerp(Color3.new(1, 1, 1), 0.2)),
			ColorSequenceKeypoint.new(1,    S:Lerp(dark, 0.4)),
		})
	end
	btnStroke.Color = Color3.new(1, 1, 1)
end

local function applyUIMode(mode)
	uiMode = mode % 3
	local tInfo = TweenInfo.new(0.25, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
	setMinIcon(uiMode)

	if uiMode == 0 then
		TweenService:Create(root, tInfo, { Size = UDim2.fromOffset(250, 122) }):Play()
		frameCorner.CornerRadius = UDim.new(0, 14)
		glowCorner.CornerRadius = UDim.new(0, 20)
		shadowCorner.CornerRadius = UDim.new(0, 18)

		logoBox.Visible = true
		titleLbl.Visible = true
		line.Visible = true
		barBack.Visible = true
		medal.Visible = true
		captionLbl.Visible = true
		statusLbl.Visible = true

		itemIcon.Visible = true
		itemIcon.Size = UDim2.fromOffset(34, 34)
		itemIcon.Position = UDim2.fromOffset(20, 56)

		countLbl.Visible = true
		countLbl.Position = UDim2.fromOffset(70, 60)
		countLbl.Size = UDim2.fromOffset(90, 28)
		countLbl.TextSize = 24

		btnBack.Visible = true
		btnBack.Position = UDim2.fromOffset(162, 50)
		btnBack.Size = UDim2.fromOffset(76, 44)
		btnCorner.CornerRadius = UDim.new(0, 12)
		toggle.TextSize = 12

		titleLbl.Position = UDim2.fromOffset(112, 5)
		logoBox.Size = UDim2.fromOffset(70, 39)
		placeHeader(headerSide, false)
		minBtn.Size = UDim2.fromOffset(20, 20)
		minBtn.Position = UDim2.new(1, -50, 0, 4)
		closeBtn.Size = UDim2.fromOffset(20, 20)
		closeBtn.Position = UDim2.new(1, -26, 0, 4)

	elseif uiMode == 1 then
		TweenService:Create(root, tInfo, { Size = UDim2.fromOffset(170, 38) }):Play()
		frameCorner.CornerRadius = UDim.new(0, 11)
		glowCorner.CornerRadius = UDim.new(0, 16)
		shadowCorner.CornerRadius = UDim.new(0, 14)

		logoBox.Visible = false
		titleLbl.Visible = false
		line.Visible = false
		barBack.Visible = false
		btnBack.Visible = false
		medal.Visible = false
		captionLbl.Visible = false
		statusLbl.Visible = false

		itemIcon.Visible = true
		itemIcon.Size = UDim2.fromOffset(26, 26)
		itemIcon.Position = UDim2.fromOffset(7, 6)

		countLbl.Visible = true
		countLbl.Position = UDim2.fromOffset(38, 5)
		countLbl.Size = UDim2.new(1, -90, 0, 28)
		countLbl.TextSize = 15

		minBtn.Size = UDim2.fromOffset(18, 18)
		minBtn.Position = UDim2.new(1, -45, 0, 10)
		closeBtn.Size = UDim2.fromOffset(18, 18)
		closeBtn.Position = UDim2.new(1, -23, 0, 10)

	elseif uiMode == 2 then
		TweenService:Create(root, tInfo, { Size = UDim2.fromOffset(118, 38) }):Play()
		frameCorner.CornerRadius = UDim.new(0, 19)
		glowCorner.CornerRadius = UDim.new(0, 24)
		shadowCorner.CornerRadius = UDim.new(0, 22)

		logoBox.Visible = false
		titleLbl.Visible = false
		line.Visible = false
		barBack.Visible = false
		medal.Visible = false
		captionLbl.Visible = false
		statusLbl.Visible = false
		itemIcon.Visible = false
		countLbl.Visible = false

		btnBack.Visible = true
		btnBack.Position = UDim2.fromOffset(5, 5)
		btnBack.Size = UDim2.new(1, -54, 1, -10)
		btnCorner.CornerRadius = UDim.new(0, 14)
		toggle.TextSize = 13

		minBtn.Size = UDim2.fromOffset(18, 18)
		minBtn.Position = UDim2.new(1, -47, 0, 10)
		closeBtn.Size = UDim2.fromOffset(18, 18)
		closeBtn.Position = UDim2.new(1, -25, 0, 10)
	end

	setToggleVisual(running)
end

minBtn.Activated:Connect(function()
	applyUIMode(uiMode + 1)
end)

setToggleVisual(false)
updateThemeVisuals()

-- แอนิเมชันขอบหมุน + พื้นหลังขยับ + แสงวิ่ง
task.spawn(function()
	while gui.Parent do
		local t = os.clock()
		local r = (t * 90) % 360
		strokeGrad.Rotation = r
		medalGrad.Rotation = -r
		logoGrad.Offset = Vector2.new(((t * 0.55) % 2) - 1, 0)
		logoImg.Position = UDim2.fromOffset(0, math.sin(t * 2.2) * 1.5)
		playRing.Rotation = (t * (running and 260 or 90)) % 360
		playStroke.Transparency = 0.15 + 0.3 * (0.5 + 0.5 * math.sin(t * 3))
		triClip.Position = UDim2.new(0.5, 1 + math.sin(t * 4) * 1.2, 0.5, 0)
		local sq = 9 + math.sin(t * 8)
		stopSq.Size = UDim2.fromOffset(sq, sq)
		glowGrad.Rotation = -r
		lineGrad.Rotation = r
		barGrad.Rotation = r
		bgGrad.Offset = Vector2.new(0.08 * math.sin(t * 0.6), 0.08 * math.cos(t * 0.5))
		tintGrad.Rotation = 35 + 12 * math.sin(t * 0.4)
		auroraGrad.Rotation = 215 + 12 * math.sin(t * 0.35)
		sweep.Position = UDim2.new(0, -60 + ((t * 38) % 360), 0.5, 0)
		glow.BackgroundTransparency = 0.75 + 0.1 * math.sin(t * 2.5)
		btnStroke.Transparency = 0.15 + 0.25 * (0.5 + 0.5 * math.sin(t * 3.2))
		-- ปุ่ม START: สีไหลวน + แสงวิ่ง + ขอบเต้นตอนทำงาน
		btnGrad.Rotation = (t * (running and 90 or 35)) % 360
		local cycle = running and 1.2 or 2.6
		btnShine.Position = UDim2.new(-0.2 + ((t % cycle) / cycle) * 1.4, 0, 0.5, 0)
		btnStroke.Thickness = running and (2 + 0.7 * math.sin(t * 7)) or 1.5
		RunService.RenderStepped:Wait()
	end
end)

local function updateCountUI()
	autoDetectNearestMode()
	updateThemeVisuals()

	local n = getItemCount()
	local shown = n or lastKnown
	countLbl.Text = ("%s/%d"):format(shown and tostring(shown) or "?", CONFIG.MAX_COUNT)
	countLbl.TextColor3 = (shown and shown >= CONFIG.MAX_COUNT) and Color3.fromRGB(255, 255, 190) or Color3.new(1, 1, 1)
	local frac = math.clamp((shown or 0) / math.max(CONFIG.MAX_COUNT, 1), 0, 1)
	TweenService:Create(barFill, TweenInfo.new(0.3, Enum.EasingStyle.Quad), { Size = UDim2.fromScale(frac, 1) }):Play()
end

task.spawn(function()
	while gui.Parent do
		pcall(updateCountUI)
		task.wait(0.5)
	end
end)

-- ===================================================== ระบบคลิกปลอดภัย
local function unblock(pos, target)
	local changed = {}
	local ok, objs = pcall(function() return PG:GetGuiObjectsAtPosition(pos.X, pos.Y) end)
	if not ok then return changed end
	for _, o in ipairs(objs) do
		if o == target or o:IsDescendantOf(target) or target:IsDescendantOf(o) then break end
		local sg = o:FindFirstAncestorWhichIsA("ScreenGui")
		if sg and (sg.Name == "TouchGui" or sg.Name == "RiceMacroUI") then continue end
		if o.Active then
			o.Active = false
			temporarilyDisabled[o] = true
			changed[#changed + 1] = o
		end
	end
	return changed
end

local SIGNALS = { "Activated", "MouseButton1Click", "MouseButton1Down", "MouseButton1Up",
	"TouchTap", "InputBegan", "InputEnded", "MouseEnter", "MouseMoved" }

local function slotRootOf(obj)
	local sf = obj:FindFirstAncestorWhichIsA("ScrollingFrame")
	if not sf then return obj end
	local o = obj
	while o.Parent and o.Parent ~= sf and o.Parent:IsA("GuiObject") do
		o = o.Parent
	end
	return o
end

local function eachInSlot(obj, fn)
	local r = slotRootOf(obj)
	fn(r)
	for _, d in ipairs(r:GetDescendants()) do fn(d) end
end

local function fireAllSignals(obj, cx, cy)
	if not getconnections then return 0 end
	local pos3 = Vector3.new(cx, cy, 0)
	local function fake(state)
		return { UserInputType = Enum.UserInputType.MouseButton1, UserInputState = state,
			Position = pos3, Delta = Vector3.new(0, 0, 0), KeyCode = Enum.KeyCode.Unknown }
	end
	local total = 0
	eachInSlot(obj, function(o)
		if not o:IsA("GuiObject") then return end
		for _, name in ipairs(SIGNALS) do
			local ok, conns = pcall(function() return getconnections(o[name]) end)
			if ok and conns then
				for _, c in ipairs(conns) do
					local args
					if name == "InputBegan" then args = { fake(Enum.UserInputState.Begin), false }
					elseif name == "InputEnded" then args = { fake(Enum.UserInputState.End), false }
					elseif name == "Activated" then args = { fake(Enum.UserInputState.Begin), 1 }
					elseif name == "TouchTap" then args = { { Vector2.new(cx, cy) }, false }
					else args = { cx, cy } end
					local f = c.Function
					if f then
						task.spawn(function() pcall(f, table.unpack(args)) end)
						total += 1
					elseif c.Fire then
						pcall(function() c:Fire(table.unpack(args)) end)
						total += 1
					end
				end
			end
		end
	end)
	return total
end

-- ===================================================== ปรับเทียบพิกัด
local calib = {}

local function rawSend(kind, sx, sy)
	if kind == "touch" then
		local id = math.random(2000, 9999)
		pcall(function()
			VIM:SendTouchEvent(id, 0, sx, sy)
			task.wait(0.04)
			VIM:SendTouchEvent(id, 2, sx, sy)
		end)
	else
		pcall(function()
			VIM:SendMouseMoveEvent(sx, sy, game)
			task.wait(0.04)
			VIM:SendMouseButtonEvent(sx, sy, 0, true, game, 0)
			task.wait(0.05)
			VIM:SendMouseButtonEvent(sx, sy, 0, false, game, 0)
		end)
	end
end

local function probe(kind, sx, sy)
	local got
	local want = (kind == "touch") and Enum.UserInputType.Touch or Enum.UserInputType.MouseButton1
	local c = UIS.InputBegan:Connect(function(input)
		if input.UserInputType == want and not got then
			got = Vector2.new(input.Position.X, input.Position.Y)
		end
	end)
	rawSend(kind, sx, sy)
	local t0 = os.clock()
	while not got and os.clock() - t0 < 0.6 do task.wait(0.02) end
	c:Disconnect()
	return got
end

local function calibrate()
	local pad = Instance.new("TextButton")
	pad.Size = UDim2.fromScale(1, 1)
	pad.Position = UDim2.fromScale(0, 0)
	pad.BackgroundTransparency = 1
	pad.Text = ""
	pad.AutoButtonColor = false
	pad.Active = true
	pad.Modal = true
	pad.ZIndex = 99999
	pad.Parent = gui
	task.wait(0.05)

	local P1, P2 = Vector2.new(330, 260), Vector2.new(560, 400)
	for _, kind in ipairs({ "mouse", "touch" }) do
		local r1 = probe(kind, P1.X, P1.Y)
		task.wait(0.05)
		local r2 = probe(kind, P2.X, P2.Y)
		if r1 and r2 and math.abs(r2.X - r1.X) > 50 and math.abs(r2.Y - r1.Y) > 50 then
			local ax = (r2.X - r1.X) / (P2.X - P1.X)
			local ay = (r2.Y - r1.Y) / (P2.Y - P1.Y)
			if ax > 0.5 and ax < 2 and ay > 0.5 and ay < 2 then
				calib[kind] = { ax = ax, ay = ay, bx = r1.X - ax * P1.X, by = r1.Y - ay * P1.Y }
			end
		end
		task.wait(0.05)
	end
	pad:Destroy()
end

local function mapPoint(kind, T)
	local c = calib[kind]
	if c then return Vector2.new((T.X - c.bx) / c.ax, (T.Y - c.by) / c.ay) end
	return T + GuiService:GetGuiInset()
end

local function findInnerButton(obj)
	if obj:IsA("GuiButton") then return obj end
	return obj:FindFirstChildWhichIsA("GuiButton", true)
end

local function fireFirst(btn)
	if not getconnections then return false end
	for _, sig in ipairs({ btn.Activated, btn.MouseButton1Click, btn.MouseButton1Down }) do
		local ok, conns = pcall(getconnections, sig)
		if ok and conns and #conns > 0 then
			for _, c in ipairs(conns) do
				if c.Fire then pcall(function() c:Fire() end)
				elseif c.Function then pcall(c.Function) end
			end
			return true
		end
	end
	return false
end

local function clickFrame(guiObj, times, mode, inset, pass)
	if not guiObj or not guiObj:IsA("GuiObject") then return false end
	times = times or 1
	mode = mode or "both"
	inset = inset or "cal"

	if mode == "fire" then
		local btn = findInnerButton(guiObj)
		return btn ~= nil and fireFirst(btn)
	end

	local T = guiObj.AbsolutePosition + guiObj.AbsoluteSize / 2
	local function target(kind)
		if inset == "cal" then return mapPoint(kind, T) end
		if inset == "add" then return T + GuiService:GetGuiInset() end
		return T
	end
	local sm, st = target("mouse"), target("touch")

	local changed = unblock(T, guiObj)

	if pass and guiObj:FindFirstAncestorWhichIsA("ScrollingFrame") then
		local sRoot = slotRootOf(guiObj)
		for _, d in ipairs(sRoot:GetDescendants()) do
			if d:IsA("GuiObject") and d.Active then
				d.Active = false
				temporarilyDisabled[d] = true
				changed[#changed + 1] = d
			end
		end
	end

	for i = 1, times do
		if mode == "signals" then
			fireAllSignals(guiObj, T.X, T.Y)
		end
		if mode == "hover" then
			pcall(function()
				VIM:SendMouseMoveEvent(sm.X - 4, sm.Y - 4, game)
				task.wait(0.08)
				VIM:SendMouseMoveEvent(sm.X, sm.Y, game)
				task.wait(0.25)
			end)
		end
		if mode == "both" or mode == "touch" then
			local touchId = math.random(2000, 9999)
			pcall(function()
				VIM:SendTouchEvent(touchId, 0, st.X, st.Y)
				task.wait(0.04)
				VIM:SendTouchEvent(touchId, 1, st.X + 1, st.Y + 1)
				task.wait(0.06)
				VIM:SendTouchEvent(touchId, 2, st.X + 1, st.Y + 1)
			end)
		end
		if mode == "both" or mode == "mouse" or mode == "hover" then
			local hold = (mode == "hover") and 0.12 or 0.05
			pcall(function()
				VIM:SendMouseButtonEvent(sm.X, sm.Y, 0, true, game, 0)
				task.wait(hold)
				VIM:SendMouseButtonEvent(sm.X, sm.Y, 0, false, game, 0)
			end)
		end
		if i < times then task.wait(0.15) end
	end

	task.delay(0.4, function()
		for _, o in ipairs(changed) do
			if o and o.Parent then o.Active = true end
			temporarilyDisabled[o] = nil
		end
	end)
	return true
end

local VARIANTS = {
	{ "fire" },
	{ "both",  "cal" },
	{ "mouse", "cal" },
	{ "touch", "cal" },
	{ "hover", "cal" },
	{ "mouse", "cal", true },
	{ "hover", "cal", true },
	{ "both",  "add" },
	{ "hover", "add", true },
	{ "signals", "cal" },
}
local goodVar = 1

-- กดครั้งเดียว แล้วตรวจผล: ถ้าสำเร็จไปต่อทันที ถ้ายังไม่สำเร็จค่อยกดซ้ำด้วยวิธีถัดไป
local function clickUntil(obj, doneFn, maxTries)
	local limit = math.min(maxTries or #VARIANTS, #VARIANTS)
	for k = 0, limit - 1 do
		if not running then return false end
		if doneFn() then return true end
		if not (obj and obj.Parent and isShown(obj)) then return doneFn() end
		local idx = ((goodVar - 1 + k) % #VARIANTS) + 1
		local v = VARIANTS[idx]
		if clickFrame(obj, 1, v[1], v[2], v[3]) then
			-- ครั้งแรกรอผลนานหน่อย (กันเซิร์ฟเวอร์ตอบช้าแล้วโดนกดซ้ำ) แต่เจอผลเมื่อไหร่ออกทันที
			local waitSec = (k == 0) and 1.0 or 0.6
			local t0 = os.clock()
			repeat
				if doneFn() then
					goodVar = idx
					return true
				end
				task.wait(0.03)
			until os.clock() - t0 >= waitSec or not running
		end
	end
	return doneFn()
end

local function clickOnce(obj)
	if not (obj and isShown(obj)) then return false end
	for k = 0, #VARIANTS - 1 do
		local idx = ((goodVar - 1 + k) % #VARIANTS) + 1
		local v = VARIANTS[idx]
		if clickFrame(obj, 1, v[1], v[2], v[3]) then return true end
	end
	return false
end

-- ===================================================== ระบบเดินสุ่มวิถีโค้ง
local function charParts()
	local ch = LP.Character
	return ch and ch:FindFirstChild("HumanoidRootPart"), ch and ch:FindFirstChildOfClass("Humanoid")
end

local function buildVariedWaypoints(rawWps, startPos, targetPos, character)
	local totalWps = #rawWps
	if totalWps <= 2 then return rawWps end

	local flatDelta = Vector3.new(targetPos.X - startPos.X, 0, targetPos.Z - startPos.Z)
	local totalDist = flatDelta.Magnitude
	if totalDist < 8 then return rawWps end

	local forward = flatDelta.Unit
	local rightVec = Vector3.new(-forward.Z, 0, forward.X)

	local styleRoll = rng:NextNumber()
	local sideSign = (rng:NextInteger(0, 1) == 0) and -1 or 1
	local maxAmp = math.clamp(totalDist * 0.28, SETTINGS.SWAY_MIN, SETTINGS.SWAY_MAX)
	local amp, freq

	if styleRoll < 0.36 then
		amp = rng:NextNumber(SETTINGS.SWAY_MIN, maxAmp) * sideSign
		freq = 1
	elseif styleRoll < 0.72 then
		amp = rng:NextNumber((SETTINGS.SWAY_MIN + maxAmp) * 0.5, maxAmp) * sideSign
		freq = 1
	elseif styleRoll < 0.90 then
		amp = rng:NextNumber(SETTINGS.SWAY_MIN * 0.85, maxAmp * 0.85) * sideSign
		freq = 2
	else
		amp = rng:NextNumber(1.2, SETTINGS.SWAY_MIN * 0.7) * sideSign
		freq = 1
	end

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { character }

	local varied = {}
	for idx, wp in ipairs(rawWps) do
		if idx == 1 or idx == totalWps then
			varied[idx] = wp
		else
			local progress = (idx - 1) / (totalWps - 1)
			local envelope = math.sin(progress * math.pi)
			local wave = (freq == 1) and envelope or (math.sin(progress * math.pi * 2) * envelope)
			local jitter = rng:NextNumber(-0.85, 0.85) * envelope
			local offsetDist = (amp * wave) + jitter

			local offsetVec = rightVec * offsetDist
			local origin = wp.Position + Vector3.new(0, 2, 0)
			local hit = workspace:Raycast(origin, offsetVec, rayParams)
			if hit then
				local safeDist = math.max(0, (hit.Position - origin).Magnitude - 2.2)
				offsetVec = offsetVec.Unit * safeDist
			end

			varied[idx] = {
				Position = wp.Position + offsetVec,
				Action = wp.Action,
			}
		end
	end
	return varied
end

local function walkTo(target, stopDist)
	local hrp, hum = charParts()
	if not (hrp and hum) then return false end
	local deadline = os.clock() + SETTINGS.WALK_TIMEOUT

	local angle = rng:NextNumber(0, math.pi * 2)
	local radius = rng:NextNumber(0.4, math.max(0.5, stopDist * 0.35))
	local randomizedTarget = target + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)

	local function dist()
		local h = charParts()
		return h and (h.Position - target).Magnitude or math.huge
	end

	local reached = false
	while running and not reached and os.clock() < deadline do
		hrp, hum = charParts()
		if not (hrp and hum) or hum.Health <= 0 then break end
		if dist() <= stopDist then reached = true break end

		local path = PathfindingService:CreatePath({
			AgentRadius = 2,
			AgentHeight = 5,
			AgentCanJump = true,
			WaypointSpacing = 4,
		})
		local ok = pcall(function() path:ComputeAsync(hrp.Position, randomizedTarget) end)
		local rawWps = (ok and path.Status == Enum.PathStatus.Success) and path:GetWaypoints() or { { Position = randomizedTarget } }
		local wps = buildVariedWaypoints(rawWps, hrp.Position, randomizedTarget, LP.Character)

		local i = (#wps >= 2) and 2 or 1
		local lastPos, lastT = hrp.Position, os.clock()
		while running and i <= #wps and os.clock() < deadline do
			hrp, hum = charParts()
			if not (hrp and hum) or hum.Health <= 0 then break end
			if dist() <= stopDist then reached = true break end

			local wp = wps[i]
			if wp.Action == Enum.PathWaypointAction.Jump then hum.Jump = true end
			hum:MoveTo(wp.Position)
			if (Vector3.new(hrp.Position.X, wp.Position.Y, hrp.Position.Z) - wp.Position).Magnitude <= 4.8 then
				i += 1
			end

			if os.clock() - lastT > 0.75 then
				if (hrp.Position - lastPos).Magnitude < 1 then hum.Jump = true break end
				lastPos, lastT = hrp.Position, os.clock()
			end
			RunService.Heartbeat:Wait()
		end
	end

	hrp, hum = charParts()
	if hrp and hum then
		hum:MoveTo(hrp.Position)
	end
	return dist() <= stopDist
end

local function posOf(obj)
	if obj:IsA("BasePart") then return obj.Position end
	if obj:IsA("Attachment") then return obj.WorldPosition end
	return obj:GetPivot().Position
end

local function pressPrompt(prompt)
	if fireproximityprompt then
		pcall(fireproximityprompt, prompt)
	else
		VIM:SendKeyEvent(true, Enum.KeyCode.E, false, game)
		task.wait(0.2)
		VIM:SendKeyEvent(false, Enum.KeyCode.E, false, game)
	end
end

local function triggerFarmPrompt()
	local farmPart = child(workspace, table.unpack(CONFIG.FARM_PATH))
	if not farmPart then return false end

	local prompt = farmPart:IsA("ProximityPrompt") and farmPart or farmPart:FindFirstChildWhichIsA("ProximityPrompt", true)
	walkTo(posOf(prompt and prompt.Parent or farmPart), 5)
	if not running then return false end

	if prompt then
		pressPrompt(prompt)
		return true
	end
	return false
end

-- ===================================================== ท้ายรถ
local function nearestSpawn()
	local hrp = charParts()
	if not hrp then return nil end

	local prompts = {}
	local folder = child(workspace, table.unpack(CONFIG.SPAWN_FOLDER)) or child(workspace, "Systems", "Car_Spawn")
	if folder then
		for _, sp in ipairs(folder:GetChildren()) do
			local p = sp:FindFirstChildWhichIsA("ProximityPrompt", true)
			if p then prompts[#prompts + 1] = p end
		end
	end
	if #prompts == 0 then
		for _, d in ipairs(workspace:GetDescendants()) do
			if d:IsA("ProximityPrompt") and d.Parent then
				local t = (d.ActionText .. " " .. d.ObjectText .. " " .. d.Parent.Name):lower()
				if (t:find("spawn") or t:find("car") or t:find("รถ")) and not t:find("farm") then
					prompts[#prompts + 1] = d
				end
			end
		end
	end

	local best, bestD
	for _, prompt in ipairs(prompts) do
		local par = prompt.Parent
		local pos = par:IsA("BasePart") and par.Position or (par:IsA("Attachment") and par.WorldPosition)
		if pos then
			local d = (hrp.Position - pos).Magnitude
			if not bestD or d < bestD then
				best, bestD = { prompt = prompt, pos = pos }, d
			end
		end
	end
	return best
end

local function storageOpen()
	local g = child(PG, "Car_Storage", "Group")
	return g ~= nil and g.Visible
end

local function scanTrunk()
	for _, d in ipairs(PG:GetDescendants()) do
		if (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Text:upper():find(SETTINGS.TRUNK_TEXT) then
			local btn = d:FindFirstAncestorWhichIsA("GuiButton") or d.Parent
			if btn and btn:IsA("GuiObject") and btn.AbsoluteSize.X > 0 and isShown(btn) then
				return btn
			end
		end
	end
	return nil
end

local function openTrunk()
	if storageOpen() then return true end
	local target = nearestSpawn()
	if not target then return false end

	walkTo(target.pos, 5)

	for _ = 1, SETTINGS.PROMPT_TRIES do
		if not running then return false end
		pressPrompt(target.prompt)

		local trunkBtn
		local t0 = os.clock()
		repeat
			trunkBtn = scanTrunk()
			if trunkBtn then break end
			task.wait(0.05)
		until os.clock() - t0 >= 0.8

		if trunkBtn and clickUntil(trunkBtn, storageOpen, 5) then return true end
	end
	return false
end

local function closeTrunk()
	if not storageOpen() then
		clearStuckBlur()
		return
	end
	local r = refs()
	if r.cancel and isShown(r.cancel) then
		clickUntil(r.cancel, function() return not storageOpen() end, 3)
	end
	restoreAllBlockedGuis()
	task.delay(0.2, clearStuckBlur)
end

-- ===================================================== ย้ายไอเทม
local function findItemFrame()
	local r = refs()
	if not (r.group and r.group.Visible) then return nil end
	local invScroll = child(r.main, "Scrolling", CONFIG.FROM, "Scrolling")
	if not invScroll then return nil end

	local slot = invScroll:FindFirstChild(CONFIG.ITEM)
	if slot and slot:IsA("GuiObject") and isShown(slot) then
		local lbl = child(slot, "Holder", "items") or slot:FindFirstChild("items")
		if lbl and lbl.Text ~= "" and (numFrom(lbl.Text) or 0) <= 0 then
			return nil
		end
		return slot
	end

	for _, cell in ipairs(invScroll:GetChildren()) do
		if cell:IsA("GuiObject") and isShown(cell) then
			local nm = child(cell, "Holder", "itemname") or cell:FindFirstChild("itemname")
			if nm and nm:IsA("TextLabel") and nm.Text:lower() == CONFIG.ITEM:lower() then
				local lbl = child(cell, "Holder", "items") or cell:FindFirstChild("items")
				if lbl and lbl.Text ~= "" and (numFrom(lbl.Text) or 0) <= 0 then
					return nil
				end
				return cell
			end
		end
	end
	return nil
end

local function menuName()
	local r = refs()
	return (r.itemName and r.itemName.Text or ""), ((r.confirm and isShown(r.confirm)) or false)
end

local function nameHasItem(t)
	t = t:lower()
	return t:find(CONFIG.ITEM:lower(), 1, true) ~= nil
end

local function scrollIntoView(obj)
	local sf = obj:FindFirstAncestorWhichIsA("ScrollingFrame")
	if not sf then return end
	local relX = obj.AbsolutePosition.X - sf.AbsolutePosition.X
	local relY = obj.AbsolutePosition.Y - sf.AbsolutePosition.Y
	local outX = relX < 0 or relX + obj.AbsoluteSize.X > sf.AbsoluteSize.X
	local outY = relY < 0 or relY + obj.AbsoluteSize.Y > sf.AbsoluteSize.Y
	if outX or outY then
		local cp = sf.CanvasPosition
		local nx = outX and (cp.X + relX - (sf.AbsoluteSize.X - obj.AbsoluteSize.X) / 2) or cp.X
		local ny = outY and (cp.Y + relY - (sf.AbsoluteSize.Y - obj.AbsoluteSize.Y) / 2) or cp.Y
		sf.CanvasPosition = Vector2.new(math.max(0, nx), math.max(0, ny))
		task.wait(0.1)
	end
end

-- ===================================================== กด MAX (ก่อน Confirm)
local function menuMainFrame()
	local r = refs()
	return r.main and child(r.main, "Menu", "Main")
end

local function functionFrame()
	local r = refs()
	if r.max and r.max.Parent then return r.max.Parent end
	local mm = menuMainFrame()
	return mm and mm:FindFirstChild("Function")
end

local function functionTexts()
	local fn = functionFrame()
	if not fn then return "" end
	local parts = {}
	for _, d in ipairs(fn:GetDescendants()) do
		if d:IsA("TextBox") or d:IsA("TextLabel") or d:IsA("TextButton") then
			parts[#parts + 1] = d.Text
		end
	end
	return table.concat(parts, "|")
end

local function findAmountBox()
	local fn = functionFrame()
	return fn and fn:FindFirstChildWhichIsA("TextBox", true)
end

-- หาปุ่ม Max: ลองตาม path เดิมก่อน ถ้าไม่เจอค้นหาจากชื่อ/ข้อความ
local function findMaxButton()
	local r = refs()
	if r.max and isShown(r.max) then return r.max end
	local mm = menuMainFrame()
	if not mm then return nil end
	for _, d in ipairs(mm:GetDescendants()) do
		if d:IsA("GuiObject") and isShown(d) then
			local nm = d.Name:lower()
			local tx = (d:IsA("TextButton") or d:IsA("TextLabel")) and d.Text:lower() or ""
			if nm == "max" or tx:match("^%s*max%s*$") or tx:find("สูงสุด", 1, true) then
				return d
			end
		end
	end
	return nil
end

-- รอให้ปุ่มหยุดเคลื่อนที่ (กันคลิกตอนเมนูกำลังเด้ง)
local function waitStable(obj, timeout)
	local last, since, t0 = obj.AbsolutePosition, os.clock(), os.clock()
	while os.clock() - t0 < timeout do
		task.wait(0.05)
		local p = obj.AbsolutePosition
		if (p - last).Magnitude > 0.5 then
			last, since = p, os.clock()
		elseif os.clock() - since >= 0.2 then
			return
		end
	end
end

-- พิมพ์โครงสร้างเมนูลง Console (F9) ครั้งเดียว ไว้ใช้ดีบัก
local dumped = false
local function dumpMenu()
	if dumped then return end
	dumped = true
	local mm = menuMainFrame()
	if not mm then
		warn("[MAXDEBUG] ไม่พบ Car_Storage.Group.Main.Menu.Main")
		return
	end
	for _, d in ipairs(mm:GetDescendants()) do
		if d:IsA("GuiObject") then
			local tx = (d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox")) and d.Text or ""
			warn(("[MAXDEBUG] %s | %s | visible=%s | text=%s"):format(d:GetFullName(), d.ClassName, tostring(d.Visible), tx))
		end
	end
end

local MAX_VARIANTS = {
	{ "fire" },
	{ "signals", "cal" },
	{ "both", "cal" },
	{ "hover", "cal" },
	{ "mouse", "cal", true },
	{ "touch", "cal" },
}

local goodMax = 1

-- expected = จำนวนที่คาดว่าจะเป็นค่า MAX
local function pressMax(expected)
	local maxBtn
	local t0 = os.clock()
	repeat
		maxBtn = findMaxButton()
		if maxBtn then break end
		task.wait(0.05)
	until os.clock() - t0 >= 2 or not running

	if not maxBtn then
		dumpMenu()
		return false
	end

	waitStable(maxBtn, 0.8)
	dumpMenu()

	local box = findAmountBox()
	if expected and box and numFrom(box.Text) == expected then
		return true
	end

	local before = functionTexts()
	local function applied()
		if functionTexts() ~= before then return true end
		local b = findAmountBox()
		return (expected and b and numFrom(b.Text) == expected) or false
	end

	for k = 0, #MAX_VARIANTS - 1 do
		if not running then return false end
		if not (maxBtn.Parent and isShown(maxBtn)) then break end
		local idx = ((goodMax - 1 + k) % #MAX_VARIANTS) + 1
		local v = MAX_VARIANTS[idx]
		if clickFrame(maxBtn, 1, v[1], v[2], v[3]) then
			local waitSec = (k == 0) and 0.8 or 0.5
			local t1 = os.clock()
			repeat
				if applied() then
					goodMax = idx
					task.wait(0.03)
					return true
				end
				task.wait(0.03)
			until os.clock() - t1 >= waitSec
		end
	end

	-- สำรอง: ใส่ตัวเลขลงช่องจำนวนเอง
	box = findAmountBox()
	if expected and box then
		pcall(function()
			box.Text = tostring(expected)
			if getconnections then
				for _, sig in ipairs({ box.FocusLost, box:GetPropertyChangedSignal("Text") }) do
					local ok, conns = pcall(getconnections, sig)
					if ok and conns then
						for _, c in ipairs(conns) do
							if c.Function then task.spawn(pcall, c.Function, true) end
						end
					end
				end
			end
		end)
		task.wait(0.1)
		return true
	end
	return false
end

local function transferOnce()
	local r = refs()
	if not (r.group and r.group.Visible) then return "fail" end

	local itemFrame = findItemFrame()
	if not itemFrame then return "done" end

	scrollIntoView(itemFrame)

	local itemsLbl = child(itemFrame, "Holder", "items") or itemFrame:FindFirstChild("items")
	local before = itemsLbl and numFrom(itemsLbl.Text)

	local nm0 = menuName()
	local function itemSelected()
		if not findItemFrame() then return true end
		local t, shown = menuName()
		if shown and nameHasItem(t) then return true end
		if shown and t ~= "" and t ~= nm0 then return true end
		return false
	end
	if not clickUntil(itemFrame, itemSelected, 5) then return "fail" end
	if not findItemFrame() then return "done" end

	task.wait(0.03)

	-- กด MAX ให้ติดก่อน แล้วค่อย Confirm
	if CONFIG.USE_MAX then
		pressMax(before)
	end

	r = refs()
	local function confirmed()
		if not itemFrame.Parent or not isShown(itemFrame) then return true end
		local rr = refs()
		if not (rr.confirm and isShown(rr.confirm)) then return true end
		local now = itemsLbl and numFrom(itemsLbl.Text)
		return (before and now and now < before) or (now == 0) or false
	end
	if r.confirm and clickUntil(r.confirm, confirmed, 5) then
		lastKnown = 0
		return "ok"
	end
	return "fail"
end

local function depositItems()
	if not openTrunk() then return false end
	local success = false
	local maxLoops = CONFIG.USE_MAX and 2 or 10

	for _ = 1, maxLoops do
		if not running then break end
		if not findItemFrame() then
			success = true
			break
		end
		local res = transferOnce()
		if res == "ok" then
			success = true
			-- ตรวจผลจริง: รอจนของหมด/จำนวนลด (ออกทันทีที่เห็นผล) ถ้าของหมดแล้วไปขั้นสุดท้ายเลย ไม่กดซ้ำ
			local t0 = os.clock()
			local gone = false
			repeat
				local f = findItemFrame()
				if not f then gone = true break end
				task.wait(0.03)
			until os.clock() - t0 >= 0.6 or not running
			if gone then break end
			if CONFIG.USE_MAX then break end -- ยังเหลือแต่ MAX แล้ว ไม่ต้องวนกดซ้ำ
		elseif res == "done" then
			success = true
			break
		else
			break
		end
	end

	closeTrunk()
	pcall(updateCountUI)
	return success
end

-- ===================================================== วิ่งอัตโนมัติ (PlayerGui.Button.Run)
local autoRunId = 0

local function getRunButton()
	local g = LP:FindFirstChild("PlayerGui")
	local b = g and g:FindFirstChild("Button")
	return b and b:FindFirstChild("Run")
end

local function pressRunOnce()
	local btn = getRunButton()
	if not btn then return false end
	if clickOnce(btn) then return true end
	local inner = findInnerButton(btn)
	return inner ~= nil and fireFirst(inner)
end

local function startAutoRun()
	if not SETTINGS.AUTO_RUN then return end
	autoRunId += 1
	local myId = autoRunId
	task.spawn(function()
		local lastHum, lastPress = nil, 0
		local baseSpeed, runSpeed, speedMode = 16, nil, nil -- speedMode: nil=ยังไม่รู้ true=ตรวจจากความเร็ว false=ตรวจจากการเดิน
		local stoppedSince = nil
		while running and autoRunId == myId do
			task.wait(0.3)
			local _, hum = charParts()
			if not hum or hum.Health <= 0 then
				lastHum = nil
				continue
			end
			if hum ~= lastHum then -- เกิดใหม่/เริ่มใหม่: เริ่มตรวจใหม่
				lastHum = hum
				baseSpeed = hum.WalkSpeed
				runSpeed, speedMode, stoppedSince = nil, nil, nil
			end

			if speedMode == nil then
				-- กดครั้งเดียว แล้วตรวจว่าความเร็วเพิ่มขึ้นไหม
				if pressRunOnce() then
					lastPress = os.clock()
					task.wait(0.8)
					if hum.WalkSpeed > baseSpeed + 0.5 then
						runSpeed, speedMode = hum.WalkSpeed, true
					else
						speedMode = false
					end
				else
					task.wait(1)
				end

			elseif speedMode == true then
				-- ถ้าความเร็วตกลงมา = หยุดวิ่ง -> กดใหม่ครั้งเดียว
				local running_ = hum.WalkSpeed >= baseSpeed + (runSpeed - baseSpeed) * 0.5
				if not running_ and os.clock() - lastPress > 2 then
					if pressRunOnce() then lastPress = os.clock() end
				end

			else
				-- ตรวจความเร็วไม่ได้: ถ้าหยุดเดินนานแล้วกลับมาเดิน -> กดใหม่ครั้งเดียว
				if hum.MoveDirection.Magnitude > 0.1 then
					if stoppedSince and os.clock() - stoppedSince >= 1 and os.clock() - lastPress > 1.5 then
						if pressRunOnce() then lastPress = os.clock() end
					end
					stoppedSince = nil
				else
					stoppedSince = stoppedSince or os.clock()
				end
			end
		end
	end)
end

-- ===================================================== MAIN LOOP
local function stopMacro()
	running = false
	setToggleVisual(false)
	restoreAllBlockedGuis()
	clearStuckBlur()
end

-- ===================================================== WATCHDOG (v21)
-- ตัวเช็คทุก 0.7 วิ ว่าตอนนี้ควรทำอะไร:
--   * ของยังไม่เต็ม            -> ฟาม
--   * ของเต็ม                  -> ไปเก็บใส่ท้ายรถ
--   * กำลังเก็บ (ท้ายรถเปิดอยู่) -> เก็บต่อให้เสร็จ แล้วค่อยกลับมาฟาม
--   * งานค้าง/ยืนนิ่งนานเกิน    -> ยกเลิกงานนั้นแล้วเริ่มใหม่เอง
local WATCHDOG_INTERVAL = 0.7
local STEP_TIMEOUT = { farm = 120, deposit = 40, probe = 30 }

local worker, workerPhase, workerStart = nil, nil, 0
local loopId = 0

local function workerBusy()
	return worker ~= nil and coroutine.status(worker) ~= "dead"
end

local function cancelWorker()
	if worker then
		pcall(task.cancel, worker)
		worker = nil
	end
	local hrp, hum = charParts()
	if hrp and hum then pcall(function() hum:MoveTo(hrp.Position) end) end
end

local function decidePhase()
	if storageOpen() then return "deposit" end -- กำลังเก็บอยู่ -> เก็บต่อ
	local count = getItemCount()
	if count == nil then
		return SETTINGS.AUTO_OPEN and "probe" or "farm"
	end
	if count >= CONFIG.MAX_COUNT then return "deposit" end
	return "farm"
end

local function runPhase(phase)
	if phase == "deposit" then
		if depositItems() then
			if running then triggerFarmPrompt() end
			task.wait(SETTINGS.FARM_WAIT)
		else
			pcall(closeTrunk)
			task.wait(SETTINGS.LOOP_DELAY)
		end
	elseif phase == "probe" then
		if openTrunk() then
			task.wait(0.2)
			local count = getItemCount()
			if count == nil or count < CONFIG.MAX_COUNT then closeTrunk() end
		end
	else
		triggerFarmPrompt()
		task.wait(SETTINGS.FARM_WAIT)
	end
end

local function startWorker(phase)
	workerPhase, workerStart = phase, os.clock()
	worker = task.spawn(function()
		local ok, err = pcall(runPhase, phase)
		if not ok then warn("[Macro] " .. tostring(err)) end
	end)
end

toggle.Activated:Connect(function()
	if running then
		loopId += 1
		cancelWorker()
		stopMacro()
		return
	end

	running = true
	loopId += 1
	local myLoop = loopId
	setToggleVisual(true)
	startAutoRun()

	task.spawn(function()
		if not (calib.mouse or calib.touch) then calibrate() end

		while running and myLoop == loopId do
			pcall(autoDetectNearestMode)

			local okD, want = pcall(decidePhase)
			if not okD then want = "farm" end

			if workerBusy() then
				local age = os.clock() - workerStart
				if workerPhase == "farm" and want == "deposit" then
					-- ของเต็มระหว่างฟาม/เดินอยู่ -> เลิกฟามแล้วไปเก็บทันที
					cancelWorker()
				elseif age > (STEP_TIMEOUT[workerPhase] or 60) then
					-- งานค้างนานเกิน (ยืนนิ่ง) -> ยกเลิกแล้วเริ่มใหม่
					cancelWorker()
					if workerPhase ~= "farm" then pcall(closeTrunk) end
				end
			end

			if not workerBusy() then
				startWorker(want)
			end

			task.wait(WATCHDOG_INTERVAL)
		end

		cancelWorker()
	end)
end)

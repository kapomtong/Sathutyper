--[[
  ✦ TELEPORT UI  (สไตล์ Sathuu)
  - ฝังพิกัด Custom Locations ไว้ในสคริปต์แล้ว (ไม่ต้องมีไฟล์ JSON ก็ใช้ได้)
  - พื้นหลังไล่สีหลายชั้น + ขอบหมุนวน + แสงวิ่ง + โลโก้เด้ง/ประกาย
  - อนิเมชั่นวาร์ป: จอมืด+เบลอ, วงแหวนกระเพื่อม, เส้นแสงพุ่งออกรอบทิศ, โลโก้หมุน, FOV ซูมพุ่ง, แฟลชขาว, ประกายตอนถึง
  - ค้นหาสถานที่ / เห็นระยะทางจากตัวเรา / บันทึกตำแหน่งใหม่ / Freecam / ปิดสคริปต์
  - ต้องนั่งรถก่อนถึงจะวาร์ปได้ (เหมือนสคริปต์เดิม)
]]

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local Workspace        = game:GetService("Workspace")
local HttpService      = game:GetService("HttpService")
local UIS              = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local Lighting         = game:GetService("Lighting")
local ContentProvider  = game:GetService("ContentProvider")

local LP = Players.LocalPlayer
local PG = LP:WaitForChild("PlayerGui")

-- ===================================================== ตั้งค่า
local CONFIG = {
	FileName            = "CustomLocations.json",
	PlayerWarningRadius = 10,
	LOGO_ID             = "rbxassetid://76441169372717",
	LOGO_THUMB          = "rbxthumb://type=Asset&id=76441169372717&w=420&h=420",
	WarpFov             = 115,
}

-- สถานที่ที่ฝังมากับสคริปต์ (นำเข้าจาก CustomLocations.json)
local BUILTIN = {
	{ name = "โรงพยาบาล",     x = -297,  y = 20, z = 3438,  icon = nil },                -- ยังไม่มีไอดีรูป
	{ name = "ปั้ม",           x = -1285, y = 17, z = 2314,  icon = "102468344398674" },
	{ name = "การาจ",         x = -850,  y = 17, z = 4624,  icon = "113414891289332" },
	{ name = "ขายของ",        x = -521,  y = 15, z = 5398,  icon = "122594706857863" },
	{ name = "โพหิน",         x = -930,  y = 13, z = 6589,  icon = "122594706857863" },
	{ name = "เบลแดง",        x = -496,  y = 22, z = 8127,  icon = "125766243971981" },
	{ name = "ฟามข้าว",       x = 55,    y = 14, z = 128,   icon = "100600116558646" },
	{ name = "ฟามมะม่วง",     x = -1688, y = 18, z = 550,   icon = "124088933252520" }, -- ไอคอนมะม่วงจาก Sathuu
	{ name = "ฟามไวเบรเนียม", x = 2928,  y = 27, z = -62,   icon = "90789610938397"  },
	{ name = "ฟามกล้วย",      x = -1295, y = 28, z = -1327, icon = "84273609389156"  },
	{ name = "ฟามหิน",        x = -3751, y = 53, z = -1047, icon = "126106220040246" },
	{ name = "โพของ",         x = 3551,  y = 58, z = 3709,  icon = "119747117879748" },
}

-- ธีมสี
local C = {
	P  = Color3.fromRGB(0, 205, 255),    -- ฟ้า
	S  = Color3.fromRGB(150, 70, 255),   -- ม่วง
	A  = Color3.fromRGB(255, 120, 220),  -- ชมพู
	BG = Color3.fromRGB(8, 10, 24),
	GOLD = Color3.fromRGB(255, 232, 130),
}
local ROW_COLORS = {
	Color3.fromRGB(0, 205, 255), Color3.fromRGB(150, 90, 255), Color3.fromRGB(255, 120, 220),
	Color3.fromRGB(70, 235, 160), Color3.fromRGB(255, 190, 70), Color3.fromRGB(255, 100, 110),
}

local rng = Random.new()
local connections = {}
local alive = true

-- ===================================================== ข้อมูลสถานที่
local customLocs = {}   -- ที่ผู้ใช้บันทึกเพิ่มเอง (ลบได้)

local function isBuiltinName(n)
	for _, b in ipairs(BUILTIN) do if b.name == n then return true end end
	return false
end

local function saveCustom()
	if writefile then
		pcall(function() writefile(CONFIG.FileName, HttpService:JSONEncode(customLocs)) end)
	end
end

local function loadCustom()
	if readfile and isfile and isfile(CONFIG.FileName) then
		local ok, res = pcall(function() return HttpService:JSONDecode(readfile(CONFIG.FileName)) end)
		if ok and type(res) == "table" then
			for _, l in ipairs(res) do
				if type(l) == "table" and l.name and l.x and l.y and l.z and not isBuiltinName(l.name) then
					table.insert(customLocs, { name = tostring(l.name), x = l.x, y = l.y, z = l.z })
				end
			end
		end
	end
end
pcall(loadCustom)

local function allLocations()
	local out = {}
	for _, b in ipairs(BUILTIN) do table.insert(out, { name = b.name, x = b.x, y = b.y, z = b.z, icon = b.icon, builtin = true }) end
	for _, c in ipairs(customLocs) do table.insert(out, { name = c.name, x = c.x, y = c.y, z = c.z, ref = c }) end
	return out
end

-- ===================================================== Freecam
local freecamActive = false
local Camera = Workspace.CurrentCamera
local freecamPos = Camera.CFrame.Position
local freecamYaw, freecamPitch = 0, 0
local freecamSpeed = 100
local keysDown = {}
local camWasScriptable = false

table.insert(connections, UIS.InputBegan:Connect(function(input, gp)
	if gp then return end
	if input.UserInputType == Enum.UserInputType.Keyboard then keysDown[input.KeyCode] = true end
end))
table.insert(connections, UIS.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.Keyboard then keysDown[input.KeyCode] = nil end
end))
table.insert(connections, UIS.InputChanged:Connect(function(input)
	if freecamActive and input.UserInputType == Enum.UserInputType.MouseMovement then
		freecamYaw = freecamYaw - (input.Delta.X * 0.003)
		freecamPitch = math.clamp(freecamPitch - (input.Delta.Y * 0.003), math.rad(-85), math.rad(85))
	end
end))
table.insert(connections, RunService.RenderStepped:Connect(function(dt)
	Camera = Workspace.CurrentCamera
	if freecamActive then
		camWasScriptable = true
		Camera.CameraType = Enum.CameraType.Scriptable
		local mv = Vector3.zero
		if keysDown[Enum.KeyCode.W] then mv += Vector3.new(0, 0, -1) end
		if keysDown[Enum.KeyCode.S] then mv += Vector3.new(0, 0, 1) end
		if keysDown[Enum.KeyCode.A] then mv += Vector3.new(-1, 0, 0) end
		if keysDown[Enum.KeyCode.D] then mv += Vector3.new(1, 0, 0) end
		if keysDown[Enum.KeyCode.E] then mv += Vector3.new(0, 1, 0) end
		if keysDown[Enum.KeyCode.Q] then mv += Vector3.new(0, -1, 0) end
		local rot = CFrame.fromOrientation(freecamPitch, freecamYaw, 0)
		freecamPos += (rot * mv) * (freecamSpeed * dt)
		Camera.CFrame = CFrame.new(freecamPos) * rot
	elseif camWasScriptable then
		camWasScriptable = false
		Camera.CameraType = Enum.CameraType.Custom
	end
end))

-- ===================================================== ตัวช่วย UI
local parentGui = (gethui and gethui()) or PG
for _, n in ipairs({ "LocationManagerUI", "TeleportFX" }) do
	local o = parentGui:FindFirstChild(n) or PG:FindFirstChild(n)
	if o then o:Destroy() end
end

local function corner(p, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = p
	return c
end

local function rainbow(parent)
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0,    C.P),
		ColorSequenceKeypoint.new(0.35, C.S),
		ColorSequenceKeypoint.new(0.7,  C.A),
		ColorSequenceKeypoint.new(1,    C.P),
	})
	g.Parent = parent
	return g
end

local function tw(obj, t, props, style, dir)
	local tween = TweenService:Create(obj, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	tween:Play()
	return tween
end

local function newFrame(parent, props)
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.BackgroundColor3 = Color3.new(1, 1, 1)
	for k, v in pairs(props) do f[k] = v end
	f.Parent = parent
	return f
end

local function newLabel(parent, props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBold
	l.TextColor3 = Color3.new(1, 1, 1)
	l.TextSize = 12
	for k, v in pairs(props) do l[k] = v end
	l.Parent = parent
	return l
end

local function gloss(parent, strength)
	local g = newFrame(parent, { Size = UDim2.new(1, 0, 0.5, 0), Active = false })
	local gg = Instance.new("UIGradient")
	gg.Rotation = 90
	gg.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, strength or 0.8),
		NumberSequenceKeypoint.new(1, 1),
	})
	gg.Parent = g
	return g
end

local spinners = {}  -- { gradient, speed }
local function spin(grad, speed) table.insert(spinners, { grad, speed }) end

-- ===================================================== GUI หลัก
local gui = Instance.new("ScreenGui")
gui.Name = "LocationManagerUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 99999
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = parentGui

local W, H_FULL, H_MIN = 290, 384, 46

local root = Instance.new("Frame")
root.Size = UDim2.fromOffset(W, H_FULL)
root.Position = UDim2.fromOffset(16, 55)
root.BackgroundTransparency = 1
root.Parent = gui

local rootScale = Instance.new("UIScale")
rootScale.Scale = 0.6
rootScale.Parent = root

local shadow = newFrame(root, {
	Size = UDim2.new(1, 10, 1, 10), Position = UDim2.fromOffset(-5, 5),
	BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.55, Active = false, ZIndex = 0,
})
corner(shadow, 20)

local glow = newFrame(root, {
	Size = UDim2.new(1, 14, 1, 14), Position = UDim2.fromOffset(-7, -7),
	BackgroundTransparency = 0.78, Active = false, ZIndex = 1,
})
corner(glow, 22)
spin(rainbow(glow), 40)

local frame = newFrame(root, { Size = UDim2.fromScale(1, 1), Active = true, ClipsDescendants = true, ZIndex = 2 })
corner(frame, 16)

local bgGrad = Instance.new("UIGradient")
bgGrad.Rotation = 58
bgGrad.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0,    Color3.fromRGB(48, 36, 110)),
	ColorSequenceKeypoint.new(0.45, C.BG),
	ColorSequenceKeypoint.new(1,    Color3.fromRGB(10, 24, 56)),
})
bgGrad.Parent = frame

local function tintLayer(color, rot, t0, t1)
	local f = newFrame(frame, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = color, Active = false })
	corner(f, 16)
	local g = Instance.new("UIGradient")
	g.Rotation = rot
	g.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, t0),
		NumberSequenceKeypoint.new(0.55, t1),
		NumberSequenceKeypoint.new(1, 1),
	})
	g.Parent = f
	return f, g
end
local tintA, tintAGrad = tintLayer(C.P, 35, 0.6, 0.92)
local tintB, tintBGrad = tintLayer(C.A, 215, 0.66, 0.94)

-- ออโรร่าขยับช้าๆ
table.insert(connections, RunService.Heartbeat:Connect(function()
	local t = os.clock()
	tintAGrad.Offset = Vector2.new(0.12 * math.sin(t * 0.7), 0.12 * math.cos(t * 0.5))
	tintBGrad.Offset = Vector2.new(0.12 * math.cos(t * 0.6), 0.12 * math.sin(t * 0.8))
end))

-- แสงวิ่งผ่านทแยง
local sweep = newFrame(frame, {
	Size = UDim2.new(0, 50, 1.9, 0), AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0, -70, 0.5, 0), Rotation = 22, Active = false,
})
do
	local g = Instance.new("UIGradient")
	g.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.86), NumberSequenceKeypoint.new(1, 1),
	})
	g.Parent = sweep
end
task.spawn(function()
	while alive do
		sweep.Position = UDim2.new(0, -70, 0.5, 0)
		local t = tw(sweep, 1.6, { Position = UDim2.new(1, 70, 0.5, 0) }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
		t.Completed:Wait()
		task.wait(3.2)
	end
end)

gloss(frame, 0.82)

local bottomShade = newFrame(frame, {
	Size = UDim2.new(1, 0, 0.4, 0), Position = UDim2.fromScale(0, 0.6),
	BackgroundColor3 = Color3.new(0, 0, 0), Active = false,
})
corner(bottomShade, 16)
do
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.78) })
	g.Parent = bottomShade
end

local rim = newFrame(frame, { Size = UDim2.new(1, -6, 1, -6), Position = UDim2.fromOffset(3, 3), BackgroundTransparency = 1, Active = false })
corner(rim, 13)
do
	local s = Instance.new("UIStroke")
	s.Thickness = 1; s.Transparency = 0.86; s.Parent = rim
end

local stroke = Instance.new("UIStroke")
stroke.Thickness = 2
stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
stroke.Parent = frame
spin(rainbow(stroke), 90)

-- ===================================================== ลากหน้าต่าง
do
	local dragging, startIn, startPos
	frame.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			-- ลากได้เฉพาะแถบหัว
			if i.Position.Y - frame.AbsolutePosition.Y <= 46 * rootScale.Scale then
				dragging, startIn, startPos = true, i.Position, root.Position
				i.Changed:Connect(function()
					if i.UserInputState == Enum.UserInputState.End then dragging = false end
				end)
			end
		end
	end)
	table.insert(connections, UIS.InputChanged:Connect(function(i)
		if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
			local d = i.Position - startIn
			root.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
		end
	end))
end

-- ===================================================== โลโก้
local resolved = {}
local function resolveImage(id)
	if resolved[id] then return resolved[id] end
	local out = id
	pcall(function()
		local objs = game:GetObjects(id)
		for _, o in ipairs(objs or {}) do
			if (o:IsA("Decal") or o:IsA("Texture")) and o.Texture ~= "" then out = o.Texture end
			pcall(function() o:Destroy() end)
		end
	end)
	resolved[id] = out
	return out
end

local logoBox = newFrame(root, {
	Size = UDim2.fromOffset(64, 38), Position = UDim2.fromOffset(6, 4),
	BackgroundTransparency = 1, Active = false, ZIndex = 50,
})
local logoScale = Instance.new("UIScale"); logoScale.Parent = logoBox

local logoImg = Instance.new("ImageLabel")
logoImg.Size = UDim2.fromScale(1, 1)
logoImg.BackgroundTransparency = 1
logoImg.Image = CONFIG.LOGO_ID
logoImg.ScaleType = Enum.ScaleType.Fit
logoImg.ZIndex = 51
logoImg.Parent = logoBox
do
	local g = Instance.new("UIGradient")
	g.Rotation = 20
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0,    Color3.fromRGB(205, 205, 205)),
		ColorSequenceKeypoint.new(0.45, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(0.55, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(1,    Color3.fromRGB(205, 205, 205)),
	})
	g.Parent = logoImg
	spin(g, 60)
end

local logoFallback = newLabel(logoBox, {
	Size = UDim2.fromScale(1, 1), Text = "✦ TP", TextSize = 15, Font = Enum.Font.GothamBlack,
	TextColor3 = C.GOLD, Visible = false, ZIndex = 52,
})

task.spawn(function()
	local function waitLoaded(img, t)
		local t0 = os.clock()
		while os.clock() - t0 < t do
			if img.IsLoaded then return true end
			task.wait(0.1)
		end
		return img.IsLoaded
	end
	local real = resolveImage(CONFIG.LOGO_ID)
	if real ~= CONFIG.LOGO_ID then logoImg.Image = real end
	pcall(function() ContentProvider:PreloadAsync({ logoImg }) end)
	if waitLoaded(logoImg, 2) then return end
	logoImg.Image = CONFIG.LOGO_THUMB
	if waitLoaded(logoImg, 4) then return end
	logoFallback.Visible = true
end)

-- โหลดไอคอนสถานที่ (รองรับทั้งไอดีรูปและไอดี Decal + มีตัวสำรอง)
local function loadIcon(img, id, onFail)
	local full = "rbxassetid://" .. id
	img.Image = full
	task.spawn(function()
		local function waitLoaded(t)
			local t0 = os.clock()
			while os.clock() - t0 < t do
				if not img.Parent then return true end
				if img.IsLoaded then return true end
				task.wait(0.1)
			end
			return img.IsLoaded
		end
		local real = resolveImage(full)
		if not img.Parent then return end
		if real ~= full then img.Image = real end
		if waitLoaded(2) then return end
		img.Image = "rbxthumb://type=Asset&id=" .. id .. "&w=420&h=420"
		if waitLoaded(4) then return end
		if onFail and img.Parent then onFail() end
	end)
end

-- โลโก้ "หายใจ"
table.insert(connections, RunService.Heartbeat:Connect(function()
	logoScale.Scale = 1 + 0.035 * math.sin(os.clock() * 2.2)
	for _, s in ipairs(spinners) do
		s[1].Rotation = (os.clock() * s[2]) % 360
	end
end))

-- ชื่อสคริปต์
local titleLbl = newLabel(root, {
	Size = UDim2.fromOffset(120, 20), Position = UDim2.fromOffset(78, 5),
	Text = "TELEPORT", Font = Enum.Font.GothamBlack, TextSize = 17,
	TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 53,
})
do
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(0.5, C.GOLD),
		ColorSequenceKeypoint.new(1, Color3.new(1, 1, 1)),
	})
	g.Parent = titleLbl
	spin(g, 80)
end
newLabel(root, {
	Size = UDim2.fromOffset(130, 14), Position = UDim2.fromOffset(79, 25),
	Text = "ระบบวาร์ปสถานที่", Font = Enum.Font.GothamMedium, TextSize = 10,
	TextColor3 = Color3.fromRGB(190, 200, 235), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 53,
})

-- โลโก้: กดแล้วเด้ง + ประกาย
local function sparkBurst(parent, cx, cy, count, z)
	local cols = { C.GOLD, Color3.new(1, 1, 1), C.P, C.A }
	for _ = 1, count do
		local d = newFrame(parent, {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(cx, cy),
			Size = UDim2.fromOffset(rng:NextInteger(3, 6), rng:NextInteger(3, 6)),
			BackgroundColor3 = cols[rng:NextInteger(1, #cols)], Rotation = rng:NextInteger(0, 90),
			Active = false, ZIndex = z or 70,
		})
		corner(d, 2)
		local ang, dist, dur = rng:NextNumber(0, math.pi * 2), rng:NextNumber(24, 56), rng:NextNumber(0.4, 0.8)
		tw(d, dur, {
			Position = UDim2.fromOffset(cx + math.cos(ang) * dist, cy + math.sin(ang) * dist),
			BackgroundTransparency = 1, Rotation = d.Rotation + 180,
		})
		task.delay(dur + 0.05, function() d:Destroy() end)
	end
end

local logoHit = Instance.new("TextButton")
logoHit.Size = UDim2.fromScale(1, 1)
logoHit.BackgroundTransparency = 1
logoHit.Text = ""
logoHit.ZIndex = 60
logoHit.Parent = logoBox
local logoBusy = false
logoHit.Activated:Connect(function()
	if logoBusy then return end
	logoBusy = true
	sparkBurst(root, 38, 23, 10)
	tw(logoBox, 0.2, { Rotation = 14 })
	task.delay(0.2, function()
		tw(logoBox, 0.6, { Rotation = 0 }, Enum.EasingStyle.Elastic)
	end)
	task.delay(0.7, function() logoBusy = false end)
end)

-- ===================================================== ปุ่มกลมแบบกระจก
local function roundGlassButton(size, c1, c2, strokeCol)
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(size, size)
	b.BackgroundColor3 = Color3.new(1, 1, 1)
	b.BorderSizePixel = 0
	b.Text = ""
	b.AutoButtonColor = false
	b.ZIndex = 5
	b.Parent = root
	b.ZIndex = 60
	local cr = Instance.new("UICorner"); cr.CornerRadius = UDim.new(1, 0); cr.Parent = b
	local g = Instance.new("UIGradient"); g.Rotation = 90; g.Color = ColorSequence.new(c1, c2); g.Parent = b
	local st = Instance.new("UIStroke"); st.Thickness = 1.2; st.Color = strokeCol; st.Transparency = 0.15
	st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; st.Parent = b
	b.MouseEnter:Connect(function() tw(st, 0.15, { Thickness = 2, Transparency = 0 }) end)
	b.MouseLeave:Connect(function() tw(st, 0.15, { Thickness = 1.2, Transparency = 0.15 }) end)
	return b
end

local function bar(parent, w, h, rot)
	local f = newFrame(parent, {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(w, h), Rotation = rot, Active = false, ZIndex = 61,
	})
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1, 0); c.Parent = f
	return f
end

local closeBtn = roundGlassButton(20, Color3.fromRGB(255, 110, 110), Color3.fromRGB(170, 20, 45), Color3.fromRGB(255, 175, 175))
closeBtn.Position = UDim2.fromOffset(W - 30, 13)
bar(closeBtn, 10, 2, 45); bar(closeBtn, 10, 2, -45)

local minBtn = roundGlassButton(20, C.P:Lerp(C.BG, 0.35), C.S:Lerp(C.BG, 0.2), C.P)
minBtn.Position = UDim2.fromOffset(W - 56, 13)
local minBar = bar(minBtn, 9, 2, 0)
local minBox = newFrame(minBtn, {
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(8, 8),
	BackgroundTransparency = 1, Visible = false, Active = false, ZIndex = 61,
})
corner(minBox, 2)
do local s = Instance.new("UIStroke"); s.Thickness = 1.5; s.Parent = minBox end

local line = newFrame(frame, { Size = UDim2.new(1, -28, 0, 1), Position = UDim2.fromOffset(14, 45) })
rainbow(line)

-- ===================================================== เนื้อหา
local content = newFrame(frame, {
	Size = UDim2.new(1, 0, 1, -50), Position = UDim2.fromOffset(0, 50), BackgroundTransparency = 1, Active = false,
})

local function glassBox(parent, pos, size, r)
	local f = newFrame(parent, { Position = pos, Size = size, BackgroundColor3 = Color3.fromRGB(14, 18, 42), BackgroundTransparency = 0.25 })
	corner(f, r or 9)
	local s = Instance.new("UIStroke"); s.Thickness = 1.2; s.Transparency = 0.45; s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; s.Parent = f
	rainbow(s)
	return f, s
end

-- ช่องค้นหา
local searchHolder = glassBox(content, UDim2.fromOffset(10, 0), UDim2.new(1, -20, 0, 28))
newLabel(searchHolder, { Size = UDim2.fromOffset(24, 28), Text = "🔍", TextSize = 12, Font = Enum.Font.Gotham })
local searchBox = Instance.new("TextBox")
searchBox.Size = UDim2.new(1, -30, 1, 0)
searchBox.Position = UDim2.fromOffset(26, 0)
searchBox.BackgroundTransparency = 1
searchBox.Font = Enum.Font.GothamMedium
searchBox.PlaceholderText = "ค้นหาสถานที่..."
searchBox.PlaceholderColor3 = Color3.fromRGB(140, 150, 190)
searchBox.Text = ""
searchBox.TextSize = 12
searchBox.TextColor3 = Color3.new(1, 1, 1)
searchBox.TextXAlignment = Enum.TextXAlignment.Left
searchBox.ClearTextOnFocus = false
searchBox.Parent = searchHolder

-- รายการสถานที่
local listHolder = glassBox(content, UDim2.fromOffset(10, 36), UDim2.new(1, -20, 0, 188), 10)
local scroll = Instance.new("ScrollingFrame")
scroll.Size = UDim2.new(1, -6, 1, -8)
scroll.Position = UDim2.fromOffset(3, 4)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 3
scroll.ScrollBarImageColor3 = C.P
scroll.CanvasSize = UDim2.new()
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.Parent = listHolder
local layout = Instance.new("UIListLayout")
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding = UDim.new(0, 4)
layout.Parent = scroll
local pad = Instance.new("UIPadding")
pad.PaddingLeft = UDim.new(0, 3); pad.PaddingRight = UDim.new(0, 5); pad.PaddingTop = UDim.new(0, 2); pad.PaddingBottom = UDim.new(0, 2)
pad.Parent = scroll

-- ช่องชื่อ + ปุ่มบันทึก / Freecam
local nameHolder = glassBox(content, UDim2.fromOffset(10, 232), UDim2.new(1, -20, 0, 28))
local nameBox = Instance.new("TextBox")
nameBox.Size = UDim2.new(1, -16, 1, 0)
nameBox.Position = UDim2.fromOffset(8, 0)
nameBox.BackgroundTransparency = 1
nameBox.Font = Enum.Font.GothamMedium
nameBox.PlaceholderText = "ตั้งชื่อสถานที่ใหม่..."
nameBox.PlaceholderColor3 = Color3.fromRGB(140, 150, 190)
nameBox.Text = ""
nameBox.TextSize = 12
nameBox.TextColor3 = Color3.new(1, 1, 1)
nameBox.TextXAlignment = Enum.TextXAlignment.Left
nameBox.ClearTextOnFocus = false
nameBox.Parent = nameHolder

local function fancyButton(parent, text, c1, c2, pos, size)
	local f = newFrame(parent, { Position = pos, Size = size, ClipsDescendants = true })
	corner(f, 10)
	local g = Instance.new("UIGradient"); g.Rotation = 90; g.Color = ColorSequence.new(c1, c2); g.Parent = f
	local st = Instance.new("UIStroke"); st.Thickness = 1.4; st.Transparency = 0.5; st.Parent = f
	gloss(f, 0.6)
	local shine = newFrame(f, {
		Size = UDim2.new(0, 22, 2.2, 0), AnchorPoint = Vector2.new(0.5, 0.5), Rotation = 20,
		Position = UDim2.new(-0.2, 0, 0.5, 0), Active = false,
	})
	do
		local sg = Instance.new("UIGradient")
		sg.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.55), NumberSequenceKeypoint.new(1, 1) })
		sg.Parent = shine
	end
	local sc = Instance.new("UIScale"); sc.Parent = f
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromScale(1, 1)
	b.BackgroundTransparency = 1
	b.Text = text
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Font = Enum.Font.GothamBold
	b.TextSize = 12
	b.AutoButtonColor = false
	b.ZIndex = 5
	b.Parent = f
	b.MouseEnter:Connect(function()
		shine.Position = UDim2.new(-0.2, 0, 0.5, 0)
		tw(shine, 0.5, { Position = UDim2.new(1.2, 0, 0.5, 0) })
		tw(st, 0.15, { Transparency = 0.1 })
	end)
	b.MouseLeave:Connect(function()
		tw(st, 0.2, { Transparency = 0.5 })
		tw(sc, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
	end)
	b.MouseButton1Down:Connect(function() tw(sc, 0.08, { Scale = 0.92 }) end)
	b.MouseButton1Up:Connect(function() tw(sc, 0.3, { Scale = 1 }, Enum.EasingStyle.Back) end)
	return b, f, g
end

local saveBtn = fancyButton(content, "💾 บันทึกตำแหน่งนี้", Color3.fromRGB(70, 235, 160), Color3.fromRGB(20, 140, 100),
	UDim2.fromOffset(10, 266), UDim2.new(0.58, -12, 0, 30))
local fcBtn, fcFrame, fcGrad = fancyButton(content, "📷 Freecam", Color3.fromRGB(80, 160, 255), Color3.fromRGB(60, 60, 200),
	UDim2.new(0.58, 0, 0, 266), UDim2.new(0.42, -10, 0, 30))

local statusLbl = newLabel(content, {
	Size = UDim2.new(1, -20, 0, 16), Position = UDim2.fromOffset(10, 302),
	Text = "● พร้อม — เลือกสถานที่ที่จะวาร์ป", Font = Enum.Font.GothamMedium, TextSize = 10,
	TextColor3 = Color3.fromRGB(190, 205, 240), TextXAlignment = Enum.TextXAlignment.Center,
})
local statusToken = 0
local function toast(text, color, hold)
	statusToken += 1
	local my = statusToken
	statusLbl.Text = text
	statusLbl.TextColor3 = color or Color3.new(1, 1, 1)
	task.delay(hold or 2, function()
		if my == statusToken and statusLbl.Parent then
			statusLbl.Text = "● พร้อม — เลือกสถานที่ที่จะวาร์ป"
			statusLbl.TextColor3 = Color3.fromRGB(190, 205, 240)
		end
	end)
end

-- ===================================================== วาร์ป
local function getRoot()
	local ch = LP.Character
	return ch and ch:FindFirstChild("HumanoidRootPart")
end

local function checkNearbyPlayers(pos)
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= LP and p.Character then
			local hrp = p.Character:FindFirstChild("HumanoidRootPart")
			if hrp then
				local d = (hrp.Position - pos).Magnitude
				if d <= CONFIG.PlayerWarningRadius then return true, p.Name, math.floor(d) end
			end
		end
	end
	return false
end

local function executeTeleport(destPos)
	local ch = LP.Character
	if not ch then return false end
	local hum = ch:FindFirstChildOfClass("Humanoid")
	local seat = hum and hum.SeatPart
	if not seat then return false, "NOT_IN_VEHICLE" end
	local target = CFrame.new(destPos + Vector3.new(0, 5, 0))
	local model = seat:FindFirstAncestorOfClass("Model")
	if model then model:PivotTo(target) else ch:PivotTo(target) end
	return true
end

local warping = false

local function playWarp(loc)
	warping = true
	local cam = Workspace.CurrentCamera
	local baseFov = cam.FieldOfView
	local destPos = Vector3.new(loc.x, loc.y, loc.z)

	local fx = Instance.new("ScreenGui")
	fx.Name = "TeleportFX"
	fx.ResetOnSpawn = false
	fx.IgnoreGuiInset = true
	fx.DisplayOrder = 100000
	fx.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	fx.Parent = parentGui

	-- ฉากมืดไล่สี
	local dim = newFrame(fx, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(6, 4, 20), BackgroundTransparency = 1, ZIndex = 1 })
	local dimGrad = Instance.new("UIGradient")
	dimGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(20, 10, 60)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(4, 6, 20)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(40, 10, 70)),
	})
	dimGrad.Parent = dim
	local dimSpin = RunService.Heartbeat:Connect(function() dimGrad.Rotation = (os.clock() * 120) % 360 end)
	tw(dim, 0.3, { BackgroundTransparency = 0.25 })

	local blur = Instance.new("BlurEffect")
	blur.Size = 0
	blur.Parent = Lighting
	tw(blur, 0.8, { Size = 22 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

	-- จุดศูนย์กลาง
	local center = newFrame(fx, { Size = UDim2.fromOffset(0, 0), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), BackgroundTransparency = 1, ZIndex = 2 })

	-- วงแหวนกระเพื่อม
	local function ring(delay, endSize, col, thick)
		task.delay(delay, function()
			if not center.Parent then return end
			local r = newFrame(center, { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(20, 20), BackgroundTransparency = 1, ZIndex = 3 })
			corner(r, 1000)
			local s = Instance.new("UIStroke"); s.Thickness = thick or 4; s.Color = col or Color3.new(1, 1, 1); s.Parent = r
			local sg = rainbow(s)
			tw(r, 0.9, { Size = UDim2.fromOffset(endSize, endSize) })
			tw(s, 0.9, { Transparency = 1, Thickness = 0.5 })
			task.spawn(function()
				local t0 = os.clock()
				while r.Parent and os.clock() - t0 < 1 do sg.Rotation = (os.clock() - t0) * 360; task.wait() end
			end)
			task.delay(1, function() r:Destroy() end)
		end)
	end
	for i = 0, 4 do ring(i * 0.17, 900 + i * 120) end

	-- เส้นแสงพุ่งออกรอบทิศ
	local streakCols = { C.P, C.S, C.A, Color3.new(1, 1, 1), C.GOLD }
	local function streak(angle, len, dur)
		local holder = newFrame(center, {
			AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(2200, 3),
			BackgroundTransparency = 1, Rotation = angle, ZIndex = 3,
		})
		local s = newFrame(holder, {
			AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0.5, 40, 0.5, 0),
			Size = UDim2.fromOffset(0, rng:NextInteger(2, 4)), BackgroundColor3 = streakCols[rng:NextInteger(1, #streakCols)],
		})
		local g = Instance.new("UIGradient")
		g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.6, 0.1), NumberSequenceKeypoint.new(1, 0.5) })
		g.Parent = s
		tw(s, dur, { Size = UDim2.fromOffset(len, s.Size.Y.Offset), Position = UDim2.new(0.5, 40 + len * 1.3, 0.5, 0) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.delay(dur * 0.7, function() tw(s, dur * 0.3, { BackgroundTransparency = 1 }) end)
		task.delay(dur + 0.1, function() holder:Destroy() end)
	end
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < 0.85 and fx.Parent do
			for _ = 1, 3 do streak(rng:NextInteger(0, 359), rng:NextInteger(180, 420), rng:NextNumber(0.35, 0.6)) end
			task.wait(0.04)
		end
	end)

	-- ประกายลอยขึ้น
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < 0.9 and fx.Parent do
			local d = newFrame(fx, {
				Size = UDim2.fromOffset(rng:NextInteger(3, 7), rng:NextInteger(3, 7)),
				Position = UDim2.fromScale(rng:NextNumber(0, 1), rng:NextNumber(0.6, 1)),
				BackgroundColor3 = streakCols[rng:NextInteger(1, #streakCols)], Rotation = rng:NextInteger(0, 90), ZIndex = 4,
			})
			corner(d, 2)
			local dur = rng:NextNumber(0.5, 0.9)
			tw(d, dur, { Position = UDim2.new(d.Position.X.Scale, 0, d.Position.Y.Scale - 0.4, 0), BackgroundTransparency = 1, Rotation = d.Rotation + 200 })
			task.delay(dur + 0.05, function() d:Destroy() end)
			task.wait(0.03)
		end
	end)

	-- ออร่าหลังโลโก้
	local aura = newFrame(center, { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(0, 0), BackgroundTransparency = 0.55, ZIndex = 5 })
	corner(aura, 1000)
	local auraGrad = rainbow(aura)
	local auraSpin = RunService.Heartbeat:Connect(function() auraGrad.Rotation = (os.clock() * 300) % 360 end)
	tw(aura, 0.5, { Size = UDim2.fromOffset(190, 190) }, Enum.EasingStyle.Back)

	-- โลโก้กลางจอ หมุน + ขยาย
	local bigLogo = Instance.new("ImageLabel")
	bigLogo.AnchorPoint = Vector2.new(0.5, 0.5)
	bigLogo.Size = UDim2.fromOffset(0, 0)
	bigLogo.BackgroundTransparency = 1
	bigLogo.Image = logoImg.Image
	bigLogo.ScaleType = Enum.ScaleType.Fit
	bigLogo.ZIndex = 8
	bigLogo.Parent = center
	tw(bigLogo, 0.5, { Size = UDim2.fromOffset(150, 88) }, Enum.EasingStyle.Back)
	local logoSpin = RunService.Heartbeat:Connect(function()
		bigLogo.Rotation = math.sin(os.clock() * 9) * 8
	end)

	-- ไอคอนของสถานที่ปลายทาง (เด้งขึ้นเหนือโลโก้)
	local destIcon, destRing
	if loc.icon then
		-- วงแหวนไล่สีหมุนรอบไอคอน
		destRing = newFrame(center, {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(0, -175),
			Size = UDim2.fromOffset(0, 0), BackgroundColor3 = Color3.fromRGB(10, 8, 30), BackgroundTransparency = 0.35, ZIndex = 8,
		})
		corner(destRing, 1000)
		local drStroke = Instance.new("UIStroke"); drStroke.Thickness = 3.5; drStroke.Parent = destRing
		local drGrad = rainbow(drStroke)

		destIcon = Instance.new("ImageLabel")
		destIcon.AnchorPoint = Vector2.new(0.5, 0.5)
		destIcon.Position = UDim2.fromOffset(0, -175)
		destIcon.Size = UDim2.fromOffset(0, 0)
		destIcon.BackgroundTransparency = 1
		destIcon.ScaleType = Enum.ScaleType.Fit
		destIcon.ZIndex = 9
		destIcon.Parent = center
		loadIcon(destIcon, loc.icon)
		tw(destRing, 0.55, { Size = UDim2.fromOffset(150, 150) }, Enum.EasingStyle.Back)
		tw(destIcon, 0.6, { Size = UDim2.fromOffset(110, 110) }, Enum.EasingStyle.Back)
		local floatConn
		floatConn = RunService.Heartbeat:Connect(function()
			if not destIcon.Parent then floatConn:Disconnect() return end
			local t = os.clock()
			destIcon.Rotation = math.sin(t * 4) * 6
			drGrad.Rotation = (t * 240) % 360
		end)
	end

	-- ข้อความ
	local warpTxt = newLabel(center, {
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(0, 70), Size = UDim2.fromOffset(420, 22),
		Text = "✦ กำลังวาร์ปไปยัง ✦", Font = Enum.Font.GothamBold, TextSize = 15,
		TextColor3 = Color3.fromRGB(215, 225, 255), TextTransparency = 1, ZIndex = 9,
	})
	local destTxt = newLabel(center, {
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(0, 94), Size = UDim2.fromOffset(460, 44),
		Text = loc.name, Font = Enum.Font.GothamBlack, TextSize = 32, TextTransparency = 1, ZIndex = 9,
	})
	local destStroke = Instance.new("UIStroke")
	destStroke.Thickness = 2; destStroke.Color = Color3.fromRGB(40, 10, 90); destStroke.Transparency = 1; destStroke.Parent = destTxt
	local destGrad = Instance.new("UIGradient")
	destGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, C.P), ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)), ColorSequenceKeypoint.new(1, C.A),
	})
	destGrad.Parent = destTxt
	local destScale = Instance.new("UIScale"); destScale.Scale = 0.6; destScale.Parent = destTxt
	tw(warpTxt, 0.35, { TextTransparency = 0 })
	tw(destTxt, 0.4, { TextTransparency = 0 })
	tw(destStroke, 0.4, { Transparency = 0.2 })
	tw(destScale, 0.5, { Scale = 1 }, Enum.EasingStyle.Back)
	local txtShimmer = RunService.Heartbeat:Connect(function() destGrad.Offset = Vector2.new(math.sin(os.clock() * 5) * 0.4, 0) end)

	-- แถบโหลด
	local barBack = newFrame(center, {
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(0, 146), Size = UDim2.fromOffset(240, 6),
		BackgroundColor3 = Color3.fromRGB(20, 24, 50), BackgroundTransparency = 0.2, ZIndex = 9,
	})
	corner(barBack, 3)
	local barFill = newFrame(barBack, { Size = UDim2.fromScale(0, 1), ZIndex = 10 })
	corner(barFill, 3)
	rainbow(barFill)
	tw(barFill, 0.95, { Size = UDim2.fromScale(1, 1) }, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)

	-- FOV พุ่ง
	tw(cam, 0.95, { FieldOfView = CONFIG.WarpFov }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

	task.wait(1)

	-- ===== วาร์ปจริง + แฟลชขาว
	local flash = newFrame(fx, { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 50 })
	tw(flash, 0.08, { BackgroundTransparency = 0 })
	task.wait(0.09)
	local ok, status = executeTeleport(destPos)
	blur.Size = 6

	-- เปลี่ยนเป็นหน้าจอ "ถึงแล้ว"
	warpTxt.Text = ok and "✦ มาถึงแล้ว ✦" or "✦ วาร์ปไม่สำเร็จ ✦"
	warpTxt.TextColor3 = ok and C.GOLD or Color3.fromRGB(255, 120, 120)
	barBack.Visible = false
	tw(aura, 0.3, { Size = UDim2.fromOffset(240, 240), BackgroundTransparency = 0.8 })
	tw(bigLogo, 0.4, { Size = UDim2.fromOffset(170, 100) }, Enum.EasingStyle.Back)
	if destIcon then
		-- ไอคอนเด้งตอนถึงจุดหมาย
		tw(destIcon, 0.2, { Size = UDim2.fromOffset(145, 145) }, Enum.EasingStyle.Quad)
		tw(destRing, 0.2, { Size = UDim2.fromOffset(185, 185) }, Enum.EasingStyle.Quad)
		task.delay(0.2, function()
			if destIcon.Parent then
				tw(destIcon, 0.5, { Size = UDim2.fromOffset(120, 120) }, Enum.EasingStyle.Elastic)
				tw(destRing, 0.5, { Size = UDim2.fromOffset(160, 160) }, Enum.EasingStyle.Elastic)
			end
		end)
	end

	-- คลื่นกระแทกตอนถึง
	for i = 0, 2 do ring(i * 0.1, 1100 + i * 150, C.GOLD, 5) end
	for _ = 1, 40 do streak(rng:NextInteger(0, 359), rng:NextInteger(120, 320), rng:NextNumber(0.4, 0.7)) end

	tw(flash, 0.6, { BackgroundTransparency = 1 })
	tw(cam, 0.8, { FieldOfView = baseFov }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	tw(blur, 0.8, { Size = 0 })

	task.wait(0.95)

	-- ปิดฉาก
	tw(dim, 0.5, { BackgroundTransparency = 1 })
	tw(bigLogo, 0.45, { Size = UDim2.fromOffset(0, 0), ImageTransparency = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
	tw(aura, 0.45, { Size = UDim2.fromOffset(0, 0) }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
	tw(warpTxt, 0.4, { TextTransparency = 1 })
	tw(destTxt, 0.4, { TextTransparency = 1 })
	tw(destStroke, 0.4, { Transparency = 1 })
	if destIcon then
		tw(destIcon, 0.45, { Size = UDim2.fromOffset(0, 0), ImageTransparency = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		tw(destRing, 0.45, { Size = UDim2.fromOffset(0, 0) }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
	end
	task.wait(0.55)

	for _, c in ipairs({ dimSpin, auraSpin, logoSpin, txtShimmer }) do c:Disconnect() end
	pcall(function() blur:Destroy() end)
	pcall(function() cam.FieldOfView = baseFov end)
	fx:Destroy()
	warping = false
	return ok, status
end

local pendingTarget, pendingExpiry = nil, 0

local function requestWarp(loc, flashRow)
	if warping then return end
	local ch = LP.Character
	local hum = ch and ch:FindFirstChildOfClass("Humanoid")
	if not hum or not hum.SeatPart then
		toast("🚨 กรุณานั่งรถก่อน!", Color3.fromRGB(255, 120, 120))
		flashRow(Color3.fromRGB(255, 80, 90))
		return
	end

	local destPos = Vector3.new(loc.x, loc.y, loc.z)
	local has, pname, dist = checkNearbyPlayers(destPos)
	local now = os.clock()
	if has and not (pendingTarget == loc and now < pendingExpiry) then
		pendingTarget, pendingExpiry = loc, now + 3
		toast(string.format("⚠️ มีผู้เล่น %s อยู่ใกล้ (%dm) — กดอีกครั้งเพื่อยืนยัน", pname, dist), Color3.fromRGB(255, 200, 90), 3)
		flashRow(Color3.fromRGB(255, 190, 70))
		return
	end
	pendingTarget = nil

	toast("🚀 กำลังวาร์ป → " .. loc.name, C.GOLD, 3)
	task.spawn(function()
		local ok, status = playWarp(loc)
		if ok then
			toast("✨ วาร์ปสำเร็จ: " .. loc.name, Color3.fromRGB(110, 255, 180), 2.5)
		else
			toast("🚨 วาร์ปไม่สำเร็จ (ลงจากรถ?)", Color3.fromRGB(255, 120, 120), 2.5)
		end
	end)
end

-- ===================================================== รายการสถานที่
local rows = {}  -- { frame, name, distLbl, loc }

local function fmtDist(d)
	if d >= 1000 then return string.format("%.1fkm", d / 1000) end
	return string.format("%dm", math.floor(d))
end

local function applyFilter()
	local q = string.lower(searchBox.Text)
	for _, r in ipairs(rows) do
		r.frame.Visible = (q == "") or (string.find(string.lower(r.loc.name), q, 1, true) ~= nil)
	end
end

local function refreshList()
	for _, r in ipairs(rows) do r.frame:Destroy() end
	table.clear(rows)

	for i, loc in ipairs(allLocations()) do
		local col = ROW_COLORS[(i - 1) % #ROW_COLORS + 1]

		local row = newFrame(scroll, {
			Size = UDim2.new(1, 0, 0, 36), BackgroundColor3 = Color3.fromRGB(24, 28, 60), LayoutOrder = i,
			BackgroundTransparency = 1, ClipsDescendants = true,
		})
		corner(row, 8)
		local rg = Instance.new("UIGradient")
		rg.Color = ColorSequence.new(col:Lerp(Color3.fromRGB(14, 16, 40), 0.7), Color3.fromRGB(22, 24, 54))
		rg.Parent = row
		local rs = Instance.new("UIStroke")
		rs.Thickness = 1.2; rs.Color = col; rs.Transparency = 0.8; rs.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; rs.Parent = row

		-- แถบสีด้านซ้าย
		local accent = newFrame(row, { Size = UDim2.new(0, 4, 1, 0), BackgroundColor3 = col, Active = false })
		local ag = Instance.new("UIGradient"); ag.Rotation = 90
		ag.Color = ColorSequence.new(col, col:Lerp(C.S, 0.6)); ag.Parent = accent

		-- ไอคอนสถานที่ (ถ้าไม่มี/โหลดไม่ได้ ใช้เลขลำดับแทน)
		local numLbl = newLabel(row, {
			Size = UDim2.fromOffset(28, 36), Position = UDim2.fromOffset(9, 0),
			Text = string.format("%02d", i), TextSize = 10, Font = Enum.Font.GothamBlack,
			TextColor3 = col, TextTransparency = 0.15,
		})
		if loc.icon then
			numLbl.Visible = false
			local ic = Instance.new("ImageLabel")
			ic.Size = UDim2.fromOffset(28, 28)
			ic.Position = UDim2.fromOffset(9, 4)
			ic.BackgroundTransparency = 1
			ic.ScaleType = Enum.ScaleType.Fit
			ic.ZIndex = 3
			ic.Parent = row
			loadIcon(ic, loc.icon, function() ic:Destroy(); numLbl.Visible = true end)
		end

		local nameLbl = newLabel(row, {
			Size = UDim2.new(1, -126, 0, 18), Position = UDim2.fromOffset(42, 3),
			Text = loc.name, TextSize = 13, Font = Enum.Font.GothamBold,
			TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
		})
		newLabel(row, {
			Size = UDim2.new(1, -126, 0, 12), Position = UDim2.fromOffset(42, 21),
			Text = string.format("%d, %d, %d", loc.x, loc.y, loc.z), TextSize = 9, Font = Enum.Font.Gotham,
			TextColor3 = Color3.fromRGB(150, 160, 205), TextXAlignment = Enum.TextXAlignment.Left,
		})

		local distLbl = newLabel(row, {
			Size = UDim2.fromOffset(52, 36), Position = UDim2.new(1, loc.builtin and -58 or -84, 0, 0),
			Text = "-", TextSize = 10, Font = Enum.Font.GothamBold, TextColor3 = col, TextXAlignment = Enum.TextXAlignment.Right,
		})

		local hit = Instance.new("TextButton")
		hit.Size = UDim2.new(1, loc.builtin and 0 or -26, 1, 0)
		hit.BackgroundTransparency = 1
		hit.Text = ""
		hit.ZIndex = 5
		hit.Parent = row

		local ripple = newFrame(row, {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.3, 0.5), Size = UDim2.fromOffset(0, 0),
			BackgroundColor3 = col, BackgroundTransparency = 1, Active = false, ZIndex = 2,
		})
		corner(ripple, 100)

		hit.MouseEnter:Connect(function()
			tw(rs, 0.15, { Transparency = 0.2 })
			tw(row, 0.15, { BackgroundTransparency = 0.05 })
			tw(accent, 0.2, { Size = UDim2.new(0, 7, 1, 0) })
		end)
		hit.MouseLeave:Connect(function()
			tw(rs, 0.2, { Transparency = 0.8 })
			tw(row, 0.2, { BackgroundTransparency = 0.2 })
			tw(accent, 0.2, { Size = UDim2.new(0, 4, 1, 0) })
		end)

		local function flashRow(c)
			rs.Color = c
			rs.Transparency = 0
			tw(rs, 0.8, { Transparency = 0.8 })
			task.delay(0.8, function() if rs.Parent then rs.Color = col end end)
		end

		hit.Activated:Connect(function()
			ripple.Size = UDim2.fromOffset(0, 0)
			ripple.BackgroundTransparency = 0.4
			tw(ripple, 0.45, { Size = UDim2.fromOffset(320, 320), BackgroundTransparency = 1 })
			requestWarp(loc, flashRow)
		end)

		-- ปุ่มลบ (เฉพาะที่บันทึกเอง)
		if not loc.builtin then
			local del = Instance.new("TextButton")
			del.Size = UDim2.fromOffset(22, 22)
			del.Position = UDim2.new(1, -26, 0.5, -11)
			del.BackgroundColor3 = Color3.new(1, 1, 1)
			del.Text = "✕"
			del.TextColor3 = Color3.new(1, 1, 1)
			del.Font = Enum.Font.GothamBold
			del.TextSize = 11
			del.AutoButtonColor = false
			del.ZIndex = 6
			del.Parent = row
			corner(del, 7)
			local dg = Instance.new("UIGradient"); dg.Rotation = 90
			dg.Color = ColorSequence.new(Color3.fromRGB(255, 110, 110), Color3.fromRGB(170, 20, 45)); dg.Parent = del
			del.Activated:Connect(function()
				local idx = table.find(customLocs, loc.ref)
				if idx then table.remove(customLocs, idx) end
				saveCustom()
				refreshList()
				toast("🗑️ ลบ " .. loc.name .. " แล้ว", Color3.fromRGB(255, 160, 160))
			end)
		end

		table.insert(rows, { frame = row, loc = loc, distLbl = distLbl })

		-- อนิเมชั่นเข้าทีละแถว
		row.Position = UDim2.fromOffset(-30, 0)
		task.delay(0.04 * i, function()
			if row.Parent then tw(row, 0.35, { BackgroundTransparency = 0.2 }, Enum.EasingStyle.Quad) end
		end)
		nameLbl.TextTransparency = 1
		task.delay(0.04 * i, function()
			if nameLbl.Parent then tw(nameLbl, 0.35, { TextTransparency = 0 }) end
		end)
	end
	applyFilter()
end

searchBox:GetPropertyChangedSignal("Text"):Connect(applyFilter)
refreshList()

-- อัปเดตระยะทางทุก 0.4 วิ
task.spawn(function()
	while alive do
		local hrp = getRoot()
		if hrp then
			for _, r in ipairs(rows) do
				if r.distLbl.Parent then
					r.distLbl.Text = fmtDist((hrp.Position - Vector3.new(r.loc.x, r.loc.y, r.loc.z)).Magnitude)
				end
			end
		end
		task.wait(0.4)
	end
end)

-- ===================================================== ปุ่มต่างๆ
saveBtn.Activated:Connect(function()
	local name = nameBox.Text
	if name == "" then name = "สถานที่ " .. (#customLocs + 1) end
	local hrp = getRoot()
	if not hrp then toast("🚨 ไม่พบตัวละคร", Color3.fromRGB(255, 120, 120)) return end
	local pos = freecamActive and freecamPos or hrp.Position
	table.insert(customLocs, { name = name, x = math.round(pos.X), y = math.round(pos.Y), z = math.round(pos.Z) })
	saveCustom()
	nameBox.Text = ""
	refreshList()
	scroll.CanvasPosition = Vector2.new(0, 99999)
	toast("💾 บันทึก " .. name .. " แล้ว", Color3.fromRGB(110, 255, 180))
end)

fcBtn.Activated:Connect(function()
	freecamActive = not freecamActive
	if freecamActive then
		Camera = Workspace.CurrentCamera
		freecamPos = Camera.CFrame.Position
		local look = Camera.CFrame.LookVector
		freecamYaw = math.atan2(-look.X, -look.Z)
		freecamPitch = math.asin(look.Y)
		fcGrad.Color = ColorSequence.new(Color3.fromRGB(70, 235, 160), Color3.fromRGB(20, 140, 100))
		fcBtn.Text = "📷 เปิดอยู่"
		toast("📷 Freecam: WASD+QE เคลื่อนที่ / เมาส์หมุน", Color3.fromRGB(150, 220, 255), 3)
	else
		fcGrad.Color = ColorSequence.new(Color3.fromRGB(80, 160, 255), Color3.fromRGB(60, 60, 200))
		fcBtn.Text = "📷 Freecam"
	end
end)

-- ย่อ/ขยาย
local minimized = false
minBtn.Activated:Connect(function()
	minimized = not minimized
	minBar.Visible = not minimized
	minBox.Visible = minimized
	if minimized then
		content.Visible = false
		tw(root, 0.35, { Size = UDim2.fromOffset(W, H_MIN) }, Enum.EasingStyle.Quint)
	else
		tw(root, 0.4, { Size = UDim2.fromOffset(W, H_FULL) }, Enum.EasingStyle.Back)
		task.delay(0.15, function() if not minimized then content.Visible = true end end)
	end
end)

-- ปิดสคริปต์ (มีหน้าต่างยืนยัน)
local function unloadScript()
	alive = false
	freecamActive = false
	pcall(function()
		Workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
	end)
	for _, c in ipairs(connections) do pcall(function() c:Disconnect() end) end
	pcall(function() gui:Destroy() end)
	local fxg = parentGui:FindFirstChild("TeleportFX")
	if fxg then fxg:Destroy() end
end

local confirmOpen = false
closeBtn.Activated:Connect(function()
	if confirmOpen then return end
	confirmOpen = true

	local dim = Instance.new("TextButton")
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Color3.fromRGB(4, 6, 14)
	dim.BackgroundTransparency = 1
	dim.AutoButtonColor = false
	dim.Text = ""
	dim.ZIndex = 200
	dim.Parent = gui
	tw(dim, 0.2, { BackgroundTransparency = 0.4 })

	local card = newFrame(dim, {
		Size = UDim2.fromOffset(280, 140), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Active = true, ClipsDescendants = true, ZIndex = 201,
	})
	corner(card, 18)
	local cs = Instance.new("UIScale"); cs.Scale = 0.7; cs.Parent = card
	tw(cs, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
	local cg = Instance.new("UIGradient"); cg.Rotation = 60
	cg.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(60, 30, 120)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(16, 20, 40)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(20, 40, 90)),
	})
	cg.Parent = card
	local st = Instance.new("UIStroke"); st.Thickness = 2.5; st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; st.Parent = card
	local sg = rainbow(st)

	newLabel(card, {
		Size = UDim2.new(1, -32, 0, 24), Position = UDim2.fromOffset(16, 16), Text = "ปิดสคริปต์ทั้งหมด?",
		TextSize = 17, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 203,
	})
	newLabel(card, {
		Size = UDim2.new(1, -32, 0, 34), Position = UDim2.fromOffset(16, 42), Text = "UI และอนิเมชั่นทั้งหมดจะหายไปทันที",
		TextSize = 12, Font = Enum.Font.Gotham, TextColor3 = Color3.fromRGB(205, 215, 235),
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 203,
	})

	local noB = fancyButton(card, "ยกเลิก", Color3.fromRGB(80, 110, 190), Color3.fromRGB(28, 44, 100),
		UDim2.new(0, 16, 1, -54), UDim2.new(0.5, -21, 0, 38))
	local yesB = fancyButton(card, "ปิดเลย", Color3.fromRGB(255, 95, 95), Color3.fromRGB(175, 20, 45),
		UDim2.new(0.5, 5, 1, -54), UDim2.new(0.5, -21, 0, 38))
	for _, d in ipairs(card:GetDescendants()) do
		if d:IsA("GuiObject") and d.ZIndex < 203 then d.ZIndex = 204 end
	end

	local conn = RunService.Heartbeat:Connect(function() sg.Rotation = (os.clock() * 120) % 360 end)
	local function closeDialog()
		conn:Disconnect()
		confirmOpen = false
		dim:Destroy()
	end
	noB.Activated:Connect(closeDialog)
	dim.Activated:Connect(closeDialog)
	yesB.Activated:Connect(function()
		conn:Disconnect()
		unloadScript()
	end)
end)

-- ===================================================== เปิดตัว
tw(rootScale, 0.55, { Scale = 1 }, Enum.EasingStyle.Back)
task.delay(0.35, function() sparkBurst(root, 38, 23, 8) end)
toast("✦ พร้อมใช้งาน — มี " .. #BUILTIN .. " สถานที่ในระบบ", C.GOLD, 3)

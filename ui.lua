--[[
	UILibrary.lua
	General-purpose dark-themed UI library for Roblox (or adaptable Lua/love2d-style env).
	- Sidebar navigation with categories
	- Tabs, Toggles, Sliders, Dropdowns, Color pickers
	- JSON-based config save/load (multiple named configs + trash)
	- PC + Mobile support (drag, resize, touch-friendly hit areas)
	- No game-specific modules included — all content below is placeholder/test data
	  meant to be swapped out by whatever you build on top of this.

	USAGE:
		local UILib = require(path.to.UILibrary)
		local Window = UILib:CreateWindow({
			Title = "MyApp",
			SubTitle = "for MyGame",
		})

		local Tab = Window:AddTab("General")
		Tab:AddToggle({ Text = "Enabled", Default = true, Callback = function(v) end })
		Tab:AddSlider({ Text = "Range", Min = 0, Max = 1000, Default = 500, Callback = function(v) end })
		Tab:AddDropdown({ Text = "Bones", Options = {"Head","Body"}, Callback = function(v) end })
		Tab:AddColorPicker({ Text = "Border Color", Default = Color3.new(1,1,1), Callback = function(c) end })

		Window:SaveConfig("MyConfigName")
		Window:LoadConfig("MyConfigName")
]]

local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

--=========================================================
-- THEME
--=========================================================
local Theme = {
	Background      = Color3.fromRGB(18, 18, 20),
	Sidebar         = Color3.fromRGB(15, 15, 17),
	Panel           = Color3.fromRGB(22, 22, 25),
	Card            = Color3.fromRGB(26, 26, 29),
	CardHover       = Color3.fromRGB(32, 32, 36),
	Border          = Color3.fromRGB(38, 38, 42),
	TextPrimary     = Color3.fromRGB(235, 235, 240),
	TextSecondary   = Color3.fromRGB(150, 150, 158),
	Accent          = Color3.fromRGB(255, 255, 255),
	AccentMuted     = Color3.fromRGB(60, 60, 66),
	Success         = Color3.fromRGB(80, 200, 120),
	Danger          = Color3.fromRGB(220, 90, 90),
	Font            = Enum.Font.GothamMedium,
	FontBold        = Enum.Font.GothamBold,

	-- Live/mutable settings — changed in real time from the UI Settings tab.
	-- AnimSpeed and CornerRadius apply instantly (read dynamically by the
	-- tween/corner helpers below and, for corners, via a live registry).
	-- Padding/CompactMode/IconSize apply to newly created components; existing
	-- rows aren't retroactively resized to avoid a full re-layout pass.
	CornerRadius    = 8,
	AnimSpeed       = 1,     -- multiplier: 0.5 = twice as fast, 2 = twice as slow
	Padding         = 8,
	CompactMode     = false,
	IconSize        = 16,
	Transparency    = 0,     -- 0-1 applied to panels/cards
}

-- Registry of every UICorner we hand out, so the Settings tab can restyle
-- corner roundness across the whole UI in real time.
local _cornerRegistry = {}

-- Registry of instances that use Theme.Accent as their background/text
-- color, so the accent color picker in Settings can restyle them live.
local _accentRegistry = {} -- { {inst=Instance, prop="BackgroundColor3"}, ... }

local function registerAccent(inst, prop)
	table.insert(_accentRegistry, { inst = inst, prop = prop or "BackgroundColor3" })
	return inst
end


--=========================================================
-- UTILITY HELPERS
--=========================================================
local function new(class, props)
	local inst = Instance.new(class)
	for k, v in pairs(props or {}) do
		if k ~= "Parent" then
			inst[k] = v
		end
	end
	if props and props.Parent then
		inst.Parent = props.Parent
	end
	return inst
end

local tween -- forward declaration; corner()/setCornerRadius() call this before its definition below

local function corner(parent, radius)
	local c = new("UICorner", { CornerRadius = UDim.new(0, radius or Theme.CornerRadius), Parent = parent })
	if not radius then
		-- only auto-managed corners (ones that used the theme default) get
		-- live-updated when CornerRadius changes from the Settings tab
		table.insert(_cornerRegistry, c)
	end
	return c
end

local function setCornerRadius(px)
	Theme.CornerRadius = px
	for _, c in ipairs(_cornerRegistry) do
		if c and c.Parent then
			tween(c, { CornerRadius = UDim.new(0, px) }, 0.15)
		end
	end
end

local function setAccentColor(color)
	Theme.Accent = color
	for _, entry in ipairs(_accentRegistry) do
		if entry.inst and entry.inst.Parent then
			tween(entry.inst, { [entry.prop] = color }, 0.15)
		end
	end
end

-- Applies (or replaces) a UIGradient on an instance. angle is in degrees.
-- transparencySeq is optional (defaults to fully opaque).
local function applyGradient(inst, colorSequence, angle, transparencySeq)
	local existing = inst:FindFirstChildOfClass("UIGradient")
	if existing then existing:Destroy() end
	return new("UIGradient", {
		Color = colorSequence,
		Rotation = angle or 0,
		Transparency = transparencySeq or NumberSequence.new(0),
		Parent = inst,
	})
end

local function clearGradient(inst)
	local existing = inst:FindFirstChildOfClass("UIGradient")
	if existing then existing:Destroy() end
end

local function stroke(parent, color, thickness)
	return new("UIStroke", {
		Color = color or Theme.Border,
		Thickness = thickness or 1,
		Parent = parent,
	})
end

tween = function(obj, props, time, style)
	local t = TweenService:Create(obj, TweenInfo.new((time or 0.18) * Theme.AnimSpeed, style or Enum.EasingStyle.Quad), props)
	t:Play()
	return t
end

local function isMobile()
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

local function pointInGui(pos, gui)
	local p, s = gui.AbsolutePosition, gui.AbsoluteSize
	return pos.X >= p.X and pos.X <= p.X + s.X and pos.Y >= p.Y and pos.Y <= p.Y + s.Y
end

-- Lets `Toggle.Value` (etc.) read the live current value without storing a
-- stale copy — used so Hidden = function() return not Toggle.Value end works.
local function withLiveValue(obj, getter)
	return setmetatable(obj, { __index = function(_, k)
		if k == "Value" then return getter() end
		return nil
	end })
end

--=========================================================
-- ICONS
--=========================================================
-- Three supported forms, auto-detected:
--   1. "rbxassetid://123456"        -> rendered as an ImageLabel
--   2. A short glyph/emoji, e.g. "★" -> rendered as a text glyph (default;
--      no external assets needed, works everywhere out of the box)
--   3. A registered name, e.g. "user" -> looked up in Icons.Providers and
--      rendered as whatever asset id that name maps to
-- Lucide (or any other icon set) needs its sprite sheet/font uploaded to
-- Roblox first — there's no built-in Lucide asset bundled here. Register
-- names once via Icons.Providers["user"] = "rbxassetid://..." and every
-- component that takes an Icon/Image option will resolve it automatically.
local Icons = { Providers = {} }

local function renderIcon(parent, icon, size, position)
	size = size or Theme.IconSize
	if typeof(icon) ~= "string" then return nil end
	local resolved = icon
	if not icon:match("^rbxassetid://") and Icons.Providers[icon] then
		resolved = Icons.Providers[icon]
	end
	if resolved:match("^rbxassetid://") then
		return new("ImageLabel", {
			Image = resolved,
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(size, size),
			Position = position or UDim2.fromOffset(0, 0),
			Parent = parent,
		})
	end
	-- fall back to rendering the raw string as a text glyph (emoji, unicode
	-- icon, or a single letter placeholder)
	return new("TextLabel", {
		Text = icon,
		Font = Theme.FontBold,
		TextSize = size,
		TextColor3 = Theme.TextPrimary,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(size, size),
		Position = position or UDim2.fromOffset(0, 0),
		Parent = parent,
	})
end

--=========================================================
-- JSON CONFIG STORE
--=========================================================
local ConfigStore = {}
ConfigStore.__index = ConfigStore

function ConfigStore.new(namespace)
	local self = setmetatable({}, ConfigStore)
	self.Namespace = namespace or "UILibrary"
	self.Configs = {}     -- [name] = { data = {}, created = os.time() }
	self.Trash = {}       -- [name] = { data = {}, created = os.time(), deletedAt = os.time() }
	self:_load()
	return self
end

-- Swap these two functions for DataStoreService, a file write (plugin/exploit env),
-- or a remote to a backend. Defaults to an in-memory + optional attribute-based cache.
function ConfigStore:_persistKey()
	return "UILib_" .. self.Namespace
end

function ConfigStore:_save()
	local ok, encoded = pcall(function()
		return HttpService:JSONEncode({
			Configs = self.Configs,
			Trash = self.Trash,
		})
	end)
	if ok then
		-- Placeholder persistence: stash JSON string on an attribute of PlayerGui.
		-- Replace with DataStoreService:SetAsync(...) for real cross-session persistence.
		pcall(function()
			PlayerGui:SetAttribute(self:_persistKey(), encoded)
		end)
	end
	return ok
end

function ConfigStore:_load()
	local ok, raw = pcall(function()
		return PlayerGui:GetAttribute(self:_persistKey())
	end)
	if ok and raw and typeof(raw) == "string" then
		local success, decoded = pcall(function()
			return HttpService:JSONDecode(raw)
		end)
		if success and decoded then
			self.Configs = decoded.Configs or {}
			self.Trash = decoded.Trash or {}
		end
	end
end

function ConfigStore:Save(name, data)
	assert(type(name) == "string" and #name > 0, "Config name must be a non-empty string")
	self.Configs[name] = {
		data = data,
		created = self.Configs[name] and self.Configs[name].created or os.date("%d.%m.%Y"),
		updated = os.date("%d.%m.%Y"),
	}
	self:_save()
	return true
end

function ConfigStore:Load(name)
	local entry = self.Configs[name]
	return entry and entry.data or nil
end

function ConfigStore:List()
	local out = {}
	for name, entry in pairs(self.Configs) do
		table.insert(out, { name = name, created = entry.created, updated = entry.updated })
	end
	table.sort(out, function(a, b) return a.name < b.name end)
	return out
end

function ConfigStore:Delete(name)
	if self.Configs[name] then
		self.Trash[name] = self.Configs[name]
		self.Trash[name].deletedAt = os.date("%d.%m.%Y")
		self.Configs[name] = nil
		self:_save()
	end
end

function ConfigStore:Restore(name)
	if self.Trash[name] then
		self.Configs[name] = self.Trash[name]
		self.Trash[name] = nil
		self:_save()
	end
end

function ConfigStore:PermanentlyDelete(name)
	self.Trash[name] = nil
	self:_save()
end

function ConfigStore:ListTrash()
	local out = {}
	for name, entry in pairs(self.Trash) do
		table.insert(out, { name = name, deletedAt = entry.deletedAt })
	end
	table.sort(out, function(a, b) return a.name < b.name end)
	return out
end

--=========================================================
-- LIBRARY
--=========================================================
local UILib = {}
UILib.__index = UILib

local Window = {}
Window.__index = Window

local Tab = {}
Tab.__index = Tab

local Section = {}
Section.__index = Section

--=========================================================
-- WINDOW
--=========================================================
function UILib:CreateWindow(opts)
	opts = opts or {}
	local title = opts.Title or "App"
	local subtitle = opts.SubTitle or ""

	local screenGui = new("ScreenGui", {
		Name = "UILibrary_" .. title,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 100,
		Parent = PlayerGui,
	})

	-- Root sizing: responsive base, scales down for mobile
	local baseWidth, baseHeight = 980, 620
	if isMobile() then
		baseWidth, baseHeight = 380, 560
	end

	local root = new("Frame", {
		Name = "Root",
		Size = UDim2.fromOffset(baseWidth, baseHeight),
		Position = UDim2.new(0.5, -baseWidth / 2, 0.5, -baseHeight / 2),
		BackgroundColor3 = Theme.Background,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Parent = screenGui,
	})
	corner(root, 12)
	stroke(root, Theme.Border, 1)

	-- Header status pill (floating, like "Arcane · PUBG · 144fps" reference)
	local pill = new("Frame", {
		Name = "StatusPill",
		Size = UDim2.fromOffset(220, 34),
		Position = UDim2.new(0, 0, 0, -46),
		BackgroundColor3 = Theme.Sidebar,
		Active = true,
		Parent = root,
	})
	corner(pill, 8)
	local pillLayout = new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 8),
		Parent = pill,
	})
	new("UIPadding", { PaddingLeft = UDim.new(0, 10), Parent = pill })
	new("TextLabel", {
		Text = title,
		Font = Theme.FontBold,
		TextSize = 13,
		TextColor3 = Theme.TextPrimary,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(60, 34),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = pill,
	})

	-- Sidebar
	local sidebarWidth = isMobile() and 0 or 220
	local sidebar = new("Frame", {
		Name = "Sidebar",
		Size = UDim2.new(0, sidebarWidth, 1, 0),
		BackgroundColor3 = Theme.Sidebar,
		BorderSizePixel = 0,
		Visible = not isMobile(),
		Parent = root,
	})

	local sidebarHeader = new("Frame", {
		Size = UDim2.new(1, 0, 0, 60),
		BackgroundTransparency = 1,
		Parent = sidebar,
	})
	local logoBox = new("Frame", {
		Size = UDim2.fromOffset(34, 34),
		Position = UDim2.fromOffset(16, 14),
		BackgroundColor3 = Theme.Accent,
		Parent = sidebarHeader,
	})
	registerAccent(logoBox)
	corner(logoBox, 8)
	new("TextLabel", {
		Text = title:sub(1, 1),
		Font = Theme.FontBold,
		TextSize = 16,
		TextColor3 = Theme.Background,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = logoBox,
	})
	new("TextLabel", {
		Text = title,
		Font = Theme.FontBold,
		TextSize = 13,
		TextColor3 = Theme.TextPrimary,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(58, 12),
		Size = UDim2.fromOffset(140, 16),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = sidebarHeader,
	})
	new("TextLabel", {
		Text = subtitle,
		Font = Theme.Font,
		TextSize = 11,
		TextColor3 = Theme.TextSecondary,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(58, 30),
		Size = UDim2.fromOffset(140, 14),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = sidebarHeader,
	})

	local categoryLabel = new("TextLabel", {
		Text = "CATEGORY",
		Font = Theme.Font,
		TextSize = 10,
		TextColor3 = Theme.TextSecondary,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(16, 70),
		Size = UDim2.fromOffset(150, 14),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = sidebar,
	})

	local tabListFrame = new("Frame", {
		Name = "TabList",
		Position = UDim2.fromOffset(8, 92),
		Size = UDim2.new(1, -16, 1, -160),
		BackgroundTransparency = 1,
		Parent = sidebar,
	})
	local tabListLayout = new("UIListLayout", {
		Padding = UDim.new(0, 4),
		Parent = tabListFrame,
	})

	-- Footer (session info placeholder)
	local footer = new("Frame", {
		Size = UDim2.new(1, -16, 0, 50),
		Position = UDim2.new(0, 8, 1, -58),
		BackgroundTransparency = 1,
		Parent = sidebar,
	})
	local footerLine1 = new("TextLabel", {
		Text = "Status: Ready",
		Font = Theme.Font,
		TextSize = 11,
		TextColor3 = Theme.TextSecondary,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 14),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = footer,
	})
	local footerLine2 = new("TextLabel", {
		Text = "Session: 00:00",
		Font = Theme.FontBold,
		TextSize = 11,
		TextColor3 = Theme.TextPrimary,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 16),
		Size = UDim2.new(1, 0, 0, 14),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = footer,
	})

	-- Content area
	local content = new("Frame", {
		Name = "Content",
		Position = UDim2.new(0, sidebarWidth, 0, 0),
		Size = UDim2.new(1, -sidebarWidth, 1, 0),
		BackgroundTransparency = 1,
		Parent = root,
	})

	-- On mobile the hamburger button (16,16 · 36x36) would otherwise overlap
	-- the header/first row of content, so push everything down to clear it.
	local topInset = isMobile() and 52 or 20

	local contentHeader = new("TextLabel", {
		Text = "",
		Font = Theme.FontBold,
		TextSize = 20,
		TextColor3 = Theme.TextPrimary,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(24, topInset),
		Size = UDim2.new(1, -128, 0, 28),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = content,
	})

	-- Window controls: minimize / maximize / close, top-right of content area.
	local windowControls = new("Frame", {
		Name = "WindowControls",
		Size = UDim2.fromOffset(84, 24),
		Position = UDim2.new(1, -24, 0, topInset + 2),
		AnchorPoint = Vector2.new(1, 0),
		BackgroundTransparency = 1,
		Parent = content,
	})
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		Padding = UDim.new(0, 6),
		Parent = windowControls,
	})
	local function makeWinCtrlButton(glyph)
		local b = new("TextButton", {
			Text = glyph,
			Font = Theme.FontBold,
			TextSize = 13,
			TextColor3 = Theme.TextSecondary,
			BackgroundColor3 = Theme.Card,
			Size = UDim2.fromOffset(24, 24),
			Parent = windowControls,
		})
		corner(b, 6)
		b.MouseEnter:Connect(function() tween(b, { BackgroundColor3 = Theme.CardHover }, 0.1) end)
		b.MouseLeave:Connect(function() tween(b, { BackgroundColor3 = Theme.Card }, 0.1) end)
		return b
	end
	local minimizeBtn = makeWinCtrlButton("—")
	local maximizeBtn = makeWinCtrlButton("▢")
	local closeBtn = makeWinCtrlButton("×")

	local isMinimized, isMaximized = false, false
	local restoreSize, restorePos = root.Size, root.Position

	minimizeBtn.MouseButton1Click:Connect(function()
		isMinimized = not isMinimized
		if isMinimized then
			restoreSize = root.Size
			sidebar.Visible = false
			content.Visible = false
			tween(root, { Size = UDim2.fromOffset(root.Size.X.Offset, 46) }, 0.2)
		else
			sidebar.Visible = not isMobile()
			content.Visible = true
			tween(root, { Size = restoreSize }, 0.2)
		end
	end)

	maximizeBtn.MouseButton1Click:Connect(function()
		isMaximized = not isMaximized
		if isMaximized then
			restoreSize, restorePos = root.Size, root.Position
			local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
			tween(root, { Size = UDim2.fromOffset(vp.X - 40, vp.Y - 40), Position = UDim2.fromOffset(20, 20) }, 0.2)
		else
			tween(root, { Size = restoreSize, Position = restorePos }, 0.2)
		end
	end)

	closeBtn.MouseButton1Click:Connect(function()
		tween(root, { BackgroundTransparency = 1, Size = UDim2.new(root.Size.X.Scale, math.floor(root.Size.X.Offset * 0.96), root.Size.Y.Scale, math.floor(root.Size.Y.Offset * 0.96)) }, 0.15)
		task.delay(0.16 * Theme.AnimSpeed, function() screenGui:Destroy() end)
	end)

	local pageHolder = new("Frame", {
		Name = "Pages",
		Position = UDim2.fromOffset(24, topInset + 40),
		Size = UDim2.new(1, -48, 1, -topInset - 64),
		BackgroundTransparency = 1,
		Parent = content,
	})

	-- Mobile: hamburger to open sidebar as overlay
	local mobileToggle
	if isMobile() then
		mobileToggle = new("TextButton", {
			Text = "☰",
			Font = Theme.FontBold,
			TextSize = 20,
			TextColor3 = Theme.TextPrimary,
			BackgroundColor3 = Theme.Card,
			Size = UDim2.fromOffset(36, 36),
			Position = UDim2.fromOffset(16, 16),
			Parent = root,
		})
		corner(mobileToggle, 8)
		sidebar.Position = UDim2.fromOffset(-260, 0)
		sidebar.Size = UDim2.fromOffset(240, baseHeight)
		sidebar.ZIndex = 10
		sidebar.Visible = true
		local sidebarOpen = false
		mobileToggle.MouseButton1Click:Connect(function()
			sidebarOpen = not sidebarOpen
			tween(sidebar, { Position = sidebarOpen and UDim2.fromOffset(0, 0) or UDim2.fromOffset(-260, 0) }, 0.22)
		end)
	end

	-- Draggable (PC: drag by pill; Mobile: drag by header)
	do
		local dragging, dragStart, startPos
		local dragHandle = isMobile() and content or pill
		dragHandle.Active = true
		local function beginDrag(input)
			dragging = true
			dragStart = input.Position
			startPos = root.Position
		end
		local function updateDrag(input)
			if dragging then
				local delta = input.Position - dragStart
				root.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
			end
		end
		pill.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				beginDrag(input)
			end
		end)
		UserInputService.InputChanged:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
				updateDrag(input)
			end
		end)
		UserInputService.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				dragging = false
			end
		end)
	end

	-- Resizable (bottom-right handle), works for both mouse + touch
	local resizeHandleRef
	do
		local resizeHandle = new("Frame", {
			Size = UDim2.fromOffset(18, 18),
			Position = UDim2.new(1, -18, 1, -18),
			BackgroundTransparency = 1,
			Active = true,
			Parent = root,
		})
		resizeHandleRef = resizeHandle
		new("TextLabel", {
			Text = "◢",
			Font = Theme.Font,
			TextSize = 14,
			TextColor3 = Theme.TextSecondary,
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Parent = resizeHandle,
		})
		local resizing, resizeStart, startSize
		resizeHandle.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				resizing = true
				resizeStart = input.Position
				startSize = root.Size
			end
		end)
		UserInputService.InputChanged:Connect(function(input)
			if resizing and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
				local delta = input.Position - resizeStart
				local newW = math.clamp(startSize.X.Offset + delta.X, 340, 1400)
				local newH = math.clamp(startSize.Y.Offset + delta.Y, 300, 900)
				root.Size = UDim2.fromOffset(newW, newH)
			end
		end)
		UserInputService.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				resizing = false
			end
		end)
	end

	-- React to viewport changes (rotation, window resize) for responsive scaling
	local uiScale = new("UIScale", { Scale = 1, Parent = root })
	local function updateScale()
		local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize
		if not viewport then return end
		local scaleX = viewport.X / (baseWidth + 80)
		local scaleY = viewport.Y / (baseHeight + 80)
		local s = math.clamp(math.min(scaleX, scaleY, 1), 0.55, 1)
		tween(uiScale, { Scale = s }, 0.15)
	end
	if workspace.CurrentCamera then
		workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
	end
	updateScale()

	-- Overlay: a top-level layer parented as a LAST sibling of root inside the
	-- ScreenGui, at a very high ZIndex. Dropdown option lists, dialogs, and
	-- notifications all render into this instead of their local parent so
	-- they're never clipped or hidden behind other controls.
	local overlay = new("Frame", {
		Name = "Overlay",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 500,
		Parent = screenGui,
	})

	local notifyContainer = new("Frame", {
		Name = "Notifications",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -20, 1, -20),
		Size = UDim2.fromOffset(300, 1),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		ZIndex = 600,
		Parent = overlay,
	})
	new("UIListLayout", {
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = notifyContainer,
	})

	-- Loading screen: shown for a beat before the window becomes usable so
	-- the reveal feels intentional rather than an instant pop-in. Logo
	-- reveal + a thin progress fill, then fades out as the window scales
	-- in from the center.
	root.Visible = false
	local loadingScreen = new("Frame", {
		Name = "Loading",
		Size = root.Size,
		Position = root.Position,
		BackgroundColor3 = Theme.Background,
		BorderSizePixel = 0,
		ZIndex = 900,
		Parent = screenGui,
	})
	corner(loadingScreen, 12)
	stroke(loadingScreen, Theme.Border, 1)
	local loadLogo = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, -20),
		Size = UDim2.fromOffset(44, 44),
		BackgroundColor3 = Theme.Accent,
		BackgroundTransparency = 1,
		ZIndex = 901,
		Parent = loadingScreen,
	})
	corner(loadLogo, 10)
	local loadLogoText = new("TextLabel", {
		Text = title:sub(1, 1),
		Font = Theme.FontBold,
		TextSize = 20,
		TextColor3 = Theme.Background,
		TextTransparency = 1,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 902,
		Parent = loadLogo,
	})
	local loadBarBack = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 36),
		Size = UDim2.fromOffset(120, 4),
		BackgroundColor3 = Theme.AccentMuted,
		ZIndex = 901,
		Parent = loadingScreen,
	})
	corner(loadBarBack, 2)
	local loadBarFill = new("Frame", {
		Size = UDim2.new(0, 0, 1, 0),
		BackgroundColor3 = Theme.Accent,
		ZIndex = 902,
		Parent = loadBarBack,
	})
	corner(loadBarFill, 2)

	tween(loadLogo, { BackgroundTransparency = 0 }, 0.25)
	tween(loadLogoText, { TextTransparency = 0 }, 0.25)
	tween(loadBarFill, { Size = UDim2.new(1, 0, 1, 0) }, 0.45, Enum.EasingStyle.Quad)
	task.delay(0.55, function()
		tween(loadingScreen, { BackgroundTransparency = 1 }, 0.2)
		for _, d in ipairs(loadingScreen:GetDescendants()) do
			if d:IsA("GuiObject") then tween(d, { BackgroundTransparency = 1 }, 0.2) end
			if d:IsA("TextLabel") then tween(d, { TextTransparency = 1 }, 0.2) end
		end
		task.delay(0.2, function() loadingScreen:Destroy() end)

		-- reveal the real window: fade + scale in from center (reuses the
		-- existing responsive uiScale instance rather than adding a second
		-- UIScale, which would conflict with it)
		root.Visible = true
		root.BackgroundTransparency = 1
		local targetScale = uiScale.Scale
		uiScale.Scale = targetScale * 0.94
		tween(root, { BackgroundTransparency = 0 }, 0.25)
		tween(uiScale, { Scale = targetScale }, 0.28, Enum.EasingStyle.Back)
	end)

	local self = setmetatable({}, Window)
	self.ScreenGui = screenGui
	self.Root = root
	self.Sidebar = sidebar
	self.TabListFrame = tabListFrame
	self.PageHolder = pageHolder
	self.ContentHeader = contentHeader
	self.Overlay = overlay
	self.NotifyContainer = notifyContainer
	self.UIScaleInstance = uiScale
	self.ResizeHandle = resizeHandleRef
	self.Tabs = {}
	self.ActiveTab = nil
	self.Store = ConfigStore.new(title)
	self.FooterLine2 = footerLine2
	self._sessionStart = os.clock()

	-- Autosave: whenever any control changes, the currently active config
	-- (CurrentConfigName) is re-saved automatically. Defaults to "Autosave"
	-- so there's always somewhere to write to even before the user creates
	-- a named config of their own. Debounced so rapid slider drags don't
	-- spam saves every frame.
	self.CurrentConfigName = "Autosave"
	self.AutoSaveEnabled = true
	self._autoSavePending = false
	self._autoSaveDebounce = 0.25 -- seconds

	-- Conditional visibility: any component created with `Hidden = function()
	-- return bool end` gets registered here. Re-checked on a light interval
	-- (not every frame) and animated in/out when the result changes.
	self._conditionals = {}
	task.spawn(function()
		while root.Parent do
			for _, c in ipairs(self._conditionals) do
				local ok, shouldHide = pcall(c.fn)
				shouldHide = ok and shouldHide or false
				if shouldHide ~= c.state then
					c.state = shouldHide
					if shouldHide then
						tween(c.row, { Size = UDim2.new(c.naturalSize.X.Scale, c.naturalSize.X.Offset, 0, 0) }, 0.15)
						task.delay(0.16 * Theme.AnimSpeed, function()
							if c.state then c.row.Visible = false end
						end)
					else
						c.row.Visible = true
						tween(c.row, { Size = c.naturalSize }, 0.15)
					end
				end
			end
			task.wait(0.15)
		end
	end)

	-- live session timer + current autosave target
	task.spawn(function()
		while root.Parent do
			local elapsed = os.clock() - self._sessionStart
			local m = math.floor(elapsed / 60)
			local s = math.floor(elapsed % 60)
			footerLine2.Text = string.format("Session: %02d:%02d", m, s)
			footerLine1.Text = "Config: " .. self.CurrentConfigName .. (self.AutoSaveEnabled and " (auto)" or "")
			task.wait(1)
		end
	end)

	return self
end

--=========================================================
-- TAB CREATION
--=========================================================
function Window:AddTab(nameOrOpts, icon, parentFrame)
	local opts = nameOrOpts
	if type(nameOrOpts) == "string" then
		opts = { Title = nameOrOpts, Icon = icon }
	end
	opts = opts or {}
	local name = opts.Title or "Tab"
	local description = opts.Description
	local tag = opts.Tag
	parentFrame = parentFrame or self.TabListFrame

	local btnHeight = description and 46 or 36
	local btn = new("TextButton", {
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Theme.Panel,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, btnHeight),
		Parent = parentFrame,
	})
	corner(btn, 8)

	new("TextLabel", {
		Name = "Title",
		Text = (opts.Icon and (opts.Icon .. "  ") or "• ") .. name,
		Font = Theme.Font,
		TextSize = 13,
		TextColor3 = Theme.TextSecondary,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, (tag and -56 or -16), 0, description and 18 or btnHeight),
		Position = UDim2.fromOffset(12, description and 5 or 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = btn,
	})

	if description then
		new("TextLabel", {
			Name = "Description",
			Text = description,
			Font = Theme.Font,
			TextSize = 10,
			TextColor3 = Theme.TextSecondary,
			TextTransparency = 0.35,
			BackgroundTransparency = 1,
			Size = UDim2.new(1, -16, 0, 14),
			Position = UDim2.fromOffset(12, 23),
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = btn,
		})
	end

	if tag then
		local tagFrame = new("Frame", {
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 16),
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -8, 0, description and 6 or 10),
			BackgroundColor3 = tag.Color or Theme.Accent,
			Parent = btn,
		})
		corner(tagFrame, 4)
		new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6), Parent = tagFrame })
		new("TextLabel", {
			Text = tag.Title or "New",
			Font = Theme.FontBold,
			TextSize = 9,
			TextColor3 = Theme.Background,
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 1, 0),
			Parent = tagFrame,
		})
	end

	local page = new("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = Theme.Border,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Visible = false,
		Parent = self.PageHolder,
	})
	new("UIListLayout", { Parent = page }) -- single child ("columns") drives AutomaticCanvasSize

	-- Two-column content: components alternate Left/Right so horizontal
	-- space gets used instead of one narrow vertical stack.
	local columns = new("Frame", {
		Name = "Columns",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = page,
	})
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 12),
		Parent = columns,
	})
	local colLeft = new("Frame", {
		Name = "ColumnLeft",
		Size = opts.Columns == 1 and UDim2.new(1, 0, 0, 0) or UDim2.new(0.5, -6, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = columns,
	})
	new("UIListLayout", { Padding = UDim.new(0, 12), Parent = colLeft })
	local colRight = new("Frame", {
		Name = "ColumnRight",
		Size = UDim2.new(0.5, -6, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Visible = opts.Columns ~= 1,
		Parent = columns,
	})
	new("UIListLayout", { Padding = UDim.new(0, 12), Parent = colRight })

	-- Full-width row (used by components with Fully = true, e.g. a progress
	-- bar that should span both columns instead of sitting in just one).
	local fullWidth = new("Frame", {
		Name = "FullWidth",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = page,
	})
	new("UIListLayout", { Padding = UDim.new(0, 12), Parent = fullWidth })

	local tabObj = setmetatable({}, Tab)
	tabObj.Name = name
	tabObj.Button = btn
	tabObj.Page = page
	tabObj.Columns = opts.Columns or 2
	tabObj.ColumnLeft = colLeft
	tabObj.ColumnRight = colRight
	tabObj.FullWidth = fullWidth
	tabObj.Window = self
	tabObj.Controls = {}
	tabObj.Elements = {}
	tabObj._colToggle = 0

	table.insert(self.Tabs, tabObj)

	btn.MouseButton1Click:Connect(function()
		self:SelectTab(tabObj)
	end)

	if #self.Tabs == 1 then
		self:SelectTab(tabObj)
	end

	return tabObj
end

function Window:SelectTab(tabObj)
	for _, t in ipairs(self.Tabs) do
		t.Page.Visible = (t == tabObj)
		local label = t.Button:FindFirstChild("Title")
		if t == tabObj then
			tween(t.Button, { BackgroundTransparency = 0 }, 0.15)
			if label then label.TextColor3 = Theme.TextPrimary end
		else
			tween(t.Button, { BackgroundTransparency = 1 }, 0.15)
			if label then label.TextColor3 = Theme.TextSecondary end
		end
	end
	self.ContentHeader.Text = tabObj.Name
	self.ActiveTab = tabObj
end

-- Collapsible sidebar group, e.g.:
--   local Main = Window:AddSection("Main")
--   Main:AddTab("Update Log")
--   Main:AddTab("Credits")
-- Sections start expanded; clicking the header collapses/expands with a
-- smooth height tween. Tabs added outside a section (Window:AddTab) still
-- work exactly as before, appearing as standalone rows in the sidebar.
function Window:AddSection(name)
	local header = new("TextButton", {
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 26),
		Parent = self.TabListFrame,
	})
	new("TextLabel", {
		Text = name,
		Font = Theme.Font,
		TextSize = 10,
		TextColor3 = Theme.TextSecondary,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -20, 1, 0),
		Position = UDim2.fromOffset(4, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = header,
	})
	local chevron = new("TextLabel", {
		Text = "▾",
		Font = Theme.Font,
		TextSize = 11,
		TextColor3 = Theme.TextSecondary,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(20, 26),
		Position = UDim2.new(1, -20, 0, 0),
		Parent = header,
	})

	local container = new("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Parent = self.TabListFrame,
	})
	new("UIListLayout", { Padding = UDim.new(0, 4), Parent = container })

	local expanded = true
	header.MouseButton1Click:Connect(function()
		expanded = not expanded
		tween(chevron, { Rotation = expanded and 0 or -90 }, 0.15)
		container.Visible = expanded
	end)

	local section = setmetatable({}, Section)
	section.Window = self
	section.Container = container

	function section:AddTab(nameOrOpts, icon)
		return self.Window:AddTab(nameOrOpts, icon, self.Container)
	end

	return section
end

--=========================================================
-- CONFIG SAVE / LOAD (gathers all control values across all tabs)
--=========================================================
function Window:_gatherState()
	local state = {}
	for _, t in ipairs(self.Tabs) do
		for id, ctrl in pairs(t.Controls) do
			state[id] = ctrl.Get()
		end
	end
	return state
end

function Window:_applyState(state)
	for _, t in ipairs(self.Tabs) do
		for id, ctrl in pairs(t.Controls) do
			if state[id] ~= nil then
				ctrl.Set(state[id])
			end
		end
	end
end

function Window:SaveConfig(name)
	local state = self:_gatherState()
	self.CurrentConfigName = name -- future auto-saves go to this config too
	return self.Store:Save(name, state)
end

function Window:LoadConfig(name)
	local state = self.Store:Load(name)
	if state then
		self:_applyState(state)
		self.CurrentConfigName = name -- switching configs redirects auto-save
		return true
	end
	return false
end

-- Call this to point auto-save at a different config name without
-- immediately saving/loading (e.g. right after creating a brand new one).
function Window:SetActiveConfig(name)
	self.CurrentConfigName = name
end

function Window:SetAutoSaveEnabled(enabled)
	self.AutoSaveEnabled = enabled
end

-- Internal: called by every control after its value changes. Debounced with
-- task.delay so a slider being dragged doesn't write to the store every
-- single frame — it coalesces into one save shortly after input settles.
function Window:_autoSave()
	if not self.AutoSaveEnabled then return end
	if self._autoSavePending then return end
	self._autoSavePending = true
	task.delay(self._autoSaveDebounce, function()
		self._autoSavePending = false
		local state = self:_gatherState()
		self.Store:Save(self.CurrentConfigName, state)
	end)
end

function Window:ListConfigs()
	return self.Store:List()
end

function Window:DeleteConfig(name)
	self.Store:Delete(name)
end

function Window:RestoreConfig(name)
	self.Store:Restore(name)
end

--=========================================================
-- DIALOG SYSTEM (modal, blocks the main window while open)
--=========================================================
-- local Dialog = Window:Dialog({
--     Title = "Confirm Action", Content = "Are you sure?",
--     Buttons = { { Title = "Yes", Callback = function() end }, { Title = "No", Callback = function() end } },
--     ClickOutsideCloses = false, -- default: outside clicks do nothing
-- })
function Window:Dialog(opts)
	opts = opts or {}
	local overlay = self.Overlay

	local dim = new("TextButton", {
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1, -- fades in below
		Size = UDim2.fromScale(1, 1),
		ZIndex = 700,
		Parent = overlay,
	})

	local card = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0, 360, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Theme.Panel,
		ZIndex = 701,
		Parent = dim,
	})
	corner(card, 12)
	stroke(card, Theme.Border, 1)
	new("UIPadding", {
		PaddingTop = UDim.new(0, 18), PaddingBottom = UDim.new(0, 18),
		PaddingLeft = UDim.new(0, 20), PaddingRight = UDim.new(0, 20),
		Parent = card,
	})
	new("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 14),
		Parent = card,
	})

	local titleRow = new("Frame", {
		Size = UDim2.new(1, 0, 0, 20),
		BackgroundTransparency = 1,
		LayoutOrder = 1,
		ZIndex = 701,
		Parent = card,
	})
	new("TextLabel", {
		Text = opts.Title or "Dialog",
		Font = Theme.FontBold,
		TextSize = 16,
		TextColor3 = Theme.TextPrimary,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -24, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 701,
		Parent = titleRow,
	})
	local closeX = new("TextButton", {
		Text = "×",
		Font = Theme.FontBold,
		TextSize = 18,
		TextColor3 = Theme.TextSecondary,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(20, 20),
		Position = UDim2.new(1, -20, 0, 0),
		ZIndex = 701,
		Parent = titleRow,
	})

	if opts.Content then
		new("TextLabel", {
			Text = opts.Content,
			Font = Theme.Font,
			TextSize = 13,
			TextColor3 = Theme.TextSecondary,
			TextWrapped = true,
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = 2,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 701,
			Parent = card,
		})
	end

	local function close()
		tween(dim, { BackgroundTransparency = 1 }, 0.18)
		local scaleOut = card:FindFirstChildOfClass("UIScale")
		if scaleOut then tween(scaleOut, { Scale = 0.92 }, 0.18) end
		task.delay(0.18 * Theme.AnimSpeed, function() dim:Destroy() end)
	end
	closeX.MouseButton1Click:Connect(close)

	if opts.Buttons and #opts.Buttons > 0 then
		local btnRow = new("Frame", {
			Size = UDim2.new(1, 0, 0, 34),
			BackgroundTransparency = 1,
			LayoutOrder = 3,
			ZIndex = 701,
			Parent = card,
		})
		new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 8),
			ZIndex = 701,
			Parent = btnRow,
		})
		for _, b in ipairs(opts.Buttons) do
			local bBtn = new("TextButton", {
				Text = b.Title or "OK",
				Font = Theme.FontBold,
				TextSize = 13,
				TextColor3 = b.Primary and Theme.Background or Theme.TextPrimary,
				BackgroundColor3 = b.Primary and Theme.Accent or Theme.Card,
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, 34),
				ZIndex = 701,
				Parent = btnRow,
			})
			new("UISizeConstraint", { MinSize = Vector2.new(64, 34), Parent = bBtn })
			new("UIPadding", { PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16), Parent = bBtn })
			corner(bBtn, 6)
			if b.Primary then registerAccent(bBtn) end
			bBtn.MouseEnter:Connect(function() tween(bBtn, { BackgroundTransparency = 0.15 }, 0.1) end)
			bBtn.MouseLeave:Connect(function() tween(bBtn, { BackgroundTransparency = 0 }, 0.1) end)
			bBtn.MouseButton1Click:Connect(function()
				if b.Callback then b.Callback() end
				close()
			end)
		end
	end

	if opts.ClickOutsideCloses then
		dim.MouseButton1Click:Connect(close)
	end

	-- open animation: fade dim in, card scales up from 0.92 -> 1 (no Size
	-- reassignment here — that would stomp the AutomaticSize-computed
	-- height and is what caused buttons to not render before).
	local scale = new("UIScale", { Scale = 0.92, Parent = card })
	tween(dim, { BackgroundTransparency = 0.5 }, 0.18)
	tween(scale, { Scale = 1 }, 0.2, Enum.EasingStyle.Back)

	return { Close = close }
end

--=========================================================
-- GRADIENT THEMES
--=========================================================
-- Window:SetPrimaryGradient(ColorSequence.new(...), angleDegrees)
-- Window:SetSecondaryGradient(ColorSequence.new(...), angleDegrees)
-- Window:ClearGradients()
-- Applies to the main window background and the sidebar respectively.
-- Developers can also call applyGradient-style code directly on any
-- instance they build themselves using the same UIGradient pattern.
function Window:SetPrimaryGradient(colorSequence, angle)
	self._primaryGradient = applyGradient(self.Root, colorSequence, angle)
	return self._primaryGradient
end

function Window:SetSecondaryGradient(colorSequence, angle)
	self._secondaryGradient = applyGradient(self.Sidebar, colorSequence, angle)
	return self._secondaryGradient
end

function Window:ClearGradients()
	clearGradient(self.Root)
	clearGradient(self.Sidebar)
	self._primaryGradient, self._secondaryGradient = nil, nil
end

--=========================================================
-- NOTIFICATION SYSTEM (bottom-right, stacking, auto-dismiss)
--=========================================================
-- Window:Notify({ Title = "Saved", Desc = "Config saved successfully",
--                  Icon = "✓", Duration = 4 })
function Window:Notify(opts)
	opts = opts or {}
	local duration = opts.Duration or 4

	local card = new("Frame", {
		Size = UDim2.fromOffset(280, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Theme.Panel,
		ClipsDescendants = true,
		LayoutOrder = math.floor(-os.clock() * 1000), -- newest at bottom, keeps stack ordered
		Position = UDim2.fromOffset(40, 0),
		Parent = self.NotifyContainer,
	})
	corner(card, 10)
	stroke(card, Theme.Border, 1)
	new("UIPadding", {
		PaddingTop = UDim.new(0, 12), PaddingBottom = UDim.new(0, 12),
		PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12),
		Parent = card,
	})

	local hasIcon = opts.Icon ~= nil
	local textX = hasIcon and 34 or 0

	if hasIcon then
		local iconBox = new("Frame", {
			Size = UDim2.fromOffset(24, 24),
			BackgroundColor3 = Theme.AccentMuted,
			Parent = card,
		})
		corner(iconBox, 6)
		new("TextLabel", {
			Text = opts.Icon,
			Font = Theme.FontBold,
			TextSize = 13,
			TextColor3 = Theme.TextPrimary,
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Parent = iconBox,
		})
	end

	local closeBtn = new("TextButton", {
		Text = "×",
		Font = Theme.FontBold,
		TextSize = 16,
		TextColor3 = Theme.TextSecondary,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(20, 20),
		Position = UDim2.new(1, -20, 0, 12),
		Parent = card,
	})

	new("TextLabel", {
		Text = opts.Title or "Notification",
		Font = Theme.FontBold,
		TextSize = 13,
		TextColor3 = Theme.TextPrimary,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(textX, 0),
		Size = UDim2.new(1, -textX - 24, 0, 16),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = card,
	})
	if opts.Desc then
		new("TextLabel", {
			Text = opts.Desc,
			Font = Theme.Font,
			TextSize = 12,
			TextColor3 = Theme.TextSecondary,
			TextWrapped = true,
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(textX, 18),
			Size = UDim2.new(1, -textX, 0, 16),
			AutomaticSize = Enum.AutomaticSize.Y,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = card,
		})
	end

	local progressBack = new("Frame", {
		Size = UDim2.new(1, 0, 0, 3),
		Position = UDim2.new(0, 0, 1, -3),
		BackgroundColor3 = Theme.AccentMuted,
		Parent = card,
	})
	local progressFill = new("Frame", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = Theme.Accent,
		Parent = progressBack,
	})

	local dismissed = false
	local function dismiss()
		if dismissed then return end
		dismissed = true
		tween(card, { Size = UDim2.fromOffset(280, 0) }, 0.15)
		local scale = new("UIScale", { Scale = 1, Parent = card })
		tween(scale, { Scale = 0.9 }, 0.15)
		task.delay(0.16 * Theme.AnimSpeed, function() card:Destroy() end)
	end
	closeBtn.MouseButton1Click:Connect(dismiss)

	-- slide/fade in
	local goalPos = UDim2.fromOffset(0, 0)
	tween(card, { Position = goalPos }, 0.2)
	if duration and duration > 0 then
		tween(progressFill, { Size = UDim2.new(0, 0, 1, 0) }, duration, Enum.EasingStyle.Linear)
		task.delay(duration, dismiss)
	end

	return { Close = dismiss }
end

--=========================================================
-- CONTROLS
--=========================================================
local function makeRow(parent, height)
	local row = new("Frame", {
		Size = UDim2.new(1, 0, 0, height or 44),
		BackgroundColor3 = Theme.Panel,
		Active = true,
		Parent = parent,
	})
	corner(row, 8)
	stroke(row, Theme.Border, 1)
	row.MouseEnter:Connect(function() tween(row, { BackgroundColor3 = Theme.CardHover }, 0.15) end)
	row.MouseLeave:Connect(function() tween(row, { BackgroundColor3 = Theme.Panel }, 0.15) end)
	return row
end

-- id counter so configs can key controls uniquely even with duplicate labels
local _idCounter = 0
local function nextId(prefix)
	_idCounter = _idCounter + 1
	return (prefix or "ctrl") .. "_" .. _idCounter
end

-- Alternates Left/Right so components fill both columns instead of stacking
-- in one narrow strip. Call once per top-level component you add.
function Tab:_target()
	if self.Columns == 1 then
		return self.ColumnLeft
	end
	local target = (self._colToggle % 2 == 0) and self.ColumnLeft or self.ColumnRight
	self._colToggle = self._colToggle + 1
	return target
end

-- Tracks every top-level row/element in creation order so ScrollToElement
-- can find it later. Also wires up `opts.Hidden = function() return bool end`
-- if present on the options table that produced this row.
function Tab:_registerRow(row, opts)
	table.insert(self.Elements, row)
	if opts and type(opts.Hidden) == "function" then
		table.insert(self.Window._conditionals, {
			row = row,
			fn = opts.Hidden,
			naturalSize = row.Size,
			state = nil,
		})
	end
	return row
end

-- Smoothly scrolls this tab's page until the Nth element (1-indexed, in the
-- order it was added) is in view. Works across both columns.
function Tab:ScrollToElement(index)
	local el = self.Elements[index]
	if not el then return end
	local targetY = math.max(0, el.AbsolutePosition.Y - self.Page.AbsolutePosition.Y + self.Page.CanvasPosition.Y - 12)
	tween(self.Page, { CanvasPosition = Vector2.new(0, targetY) }, 0.35, Enum.EasingStyle.Quart)
end

function Tab:AddSectionLabel(text)
	local lbl = new("TextLabel", {
		Text = text,
		Font = Theme.FontBold,
		TextSize = 12,
		TextColor3 = Theme.TextSecondary,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 20),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = self:_target(),
	})
	self:_registerRow(lbl)
end

function Tab:AddToggle(opts)
	opts = opts or {}
	local id = opts.Id or nextId("toggle")
	local row = self:_registerRow(makeRow(self:_target()), opts)
	new("TextLabel", {
		Text = opts.Text or "Toggle",
		Font = Theme.Font,
		TextSize = 13,
		TextColor3 = Theme.TextPrimary,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(14, 0),
		Size = UDim2.new(1, -70, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = row,
	})

	local track = new("TextButton", {
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.fromOffset(40, 22),
		Position = UDim2.new(1, -54, 0.5, -11),
		BackgroundColor3 = opts.Default and Theme.Success or Theme.AccentMuted,
		Parent = row,
	})
	corner(track, 11)
	local knob = new("Frame", {
		Size = UDim2.fromOffset(18, 18),
		Position = opts.Default and UDim2.new(1, -20, 0.5, -9) or UDim2.new(0, 2, 0.5, -9),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = track,
	})
	corner(knob, 9)

	local state = opts.Default or false
	local function set(v, fireCallback)
		state = v
		tween(track, { BackgroundColor3 = state and Theme.Success or Theme.AccentMuted }, 0.15)
		tween(knob, { Position = state and UDim2.new(1, -20, 0.5, -9) or UDim2.new(0, 2, 0.5, -9) }, 0.15)
		if fireCallback ~= false and opts.Callback then
			opts.Callback(state)
		end
		if fireCallback ~= false then
			self.Window:_autoSave()
		end
	end

	track.MouseButton1Click:Connect(function()
		set(not state)
	end)

	self.Controls[id] = {
		Get = function() return state end,
		Set = function(v) set(v, false) end,
	}

	return withLiveValue({ Set = function(v) set(v, false) end, Get = function() return state end }, function() return state end)
end

function Tab:AddSlider(opts)
	opts = opts or {}
	local id = opts.Id or nextId("slider")
	local min, max = opts.Min or 0, opts.Max or 100
	local default = opts.Default or min
	local suffix = opts.Suffix or ""

	local row = self:_registerRow(makeRow(self:_target(), 54), opts)
	new("TextLabel", {
		Text = opts.Text or "Slider",
		Font = Theme.Font,
		TextSize = 13,
		TextColor3 = Theme.TextPrimary,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(14, 8),
		Size = UDim2.new(1, -100, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = row,
	})
	local valueLabel = new("TextButton", {
		Text = tostring(default) .. suffix,
		Font = Theme.FontBold,
		TextSize = 13,
		TextColor3 = Theme.TextPrimary,
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Position = UDim2.new(1, -80, 0, 8),
		Size = UDim2.fromOffset(66, 18),
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = row,
	})
	local valueBox = new("TextBox", {
		Text = tostring(default),
		Font = Theme.FontBold,
		TextSize = 13,
		TextColor3 = Theme.TextPrimary,
		BackgroundColor3 = Theme.Card,
		Visible = false,
		ClearTextOnFocus = false,
		Position = UDim2.new(1, -80, 0, 6),
		Size = UDim2.fromOffset(66, 20),
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 5,
		Parent = row,
	})
	corner(valueBox, 4)

	local barBack = new("Frame", {
		Size = UDim2.new(1, -28, 0, 6),
		Position = UDim2.fromOffset(14, 34),
		BackgroundColor3 = Theme.AccentMuted,
		Active = true,
		Parent = row,
	})
	corner(barBack, 3)
	local barFill = new("Frame", {
		Size = UDim2.new((default - min) / (max - min), 0, 1, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = barBack,
	})
	corner(barFill, 3)
	local handle = new("Frame", {
		Size = UDim2.fromOffset(14, 14),
		Position = UDim2.new((default - min) / (max - min), -7, 0.5, -7),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = barBack,
	})
	corner(handle, 7)

	local value = default
	local dragging = false

	local function setFromAlpha(alpha)
		alpha = math.clamp(alpha, 0, 1)
		value = math.floor((min + (max - min) * alpha) * 100 + 0.5) / 100
		if opts.Integer ~= false then
			value = math.floor(value + 0.5)
		end
		barFill.Size = UDim2.new(alpha, 0, 1, 0)
		handle.Position = UDim2.new(alpha, -7, 0.5, -7)
		valueLabel.Text = tostring(value) .. suffix
		if opts.Callback then opts.Callback(value) end
		self.Window:_autoSave()
	end

	local function setValue(v, fireCallback)
		local alpha = (v - min) / (max - min)
		alpha = math.clamp(alpha, 0, 1)
		value = v
		barFill.Size = UDim2.new(alpha, 0, 1, 0)
		handle.Position = UDim2.new(alpha, -7, 0.5, -7)
		valueLabel.Text = tostring(v) .. suffix
		if fireCallback ~= false and opts.Callback then opts.Callback(v) end
		if fireCallback ~= false then self.Window:_autoSave() end
	end

	local function beginDrag(input)
		dragging = true
	end
	local function processInput(input)
		if dragging then
			local relX = input.Position.X - barBack.AbsolutePosition.X
			setFromAlpha(relX / barBack.AbsoluteSize.X)
		end
	end

	barBack.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			beginDrag(input)
			processInput(input)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			processInput(input)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)

	-- Editable value: click the number to type an exact value; Enter applies
	-- it (clamped to Min/Max), Escape/clicking away cancels.
	valueLabel.MouseButton1Click:Connect(function()
		valueBox.Text = tostring(value)
		valueLabel.Visible = false
		valueBox.Visible = true
		valueBox:CaptureFocus()
	end)
	valueBox.FocusLost:Connect(function(enterPressed)
		valueBox.Visible = false
		valueLabel.Visible = true
		if enterPressed then
			local n = tonumber(valueBox.Text)
			if n then
				n = math.clamp(n, min, max)
				if opts.Integer ~= false then n = math.floor(n + 0.5) end
				setValue(n, true)
			end
		end
	end)

	self.Controls[id] = {
		Get = function() return value end,
		Set = function(v) setValue(v, false) end,
	}

	return withLiveValue({ Set = function(v) setValue(v, false) end, Get = function() return value end }, function() return value end)
end

function Tab:AddDropdown(opts)
	opts = opts or {}
	local id = opts.Id or nextId("dropdown")
	local options = opts.Options or {}
	local multi = opts.Multi or false
	local selected = {}
	if opts.Default then
		if multi and typeof(opts.Default) == "table" then
			for _, v in ipairs(opts.Default) do selected[v] = true end
		else
			selected[opts.Default] = true
		end
	end

	local row = self:_registerRow(makeRow(self:_target(), 44), opts)
	new("TextLabel", {
		Text = opts.Text or "Dropdown",
		Font = Theme.Font,
		TextSize = 13,
		TextColor3 = Theme.TextPrimary,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(14, 0),
		Size = UDim2.new(0.5, 0, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = row,
	})

	local function summaryText()
		local names = {}
		for k, v in pairs(selected) do
			if v then table.insert(names, tostring(k)) end
		end
		if #names == 0 then return "None" end
		return table.concat(names, ", ")
	end

	local valueBtn = new("TextButton", {
		Text = summaryText(),
		Font = Theme.Font,
		TextSize = 12,
		TextColor3 = Theme.TextSecondary,
		TextTruncate = Enum.TextTruncate.AtEnd,
		BackgroundColor3 = Theme.Card,
		Size = UDim2.new(0.42, 0, 0, 28),
		Position = UDim2.new(1, -0.42 * 300 - 14, 0.5, -14),
		AnchorPoint = Vector2.new(0, 0),
		Parent = row,
	})
	valueBtn.Size = UDim2.new(0.42, 0, 0, 28)
	valueBtn.Position = UDim2.new(1, -160, 0.5, -14)
	valueBtn.Size = UDim2.fromOffset(146, 28)
	corner(valueBtn, 6)
	stroke(valueBtn, Theme.Border, 1)

	local optionList = new("Frame", {
		Size = UDim2.fromOffset(146, math.min(#options * 28, 160)),
		BackgroundColor3 = Theme.Card,
		Visible = false,
		ZIndex = 520,
		Parent = self.Window.Overlay,
	})
	corner(optionList, 6)
	stroke(optionList, Theme.Border, 1)
	local optScroll = new("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ScrollBarThickness = 3,
		CanvasSize = UDim2.new(0, 0, 0, #options * 28),
		ZIndex = 521,
		Parent = optionList,
	})
	local optLayout = new("UIListLayout", { Parent = optScroll })

	local function refreshLabel()
		valueBtn.Text = summaryText()
	end

	local function positionList()
		local pos, size = valueBtn.AbsolutePosition, valueBtn.AbsoluteSize
		optionList.Position = UDim2.fromOffset(pos.X + size.X - optionList.AbsoluteSize.X, pos.Y + size.Y + 4)
	end

	local function closeList()
		optionList.Visible = false
	end

	local function openList()
		positionList()
		optionList.Visible = true
	end

	for _, optName in ipairs(options) do
		local optBtn = new("TextButton", {
			Text = "  " .. optName,
			Font = Theme.Font,
			TextSize = 12,
			TextColor3 = selected[optName] and Theme.TextPrimary or Theme.TextSecondary,
			TextXAlignment = Enum.TextXAlignment.Left,
			BackgroundColor3 = Theme.Card,
			Size = UDim2.new(1, 0, 0, 28),
			ZIndex = 522,
			Parent = optScroll,
		})
		optBtn.MouseButton1Click:Connect(function()
			if multi then
				selected[optName] = not selected[optName]
			else
				selected = { [optName] = true }
				closeList()
			end
			for _, child in ipairs(optScroll:GetChildren()) do
				if child:IsA("TextButton") then
					local name = child.Text:gsub("^%s+", "")
					child.TextColor3 = selected[name] and Theme.TextPrimary or Theme.TextSecondary
				end
			end
			refreshLabel()
			if opts.Callback then
				if multi then
					local out = {}
					for k, v in pairs(selected) do if v then table.insert(out, k) end end
					opts.Callback(out)
				else
					local single
					for k, v in pairs(selected) do if v then single = k end end
					opts.Callback(single)
				end
			end
			self.Window:_autoSave()
		end)
	end

	valueBtn.MouseButton1Click:Connect(function()
		if optionList.Visible then closeList() else openList() end
	end)

	-- Click anywhere outside the button/list closes it — dropdown now lives
	-- in the Overlay so it always renders above every other control.
	UserInputService.InputBegan:Connect(function(input)
		if not optionList.Visible then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			local p = Vector2.new(input.Position.X, input.Position.Y)
			if not (pointInGui(p, optionList) or pointInGui(p, valueBtn)) then
				closeList()
			end
		end
	end)

	self.Controls[id] = {
		Get = function()
			if multi then
				local out = {}
				for k, v in pairs(selected) do if v then table.insert(out, k) end end
				return out
			else
				for k, v in pairs(selected) do if v then return k end end
				return nil
			end
		end,
		Set = function(v)
			if multi and typeof(v) == "table" then
				selected = {}
				for _, name in ipairs(v) do selected[name] = true end
			else
				selected = { [v] = true }
			end
			refreshLabel()
		end,
	}

	return withLiveValue({ Get = self.Controls[id].Get, Set = self.Controls[id].Set }, self.Controls[id].Get)
end

local function color3ToHex(c)
	return string.format("%02X%02X%02X", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end
local function hexToColor3(hex)
	hex = hex:gsub("#", ""):gsub("%s", "")
	if #hex ~= 6 then return nil end
	local r, g, b = tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16)
	if not (r and g and b) then return nil end
	return Color3.fromRGB(r, g, b)
end

local _defaultPresets = {
	Color3.fromRGB(255, 255, 255), Color3.fromRGB(255, 80, 80), Color3.fromRGB(255, 170, 60),
	Color3.fromRGB(255, 230, 70), Color3.fromRGB(100, 220, 120), Color3.fromRGB(70, 180, 255),
	Color3.fromRGB(140, 110, 255), Color3.fromRGB(255, 110, 200),
}
local _recentColors = {} -- shared across pickers in this session, newest first

-- Tab:ColorPicker({ Text, Default, Alpha = bool, Presets = {Color3,...}, Callback = function(color, alpha) end })
-- Popout design: SV square + hue slider + RGB/HEX inputs + presets/recents,
-- rendered in the Overlay layer so it draws above every other control.
function Tab:AddColorPicker(opts)
	opts = opts or {}
	local id = opts.Id or nextId("color")
	local color = opts.Default or Color3.new(1, 1, 1)
	local alpha = opts.AlphaDefault or 1
	local hasAlpha = opts.Alpha == true

	local row = self:_registerRow(makeRow(self:_target()), opts)
	new("TextLabel", {
		Text = opts.Text or "Color",
		Font = Theme.Font,
		TextSize = 13,
		TextColor3 = Theme.TextPrimary,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(14, 0),
		Size = UDim2.new(1, -70, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = row,
	})

	local swatch = new("TextButton", {
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.fromOffset(28, 28),
		Position = UDim2.new(1, -42, 0.5, -14),
		BackgroundColor3 = color,
		Parent = row,
	})
	corner(swatch, 6)
	stroke(swatch, Theme.Border, 1)

	local popup = new("Frame", {
		Size = UDim2.fromOffset(220, hasAlpha and 388 or 356),
		BackgroundColor3 = Theme.Panel,
		Visible = false,
		ZIndex = 520,
		Parent = self.Window.Overlay,
	})
	corner(popup, 10)
	stroke(popup, Theme.Border, 1)
	new("UIPadding", {
		PaddingTop = UDim.new(0, 12), PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), PaddingBottom = UDim.new(0, 12),
		Parent = popup,
	})
	new("UIListLayout", { Padding = UDim.new(0, 10), ZIndex = 520, Parent = popup })

	local h, s, v = color:ToHSV()

	-- SV square
	local svSquare = new("Frame", {
		Size = UDim2.new(1, 0, 0, 140),
		BackgroundColor3 = Color3.fromHSV(h, 1, 1),
		Active = true,
		ZIndex = 521,
		Parent = popup,
	})
	corner(svSquare, 6)
	local svWhite = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 522, Parent = svSquare })
	new("UIGradient", { Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.new(1, 1, 1)), Transparency = NumberSequence.new(0, 1), Parent = svWhite })
	corner(svWhite, 6)
	local svBlack = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, ZIndex = 523, Parent = svSquare })
	new("UIGradient", { Color = ColorSequence.new(Color3.new(0, 0, 0), Color3.new(0, 0, 0)), Transparency = NumberSequence.new(1, 0), Rotation = 90, Parent = svBlack })
	corner(svBlack, 6)
	local svCursor = new("Frame", {
		Size = UDim2.fromOffset(12, 12),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(s, 0, 1 - v, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ZIndex = 525,
		Parent = svSquare,
	})
	corner(svCursor, 6)
	stroke(svCursor, Color3.new(0, 0, 0), 2)

	-- Hue slider
	local hueBar = new("Frame", { Size = UDim2.new(1, 0, 0, 14), Active = true, ZIndex = 521, Parent = popup })
	corner(hueBar, 7)
	new("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255, 0, 0)),
			ColorSequenceKeypoint.new(0.17, Color3.fromRGB(255, 255, 0)),
			ColorSequenceKeypoint.new(0.33, Color3.fromRGB(0, 255, 0)),
			ColorSequenceKeypoint.new(0.50, Color3.fromRGB(0, 255, 255)),
			ColorSequenceKeypoint.new(0.67, Color3.fromRGB(0, 0, 255)),
			ColorSequenceKeypoint.new(0.83, Color3.fromRGB(255, 0, 255)),
			ColorSequenceKeypoint.new(1.00, Color3.fromRGB(255, 0, 0)),
		}),
		Parent = hueBar,
	})
	local hueCursor = new("Frame", {
		Size = UDim2.fromOffset(6, 18),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(h, 0, 0.5, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 522,
		Parent = hueBar,
	})
	corner(hueCursor, 3)
	stroke(hueCursor, Color3.new(0, 0, 0), 1)

	-- Alpha slider (optional)
	local alphaBar, alphaCursor, alphaFill
	if hasAlpha then
		alphaBar = new("Frame", { Size = UDim2.new(1, 0, 0, 14), BackgroundColor3 = Theme.AccentMuted, Active = true, ZIndex = 521, Parent = popup })
		corner(alphaBar, 7)
		alphaFill = new("Frame", { Size = UDim2.new(alpha, 0, 1, 0), BackgroundColor3 = color, ZIndex = 522, Parent = alphaBar })
		corner(alphaFill, 7)
		alphaCursor = new("Frame", {
			Size = UDim2.fromOffset(6, 18), AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(alpha, 0, 0.5, 0), BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 523, Parent = alphaBar,
		})
		corner(alphaCursor, 3)
		stroke(alphaCursor, Color3.new(0, 0, 0), 1)
	end

	-- Live preview + HEX input
	local previewRow = new("Frame", { Size = UDim2.new(1, 0, 0, 28), BackgroundTransparency = 1, ZIndex = 521, Parent = popup })
	local previewSwatch = new("Frame", { Size = UDim2.fromOffset(28, 28), BackgroundColor3 = color, ZIndex = 521, Parent = previewRow })
	corner(previewSwatch, 6)
	stroke(previewSwatch, Theme.Border, 1)
	local hexBox = new("TextBox", {
		Text = "#" .. color3ToHex(color),
		Font = Enum.Font.Code,
		TextSize = 13,
		TextColor3 = Theme.TextPrimary,
		BackgroundColor3 = Theme.Card,
		Position = UDim2.fromOffset(36, 0),
		Size = UDim2.new(1, -36, 1, 0),
		ClearTextOnFocus = false,
		ZIndex = 521,
		Parent = previewRow,
	})
	corner(hexBox, 6)
	stroke(hexBox, Theme.Border, 1)

	-- RGB inputs
	local rgbRow = new("Frame", { Size = UDim2.new(1, 0, 0, 26), BackgroundTransparency = 1, ZIndex = 521, Parent = popup })
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), ZIndex = 521, Parent = rgbRow })
	local function makeRGBBox(labelText, initial)
		local wrap = new("Frame", { Size = UDim2.new(0.333, -4, 1, 0), BackgroundColor3 = Theme.Card, ZIndex = 521, Parent = rgbRow })
		corner(wrap, 6)
		stroke(wrap, Theme.Border, 1)
		new("TextLabel", {
			Text = labelText, Font = Theme.Font, TextSize = 9, TextColor3 = Theme.TextSecondary,
			BackgroundTransparency = 1, Size = UDim2.fromOffset(14, 26), ZIndex = 521, Parent = wrap,
		})
		local box = new("TextBox", {
			Text = tostring(initial), Font = Theme.Font, TextSize = 12, TextColor3 = Theme.TextPrimary,
			BackgroundTransparency = 1, Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -16, 1, 0),
			ClearTextOnFocus = false, ZIndex = 521, Parent = wrap,
		})
		return box
	end
	local rBox = makeRGBBox("R", math.floor(color.R * 255 + 0.5))
	local gBox = makeRGBBox("G", math.floor(color.G * 255 + 0.5))
	local bBox = makeRGBBox("B", math.floor(color.B * 255 + 0.5))

	-- Presets
	new("TextLabel", { Text = "Presets", Font = Theme.Font, TextSize = 10, TextColor3 = Theme.TextSecondary, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 12), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 521, Parent = popup })
	local presetsRow = new("Frame", { Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1, ZIndex = 521, Parent = popup })
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), ZIndex = 521, Parent = presetsRow })

	-- Recents
	local recentsLabel = new("TextLabel", { Text = "Recent", Font = Theme.Font, TextSize = 10, TextColor3 = Theme.TextSecondary, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 12), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 521, Parent = popup })
	local recentsRow = new("Frame", { Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1, ZIndex = 521, Parent = popup })
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), ZIndex = 521, Parent = recentsRow })

	local updateAll -- forward declare

	local function makeSwatchButton(parent, c)
		local b = new("TextButton", { Text = "", AutoButtonColor = false, Size = UDim2.fromOffset(20, 20), BackgroundColor3 = c, ZIndex = 521, Parent = parent })
		corner(b, 5)
		stroke(b, Theme.Border, 1)
		b.MouseButton1Click:Connect(function()
			h, s, v = c:ToHSV()
			updateAll(true)
		end)
		return b
	end
	for _, c in ipairs(opts.Presets or _defaultPresets) do makeSwatchButton(presetsRow, c) end
	local function refreshRecents()
		for _, child in ipairs(recentsRow:GetChildren()) do
			if child:IsA("TextButton") then child:Destroy() end
		end
		for _, c in ipairs(_recentColors) do makeSwatchButton(recentsRow, c) end
	end
	refreshRecents()

	updateAll = function(fireCallback)
		color = Color3.fromHSV(h, s, v)
		swatch.BackgroundColor3 = color
		previewSwatch.BackgroundColor3 = color
		svSquare.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
		svCursor.Position = UDim2.new(s, 0, 1 - v, 0)
		hueCursor.Position = UDim2.new(h, 0, 0.5, 0)
		hexBox.Text = "#" .. color3ToHex(color)
		rBox.Text = tostring(math.floor(color.R * 255 + 0.5))
		gBox.Text = tostring(math.floor(color.G * 255 + 0.5))
		bBox.Text = tostring(math.floor(color.B * 255 + 0.5))
		if alphaFill then alphaFill.BackgroundColor3 = color end
		if fireCallback ~= false then
			if opts.Callback then
				if hasAlpha then opts.Callback(color, alpha) else opts.Callback(color) end
			end
			self.Window:_autoSave()
		end
	end

	-- SV square drag
	local svDragging = false
	svSquare.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then svDragging = true end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if svDragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local rel = Vector2.new(
				math.clamp((input.Position.X - svSquare.AbsolutePosition.X) / svSquare.AbsoluteSize.X, 0, 1),
				math.clamp((input.Position.Y - svSquare.AbsolutePosition.Y) / svSquare.AbsoluteSize.Y, 0, 1)
			)
			s, v = rel.X, 1 - rel.Y
			updateAll(true)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then svDragging = false end
	end)

	-- Hue slider drag
	local hueDragging = false
	hueBar.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then hueDragging = true end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if hueDragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			h = math.clamp((input.Position.X - hueBar.AbsolutePosition.X) / hueBar.AbsoluteSize.X, 0, 1)
			updateAll(true)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then hueDragging = false end
	end)

	-- Alpha slider drag
	if hasAlpha then
		local alphaDragging = false
		alphaBar.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then alphaDragging = true end
		end)
		UserInputService.InputChanged:Connect(function(input)
			if alphaDragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
				alpha = math.clamp((input.Position.X - alphaBar.AbsolutePosition.X) / alphaBar.AbsoluteSize.X, 0, 1)
				alphaCursor.Position = UDim2.new(alpha, 0, 0.5, 0)
				alphaFill.Size = UDim2.new(alpha, 0, 1, 0)
				updateAll(true)
			end
		end)
		UserInputService.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then alphaDragging = false end
		end)
	end

	-- HEX / RGB text input
	hexBox.FocusLost:Connect(function()
		local parsed = hexToColor3(hexBox.Text)
		if parsed then
			h, s, v = parsed:ToHSV()
			updateAll(true)
		else
			hexBox.Text = "#" .. color3ToHex(color)
		end
	end)
	local function bindRGBBox(box)
		box.FocusLost:Connect(function()
			local n = tonumber(box.Text)
			if n then
				n = math.clamp(math.floor(n), 0, 255)
				local newColor = Color3.fromRGB(
					box == rBox and n or math.floor(color.R * 255 + 0.5),
					box == gBox and n or math.floor(color.G * 255 + 0.5),
					box == bBox and n or math.floor(color.B * 255 + 0.5)
				)
				h, s, v = newColor:ToHSV()
				updateAll(true)
			else
				updateAll(false)
			end
		end)
	end
	bindRGBBox(rBox); bindRGBBox(gBox); bindRGBBox(bBox)

	-- Open/close (popout renders in Overlay, positioned near the swatch,
	-- closes on outside click — same pattern as dropdowns)
	local function positionPopup()
		local pos, size = swatch.AbsolutePosition, swatch.AbsoluteSize
		popup.Position = UDim2.fromOffset(pos.X + size.X - popup.AbsoluteSize.X, pos.Y + size.Y + 6)
	end
	local function closePopup()
		popup.Visible = false
		-- commit to recents on close, newest first, de-duplicated, capped at 6
		for i = #_recentColors, 1, -1 do
			if _recentColors[i] == color then table.remove(_recentColors, i) end
		end
		table.insert(_recentColors, 1, color)
		while #_recentColors > 6 do table.remove(_recentColors) end
		refreshRecents()
	end
	swatch.MouseButton1Click:Connect(function()
		if popup.Visible then
			closePopup()
		else
			positionPopup()
			popup.Visible = true
		end
	end)
	UserInputService.InputBegan:Connect(function(input)
		if not popup.Visible then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			local p = Vector2.new(input.Position.X, input.Position.Y)
			if not (pointInGui(p, popup) or pointInGui(p, swatch)) then
				closePopup()
			end
		end
	end)

	self.Controls[id] = {
		Get = function() return { r = color.R, g = color.G, b = color.B, a = alpha } end,
		Set = function(val)
			if typeof(val) == "table" then
				h, s, v = Color3.new(val.r, val.g, val.b):ToHSV()
				if val.a then alpha = val.a end
			elseif typeof(val) == "Color3" then
				h, s, v = val:ToHSV()
			end
			updateAll(false)
		end,
	}

	return withLiveValue({
		Get = function() return color end,
		Set = function(v) self.Controls[id].Set(v) end,
	}, function() return color end)
end

function Tab:AddButton(opts)
	opts = opts or {}
	local row = self:_registerRow(makeRow(self:_target(), 40), opts)
	local btn = new("TextButton", {
		Text = opts.Text or opts.Title or "Button",
		Font = Theme.FontBold,
		TextSize = 13,
		TextColor3 = Theme.TextPrimary,
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Size = UDim2.fromScale(1, 1),
		Parent = row,
	})
	btn.MouseEnter:Connect(function() tween(row, { BackgroundColor3 = Theme.CardHover }, 0.12) end)
	btn.MouseLeave:Connect(function() tween(row, { BackgroundColor3 = Theme.Panel }, 0.12) end)
	btn.MouseButton1Down:Connect(function() tween(btn, { TextTransparency = 0.4 }, 0.08) end)
	btn.MouseButton1Up:Connect(function() tween(btn, { TextTransparency = 0 }, 0.12) end)
	btn.MouseButton1Click:Connect(function()
		if opts.Callback then opts.Callback() end
	end)
	return btn
end
Tab.Button = Tab.AddButton -- Tab:Button({ Title = "...", Callback = ... }) alias to match spec examples

-- Tab:Divider() or Tab:Divider({ Text = "Section", Size = "sm"|"md"|"lg", Hidden = fn })
function Tab:AddDivider(opts)
	opts = opts or {}
	local sizeMap = { sm = 16, md = 24, lg = 36 }
	local h = sizeMap[opts.Size] or sizeMap.md
	local row = self:_registerRow(new("Frame", {
		Size = UDim2.new(1, 0, 0, h),
		BackgroundTransparency = 1,
		Parent = self:_target(),
	}), opts)

	if opts.Text then
		local lineL = new("Frame", { Size = UDim2.new(0.5, -40, 0, 1), Position = UDim2.new(0, 0, 0.5, 0), BackgroundColor3 = Theme.Border, Parent = row })
		local label = new("TextLabel", {
			Text = opts.Text,
			Font = Theme.Font,
			TextSize = 11,
			TextColor3 = Theme.TextSecondary,
			BackgroundTransparency = 1,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, h),
			Position = UDim2.new(0.5, 0, 0, 0),
			AnchorPoint = Vector2.new(0.5, 0),
			Parent = row,
		})
		local lineR = new("Frame", { Size = UDim2.new(0.5, -40, 0, 1), Position = UDim2.new(1, 0, 0.5, 0), AnchorPoint = Vector2.new(1, 0), BackgroundColor3 = Theme.Border, Parent = row })
	else
		new("Frame", {
			Size = UDim2.new(1, 0, 0, 1),
			Position = UDim2.new(0, 0, 0.5, 0),
			BackgroundColor3 = Theme.Border,
			Parent = row,
		})
	end
	return row
end
Tab.Divider = Tab.AddDivider

function Tab:AddLabel(text)
	local row = self:_registerRow(new("Frame", { Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1, Parent = self:_target() }))
	new("TextLabel", {
		Text = text,
		Font = Theme.Font,
		TextSize = 12,
		TextColor3 = Theme.TextSecondary,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = row,
	})
	return row
end

-- Tab:TextBox({ Title, Placeholder, Default, Clearable, Callback })
-- Tab:Textbox({ Title, Desc, Icon, Placeholder, Default, CharacterLimit,
--   Mode = "Text"|"Number"|"Decimal"|"Integer"|"Alphanumeric", Validator = fn,
--   Clearable, Callback })
function Tab:AddTextBox(opts)
	opts = opts or {}
	local id = opts.Id or nextId("textbox")
	local hasDesc = opts.Desc ~= nil
	local hasIcon = opts.Icon ~= nil
	local height = 54 + (hasDesc and 14 or 0)
	local row = self:_registerRow(makeRow(self:_target(), height), opts)
	local textX = hasIcon and 32 or 14

	if hasIcon then
		new("TextLabel", {
			Text = opts.Icon,
			Font = Theme.FontBold,
			TextSize = 14,
			TextColor3 = Theme.TextSecondary,
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(12, 8),
			Size = UDim2.fromOffset(18, 18),
			Parent = row,
		})
	end

	new("TextLabel", {
		Text = opts.Title or opts.Text or "Text Input",
		Font = Theme.Font,
		TextSize = 13,
		TextColor3 = Theme.TextPrimary,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(textX, 8),
		Size = UDim2.new(1, -textX - 14, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = row,
	})
	if hasDesc then
		new("TextLabel", {
			Text = opts.Desc,
			Font = Theme.Font,
			TextSize = 11,
			TextColor3 = Theme.TextSecondary,
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(textX, 24),
			Size = UDim2.new(1, -textX - 14, 0, 14),
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = row,
		})
	end

	local inputY = hasDesc and 40 or 22
	local inputWrap = new("Frame", {
		Size = UDim2.new(1, -28, 0, 26),
		Position = UDim2.fromOffset(14, inputY),
		BackgroundColor3 = Theme.Card,
		Parent = row,
	})
	corner(inputWrap, 6)
	stroke(inputWrap, Theme.Border, 1)

	local box = new("TextBox", {
		Text = opts.Default or "",
		PlaceholderText = opts.Placeholder or "",
		PlaceholderColor3 = Theme.TextSecondary,
		Font = Theme.Font,
		TextSize = 12,
		TextColor3 = Theme.TextPrimary,
		BackgroundTransparency = 1,
		ClearTextOnFocus = false,
		Size = UDim2.new(1, opts.Clearable and -26 or -12, 1, 0),
		Position = UDim2.fromOffset(8, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = inputWrap,
	})

	-- Validation: filters keystrokes live so invalid characters never stick,
	-- then reverts to the last valid text if a custom Validator rejects it.
	local mode = opts.Mode
	local modeFilters = {
		Number = "%d",
		Integer = "%d",
		Decimal = "[%d%.]",
		Alphanumeric = "[%w]",
	}
	local lastValid = box.Text
	box:GetPropertyChangedSignal("Text"):Connect(function()
		local text = box.Text
		if opts.CharacterLimit and #text > opts.CharacterLimit then
			text = text:sub(1, opts.CharacterLimit)
		end
		local pattern = mode and modeFilters[mode]
		if pattern then
			local filtered = text:gsub("[^" .. pattern:gsub("[%[%]]", "") .. "]", "")
			-- allow a single leading "-" for negative numbers
			if mode == "Number" or mode == "Integer" or mode == "Decimal" then
				local sign = text:match("^%-") or ""
				filtered = sign .. filtered:gsub("^%-", "")
			end
			text = filtered
		end
		if text ~= box.Text then box.Text = text end
		if opts.Validator and not opts.Validator(text) then
			box.Text = lastValid
			return
		end
		lastValid = box.Text
	end)

	if opts.Clearable then
		local clearBtn = new("TextButton", {
			Text = "×",
			Font = Theme.FontBold,
			TextSize = 14,
			TextColor3 = Theme.TextSecondary,
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(22, 26),
			Position = UDim2.new(1, -22, 0, 0),
			Parent = inputWrap,
		})
		clearBtn.MouseButton1Click:Connect(function()
			box.Text = ""
			lastValid = ""
			if opts.Callback then opts.Callback("") end
			self.Window:_autoSave()
		end)
	end

	box.FocusLost:Connect(function(enterPressed)
		if opts.Callback then opts.Callback(box.Text) end
		self.Window:_autoSave()
	end)

	self.Controls[id] = {
		Get = function() return box.Text end,
		Set = function(v) box.Text = tostring(v); lastValid = box.Text end,
	}
	return withLiveValue({ Get = self.Controls[id].Get, Set = self.Controls[id].Set }, self.Controls[id].Get)
end
Tab.TextBox = Tab.AddTextBox
Tab.Textbox = Tab.AddTextBox

-- Tab:Keybind({ Title, Value = "V", MobilePosition = UDim2, Callback = function(key) end })
-- Desktop: click the key display to listen, press any key to bind, Escape clears.
-- Mobile: no keyboard, so the key display instead toggles a single floating,
-- draggable action button; tapping it fires Callback. Its dragged position
-- persists through the normal Get/Set config system, same as everything else.
function Tab:AddKeybind(opts)
	opts = opts or {}
	local id = opts.Id or nextId("keybind")
	local row = self:_registerRow(makeRow(self:_target(), 44), opts)

	new("TextLabel", {
		Text = opts.Title or "Keybind",
		Font = Theme.Font,
		TextSize = 13,
		TextColor3 = Theme.TextPrimary,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(14, 0),
		Size = UDim2.new(1, -110, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = row,
	})

	local currentKey = opts.Value or "None"
	local listening = false
	local floatingBtn = nil

	local keyBtn = new("TextButton", {
		Text = currentKey,
		Font = Theme.FontBold,
		TextSize = 12,
		TextColor3 = Theme.TextPrimary,
		BackgroundColor3 = Theme.Card,
		AutoButtonColor = false,
		Size = UDim2.fromOffset(84, 26),
		Position = UDim2.new(1, -98, 0.5, -13),
		Parent = row,
	})
	corner(keyBtn, 6)
	stroke(keyBtn, Theme.Border, 1)

	local function setKey(k, fireCallback)
		currentKey = k
		keyBtn.Text = k
		if fireCallback ~= false and opts.Callback then opts.Callback(k) end
		if fireCallback ~= false then self.Window:_autoSave() end
	end

	local function ensureFloatingButton()
		if floatingBtn then return floatingBtn end
		floatingBtn = new("TextButton", {
			Text = (opts.Title or "•"):sub(1, 3),
			Font = Theme.FontBold,
			TextSize = 11,
			TextColor3 = Theme.TextPrimary,
			BackgroundColor3 = Theme.Panel,
			AutoButtonColor = false,
			Size = UDim2.fromOffset(56, 56),
			-- sensible default corner position, not wherever the user tapped
			Position = opts.MobilePosition or UDim2.new(1, -76, 1, -160),
			Active = true,
			ZIndex = 550,
			Parent = self.Window.Overlay,
		})
		corner(floatingBtn, 28)
		stroke(floatingBtn, Theme.Border, 1)

		local dragging, dragStart, startPos, moved = false, nil, nil, false
		floatingBtn.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
				dragging = true
				moved = false
				dragStart = input.Position
				startPos = floatingBtn.Position
			end
		end)
		UserInputService.InputChanged:Connect(function(input)
			if dragging and (input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseMovement) then
				local delta = input.Position - dragStart
				if delta.Magnitude > 4 then moved = true end
				floatingBtn.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
			end
		end)
		UserInputService.InputEnded:Connect(function(input)
			if dragging and (input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1) then
				dragging = false
				if moved then
					self.Window:_autoSave() -- persists the new dragged position
				else
					if opts.Callback then opts.Callback(currentKey) end
				end
			end
		end)
		return floatingBtn
	end

	keyBtn.MouseButton1Click:Connect(function()
		if isMobile() then
			local fb = ensureFloatingButton()
			fb.Visible = not fb.Visible
		else
			listening = true
			keyBtn.Text = "..."
		end
	end)

	if not isMobile() then
		UserInputService.InputBegan:Connect(function(input)
			if not listening then return end
			if input.UserInputType == Enum.UserInputType.Keyboard then
				listening = false
				if input.KeyCode == Enum.KeyCode.Escape then
					setKey("None")
				else
					setKey(input.KeyCode.Name)
				end
			end
		end)
	end

	self.Controls[id] = {
		Get = function()
			local data = { key = currentKey }
			if floatingBtn then
				data.pos = { x = floatingBtn.Position.X.Offset, y = floatingBtn.Position.Y.Offset }
			end
			return data
		end,
		Set = function(v)
			if type(v) == "table" then
				if v.key then setKey(v.key, false) end
				if v.pos then
					ensureFloatingButton().Position = UDim2.new(0, v.pos.x, 0, v.pos.y)
				end
			end
		end,
	}

	return withLiveValue({ Get = self.Controls[id].Get, Set = self.Controls[id].Set }, function() return currentKey end)
end
Tab.Keybind = Tab.AddKeybind

-- Lightweight single-pass highlighter (not a full tokenizer/parser — good
-- enough for readability, not a syntax-perfect Lua lexer). Single-pass
-- avoids the classic bug where layering separate gsub passes for
-- comments/strings/keywords corrupts already-inserted <font> tags.
local function escapeRichText(s)
	return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end
local _LUA_KEYWORDS = {}
for _, k in ipairs({
	"function", "local", "end", "if", "then", "else", "elseif", "return",
	"for", "while", "do", "and", "or", "not", "true", "false", "nil",
	"break", "repeat", "until", "in",
}) do
	_LUA_KEYWORDS[k] = true
end
local function highlightLua(code)
	local out, i, n = {}, 1, #code
	while i <= n do
		local c = code:sub(i, i)
		if c == "-" and code:sub(i, i + 1) == "--" then
			local nl = code:find("\n", i, true)
			local seg = nl and code:sub(i, nl - 1) or code:sub(i)
			table.insert(out, "<font color=\"rgb(106,153,85)\">" .. escapeRichText(seg) .. "</font>")
			i = nl or (n + 1)
		elseif c == "\"" or c == "'" then
			local q, j = c, i + 1
			while j <= n and code:sub(j, j) ~= q do j = j + 1 end
			local seg = code:sub(i, math.min(j, n))
			table.insert(out, "<font color=\"rgb(206,145,120)\">" .. escapeRichText(seg) .. "</font>")
			i = j + 1
		elseif c:match("%a") or c == "_" then
			local j = i
			while j <= n and code:sub(j, j):match("[%w_]") do j = j + 1 end
			local word = code:sub(i, j - 1)
			if _LUA_KEYWORDS[word] then
				table.insert(out, "<font color=\"rgb(197,134,192)\">" .. word .. "</font>")
			else
				table.insert(out, escapeRichText(word))
			end
			i = j
		else
			table.insert(out, escapeRichText(c))
			i = i + 1
		end
	end
	return table.concat(out)
end

-- Tab:Code({ Title, Code, LineNumbers = true })
-- Roblox LocalScripts have no system clipboard write API, so "Copy" focuses
-- a hidden selectable TextBox with the raw code and prompts the player to
-- press Ctrl+C themselves — the closest honest equivalent available.
function Tab:AddCode(opts)
	opts = opts or {}
	local code = opts.Code or ""
	local showLineNumbers = opts.LineNumbers ~= false
	local lineCount = select(2, code:gsub("\n", "\n")) + 1
	local bodyHeight = math.clamp(lineCount * 16 + 12, 40, 220)

	local row = self:_registerRow(makeRow(opts.Fully and self.FullWidth or self:_target(), 34 + bodyHeight), opts)

	new("TextLabel", {
		Text = opts.Title or "Code",
		Font = Theme.Font,
		TextSize = 12,
		TextColor3 = Theme.TextSecondary,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(14, 8),
		Size = UDim2.new(1, -80, 0, 16),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = row,
	})
	local copyBtn = new("TextButton", {
		Text = "Copy",
		Font = Theme.FontBold,
		TextSize = 11,
		TextColor3 = Theme.TextSecondary,
		BackgroundColor3 = Theme.Card,
		Size = UDim2.fromOffset(52, 20),
		Position = UDim2.new(1, -66, 0, 6),
		Parent = row,
	})
	corner(copyBtn, 5)

	local codeBg = new("Frame", {
		Position = UDim2.fromOffset(14, 30),
		Size = UDim2.new(1, -28, 0, bodyHeight),
		BackgroundColor3 = Theme.Card,
		Parent = row,
	})
	corner(codeBg, 6)
	stroke(codeBg, Theme.Border, 1)

	local scroll = new("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		CanvasSize = UDim2.new(0, 0, 0, lineCount * 16 + 12),
		Parent = codeBg,
	})
	local textX = showLineNumbers and 38 or 8

	if showLineNumbers then
		local numLines = {}
		for idx = 1, lineCount do numLines[idx] = tostring(idx) end
		new("TextLabel", {
			Text = table.concat(numLines, "\n"),
			Font = Enum.Font.Code,
			TextSize = 12,
			TextColor3 = Theme.TextSecondary,
			TextTransparency = 0.4,
			BackgroundTransparency = 1,
			TextXAlignment = Enum.TextXAlignment.Right,
			TextYAlignment = Enum.TextYAlignment.Top,
			Position = UDim2.fromOffset(6, 6),
			Size = UDim2.fromOffset(24, lineCount * 16),
			Parent = scroll,
		})
	end

	new("TextLabel", {
		Text = highlightLua(code),
		RichText = true,
		Font = Enum.Font.Code,
		TextSize = 12,
		TextColor3 = Theme.TextPrimary,
		BackgroundTransparency = 1,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = false,
		Position = UDim2.fromOffset(textX, 6),
		Size = UDim2.new(1, -textX - 8, 0, lineCount * 16),
		Parent = scroll,
	})

	-- hidden raw TextBox purely so the player has something focusable/
	-- selectable to Ctrl+C from — Roblox gives LocalScripts no clipboard API
	local hiddenBox = new("TextBox", {
		Text = code,
		Visible = false,
		Parent = codeBg,
	})
	copyBtn.MouseButton1Click:Connect(function()
		hiddenBox.Visible = true
		hiddenBox:CaptureFocus()
		self.Window:Notify({
			Title = "Ready to copy",
			Desc = "Press Ctrl+C now — Roblox doesn't let scripts copy for you",
			Icon = "⧉",
			Duration = 3,
		})
		task.delay(4, function() hiddenBox.Visible = false end)
	end)

	return row
end
Tab.Code = Tab.AddCode

-- Tab:Paragraph({ Title, Desc, Image (emoji/text icon or rbxassetid), ImageSize, Buttons = {{Title, Callback}, ...} })
function Tab:AddParagraph(opts)
	opts = opts or {}
	local hasButtons = opts.Buttons and #opts.Buttons > 0
	local hasImage = opts.Image ~= nil
	local baseHeight = 20 + (opts.Desc and 18 or 0) + (hasButtons and 34 or 0) + 24

	local row = self:_registerRow(makeRow(self:_target(), baseHeight), opts)
	local textX = hasImage and 54 or 14

	if hasImage then
		local imgBox = new("Frame", {
			Size = UDim2.fromOffset(opts.ImageSize or 28, opts.ImageSize or 28),
			Position = UDim2.fromOffset(14, 14),
			BackgroundColor3 = Theme.AccentMuted,
			Parent = row,
		})
		corner(imgBox, 6)
		if typeof(opts.Image) == "string" and opts.Image:match("^rbxassetid://") then
			new("ImageLabel", { Image = opts.Image, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = imgBox })
		else
			-- treat as an emoji/text glyph placeholder icon
			new("TextLabel", {
				Text = opts.Image or "•",
				Font = Theme.FontBold,
				TextSize = 14,
				TextColor3 = Theme.TextPrimary,
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 1),
				Parent = imgBox,
			})
		end
	end

	new("TextLabel", {
		Text = opts.Title or "Title",
		Font = Theme.FontBold,
		TextSize = 14,
		TextColor3 = Theme.TextPrimary,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(textX, 12),
		Size = UDim2.new(1, -textX - 14, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = row,
	})
	if opts.Desc then
		new("TextLabel", {
			Text = opts.Desc,
			Font = Theme.Font,
			TextSize = 12,
			TextColor3 = Theme.TextSecondary,
			BackgroundTransparency = 1,
			TextWrapped = true,
			Position = UDim2.fromOffset(textX, 30),
			Size = UDim2.new(1, -textX - 14, 0, 18),
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = row,
		})
	end

	if hasButtons then
		local btnRow = new("Frame", {
			Size = UDim2.new(1, -textX - 14, 0, 26),
			Position = UDim2.fromOffset(textX, baseHeight - 32),
			BackgroundTransparency = 1,
			Parent = row,
		})
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), Parent = btnRow })
		for _, b in ipairs(opts.Buttons) do
			local pbtn = new("TextButton", {
				Text = b.Title or "Button",
				Font = Theme.FontBold,
				TextSize = 12,
				TextColor3 = Theme.Background,
				BackgroundColor3 = Theme.Accent,
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, 26),
				Parent = btnRow,
			})
			new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), Parent = pbtn })
			corner(pbtn, 6)
			pbtn.MouseButton1Click:Connect(function()
				if b.Callback then b.Callback() end
			end)
		end
	end

	return row
end
Tab.Paragraph = Tab.AddParagraph

-- local Progress = Tab:ProgressBar({ Title, Desc, Value = {Min, Max, Default}, DisplayMode = "Value"|"Percent" })
-- Progress:Set(newValue) animates the fill.
function Tab:AddProgressBar(opts)
	opts = opts or {}
	local id = opts.Id or nextId("progress")
	local v = opts.Value or {}
	local min, max = v.Min or 0, v.Max or 100
	local value = v.Default or min
	local displayMode = opts.DisplayMode or "Percent"
	local barColor = opts.Color or Theme.Accent

	local row = self:_registerRow(makeRow(opts.Fully and self.FullWidth or self:_target(), 62), opts)
	new("TextLabel", {
		Text = opts.Title or "Progress",
		Font = Theme.Font,
		TextSize = 13,
		TextColor3 = Theme.TextPrimary,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(14, 8),
		Size = UDim2.new(1, -100, 0, 16),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = row,
	})
	local valueLabel = new("TextLabel", {
		Text = "",
		Font = Theme.FontBold,
		TextSize = 12,
		TextColor3 = Theme.TextSecondary,
		BackgroundTransparency = 1,
		Position = UDim2.new(1, -80, 0, 8),
		Size = UDim2.fromOffset(66, 16),
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = row,
	})
	if opts.Desc then
		new("TextLabel", {
			Text = opts.Desc,
			Font = Theme.Font,
			TextSize = 11,
			TextColor3 = Theme.TextSecondary,
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(14, 24),
			Size = UDim2.new(1, -28, 0, 14),
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = row,
		})
	end

	local barBack = new("Frame", {
		Size = UDim2.new(1, -28, 0, 8),
		Position = UDim2.fromOffset(14, 44),
		BackgroundColor3 = Theme.AccentMuted,
		Parent = row,
	})
	corner(barBack, 4)
	local barFill = new("Frame", {
		Size = UDim2.new(0, 0, 1, 0),
		BackgroundColor3 = barColor,
		Parent = barBack,
	})
	corner(barFill, 4)

	local function refresh()
		local alpha = max > min and math.clamp((value - min) / (max - min), 0, 1) or 0
		tween(barFill, { Size = UDim2.new(alpha, 0, 1, 0) }, 0.3, Enum.EasingStyle.Quart)
		if displayMode == "Value" then
			valueLabel.Text = string.format("%d/%d", value, max)
		else
			valueLabel.Text = string.format("%d%%", math.floor(alpha * 100 + 0.5))
		end
	end
	refresh()

	self.Controls[id] = {
		Get = function() return value end,
		Set = function(nv) value = math.clamp(nv, min, max); refresh() end,
	}

	return withLiveValue({
		Set = function(nv) value = math.clamp(nv, min, max); refresh() end,
		Get = function() return value end,
	}, function() return value end)
end
Tab.ProgressBar = Tab.AddProgressBar

-- Short-name aliases matching common UI-library conventions, all pointing
-- to the same implementations above (Tab:Toggle == Tab:AddToggle, etc).
Tab.Toggle = Tab.AddToggle
Tab.Slider = Tab.AddSlider
Tab.Dropdown = Tab.AddDropdown
Tab.ColorPicker = Tab.AddColorPicker
Tab.Label = Tab.AddLabel
Tab.SectionLabel = Tab.AddSectionLabel

--=========================================================
-- READY-MADE UI SETTINGS PANEL
--=========================================================
-- Window:AddSettingsTab() builds a full "UI Settings" tab wired to the
-- library's live theme controls. Notes on what's genuinely real-time vs.
-- applied going forward (Roblox has no true GPU blur for 2D UI, so
-- Blur/Acrylic is a semi-transparent layered approximation, not a real
-- backdrop blur):
--   Real-time across the whole UI already on screen:
--     Accent Color, Corner Roundness, Animation Speed, Window Resizing,
--     UI Scale
--   Applied to components created after the change (documented, not a bug):
--     Padding, Compact Mode, Font, Icon Size — retroactively resizing every
--     existing row would require a full re-layout pass; these are exposed
--     as Theme fields for your own components to read going forward.
function Window:AddSettingsTab(sectionOrWindow)
	local host = sectionOrWindow or self
	local Tab = host:AddTab({ Title = "UI Settings", Icon = "⚙" })
	local W = self

	Tab:AddSectionLabel("Appearance")
	Tab:AddDropdown({
		Text = "Theme",
		Options = { "Dark (default)", "Midnight", "Charcoal" },
		Default = "Dark (default)",
		Callback = function(v)
			if v == "Midnight" then
				Theme.Background = Color3.fromRGB(10, 10, 14)
				Theme.Panel = Color3.fromRGB(16, 16, 22)
			elseif v == "Charcoal" then
				Theme.Background = Color3.fromRGB(24, 24, 24)
				Theme.Panel = Color3.fromRGB(30, 30, 30)
			else
				Theme.Background = Color3.fromRGB(18, 18, 20)
				Theme.Panel = Color3.fromRGB(22, 22, 25)
			end
			tween(W.Root, { BackgroundColor3 = Theme.Background }, 0.2)
			W:Notify({ Title = "Theme changed", Desc = v, Icon = "🎨", Duration = 2.5 })
		end,
	})
	Tab:AddColorPicker({
		Text = "Accent Color",
		Default = Theme.Accent,
		Callback = function(c) setAccentColor(c) end,
	})

	Tab:AddSectionLabel("Layout")
	Tab:AddSlider({
		Text = "UI Scale",
		Min = 60, Max = 130, Default = 100, Suffix = "%",
		Callback = function(v)
			if W.UIScaleInstance then
				tween(W.UIScaleInstance, { Scale = v / 100 }, 0.12)
			end
		end,
	})
	Tab:AddToggle({
		Text = "Allow Window Resizing",
		Default = true,
		Callback = function(v)
			if W.ResizeHandle then W.ResizeHandle.Visible = v end
		end,
	})
	Tab:AddSlider({
		Text = "Corner Roundness",
		Min = 0, Max = 16, Default = Theme.CornerRadius, Suffix = "px",
		Callback = function(v) setCornerRadius(v) end,
	})
	Tab:AddSlider({
		Text = "UI Padding",
		Min = 4, Max = 16, Default = Theme.Padding, Suffix = "px",
		Callback = function(v) Theme.Padding = v end,
	})
	Tab:AddToggle({
		Text = "Compact Mode",
		Default = false,
		Callback = function(v) Theme.CompactMode = v end,
	})

	Tab:AddSectionLabel("Effects")
	Tab:AddSlider({
		Text = "Transparency",
		Min = 0, Max = 60, Default = 0, Suffix = "%",
		Callback = function(v)
			Theme.Transparency = v / 100
			tween(W.Root, { BackgroundTransparency = Theme.Transparency }, 0.15)
		end,
	})
	Tab:AddToggle({
		Text = "Acrylic / Glass Effect",
		Default = false,
		Callback = function(v)
			-- Approximation only — Roblox 2D UI has no real backdrop blur.
			-- This layers a translucent panel tint to fake a frosted look.
			tween(W.Root, { BackgroundTransparency = v and 0.12 or Theme.Transparency }, 0.2)
			W:Notify({
				Title = "Glass effect " .. (v and "on" or "off"),
				Desc = "Approximated — Roblox UI has no true backdrop blur",
				Icon = "◇",
				Duration = 3,
			})
		end,
	})
	Tab:AddSlider({
		Text = "Animation Speed",
		Min = 50, Max = 200, Default = 100, Suffix = "%",
		Callback = function(v)
			-- Lower % = faster animations (multiplier < 1), matching the
			-- slider reading like a "speed" control rather than a duration.
			Theme.AnimSpeed = 100 / v
		end,
	})
	Tab:AddDropdown({
		Text = "Gradient Background",
		Options = { "None", "Sunset", "Ocean", "Violet" },
		Default = "None",
		Callback = function(v)
			if v == "None" then
				W:ClearGradients()
				return
			end
			local presets = {
				Sunset = ColorSequence.new(Color3.fromRGB(30, 18, 22), Color3.fromRGB(20, 20, 26)),
				Ocean = ColorSequence.new(Color3.fromRGB(14, 22, 30), Color3.fromRGB(20, 20, 26)),
				Violet = ColorSequence.new(Color3.fromRGB(24, 16, 32), Color3.fromRGB(20, 20, 26)),
			}
			W:SetPrimaryGradient(presets[v], 135)
		end,
	})

	Tab:AddSectionLabel("Text & Icons")
	Tab:AddDropdown({
		Text = "Font",
		Options = { "Gotham", "GothamBold", "SourceSans", "Code" },
		Default = "Gotham",
		Callback = function(v)
			local map = {
				Gotham = Enum.Font.GothamMedium,
				GothamBold = Enum.Font.GothamBold,
				SourceSans = Enum.Font.SourceSans,
				Code = Enum.Font.Code,
			}
			Theme.Font = map[v] or Theme.Font
		end,
	})
	Tab:AddSlider({
		Text = "Icon Size",
		Min = 12, Max = 28, Default = Theme.IconSize, Suffix = "px",
		Callback = function(v) Theme.IconSize = v end,
	})

	return Tab
end

UILib.Icons = Icons

return UILib

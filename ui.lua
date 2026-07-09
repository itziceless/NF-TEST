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

	local contentHeader = new("TextLabel", {
		Text = "",
		Font = Theme.FontBold,
		TextSize = 20,
		TextColor3 = Theme.TextPrimary,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(24, 20),
		Size = UDim2.new(1, -48, 0, 28),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = content,
	})

	local pageHolder = new("Frame", {
		Name = "Pages",
		Position = UDim2.fromOffset(24, 60),
		Size = UDim2.new(1, -48, 1, -84),
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
		Size = UDim2.new(0.5, -6, 0, 0),
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
		Parent = columns,
	})
	new("UIListLayout", { Padding = UDim.new(0, 12), Parent = colRight })

	local tabObj = setmetatable({}, Tab)
	tabObj.Name = name
	tabObj.Button = btn
	tabObj.Page = page
	tabObj.ColumnLeft = colLeft
	tabObj.ColumnRight = colRight
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
		Size = UDim2.fromOffset(360, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Theme.Panel,
		ZIndex = 701,
		Parent = dim,
	})
	corner(card, 12)
	stroke(card, Theme.Border, 1)
	new("UIPadding", {
		PaddingTop = UDim.new(0, 20), PaddingBottom = UDim.new(0, 20),
		PaddingLeft = UDim.new(0, 20), PaddingRight = UDim.new(0, 20),
		Parent = card,
	})
	new("UIListLayout", { Padding = UDim.new(0, 14), Parent = card })

	new("TextLabel", {
		Text = opts.Title or "Dialog",
		Font = Theme.FontBold,
		TextSize = 16,
		TextColor3 = Theme.TextPrimary,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 20),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 701,
		Parent = card,
	})
	if opts.Content then
		new("TextLabel", {
			Text = opts.Content,
			Font = Theme.Font,
			TextSize = 13,
			TextColor3 = Theme.TextSecondary,
			TextWrapped = true,
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 40),
			AutomaticSize = Enum.AutomaticSize.Y,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 701,
			Parent = card,
		})
	end

	local function close()
		tween(dim, { BackgroundTransparency = 1 }, 0.18)
		tween(card, { Size = UDim2.fromOffset(360, 0) }, 0.18)
		task.delay(0.18 * Theme.AnimSpeed, function() dim:Destroy() end)
	end

	if opts.Buttons and #opts.Buttons > 0 then
		local btnRow = new("Frame", {
			Size = UDim2.new(1, 0, 0, 34),
			BackgroundTransparency = 1,
			ZIndex = 701,
			Parent = card,
		})
		new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
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
			new("UIPadding", { PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16), Parent = bBtn })
			corner(bBtn, 6)
			bBtn.MouseButton1Click:Connect(function()
				if b.Callback then b.Callback() end
				close()
			end)
		end
	end

	if opts.ClickOutsideCloses then
		dim.MouseButton1Click:Connect(function()
			close()
		end)
	end

	-- open animation: fade dim in, card scales up from 0.9 -> 1
	card.Size = UDim2.fromOffset(360, 0)
	local scale = new("UIScale", { Scale = 0.9, Parent = card })
	tween(dim, { BackgroundTransparency = 0.5 }, 0.18)
	tween(scale, { Scale = 1 }, 0.18, Enum.EasingStyle.Back)

	return { Close = close }
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
	local target = (self._colToggle % 2 == 0) and self.ColumnLeft or self.ColumnRight
	self._colToggle = self._colToggle + 1
	return target
end

-- Tracks every top-level row/element in creation order so ScrollToElement
-- can find it later.
function Tab:_registerRow(row)
	table.insert(self.Elements, row)
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
	local row = self:_registerRow(makeRow(self:_target()))
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

	return { Set = function(v) set(v, false) end, Get = function() return state end }
end

function Tab:AddSlider(opts)
	opts = opts or {}
	local id = opts.Id or nextId("slider")
	local min, max = opts.Min or 0, opts.Max or 100
	local default = opts.Default or min
	local suffix = opts.Suffix or ""

	local row = self:_registerRow(makeRow(self:_target(), 54))
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

	return { Set = function(v) setValue(v, false) end, Get = function() return value end }
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

	local row = self:_registerRow(makeRow(self:_target(), 44))
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

	return { Get = self.Controls[id].Get, Set = self.Controls[id].Set }
end

function Tab:AddColorPicker(opts)
	opts = opts or {}
	local id = opts.Id or nextId("color")
	local color = opts.Default or Color3.new(1, 1, 1)

	local row = self:_registerRow(makeRow(self:_target()))
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

	-- Simple popup with R/G/B sliders (test/placeholder implementation)
	local popup = new("Frame", {
		Size = UDim2.fromOffset(200, 140),
		Position = UDim2.new(1, -214, 1, 4),
		BackgroundColor3 = Theme.Card,
		Visible = false,
		ZIndex = 30,
		Parent = row,
	})
	corner(popup, 8)
	stroke(popup, Theme.Border, 1)
	new("UIPadding", {
		PaddingTop = UDim.new(0, 10), PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10),
		Parent = popup,
	})
	local popupLayout = new("UIListLayout", { Padding = UDim.new(0, 8), Parent = popup })

	local function makeChannelSlider(labelText, initial, onChange)
		local wrap = new("Frame", { Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, ZIndex = 30, Parent = popup })
		new("TextLabel", {
			Text = labelText, Font = Theme.Font, TextSize = 11, TextColor3 = Theme.TextSecondary,
			BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 12), TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 30, Parent = wrap,
		})
		local track = new("Frame", { Size = UDim2.new(1, 0, 0, 6), Position = UDim2.fromOffset(0, 16), BackgroundColor3 = Theme.AccentMuted, Active = true, ZIndex = 30, Parent = wrap })
		corner(track, 3)
		local fill = new("Frame", { Size = UDim2.new(initial, 0, 1, 0), BackgroundColor3 = Color3.new(1,1,1), ZIndex = 30, Parent = track })
		corner(fill, 3)
		local dragging = false
		track.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				dragging = true
			end
		end)
		UserInputService.InputChanged:Connect(function(input)
			if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
				local alpha = math.clamp((input.Position.X - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
				fill.Size = UDim2.new(alpha, 0, 1, 0)
				onChange(alpha)
			end
		end)
		UserInputService.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				dragging = false
			end
		end)
		return fill
	end

	local r, g, b = color.R, color.G, color.B
	local function updateColor()
		local c = Color3.new(r, g, b)
		color = c
		swatch.BackgroundColor3 = c
		if opts.Callback then opts.Callback(c) end
		self.Window:_autoSave()
	end
	makeChannelSlider("R", r, function(a) r = a; updateColor() end)
	makeChannelSlider("G", g, function(a) g = a; updateColor() end)
	makeChannelSlider("B", b, function(a) b = a; updateColor() end)

	swatch.MouseButton1Click:Connect(function()
		popup.Visible = not popup.Visible
	end)

	self.Controls[id] = {
		Get = function() return { r = color.R, g = color.G, b = color.B } end,
		Set = function(v)
			if typeof(v) == "table" then
				r, g, b = v.r, v.g, v.b
				color = Color3.new(r, g, b)
				swatch.BackgroundColor3 = color
			elseif typeof(v) == "Color3" then
				color = v
				r, g, b = v.R, v.G, v.B
				swatch.BackgroundColor3 = color
			end
		end,
	}

	return {
		Get = function() return color end,
		Set = function(v) self.Controls[id].Set(v) end,
	}
end

function Tab:AddButton(opts)
	opts = opts or {}
	local row = self:_registerRow(makeRow(self:_target(), 40))
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
function Tab:AddTextBox(opts)
	opts = opts or {}
	local id = opts.Id or nextId("textbox")
	local row = self:_registerRow(makeRow(self:_target(), 54))
	new("TextLabel", {
		Text = opts.Title or opts.Text or "Text Input",
		Font = Theme.Font,
		TextSize = 13,
		TextColor3 = Theme.TextPrimary,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(14, 8),
		Size = UDim2.new(1, -28, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = row,
	})

	local inputWrap = new("Frame", {
		Size = UDim2.new(1, -28, 0, 26),
		Position = UDim2.fromOffset(14, 22),
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
		Set = function(v) box.Text = tostring(v) end,
	}
	return { Get = self.Controls[id].Get, Set = self.Controls[id].Set }
end
Tab.TextBox = Tab.AddTextBox

-- Tab:Paragraph({ Title, Desc, Image (emoji/text icon or rbxassetid), ImageSize, Buttons = {{Title, Callback}, ...} })
function Tab:AddParagraph(opts)
	opts = opts or {}
	local hasButtons = opts.Buttons and #opts.Buttons > 0
	local hasImage = opts.Image ~= nil
	local baseHeight = 20 + (opts.Desc and 18 or 0) + (hasButtons and 34 or 0) + 24

	local row = self:_registerRow(makeRow(self:_target(), baseHeight))
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

	local row = self:_registerRow(makeRow(self:_target(), 62))
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

	return {
		Set = function(nv) value = math.clamp(nv, min, max); refresh() end,
		Get = function() return value end,
	}
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

return UILib

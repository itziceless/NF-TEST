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
}

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

local function corner(parent, radius)
	return new("UICorner", { CornerRadius = UDim.new(0, radius or 8), Parent = parent })
end

local function stroke(parent, color, thickness)
	return new("UIStroke", {
		Color = color or Theme.Border,
		Thickness = thickness or 1,
		Parent = parent,
	})
end

local function tween(obj, props, time, style)
	local t = TweenService:Create(obj, TweenInfo.new(time or 0.18, style or Enum.EasingStyle.Quad), props)
	t:Play()
	return t
end

local function isMobile()
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
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
		dragHandle.InputBegan = dragHandle.InputBegan
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
	do
		local resizeHandle = new("Frame", {
			Size = UDim2.fromOffset(18, 18),
			Position = UDim2.new(1, -18, 1, -18),
			BackgroundTransparency = 1,
			Parent = root,
		})
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

	local self = setmetatable({}, Window)
	self.ScreenGui = screenGui
	self.Root = root
	self.Sidebar = sidebar
	self.TabListFrame = tabListFrame
	self.PageHolder = pageHolder
	self.ContentHeader = contentHeader
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
function Window:AddTab(name, icon)
	local btn = new("TextButton", {
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Theme.Panel,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 36),
		Parent = self.TabListFrame,
	})
	corner(btn, 8)
	new("TextLabel", {
		Text = (icon and (icon .. "  ") or "• ") .. name,
		Font = Theme.Font,
		TextSize = 13,
		TextColor3 = Theme.TextSecondary,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -16, 1, 0),
		Position = UDim2.fromOffset(12, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = btn,
	})

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
	local grid = new("UIListLayout", {
		Padding = UDim.new(0, 12),
		Parent = page,
	})

	local tabObj = setmetatable({}, Tab)
	tabObj.Name = name
	tabObj.Button = btn
	tabObj.Page = page
	tabObj.Window = self
	tabObj.Controls = {}

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
		local label = t.Button:FindFirstChildOfClass("TextLabel")
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
-- CONTROLS
--=========================================================
local function makeRow(parent, height)
	local row = new("Frame", {
		Size = UDim2.new(1, 0, 0, height or 44),
		BackgroundColor3 = Theme.Panel,
		Parent = parent,
	})
	corner(row, 8)
	stroke(row, Theme.Border, 1)
	return row
end

-- id counter so configs can key controls uniquely even with duplicate labels
local _idCounter = 0
local function nextId(prefix)
	_idCounter += 1
	return (prefix or "ctrl") .. "_" .. _idCounter
end

function Tab:AddSectionLabel(text)
	new("TextLabel", {
		Text = text,
		Font = Theme.FontBold,
		TextSize = 12,
		TextColor3 = Theme.TextSecondary,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 20),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = self.Page,
	})
end

function Tab:AddToggle(opts)
	opts = opts or {}
	local id = opts.Id or nextId("toggle")
	local row = makeRow(self.Page)
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

	local row = makeRow(self.Page, 54)
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
	local valueLabel = new("TextLabel", {
		Text = tostring(default) .. suffix,
		Font = Theme.FontBold,
		TextSize = 13,
		TextColor3 = Theme.TextPrimary,
		BackgroundTransparency = 1,
		Position = UDim2.new(1, -80, 0, 8),
		Size = UDim2.fromOffset(66, 18),
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = row,
	})

	local barBack = new("Frame", {
		Size = UDim2.new(1, -28, 0, 6),
		Position = UDim2.fromOffset(14, 34),
		BackgroundColor3 = Theme.AccentMuted,
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

	local row = makeRow(self.Page, 44)
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
		Size = UDim2.fromOffset(146, math.min(#options * 28, 140)),
		Position = UDim2.new(1, -160, 1, 4),
		BackgroundColor3 = Theme.Card,
		Visible = false,
		ZIndex = 20,
		Parent = row,
	})
	corner(optionList, 6)
	stroke(optionList, Theme.Border, 1)
	local optScroll = new("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ScrollBarThickness = 3,
		CanvasSize = UDim2.new(0, 0, 0, #options * 28),
		ZIndex = 20,
		Parent = optionList,
	})
	local optLayout = new("UIListLayout", { Parent = optScroll })

	local function refreshLabel()
		valueBtn.Text = summaryText()
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
			ZIndex = 21,
			Parent = optScroll,
		})
		optBtn.MouseButton1Click:Connect(function()
			if multi then
				selected[optName] = not selected[optName]
			else
				selected = { [optName] = true }
				optionList.Visible = false
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
		optionList.Visible = not optionList.Visible
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

	local row = makeRow(self.Page)
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
		local track = new("Frame", { Size = UDim2.new(1, 0, 0, 6), Position = UDim2.fromOffset(0, 16), BackgroundColor3 = Theme.AccentMuted, ZIndex = 30, Parent = wrap })
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
	local row = makeRow(self.Page, 40)
	local btn = new("TextButton", {
		Text = opts.Text or "Button",
		Font = Theme.FontBold,
		TextSize = 13,
		TextColor3 = Theme.TextPrimary,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = row,
	})
	btn.MouseButton1Click:Connect(function()
		if opts.Callback then opts.Callback() end
	end)
	return btn
end

function Tab:AddLabel(text)
	local row = new("Frame", { Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1, Parent = self.Page })
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

return UILib

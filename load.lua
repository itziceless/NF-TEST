


--[[
	ShowcaseAll.lua
	Everything UILibrary.lua can do, old and new, in one file.
	Run as-is. All content is placeholder/test data — nothing to wire up.
]]

local UILib = loadstring(game:HttpGet("https://raw.githubusercontent.com/itziceless/NF-TEST/refs/heads/main/ui.lua",  true))() -- adjust path if needed

local Window = UILib:CreateWindow({
	Title = "Nightfall",
	SubTitle = "Private - v0.1",
})

--=========================================================
-- SECTION: Main  (old: Paragraph, Notify, Dialog, ProgressBar, Credits)
--=========================================================
local Main = Window:AddSection("Main")

local Overview = Main:AddTab({
	Title = "Overview",
	Icon = "🏠",
	Description = "Everything in one place",
	Tag = { Title = "Start Here", Color = Color3.fromRGB(100, 200, 120) },
})
Overview:AddParagraph({
	Title = "Welcome",
	Desc = "The Paragraph component — icon, description, and action buttons.",
	Image = "★",
	Buttons = {
		{ Title = "Say Hi", Callback = function() print("Hi!") end },
		{
			Title = "Open Dialog",
			Callback = function()
				Window:Dialog({
					Title = "Confirm Action",
					Content = "The modal Dialog system — background dims, window is non-interactable until you choose.",
					Buttons = {
						{ Title = "No", Callback = function() print("Cancelled") end },
						{ Title = "Yes", Primary = true, Callback = function() print("Confirmed") end },
					},
				})
			end,
		},
	},
})
Overview:AddButton({
	Text = "Fire a Notification",
	Callback = function()
		Window:Notify({ Title = "Saved", Desc = "Config saved successfully.", Icon = "✓", Duration = 4 })
	end,
})
Overview:AddProgressBar({
	Title = "Storage",
	Desc = "Compact progress bar (test data)",
	Value = { Min = 0, Max = 100, Default = 42 },
	DisplayMode = "Percent",
})
Overview:AddProgressBar({
	Title = "Full-width progress bar",
	Fully = true,
	Value = { Min = 0, Max = 100, Default = 70 },
	DisplayMode = "Value",
})

local Credits = Main:AddTab({ Title = "Credits", Icon = "✎", Description = "Who built this" })
Credits:AddLabel("Nightfall UI Library — built on UILibrary.lua")
Credits:AddDivider({ Text = "Layout" })
Credits:AddLabel("This tab uses the default two-column layout.")

--=========================================================
-- SECTION: Layout  (new: Columns, Divider)
--=========================================================
local Layout = Window:AddSection("Layout")

local SingleCol = Layout:AddTab({ Title = "Single Column", Icon = "▤", Description = "Columns = 1" })
SingleCol:AddLabel("Created with Columns = 1 — everything stacks in one column instead of two.")
SingleCol:AddDivider({ Text = "Divider with text" })
SingleCol:AddButton({ Title = "Option 1", Callback = function() print("1") end })
SingleCol:AddButton({ Title = "Option 2", Callback = function() print("2") end })
SingleCol:AddDivider() -- plain line, no text
SingleCol:AddButton({ Title = "Option 3", Callback = function() print("3") end })
SingleCol:AddButton({ Title = "Option 4", Callback = function() print("4") end })

--=========================================================
-- SECTION: Commands  (old: Toggle, Slider, Dropdown, Multi, ColorPicker, TextBox)
--=========================================================
local Commands = Window:AddSection("Commands")

local PlayerTab = Commands:AddTab({ Title = "Player", Icon = "🧍", Tag = { Title = "Beta", Color = Color3.fromRGB(90, 140, 230) } })
PlayerTab:AddSectionLabel("Basics")
PlayerTab:AddToggle({ Text = "Test Toggle", Default = true, Callback = function(v) print("Toggle ->", v) end })
PlayerTab:AddSlider({ Text = "Test Slider (click # to edit)", Min = 0, Max = 200, Default = 60, Callback = function(v) print("Slider ->", v) end })
PlayerTab:AddDropdown({
	Text = "Single Select",
	Options = { "Option A", "Option B", "Option C" },
	Default = "Option A",
	Callback = function(v) print("Dropdown ->", v) end,
})
PlayerTab:AddDropdown({
	Text = "Multi Select",
	Multi = true,
	Options = { "Alpha", "Beta", "Gamma", "Delta" },
	Default = { "Alpha" },
	Callback = function(v) print("Multi ->", table.concat(v, ", ")) end,
})
PlayerTab:AddColorPicker({
	Text = "Test Color",
	Default = Color3.fromRGB(120, 170, 255),
	Callback = function(c) print("Color ->", c) end,
})
PlayerTab:AddColorPicker({
	Text = "Color w/ Alpha",
	Default = Color3.fromRGB(255, 140, 140),
	Alpha = true,
	Callback = function(c, a) print("Color ->", c, "Alpha ->", a) end,
})
PlayerTab:AddTextBox({
	Title = "Player Name",
	Desc = "Text mode, character limit 16",
	Icon = "👤",
	Placeholder = "Enter a name...",
	Mode = "Text",
	CharacterLimit = 16,
	Clearable = true,
	Callback = function(v) print("Name ->", v) end,
})
PlayerTab:AddButton({ Text = "Scroll to first element", Callback = function() PlayerTab:ScrollToElement(1) end })

local GameTab = Commands:AddTab({ Title = "Game", Icon = "🎮", Description = "Server-level test controls" })
for i = 1, 6 do
	GameTab:AddToggle({ Text = "Test Setting " .. i, Default = (i % 2 == 0), Callback = function(v) print("Setting " .. i, "->", v) end })
end
GameTab:AddTextBox({
	Title = "WalkSpeed",
	Desc = "Integer mode — non-digits filtered live",
	Placeholder = "16",
	Mode = "Integer",
	Callback = function(v) print("WalkSpeed ->", v) end,
})

--=========================================================
-- SECTION: New Components  (new: Keybind, Code)
--=========================================================
local Components = Window:AddSection("New Components")

local KeybindTab = Components:AddTab({ Title = "Keybind", Icon = "⌨", Tag = { Title = "New", Color = Color3.fromRGB(100, 200, 120) } })
KeybindTab:AddLabel("Desktop: click the key box, press any key to bind, Escape clears.")
KeybindTab:AddLabel("Mobile: click the key box to toggle a floating draggable button instead.")
KeybindTab:AddKeybind({
	Title = "Toggle UI",
	Value = "V",
	Callback = function(key) print("Keybind fired:", key) end,
})
KeybindTab:AddKeybind({
	Title = "Quick Action",
	Value = "None",
	Callback = function(key) print("Quick Action fired:", key) end,
})

local CodeTab = Components:AddTab({ Title = "Code Block", Icon = "⌗" })
CodeTab:AddCode({
	Title = "Example Code",
	Code = [[local function greet(name)
    -- says hello to someone
    print("Hello, " .. name .. "!")
end

greet("World")]],
})
CodeTab:AddCode({
	Title = "Full width example",
	Fully = true,
	Code = "for i = 1, 10 do\n    print(i)\nend",
})

local CustomValTab = Components:AddTab({ Title = "Validators", Icon = "✔" })
CustomValTab:AddTextBox({
	Title = "Custom Validator",
	Desc = "Only accepts text starting with 'ok_'",
	Placeholder = "ok_...",
	Validator = function(text) return text == "" or text:match("^ok_") ~= nil end,
	Callback = function(v) print("Validated ->", v) end,
})

--=========================================================
-- SECTION: Interaction  (new: Hidden/conditional visibility)
--=========================================================
local Interaction = Window:AddSection("Interaction")

local HiddenTab = Interaction:AddTab({ Title = "Conditional Visibility", Icon = "◔" })
local masterToggle = HiddenTab:AddToggle({ Text = "Show extra options", Default = false })
HiddenTab:AddSlider({
	Text = "Only visible when toggle is ON",
	Min = 0, Max = 100, Default = 50,
	Hidden = function() return not masterToggle.Value end,
})
HiddenTab:AddTextBox({
	Title = "Also hidden until toggled",
	Placeholder = "type here...",
	Hidden = function() return not masterToggle.Value end,
})
HiddenTab:AddLabel("Flip the toggle above — controls fade/collapse in and out (checked ~every 0.15s).")

local NotifyTab = Interaction:AddTab({ Title = "Notifications", Icon = "◫" })
NotifyTab:AddButton({
	Title = "Fire 3 Stacked Notifications",
	Callback = function()
		Window:Notify({ Title = "Step 1", Desc = "Connecting...", Icon = "①", Duration = 5 })
		task.wait(0.3)
		Window:Notify({ Title = "Step 2", Desc = "Loading data...", Icon = "②", Duration = 5 })
		task.wait(0.3)
		Window:Notify({ Title = "Step 3", Desc = "Done.", Icon = "③", Duration = 5 })
	end,
})

--=========================================================
-- SECTION: Misc  (old: Filter-style list · new: Window controls, Settings w/ gradients)
--=========================================================
local Misc = Window:AddSection("Misc")

local ListTab = Misc:AddTab({ Title = "Filter Demo", Icon = "☰", Description = "Selectable test rows" })
for i = 1, 8 do
	ListTab:AddToggle({
		Text = "Test Item " .. i,
		Default = (i == 1),
		Callback = function(v) print("Test Item " .. i, "->", v) end,
	})
end

local WinCtrlTab = Misc:AddTab({ Title = "Window Controls", Icon = "▭" })
WinCtrlTab:AddLabel("Top-right of the window: — minimize, ▢ maximize, × close.")
WinCtrlTab:AddLabel("Close destroys this whole demo — reopen by rerunning the script.")

-- Ready-made settings panel: theme, accent color, corner roundness, anim
-- speed, UI scale, transparency, padding, compact mode, font, icon size,
-- and the new Gradient Background presets — all wired to the live Theme.
Window:AddSettingsTab(Misc)

print("ShowcaseAll loaded — every old + new feature is in the sidebar sections.")

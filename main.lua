local UILib = loadstring(game:HttpGet("https://raw.githubusercontent.com/itziceless/NF-TEST/refs/heads/main/ui.lua",  true))()

local Window = UILib:CreateWindow({
	Title = "Nightfall",
	SubTitle = "showcase build",
})

--=========================================================
-- SECTION: Main (collapsible sidebar group)
--=========================================================
local Main = Window:AddSection("Main")

local Overview = Main:AddTab({
	Title = "Overview",
	Icon = "🏠",
	Description = "Everything in one place",
	Tag = { Title = "New", Color = Color3.fromRGB(100, 200, 120) },
})
Overview:AddParagraph({
	Title = "Welcome",
	Desc = "This tab shows the Paragraph component with an icon and action buttons.",
	Image = "★",
	Buttons = {
		{ Title = "Say Hi", Callback = function() print("Hi!") end },
		{
			Title = "Open Dialog",
			Callback = function()
				Window:Dialog({
					Title = "Confirm Action",
					Content = "This is the modal Dialog system — background dims and the window is non-interactable until you choose.",
					Buttons = {
						{ Title = "Yes", Primary = true, Callback = function() print("Confirmed") end },
						{ Title = "No", Callback = function() print("Cancelled") end },
					},
				})
			end,
		},
	},
})
Overview:AddButton({
	Text = "Fire a Notification",
	Callback = function()
		Window:Notify({
			Title = "Saved",
			Desc = "Config saved successfully.",
			Icon = "✓",
			Duration = 4,
		})
	end,
})
Overview:AddProgressBar({
	Title = "Storage",
	Desc = "Used space (test data)",
	Value = { Min = 0, Max = 100, Default = 42 },
	DisplayMode = "Percent",
})

local Credits = Main:AddTab({ Title = "Credits", Icon = "✎", Description = "Who built this" })
Credits:AddLabel("Nightfall UI Library — built on UILibrary.lua")
Credits:AddLabel("All content on this tab is placeholder text.")

--=========================================================
-- SECTION: Commands
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
PlayerTab:AddColorPicker({ Text = "Test Color", Default = Color3.fromRGB(255, 255, 255), Callback = function(c) print("Color ->", c) end })
PlayerTab:AddTextBox({ Title = "Test Text Input", Placeholder = "type something...", Clearable = true, Callback = function(v) print("Text ->", v) end })
PlayerTab:AddButton({ Text = "Scroll to first element", Callback = function() PlayerTab:ScrollToElement(1) end })

local GameTab = Commands:AddTab({ Title = "Game", Icon = "🎮", Description = "Server-level test controls" })
for i = 1, 6 do
	GameTab:AddToggle({ Text = "Test Setting " .. i, Default = (i % 2 == 0), Callback = function(v) print("Setting " .. i, "->", v) end })
end

--=========================================================
-- SECTION: Misc
--=========================================================
local Misc = Window:AddSection("Misc")

-- Ready-made settings panel: theme, accent color, corner roundness, anim
-- speed, UI scale, transparency, padding, compact mode, font, icon size —
-- all wired to the live Theme already.
Window:AddSettingsTab(Misc)

print("Showcase loaded — check the Main/Commands/Misc sections in the sidebar.")

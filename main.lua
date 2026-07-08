--[[
	TestBuild.lua

	Self-contained test harness. Run this as-is to see the entire library
	working end to end — it builds a full demo UI by itself (every control
	type, multiple tabs, config manager) with placeholder/test values only.

	This is meant to be thrown away or heavily trimmed later — when you're
	ready to build your real panel, start a NEW script that requires
	UILibrary.lua directly (see the two-line pattern at the bottom of this
	file) rather than editing this one.

	Autosave: every toggle flip, slider drag, dropdown pick, or color change
	below gets written to the "Autosave" config automatically (debounced
	~0.25s so slider drags don't spam saves). Check Window.CurrentConfigName
	/ Window.Store.Configs to confirm it's persisting as you interact.
]]

local UILib = require(script.Parent.UILibrary) -- adjust path if UILibrary.lua lives elsewhere

local Window = UILib:CreateWindow({
	Title = "TestBuild",
	SubTitle = "self-generated demo",
})

-- ── helper: dumps every control's current value, so you can watch
-- autosave actually mutate the stored JSON as you interact ──────────────
local function dumpAutosave()
	local cfg = Window.Store:Load(Window.CurrentConfigName)
	print("---- Autosave (" .. Window.CurrentConfigName .. ") ----")
	if cfg then
		for k, v in pairs(cfg) do
			print("  " .. tostring(k) .. " = " .. tostring(v))
		end
	else
		print("  (nothing saved yet — change a control)")
	end
	print("--------------------------------------")
end

--=========================================================
-- Tab 1: General — one of each basic control
--=========================================================
local General = Window:AddTab("General")
General:AddSectionLabel("Toggles")
General:AddToggle({ Text = "Test Toggle A", Default = true,  Callback = function(v) print("Toggle A ->", v) end })
General:AddToggle({ Text = "Test Toggle B", Default = false, Callback = function(v) print("Toggle B ->", v) end })

General:AddSectionLabel("Sliders")
General:AddSlider({ Text = "Test Slider (0-100)", Min = 0, Max = 100, Default = 42, Callback = function(v) print("Slider ->", v) end })
General:AddSlider({ Text = "Test Range (0-1000m)", Min = 0, Max = 1000, Default = 250, Suffix = "m", Callback = function(v) print("Range ->", v) end })

General:AddSectionLabel("Dropdown")
General:AddDropdown({
	Text = "Test Single-Select",
	Options = { "Option A", "Option B", "Option C" },
	Default = "Option A",
	Callback = function(v) print("Single-select ->", v) end,
})
General:AddDropdown({
	Text = "Test Multi-Select",
	Options = { "Alpha", "Beta", "Gamma", "Delta" },
	Multi = true,
	Default = { "Alpha" },
	Callback = function(v) print("Multi-select ->", table.concat(v, ", ")) end,
})

General:AddSectionLabel("Color")
General:AddColorPicker({ Text = "Test Color", Default = Color3.fromRGB(255, 255, 255), Callback = function(c) print("Color ->", c) end })

General:AddButton({ Text = "Print Autosave Contents", Callback = dumpAutosave })

--=========================================================
-- Tab 2: Filter-style list (mirrors the searchable-table layout,
-- generic placeholder rows instead of anything game-specific)
--=========================================================
local ListTab = Window:AddTab("Filter Demo")
ListTab:AddSectionLabel("Selectable Rows (test data)")
for i = 1, 8 do
	ListTab:AddToggle({
		Text = "Test Item " .. i,
		Default = (i == 1),
		Callback = function(v) print("Test Item " .. i, "->", v) end,
	})
end

--=========================================================
-- Tab 3: Settings — config manager (Configs / Trash pattern)
--=========================================================
local Settings = Window:AddTab("Settings")
Settings:AddSectionLabel("Configs")

Settings:AddButton({
	Text = "+ Create 'Demo Config'",
	Callback = function()
		Window:SaveConfig("Demo Config")
		print("Created + switched active config to 'Demo Config'")
	end,
})
Settings:AddButton({
	Text = "Switch back to Autosave config",
	Callback = function()
		Window:LoadConfig("Autosave")
		print("Switched active config to 'Autosave'")
	end,
})
Settings:AddButton({
	Text = "List All Configs",
	Callback = function()
		for _, entry in ipairs(Window:ListConfigs()) do
			print(entry.name, "| created", entry.created, "| updated", entry.updated)
		end
	end,
})
Settings:AddButton({
	Text = "Delete 'Demo Config' (-> Trash)",
	Callback = function()
		Window:DeleteConfig("Demo Config")
		print("Moved 'Demo Config' to Trash")
	end,
})
Settings:AddButton({
	Text = "Restore 'Demo Config' from Trash",
	Callback = function()
		Window:RestoreConfig("Demo Config")
		print("Restored 'Demo Config'")
	end,
})

print("TestBuild loaded — flip a toggle or drag a slider, then hit 'Print Autosave Contents' to confirm it saved.")

--=========================================================
-- WHEN YOU BUILD THE REAL VERSION LATER:
-- In a brand new script, just do:
--
--   local UILib = require(path.to.UILibrary)
--   local Window = UILib:CreateWindow({ Title = "...", SubTitle = "..." })
--   local Tab = Window:AddTab("...")
--   Tab:AddToggle({ ... })
--   -- etc.
--
-- Everything (autosave, resizing, mobile support, config store) comes
-- for free from UILibrary.lua — this file was only scaffolding to prove
-- it all works.
--=========================================================

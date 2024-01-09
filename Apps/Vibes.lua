------------------------------------------------------------------------------------
--	Vibes																																					--
--	Copyright (C) 2023 Jesper Frickmann																						--
--																																								--
--	This program is free software: you can redistribute it and/or modify					--
--	it under the terms of the GNU General Public License as published by					--
--	the Free Software Foundation, either version 3 of the License, or							--
--	(at your option) any later version.																						--
--																																								--
--	This program is distributed in the hope that it will be useful,								--
--	but WITHOUT ANY WARRANTY; without even the implied warranty of								--
--	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.	See the									--
--	GNU General Public License for more details.																	--
--																																								--
--	You should have received a copy of the GNU General Public License							--
--	along with this program.	If not, see <http://www.gnu.org/licenses/>.					--
------------------------------------------------------------------------------------

-- Constants
local appName =		"Vibes"
local author =		"Jesper Frickmann"
local version =		"1.0.0"
local profiles = { "Long", "Short", "2short", "3short" }
local MAX = 15

-- Shared variables
local lang						-- Language translations
local items						-- List of items
local now							-- Current time count

-- Return a new alert item
local function newItem(idx, switch, values)
	local item = { }		-- List of public members
	local profile				-- Index into list
	local delay					-- Delay before first
	local rept					-- Interval between repetitions
	local prevSw				-- Previous switch value
	local nextVibe = 0	-- Time for next vibration

	if values then
		profile, delay, rept = table.unpack(values)
	else
		profile, delay, rept = 1, 0, 0
	end
	
	local function save()
		system.pSave(string.format("Switch %02i", idx), switch)
		system.pSave(string.format("Values %02i", idx), { profile, delay, rept })
	end
	
	local function switchChanged(value)
		switch = value
		if switch then
			prevSw = system.getInputsVal(switch)
		end
		save()
	end
	
	local function profileChanged(value)
		profile = value
		save()
	end
	
	local function delayChanged(value)
		delay = value
		save()
	end
	
	local function reptChanged(value)
		rept = value
		save()
	end
	
	function item.initForm()
		form.addRow(4)
		form.addInputbox(switch, false, switchChanged, { width = 73 })
		form.addSelectbox(profiles, profile, false, profileChanged, { width = 85 })
		form.addIntbox (delay, 0, 250, 0, 1, 1, delayChanged, { width = 65 })
		form.addIntbox (rept, 0, 250, 0, 1, 1, reptChanged, { width = 65 })
	end
	
	function item.setIdx(i)
		idx = i
		save()
	end
	
	function item.loop()
		if switch == nil then return end
		local sw = system.getInputsVal(switch)
		if sw == nil then return end
		
		if sw > 0 then			
			if prevSw <= 0 then
				nextVibe = now + 100 * delay
			end
			
			if nextVibe > 0 and now >= nextVibe then
				system.vibration(true, profile)
				
				if rept == 0 then
					nextVibe = 0
				else
					nextVibe = nextVibe + 100 * rept
				end
			end
		end
		
		prevSw = sw
	end
	
	save()
	return item
end -- newItem()

local function loop()
	now = system.getTimeCounter()
	for i, item in ipairs(items) do
		item.loop()
	end
end -- loop()

local function keyPress(key)
	if key == KEY_3 then
		if #items < MAX then
			table.insert(items, newItem(#items + 1))
			form.reinit(#items)
		end
	elseif key == KEY_4 then
		if #items > 0 then
			local sel = form.getFocusedRow() - 1
			local n = #items
			for i = sel, n - 1 do
				items[i] = items[i + 1]
				items[i].setIdx(i)
			end
			items[n] = nil
			system.pSave(string.format("Switch %02i", n), nil)
			system.pSave(string.format("Values %02i", n), nil)
			form.reinit(sel)
		end
	end
end

local function printForm()
	lcd.drawText( 90, 0, lang.profile, FONT_BOLD)
	lcd.drawText(170, 0, lang.delay, FONT_BOLD)
	lcd.drawText(235, 0, lang.repeat_, FONT_BOLD)
end

local function initForm(sf)
	if #items < MAX then
		form.setButton(3, ":add", ENABLED)
	else
		form.setButton(3, ":add", DISABLED)
	end
	
	if #items > 0 then
		form.setButton(4, ":delete", ENABLED)
	else
		form.setButton(4, ":delete", DISABLED)
	end
	
	form.addLabel({ label = lang.switch, font = FONT_BOLD, width = 60 })
	
	for i, item in ipairs(items) do
		item.initForm()
	end
	
	form.setFocusedRow(sf + 1)
end -- initForm()

local function init()
	local path = "Apps/" .. appName .. "/"
	local chunk = loadfile(path .. system.getLocale() .. ".lua") or loadfile(path .. "en.lua")
	lang = chunk()

	items = { }
	for idx = 1, MAX do
		local values = system.pLoad(string.format("Values %02i", idx))
		if values then
			local switch = system.pLoad(string.format("Switch %02i", idx))
			table.insert(items, newItem(idx, switch, values))
		else
			break
		end
	end
	
	system.registerForm(1, MENU_ADVANCED, appName, initForm, keyPress, printForm)
end -- init()

return {init = init, loop = loop, author = author, version = version, name = appName}

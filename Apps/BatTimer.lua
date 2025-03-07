------------------------------------------------------------------------------------
--	SoarJETI Battery Timer																												--
--	Copyright (C) 2024 Jesper Frickmann																						--
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
local appName =		"Battery Timer"
local author =		"Jesper Frickmann"
local version =		"1.0.0"

-- Presistent variables
local timerSwitch				-- Switch for starting and stopping the timer
local resetSwitch				-- Switch for resetting the timer
local vMin							-- Battery warning level

-- Other variables
local timer							-- Motor run time
local keyPress					-- Functions vary by active form
local printForm 				-- Functions vary by active form
local cellValues = { }	-- Battery cell voltage
local minValues = { }		-- Minimum battery cell voltage
local tWarnV = 0				-- Timer for battery warning

local lang = system.getLocale()

if lang == "de" then
	lang = {
		timerSwitch = "Timerschalter",
		resetSwitch = "Zurücksetzen",
		startTime = "Anfangszeit (sek.)",
		saveChanges = "Änderungen speichern?",
		vMin = "Batterie Warnstufe"
	}
elseif lang == "fr" then
	lang = {
		timerSwitch = "Interrupteur de minuterie",
		resetSwitch = "Réinitialiser la minuterie",
		startTime = "Temps initial (sec.)",
		saveChanges = "Enregistrer les modifications?",
		vMin = "Niveau d'alarme de la batterie"
	}
else
		lang = {
		timerSwitch = "Timer switch",
		resetSwitch = "Reset timer",
		startTime = "Start time (sec.)",
		saveChanges = "Save changes?",
		vMin = "Battery warning level"		
	}
end
-------------------------------- Utility functions ---------------------------------

local function void()
end

-- Set back to default drawing color (undocumented)
local function setColor()
	local r, g, b = lcd.getBgColor()
	if r + g + b < 384 then
		lcd.setColor(255, 255, 255)
	else
		lcd.setColor(0, 0, 0)
	end
end

-- LiPo battery pct. from V
local function lipoPct(v)
	if v <= 3.3 then
		return 0.0
	elseif v >= 4.2 then
		return 1.0
	else
		local z = (1.749983661 * (v - 3.3)) ^ 4.897057756
		return 1.108124863 * z / (1.0 + z)
	end
end

-- Find default sensor id for MULi6S
local function getMULi6S()
	for i, sensor in ipairs(system.getSensors()) do
		if (sensor.id & 0xFFFF) >= 43185 and (sensor.id & 0xFFFF) <= 43188 then
			muli6sId = sensor.id
			break
		end
	end
end

-- Read flight pack charge pct.
local function fltBatV()
	local values = { }
	local low
	
	if muli6sId then
		-- Find values for cells 1-6 and convert to pct.
		for i = 1, 6 do
			local sensor = system.getSensorByID(muli6sId, i)
			if sensor and sensor.valid then
				table.insert(values, sensor.value)
			end
		end
		low = system.getSensorByID(muli6sId, 7).value
	else
		getMULi6S()
	end

	return values, low
end

-- Draw battery cell with charge level
local function drawBat(x, y, v, mv)
	local H = 60
	local W = (lcd.width - 32) * 2 / 17
	local h = math.floor(lipoPct(v) * (H - 6))

	lcd.setColor(lcd.getFgColor())
	lcd.drawFilledRectangle (x + 3, y + H - h, W - 6, h, 96)
	lcd.drawFilledRectangle (x + 9, y, W - 18, 3)
	lcd.drawRectangle (x, y + 3, W, H, 4)
	lcd.drawRectangle (x + 1, y + 4, W - 2, H - 2, 3)
	lcd.setColor (200, 0, 0)
	lcd.drawText(x + W / 2 - 10, y + H - 16, string.format("%1.1f", mv))
	setColor()
	lcd.drawText(x + W / 2 - 10, y + 3, string.format("%1.1f", v))
end

-- Draw signal bars
local function drawBars(x, y, dh, value)
	local dx = 14
	local dy = 0

	if dh < 0 then
		dh = -dh
	else
		dy = dh
	end

	for i = 1, math.min(5, math.floor(value)) do
		lcd.drawFilledRectangle(x + i * dx, y - i * dy, dx - 2, i * dh, 96)
	end
	for i = 1, 5 do
		lcd.drawRectangle(x + i * dx, y - i * dy, dx - 2, i * dh)
	end
end

-- Safely read switch as boolean
local function getSwitch(sw)
	if not sw then return false end
	local val = system.getInputsVal(sw)
	if not val then return false end
	return (val > 0)
end

-- Draw text right adjusted
local function drawTxtRgt(x, y, txt, flags)
	x = x - lcd.getTextWidth(flags, txt)
	lcd.drawText(x, y, txt, flags)
end

-- Return true if the first arg matches any of the following args
local function match(x, ...)
	for i, y in ipairs({...}) do
		if x == y then
			return true
		end
	end
	return false
end

--------------------------------- Timer functions ----------------------------------

-- Create a new timer
local function newTimer(control, interval)
	local timer = {
		start = 0,
		value = 0,
		prev = 0,
		interval = interval
	}
	
	local d, t0, nextIntCall

	function timer.set(s)
		timer.start = s
		timer.value = s
		timer.prev = s
	end

	function timer.update()
		if t0 then
			local ms = system.getTimeCounter() - t0
			timer.prev = timer.value
			timer.value = math.floor(0.001 * d * ms + 0.5)
			
			if timer.interval and system.getInputsVal(timer.interval) > 0 and ms >= nextIntCall then
				playDuration(timer.value)
				nextIntCall = 10000 * math.floor(0.0001 * ms + 1.5)
			end
		end
	end
	
	function timer.run()
		if t0 then return end
		
		if timer.start > 0 then
			d = -1
		else
			d = 1
		end
		
		t0 = system.getTimeCounter() - d * 1000 * timer.value
		nextIntCall = -2E9
		
		if control then
			system.setControl (control, 1, 0)
		end
	end
	
	function timer.stop()
		if t0 then
			timer.update()
			t0 = nil
		end
		
		if control then
			system.setControl (control, -1, 0)
		end
	end
	
	return timer
end

-- Convert seconds to "mm:ss"
local function s2str(s)
	if not s then
		return "-- -- --"
	end
	
	local sign = ""
	if s < 0 then
		s = -s
		sign = "-"
	end

	return sign .. string.format("%02i:%02i", math.floor(s / 60), s % 60)
end

------------------------------------ Business --------------------------------------

-- Main loop running all the time
local function loop()
	local low
	cellValues, low = fltBatV()
	
	-- Warning?
	low = low and (low > 0 and 10 * low <= vMin)
	if low then
		if tWarnV == 0 then
			tWarnV = system.getTimeCounter() + 10000
		end
		system.setControl (1, 1, 0)
	else
		tWarnV = 0
		system.setControl (1, -1, 0)
	end

	if tWarnV > 0 and system.getTimeCounter() >= tWarnV then
		system.playFile("Low_U.wav")
		tWarnV = 0
	end
	
	-- Min. cell values
	if #cellValues == 0 then
		-- Reset if telemetry lost
		minValues = { }
	else
		if #minValues == 0 then
			for i, v in ipairs(cellValues) do
				minValues[i] = v
			end
		else
			for i, v in ipairs(cellValues) do
				minValues[i] = math.min(v, minValues[i])
			end
		end
	end

	-- Update timer
	if getSwitch(timerSwitch) then
		timer.run()
	else
		timer.stop()
	end
	
	if getSwitch(resetSwitch) then
		timer.set(timer.start)
	end

	timer.update()
end -- loop()

--------------------------- Print fullscreen telemetry ------------------------------

local function printTeleFull()
	local rgt = lcd.width - 16
	local xt = rgt - lcd.getTextWidth(FONT_MAXI, "00:00")
	local h

	-- Draw flight battery status
	local dx = (lcd.width - 32) * 3 / 17
	local x = 16
	for i, v in ipairs(cellValues) do
		drawBat(x, 6, v, minValues[i])
		x = x + dx
	end
	
	-- Draw signal strength
	lcd.setColor(lcd.getFgColor())
	local txTele = system.getTxTelemetry()
	drawBars(2, 117, 6, 0.5 + 0.5 * txTele.RSSI[1])
	drawBars(2, 118, -6, 0.5 + 0.5 * txTele.RSSI[2])
	drawBars(96, 147, 12, 0.999 + 0.05 * txTele.rx1Percent)

	-- Text
	setColor()
	lcd.drawText(16, 80, "A1", FONT_BOLD)
	lcd.drawText(16, 132, "A2", FONT_BOLD)
	lcd.drawText(110, 80, "Q%", FONT_BOLD)
	drawTxtRgt(rgt, 96, s2str(timer.value), FONT_MAXI)
end -- printTeleFull()

--------------------------------- Settings form -------------------------------------

local function initSettings()
	local sensorTbl = system.getSensors()
	local sensors = { }
	local labels = { }
	local ts = timerSwitch
	local rs = resetSwitch
	local st = timer.start
	local vm = vMin

	form.setTitle(appName)

	for i, sensor in ipairs(sensorTbl) do
		if not match(sensor.type, 5, 9) and sensor.param ~= 0 then
			table.insert(sensors, sensor)
			table.insert(labels, sensor.label)
			if altiSensor and altiSensor[1] == sensor.id and altiSensor[2] == sensor.param then
				altiIdx = #sensors
			end
		end
	end
	
	keyPress = function(key)
		if match(key, KEY_5, KEY_ESC) then
			local saveChanges = 1
			if key == KEY_ESC then
				saveChanges = form.question(lang.saveChanges)
			end

			if saveChanges == 1 then
				system.pSave("TimerSw", ts)
				timerSwitch = ts
				system.pSave("ResetSw", rs)
				resetSwitch = rs
				system.pSave("Start", st)
				timer.set(st)
				system.pSave("vMin", vm)
				vMin = vm
			end
		end
	end

	printForm = void

	form.addRow(2)
	form.addLabel({ label = lang.timerSwitch, width = 225 })
	form.addInputbox(ts, false, function(v) ts = v end)

	form.addRow(2)
	form.addLabel({ label = lang.resetSwitch, width = 225 })
	form.addInputbox(rs, false, function(v) rs = v end)

	form.addRow(2)
	form.addLabel({ label = lang.startTime, width = 225 })
	form.addIntbox(st, 0, 2400, 0, 0, 10, function(v) st = v end)

	form.addRow(2)
	form.addLabel({ label = lang.vMin, width = 225 })
	form.addIntbox(vm, 30, 42, 33, 1, 1, function(v) vm = v end)

	form.addLink(function() form.reinit(2) end, { label = "About " .. appName })
end

------------------------------------ About form -------------------------------------

local function initAbout()
	form.setTitle("About " .. appName)

	keyPress = function(key)
		if match(key, KEY_5, KEY_ESC) then
			form.preventDefault()
			form.reinit(1)
		end
	end
	
	printForm = function()
		lcd.drawText(30, 10, "Copyright 2023 Jesper Frickmann")
		lcd.drawText(30, 40, "This app is released under the")
		lcd.drawText(30, 60, "GNU General Public License V3")
		lcd.drawText(30, 80, "Please see www.gnu.org/licenses")
		lcd.drawText(30, 110, "Version " .. version)
	end
end

---------------------------------- Initialization ------------------------------------

-- Change to another sub form
local function initForm(f)
	if f == 1 then
		initSettings()
	else
		initAbout()
	end
end

-- Initialization
local function init()
	timer = newTimer()
	initSettings()
	system.registerForm(1, MENU_MAIN, appName, initForm, function(key) keyPress(key) end, function() printForm() end)
	system.registerTelemetry(1, system.getProperty("Model"), 4, printTeleFull)
	timerSwitch = system.pLoad("TimerSw")
	resetSwitch = system.pLoad("ResetSw")
	timer.set(system.pLoad("Start") or 0)
	vMin = system.pLoad("vMin") or 35
	system.registerControl (1, "Battery warning", "BtL")
	system.setControl (1, -1, 0)
end -- init()

return {init = init, loop = loop, author = author, version = version, name = appName}

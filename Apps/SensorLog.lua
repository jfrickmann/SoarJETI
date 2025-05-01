------------------------------------------------------------------------------------
--	SoarJETI Sensor Log																														--
--	Copyright (C) 2025 Jesper Frickmann																						--
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
local appName =		"SensorLog"
local author =		"Jesper Frickmann"
local version =		"1.0.0"
local LINES
local COLS = 3
local LOG_FILE = "Log/SensorLog%06i.txt"

-- Presistent variables
local sensor	-- Sensor to log
local switch	-- Triggers logging
local logFile	-- Log file name

-- Variables
local lang								-- Language translations
local keyPress, printForm	-- Functions vary by active form
local lcdw, lcdh					-- Work around lcd.width issue
local prevSw							-- Previous cycle value (for edge cond.)
local values							-- Saved sensor values

if string.find(system.getDeviceType(), "24 II") then
	LINES = 12
	lcdw = 320
	lcdh = 204
else
	LINES = 8
	lcdw = lcd.width - 10
	lcdh = 136
end
local N = LINES * COLS

-------------------------------- Utility functions ---------------------------------

-- Safely read switch as boolean
local function getSwitch(sw)
	 if not sw then return false end
	 local val = system.getInputsVal(sw)
	 if not val then return false end
	 return (val > 0)
end

-- Safely read sensor
local function getSensor()
	if not sensor then return 0.0, "" end
	local id = sensor[1]
	local param = sensor[2]
	if not (id and param) then return 0.0, "" end
	local sens = system.getSensorByID(id, param)
	if not sens then return 0.0, "" end
	local fmtstr
	if sens.decimals == 0 then
		fmtstr = "%i " .. sens.unit
	else
		fmtstr = "%1." .. string.format("%if %s", sens.decimals, sens.unit)
	end
	return string.format(fmtstr, sens.value)
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

-- Draw text right adjusted
local function drawTxtRgt(x, y, txt, flags)
	x = x - lcd.getTextWidth(flags, txt)
	lcd.drawText(x, y, txt, flags)
end

-- Read persistent variables
local function readPersistent()
	sensor = system.pLoad("Sensor")
	switch = system.pLoad("Switch")
end

-- Save sensor values to the file
local function saveValues()
	local file = io.open(logFile, "w+")
	for i, value in ipairs(values) do
		io.write(file, value, "\n")
	end
	io.close(file)
end

------------------------------------ Business --------------------------------------

-- Main loop running all the time
local function loop()
	local sw = getSwitch(switch)

	if sensor and not prevSw and sw then
		-- Save value
		local i = #values
		if i == N then
			for j = 2, N do
				values[j - 1] = values[j]
			end
		else
			i = i + 1
		end
		values[i] = getSensor()
		saveValues()
	end

	prevSw = sw
end -- loop()

----------------------------------- Main form ---------------------------------------

local function printValues()
	local cw = lcdw / COLS
	local lh = lcdh / LINES
	
	for i = 1, COLS - 1 do
		local x = i * cw + 1
		lcd.drawLine(x, 0, x, lcdh)
	end
	
	for i = 1, #values do
		drawTxtRgt(cw * (1 + math.floor((i - 1) / LINES)) - 5, lh * ((i - 1) % LINES), values[i], FONT_BIG)
	end
end -- printValues()

local function initMain()
	keyPress = function(key)
		if key == KEY_1 then
			form.reinit(2)
		elseif key == KEY_2 then
			values = { }
			saveValues()
		end
	end
	
	form.setButton(1, ":tools", ENABLED)
	form.setButton(2, ":delete", ENABLED)
	printForm = printValues
	form.setTitle(appName)
end

--------------------------------- Settings form -------------------------------------

local function initSettings()
	local sensIdx = 1
	local sensors = { }
	local labels = { }
	form.setTitle(lang.settings)

	for i, sens in ipairs(system.getSensors()) do
		if not match(sens.type, 5, 9) and sens.param ~= 0 then
			table.insert(sensors, sens)
			table.insert(labels, sens.label)
			if sensor and sensor[1] == sens.id and sensor[2] == sens.param then
				sensIdx = #sensors
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
				system.pSave("Switch", switch)
				system.pSave("Sensor", sensor)
			else
				readPersistent()
			end

			if switch and sensor then
				form.reinit(1)
				form.preventDefault()
			end
		end
	end

	printForm = function()
		lcd.drawText(30, 60, "Copyright 2023 Jesper Frickmann")
		lcd.drawText(30, 76, "This app is released under the")
		lcd.drawText(30, 92, "GNU General Public License V3")
		lcd.drawText(30, 108, "Please see www.gnu.org/licenses")
		lcd.drawText(30, 124, "Version " .. version)
	end

	local function sensorChanged(idx)
		if sensors[idx] then
			sensor = { sensors[idx].id, sensors[idx].param }
		else
			sensor = nil
		end
		values = { }
		saveValues()
	end
	
	form.addRow(2)
	form.addLabel({ label = lang.sensor, width = 225 })
	form.addSelectbox(labels, sensIdx, false, sensorChanged)

	form.addRow(2)
	form.addLabel({ label = lang.switch, width = 225 })
	form.addInputbox(switch, false, function(v) switch = v end)
end

------------------------------ Other form / telemetry -------------------------------

-- Change to another sub form
local function initForm(f)
	if f == 1 then
		if switch and sensor then
			initMain()
		else
			form.reinit(2)
		end
	else
		initSettings()
	end
end

---------------------------------- Initialization ------------------------------------

-- Initialization
local function init()
	math.randomseed(system.getTime())
	local path = "Apps/" .. appName .. "/"
	local chunk = loadfile(path .. system.getLocale() .. ".lua") or loadfile(path .. "en.lua")
	lang = chunk()
	
	system.registerForm(1, MENU_APPS, appName, initForm, function(key) keyPress(key) end, function() printForm() end)
	system.registerTelemetry(1, appName, 4, printValues)

	readPersistent()
	prevSw = getSwitch(switch)
	values = { }
	
	-- Make sure that we have a log file
	logFile = system.pLoad("LogFile")
	while logFile == nil do
		local fn = string.format(LOG_FILE, math.random(999999))
		local file = io.open(fn)
		if file == nil then
			logFile = fn
			system.pSave("LogFile", logFile)
		else
			io.close(file)
		end
	end
	
	-- Read log file
	local buffer = io.readall(logFile)
	if buffer == nil then return end

	for value in string.gmatch(buffer, "[^\r\n]+") do
		local i = #values + 1
		values[i] = value
		if i == N then break end
	end
end -- init()

return {init = init, loop = loop, author = author, version = version, name = appName}

------------------------------------------------------------------------------------
--	SoarJETI F5J score keeper																											--
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
local appName =		"F5J score keeper"
local author =		"Jesper Frickmann"
local version =		"1.0.0"
local SCORE_LOG =	"Log/F5J scores.csv"

-- Presistent variables
local motorSwitch						-- Logical switch for motor (starts timers)
local timerSwitch						-- Switch for stopping the timer (and optionally the motor)
local altiSensor						-- Altimeter sensor (optional)
local altiSwitch						-- Report launch height
local altiSwitch10					-- Report altitude every 10 s
local scoreLogSize					-- Max. no. of score records in file

-- Program states, shared with loadable part
local STATE_INITIAL = 1			-- Set flight time before the flight
local STATE_MOTOR= 2				-- Motor running
local STATE_GLIDE = 3				-- Gliding
local STATE_RESTART = 4			-- Motor restart
local STATE_SAVE = 5				-- Prompt to save
local state = STATE_INITIAL	-- Current program state

-- Variables
local lang									-- Language translations
local flightTimer						-- Flight timer
local motorTimer						-- Motor run timer
local flightTime						-- Flight time to save. Needed b/c of weird code flow around form.question
local prevTimerSw						-- Previous cycle value (for edge cond.)
local offTime								-- Time motor off
local prevCnt								-- Previous motor off count
local startHeight						-- Recorded start height
local nextAltiCall = 0			-- Time stamp for 10 s altitude report
local activeSubForm					-- Currently active sub form
local scoreLog							-- List of previous scores
local muli6sId							-- Sensor id for MULi6S battery sensor

--------------------------------- Language locale ----------------------------------

local languages = {
	en = {
		motor = "Motor:",
		flight = "Flight:",
		motorSwitch = "Motor run switch",
		timerSwitch = "Timer switch",
		altiSensor = "Altimeter sensor",
		altiSwitch = "Report launch height",
		altiSwitch10 = "Report alt. every 10s",
		logSize = "Score log size",
		saveScores = "Save scores?",
		noScores = "No scores yet!",
		pressedESC = "You pressed ESC",
		changesNotSaved = "Changes were NOT saved!",
		flightTime = "Flight time",
		landingPoints = "Landing points",
		startHeight = "Start height",
		heightPenalty = "Height penalty"
	}
}

-------------------------------- Utility functions ---------------------------------

local function void()
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

-- Read flight pack charge pct.
local function fltBatPct()
	local values = { }
	
	if muli6sId then
		-- Find values for cells 1-6 and convert to pct.
		for i = 1, 6 do
			local sensor = system.getSensorByID(muli6sId, i)
			if sensor and sensor.valid then
				table.insert(values, lipoPct(sensor.value))
			end
		end
		-- Did we somehow loose the sensor?
		if #values == 0 then
			muli6sId = nil
		end
	else
		-- Find default sensor id for MULi6S
    for i, sensor in ipairs(system.getSensors()) do
      if (sensor.id & 0xFFFF) >= 43185 and (sensor.id & 0xFFFF) <= 43188 then
        muli6sId = sensor.id
        break
      end
    end
	end

	return values
end

-- Draw battery cell with charge level
local function drawBat(x, y, pct)
	local h = math.floor(pct * 42)
	lcd.drawFilledRectangle (x + 3, y + 48 - h, 22, h, 142)
	lcd.drawFilledRectangle (x + 9, y, 10, 3)
	lcd.drawRectangle (x, y + 3, 28, 48, 4)
	lcd.drawRectangle (x + 1, y + 4, 26, 46, 3)
end

-- Safely read switch as boolean
local function getSwitch(sw)
       if not sw then return false end
       local val = system.getInputsVal(sw)
       if not val then return false end
       return (val > 0)
end

-- Safely read altitude
local function getAlti()
	if not altiSensor then return 0.0, "" end
	local id = altiSensor[1]
	local param = altiSensor[2]
	if not (id and param) then return 0.0, "" end
	local alti = system.getSensorByID(id, param)
	if not alti then return 0.0, "" end
	return alti.value, alti.unit
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

-- Read score file
local function readScores()
	scoreLog = { }
	local buffer = io.readall(SCORE_LOG)
	if buffer == nil then return end

	for line in string.gmatch(buffer, "[^\r\n]+") do
		local fields = { }
		for field in string.gmatch(line, "[^,]+") do
			fields[#fields + 1] = field
		end
		scoreLog[#scoreLog + 1] = fields
	end
end -- readScores()

-- Save scores
local function saveScores(addNew)
	if addNew then
		if startHeight == 0 then startHeight = 100 end
		
		-- Build new score record
		local t = system.getDateTime()

		local record = {
			system.getProperty("Model"),
			string.format("%04i-%02i-%02i %02i:%02i", t.year, t.mon, t.day, t.hour, t.min),
			flightTime,
			0,
			startHeight
		}
		
		-- Insert record in scoreLog with max. entries
		table.insert(scoreLog, record)
		while #scoreLog > scoreLogSize do
			for i in 1, #scoreLog do
				scoreLog[i] = scoreLog[i + 1]
			end
		end
	end

	local file = io.open(SCORE_LOG, "w+")
	
	for i, record in ipairs(scoreLog) do
		io.write(file, table.concat(record, ","), "\n")
	end
	
	io.close(file)
end -- saveScores()

-- Read persistent variables
local function readPersistent()
	motorSwitch = system.pLoad("MotorSw")
	timerSwitch = system.pLoad("TimerSw")
	altiSensor = system.pLoad("AltiSensor")
	altiSwitch = system.pLoad("AltiSw")
	altiSwitch10 = system.pLoad("AltiSw10")
	scoreLogSize = system.pLoad("LogSize") or 40
end	

--------------------------------- Timer functions ----------------------------------

-- Play timer calls as mm:ss
local function playDuration(s)
	local sign = 1

	if s < 0 then
		s = -s
		sign = -1
	end

	local m = math.floor(s / 60)
	s = s - 60 * m
	
	if m ~= 0 then
		m = sign * m
		system.playNumber(m, 0, "min")
	else
		s = sign * s
	end
	
	if m == 0 then
		if math.abs(s) <= 15 then
			system.playNumber(s, 0)
		else
			system.playNumber(s, 0, "s")
		end
	elseif s ~= 0 then
		system.playNumber(s, 0, "s")
	end
end

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
	local now = system.getTimeCounter()
	local cnt -- Count interval
	local motorOn = getSwitch(motorSwitch)
	local timerSw = getSwitch(timerSwitch)

	flightTimer.update()
	motorTimer.update()

	if state == STATE_INITIAL then
		flightTimer.set(flightTimer.start)
		motorTimer.set(0)

		if motorOn then
			state = STATE_MOTOR
			flightTimer.run()
			motorTimer.run()
			offTime = 0
			startHeight = 0.0
			form.reinit(1)
		end

	elseif state == STATE_MOTOR then
		local mt = motorTimer.value -- Current motor timer value
		local sayt -- Timer value to announce (we don't have time to say "twenty-something")
		
		if mt <= 20 then
			cnt = 5
			sayt = mt
		elseif mt < 30 then
			cnt = 1
			sayt = mt - 20
		else
			cnt = 1
			sayt = mt
		end
		
		if math.floor(motorTimer.prev / cnt) < math.floor(mt / cnt) then
			system.playNumber(sayt, 0)
		end
		
		if not motorOn then -- Motor stopped; start 10 sec. count and record start height
			state = STATE_GLIDE
			motorTimer.stop()			
			offTime = now
			prevCnt = 1
		end

	elseif state == STATE_GLIDE then
		local ft = flightTimer.value
		
		-- Count down flight time
		if ft > 120 then
			cnt = 60
		elseif ft >60 then
			cnt = 15
		elseif ft >10 then
			cnt = 5
		else
			cnt = 1
		end
		
		if math.ceil(flightTimer.prev / cnt) > math.ceil(ft / cnt) then
			if ft > 10 then
				playDuration(ft, 0)
			elseif ft > 0 then
				system.playNumber(ft, 0)
			end
		end
		
		-- Altitude report every 10 s?
		if getSwitch(altiSwitch10) and nextAltiCall >= now then
			nextAltiCall = now + 10000
			local alti, unit = getAlti()
			system.playNumber(alti, 0, unit)
		end
		
		if motorOn then
			-- Motor restart; score a zero
			state = STATE_RESTART
			motorTimer.set(0)
			motorTimer.run()
			flightTimer.stop()
			flightTimer.set(flightTimer.start)
			flightTime = 0
			startHeight = 0.0
		
		elseif offTime > 0 then
			-- 10 sec. count after motor off
			cnt = math.floor(0.001 * (now - offTime))
			local hgt = getAlti()
			startHeight = math.max(startHeight, hgt)
			if cnt > prevCnt then
				prevCnt = cnt
				
				if cnt >= 10 then
					offTime = 0 -- No more counts
					if getSwitch(altiSwitch) then
						local alti, unit = getAlti()
						system.playNumber(startHeight, 0, unit)
					else
						system.playNumber(cnt, 0)
					end
				else
					system.playNumber(cnt, 0)				
				end
			end

		elseif not prevTimerSw and timerSw then
			state = STATE_SAVE
			flightTimer.stop()
			flightTime = flightTimer.start - flightTimer.value
			playDuration(flightTime)
		end
	
	elseif state == STATE_RESTART then
		if not motorOn then
			motorTimer.stop()			
			state = STATE_SAVE
		end
		
	elseif state == STATE_SAVE then
		local save = form.question(lang.saveScores)
		if save == 1 then
			saveScores(true)
			form.reinit(3)
		else
			form.reinit(1)
		end

		state = STATE_INITIAL
	end
	
	prevTimerSw = timerSw
end -- loop()

----------------------------------- Task form ---------------------------------------

local function initTask()
	local rgt = lcd.width - 20
	local xt = rgt - lcd.getTextWidth(FONT_MAXI, "00:00")
	local setTime = 0

	local function setKeys()
		if state == STATE_INITIAL then
			form.setButton(1, ":down", ENABLED)
			form.setButton(2, ":up", ENABLED)
			form.setButton(3, ":tools", ENABLED)
			form.setButton(4, ":file", ENABLED)
		else
			if setTime == 0 then
				form.setButton(1, ":down", DISABLED)
				form.setButton(2, ":up", DISABLED)
				form.setButton(3, ":timer", ENABLED)
			else
				if setTime <= 60 then
					form.setButton(1, ":down", DISABLED)
				else
					form.setButton(1, ":down", ENABLED)
				end
				form.setButton(2, ":up", ENABLED)
				form.setButton(3, ":timer", HIGHLIGHTED)
			end
		end
	end -- setKeys()

	keyPress = function(key)
		if state == STATE_INITIAL then
			if key == KEY_1 then
				if flightTimer.start > 60 then
					flightTimer.set(flightTimer.start - 60)
				end
			elseif key == KEY_2 then
				flightTimer.set(flightTimer.start + 60)
			elseif key == KEY_3 then
				form.reinit(2)
			elseif key == KEY_4 then
				form.reinit(3)
			end
			
		else
			if setTime == 0 then
				if key == KEY_3 then
					setTime = math.max(60, 60 * math.floor(flightTimer.value / 60))
				end
			else
				if key == KEY_1 then
					if setTime > 60 then
						setTime = setTime - 60
					end
				elseif key == KEY_2 then
					setTime = setTime + 60
				elseif match(key, KEY_3, KEY_ESC) then
					setTime = 0
				elseif match(key, KEY_5, KEY_ENTER) then
					flightTimer.stop()
					flightTimer.value = setTime
					flightTimer.run()
					setTime = 0
				end
				
				form.preventDefault()
			end
		end
		
		setKeys()
	end

	printForm = function()
		local tme
		local h
		
		if setTime > 0 then
			tme = setTime
		else
			tme = flightTimer.value
		end
		
		lcd.drawText(xt, 4, lang.motor, FONT_BIG)
		drawTxtRgt(rgt, 22, s2str(motorTimer.value), FONT_MAXI)
		lcd.drawText(xt, 80, lang.flight, FONT_BIG)
		drawTxtRgt(rgt, 98, s2str(tme), FONT_MAXI)
		
		-- Draw flight battery status
		local x = 16
		for i, pct in ipairs(fltBatPct()) do
			drawBat(x, 6, pct)
			x = x + 46
		end
		
		-- Draw signal strength
		local txTele = system.getTxTelemetry()
		-- A1/A2
		lcd.drawText(16, 76, "A", FONT_BOLD)
		for i = 1, 5 do
			h = 10 * i
			lcd.drawRectangle(2 + 14 * i, 130 - h, 12, h)
			for j = 1, 2 do
				if txTele.RSSI[j]  >= 2 * i - 2 then
					lcd.drawFilledRectangle(2 + 14 * i, 130 - h, 12, h, 85)
				end
			end
		end
		-- Q%
		lcd.drawText(110, 76, "Q%", FONT_BOLD)
		for i = 1, 5 do
			h = 10 * i
			lcd.drawRectangle(96 + 14 * i, 130 - h, 12, h)
			if txTele.rx1Percent  > 20 * i - 20 then
				lcd.drawFilledRectangle(96 + 14 * i, 130 - h, 12, h, 142)
			end
		end
	end -- printTask()

	setKeys()
	form.setTitle(appName)
end

--------------------------------- Settings form -------------------------------------

local function initSettings()
	local sensorTbl = system.getSensors()
	local altiIdx = 1
	local sensors = { }
	local labels = { }
	
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
			if key == KEY_5 then
				system.pSave("MotorSw", motorSwitch)
				system.pSave("TimerSw", timerSwitch)
				system.pSave("AltiSensor", altiSensor)
				system.pSave("AltiSw", altiSwitch)
				system.pSave("AltiSw10", altiSwitch10)
				system.pSave("LogSize", scoreLogSize)
			else
				readPersistent()
				form.question (lang.changesNotSaved, lang.pressedESC, "", 2500, true)
			end
			if motorSwitch and timerSwitch then
				form.reinit(1)
				form.preventDefault()
			end
		end
	end

	printForm = void

	local function altiChanged(idx)
		if #sensors >= idx then
			altiSensor = { sensors[idx].id, sensors[idx].param }
		else
			altiSensor = nil
		end
	end
	
	form.addRow(2)
	form.addLabel({ label = lang.motorSwitch })
	form.addInputbox(motorSwitch, false, function(v) motorSwitch = v end)

	form.addRow(2)
	form.addLabel({ label = lang.timerSwitch })
	form.addInputbox(timerSwitch, false, function(v) timerSwitch = v end)

	form.addRow(2)
	form.addLabel({ label = lang.altiSensor })
	form.addSelectbox(labels, altiIdx, false, altiChanged)

	form.addRow(2)
	form.addLabel({ label = lang.altiSwitch })
	form.addInputbox(altiSwitch, false, function(v) altiSwitch = v end)

	form.addRow(2)
	form.addLabel({ label = lang.altiSwitch10 })
	form.addInputbox(altiSwitch10, false, function(v) altiSwitch10 = v end)

	form.addRow(2)
	form.addLabel({ label = lang.logSize, width = 220 })
	form.addIntbox(scoreLogSize, 5, 200, 40, 0, 5, function(v) scoreLogSize = v end)
	
	form.addLink(function() form.reinit(4) end, { label = "About " .. appName })
end

----------------------------------- Scores form -------------------------------------

local function initScores()
	local browseRecord = #scoreLog
	local record
	local min, sec, landingPts, startHgt
	local editing
	local x = {
		10,
		310 - lcd.getTextWidth(FONT_BIG, "00:00"),
		310 - lcd.getTextWidth(FONT_BIG, "00"),
		310 - lcd.getTextWidth(FONT_BIG, "000"),
		310
	}
	local rb, gb, bb = lcd.getBgColor()
	local rf, gf, bf = lcd.getFgColor()
	
	form.setTitle(lang.noScores)

	-- Update form when record changes
	local function updateRecord()
		record = scoreLog[browseRecord]
		form.setTitle(record[2])
		local tme = math.tointeger(record[3])
		min = math.floor(tme / 60)
		sec = tme % 60
		landingPts = math.tointeger(record[4])
		startHgt = math.tointeger(record[5])
	end

	-- Update buttons when editing level changes
	local function setEditing(ed)
		if ed == 0 then
			form.setButton(1, ":down", ENABLED)
			form.setButton(2, ":up", ENABLED)
			form.setButton(3, ":edit", ENABLED)
			updateRecord()
		else
			form.setButton(1, ":left", ENABLED)
			form.setButton(2, ":right", ENABLED)
			form.setButton(3, "", ENABLED)
		end
		editing = ed
	end
	
	if browseRecord > 0 then
		setEditing(0)
		updateRecord()
	end
	
	keyPress = function(key)
		if match(key, KEY_5, KEY_ESC) then
			form.preventDefault()
		end
			
		if browseRecord == 0 then
			if match(key, KEY_5, KEY_ESC) then
				form.reinit(1)
			end
			return
		end

		if editing == 0 then
			if match(key, KEY_1, KEY_UP) then
				browseRecord = browseRecord % #scoreLog + 1
				updateRecord()
			elseif match(key, KEY_2, KEY_DOWN) then
				browseRecord = (browseRecord - 2) % #scoreLog + 1
				updateRecord()
			elseif key == KEY_3 then
				selected = 1
				setEditing(1)
			elseif match(key, KEY_5, KEY_ESC) then
				form.reinit(1)
			end
		else
			if match(key, KEY_5, KEY_ENTER) then
				record[3] = 60 * min + sec
				record[4] = landingPts
				record[5] = startHgt
				saveScores(false)
				setEditing(0)
			elseif key == KEY_ESC then
				form.question (lang.changesNotSaved, lang.pressedESC, "", 2500, true)
				updateRecord()
				setEditing(0)
			elseif key == KEY_1 then
				editing = (editing - 2) % 4 + 1
			elseif key == KEY_2 then
				editing = editing % 4 + 1
			elseif editing == 1 then
				if key == KEY_UP then
					min = (min + 1) % 100
				elseif key == KEY_DOWN then
					min = (min - 1) % 100
				end
			elseif editing == 2 then
				if key == KEY_UP then
					sec = (sec + 1) % 60
				elseif key == KEY_DOWN then
					sec = (sec - 1) % 60
				end
			elseif editing == 3 then
				if key == KEY_UP then
					landingPts = (landingPts + 5) % 55
				elseif key == KEY_DOWN then
					landingPts = (landingPts - 5) % 55
				end
			elseif editing == 4 then
				if key == KEY_UP then
					startHgt = (startHgt + 1) % 1000
				elseif key == KEY_DOWN then
					startHgt = (startHgt - 1) % 1000
				end
			end
		end		
	end -- keyPress()

	local function drawInverse(x, y, txt, font)
		local w = lcd.getTextWidth(font, txt)
		local h = lcd.getTextHeight(font)
		lcd.drawFilledRectangle(x, y, w, h)
		lcd.setColor(rb, gb, bb, 255)
		lcd.drawText(x, y, txt, font)
		lcd.setColor(rf, gf, bf, 255)
	end

	printForm = function()
		if browseRecord == 0 then return end
		
		lcd.drawText(x[1], 0, lang.flightTime, FONT_BIG)
		drawTxtRgt(x[5], 0, string.format("%02i:%02i", min, sec), FONT_BIG)
		
		lcd.drawText(x[1], 25, lang.landingPoints, FONT_BIG)
		drawTxtRgt(x[5], 25, landingPts, FONT_BIG)
		
		lcd.drawText(x[1], 50, lang.startHeight, FONT_BIG)
		drawTxtRgt(x[5], 50, startHgt, FONT_BIG)
		
		local penalty = 0.5 * math.min(200, startHgt) + 3 * math.max(0, startHgt - 200)
		lcd.drawText(x[1], 75, lang.heightPenalty, FONT_BIG)
		drawTxtRgt(x[5], 75, string.format("%1.1f", penalty), FONT_BIG)
		
		lcd.drawText(x[1], 110, record[1], FONT_BIG)

		if editing == 1 then
			drawInverse(x[2], 0, string.format("%02i", min), FONT_BIG)
		elseif editing == 2 then
			drawInverse(x[3], 0, string.format("%02i", sec), FONT_BIG)
		elseif editing == 3 then
			drawInverse(x[3], 25, string.format("%02i", landingPts), FONT_BIG)
		elseif editing == 4 then
			drawInverse(x[4], 50, string.format("%03i", startHgt), FONT_BIG)
		end
	end -- printForm()
end

------------------------------------ About form -------------------------------------

local function initAbout()
	form.setTitle("About " .. appName)

	keyPress = function(key)
		if match(key, KEY_5, KEY_ESC) then
			form.preventDefault()
			form.reinit(2)
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

------------------------------ Other form / telemetry -------------------------------

-- Change to another sub form
local function initForm(f)
	activeSubForm = f
	if f == 1 then
		if motorSwitch and timerSwitch then
			initTask()
		else
			form.reinit(4)
		end
	elseif f == 2 then
		initSettings()
	elseif f == 3 then
		initScores()
	else
		initAbout()
	end
end

-- Flight timer in telemetry window
local function printTele(w, h)
	local h2 = 0.5 * h
	lcd.drawText(8, 6, lang.motor, FONT_NORMAL)
	drawTxtRgt(w - 8, 0, s2str(motorTimer.value), FONT_MAXI)
	lcd.drawText(8, h2 + 6, lang.flight, FONT_NORMAL)
	drawTxtRgt(w - 8, h2, s2str(flightTimer.value), FONT_MAXI)
end

---------------------------------- Initialization ------------------------------------

-- Initialization
local function init()
	lang = languages[system.getLocale()] or languages.en
	system.registerForm(1, MENU_MAIN, appName, initForm, function(key) keyPress(key) end, function() printForm() end)
	system.registerTelemetry(1, appName, 0, printTele)
	system.registerControl (1, "Flight timer", "Flt")
	system.setControl (1, -1, 0)

	readPersistent()
	prevTimerSw = getSwitch(timerSwitch)	
	flightTimer = newTimer(1)
	flightTimer.set(600)
	motorTimer = newTimer()
	motorTimer.set(0)
	
	readScores()
end -- init()

return {init = init, loop = loop, author = author, version = version, name = appName}

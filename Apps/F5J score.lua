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
local appName =		"F5J score"
local author =		"Jesper Frickmann"
local version =		"1.0.5"
local SCORE_LOG =	"Log/F5J scores.csv"

-- Presistent variables
local motorSwitch						-- Logical switch for motor (starts timers)
local timerSwitch						-- Switch for stopping the timer (and optionally the motor)
local vMin									-- Battery warning level
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
local nxtBatWarning = 0			-- Time stamp for next battery warning
local setTime = 0						-- Set flight time
local lcdw									-- Work around lcd.width issue

if string.find(system.getDeviceType(), "24 II") then
	lcdw = 320
else
	lcdw = lcd.width - 10
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

-- Draw inverse text
local function drawInverse(x, y, txt, font, rgt)
	local w = lcd.getTextWidth(font, txt)
	local h = lcd.getTextHeight(font)
	
	if rgt then
		x = x - w
	end
	lcd.drawFilledRectangle(x, y, w, h)
	lcd.setColor(lcd.getBgColor())
	lcd.drawText(x, y, txt, font)
	setColor()
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
local function getFltBat()
	local values = { }
	
	if muli6sId then
		-- Find values for cells 1-6 and convert to pct.
		for i = 1, 6 do
			local sensor = system.getSensorByID(muli6sId, i)
			if sensor and sensor.valid then
				table.insert(values, sensor.value)
			end
		end
		-- Did we somehow loose the sensor?
		if #values == 0 then
			muli6sId = nil
		end
	else
		getMULi6S()
	end

	return values
end

-- Draw battery cell with charge level
local function drawBat(x, y, v, w)
	local H = 60
	local h = math.floor(lipoPct(v) * (H - 6))

	lcd.setColor(lcd.getFgColor())
	lcd.drawFilledRectangle (x + 3, y + H - h, w - 6, h, 96)
	lcd.drawFilledRectangle (x + 9, y, w - 18, 3)
	lcd.drawRectangle (x, y + 3, w, H, 4)
	lcd.drawRectangle (x + 1, y + 4, w - 2, H - 2, 3)
	setColor()
	lcd.drawText(x + w / 2 - 10, y + 3, string.format("%1.1f", v))
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

	lcd.setColor(lcd.getFgColor())
	for i = 1, math.min(5, math.floor(value)) do
		lcd.drawFilledRectangle(x + i * dx, y - i * dy, dx - 2, i * dh, 96)
	end
	setColor()
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
		if #fields < 6 then
			table.insert(fields, 0)
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
		local round = 0
		if #scoreLog > 0 then
			round = scoreLog[#scoreLog][6] + 1
		end

		local record = {
			system.getProperty("Model"),
			string.format("%04i-%02i-%02i %02i:%02i", t.year, t.mon, t.day, t.hour, t.min),
			flightTime,
			0,
			startHeight,
			round
		}
		
		-- Insert record in scoreLog with max. entries
		table.insert(scoreLog, record)
		while #scoreLog > scoreLogSize do
			local n = #scoreLog
			for i = 1, n do
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
	vMin = 0.1 * (system.pLoad("vMin") or 37)
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
		return "- -  - -"
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
		local hgt = getAlti()
		startHeight = math.max(startHeight, hgt)

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
			prevCnt = 0
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
			local hgt = getAlti()
			startHeight = math.max(startHeight, hgt)

			-- 10 sec. count after motor off
			cnt = math.floor(0.001 * (now - offTime))
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

		else
			-- Was trigger pressed to stop timer?
			if not prevTimerSw and timerSw then
				state = STATE_SAVE
				flightTimer.stop()
				flightTime = flightTimer.start - flightTimer.value
				playDuration(flightTime)
			end
			
			-- Battery warning?
			if now >= nxtBatWarning then
				if muli6sId then
					local sensor = system.getSensorByID(muli6sId, 7)
					if sensor and sensor.valid then
						if sensor.value <= vMin then
							system.playFile("Low_U.wav")
							system.vibration(true, 3)
						end
						nxtBatWarning = now + 30000
					else
						muli6sId = nil
					end
				else
					getMULi6S()
				end
			end

			-- Altitude report every 10 s?
			if getSwitch(altiSwitch10) and now >= nextAltiCall then
				nextAltiCall = now + 10000
				local alti, unit = getAlti()
				system.playNumber(alti, 0, unit)
			end

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

local function printTask()
	local rgt = lcdw - 10
	local xt = rgt - lcd.getTextWidth(FONT_MAXI, "00:00")
	local h

	lcd.drawText(xt, 10, lang.flight, FONT_BIG)
	if setTime > 0 then
		drawInverse(rgt, 32, s2str(setTime), FONT_MAXI, true)
	else
		drawTxtRgt(rgt, 32, s2str(flightTimer.value), FONT_MAXI)
	end

	lcd.drawText(xt, 82, lang.motor, FONT_BIG)
	drawTxtRgt(rgt, 104, s2str(motorTimer.value), FONT_MAXI)

	-- Draw flight battery status
	local x = 16
	local fltBat = getFltBat()
	local a = 164 / (11 * #fltBat - 3)
	local dx = math.floor(11 * a + 0.5)
	local w = math.min(40, math.floor(8 * a + 0.5))
	for i, v in ipairs(fltBat) do
		drawBat(x, 6, v, w)
		x = x + dx
	end
	
	lcd.drawText(16, 84, "A1", FONT_BOLD)
	lcd.drawText(16, 122, "A2", FONT_BOLD)
	lcd.drawText(110, 84, "Q%", FONT_BOLD)
	
	lcd.setColor(lcd.getFgColor())

	-- Draw signal strength
	local txTele = system.getTxTelemetry()
	drawBars(2, 112, 5, 0.5 + 0.5 * txTele.RSSI[1])
	drawBars(2, 113, -5, 0.5 + 0.5 * txTele.RSSI[2])
	drawBars(96, 137, 10, 0.999 + 0.05 * txTele.rx1Percent)
end -- printTask()

local function initTask()
	setTime = 0

	local function setKeys()
		if state == STATE_INITIAL then
			form.setButton(1, ":tools", ENABLED)
			form.setButton(2, ":file", ENABLED)
		else
			form.setButton(1, ":tools", DISABLED)
			form.setButton(2, ":file", DISABLED)
		end

		if setTime == 0 then
			form.setButton(3, ":timer", ENABLED)
		else
			form.setButton(3, ":timer", HIGHLIGHTED)
		end
	end -- setKeys()

	keyPress = function(key)
		if state == STATE_INITIAL then
			if setTime == 0 then
				if key == KEY_1 then
					form.reinit(2)
				elseif key == KEY_2 then
					form.reinit(3)
				elseif key == KEY_3 then
					setTime = flightTimer.start
				end
			else
				if match(key, KEY_3, KEY_5, KEY_ENTER, KEY_ESC) then
					setTime = 0
				elseif key == KEY_DOWN then
					if setTime > 60 then
						setTime = setTime - 60
						flightTimer.set(setTime)
					end
				elseif key == KEY_UP then
					setTime = setTime + 60
					flightTimer.set(setTime)
				end
				form.preventDefault()
			end
		else
			if setTime == 0 then
				if key == KEY_3 then
					setTime = math.max(60, 60 * math.floor(flightTimer.value / 60))
				end
			else
				if key == KEY_DOWN then
					if setTime > 60 then
						setTime = setTime - 60
					end
				elseif key == KEY_UP then
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

	printForm = printTask
	setKeys()
	form.setTitle(appName)
end

--------------------------------- Settings form -------------------------------------

local function initSettings()
	local sensorTbl = system.getSensors()
	local altiIdx = 1
	local sensors = { }
	local labels = { }
	form.setTitle(lang.settings)

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
				system.pSave("MotorSw", motorSwitch)
				system.pSave("TimerSw", timerSwitch)
				system.pSave("vMin", 10 * vMin)
				system.pSave("AltiSensor", altiSensor)
				system.pSave("AltiSw", altiSwitch)
				system.pSave("AltiSw10", altiSwitch10)
				system.pSave("LogSize", scoreLogSize)
			else
				readPersistent()
			end

			if motorSwitch and timerSwitch then
				form.reinit(1)
				form.preventDefault()
			end
		end
	end

	printForm = void

	local function altiChanged(idx)
		if sensors[idx] then
			altiSensor = { sensors[idx].id, sensors[idx].param }
		else
			altiSensor = nil
		end
	end
	
	form.addRow(2)
	form.addLabel({ label = lang.motorSwitch, width = 225 })
	form.addInputbox(motorSwitch, false, function(v) motorSwitch = v end)

	form.addRow(2)
	form.addLabel({ label = lang.timerSwitch, width = 225 })
	form.addInputbox(timerSwitch, false, function(v) timerSwitch = v end)

	form.addRow(2)
	form.addLabel({ label = lang.vMin, width = 225 })
	form.addIntbox(10 * vMin, 30, 50, 37, 1, 1, function(v) vMin = 0.1 * v end)

	form.addRow(2)
	form.addLabel({ label = lang.altiSensor, width = 225 })
	form.addSelectbox(labels, altiIdx, false, altiChanged)

	form.addRow(2)
	form.addLabel({ label = lang.altiSwitch, width = 225 })
	form.addInputbox(altiSwitch, false, function(v) altiSwitch = v end)

	form.addRow(2)
	form.addLabel({ label = lang.altiSwitch10, width = 225 })
	form.addInputbox(altiSwitch10, false, function(v) altiSwitch10 = v end)

	form.addRow(2)
	form.addLabel({ label = lang.logSize, width = 225 })
	form.addIntbox(scoreLogSize, 5, 200, 40, 0, 5, function(v) scoreLogSize = v end)
	
	form.addLink(function() form.reinit(4) end, { label = "About " .. appName })
end

----------------------------------- Scores form -------------------------------------

local function initScores()
	local browseRecord = #scoreLog
	local record
	local min, sec, landingPts, startHgt, round
	local editing
	local changed
	local x = {
		10,
		310 - lcd.getTextWidth(FONT_BIG, "00:00"),
		310 - lcd.getTextWidth(FONT_BIG, "00"),
		310 - lcd.getTextWidth(FONT_BIG, "000"),
		310
	}
	form.setTitle(lang.noScores)

	-- Update form when record changes
	local function updateRecord()
		record = scoreLog[browseRecord]
		form.setTitle(record[2] .. " " .. record[1])
		local tme = math.tointeger(record[3])
		min = math.floor(tme / 60)
		sec = tme % 60
		landingPts = math.tointeger(record[4])
		startHgt = math.tointeger(record[5])
		round = record[6]
		changed = false
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
			if match(key, KEY_5, KEY_ENTER, KEY_ESC) then
				local saveChanges = 1
				if changed and key == KEY_ESC then
					saveChanges = form.question(lang.saveChanges)
				end

				if saveChanges == 1 then
					record[3] = 60 * min + sec
					record[4] = landingPts
					record[5] = startHgt
					record[6] = round
					saveScores(false)
				else
					updateRecord()
				end
				setEditing(0)
			elseif key == KEY_1 then
				editing = (editing - 2) % 5 + 1
			elseif key == KEY_2 then
				editing = editing % 5 + 1
			elseif key == KEY_UP then
				changed = true
				if editing == 1 then
					round = math.floor(round + 1.1)
				elseif editing == 2 then
					min = (min + 1) % 100
				elseif editing == 3 then
					sec = (sec + 1) % 60
				elseif editing == 4 then
					landingPts = (landingPts + 5) % 55
				elseif editing == 5 then
					startHgt = (startHgt + 1) % 1000
				end
			elseif key == KEY_DOWN then
				changed = true
				if editing == 1 then
					if round > 0 then
						round = math.floor(round - 0.9)
					end
				elseif editing == 2 then
					min = (min - 1) % 100
				elseif editing == 3 then
					sec = (sec - 1) % 60
				elseif editing == 4 then
					landingPts = (landingPts - 5) % 55
				elseif editing == 5 then
					startHgt = (startHgt - 1) % 1000
				end
			end
		end		
	end -- keyPress()

	printForm = function()
		if browseRecord == 0 then return end
		
		lcd.drawText(x[1], 0, lang.round, FONT_BIG)
		drawTxtRgt(x[5], 0, tostring(round), FONT_BIG)
		
		lcd.drawText(x[1], 24, lang.flightTime, FONT_BIG)
		drawTxtRgt(x[5], 24, string.format("%02i:%02i", min, sec), FONT_BIG)
		
		lcd.drawText(x[1], 48, lang.landingPoints, FONT_BIG)
		drawTxtRgt(x[5], 48, landingPts, FONT_BIG)
		
		lcd.drawText(x[1], 72, lang.startHeight, FONT_BIG)
		drawTxtRgt(x[5], 72, startHgt, FONT_BIG)
		
		local penalty = 0.5 * math.min(200, startHgt) + 3 * math.max(0, startHgt - 200)
		lcd.drawText(x[1], 96, lang.heightPenalty, FONT_BIG)
		drawTxtRgt(x[5], 96, string.format("%1.1f", penalty), FONT_BIG)
		
		local total = 60 * min + sec + landingPts - penalty
		lcd.drawText(x[1], 120, lang.total, FONT_BIG)
		drawTxtRgt(x[5], 120, string.format("%1.1f", total), FONT_BIG)

		if editing == 1 then
			drawInverse(x[5], 0, tostring(round), FONT_BIG, true)
		elseif editing == 2 then
			drawInverse(x[2], 24, string.format("%02i", min), FONT_BIG)
		elseif editing == 3 then
			drawInverse(x[3], 24, string.format("%02i", sec), FONT_BIG)
		elseif editing == 4 then
			drawInverse(x[3], 48, string.format("%02i", landingPts), FONT_BIG)
		elseif editing == 5 then
			drawInverse(x[4], 72, string.format("%03i", startHgt), FONT_BIG)
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
	lcd.drawText(8, 6, lang.flight, FONT_NORMAL)
	drawTxtRgt(w - 8, 0, s2str(flightTimer.value), FONT_MAXI)
	lcd.drawText(8, h2 + 6, lang.motor, FONT_NORMAL)
	drawTxtRgt(w - 8, h2, s2str(motorTimer.value), FONT_MAXI)
end

---------------------------------- Initialization ------------------------------------

-- Initialization
local function init()
	local path = "Apps/" .. appName .. "/"
	local chunk = loadfile(path .. system.getLocale() .. ".lua") or loadfile(path .. "en.lua")
	lang = chunk()
	
	system.registerForm(1, MENU_MAIN, appName, initForm, function(key) keyPress(key) end, function() printForm() end)
	system.registerTelemetry(1, system.getProperty("Model"), 4, printTask)
	system.registerTelemetry(2, appName, 2, printTele)

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

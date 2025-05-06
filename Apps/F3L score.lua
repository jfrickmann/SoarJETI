------------------------------------------------------------------------------------
--	SoarJETI F3L/F3RES score keeper																								--
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
local appName =		"F3L score"
local author =		"Jesper Frickmann"
local version =		"1.0.0"
local SCORE_LOG =	"Log/F3L scores.csv"

-- Presistent variables
local timerSwitch						-- Switch for stopping the timer
local scoreLogSize					-- Max. no. of score records in file
local batteryType						-- Battery chemistry
local vMin									-- Battery warning level

-- Program states
local STATE_INITIAL = 0		 	-- Before starting the task
local STATE_PAUSE = 1		 		-- Task window paused, not flying
local STATE_WINDELAY = 2		-- Delay before starting the window with F3
local STATE_WINDOW = 3			-- Task window started, not flying
local STATE_FLYING = 4			-- Flying
local state = STATE_INITIAL	-- Current program state

-- Variables
local lang									-- Language translations
local prevTimerSw						-- Remember position of the timer switch
local flightTimer						-- Flight timer
local targetTime						-- Flight target time
local windowTimer						-- Window timer
local winTime								-- Task window time	 
local score									-- Last flight time
local landingPts						-- Landing points
local activeSubForm					-- Currently active sub form
local scoreLog							-- List of previous scores
local taskEntered						-- Task menu has been entered
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

local function batteryPct(v)
	if batteryType==1 then
		-- LiPo battery pct. from V	
		if v > 0 then -- More than 1S?
			v = v / math.ceil(v / 4.5)
		end

		if v <= 3.3 then
			return 0.0
		elseif v >= 4.2 then
			return 1.0
		else
			local z = (1.749983661 * (v - 3.3)) ^ 4.897057756
			return 1.108124863 * z / (1.0 + z)
		end
	else
		-- NiMH battery pct. from V
		v = v / 4 -- 4S
		if v <= 1.0 then
			return 0.0
		elseif v >= 1.4 then
			return 1.0
		else
			local values = { 0, 0.03, 0.08, 0.18, 0.5, 0.9, 0.95, 0.98, 1 }
			local i = math.floor((v - 1.0) / 0.05) + 1
			return values[i] + (v - 0.95 - i * 0.05) / 0.05 * (values[i + 1] - values[i])
		end
	end
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
		-- Build new score record
		local t = system.getDateTime()
		local round = 0
		if #scoreLog > 0 then
			round = scoreLog[#scoreLog][6] + 1
		end

		local record = {
			system.getProperty("Model"),
			string.format("%04i-%02i-%02i %02i:%02i", t.year, t.mon, t.day, t.hour, t.min),
			targetTime,
			score,
			landingPts,
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
	timerSwitch = system.pLoad("TimerSw")
	targetTime = system.pLoad("TgtTime") or 360
	winTime = system.pLoad("WinTime") or 540
	batteryType = system.pLoad("BatType") or 1
	vMin = 0.1 * (system.pLoad("vMin") or 37)
	scoreLogSize = system.pLoad("LogSize") or 40
end	

-- Navigate list of F3L landing points
local function landingUp(landingPts)
	if landingPts == 100 then
		return 0
	elseif landingPts >= 90 then
		return landingPts + 1
	elseif landingPts >= 30 then
		return landingPts + 5
	else
		return 30
	end
end

local function landingDown(landingPts)
	if landingPts == 0 then
		return 100
	elseif landingPts == 30 then
		return 0
	elseif landingPts <= 90 then
		return landingPts - 5
	else
		return landingPts - 1
	end
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

			-- Optional 10 sec. interval call
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

local function setTaskKeys()
	if state == STATE_INITIAL then
		form.setButton(1, ":tools", ENABLED)
		form.setButton(2, ":file", ENABLED)
	else
		form.setButton(1, ":tools", DISABLED)
		form.setButton(2, ":file", DISABLED)		
	end

	if state == STATE_FLYING or windowTimer.value <= 0 then
		form.setButton(3, ":timer", DISABLED)
	elseif state == STATE_WINDOW or state == STATE_WINDELAY then
		form.setButton(3, ":timer", HIGHLIGHTED)
	else
		form.setButton(3, ":timer", ENABLED)
	end
end -- setTaskKeys()

local function totalScore(targetTime, score, landingPts)
	return math.max(0, 2 * (math.min(targetTime, score) - math.max(0, score - targetTime)) + landingPts)
end

------------------------------------ Business --------------------------------------

-- Record the latest flight time (if >= 10 sec.)
local function recordScore(flightTime)
	flightTime = math.floor(flightTime)
	if flightTime >= 10 then
		score = flightTime
		playDuration(flightTime)
	else
		system.playBeep(0, 1760, 200)
	end
end

-- Handle transitions between program states
local function gotoState(newState)
	if state == STATE_WINDELAY then
		windowTimer.stop()
		windowTimer.set(winTime)
	end
	
	state = newState
	
	if taskEntered then
		if state < STATE_WINDELAY then
			windowTimer.stop()
			if state == STATE_INITIAL then
				score = 0
				landingPts = 0
			end
		else
			if state == STATE_WINDELAY then
				windowTimer.set(10.1)
			end
			windowTimer.run()
		end
	end
	
	if state == STATE_FLYING then
		flightTimer.run()
	else
		flightTimer.stop()
		flightTimer.set(targetTime)
	end
	
	if activeSubForm == 1 then
		setTaskKeys()
	end
end -- gotoState()

-- Main loop running all the time
local function loop()
	local interval -- Count interval
	local timerSw = getSwitch(timerSwitch)

	flightTimer.update()
	windowTimer.update()
	local flightTime = flightTimer.start - flightTimer.value

	-- Call out count down
	if flightTimer.value < 10 then
		interval = 1
	elseif flightTimer.value < 30 then
		interval = 5
	elseif flightTimer.value < 60 then
		interval = 15
	else
		interval = 60
	end

	if flightTimer.value >= 0 and math.ceil(flightTimer.value / interval) ~= math.ceil(flightTimer.prev / interval) then
		playDuration(flightTimer.value)
	end

	if state == STATE_INITIAL then
		windowTimer.set(winTime)
		flightTimer.set(targetTime)
	elseif state == STATE_WINDELAY then
		if windowTimer.value <= 0 then
			system.playBeep(0, 880, 500)
			gotoState(STATE_WINDOW)
		elseif math.ceil(windowTimer.value) ~= math.ceil(windowTimer.prev) then
			playDuration(windowTimer.value)
		end
	end
	
	if state <= STATE_WINDOW and timerSw and not prevTimerSw and windowTimer.value > 10 then
		flightTimer.set(math.min(flightTimer.start, windowTimer.value))
		playDuration(flightTimer.value)
		gotoState(STATE_FLYING)
	end
	
	if state == STATE_FLYING then
		if prevTimerSw and not timerSw and flightTime > 1 then
			recordScore(flightTime)
			if taskEntered then
				gotoState(STATE_WINDOW)
			else
				gotoState(STATE_INITIAL)
			end
		end
	end
	
	if state > STATE_WINDELAY and windowTimer.value <= 0 then
		system.playBeep(0, 880, 500)
		recordScore(flightTime)
		gotoState(STATE_PAUSE)
	end
	prevTimerSw = timerSw
end -- loop()

----------------------------------- Task form ---------------------------------------

local function printTask()
	local rgt = lcdw - 10
	local xt = rgt - lcd.getTextWidth(FONT_MAXI, "00:00")
	local w = rgt - xt - 6
	local txTele = system.getTxTelemetry()
	if txTele.rx1Percent == 0 then
		txTele.rx1Voltage = 0
	end

	-- Scores
	lcd.drawText(10, 0, lang.flightTime, FONT_BIG)
	drawTxtRgt(xt - 30, 0, s2str(score), FONT_BIG)
	lcd.drawText(10, 28, lang.landingPoints, FONT_BIG)
	if state == STATE_PAUSE then
		drawInverse(xt - 30, 28, landingPts, FONT_BIG, true)
	else
		drawTxtRgt(xt - 30, 28, landingPts, FONT_BIG)
	end
	lcd.drawText(10, 56, lang.total, FONT_BIG)
	drawTxtRgt(xt - 30, 56, totalScore(targetTime, score, landingPts), FONT_BIG)
	
	-- Timers
	lcd.drawText(xt, 0, lang.flight, FONT_BIG)
	drawTxtRgt(rgt, 16, s2str(flightTimer.value), FONT_MAXI)
	lcd.drawText(xt, 56, lang.window, FONT_BIG)
	drawTxtRgt(rgt, 72, s2str(windowTimer.value), FONT_MAXI)

	-- Draw flight battery status	
	lcd.setColor(lcd.getFgColor())
	lcd.drawFilledRectangle (xt + 2, 119, math.floor(batteryPct(txTele.rx1Voltage) * w), 22, 96)
	lcd.drawRectangle (xt + 1	, 118, w + 2, 24, 3)
	lcd.drawRectangle (xt, 117, w + 4, 26, 4)
	lcd.drawFilledRectangle (rgt - 2, 126, 3, 8)
	setColor()
	lcd.drawText(xt + 0.5 * w - 10, 119, string.format("%0.1f", txTele.rx1Voltage), FONT_BIG)

	-- Draw signal strength
	drawBars(0, 117, 5, 0.5 + 0.5 * txTele.RSSI[1])
	drawBars(0, 118, -5, 0.5 + 0.5 * txTele.RSSI[2])
	drawBars(xt - 114, 142, 10, 0.999 + 0.05 * txTele.rx1Percent)
end -- printTask()

local function initTask()
	if not taskEntered then
		taskEntered = true
		gotoState(STATE_INITIAL)
	end
	
	keyPress = function(key)
		if state == STATE_INITIAL then
			if key == KEY_1 then
				form.reinit(2)
			elseif key == KEY_2 then
				form.reinit(3)
			elseif key == KEY_3 then
				gotoState(STATE_WINDELAY)
			end
		elseif state == STATE_WINDELAY then
			if key == KEY_3 then
				gotoState(STATE_INITIAL)
			end
		elseif state == STATE_PAUSE then
			if key == KEY_3 and windowTimer.value > 0 then
				gotoState(STATE_WINDOW)
			elseif key == KEY_DOWN then
				landingPts = landingDown(landingPts)
			elseif key == KEY_UP then
				landingPts = landingUp(landingPts)
			elseif match(key, KEY_5, KEY_ENTER) then
				local save = form.question(lang.saveScores)
				if save == 1 then
					saveScores(true)
				end
				gotoState(STATE_INITIAL)
				form.preventDefault()
			end
		elseif state == STATE_WINDOW then
			if key == KEY_3 then
				gotoState(STATE_PAUSE)
			end
		end
		setTaskKeys()
	end

	printForm = printTask
	setTaskKeys()
	form.setTitle(appName)
end

--------------------------------- Settings form -------------------------------------

local function initSettings()
	local flt, win
	
	form.setTitle(lang.settings)

	local function fltChanged(t)
		targetTime = 60 * t
		if targetTime > winTime then
			winTime = targetTime
			form.setValue(win, winTime / 60)
		end
	end
	
	local function winChanged(t)
		winTime = 60 * t
		if winTime < targetTime then
			targetTime = winTime
			form.setValue(flt, targetTime / 60)
		end
	end
	
	keyPress = function(key)
		if match(key, KEY_5, KEY_ESC) then
			local saveChanges = 1
			if key == KEY_ESC then
				saveChanges = form.question(lang.saveChanges)
			end

			if saveChanges == 1 then
				system.pSave("TimerSw", timerSwitch)
				system.pSave("TgtTime", targetTime)
				system.pSave("WinTime", winTime)
				system.pSave("BatType", batteryType)
				system.pSave("vMin", 10 * vMin)
				system.pSave("LogSize", scoreLogSize)
			else
				readPersistent()
			end

			if timerSwitch then
				form.reinit(1)
				form.preventDefault()
			end
		end
	end

	printForm = void

	form.addRow(2)
	form.addLabel({ label = lang.timerSwitch, width = 225 })
	form.addInputbox(timerSwitch, false, function(v) timerSwitch = v end)

	form.addRow(2)
	form.addLabel({ label = lang.target, width = 225 })
	flt = form.addIntbox(targetTime / 60, 1, 99, 6, 0, 1, fltChanged)

	form.addRow(2)
	form.addLabel({ label = lang.winTime, width = 225 })
	win = form.addIntbox(winTime / 60, 1, 99, 6, 0, 1, winChanged)

	form.addRow(2)
	form.addLabel({ label = lang.batType, width = 225 })
	form.addSelectbox ({"LiPo", "NiMHx4"}, batteryType or 1, false, function(i) batteryType = i end) 

	form.addRow(2)
	form.addLabel({ label = lang.vMin, width = 225 })
	form.addIntbox(10 * vMin, 30, 50, 37, 1, 1, function(v) vMin = 0.1 * v end)

	form.addRow(2)
	form.addLabel({ label = lang.logSize, width = 225 })
	form.addIntbox(scoreLogSize, 5, 200, 40, 0, 5, function(v) scoreLogSize = v end)
	
	form.addLink(function() form.reinit(4) end, { label = "About " .. appName })
end

----------------------------------- Scores form -------------------------------------

local function initScores()
	local browseRecord = #scoreLog
	local record
	local min, sec, targetTime, landingPts, round
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
		targetTime = math.tointeger(record[3])
		local tme = math.tointeger(record[4])
		min = math.floor(tme / 60)
		sec = tme % 60
		landingPts = math.tointeger(record[5])
		round = math.tointeger(record[6])
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
					record[4] = 60 * min + sec
					record[5] = landingPts
					record[6] = round
					saveScores(false)
				else
					updateRecord()
				end
				setEditing(0)
			elseif key == KEY_1 then
				editing = (editing - 2) % 4 + 1
			elseif key == KEY_2 then
				editing = editing % 4 + 1
			elseif key == KEY_UP then
				changed = true
				if editing == 1 then
					round = round + 1
				elseif editing == 2 then
					min = (min + 1) % 100
				elseif editing == 3 then
					sec = (sec + 1) % 60
				elseif editing == 4 then
					landingPts = landingUp(landingPts)
				end
			elseif key == KEY_DOWN then
				changed = true
				if editing == 1 then
					if round > 0 then
						round = round - 1
					end
				elseif editing == 2 then
					min = (min - 1) % 100
				elseif editing == 3 then
					sec = (sec - 1) % 60
				elseif editing == 4 then
					landingPts = landingDown(landingPts)
				end
			end
		end		
	end -- keyPress()

	printForm = function()
		if browseRecord == 0 then return end
		
		lcd.drawText(x[1], 0, lang.round, FONT_BIG)
		drawTxtRgt(x[5], 0, string.format("%i", round), FONT_BIG)

		lcd.drawText(x[1], 24, lang.flightTime, FONT_BIG)
		drawTxtRgt(x[5], 24, string.format("%02i:%02i", min, sec), FONT_BIG)

		lcd.drawText(x[1], 48, lang.landingPoints, FONT_BIG)
		drawTxtRgt(x[5], 48, landingPts, FONT_BIG)
		
		lcd.drawText(x[1], 72, lang.total, FONT_BIG)
		drawTxtRgt(x[5], 72, totalScore(targetTime, 60 * min + sec, landingPts), FONT_BIG)
		
		lcd.drawText(x[1], 96, lang.target, FONT_BIG)
		drawTxtRgt(x[5], 96, tostring(math.floor(targetTime / 60 + 0.5)), FONT_BIG)

		if editing == 1 then
			drawInverse(x[5], 0, string.format("%i", round), FONT_BIG, true)
		elseif editing == 2 then
			drawInverse(x[2], 24, string.format("%02i", min), FONT_BIG)
		elseif editing == 3 then
			drawInverse(x[3], 24, string.format("%02i", sec), FONT_BIG)
		elseif editing == 4 then
			drawInverse(x[5], 48, string.format("%02i", landingPts), FONT_BIG, true)
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
		lcd.drawText(30, 10, "Copyright 2025 Jesper Frickmann")
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
		if timerSwitch then
			initTask()
		else
			initForm(4)
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
	local h2 = 0.5 * h - 4
	lcd.drawText(5, 6, lang.flight, FONT_NORMAL)
	drawTxtRgt(w - 5, 0, s2str(flightTimer.value), FONT_MAXI)
	lcd.drawText(5, h2 + 6, lang.win, FONT_NORMAL)
	drawTxtRgt(w - 5, h2, s2str(windowTimer.value), FONT_MAXI)
end

---------------------------------- Initialization ------------------------------------

-- Initialization
local function init()
	local path = "Apps/" .. appName .. "/"
	local chunk = loadfile(path .. system.getLocale() .. ".lua") or loadfile(path .. "en.lua")
	lang = chunk()
	
	score = 0
	landingPts = 0
	
	system.registerForm(1, MENU_MAIN, appName, initForm, function(key) keyPress(key) end, function() printForm() end)
	system.registerTelemetry(1, system.getProperty("Model"), 4, printTask)
	system.registerTelemetry(2, appName, 2, printTele)

	system.registerControl (1, "Flight timer", "Flt")
	system.setControl (1, -1, 0)

	readPersistent()
	prevTimerSw = getSwitch(timerSwitch)	
	flightTimer = newTimer(1)
	flightTimer.set(targetTime)
	windowTimer = newTimer()
	windowTimer.set(winTime)
	
	readScores()
end -- init()

return {init = init, loop = loop, author = author, version = version, name = appName}

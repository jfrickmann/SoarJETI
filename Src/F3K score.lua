------------------------------------------------------------------------------------
--	SoarJETI F3K score keeper																											--
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
local appName =		"F3K score keeper"
local author =		"Jesper Frickmann"
local version =		"1.0.0"
local SCORE_LOG =	"Log/F3K scores.csv"

-- Persistent variables
local launchSwitch					-- Launch switch, persistent data
local timeDial							-- For adjusting Poker calls, persistent data
local scoreLogSize					-- Max. no. of score records in file

-- Program states
local STATE_IDLE = 1				-- Task window not running
local STATE_PAUSE = 2		 		-- Task window paused, not flying
local STATE_FINISHED = 3		-- Task has been finished
local STATE_WINDOW = 4			-- Task window started, not flying
local STATE_READY = 5		 		-- Flight timer will be started when launch switch is released
local STATE_FLYING = 6			-- Flight timer started but flight not yet committed
local STATE_COMMITTED = 7 	-- Flight timer started, and flight committed
local STATE_FREEZE = 8			-- Still committed, but freeze	the flight timer
local state = STATE_IDLE		-- Current program state

-- Form navigation
local lang									-- Language translations
local labelInfo							-- Info label on screen
local labelTmr							-- Label before flight timer
local activeSubForm					-- Currently active sub form
local keyPress, printForm 	-- Functions vary by active form

-- Common variables for score keeping
local labelTask							-- Task menu label
local taskWindow						-- Length of task window
local launches							-- Number of launches allowed, -1 for unlimited
local taskScores						-- Number of scores in task 
local finalScores						-- Task scores are final
local targetType						-- 1. Huge ladder, 2. Poker, 3. "1234", 4. Big ladder, Else: constant time
local scoreType							-- 1. Best, 2. Last, 3. Make time
local currentTask						-- Currently selected task on menu
local counts								-- Flight timer countdown
local winTimer							-- Window timer
local flightTimer						-- Flight timer
local flightTime						-- Flight flown
local scores = { }					-- List of saved scores
local totalScore						-- Total score
local scoreLog = { }				-- List of previous scores
local prevLaunchSw					-- Used for detecting when Launch switch changes
local eow	= true						-- Automatically stop flight at end of window834
local qr = false						-- Quick relaunch

-- Variables used for time dial tasks like Poker
local pokerCalled						-- Lock in time
local lastInput = 0					-- For announcing changes in pokerCall
local lastChange = 0				-- Same
local timeDialSteps = { }		-- Steps for various time dial tasks

--------------------------------- Language locale ----------------------------------

local languages = {
	en = {
		qr = "QR",							-- Quick Relaunch
		eow = "EoW",						-- End of Window
		ok = "OK",
		flight = "Flight:",
		flt = "Flt",
		target = "Target:",
		window = "Window:",
		win = "Win",
		total = "Total",
		done = "Done!",
		launchLeft = "launch left",
		launchesLeft = "launches left",
		saveScores = "Save scores?",
		noScores = "No scores yet!",
		pressedESC = "You pressed ESC",
		changesNotSaved = "Changes were NOT saved!",
		launchSwitch = "Launch switch",
		timeDial = "Time dial for Poker",
		winCall = "Window time switch",
		logSize = "Score log size"
	}
}

------------------------------------ Task data -------------------------------------

-- { label, window, launches, scores, final, tgtType, scoreType }
local tasks = {
	{ "A. Last flight", 420, -1, 1, false, 300, 2	},
	{ "B. Two last 3:00", 420, -1, 2, false, 180, 2	},
	{ "B. Two last 4:00", 600, -1, 2, false, 240, 2	},
	{ "C. All up last down", 0, 8, 8, true, 180, 2	},
	{ "D. Two flights only", 600, 2, 2, true, 300, 2	},
	{ "E. Poker 10 min.", 600, -1, 3, true, 2, 3	},
	{ "E. Poker 15 min.", 900, -1, 3, true, 2, 3	},
	{ "F. Three best of six", 600, 6, 3, false, 180, 1	},
	{ "G. Five best flights", 600, -1, 5, false, 120, 1	},
	{ "H. 1-2-3-4 any order", 600, -1, 4, false, 3, 1	},
	{ "I. Three best flights", 600, -1, 3, false, 200, 1	},
	{ "J. Three last flights", 600, -1, 3, false, 180, 2	},
	{ "K. Big Ladder", 600, 5, 5, true, 4, 2	},
	{ "L. One flight only", 600, 1, 1, true, 599, 2	},
	{ "M. Huge Ladder", 900, 3, 3, true, 1, 2	},
	{ "Y. Quick Relaunch!", 0, -1, 8, false, 2, 2	},
	{ "Z. Just Fly!", 0, -1, 8, false, 0, 2	}
}

timeDialSteps[6]	= { {30,	5}, {60, 10}, {120, 15}, {210, 30}, {420, 60}, {660, 1} }	-- Poker 10 min.
timeDialSteps[7]	= { {30, 10}, {90, 15}, {270, 30}, {480, 60}, {960, 1} } 						-- Poker 15 min.
timeDialSteps[16] = { {15,	5}, {30, 10}, { 60, 15}, {120, 30}, {270, 1} } 							-- QR

-------------------------------- Utility functions ---------------------------------

local function void()
end

-- Safely read switch as boolean
local function getSwitch(sw)
       if not sw then return false end
       local val = system.getInputsVal(sw)
       if not val then return false end
       return (val > 0)
end

-- LiPo flight pack pct.
local function fltBatPct()
	local v = system.getTxTelemetry().rx1Voltage or 0.0
	-- More than 1S?
	if v > 0 then
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
end

-- Draw text right adjusted
local function drawTxtRgt(x, y, txt, flags)
	x = x - lcd.getTextWidth(flags, txt)
	lcd.drawText(x, y, txt, flags)
end

-- Draw text center adjusted
local function drawTxtCtr(x, y, txt, flags)
	x = x - 0.5 * lcd.getTextWidth(flags, txt)
	lcd.drawText(x, y, txt, flags)
end

-- Button ENABLED or DISABLED
local function hl(b)
	if b then
		return HIGHLIGHTED
	else
		return ENABLED
	end
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

-- Set the key labels in the task menu
local function setTaskKeys()
	form.setButton(1, lang.qr, hl(qr))
	form.setButton(2, lang.eow, hl(eow))

	-- Configure button 3
	if state <= STATE_PAUSE then
		form.setButton(3, ":timer", ENABLED)
	elseif state == STATE_WINDOW then
		form.setButton(3, ":wait", ENABLED)
	elseif state >= STATE_COMMITTED then
		form.setButton(3, ":delete", ENABLED)
	else
		form.setButton(3, "", ENABLED)
	end

	-- Configure button 5
	if state < STATE_WINDOW or state == STATE_FREEZE then
		form.setButton(5, lang.ok, ENABLED)
	else
		form.setButton(5, lang.ok, DISABLED)
	end
end -- setTaskKeys()

-- Save scores
local function saveScores(addNew)
	if addNew then
		-- Build new score record
		local record = {
			labelTask,
			system.getProperty ("Model"),
		}
		
		local t = system.getDateTime()
		table.insert(record, string.format("%04i-%02i-%02i %02i:%02i", t.year, t.mon, t.day, t.hour, t.min))
		table.insert(record, totalScore)
		
		for i, s in ipairs(scores) do
			table.insert(record, s)
		end

		-- Insert record in scoreLog with max. entries
		table.insert(scoreLog, record)
		while #scoreLog > scoreLogSize do
			for i = 1, #scoreLog do
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

-- Change to another sub form
local function gotoForm(f)
	activeSubForm = f
	form.reinit()
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
			timer.value = 0.1 * math.floor(0.01 * d * ms + 0.5)
			
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

-- Convert seconds to "mm:ss.s"
local function s2str(s)
	if not s then
		return "-- -- --"
	end
	
	local sign = ""
	if s < 0 then
		s = -s
		sign = "-"
	end

	local m = math.floor(s / 60)
	s = s - 60 * m
	
	return sign .. string.format("%02i:%04.1f", m, s)
end

------------------------------------ Business --------------------------------------

-- Keep the best scores
local function recordBest(scores, newScore)
	local n = #scores
	local i = 1
	local j = 0

	-- Find the position where the new score is going to be inserted
	if n == 0 then
		j = 1
	else
		-- Find the first position where existing score is smaller than the new score
		while i <= n and j == 0 do
			if newScore > scores[i] then j = i end
			i = i + 1
		end
		
		if j == 0 then j = i end -- New score is smallest; end of the list
	end

	-- If the list is not yet full; let it grow
	if n < taskScores then n = n + 1 end

	-- Insert the new score and move the following scores down the list
	for i = j, n do
		newScore, scores[i] = scores[i], newScore
	end
end	--	recordBest (...)

-- Used for calculating the total score and sometimes target time
local function maxScore(iFlight, targetType)
	if targetType == 1 then -- Huge ladder
		return 60 + 120 * iFlight
	elseif targetType == 2 then -- Poker
		return 9999
	elseif targetType == 3 then -- 1234
		return 300 - 60 * iFlight
	elseif targetType == 4 then -- Big ladder
		return 30 + 30 * iFlight
	else -- maxScore = targetType
		return targetType
	end
end

-- Calculate total score for task
local function calcTotalScore(scores, targetType)
	local total = 0	
	for i = 1, #scores do
		total = total + math.min(maxScore(i, targetType), scores[i])
	end
	return total
end

-- Record scores
local function score()
	if scoreType == 1 then -- Best scores
		recordBest(scores, flightTime)

	elseif scoreType == 2 then -- Last scores
		local n = #scores
		if n >= taskScores then
			-- List is full; move other scores one up to make room for the latest at the end
			for j = 1, n - 1 do
				scores[j] = scores[j + 1]
			end
		else
			-- List can grow; add to the end of the list
			n = n + 1
		end
		scores[n] = flightTime

	else -- Must make time to get score
		local score = flightTime
		-- Did we make time?
		if flightTimer.value > 0 then
			return
		else
			-- In Poker, only score the call
			if pokerCalled then
				score = flightTimer.start
				pokerCalled = false
			end
		end
		scores[#scores + 1] = score

	end
	totalScore = calcTotalScore(scores, targetType)
end -- score()

-- Find the best target time, given what has already been scored, as well as the remaining time of the window.
-- Note: maxTarget ensures that recursive calls to this function only test shorter target times. That way, we start with
-- the longest flight and work down the list. And we do not waste time testing the same target times in different orders.
local function best1234Target(timeLeft, scores, maxTarget)
	local bestTotal = 0
	local bestTarget = 0

	-- Max. minutes there is time left to fly
	local maxMinutes = math.min(maxTarget, 4, math.ceil(timeLeft / 60))

	-- Iterate from 1 to n minutes to find the best target time
	for i = 1, maxMinutes do
		local target
		local tl
		local tot
		local dummy

		-- Target in seconds
		target = 60 * i

		-- Copy scores to a new table
		local s = {}
		for j = 1, #scores do
			s[j] = scores[j]
		end

		-- Add new target time to s; only until the end of the window
		recordBest(s, math.min(timeLeft, target))
		tl = timeLeft - target

		-- Add up total score, assuming that the new target time was made
		if tl <= 0 or i == 1 then
			-- No more flights are made; sum it all up
			tot = 0
			for j = 1, math.min(4, #s) do
				tot = tot + math.min(300 - 60 * j, s[j])
			end
		else
			-- More flights can be made; add more flights recursively
			-- Subtract one second from tl for turnaround time
			dummy, tot = best1234Target(tl - 1, s, i - 1)
		end

		-- Do we have a new winner?
		if tot > bestTotal then
			bestTotal = tot
			bestTarget = target
		end
	end

	return bestTarget, bestTotal
end	--	best1234Target(..)

-- Get called time from user in Poker
local function pokerCall()
	if not timeDial then return 60 end
	local input = system.getInputsVal(timeDial)
	if not input then return 60 end
	input = math.min(0.999, input)
	local tblStep = timeDialSteps[currentTask]
	
	local i, x = math.modf(1 + (#tblStep - 1) * (input + 1) / 2)
	local t1 = tblStep[i][1]
	local dt = tblStep[i][2]
	local t2 = tblStep[i + 1][1]	
	local result = t1 + dt * math.floor(x * (t2 - t1) / dt)
	
	if scoreType == 3 then
		result = math.min(winTimer.value - 1, result)
	end
	
	if math.abs(input - lastInput) >= 0.02 then
		lastInput = input
		lastChange = system.getTimeCounter()
	end
	
	if state == STATE_COMMITTED and lastChange > 0 and system.getTimeCounter() - lastChange > 1000 then
		system.playBeep(0, 3000, 100)
		playDuration(result)
		lastChange = 0
	end
	
	return result
end -- pokerCall()

local function targetTime()
	if targetType == 2 then -- Poker
		if pokerCalled then
			return flightTimer.start
		else
			return pokerCall()
		end
	elseif targetType == 3 then -- 1234
		return best1234Target(winTimer.value, scores, 4)
	else -- All other tasks
		return maxScore(#scores + 1, targetType)
	end
end -- targetTime()

-- Handle transitions between program states
local function gotoState(newState)
	state = newState
 
	if state < STATE_WINDOW or state == STATE_FREEZE then
		winTimer.stop()
		flightTimer.stop()
		labelTmr = lang.target

		if state == STATE_FINISHED then
			system.playBeep(0, 880, 1000)
		end
	
	elseif state <= STATE_READY then
		winTimer.run()
		flightTimer.stop()
		labelTmr = lang.target
		
	elseif state == STATE_FLYING then
		flightTimer.run()
		labelTmr = lang.flight
		
		-- Get ready to count down
		local tgtTime = targetTime()
		
		-- A few extra counts in 1234
		if targetType == 3 then
			counts = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 15, 20, 30, 45, 65, 70, 75, 125, 130, 135, 185, 190, 195}
		else
			counts = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 15, 20, 30, 45}
		end

		while #counts > 1 and counts[#counts] >= tgtTime do
			counts[#counts] = nil
		end

		if flightTimer.start > 0 then
			playDuration(flightTimer.start)
		else
			system.playBeep(0, 1760, 100)
		end
	
	elseif state == STATE_COMMITTED then
		if launches > 0 then
			launches = launches - 1
		end
		lastChange = 0
	end
 
	if activeSubForm == 3 then
		setTaskKeys()
	end

	-- Configure info text label
	if state == STATE_PAUSE then
		labelInfo = string.format(lang.total .. ": %i sec.", totalScore)
	elseif state == STATE_FINISHED then
		labelInfo = string.format(lang.done .. " %i sec.", totalScore)
	else
		if launches >= 0 then
			local s
			if launches == 1 then
				s = lang.launchLeft
			else
				s = lang.launchesLeft
			end
			labelInfo = string.format("%i %s", launches, s)
		else
			labelInfo = ""
		end
	end
end -- gotoState()

-- Function for setting up a task
local function setupTask(taskData)
	labelTask = taskData[1]
	taskWindow = taskData[2]
	launches = taskData[3]
	taskScores = taskData[4]
	finalScores = taskData[5]
	targetType = taskData[6]
	scoreType = taskData[7]
	scores = { }
	totalScore = 0
	pokerCalled = false
	
	gotoState(STATE_IDLE)
end -- setupTask(...)

-- Main loop running all the time
local function loop()
	local launchSw = getSwitch(launchSwitch)
	local launchPulled = (launchSw and not prevLaunchSw)
	local launchReleased = (not launchSw and prevLaunchSw)
	prevLaunchSw = launchSw
	
	flightTimer.update()
	winTimer.update()
	flightTime = math.abs(flightTimer.start - flightTimer.value)
	
	if state <= STATE_READY and state ~= STATE_FINISHED then
		flightTimer.set(targetTime())
	end
	
	if state < STATE_WINDOW then
		if state == STATE_IDLE then
			winTimer.set(taskWindow)

			-- Automatically start window and flight if launch switch is released
			if launchPulled then
				gotoState(STATE_READY)
			end
		end

	else
		-- Did the window expire?
		if winTimer.prev > 0 and winTimer.value <= 0 then
			system.playBeep(0, 880, 1000)

			if state < STATE_FLYING then
				gotoState(STATE_FINISHED)
			elseif eow then
				gotoState(STATE_FREEZE)
			end
		end

		if state == STATE_WINDOW then
			if launchPulled then
				gotoState(STATE_READY)
			elseif launchReleased then
				-- Play tone to warn that timer is NOT running
				system.playBeep(0, 1760, 200)
			end
			
		elseif state == STATE_READY then
			if launchReleased then
				gotoState(STATE_FLYING)
			end

		elseif state >= STATE_FLYING then
			-- Time counts
			if flightTimer.value <= counts[#counts] and flightTimer.prev > counts[#counts]	then
				playDuration(flightTimer.value)
				if #counts > 1 then 
					counts[#counts] = nil
				end
			elseif math.ceil(flightTimer.value / 60) ~= math.ceil(flightTimer.prev / 60) and flightTimer.prev > 0 then
				playDuration(flightTimer.value)
			end
			
			if state == STATE_FLYING then
				-- Within 10 sec. "grace period", cancel the flight
				if launchPulled then
					gotoState(STATE_WINDOW)
				end

				-- After 10 seconds, commit flight
				if flightTime >= 10 then
					gotoState(STATE_COMMITTED)
				end
				
			elseif launchPulled then
				-- Report the time after flight is done
				if flightTimer.start == 0 then
					playDuration(flightTime)
				end

				score()
				
				-- Change state
				if (finalScores and #scores == taskScores) or launches == 0 or (taskWindow > 0 and winTimer.value <= 0) then
					gotoState(STATE_FINISHED)
				elseif qr then
					gotoState(STATE_READY)
				else
					gotoState(STATE_WINDOW)
				end
			end
		end
	end

	-- Update info for user dial targets
	if state == STATE_COMMITTED and targetType == 2 and (scoreType ~= 3 or taskScores - #scores > 1) then
		local call = pokerCall()
		local min = math.floor(call / 60)
		local sec = call - 60 * min
		labelInfo = string.format("Next call: %02i:%02i", min, sec)
	end

	-- "Must make time" tasks
	if scoreType == 3 then
		if state == STATE_COMMITTED then
			pokerCalled = true
		elseif state < STATE_FLYING and state ~= STATE_FINISHED and winTimer.value < targetTime() then
			gotoState(STATE_FINISHED)
		end
	end
end -- loop()

----------------------------------- Menu form --------------------------------------

local function keyPressMenu(key)
	if key == KEY_1 then
		gotoForm(2)
	elseif key == KEY_2 then
		gotoForm(4)
	end
end

local function initMenu()
	keyPress = keyPressMenu
	printForm = void

	form.setButton(1, ":tools", ENABLED)
	form.setButton(2, ":file", ENABLED)
	
	for i, task in ipairs(tasks) do
		local function startTask()
			currentTask = i
			setupTask(task)
			gotoForm(3)
		end
		
		form.addLink(startTask, { label = task[1], font = FONT_BIG })
	end
	
	form.setFocusedRow(currentTask)
	form.setTitle(appName)
	
	-- Start dummy task
	setupTask({ "", 0, -1, 1, false, 0, 2	})
	qr = false
end

--------------------------------- Settings form -------------------------------------

local function keyPressSettings(key)
	if match(key, KEY_5, KEY_ESC) then
		if key == KEY_5 then
			system.pSave("LaunchSw", launchSwitch)
			system.pSave("TimeDial", timeDial)
			system.pSave("WinCall", winTimer.interval)
			system.pSave("LogSize", scoreLogSize)
		else
			launchSwitch = system.pLoad("LaunchSw")
			timeDial = system.pLoad("TimeDial")
			winTimer.interval = system.pLoad("WinCall")
			scoreLogSize = system.pLoad("LogSize") or 40
			form.question (lang.changesNotSaved, lang.pressedESC, "", 2500, true)
		end
		if launchSwitch then
			gotoForm(1)
			form.preventDefault()
		end
	end
end

local function initSettings()
	keyPress = keyPressSettings
	printForm = void

	form.addRow(2)
	form.addLabel({ label = lang.launchSwitch, font = FONT_BIG })
	form.addInputbox(launchSwitch, false, function(v) launchSwitch = v end, { font = FONT_BIG })

	form.addRow(2)
	form.addLabel({ label = lang.timeDial, font = FONT_BIG, width = 220 })
	form.addInputbox(timeDial, true, function(v) timeDial = v end, { font = FONT_BIG })

	form.addRow(2)
	form.addLabel({ label = lang.winCall, font = FONT_BIG, width = 220 })
	form.addInputbox(winTimer.interval, true, function(v) winTimer.interval = v end, { font = FONT_BIG })
	
	form.addRow(2)
	form.addLabel({ label = lang.logSize, font = FONT_BIG, width = 220 })
	form.addIntbox(scoreLogSize, 5, 200, 40, 0, 5, function(v) scoreLogSize = v end, { font = FONT_BIG })
	
	form.addLink(function() gotoForm(5) end, { label = "About " .. appName, font = FONT_BIG })
end

----------------------------------- Task form ---------------------------------------

local function keyPressTask(key)
	if key == KEY_1 then
		qr = not qr
		form.setButton(1, lang.qr, hl(qr))
	elseif key == KEY_2 then
		eow = not eow
		form.setButton(2, lang.eow, hl(eow))
	elseif key == KEY_3 then
		if state <= STATE_PAUSE then
			gotoState(STATE_WINDOW)
		elseif state == STATE_WINDOW then
			gotoState(STATE_PAUSE)
		elseif state >= STATE_COMMITTED then
			-- Record a zero score!
			flightTime = 0
			score()
			-- Change state
			if winTimer.value <= 0 or (finalScores and #scores == taskScores) or launches == 0 then
				gotoState(STATE_FINISHED)
			else
				system.playBeep(0, 440, 333)
				gotoState(STATE_WINDOW)
			end
		end
	elseif key == KEY_5 then
		if state < STATE_WINDOW or state == STATE_FREEZE then
			if key == KEY_5 and match(state, STATE_PAUSE, STATE_FINISHED, STATE_FREEZE) then
				local save = form.question(lang.saveScores)
				if save == 1 then
					saveScores(true)
				end
			end
			gotoForm(1)
		end
		form.preventDefault()
	elseif key == KEY_ESC and state == STATE_IDLE then
		gotoForm(1)
		form.preventDefault()
	end
end

local function printTask()
	local rgt = lcd.width - 10
	local xt = rgt - lcd.getTextWidth(FONT_MAXI, "00:00.0")
	local x = 5
	local y = 6
	local split
	local rxBt

	if match(taskScores, 5, 6) then
		split = 3
	else
		split = 4
	end
	
	for i = 1, taskScores do
		lcd.drawText(x, y, string.format("%i. %s", i, s2str(scores[i])), FONT_BIG)
		if i == split then
			x = 105
			y = 6
		else
			y = y + 28
		end
	end
	
	lcd.drawText(xt, 0, labelTmr, FONT_BIG)
	drawTxtRgt(rgt, 16, s2str(flightTimer.value), FONT_MAXI)
	lcd.drawText(xt, 60, lang.window, FONT_BIG)
	drawTxtRgt(rgt, 76, s2str(winTimer.value), FONT_MAXI)
	lcd.drawText(5, 120, labelInfo, FONT_BIG)
	
	local w = math.floor(fltBatPct() * 80)
	lcd.drawFilledRectangle (217, 120, w, 20, 142)
	lcd.drawFilledRectangle (300, 126, 3, 8)
	lcd.drawRectangle (214, 117, 86, 26, 4)
	lcd.drawRectangle (215, 118, 84, 24, 3)
end -- printTask()

local function initTask()
	keyPress = keyPressTask
	printForm = printTask
	setTaskKeys()
	form.setTitle(labelTask)
end

----------------------------------- Scores form -------------------------------------

local function initScores()
	local browseRecord = #scoreLog
	local record
	local scores
	local taskScores
	local targetType
	local editing
	local selected = 1
	local min, sec, dec
	local dx = {
		lcd.getTextWidth(FONT_BIG, "0. "),
		lcd.getTextWidth(FONT_BIG, "0. 00:"),
		lcd.getTextWidth(FONT_BIG, "0. 00:00.")
	}
	local rb, gb, bb = lcd.getBgColor()
	local rf, gf, bf = lcd.getFgColor()
	
	form.setTitle(lang.noScores)

	-- Update form when record changes
	local function updateRecord()
		record = scoreLog[browseRecord]
		local taskName = record[1]
		form.setTitle(taskName)
		
		-- Find task type, number of scores, and target type
		taskScores = 8
		targetType = 9999
		for i, task in ipairs(tasks) do
			if taskName == task[1] then
				taskScores = task[4]
				targetType = task[6]
				break
			end
		end

		-- Copy scores from record
		scores = { }
		for i = 1, #record - 4 do
			scores[i] = tonumber(record[i + 4])
		end
	end
		
	-- Update buttons when editing level changes
	local function setEditing(ed)
		if ed == 0 then
			form.setButton(1, ":down", ENABLED)
			form.setButton(2, ":up", ENABLED)
			form.setButton(3, ":edit", ENABLED)
			updateRecord()
		elseif ed == 1 then
			form.setButton(1, ":left", ENABLED)
			form.setButton(2, ":right", ENABLED)
			form.setButton(3, "", ENABLED)
		elseif ed == 2 then
			form.setButton(1, ":left", DISABLED)
			form.setButton(2, ":right", ENABLED)
		elseif ed == 3 then
			form.setButton(1, ":left", ENABLED)
			form.setButton(2, ":right", ENABLED)
		else -- ed == 4
			form.setButton(1, ":left", ENABLED)
			form.setButton(2, ":right", DISABLED)
		end
		editing = ed
	end
	
	if browseRecord > 0 then
		setEditing(0)
	end
	
	local function updateSelected()
		scores[selected] = 60 * min + sec + 0.1 * dec
	end
	
	keyPress = function(key)
		if match(key, KEY_5, KEY_ESC) then
			form.preventDefault()
		end
			
		if browseRecord == 0 then
			if match(key, KEY_5, KEY_ESC) then
				gotoForm(1)
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
				gotoForm(1)
			end
		elseif editing == 1 then
			if key == KEY_ENTER then
				local s = scores[selected] or 0
				min = math.floor(s / 60)
				s = s - 60 * min
				sec = math.floor(s)
				dec = math.floor(10 * (s - sec) + 0.5)
				updateSelected()
				setEditing(2)
			elseif match(key, KEY_1, KEY_DOWN) then
				selected = (selected - 2) % math.min(#scores + 1, taskScores) + 1
			elseif match(key, KEY_2, KEY_UP) then
				selected = selected % math.min(#scores + 1, taskScores) + 1
			elseif match(key, KEY_5, KEY_ESC) then
				if key == KEY_5 then
					for i = 1, #scores do
						record[i + 4] = string.format("%0.1f", scores[i])
					end
					record[4] = calcTotalScore(scores, targetType)
					saveScores(false)
				else
					form.question (lang.changesNotSaved, lang.pressedESC, "", 2500, true)
				end
				setEditing(0)
			end
		else
			if match(key, KEY_5, KEY_ESC, KEY_ENTER) then
				updateSelected()
				setEditing(1)
			end
			
			if editing == 2 then
				if key == KEY_2 then
					updateSelected()
					setEditing(3)
				elseif key == KEY_UP then
					min = (min + 1) % 100
				elseif key == KEY_DOWN then
					min = (min - 1) % 100
				end
			elseif editing == 3 then
				if key == KEY_1 then
					updateSelected()
					setEditing(2)
				elseif key == KEY_2 then
					updateSelected()
					setEditing(4)
				elseif key == KEY_UP then
					sec = (sec + 1) % 60
				elseif key == KEY_DOWN then
					sec = (sec - 1) % 60
				end
			else -- editing == 4
				if key == KEY_1 then
					updateSelected()
					setEditing(3)
				elseif key == KEY_UP then
					dec = (dec + 1) % 10
				elseif key == KEY_DOWN then
					dec = (dec - 1) % 10
				end
			end
		end
	end
	
	local function scorePos(i)
		i = i - 1
		local x = 10 + 100 * (i % 3)
		local y = 25 * math.floor(i / 3)
		return x, y
	end

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
		
		local x, y
		
		for i = 1, taskScores do
			x, y = scorePos(i)
			lcd.drawText(x, y, string.format("%i. %s", i, s2str(scores[i])), FONT_BIG)
		end
			
		y = y + 25
		lcd.drawText(10, y, string.format("Total: %0.1f s", tonumber(record[4])), FONT_BIG)	

		y = 120
		lcd.drawText(10, y, tostring(record[2]), FONT_BIG)
		drawTxtRgt(lcd.width - 10, y, tostring(record[3]), FONT_BIG)
		
		x, y = scorePos(selected)
		if editing == 1 then
			drawInverse(x + dx[1], y, s2str(scores[selected]), FONT_BIG)
		elseif editing == 2 then
			drawInverse(x + dx[1], y, string.format("%02i", min), FONT_BIG)
		elseif editing == 3 then
			drawInverse(x + dx[2], y, string.format("%02i", sec), FONT_BIG)
		elseif editing == 4 then
			drawInverse(x + dx[3], y, dec, FONT_BIG)
		end
	end
end

------------------------------------ About form -------------------------------------

local function initAbout()
	form.setTitle("About " .. appName)

	keyPress = function(key)
		if match(key, KEY_5, KEY_ESC) then
			form.preventDefault()
			gotoForm(2)
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

------------------------------ Other form / telemetry --------------------------------

-- Called by form.reinit()
local function reInit()
	if activeSubForm == 1 then
		if not launchSwitch then
			gotoForm(5)
		else
			initMenu()
		end
	elseif activeSubForm == 2 then
		initSettings()
	elseif activeSubForm == 3 then
		initTask()
	elseif activeSubForm == 4 then
		initScores()
	else
		initAbout()
	end
end

-- Flight timer in telemetry window
local function printTele(w, h)
	local h2 = 0.5 * h
	lcd.drawText(2, 6, lang.win, FONT_NORMAL)
	drawTxtRgt(w - 2, 0, s2str(winTimer.value), FONT_MAXI)
	lcd.drawText(2, h2 + 6, lang.flt, FONT_NORMAL)
	drawTxtRgt(w - 2, h2, s2str(flightTimer.value), FONT_MAXI)
end

---------------------------------- Initialization ------------------------------------

-- Initialization
local function init()
	lang = languages[system.getLocale()] or languages.en
	system.registerForm(1, MENU_MAIN, appName, reInit, function(key) keyPress(key) end, function() printForm() end)
	system.registerTelemetry(1, "F3K", 0, printTele)
	system.registerControl (1, "Window timer", "Win")
	system.setControl (1, -1, 0)
	system.registerControl (2, "Flight timer", "Flt")
	system.setControl (2, -1, 0)

	launchSwitch = system.pLoad("LaunchSw")
	prevLaunchSw = getSwitch(launchSwitch)
	timeDial = system.pLoad("TimeDial")
	scoreLogSize = system.pLoad("LogSize") or 40	
	winTimer = newTimer(1, system.pLoad("WinCall"))
	flightTimer = newTimer(2)
	currentTask = 1
	activeSubForm = 1
	
	-- Start dummy task
	setupTask({ "", 0, -1, 1, false, 0, 2	})
	
	-- Read score file
	local buffer = io.readall(SCORE_LOG)
	if buffer == nil then return end

	for line in string.gmatch(buffer, "[^\r\n]+") do
		local fields = { }
		for field in string.gmatch(line, "[^,]+") do
			fields[#fields + 1] = field
		end
		scoreLog[#scoreLog + 1] = fields
	end
end -- init()

return {init = init, loop = loop, author = author, version = version, name = appName}

------------------------------------------------------------------------------------
--	Print global variables																												--
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
local appName =		"Print global variables"
local author =		"Jesper Frickmann"
local version =		"1.0.0"

-- Globals defined by Lua and JETI
local globs = {
	_G = true,
	_VERSION = true,
	assert = true,
	AUDIO_BACKGROUND = true,
	AUDIO_IMMEDIATE = true,
	AUDIO_QUEUE = true,
	collectgarbage = true,
	coroutine = true,
	debug = true,
	dir = true,
	DISABLED = true,
	dofile = true,
	ENABLED = true,
	error = true,
	FONT_AND = true,
	FONT_BIG = true,
	FONT_BOLD = true,
	FONT_GRAYED = true,
	FONT_MAXI = true,
	FONT_MINI = true,
	FONT_NORMAL = true,
	FONT_OR = true,
	FONT_REVERSED = true,
	FONT_XOR = true,
	form = true,
	getmetatable = true,
	gpio = true,
	gps = true,
	HIGHLIGHTED = true,
	io = true,
	ipairs = true,
	json = true,
	KEY_1 = true,
	KEY_2 = true,
	KEY_3 = true,
	KEY_4 = true,
	KEY_5 = true,
	KEY_DOWN = true,
	KEY_ENTER = true,
	KEY_ESC = true,
	KEY_MENU = true,
	KEY_RELEASED = true,
	KEY_UP = true,
	lcd = true,
	load = true,
	loadfile = true,
	math = true,
	MENU_ADVANCED = true,
	MENU_APPS = true,
	MENU_FINE = true,
	MENU_GAMES = true,
	MENU_MAIN = true,
	MENU_NONE = true,
	MENU_SYSTEM = true,
	MENU_TELEMETRY = true,
	MODEL = true,
	next = true,
	os = true,
	package = true,
	pairs = true,
	pcall = true,
	print = true,
	rawequal = true,
	rawget = true,
	rawlen = true,
	rawset = true,
	require = true,
	select = true,
	serial = true,
	setmetatable = true,
	SOUND_AUTOTRIM = true,
	SOUND_BKUP = true,
	SOUND_BOUND = true,
	SOUND_INACT = true,
	SOUND_LOWSIGNAL = true,
	SOUND_LOWTXVOLT = true,
	SOUND_RANGETEST = true,
	SOUND_RXRESET = true,
	SOUND_START = true,
	SOUND_TELEMLOSS = true,
	string = true,
	SYSTEM = true,
	system = true,
	table = true,
	tonumber = true,
	tostring = true,
	type = true,
	utf8 = true,
	xpcall = true
}

local function printGlobals()
	print("------ Global variables -------")
	for name, var in pairs(_G) do
		if not globs[name] then
			print(string.format("%s <%s>", name, type(var)))
		end
	end
	print("------------ End --------------")
end

local function initForm(f)
  form.addLink(printGlobals, { label = appName, font=FONT_BOLD })
end

local function init()
  system.registerForm(1, MENU_APPS, appName, initForm, nil, nil)
end

return { init = init, author = author, version = version, name = appName }

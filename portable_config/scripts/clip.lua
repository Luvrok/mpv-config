-- clip: lossless cuts (c) in a uosc menu. the streams are copied, never
-- re-encoded, so the picture and the sound stay bit-identical. s and e take
-- the current time as the start and the end, a track can be picked for the
-- audio and the subtitles (or none of them), and the folder the clip goes to
-- is picked in a browser over the XDG folders and the disk. the file is
-- always an mkv, it holds any
-- codec the source has, subtitles and attached fonts included. copy means the
-- cut starts at the keyframe before the chosen time: the clip can open a few
-- seconds early, nothing is lost to an encoder

local utils = require('mp.utils')
local input = require('mp.input')

local o = {
	-- expanded, ~ works. the folder picked in the menu is remembered
	output_folder = '~/documents/videos',
	-- %n name, %s start, %e end
	filename_template = '%n_%s-%e',
	-- what opens the menu
	key = 'c',
}
require('mp.options').read_options(o, 'clip')

local script = mp.get_script_name()
local timings = {}
local sel = {}
local home = mp.command_native({'expand-path', '~'})
local folder_current = home
local folder_typing = false

-- ~~ only expands once the player is up, so the state paths are made on use
local function state_path(name)
	return mp.command_native({'expand-path', '~~state/' .. name})
end

local function trim(s) return (s:gsub('^%s+', ''):gsub('%s+$', '')) end

-- the folders from ~/.config/user-dirs.dirs, so the menu offers the same
-- Videos, Downloads and Documents the desktop does
local function xdg_dirs()
	local dirs = {}
	local f = io.open(home .. '/.config/user-dirs.dirs', 'r')
	if not f then return dirs end
	for line in f:lines() do
		local key, value = line:match('^%s*XDG_([%u_]+)_DIR%s*=%s*"(.*)"%s*$')
		if key and value ~= '' then
			dirs[key:lower()] = (value:gsub('%$HOME', home))
		end
	end
	f:close()
	return dirs
end

local xdg = xdg_dirs()

local function notify(msg, duration)
	mp.osd_message(msg, duration or 4)
end

local function error_text(res, err)
	local text = res and (res.stderr ~= '' and res.stderr or res.stdout) or err or 'unknown error'
	return trim(text):gsub('%s+', ' ')
end

-- the folder picked last time, else the config default, else the XDG videos
local function output_folder()
	local f = io.open(state_path('clip-output'), 'r')
	local saved = f and trim(f:read('*a') or '') or ''
	if f then f:close() end
	if saved ~= '' then return mp.command_native({'expand-path', saved}) end
	if o.output_folder and o.output_folder ~= '' then
		return mp.command_native({'expand-path', o.output_folder})
	end
	return xdg.videos or home
end

local function remember_folder(path)
	local file = state_path('clip-output')
	mp.command_native({name = 'subprocess', args = {'mkdir', '-p', file:match('^(.*)/[^/]*$')}, playback_only = false})
	local f = io.open(file, 'w')
	if f then
		f:write(path .. '\n')
		f:close()
	end
end

local function pretty_path(path)
	if path == home then return '~' end
	if path:sub(1, #home + 1) == home .. '/' then return '~' .. path:sub(#home + 1) end
	return path
end

local function clock(t, separator)
	t = math.max(0, math.floor(t or 0))
	return string.format('%02d%s%02d%s%02d', math.floor(t / 3600), separator,
		math.floor(t % 3600 / 60), separator, t % 60)
end

local function tracks(kind)
	local out = {}
	for _, t in ipairs(mp.get_property_native('track-list') or {}) do
		if t.type == kind then out[#out + 1] = t end
	end
	return out
end

local function track_label(t)
	local bits = {}
	if t.lang and t.lang ~= '' then bits[#bits + 1] = t.lang end
	if t.title and t.title ~= '' then bits[#bits + 1] = t.title end
	if t.codec and t.codec ~= '' then bits[#bits + 1] = t.codec end
	if t.forced then bits[#bits + 1] = 'forced' end
	if t.external then bits[#bits + 1] = 'external file' end
	return table.concat(bits, ' · ')
end

-- every track is a choice: `internal` is an ffmpeg stream of the source,
-- `external` a separate subtitle file, `none` keeps it out of the clip
local function choices(kind)
	local list = {{label = 'none', value = 'none'}}
	for _, t in ipairs(tracks(kind)) do
		if kind == 'sub' and t.external and t['external-filename'] then
			list[#list + 1] = {label = track_label(t), value = 'e:' .. t['external-filename'], file = t['external-filename']}
		elseif not t.external and t['ff-index'] then
			list[#list + 1] = {label = track_label(t), value = 'i:' .. t['ff-index'], index = t['ff-index']}
		end
	end
	return list
end

local function current_value(kind)
	for _, t in ipairs(tracks(kind)) do
		if t.selected then
			if kind == 'sub' and t.external and t['external-filename'] then
				return 'e:' .. t['external-filename']
			elseif not t.external and t['ff-index'] then
				return 'i:' .. t['ff-index']
			end
		end
	end
	return 'none'
end

local function chosen(kind)
	if not sel[kind] then
		local wanted = current_value(kind)
		for _, c in ipairs(choices(kind)) do
			if c.value == wanted then sel[kind] = c end
		end
		sel[kind] = sel[kind] or {label = 'none', value = 'none'}
	end
	return sel[kind]
end

local function cycle(kind)
	local list = choices(kind)
	local current = chosen(kind)
	local index = 1
	for i, c in ipairs(list) do
		if c.value == current.value then index = i end
	end
	sel[kind] = list[index % #list + 1]
end

-- reset when another file starts, the times and tracks mean nothing in a new one
mp.register_event('file-loaded', function()
	timings = {}
	sel = {}
end)

local function menu()
	local audio, subs = chosen('audio'), chosen('sub')
	local items = {
		{title = 'Start', hint = clock(timings.start or 0, ':'), value = 'start', keep_open = true},
		{title = 'End', hint = timings.stop and clock(timings.stop, ':') or 'end of file', value = 'end', keep_open = true},
		{title = 'Reset', value = 'reset', keep_open = true},
		{separator = true},
		{title = 'Output folder', hint = pretty_path(output_folder()), value = 'folder'},
		{title = 'Audio', hint = audio.label, value = 'audio', keep_open = true},
		{title = 'Subtitles', hint = subs.label, value = 'subs', keep_open = true},
		{separator = true},
		{title = 'Create clip', hint = 'lossless, mkv', value = 'create'},
	}
	return utils.format_json({
		type = 'clip',
		title = 'Clip',
		on_close = 'callback',
		callback = {script, 'menu-event'},
		items = items,
	})
end

local function update()
	mp.commandv('script-message-to', 'uosc', 'update-menu', menu())
end

local function set_start()
	timings.start = mp.get_property_number('time-pos')
	update()
end

local function set_end()
	timings.stop = mp.get_property_number('time-pos')
	update()
end

local function reset_timings()
	timings = {}
	update()
end

-- s, e and r work while the menu is open, like videoclip's did, and go away
-- with it so they keep their normal meaning otherwise
local keys_bound = false

local function bind_keys()
	if keys_bound then return end
	keys_bound = true
	mp.add_forced_key_binding('s', 'clip-start', set_start)
	mp.add_forced_key_binding('e', 'clip-end', set_end)
	mp.add_forced_key_binding('r', 'clip-reset', reset_timings)
end

local function unbind_keys()
	if not keys_bound then return end
	keys_bound = false
	mp.remove_key_binding('clip-start')
	mp.remove_key_binding('clip-end')
	mp.remove_key_binding('clip-reset')
end

local function open()
	-- the tracks are read from mpv on every open
	sel = {}
	bind_keys()
	mp.commandv('script-message-to', 'uosc', 'open-menu', menu())
end

local function normalize_path(path)
	path = path:gsub('/+$', '')
	return path ~= '' and path or '/'
end

local function parent_of(path)
	local parent = path:match('^(.*)/[^/]*$')
	return parent ~= '' and parent or '/'
end

-- the folder picker: the XDG shortcuts, the subfolders of where we are, and
-- "use this folder"
local function folder_menu()
	local items = {
		{title = 'Use this folder', hint = pretty_path(folder_current), value = 'use', bold = true},
		{title = 'Type a path', value = 'type'},
	}
	if folder_current ~= '/' then
		items[#items + 1] = {title = '..', hint = pretty_path(parent_of(folder_current)), value = 'up', keep_open = true}
	end
	items[#items + 1] = {separator = true}

	local seen = {}
	for _, pair in ipairs({
		{'Videos (XDG)', xdg.videos},
		{'Downloads (XDG)', xdg.download},
		{'Documents (XDG)', xdg.documents},
		{'Home', home},
	}) do
		local label, path = pair[1], pair[2]
		if path and path ~= '' and path ~= folder_current and not seen[path] then
			seen[path] = true
			local info = utils.file_info(path)
			if info and info.is_dir then
				items[#items + 1] = {title = label, hint = pretty_path(path), value = 'go:' .. path, keep_open = true}
			end
		end
	end
	items[#items + 1] = {separator = true}

	local shown = 0
	local dirs = utils.readdir(folder_current, 'dirs')
	if dirs then
		table.sort(dirs, function(a, b) return a:lower() < b:lower() end)
		for _, name in ipairs(dirs) do
			if name:sub(1, 1) ~= '.' then
				items[#items + 1] = {title = name, value = 'go:' .. folder_current .. '/' .. name, keep_open = true}
				shown = shown + 1
			end
		end
	end
	if shown == 0 then
		items[#items + 1] = {title = 'No folders here', selectable = false, muted = true, italic = true}
	end

	return utils.format_json({
		type = 'clip-folder',
		title = 'Clip folder',
		on_close = 'callback',
		callback = {script, 'folder-event'},
		items = items,
	})
end

local function update_folder()
	mp.commandv('script-message-to', 'uosc', 'update-menu', folder_menu())
end

local function open_folder()
	folder_current = normalize_path(output_folder())
	local info = utils.file_info(folder_current)
	if not info or not info.is_dir then folder_current = xdg.videos or home end
	mp.add_timeout(0.05, function()
		mp.commandv('script-message-to', 'uosc', 'open-menu', folder_menu())
	end)
end

local function ask_path()
	mp.add_timeout(0.05, function()
		local answered = false
		local function done()
			if answered then return end
			answered = true
			mp.add_timeout(0.05, function()
				mp.commandv('script-message-to', 'uosc', 'open-menu', folder_menu())
			end)
		end
		input.get({
			prompt = 'Output folder: ',
			default_text = folder_current,
			history_path = state_path('clip-paths'),
			submit = function(text)
				if answered then return end
				text = trim(text or '')
				if text ~= '' then
					local path = normalize_path(mp.command_native({'expand-path', text}))
					local info = utils.file_info(path)
					if info and info.is_dir then
						folder_current = path
					else
						notify('Clip: no folder ' .. text, 4)
					end
				end
				done()
			end,
			closed = done,
		})
	end)
end

mp.register_script_message('folder-event', function(json)
	local e = utils.parse_json(json) or {}
	if e.type == 'close' then
		mp.commandv('script-message-to', 'uosc', 'close-menu', 'clip-folder')
		if folder_typing then
			folder_typing = false
		else
			mp.add_timeout(0.05, open)
		end
		return
	end
	if e.type ~= 'activate' then return end
	if e.value == 'use' then
		remember_folder(folder_current)
	elseif e.value == 'up' then
		folder_current = parent_of(folder_current)
		update_folder()
	elseif e.value == 'type' then
		folder_typing = true
		ask_path()
	elseif e.value and e.value:sub(1, 3) == 'go:' then
		folder_current = normalize_path(e.value:sub(4))
		update_folder()
	end
end)

-- the frame-exact start is impossible without re-encoding, ffmpeg starts a
-- copied stream at the keyframe before the time; knowing it lets the external
-- subtitle file start at the same frame instead of drifting by the snap
local function keyframe_before(path, time)
	if time <= 0 or #tracks('video') == 0 then return time end
	local from = math.max(0, time - 60)
	local res = mp.command_native({
		name = 'subprocess', playback_only = false, capture_stdout = true, capture_stderr = true,
		args = {'ffprobe', '-v', 'error', '-select_streams', 'v:0', '-show_entries', 'packet=pts_time,flags',
			'-of', 'csv=p=0', '-read_intervals', from .. '%' .. time, path},
	})
	if not res or res.status ~= 0 then return time end
	local keyframe
	for line in ((res.stdout or '') .. '\n'):gmatch('([^\n]*)\n') do
		local pts, flags = line:match('^([%d%.%-]+),([^,]+)')
		if pts and flags:find('K') then keyframe = tonumber(pts) end
	end
	return keyframe or time
end

local function cut()
	local path = mp.get_property('path')
	if not path then
		notify('Clip: no file is playing', 4)
		return
	end
	local info = utils.file_info(path)
	if not info or info.is_dir then
		notify('Clip: only local files can be cut', 5)
		return
	end

	local start = timings.start or 0
	local duration = mp.get_property_number('duration') or 0
	local stop = timings.stop or duration
	if stop - start < 0.1 then
		notify('Clip: the end must be after the start', 5)
		return
	end

	local folder = output_folder()
	local made = mp.command_native({name = 'subprocess', args = {'mkdir', '-p', folder}, playback_only = false})
	if not made or made.status ~= 0 then
		notify('Clip: cannot create ' .. folder, 6)
		return
	end

	local _, name = utils.split_path(path)
	name = name:gsub('%.[^%.]+$', ''):gsub('/', '_'):gsub('\\', '_')
	local filename = o.filename_template
		:gsub('%%n', function() return name end)
		:gsub('%%s', function() return clock(start, '.') end)
		:gsub('%%e', function() return clock(stop, '.') end) .. '.mkv'
	local out = folder .. '/' .. filename

	local seek = keyframe_before(path, start)
	local args = {'ffmpeg', '-hide_banner', '-nostdin', '-loglevel', 'error', '-y', '-ss', tostring(seek), '-i', path}
	local maps = {}
	local video
	for _, t in ipairs(tracks('video')) do
		if not t.image and t['ff-index'] then
			video = t
			break
		end
	end
	if video then maps[#maps + 1] = '0:' .. video['ff-index'] end

	local audio = chosen('audio')
	if audio.value ~= 'none' then maps[#maps + 1] = '0:' .. audio.index end

	local subs = chosen('sub')
	if subs.value:sub(1, 2) == 'e:' then
		args[#args + 1] = '-ss'
		args[#args + 1] = tostring(seek)
		args[#args + 1] = '-i'
		args[#args + 1] = subs.file
		maps[#maps + 1] = '1:s:0'
	elseif subs.value ~= 'none' then
		maps[#maps + 1] = '0:' .. subs.index
	end
	-- attached fonts and the like, so ass subtitles keep their look
	maps[#maps + 1] = '0:t?'

	for _, m in ipairs(maps) do
		args[#args + 1] = '-map'
		args[#args + 1] = m
	end
	for _, a in ipairs({
		'-t', tostring(stop - seek),
		'-c', 'copy',
		'-map_metadata', '0',
		'-map_chapters', '-1',
		'-avoid_negative_ts', 'make_zero',
	}) do
		args[#args + 1] = a
	end
	if audio.value == 'none' then args[#args + 1] = '-an' end
	if subs.value == 'none' then args[#args + 1] = '-sn' end
	args[#args + 1] = out

	notify('Clip: cutting ' .. pretty_path(out), 9999)
	mp.command_native_async({
		name = 'subprocess', args = args, capture_stdout = true, capture_stderr = true, playback_only = false,
	}, function(success, res, err)
		if success and res and res.status == 0 then
			notify('Clip saved: ' .. pretty_path(out), 6)
		else
			notify('Clip: ffmpeg failed: ' .. error_text(res, err), 10)
		end
	end)
end

mp.register_script_message('menu-event', function(json)
	local e = utils.parse_json(json) or {}
	if e.type == 'close' then
		unbind_keys()
		-- with on_close='callback' uosc waits for the script to close it
		mp.commandv('script-message-to', 'uosc', 'close-menu', 'clip')
		return
	end
	if e.type ~= 'activate' then return end
	if e.value == 'start' then
		set_start()
	elseif e.value == 'end' then
		set_end()
	elseif e.value == 'reset' then
		reset_timings()
	elseif e.value == 'folder' then
		open_folder()
	elseif e.value == 'audio' then
		cycle('audio')
		update()
	elseif e.value == 'subs' then
		cycle('sub')
		update()
	elseif e.value == 'create' then
		cut()
	end
end)

mp.register_script_message('open', open)
mp.add_key_binding(o.key, 'menu', open)

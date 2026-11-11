-- clip: lossless cuts (c) in a uosc menu. the streams are copied, never
-- re-encoded, so the picture and the sound stay bit-identical. s and e take
-- the current time as the start and the end, a track can be picked for the
-- audio and the subtitles (or none of them), and the folder the clip goes to
-- is picked right in the menu too. the file is always an mkv, it holds any
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
local state_dir = mp.command_native({'expand-path', '~~state'})
local folder_file = state_dir .. '/clip-output'
local paths_file = state_dir .. '/clip-paths'
local timings = {}
local sel = {}

mp.command_native({name = 'subprocess', args = {'mkdir', '-p', state_dir}, playback_only = false})

local function trim(s) return (s:gsub('^%s+', ''):gsub('%s+$', '')) end

local function notify(msg, duration)
	mp.osd_message(msg, duration or 4)
end

local function error_text(res, err)
	local text = res and (res.stderr ~= '' and res.stderr or res.stdout) or err or 'unknown error'
	return trim(text):gsub('%s+', ' ')
end

-- the folder picked last time, else the config default
local function output_folder()
	local f = io.open(folder_file, 'r')
	local saved = f and trim(f:read('*a') or '')
	if f then f:close() end
	return mp.command_native({'expand-path', saved ~= '' and saved or o.output_folder})
end

local function remember_folder(path)
	local f = io.open(folder_file, 'w')
	if f then
		f:write(path .. '\n')
		f:close()
	end
end

local function pretty_path(path)
	local home = mp.command_native({'expand-path', '~'})
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
		callback = {script, 'menu-event'},
		items = items,
	})
end

local function update()
	mp.commandv('script-message-to', 'uosc', 'update-menu', menu())
end

local function open()
	mp.commandv('script-message-to', 'uosc', 'open-menu', menu())
end

local function ask_folder()
	-- the menu closes first, the console takes the keys
	mp.add_timeout(0.05, function()
		local answered = false
		local function done()
			if answered then return end
			answered = true
			-- closed cancels, it must not save what was typed
			open()
		end
		input.get({
			prompt = 'Output folder: ',
			default_text = output_folder(),
			history_path = paths_file,
			submit = function(text)
				if answered then return end
				text = trim(text or '')
				if text ~= '' then remember_folder(text) end
				done()
			end,
			closed = done,
		})
	end)
end

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
	if e.type ~= 'activate' then return end
	if e.value == 'start' then
		timings.start = mp.get_property_number('time-pos')
		update()
	elseif e.value == 'end' then
		timings.stop = mp.get_property_number('time-pos')
		update()
	elseif e.value == 'reset' then
		timings = {}
		update()
	elseif e.value == 'folder' then
		ask_folder()
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

-- find: a fuzzy finder over the video folders here (ctrl+p, like telescope's
-- find_files). it lists the files under `roots`, newest first, in a uosc
-- palette menu and filters them while you type: the letters only have to
-- come in order, word starts and runs rank higher, every word of the query
-- has to match, in the name or the folder. enter plays (autoload then makes
-- that folder the playlist), shift+enter queues. the list is kept for the
-- session and scanned again in the background on every open

local utils = require('mp.utils')

local o = {
	roots = '~/downloads,~/documents/videos,/media/outer-1',
	extensions = 'mkv,mp4,avi,webm,mov,m4v,ts,m2ts,wmv,flv,mpg,mpeg,ogv,3gp',
	-- rows in the menu, the best ones
	limit = 200,
}
require('mp.options').read_options(o, 'find')

local script = mp.get_script_name()
local utf8_char = '[%z\1-\127\194-\244][\128-\191]*'
local separators = {[' '] = true, ['/'] = true, ['.'] = true, ['_'] = true, ['-'] = true,
	['('] = true, [')'] = true, ['['] = true, [']'] = true}

local files -- {path, name, where, chars, starts, time}, newest first
local query = ''
local shown = false
local scanning = false

local function trim(s) return (s:gsub('^%s+', ''):gsub('%s+$', '')) end

-- йцукен -> qwerty, the same keys: "учз" typed on the wrong layout is "exp"
local qwerty = {}
do
	local latin, i = [[qwertyuiop[]asdfghjkl;'zxcvbnm,.`]], 0
	for c in ('йцукенгшщзхъфывапролджэячсмитьбюё'):gmatch(utf8_char) do
		i = i + 1
		qwerty[c] = latin:sub(i, i)
	end
end

-- ascii and cyrillic: А-П, Р-Я, Ё
local function lower(s)
	s = s:lower()
	s = s:gsub('\208([\144-\159])', function(c) return '\208' .. string.char(c:byte() + 32) end)
	s = s:gsub('\208([\160-\175])', function(c) return '\209' .. string.char(c:byte() - 32) end)
	return (s:gsub('\208\129', '\209\145'))
end

local function entry(path, time, root)
	local dir, name = utils.split_path(path)
	local rel = dir:sub(#root.path + 2):gsub('/$', '')
	local where = rel == '' and root.label or root.label .. '/' .. rel
	local chars, starts, prev = {}, {}, ' '
	for c in lower(name .. ' ' .. where):gmatch(utf8_char) do
		chars[#chars + 1] = c
		if separators[prev] then starts[#chars] = true end
		prev = c
	end
	return {path = path, name = name, where = where, chars = chars, starts = starts, time = time}
end

-- the best way the word's letters appear in order, nil when they don't
local function score(word, e)
	local c, starts, best = e.chars, e.starts, nil
	for i = 1, #c do
		if c[i] == word[1] then
			local s, pos, prev = 0, i, nil
			for k = 1, #word do
				while pos <= #c and c[pos] ~= word[k] do pos = pos + 1 end
				-- a later start can't fit the word either
				if pos > #c then return best end
				s = s + 1 + (starts[pos] and 2 or 0)
				if prev then s = s + (pos == prev + 1 and 3 or -math.min(pos - prev - 1, 4) * 0.25) end
				prev, pos = pos, pos + 1
			end
			if not best or s > best then best = s end
		end
	end
	return best
end

-- the words as typed, and again as the qwerty keys when that differs
local function word_sets()
	local typed, swapped, differs = {}, {}, false
	for w in lower(query):gmatch('%S+') do
		local a, b = {}, {}
		for c in w:gmatch(utf8_char) do
			a[#a + 1] = c
			b[#b + 1] = qwerty[c] or c
			differs = differs or qwerty[c] ~= nil
		end
		typed[#typed + 1], swapped[#swapped + 1] = a, b
	end
	return differs and {typed, swapped} or {typed}
end

local function total(words, e)
	local sum = 0
	for _, w in ipairs(words) do
		local s = score(w, e)
		if not s then return nil end
		sum = sum + s
	end
	return sum
end

local function results()
	local sets = word_sets()
	local out = {}
	for _, e in ipairs(files or {}) do
		local best
		for _, words in ipairs(sets) do
			local t = total(words, e)
			if t and (not best or t > best) then best = t end
		end
		if best then out[#out + 1] = {e = e, s = best} end
	end
	local words = sets[1]
	if #words > 0 then
		table.sort(out, function(a, b)
			if a.s ~= b.s then return a.s > b.s end
			return a.e.time > b.e.time
		end)
	end
	return out
end

local function menu()
	local items = {}
	if not files then
		items[1] = {title = 'Looking through the folders', icon = 'spinner', selectable = false, muted = true, align = 'center'}
	else
		local current = mp.get_property('path')
		for i, r in ipairs(results()) do
			if i > o.limit then break end
			items[i] = {title = r.e.name, hint = r.e.where, value = r.e.path, active = r.e.path == current}
		end
		if #items == 0 then
			items[1] = {title = 'Nothing found', selectable = false, muted = true, italic = true, align = 'center'}
		end
	end
	return utils.format_json({
		type = 'find',
		title = 'Find a file',
		search_style = 'palette',
		search_debounce = 30,
		on_search = 'callback',
		on_close = 'callback',
		callback = {script, 'menu-event'},
		items = items,
	})
end

local function update()
	if shown then mp.commandv('script-message-to', 'uosc', 'update-menu', menu()) end
end

local function scan()
	if scanning then return end
	local roots, args = {}, {'find'}
	for r in o.roots:gmatch('[^,]+') do
		local path = mp.command_native({'expand-path', trim(r)}):gsub('/$', '')
		local info = utils.file_info(path)
		if info and info.is_dir then
			roots[#roots + 1] = {path = path, label = path:match('([^/]+)$') or path}
			args[#args + 1] = path
		end
	end
	if #roots == 0 then
		files = {}
		return update()
	end
	-- hidden folders stay out, only the extensions, with the modification time
	for _, a in ipairs({'-mindepth', '1', '(', '-name', '.*', '-prune', ')', '-o', '-type', 'f', '('}) do
		args[#args + 1] = a
	end
	local first = true
	for ext in o.extensions:gmatch('[^,]+') do
		if not first then args[#args + 1] = '-o' end
		args[#args + 1] = '-iname'
		args[#args + 1] = '*.' .. trim(ext)
		first = false
	end
	for _, a in ipairs({')', '-printf', '%T@\t%p\n'}) do args[#args + 1] = a end

	scanning = true
	mp.command_native_async({
		name = 'subprocess', args = args, capture_stdout = true, capture_stderr = true, playback_only = false,
	}, function(_, res)
		scanning = false
		local list = {}
		for line in (res and res.stdout or ''):gmatch('[^\n]+') do
			local time, path = line:match('^([%d.]+)\t(.+)$')
			if path then
				for _, root in ipairs(roots) do
					if path:sub(1, #root.path + 1) == root.path .. '/' then
						list[#list + 1] = entry(path, tonumber(time), root)
						break
					end
				end
			end
		end
		table.sort(list, function(a, b) return a.time > b.time end)
		files = list
		update()
	end)
end

mp.register_script_message('menu-event', function(json)
	local e = utils.parse_json(json) or {}
	if e.type == 'search' then
		query = e.query or ''
		update()
	elseif e.type == 'activate' and e.value then
		if e.modifiers == 'shift' then
			mp.commandv('loadfile', e.value, 'append')
			mp.commandv('show-text', 'Queued: ' .. (e.value:match('([^/]+)$') or e.value), 2000)
		else
			mp.commandv('loadfile', e.value)
			mp.commandv('script-message-to', 'uosc', 'close-menu', 'find')
		end
	elseif e.type == 'close' then
		shown = false
	end
end)

mp.add_key_binding(nil, 'toggle', function()
	if shown then
		mp.commandv('script-message-to', 'uosc', 'close-menu', 'find')
		return
	end
	shown, query = true, ''
	mp.commandv('script-message-to', 'uosc', 'open-menu', menu())
	scan()
end)

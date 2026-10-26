-- keys: the hotkey cheat sheet, drawn like uosc's menus. the sizes, colors
-- and opacities come from script-opts/uosc.conf, so it follows the ui.
--
-- the rows are input.conf itself:
--   ## Name                        opens a section
--   KEY  command  # what it does   a row. #! (uosc menu) and #@ (inputevent)
--                                  parts are skipped, a binding with only a
--                                  #! title shows the title's last part
--   #? KEYS  what they do          a row for keys bound elsewhere (menus,
--                                  plugins): alternatives split by " / ",
--                                  two spaces before the text
-- a binding without a comment isn't shown. bindings of a section that say
-- the same thing share a row: "back 5 s  ← / h". g-g is the sequence g g.
--
-- / searches like vim and uosc's menus, enter keeps the result, esc drops
-- it. q, esc or ? close. other keys still reach mpv, so they can be tried

local assdraw = require('mp.assdraw')

local o = {
	-- at most, fewer when they'd have to shrink more to fit the window
	columns = 4,
	title = 'Hotkeys',
}
require('mp.options').read_options(o, 'keys')

local function round(n) return math.floor(n + 0.5) end
local function clamp(lo, n, hi) return math.max(lo, math.min(hi, n)) end
local function trim(s) return (s:gsub('^%s+', ''):gsub('%s+$', '')) end

-- uosc.conf -------------------------------------------------------------------

-- what the menus use, uosc's defaults until the file says otherwise
local ui = {
	scale = 1,
	scale_fullscreen = 1.3,
	font_scale = 1,
	menu_item_height = 36,
	menu_padding = 4,
	border_radius = 4,
	animation_duration = 100,
	font_bold = 'no',
	color = '',
	opacity = '',
}
local color = {foreground = 'ffffff', background = '000000', background_text = 'ffffff', curtain = '111111'}
local opacity = {menu = 1, curtain = 0.8}

do
	local path = mp.find_config_file('script-opts/uosc.conf')
	local file = path and io.open(path)
	if file then
		for line in file:lines() do
			local k, v = line:match('^%s*([%w_]+)%s*=%s*(.-)%s*$')
			if k and ui[k] ~= nil then
				ui[k] = type(ui[k]) == 'number' and (tonumber(v) or ui[k]) or v
			end
		end
		file:close()
	end
	for k, v in ui.color:gmatch('([%w_]+)=(%x%x%x%x%x%x)') do color[k] = v end
	for k, v in ui.opacity:gmatch('([%w_]+)=([%d.]+)') do opacity[k] = tonumber(v) end
	-- ass wants bgr
	for k, v in pairs(color) do color[k] = v:sub(5, 6) .. v:sub(3, 4) .. v:sub(1, 2) end
end

local fg, bg, bgt = color.foreground, color.background, color.background_text

-- input.conf ------------------------------------------------------------------

local names = {
	space = 'space', enter = 'enter', kp_enter = 'enter', esc = 'esc', tab = 'tab', bs = 'bksp',
	del = 'del', ins = 'ins', home = 'home', ['end'] = 'end', pgup = 'pgup', pgdwn = 'pgdn',
	left = '←', right = '→', up = '↑', down = '↓', sharp = '#', plus = '+',
	wheel_up = 'wheel ↑', wheel_down = 'wheel ↓', wheel_left = 'wheel ←', wheel_right = 'wheel →',
	mbtn_left = 'lmb', mbtn_right = 'rmb', mbtn_mid = 'mmb', mbtn_back = 'mb4', mbtn_forward = 'mb5',
	mouse_btn0 = 'lmb', mouse_btn1 = 'mmb', mouse_btn2 = 'rmb', mbtn_left_dbl = '2× lmb',
}
local mods = {shift = true, ctrl = true, alt = true, meta = true}

-- "Ctrl+LEFT" -> ctrl ←, "W" -> shift w, "g-g" -> g g: a keycap each,
-- modifiers dim
local function keycaps(key)
	local first, others = key:match('^(.-[^-])%-(.+)$')
	if first then
		local caps = keycaps(first)
		for _, c in ipairs(keycaps(others)) do caps[#caps + 1] = c end
		return caps
	end
	local caps, rest = {}, key
	while true do
		local m, r = rest:match('^([^+]+)%+(.+)$')
		if not (m and mods[m:lower()]) then break end
		caps[#caps + 1] = {t = m:lower(), mod = true}
		rest = r
	end
	local k = names[rest:lower()] or rest
	if k == rest and #k == 1 and k:match('%u') then
		if not (caps[1] and caps[1].t == 'shift') then caps[#caps + 1] = {t = 'shift', mod = true} end
		k = k:lower()
	elseif k == rest and k:match('^%u[%u%d_]+$') then
		k = k:lower()
	end
	caps[#caps + 1] = {t = k}
	return caps
end

-- what a binding's comment says it does, nil when it says nothing
local function describe(comment)
	local title
	for part in (comment .. '#'):gmatch('([^#]*)#') do
		part = trim(part)
		if part:sub(1, 1) == '!' or part:sub(1, 5) == 'menu:' then
			title = title or trim(part:gsub('^!', ''):gsub('^menu:', ''))
		elseif part ~= '' and part:sub(1, 1) ~= '@' then
			return part
		end
	end
	return title and trim(title:match('([^>]*)$'))
end

local function parse()
	local path = mp.get_property_native('input-conf', '')
	path = mp.command_native({'expand-path', path ~= '' and path or '~~/input.conf'})
	local file = io.open(path)
	if not file then return {} end

	local secs, sec = {}, nil
	local function add(key, what)
		if not sec then
			sec = {name = '', rows = {}}
			secs[#secs + 1] = sec
		end
		local row
		for _, r in ipairs(sec.rows) do if r.what == what then row = r end end
		if not row then
			row = {what = what, keys = {}, text = (sec.name .. ' ' .. what):lower()}
			sec.rows[#sec.rows + 1] = row
		end
		for _, k in ipairs(row.keys) do if k == key then return end end
		row.keys[#row.keys + 1] = key
		row.text = row.text .. ' ' .. key:lower()
	end

	for line in file:lines() do
		local head = line:match('^##%s+([^#].-)[%s#]*$')
		local doc_keys, doc_what = line:match('^#%?%s+(.-%S)%s%s+(%S.-)%s*$')
		if head then
			sec = nil
			for _, s in ipairs(secs) do if s.name == head then sec = s end end
			if not sec then
				sec = {name = head, rows = {}}
				secs[#secs + 1] = sec
			end
		elseif doc_keys then
			for key in (doc_keys .. ' / '):gmatch('(.-) / ') do add(trim(key), doc_what) end
		elseif not line:match('^%s*#') then
			local key, comment = line:match('^%s*(%S+)%s+[^#]*#(.*)$')
			local what = key and describe(comment)
			if what then add(key, what) end
		end
	end
	file:close()

	for _, s in ipairs(secs) do
		for _, r in ipairs(s.rows) do
			r.caps = {}
			for i, key in ipairs(r.keys) do
				if i > 1 then r.caps[#r.caps + 1] = {t = '/', sep = true} end
				for _, c in ipairs(keycaps(key)) do
					r.caps[#r.caps + 1] = c
					if not c.mod then r.text = r.text .. ' ' .. c.t end
				end
			end
		end
	end
	return secs
end

-- drawing ---------------------------------------------------------------------

local font = mp.get_property('options/osd-font', 'sans-serif')
local bold = ui.font_bold == 'yes'
local overlay = mp.create_osd_overlay('ass-events')
overlay.z = 2000

local function ass_escape(s)
	return (s:gsub('\\', '\\\239\187\191'):gsub('{', '\\{'):gsub('}', '\\}'):gsub('^ ', '\\h'))
end

local function alpha(op)
	-- clamped: an animation can overshoot, and %X dies on a negative
	return string.format('\\alpha&H%02X&', clamp(0, 255 - math.ceil(255 * op), 255))
end

local function rect(ass, ax, ay, bx, by, col, op, radius)
	ass:new_event()
	ass:append('{\\pos(0,0)\\rDefault\\an7\\blur0\\bord0\\shad0\\1c&H' .. col .. '&' .. alpha(op) .. '}')
	ass:draw_start()
	if radius and radius > 0 then ass:round_rect_cw(ax, ay, bx, by, radius) else ass:rect_cw(ax, ay, bx, by) end
	ass:draw_stop()
end

-- opts: size, color, opacity, bold, italic, font, clip
local function txt(ass, x, y, align, text, opts)
	ass:new_event()
	ass:append(string.format('{\\pos(%s,%s)\\rDefault\\an%d\\blur0\\bord0\\shad0\\q2\\fn%s\\fs%d\\b%d\\i%d\\1c&H%s&%s%s}%s',
		x, y, align, opts.font or font, opts.size, (opts.bold == nil and bold or opts.bold) and 1 or 0,
		opts.italic and 1 or 0, opts.color or bgt, alpha(opts.opacity or 1), opts.clip or '', text))
end

-- text width at font size 1: measured once by libass and kept
local width_of
do
	local probe = mp.create_osd_overlay('ass-events')
	probe.compute_bounds, probe.hidden = true, true
	local cache = {}
	width_of = function(text, is_bold)
		local id = (is_bold and 'b' or 'r') .. text
		if not cache[id] then
			-- in the window's own units, like uosc measures
			local w, h = mp.get_osd_size()
			probe.res_x, probe.res_y = math.max(w, 1000), math.max(h, 500)
			probe.data = string.format('{\\an7\\pos(0,0)\\rDefault\\bord0\\shad0\\q2\\fn%s\\fs40\\b%d}%s',
				font, is_bold and 1 or 0, ass_escape(text))
			local res = probe:update()
			cache[id] = res and res.x1 and res.x1 / 40 or #text * 0.6
		end
		return cache[id]
	end
end

-- state -----------------------------------------------------------------------

local secs = {}
local query = ''
local typing = false -- / is typing a search
local shown = false
local fade = 0 -- the whole sheet's opacity
local opened_at = 0
local tick -- the animation timer while something moves
local layout -- sizes for the current window, see relayout()

local function ease(p) return 1 - (1 - p) ^ 3 end

local function words()
	local out = {}
	for w in query:lower():gmatch('%S+') do out[#out + 1] = w end
	return out
end

local function filtered()
	local ws = words()
	if #ws == 0 then return secs end
	local out = {}
	for _, s in ipairs(secs) do
		local rows = {}
		for _, r in ipairs(s.rows) do
			local ok = true
			for _, w in ipairs(ws) do
				if not r.text:find(w, 1, true) then ok = false end
			end
			if ok then rows[#rows + 1] = r end
		end
		if #rows > 0 then out[#out + 1] = {name = s.name, rows = rows} end
	end
	return out
end

-- the sections into the columns in order, the tallest column as short as
-- it gets (the same as the quickshell keys menu)
local function split(list, k, height)
	local n = #list
	k = math.min(k, n)
	if n == 0 then return {} end
	local pre = {[0] = 0}
	for i = 1, n do pre[i] = pre[i - 1] + height(list[i]) end
	-- best[j][i]: the tallest column with the first i sections in j columns,
	-- cut[j][i]: where the last of them starts
	local best, cut = {{}}, {{}}
	for i = 0, n do best[1][i] = pre[i] end
	for j = 2, k do
		best[j], cut[j] = {}, {}
		for i = 0, n do
			best[j][i] = math.huge
			for m = j - 1, i do
				local h = math.max(best[j - 1][m], pre[i] - pre[m])
				if h < best[j][i] then best[j][i], cut[j][i] = h, m end
			end
		end
	end
	local cols, stop = {}, n
	for j = k, 1, -1 do
		local start = j > 1 and cut[j][stop] or 0
		local col = {}
		for i = start + 1, stop do col[#col + 1] = list[i] end
		table.insert(cols, 1, col)
		stop = start
	end
	return cols
end

local function sizes(scale)
	local s = {}
	s.item = round(ui.menu_item_height * scale)
	s.font = round(s.item * 0.48 * ui.font_scale)
	s.hint = s.font - 1
	s.pad = round(ui.menu_padding * scale)
	s.ipad = round((s.item - s.font) * 0.6)
	s.radius = ui.border_radius * scale
	s.line = math.max(1, round(scale))
	s.gap = round(2 * scale)
	s.cap_h = round(s.font * 1.15)
	s.cap_pad = round(s.font * 0.3)
	s.sec_gap = s.ipad
	return s
end

local function caps_width(s, caps)
	local w = 0
	for i, c in ipairs(caps) do
		if i > 1 then w = w + s.gap * 2 end
		w = w + width_of(c.t, bold) * s.hint + (c.sep and 0 or s.cap_pad * 2)
	end
	return w
end

local function sec_height(s, sec)
	return s.sec_gap + (sec.name ~= '' and s.item or 0) + #sec.rows * s.item
end

-- the panel's size from every row, so a search doesn't change it
local function relayout()
	local dims = mp.get_property_native('osd-dimensions')
	if not dims or dims.w <= 0 then return nil end
	local hidpi = mp.get_property_native('display-hidpi-scale', 1)
	local full = mp.get_property_native('fullscreen') or mp.get_property_native('window-maximized')
	local scale = hidpi * (full and ui.scale_fullscreen or ui.scale)

	local function measure(sc, cols)
		local s = sizes(sc)
		local col_w = width_of(o.title, false) * s.font
		for _, sec in ipairs(secs) do
			col_w = math.max(col_w, width_of(sec.name, true) * s.font)
			for _, r in ipairs(sec.rows) do
				r.what_w = width_of(r.what, bold)
				col_w = math.max(col_w, r.what_w * s.font + s.item + caps_width(s, r.caps))
			end
		end
		s.col_w = math.ceil(col_w + s.ipad * 2)
		s.cols = cols
		local body = 0
		for _, col in ipairs(split(secs, s.cols, function(sec) return sec_height(s, sec) end)) do
			local h = 0
			for _, sec in ipairs(col) do h = h + sec_height(s, sec) end
			body = math.max(body, h)
		end
		s.body_h = body + s.ipad
		s.head_h = s.item
		s.w = s.cols * s.col_w + (s.cols - 1) * s.line + s.pad * 2
		s.h = s.pad + s.head_h + s.pad + s.body_h + s.pad
		return s
	end

	-- the column count that needs the least shrinking, then the fewest.
	-- too big for the window: everything a bit smaller
	local s, fit, cols
	for c = 1, clamp(1, o.columns, math.max(1, #secs)) do
		local m = measure(scale, c)
		local f = math.min(1, dims.w * 0.96 / m.w, dims.h * 0.9 / m.h)
		if not fit or f > fit + 0.01 then s, fit, cols = m, f, c end
	end
	if fit < 1 then s = measure(scale * fit, cols) end
	s.dw, s.dh = dims.w, dims.h
	s.ax, s.ay = round((dims.w - s.w) / 2), round((dims.h - s.h) / 2)
	layout = s
	return s
end

local function render()
	local s = layout
	if not s then return end
	local ass = assdraw.ass_new()
	local now = mp.get_time()
	local moving = false

	-- curtain and panel, like uosc's menus
	rect(ass, 0, 0, s.dw, s.dh, color.curtain, opacity.curtain * fade)
	local ax, ay, bx, by = s.ax, s.ay, s.ax + s.w, s.ay + s.h
	rect(ass, ax, ay, bx, by, bg, opacity.menu * fade, s.radius > 0 and s.radius + s.pad or 0)

	-- the header is uosc's: the title, or while searching its search row,
	-- an icon and the query on the right
	local hax, hbx = ax + s.pad + round(s.ipad / 2), bx - s.pad - round(s.ipad / 2)
	local hay, hby = ay + s.pad, ay + s.pad + s.head_h
	local hcy = round((hay + hby) / 2)
	if typing or query ~= '' then
		local icon = round(s.font * 1.3)
		txt(ass, hax + icon / 2, hcy, 5, 'search', {
			font = 'MaterialIconsRound-Regular', size = icon, bold = false, color = fg, opacity = fade,
		})
		local field = string.format('\\clip(%d,%d,%d,%d)', hax + icon + s.ipad, hay, hbx, hby)
		if query ~= '' then
			txt(ass, hbx, hcy, 6, ass_escape(query) .. '\239\187\191', {size = s.font, opacity = fade, clip = field})
		else
			txt(ass, hbx, hcy, 6, 'type to search', {size = s.font, italic = true, opacity = 0.4 * fade, clip = field})
		end
		if typing then
			local half, thick = round(s.font * 0.6), round(s.font / 12)
			rect(ass, hbx + 1, hcy - half, hbx + 1 + thick, hcy + half, fg, fade)
		end
	else
		txt(ass, (hax + hbx) / 2, hcy, 5, ass_escape(o.title), {size = s.font, bold = true, opacity = fade})
	end
	rect(ass, ax, hby + s.pad - s.line, bx, hby + s.pad, fg, 0.2 * fade)

	-- the body: columns with a line between them, sections drop in one
	-- after another on open
	local top = hby + s.pad
	local list = filtered()
	local cols = split(list, s.cols, function(sec) return sec_height(s, sec) end)
	local order = 0
	for c = 1, s.cols do
		local cx = ax + s.pad + (c - 1) * (s.col_w + s.line)
		if c > 1 then rect(ass, cx - s.line, top + s.ipad, cx, by - s.pad - s.ipad, fg, 0.13 * fade) end
		local y = top
		for _, sec in ipairs(cols[c] or {}) do
			local p = 1
			if ui.animation_duration > 0 then
				local dur = ui.animation_duration * 1.5 / 1000
				p = clamp(0, (now - opened_at - order * 0.025) / dur, 1)
				if p < 1 then moving = true end
			end
			order = order + 1
			local op, dy = fade * ease(p), round((1 - ease(p)) * -s.item * 0.2)
			local lx, rx = cx + s.ipad, cx + s.col_w - s.ipad
			y = y + s.sec_gap
			if sec.name ~= '' then
				txt(ass, lx, y + dy + s.item / 2, 4, ass_escape(sec.name), {size = s.font, bold = true, opacity = 0.5 * op})
				y = y + s.item
			end
			for i, r in ipairs(sec.rows) do
				local cy = y + dy + s.item / 2
				-- keycaps from the right
				local x = rx
				for k = #r.caps, 1, -1 do
					local cap = r.caps[k]
					local w = width_of(cap.t, bold) * s.hint
					if cap.sep then
						txt(ass, x, cy, 6, ass_escape(cap.t), {size = s.hint, opacity = 0.5 * op})
						x = x - w
					else
						local cw = w + s.cap_pad * 2
						rect(ass, x - cw, cy - s.cap_h / 2, x, cy + s.cap_h / 2, fg, 0.12 * op, s.radius)
						txt(ass, x - cw / 2, cy, 5, ass_escape(cap.t), {size = s.hint, opacity = (cap.mod and 0.5 or 1) * op})
						x = x - cw
					end
					if k > 1 then x = x - s.gap * 2 end
				end
				local clip = string.format('\\clip(%d,%d,%d,%d)', lx, y, x - s.ipad, y + s.item)
				txt(ass, lx, cy, 4, ass_escape(r.what), {size = s.font, opacity = op, clip = clip})
				if i < #sec.rows then
					rect(ass, cx + s.ipad / 2, y + s.item - s.line, cx + s.col_w - s.ipad / 2, y + s.item, fg, 0.04 * op)
				end
				y = y + s.item
			end
		end
	end
	if #list == 0 then
		txt(ass, ax + s.w / 2, top + (by - top) / 2, 5, 'nothing found', {size = s.font, italic = true, opacity = 0.5 * fade})
	end

	overlay.res_x, overlay.res_y = s.dw, s.dh
	overlay.data = ass.text
	overlay:update()
	return moving
end

-- open / close ----------------------------------------------------------------

local close

local function animate(to, done)
	if tick then tick:kill() end
	local from, start = fade, mp.get_time()
	local dur = math.max(ui.animation_duration, 1) / 1000
	tick = mp.add_periodic_timer(1 / 60, function()
		local p = clamp(0, (mp.get_time() - start) / dur, 1)
		fade = from + (to - from) * ease(p)
		local moving = render()
		if p >= 1 and not moving then
			tick:kill()
			tick = nil
			if done then done() end
		end
	end)
end

local function set_query(q)
	query = q
	render()
end

local function type_char(e)
	if e.event == 'up' or not e.key_text then return end
	if query == '' and e.key_text == ' ' then return end
	set_query(query .. e.key_text)
end

-- while / is typing a search these keys are text, after it they reach mpv
local typing_binds = {
	{'ANY_UNICODE', type_char, {complex = true, repeatable = true}},
	{'BS', function()
		-- a whole utf-8 character
		set_query(query:gsub('[%z\1-\127\194-\244][\128-\191]*$', ''))
	end, {repeatable = true}},
	{'Ctrl+BS', function() set_query('') end},
	{'Ctrl+w', function() set_query('') end},
}

local function search(on, keep)
	typing = on
	for i, b in ipairs(typing_binds) do
		if on then mp.add_forced_key_binding(b[1], 'keys-type-' .. i, b[2], b[3])
		else mp.remove_key_binding('keys-type-' .. i) end
	end
	if not on and not keep then query = '' end
	render()
end

local function on_click()
	local m = mp.get_property_native('mouse-pos')
	local s = layout
	if not (m and s and m.x >= s.ax and m.x <= s.ax + s.w and m.y >= s.ay and m.y <= s.ay + s.h) then close() end
end

-- esc: drop the search, then close. enter: keep the search, then close
local binds = {
	{'ESC', function()
		if typing or query ~= '' then search(false) else close() end
	end},
	{'ENTER', function() if typing then search(false, true) else close() end end},
	{'KP_ENTER', function() if typing then search(false, true) else close() end end},
	{'/', function() search(true, true) end},
	{'q', function() close() end},
	{'MBTN_LEFT', on_click},
	{'MBTN_RIGHT', function() close() end},
}

local function open()
	secs = parse()
	query = ''
	if not relayout() then return end
	shown = true
	opened_at = mp.get_time()
	for i, b in ipairs(binds) do mp.add_forced_key_binding(b[1], 'keys-' .. i, b[2], b[3]) end
	animate(1)
end

close = function()
	if not shown then return end
	shown = false
	if typing then search(false, true) end
	for i = 1, #binds do mp.remove_key_binding('keys-' .. i) end
	animate(0, function()
		overlay:remove()
	end)
end

local function refit()
	if shown and relayout() then render() end
end

mp.observe_property('osd-dimensions', 'native', refit)
mp.observe_property('fullscreen', 'bool', refit)
mp.observe_property('window-maximized', 'bool', refit)
mp.observe_property('display-hidpi-scale', 'native', refit)

mp.add_key_binding(nil, 'toggle', function() if shown then close() else open() end end)

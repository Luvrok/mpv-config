-- layout: the keys work on the russian layout too. mpv binds characters,
-- so with йцукен active h arrives as р and nothing happens. this binds every
-- input.conf key once more at the same place on йцукен: р for h, Ctrl+р for
-- Ctrl+h, п-п for g-g, Ж for :, х for [. mpv runs them like input.conf lines
-- (key repeat, sequences).
--
-- keys that type ascii on both layouts can't be told apart: / is . on
-- йцукен and ? is , there, so those two keep their english meaning. F1 and
-- Ctrl+f do the same and work on both

-- us qwerty -> йцукен, the same physical keys
local qwerty = [[qwertyuiop[]asdfghjkl;'zxcvbnm,.`QWERTYUIOP{}ASDFGHJKL:"ZXCVBNM<>~]]
local jcuken = {
	'й', 'ц', 'у', 'к', 'е', 'н', 'г', 'ш', 'щ', 'з', 'х', 'ъ', 'ф', 'ы', 'в', 'а', 'п', 'р', 'о', 'л', 'д',
	'ж', 'э', 'я', 'ч', 'с', 'м', 'и', 'т', 'ь', 'б', 'ю', 'ё',
	'Й', 'Ц', 'У', 'К', 'Е', 'Н', 'Г', 'Ш', 'Щ', 'З', 'Х', 'Ъ', 'Ф', 'Ы', 'В', 'А', 'П', 'Р', 'О', 'Л', 'Д',
	'Ж', 'Э', 'Я', 'Ч', 'С', 'М', 'И', 'Т', 'Ь', 'Б', 'Ю', 'Ё',
}
local map = {}
for i = 1, #qwerty do map[qwerty:sub(i, i)] = jcuken[i] end

-- "Ctrl+h" -> "Ctrl+р", "g-l" -> "п-д", nil when nothing moves
local function translate(key)
	local first, rest = key:match('^(.-[^-])%-(.+)$')
	if first then
		local a, b = translate(first), translate(rest)
		if not (a or b) then return nil end
		return (a or first) .. '-' .. (b or rest)
	end
	local mods, base = key:match('^(.*%+)(.+)$')
	if not mods then mods, base = '', key end
	return map[base] and mods .. map[base] or nil
end

local lines, at = {}, {}
for _, b in ipairs(mp.get_property_native('input-bindings', {})) do
	-- input.conf's, not mpv's own weak defaults. a key bound twice keeps the
	-- later command, like in input.conf
	if b.section == 'default' and not b.is_weak then
		local key = translate(b.key)
		if key then
			at[key] = at[key] or #lines + 1
			lines[at[key]] = key .. ' ' .. b.cmd
		end
	end
end

mp.commandv('define-section', 'layout-ru', table.concat(lines, '\n'), 'force')
mp.commandv('enable-section', 'layout-ru', 'allow-hide-cursor+allow-vo-dragging')

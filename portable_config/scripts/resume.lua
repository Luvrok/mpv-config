-- resume: q saves where the file stopped, closing the window or killing mpv
-- does not (mpv.conf has save-position-on-quit=no). q at the end of a file
-- drops the position instead, so a finished one starts over next time

local function quit(save)
	mp.set_property_bool('save-position-on-quit', save)
	if not save then mp.command('delete-watch-later-config') end
	mp.command('quit')
end

mp.add_key_binding(nil, 'quit-save', function()
	local duration = mp.get_property_number('duration') or 0
	local position = mp.get_property_number('time-pos') or 0
	local at_end = mp.get_property_bool('eof-reached')
		or (duration > 0 and position >= duration - 1)
	quit(not at_end)
end)

-- resume: mpv.conf saves the position on every quit, so closing the window
-- (hyprland's killactive, the close button, pkill before suspend) resumes
-- like q does. with keep-open the end of a file is a position too, and the
-- next open would start there: at the end the saved position is dropped

local save = mp.get_property_bool('save-position-on-quit')

mp.observe_property('eof-reached', 'bool', function(_, eof)
	if not save then return end
	mp.set_property_bool('save-position-on-quit', not eof)
	if eof then mp.command('delete-watch-later-config') end
end)

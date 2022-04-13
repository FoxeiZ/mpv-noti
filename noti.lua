local utils = require 'mp.utils'
local mp = require 'mp'
local rep = string.rep
local substring = string.gsub


active = true
status = ''
filename = ''

id = 'mpv.'..utils.getpid()
socket = '/data/data/com.termux/files/home/bin/mpvsocket'
removeSocket = false

if mp.get_property('options/input-ipc-server') == '' then
    print('setup ipc server')
    mp.set_property("options/input-ipc-server", '/data/data/com.termux/files/home/.config/mpv/socket/'..id)
    socket = '/data/data/com.termux/files/home/.config/mpv/socket/'..id
    removeSocket = true
end


local function SecondsToClock(seconds)
    if seconds == nil or seconds <= 0 then
        return "00:00:00"
    else
        hours = string.format("%02.f", math.floor(seconds/3600))
        mins = string.format("%02.f", math.floor(seconds/60 - (hours*60)))
        secs = string.format("%02.f", math.floor(seconds - hours*3600 - mins *60))
        if hours == '00' then
            return mins..":"..secs
        else
            return hours..":"..mins..":"..secs
        end
    end
end


local function postNotification(title, content)
    command = {'termux-notification', '-i', id, '--type', 'media',
            '-t', title, '-c', content, '--ongoing',
            '--media-previous', 'echo playlist-prev | socat - '..socket,
            '--media-play', 'echo "cycle pause" | socat - '..socket,
            '--media-pause', 'echo "cycle pause" | socat - '..socket,
            '--media-next', 'echo playlist-next | socat - '..socket}

    if mp.get_property_bool("pause") then
        table.insert(command, '--icon')
        table.insert(command, 'pause')
    else
        table.insert(command, '--icon')
        table.insert(command, 'play_arrow')
    end


    utils.subprocess( { args=command, cancellable=true } )
    --utils.subprocess({args={'su', '-lp', '2000', '-c', "cmd notification post -S bigtext -t '"..title.."' mpv_playback '"..content.."'"}, cancellable = true })
end

function removeNotification()
    print('Removing notification...')
    utils.subprocess_detached({args={'termux-notification-remove', id}, cancellable = false })
end


-- main entry
function main(event)
    local songtitle = mp.get_property("media-title")
    local artist = mp.get_property_native("metadata/by-key/Artist")
    if songtitle ~= nil then
        filename = songtitle
    end

    if artist ~= nil then
        filename = ("%s - %s"):format(artist, filename)
    end

    -- just to make sure that we dont get nil or the script will fuckup    
    totalTime = mp.get_property("duration")
    while totalTime == nil do
        totalTime = mp.get_property("duration")
    end
    totalTime = tonumber(totalTime)
    format_totalTime = SecondsToClock(totalTime)

    postNotification(status..' '..filename, format_totalTime)
end


-- update status
local function pause_change(name, data)
    if active then
        main()
    end
end

local function mute_change(name, data)
    if data then
        status = status..'🔇'
    else
        status = substring(status, '🔇', '')
    end
    if active then
        main()
    end
end

local function loop_file_change(name, data)
    if data == 'inf' then
        status = status..'🔂'
    elseif data == 'no' then
        status = substring(status, '🔂', '')
    end
    if active then
        main()
    end
end

local function loop_playlist_change(name, data)
    if data == 'inf' then
        status = status..'🔁'
    elseif data == 'no' then
        status = substring(status, '🔁', '')
    end
    if active then
        main()
    end
end

local function title_change(name, data)
    if active then
        main()
    end
end

--status update function
function enable_update_status()
    mp.observe_property('mute', 'bool', mute_change)
    mp.observe_property('pause', 'bool', pause_change)
    mp.observe_property('media-title', 'string', title_change)
    mp.observe_property('loop-file', 'string', loop_file_change)
    mp.observe_property('loop-playlist', 'string', loop_playlist_change)
end

function disable_update_status()
    mp.unobserve_property(mute_change)
    mp.unobserve_property(pause_change)
    mp.unobserve_property(title_change)
    mp.unobserve_property(loop_file_change)
    mp.unobserve_property(loop_playlist_change)
end

-- register events to mpv
local function init(event)
    enable_update_status()
    main(event)
end

function toggle()
    active = not active

    if active then
        mp.register_event("file-loaded", init)
        enable_update_status()
        main()
    else
        mp.unregister_event(init)
        disable_update_status()
        removeNotification()
    end
    print('Toggle for noti:', active)
end

mp.register_event("file-loaded", init)
mp.register_event("end-file", disable_update_status)
mp.add_key_binding("y", "noti_toggle", toggle)
mp.register_event("shutdown",
    function()
        removeNotification()
        disable_update_status()
        if removeSocket then
            print('Removing socket...')
            os.remove(socket)
        end
    end
)

--softcut buffer regions
local reg = {}
reg.blank = warden.divide(warden.buffer_stereo, 2)
reg.rec = warden.subloop(reg.blank)
reg.play = warden.subloop(reg.rec)

-- softcut utilities
local sc = {
    setup = function()
        audio.level_cut(1.0)
        audio.level_adc_cut(1)
        audio.level_eng_cut(1)

        for i = 1, 4 do
            softcut.enabled(i, 1)
            softcut.rec(i, 1)
            softcut.loop(i, 1)
            softcut.level_slew_time(i, 0.25)
            softcut.rate(i, 1)
        end
        for i = 1, 2 do
            local l, r = i*2 - 1, i*2

            softcut.pan(l, -1)
            softcut.pan(r, 1)
            softcut.level_input_cut(1, r, 1)
            softcut.level_input_cut(2, r, 0)
            softcut.level_input_cut(1, l, 0)
            softcut.level_input_cut(2, l, 1)
            
            softcut.phase_quant(i*2, 1/25)
        end

        softcut.event_phase(function(i, ph)
            if i == 2 then gfx.wrms:set_phase(1, ph) 
            elseif i == 4 then 
                gfx.wrms:set_phase(2, ph)
                gfx.wrms:action()
            end
        end)

        softcut.poll_start_phase()
    end,
    stereo = function(command, pair, ...)
        local off = (pair - 1) * 2
        for i = 1, 2 do
            softcut[command](off + i, ...)
        end
    end,
    lvlmx = {
        {
            vol = 1, send = 1, pan = 0,
            update = function(s)
                softcut.level_cut_cut(1, 3, s.send * s.vol)
                softcut.level_cut_cut(2, 4, s.send * s.vol)
            end
        }, {
            vol = 1, send = 0, pan = 0,
            update = function(s)
                softcut.level_cut_cut(3, 1, s.send * s.vol)
                softcut.level_cut_cut(4, 2, s.send * s.vol)
            end
        },
        update = function(s, n)
            local v, p = s[n].vol, s[n].pan
            local off = (pair - 1) * 2
            softcut.level(off + 1, v * ((p > 0) and 1 - p or 1))
            softcut.level(off + 2, v * ((p < 0) and 1 - p or 1))
            s[n]:update()
        end
    },
    recmx = {
        { rec = 1 },
        { rec = 0 },
        update = function(s, n)
            sc.stereo('rec_level', n, s[n].rec)
        end
    },
    oldmx = {
        { old = 0.5, mode = 'ping-pong' },
        { old = 1, mode = 'overdub' },
        update = function(s, n)
            local off = n == 1 and 0 or 2
            if mode == 'overdub' then
                sc.stereo('pre_level', n, s.old)
                softcut.level_cut_cut(1 + off, 2 + off, 0)
                softcut.level_cut_cut(2 + off, 1 + off, 0)
            else
                sc.stereo('pre_level', n, 0)
                if mode == 'ping-pong' then
                    softcut.level_cut_cut(1 + off, 2 + off, s.old)
                    softcut.level_cut_cut(2 + off, 1 + off, s.old)
                else
                    softcut.level_cut_cut(1 + off, 1 + off, s.old)
                    softcut.level_cut_cut(2 + off, 2 + off, s.old)
                end
            end
        end
    },
    mod = {  
        { rate = 0, mul = 0, phase = 0,
            shape = function(p) return math.sin(2 * math.pi * p) end
            action = function(v) for i = 1,2 do
                sc.ratemx[i].mod = v; sc.ratemx:update(i)
            end end
        },
        { rate = 0, mul = 0, phase = 0,
            shape = function(p) return math.sin(2 * math.pi * p) end
            action = function(v) end
        },
        quant = 0.01, 
        init = function(s, n)
            s[n].clock = clock.run(function()
                clock.sleep(s.quant)

                local T = 1/s[n].rate
                local d = s.quant / T
                s[n].phase = s[n].phase + d
                while s[n].phase > 1 do s[n].phase = s[n].phase - 1 end

                s[n].action(s[n].shape(s[n].phase) * s[n].mul)
            end)
        end
    },
    ratemx = {
        { oct = 1, bnd = 1, mod = 0, dir = 1, rate = 0 },
        { oct = 1, bnd = 1, mod = 0, dir = -1, rate = 0 },
        update = function(s, n)
            s[n].rate = s[n].oct * 2^(s[n].bnd - 1) * 2^s[n].mod * s[n].dir
            sc.stereo('rate', n, s[n].rate)
        end
    },
    slew = function(n, t)
        local st = (2 + (math.random() * 0.5)) * t 
        sc.stereo('rate_slew_time', n, st)
        return st
    end,
    input = function(pair, inn, chan) return function(v) 
        local off = (pair - 1) * 2
        local vc = (chan - 1) + off
        softcut.level_input_cut(inn, vc, v)
    end end,
    voice = {
        { reg = 1, reg_name = 'play' },
        { reg = 2, reg_name = 'rec' },
        reg = function(s, pair, name) 
            name = name or s[pair].reg_name
            return reg[name][s[pair].reg] 
        end
    },
    punch_in = {
        quant = 0.01,
        { recording = false, recorded = true, t = 0, clock = nil },
        { recording = false, recorded = false, t = 0, clock = nil },
        toggle = function(s, pair, v)
            local i = sc.voice[pair].reg

            if s[i].recorded then
                sc.recmx[pair].rec = v; sc.recmx:update(pair)
            elseif v == 1 then
                sc.recmx[pair].rec = 1; sc.recmx:update(pair)
                sc.stereo('play', pair, 1)

                reg.rec[i]:set_length(1, 'fraction')
                reg.play[i]:set_length(1, 'fraction')

                s[i].clock = clock.run(function()
                    clock.sleep(s.quant)
                    s[i].t = s[i].t + (s.quant * sc.ratemx[pair].rate)
                end)

                s[i].recording = true
            elseif s[i].recording then
                sc.recmx[pair].rec = 0; sc.recmx:update(pair)

                reg.rec[i]:set_length(s[i].t)
                reg.play[i]:set_length(1, 'fraction')

                clock.cancel(s[i].clock)
                s[i].recorded = true
                s[i].recording = false
                s[i].t = 0

                gfx.wrms:wake(i)
            end
        end,
        clear = function(s, pair)
            sc.recmx[pair].rec = 0; sc.recmx:update(pair)

            local i = sc.voice[pair].reg
            reg.rec[i]:clear()

            clock.cancel(s[i].clock)
            s[i].recorded = false
            s[i].recording = false
            s[i].t = 0
        end
    }
}

local segs = function()
  ret = {}
  
  for i = 1, 24 do
    ret[i] = false
  end
  
  return ret
end

--screen graphics
local mar, mul = 2, 29
local gfx = {
    pos = { 
        x = {
            [1] = { mar, mar + mul },
            [1.5] = mar + mul*1.5,
            [2] = { mar + mul*2, mar + mul*3 }
        }, 
        y = {
            enc = 46,
            key = 46 + 10
        }
    },
    wrms = {
        phase = { 0, 0 },
        phase_abs = { 0, 0 },
        set_phase = function(s, n, v)
            --[[
            s.phase[n] = (
                (v - sc.voice:reg(n):get_start('seconds', 'absolute')) 
                / sc.voice:reg(n):get_length('seconds')
            )
            ]]
            s.phase_abs[n] = v
            s.phase[n] = sc.voice:reg(n):phase_relative(v, 'fraction')
        end,
        action = function() end,
        draw = function()
            local s = gfx.wrms

            --feed indicators
            screen.level(math.floor(sc.lvlmx[1].send * 4))
            screen.pixel(42, 23)
            screen.pixel(43, 24)
            screen.pixel(42, 25)
            screen.fill()
          
            screen.level(math.floor(sc.lvlmx[2].send * 4))
            screen.pixel(54, 23)
            screen.pixel(53, 24)
            screen.pixel(54, 25)
            screen.fill()
          
            for i = 1,2 do
                local left = 2 + (i-1) * 58
                local top = 34
                local width = 44
                local r = sc.voice:reg(i)
                local rrec = sc.voice:reg(i, 'rec')
                
                --phase
                screen.level(2)
                if not punch_in.recording then
                    screen.pixel(left + width * r:get_start('fraction'), top) --loop start
                    screen.fill()
                end
                if punch_in.recorded then
                    screen.pixel(left + width * r:get_end('fraction'), top) --loop end
                    screen.fill()
                end
        
                screen.level(6 + 10 * sc.recmx[i].rec)
                if not punch_in.recorded then 
                    -- rec line
                    if punch_in.recording then
                        screen.move(left + width*r:get_start('fraction'), top + 1)
                        screen.line(1 + left + width*s.phase[i], top + 1)
                        screen.stroke()
                    end
                else
                    screen.pixel(left + width*s.phase[i], top) -- loop point
                    screen.fill()
                end
        
                --fun wrm animaions
                local top = 18
                local width = 24
                local lowamp = 0.5
                local highamp = 1.75
        
                screen.level(math.floor(sc.lvlmx[i].vol * 10))

                local width = util.linexp(0, rrec:get_length(), 0.01, width, r:get_length() + 4.125)
                for j = 1, width do
                    local amp = 
                        s.segment_awake[i][j] 
                        and 
                            math.sin(
                                (
                                    (s.phase_abs[i] - r:get_start())*(i==1 and 1 or 2) 
                                    / (r:get_end() - r:get_start(i)) + j/width
                                )
                                * (i == 1 and 2 or 4) * math.pi
                            ) * util.linlin(
                                1, width / 2, lowamp, highamp + mod[i].mul, 
                                j < (width / 2) and j or width - j
                            ) 
                            - 0.75*util.linlin(
                                1, width / 2, lowamp, highamp + mod[i].mul, 
                                j < (width / 2) and j or width - j
                            ) - (
                                util.linexp(0, 1, 0.5, 6, j/width) 
                                * (ratemx[i].bnd - 1)
                            ) 
                        or 0      
                   
                    local x = left - (r:get_start()) / (r:get_length()) * (width - 44)
                
                    screen.pixel(x - 1 + j, top + amp)
                end
                screen.fill()
            end
        end,
        sleep = function(s, n) s.sleep_index[n] = 24 end,
        wake = function(s, n) s.sleep_index[n] = 24 end,
        segment_awake = { segs(), segs() },
        sleep_index = { 24, 24 },
    }   
}

gfx.wrms.sleep_clock = clock.run(function()
    local s = gfx.wrms
    while true do
        clock.sleep(1/150)
        for i = 1,2 do
            local si = s.sleep_index[i]
            if si > 0 and si <= 24 then
                s.segment_awake[i][math.floor(si)] = sc.punch_in[i].recorded
                s.sleep_index[i] = si + (0.5 * sc.punch_in[i].recorded and -1 or -2)
            end
        end
    end
end)

--param utilities
local param = {
    mix = function()
        params:add_seperator('mix')
        for i = 1,2 do
            params:add_control("in L > wrm " .. i .. "  L", "in L > wrm " .. i .. "  L", controlspec.new(0,1,'lin',0,1,''))
            params:set_action("in L > wrm " .. i .. "  L", sc.input(i, 1, 1))

            params:add_control("in L > wrm " .. i .. "  R", "in L > wrm " .. i .. "  R", controlspec.new(0,1,'lin',0,0,''))
            params:set_action("in L > wrm " .. i .. "  R", sc.input(i, 1, 2))
            
            params:add_control("in R > wrm " .. i .. "  R", "in R > wrm " .. i .. "  R", controlspec.new(0,1,'lin',0,1,''))
            params:set_action("in R > wrm " .. i .. "  R", sc.input(i, 2, 2))

            params:add_control("in R > wrm " .. i .. "  L", "in R > wrm " .. i .. "  L", controlspec.new(0,1,'lin',0,0,''))
            params:set_action("in R > wrm " .. i .. "  L", sc.input(i, 2, 1))

            params:add_control("wrm " .. i .. " pan", "wrm " .. i .. " pan", controlspec.PAN)
            params:set_action("wrm " .. i .. " pan", function(v) 
                sc.lvlmx[i].pan = v 
                sc.lvlmx:update(i)
            end)
        end
        params:add_seperator('wrms')
    end,
    filter = function(i)
        params:add {
            type = 'control', id = 'f', 
            controlspec = cs.new(50,5000,'exp',0,5000,'hz'),
            action = function(v) 
                sc.stereo('post_filter_fc', i, v) 
                redraw()
            end
        }
        params:add {
            type = 'control', id = 'q',
            controlspec = cs.RQ,
            action = function(v) 
                sc.stereo('post_filter_rq', i, v) 
                redraw()
            end
        }
        local options = { 'lp', 'bp', 'hp' } 
        params:add {
            type = 'option', id = 'filter type',
            options = options,
            action = function(v)
                for _,k in ipairs(options) do stereo('post_filter_'..k, i, 0) end
                stereo('post_filter_'..options[v], i, 1)
                redraw()
            end
        }
    end,
    _control = function(id, o)
        return _txt.enc.control {
            label = id,
            controlspec = params:lookup_param(id).controlspec,
            value = function() return params:get(id) end,
            action = function(s, v) params:set(id, v) end
        } :merge(o)
    end,
    _icontrol = function(label, i, o)
        return _txt.enc.control {
            label = label,
            controlspec = params:lookup_param(label ..' '..i).controlspec,
            value = function() return params:get(label ..' '..i) end,
            action = function(s, v) params:set(label ..' '..i, v) end
        } :merge(o)
    end
}

return sc, gfx, param

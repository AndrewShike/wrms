--TODO
--persistence 
--  paramset
--  all preset data
--  region lengths
--  clear punched in loops, 
--  reset all pitch data
--add 'in mode' - mono, stereo
--tp: display note name (nest)
--punch-in varispeed (cartographer -> rate_query)
--s: small length bugs (cartographer) (add delta_startend)
--gfx = _screen { } when available
--pan: map input/output based on record state


--cartographer hax
Slice.skew = 0

function Slice:update()
    --re-clamp start/end
    self.startend[1] = util.clamp(self.startend[1], self.bounds[1], self.bounds[2])
    self.startend[2] = util.clamp(self.startend[2], self.startend[1], self.bounds[2])

    local b = self.buffer
    for i,v in ipairs(self.voices) do
        softcut.loop_start(v, self.startend[1])
        softcut.loop_end(v, 
            self.startend[2]
            + (self.skew)*(i==1 and 0 or -1)
        )
        softcut.buffer(v, b[(i - 1)%(#b) + 1])
    end

    --propagate downward
    for i,v in ipairs(self.children) do
        v:update()
    end
end

--softcut buffer regions
local reg = {}
reg.blank = cartographer.divide(cartographer.buffer_stereo, 2)
reg.rec = cartographer.subloop(reg.blank)
reg.play = cartographer.subloop(reg.rec, 2)

-- softcut utilities
local sc = {
    phase = { 0, 0 },
    phase_abs = { 0, 0 },
    set_phase = function(s, n, v)
        s.phase_abs[n] = v
        s.phase[n] = reg.rec:phase_relative(n*2, v, 'fraction')
    end,
    setup = function()
        audio.level_cut(1.0)
        audio.level_adc_cut(1)
        audio.level_eng_cut(1)

        for i = 1, 4 do
            softcut.enable(i, 1)
            softcut.rec(i, 1)
            softcut.loop(i, 1)
            softcut.level_slew_time(i, 0.1)
            softcut.recpre_slew_time(i, 0.1)
            softcut.rate(i, 1)
            softcut.post_filter_dry(i, 0)
        end
        for i = 1, 2 do
            local l, r = i*2 - 1, i*2

            softcut.pan(l, -1)
            softcut.pan(r, 1)
            softcut.level_input_cut(1, r, 1)
            softcut.level_input_cut(2, r, 0)
            softcut.level_input_cut(1, l, 0)
            softcut.level_input_cut(2, l, 1)
            
            softcut.phase_quant(i*2 - 1, 1/60)
            sc.slew(i, 0.2)
        end

        local function e(i, ph)
            if i == 1 then sc:set_phase(1, ph) 
            elseif i == 3 then 
                sc:set_phase(2, ph)
                redraw()
            end
        end

        softcut.event_phase(e)
        softcut.poll_start_phase()
    end,
    scoot = function()
        reg.play:position(2, 0)
        reg.play:position(4, 0)
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
            local off = (n - 1) * 2
            softcut.level(off + 1, v * ((p > 0) and 1 - p or 1))
            softcut.level(off + 2, v * ((p < 0) and 1 + p or 1))
            s[n]:update()
        end
    },
    oldmx = {
        { old = 0.5, mode = 'ping-pong', rec = 1 },
        { old = 1, mode = 'overdub', rec = 0 },
        update = function(s, n)
            local off = n == 1 and 0 or 2
            local mode = s[n].mode

            sc.stereo('rec_level', n, s[n].rec)
            if s[n].rec == 0 then
                sc.stereo('pre_level', n, 1)
            else
                if mode == 'overdub' then
                    sc.stereo('pre_level', n, s[n].old)
                    softcut.level_cut_cut(1 + off, 2 + off, 0)
                    softcut.level_cut_cut(2 + off, 1 + off, 0)
                else
                    sc.stereo('pre_level', n, 0)
                    if mode == 'ping-pong' then
                        softcut.level_cut_cut(1 + off, 2 + off, s[n].old)
                        softcut.level_cut_cut(2 + off, 1 + off, s[n].old)
                    else
                        softcut.level_cut_cut(1 + off, 1 + off, s[n].old)
                        softcut.level_cut_cut(2 + off, 2 + off, s[n].old)
                    end
                end
            end
        end
    },
    mod = {  
        { rate = 0.4, mul = 0, phase = 0,
            shape = function(p) return math.sin(2 * math.pi * p) end,
            action = function(v) for i = 1,2 do
                sc.ratemx[i].mod = v; sc.ratemx:update(i)
            end end
        },
        quant = 0.01, 
        init = function(s, n)
            s[n].clock = clock.run(function()
                while true do
                    clock.sleep(s.quant)

                    local T = 1/s[n].rate
                    local d = s.quant / T
                    s[n].phase = s[n].phase + d
                    while s[n].phase > 1 do s[n].phase = s[n].phase - 1 end

                    s[n].action(s[n].shape(s[n].phase) * s[n].mul)
                end
            end)
        end
    },
    ratemx = {
        { oct = 1, bnd = 1, bndw = 0, mod = 0, dir = 1, rate = 0 },
        { oct = 1, bnd = 1, bndw = 0, mod = 0, dir = 1, rate = 0 },
        update = function(s, n)
            s[n].rate = 2^s[n].oct * 2^(s[n].bnd - 1) * 2^s[n].bndw * (1 + s[n].mod) * s[n].dir
            sc.stereo('rate', n, s[n].rate)
        end
    },
    slew = function(n, t)
        local st = (2 + (math.random() * 0.5)) * (t or 0)
        sc.stereo('rate_slew_time', n, st)
        return st
    end,
    inmx = {
        { vol = 1, pan = 0 },
        { vol = 1, pan = 0 },
        update = function(s, n)
            local v, p = s[n].vol, s[n].pan
            local off = (n - 1) * 2
            softcut.level_input_cut(1, off + 1, v * ((p > 0) and 1 - p or 1))
            softcut.level_input_cut(2, off + 1, 0)
            softcut.level_input_cut(2, off + 2, v * ((p < 0) and 1 + p or 1))
            softcut.level_input_cut(1, off + 2, 0)
        end
    },
    buf = {
        1, 2, -- [pair] = buf
        assign = function(s, pair, buf, slice)
            local off = (pair - 1) * 2
            s[pair] = buf
            cartographer.assign(reg.play[buf][slice], 1 + off, 2 + off)

            wrms.preset:set((s[1]-1) + (s[2]-1)*2)
        end
    },
    punch_in = {
        quant = 0.01,
        delay_size = 4,
        { recording = false, recorded = false, big = true, play = 0, t = 0, clock = nil },
        { recording = false, recorded = false, big = false, play = 0, t = 0, clock = nil },
        update_play = function(s, pair)
            sc.stereo('play', pair, s[pair].play)
        end,
        toggle = function(s, pair, v) --only use when pair==2 and voice[2]==2
            local i = pair * 2

            if s[pair].recorded then
                sc.oldmx[pair].rec = v; sc.oldmx:update(pair)
            elseif v == 1 then
                sc.oldmx[pair].rec = 1; sc.oldmx:update(pair)
                s[pair].play = 1; s:update_play(pair)

                -- set quant to sc.ratemx.rate * s.quant
                reg.blank:set_length(i, 16777216 / 48000 / 2)
                reg.rec:punch_in(i)

                s[pair].recording = true
            elseif s[pair].recording then
                sc.oldmx[pair].rec = 0; sc.oldmx:update(pair)
            
                reg.rec:punch_out(i)

                s[pair].recorded = true
                s[pair].big = true
                s[pair].recording = false

                wrms.gfx:wake(pair)
            end
        end,
        manual = function(s, pair)
            if not s[pair].recorded then
                reg.blank[pair]:set_length(s.delay_size)

                sc.oldmx[pair].rec = 1; sc.oldmx:update(pair)
                s[pair].play = 1; s:update_play(pair)

                s[pair].recorded = true
                wrms.gfx:wake(pair)
            end
        end,
        clear = function(s, pair)
            local i = pair * 2

            s[pair].play = 0; s:update_play(pair)

            reg.rec:position(i, 0)
            reg.rec:clear(i)
            reg.rec:punch_out(i)

            s[pair].recorded = false
            s[pair].recording = false
            s[pair].big = false

            reg.rec:expand(i)
            for i,v in ipairs(reg.rec:get_slice(i).children) do
                v:set_length(0)
            end
                
            wrms.gfx:sleep(pair)

            --[[
            sc.ratemx[pair].oct = 1
            sc.ratemx[pair].dir = 1
            sc.ratemx:update(pair)
            --]]
        end
    }
}

return sc, reg

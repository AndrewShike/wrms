--  _       ___________ ___  _____ 
-- | | /| / / ___/ __ `__ \/ ___/  
-- | |/ |/ / /  / / / / / (__  )   
-- |__/|__/_/  /_/ /_/ /_/____/    
--
-- dual asyncronous 
-- time-wigglers / echo loopers
--
-- version 2.0.0 @andrew
-- default template
-- https://llllllll.co/t/wrms
--
-- two wrms (stereo loops), 
-- similar in function but each 
-- with thier own quirks + 
-- abilities
-- 
-- E1 up top changes which page 
-- is displayed. pages contain 
-- controls, mapped to norns’ 
-- lower keys and encoders. 
-- the location of the control 
-- shows which wrm will be 
-- affected. 

function r() norns.script.load(norns.script.state) end

include 'wrms/lib/nest/core'
include 'wrms/lib/nest/norns'
include 'wrms/lib/nest/txt'
cartographer = include 'wrms/lib/cartographer/cartographer'
cs = require 'controlspec'

local sc, gfx, param, reg = include 'wrms/lib/wrms'

--params
param.mix()
for i = 1,2 do 
    params:add {
        type = 'control',
        id = 'vol ' .. i,
        controlspec = cs.def { default = 1, max = 2 },
        action = function(v)
            sc.lvlmx[i].vol = v
            sc.lvlmx:update(i)
            --redraw()
        end
    }
    params:add {
        type = 'control',
        id = 'old ' .. i,
        controlspec = cs.def { default = i==1 and 0.5 or 1 },
        action = function(v)
            sc.oldmx[i].old = v
            sc.oldmx:update(i)
            --redraw()
        end
    }
    local options = { 'overdub', 'feedback', 'ping-pong' } 
    params:add {
        type = 'option',
        id = 'old mode ' .. i,
        options = options,
        action = function(v)
            sc.oldmx[i].mode = options[v]
            sc.oldmx:update(i)
        end
    }
end
params:add {
    type = 'binary',
    behavior = 'toggle',
    id = 'rec 1', default = 1,
    action = function(v)
        sc.oldmx[1].rec = v; sc.oldmx:update(1)
        --redraw()
    end
}
params:add {
    type = 'binary',
    behavior = 'trigger',
    id = 'clear 1',
    action = function()
        params:set('rec 1', 0)
        reg.rec:clear(1)
    end
}
params:add {
    type = 'binary',
    behavior = 'toggle',
    id = 'rec 2',
    action = function(v)
        if sc.buf[2]==2 then
            sc.punch_in:toggle(2, v)
        else
            -- regular record toggle probably
        end

        --sc.voice:reg(1):update_voice(1, 2)
        --sc.voice:reg(2):update_voice(3, 4)

        --redraw()
    end
}
params:add {
    type = 'binary',
    behavior = 'trigger',
    id = 'clear 2',
    action = function()
        params:set('rec 2', 0)

        if sc.buf[2]==2 then
            sc.punch_in:clear(2)
        else
        end

        --sc.voice:reg(1):update_voice(1, 2)
        --sc.voice:reg(2):update_voice(3, 4)
    end
}
params:add {
    type = 'control', id = 'bnd',
    controlspec = cs.def { default = 1, min = 1, max = 2 },
    action = function(v)
        sc.ratemx[1].bnd = v
        sc.ratemx:update(1)
        --redraw()
    end
}
params:add {
    type = 'control', id = 'wgl',
    controlspec = cs.def { min = 0, max = 100, quantum = 0.01/100 },
    action = function(v) 
        local d = (util.linexp(0, 1, 0.01, 1, v) - 0.01) * 100
        sc.mod[1].mul = d * 0.01 
    end --; redraw() end
}
params:add {
    type = 'control', id = '>',
    controlspec = cs.def { default = 1 },
    action = function(v) sc.lvlmx[1].send = v; sc.lvlmx:update(1) end --; redraw() end
}
params:add {
    type = 'control', id = '<',
    controlspec = cs.def { default = 0 },
    action = function(v) sc.lvlmx[2].send = v; sc.lvlmx:update(2) end --; redraw() end
}
params:add {
    type = 'number', id = 'buf 1', default = 1,
    min = 1, max = 2, wrap = true,
    action = function(v) 
        sc.buf:assign(1, v, v) -- play[1][1] or play[2][2]
    end
}
params:add {
    type = 'number', id = 'buf 2', default = 2,
    min = 1, max = 2, wrap = true,
    action = function(v) 
        if v==1 then
            sc.buf:assign(2, 1, 1)  --play[1][1] or play[2][1]
            sc.stereo('play', 2, 1)
        else
            sc.buf:assign(2, 2, 1) 
            sc.punch_in:update_play(2)
        end
    end
}
param.filter(1)

local x, y = gfx.pos.x, gfx.pos.y

local _rec = function(i)
    return _txt.key.toggle {
        n = i+1, x = x[i][1], y = y.key,
        label = 'rec', edge = 0,
        v = function() return params:get('rec '..i) end,
        action = function(s, v, t)
            if t < 0.5 then params:set('rec '..i, v)
            else params:delta('clear '..i, 1) end
        end
    }
end
local _trans = function(i, o)
    return _txt.key.trigger {
        label = { '<<', '>>' },
        edge = 0,
        blinktime = 0.2,
        n = { 2, 3 },
        y = y.key, x = { { x[i][1] }, { x[i][2] } },
        action = function(s, v, t, d, add, rem, l)
            s.blinktime = sc.slew(i, t[add]) / 2

            if #l == 2 then
                sc.ratemx[i].dir = sc.ratemx[i].dir * -1
                sc.ratemx:update(i)
            else
                local o = sc.ratemx[i].oct
                sc.ratemx[i].oct = add==2 and o*2 or o/2
                sc.ratemx:update(i)
            end
        end
    } :merge(o)
end

--screen interface
wrms_ = nest_ {
    gfx = _screen.affordance {
        redraw = gfx.wrms.draw
    },
    tab = _txt.enc.option {
        n = 1, x = 128, y = 2, sens = 0.5, align = 'right', margin = 2,
        flow = 'y', options = { 'v', 'o', 'b', 's', '>', 'f' }
    },
    pages = nest_ {
        v = nest_ {
            vol = nest_(2):each(function(i)
                return param._icontrol('vol', i, {
                    n = i + 1, x = x[i][1], y = y.enc
                })
            end),
            rec = nest_(2):each(function(i)
                return _rec(i)
            end)
        },
        o = nest_ {
            old = nest_(2):each(function(i)
                return param._icontrol('old', i, {
                    n = i + 1, x = x[i][1], y = y.enc
                })
            end),
            rec = nest_(2):each(function(i)
               return _rec(i)
            end)
        },
        b = nest_ {
            bnd = param._control('bnd', {
                n = 2, x = x[1][1], y = y.enc
            }),
            wgl = param._control('wgl', {
                n = 3, x = x[1.5], y = y.enc
            }),
            trans = _trans(2, {})
        },
        s = nest_ {
            s = _txt.enc.number {
                min = 0, max = math.huge, inc = 0.01,
                n = 2, x = x[1][1], y = y.enc,
                value = function() return reg.play:get_start(1) end,
                action = function(s, v)
                    local l = reg.play:get_length(1)
                    reg.play:set_start(1, v)
                    reg.play:set_length(1, l)
                end
            },
            l = _txt.enc.number {
                min = 0, max = math.huge, inc = 0.01,
                n = 3, x = x[1][2], y = y.enc,
                value = function() return reg.play:get_length(1) end,
                action = function(s, v)
                    reg.play:set_length(1, v)
                end
            },
            trans = _trans(1, {})
        },
        ['>'] = nest_ {
            ['>'] = param._control('>', {
                n = 2, x = x[1][1], y = y.enc,
            }),
            ['<'] = param._control('<', {
                n = 3, x = x[2][1], y = y.enc,
            }),
            buf = nest_(2):each(function(i)
                return _txt.key.number {
                    label = 'buf', n = i+1, x = x[i][1], y = y.key,
                    min = 1, max = 2, inc = 1, wrap = true, step = 1,
                    value = function() return params:get('buf '..i) end,
                    action = function(s, v) params:set('buf '..i, v) end
                }
            end)
        },
        f = nest_ {
            f = param._control('f', {
                n = 2, x = x[1][1], y = y.enc,
            }),
            q = param._control('q', {
                n = 3, x = x[1][2], y = y.enc,
            }),
            type = _txt.key.option {
                n = { 2, 3 }, x = x[1][1], y = y.key,
                options = params:lookup_param('filter type').options,
                value = function() return params:get('filter type') end,
                action = function(s, v) params:set('filter type', v) end
            }
        }    
    }: each(function(k, v)
        v.enabled = function(s) 
            return wrms_.tab.options[wrms_.tab.v//1] == k 
        end
    end)
} :connect { screen = screen, enc = enc, key = key } 

local function setup()
    sc.setup()
    sc.stereo('play', 1, 1)
    sc.mod:init(1)
    reg.rec[1]:set_length(4)
    reg.play[1][1]:set_length(0.4)
end

function init()
    setup()
    params:bang()
    wrms_:init()
end

function cleanup()
    --todo: save state for wrm 1 regions & params
end

return { sc = sc, gfx = gfx, param = param, reg = reg, wrms_ = wrms_, setup = setup }

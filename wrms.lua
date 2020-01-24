-- wrms
-- minimal, extensible dual 
-- echo looper
-- v011820 @andrew
-- llllllll.co/t/22222
-- norns interface only
-- 2 wrms (stereo loops) with 
-- unique characteristics
-- v - channel volumes plus 
-- record toggle wrm1 is a 
-- simple toggle, wrm2 a loop 
-- pedal-style punch-in
-- o - old controls how much 
-- of the past remains as wrms 
-- circle thru time
-- b - 2 controls for rate/pitch 
-- as wrms apprach light speed
-- s - length of wrm1 and where 
-- he begins - allows tiny bit 
-- chopping and subtle delay 
-- movement
-- > - config for telepathic 
-- inter-wrm time loop 
-- communication

include 'wrms/lib/lib_wrms'

function init()
  
  -- softcut initial settings
  softcut.buffer_clear()
  
  audio.level_adc_cut(1)
  audio.level_eng_cut(1)
  
  for h, i in ipairs({ 0, 2 }) do
    softcut.play(h, 1)
    softcut.pre_level(h, 0.0)
    softcut.rate_slew_time(h, 0.2)
    softcut.rec_level(h + 2, 1.0)
    softcut.rate(h + 2, 1.0)
    
    for j = 1,2 do
      softcut.enable(i + j, 1)
      softcut.loop(i + j, 1)
      softcut.fade_time(i + j, 0.1)
      
      softcut.level_input_cut(j, i + j, 1.0)
      softcut.buffer(i + j,j)
      softcut.pan(i + j, j == 1 and -1 or 1)
      
      softcut.loop_start(i+j, wrms_loop[j].loop_start)
      softcut.loop_end(i+j, wrms_loop[j].loop_end)
      softcut.position(i+j, wrms_loop[j].loop_start)
    end
  end
  
  wrms_init()
  
  redraw()
end

wrms_pages = { -- ordered pages of visual controls and actions (event callback functions)
  {
    label = "v",
    e2 = { -- wrm 1 volume
      worm = 1,
      label = "vol",
      value = 1.0,
      range = { 0.0, 2.0 },
      event = function(v) 
        softcut.level(1, v)
        softcut.level(2, v)
      end
    },
    e3 = { -- wrm 2 volume
      worm = 2,
      label = "vol",
      value = 1.0,
      range = { 0.0, 2.0 },
      event = function(v)
        softcut.level(3, v)
        softcut.level(4, v)
      end
    },
    k2 = { -- wrm 2 record toggle
      worm = 1,
      label = "rec",
      value = 1,
      behavior = "toggle",
      event = function(v, t)
        if t < 1 then -- if short press toggle record
          softcut.rec(1, v)
          softcut.rec(2, v)
        else -- else long press clears loop region
          softcut.rec(1, 0)
          softcut.rec(2, 0)
          
          wrms_pages[1].k2.value = 0
          
          softcut.buffer_clear_region(wrms_loop[1].region_start, wrms_loop[1].region_end)
        end
      end
    },
    k3 = { -- wrm 2 record toggle + loop punch-in
      worm = 2,
      label = "rec",
      value = 0,
      behavior = "toggle",
      event = function(v, t)
        if t < 1 then -- if short press
          if wrms_loop[2].has_initial then -- if inital loop has been recorded
            softcut.rec(3, v) -- toggle recording
            softcut.rec(4, v)
          elseif wrms_loop[2].punch_in_time ~= nil then -- else if inital loop is being punched in, punch out
            softcut.rec(3, 0) -- stop recording but keep playing
            softcut.rec(4, 0)
            
            local lt = util.clamp(util.time() - wrms_loop[2].punch_in_time, 0, 200) -- loop time = now - when we punched-in
            wrms_loop[2].region_end = lt + wrms_loop[2].region_start -- set loop end to loop time
            wrms_loop[2].loop_end = lt + wrms_loop[2].loop_start
            softcut.loop_end(3, wrms_loop[2].loop_end)
            softcut.loop_end(4, wrms_loop[2].loop_end)
            softcut.position(3, wrms_loop[2].loop_start)
            softcut.position(4, wrms_loop[2].loop_start)
            
            wrms_loop[2].has_initial = true -- this is how we know we're done with the punch-in
            
          elseif v == 1 then -- else start loop punch-in
            wrms_loop[2].region_end = 201 -- set loop end to max
            wrms_loop[2].loop_end = 201
            softcut.loop_start(3, wrms_loop[2].loop_start)
            softcut.loop_start(4, wrms_loop[2].loop_start)
            softcut.loop_end(3, 201)
            softcut.loop_end(4, 201)
            softcut.position(3, wrms_loop[2].loop_start)
            softcut.position(4, wrms_loop[2].loop_start)
            
            softcut.rec(3, 1) -- start recording
            softcut.rec(4, 1)
            softcut.play(3, 1)
            softcut.play(4, 1)
            
            wrms_loop[2].punch_in_time = util.time() -- store the punch in time for when we punch out
          end
        else -- else (long press)
          softcut.rec(3, 0) -- stop recording
          softcut.rec(4, 0)
          softcut.play(3, 0)
          softcut.play(4, 0)
          wrms_pages[1].k3.value = 0
          
          wrms_loop[2].punch_in_time = nil
          wrms_loop[2].has_initial = false
        
          softcut.buffer_clear_region(wrms_loop[2].region_start, wrms_loop[2].region_end) -- clear loop region
        end
      end
    }
  },
  {
    label = "o",
    e2 = { -- wrm 1 old volume (using rec_level)
      worm = 1,
      label = "old",
      value = 0.5,
      range = { 0.0, 1.0 },
      event = function(v)
        softcut.rec_level(1, v)
        softcut.rec_level(2, v)
      end
    },
    e3 = { -- wrm 2 old volume (using pre_level)
      worm = 2,
      label = "old",
      value = 1.0,
      range = { 0.0, 1.0 },
      event = function(v) 
        softcut.pre_level(3,  v)
        softcut.pre_level(4,  v)
      end
    },
    k2 = {},
    k3 = {}
  },
  {
    label = "b",
    e2 = {
      worm = 1,
      label = "bnd",
      value = 1.0,
      range = { 1, 2.0 },
      event = function(v) 
        softcut.rate(1, 2^(v-1))
        softcut.rate(2, 2^(v-1))
        wrms_loop[1].rate = 2^(v-1)
      end
    },
    -- e3 = {
    --   worm = "both",
    --   label = "wgl",
    --   value = 0.0,
    --   range = { 0.0, 10.0 },
    --   event = function(v) end
    -- },
    k2 = {
      worm = 2,
      label = "<<",
      value = 0,
      behavior = "momentary",
      event = function(v, t)
        local st = (1 + (math.random() * 0.5)) * t
        softcut.rate_slew_time(3, st)
        softcut.rate_slew_time(4, st)
        
        wrms_loop[2].rate = wrms_loop[2].rate / 2
        softcut.rate(3, wrms_loop[2].rate)
        softcut.rate(4, wrms_loop[2].rate)
      end
    },
    k3 = {
      worm = 2,
      label = ">>",
      value = 0,
      behavior = "momentary",
      event = function(v, t) 
        local st = (1 + (math.random() * 0.5)) * t
        softcut.rate_slew_time(3, st)
        softcut.rate_slew_time(4, st)
        
        wrms_loop[2].rate = wrms_loop[2].rate * 2
        softcut.rate(3, wrms_loop[2].rate)
        softcut.rate(4, wrms_loop[2].rate)
      end
    }
  },
  {
    label = "s", 
    e2 = { -- wrm 1 loop start point
      worm = 1,
      label = "s",
      value = 0.0,
      range = { 0.0, 1.0 },
      event = function(v) 
        wrms_pages[4].e2.range[2] = wrms_loop[1].region_end - wrms_loop[1].region_start -- set encoder range
        
        wrms_loop[1].loop_start = v + wrms_loop[1].region_start-- set start point
        softcut.loop_start(1, wrms_loop[1].loop_start)
        softcut.loop_start(2, wrms_loop[1].loop_start)
        
        wrms_pages[4].e3.event(wrms_pages[4].e3.value)
      end
    },
    e3 = { -- wrm 1 loop length
      worm = 1,
      label = "l",
      value = 0.3,
      range = { 0.01, 1.0 },
      event = function(v) 
        wrms_pages[4].e3.range[2] = wrms_loop[1].region_end - wrms_loop[1].region_start -- set encoder range
        
        wrms_loop[1].loop_end = v + wrms_loop[1].loop_start -- set loop end from length
        softcut.loop_end(1, wrms_loop[1].loop_end)
        softcut.loop_end(2, wrms_loop[1].loop_end)
      end
    }
    -- ,
    -- k2 = {
    --   worm = 1,
    --   label = "p",
    --   value = 0,
    --   behavior = "toggle",
    --   event = function(v, t) end
    -- },
    -- k3 = {
    --   worm = 1,
    --   label = "p",
    --   value = 0,
    --   behavior = "toggle",
    --   event = function(v, t) end
    -- }
  },
  -- {
  --   label = "f",
  --   e2 = {
  --     worm = 1,
  --     label = "f",
  --     value = 1.0,
  --     range = { 0.0, 1.0 },
  --     event = function(v) end
  --   },
  --   e3 = {
  --     worm = 1,
  --     label = "q",
  --     value = 0.3,
  --     range = { 0.0, 1.0 },
  --     event = function(v) end
  --   },
  --   k2 = {
  --     worm = 1,
  --     label = { "1", "2" },
  --     value = 1,
  --     behavior = "enum",
  --     event = function(v, t) end
  --   },
  --   k3 = {
  --     worm = 1,
  --     label = { "lp", "bp", "hp"  },
  --     value = 1,
  --     behavior = "enum",
  --     event = function(v, t) end
  --   }
  -- },
  {
    label = ">",
    e2 = { -- feed wrm 1 to wrm 2
      worm = 1,
      label = ">",
      value = 1.0,
      range = { 0.0, 1.0 },
      event = function(v)
        softcut.level_cut_cut(1, 3, v * wrms_pages[1].e2.value)
        softcut.level_cut_cut(2, 4, v * wrms_pages[1].e2.value)
      end
    },
    e3 = { -- feed wrm 2 to wrm 1
      worm = 2,
      label = "<",
      value = 0.0,
      range = { 0.0, 1.0 },
      event = function(v) 
        softcut.level_cut_cut(3, 1, v * wrms_pages[2].e2.value)
        softcut.level_cut_cut(4, 2, v * wrms_pages[2].e2.value)
      end
    },
    k2 = {
      worm = 1,
      label = "pp",
      value = 0,
      behavior = "toggle",
      event = function(v, t) 
        if v == 1 then -- if ping-pong is enabled, route across voices
          softcut.level_cut_cut(1, 2, 1)
          softcut.level_cut_cut(2, 1, 1)
          softcut.level_cut_cut(1, 1, 0)
          softcut.level_cut_cut(2, 2, 0)
        else -- else (ping-pong is not enabled) route voice to voice
          softcut.level_cut_cut(1, 2, 0)
          softcut.level_cut_cut(2, 1, 0)
          softcut.level_cut_cut(1, 1, 1)
          softcut.level_cut_cut(2, 2, 1)
        end
      end
    },
    k3 = { -- toggle share buffer region
      worm = "both",
      label = "share",
      value = 0,
      behavior = "toggle",
      event = function(v, t) 
        if v == 1 then -- if sharing
          wrms_loop[1].region_start = wrms_loop[2].region_start -- set wrm 1 region points to wrm 2 region points
          wrms_loop[1].region_end = wrms_loop[2].region_end
        else -- else (not sharing)
          wrms_loop[1].region_start = 201 -- set wrm 1 region points to default
          wrms_loop[1].region_end = 301
        end
        
        wrms_pages[4].e2.event(wrms_pages[4].e2.value) -- update loop points
        wrms_pages[4].e3.event(wrms_pages[4].e3.value)
      end
    }
  }
}

wrms_pages[2].k2 = wrms_pages[1].k2
wrms_pages[2].k3 = wrms_pages[1].k3


---------------------------------------------------------------------------------------------------------------------------

function enc(n, delta)
  wrms_enc(n, delta)
  
  redraw()
end

function key(n,z)
  wrms_key(n,z)
  
  redraw()
end

function redraw()
  screen.clear()
  
  wrms_redraw()
  
  screen.update()
end

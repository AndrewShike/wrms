wrms = {}

wrms.lfo = include 'lib/hnds_wrms'
supercut = include 'lib/supercut'

wrms.sens = 0.01
wrms.phase_quant = 0.05

wrms.pages = {}

wrms.page_n = 1
local get_page_n = function() return math.floor(wrms.page_n) end

supercut.add_data("is_punch_in", false)
supercut.add_data("has_initial", false)
supercut.add_data("wiggle", 0)
supercut.add_data("feed", 0)
supercut.has_initial(1, true)
supercut.feed(1, 1)

-- wrms.loop = {
--   {
--     is_punch_in = false,
--     has_initial = true,
--     phase = 0,
--     default_region_start = 295,
--     default_region_end = 300,
--     region_start = 0,
--     region_end = 0,
--     loop_start = 0,
--     loop_end = 0,
--     rate = 1,
--     bend = 1,
--     vol = 1,
--     wgl = 0,
--     feed = 1,
--     rec = 1
--   },
--   {
--     is_punch_in = false,
--     has_initial = false,
--     phase = 0,
--     default_region_start = 1,
--     default_region_end = 60,
--     region_start = 0,
--     region_end = 0,
--     loop_start = 0,
--     loop_end = 0,
--     rate = 1,
--     bend = 1,
--     vol = 1,
--     wgl = 0,
--     feed = 0,
--     rec = 0
--   }
-- }

-- for i,v in ipairs(wrms.loop) do
--   v.region_start = v.default_region_start
--   v.region_end = v.default_region_end
--   v.loop_start = v.default_region_start
--   v.loop_end = v.default_region_end
-- end

-- for putting wrms to sleep zZzz :)
local function awake_seg()
  ret = {}
  
  for i = 1, 24 do
    ret[i] = false
  end
  
  return ret
end

supercut.add_data("segment_is_awake", awake_seg())
supercut.add_data("sleep_index", 24)

function wrms.wake(voice)
  supercut.sleep_index(voice, 24)
end

function wrms.sleep(voice)
  supercut.sleep_index(voice, 1)
end

-- function wrm_phase_event(voice, p)
--   if voice == 1 or voice == 3 then
--     local l = voice == 1 and 1 or 2
--     wrms.loop[l].phase = p
    
--     redraw()
--   end
-- end

------------

supercut.phase_quant(1, wrms.phase_quant)
supercut.phase_quant(2, wrms.phase_quant)

function wrms.init()
  for i,v in ipairs(wrms.pages) do
    for j,w in ipairs({ v.e2, v.e3 }) do
      if w ~= nil then w:event(w.value) end
    end
    for j,w in ipairs({ v.k2, v.k3 }) do
      if w ~= nil then if w.behavior ~= "momentary" then w:event(w.value, 0) end end
    end
  end
end

function wrms.enc(n, delta)
  if n == 1 then wrms.page_n = util.clamp(wrms.page_n + (util.clamp(delta, -1, 1) * 0.25), 1, #wrms.pages)
  else
    local e = wrms.pages[get_page_n()]["e" .. n]
    
    if e ~= nil then
      local sens = e.sens == nil and wrms.sens or e.sens
      e.value = util.round(util.clamp(e.value + (delta * sens), e.range[1], e.range[2]), sens)
      e:event(e.value)
    end
  end
end

function wrms.key(n,z)
  if n == 1 then
    rec = z
  else
    local k = wrms.pages[get_page_n()]["k" .. n]
    
    if k ~= nil then
      if z == 1 then
        k.time = util.time()
        if k.behavior == "momentary" then k.value = 1 end
      else
        if k.behavior == "momentary" then k.value = 0
        elseif k.behavior == "toggle" then k.value = k.value == 0 and 1 or 0
        elseif k.behavior == "enum" then k.value = k.value == #k.label and 1 or k.value + 1 end
        
        k:event(k.value, util.time() - k.time)
        k.time = nil
      end
    end
  end
end


wrms.draw = {}

wrms.draw.pager = function()
  for i,v in ipairs(wrms.pages) do
    screen.move(128 - 4, i * 7)
    screen.level(get_page_n() == i and 8 or 2)
    screen.text_center(v.label)
  end
end

local function get_x_pos(c1, c2)
  local ret, wrm1, wrm2
  
  if c1 == nil then wrm1 = 1 else wrm1 = c1.worm end
  if c2 == nil then wrm2 = 2 else wrm2 = c2.worm end
  
  if wrm1 == 1 and wrm2 == 2 then ret = { 0, 2 }
  elseif wrm1 == 1 and wrm2 == 1 then ret = { 0, 1 }
  elseif wrm1 == 2 and wrm2 == 2 then ret = { 2, 3 }
  elseif wrm1 == "both" and wrm2 == 2 then ret = { 1.5, 3 }
  elseif wrm1 == 1 and wrm2 == "both" then ret = { 0, 1.5 }
  else ret = { 2, 0 } end
  
  return ret
end

wrms.draw.enc = function()
  local ex = get_x_pos(wrms.pages[get_page_n()].e2, wrms.pages[get_page_n()].e3)
  for i,v in ipairs({ wrms.pages[get_page_n()].e2, wrms.pages[get_page_n()].e3 }) do
    if v ~= nil then
      screen.move(2 + ex[i] * 29, 46)
      screen.level(4)
      screen.text(v.label)
      screen.move(2 + (ex[i] * 29) + ((string.len(v.label) + 0.5) * 5), 46)
      screen.level(10)
      screen.text(v.value)
    end
  end
end

wrms.draw.key = function()
  local kx = get_x_pos(wrms.pages[get_page_n()].k2, wrms.pages[get_page_n()].k3)
  for i,v in ipairs({ wrms.pages[get_page_n()].k2, wrms.pages[get_page_n()].k3 }) do
    if v ~= nil then
      screen.move(2 + kx[i] * 29, 46 + 10)
      
      if v.behavior == "enum" then
        screen.level(8)
        screen.text(v.label[math.floor(v.value)])
      else
        screen.level(v.value * 10 + 2)
        screen.text(v.label)
      end
    end
  end
end

wrms.draw.animations = function()
  
  --feed indicators
  screen.level(math.floor(supercut.feed(1) * 4))
  screen.pixel(42, 23)
  screen.pixel(43, 24)
  screen.pixel(42, 25)
  screen.fill()
  
  screen.level(math.floor(supercut.feed(2) * 4))
  screen.pixel(54, 23)
  screen.pixel(53, 24)
  screen.pixel(54, 25)
  screen.fill()
  
  for i = 1,2 do
    local left = 2 + (i-1) * 58
    local top = 34
    local width = 44
    
    --phase
    screen.level(2)
    if supercut.is_punch_in(i) == false then
      screen.pixel(left + width * (supercut.loop_start(i) - supercut.region_start(i)) / (supercut.region_end(i) - supercut.region_start(i)), top)
      screen.fill()
    end
    if supercut.has_initial(i) then
      screen.pixel(left + width * (supercut.loop_end(i) - supercut.region_start(i)) / (supercut.region_end(i) - supercut.region_start(i)), top)
      screen.fill()
    end
    
    screen.level(6 + 10 * supercut.rec(i))
    if supercut.has_initial(i) == false then
      if supercut.is_punch_in(i) then
        screen.move(left + width * (supercut.loop_start(i) - supercut.region_start(i)) / (supercut.region_end(i) - supercut.region_start(i)), top + 1)
        screen.line(1 + left + width * (supercut.position(i) - supercut.region_start(i)) / (supercut.region_end(i) - supercut.region_start(i)), top + 1)
        screen.stroke()
      end
    else
      screen.pixel(left + width * (supercut.position(i) - supercut.region_start(i)) / (supercut.region_end(i) - supercut.region_start(i)), top)
      screen.fill()
    end
    
    --fun wrm animaions
    local top = 18
    local width = 24
    local lowamp = 0.5
    local highamp = 1.75
    
    if supercut.sleep_index(i) > 0 and supercut.sleep_index(i) <= 24 then
      supercut.segment_is_awake(i)[math.floor(supercut.sleep_index(i))] = supercut.has_initial(i)
      supercut.sleep_index(i, supercut.sleep_index(i) + (1 * (supercut.has_initial(i) and -1 or -4)))
    end
    
    screen.level(math.floor(supercut.level(i) * 10))
    local width = util.linexp(0, (supercut.region_end(i) - supercut.region_start(i)), 0.01, width, (supercut.loop_end(i)  + 4.125 - supercut.loop_start(i)))
    for j = 1, width do
      local amp = supercut.segment_is_awake(i)[j] and math.sin(((supercut.position(i) - supercut.loop_start(i)) * (i == 1 and 1 or 2) / (supercut.loop_end(i) - supercut.loop_start(i)) + j / width) * (i == 1 and 2 or 4) * math.pi) * util.linlin(1, width / 2, lowamp, highamp + supercut.wiggle(i), j < (width / 2) and j or width - j) - 0.75 * util.linlin(1, width / 2, lowamp, highamp + supercut.wiggle(i), j < (width / 2) and j or width - j) - (util.linexp(0, 1, 0.5, 6, j/width) * (supercut.rate2(i) - 1)) or 0
      local left = left - (supercut.loop_start(i) - supercut.region_start(i)) / (supercut.region_end(i) - supercut.region_start(i)) * (width - 44)
      
      screen.pixel(left - 1 + j, top + amp)
    end
    screen.fill()
  end
end


function wrms.redraw()
  wrms.draw.pager()
  wrms.draw.enc()
  wrms.draw.key()
  wrms.draw.animations()
end



-- utility functions

function wrms.page_from_label(label)
  for i,v in ipairs(wrms.pages) do
    if(v.label == label) then return v end
  end
end

function wrms.update_control(control)
  control:event(control.value)
end


return wrms
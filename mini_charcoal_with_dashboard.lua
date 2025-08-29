-- tiny_charcoal_with_dashboard.lua  (deduped + no ID display)
-- CC:Tweaked + Advanced Peripherals + MineColonies (ATM10 1.21.x)
-- Watches Colony Integrator requests, finds utilitarian:tiny_charcoal,
-- crafts exactly 2x of each request (once per ticket, with delta handling),
-- pulses a vanilla Crafter, and shows a tidy monitor/terminal dashboard.
-- Progress persists to disk so it won't re-craft the same ticket after reboot.

-------------------- CONFIG --------------------
local COLONY_SIDE      = "right"   -- side/name where 'colony_integrator' is visible
local CRAFTER_RS_SIDE  = "left"    -- redstone side wired to the Crafter
local OUTPUT_PER_PULSE = 8         -- Tiny Charcoal items per craft pulse (set to your recipe yield)
local PULSE_ON_SEC     = 0.20      -- Crafter redstone ON duration
local PULSE_OFF_SEC    = 0.40      -- cooldown between pulses
local POLL_IDLE_SEC    = 3         -- idle poll interval
local TINY_CHARCOAL_ID = "utilitarian:tiny_charcoal" -- strict item id
local STATE_FILE       = "tiny_charcoal_state.json"  -- persistent ledger file
------------------------------------------------

-- Peripherals
local colony = peripheral.wrap(COLONY_SIDE) or peripheral.find("colony_integrator") or peripheral.find("colonyIntegrator")
assert(colony, "Colony Integrator not found (check side/name/wiring).")

local mon = peripheral.find("monitor")
if mon then pcall(function() mon.setTextScale(0.5) end) end

-------------------- STATE ---------------------
-- state.crafted[request_id] = total tiny charcoal we've crafted for that ticket
local state = { crafted = {} }

local function loadState()
  if not fs.exists(STATE_FILE) then return end
  local h = fs.open(STATE_FILE, "r"); if not h then return end
  local s = h.readAll(); h.close()
  local ok, data = pcall(textutils.unserialiseJSON, s)
  if ok and type(data) == "table" and type(data.crafted) == "table" then
    state = data
  end
end

local function saveState()
  local h = fs.open(STATE_FILE, "w"); if not h then return end
  h.write(textutils.serialiseJSON(state)); h.close()
end

loadState()

------------------- HELPERS --------------------
local function draw(lines)
  if mon then
    mon.clear(); mon.setCursorPos(1,1)
    local y = 1
    for _,ln in ipairs(lines) do
      mon.setCursorPos(1,y); mon.write(ln); y = y + 1
      if y > 19 then break end
    end
  else
    term.clear(); term.setCursorPos(1,1)
    for _,ln in ipairs(lines) do print(ln) end
  end
end

local function pulseCrafter(n, status)
  n = math.max(0, n or 0)
  for i = 1, n do
    status.lastAction = ("Pulsing crafter (%d/%d)"):format(i, n)
    redstone.setOutput(CRAFTER_RS_SIDE, true)  sleep(PULSE_ON_SEC)
    redstone.setOutput(CRAFTER_RS_SIDE, false) sleep(PULSE_OFF_SEC)
  end
  if n > 0 then status.lastAction = ("Completed %d pulse(s)"):format(n) end
end

-- Fallback matcher if a request arrives without items[]
local function textMentionsTinyCharcoal(r)
  local t = ((r.name or "") .. " " .. (r.desc or "")):lower()
  return t:find("tiny") and t:find("charcoal")
end

-- Return list of tiny-charcoal tickets with computed needs:
-- { id, rstate, want, desired, done, need, pulses }
local function collectTinyReqs()
  local out = {}
  local ok, reqs = pcall(colony.getRequests)
  if not ok or type(reqs) ~= "table" then return out end

  for _, r in ipairs(reqs) do
    local want = 0

    if type(r.items) == "table" then
      for _, it in ipairs(r.items) do
        if (it.name or "") == TINY_CHARCOAL_ID then
          want = want + (tonumber(it.count) or 0)
        end
      end
    elseif textMentionsTinyCharcoal(r) then
      want = tonumber(r.minCount) or tonumber(r.count) or 0
    end

    if want > 0 then
      local id = tostring(r.id or "?")
      local desired = want * 2
      local done = tonumber(state.crafted[id] or 0)
      if done > desired then done = desired end -- clamp if ticket shrank
      local need = math.max(0, desired - done)
      local pulses = math.ceil(need / OUTPUT_PER_PULSE)

      table.insert(out, {
        id = id,
        rstate = r.state or "?",
        want = want,
        desired = desired,
        done = done,
        need = need,
        pulses = pulses
      })
    end
  end

  return out
end

-- GC old ids that are no longer present
local function gcState(activeIds)
  local keep = {}
  for _, id in ipairs(activeIds) do keep[id] = true end
  for id in pairs(state.crafted) do
    if not keep[id] then state.crafted[id] = nil end
  end
end

-------------------- MAIN ----------------------
local status = { lastAction = "Boot" }
print("Tiny Charcoal (deduped) auto-crafter started.")

while true do
  local reqs = collectTinyReqs()

  -- Build dashboard and plan
  local activeIds, totalWant, totalNeed = {}, 0, 0
  for _, q in ipairs(reqs) do
    table.insert(activeIds, q.id)
    totalWant = totalWant + q.want
    totalNeed = totalNeed + q.need
  end
  gcState(activeIds)

  local header = {
    "MineColonies Requests • Tiny Charcoal Auto-Crafter (deduped)",
    ("Yield per pulse: %d    Crafter side: %s"):format(OUTPUT_PER_PULSE, CRAFTER_RS_SIDE),
    ("Last action: %s"):format(status.lastAction or "-"),
    ("Planned: %d requested  ->  %d to craft  ->  %d pulses")
      :format(totalWant * 2, totalNeed, math.ceil(totalNeed / OUTPUT_PER_PULSE)),
    ""
  }

  -- Show compact per-ticket progress WITHOUT printing IDs
  if #reqs == 0 then
    table.insert(header, "(no tiny charcoal requests)")
  else
    for _, q in ipairs(reqs) do
      table.insert(header,
        ("[%s] want:%d  done:%d/%d  need:%d  pulses:%d")
          :format(q.rstate, q.want, q.done, q.desired, q.need, q.pulses))
    end
  end

  draw(header)

  -- Work on tickets (deduped)
  local didWork = false
  for _, q in ipairs(reqs) do
    if q.need > 0 then
      didWork = true
      status.lastAction = ("Pulsing %d for ticket"):format(q.pulses)
      draw(header)
      pulseCrafter(q.pulses, status)
      state.crafted[q.id] = (state.crafted[q.id] or 0) + q.pulses * OUTPUT_PER_PULSE
      saveState()
    end
  end

  if not didWork then
    status.lastAction = "Idle (nothing needed)"
    sleep(POLL_IDLE_SEC)
  else
    sleep(1) -- small breather while MineColonies updates
  end
end

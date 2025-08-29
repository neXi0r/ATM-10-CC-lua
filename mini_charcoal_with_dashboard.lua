-- tiny_charcoal_with_dashboard.lua
-- ATM10 • CC:Tweaked + Advanced Peripherals + MineColonies
-- Reads MineColonies requests, if "utilitarian:tiny_charcoal" is requested:
-- craft 2x the requested amount using a vanilla Crafter via redstone pulses.
-- Output is hopper-fed into a Stash (couriers pick it up). Includes a live dashboard.

-------------------- CONFIG --------------------
local COLONY_SIDE      = "right"  -- side/name where the Colony Integrator is visible (use peripheral.getNames to confirm)
local CRAFTER_RS_SIDE  = "left"   -- redstone side wired to the Crafter
local POLL_IDLE_SEC    = 3        -- how often to poll when idle
local PULSE_ON_SEC     = 0.20     -- redstone ON time per craft
local PULSE_OFF_SEC    = 0.40     -- cooldown after each craft
local OUTPUT_PER_PULSE = 8        -- Tiny Charcoal produced per craft pulse (adjust if your recipe differs)
local TINY_CHARCOAL_ID = "utilitarian:tiny_charcoal" -- strict item id to match
------------------------------------------------

-- Peripherals
local colony = peripheral.wrap(COLONY_SIDE) or peripheral.find("colony_integrator") or peripheral.find("colonyIntegrator")
assert(colony, "Colony Integrator not found. Check side/name and wiring.")

local mon = peripheral.find("monitor")
local useMonitor = mon ~= nil
if useMonitor then pcall(function() mon.setTextScale(0.5) end) end

-- Helpers
local function pulseCrafter(times, status)
  times = math.max(0, times or 0)
  for i = 1, times do
    status.lastAction = ("Pulsing crafter (%d/%d)"):format(i, times)
    redstone.setOutput(CRAFTER_RS_SIDE, true)
    sleep(PULSE_ON_SEC)
    redstone.setOutput(CRAFTER_RS_SIDE, false)
    sleep(PULSE_OFF_SEC)
  end
  if times > 0 then
    status.lastAction = ("Completed %d pulse(s)"):format(times)
  end
end

local function reqTextMatch(r)
  -- Fallback if items[] missing: match by request title/desc
  local t = ((r.name or "") .. " " .. (r.desc or "")):lower()
  return t:find("tiny") and t:find("charcoal")
end

-- Scan requests; return total tiny-charcoal count requested and a few pretty lines for UI
local function readTinyCharcoalRequests()
  local ok, reqs = pcall(colony.getRequests)
  if not ok or type(reqs) ~= "table" then return 0, {"(no requests or API error)"} end

  local total = 0
  local lines = {}
  for _, r in ipairs(reqs) do
    local added = 0
    local shown = false

    if type(r.items) == "table" then
      for _, it in ipairs(r.items) do
        local id   = (it.name or "")
        local disp = (it.displayName or id)
        local cnt  = tonumber(it.count) or 0
        if id == TINY_CHARCOAL_ID then
          total = total + cnt
          added = added + cnt
          table.insert(lines, ("#%s %s  %dx [%s]"):format(
            tostring(r.id or "?"), r.state or "?", cnt, disp))
          shown = true
        end
      end
    end

    if added == 0 and reqTextMatch(r) then
      local cnt = tonumber(r.minCount) or tonumber(r.count) or 0
      if cnt > 0 then
        total = total + cnt
        table.insert(lines, ("#%s %s  %dx [Tiny Charcoal]*text-match"):format(
          tostring(r.id or "?"), r.state or "?", cnt))
        shown = true
      end
    end

    if not shown and (r.name or r.desc) then
      -- show only a compact header for non-matching requests (comment this out to hide noise)
      -- table.insert(lines, ("#%s %s"):format(tostring(r.id or "?"), r.name or r.desc or "Request"))
    end
  end

  if #lines == 0 then lines = {"(no tiny charcoal requests)"} end
  return total, lines
end

local function drawDashboard(status)
  local header = {
    "MineColonies Requests • Tiny Charcoal Auto-Crafter",
    ("Yield per pulse: %d   Crafter side: %s"):format(OUTPUT_PER_PULSE, CRAFTER_RS_SIDE),
    ("Last action: %s"):format(status.lastAction or "-"),
    ("Planned: %d requested  →  %d to craft  →  %d pulses"):format(
      status.req or 0, status.toCraft or 0, status.pulses or 0),
    ""
  }

  local function render(writeLine)
    for _, line in ipairs(header) do writeLine(line) end
    for i, line in ipairs(status.reqLines or {}) do
      if i > 30 then break end -- avoid spamming very small monitors
      writeLine(line)
    end
  end

  if useMonitor then
    mon.clear() ; mon.setCursorPos(1,1)
    local y = 1
    render(function(s) mon.setCursorPos(1,y) ; mon.write(s) ; y = y + 1 end)
  else
    term.clear() ; term.setCursorPos(1,1)
    render(function(s) print(s) end)
  end
end

-- Main loop
local status = { lastAction = "Boot" }
print("Tiny Charcoal dashboard + automation started.")
while true do
  local req, lines = readTinyCharcoalRequests()
  status.reqLines = lines
  status.req = req

  if req > 0 then
    status.toCraft = req * 2
    status.pulses  = math.ceil(status.toCraft / OUTPUT_PER_PULSE)
    status.lastAction = ("Planning %d pulses for %d items"):format(status.pulses, status.toCraft)
    drawDashboard(status)

    pulseCrafter(status.pulses, status)
    drawDashboard(status)

    -- let MineColonies update its tickets
    sleep(1)
  else
    status.toCraft = 0
    status.pulses  = 0
    status.lastAction = "Idle (no tiny charcoal requests)"
    drawDashboard(status)
    sleep(POLL_IDLE_SEC)
  end
end

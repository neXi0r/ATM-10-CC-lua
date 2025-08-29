-- mini_charcoal_with_dashboard.lua
-- ATM10 • CC:Tweaked + Advanced Peripherals + MineColonies
-- Dashboard + automation:
--   - Poll MineColonies requests via Colony Integrator
--   - If "Mini Charcoal" (Utilitarian) is requested, craft 2x the requested amount
--     using a vanilla Crafter triggered by redstone pulses
--   - Output is hopper-fed into a Stash (couriers will pick it up)
--   - A Monitor shows live requests and what the script is doing

-------------------- CONFIG --------------------
local CRAFTER_RS_SIDE  = "left"   -- redstone side wired to Crafter
local POLL_IDLE_SEC    = 3        -- how often to poll when idle
local PULSE_ON_SEC     = 0.20     -- redstone ON time per craft
local PULSE_OFF_SEC    = 0.40     -- cooldown after each craft
local OUTPUT_PER_PULSE = 8        -- Mini Charcoal produced per craft pulse (adjust if different)
-- Strict registry ID; change if your pack uses another id
local MINI_CHARCOAL_ID = "utilitarian:mini_charcoal"
-----------------------------------------------

-- Peripherals
local colony = peripheral.find("colonyIntegrator") or peripheral.find("colony_integrator")
assert(colony, "Colony Integrator not found. Place it or connect with a wired modem.")

local mon = peripheral.find("monitor")
local useMonitor = false
if mon then
  useMonitor = true
  pcall(function() mon.setTextScale(0.5) end)
end

-- Helpers
local function isMiniCharcoalItem(it)
  if not it then return false end
  local id   = (it.name or ""):lower()
  local disp = (it.displayName or ""):lower()
  if id == MINI_CHARCOAL_ID then return true end
  if (id:find("mini") and id:find("charcoal")) then return true end
  if disp == "mini charcoal" then return true end
  return false
end

local function pulseCrafter(times, status)
  for i = 1, times do
    status.lastAction = ("Pulsing crafter (%d/%d)"):format(i, times)
    redstone.setOutput(CRAFTER_RS_SIDE, true)
    sleep(PULSE_ON_SEC)
    redstone.setOutput(CRAFTER_RS_SIDE, false)
    sleep(PULSE_OFF_SEC)
  end
  status.lastAction = ("Completed %d pulse(s)"):format(times)
end

-- Build a compact list of current requests and compute totals for mini charcoal
local function readRequests()
  local ok, reqs = pcall(colony.getRequests)
  if not ok or type(reqs) ~= "table" then
    return {}, 0
  end

  local lines = {}
  local totalMini = 0

  for _, r in ipairs(reqs) do
    local rid   = tostring(r.id or "?")
    local rname = r.name or r.desc or "Request"
    local rstate= r.state or "?"
    local anyMini = false
    local shownSub = false

    if type(r.items) == "table" then
      for _, it in ipairs(r.items) do
        local cnt = tonumber(it.count) or 0
        local line = ("  - %dx %s"):format(cnt, it.displayName or it.name or "?")
        if isMiniCharcoalItem(it) then
          anyMini = true
          totalMini = totalMini + cnt
          line = "* " .. line -- mark fuel line
        else
          line = "  " .. line
        end
        table.insert(lines, line)
        shownSub = true
      end
    end

    table.insert(lines, 1, ("#%s %s [%s]%s"):format(
      rid, rname, rstate, anyMini and "  (mini charcoal in list)" or ""))

    if not shownSub then
      -- show a single line if no item breakdown was provided
      local want = tonumber(r.minCount) or tonumber(r.count) or 0
      table.insert(lines, "  - "..want.."x (no item breakdown)")
    end

    table.insert(lines, "") -- blank spacer between requests
  end

  return lines, totalMini
end

-- UI
local function drawDashboard(status)
  local out = {
    "MineColonies Requests • Mini Charcoal Auto-Crafter",
    ("Output/CRAFT yield per pulse: %d"):format(OUTPUT_PER_PULSE),
    ("Last action: %s"):format(status.lastAction or "-"),
    ("Planned: %d requested → %d to craft → %d pulses"):format(
      status.req or 0, status.toCraft or 0, status.pulses or 0),
    ""
  }
  for _, line in ipairs(status.reqLines or {}) do
    table.insert(out, line)
  end

  if useMonitor then
    mon.clear()
    mon.setCursorPos(1,1)
    local y = 1
    for _, line in ipairs(out) do
      mon.setCursorPos(1, y)
      mon.write(line)
      y = y + 1
      if y > 19 then break end
    end
  else
    term.clear()
    term.setCursorPos(1,1)
    for _, line in ipairs(out) do print(line) end
  end
end

-- Main loop
local status = { lastAction = "Idle" }
print("Mini Charcoal dashboard + automation started.")
while true do
  -- 1) Read requests & compute total mini charcoal asked for
  local reqLines, totalMini = readRequests()
  status.reqLines = reqLines
  status.req = totalMini

  -- 2) If any requested, plan to craft 2x
  if totalMini > 0 then
    status.toCraft = totalMini * 2
    status.pulses  = math.ceil(status.toCraft / OUTPUT_PER_PULSE)
    status.lastAction = ("Planning %d pulses for %d items"):format(status.pulses, status.toCraft)
    drawDashboard(status)

    -- 3) Execute pulses (crafting)
    pulseCrafter(status.pulses, status)
    drawDashboard(status)

    -- brief pause so MineColonies can update requests
    sleep(1)
  else
    status.toCraft = 0
    status.pulses  = 0
    status.lastAction = "Idle (no mini charcoal requests)"
    drawDashboard(status)
    sleep(POLL_IDLE_SEC)
  end
end

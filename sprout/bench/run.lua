-- bench/run.lua -- orchestrator: time Sprout vs Python, report ratios.
-- Usage: luajit sprout/bench/run.lua

local function time_cmd(cmd)
  local t0 = os.clock()
  -- Use os.execute with a wall-clock-ish wrapper.  For benchmarking the
  -- compiled program we shell out so each run is its own process; that's
  -- the apples-to-apples comparison with python3.
  local start = io.popen("date +%s%N"):read("*a")
  os.execute(cmd .. " > /dev/null")
  local fin = io.popen("date +%s%N"):read("*a")
  return (tonumber(fin) - tonumber(start)) / 1e9
end

local benches = {
  { name = "sum_1m", sprout = "sprout/bench/sum_list.sprout",
                     py     = "sprout/bench/sum_list.py" },
  { name = "sum_5m", sprout = "sprout/bench/sum_5m.sprout",
                     py     = "sprout/bench/sum_5m.py" },
}

io.write(string.format("%-12s %10s %10s %10s\n", "bench", "sprout(s)", "python(s)", "ratio"))
io.write(string.rep("-", 50) .. "\n")

for _, b in ipairs(benches) do
  local s = time_cmd("luajit sprout/init.lua " .. b.sprout)
  local p = time_cmd("python3 " .. b.py)
  local ratio = s > 0 and (p / s) or 0
  io.write(string.format("%-12s %10.3f %10.3f %9.2fx\n", b.name, s, p, ratio))
end

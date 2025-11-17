--------------------------------------------------------------------------------
-- LabJack T7 - MUX80 Strain Gauge & PT Sensor Data Acquisition
-- Purpose: Read 9 differential strain gauges via MUX80 and 1 PT sensor
-- Kipling Compatible - Real-time plotting enabled
-- Author: Generated for LabJack T7 DAQ System
-- Date: 2025-11-17
--------------------------------------------------------------------------------
--
-- HOW TO USE IN KIPLING:
-- 1. Open Kipling and connect to your T7
-- 2. Go to the Lua Script Debugger tab
-- 3. Paste this script into the editor
-- 4. Configure the parameters below (gain, channels, timing, etc.)
-- 5. Click "Run Script" to start data acquisition
-- 6. Real-time data will print to console (can be plotted in Kipling)
-- 7. Optional: Enable CSV logging to microSD card
--
-- REAL-TIME PLOTTING:
-- - Data is printed in CSV format: timestamp,sg1,sg2,...,sg9,pt
-- - Use Kipling's "Graph" feature to visualize data in real-time
-- - Adjust PRINT_INTERVAL_MS to control update rate
--
-- MUX80 X4 CONNECTOR NOTES:
-- - X4 FIO0-FIO7 map to extended channels AIN88-AIN95
-- - For differential: negative channel = positive channel + 8
-- - Example: AIN88(+) pairs with AIN96(-), AIN89(+) with AIN97(-), etc.
--
--------------------------------------------------------------------------------

-- Disable truncation warnings
MB.writeName("LUA_NO_WARN_TRUNCATION", 1)

--------------------------------------------------------------------------------
-- CONFIGURATION SECTION - EASILY ADJUSTABLE PARAMETERS
--------------------------------------------------------------------------------

-- Gain Settings (LabJack T7 gain options: 1, 10, 100, 1000)
-- Higher gain = better resolution for small signals
local STRAIN_GAIN = 100          -- Gain for all strain gauge channels
local PT_GAIN = 1                -- Gain for PT sensor channel

-- Strain Gauge Configuration
local NUM_STRAIN_GAUGES = 9      -- Total number of strain gauges

-- MUX80 Configuration
-- IMPORTANT: When using MUX80, only AIN0-3 are available for built-in differential!
--            AIN4-13 are NOT available when MUX80 is connected.
--            See documentation: how_to_diff_input_mux80.md
--
-- Built-in differential pairs (use these with MUX80):
--   - AIN0 (+) with AIN1 (-) ← Use this for MUX80 #1
--   - AIN2 (+) with AIN3 (-) ← Use this for MUX80 #2
--
-- For 9 strain gauges with MUX80, recommended configuration:
--   - 2 MUX80 boards on AIN0/1 and AIN2/3 (8 channels total)
--   - 1 direct differential connection on AIN8/9 (9th channel)
--
-- Extended channels (if using X4 connector with CB37):
--   - Use extended channel numbers (e.g., AIN64-71 for X3, AIN88-95 for X4)
--   - Negative channel = Positive channel + 8
--   - Example: AIN64(+) pairs with AIN72(-), AIN88(+) pairs with AIN96(-)
--
local MUX_CONFIGS = {
  -- MUX80 #1 - Strain Gauges 1-4
  -- Using AIN0/AIN1 differential pair (built-in, compatible with MUX80)
  {
    enable_dio = 0,              -- DIO line for MUX enable (FIO0)
    address_dio = {1, 2},        -- DIO lines for address bits (FIO1, FIO2)
    ain_pos = 0,                 -- AIN0+ for differential input
    ain_neg = 1,                 -- AIN1- for differential input
    num_channels = 4             -- Number of channels on this MUX
  },
  -- MUX80 #2 - Strain Gauges 5-8
  -- Using AIN2/AIN3 differential pair (built-in, compatible with MUX80)
  {
    enable_dio = 3,              -- DIO line for MUX enable (FIO3)
    address_dio = {4, 5},        -- DIO lines for address bits (FIO4, FIO5)
    ain_pos = 2,                 -- AIN2+ for differential input
    ain_neg = 3,                 -- AIN3- for differential input
    num_channels = 4             -- Number of channels on this MUX
  },
  -- Strain Gauge 9 - Direct connection (no MUX)
  -- Using AIN8/AIN9 differential pair (AIN8-13 available when NOT using them for MUX)
  -- Alternative: Use extended channels if using X-series connectors
  {
    enable_dio = nil,            -- No MUX enable (direct connection)
    address_dio = {},            -- No address lines (direct connection)
    ain_pos = 8,                 -- AIN8+ for differential input
    ain_neg = 9,                 -- AIN9- for differential input
    num_channels = 1             -- Single direct channel
  }
}

-- PT Sensor Configuration (4-20mA Current Loop)
-- For 4-20mA sensors, use a shunt resistor to convert current to voltage
-- Common values: 50Ω (0.2-1.0V), 100Ω (0.4-2.0V), 249Ω (1.0-5.0V)
local PT_AIN = 6                 -- AIN6 for PT sensor (single-ended)
local PT_SHUNT_RESISTOR = 100    -- Shunt resistor value in Ohms (default: 100Ω)
                                  -- 4mA * 100Ω = 0.4V, 20mA * 100Ω = 2.0V

-- Data Output Configuration
-- Results stored in USER_RAM registers for reading by host computer
local USER_RAM_BASE = 46000      -- Base address for strain gauge data
local USER_RAM_PT = 46020        -- Address for PT sensor data
local USER_RAM_STATUS = 46022    -- Status register (0=ok, >0=error code)

-- Timing Configuration
local SCAN_RATE_MS = 100         -- Time between complete scans (milliseconds)
local PRINT_INTERVAL_MS = 500    -- Time between console prints for plotting (ms)
local SETTLING_TIME_US = 500     -- Settling time after MUX switch (microseconds)

-- Data Logging Configuration (T7-Pro with microSD card)
local ENABLE_FILE_LOGGING = false -- Set to true to enable CSV logging to SD card
local LOG_FILENAME = "daq_log.csv" -- CSV file name on microSD card
local LOG_INTERVAL_MS = 1000     -- Time between file writes (ms)

--------------------------------------------------------------------------------
-- INITIALIZATION
--------------------------------------------------------------------------------

print("==============================================")
print("LabJack T7 Strain Gauge & PT DAQ System")
print("Kipling Real-Time Data Acquisition")
print("==============================================")
print(string.format("Strain Gauges: %d (Gain: %d)", NUM_STRAIN_GAUGES, STRAIN_GAIN))
print(string.format("PT Sensor (4-20mA): AIN%d, Shunt: %dΩ, Gain: %d", PT_AIN, PT_SHUNT_RESISTOR, PT_GAIN))
print(string.format("Scan Rate: %d ms", SCAN_RATE_MS))
print(string.format("Print Interval: %d ms", PRINT_INTERVAL_MS))
print(string.format("CSV Logging: %s", ENABLE_FILE_LOGGING and "ENABLED" or "DISABLED"))
print("==============================================")

-- Ensure analog inputs are powered on
MB.writeName("POWER_AIN", 1)

-- Configure all DIO pins as outputs for MUX control
for i, mux in ipairs(MUX_CONFIGS) do
  if mux.enable_dio then  -- Only configure if MUX is used (not direct connection)
    -- Set enable pin as output
    local enable_name = string.format("DIO%d_DIRECTION", mux.enable_dio)
    MB.writeName(enable_name, 1)  -- 1 = output

    -- Set address pins as outputs
    for j, addr_pin in ipairs(mux.address_dio) do
      local addr_name = string.format("DIO%d_DIRECTION", addr_pin)
      MB.writeName(addr_name, 1)  -- 1 = output
    end

    -- Disable MUX initially (active low typically)
    local dio_name = string.format("DIO%d", mux.enable_dio)
    MB.writeName(dio_name, 1)  -- Disable (high)

    print(string.format("MUX #%d configured: Enable=DIO%d, AIN%d/AIN%d",
                        i, mux.enable_dio, mux.ain_pos, mux.ain_neg))
  else
    -- Direct connection (no MUX)
    print(string.format("Channel #%d (direct): AIN%d/AIN%d", i, mux.ain_pos, mux.ain_neg))
  end
end

-- Configure analog input resolution and settling time
MB.writeName("AIN_ALL_RESOLUTION_INDEX", 8)  -- Higher resolution
MB.writeName("AIN_ALL_SETTLING_US", SETTLING_TIME_US)

-- Initialize file logging if enabled
local log_file = nil
if ENABLE_FILE_LOGGING then
  -- Check if device has SD card support (bit 3 = 8 in HARDWARE_INSTALLED)
  local hardware = MB.readName("HARDWARE_INSTALLED")
  local has_sd = (bit.band(hardware, 8) == 8)

  if has_sd then
    log_file = io.open(LOG_FILENAME, "w")
    if log_file then
      -- Write CSV header
      local header = "Timestamp_ms"
      for i = 1, NUM_STRAIN_GAUGES do
        header = header .. string.format(",SG%d_V", i)
      end
      header = header .. ",PT_mA\n"
      log_file:write(header)
      log_file:flush()
      print(string.format("Logging to: %s", LOG_FILENAME))
    else
      print("ERROR: Could not open log file!")
      ENABLE_FILE_LOGGING = false
    end
  else
    print("WARNING: microSD card not detected. Logging disabled.")
    print("         (SD card feature requires T7-Pro)")
    ENABLE_FILE_LOGGING = false
  end
end

-- Setup interval timers for periodic operations
LJ.IntervalConfig(0, SCAN_RATE_MS)      -- Interval 0: Data acquisition
LJ.IntervalConfig(1, PRINT_INTERVAL_MS) -- Interval 1: Console output
if ENABLE_FILE_LOGGING then
  LJ.IntervalConfig(2, LOG_INTERVAL_MS) -- Interval 2: File logging
end

print("Initialization complete. Starting acquisition...")
print("==============================================")

-- Print CSV header for Kipling plotting
local csv_header = "Time_ms"
for i = 1, NUM_STRAIN_GAUGES do
  csv_header = csv_header .. string.format(",SG%d", i)
end
csv_header = csv_header .. ",PT"
print(csv_header)

--------------------------------------------------------------------------------
-- HELPER FUNCTIONS
--------------------------------------------------------------------------------

-- Function to set MUX address (2-bit address for 4 channels)
local function setMuxAddress(mux_config, channel)
  if not mux_config.enable_dio then return end  -- Skip for direct connections

  -- Channel is 0-3 for 4-channel MUX
  local addr_bit0 = channel % 2
  local addr_bit1 = math.floor(channel / 2) % 2

  -- Set address bit 0
  local dio0_name = string.format("DIO%d", mux_config.address_dio[1])
  MB.writeName(dio0_name, addr_bit0)

  -- Set address bit 1
  local dio1_name = string.format("DIO%d", mux_config.address_dio[2])
  MB.writeName(dio1_name, addr_bit1)
end

-- Function to enable/disable MUX (assumes active-low enable)
local function setMuxEnable(mux_config, enable)
  if not mux_config.enable_dio then return end  -- Skip for direct connections

  local dio_name = string.format("DIO%d", mux_config.enable_dio)
  if enable then
    MB.writeName(dio_name, 0)  -- Enable (low)
  else
    MB.writeName(dio_name, 1)  -- Disable (high)
  end
end

-- Function to read differential analog input with specified gain
local function readDifferential(ain_pos, ain_neg, gain)
  -- Set gain for positive channel
  local gain_name = string.format("AIN%d_RANGE", ain_pos)

  -- LabJack gain to range mapping:
  -- Gain 1 = ±10V (range = 10.0)
  -- Gain 10 = ±1V (range = 1.0)
  -- Gain 100 = ±0.1V (range = 0.1)
  -- Gain 1000 = ±0.01V (range = 0.01)
  local range = 10.0 / gain
  MB.writeName(gain_name, range)

  -- Read differential voltage
  local neg_ch_name = string.format("AIN%d_NEGATIVE_CH", ain_pos)
  MB.writeName(neg_ch_name, ain_neg)

  -- Perform read
  local voltage_name = string.format("AIN%d", ain_pos)
  local voltage = MB.readName(voltage_name)

  return voltage
end

-- Function to read single-ended analog input with specified gain
local function readSingleEnded(ain_channel, gain)
  -- Set gain for channel
  local gain_name = string.format("AIN%d_RANGE", ain_channel)

  -- LabJack gain to range mapping:
  -- Gain 1 = ±10V (range = 10.0)
  -- Gain 10 = ±1V (range = 1.0)
  -- Gain 100 = ±0.1V (range = 0.1)
  -- Gain 1000 = ±0.01V (range = 0.01)
  local range = 10.0 / gain
  MB.writeName(gain_name, range)

  -- Set to single-ended mode (negative channel = 199 for GND)
  local neg_ch_name = string.format("AIN%d_NEGATIVE_CH", ain_channel)
  MB.writeName(neg_ch_name, 199)

  -- Perform read
  local voltage_name = string.format("AIN%d", ain_channel)
  local voltage = MB.readName(voltage_name)

  return voltage
end

-- Function to read a single strain gauge via MUX
local function readStrainGauge(mux_index, channel_index)
  local mux = MUX_CONFIGS[mux_index]

  -- Set MUX address
  setMuxAddress(mux, channel_index)

  -- Enable MUX
  setMuxEnable(mux, true)

  -- Wait for settling
  MB.wait(SETTLING_TIME_US)

  -- Read differential input with gain
  local voltage = readDifferential(mux.ain_pos, mux.ain_neg, STRAIN_GAIN)

  -- Disable MUX
  setMuxEnable(mux, false)

  return voltage
end

-- Function to read PT sensor (4-20mA current loop)
local function readPTSensor()
  -- Read voltage across shunt resistor
  local voltage = readSingleEnded(PT_AIN, PT_GAIN)

  -- Convert voltage to current using Ohm's law: I = V / R
  -- Current in milliamps
  local current_mA = (voltage / PT_SHUNT_RESISTOR) * 1000

  return current_mA
end

--------------------------------------------------------------------------------
-- MAIN ACQUISITION LOOP
--------------------------------------------------------------------------------

local scan_count = 0
local error_count = 0

-- Data buffers for current readings
local strain_voltages = {}
local pt_current = 0

-- Timing
local start_time = MB.readName("CORE_TIMER")  -- Microseconds

while true do
  -- Check if it's time to acquire data
  local scan_interval = LJ.CheckInterval(0)

  if scan_interval == 1 then
    -- Clear status
    MB.writeName(string.format("USER_RAM%d_F32", USER_RAM_STATUS - 46000), 0)

    -- Read all strain gauges
    local strain_index = 0
    for mux_idx, mux in ipairs(MUX_CONFIGS) do
      for ch = 0, mux.num_channels - 1 do
        strain_index = strain_index + 1
        if strain_index <= NUM_STRAIN_GAUGES then
          -- Read strain gauge
          local voltage = readStrainGauge(mux_idx, ch)
          strain_voltages[strain_index] = voltage

          -- Store in USER_RAM (each reading takes 4 bytes as F32)
          local ram_addr = USER_RAM_BASE + (strain_index - 1) * 2
          local ram_name = string.format("USER_RAM%d_F32", ram_addr - 46000)
          MB.writeName(ram_name, voltage)
        end
      end
    end

    -- Read PT sensor (returns current in mA)
    pt_current = readPTSensor()
    local pt_ram_name = string.format("USER_RAM%d_F32", USER_RAM_PT - 46000)
    MB.writeName(pt_ram_name, pt_current)

    scan_count = scan_count + 1
  end

  -- Check if it's time to print data for Kipling plotting
  local print_interval = LJ.CheckInterval(1)
  if print_interval == 1 and scan_count > 0 then
    -- Get current timestamp in milliseconds
    local current_time = MB.readName("CORE_TIMER")
    local timestamp_ms = (current_time - start_time) / 1000

    -- Build CSV output line
    local output = string.format("%.0f", timestamp_ms)
    for i = 1, NUM_STRAIN_GAUGES do
      output = output .. string.format(",%.6f", strain_voltages[i] or 0)
    end
    output = output .. string.format(",%.3f", pt_current)

    -- Print to console (for Kipling plotting)
    print(output)
  end

  -- Check if it's time to log data to file
  if ENABLE_FILE_LOGGING and log_file then
    local log_interval = LJ.CheckInterval(2)
    if log_interval == 1 and scan_count > 0 then
      -- Get current timestamp
      local current_time = MB.readName("CORE_TIMER")
      local timestamp_ms = (current_time - start_time) / 1000

      -- Build CSV line
      local log_line = string.format("%.0f", timestamp_ms)
      for i = 1, NUM_STRAIN_GAUGES do
        log_line = log_line .. string.format(",%.6f", strain_voltages[i] or 0)
      end
      log_line = log_line .. string.format(",%.3f", pt_current) .. "\n"

      -- Write to file
      log_file:write(log_line)
      log_file:flush()
    end
  end

  -- Small delay to prevent CPU overload
  MB.wait(1000)  -- 1ms
end

--------------------------------------------------------------------------------
-- CLEANUP (unreachable in infinite loop, but good practice)
--------------------------------------------------------------------------------

if log_file then
  log_file:close()
end

print("Stopping Lua script...")
MB.writeName("LUA_RUN", 0)

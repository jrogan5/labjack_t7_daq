--------------------------------------------------------------------------------
-- LabJack T7 - MUX80 Strain Gauge & PT Sensor Data Acquisition
-- Purpose: Read 9 differential strain gauges via MUX80 and 1 PT sensor
-- Author: Generated for LabJack T7 DAQ System
-- Date: 2025-11-16
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
-- The MUX80 in X4 mode provides 4 differential channels per board
-- For 9 channels, you'll need 3 MUX80 boards (or 2 boards + 1 direct channel)
local MUX_CONFIGS = {
  -- MUX80 #1 - Strain Gauges 1-4
  {
    enable_dio = 0,              -- DIO line for MUX enable (FIO0)
    address_dio = {1, 2},        -- DIO lines for address bits (FIO1, FIO2)
    ain_pos = 0,                 -- AIN0+ for differential input
    ain_neg = 1,                 -- AIN1- for differential input
    num_channels = 4             -- Number of channels on this MUX
  },
  -- MUX80 #2 - Strain Gauges 5-8
  {
    enable_dio = 3,              -- DIO line for MUX enable (FIO3)
    address_dio = {4, 5},        -- DIO lines for address bits (FIO4, FIO5)
    ain_pos = 2,                 -- AIN2+ for differential input
    ain_neg = 3,                 -- AIN3- for differential input
    num_channels = 4             -- Number of channels on this MUX
  },
  -- MUX80 #3 - Strain Gauge 9 (or use direct connection)
  {
    enable_dio = 6,              -- DIO line for MUX enable (FIO6)
    address_dio = {7, 8},        -- DIO lines for address bits (FIO7, EIO0)
    ain_pos = 4,                 -- AIN4+ for differential input
    ain_neg = 5,                 -- AIN5- for differential input
    num_channels = 1             -- Only using 1 channel on this MUX
  }
}

-- PT Sensor Configuration
local PT_AIN_POS = 6             -- AIN6+ for PT sensor (differential)
local PT_AIN_NEG = 7             -- AIN7- for PT sensor (differential)

-- Data Output Configuration
-- Results stored in USER_RAM registers for reading by host computer
local USER_RAM_BASE = 46000      -- Base address for strain gauge data
local USER_RAM_PT = 46020        -- Address for PT sensor data
local USER_RAM_STATUS = 46022    -- Status register (0=ok, >0=error code)

-- Timing Configuration
local SCAN_RATE_MS = 100         -- Time between complete scans (milliseconds)
local SETTLING_TIME_US = 500     -- Settling time after MUX switch (microseconds)

--------------------------------------------------------------------------------
-- INITIALIZATION
--------------------------------------------------------------------------------

print("==============================================")
print("LabJack T7 Strain Gauge & PT DAQ System")
print("==============================================")
print(string.format("Strain Gauges: %d (Gain: %d)", NUM_STRAIN_GAUGES, STRAIN_GAIN))
print(string.format("PT Sensor: AIN%d/AIN%d (Gain: %d)", PT_AIN_POS, PT_AIN_NEG, PT_GAIN))
print(string.format("Scan Rate: %d ms", SCAN_RATE_MS))
print("==============================================")

-- Configure all DIO pins as outputs for MUX control
for i, mux in ipairs(MUX_CONFIGS) do
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
end

-- Configure analog input resolution and settling time
MB.writeName("AIN_ALL_RESOLUTION_INDEX", 8)  -- Higher resolution
MB.writeName("AIN_ALL_SETTLING_US", SETTLING_TIME_US)

print("Initialization complete. Starting acquisition...")
print("==============================================")

--------------------------------------------------------------------------------
-- HELPER FUNCTIONS
--------------------------------------------------------------------------------

-- Function to set MUX address (2-bit address for 4 channels)
local function setMuxAddress(mux_config, channel)
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

-- Function to read PT sensor
local function readPTSensor()
  return readDifferential(PT_AIN_POS, PT_AIN_NEG, PT_GAIN)
end

--------------------------------------------------------------------------------
-- MAIN ACQUISITION LOOP
--------------------------------------------------------------------------------

local scan_count = 0
local error_count = 0

-- Calculate interval in microseconds
local interval_us = SCAN_RATE_MS * 1000

while true do
  local loop_start = MB.readName("CORE_TIMER")

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

        -- Store in USER_RAM (each reading takes 4 bytes as F32)
        local ram_addr = USER_RAM_BASE + (strain_index - 1) * 2
        local ram_name = string.format("USER_RAM%d_F32", ram_addr - 46000)
        MB.writeName(ram_name, voltage)

        -- Debug output for first scan
        if scan_count == 0 then
          print(string.format("Strain Gauge %d: %.6f V", strain_index, voltage))
        end
      end
    end
  end

  -- Read PT sensor
  local pt_voltage = readPTSensor()
  local pt_ram_name = string.format("USER_RAM%d_F32", USER_RAM_PT - 46000)
  MB.writeName(pt_ram_name, pt_voltage)

  if scan_count == 0 then
    print(string.format("PT Sensor: %.6f V", pt_voltage))
    print("==============================================")
    print("Data acquisition running. Output to USER_RAM.")
  end

  scan_count = scan_count + 1

  -- Status update every 100 scans
  if scan_count % 100 == 0 then
    print(string.format("Scan #%d complete (Errors: %d)", scan_count, error_count))
  end

  -- Calculate elapsed time and sleep for remainder
  local loop_end = MB.readName("CORE_TIMER")
  local elapsed_us = loop_end - loop_start
  local sleep_us = interval_us - elapsed_us

  if sleep_us > 0 then
    MB.wait(sleep_us)
  else
    error_count = error_count + 1
    -- Set error status
    MB.writeName(string.format("USER_RAM%d_F32", USER_RAM_STATUS - 46000), 1)
  end
end

--------------------------------------------------------------------------------
-- CLEANUP (unreachable in infinite loop, but good practice)
--------------------------------------------------------------------------------

print("Stopping Lua script...")
MB.writeName("LUA_RUN", 0)

set_global_assignment -name FAMILY "MAX 10"
set_global_assignment -name DEVICE 10M50DAF484C7G

# System Clocks and Reset
set_location_assignment PIN_P11 -to MAX10_CLK1_50
set_location_assignment PIN_B8 -to KEY[0]

# Accelerometer (ADXL345)
set_location_assignment PIN_AB16 -to GSENSOR_CS_N
set_location_assignment PIN_AB15 -to GSENSOR_SCLK
set_location_assignment PIN_V11 -to GSENSOR_SDI
set_location_assignment PIN_V12 -to GSENSOR_SDO

# 7-Segment Displays (Step Count)
set_location_assignment PIN_C14 -to HEX0[0]
set_location_assignment PIN_E15 -to HEX0[1]
set_location_assignment PIN_C15 -to HEX0[2]
set_location_assignment PIN_C16 -to HEX0[3]
set_location_assignment PIN_E16 -to HEX0[4]
set_location_assignment PIN_D17 -to HEX0[5]
set_location_assignment PIN_C17 -to HEX0[6]
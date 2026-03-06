// ============================================================
// Module      : tt_um_pedometer
// Description : Tiny Tapeout Top-Level Wrapper
//               Ultra Low Power Pedometer ASIC
//               SASTRA Deemed University, Thanjavur
//
// Author      : Dr. Sriram Anbalagan
// Date        : Feb 2026
// PDK         : SkyWater SKY130 (ChipFoundry)
// Shuttle     : Tiny Tapeout SKY130
//
// PIN MAPPING:
// ============
//  ui_in[0]  -> spi_clk      (SPI Clock from MEMS accelerometer)
//  ui_in[1]  -> spi_mosi     (SPI Data In — 48-bit X/Y/Z frame)
//  ui_in[2]  -> spi_cs_n     (SPI Chip Select, active LOW)
//  ui_in[3]  -> byte_sel     (0 = step_count[7:0], 1 = step_count[15:8])
//  ui_in[7:4] -> reserved
//
//  uo_out[7:0] -> step_count[7:0]  when byte_sel = 0
//                 step_count[15:8] when byte_sel = 1
//
//  uio_out[0]  -> step_detected    (pulses HIGH for 1 clk per step)
//  uio_out[1]  -> artifact_flag    (HIGH when motion rejected)
//  uio_oe      -> 8'b00000011      (uio[0] and uio[1] are outputs)
//
//  clk         -> 32.768 kHz system clock
//  rst_n       -> Active LOW reset
// ============================================================
`default_nettype none
`timescale 1ns/1ps

module tt_um_pedometer (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path (unused)
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (1=output)
    input  wire       ena,      // Always 1 when powered
    input  wire       clk,      // 32.768 kHz clock
    input  wire       rst_n     // Active LOW reset
);

    // --------------------------------------------------------
    // Input signal mapping
    // --------------------------------------------------------
    wire spi_clk   = ui_in[0];
    wire spi_mosi  = ui_in[1];
    wire spi_cs_n  = ui_in[2];
    wire byte_sel  = ui_in[3];  // 0 = low byte, 1 = high byte

    // --------------------------------------------------------
    // Internal signals
    // --------------------------------------------------------
    wire [15:0] step_count;
    wire        step_detected;
    wire        artifact_flag;

    // --------------------------------------------------------
    // Pedometer Core Instantiation
    // --------------------------------------------------------
    pedometer_core u_core (
        .clk           (clk),
        .rst_n         (rst_n),
        .spi_clk       (spi_clk),
        .spi_mosi      (spi_mosi),
        .spi_cs_n      (spi_cs_n),
        .step_count    (step_count),
        .step_detected (step_detected),
        .artifact_flag (artifact_flag)
    );

    // --------------------------------------------------------
    // Output mapping
    // byte_sel=0 → uo_out = step_count[7:0]  (low byte)
    // byte_sel=1 → uo_out = step_count[15:8] (high byte)
    // --------------------------------------------------------
    assign uo_out  = byte_sel ? step_count[15:8] : step_count[7:0];

    // --------------------------------------------------------
    // Bidirectional IO — used as outputs only
    // uio_out[0] = step_detected
    // uio_out[1] = artifact_flag
    // uio_out[7:2] = 0 (unused)
    // --------------------------------------------------------
    assign uio_out = {6'b000000, artifact_flag, step_detected};
    assign uio_oe  = 8'b00000011;  // uio[0] and uio[1] = outputs

    // Suppress unused input warning
    wire _unused = &{uio_in, ui_in[7:4], ena, 1'b0};

endmodule

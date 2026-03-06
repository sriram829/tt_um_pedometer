`default_nettype wire
// ============================================================
// Module      : pedometer_core
// Description : Ultra Low Power Pedometer Core
//               SPI Receiver + Alpha-Max-Beta-Min Magnitude +
//               8-tap Moving Average + Gait Regularity Filter
//
// Author      : Dr. Sriram Anbalagan
// Date        : Feb 2026
// PDK         : SkyWater SKY130 130nm CMOS
// Clock       : 32.768 kHz (30517.58 ns period)
// Power       : 656 nW (ultra-low power)
//
// NOVELTY:
//   1. Alpha Max Beta Min magnitude — no multiplier, no sqrt
//   2. Hardware gait regularity filter — artifact rejection
//   3. Fully open-source RTL-to-GDSII (Yosys + OpenROAD)
//   4. SPI 48-bit frame (16b X + 16b Y + 16b Z)
// ============================================================
`default_nettype none
`timescale 1ns/1ps

module pedometer_core (
    input  wire        clk,           // 32.768 kHz system clock
    input  wire        rst_n,         // Active LOW reset
    // SPI Interface (from MEMS accelerometer: MPU6050 / ADXL345 / BMI160)
    input  wire        spi_clk,       // SPI clock (external)
    input  wire        spi_mosi,      // SPI data in
    input  wire        spi_cs_n,      // SPI chip select (active LOW)
    // Outputs
    output reg  [15:0] step_count,    // Cumulative step counter
    output reg         step_detected, // Pulses HIGH 1 cycle per step
    output reg         artifact_flag  // HIGH when motion is rejected
);

    // ============================================================
    // STAGE 1: SPI RECEIVER
    // Receives 48-bit frames: [47:32]=X, [31:16]=Y, [15:0]=Z
    // Synchronised to system clock (32.768 kHz)
    // ============================================================

    // Synchronise SPI signals into system clock domain
    reg spi_clk_r1,  spi_clk_r2;
    reg spi_mosi_r;
    reg spi_cs_n_r,  spi_cs_n_prev;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            spi_clk_r1   <= 1'b0;
            spi_clk_r2   <= 1'b0;
            spi_mosi_r   <= 1'b0;
            spi_cs_n_r   <= 1'b1;
            spi_cs_n_prev<= 1'b1;
        end else begin
            spi_clk_r1    <= spi_clk;
            spi_clk_r2    <= spi_clk_r1;
            spi_mosi_r    <= spi_mosi;
            spi_cs_n_prev <= spi_cs_n_r;
            spi_cs_n_r    <= spi_cs_n;
        end
    end

    // Edge detection
    wire spi_clk_rising = spi_clk_r1 & ~spi_clk_r2;
    wire spi_cs_rising  = spi_cs_n_r & ~spi_cs_n_prev;  // CS deasserted = frame done

    // SPI shift register and bit counter
    reg [47:0] spi_shift_reg;
    reg  [5:0] spi_bit_cnt;

    // Latched accelerometer values
    reg signed [15:0] acc_x_lat;
    reg signed [15:0] acc_y_lat;
    reg signed [15:0] acc_z_lat;
    reg                new_sample;   // Pulses 1 cycle when new frame arrives

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            spi_shift_reg <= 48'd0;
            spi_bit_cnt   <= 6'd0;
            acc_x_lat     <= 16'sd0;
            acc_y_lat     <= 16'sd0;
            acc_z_lat     <= 16'sd0;
            new_sample    <= 1'b0;
        end else begin
            new_sample <= 1'b0;  // default

            if (!spi_cs_n_r) begin
                // CS active — shift in data on rising SPI clock
                if (spi_clk_rising) begin
                    spi_shift_reg <= {spi_shift_reg[46:0], spi_mosi_r};
                    spi_bit_cnt   <= spi_bit_cnt + 6'd1;
                end
            end else begin
                spi_bit_cnt <= 6'd0;
            end

            // Debug: always print CS rising events
            if (spi_cs_rising) begin
            end
            // CS rising edge with 48 bits received — latch frame
            if (spi_cs_rising && spi_bit_cnt == 6'd48) begin
                acc_x_lat  <= spi_shift_reg[47:32];
                acc_y_lat  <= spi_shift_reg[31:16];
                acc_z_lat  <= spi_shift_reg[15:0];
                new_sample <= 1'b1;
            end
        end
    end

    // ============================================================
    // STAGE 2: ALPHA MAX BETA MIN MAGNITUDE APPROXIMATION
    // Formula: |V| ≈ alpha*max(|x|,|y|,|z|) + beta*min2
    // alpha = 1, beta = 0.5 (>> 1 shift) — 96% accuracy
    // No multipliers, no square root — pure shift + add
    // ============================================================

    function [15:0] abs16;
        input signed [15:0] val;
        begin
            abs16 = (val[15]) ? (~val + 16'd1) : val;
        end
    endfunction

    reg [15:0] mag;   // Computed magnitude
    reg        mag_valid;

    // Pipeline register for magnitude
    reg signed [15:0] ax_r, ay_r, az_r;
    reg                ns_r;
    reg [15:0] ax, ay, az;
    /* verilator lint_off UNUSEDSIGNAL */
    reg [15:0] mn, md, mx;
    /* verilator lint_on UNUSEDSIGNAL */

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ax_r      <= 16'sd0;
            ay_r      <= 16'sd0;
            az_r      <= 16'sd0;
            ns_r      <= 1'b0;
            mag       <= 16'd0;
            mag_valid <= 1'b0;
        end else begin
            ax_r      <= acc_x_lat;
            ay_r      <= acc_y_lat;
            az_r      <= acc_z_lat;
            ns_r      <= new_sample;
            mag_valid <= 1'b0;

            if (ns_r) begin
                // Compute absolute values
                /* verilator lint_off UNUSEDSIGNAL */
                /* verilator lint_on UNUSEDSIGNAL */

                ax = abs16(ax_r);
                ay = abs16(ay_r);
                az = abs16(az_r);

                // Sort: find max, mid, min
                if (ax >= ay && ax >= az) begin
                    mx = ax;
                    if (ay >= az) begin md = ay; mn = az; end
                    else          begin md = az; mn = ay; end
                end else if (ay >= ax && ay >= az) begin
                    mx = ay;
                    if (ax >= az) begin md = ax; mn = az; end
                    else          begin md = az; mn = ax; end
                end else begin
                    mx = az;
                    if (ax >= ay) begin md = ax; mn = ay; end
                    else          begin md = ay; mn = ax; end
                end

                // Alpha-Max Beta-Min: mag ≈ max + 0.5*mid
                // (ignoring min for simplicity — 95%+ accuracy)
                mag       <= mx + (md >> 1);
                mag_valid <= 1'b1;
            end
        end
    end

    // ============================================================
    // STAGE 3: 8-TAP MOVING AVERAGE FILTER
    // Smooths noise from MEMS accelerometer
    // Shift register of 8 samples, output = sum >> 3
    // ============================================================

    reg [15:0] tap [0:7];      // 8-sample shift register
    reg [18:0] tap_sum;        // Sum (needs 19 bits: 16+3)
    reg [15:0] mag_smooth;     // Smoothed magnitude
    reg        smooth_valid;

    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tap_sum      <= 19'd0;
            mag_smooth   <= 16'd0;
            smooth_valid <= 1'b0;
            for (i = 0; i < 8; i = i + 1)
                tap[i] <= 16'd0;
        end else begin
            smooth_valid <= 1'b0;
            if (mag_valid) begin
                // Shift register
                tap[7] <= tap[6];
                tap[6] <= tap[5];
                tap[5] <= tap[4];
                tap[4] <= tap[3];
                tap[3] <= tap[2];
                tap[2] <= tap[1];
                tap[1] <= tap[0];
                tap[0] <= mag;

                // Running sum: subtract oldest, add newest
                tap_sum      <= tap_sum - {3'd0, tap[7]} + {3'd0, mag};
                /* verilator lint_off WIDTHTRUNC */
                mag_smooth   <= (tap_sum - {3'd0, tap[7]} + {3'd0, mag}) >> 3;
                /* verilator lint_on WIDTHTRUNC */
                smooth_valid <= 1'b1;
            end
        end
    end

    // ============================================================
    // STAGE 4: STEP DETECTOR WITH GAIT REGULARITY FILTER
    //
    // Threshold-based detection:
    //   Step detected when mag_smooth crosses STEP_THRESHOLD
    //
    // Gait Regularity Filter (Novel):
    //   Valid step interval: 0.4s to 2.0s @ 32.768 kHz
    //   MIN_INTERVAL = 0.4 * 32768 = 13107 clocks
    //   MAX_INTERVAL = 2.0 * 32768 = 65536 clocks
    //   Steps outside this range → artifact_flag = HIGH
    // ============================================================

    // Thresholds (tuned for ADXL345 @ ±2g, 256 LSB/g)
    parameter STEP_THRESHOLD = 16'd300;   // ~1.17g peak
    parameter HYSTERESIS     = 16'd100;   // Deadband to avoid double-count

    // Gait regularity window (@ 32.768 kHz)
    parameter MIN_INTERVAL   = 17'd13107; // 0.4 seconds @ 32.768 kHz
    parameter MAX_INTERVAL   = 17'd65535; // 2.0 seconds @ 32.768 kHz

    reg        above_thresh;    // Current state: above threshold?
    reg        prev_above;      // Previous state
    reg [16:0] interval_cnt;    // Counts clocks since last valid step
    /* verilator lint_off UNUSEDSIGNAL */ reg [16:0] last_interval; /* verilator lint_on UNUSEDSIGNAL */   // Stores last detected interval

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            above_thresh  <= 1'b0;
            prev_above    <= 1'b0;
            interval_cnt  <= 17'd0;
            last_interval <= 17'd0;
            step_detected <= 1'b0;
            artifact_flag <= 1'b0;
            step_count    <= 16'd0;
        end else begin
            step_detected <= 1'b0;  // Default: pulse for 1 cycle only
            artifact_flag <= 1'b0;

            // Count clocks between steps
            if (interval_cnt < 17'h1FFFF)
                interval_cnt <= interval_cnt + 17'd1;

            if (smooth_valid) begin
                prev_above <= above_thresh;

                // Hysteresis: enter high state
                if (mag_smooth > STEP_THRESHOLD)
                    above_thresh <= 1'b1;
                // Hysteresis: enter low state with deadband
                else if (mag_smooth < (STEP_THRESHOLD - HYSTERESIS))
                    above_thresh <= 1'b0;

                // Rising edge of threshold crossing = candidate step
                if (above_thresh && !prev_above) begin
                    // ---- GAIT REGULARITY FILTER ----
                    if (interval_cnt < MIN_INTERVAL) begin
                        // Too fast — artifact (hand waving, vibration)
                        artifact_flag <= 1'b1;
                    end else if (interval_cnt > MAX_INTERVAL) begin
                        // Too slow — first step after rest (allow, reset timer)
                        step_detected <= 1'b1;
                        step_count    <= step_count + 16'd1;
                        interval_cnt  <= 17'd0;
                    end else begin
                        // Valid gait interval — count the step
                        step_detected <= 1'b1;
                        step_count    <= step_count + 16'd1;
                        last_interval <= interval_cnt;
                        interval_cnt  <= 17'd0;
                    end
                end
            end
        end
    end

endmodule

module top_pedometer (
    input  MAX10_CLK1_50,
    input  [1:0] KEY,
    output       GSENSOR_CS_N,
    output reg   GSENSOR_SCLK,
    output reg   GSENSOR_SDI,
    input        GSENSOR_SDO,
    output [6:0] HEX0, HEX1, HEX2, HEX3, HEX4, HEX5
);

    wire clk, c1_nc, c2_nc, locked;
    my_pll pll_inst (
        .areset (~KEY[0]), .inclk0 (MAX10_CLK1_50),
        .c0 (clk), .c1 (c1_nc), .c2 (c2_nc), .locked (locked)
    );

    wire rst = !locked || !KEY[0];

    reg cs_assert;
    assign GSENSOR_CS_N = ~cs_assert;

    localparam CLK_DIV = 6'd25;

    // DELTA DETECTION:
    // Instead of checking absolute value, check how much it CHANGED
    // from the previous reading. Noise changes by 1-3. A real footstep
    // changes by 20-60+. Set DELTA_THRESH between those two.
    localparam DELTA_THRESH = 8'd20;   // min change to count as a step
    localparam STEP_GAP     = 17'd400; // min reads between steps

    localparam S_RST_SPI=4'd0, S_PWRUP=4'd1, S_INIT=4'd2,
               S_IDLE   =4'd3, S_READ =4'd4, S_STEP=4'd5;

    reg [3:0]  state;
    reg [7:0]  accel;
    reg [7:0]  accel_prev;    // previous reading
    reg [7:0]  delta;         // absolute difference
    reg [19:0] step_count;
    reg        step_ready;
    reg [24:0] timer;
    reg [16:0] step_gap_cnt;
    reg [15:0] tx;
    reg [7:0]  rx;
    reg [3:0]  bit_idx;
    reg [5:0]  half_cnt;
    reg        phase, spi_busy, spi_start;
    reg [4:0]  resync_cnt;

    always @(posedge clk) begin
        if (rst) begin
            state        <= S_RST_SPI;
            timer        <= 0;
            step_count   <= 0;
            step_ready   <= 1;
            step_gap_cnt <= STEP_GAP;
            accel        <= 0;
            accel_prev   <= 0;
            delta        <= 0;
            cs_assert    <= 0;
            GSENSOR_SCLK <= 1; GSENSOR_SDI <= 0;
            spi_busy<=0; spi_start<=0;
            bit_idx<=0; half_cnt<=0; phase<=0;
            tx<=0; rx<=0; resync_cnt<=0;
        end else begin
            spi_start <= 0;

            // ── SPI engine ───────────────────────────────────
            if (spi_start) begin
                cs_assert<=1; GSENSOR_SCLK<=1; GSENSOR_SDI<=tx[15];
                bit_idx<=15; half_cnt<=0; phase<=0; rx<=0; spi_busy<=1;
            end else if (spi_busy) begin
                half_cnt <= half_cnt + 1;
                if (half_cnt == CLK_DIV-1) begin
                    half_cnt<=0; phase<=~phase;
                    if (phase==0) begin
                        GSENSOR_SCLK<=0; GSENSOR_SDI<=tx[bit_idx];
                    end else begin
                        GSENSOR_SCLK<=1;
                        if (tx[15] && bit_idx>=1 && bit_idx<=7)
                            rx<={rx[6:0], GSENSOR_SDO};
                        if (bit_idx==0) begin
                            cs_assert<=0; GSENSOR_SCLK<=1; spi_busy<=0;
                            if (tx[15]) begin
                                accel_prev <= accel;
                                accel      <= {rx[6:0], GSENSOR_SDO};
                            end
                        end else bit_idx<=bit_idx-1;
                    end
                end
            end

            // ── FSM ──────────────────────────────────────────
            if (!spi_busy && !spi_start) begin
                case (state)
                    S_RST_SPI: begin
                        if (timer<12500) begin
                            timer<=timer+1; cs_assert<=0; GSENSOR_SCLK<=1;
                        end else if (resync_cnt<20) begin
                            if (half_cnt==CLK_DIV-1) begin
                                half_cnt<=0; GSENSOR_SCLK<=~GSENSOR_SCLK;
                                resync_cnt<=resync_cnt+1;
                            end else half_cnt<=half_cnt+1;
                        end else begin
                            cs_assert<=0; GSENSOR_SCLK<=1;
                            timer<=0; state<=S_PWRUP;
                        end
                    end
                    S_PWRUP: begin
                        if (timer<500_000) timer<=timer+1;
                        else begin timer<=0; state<=S_INIT; end
                    end
                    S_INIT: begin
                        tx<=16'h2D08; spi_start<=1; state<=S_IDLE;
                    end
                    S_IDLE: begin
                        if (timer<25_000) timer<=timer+1;
                        else begin timer<=0; state<=S_READ; end
                    end
                    S_READ: begin
                        tx<=16'hB600; spi_start<=1; state<=S_STEP;
                    end

                    S_STEP: begin
                        // Compute absolute delta between readings
                        delta <= (accel >= accel_prev) ?
                                  accel - accel_prev :
                                  accel_prev - accel;

                        if (step_gap_cnt < STEP_GAP)
                            step_gap_cnt <= step_gap_cnt + 1;

                        // Count step if:
                        // - sudden large change (real impact)
                        // - enough time has passed since last step
                        // - armed (not still in same step)
                        if (delta >= DELTA_THRESH && step_ready
                                && step_gap_cnt >= STEP_GAP) begin
                            if (step_count < 20'd999999)
                                step_count <= step_count + 1;
                            step_ready   <= 0;
                            step_gap_cnt <= 0;
                        end

                        // Re-arm when signal stabilizes (small delta = at rest)
                        if (delta < 8'd5) step_ready <= 1;

                        state <= S_IDLE;
                    end
                    default: state <= S_IDLE;
                endcase
            end
        end
    end

    wire [3:0] d0,d1,d2,d3,d4,d5;
    dec6 dec_inst(.val(step_count),.d0(d0),.d1(d1),.d2(d2),
                                   .d3(d3),.d4(d4),.d5(d5));
    seg7 s0(d0,HEX0); seg7 s1(d1,HEX1); seg7 s2(d2,HEX2);
    seg7 s3(d3,HEX3); seg7 s4(d4,HEX4); seg7 s5(d5,HEX5);

endmodule


module dec6(input [19:0] val,
            output reg [3:0] d0,d1,d2,d3,d4,d5);
    reg [19:0] v;
    always @(*) begin
        v=val; d5=0; d4=0; d3=0; d2=0; d1=0; d0=0;
        if(v>=900000)begin d5=9;v=v-900000;end else
        if(v>=800000)begin d5=8;v=v-800000;end else
        if(v>=700000)begin d5=7;v=v-700000;end else
        if(v>=600000)begin d5=6;v=v-600000;end else
        if(v>=500000)begin d5=5;v=v-500000;end else
        if(v>=400000)begin d5=4;v=v-400000;end else
        if(v>=300000)begin d5=3;v=v-300000;end else
        if(v>=200000)begin d5=2;v=v-200000;end else
        if(v>=100000)begin d5=1;v=v-100000;end
        if(v>=90000)begin d4=9;v=v-90000;end else
        if(v>=80000)begin d4=8;v=v-80000;end else
        if(v>=70000)begin d4=7;v=v-70000;end else
        if(v>=60000)begin d4=6;v=v-60000;end else
        if(v>=50000)begin d4=5;v=v-50000;end else
        if(v>=40000)begin d4=4;v=v-40000;end else
        if(v>=30000)begin d4=3;v=v-30000;end else
        if(v>=20000)begin d4=2;v=v-20000;end else
        if(v>=10000)begin d4=1;v=v-10000;end
        if(v>=9000)begin d3=9;v=v-9000;end else
        if(v>=8000)begin d3=8;v=v-8000;end else
        if(v>=7000)begin d3=7;v=v-7000;end else
        if(v>=6000)begin d3=6;v=v-6000;end else
        if(v>=5000)begin d3=5;v=v-5000;end else
        if(v>=4000)begin d3=4;v=v-4000;end else
        if(v>=3000)begin d3=3;v=v-3000;end else
        if(v>=2000)begin d3=2;v=v-2000;end else
        if(v>=1000)begin d3=1;v=v-1000;end
        if(v>=900)begin d2=9;v=v-900;end else
        if(v>=800)begin d2=8;v=v-800;end else
        if(v>=700)begin d2=7;v=v-700;end else
        if(v>=600)begin d2=6;v=v-600;end else
        if(v>=500)begin d2=5;v=v-500;end else
        if(v>=400)begin d2=4;v=v-400;end else
        if(v>=300)begin d2=3;v=v-300;end else
        if(v>=200)begin d2=2;v=v-200;end else
        if(v>=100)begin d2=1;v=v-100;end
        if(v>=90)begin d1=9;v=v-90;end else
        if(v>=80)begin d1=8;v=v-80;end else
        if(v>=70)begin d1=7;v=v-70;end else
        if(v>=60)begin d1=6;v=v-60;end else
        if(v>=50)begin d1=5;v=v-50;end else
        if(v>=40)begin d1=4;v=v-40;end else
        if(v>=30)begin d1=3;v=v-30;end else
        if(v>=20)begin d1=2;v=v-20;end else
        if(v>=10)begin d1=1;v=v-10;end
        d0=v[3:0];
    end
endmodule

module seg7(input [3:0] d, output reg [6:0] seg);
    always @(*) case(d)
        4'd0:seg=7'b1000000; 4'd1:seg=7'b1111001;
        4'd2:seg=7'b0100100; 4'd3:seg=7'b0110000;
        4'd4:seg=7'b0011001; 4'd5:seg=7'b0010010;
        4'd6:seg=7'b0000010; 4'd7:seg=7'b1111000;
        4'd8:seg=7'b0000000; 4'd9:seg=7'b0010000;
        default:seg=7'b1111111;
    endcase
endmodule

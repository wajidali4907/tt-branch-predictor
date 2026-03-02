/*
 * Prediction = MSB of the selected counter (1=Taken, 0=Not Taken)
 *
 * Pin Mapping:
 *   ui_in[3:0]  = pc_index   : selects 1 of 16 PHT entries
 *   ui_in[4]    = outcome    : actual branch result (1=Taken)
 *   ui_in[5]    = update     : 1 = write outcome into PHT on rising edge
 *   ui_in[7:6]  = unused
 *
 *   uo_out[0]   = prediction : 1=Taken, 0=Not Taken
 *   uo_out[2:1] = state      : current 2-bit counter value (debug)
 *   uo_out[7:3] = unused
 */

`default_nettype none

module tt_um_branch_predictor (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

    wire [3:0] pc_index = ui_in[3:0];
    wire       outcome  = ui_in[4];
    wire       update   = ui_in[5];
    reg [1:0] pht [0:15];
    wire [1:0] current = pht[pc_index];
    wire prediction = current[1];
    function [1:0] next_state;
        input [1:0] state;
        input       taken;
        begin
            if (taken)
                next_state = (state == 2'b11) ? 2'b11 : state + 2'b01;
            else
                next_state = (state == 2'b00) ? 2'b00 : state - 2'b01;
        end
    endfunction

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Initialize all counters to Weakly Taken (10)
            for (i = 0; i < 16; i = i + 1)
                pht[i] <= 2'b10;
        end else if (update) begin
            pht[pc_index] <= next_state(current, outcome);
        end
    end

    // Outputs
    assign uo_out[0]   = prediction;
    assign uo_out[2:1] = current;
    assign uo_out[7:3] = 5'b0;

    // Unused pins
    assign uio_out = 8'b0;
    assign uio_oe  = 8'b0;

endmodule

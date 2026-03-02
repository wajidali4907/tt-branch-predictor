`timescale 1ns/1ps

`define START_TESTBENCH  error_o = 0; pass_o = 0; #10;
`define FINISH_WITH_FAIL error_o = 1; pass_o = 0; #10; $finish();
`define FINISH_WITH_PASS pass_o = 1; error_o = 0; #10; $finish();

// ============================================================
// Clock generator
// ============================================================
module nonsynth_clock_gen #(parameter cycle_time_p = 10) (output reg clk_o);
    initial clk_o = 0;
    always #(cycle_time_p/2) clk_o = ~clk_o;
endmodule

// ============================================================
// Reset generator
// ============================================================
module nonsynth_reset_gen
  #(parameter reset_cycles_lo_p = 1,
    parameter reset_cycles_hi_p = 4)
  (input clk_i, output reg async_reset_o);
    integer i;
    initial begin
        async_reset_o = 0;
        for (i = 0; i < reset_cycles_lo_p; i++) @(posedge clk_i);
        async_reset_o = 1;
        for (i = 0; i < reset_cycles_hi_p; i++) @(posedge clk_i);
        async_reset_o = 0;
    end
endmodule

// ============================================================
// TESTBENCH
// ============================================================
module testbench
  (output logic error_o = 1'bx,
   output logic pass_o  = 1'bx);

    wire        clk_i;
    logic       reset_i;

    // DUT signals
    logic [3:0] pc_index;
    logic       outcome;
    logic       update;

    wire [7:0]  ui_in;
    wire [7:0]  uo_out;
    wire [7:0]  uio_in;
    wire [7:0]  uio_out;
    wire [7:0]  uio_oe;

    assign ui_in  = {2'b0, update, outcome, pc_index};
    assign uio_in = 8'b0;

    wire        prediction = uo_out[0];
    wire [1:0]  state      = uo_out[2:1];

    // Clock & Reset
    nonsynth_clock_gen #(.cycle_time_p(10)) cg (.clk_o(clk_i));
    nonsynth_reset_gen #(.reset_cycles_lo_p(1), .reset_cycles_hi_p(4))
        rg (.clk_i(clk_i), .async_reset_o(reset_i));

    // DUT
    tt_um_branch_predictor dut (
        .ui_in   (ui_in),
        .uo_out  (uo_out),
        .uio_in  (uio_in),
        .uio_out (uio_out),
        .uio_oe  (uio_oe),
        .ena     (1'b1),
        .clk     (clk_i),
        .rst_n   (~reset_i)
    );

    // ============================================================
    // SOFTWARE REFERENCE MODEL
    // Mirrors the PHT table in software to predict expected outputs
    // ============================================================
    reg [1:0] ref_pht [0:15];
    integer k;

    // Initialize reference model to match reset state (all WT = 10)
    task ref_reset;
        for (k = 0; k < 16; k = k + 1)
            ref_pht[k] = 2'b10;
    endtask

    // Update reference model
    task ref_update;
        input [3:0] idx;
        input       taken;
        begin
            if (taken)
                ref_pht[idx] = (ref_pht[idx] == 2'b11) ? 2'b11 : ref_pht[idx] + 1;
            else
                ref_pht[idx] = (ref_pht[idx] == 2'b00) ? 2'b00 : ref_pht[idx] - 1;
        end
    endtask

    function automatic [0:0] ref_predict;
        input [3:0] idx;
        ref_predict = ref_pht[idx][1]; // MSB
    endfunction

    // ============================================================
    // Helper tasks
    // ============================================================
    int fail_count;

    // Read prediction (no update)
    task check_prediction;
        input string  test_name;
        input [3:0]   idx;
        input [0:0]   expected_pred;
        begin
            pc_index = idx;
            outcome  = 0;
            update   = 0;
            #2;
            if (prediction !== expected_pred) begin
                $display("FAIL [%s]: pc=%0d expected pred=%0b got=%0b (state=%0b)",
                         test_name, idx, expected_pred, prediction, state);
                fail_count++;
            end else begin
                $display("PASS [%s]: pc=%0d pred=%0b state=%2b",
                         test_name, idx, prediction, state);
            end
        end
    endtask

    // Apply one branch outcome: read prediction THEN update
    task apply_branch;
        input [3:0]  idx;
        input        taken;
        output [0:0] pred_out;
        begin
            // Step 1: read prediction
            pc_index = idx;
            outcome  = taken;
            update   = 0;
            #2;
            pred_out = prediction;

            // Step 2: update on rising clock edge
            update = 1;
            @(posedge clk_i); #1;
            update = 0;

            // Update reference model
            ref_update(idx, taken);
        end
    endtask

    // ============================================================
    // MAIN TEST SEQUENCE
    // ============================================================
    logic [0:0] pred;
    integer     j;

    initial begin
        fail_count = 0;
        `START_TESTBENCH

        // Wait for reset
        @(negedge reset_i);
        ref_reset();
        #5;

        // ----------------------------------------------------------
        // TEST 1: After reset, all entries should be WT (10) → predict Taken
        // ----------------------------------------------------------
        $display("\n--- TEST 1: Reset state (all WT=10, predict Taken) ---");
        for (j = 0; j < 16; j = j + 1) begin
            check_prediction($sformatf("reset pc=%0d", j), j[3:0], 1'b1);
        end

        // ----------------------------------------------------------
        // TEST 2: Always Taken → counter climbs to ST (11)
        //   Start at WT(10), after 1 taken → ST(11), stays ST
        // ----------------------------------------------------------
        $display("\n--- TEST 2: Always Taken on pc=0 ---");
        apply_branch(4'd0, 1, pred); // WT→ST, pred was Taken ✓
        check_prediction("after 1 taken", 4'd0, 1'b1); // ST → predict Taken

        apply_branch(4'd0, 1, pred); // ST→ST (saturate), pred=Taken ✓
        check_prediction("after 2 taken", 4'd0, 1'b1);

        apply_branch(4'd0, 1, pred); // stays ST
        check_prediction("after 3 taken", 4'd0, 1'b1);

        // ----------------------------------------------------------
        // TEST 3: Always Not Taken → counter drops to SNT (00)
        //   pc=1 starts at WT(10)
        //   taken=0: WT→WNT, taken=0: WNT→SNT, then saturates
        // ----------------------------------------------------------
        $display("\n--- TEST 3: Always Not Taken on pc=1 ---");
        apply_branch(4'd1, 0, pred); // WT→WNT, pred was Taken
        check_prediction("after 1 NT", 4'd1, 1'b0); // WNT → predict NT

        apply_branch(4'd1, 0, pred); // WNT→SNT
        check_prediction("after 2 NT", 4'd1, 1'b0); // SNT → predict NT

        apply_branch(4'd1, 0, pred); // SNT→SNT (saturate)
        check_prediction("after 3 NT", 4'd1, 1'b0);

        // ----------------------------------------------------------
        // TEST 4: Hysteresis — 2-bit counter requires 2 mispredictions
        //   to flip prediction. Start ST(11) on pc=0 from TEST 2.
        //   One NT shouldn't flip prediction.
        // ----------------------------------------------------------
        $display("\n--- TEST 4: Hysteresis (ST needs 2 NTs to flip) ---");
        // pc=0 is at ST(11), predict Taken
        apply_branch(4'd0, 0, pred); // ST→WT, pred=Taken (correct, still T)
        check_prediction("after 1 NT from ST", 4'd0, 1'b1); // WT → still Taken

        apply_branch(4'd0, 0, pred); // WT→WNT, pred=Taken (now mispredicts)
        check_prediction("after 2 NT from ST", 4'd0, 1'b0); // WNT → Not Taken

        // ----------------------------------------------------------
        // TEST 5: Alternating T/NT pattern
        //   2-bit counter oscillates but prediction is stable (WT/ST)
        // ----------------------------------------------------------
        $display("\n--- TEST 5: Alternating pattern on pc=2 ---");
        // pc=2 starts at WT(10)
        apply_branch(4'd2, 1, pred); // WT→ST
        apply_branch(4'd2, 0, pred); // ST→WT
        apply_branch(4'd2, 1, pred); // WT→ST
        apply_branch(4'd2, 0, pred); // ST→WT
        // Should still be WT → predict Taken
        check_prediction("alternating ends WT", 4'd2, 1'b1);

        // ----------------------------------------------------------
        // TEST 6: Different PCs are independent
        // ----------------------------------------------------------
        $display("\n--- TEST 6: Independence of PHT entries ---");
        // Drive pc=3 to SNT
        apply_branch(4'd3, 0, pred);
        apply_branch(4'd3, 0, pred); // now SNT
        // Drive pc=4 to ST
        apply_branch(4'd4, 1, pred); // now ST
        // Check they don't interfere
        check_prediction("pc=3 SNT independent", 4'd3, 1'b0);
        check_prediction("pc=4 ST independent",  4'd4, 1'b1);
        // pc=5 should still be at reset default WT → Taken
        check_prediction("pc=5 untouched WT",    4'd5, 1'b1);

        // ----------------------------------------------------------
        // TEST 7: Full saturating counter - verify all 4 states
        //   Use pc=6. Start at WT(10).
        // ----------------------------------------------------------
        $display("\n--- TEST 7: All 4 saturating counter states on pc=6 ---");
        // WT(10) → predict Taken
        check_prediction("WT state", 4'd6, 1'b1);
        apply_branch(4'd6, 0, pred); // WT→WNT
        // WNT(01) → predict Not Taken
        check_prediction("WNT state", 4'd6, 1'b0);
        apply_branch(4'd6, 0, pred); // WNT→SNT
        // SNT(00) → predict Not Taken
        check_prediction("SNT state", 4'd6, 1'b0);
        apply_branch(4'd6, 1, pred); // SNT→WNT
        check_prediction("WNT again", 4'd6, 1'b0);
        apply_branch(4'd6, 1, pred); // WNT→WT
        check_prediction("WT again", 4'd6, 1'b1);
        apply_branch(4'd6, 1, pred); // WT→ST
        check_prediction("ST state", 4'd6, 1'b1);

        // ----------------------------------------------------------
        // TEST 8: Saturation boundaries
        //   SNT should not go below 00, ST should not go above 11
        // ----------------------------------------------------------
        $display("\n--- TEST 8: Saturation boundaries ---");
        // pc=7 → push to SNT then keep applying NT
        apply_branch(4'd7, 0, pred);
        apply_branch(4'd7, 0, pred); // now SNT
        apply_branch(4'd7, 0, pred); // should stay SNT
        apply_branch(4'd7, 0, pred); // should stay SNT
        check_prediction("SNT saturated", 4'd7, 1'b0);
        // Now push to ST
        apply_branch(4'd7, 1, pred); // SNT→WNT
        apply_branch(4'd7, 1, pred); // WNT→WT
        apply_branch(4'd7, 1, pred); // WT→ST
        apply_branch(4'd7, 1, pred); // ST stays ST
        apply_branch(4'd7, 1, pred); // ST stays ST
        check_prediction("ST saturated", 4'd7, 1'b1);

        // ----------------------------------------------------------
        // TEST 9: Reference model cross-check on all 16 PCs
        //   Apply a known sequence and compare against ref model
        // ----------------------------------------------------------
        $display("\n--- TEST 9: Reference model sweep all 16 PCs ---");
        begin
            logic [0:0] ref_pred;
            for (j = 0; j < 16; j = j + 1) begin
                ref_pred = ref_predict(j[3:0]);
                check_prediction($sformatf("ref sweep pc=%0d", j), j[3:0], ref_pred);
            end
        end

        // ----------------------------------------------------------
        // DONE
        // ----------------------------------------------------------
        if (fail_count > 0) begin
            $display("\n%0d test(s) FAILED.", fail_count);
            `FINISH_WITH_FAIL
        end else begin
            $display("\nAll tests PASSED!");
            `FINISH_WITH_PASS
        end
    end

    // ============================================================
    // Final summary banner
    // ============================================================
    final begin
        $display("Simulation time is %t", $time);
        if (error_o === 1) begin
            $display("\033[0;31m    ______                    \033[0m");
            $display("\033[0;31m   / ____/_____________  _____\033[0m");
            $display("\033[0;31m  / __/ / ___/ ___/ __ \\/ ___/\033[0m");
            $display("\033[0;31m / /___/ /  / /  / /_/ / /    \033[0m");
            $display("\033[0;31m/_____/_/  /_/   \\____/_/     \033[0m");
            $display("Simulation Failed");
        end else if (pass_o === 1) begin
            $display("\033[0;32m    ____  ___   __________\033[0m");
            $display("\033[0;32m   / __ \\/   | / ___/ ___/\033[0m");
            $display("\033[0;32m  / /_/ / /| | \\__ \\__ \\ \033[0m");
            $display("\033[0;32m / ____/ ___ |___/ /__/ / \033[0m");
            $display("\033[0;32m/_/   /_/  |_/____/____/  \033[0m");
            $display("Simulation Succeeded!");
        end else begin
            $display("UNKNOWN - Please set error_o or pass_o!");
        end
    end

endmodule

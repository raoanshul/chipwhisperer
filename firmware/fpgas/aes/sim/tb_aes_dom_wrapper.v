/* 
Testbench for AES-DOM Wrapper Integration

This testbench verifies the aes_dom_wrapper module which bridges 
the DOM AES core to ChipWhisperer's interface.

Tests:
1. Basic encryption with known test vector
2. Verify ciphertext matches expected value
3. Check timing signals (load, busy)

Copyright (c) 2024
*/

`timescale 1ns / 1ns
`default_nettype none 

module tb_aes_dom_wrapper();

    // Parameters
    parameter CLK_PERIOD = 10;  // 100 MHz
    parameter TIMEOUT = 500000; // cycles
    
    // Clock and reset
    reg clk;
    reg rst_n;
    
    // Interface signals
    reg [127:0] pt_parallel;
    reg [127:0] key_parallel;
    reg load;
    wire [127:0] ct_parallel;
    wire busy;
    
    // Test vectors (NIST FIPS 197 - Appendix C.1)
    localparam [127:0] TEST_PT  = 128'h00112233445566778899aabbccddeeff;
    localparam [127:0] TEST_KEY = 128'h000102030405060708090a0b0c0d0e0f;
    localparam [127:0] EXPECTED_CT = 128'h69c4e0d86a7b0430d8cdb78070b4c55a;
    
    // Additional test vectors
    localparam [127:0] TEST_PT2  = 128'h12345678abcdef0187654321deadbeef;
    localparam [127:0] TEST_KEY2 = 128'habcdef0112345678deadbeef87654321;
    
    // Statistics
    integer errors = 0;
    integer cycle_count = 0;
    integer encryption_cycles = 0;
    
    // Clock generation
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    // Cycle counter
    always @(posedge clk) begin
        if (!rst_n)
            cycle_count <= 0;
        else
            cycle_count <= cycle_count + 1;
    end
    
    // DUT instantiation
    aes_dom_wrapper #(
        .N(1)  // First-order masking
    ) DUT (
        .clk(clk),
        .rst_n(rst_n),
        .pt_parallel(pt_parallel),
        .key_parallel(key_parallel),
        .load(load),
        .ct_parallel(ct_parallel),
        .busy(busy)
    );
    
    // Main test sequence
    initial begin
        $display("============================================");
        $display("AES-DOM Wrapper Testbench");
        $display("============================================");
        $display("Test Vector 1:");
        $display("  Plaintext:  %h", TEST_PT);
        $display("  Key:        %h", TEST_KEY);
        $display("  Expected CT:%h", EXPECTED_CT);
        $display("============================================");
        
        // Initialize
        rst_n = 1'b0;
        pt_parallel = 128'b0;
        key_parallel = 128'b0;
        load = 1'b0;
        
        // Apply reset
        repeat (10) @(posedge clk);
        rst_n = 1'b1;
        repeat (5) @(posedge clk);
        
        // ===== Test 1: Basic encryption =====
        $display("\n[Test 1] Starting encryption...");
        
        @(posedge clk);
        pt_parallel = TEST_PT;
        key_parallel = TEST_KEY;
        load = 1'b1;
        
        @(posedge clk);
        load = 1'b0;
        
        // Wait for busy to go high
        wait(busy == 1'b1);
        $display("  Encryption started at cycle %0d", cycle_count);
        encryption_cycles = cycle_count;
        
        // Wait for busy to go low (encryption complete)
        wait(busy == 1'b0);
        $display("  Encryption complete at cycle %0d", cycle_count);
        encryption_cycles = cycle_count - encryption_cycles;
        $display("  Encryption took %0d cycles", encryption_cycles);
        
        // Allow a few cycles for output to stabilize
        repeat (5) @(posedge clk);
        
        // Check result
        $display("  Got CT:     %h", ct_parallel);
        if (ct_parallel == EXPECTED_CT) begin
            $display("  [PASS] Ciphertext matches!");
        end else begin
            $display("  [FAIL] Ciphertext mismatch!");
            $display("         Expected: %h", EXPECTED_CT);
            $display("         Got:      %h", ct_parallel);
            errors = errors + 1;
        end
        
        // ===== Test 2: Back-to-back encryptions =====
        $display("\n[Test 2] Back-to-back encryption...");
        
        repeat (10) @(posedge clk);
        
        @(posedge clk);
        pt_parallel = TEST_PT2;
        key_parallel = TEST_KEY2;
        load = 1'b1;
        
        @(posedge clk);
        load = 1'b0;
        
        wait(busy == 1'b1);
        $display("  Second encryption started");
        
        wait(busy == 1'b0);
        $display("  Second encryption complete");
        $display("  CT: %h", ct_parallel);
        // Note: We don't have the expected value for this test
        // Just verify it completes without hanging
        
        // ===== Test 3: Reset during encryption =====
        $display("\n[Test 3] Reset during encryption...");
        
        repeat (10) @(posedge clk);
        
        @(posedge clk);
        pt_parallel = TEST_PT;
        key_parallel = TEST_KEY;
        load = 1'b1;
        
        @(posedge clk);
        load = 1'b0;
        
        wait(busy == 1'b1);
        $display("  Encryption started, applying reset...");
        
        // Wait a few cycles then reset
        repeat (50) @(posedge clk);
        rst_n = 1'b0;
        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (5) @(posedge clk);
        
        // Verify busy is low after reset
        if (busy == 1'b0) begin
            $display("  [PASS] Busy cleared after reset");
        end else begin
            $display("  [FAIL] Busy still high after reset");
            errors = errors + 1;
        end
        
        // ===== Test 4: Verify encryption still works after reset =====
        $display("\n[Test 4] Encryption after reset...");
        
        @(posedge clk);
        pt_parallel = TEST_PT;
        key_parallel = TEST_KEY;
        load = 1'b1;
        
        @(posedge clk);
        load = 1'b0;
        
        wait(busy == 1'b1);
        wait(busy == 1'b0);
        
        repeat (5) @(posedge clk);
        
        if (ct_parallel == EXPECTED_CT) begin
            $display("  [PASS] Encryption works after reset");
        end else begin
            $display("  [FAIL] Encryption failed after reset");
            errors = errors + 1;
        end
        
        // ===== Summary =====
        $display("\n============================================");
        if (errors == 0) begin
            $display("ALL TESTS PASSED!");
        end else begin
            $display("TESTS FAILED: %0d errors", errors);
        end
        $display("============================================");
        
        $finish;
    end
    
    // Timeout watchdog
    initial begin
        repeat (TIMEOUT) @(posedge clk);
        $display("\n[ERROR] Simulation timeout!");
        $display("TESTS FAILED due to timeout");
        $finish;
    end
    
    // Optional: Dump waveforms
    initial begin
        $dumpfile("tb_aes_dom_wrapper.vcd");
        $dumpvars(0, tb_aes_dom_wrapper);
    end

endmodule

`default_nettype wire

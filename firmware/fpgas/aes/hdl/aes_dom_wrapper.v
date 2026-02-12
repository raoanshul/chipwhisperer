/*
AES DOM Wrapper - Interface between CW305 and Domain-Oriented Masking AES

This module wraps the aes_top.vhdl (DOM protected AES) and provides:
1. Parallel-to-byte-serial conversion for plaintext/key
2. Share splitting (masking) for side-channel protection
3. Randomness generation (LFSR-based PRNG)
4. Ciphertext collection and share recombination
5. CW305-compatible control interface

IMPORTANT: The DOM core is byte-serial. It processes one byte per clock cycle
through the S-box. The internal state/key registers shift in a "meander" pattern.
- 20 cycles per round (for perfectly interleaved design)
- 10 rounds = 200 cycles total per encryption
- During preliminary round (first 16 cycles), PT and Key bytes are loaded
- Output ciphertext appears byte-by-byte during the final cycles

Copyright (c) 2026
*/

`timescale 1ns / 1ps
`default_nettype none

module aes_dom_wrapper #(
    parameter pPT_WIDTH  = 128,
    parameter pKEY_WIDTH = 128,
    parameter pCT_WIDTH  = 128,
    // DOM protection order: N=1 means 2 shares (first-order protection)
    parameter N = 1
)(
    // Clock and Reset
    input  wire                     clk,
    input  wire                     rst,
    
    // =========================================================================
    // Parallel Interface (compatible with existing CW305 register module)
    // =========================================================================
    
    // Parallel inputs (directly from registers)
    input  wire [pPT_WIDTH-1:0]     pt_parallel,    // Full 128-bit plaintext
    input  wire [pKEY_WIDTH-1:0]    key_parallel,   // Full 128-bit key
    
    // Parallel output
    output wire [pCT_WIDTH-1:0]     ct_parallel,    // Full 128-bit ciphertext
    
    // Control signals (directly compatible with aes_core interface)
    input  wire                     load,           // Start encryption (pulse)
    output wire                     busy,           // Encryption in progress
    
    // Optional: PRNG seed (can be loaded via register)
    input  wire [63:0]              prng_seed
);

    // =========================================================================
    // Local Parameters
    // =========================================================================
    
    // Number of shares = N + 1 (for N=1, we have 2 shares)
    localparam NUM_SHARES = N + 1;
    
    // Randomness widths for N=1 (first-order)
    localparam ZMUL_WIDTH = (N*(N+1)/2) * 4;  // 4 bits for N=1
    localparam ZINV_WIDTH = (N*(N+1)/2) * 2;  // 2 bits for N=1
    localparam BMUL_WIDTH = (N+1) * 4;        // 8 bits for N=1
    localparam BINV_WIDTH = (N+1) * 2;        // 4 bits for N=1

    // =========================================================================
    // Internal Signals
    // =========================================================================
    
    // Latched parallel data
    reg [127:0] pt_latched;
    reg [127:0] key_latched;
    reg [127:0] ct_collected;
    
    // Byte selection counter (tracks which byte to present to DOM core)
    // This runs continuously while the DOM core is active
    reg [7:0] cycle_counter;
    reg       running;
    
    // Current byte index (0-15 for PT/Key, wraps around)
    wire [3:0] byte_index = cycle_counter[3:0];
    
    // DOM core interface signals
    reg        dom_start_r;
    wire       dom_done;
    
    // Current bytes selected from latched parallel data
    // Note: The DOM expects bytes in a specific order matching its meander pattern
    // For now, we assume linear order (byte 0 = MSB, byte 15 = LSB)
    wire [7:0] current_pt_byte;
    wire [7:0] current_key_byte;
    
    // Byte selection using variable part select
    assign current_pt_byte  = pt_latched[127 - byte_index*8 -: 8];
    assign current_key_byte = key_latched[127 - byte_index*8 -: 8];
    
    // Random mask for share splitting
    wire [7:0] mask_byte;
    
    // DOM shares
    wire [7:0] dom_pt_share  [0:N];
    wire [7:0] dom_key_share [0:N];
    wire [7:0] dom_ct_share  [0:N];
    
    // Share splitting: share0 = mask, share1 = data XOR mask
    assign dom_pt_share[0]  = mask_byte;
    assign dom_pt_share[1]  = current_pt_byte ^ mask_byte;
    assign dom_key_share[0] = mask_byte;  // Could use different mask
    assign dom_key_share[1] = current_key_byte ^ mask_byte;
    
    // Randomness signals
    wire [ZMUL_WIDTH-1:0] zmul1, zmul2, zmul3;
    wire [ZINV_WIDTH-1:0] zinv1, zinv2, zinv3;
    wire [BMUL_WIDTH-1:0] bmul1;
    wire [BINV_WIDTH-1:0] binv1, binv2, binv3;
    
    // PRNG
    reg [63:0] prng_state;
    wire [63:0] prng_out;
    
    // =========================================================================
    // PRNG (Linear Feedback Shift Register)
    // =========================================================================
    // 64-bit Galois LFSR with maximal period
    
    wire lfsr_bit = prng_state[63] ^ prng_state[62] ^ prng_state[60] ^ prng_state[59];
    
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            prng_state <= (prng_seed != 64'b0) ? prng_seed : 64'hDEADBEEFCAFEBABE;
        end else if (running) begin
            prng_state <= {prng_state[62:0], lfsr_bit};
        end
    end
    
    assign prng_out = prng_state;
    assign mask_byte = prng_out[7:0];
    
    // Distribute randomness to DOM inputs
    assign zmul1 = prng_out[ZMUL_WIDTH-1:0];
    assign zmul2 = prng_out[2*ZMUL_WIDTH-1:ZMUL_WIDTH];
    assign zmul3 = prng_out[3*ZMUL_WIDTH-1:2*ZMUL_WIDTH];
    assign zinv1 = prng_out[3*ZMUL_WIDTH+ZINV_WIDTH-1:3*ZMUL_WIDTH];
    assign zinv2 = prng_out[3*ZMUL_WIDTH+2*ZINV_WIDTH-1:3*ZMUL_WIDTH+ZINV_WIDTH];
    assign zinv3 = prng_out[3*ZMUL_WIDTH+3*ZINV_WIDTH-1:3*ZMUL_WIDTH+2*ZINV_WIDTH];
    assign bmul1 = prng_out[3*ZMUL_WIDTH+3*ZINV_WIDTH+BMUL_WIDTH-1:3*ZMUL_WIDTH+3*ZINV_WIDTH];
    assign binv1 = prng_out[3*ZMUL_WIDTH+3*ZINV_WIDTH+BMUL_WIDTH+BINV_WIDTH-1:3*ZMUL_WIDTH+3*ZINV_WIDTH+BMUL_WIDTH];
    assign binv2 = prng_out[3*ZMUL_WIDTH+3*ZINV_WIDTH+BMUL_WIDTH+2*BINV_WIDTH-1:3*ZMUL_WIDTH+3*ZINV_WIDTH+BMUL_WIDTH+BINV_WIDTH];
    assign binv3 = prng_out[3*ZMUL_WIDTH+3*ZINV_WIDTH+BMUL_WIDTH+3*BINV_WIDTH-1:3*ZMUL_WIDTH+3*ZINV_WIDTH+BMUL_WIDTH+2*BINV_WIDTH];

    // =========================================================================
    // Control Logic
    // =========================================================================
    
    // Latch input data on load pulse
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            pt_latched  <= 128'b0;
            key_latched <= 128'b0;
        end else if (load && !running) begin
            pt_latched  <= pt_parallel;
            key_latched <= key_parallel;
        end
    end
    
    // Running state and cycle counter
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            running       <= 1'b0;
            cycle_counter <= 8'd0;
            dom_start_r   <= 1'b0;
        end else begin
            dom_start_r <= 1'b0;  // Default: no start pulse
            
            if (load && !running) begin
                running       <= 1'b1;
                cycle_counter <= 8'd0;
                dom_start_r   <= 1'b1;  // Pulse start to DOM core
            end else if (running) begin
                cycle_counter <= cycle_counter + 8'd1;
                
                // Check for completion (DOM core signals done)
                if (dom_done) begin
                    running <= 1'b0;
                end
            end
        end
    end
    
    // =========================================================================
    // Ciphertext Collection
    // =========================================================================
    // The DOM core outputs ciphertext byte-by-byte. We need to collect and
    // recombine shares. The output timing depends on the DOM architecture.
    // For now, we collect when done signal is asserted.
    
    wire [7:0] ct_byte_combined = dom_ct_share[0] ^ dom_ct_share[1];
    
    // Shift register to collect ciphertext bytes
    // Note: Actual collection timing may need adjustment based on DOM core behavior
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            ct_collected <= 128'b0;
        end else if (running && cycle_counter >= 8'd184) begin
            // Collect CT bytes during final 16 cycles (approximate)
            // This timing may need adjustment based on actual DOM behavior
            ct_collected <= {ct_collected[119:0], ct_byte_combined};
        end
    end
    
    // =========================================================================
    // Output Assignments
    // =========================================================================
    
    assign ct_parallel = ct_collected;
    assign busy = running;
    
    // =========================================================================
    // DOM AES Core Instantiation (via VHDL wrapper)
    // =========================================================================
    
    wire [NUM_SHARES*8-1:0] pt_shares_flat;
    wire [NUM_SHARES*8-1:0] key_shares_flat;
    wire [NUM_SHARES*8-1:0] ct_shares_flat;
    
    assign pt_shares_flat  = {dom_pt_share[1], dom_pt_share[0]};
    assign key_shares_flat = {dom_key_share[1], dom_key_share[0]};
    
    assign dom_ct_share[0] = ct_shares_flat[7:0];
    assign dom_ct_share[1] = ct_shares_flat[15:8];
    
    aes_dom_verilog_wrapper #(
        .N(N)
    ) u_aes_dom (
        .clk_i       (clk),
        .rst_ni      (~rst),
        
        .pt_shares_i (pt_shares_flat),
        .key_shares_i(key_shares_flat),
        .ct_shares_o (ct_shares_flat),
        
        .zmul1_i     (zmul1),
        .zmul2_i     (zmul2),
        .zmul3_i     (zmul3),
        .zinv1_i     (zinv1),
        .zinv2_i     (zinv2),
        .zinv3_i     (zinv3),
        
        .bmul1_i     (bmul1),
        .binv1_i     (binv1),
        .binv2_i     (binv2),
        .binv3_i     (binv3),
        
        .start_i     (dom_start_r),
        .done_o      (dom_done)
    );

endmodule

`default_nettype wire

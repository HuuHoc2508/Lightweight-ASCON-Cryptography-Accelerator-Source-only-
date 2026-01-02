// ================================================================
// ASCON Core Optimized - Adapted for Legacy Wrapper
// Based on ascon_optimized.v but with standard IO and exposed state
// ================================================================

module ascon_core_optimized (
    input wire clk,
    input wire rst_n,
    
    // ============= CONTROL =============
    input wire [1:0] crypt_variant,
    input wire mode,
    input wire [5:0] padding_missed,
    
    // ============= KEY & NONCE =============
    input wire [159:0] secret_key,
    input wire [127:0] nonce,
    input wire r_key, r_nonce,
    
    // ============= UNIFIED DATA INPUT =============
    input wire [127:0] data_in,
    input wire [1:0] data_type, // 00=AD, 01=PT, 10=CT
    input wire data_valid,
    input wire data_last,
    output wire data_ready,
    
    // ============= TAG INPUT (For Verification) =============
    input wire [127:0] expected_tag,
    
    // ============= OUTPUTS =============
    output wire [127:0] out_data,
    output wire out_valid,
    output wire out_last,
    
    output wire [127:0] out_tag,
    output wire tag_valid,
    output wire tag_match,
    
    output wire done,
    output wire busy,
    
    // ============= STATE FLAGS (For Wrapper) =============
    output wire waiting_for_ad,
    output wire waiting_for_data,
    
    // ============= DEBUG OUTPUTS (Legacy Compatibility) =============
    output wire        dbg_perm_start,
    output wire [319:0] dbg_perm_out,
    output wire [319:0] dbg_state,
    output wire [319:0] dbg_state_next,
    output wire        dbg_perm_done
);

    // ========================================
    // Internal Signals & Config
    // ========================================
    reg perm_start;
    wire [319:0] perm_out;
    reg [319:0] state;
    reg [319:0] state_next;
    wire perm_done;
    
    // Debug Assignments
    assign dbg_perm_start = perm_start;
    assign dbg_perm_out   = perm_out;
    assign dbg_state      = state;
    assign dbg_state_next = state_next;
    assign dbg_perm_done  = perm_done;
    
    reg [9:0] key_size;
    reg [9:0] rate;
    reg [3:0] rounds_a;
    reg [3:0] rounds_b;
    reg [63:0] iv;

    // Configuration Decode
    always @(*) begin
        case (crypt_variant)
            2'b00: begin  // Ascon-128
                key_size = 128; rate = 64; rounds_a = 12; rounds_b = 6;
                iv = 64'h80400c0600000000;
            end
            2'b01: begin  // Ascon-128a
                key_size = 128; rate = 128; rounds_a = 12; rounds_b = 8;
                iv = 64'h80800c0800000000;
            end
            2'b10: begin  // Ascon-80pq
                key_size = 160; rate = 64; rounds_a = 12; rounds_b = 6;
                iv = 64'h00000000a0400c06;
            end
            default: begin // Default Ascon-128
                key_size = 128; rate = 64; rounds_a = 12; rounds_b = 6;
                iv = 64'h80400c0600000000;
            end
        endcase
    end

    // ========================================
    // Registers & FSM States
    // ========================================
    reg [255:0] cap_key_mask_I, cap_key_mask_F;
    reg perm_start_next;
    reg [3:0] perm_rounds, perm_rounds_next;
    
    // FSM States
    localparam ST_IDLE        = 4'd0,
               ST_INIT_PERM   = 4'd1,
               ST_PROC_AD     = 4'd2,
               ST_AD_PERM     = 4'd3,
               ST_DOMAIN_SEP  = 4'd4,
               ST_PROC_DATA   = 4'd5,
               ST_DATA_PERM   = 4'd6,
               ST_FINALIZE    = 4'd7,
               ST_FINAL_PERM  = 4'd8,
               ST_TAG_GEN     = 4'd9,
               ST_DONE        = 4'd10;

    reg [3:0] fsm, fsm_next;
    reg data_last_latch, data_last_latch_next;
    
    // Output buffers
    reg [127:0] out_data_reg, out_data_next;
    reg [127:0] out_tag_reg, out_tag_next;
    reg out_valid_reg, out_valid_next;
    reg tag_valid_reg, tag_valid_next;
    reg out_last_reg, out_last_next;

    // Assignments
    assign out_data  = out_data_reg;
    assign out_tag   = out_tag_reg;
    assign out_valid = out_valid_reg;
    assign tag_valid = tag_valid_reg;
    assign out_last  = out_last_reg;
    assign tag_match = (out_tag_reg == expected_tag); // Use external expected tag
    assign done      = (fsm == ST_DONE);
    assign busy      = (fsm != ST_IDLE && fsm != ST_DONE);
    
    // State Flags for Wrapper
    assign waiting_for_ad   = (fsm == ST_PROC_AD);
    assign waiting_for_data = (fsm == ST_PROC_DATA);

    // Masking Logic
    wire [127:0] mask128;
    wire [63:0]  mask64;
    
    assign mask128 = (128'd1 << (padding_missed * 4)) - 128'd1;
    assign mask64  = (64'd1  << (padding_missed * 4)) - 64'd1;

    // Key Masks
    always @(*) begin
        if (key_size == 160) begin
            cap_key_mask_I = {96'h0, secret_key[159:0]};
            cap_key_mask_F = {secret_key[159:0], 96'h0};
        end else begin
            cap_key_mask_I = {128'h0, secret_key[127:0]};
            cap_key_mask_F = {secret_key[127:0], 128'h0};
        end
    end

    // ========================================
    // Permutation Instance
    // ========================================
    ascon_permutation perm_inst (
        .clk(clk),
        .rst_n(rst_n),
        .start(perm_start),
        .rounds(perm_rounds),
        .state_in(state),
        .state_out(perm_out),
        .done(perm_done)
    );

    // ========================================
    // Data Ready Logic
    // ========================================
    assign data_ready = ((fsm == ST_PROC_AD) || (fsm == ST_PROC_DATA));

    wire is_ad_type   = (data_type == 2'b00);
    wire is_pt_type   = (data_type == 2'b01);
    wire is_ct_type   = (data_type == 2'b10);

    // ========================================
    // Sequential Logic
    // ========================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fsm              <= ST_IDLE;
            state            <= 320'h0;
            out_data_reg     <= 128'h0;
            out_tag_reg      <= 128'h0;
            out_valid_reg    <= 1'b0;
            tag_valid_reg    <= 1'b0;
            out_last_reg     <= 1'b0;
            perm_start       <= 1'b0;
            perm_rounds      <= 4'h0;
            data_last_latch  <= 1'b0;
        end else begin
            fsm              <= fsm_next;
            state            <= state_next;
            out_data_reg     <= out_data_next;
            out_tag_reg      <= out_tag_next;
            out_valid_reg    <= out_valid_next;
            tag_valid_reg    <= tag_valid_next;
            out_last_reg     <= out_last_next;
            perm_start       <= perm_start_next;
            perm_rounds      <= perm_rounds_next;
            data_last_latch  <= data_last_latch_next;
        end
    end

    // ========================================
    // Combinational Logic - FSM & Datapath
    // ========================================
    always @(*) begin
        // Defaults
        fsm_next             = fsm;
        state_next           = state;
        perm_start_next      = 1'b0;
        perm_rounds_next     = perm_rounds;
        
        out_data_next        = out_data_reg;
        out_tag_next         = out_tag_reg;
        
        out_valid_next       = 1'b0;
        tag_valid_next       = 1'b0;
        out_last_next        = 1'b0;
        
        data_last_latch_next = data_last_latch;

        case (fsm)
            // ------------------------------------
            // IDLE: Wait for key/nonce
            // ------------------------------------
            ST_IDLE: begin
                if (r_key && r_nonce) begin
                    // Init State = IV || K || N
                    if (key_size == 160)
                        state_next = {iv[31:0], secret_key[159:128], secret_key[127:0], nonce};
                    else
                        state_next = {iv, secret_key[127:0], nonce};
                    
                    perm_start_next  = 1'b1;
                    perm_rounds_next = rounds_a;
                    fsm_next         = ST_INIT_PERM;
                end
            end

            // ------------------------------------
            // INIT_PERM: Initial Permutation
            // ------------------------------------
            ST_INIT_PERM: begin
                if (perm_done) begin
                    state_next = perm_out;
                    // XOR Key into Capacity
                    if (rate == 64)
                        state_next[255:0] = perm_out[255:0] ^ cap_key_mask_I;
                    else
                        state_next[191:0] = perm_out[191:0] ^ cap_key_mask_I[191:0];
                    
                    fsm_next = ST_PROC_AD;
                end
            end

            // ------------------------------------
            // PROC_AD: Process Associated Data
            // ------------------------------------
            ST_PROC_AD: begin
                if (data_valid) begin
                    if (is_ad_type) begin
                        // Valid AD Block
                        if (rate == 64)
                            state_next[319:256] = state[319:256] ^ data_in[127:64];
                        else
                            state_next[319:192] = state[319:192] ^ data_in;

                        perm_start_next      = 1'b1;
                        perm_rounds_next     = rounds_b;
                        data_last_latch_next = data_last;
                        fsm_next             = ST_AD_PERM;
                    end 
                    else begin
                        // Received Data in AD phase -> AD is hollow/done
                        fsm_next = ST_DOMAIN_SEP;
                    end
                end
            end

            // ------------------------------------
            // AD_PERM: Permutation after AD block
            // ------------------------------------
            ST_AD_PERM: begin
                if (perm_done) begin
                    state_next = perm_out;
                    if (data_last_latch)
                        fsm_next = ST_DOMAIN_SEP;
                    else
                        fsm_next = ST_PROC_AD;
                end
            end

            // ------------------------------------
            // DOMAIN_SEP: Domain Separation XOR
            // ------------------------------------
            ST_DOMAIN_SEP: begin
                // XOR LSB of Domain Separator
                if (rate == 64)
                    state_next[255:0] = state[255:0] ^ {255'b0, 1'b1};
                else
                    state_next[191:0] = state[191:0] ^ {191'b0, 1'b1};
                
                fsm_next = ST_PROC_DATA;
            end

            // ------------------------------------
            // PROC_DATA: Encrypt/Decrypt Data
            // ------------------------------------
            ST_PROC_DATA: begin
                if (data_valid) begin
                    if (is_pt_type || is_ct_type) begin
                        // Valid Data Block
                        perm_rounds_next = rounds_b;
                        out_valid_next   = 1'b1;
                        out_last_next    = data_last;
                        data_last_latch_next = data_last;

                        if (mode == 0) begin 
                            // ===== ENCRYPT (PT -> CT) =====
                            if (rate == 64) begin
                                out_data_next[127:64] = state[319:256] ^ data_in[127:64];
                                out_data_next[63:0]   = 64'b0;
                                state_next[319:256]   = out_data_next[127:64];
                            end else begin
                                out_data_next       = state[319:192] ^ data_in;
                                state_next[319:192] = out_data_next;
                            end
                        end 
                        else begin 
                            // ===== DECRYPT (CT -> PT) =====
                            if (rate == 64) begin
                                out_data_next[127:64] = state[319:256] ^ data_in[127:64];
                                out_data_next[63:0]   = 64'b0;
                                state_next[319:256]   = data_in[127:64];
                            end else begin
                                out_data_next       = state[319:192] ^ data_in;
                                state_next[319:192] = data_in;
                            end
                        end

                        if (!data_last) begin
                            perm_start_next = 1'b1;
                            fsm_next        = ST_DATA_PERM;
                        end else begin
                            fsm_next        = ST_DATA_PERM; // Handle padding
                        end
                    end
                    else begin
                         // Unexpected type (e.g. Empty Data) -> Finalize
                         fsm_next = ST_FINALIZE;
                    end
                end
            end

            // ------------------------------------
            // DATA_PERM: Permutation after Data
            // ------------------------------------
            ST_DATA_PERM: begin
                if (data_last_latch) begin
                    // Handle Padding on Last Block
                    if (mode == 1) begin // Decrypt padding mask
                        if (rate == 64)
                            state_next[319:256] = state[319:256] & ~mask64;
                        else
                            state_next[319:192] = state[319:192] & ~mask128;
                    end
                    fsm_next = ST_FINALIZE;
                end 
                else if (perm_done) begin
                    state_next = perm_out;
                    fsm_next   = ST_PROC_DATA;
                end
            end

            // ------------------------------------
            // FINALIZE: Add Key to Capacity
            // ------------------------------------
            ST_FINALIZE: begin
                if (rate == 64)
                    state_next[255:0] = state[255:0] ^ cap_key_mask_F;
                else
                    state_next[191:0] = state[191:0] ^ cap_key_mask_F[255:64];
                
                perm_start_next  = 1'b1;
                perm_rounds_next = rounds_a;
                fsm_next         = ST_FINAL_PERM;
            end

            // ------------------------------------
            // FINAL_PERM
            // ------------------------------------
            ST_FINAL_PERM: begin
                if (perm_done) begin
                    state_next = perm_out;
                    fsm_next   = ST_TAG_GEN;
                end
            end

            // ------------------------------------
            // TAG_GEN: Generate Tag
            // ------------------------------------
            ST_TAG_GEN: begin
                out_tag_next   = state[127:0] ^ secret_key[127:0];
                tag_valid_next = 1'b1;
                fsm_next       = ST_DONE;
            end

            // ------------------------------------
            // DONE
            // ------------------------------------
            ST_DONE: begin
                if (!r_key && !r_nonce)
                    fsm_next = ST_IDLE;
            end

            default: fsm_next = ST_IDLE;
        endcase
    end

endmodule

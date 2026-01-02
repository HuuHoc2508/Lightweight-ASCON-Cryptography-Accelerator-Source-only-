// ================================================================================
// ASCON Permutation Module
// Implements the core cryptographic permutation p_a and p_b
// ================================================================================
module ascon_permutation #(
    parameter MAX_ROUNDS = 12
)(
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,
    input  wire [3:0]   rounds,
    input  wire [319:0] state_in,
    output reg  [319:0] state_out,
    output reg          done
);

    reg [319:0] current_state;
    reg [3:0] round_cnt;
    reg [1:0] perm_state;

    localparam P_IDLE = 2'b00;
    localparam P_ROUND = 2'b01;
    localparam P_DONE = 2'b10;

    // Round function wires
    wire [319:0] round_out;
    wire [63:0] round_constant;

    // Instantiate round function
    ascon_round round_inst (
        .state_in(current_state),
        .round_constant(round_constant),
        .state_out(round_out)
    );

    // Round constant generation
    ascon_round_constant rc_gen (
        .round_num(round_cnt),
        .total_rounds(rounds),
        .round_constant(round_constant)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= 320'h0;
            round_cnt <= 4'h0;
            perm_state <= P_IDLE;
            done <= 1'b0;
            state_out <= 320'h0;
        end else begin
            case (perm_state)
                P_IDLE: begin
                    done <= 1'b0;
                    if (start) begin
                        current_state <= state_in;
                        round_cnt <= 4'h0;
                        perm_state <= P_ROUND;
                    end
                end

                P_ROUND: begin
                    current_state <= round_out;
                    round_cnt <= round_cnt + 1;
                    if (round_cnt == rounds - 1) begin
                        perm_state <= P_DONE;
                        state_out <= round_out;
                        done <= 1'b1;
                    end
                end

                P_DONE: begin
                    perm_state <= P_IDLE;
                    done <= 1'b0;
                end
            endcase
        end
    end

endmodule

// ================================================================================
// ASCON Round Function (checked)
// Implements one round of the ASCON permutation: p_C ∘ p_S ∘ p_L
// ================================================================================
module ascon_round (
    input  wire [319:0] state_in,
    input  wire [63:0]  round_constant,
    output wire [319:0] state_out
);

    // State word extraction
    wire [63:0] x0_in = state_in[319:256];
    wire [63:0] x1_in = state_in[255:192];
    wire [63:0] x2_in = state_in[191:128];
    wire [63:0] x3_in = state_in[127:64];
    wire [63:0] x4_in = state_in[63:0];

    // After constant addition
    wire [63:0] x0_c = x0_in;
    wire [63:0] x1_c = x1_in;
    wire [63:0] x2_c = x2_in ^ round_constant;
    wire [63:0] x3_c = x3_in;
    wire [63:0] x4_c = x4_in;

    // After substitution layer
    wire [63:0] x0_s, x1_s, x2_s, x3_s, x4_s;

    ascon_sbox sbox_inst (
        .x0_in(x0_c), .x1_in(x1_c), .x2_in(x2_c), 
        .x3_in(x3_c), .x4_in(x4_c),
        .x0_out(x0_s), .x1_out(x1_s), .x2_out(x2_s),
        .x3_out(x3_s), .x4_out(x4_s)
    );

    // After linear diffusion layer
    wire [63:0] x0_l, x1_l, x2_l, x3_l, x4_l;

    ascon_linear linear_inst (
        .x0_in(x0_s), .x1_in(x1_s), .x2_in(x2_s),
        .x3_in(x3_s), .x4_in(x4_s),
        .x0_out(x0_l), .x1_out(x1_l), .x2_out(x2_l),
        .x3_out(x3_l), .x4_out(x4_l)
    );

    // Output state assembly
    assign state_out = {x0_l, x1_l, x2_l, x3_l, x4_l};

endmodule

// ================================================================================
// ASCON S-box Layer (Substitution) (checked)
// Implements 64 parallel 5-bit S-boxes applied bit-sliced
// ================================================================================
module ascon_sbox (
    input  wire [63:0] x0_in, x1_in, x2_in, x3_in, x4_in,
    output wire [63:0] x0_out, x1_out, x2_out, x3_out, x4_out
);

    // Bitsliced S-box implementation
    // S-box: 4,11,31,20,26,21,9,2,27,5,8,18,29,3,6,28,30,19,7,14,0,13,17,24,16,12,1,25,22,10,15,23
    // This is implemented using Boolean functions for efficiency
    wire [63:0] x0, x1, x2, x3, x4;
    assign x0 = x0_in ^ x4_in;
    assign x4 = x4_in ^ x3_in;
    assign x2 = x2_in ^ x1_in;
    assign x1 = x1_in;
    assign x3 = x3_in;

    // Nonlinear layer (5 AND operations)
    wire [63:0] t0 = ~x0 & x1;
    wire [63:0] t1 = ~x1 & x2;
    wire [63:0] t2 = ~x2 & x3;
    wire [63:0] t3 = ~x3 & x4;
    wire [63:0] t4 = ~x4 & x0;

    wire [63:0] y0 = x0 ^ t1;
    wire [63:0] y1 = x1 ^ t2;
    wire [63:0] y2 = x2 ^ t3;
    wire [63:0] y3 = x3 ^ t4;
    wire [63:0] y4 = x4 ^ t0;

    // Linear post-processing
    assign x0_out = y0 ^ y4;
    assign x1_out = y0 ^ y1;
    assign x2_out = ~y2;
    assign x3_out = y2 ^ y3;
    assign x4_out = y4;

endmodule

// ================================================================================
// ASCON Linear Diffusion Layer (checked)
// Implements Σ_i functions for each 64-bit word
// ================================================================================
module ascon_linear (
    input  wire [63:0] x0_in, x1_in, x2_in, x3_in, x4_in,
    output wire [63:0] x0_out, x1_out, x2_out, x3_out, x4_out
);

    // Linear diffusion functions as specified in ASCON
    // Σ0(x0) = x0 ⊕ (x0 >>> 19) ⊕ (x0 >>> 28)
    // Σ1(x1) = x1 ⊕ (x1 >>> 61) ⊕ (x1 >>> 39)  
    // Σ2(x2) = x2 ⊕ (x2 >>> 1)  ⊕ (x2 >>> 6)
    // Σ3(x3) = x3 ⊕ (x3 >>> 10) ⊕ (x3 >>> 17)
    // Σ4(x4) = x4 ⊕ (x4 >>> 7)  ⊕ (x4 >>> 41)

    function [63:0] rotr64;
        input [63:0] value;
        input [5:0] amount;
        begin
            rotr64 = (value >> amount) | (value << (64 - amount));
        end
    endfunction

    assign x0_out = x0_in ^ rotr64(x0_in, 19) ^ rotr64(x0_in, 28);
    assign x1_out = x1_in ^ rotr64(x1_in, 61) ^ rotr64(x1_in, 39);
    assign x2_out = x2_in ^ rotr64(x2_in, 1)  ^ rotr64(x2_in, 6);
    assign x3_out = x3_in ^ rotr64(x3_in, 10) ^ rotr64(x3_in, 17);
    assign x4_out = x4_in ^ rotr64(x4_in, 7)  ^ rotr64(x4_in, 41);

endmodule

// ================================================================================
// ASCON Round Constant Generation (checked)
// Generates round constants c_r for each round
// ================================================================================
module ascon_round_constant (
    input  wire [3:0] round_num,
    input  wire [3:0] total_rounds,
    output reg  [63:0] round_constant
);

    wire [3:0] rc_index;
    assign rc_index = (total_rounds == 12) ? round_num :
                     (total_rounds == 8)  ? round_num + 4 :
                     (total_rounds == 6)  ? round_num + 6 : round_num;

    always @(*) begin
        case (rc_index)
            4'h0: round_constant = 64'h00000000000000f0;
            4'h1: round_constant = 64'h00000000000000e1;
            4'h2: round_constant = 64'h00000000000000d2;
            4'h3: round_constant = 64'h00000000000000c3;
            4'h4: round_constant = 64'h00000000000000b4;
            4'h5: round_constant = 64'h00000000000000a5;
            4'h6: round_constant = 64'h0000000000000096;
            4'h7: round_constant = 64'h0000000000000087;
            4'h8: round_constant = 64'h0000000000000078;
            4'h9: round_constant = 64'h0000000000000069;
            4'ha: round_constant = 64'h000000000000005a;
            4'hb: round_constant = 64'h000000000000004b;
            default: round_constant = 64'h0000000000000000;
        endcase
    end

endmodule

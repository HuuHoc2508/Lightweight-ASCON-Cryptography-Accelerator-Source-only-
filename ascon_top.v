module ascon_top#(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH_WB = 32, // Wishbone address bus width
    parameter DATA_WIDTH_WB = 32  // Wishbone data bus width
)(
    input  wire         clk,
    input  wire         rst_n,
    // control signal
    input  wire [1:0]   crypt_variant,   // 00/01/10
    input  wire         mode,            // 0 = encrypt, 1 = decrypt 
    input  wire [5:0]   padding_missed, // count by hex (max 32 hex ~ 128bit)
    input  wire         start,
    //Input data
    input  wire [31:0]  input_data_ad,
    input  wire         ad_we,
    //input  wire         ad_read,
    input  wire [31:0]  input_data_pt,
    input  wire         pt_we,
    //input  wire         pt_read,
    input  wire [31:0]  input_data_ct,
    input  wire         ct_we,
    //input  wire         ct_read,
    
    input  wire [31:0]  input_data_key,
    input  wire         key_we,
    input  wire [31:0]  input_data_nonce,
    input  wire         nonce_we,
    input  wire [31:0]  input_data_tag,
    input  wire         tag_we,
    // Associated Data input

   	input  wire 		ad_hollow,
    // PlainText (encrypt)

	input  wire 		pt_hollow,
    // CipherText (decrypt)

	input  wire 		ct_hollow,
    input  wire         r_tag,
    // outputs 
    output wire [127:0]  e_ciphertext, // for encrypt mode
    output wire [127:0]  e_tag,
    output wire [127:0]  d_received_text, //for decrypt mode
    output wire         data_out_to_fifo_en,

    //Debug
    output wire [159:0] secret_key,   // key loaded from gateway
    output wire [127:0] nonce,
    output wire [127:0] tag_din,
        output wire         ad_req,
        output wire         pt_req,
        output wire         ct_req,
    output wire [127:0] ct_din,
    output wire         ct_valid,
    output wire         ct_last,
    
    output wire [127:0] ad_din,
    output wire         ad_valid,
    output wire         ad_last,
    
    output wire         pt_valid,
    output wire [127:0] pt_din,
    output wire         pt_last,
    
    output wire         out_de_valid,
    output wire [31:0]  data_de_out,
    input wire          read_PT_output,
    output wire         no_PT_data,
    
    output wire         out_en_valid,
    output wire [31:0]  data_en_out,
    input wire          read_CT_output,
    output wire         no_CT_data,
    
    output wire         out_tag_valid,
    output wire [31:0]  data_tag_out,
    input wire          read_tag_output,
    output wire         no_tag_data,
    
    output wire             perm_start,
    output wire             perm_done,
    output wire [319:0]        perm_out,
    output wire  [319:0]        state,
    output wire  [319:0]        state_next,
    
    output wire         no_data,
    output wire         done
    );


//    wire         ad_valid;
//    wire [127:0] ad_din;
//    wire         ad_last;
    
//    wire         pt_valid;
//    wire [127:0] pt_din;
//    wire         pt_last;
    
//    wire         ct_valid;
//    wire [127:0] ct_din;
//    wire         ct_last;
    
    
    wire         encrypt_done;
    wire         decrypt_done;
    
    wire          valid_d_rt;
    wire          valid_e_ct;
    
    wire          tag_match;
    
    assign done = encrypt_done + decrypt_done;
    assign data_out_to_fifo_en = valid_e_ct + valid_d_rt;


    reg ad_req_d, pt_req_d, ct_req_d;
    reg ad_rd, pt_rd, ct_rd;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ad_req_d <= 1'b0;
            pt_req_d <= 1'b0;
            ct_req_d <= 1'b0;
            ad_rd    <= 1'b0;
            pt_rd    <= 1'b0;
            ct_rd    <= 1'b0;
        end else begin
            // lưu trạng thái trước của các req
            ad_req_d <= ad_req;
            pt_req_d <= pt_req;
            ct_req_d <= ct_req;
    
            // phát xung 1 chu kỳ khi req chuyển từ 0 -> 1
            ad_rd <= ad_req & ~ad_req_d;
            pt_rd <= pt_req & ~pt_req_d;
            ct_rd <= ct_req & ~ct_req_d;
        end
    end

data_assembler_160 key_inst (
        .clk(clk), 
        .rst_n(rst_n),
        .data_in(input_data_key),
        .wr_en(key_we),
        .data_out(secret_key)
);

data_assembler_128 nonce_inst (
        .clk(clk), 
        .rst_n(rst_n),
        .data_in(input_data_nonce),
        .wr_en(nonce_we),
        .data_out(nonce)
);

data_assembler_128 tag_inst (
        .clk(clk), 
        .rst_n(rst_n),
        .data_in(input_data_tag),
        .wr_en(tag_we),
        .data_out(tag_din)
);

fifo_in #(
    .FIFO_DEPTH(4)
)   ad_in_fifo(
    .clk(clk),
    .rst_n(rst_n),
    .data_in(input_data_ad),
    .wr_en(ad_we),
    .rd_en(ad_rd),
    .mode_sel(~crypt_variant[0:0]),
    .data_out(ad_din),
    .empty(ad_last),
    .valid(ad_valid)
);

fifo_in #(
    .FIFO_DEPTH(8)
)   pt_in_fifo(
    .clk(clk),
    .rst_n(rst_n),
    .data_in(input_data_pt),
    .wr_en(pt_we),
    .rd_en(pt_rd),
    .mode_sel(~crypt_variant[0:0]),
    .data_out(pt_din),
    .empty(pt_last),
    .valid(pt_valid)
);

fifo_in #(
    .FIFO_DEPTH(8)
)   ct_in_fifo(
    .clk(clk),
    .rst_n(rst_n),
    .data_in(input_data_ct),
    .wr_en(ct_we),
    .rd_en(ct_rd),
    .mode_sel(~crypt_variant[0:0]),
    .data_out(ct_din),
    .empty(ct_last),
    .valid(ct_valid)
);

wire 	e_ct;
wire	d_rt;
fifo_split_128to32 #(
		.FIFO_DEPTH(32)
	) fifo_de_out (
		.clk(clk),
		.rst_n(rst_n),
		.data_in(d_received_text),
		.load(d_rt), //valid_d_rt
		.rd_en(read_PT_output),
		.data_out(data_de_out),
		.empty(no_PT_data),
		.full(),
		.valid(out_de_valid),
		.mode(crypt_variant[0:0])
	);
	
fifo_split_128to32 #(
		.FIFO_DEPTH(32)
	) fifo_en_out (
		.clk(clk),
		.rst_n(rst_n),
		.data_in(e_ciphertext),
		.load(e_ct), //valid_e_ct
		.rd_en(read_CT_output),
		.data_out(data_en_out),
		.empty(no_CT_data),
		.full(),
		.valid(out_en_valid),
		.mode(crypt_variant[0:0])
	);

fifo_split_128to32 #(
		.FIFO_DEPTH(32)
	) fifo_tag_out (
		.clk(clk),
		.rst_n(rst_n),
		.data_in(e_tag),
		.load(encrypt_done),
		.rd_en(read_tag_output),
		.data_out(data_tag_out),
		.empty(no_tag_data),
		.full(),
		.valid(out_tag_valid),
		.mode(1'b1)
	);

	
count_line_control count_block_ct(
			.clk(clk),
			.reset_n(rst_n),
			.mode(crypt_variant[0:0]),
			.done(done),
			.count(pt_we),
			.line_in(valid_e_ct),
			.line_out(e_ct)
			
);

count_line_control count_block_pt(
			.clk(clk),
			.reset_n(rst_n),
			.mode(crypt_variant[0:0]),
			.done(done),
			.count(ct_we),
			.line_in(valid_d_rt),
			.line_out(d_rt)
			
);	 

	
    // =====================================
    // Adapter Logic for Optimized Core
    // =====================================
    
    wire data_ready;
    wire waiting_for_ad;
    wire waiting_for_data;
    
    // Handshake mapping
    assign ad_req = waiting_for_ad;
    assign pt_req = (waiting_for_data && mode == 0);
    assign ct_req = (waiting_for_data && mode == 1);

    // Unified Data Mux
    reg [127:0] data_in_core;
    reg [1:0] data_type_core;
    reg data_valid_core;
    reg data_last_core;

    always @(*) begin
        data_in_core    = 128'h0;
        data_type_core  = 2'b00;
        data_valid_core = 1'b0;
        data_last_core  = 1'b0;

        if (waiting_for_ad) begin
            if (ad_hollow) begin
                if (mode == 0 && pt_valid) begin
                   data_in_core = pt_din;
                   data_type_core = 2'b01; // PT
                   data_valid_core = 1'b1;
                   data_last_core = pt_last;
                end else if (mode == 1 && ct_valid) begin
                   data_in_core = ct_din;
                   data_type_core = 2'b10; // CT
                   data_valid_core = 1'b1;
                   data_last_core = ct_last;
                end
            end else if (ad_valid) begin
                data_in_core = ad_din;
                data_type_core = 2'b00; // AD
                data_valid_core = 1'b1;
                data_last_core = ad_last;
            end
        end
        else if (waiting_for_data) begin
            if (mode == 0 && pt_valid) begin
                data_in_core = pt_din;
                data_type_core = 2'b01; // PT
                data_valid_core = 1'b1;
                data_last_core = pt_last;
            end 
            else if (mode == 1 && ct_valid) begin
                data_in_core = ct_din;
                data_type_core = 2'b10; // CT
                data_valid_core = 1'b1;
                data_last_core = ct_last;
            end
            else if ((mode == 0 && pt_hollow) || (mode == 1 && ct_hollow)) begin
                 data_valid_core = 1'b1; 
                 data_type_core = 2'b11; // Tag/Invalid/End
            end
        end
    end

    wire [127:0] out_data_core;
    wire out_valid_core;
    wire out_last_core;
    wire core_done;

    ascon_core_optimized core_inst (
        .clk(clk), 
        .rst_n(rst_n),
        
        .crypt_variant(crypt_variant),
        .mode(mode),
        .padding_missed(padding_missed),
        .secret_key(secret_key),
        .nonce(nonce),
        .r_key(start),
        .r_nonce(start),
        
        // Unified Inputs
        .data_in(data_in_core),
        .data_type(data_type_core),
        .data_valid(data_valid_core),
        .data_last(data_last_core),
        .data_ready(data_ready),
        
        // Tag Input
        .expected_tag(tag_din),
        
        // Outputs
        .out_data(out_data_core),
        .out_valid(out_valid_core),
        .out_last(out_last_core),
        
        .out_tag(e_tag),
        .tag_valid(),
        .tag_match(tag_match),
        
        .done(core_done),
        .busy(),
        
        // Flags
        .waiting_for_ad(waiting_for_ad),
        .waiting_for_data(waiting_for_data),
        
        // Debug
        .dbg_perm_start(perm_start),
        .dbg_perm_out(perm_out),
        .dbg_state(state),
        .dbg_state_next(state_next),
        .dbg_perm_done(perm_done)
    );
    
    // Output Demux
    assign e_ciphertext = (mode == 0 && out_valid_core) ? out_data_core : 128'b0;
    assign d_received_text = (mode == 1 && out_valid_core) ? out_data_core : 128'b0;
    
    assign valid_e_ct = (mode == 0) ? out_valid_core : 1'b0;
    assign valid_d_rt = (mode == 1) ? out_valid_core : 1'b0;
    
    assign encrypt_done = (mode == 0) ? core_done : 1'b0;
    assign decrypt_done = (mode == 1) ? core_done : 1'b0;
    
    
endmodule

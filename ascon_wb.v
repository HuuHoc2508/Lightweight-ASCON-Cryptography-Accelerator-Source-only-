module ascon_wb#(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH_WB = 32, // Wishbone address bus width
    parameter DATA_WIDTH_WB = 32  // Wishbone data bus width
)(
    // System Inputs
    input wire clk,
    input wire reset, // System reset (active high)
    // Wishbone Slave Interface (B4 compliant)
    input wire                          wb_cyc_i, // Cycle valid
    input wire                          wb_stb_i, // Strobe (address/data valid)
    input wire                          wb_we_i,  // Write enable (1=write, 0=read)
    input wire [ADDR_WIDTH_WB-1:0]      wb_adr_i, // Address
    input wire [DATA_WIDTH_WB-1:0]      wb_dat_i, // Write data
    input wire [DATA_WIDTH_WB/8-1:0]    wb_sel_i, // Byte select (assuming 32-bit data bus)

    output wire                         wb_ack_o, // Acknowledge
    output wire [DATA_WIDTH_WB-1:0]     wb_dat_o, // Read data    
    
    //Debug output
	 output wire        done
//    output reg wb_active_pulse,
//    output reg wb_cycle_active
//    
//    output  reg [31:0]  input_data_ad,
//    output  reg         ad_we,
//    output  reg [31:0]  input_data_pt,
//    output  reg         pt_we,
//    output  reg [31:0]  input_data_ct,
//    output  reg         ct_we,    
//    output  reg [31:0]  input_data_key,
//    output  reg         key_we,
//    output  reg [31:0]  input_data_nonce,
//    output  reg         nonce_we,
//    output  reg [31:0]  input_data_tag,
//    output  reg         tag_we,
//    output  reg         start,
//    output  reg         done_status,
//    
//    output wire [159:0] secret_key,
//    output wire [127:0] nonce,
//    output wire [127:0] tag_din,
//    output wire [127:0] ad_din,
//    output wire [127:0] ct_din,
//    output wire [127:0] pt_din,
//    output wire [127:0] d_received_text,
//    output wire [127:0] e_ciphertext,
//    output wire [127:0] e_tag,
//    
//    output wire         out_de_valid,
//    output wire [31:0]  data_de_out,
//    output wire          read_PT_output,
//    output wire         no_PT_data,
//    
//    output wire         out_en_valid,
//    output wire [31:0]  data_en_out,
//    output wire          read_CT_output,
//    output wire         no_CT_data,
//    
//    output wire         out_tag_valid,
//    output wire [31:0]  data_tag_out,
//    output wire          read_tag_output,
//    output wire         no_tag_data,
//    
//
//    
//            output wire             perm_start,
//    output wire             perm_done,
//    output wire [319:0]        perm_out,
//    output wire  [319:0]        state,
//    output wire  [319:0]        state_next,
//        
//    output reg         mode,
//    output reg [1:0]   crypt_variant,
//    output reg [5:0]   padding_miss
    
);
    // === Internal registers restored from commented signals ===
    reg wb_active_pulse;
    reg wb_cycle_active;

    reg [31:0] input_data_ad;
    reg        ad_we;
    reg [31:0] input_data_pt;
    reg        pt_we;
    reg [31:0] input_data_ct;
    reg        ct_we;
    reg [31:0] input_data_key;
    reg        key_we;
    reg [31:0] input_data_nonce;
    reg        nonce_we;
    reg [31:0] input_data_tag;
    reg        tag_we;

    reg        start;
    reg        done_status;

    // Control registers
    reg        mode;
    reg [1:0]  crypt_variant;
    reg [5:0]  padding_miss;

    // === Output wires from ascon_top ===
    wire [159:0] secret_key;
    wire [127:0] nonce;
    wire [127:0] tag_din;
    wire [127:0] ad_din;
    wire [127:0] ct_din;
    wire [127:0] pt_din;
    wire [127:0] d_received_text;
    wire [127:0] e_ciphertext;
    wire [127:0] e_tag;

    wire         out_de_valid;
    wire [31:0]  data_de_out;
    wire         read_PT_output;
    wire         no_PT_data;

    wire         out_en_valid;
    wire [31:0]  data_en_out;
    wire         read_CT_output;
    wire         no_CT_data;

    wire         out_tag_valid;
    wire [31:0]  data_tag_out;
    wire         read_tag_output;
    wire         no_tag_data;

    // Permutation debug signals
    wire         perm_start;
    wire         perm_done;
    wire [319:0] perm_out;
    wire [319:0] state;
    wire [319:0] state_next;

    localparam ADDR_SET_UP          = 32'h0000_0000;    //
    localparam ADDR_START           = 32'h0000_0004;    //ADDR_STATUS
    localparam ADDR_KEY             = 32'h0000_0008;
    localparam ADDR_NONCE           = 32'h0000_000C;
    localparam ADDR_TAG             = 32'h0000_0010;    //ADDR_TAG_RESULT
    localparam ADDR_AD              = 32'h0000_0014;    //
    localparam ADDR_PT              = 32'h0000_0018;    //ADDR_EN_RESULT
    localparam ADDR_CT              = 32'h0000_001C;    //ADDR_DE_RESULT

    reg wb_ack_o_reg;
    reg [DATA_WIDTH_WB-1:0] wb_dat_o_reg;

reg read_pending;

always @(posedge clk or posedge reset) begin
	if (reset) begin
		wb_ack_o_reg <= 1'b0;
		read_pending <= 1'b0;
	end else begin
		wb_ack_o_reg <= 1'b0;
		if (wb_cyc_i && wb_stb_i) begin
			if (wb_we_i) begin
				wb_ack_o_reg <= 1'b1;
			end else begin
				if (!read_pending) begin
					read_pending <= 1'b1;
				end else begin
					wb_ack_o_reg <= 1'b1;
				end
			end
		end else begin
			read_pending <= 1'b0;
		end
	end
end
    
always @(posedge clk or posedge reset) 
begin
	if (reset) 
		begin
			mode            <= 1'b0;
			crypt_variant   <= 2'b00;
			padding_miss    <= 6'd0;
			
			input_data_ad   <= 32'd0;
			ad_we           <= 1'b0;
			input_data_pt   <= 32'd0;
			pt_we           <= 1'b0;
			input_data_ct   <= 32'd0;
			ct_we           <= 1'b0;
			input_data_key  <= 32'd0;
			key_we          <= 1'b0;
			input_data_nonce    <= 32'd0;
			nonce_we        <= 1'b0;
			input_data_tag  <= 32'd0;
			tag_we          <= 1'b0;
			
			start           <= 1'b0;
			wb_dat_o_reg    <= 32'd0;

			wb_cycle_active <= 1'b0;
			wb_active_pulse <= 1'b0;
			done_status     <= 1'b0;
		end 
	else 
		begin
			wb_active_pulse <= 1'b0;
							
			// Auto-clears
			if (start)       start       <= 1'b0;
			if (key_we)      key_we      <= 1'b0;
			if (nonce_we)    nonce_we    <= 1'b0;
			if (tag_we)      tag_we      <= 1'b0;
			if (ad_we)       ad_we       <= 1'b0;
			if (pt_we)       pt_we       <= 1'b0;
			if (ct_we)       ct_we       <= 1'b0;

			if (done)
				done_status <= 1'b1;

			//---------------------------------------------------------
			// 1) LOGIC ĐỌC — luôn xử lý trước, không phụ thuộc wb_cycle_active
			//---------------------------------------------------------
			if (wb_cyc_i && wb_stb_i && !wb_we_i && read_pending) begin
				case (wb_adr_i)
					ADDR_START:    wb_dat_o_reg <= {{31{1'b0}}, done_status};
					ADDR_PT:       wb_dat_o_reg <= data_en_out;
					ADDR_TAG:      wb_dat_o_reg <= data_tag_out;
					ADDR_CT:       wb_dat_o_reg <= data_de_out;
					default:         wb_dat_o_reg <= 32'd0;
				endcase
			end

			//---------------------------------------------------------
			// 2) LOGIC GHI — chỉ khi transaction mới (!wb_cycle_active)
			//---------------------------------------------------------
			if (wb_cyc_i && wb_stb_i) begin
				if (!wb_cycle_active) begin
					wb_active_pulse <= 1'b1;
					wb_cycle_active <= 1'b1;
                    if (wb_we_i)    begin
					case (wb_adr_i)

                            ADDR_SET_UP: begin
                                mode          <= wb_dat_i[0];
                                crypt_variant <= wb_dat_i[2:1];
                            end
    
                            ADDR_KEY: begin
                                input_data_key <= wb_dat_i;
                                key_we <= 1'b1;
                            end
    
                            ADDR_NONCE: begin
                                input_data_nonce <= wb_dat_i;
                                nonce_we <= 1'b1;
                            end
    
                            ADDR_TAG: begin
                                input_data_tag <= wb_dat_i;
                                tag_we <= 1'b1;
                            end
    
                            ADDR_AD: begin
                                input_data_ad <= wb_dat_i;
                                ad_we <= 1'b1;
                            end
    
                            ADDR_PT: begin
                                input_data_pt <= wb_dat_i;
                                pt_we <= 1'b1;
                            end
    
                            ADDR_CT: begin
                                input_data_ct <= wb_dat_i;
                                ct_we <= 1'b1;
                            end
    
                            ADDR_START: begin
                                start <= 1'b1;
                                done_status <= 1'b0;
                            end
    
                        endcase
					end
				end
			end 
			//---------------------------------------------------------
			// 3) Không có transaction → clear cycle active
			//---------------------------------------------------------
			else begin
				wb_cycle_active <= 1'b0;
			end

		end
end

assign read_CT_output  = (wb_cyc_i && wb_stb_i && !wb_cycle_active && !wb_we_i && (wb_adr_i == ADDR_PT));
assign read_tag_output = (wb_cyc_i && wb_stb_i && !wb_cycle_active && !wb_we_i && (wb_adr_i == ADDR_TAG));
assign read_PT_output  = (wb_cyc_i && wb_stb_i && !wb_cycle_active && !wb_we_i && (wb_adr_i == ADDR_CT));
ascon_top #(
    .DATA_WIDTH(32),
    .ADDR_WIDTH_WB(32),
    .DATA_WIDTH_WB(32)
) ascon (
    .clk(clk),
    .rst_n(!reset),
    // control signal
    .crypt_variant(crypt_variant),
    .mode(mode),
    .padding_missed(padding_miss),
    .start(start),    
    //Input data
    .input_data_ad(input_data_ad),
    .ad_we(ad_we),
    .input_data_pt(input_data_pt),
    .pt_we(pt_we),
    .input_data_ct(input_data_ct),
    .ct_we(ct_we),
    .input_data_key(input_data_key),
    .key_we(key_we),
    .input_data_nonce(input_data_nonce),
    .nonce_we(nonce_we),
    .input_data_tag(input_data_tag),
    .tag_we(tag_we),
    .ad_hollow(1'b0),
    .pt_hollow(1'b0),
    .ct_hollow(1'b0),
    .r_tag(1'b0),
// outputs
    .done(done),
//Debug 
    .e_ciphertext(e_ciphertext),
    .e_tag(e_tag),
    .d_received_text(d_received_text),
    .secret_key(secret_key),
    .nonce(nonce),
    .tag_din(tag_din),
    .pt_din(pt_din),
    .ad_din(ad_din),
    .ct_din(ct_din),
    
    .out_de_valid(out_de_valid),
    .data_de_out(data_de_out),
    .read_PT_output(read_PT_output),
    .no_PT_data(no_PT_data),

    .out_en_valid(out_en_valid),
    .data_en_out(data_en_out),
    .read_CT_output(read_CT_output),
    .no_CT_data(no_CT_data),

    .out_tag_valid(out_tag_valid),
    .data_tag_out(data_tag_out),
    .read_tag_output(read_tag_output),
    .no_tag_data(no_tag_data)
   
);

assign wb_ack_o = wb_ack_o_reg;
assign wb_dat_o = wb_dat_o_reg;

endmodule
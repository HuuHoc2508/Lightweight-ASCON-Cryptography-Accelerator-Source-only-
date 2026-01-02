module data_assembler_160 (
	input  wire         clk,
	input  wire         rst_n,
	input  wire [31:0]  data_in,
	input  wire         wr_en,
	output reg  [159:0] data_out
);

	always @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			data_out <= 160'b0;
		end else if (wr_en) begin
			// Dịch trái 32 bit (loại bỏ word cũ nhất), thêm word mới vào MSB
			data_out <= {data_out[127:0],data_in};
		end
	end

endmodule
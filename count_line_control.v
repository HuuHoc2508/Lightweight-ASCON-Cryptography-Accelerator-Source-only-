module count_line_control (
	input	wire		clk,
	input	wire		reset_n,	// active LOW
	input	wire		done,		// active HIGH yêu cầu reset
	input	wire		mode,		// 0 = 2 count → +1 ; 1 = 4 count → +1
	input	wire		count,		// pulse
	input	wire		line_in,	// pulse
	output	reg		line_out
);

	// Reset nội bộ: ACTIVE HIGH
	wire reset = (!reset_n) | done;

	reg [31:0] count_total;
	reg [31:0] line_allow_count;
	reg [2:0]  count_group;

	always @(posedge clk or posedge reset) begin
		if (reset) begin
			count_total      <= 32'd0;
			line_allow_count <= 32'd0;
			count_group      <= 3'd0;
			line_out         <= 1'b0;
		end else begin

			// --- Gom nhóm count ---
			if (count) begin
				count_group <= count_group + 1'b1;

				if (!mode && count_group == 3'd1) begin
					count_total <= count_total + 1'b1;
					count_group <= 3'd0;
				end

				if (mode && count_group == 3'd3) begin
					count_total <= count_total + 1'b1;
					count_group <= 3'd0;
				end
			end

			// --- Xử lý line_in ---
			if (line_in) begin
				if (line_allow_count < (count_total - 1)) begin
					line_out <= 1'b1;
					line_allow_count <= line_allow_count + 1'b1;
				end else begin
					line_out <= 1'b0;
				end
			end else begin
				line_out <= 1'b0;
			end

		end
	end

endmodule

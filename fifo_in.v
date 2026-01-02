`timescale 1ns / 1ps
`default_nettype none

module fifo_in #(
    parameter FIFO_DEPTH = 8  // có thể thay đổi chiều sâu FIFO
)(
    input  wire         clk,
    input  wire         rst_n,
    input  wire [31:0]  data_in,
    input  wire         wr_en,
    input  wire         rd_en,      // tín hiệu đọc
    input  wire         mode_sel,   // 0 = chế độ 1 (4 data), 1 = chế độ 2 (2 data + pad)
    output reg  [127:0] data_out,
    output wire         empty,
    output reg          valid
);
    // =====================================================
    // Internal signals
    // =====================================================
    reg [127:0] data_buffer;     // lưu tạm 128-bit
    reg [1:0]   count;           // đếm số lần ghi 32-bit
    reg         pack_ready;      // báo khi đã gom đủ 128-bit

    // FIFO memory
    reg [127:0] fifo_mem [0:FIFO_DEPTH-1];
    reg [$clog2(FIFO_DEPTH)-1:0]  wr_ptr;
    reg [$clog2(FIFO_DEPTH)-1:0]  rd_ptr;
    reg [$clog2(FIFO_DEPTH+1)-1:0] fifo_count;

    assign empty = (fifo_count == 0);

    // =====================================================
    // Gom dữ liệu 32-bit thành 128-bit
    // =====================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_buffer <= 128'd0;
            count       <= 2'd0;
            pack_ready  <= 1'b0;
        end else begin
            pack_ready <= 1'b0;
            if (wr_en) begin
                // shift theo big-endian: từ trái sang phải
                data_buffer <= {data_buffer[95:0], data_in};
                count <= count + 1;

                // Kiểm tra khi đủ dữ liệu để nạp vào FIFO
                if ((!mode_sel && count == 2'd3) || (mode_sel && count == 2'd1)) begin
                    pack_ready <= 1'b1;
                    count <= 2'd0;

                    // Nếu chế độ 2, pad 64-bit zero ở phần sau
                    if (mode_sel)
                        data_buffer <= {data_buffer[63:0], data_in, 64'd0};
                    else
                        data_buffer <= {data_buffer[95:0], data_in};
                end
            end
        end
    end

    // =====================================================
    // Ghi vào và đọc ra FIFO (có wrap-around)
    // =====================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= 0;
            rd_ptr <= 0;
            fifo_count <= 0;
            data_out <= 128'd0;
            valid <= 1'b0;
        end else begin
            valid <= 1'b0;
            // ---------- Ghi vào FIFO ----------
            if (pack_ready && fifo_count < FIFO_DEPTH) begin
                fifo_mem[wr_ptr] <= data_buffer;

                // tăng con trỏ, có wrap-around
                if (wr_ptr == FIFO_DEPTH - 1)
                    wr_ptr <= 0;
                else
                    wr_ptr <= wr_ptr + 1;

                fifo_count <= fifo_count + 1;
            end

            // ---------- Đọc ra FIFO ----------
            if (rd_en && fifo_count > 0) begin
                data_out <= fifo_mem[rd_ptr];
                valid <= 1'b1;

                // tăng con trỏ, có wrap-around
                if (rd_ptr == FIFO_DEPTH - 1)
                    rd_ptr <= 0;
                else
                    rd_ptr <= rd_ptr + 1;

                fifo_count <= fifo_count - 1;
            end
        end
    end

endmodule

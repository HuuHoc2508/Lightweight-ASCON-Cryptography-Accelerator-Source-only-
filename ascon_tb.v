`timescale 1ns/1ps

module ascon_tb;

    // ========================================
    // Clock & Reset
    // ========================================
    reg clk;
    wire clk_in_p;
    wire clk_in_n;
    reg rst_n;

    // ========================================
    // Control Signals
    // ========================================
    reg [1:0] crypt_variant;
    reg mode;                   // 0 = encrypt, 1 = decrypt
    reg [5:0] padding_missed;

    // ========================================
    // Key & Nonce
    // ========================================
    reg [159:0] secret_key;
    reg [127:0] nonce;
    reg r_key, r_nonce;

    // ========================================
    // Unified Data Interface (New Interface)
    // ========================================
    reg [127:0] data_in;
    reg [1:0]   data_type;      // 00=AD, 01=PT, 10=CT, 11=TAG
    reg         data_valid;
    reg         data_last;
    wire        data_ready;

    // ========================================
    // Outputs
    // ========================================
    wire [127:0] out_data;
    wire         out_valid;
    wire         out_last;
    wire [127:0] out_tag;
    wire         tag_valid;
    reg          tag_ready;     // Input to DUT (flow control for tag)
    wire         tag_match;
    wire         done;

    // ========================================
    // Instantiate DUT (Optimized Version)
    // ========================================
    ascon uut (
        .clk_in_p(clk_in_p),
        .clk_in_n(clk_in_n),
        .rst_n(rst_n),
        .crypt_variant(crypt_variant),
        .mode(mode),
        .padding_missed(padding_missed),
        .secret_key(secret_key),
        .nonce(nonce),
        .r_key(r_key),
        .r_nonce(r_nonce),
        .data_in(data_in),
        .data_type(data_type),
        .data_valid(data_valid),
        .data_last(data_last),
        .data_ready(data_ready),
        .out_data(out_data),
        .out_valid(out_valid),
        .out_last(out_last),
        .out_tag(out_tag),
        .tag_valid(tag_valid),
        .tag_ready(tag_ready),
        .tag_match(tag_match),
        .done(done)
    );

    // ========================================
    // Clock Generation (200 MHz)
    // ========================================
    initial begin
        clk = 0;
        forever #2.5 clk = ~clk;
    end

    // Differential Clock Driver
    assign clk_in_p = clk;
    assign clk_in_n = ~clk;

    // ========================================
    // Helper Tasks (Abstracts the handshake)
    // ========================================
    
    // Task to send AD Block
    task send_ad(input [127:0] data, input is_last);
        begin
            // Wait until DUT is ready to receive
            wait(data_ready);
            @(posedge clk); 
            
            // Drive signals
            data_type  <= 2'b00; // AD
            data_in    <= data;
            data_valid <= 1'b1;
            data_last  <= is_last;

            // Hold for 1 clock cycle
            @(posedge clk);
            
            // Release
            data_valid <= 1'b0;
            data_last  <= 1'b0;
            
            // Optional: Wait small delay for FSM to process if strictly needed, 
            // but waiting for data_ready at start of next call is usually sufficient.
        end
    endtask

    // Task to send PT Block
    task send_pt(input [127:0] data, input is_last);
        begin
            wait(data_ready);
            @(posedge clk);
            
            data_type  <= 2'b01; // PT
            data_in    <= data;
            data_valid <= 1'b1;
            data_last  <= is_last;

            @(posedge clk);
            
            data_valid <= 1'b0;
            data_last  <= 1'b0;
        end
    endtask

    // ========================================
    // Main Test Sequence
    // ========================================
    initial begin
        // 1. Initialize Signals
        rst_n = 0;
        mode = 0;               // Encrypt
        crypt_variant = 2'b00;  // Ascon-128 (a)
        padding_missed = 6'd0;
        
        secret_key = 0;
        nonce = 0;
        r_key = 0;
        r_nonce = 0;
        
        data_in = 0;
        data_type = 0;
        data_valid = 0;
        data_last = 0;
        tag_ready = 1; // Always ready to accept tag in TB

        $display("[%t] Simulation Started", $time);

        // 2. Reset Pulse
        #20;
        rst_n = 1;
        #20;

        // 3. Load Key & Nonce
        @(posedge clk);
        secret_key = 160'h0000_0000_0012_3456_7890_1234_5678_9012_3456_7890;
        nonce      = 128'h0012_3456_7890_1234_5678_9012_3456_7890;
        r_key      = 1;
        r_nonce    = 1;
        
        @(posedge clk);
        r_key      = 0;
        r_nonce    = 0;
        $display("[%t] Key & Nonce Loaded. Waiting for Initialization...", $time);

        // 4. Send Associated Data (AD)
        // --------------------------------
        // DUT needs time to initialize (perm_start -> perm_done).
        // send_ad task will automatically wait for data_ready.
        
        // Block 1
        send_ad(128'h11111111_11111111_00000000_00000000, 0);
        $display("[%t] AD Block 1 sent", $time);

        // Block 2
        send_ad(128'h22222222_22222222_00000000_00000000, 0);
        $display("[%t] AD Block 2 sent", $time);
        
        // Block 3
        send_ad(128'h33333333_33333333_00000000_00000000, 0);
        $display("[%t] AD Block 3 sent", $time);

        // Block 4 (Last AD)
        send_ad(128'h80000000_00000000_00000000_00000000, 1);
        $display("[%t] AD Block 4 (Last) sent", $time);


        // 5. Send Plaintext (PT)
        // --------------------------------
        
        // Block 1
        send_pt(128'h44444444_44444444_00000000_00000000, 0);
        $display("[%t] PT Block 1 sent", $time);
        
        // Block 2
        send_pt(128'h55555555_55555555_00000000_00000000, 0);
        $display("[%t] PT Block 2 sent", $time);
        
        // Block 3
        send_pt(128'h66666666_66666666_00000000_00000000, 0);
        $display("[%t] PT Block 3 sent", $time);

        // Block 4
        send_pt(128'h77777777_77777777_00000000_00000000, 0);
        $display("[%t] PT Block 3 sent", $time);

        // Block 5 
        send_pt(128'h88888888_88888888_00000000_00000000, 0);
        $display("[%t] PT Block 3 sent", $time);

        // Block 6 (Last PT with padding miss configured logic)
        // Note: padding_missed is set to 0 initially, change signals before sending last if needed logic differs
        send_pt(128'h80000000_00000000_00000000_00000000, 1);
        $display("[%t] PT Block 4 (Last) sent", $time);

        // 6. Wait for Completion
        // --------------------------------
        wait(done);
        $display("[%t] Encryption DONE signal received", $time);
        
        // Wait a bit more to ensure waveforms are clear
        #100;
        $display("[%t] Test Finished", $time);
        $finish;
    end

    // ========================================
    // Monitor Output
    // ========================================
    always @(posedge clk) begin
        if (out_valid) begin
            $display("[%t] OUTPUT DATA RECIEVED: %h | Last: %b", $time, out_data, out_last);
        end
        if (tag_valid) begin
            $display("[%t] TAG GENERATED: %h", $time, out_tag);
        end
    end

endmodule
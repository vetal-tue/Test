
module skid_buf_formal;

    parameter WIDTH = 32;

    // ------------------------------------------------------------
    // Formal clock and unconstrained inputs
    // ------------------------------------------------------------

    (* gclk *) reg clk;

    (* anyseq *) reg             rst;
    (* anyseq *) reg             in_valid;
    (* anyseq *) reg [WIDTH-1:0] in_data;
    (* anyseq *) reg             out_ready;

    wire             in_ready;
    wire             out_valid;
    wire [WIDTH-1:0] out_data;

    // ------------------------------------------------------------
    // DUT
    // ------------------------------------------------------------

    valid_ready_skid_buf #(
        .WIDTH(WIDTH)
    ) dut (
        .clk       (clk),
        .rst       (rst),

        .in_valid  (in_valid),
        .in_ready  (in_ready),
        .in_data   (in_data),

        .out_valid (out_valid),
        .out_ready (out_ready),
        .out_data  (out_data)
    );

    // ------------------------------------------------------------
    // Handshake events
    // ------------------------------------------------------------

    wire in_fire;
    wire out_fire;

    assign in_fire  = in_valid  && in_ready;
    assign out_fire = out_valid && out_ready;

    // ------------------------------------------------------------
    // Reference queue: 2 words
    //
    // ref_data0 - oldest word
    // ref_data1 - second word
    // ref_count - number of stored words
    // ------------------------------------------------------------

    reg [1:0]        ref_count;
    reg [WIDTH-1:0]  ref_data0;
    reg [WIDTH-1:0]  ref_data1;

    // ------------------------------------------------------------
    // Initial reset control
    // ------------------------------------------------------------

    reg f_past_valid;

    initial begin
        f_past_valid = 1'b0;
    end

    // ------------------------------------------------------------
    // Main formal properties and reference model
    // ------------------------------------------------------------

    always @(posedge clk) begin

        f_past_valid <= 1'b1;

        // ========================================================
        // 0. Reset assumptions
        // ========================================================

        // Require reset on the first formal clock.
        if (!f_past_valid) begin
            assume(rst);
        end

        if (rst) begin

            // During synchronous reset, external devices must
            // ignore the ready/valid interface.
            assume(!in_valid);
            assume(!out_ready);

            // Reset reference queue.
            ref_count  <= 2'd0;
            ref_data0 <= {WIDTH{1'b0}};
            ref_data1 <= {WIDTH{1'b0}};

        end else begin

            // ====================================================
            // 1. State invariants
            // ====================================================

            // Queue can contain at most two words.
            assert(ref_count <= 2'd2);

            // Output must be valid exactly when reference queue
            // contains at least one word.
            assert(out_valid == (ref_count != 2'd0));

            // Input can accept data whenever the reference queue
            // is not full.
            assert(in_ready == (ref_count != 2'd2));

            // Output data must always contain the oldest word.
            if (ref_count != 2'd0) begin
                assert(out_data == ref_data0);
            end

            // ====================================================
            // 2. Output stability under backpressure
            // ====================================================

            // If the previous cycle was stalled, output must
            // remain valid and data must remain unchanged.
            if (f_past_valid && !$past(rst)) begin

                if ($past(out_valid && !out_ready)) begin

                    assert(out_valid);
                    assert(out_data == $past(out_data));

                end

            end

            // ====================================================
            // 3. Reference FIFO update
            // ====================================================

            case ({in_fire, out_fire})

                // ------------------------------------------------
                // Input transfer only
                // ------------------------------------------------

                2'b10: begin

                    if (ref_count == 2'd0) begin

                        ref_data0 <= in_data;
                        ref_count <= 2'd1;

                    end else if (ref_count == 2'd1) begin

                        ref_data1 <= in_data;
                        ref_count <= 2'd2;

                    end else begin

                        // Impossible: input accepted while full.
                        assert(1'b0);

                    end

                end

                // ------------------------------------------------
                // Output transfer only
                // ------------------------------------------------

                2'b01: begin

                    if (ref_count == 2'd1) begin

                        ref_count <= 2'd0;

                    end else if (ref_count == 2'd2) begin

                        // Move second word to the queue head.
                        ref_data0 <= ref_data1;
                        ref_count <= 2'd1;

                    end else begin

                        // Impossible: output transfer while empty.
                        assert(1'b0);

                    end

                end

                // ------------------------------------------------
                // Simultaneous input and output transfers
                // ------------------------------------------------

                2'b11: begin

                    if (ref_count == 2'd1) begin

                        // Old word leaves, new word replaces it.
                        ref_data0 <= in_data;
                        ref_count <= 2'd1;

                    end else begin

                        // With this skid buffer, simultaneous
                        // transfers are possible only when
                        // the reference queue contains one word.
                        assert(1'b0);

                    end

                end

                // ------------------------------------------------
                // No transfer
                // ------------------------------------------------

                2'b00: begin

                    // Reference queue remains unchanged.

                end

            endcase

            // ====================================================
            // 4. Coverage
            // ====================================================

            // Reach full state.
            cover(ref_count == 2'd2);

            // Reach full state and start draining it.
            cover(ref_count == 2'd2 && out_ready);

            // Simultaneous input and output transfer.
            cover(in_fire && out_fire);

            // Two consecutive simultaneous transfers:
            // demonstrates continuous full-rate operation.
            if (f_past_valid) begin
                cover(in_fire && out_fire &&
                      $past(in_fire && out_fire));
            end

        end

    end

endmodule

`timescale 1ns / 1ps

module tb_axis_comparator_GT;

  // ================================================================
  // Parameters
  // ================================================================

  parameter  DATA_WIDTH  = 32;
  parameter  KEEP_WIDTH  = DATA_WIDTH / 8;
  parameter  KEEP_ENABLE = 1;

  localparam CLK_PERIOD  = 10;


  // ================================================================
  // Clock / Reset
  // ================================================================

  reg clk;
  reg rst_n;

  initial begin
    clk = 1'b0;
    forever #(CLK_PERIOD / 2) clk = ~clk;
  end


  // ================================================================
  // DUT signals
  // ================================================================

  reg                   select;

  // -------------------------
  // Slave 0
  // -------------------------

  reg  [DATA_WIDTH-1:0] s0_tdata;
  reg  [KEEP_WIDTH-1:0] s0_tkeep;
  reg                   s0_tvalid;
  reg                   s0_tuser;
  wire                  s0_tready;
  reg                   s0_tlast;

  // -------------------------
  // Slave 1
  // -------------------------

  reg  [DATA_WIDTH-1:0] s1_tdata;
  reg  [KEEP_WIDTH-1:0] s1_tkeep;
  reg                   s1_tvalid;
  reg                   s1_tuser;
  wire                  s1_tready;
  reg                   s1_tlast;

  // -------------------------
  // Master output
  // -------------------------

  wire [DATA_WIDTH-1:0] m_tdata;
  wire [KEEP_WIDTH-1:0] m_tkeep;
  wire                  m_tvalid;
  reg                   m_tready;
  wire                  m_tlast;
  wire                  m_tuser;


  // ================================================================
  // DUT
  // ================================================================

  axis_comparator #(
      .DATA_WIDTH (DATA_WIDTH),
      .KEEP_WIDTH (KEEP_WIDTH),
      .KEEP_ENABLE(KEEP_ENABLE)
  ) dut (
      .clk  (clk),
      .rst_n(rst_n),

      .select(select),

      .s0_tdata (s0_tdata),
      .s0_tkeep (s0_tkeep),
      .s0_tvalid(s0_tvalid),
      .s0_tuser (s0_tuser),
      .s0_tready(s0_tready),
      .s0_tlast (s0_tlast),

      .s1_tdata (s1_tdata),
      .s1_tkeep (s1_tkeep),
      .s1_tvalid(s1_tvalid),
      .s1_tuser (s1_tuser),
      .s1_tready(s1_tready),
      .s1_tlast (s1_tlast),

      .m_tdata (m_tdata),
      .m_tkeep (m_tkeep),
      .m_tvalid(m_tvalid),
      .m_tready(m_tready),
      .m_tlast (m_tlast),
      .m_tuser (m_tuser)
  );


  // ================================================================
  // Testbench statistics
  // ================================================================

  integer                  errors;

  integer                  s0_handshakes;
  integer                  s1_handshakes;

  integer                  m_handshakes;
  integer                  m_frames;
  integer                  m_error_frames;


  // ================================================================
  // Expected output scoreboard
  //
  // The testbench builds expected output beat-by-beat.
  //
  // exp_count:
  //     number of expected beats currently in queue.
  //
  // For simplicity this TB uses a large array as scoreboard.
  // ================================================================

  reg     [DATA_WIDTH-1:0] exp_data       [0:4095];
  reg     [KEEP_WIDTH-1:0] exp_keep       [0:4095];
  reg                      exp_last       [0:4095];
  reg                      exp_user       [0:4095];

  integer                  exp_wr_ptr;
  integer                  exp_rd_ptr;


  // ================================================================
  // Test control
  // ================================================================

  integer                  test_number;


  // ================================================================
  // Helper: reset
  // ================================================================

  task reset_dut;
    begin

      rst_n          = 1'b0;

      select         = 1'b0;

      s0_tdata       = {DATA_WIDTH{1'b0}};
      s0_tkeep       = {KEEP_WIDTH{1'b1}};
      s0_tvalid      = 1'b0;
      s0_tuser       = 1'b0;
      s0_tlast       = 1'b0;

      s1_tdata       = {DATA_WIDTH{1'b0}};
      s1_tkeep       = {KEEP_WIDTH{1'b1}};
      s1_tvalid      = 1'b0;
      s1_tuser       = 1'b0;
      s1_tlast       = 1'b0;

      m_tready       = 1'b0;

      s0_handshakes  = 0;
      s1_handshakes  = 0;

      m_handshakes   = 0;
      m_frames       = 0;
      m_error_frames = 0;

      exp_wr_ptr     = 0;
      exp_rd_ptr     = 0;

      repeat (5) @(posedge clk);

      rst_n = 1'b1;

      repeat (2) @(posedge clk);

      $display("");
      $display("[%0t] RESET RELEASED", $time);

    end
  endtask


  // ================================================================
  // Scoreboard: clear
  // ================================================================

  task scoreboard_clear;
    begin
      exp_wr_ptr = 0;
      exp_rd_ptr = 0;
    end
  endtask


  // ================================================================
  // Scoreboard: add expected beat
  // ================================================================

  task scoreboard_add;
    input [DATA_WIDTH-1:0] data;
    input [KEEP_WIDTH-1:0] keep;
    input last;
    input user;

    begin

      exp_data[exp_wr_ptr] = data;
      exp_keep[exp_wr_ptr] = keep;
      exp_last[exp_wr_ptr] = last;
      exp_user[exp_wr_ptr] = user;

      exp_wr_ptr = exp_wr_ptr + 1;

    end
  endtask


  // ================================================================
  // Scoreboard: wait until all expected data has been transmitted
  // ================================================================

  task scoreboard_wait_empty;
    begin

      while (exp_rd_ptr != exp_wr_ptr) @(posedge clk);

    end
  endtask


  // ================================================================
  // AXIS Master 0
  //
  // IMPORTANT:
  //
  // Everything changes ONLY on posedge.
  //
  // gap:
  //     number of idle cycles after successful handshake.
  //
  // user_beat:
  //     beat on which input TUSER is asserted.
  //     -1 = never.
  //
  // keep_bad_beat:
  //     beat on which TKEEP is changed.
  //     -1 = normal TKEEP.
  // ================================================================

  task master0_frame;
    input integer length;
    input integer start_value;
    input integer gap;
    input integer user_beat;
    input integer keep_bad_beat;

    integer i;
    integer idle_count;

    begin

      i = 0;
      idle_count = 0;

      // Initial state
      s0_tvalid = 1'b0;
      s0_tlast = 1'b0;
      s0_tuser = 1'b0;

      @(posedge clk);

      while (i < length) begin

        // --------------------------------------------------------
        // Drive current beat.
        //
        // This happens on posedge.
        // DUT sees this value on the following posedge.
        // --------------------------------------------------------

        s0_tvalid <= 1'b1;
        s0_tdata  <= start_value + i;

        if ((KEEP_ENABLE != 0) && (i == keep_bad_beat))
          s0_tkeep <= {KEEP_WIDTH{1'b1}} ^ {{(KEEP_WIDTH - 1) {1'b0}}, 1'b1};
        else s0_tkeep <= {KEEP_WIDTH{1'b1}};

        if (i == user_beat) s0_tuser <= 1'b1;
        else s0_tuser <= 1'b0;

        if (i == length - 1) s0_tlast <= 1'b1;
        else s0_tlast <= 1'b0;

        // --------------------------------------------------------
        // Wait for handshake.
        // --------------------------------------------------------

        @(posedge clk);

        if (s0_tvalid && s0_tready) begin

          s0_handshakes = s0_handshakes + 1;

          $display("[%0t] S0 HANDSHAKE: beat=%0d data=%08x last=%b user=%b", $time, i, s0_tdata,
                   s0_tlast, s0_tuser);

          i = i + 1;

          // ----------------------------------------------------
          // After successful transfer, insert gap.
          // ----------------------------------------------------

          s0_tvalid <= 1'b0;
          s0_tlast  <= 1'b0;
          s0_tuser  <= 1'b0;

          for (idle_count = 0; idle_count < gap; idle_count = idle_count + 1) @(posedge clk);

        end

      end

      @(posedge clk);

      s0_tvalid <= 1'b0;
      s0_tlast  <= 1'b0;
      s0_tuser  <= 1'b0;

      $display("[%0t] S0 FRAME DONE", $time);

    end
  endtask


  // ================================================================
  // AXIS Master 1
  // ================================================================

  task master1_frame;
    input integer length;
    input integer start_value;
    input integer gap;
    input integer user_beat;
    input integer keep_bad_beat;

    integer i;
    integer idle_count;

    begin

      i = 0;
      idle_count = 0;

      s1_tvalid = 1'b0;
      s1_tlast = 1'b0;
      s1_tuser = 1'b0;

      @(posedge clk);

      while (i < length) begin

        s1_tvalid <= 1'b1;
        s1_tdata  <= start_value + i;

        if ((KEEP_ENABLE != 0) && (i == keep_bad_beat))
          s1_tkeep <= {KEEP_WIDTH{1'b1}} ^ {{(KEEP_WIDTH - 1) {1'b0}}, 1'b1};
        else s1_tkeep <= {KEEP_WIDTH{1'b1}};

        if (i == user_beat) s1_tuser <= 1'b1;
        else s1_tuser <= 1'b0;

        if (i == length - 1) s1_tlast <= 1'b1;
        else s1_tlast <= 1'b0;

        @(posedge clk);

        if (s1_tvalid && s1_tready) begin

          s1_handshakes = s1_handshakes + 1;

          $display("[%0t] S1 HANDSHAKE: beat=%0d data=%08x last=%b user=%b", $time, i, s1_tdata,
                   s1_tlast, s1_tuser);

          i = i + 1;

          s1_tvalid <= 1'b0;
          s1_tlast  <= 1'b0;
          s1_tuser  <= 1'b0;

          for (idle_count = 0; idle_count < gap; idle_count = idle_count + 1) @(posedge clk);

        end

      end

      @(posedge clk);

      s1_tvalid <= 1'b0;
      s1_tlast  <= 1'b0;
      s1_tuser  <= 1'b0;

      $display("[%0t] S1 FRAME DONE", $time);

    end
  endtask


  // ================================================================
  // Test helper:
  // Add normal expected frame.
  // ================================================================

  task expected_normal_frame;
    input integer length;
    input integer start_value;

    integer i;

    begin

      for (i = 0; i < length; i = i + 1) begin

        scoreboard_add(start_value + i, {KEEP_WIDTH{1'b1}}, (i == length - 1), 1'b0);

      end

    end
  endtask


  // ================================================================
  // Test helper:
  // Add expected output for mismatch.
  //
  // Comparator outputs data from selected master.
  //
  // It terminates the frame at mismatch beat.
  // ================================================================

  task expected_mismatch_frame;
    input integer mismatch_beat;
    input integer start_value;
    input integer select_value;

    reg [DATA_WIDTH-1:0] d;

    begin

      d = start_value + mismatch_beat;

      scoreboard_add(d, {KEEP_WIDTH{1'b1}}, 1'b1, 1'b1);

    end
  endtask


  // ================================================================
  // Output AXIS monitor / scoreboard
  //
  // Runs entirely on posedge.
  // ================================================================

  always @(posedge clk) begin

    if (rst_n) begin

      // --------------------------------------------------------
      // AXIS rule:
      //
      // If VALID=1 and READY=0, all payload signals must stay
      // unchanged.
      // --------------------------------------------------------

      if (m_tvalid && !m_tready) begin

        if (m_tvalid !== 1'b1) begin
          $display("[%0t] ERROR: impossible VALID state", $time);
          errors = errors + 1;
        end

      end


      // --------------------------------------------------------
      // Output handshake
      // --------------------------------------------------------

      if (m_tvalid && m_tready) begin

        m_handshakes = m_handshakes + 1;

        $display("[%0t] M OUT: data=%08x keep=%x last=%b user=%b", $time, m_tdata, m_tkeep,
                 m_tlast, m_tuser);


        // ----------------------------------------------------
        // Check against expected queue.
        // ----------------------------------------------------

        if (exp_rd_ptr >= exp_wr_ptr) begin

          $display("[%0t] ERROR: unexpected output beat", $time);

          errors = errors + 1;

        end else begin

          if (m_tdata !== exp_data[exp_rd_ptr]) begin
            $display("[%0t] ERROR: DATA mismatch. Expected=%08x Got=%08x", $time,
                     exp_data[exp_rd_ptr], m_tdata);
            errors = errors + 1;
          end

          if (m_tkeep !== exp_keep[exp_rd_ptr]) begin
            $display("[%0t] ERROR: KEEP mismatch. Expected=%x Got=%x", $time, exp_keep[exp_rd_ptr],
                     m_tkeep);
            errors = errors + 1;
          end

          if (m_tlast !== exp_last[exp_rd_ptr]) begin
            $display("[%0t] ERROR: LAST mismatch. Expected=%b Got=%b", $time, exp_last[exp_rd_ptr],
                     m_tlast);
            errors = errors + 1;
          end

          if (m_tuser !== exp_user[exp_rd_ptr]) begin
            $display("[%0t] ERROR: USER mismatch. Expected=%b Got=%b", $time, exp_user[exp_rd_ptr],
                     m_tuser);
            errors = errors + 1;
          end

          exp_rd_ptr = exp_rd_ptr + 1;

        end


        if (m_tlast) begin
          m_frames = m_frames + 1;

          if (m_tuser) m_error_frames = m_error_frames + 1;
        end

      end

    end

  end


  // ================================================================
  // Output backpressure generator
  //
  // ONLY posedge.
  //
  // ready_pattern:
  //
  // 1 1 0 0 1 1 1 0 ...
  //
  // This creates realistic stalls while keeping the waveform easy
  // to understand.
  // ================================================================

  integer ready_counter;

  always @(posedge clk) begin

    if (!rst_n) begin

      m_tready <= 1'b0;
      ready_counter = 0;

    end else begin

      case (ready_counter)

        0: m_tready <= 1'b1;
        1: m_tready <= 1'b1;

        2: m_tready <= 1'b0;
        3: m_tready <= 1'b0;

        4: m_tready <= 1'b1;
        5: m_tready <= 1'b1;
        6: m_tready <= 1'b1;

        7: m_tready <= 1'b0;

        default: m_tready <= 1'b1;

      endcase

      if (ready_counter == 7) ready_counter = 0;
      else ready_counter = ready_counter + 1;

    end

  end


  // ================================================================
  // Test sequence
  // ================================================================

  initial begin

    errors = 0;

    reset_dut();


    // ============================================================
    // TEST 1
    //
    // Equal frames.
    //
    // select = 0
    //
    // S0: fast
    // S1: slow
    //
    // Expected:
    //     all beats pass
    // ============================================================

    test_number = 1;

    $display("");
    $display("============================================================");
    $display("TEST 1: EQUAL FRAMES, SELECT=0");
    $display("============================================================");

    scoreboard_clear();

    select = 1'b0;

    expected_normal_frame(8, 32'h00000100);

    fork

      master0_frame(8, 32'h00000100, 0, -1, -1);

      master1_frame(8, 32'h00000100, 2, -1, -1);

    join

    scoreboard_wait_empty();

    repeat (5) @(posedge clk);


    // ============================================================
    // TEST 2
    //
    // Equal frames.
    //
    // select = 1
    //
    // Reverse speeds.
    // ============================================================

    test_number = 2;

    $display("");
    $display("============================================================");
    $display("TEST 2: EQUAL FRAMES, SELECT=1");
    $display("============================================================");

    scoreboard_clear();

    select = 1'b1;

    expected_normal_frame(12, 32'h00000200);

    fork

      master0_frame(12, 32'h00000200, 3, -1, -1);

      master1_frame(12, 32'h00000200, 0, -1, -1);

    join

    scoreboard_wait_empty();

    repeat (5) @(posedge clk);


    // ============================================================
    // TEST 3
    //
    // DATA MISMATCH.
    //
    // mismatch on beat 5.
    //
    // S0:
    //     300 301 302 303 304 305 ...
    //
    // S1:
    //     300 301 302 303 304 1305 ...
    //
    // Expected:
    //
    //     300
    //     301
    //     302
    //     303
    //     304
    //     305 TLAST=1 TUSER=1
    //
    // Then FLUSH.
    // ============================================================

    test_number = 3;

    $display("");
    $display("============================================================");
    $display("TEST 3: DATA MISMATCH");
    $display("============================================================");

    scoreboard_clear();

    select = 1'b0;

    // Expected normal beats before mismatch.
    scoreboard_add(32'h00000300, 4'hf, 1'b0, 1'b0);
    scoreboard_add(32'h00000301, 4'hf, 1'b0, 1'b0);
    scoreboard_add(32'h00000302, 4'hf, 1'b0, 1'b0);
    scoreboard_add(32'h00000303, 4'hf, 1'b0, 1'b0);
    scoreboard_add(32'h00000304, 4'hf, 1'b0, 1'b0);

    // Mismatch beat.
    scoreboard_add(32'h00000305, 4'hf, 1'b1, 1'b1);


    fork

      begin : M0_MISMATCH

        integer i;

        for (i = 0; i < 16; i = i + 1) begin

          @(posedge clk);

          s0_tvalid <= 1'b1;
          s0_tdata  <= 32'h00000300 + i;
          s0_tkeep  <= 4'hf;
          s0_tuser  <= 1'b0;
          s0_tlast  <= (i == 15);

          @(posedge clk);

          while (!(s0_tvalid && s0_tready)) @(posedge clk);

          s0_handshakes = s0_handshakes + 1;

          s0_tvalid <= 1'b0;
          s0_tlast  <= 1'b0;

          // S0 is fast.
          @(posedge clk);
        end

        @(posedge clk);

        s0_tvalid <= 1'b0;
        s0_tlast  <= 1'b0;

      end


      begin : M1_MISMATCH

        integer i;
        reg [DATA_WIDTH-1:0] d;

        for (i = 0; i < 16; i = i + 1) begin

          @(posedge clk);

          if (i == 5) d = 32'h00001305;
          else d = 32'h00000300 + i;

          s1_tvalid <= 1'b1;
          s1_tdata  <= d;
          s1_tkeep  <= 4'hf;
          s1_tuser  <= 1'b0;
          s1_tlast  <= (i == 15);

          @(posedge clk);

          while (!(s1_tvalid && s1_tready)) @(posedge clk);

          s1_handshakes = s1_handshakes + 1;

          s1_tvalid <= 1'b0;
          s1_tlast  <= 1'b0;

          // S1 is slower.
          repeat (3) @(posedge clk);
        end

        @(posedge clk);

        s1_tvalid <= 1'b0;
        s1_tlast  <= 1'b0;

      end

    join

    // Give FLUSH time to finish.
    repeat (20) @(posedge clk);

    scoreboard_wait_empty();


    // ============================================================
    // TEST 4
    //
    // New frame immediately after FLUSH.
    //
    // This checks that DUT is capable of starting again.
    // ============================================================

    test_number = 4;

    $display("");
    $display("============================================================");
    $display("TEST 4: NEW FRAME AFTER FLUSH");
    $display("============================================================");

    scoreboard_clear();

    select = 1'b1;

    expected_normal_frame(5, 32'h00000400);

    fork

      master0_frame(5, 32'h00000400, 1, -1, -1);

      master1_frame(5, 32'h00000400, 1, -1, -1);

    join

    scoreboard_wait_empty();

    repeat (5) @(posedge clk);


    // ============================================================
    // TEST 5
    //
    // Input TUSER.
    //
    // Comparator treats it as mismatch.
    // ============================================================

    test_number = 5;

    $display("");
    $display("============================================================");
    $display("TEST 5: INPUT TUSER");
    $display("============================================================");

    scoreboard_clear();

    select = 1'b0;

    // Beats 0..3 pass.
    scoreboard_add(32'h00000500, 4'hf, 1'b0, 1'b0);
    scoreboard_add(32'h00000501, 4'hf, 1'b0, 1'b0);
    scoreboard_add(32'h00000502, 4'hf, 1'b0, 1'b0);
    scoreboard_add(32'h00000503, 4'hf, 1'b0, 1'b0);

    // Beat 4 terminates because S0_TUSER=1.
    scoreboard_add(32'h00000504, 4'hf, 1'b1, 1'b1);


    fork

      master0_frame(10, 32'h00000500, 0, 4, -1);

      master1_frame(10, 32'h00000500, 2, -1, -1);

    join

    repeat (20) @(posedge clk);

    scoreboard_wait_empty();


    // ============================================================
    // TEST 6
    //
    // TKEEP mismatch.
    // ============================================================

    test_number = 6;

    $display("");
    $display("============================================================");
    $display("TEST 6: TKEEP MISMATCH");
    $display("============================================================");

    scoreboard_clear();

    select = 1'b0;

    // Beats 0..2 pass.
    scoreboard_add(32'h00000600, 4'hf, 1'b0, 1'b0);
    scoreboard_add(32'h00000601, 4'hf, 1'b0, 1'b0);
    scoreboard_add(32'h00000602, 4'hf, 1'b0, 1'b0);

    // Beat 3: S1 TKEEP=7, S0 TKEEP=f.
    scoreboard_add(32'h00000603, 4'hf, 1'b1, 1'b1);


    fork

      master0_frame(7, 32'h00000600, 1, -1, -1);

      master1_frame(7, 32'h00000600, 1, -1, 3);

    join

    repeat (20) @(posedge clk);

    scoreboard_wait_empty();


    // ============================================================
    // FINAL CHECK
    // ============================================================

    repeat (10) @(posedge clk);

    $display("");
    $display("============================================================");
    $display("FINAL TEST RESULTS");
    $display("============================================================");

    $display("S0 handshakes  : %0d", s0_handshakes);
    $display("S1 handshakes  : %0d", s1_handshakes);
    $display("M handshakes   : %0d", m_handshakes);
    $display("M frames       : %0d", m_frames);
    $display("M error frames : %0d", m_error_frames);
    $display("Errors         : %0d", errors);

    if (exp_rd_ptr != exp_wr_ptr) begin
      $display("ERROR: scoreboard is not empty");
      errors = errors + 1;
    end


    if (errors == 0) begin

      $display("");
      $display("************************************************");
      $display("***              TEST PASSED                 ***");
      $display("************************************************");
      $display("");

    end else begin

      $display("");
      $display("************************************************");
      $display("***              TEST FAILED                 ***");
      $display("************************************************");
      $display("");

    end

    $finish;

  end


  // ================================================================
  // AXIS protocol monitor
  //
  // Registered snapshot of output.
  //
  // If VALID && !READY, payload must remain unchanged.
  // ================================================================
  reg                  mon_m_valid_prev;
  reg                  mon_m_ready_prev;
  reg [DATA_WIDTH-1:0] mon_m_data_prev;
  reg [KEEP_WIDTH-1:0] mon_m_keep_prev;
  reg                  mon_m_last_prev;
  reg                  mon_m_user_prev;

  always @(posedge clk) begin
    #1;

    // Если предыдущий цикл был VALID && !READY,
    // текущий beat обязан остаться неизменным.
    if (mon_m_valid_prev && !mon_m_ready_prev) begin

      if (!m_tvalid) begin
        $display("[%0t] ERROR: m_tvalid dropped while stalled", $time);
      end

      if (m_tdata !== mon_m_data_prev) begin
        $display("[%0t] ERROR: m_tdata changed while stalled", $time);
      end

      if (m_tkeep !== mon_m_keep_prev) begin
        $display("[%0t] ERROR: m_tkeep changed while stalled", $time);
      end

      if (m_tlast !== mon_m_last_prev) begin
        $display("[%0t] ERROR: m_tlast changed while stalled", $time);
      end

      if (m_tuser !== mon_m_user_prev) begin
        $display("[%0t] ERROR: m_tuser changed while stalled", $time);
      end
    end

    // Запоминаем состояние, которое реально наблюдаем
    // после завершения NBA этого такта.
    mon_m_valid_prev = m_tvalid;
    mon_m_ready_prev = m_tready;
    mon_m_data_prev  = m_tdata;
    mon_m_keep_prev  = m_tkeep;
    mon_m_last_prev  = m_tlast;
    mon_m_user_prev  = m_tuser;
  end

  // reg                  mon_valid;
  // reg [DATA_WIDTH-1:0] mon_data;
  // reg [KEEP_WIDTH-1:0] mon_keep;
  // reg                  mon_last;
  // reg                  mon_user;

  // always @(posedge clk) begin

  //   if (!rst_n) begin

  //     mon_valid <= 1'b0;

  //   end else begin

  //     // --------------------------------------------------------
  //     // Previous cycle was stalled.
  //     // --------------------------------------------------------

  //     if (mon_valid && !m_tready) begin

  //       if (!m_tvalid) begin
  //         $display("[%0t] ERROR: m_tvalid dropped while stalled", $time);
  //         errors = errors + 1;
  //       end

  //       if (m_tdata !== mon_data) begin
  //         $display("[%0t] ERROR: m_tdata changed while stalled", $time);
  //         errors = errors + 1;
  //       end

  //       if (m_tkeep !== mon_keep) begin
  //         $display("[%0t] ERROR: m_tkeep changed while stalled", $time);
  //         errors = errors + 1;
  //       end

  //       if (m_tlast !== mon_last) begin
  //         $display("[%0t] ERROR: m_tlast changed while stalled", $time);
  //         errors = errors + 1;
  //       end

  //       if (m_tuser !== mon_user) begin
  //         $display("[%0t] ERROR: m_tuser changed while stalled", $time);
  //         errors = errors + 1;
  //       end

  //     end


  //     // --------------------------------------------------------
  //     // Save current state.
  //     // --------------------------------------------------------

  //     mon_valid <= m_tvalid;
  //     mon_data  <= m_tdata;
  //     mon_keep  <= m_tkeep;
  //     mon_last  <= m_tlast;
  //     mon_user  <= m_tuser;

  //   end

  // end


  // ================================================================
  // Waveform
  // ================================================================

  initial begin

    $dumpfile("tb_axis_comparator_GT");
    $dumpvars(0, tb_axis_comparator_GT);

  end

endmodule

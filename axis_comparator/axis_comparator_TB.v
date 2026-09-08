`timescale 1 ns / 1 ps

module axis_comparator_TB ();

  parameter SIM_MAX_TIME = 150000;  //To quit the simulation
  // parameter   clk1_period = 10000 ; // 100 MHz
  // parameter   clk2_period = 6400 ; // 156.25 MHz
  parameter clk1_period = 10;  // 100 MHz



  reg     clk1;
  // reg     clk2;
  reg     reset;

  integer cycle_count = 0;


  initial begin
    reset = 1'b1;
    #19 @(negedge clk1) reset = 1'b0;
  end

  initial begin
    clk1 = 1'b0;
    forever #(clk1_period / 2) clk1 = !clk1;
  end


  initial begin
    $dumpfile("axis_comparator_TB.vcd");
    $dumpvars(0, axis_comparator_TB);
  end

  // 3. Блок для подсчета тактов
  always @(posedge clk1) begin
    cycle_count = cycle_count + 1;
  end

  // 4. Основной блок тестирования
  initial begin
    $display("Simulation start.");

    // Ждем N тактов. Например, 100.
    wait (cycle_count == 200);

    $display("Simulation stopped after %0d cycle_counts.", cycle_count);
    $finish;  // Останавливаем симуляцию
  end



  wire [31:0] m_axi_tdata1;
  wire [31:0] s1_axis_tdata_tb = m_axi_tdata1;
  wire        m_axi_tvalid1;
  wire        m_axi_tlast1;
  wire        m_axi_tready1;
  wire [ 3:0] m_axi_tkeep1;
  //   wire        axi_err_out1;

  wire s0_axis_tready, s1_axis_tready;

  wire [31:0] m_axi_tdata2;
  wire        m_axi_tvalid2;
  wire        m_axi_tlast2;
  wire        m_axi_tready2;
  wire [ 3:0] m_axi_tkeep2;

  wire [31:0] m_axi_tdata3;
  wire        m_axi_tvalid3;
  wire        m_axi_tlast3;
  wire        m_axi_tready3;
  wire [ 3:0] m_axi_tkeep3;

  //   wire        axi_err_out2;


  //   wire [15:0] av_data1;
  //   wire        av_valid1;
  //   wire        av_sop1;
  //   wire        av_eop1;
  //   wire        av_ready1;
  //   wire        av_err_out1;

  //   wire [15:0] av_data1_from_axi;
  //   wire        av_valid1_from_axi;
  //   wire        av_sop1_from_axi;
  //   wire        av_eop1_from_axi;
  //   wire        av_ready1_to_axi;

  //   wire [15:0] av_data2;
  //   wire        av_valid2;
  //   wire        av_sop2;
  //   wire        av_eop2;
  //   wire        av_ready2;
  //   wire        av_err_out2;

  //   wire [15:0] av_data2_from_axi;
  //   wire        av_valid2_from_axi;
  //   wire        av_sop2_from_axi;
  //   wire        av_eop2_from_axi;
  //   wire        av_ready2_to_axi;



  AXIS_rnd_master_32bit AXIS_rnd_master_32bit (
      .clk(clk1),
      .reset(reset),
      .lane_up(1'b1),
      .channel_up(1'b1),
      .enable(1'b1),
      .m_axis_tready(s0_axis_tready  /*m_axi_tready1*/),
      .m_axis_tdata(m_axi_tdata1),
      .m_axis_tvalid(m_axi_tvalid1),
      .m_axis_tlast(m_axi_tlast1),
      .m_axis_tkeep(m_axi_tkeep1)
  );

  initial begin
    #105ns;
    // force AXIS_comparator_my.s1_axis_tdata = m_axi_tdata1 + 1'b1;
    force s1_axis_tdata_tb = 32'hDEADBEEF;

    #clk1_period;
    release s1_axis_tdata_tb;
  end



  AXIS_comparator AXIS_comparator_my (
      .clk(clk1),
      .reset(reset),
      .select_in(1'b0),
      .s0_axis_tready(s0_axis_tready),
      .s0_axis_tdata(m_axi_tdata1),
      .s0_axis_tvalid(m_axi_tvalid1),
      .s0_axis_tlast(m_axi_tlast1),
      .s0_axis_tkeep(m_axi_tkeep1),
      .s0_axis_tuser(1'b0),
      .s1_axis_tready(s1_axis_tready),
      .s1_axis_tdata(s1_axis_tdata_tb  /*m_axi_tdata1*/),
      .s1_axis_tvalid(m_axi_tvalid1),
      .s1_axis_tlast(m_axi_tlast1),
      .s1_axis_tkeep(m_axi_tkeep1),
      .s1_axis_tuser(1'b0),
      .m_axis_tready(1'b1),
      .m_axis_tdata(m_axi_tdata2),
      .m_axis_tvalid(m_axi_tvalid2),
      .m_axis_tlast(m_axi_tlast2),
      .m_axis_tkeep(m_axi_tkeep2)
  );

  wire s0_tready, s1_tready;
  axis_comparator axis_comparator (
      .clk(clk1),
      .rst_n(!reset),
      .select(1'b0),
      .s0_tready(s0_tready),
      .s0_tdata(m_axi_tdata1),
      .s0_tvalid(m_axi_tvalid1),
      .s0_tlast(m_axi_tlast1),
      .s0_tkeep(m_axi_tkeep1),
      .s1_tready(s1_tready),
      .s1_tdata(s1_axis_tdata_tb  /*m_axi_tdata1*/),
      .s1_tvalid(m_axi_tvalid1),
      .s1_tlast(m_axi_tlast1),
      .s1_tkeep(m_axi_tkeep1),
      .m_tready(1'b1),
      .m_tdata(m_axi_tdata3),
      .m_tvalid(m_axi_tvalid3),
      .m_tlast(m_axi_tlast3),
      .m_tkeep(m_axi_tkeep3)
  );



endmodule

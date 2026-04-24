`timescale 1 ps / 1 ps

module async_FIFO_TB(

);
parameter   SIM_MAX_TIME  = 150000000; //To quit the simulation
// parameter   clk1_period = 10000 ; // 100 MHz
// parameter   clk2_period = 6400 ; // 156.25 MHz
parameter   clk1_period = 6400; // 100 MHz
parameter   clk2_period = 10000; // 156.25 MHz


reg     clk1;
reg     clk2;
reg     reset;



initial begin
	reset = 1'b1;
#19000 @(negedge clk1)
	reset = 1'b0;
end

initial begin
  clk1   = 1'b0;
  forever #(clk1_period / 2) clk1 = !clk1;
end

initial begin
  clk2   = 1'b0;
  forever #(clk2_period / 2) clk2 = !clk2;
end


wire [15:0] FIFO1_wr_data;
wire        FIFO1_wr_en;
wire        FIFO1_wr_full;
wire        FIFO1_wr_afull;
wire [4:0]  FIFO1_wr_used;
wire        FIFO1_rd_en;
wire        FIFO1_rd_empty;
wire        FIFO1_rd_aempty;
wire [15:0] FIFO1_rd_data;
wire [4:0]  FIFO1_rd_used;

wire [15:0] FIFO2_wr_data;
wire        FIFO2_wr_en;
wire        FIFO2_wr_full;
wire        FIFO2_wr_afull;
wire [4:0]  FIFO2_wr_used;
wire        FIFO2_rd_en;
wire        FIFO2_rd_empty;
wire        FIFO2_rd_aempty;
wire [15:0] FIFO2_rd_data;
wire [4:0]  FIFO2_rd_used;

wire [15:0] FIFO3_wr_data;
wire        FIFO3_wr_en;
wire        FIFO3_wr_full;
wire        FIFO3_wr_afull;
wire [4:0]  FIFO3_wr_used;
wire        FIFO3_rd_en;
wire        FIFO3_rd_empty;
wire        FIFO3_rd_aempty;
wire [15:0] FIFO3_rd_data;
wire [4:0]  FIFO3_rd_used;

wire [15:0] FIFO4_wr_data;
wire        FIFO4_wr_en;
wire        FIFO4_wr_full;
wire        FIFO4_wr_afull;
wire [4:0]  FIFO4_wr_used;
wire        FIFO4_rd_en;
wire        FIFO4_rd_empty;
wire        FIFO4_rd_aempty;
wire [15:0] FIFO4_rd_data;
wire [4:0]  FIFO4_rd_used;

// Simple_FIFO_wr        Simple_FIFO_wr1    (
//         // AXI TX Interface
//   .clk                (clk1),
//   .reset              (reset),
//   // .wr_full            (FIFO1_wr_full),
//   // .wr_almost_full     (FIFO1_wr_afull),
//   .m_axis_tready      (!FIFO1_wr_afull),
//   .wr_data            (FIFO1_wr_data),
//   .m_axi_tvalid       (),
//   .wr_en              (FIFO1_wr_en)  

//   );

// afifo_used_zipCPU     afifo_used_zipCPU    (
//         // AXI TX Interface
//   .i_wclk           (clk1),
//   .i_wr_reset_n     (!reset),
//   .i_wr             (FIFO1_wr_en),
//   .i_wr_data        (FIFO1_wr_data),
//   .o_wr_full        (FIFO1_wr_full),
//   .i_rclk           (clk2),
//   .i_rd_reset_n     (!reset),
//   .i_rd             (FIFO1_rd_en),
//   .o_rd_data        (FIFO1_rd_data),
//   .o_rd_empty       (FIFO1_rd_empty),
//   .wr_used          (FIFO1_wr_used),
//   .rd_used          (FIFO1_rd_used),
//   .almost_full      (FIFO1_wr_afull),
//   .almost_empty     (FIFO1_rd_aempty)

//   );

// Simple_FIFO_rd        Simple_FIFO_rd1    (

//   .m_axis_tready      (1'b0),
//   .m_axis_tdata       (),
//   .m_axi_tvalid       (),
//   .rd_en              (FIFO1_rd_en),
//   .rd_empty           (FIFO1_rd_empty),
//   .rd_data            (FIFO1_rd_data)

//   );

// Simple_FIFO_wr        Simple_FIFO_wr2    (
//         // AXI TX Interface
//   .clk                (clk1),
//   .reset              (reset),
//   // .wr_full            (FIFO2_wr_full),
//   // .wr_almost_full     (FIFO2_wr_afull),
//   .m_axis_tready      (!FIFO2_wr_afull),
//   .wr_data            (FIFO2_wr_data),
//   .m_axi_tvalid       (),
//   .wr_en              (FIFO2_wr_en)  

//   );

// afifo_used_zipCPU_fixed     afifo_used_zipCPU_fixed    (
//         // AXI TX Interface
//   .i_wclk           (clk1),
//   .i_wr_reset_n     (!reset),
//   .i_wr             (FIFO2_wr_en),
//   .i_wr_data        (FIFO2_wr_data),
//   .o_wr_full        (FIFO2_wr_full),
//   .i_rclk           (clk2),
//   .i_rd_reset_n     (!reset),
//   .i_rd             (FIFO2_rd_en),
//   .o_rd_data        (FIFO2_rd_data),
//   .o_rd_empty       (FIFO2_rd_empty),
//   .wr_used          (FIFO2_wr_used),
//   .rd_used          (FIFO2_rd_used),
//   .almost_full      (FIFO2_wr_afull),
//   .almost_empty     (FIFO2_rd_aempty)

//   );


// Simple_FIFO_rd        Simple_FIFO_rd2    (

//   .m_axis_tready      (1'b0),
//   .m_axis_tdata       (),
//   .m_axi_tvalid       (),
//   .rd_en              (FIFO2_rd_en),
//   .rd_empty           (FIFO2_rd_empty),
//   .rd_data            (FIFO2_rd_data)

//   );

Simple_FIFO_wr        Simple_FIFO_wr3    (
  .clk                (clk1),
  .reset              (reset),
  .m_axis_tready      (!FIFO3_wr_full),
  .wr_data            (FIFO3_wr_data),
  .m_axi_tvalid       (),
  .wr_en              (FIFO3_wr_en)  

  );

async_fifo_fwft_reg_sat     async_fifo_fwft_reg_sat    (
  .wr_clk           (clk1),
  .wr_rst           (reset),
  .wr_en            (FIFO3_wr_en),
  .wr_data          (FIFO3_wr_data),
  .wr_full          (FIFO3_wr_full),
  .rd_clk           (clk2),
  .rd_rst           (reset),
  .rd_en            (/*1'b0*/FIFO3_rd_en),
  .rd_data          (FIFO3_rd_data),
  .rd_empty         (FIFO3_rd_empty),
  .wr_cnt           (FIFO3_wr_used),
  .rd_cnt           (FIFO3_rd_used),
  .wr_almost_full   (FIFO3_wr_afull),
  .rd_almost_empty  (FIFO3_rd_aempty)

  );

wire axis_master_from_fwft_fifo_tvalid0;
wire axis_master_from_fwft_fifo_tready0;

// simple_FIFO_rd_axis_master_2skidbufs        simple_FIFO_rd_axis_master_2skidbufs    (
  
//   .clk                (clk2),
//   .reset              (reset),
//   .m_axis_tready      (axis_master_from_fwft_fifo_tready0),
//   .m_axis_tdata       (),
//   .m_axis_tvalid      (axis_master_from_fwft_fifo_tvalid0),
//   .fifo_rd_en         (FIFO3_rd_en),
//   .fifo_empty         (FIFO3_rd_empty/*FIFO3_rd_aempty*/),
//   .fifo_data          (FIFO3_rd_data)

//   );

axis_master_from_fwft_fifo_tlast    simple_FIFO_rd_axis_master_2skidbufs    (

  .clk                (clk2),
  .rst                (reset),
  .m_axis_tready      (axis_master_from_fwft_fifo_tready0),
  .m_axis_tdata       (),
  .m_axis_tvalid      (axis_master_from_fwft_fifo_tvalid0),
  .m_axis_tlast       (),
  // .m_axis_tlast       (),
  .fifo_rd_en         (FIFO3_rd_en),
  .fifo_empty         (FIFO3_rd_empty),
  .fifo_data          (FIFO3_rd_data)

  );

Simple_tready_gen     Simple_tready_gen3 (

  .clk                (clk2),
  .reset              (reset),
  .tvalid             (axis_master_from_fwft_fifo_tvalid0),
  .tready             (axis_master_from_fwft_fifo_tready0)

  );

Simple_FIFO_wr        Simple_FIFO_wr4    (
  .clk                (clk1),
  .reset              (reset),
  // .m_axis_tready      (!FIFO4_wr_afull),
  .m_axis_tready      (!FIFO4_wr_full),
  .wr_data            (FIFO4_wr_data),
  .m_axi_tvalid       (),
  .wr_en              (FIFO4_wr_en)  

  );

async_fifo_fwft_reg_sat     async_fifo_fwft_reg_sat_1    (

  .wr_clk           (clk1),
  .wr_rst           (reset),
  .wr_en            (FIFO4_wr_en),
  .wr_data          (FIFO4_wr_data),
  .wr_full          (FIFO4_wr_full),
  .rd_clk           (clk2),
  .rd_rst           (reset),
  .rd_en            (FIFO4_rd_en),
  .rd_data          (FIFO4_rd_data),
  .rd_empty         (FIFO4_rd_empty),
  .wr_cnt           (FIFO4_wr_used),
  .rd_cnt           (FIFO4_rd_used),
  .wr_almost_full   (FIFO4_wr_afull),
  .rd_almost_empty  (FIFO4_rd_aempty)

  );


wire axis_master_from_fwft_fifo_tvalid1;
wire axis_master_from_fwft_fifo_tready1;

axis_master_from_fwft_fifo        Simple_FIFO_rd4    (

  .clk                (clk2),
  .rst                (reset),
  .m_axis_tready      (/*1'b1*/axis_master_from_fwft_fifo_tready1),
  .m_axis_tdata       (),
  .m_axis_tvalid      (axis_master_from_fwft_fifo_tvalid1),
  // .m_axis_tlast       (),
  .fifo_rd_en         (FIFO4_rd_en),
  .fifo_empty         (FIFO4_rd_empty),
  .fifo_data          (FIFO4_rd_data)

  );

Simple_tready_gen     Simple_tready_gen4 (

  .clk                (clk2),
  .reset              (reset),
  .tvalid             (axis_master_from_fwft_fifo_tvalid1),
  .tready             (axis_master_from_fwft_fifo_tready1)

  );


// ------------------------------------------------------
//      SYNC FIFO TEST BELOW:
// ------------------------------------------------------

// Simple_FIFO_wr        Simple_FIFO_wr1    (
//   .clk                (clk1),
//   .reset              (reset),
//   .m_axis_tready      (!FIFO1_wr_full),
//   .wr_data            (FIFO1_wr_data),
//   .m_axi_tvalid       (),
//   .wr_en              (FIFO1_wr_en)  

//   );

wire FIFO1_wr_done;
wire FIFO1_rd_done;

simple_FIFO_wr_check        Simple_FIFO_wr_chk1    (
  .clk                (clk1),
  .reset              (reset),
  .fifo_wr_data       (FIFO1_wr_data),
  .fifo_wr_en         (FIFO1_wr_en),
  .fifo_wr_done       (FIFO1_wr_done)

  );

sync_fifo_fwft_reg_pow2     sync_fifo_fwft_reg_pow2    (

  .clk              (clk1),
  .rst              (reset),
  .wr_en            (FIFO1_wr_en),
  .wr_data          (FIFO1_wr_data),
  .wr_full          (FIFO1_wr_full),
  .wr_almost_full   (FIFO1_wr_afull),
  .rd_en            (/*1'b0*/FIFO1_rd_en),
  .rd_data          (FIFO1_rd_data),
  .rd_empty         (FIFO1_rd_empty),
  .rd_almost_empty  (FIFO1_rd_aempty),

  .usedw            (FIFO1_wr_used)

  );

simple_FIFO_rd_check        Simple_FIFO_rd_chk1    (
  .clk                (clk1),
  .reset              (reset),
  .fifo_rd_en         (FIFO1_rd_en),
  .fifo_wr_done       (FIFO1_wr_done),
  .fifo_rd_done       (FIFO1_rd_done)

  );

wire FIFO2_wr_done;
wire FIFO2_rd_done;

simple_FIFO_wr_check        Simple_FIFO_wr_chk2    (
  .clk                (clk1),
  .reset              (reset),
  .fifo_wr_data       (FIFO2_wr_data),
  .fifo_wr_en         (FIFO2_wr_en),
  .fifo_wr_done       (FIFO2_wr_done)

  );

async_fifo_fwft_reg_gem     async_fifo_fwft_reg_gem    (

  .wr_clk           (clk1),
  .wr_rst           (reset),
  .wr_en            (FIFO2_wr_en),
  .wr_data          (FIFO2_wr_data),
  .wr_full          (FIFO2_wr_full),
  .rd_clk           (clk2),
  .rd_rst           (reset),
  .rd_en            (FIFO2_rd_en),
  .rd_data          (FIFO2_rd_data),
  .rd_empty         (FIFO2_rd_empty),
  .wr_cnt           (FIFO2_wr_used),
  .rd_cnt           (FIFO2_rd_used),
  .wr_almost_full   (FIFO2_wr_afull),
  .rd_almost_empty  (FIFO2_rd_aempty)

  );

simple_FIFO_rd_check        Simple_FIFO_rd_chk2    (
  .clk                (clk2),
  .reset              (reset),
  .fifo_rd_en         (FIFO2_rd_en),
  .fifo_wr_done       (FIFO2_wr_done),
  .fifo_rd_done       (FIFO2_rd_done)

  );

// wire axis_master_from_fwft_fifo_tvalid2;
// wire axis_master_from_fwft_fifo_tready2;

// axis_master_from_fwft_fifo        Simple_FIFO_rd1    (

//   .clk                (clk1),
//   .rst                (reset),
//   .m_axis_tready      (/*1'b0*/axis_master_from_fwft_fifo_tready2),
//   .m_axis_tdata       (),
//   .m_axis_tvalid      (axis_master_from_fwft_fifo_tvalid2),
//   // .m_axis_tlast       (),
//   .fifo_rd_en         (FIFO1_rd_en),
//   .fifo_empty         (FIFO1_rd_empty),
//   .fifo_data          (FIFO1_rd_data)

//   );

// Simple_tready_gen     Simple_tready_gen1 (

//   .clk                (clk1),
//   .reset              (reset),
//   .tvalid             (axis_master_from_fwft_fifo_tvalid2),
//   .tready             (axis_master_from_fwft_fifo_tready2)

//   );

endmodule

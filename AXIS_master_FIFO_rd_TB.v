`timescale 1 ps / 1 ps

module AXIS_master_FIFO_rd_TB (
  
);

parameter   SIM_MAX_TIME  = 150000000; //To quit the simulation
// parameter   clk1_period = 10000 ; // 100 MHz
// parameter   clk2_period = 6400 ; // 156.25 MHz
parameter   clk1_period = 6400; // 100 MHz
parameter   clk2_period = 10000; // 156.25 MHz
parameter [7:0] N  = 6;
parameter tready_toggle_enable = 1;


reg     clk1;
reg     clk2;
reg     reset;

integer cycle_count = 0;


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

initial begin
	$dumpfile("AXIS_master_FIFO_rd_TB.vcd");
	$dumpvars(0,AXIS_master_FIFO_rd_TB);
end

// 3. Блок для подсчета тактов
always @(posedge clk1) begin
    cycle_count = cycle_count + 1;
end

// 4. Основной блок тестирования
initial begin
    $display("Simulation start.");

    // Ждем N тактов. Например, 100.
    wait (cycle_count == 100);

    $display("Simulation stopped after %0d cycle_counts.", cycle_count);
    $finish; // Останавливаем симуляцию
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

wire        FIFO2_rd_en;
wire        FIFO2_rd_empty;
// wire        FIFO2_rd_aempty;
wire [15:0] FIFO2_rd_data;
// wire [4:0]  FIFO2_rd_used;

wire        FIFO3_rd_en;
wire        FIFO3_rd_empty;
// wire        FIFO3_rd_aempty;
wire [15:0] FIFO3_rd_data;
// wire [4:0]  FIFO3_rd_used;

wire        FIFO4_rd_en;
wire        FIFO4_rd_empty;
// wire        FIFO4_rd_aempty;
wire [15:0] FIFO4_rd_data;
// wire [4:0]  FIFO4_rd_used;


wire FIFO2_wr_done;
wire FIFO2_rd_done;

simple_FIFO_wr_check        Simple_FIFO_wr_chk    (
  .clk                (clk1),
  .reset              (reset),
  .fifo_wr_data       (FIFO1_wr_data),
  .fifo_wr_en         (FIFO1_wr_en),
  .fifo_wr_done       (FIFO1_wr_done)

  );



async_fifo_fwft_reg_gem     FIFO1_reg_gem    (

  .wr_clk           (clk1),
  .wr_rst           (reset),
  .wr_en            (FIFO1_wr_en),
  .wr_data          (FIFO1_wr_data),
  .wr_full          (FIFO1_wr_full),
  .rd_clk           (clk2),
  .rd_rst           (reset),
  .rd_en            (FIFO1_rd_en),
  .rd_data          (FIFO1_rd_data),
  .rd_empty         (FIFO1_rd_empty),
  .wr_cnt           (FIFO1_wr_used),
  .rd_cnt           (FIFO1_rd_used),
  .wr_almost_full   (FIFO1_wr_afull),
  .rd_almost_empty  (FIFO1_rd_aempty)

  );

async_fifo_fwft_reg_gem     FIFO2_reg_gem    (

  .wr_clk           (clk1),
  .wr_rst           (reset),
  .wr_en            (FIFO1_wr_en),
  .wr_data          (FIFO1_wr_data),
  .wr_full          (/*FIFO1_wr_full*/),
  .rd_clk           (clk2),
  .rd_rst           (reset),
  .rd_en            (FIFO2_rd_en),
  .rd_data          (FIFO2_rd_data),
  .rd_empty         (FIFO2_rd_empty),
  .wr_cnt           (/*FIFO2_wr_used*/),
  .rd_cnt           (/*FIFO2_rd_used*/),
  .wr_almost_full   (/*FIFO2_wr_afull*/),
  .rd_almost_empty  (/*FIFO2_rd_aempty*/)

  );

  async_fifo_fwft_reg_gem     FIFO3_reg_gem    (

  .wr_clk           (clk1),
  .wr_rst           (reset),
  .wr_en            (FIFO1_wr_en),
  .wr_data          (FIFO1_wr_data),
  .wr_full          (/*FIFO1_wr_full*/),
  .rd_clk           (clk2),
  .rd_rst           (reset),
  .rd_en            (FIFO3_rd_en),
  .rd_data          (FIFO3_rd_data),
  .rd_empty         (FIFO3_rd_empty),
  .wr_cnt           (/*FIFO3_wr_used*/),
  .rd_cnt           (/*FIFO3_rd_used*/),
  .wr_almost_full   (/*FIFO3_wr_afull*/),
  .rd_almost_empty  (/*FIFO3_rd_aempty*/)

  );

  async_fifo_fwft_reg_gem     FIFO4_reg_gem    (

  .wr_clk           (clk1),
  .wr_rst           (reset),
  .wr_en            (FIFO1_wr_en),
  .wr_data          (FIFO1_wr_data),
  .wr_full          (/*FIFO1_wr_full*/),
  .rd_clk           (clk2),
  .rd_rst           (reset),
  .rd_en            (FIFO4_rd_en),
  .rd_data          (FIFO4_rd_data),
  .rd_empty         (FIFO4_rd_empty),
  .wr_cnt           (/*FIFO4_wr_used*/),
  .rd_cnt           (/*FIFO4_rd_used*/),
  .wr_almost_full   (/*FIFO4_wr_afull*/),
  .rd_almost_empty  (/*FIFO4_rd_aempty*/)

  );
// async_fifo_fwft_xilinx_style     FIFO4_reg_xilinx_style    (

//   .wr_clk           (clk1),
//   .wr_rst           (reset),
//   .wr_en            (FIFO2_wr_en),
//   .wr_data          (FIFO2_wr_data),
//   .wr_full          (FIFO4_wr_full),
//   .rd_clk           (clk2),
//   .rd_rst           (reset),
//   .rd_en            (FIFO2_rd_en),
//   .rd_data          (FIFO4_rd_data),
//   .rd_empty         (FIFO4_rd_empty),
//   .wr_cnt           (FIFO4_wr_used),
//   .rd_cnt           (FIFO4_rd_used),
//   .wr_almost_full   (FIFO4_wr_afull),
//   .rd_almost_empty  (FIFO4_rd_aempty)

//   );

// async_fifo_fwft_high_fmax     FIFO5_reg_high_fmax    (

//   .wr_clk           (clk1),
//   .wr_rst           (reset),
//   .wr_en            (FIFO2_wr_en),
//   .wr_data          (FIFO2_wr_data),
//   .wr_full          (FIFO5_wr_full),
//   .rd_clk           (clk2),
//   .rd_rst           (reset),
//   .rd_en            (FIFO2_rd_en),
//   .rd_data          (FIFO5_rd_data),
//   .rd_empty         (FIFO5_rd_empty),
//   .wr_cnt           (FIFO5_wr_used),
//   .rd_cnt           (FIFO5_rd_used),
//   .wr_almost_full   (FIFO5_wr_afull),
//   .rd_almost_empty  (FIFO5_rd_aempty)

//   );

  

wire [31:0] m_axi_tdata1;
wire        m_axi_tvalid1;
wire        m_axi_tlast1;
wire        m_axi_tready1;
// wire [3:0]  m_axi_tkeep;
wire [1:0]  dbg_state_out1;

wire [31:0] m_axi_tdata2;
wire        m_axi_tvalid2;
wire        m_axi_tlast2;
wire        m_axi_tready2;
// wire [3:0]  m_axi_tkeep;
wire [1:0]  dbg_state_out2;

wire [31:0] m_axi_tdata3;
wire        m_axi_tvalid3;
wire        m_axi_tlast3;
wire        m_axi_tready3;
// wire [3:0]  m_axi_tkeep;
wire [1:0]  dbg_state_out3;

wire [31:0] m_axi_tdata4;
wire        m_axi_tvalid4;
wire        m_axi_tlast4;
wire        m_axi_tready4;
// wire [3:0]  m_axi_tkeep;
wire [1:0]  dbg_state_out4;

// AXIS_master_FIFO_rd   AXIS_master_FIFO_rd    (

//   .clk                (clk2),
//   .reset              (reset),
//   .N                  (N),
//   .lane_up            (!reset),
//   .channel_up         (!reset),
//   .s_axi_tdata        (32'b0),
//   .s_axi_tvalid       (1'b0),
//   .s_axi_tlast        (1'b0),
//   .s_axi_tkeep        (4'b0),
//   .s_axi_tuser        (1'b0),
//   .m_axi_nfc_ack      (1'b0),
//   .s_axi_rx_snf       (1'b0),
//   .s_axi_rx_fc_nb     (4'b0),
//   .LinkPartner_XOFF   (1'b0),
//   .dbg_NFC_NB_in      (4'b0),
//   .D_FIFO_rd_aempty   (/*FIFO1_rd_empty*/FIFO1_rd_aempty),
//   .D_FIFO_rd_empty    (FIFO1_rd_empty),
//   .D_FIFO_rd_data     (FIFO1_rd_data),
//   .D_WORD_rd_data     (16'hABCD),
//   .D_WORD_rd_empty    (1'b0),
//   .m_axi_tready       (m_axi_tready),
//   .m_axi_tdata        (m_axi_tdata),
//   .m_axi_tvalid       (m_axi_tvalid),
//   .m_axi_tlast        (m_axi_tlast),
//   .m_axi_tkeep        (m_axi_tkeep),
//   .m_axi_tuser        (),
//   .m_axi_nfc_req      (),
//   .m_axi_nfc_nb       (),
//   .dbg_NFC_rcvd_value (),
//   .dbg_rxerr_out      (),
//   .D_FIFO_rd_en       (FIFO1_rd_en),
//   .D_WORD_rd_en       (D_WORD_rd_en),
//   .dbg_state_out      (dbg_state_out)

//   );

AXIS_master_FIFO_rd_DIRTY   AXIS_master_FIFO_rd_DIRTY    (

  .clk                (clk2),
  .reset              (reset),
  .N                  (N),
  .lane_up            (!reset),
  .channel_up         (!reset),
  .s_axi_tdata        (32'b0),
  .s_axi_tvalid       (1'b0),
  .s_axi_tlast        (1'b0),
  .s_axi_tkeep        (4'b0),
  .s_axi_tuser        (1'b0),
  .m_axi_nfc_ack      (1'b0),
  .s_axi_rx_snf       (1'b0),
  .s_axi_rx_fc_nb     (4'b0),
  .LinkPartner_XOFF   (1'b0),
  .dbg_NFC_NB_in      (4'b0),
  .D_FIFO_rd_aempty   (1'b0),
  .D_FIFO_rd_empty    (FIFO1_rd_empty),
  .D_FIFO_rd_data     (FIFO1_rd_data),
  .D_WORD_rd_data     (16'hABCD),
  .D_WORD_rd_empty    (1'b0),
  .m_axi_tready       (m_axi_tready1),
  .m_axi_tdata        (m_axi_tdata1),
  .m_axi_tvalid       (m_axi_tvalid1),
  .m_axi_tlast        (m_axi_tlast1),
  .m_axi_tkeep        (/*m_axi_tkeep1*/),
  .m_axi_tuser        (),
  .m_axi_nfc_req      (),
  .m_axi_nfc_nb       (),
  .dbg_NFC_rcvd_value (),
  .dbg_rxerr_out      (),
  .D_FIFO_rd_en       (FIFO1_rd_en),
  .D_WORD_rd_en       (/*D_WORD_rd_en*/),
  .dbg_state_out      (dbg_state_out1)

  );

Simple_tready_gen     Simple_tready_gen1    (

  .clk                (clk2),
  .reset              (reset),
  .toggle_enable      (tready_toggle_enable),
  .tvalid             (m_axi_tvalid1),
  .tready             (m_axi_tready1)
  );

wire checker_err1;

simple_tdata_checker     simple_tdata_checker1    (

  .clk                (clk2),
  .reset              (reset),
  .N                  (N),
  .m_axis_tready      (m_axi_tready1),
  .m_axis_tdata       (m_axi_tdata1),
  .m_axis_tvalid      (m_axi_tvalid1),
  .m_axis_tlast       (m_axi_tlast1),
  .err_out            (checker_err1)
  );

  ///////////////////////////////////
  AXIS_master_FIFO_rd_reg_logic   AXIS_master_FIFO_rd_reg_logic    (

  .clk                (clk2),
  .reset              (reset),
  .N                  (N),
  .lane_up            (!reset),
  .channel_up         (!reset),
  .s_axi_tdata        (32'b0),
  .s_axi_tvalid       (1'b0),
  .s_axi_tlast        (1'b0),
  .s_axi_tkeep        (4'b0),
  .s_axi_tuser        (1'b0),
  .m_axi_nfc_ack      (1'b0),
  .s_axi_rx_snf       (1'b0),
  .s_axi_rx_fc_nb     (4'b0),
  .LinkPartner_XOFF   (1'b0),
  .dbg_NFC_NB_in      (4'b0),
  .D_FIFO_rd_aempty   (1'b0),
  .D_FIFO_rd_empty    (FIFO2_rd_empty),
  .D_FIFO_rd_data     (FIFO2_rd_data),
  .D_WORD_rd_data     (16'hABCD),
  .D_WORD_rd_empty    (1'b0),
  .m_axi_tready       (m_axi_tready2),
  .m_axi_tdata        (m_axi_tdata2),
  .m_axi_tvalid       (m_axi_tvalid2),
  .m_axi_tlast        (m_axi_tlast2),
  .m_axi_tkeep        (/*m_axi_tkeep2*/),
  .m_axi_tuser        (),
  .m_axi_nfc_req      (),
  .m_axi_nfc_nb       (),
  .dbg_NFC_rcvd_value (),
  .dbg_rxerr_out      (),
  .D_FIFO_rd_en       (FIFO2_rd_en),
  .D_WORD_rd_en       (/*D_WORD_rd_en*/),
  .dbg_state_out      (dbg_state_out2)

  );

Simple_tready_gen     Simple_tready_gen2    (

  .clk                (clk2),
  .reset              (reset),
  .toggle_enable      (tready_toggle_enable),
  .tvalid             (m_axi_tvalid2),
  .tready             (m_axi_tready2)
  );

wire checker_err2;

simple_tdata_checker     simple_tdata_checker2    (

  .clk                (clk2),
  .reset              (reset),
  .N                  (N),
  .m_axis_tready      (m_axi_tready2),
  .m_axis_tdata       (m_axi_tdata2),
  .m_axis_tvalid      (m_axi_tvalid2),
  .m_axis_tlast       (m_axi_tlast2),
  .err_out            (checker_err2)
  );

    ///////////////////////////////////
  AXIS_master_FIFO_rd_reg_logic   AXIS_master_FIFO_rd_skid    (

  .clk                (clk2),
  .reset              (reset),
  .N                  (N),
  .lane_up            (!reset),
  .channel_up         (!reset),
  .s_axi_tdata        (32'b0),
  .s_axi_tvalid       (1'b0),
  .s_axi_tlast        (1'b0),
  .s_axi_tkeep        (4'b0),
  .s_axi_tuser        (1'b0),
  .m_axi_nfc_ack      (1'b0),
  .s_axi_rx_snf       (1'b0),
  .s_axi_rx_fc_nb     (4'b0),
  .LinkPartner_XOFF   (1'b0),
  .dbg_NFC_NB_in      (4'b0),
  .D_FIFO_rd_aempty   (1'b0),
  .D_FIFO_rd_empty    (FIFO3_rd_empty),
  .D_FIFO_rd_data     (FIFO3_rd_data),
  .D_WORD_rd_data     (16'hABCD),
  .D_WORD_rd_empty    (1'b0),
  .m_axi_tready       (m_axi_tready3),
  .m_axi_tdata        (m_axi_tdata3),
  .m_axi_tvalid       (m_axi_tvalid3),
  .m_axi_tlast        (m_axi_tlast3),
  .m_axi_tkeep        (/*m_axi_tkeep2*/),
  .m_axi_tuser        (),
  .m_axi_nfc_req      (),
  .m_axi_nfc_nb       (),
  .dbg_NFC_rcvd_value (),
  .dbg_rxerr_out      (),
  .D_FIFO_rd_en       (FIFO3_rd_en),
  .D_WORD_rd_en       (/*D_WORD_rd_en*/),
  .dbg_state_out      (dbg_state_out3)

  );

Simple_tready_gen     Simple_tready_gen3    (

  .clk                (clk2),
  .reset              (reset),
  .toggle_enable      (tready_toggle_enable),
  .tvalid             (m_axi_tvalid3),
  .tready             (m_axi_tready3)
  );

wire checker_err3;

simple_tdata_checker     simple_tdata_checker3    (

  .clk                (clk2),
  .reset              (reset),
  .N                  (N),
  .m_axis_tready      (m_axi_tready3),
  .m_axis_tdata       (m_axi_tdata3),
  .m_axis_tvalid      (m_axi_tvalid3),
  .m_axis_tlast       (m_axi_tlast3),
  .err_out            (checker_err3)
  );

      ///////////////////////////////////
  AXIS_master_FIFO_rd_2_WORD_FIFO   AXIS_master_FIFO_rd_2_WORD_FIFO    (

  .clk                (clk2),
  .reset              (reset),
  .N                  (N),
  .lane_up            (!reset),
  .channel_up         (!reset),
  .s_axi_tdata        (32'b0),
  .s_axi_tvalid       (1'b0),
  .s_axi_tlast        (1'b0),
  .s_axi_tkeep        (4'b0),
  .s_axi_tuser        (1'b0),
  .m_axi_nfc_ack      (1'b0),
  .s_axi_rx_snf       (1'b0),
  .s_axi_rx_fc_nb     (4'b0),
  .LinkPartner_XOFF   (1'b0),
  .dbg_NFC_NB_in      (4'b0),
  .D_FIFO_rd_aempty   (1'b0),
  .D_FIFO_rd_empty    (FIFO4_rd_empty),
  .D_FIFO_rd_data     (FIFO4_rd_data),
  .D_WORD_rd_data     (16'hABCD),
  .D_WORD_rd_empty    (1'b0),
  .m_axi_tready       (m_axi_tready4),
  .m_axi_tdata        (m_axi_tdata4),
  .m_axi_tvalid       (m_axi_tvalid4),
  .m_axi_tlast        (m_axi_tlast4),
  .m_axi_tkeep        (/*m_axi_tkeep2*/),
  .m_axi_tuser        (),
  .m_axi_nfc_req      (),
  .m_axi_nfc_nb       (),
  .dbg_NFC_rcvd_value (),
  .dbg_rxerr_out      (),
  .D_FIFO_rd_en       (FIFO4_rd_en),
  .D_WORD_rd_en       (/*D_WORD_rd_en*/),
  .dbg_state_out      (dbg_state_out4)

  );

Simple_tready_gen     Simple_tready_gen4    (

  .clk                (clk2),
  .reset              (reset),
  .toggle_enable      (tready_toggle_enable),
  .tvalid             (m_axi_tvalid4),
  .tready             (m_axi_tready4)
  );

wire checker_err4;

simple_tdata_checker     simple_tdata_checker4    (

  .clk                (clk2),
  .reset              (reset),
  .N                  (N),
  .m_axis_tready      (m_axi_tready4),
  .m_axis_tdata       (m_axi_tdata4),
  .m_axis_tvalid      (m_axi_tvalid4),
  .m_axis_tlast       (m_axi_tlast4),
  .err_out            (checker_err4)
  );



endmodule

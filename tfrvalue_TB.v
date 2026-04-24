`timescale 1 ps / 1 ps

module tfrvalue_TB(

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


// initial begin
// 	reset = 1'b1;
// // #400000 @(negedge pll_not_locked_out)
// // 		reset = 1'b0;
// #2000000
// 		reset = 1'b0;
// end

wire [31:0] tdata;
wire        tvalid;
wire        tready;

Simple_AXIS_master    Simple_AXIS_master    (
        // AXI TX Interface
  .clk                (clk1),
  .reset              (reset),
  .m_axi_tdata        (tdata),
  .m_axi_tvalid       (tvalid),
  .m_axi_tlast        (),
  .m_axi_tkeep        (),
  .channel_up         (1'b1),
  .lane_up            (1'b1),
  .m_axi_tready       (tready),
  .s_axi_tdata        (32'b0),
  .s_axi_tvalid       (1'b0),
  .s_axi_tlast        (1'b0),
  .s_axi_tuser        (1'b0),
  .s_axi_tkeep        (4'b0),
  .m_axi_nfc_ack      (1'b0),
  .s_axi_rx_snf       (1'b0),
  .s_axi_rx_fc_nb     (4'b0),
  .LinkPartner_XOFF   (1'b0),
  .dbg_NFC_NB_in      (4'b0)
  

  );

tfrvalue              tfrvalue    (
        // AXI TX Interface
  .i_a_clk            (clk1),
  .i_a_reset          (reset),
  .i_a_valid          (tvalid),
  .o_a_ready          (tready),
  .i_a_data           (tdata),
  .i_b_clk            (clk2),
  .i_b_reset          (),
  .o_b_valid          (),
  .i_b_ready          (1'b1),
  .o_b_data           ()

  );


endmodule
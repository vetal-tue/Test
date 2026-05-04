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


initial begin
  $dumpfile("tfrvalue_TB.vcd");
  $dumpvars(0,tfrvalue_TB);
end

integer cycle_count = 0;

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
    $finish; // Останавливаем симуляцию
end

wire [31:0] tdata_in;
wire        tvalid_in;
wire        tready_in;

wire [31:0] tdata_out;
wire        tvalid_out;

Simple_AXIS_master    Simple_AXIS_master    (
        // AXI TX Interface
  .clk                (clk1),
  .reset              (reset),
  .m_axi_tdata        (tdata_in),
  .m_axi_tvalid       (tvalid_in),
  .m_axi_tlast        (),
  .m_axi_tkeep        (),
  .channel_up         (1'b1),
  .lane_up            (1'b1),
  .m_axi_tready       (tready_in),
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
  .i_a_valid          (tvalid_in),
  .o_a_ready          (tready_in),
  .i_a_data           (tdata_in),
  .i_b_clk            (clk2),
  .i_b_reset          (reset),
  .o_b_valid          (tvalid_out),
  .i_b_ready          (1'b1),
  .o_b_data           (tdata_out)

  );


endmodule

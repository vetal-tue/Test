`timescale 1 ps / 1 ps

module AvalonST_to_AXIS_TB (
  
);

parameter   SIM_MAX_TIME  = 150000000; //To quit the simulation
// parameter   clk1_period = 10000 ; // 100 MHz
// parameter   clk2_period = 6400 ; // 156.25 MHz
parameter   clk1_period = 6400; // 100 MHz
// parameter   clk2_period = 10000; // 156.25 MHz
parameter [7:0] N  = 10;
parameter tready_toggle_enable = 1'b0;


reg     clk1;
// reg     clk2;
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

// initial begin
//   clk2   = 1'b0;
//   forever #(clk2_period / 2) clk2 = !clk2;
// end

initial begin
	$dumpfile("AvalonST_to_AXIS_TB.vcd");
	$dumpvars(0,AvalonST_to_AXIS_TB);
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
    $finish; // Останавливаем симуляцию
end

  

wire [15:0] m_axi_tdata1;
wire        m_axi_tvalid1;
wire        m_axi_tlast1;
wire        m_axi_tready1;
// wire [3:0]  m_axi_tkeep;
wire        axi_err_out1;

wire [15:0] m_axi_tdata2;
wire        m_axi_tvalid2;
wire        m_axi_tlast2;
wire        m_axi_tready2;
// wire [3:0]  m_axi_tkeep;
wire        axi_err_out2;


wire [15:0] av_data1;
wire        av_valid1;
wire        av_sop1;
wire        av_eop1;
wire        av_ready1;
wire        av_err_out1;

wire [15:0] av_data1_from_axi;
wire        av_valid1_from_axi;
wire        av_sop1_from_axi;
wire        av_eop1_from_axi;
wire        av_ready1_to_axi;

wire [15:0] av_data2;
wire        av_valid2;
wire        av_sop2;
wire        av_eop2;
wire        av_ready2;
wire        av_err_out2;

wire [15:0] av_data2_from_axi;
wire        av_valid2_from_axi;
wire        av_sop2_from_axi;
wire        av_eop2_from_axi;
wire        av_ready2_to_axi;



simple_avalon_st_generator     simple_avalon_st_generator1    (

  .clk                (clk1),
  .reset              (reset),
  .av_sop             (av_sop1),
  .av_valid           (av_valid1),
  .av_data            (av_data1),
  .av_eop             (av_eop1),
  .av_ready           (av_ready1),
  .N                  (N)
  );

avalon_st_to_axis   avalon_st_to_axis    (

  .clk                (clk1),
  .reset              (reset),
  // .av_sop             (av_sop1),
  .av_valid           (av_valid1),
  .av_data            (av_data1),
  .av_eop             (av_eop1),
  .av_ready           (av_ready1),
  .m_ready            (m_axi_tready1),
  .m_valid            (m_axi_tvalid1),
  .m_data             (m_axi_tdata1),
  .m_last             (m_axi_last1)
  );


axis_to_avalon_st_skid   axis_to_avalon_st_skid    (

  .clk                (clk1),
  .reset              (reset),
  .av_sop             (av_sop1_from_axi),
  .av_valid           (av_valid1_from_axi),
  .av_data            (av_data1_from_axi),
  .av_eop             (av_eop1_from_axi),
  .av_ready           (av_ready1_to_axi),
  .axi_tready         (m_axi_tready1),
  .axi_valid          (m_axi_tvalid1),
  .axi_data           (m_axi_tdata1),
  .axi_last           (m_axi_last1)
  );

Simple_avalon_rdy_gen     Simple_tready_gen1    (

  .clk                (clk1),
  .reset              (reset),
  // .toggle_enable      (tready_toggle_enable),
  .tvalid             (av_valid1_from_axi),
  .tready             (av_ready1_to_axi)
  );

simple_avalonst_axis_checker   simple_avalonst_axis_checker1    (

  .clk                (clk1),
  .reset              (reset),
  .av_sop             (av_sop1_from_axi),
  .av_valid           (av_valid1_from_axi),
  .av_data            (av_data1_from_axi),
  .av_eop             (av_eop1_from_axi),
  // .av_ready           (av_ready1_to_axi),
  .av_err_out         (av_err_out1),
  .axis_tready        (m_axi_tready1),
  .axis_tvalid        (m_axi_tvalid1),
  .axis_tdata         (m_axi_tdata1),
  .axis_tlast         (m_axi_last1),
  .axi_err_out        (axi_err_out1),
  .N                  (N)
  );

simple_avalon_st_generator     simple_avalon_st_generator2    (

  .clk                (clk1),
  .reset              (reset),
  .av_sop             (av_sop2),
  .av_valid           (av_valid2),
  .av_data            (av_data2),
  .av_eop             (av_eop2),
  .av_ready           (av_ready2),
  .N                  (N)
  );

avalon_st_to_axis_4word_fifo   avalon_st_to_axis_4word_fifo    (

  .clk                (clk1),
  .reset              (reset),
  .av_sop             (av_sop2),
  .av_valid           (av_valid2),
  .av_data            (av_data2),
  .av_eop             (av_eop2),
  .av_ready           (av_ready2),
  .m_ready            (m_axi_tready2),
  .m_valid            (m_axi_tvalid2),
  .m_data             (m_axi_tdata2),
  .m_last             (m_axi_last2)
  );

axis_to_avalon_st_skid2   axis_to_avalon_st_skid2    (

  .clk                (clk1),
  .reset              (reset),
  .av_sop             (av_sop2_from_axi),
  .av_valid           (av_valid2_from_axi),
  .av_data            (av_data2_from_axi),
  .av_eop             (av_eop2_from_axi),
  .av_ready           (av_ready2_to_axi),
  .axi_tready         (m_axi_tready2),
  .axi_valid          (m_axi_tvalid2),
  .axi_data           (m_axi_tdata2),
  .axi_last           (m_axi_last2)
  );

simple_avalonst_axis_checker   simple_avalonst_axis_checker2    (

  .clk                (clk1),
  .reset              (reset),
  .av_sop             (av_sop2_from_axi),
  .av_valid           (av_valid2_from_axi),
  .av_data            (av_data2_from_axi),
  .av_eop             (av_eop2_from_axi),
  // .av_ready           (av_ready2_to_axi),
  .av_err_out         (av_err_out2),
  .axis_tready        (m_axi_tready2),
  .axis_tvalid        (m_axi_tvalid2),
  .axis_tdata         (m_axi_tdata2),
  .axis_tlast         (m_axi_last2),
  .axi_err_out        (axi_err_out2),
  .N                  (N)
  );

Simple_avalon_rdy_gen     Simple_tready_gen2    (

  .clk                (clk1),
  .reset              (reset),
  // .toggle_enable      (tready_toggle_enable),
  .tvalid             (av_valid2_from_axi),
  .tready             (av_ready2_to_axi)
  );



endmodule

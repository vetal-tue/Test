// ============================================================================
// SATA RX CONT / ALIGN filter
// ----------------------------------------------------------------------------
// Fully corrected production-oriented implementation.
//
// Features
// --------
// 1. Reconstructs CONT sequences according to SATA specification
//
//      <primitive> CONT <scrambled> <scrambled>
//
//    becomes:
//
//      <primitive> <primitive> <primitive> <primitive>
//
// 2. Removes ALIGN primitives by replacing them with the previous primitive
//
// 3. Properly handles Data FIS payloads
//
//      - CONT reconstruction active ONLY outside payload
//      - Payload DWORDs pass transparently
//
// 4. Constant throughput:
//      1 DWORD in  -> 1 DWORD out
//
// 5. Fixed latency:
//      1 clk
//
// 6. No bubbles
// 7. No valid signal
// 8. FPGA synthesis friendly
//
// ----------------------------------------------------------------------------
// Assumptions
// ----------------------------------------------------------------------------
//
// - Stream already DWORD aligned
// - rx_ctrl_in == 4'b0001 for SATA primitives
// - SOF/EOF are aligned primitives
//
// ============================================================================

module sata_rx_cont_align_filter (

    input wire clk,
    input wire rst,

    input wire [31:0] rx_data_in,
    input wire [ 3:0] rx_ctrl_in,

    output reg [31:0] rx_data_out,
    output reg [ 3:0] rx_ctrl_out

);

  // =========================================================================
  // SATA primitives
  // =========================================================================

  localparam [31:0] ALIGN = 32'h7B4A4ABC;
  localparam [31:0] CONT = 32'h9999AA7C;

  localparam [31:0] SOF = 32'h3737B57C;
  localparam [31:0] EOF_ = 32'hD5D5B57C;

  localparam [31:0] SYNC = 32'hB5B5957C;

  // =========================================================================
  // Primitive detection
  // =========================================================================

  wire is_kword = rx_ctrl_in == 4'b0001;

  wire is_k28_3 = is_kword && rx_data_in[7:0] == 8'hBC;
  wire is_k28_5 = is_kword && rx_data_in[7:0] == 8'h7C;

  wire is_align = is_k28_3 && rx_data_in[31:8] == ALIGN[31:8];
  wire is_cont = is_k28_5 && rx_data_in[31:8] == CONT[31:8];
  wire is_sof = is_k28_5 && rx_data_in[31:8] == SOF[31:8];
  wire is_eof = is_k28_5 && rx_data_in[31:8] == EOF_[31:8];

  // =========================================================================
  // Payload tracking
  // =========================================================================

  reg in_payload;

  // =========================================================================
  // CONT reconstruction state
  // =========================================================================

  reg cont_active;

  // =========================================================================
  // Last valid primitive
  // =========================================================================

  reg [31:0] last_primitive_data;
//   reg [3:0] last_primitive_ctrl;

  // =========================================================================
  // Selected output
  // =========================================================================

  //   reg [31:0] selected_data;
  //   reg [3:0] selected_ctrl;

  wire replace_with_last = !in_payload && (is_align || is_cont || (cont_active && !is_kword));


  // =========================================================================
  // Sequential logic
  // =========================================================================

  always @(posedge clk) begin

    if (rst) begin

      // -----------------------------------------------------------------
      // Outputs
      // -----------------------------------------------------------------

      rx_data_out <= SYNC;
      rx_ctrl_out <= 4'b0001;

      // -----------------------------------------------------------------
      // State
      // -----------------------------------------------------------------

      in_payload <= 1'b0;
      cont_active <= 1'b0;

      // -----------------------------------------------------------------
      // Last primitive
      // -----------------------------------------------------------------

      last_primitive_data <= SYNC;
    //   last_primitive_ctrl <= 4'b0001;

    end else begin

      // -----------------------------------------------------------------
      // Register outputs
      // -----------------------------------------------------------------

      if (replace_with_last) begin
        rx_data_out <= last_primitive_data;
        rx_ctrl_out <= 4'b0001;
      end else begin
        rx_data_out <= rx_data_in;
        rx_ctrl_out <= rx_ctrl_in;
      end

      // -----------------------------------------------------------------
      // Payload tracking
      // -----------------------------------------------------------------

      in_payload  <= (in_payload && !is_eof) || is_sof;

      // -----------------------------------------------------------------
      // CONT tracking
      // -----------------------------------------------------------------
      //
      // CONT valid only outside payload
      //
      // Any non-CONT primitive terminates CONT mode
      //
      // -----------------------------------------------------------------

      cont_active <= !in_payload && (is_cont || (cont_active && !is_kword));

      // -----------------------------------------------------------------
      // Learn last real primitive
      // -----------------------------------------------------------------
      //
      // DO learn:
      //   SOF
      //   EOF
      //   SYNC
      //   X_RDY
      //   R_RDY
      //   etc
      //
      // DO NOT learn:
      //   CONT
      //   ALIGN
      //
      // -----------------------------------------------------------------

      if (is_kword && !is_cont && !is_align) begin

        last_primitive_data <= rx_data_in;
        last_primitive_ctrl <= rx_ctrl_in;

      end

    end

  end

endmodule

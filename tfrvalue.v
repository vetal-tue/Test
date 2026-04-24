////////////////////////////////////////////////////////////////////////////////
//
// Filename: 	tfrvalue.v
// {{{
// Project:	Formal methods example
//
// Purpose:	Illustrates a slow method of moving data across clock domains,
//		together with a formal proof of the same.  This is the "faster"
//	version of two methods, the second one given in tfrslow.v.  This one
//	is faster because it requires only a single round trip of the request
//	and the acknowledgement.
//
////////////////////////////////////////////////////////////////////////////////
//
// Written and distributed by Gisselquist Technology, LLC, based upon an
// bug I came across in my own work.
//
// This program is hereby given to the public domain.
//
// This program is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTIBILITY or
// FITNESS FOR A PARTICULAR PURPOSE.
//
////////////////////////////////////////////////////////////////////////////////
//
//
// https://github.com/ZipCPU/website/blob/master/examples/tfrvalue.v

`default_nettype	none
// }}}
module tfrvalue #(
		parameter	W = 32
	) (
		// {{{
		input	wire		i_a_clk,
		input	wire		i_a_reset,
		input	wire		i_a_valid,
		output	wire		o_a_ready,
		input	wire	[W-1:0]	i_a_data,
		//
		input	wire		i_b_clk,
		input	wire		i_b_reset,
		output	reg		o_b_valid,
		input	wire		i_b_ready,
		output	reg	[W-1:0]	o_b_data
		// }}}
	);

	// Register declarations
	// {{{
	localparam	NFF = 2;
	reg			a_req, a_ack;
	reg	[W-1:0]		a_data;
	reg	[NFF-2:0]	a_pipe;

	reg			b_req, b_last, b_stb;
	reg	[NFF-2:0]	b_pipe;
	// }}}

	// Launch
	// {{{
	initial	a_req = 0;
	always @(posedge i_a_clk, posedge i_a_reset)
	if (i_a_reset)
		a_req <= 1'b0;
	else if (i_a_valid && o_a_ready)
		a_req  <= !a_req;

	always @(posedge i_a_clk)
	if (i_a_valid && o_a_ready)
		a_data <= i_a_data;
	// }}}

	// Request to B
	// {{{
//	initial	{ b_last, b_req, b_pipe } = 0;
	always @(posedge i_b_clk, posedge i_b_reset)
	if (i_b_reset)
		{ b_last, b_req, b_pipe } <= 3'b0;
	else begin
		{ b_last, b_req, b_pipe } <= { b_req, b_pipe, a_req };
		if (o_b_valid && !i_b_ready)
			b_last <= b_last;
	end
	// }}}

	// Return ACK
	// {{{
	always @(posedge i_a_clk, posedge i_a_reset)
	if (i_a_reset)
		{ a_ack, a_pipe } <= 1'b0;
	else
		{ a_ack, a_pipe } <= { a_pipe, b_last };
	// }}}

	// Return ready
	assign	o_a_ready = (a_ack == a_req);

	// Outgoing strobe and data
	// {{{
	always @(*)
		b_stb = (b_last != b_req);

//	initial	o_b_data = 0;
	always @(posedge i_b_clk)
	if (b_stb && (!o_b_valid || i_b_ready))
		o_b_data <= a_data;

//	initial	o_b_valid = 0;
	always @(posedge i_b_clk, posedge i_b_reset)
	if (i_b_reset)
		o_b_valid <= 1'b0;
	else if (!o_b_valid || i_b_ready)
		o_b_valid <= b_stb;
	// }}}

endmodule

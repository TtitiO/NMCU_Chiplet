// nmcu_project/src/pe/pe_array_interface.sv
// Function: This module is the interface between the control unit and the PE array.
//           It receives commands from the control unit and sends them to the PE array.
//           It also receives results from the PE array and sends them to the control unit.

`include "nmcu_pkg.sv"
`include "instr_pkg.sv"

module pe_array_interface #(
    parameter DATA_WIDTH  = nmcu_pkg::DATA_WIDTH,
    parameter ADDR_WIDTH  = nmcu_pkg::ADDR_WIDTH,
    parameter LEN_WIDTH   = nmcu_pkg::LEN_WIDTH
) (
    input  logic                            clk,
    input  logic                            rst_n,

    // From Control Unit
    input  logic                            pe_cmd_valid_i,
    input  instr_pkg::instruction_t         pe_cmd_i,
    input  logic [DATA_WIDTH-1:0]           pe_operand_a_i,
    input  logic [DATA_WIDTH-1:0]           pe_operand_b_i,
    output logic                            pe_cmd_ready_o,

    // To Control Unit
    output logic                            pe_done_o,
    output logic [DATA_WIDTH-1:0]           pe_result_o
);

    import nmcu_pkg::*;
    import instr_pkg::*;

    // Instantiate the PE array
    pe_array pe_array_inst (
        .operand_a_i    (pe_operand_a_i),
        .operand_b_i    (pe_operand_b_i),
        .result_o       (pe_result) // Connect to internal signal
    );

    // Internal signal for the result
    logic [DATA_WIDTH-1:0] pe_result;

    // This interface is always ready to accept a command.
    assign pe_cmd_ready_o = 1'b1;

    // The 'done' signal is asserted one cycle after a valid command is received.
    // 'done' now means "the computation is finished and result_o is valid".
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pe_done_o <= 1'b0;
            pe_result_o <= '0;
        end else begin
            pe_done_o <= pe_cmd_valid_i && pe_cmd_ready_o;
            pe_result_o <= pe_result;
        end
    end
endmodule

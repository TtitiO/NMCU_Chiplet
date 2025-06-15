// nmcu_project/src/pe/pe_array.sv
// Function: A single Processing Element that performs a MAC operation.
// For now, this is a simple combinatorial MAC unit.
// TODO: This is a placeholder for a real PE array.
`include "nmcu_pkg.sv"
`include "instr_pkg.sv"

module pe_array #(
    parameter DATA_WIDTH = nmcu_pkg::DATA_WIDTH
) (
    input  logic [DATA_WIDTH-1:0]   operand_a_i,
    input  logic [DATA_WIDTH-1:0]   operand_b_i,
    output logic [DATA_WIDTH-1:0]   result_o
);

    // Simple Multiply-Accumulate logic for a single operation
    // In a real PE, this would be part of a larger state machine
    // and handle accumulation over multiple cycles.
    // For now, result = A * B.
    // A proper MAC would be: result = A * B + C_input

    // Using signed multiplication for more realistic ML workloads
    logic [2*DATA_WIDTH-1:0] mult_result;

    // Assuming signed operands
    assign mult_result = $signed(operand_a_i) * $signed(operand_b_i);

    // For now, we just truncate the result. A real implementation would handle overflow.
    assign result_o = mult_result[DATA_WIDTH-1:0];

endmodule

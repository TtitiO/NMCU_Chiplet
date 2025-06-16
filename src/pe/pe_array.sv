// nmcu_project/src/pe/pe_array.sv
//
// Function: A 4x4 output-stationary systolic array.

`include "nmcu_pkg.sv"
`include "instr_pkg.sv"

//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// Corrected Processing Element (PE)
//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
module systolic_pe #(
    parameter DATA_WIDTH = nmcu_pkg::DATA_WIDTH,
    parameter PSUM_WIDTH = nmcu_pkg::PSUM_WIDTH
) (
    input  logic                    clk,
    input  logic                    rst_n,
    input  logic                    accum_en_i,     // Control signal to enable accumulation

    // Dataflow inputs
    input  logic [DATA_WIDTH-1:0]   operand_a_i,    // Input from left
    input  logic [DATA_WIDTH-1:0]   operand_b_i,    // Input from top

    // Dataflow outputs
    output logic [DATA_WIDTH-1:0]   operand_a_o,    // Output to right
    output logic [DATA_WIDTH-1:0]   operand_b_o,    // Output to bottom

    // The result is held within the PE
    output logic [PSUM_WIDTH-1:0]   result_o
);

    // Pipeline registers for the operands moving systolically.
    logic [DATA_WIDTH-1:0] operand_a_reg;
    logic [DATA_WIDTH-1:0] operand_b_reg;

    logic [PSUM_WIDTH-1:0] psum_reg;

    logic signed [PSUM_WIDTH-1:0] mult_result;

    // Pipeline the incoming operands. This creates the one-cycle delay needed
    // for the systolic movement of data.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            operand_a_reg <= '0;
            operand_b_reg <= '0;
        end else begin
            operand_a_reg <= operand_a_i;
            operand_b_reg <= operand_b_i;
        end
    end

    // Combinatorial multiplication of the registered operands.
    assign mult_result = $signed(operand_a_reg) * $signed(operand_b_reg);

    // Accumulator logic.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            psum_reg <= '0;
        end else if (accum_en_i) begin
            psum_reg <= psum_reg + mult_result;
        end
        // If accum_en_i is de-asserted, the register holds its value.
    end

    // The outputs are the registered values, passed to the next PE in the grid.
    assign operand_a_o = operand_a_reg;
    assign operand_b_o = operand_b_reg;
    assign result_o    = psum_reg; // Output the current accumulated value.

endmodule

//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// Corrected 4x4 Systolic Array
//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
module pe_array #(
    parameter DATA_WIDTH = nmcu_pkg::DATA_WIDTH,
    parameter PSUM_WIDTH = nmcu_pkg::PSUM_WIDTH,
    parameter ROWS = 4,
    parameter COLS = 4
) (
    input  logic                         clk,
    input  logic                         rst_n,
    // A single signal to control accumulation in all PEs.
    // The control unit must assert this to perform the MAC operation.
    // To clear the array, pulse rst_n.
    input  logic                         accum_en_i,

    // Input operand streams. The controller must feed these with the
    // correct timing (skew).
    input  logic [DATA_WIDTH-1:0]        operand_a_i [ROWS-1:0],  // Inputs for first column
    input  logic [DATA_WIDTH-1:0]        operand_b_i [COLS-1:0],  // Inputs for first row

    output logic [PSUM_WIDTH-1:0]        result_o [ROWS-1:0][COLS-1:0]
);

    // Internal wires for connecting PEs grid.
    logic [DATA_WIDTH-1:0] pe_a_wires [ROWS-1:0][COLS:0];
    logic [DATA_WIDTH-1:0] pe_b_wires [ROWS:0][COLS-1:0];

    // Connect top-level inputs to the wires at the array boundary.
    assign pe_b_wires[0] = operand_b_i;
    genvar r_assign;
    generate
      for (r_assign = 0; r_assign < ROWS; r_assign++) begin
        assign pe_a_wires[r_assign][0] = operand_a_i[r_assign];
      end
    endgenerate

    // Generate 4x4 array of PEs.
    genvar i, j;
    generate
        for (i = 0; i < ROWS; i++) begin : gen_row
            for (j = 0; j < COLS; j++) begin : gen_col

                systolic_pe #(
                    .DATA_WIDTH(DATA_WIDTH),
                    .PSUM_WIDTH(PSUM_WIDTH)
                ) pe_inst (
                    .clk(clk),
                    .rst_n(rst_n),
                    .accum_en_i(accum_en_i),

                    .operand_a_i(pe_a_wires[i][j]),
                    .operand_b_i(pe_b_wires[i][j]),

                    .operand_a_o(pe_a_wires[i][j+1]),
                    .operand_b_o(pe_b_wires[i+1][j]),

                    .result_o(result_o[i][j])
                );
            end
        end
    endgenerate

endmodule

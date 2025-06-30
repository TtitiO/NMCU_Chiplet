// nmcu_project/src/pe/pe_array_interface.sv
// Function: Interface between control unit and PE array.
//           Manages data flow and timing for the PE array.
`include "nmcu_pkg.sv"
`include "instr_pkg.sv"

module pe_array_interface #(
    parameter DATA_WIDTH       = nmcu_pkg::DATA_WIDTH,
    parameter PSUM_WIDTH       = nmcu_pkg::PSUM_WIDTH,
    parameter PE_ROWS          = nmcu_pkg::PE_ROWS,
    parameter PE_COLS          = nmcu_pkg::PE_COLS,
    parameter INPUT_FEATURES   = nmcu_pkg::INPUT_FEATURES,
    // Pipeline latency is the sum of:
    // 1. Computation cycles (K): INPUT_FEATURES cycles for the inner dimension.
    // 2. Systolic array fill/drain time: (PE_ROWS + PE_COLS - 2) cycles.
    // 3. PE internal pipeline depth: 2 cycles (reg for operands, reg for psum).
    // 4. Interface pipeline stage: 1 cycle (input registers in this module).
    parameter PIPELINE_LATENCY = INPUT_FEATURES + (PE_ROWS + PE_COLS - 2) + 2 + 1
) (
    input  logic                            clk,
    input  logic                            rst_n,

    // --- Interface to Control Unit ---
    input  logic                            pe_cmd_valid_i,     // Indicates a new command and valid data
    output logic                            pe_cmd_ready_o,     // Ready to accept a new command
    input  logic [PE_ROWS-1:0]              pe_accum_en_i,      // Accumulate enable signal
    input  logic [DATA_WIDTH-1:0]           pe_operand_a_i [PE_ROWS-1:0],
    input  logic [DATA_WIDTH-1:0]           pe_operand_b_i [PE_COLS-1:0],

    output logic                            pe_done_o,          // Signal that the result is valid
    output logic [PSUM_WIDTH-1:0]           pe_result_o [PE_ROWS-1:0][PE_COLS-1:0]
);

    import nmcu_pkg::*;
    import instr_pkg::*;

    // Internal signals for the PE array module
    logic [PSUM_WIDTH-1:0]   pe_result_from_pe [PE_ROWS-1:0][PE_COLS-1:0];

    // Pipeline registers for inputs to the PE array
    logic [PE_ROWS-1:0]              pe_accum_en_reg;
    logic [DATA_WIDTH-1:0]           operand_a_to_pe [PE_ROWS-1:0];
    logic [DATA_WIDTH-1:0]           operand_b_to_pe [PE_COLS-1:0];

    // The interface is always ready to accept streaming data
    assign pe_cmd_ready_o = 1'b1;

    // Instantiate the actual PE array
    pe_array #(
        .DATA_WIDTH(DATA_WIDTH),
        .PSUM_WIDTH(PSUM_WIDTH),
        .ROWS(PE_ROWS),
        .COLS(PE_COLS)
    ) pe_array_inst (
        .clk(clk),
        .rst_n(rst_n),
        .accum_en_i(pe_accum_en_reg),
        .operand_a_i(operand_a_to_pe),
        .operand_b_i(operand_b_to_pe),
        .result_o(pe_result_from_pe)
    );

    // Register inputs to create a pipeline stage and ensure timing
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            operand_a_to_pe <= '{default: '0};
            operand_b_to_pe <= '{default: '0};
            pe_accum_en_reg <= '{default: 1'b0};
        end else if (pe_cmd_valid_i) begin // Only register new data when it's valid from CU
            operand_a_to_pe <= pe_operand_a_i;
            operand_b_to_pe <= pe_operand_b_i;
            pe_accum_en_reg <= pe_accum_en_i;
        end else begin
            // If CU is not sending valid data, stream zeros to flush the array
            operand_a_to_pe <= '{default: '0};
            operand_b_to_pe <= '{default: '0};
            pe_accum_en_reg <= '{default: 1'b1}; // Keep accumulate on to finish
        end
    end

    // The pe_done signal needs to be a delayed version of a 'latch' signal from the CU.
    // For simplicity, we can have the CU signal the last valid command.
    // Let's modify the CU to send a 'last_cmd' signal and pipeline that.
    // For now, let's assume the LATCH_PE_RESULTS state in the CU is sufficient.
    // The CU transitions to LATCH_PE_RESULTS one cycle after the last stream.
    // The results will be valid after the latency of the array.

    logic [PIPELINE_LATENCY:0] done_shift_reg;

    // The CU's LATCH_PE_RESULTS state serves as the trigger.
    // We assume the CU will de-assert pe_cmd_valid when it's done streaming.
    // A simpler trigger for 'done' would be when the CU is done streaming.
    // This part is tricky. A simple fix is to use the existing `LATCH_PE_RESULTS` state.
    // We'll assume the `pe_done_i` input to the CU now signals that the result can be read.

    assign pe_done_o = done_shift_reg[PIPELINE_LATENCY];
    assign pe_result_o = pe_result_from_pe;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            done_shift_reg <= '0;
        end else begin
            // A simple way to signal done is to look for the last valid input from the CU
            // and then wait for the pipeline to drain. Let's assume the CU holds valid
            // high throughout the STREAM_PE_DATA state.
            done_shift_reg <= {done_shift_reg[PIPELINE_LATENCY-1:0], pe_cmd_valid_i};
        end
    end
    
endmodule

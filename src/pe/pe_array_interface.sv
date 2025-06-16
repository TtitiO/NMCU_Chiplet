// nmcu_project/src/pe/pe_array_interface.sv
// Function: Interface between control unit and PE array.
//           Manages data flow and timing for the PE array.
`include "nmcu_pkg.sv"
`include "instr_pkg.sv"

module pe_array_interface #(
    parameter DATA_WIDTH       = nmcu_pkg::DATA_WIDTH,
    parameter PSUM_WIDTH       = nmcu_pkg::PSUM_WIDTH,
    // Latency for a 4x4 array. Results are valid after inputs propagate.
    // A simple model: (ArrayDim - 1) for input skew + ArrayDim for processing.
    parameter PIPELINE_LATENCY = 4 + 4 - 1
) (
    input  logic                            clk,
    input  logic                            rst_n,

    // --- Interface to Control Unit ---
    input  logic                            pe_cmd_valid_i,     // Indicates a new command and valid data
    output logic                            pe_cmd_ready_o,     // Ready to accept a new command
    input  logic                            pe_accum_en_i,      // Accumulate enable signal
    input  logic [DATA_WIDTH-1:0]           pe_operand_a_i [3:0],
    input  logic [DATA_WIDTH-1:0]           pe_operand_b_i [3:0],

    output logic                            pe_done_o,          // Signal that the result is valid
    output logic [PSUM_WIDTH-1:0]           pe_result_o [3:0][3:0]
);

    import nmcu_pkg::*;
    import instr_pkg::*;

    // Internal signals for the PE array module
    logic                    pe_done_reg;
    logic [PSUM_WIDTH-1:0]   pe_result_reg [3:0][3:0];
    logic [PSUM_WIDTH-1:0]   pe_result_from_pe [3:0][3:0];
    logic [DATA_WIDTH-1:0]   operand_a_to_pe [3:0];
    logic [DATA_WIDTH-1:0]   operand_b_to_pe [3:0];
    logic [$clog2(PIPELINE_LATENCY)-1:0] latency_counter;
    logic                               start_processing;
    logic                               pe_accum_en_pulse;
    logic                               pe_accum_en_pulse_dly;

    // Instantiate the actual PE array
    // Note: The warning about DECLFILENAME suggests the module is named 'systolic_pe'
    // If you rename the module in pe_array.sv to 'pe_array', this will be correct.
    pe_array pe_array_inst (
        .clk(clk),
        .rst_n(rst_n),
        .accum_en_i(pe_accum_en_pulse_dly),
        .operand_a_i(operand_a_to_pe),
        .operand_b_i(operand_b_to_pe),
        .result_o(pe_result_from_pe)       // Connect result directly to output
    );

    // Control logic for ready/valid/done handshake
    typedef enum logic [1:0] { IDLE, PROCESSING } state_t;
    state_t current_state, next_state;

    assign start_processing = (current_state == IDLE) && pe_cmd_valid_i && pe_cmd_ready_o;
    assign pe_done_o = pe_done_reg;
    assign pe_result_o = pe_result_reg;
    // Only accumulate if the CU enables it AND it's the start of a new operation.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pe_accum_en_pulse <= 1'b0;
        end else begin
            pe_accum_en_pulse <= start_processing && pe_accum_en_i;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pe_accum_en_pulse_dly <= 1'b0;
        end else begin
            pe_accum_en_pulse_dly <= pe_accum_en_pulse;
        end
    end
    // Register inputs on command start to ensure stability
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            operand_a_to_pe <= '{default: '0};
            operand_b_to_pe <= '{default: '0};
        end else if (start_processing) begin
            operand_a_to_pe <= pe_operand_a_i;
            operand_b_to_pe <= pe_operand_b_i;
        end
    end

    // FSM for controlling the handshake
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= IDLE;
            latency_counter <= '0;
            pe_done_reg     <= 1'b0;
            pe_result_reg   <= '{default: '{default: '0}};
        end else begin
            current_state <= next_state;
            if (start_processing) begin
                latency_counter <= PIPELINE_LATENCY - 1;
            end else if (current_state == PROCESSING) begin
                latency_counter <= latency_counter - 1;
            end
        end

        if (current_state == PROCESSING && latency_counter == 1) begin
            pe_result_reg <= pe_result_from_pe;
            pe_done_reg <= 1'b1;
        end
    end

    always_comb begin
        next_state = current_state;
        pe_cmd_ready_o = 1'b0;

        case (current_state)
            IDLE: begin
                pe_cmd_ready_o = 1'b1;
                if (pe_cmd_valid_i) begin
                    next_state = PROCESSING;
                end
            end
            PROCESSING: begin
                if (pe_done_reg) begin
                    next_state = IDLE;
                end
            end
            default: begin
                next_state = IDLE;
            end
        endcase
    end

endmodule

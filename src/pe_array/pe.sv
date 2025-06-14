// src/pe_array/pe.sv
// Processing Element (PE) Module for Systolic Array

`include "../common/parameters.sv"
`include "../common/types.sv"

module pe (
    // Clock and Reset
    input  logic                    clk,
    input  logic                    rst_n,

    // Control Signals
    input  nmcu_types::pe_ctrl_t    pe_ctrl,

    // Data Inputs
    input  nmcu_types::data_t       input_north,     // From north PE
    input  nmcu_types::data_t       input_west,      // From west PE  
    input  nmcu_types::weight_t     weight_in,       // Weight input
    input  logic                    input_north_valid,
    input  logic                    input_west_valid,
    input  logic                    weight_valid,

    // Data Outputs
    output nmcu_types::data_t       output_south,    // To south PE
    output nmcu_types::data_t       output_east,     // To east PE
    output nmcu_types::result_t     result_out,      // Partial sum output
    output logic                    output_south_valid,
    output logic                    output_east_valid,
    output logic                    result_valid,

    // Status
    output logic                    pe_busy,
    output logic                    pe_error
);

    import nmcu_pkg::*;
    import nmcu_types::*;

    // ========================================================================
    // Internal Registers and Signals
    // ========================================================================

    // Weight storage register
    weight_t                weight_reg;
    logic                   weight_reg_valid;

    // Accumulator register
    result_t                accumulator;
    logic                   accumulator_valid;

    // Pipeline registers for data flow
    data_t                  north_reg [MAC_PIPELINE_STAGES-1:0];
    data_t                  west_reg [MAC_PIPELINE_STAGES-1:0];
    logic                   north_valid_reg [MAC_PIPELINE_STAGES-1:0];
    logic                   west_valid_reg [MAC_PIPELINE_STAGES-1:0];

    // MAC operation signals
    logic [DATA_WIDTH*2-1:0] mult_result;
    result_t                 mac_result;
    logic                    mac_valid;

    // Control pipeline registers
    pe_ctrl_t               ctrl_reg [MAC_PIPELINE_STAGES-1:0];

    // Error detection
    logic                   overflow_error;
    logic                   underflow_error;

    // ========================================================================
    // Weight Loading Logic
    // ========================================================================

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            weight_reg <= '0;
            weight_reg_valid <= 1'b0;
        end else begin
            if (pe_ctrl.weight_load_en && weight_valid) begin
                weight_reg <= weight_in;
                weight_reg_valid <= 1'b1;
            end
        end
    end

    // ========================================================================
    // Data Pipeline Registers
    // ========================================================================

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < MAC_PIPELINE_STAGES; i++) begin
                north_reg[i] <= '0;
                west_reg[i] <= '0;
                north_valid_reg[i] <= 1'b0;
                west_valid_reg[i] <= 1'b0;
                ctrl_reg[i] <= '0;
            end
        end else if (pe_ctrl.enable) begin
            // Pipeline stage 0 - Input
            north_reg[0] <= input_north;
            west_reg[0] <= input_west;
            north_valid_reg[0] <= input_north_valid;
            west_valid_reg[0] <= input_west_valid;
            ctrl_reg[0] <= pe_ctrl;

            // Pipeline stages 1 to MAC_PIPELINE_STAGES-1
            for (int i = 1; i < MAC_PIPELINE_STAGES; i++) begin
                north_reg[i] <= north_reg[i-1];
                west_reg[i] <= west_reg[i-1];
                north_valid_reg[i] <= north_valid_reg[i-1];
                west_valid_reg[i] <= west_valid_reg[i-1];
                ctrl_reg[i] <= ctrl_reg[i-1];
            end
        end
    end

    // ========================================================================
    // MAC (Multiply-Accumulate) Operation
    // ========================================================================

    // Multiplication stage
    always_comb begin
        mult_result = '0;
        if (ctrl_reg[1].op == PE_MAC || ctrl_reg[1].op == PE_MUL) begin
            mult_result = $signed(west_reg[1]) * $signed(weight_reg);
        end
    end

    // MAC result calculation
    always_comb begin
        mac_result = '0;
        mac_valid = 1'b0;

        case (ctrl_reg[2].op)
            PE_MAC: begin
                mac_result = $signed(mult_result) + $signed(accumulator);
                mac_valid = north_valid_reg[2] && west_valid_reg[2] && weight_reg_valid;
            end
            PE_MUL: begin
                mac_result = $signed(mult_result);
                mac_valid = west_valid_reg[2] && weight_reg_valid;
            end
            PE_ADD: begin
                mac_result = $signed(west_reg[2]) + $signed(accumulator);
                mac_valid = west_valid_reg[2];
            end
            default: begin
                mac_result = accumulator;
                mac_valid = 1'b0;
            end
        endcase
    end

    // ========================================================================
    // Accumulator Logic
    // ========================================================================

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            accumulator <= '0;
            accumulator_valid <= 1'b0;
        end else begin
            if (pe_ctrl.acc_clear) begin
                accumulator <= '0;
                accumulator_valid <= 1'b0;
            end else if (mac_valid && pe_ctrl.enable) begin
                accumulator <= mac_result;
                accumulator_valid <= 1'b1;
            end
        end
    end

    // ========================================================================
    // ReLU Activation (Optional)
    // ========================================================================

    result_t relu_result;
    always_comb begin
        if (ctrl_reg[MAC_PIPELINE_STAGES-1].op == PE_RELU) begin
            relu_result = (mac_result > 0) ? mac_result : '0;
        end else begin
            relu_result = mac_result;
        end
    end

    // ========================================================================
    // Output Logic
    // ========================================================================

    // Data flow outputs (systolic array)
    assign output_south = north_reg[MAC_PIPELINE_STAGES-1];
    assign output_east = west_reg[MAC_PIPELINE_STAGES-1];
    assign output_south_valid = north_valid_reg[MAC_PIPELINE_STAGES-1];
    assign output_east_valid = west_valid_reg[MAC_PIPELINE_STAGES-1];

    // Result output
    assign result_out = relu_result;
    assign result_valid = ctrl_reg[MAC_PIPELINE_STAGES-1].result_valid && accumulator_valid;

    // ========================================================================
    // Status and Error Detection
    // ========================================================================

    // Overflow detection
    always_comb begin
        overflow_error = 1'b0;
        if (mac_valid) begin
            // Check for overflow in MAC operation
            if (ctrl_reg[2].op == PE_MAC) begin
                logic [RESULT_WIDTH:0] temp_result;
                temp_result = $signed(mult_result) + $signed(accumulator);
                overflow_error = (temp_result[RESULT_WIDTH] != temp_result[RESULT_WIDTH-1]);
            end
        end
    end

    // Underflow detection (for ReLU)
    assign underflow_error = 1'b0; // Not critical for this design

    // PE busy signal
    logic pipeline_busy;
    always_comb begin
        pipeline_busy = 1'b0;
        for (int i = 0; i < MAC_PIPELINE_STAGES; i++) begin
            pipeline_busy |= (north_valid_reg[i] || west_valid_reg[i]);
        end
    end

    assign pe_busy = pipeline_busy || accumulator_valid;
    assign pe_error = overflow_error || underflow_error;

    // ========================================================================
    // Assertions for Verification
    // ========================================================================

    `ifdef ENABLE_ASSERTIONS
        // Weight should be loaded before MAC operations
        property weight_loaded_before_mac;
            @(posedge clk) disable iff (!rst_n)
            (pe_ctrl.op == PE_MAC) |-> weight_reg_valid;
        endproperty
        assert property (weight_loaded_before_mac) 
            else $error("PE: MAC operation attempted without valid weight");

        // Valid inputs required for valid operations
        property valid_inputs_for_mac;
            @(posedge clk) disable iff (!rst_n)
            (pe_ctrl.op == PE_MAC && pe_ctrl.enable) |-> 
            (input_north_valid && input_west_valid && weight_valid);
        endproperty
        assert property (valid_inputs_for_mac)
            else $error("PE: Invalid inputs for MAC operation");

        // Accumulator clear should reset accumulator
        property accumulator_clear_reset;
            @(posedge clk) disable iff (!rst_n)
            pe_ctrl.acc_clear |=> (accumulator == '0);
        endproperty
        assert property (accumulator_clear_reset)
            else $error("PE: Accumulator not cleared properly");
    `endif

    // ========================================================================
    // Coverage Points for Verification
    // ========================================================================

    `ifdef ENABLE_COVERAGE
        covergroup pe_operations @(posedge clk);
            op_type: coverpoint pe_ctrl.op {
                bins nop = {PE_NOP};
                bins mac = {PE_MAC};
                bins add = {PE_ADD};
                bins mul = {PE_MUL};
                bins relu = {PE_RELU};
                bins load_weight = {PE_LOAD_WEIGHT};
                bins clear_acc = {PE_CLEAR_ACC};
            }

            data_valid: coverpoint {input_north_valid, input_west_valid, weight_valid} {
                bins all_valid = {3'b111};
                bins partial_valid = {3'b001, 3'b010, 3'b011, 3'b100, 3'b101, 3'b110};
                bins none_valid = {3'b000};
            }

            cross op_type, data_valid;
        endgroup

        pe_operations pe_ops_cg = new();
    `endif

endmodule

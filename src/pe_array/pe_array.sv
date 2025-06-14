// src/pe_array/pe_array.sv
// Processing Element Array Module (Systolic Array)

`include "../common/parameters.sv"
`include "../common/types.sv"

module pe_array (
    // Clock and Reset
    input  logic                    clk,
    input  logic                    rst_n,
    
    // Control Interface
    input  nmcu_types::pe_ctrl_t    global_pe_ctrl,
    input  logic                    array_enable,
    input  logic                    weight_load_enable,
    input  logic                    acc_clear_all,
    
    // Weight Loading Interface
    input  nmcu_types::weight_t     weight_data [PE_ARRAY_SIZE_Y-1:0][PE_ARRAY_SIZE_X-1:0],
    input  logic                    weight_valid [PE_ARRAY_SIZE_Y-1:0][PE_ARRAY_SIZE_X-1:0],
    
    // Input Data Interface (Systolic inputs)
    input  nmcu_types::data_t       input_north [PE_ARRAY_SIZE_X-1:0],  // Top row inputs
    input  nmcu_types::data_t       input_west [PE_ARRAY_SIZE_Y-1:0],   // Left column inputs
    input  logic                    input_north_valid [PE_ARRAY_SIZE_X-1:0],
    input  logic                    input_west_valid [PE_ARRAY_SIZE_Y-1:0],
    
    // Output Data Interface
    output nmcu_types::data_t       output_south [PE_ARRAY_SIZE_X-1:0], // Bottom row outputs
    output nmcu_types::data_t       output_east [PE_ARRAY_SIZE_Y-1:0],  // Right column outputs
    output logic                    output_south_valid [PE_ARRAY_SIZE_X-1:0],
    output logic                    output_east_valid [PE_ARRAY_SIZE_Y-1:0],
    
    // Result Interface
    output nmcu_types::result_t     results [PE_ARRAY_SIZE_Y-1:0][PE_ARRAY_SIZE_X-1:0],
    output logic                    results_valid [PE_ARRAY_SIZE_Y-1:0][PE_ARRAY_SIZE_X-1:0],
    
    // Status Interface
    output logic                    array_busy,
    output logic                    array_error,
    output logic [PE_TOTAL_NUM-1:0] pe_busy_vector,
    output logic [PE_TOTAL_NUM-1:0] pe_error_vector
);

    import nmcu_pkg::*;
    import nmcu_types::*;

    // ========================================================================
    // Internal Signals for Systolic Array Connections
    // ========================================================================
    
    // Internal data flow signals (north-south and west-east)
    data_t          internal_north_south [PE_ARRAY_SIZE_Y:0][PE_ARRAY_SIZE_X-1:0];
    data_t          internal_west_east [PE_ARRAY_SIZE_Y-1:0][PE_ARRAY_SIZE_X:0];
    logic           internal_north_south_valid [PE_ARRAY_SIZE_Y:0][PE_ARRAY_SIZE_X-1:0];
    logic           internal_west_east_valid [PE_ARRAY_SIZE_Y-1:0][PE_ARRAY_SIZE_X:0];
    
    // PE control signals
    pe_ctrl_t       pe_controls [PE_ARRAY_SIZE_Y-1:0][PE_ARRAY_SIZE_X-1:0];
    
    // Individual PE status signals
    logic           pe_busy_array [PE_ARRAY_SIZE_Y-1:0][PE_ARRAY_SIZE_X-1:0];
    logic           pe_error_array [PE_ARRAY_SIZE_Y-1:0][PE_ARRAY_SIZE_X-1:0];
    
    // ========================================================================
    // Input Connection Assignment (Top and Left Boundaries)
    // ========================================================================
    
    // Connect top row inputs (north boundary)
    generate
        for (genvar x = 0; x < PE_ARRAY_SIZE_X; x++) begin : gen_north_inputs
            assign internal_north_south[0][x] = input_north[x];
            assign internal_north_south_valid[0][x] = input_north_valid[x];
        end
    endgenerate
    
    // Connect left column inputs (west boundary)
    generate
        for (genvar y = 0; y < PE_ARRAY_SIZE_Y; y++) begin : gen_west_inputs
            assign internal_west_east[y][0] = input_west[y];
            assign internal_west_east_valid[y][0] = input_west_valid[y];
        end
    endgenerate
    
    // ========================================================================
    // PE Control Logic
    // ========================================================================
    
    always_comb begin
        for (int y = 0; y < PE_ARRAY_SIZE_Y; y++) begin
            for (int x = 0; x < PE_ARRAY_SIZE_X; x++) begin
                pe_controls[y][x] = global_pe_ctrl;
                pe_controls[y][x].enable = array_enable;
                pe_controls[y][x].weight_load_en = weight_load_enable;
                pe_controls[y][x].acc_clear = acc_clear_all;
            end
        end
    end
    
    // ========================================================================
    // PE Array Instantiation
    // ========================================================================
    
    generate
        for (genvar y = 0; y < PE_ARRAY_SIZE_Y; y++) begin : gen_pe_rows
            for (genvar x = 0; x < PE_ARRAY_SIZE_X; x++) begin : gen_pe_cols
                
                pe pe_inst (
                    // Clock and Reset
                    .clk                    (clk),
                    .rst_n                  (rst_n),
                    
                    // Control
                    .pe_ctrl                (pe_controls[y][x]),
                    
                    // Data Inputs
                    .input_north            (internal_north_south[y][x]),
                    .input_west             (internal_west_east[y][x]),
                    .weight_in              (weight_data[y][x]),
                    .input_north_valid      (internal_north_south_valid[y][x]),
                    .input_west_valid       (internal_west_east_valid[y][x]),
                    .weight_valid           (weight_valid[y][x]),
                    
                    // Data Outputs
                    .output_south           (internal_north_south[y+1][x]),
                    .output_east            (internal_west_east[y][x+1]),
                    .output_south_valid     (internal_north_south_valid[y+1][x]),
                    .output_east_valid      (internal_west_east_valid[y][x+1]),
                    .result_out             (results[y][x]),
                    .result_valid           (results_valid[y][x]),
                    
                    // Status
                    .pe_busy                (pe_busy_array[y][x]),
                    .pe_error               (pe_error_array[y][x])
                );
                
            end
        end
    endgenerate
    
    // ========================================================================
    // Output Connection Assignment (Bottom and Right Boundaries)
    // ========================================================================
    
    // Connect bottom row outputs (south boundary)
    generate
        for (genvar x = 0; x < PE_ARRAY_SIZE_X; x++) begin : gen_south_outputs
            assign output_south[x] = internal_north_south[PE_ARRAY_SIZE_Y][x];
            assign output_south_valid[x] = internal_north_south_valid[PE_ARRAY_SIZE_Y][x];
        end
    endgenerate
    
    // Connect right column outputs (east boundary)
    generate
        for (genvar y = 0; y < PE_ARRAY_SIZE_Y; y++) begin : gen_east_outputs
            assign output_east[y] = internal_west_east[y][PE_ARRAY_SIZE_X];
            assign output_east_valid[y] = internal_west_east_valid[y][PE_ARRAY_SIZE_X];
        end
    endgenerate
    
    // ========================================================================
    // Status Signal Generation
    // ========================================================================
    
    // Convert 2D arrays to 1D vectors for external interface
    generate
        for (genvar y = 0; y < PE_ARRAY_SIZE_Y; y++) begin : gen_status_rows
            for (genvar x = 0; x < PE_ARRAY_SIZE_X; x++) begin : gen_status_cols
                localparam int pe_index = y * PE_ARRAY_SIZE_X + x;
                assign pe_busy_vector[pe_index] = pe_busy_array[y][x];
                assign pe_error_vector[pe_index] = pe_error_array[y][x];
            end
        end
    endgenerate
    
    // Overall array status
    assign array_busy = |pe_busy_vector;
    assign array_error = |pe_error_vector;
    
    // ========================================================================
    // Debug and Monitoring Logic
    // ========================================================================
    
    // Performance counters
    logic [31:0] mac_operations_count;
    logic [31:0] weight_loads_count;
    logic [31:0] results_generated_count;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mac_operations_count <= '0;
            weight_loads_count <= '0;
            results_generated_count <= '0;
        end else begin
            // Count MAC operations
            if (array_enable && global_pe_ctrl.op == PE_MAC) begin
                mac_operations_count <= mac_operations_count + PE_TOTAL_NUM;
            end
            
            // Count weight loads
            if (weight_load_enable) begin
                logic [7:0] weight_load_count_cycle;
                weight_load_count_cycle = '0;
                for (int y = 0; y < PE_ARRAY_SIZE_Y; y++) begin
                    for (int x = 0; x < PE_ARRAY_SIZE_X; x++) begin
                        if (weight_valid[y][x]) begin
                            weight_load_count_cycle++;
                        end
                    end
                end
                weight_loads_count <= weight_loads_count + weight_load_count_cycle;
            end
            
            // Count results generated
            logic [7:0] results_count_cycle;
            results_count_cycle = '0;
            for (int y = 0; y < PE_ARRAY_SIZE_Y; y++) begin
                for (int x = 0; x < PE_ARRAY_SIZE_X; x++) begin
                    if (results_valid[y][x]) begin
                        results_count_cycle++;
                    end
                end
            end
            results_generated_count <= results_generated_count + results_count_cycle;
        end
    end
    
    // ========================================================================
    // Assertions for Verification
    // ========================================================================
    
    `ifdef ENABLE_ASSERTIONS
        // Array should not be enabled when in reset
        property array_disabled_in_reset;
            @(posedge clk) !rst_n |-> !array_enable;
        endproperty
        assert property (array_disabled_in_reset)
            else $error("PE Array: Array enabled during reset");
        
        // Weight loading should precede computation
        property weight_before_compute;
            @(posedge clk) disable iff (!rst_n)
            (array_enable && global_pe_ctrl.op == PE_MAC) |-> 
            $past(weight_load_enable, 1);
        endproperty
        assert property (weight_before_compute)
            else $warning("PE Array: MAC operation without prior weight loading");
        
        // Results should be valid only when array is computing
        property results_valid_when_computing;
            @(posedge clk) disable iff (!rst_n)
            (|results_valid) |-> array_busy;
        endproperty
        assert property (results_valid_when_computing)
            else $error("PE Array: Results valid when array not busy");
        
        // No simultaneous weight load and compute
        property no_simultaneous_weight_compute;
            @(posedge clk) disable iff (!rst_n)
            !(weight_load_enable && array_enable && global_pe_ctrl.op == PE_MAC);
        endproperty
        assert property (no_simultaneous_weight_compute)
            else $error("PE Array: Simultaneous weight load and compute");
    `endif
    
    // ========================================================================
    // Coverage Points for Verification
    // ========================================================================
    
    `ifdef ENABLE_COVERAGE
        covergroup pe_array_operations @(posedge clk);
            array_state: coverpoint {array_enable, weight_load_enable, acc_clear_all} {
                bins idle = {3'b000};
                bins weight_load = {3'b010};
                bins compute = {3'b100};
                bins clear = {3'b001};
                bins weight_and_clear = {3'b011};
            }
            
            operation_type: coverpoint global_pe_ctrl.op {
                bins mac_op = {PE_MAC};
                bins mul_op = {PE_MUL};
                bins add_op = {PE_ADD};
                bins relu_op = {PE_RELU};
            }
            
            busy_level: coverpoint $countones(pe_busy_vector) {
                bins none_busy = {0};
                bins quarter_busy = {[1:PE_TOTAL_NUM/4]};
                bins half_busy = {[PE_TOTAL_NUM/4+1:PE_TOTAL_NUM/2]};
                bins most_busy = {[PE_TOTAL_NUM/2+1:PE_TOTAL_NUM*3/4]};
                bins all_busy = {[PE_TOTAL_NUM*3/4+1:PE_TOTAL_NUM]};
            }
            
            cross array_state, operation_type;
        endgroup
        
        pe_array_operations pe_array_ops_cg = new();
        
        // Data flow coverage
        covergroup data_flow_coverage @(posedge clk);
            north_inputs_valid: coverpoint $countones(input_north_valid) {
                bins none = {0};
                bins partial = {[1:PE_ARRAY_SIZE_X-1]};
                bins all = {PE_ARRAY_SIZE_X};
            }
            
            west_inputs_valid: coverpoint $countones(input_west_valid) {
                bins none = {0};
                bins partial = {[1:PE_ARRAY_SIZE_Y-1]};
                bins all = {PE_ARRAY_SIZE_Y};
            }
            
            cross north_inputs_valid, west_inputs_valid;
        endgroup
        
        data_flow_coverage data_flow_cg = new();
    `endif

endmodule

// pe_interface.sv
//PE Array Interface and Data Dispatcher
`include "parameters.sv"
`include "types.sv"

module pe_interface (
    input  logic                    clk,
    input  logic                    rst_n,
    
    // Input Data Interface
    input  pe_data_t               pe_data,
    input  logic                   pe_data_valid,
    output logic                   pe_data_ready,
    
    // Output Result Interface
    output pe_result_t             pe_result,
    output logic                   pe_result_valid,
    input  logic                   pe_result_ready
);

    // PE Array instantiation
    logic [PE_ARRAY_SIZE-1:0][DATA_WIDTH-1:0] pe_input_a;
    logic [PE_ARRAY_SIZE-1:0][DATA_WIDTH-1:0] pe_input_b;
    logic [PE_ARRAY_SIZE-1:0]                 pe_input_valid;
    logic [PE_ARRAY_SIZE-1:0]                 pe_input_ready;
    
    logic [PE_ARRAY_SIZE-1:0][DATA_WIDTH-1:0] pe_output;
    logic [PE_ARRAY_SIZE-1:0]                 pe_output_valid;
    logic [PE_ARRAY_SIZE-1:0]                 pe_output_ready;
    
    // Data dispatcher state machine
    typedef enum logic [2:0] {
        IDLE,
        DISPATCH_DATA,
        WAIT_COMPUTE,
        COLLECT_RESULTS,
        OUTPUT_RESULT
    } dispatch_state_t;
    
    dispatch_state_t               state, next_state;
    
    // Input data buffering
    pe_data_t                      data_buffer;
    logic                          data_buffer_valid;
    
    // Result collection
    pe_result_t                    result_buffer;
    logic                          result_buffer_valid;
    logic [PE_ARRAY_SIZE-1:0]      result_collected;
    
    // Dispatch control
    logic [$clog2(PE_ARRAY_SIZE):0] dispatch_count;
    logic [$clog2(PE_ARRAY_SIZE):0] collect_count;
    
    // State machine
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
        end else begin
            state <= next_state;
        end
    end
    
    always_comb begin
        next_state = state;
        case (state)
            IDLE: begin
                if (pe_data_valid) begin
                    next_state = DISPATCH_DATA;
                end
            end
            
            DISPATCH_DATA: begin
                if (dispatch_count == PE_ARRAY_SIZE) begin
                    next_state = WAIT_COMPUTE;
                end
            end
            
            WAIT_COMPUTE: begin
                if (|pe_output_valid) begin
                    next_state = COLLECT_RESULTS;
                end
            end
            
            COLLECT_RESULTS: begin
                if (collect_count == PE_ARRAY_SIZE) begin
                    next_state = OUTPUT_RESULT;
                end
            end
            
            OUTPUT_RESULT: begin
                if (pe_result_ready) begin
                    next_state = IDLE;
                end
            end
        endcase
    end
    
    // Input data buffering
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_buffer <= '0;
            data_buffer_valid <= 1'b0;
        end else begin
            if (state == IDLE && pe_data_valid) begin
                data_buffer <= pe_data;
                data_buffer_valid <= 1'b1;
            end else if (state == OUTPUT_RESULT && pe_result_ready) begin
                data_buffer_valid <= 1'b0;
            end
        end
    end
    
    // Data dispatch logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dispatch_count <= '0;
        end else begin
            if (state == DISPATCH_DATA) begin
                // Simple broadcast dispatch - send same data to all PEs
                // In a real implementation, this would intelligently partition data
                if (dispatch_count < PE_ARRAY_SIZE) begin
                    dispatch_count <= dispatch_count + 1;
                end
            end else if (state == IDLE) begin
                dispatch_count <= '0;
            end
        end
    end
    
    // PE Array inputs
    always_comb begin
        for (int i = 0; i < PE_ARRAY_SIZE; i++) begin
            pe_input_a[i] = data_buffer.data_a;
            pe_input_b[i] = data_buffer.data_b;
            pe_input_valid[i] = (state == DISPATCH_DATA) && (i < dispatch_count);
        end
    end
    
    // Result collection logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            collect_count <= '0;
            result_collected <= '0;
        end else begin
            if (state == COLLECT_RESULTS) begin
                for (int i = 0; i < PE_ARRAY_SIZE; i++) begin
                    if (pe_output_valid[i] && !result_collected[i]) begin
                        result_collected[i] <= 1'b1;
                        collect_count <= collect_count + 1;
                    end
                end
            end else if (state == IDLE) begin
                collect_count <= '0;
                result_collected <= '0;
            end
        end
    end
    
    // Result aggregation
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            result_buffer <= '0;
            result_buffer_valid <= 1'b0;
        end else begin
            if (state == COLLECT_RESULTS && collect_count == PE_ARRAY_SIZE) begin
                // Simple aggregation - sum all PE outputs
                // In real implementation, this would depend on operation type
                result_buffer.result_data <= '0;
                for (int i = 0; i < PE_ARRAY_SIZE; i++) begin
                    result_buffer.result_data <= result_buffer.result_data + pe_output[i];
                end
                result_buffer.trans_id <= data_buffer.trans_id;
                result_buffer.op_type <= data_buffer.op_type;
                result_buffer_valid <= 1'b1;
            end else if (state == OUTPUT_RESULT && pe_result_ready) begin
                result_buffer_valid <= 1'b0;
            end
        end
    end
    
    // PE Array instantiation
    pe_array u_pe_array (
        .clk                       (clk),
        .rst_n                     (rst_n),
        .pe_input_a                (pe_input_a),
        .pe_input_b                (pe_input_b),
        .pe_input_valid            (pe_input_valid),
        .pe_input_ready            (pe_input_ready),
        .pe_output                 (pe_output),
        .pe_output_valid           (pe_output_valid),
        .pe_output_ready           (pe_output_ready)
    );
    
    // Interface assignments
    assign pe_data_ready = (state == IDLE);
    assign pe_result = result_buffer;
    assign pe_result_valid = result_buffer_valid && (state == OUTPUT_RESULT);
    
    // PE output ready - ready to accept results when collecting
    assign pe_output_ready = {PE_ARRAY_SIZE{state == COLLECT_RESULTS}};

endmodule
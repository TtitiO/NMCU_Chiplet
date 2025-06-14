// control_unit.sv
// Control Unit and Instruction Decoder
`include "parameters.sv"
`include "types.sv"

module control_unit (
    input  logic                    clk,
    input  logic                    rst_n,
    
    // Command Interface from UCIe Adapter
    input  ctrl_cmd_t              ctrl_cmd,
    input  logic                   ctrl_cmd_valid,
    output logic                   ctrl_cmd_ready,
    
    // Cache Request Interface
    output cache_req_t             cache_req,
    output logic                   cache_req_valid,
    input  logic                   cache_req_ready,
    
    // Cache Response Interface
    input  cache_resp_t            cache_resp,
    input  logic                   cache_resp_valid,
    output logic                   cache_resp_ready,
    
    // PE Data Interface
    output pe_data_t               pe_data,
    output logic                   pe_data_valid,
    input  logic                   pe_data_ready,
    
    // Status and Control
    output logic [31:0]            status_reg,
    output logic                   ready,
    output logic                   error
);

    // State machine for control flow
    typedef enum logic [3:0] {
        IDLE,
        DECODE_CMD,
        FETCH_OPERAND_A,
        FETCH_OPERAND_B,
        WAIT_CACHE_A,
        WAIT_CACHE_B,
        DISPATCH_COMPUTE,
        WAIT_COMPUTE,
        ERROR_STATE
    } ctrl_state_t;
    
    ctrl_state_t                   state, next_state;
    
    // Command buffer and processing
    ctrl_cmd_t                     cmd_reg;
    logic                          cmd_valid_reg;
    
    // Operand fetch state
    logic                          operand_a_ready;
    logic                          operand_b_ready;
    logic [DATA_WIDTH-1:0]         operand_a_data;
    logic [DATA_WIDTH-1:0]         operand_b_data;
    
    // Transaction tracking
    logic [TRANS_ID_WIDTH-1:0]     current_trans_id;
    logic [31:0]                   cycle_counter;
    
    // Error tracking
    logic                          timeout_error;
    logic                          cache_error;
    
    // Performance counters
    logic [31:0]                   cmd_count;
    logic [31:0]                   compute_cycles;
    
    // State machine
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            cycle_counter <= '0;
        end else begin
            state <= next_state;
            cycle_counter <= cycle_counter + 1;
        end
    end
    
    always_comb begin
        next_state = state;
        case (state)
            IDLE: begin
                if (ctrl_cmd_valid) begin
                    next_state = DECODE_CMD;
                end
            end
            
            DECODE_CMD: begin
                case (cmd_reg.cmd_type)
                    CMD_MATMUL, CMD_CONV: begin
                        next_state = FETCH_OPERAND_A;
                    end
                    CMD_NOP: begin
                        next_state = IDLE;
                    end
                    default: begin
                        next_state = ERROR_STATE;
                    end
                endcase
            end
            
            FETCH_OPERAND_A: begin
                if (cache_req_ready) begin
                    next_state = WAIT_CACHE_A;
                end
            end
            
            WAIT_CACHE_A: begin
                if (cache_resp_valid && cache_resp.hit) begin
                    next_state = FETCH_OPERAND_B;
                end else if (cache_resp_valid && !cache_resp.hit) begin
                    next_state = ERROR_STATE;
                end else if (timeout_error) begin
                    next_state = ERROR_STATE;
                end
            end
            
            FETCH_OPERAND_B: begin
                if (cache_req_ready) begin
                    next_state = WAIT_CACHE_B;
                end
            end
            
            WAIT_CACHE_B: begin
                if (cache_resp_valid && cache_resp.hit) begin
                    next_state = DISPATCH_COMPUTE;
                end else if (cache_resp_valid && !cache_resp.hit) begin
                    next_state = ERROR_STATE;
                end else if (timeout_error) begin
                    next_state = ERROR_STATE;
                end
            end
            
            DISPATCH_COMPUTE: begin
                if (pe_data_ready) begin
                    next_state = WAIT_COMPUTE;
                end
            end
            
            WAIT_COMPUTE: begin
                // Simplified - assume PE completes in fixed cycles
                // In real implementation, would wait for PE completion signal
                if (cycle_counter[7:0] == 8'hFF) begin // Placeholder timing
                    next_state = IDLE;
                end
            end
            
            ERROR_STATE: begin
                next_state = IDLE; // Reset after error handling
            end
        endcase
    end
    
    // Command buffer
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cmd_reg <= '0;
            cmd_valid_reg <= 1'b0;
            current_trans_id <= '0;
        end else begin
            if (state == IDLE && ctrl_cmd_valid) begin
                cmd_reg <= ctrl_cmd;
                cmd_valid_reg <= 1'b1;
                current_trans_id <= ctrl_cmd.trans_id;
            end else if (state == WAIT_COMPUTE && next_state == IDLE) begin
                cmd_valid_reg <= 1'b0;
            end
        end
    end
    
    // Operand data storage
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            operand_a_data <= '0;
            operand_b_data <= '0;
            operand_a_ready <= 1'b0;
            operand_b_ready <= 1'b0;
        end else begin
            case (state)
                WAIT_CACHE_A: begin
                    if (cache_resp_valid && cache_resp.hit) begin
                        operand_a_data <= cache_resp.data;
                        operand_a_ready <= 1'b1;
                    end
                end
                WAIT_CACHE_B: begin
                    if (cache_resp_valid && cache_resp.hit) begin
                        operand_b_data <= cache_resp.data;
                        operand_b_ready <= 1'b1;
                    end
                end
                IDLE: begin
                    operand_a_ready <= 1'b0;
                    operand_b_ready <= 1'b0;
                end
            endcase
        end
    end
    
    // Cache request generation
    always_comb begin
        cache_req = '0;
        cache_req_valid = 1'b0;
        
        case (state)
            FETCH_OPERAND_A: begin
                cache_req.addr = cmd_reg.addr_a;
                cache_req.req_type = CACHE_READ;
                cache_req.trans_id = current_trans_id;
                cache_req_valid = 1'b1;
            end
            FETCH_OPERAND_B: begin
                cache_req.addr = cmd_reg.addr_b;
                cache_req.req_type = CACHE_READ;
                cache_req.trans_id = current_trans_id;
                cache_req_valid = 1'b1;
            end
        endcase
    end
    
    // PE data dispatch
    always_comb begin
        pe_data = '0;
        pe_data_valid = 1'b0;
        
        if (state == DISPATCH_COMPUTE && operand_a_ready && operand_b_ready) begin
            pe_data.op_type = (cmd_reg.cmd_type == CMD_MATMUL) ? PE_MATMUL : PE_CONV;
            pe_data.data_a = operand_a_data;
            pe_data.data_b = operand_b_data;
            pe_data.trans_id = current_trans_id;
            pe_data_valid = 1'b1;
        end
    end
    
    // Timeout detection
    logic [15:0] timeout_counter;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            timeout_counter <= '0;
            timeout_error <= 1'b0;
        end else begin
            if (state == WAIT_CACHE_A || state == WAIT_CACHE_B) begin
                timeout_counter <= timeout_counter + 1;
                timeout_error <= (timeout_counter > CACHE_TIMEOUT_CYCLES);
            end else begin
                timeout_counter <= '0;
                timeout_error <= 1'b0;
            end
        end
    end
    
    // Performance counters
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cmd_count <= '0;
            compute_cycles <= '0;
        end else begin
            if (state == DECODE_CMD && next_state != ERROR_STATE) begin
                cmd_count <= cmd_count + 1;
            end
            if (state == WAIT_COMPUTE) begin
                compute_cycles <= compute_cycles + 1;
            end
        end
    end
    
    // Interface assignments
    assign ctrl_cmd_ready = (state == IDLE);
    assign cache_resp_ready = (state == WAIT_CACHE_A || state == WAIT_CACHE_B);
    
    // Status and control outputs
    assign ready = (state == IDLE);
    assign error = (state == ERROR_STATE) || timeout_error;
    
    always_comb begin
        status_reg = '0;
        status_reg[3:0] = state;
        status_reg[4] = ready;
        status_reg[5] = error;
        status_reg[6] = operand_a_ready;
        status_reg[7] = operand_b_ready;
        status_reg[23:8] = cmd_count[15:0];
        status_reg[31:24] = current_trans_id;
    end

endmodule
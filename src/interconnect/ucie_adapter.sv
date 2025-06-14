// ucie_adapter.sv 
// UCIe Interconnect Adapter
`include "parameters.sv"
`include "types.sv"

module ucie_adapter (
    input  logic                    clk,
    input  logic                    rst_n,
    
    // UCIe Interface
    ucie_interface.slave           ucie_if,
    
    // Control Command Interface
    output ctrl_cmd_t              ctrl_cmd,
    output logic                   ctrl_cmd_valid,
    input  logic                   ctrl_cmd_ready,
    
    // Result Interface
    input  pe_result_t             pe_result,
    input  logic                   pe_result_valid,
    output logic                   pe_result_ready
);

    // Internal FIFOs for command and response
    localparam CMD_FIFO_DEPTH = 8;
    localparam RESP_FIFO_DEPTH = 8;
    
    // Command FIFO signals
    logic                          cmd_fifo_push;
    logic                          cmd_fifo_pop;
    logic                          cmd_fifo_full;
    logic                          cmd_fifo_empty;
    ctrl_cmd_t                     cmd_fifo_data_in;
    ctrl_cmd_t                     cmd_fifo_data_out;
    
    // Response FIFO signals
    logic                          resp_fifo_push;
    logic                          resp_fifo_pop;
    logic                          resp_fifo_full;
    logic                          resp_fifo_empty;
    pe_result_t                    resp_fifo_data_in;
    pe_result_t                    resp_fifo_data_out;
    
    // State machine for UCIe protocol handling
    typedef enum logic [2:0] {
        IDLE,
        RECV_HEADER,
        RECV_PAYLOAD,
        SEND_RESPONSE,
        ERROR
    } ucie_state_t;
    
    ucie_state_t                   state, next_state;
    
    // Packet parsing
    logic [31:0]                   header_reg;
    logic [2:0]                    payload_count;
    logic [2:0]                    payload_expected;
    
    // UCIe packet format (simplified)
    // Header: [31:24] - packet type, [23:16] - length, [15:0] - transaction ID
    // Payload: data based on packet type
    
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
                if (ucie_if.valid && ucie_if.ready) begin
                    next_state = RECV_HEADER;
                end
            end
            RECV_HEADER: begin
                if (ucie_if.valid && ucie_if.ready) begin
                    if (payload_expected > 0) begin
                        next_state = RECV_PAYLOAD;
                    end else begin
                        next_state = IDLE;
                    end
                end
            end
            RECV_PAYLOAD: begin
                if (ucie_if.valid && ucie_if.ready && payload_count == payload_expected) begin
                    next_state = IDLE;
                end
            end
            SEND_RESPONSE: begin
                if (ucie_if.valid && ucie_if.ready) begin
                    next_state = IDLE;
                end
            end
            ERROR: begin
                next_state = IDLE;
            end
        endcase
    end
    
    // Header and payload processing
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            header_reg <= '0;
            payload_count <= '0;
            payload_expected <= '0;
        end else begin
            case (state)
                RECV_HEADER: begin
                    if (ucie_if.valid && ucie_if.ready) begin
                        header_reg <= ucie_if.data;
                        payload_expected <= ucie_if.data[18:16]; // Extract payload length
                        payload_count <= '0;
                    end
                end
                RECV_PAYLOAD: begin
                    if (ucie_if.valid && ucie_if.ready) begin
                        payload_count <= payload_count + 1;
                    end
                end
                IDLE: begin
                    payload_count <= '0;
                    payload_expected <= '0;
                end
            endcase
        end
    end
    
    // Command FIFO - stores incoming commands
    sync_fifo #(
        .DATA_WIDTH($bits(ctrl_cmd_t)),
        .DEPTH(CMD_FIFO_DEPTH)
    ) u_cmd_fifo (
        .clk(clk),
        .rst_n(rst_n),
        .push(cmd_fifo_push),
        .pop(cmd_fifo_pop),
        .data_in(cmd_fifo_data_in),
        .data_out(cmd_fifo_data_out),
        .full(cmd_fifo_full),
        .empty(cmd_fifo_empty)
    );
    
    // Response FIFO - stores outgoing responses
    sync_fifo #(
        .DATA_WIDTH($bits(pe_result_t)),
        .DEPTH(RESP_FIFO_DEPTH)
    ) u_resp_fifo (
        .clk(clk),
        .rst_n(rst_n),
        .push(resp_fifo_push),
        .pop(resp_fifo_pop),
        .data_in(resp_fifo_data_in),
        .data_out(resp_fifo_data_out),
        .full(resp_fifo_full),
        .empty(resp_fifo_empty)
    );
    
    // Command processing - convert UCIe packets to internal commands
    always_comb begin
        cmd_fifo_push = 1'b0;
        cmd_fifo_data_in = '0;
        
        if (state == RECV_PAYLOAD && payload_count == payload_expected && 
            ucie_if.valid && !cmd_fifo_full) begin
            cmd_fifo_push = 1'b1;
            
            // Parse packet type and create command
            case (header_reg[31:24])
                8'h01: begin // Matrix multiplication command
                    cmd_fifo_data_in.cmd_type = CMD_MATMUL;
                    cmd_fifo_data_in.addr_a = header_reg[23:0];
                    cmd_fifo_data_in.addr_b = ucie_if.data;
                    cmd_fifo_data_in.trans_id = header_reg[15:0];
                end
                8'h02: begin // Convolution command
                    cmd_fifo_data_in.cmd_type = CMD_CONV;
                    cmd_fifo_data_in.addr_a = header_reg[23:0];
                    cmd_fifo_data_in.addr_b = ucie_if.data;
                    cmd_fifo_data_in.trans_id = header_reg[15:0];
                end
                default: begin
                    cmd_fifo_data_in.cmd_type = CMD_NOP;
                end
            endcase
        end
    end
    
    // Output command interface
    assign ctrl_cmd = cmd_fifo_data_out;
    assign ctrl_cmd_valid = !cmd_fifo_empty;
    assign cmd_fifo_pop = ctrl_cmd_valid && ctrl_cmd_ready;
    
    // Response handling
    assign resp_fifo_push = pe_result_valid && !resp_fifo_full;
    assign resp_fifo_data_in = pe_result;
    assign pe_result_ready = !resp_fifo_full;
    
    // UCIe interface response
    logic sending_response;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sending_response <= 1'b0;
        end else begin
            if (!resp_fifo_empty && !sending_response) begin
                sending_response <= 1'b1;
            end else if (sending_response && ucie_if.valid && ucie_if.ready) begin
                sending_response <= 1'b0;
            end
        end
    end
    
    assign resp_fifo_pop = sending_response && ucie_if.ready;
    
    // UCIe interface assignments
    assign ucie_if.ready = (state == RECV_HEADER || state == RECV_PAYLOAD) && !cmd_fifo_full;
    assign ucie_if.valid = sending_response;
    assign ucie_if.data = sending_response ? resp_fifo_data_out.result_data : '0;

endmodule

// Simple synchronous FIFO for internal buffering
module sync_fifo #(
    parameter DATA_WIDTH = 32,
    parameter DEPTH = 8,
    parameter ADDR_WIDTH = $clog2(DEPTH)
) (
    input  logic                    clk,
    input  logic                    rst_n,
    input  logic                    push,
    input  logic                    pop,
    input  logic [DATA_WIDTH-1:0]   data_in,
    output logic [DATA_WIDTH-1:0]   data_out,
    output logic                    full,
    output logic                    empty
);

    logic [DATA_WIDTH-1:0]         mem [0:DEPTH-1];
    logic [ADDR_WIDTH:0]           wr_ptr, rd_ptr;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= '0;
            rd_ptr <= '0;
        end else begin
            if (push && !full) begin
                wr_ptr <= wr_ptr + 1;
            end
            if (pop && !empty) begin
                rd_ptr <= rd_ptr + 1;
            end
        end
    end
    
    always_ff @(posedge clk) begin
        if (push && !full) begin
            mem[wr_ptr[ADDR_WIDTH-1:0]] <= data_in;
        end
    end
    
    assign data_out = mem[rd_ptr[ADDR_WIDTH-1:0]];
    assign full = (wr_ptr[ADDR_WIDTH] != rd_ptr[ADDR_WIDTH]) && 
                  (wr_ptr[ADDR_WIDTH-1:0] == rd_ptr[ADDR_WIDTH-1:0]);
    assign empty = (wr_ptr == rd_ptr);

endmodule
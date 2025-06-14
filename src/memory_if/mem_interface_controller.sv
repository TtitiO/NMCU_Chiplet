// mem_interface_controller.sv
// Memory Interface Controller
`include "parameters.sv"
`include "types.sv"

module mem_interface_controller (
    input  logic                    clk,
    input  logic                    rst_n,
    
    // Cache side interface
    mem_interface.slave            cache_if,
    
    // External memory interface (HBM/DDR/SRAM)
    output logic                   mem_clk,
    output logic                   mem_rst_n,
    output logic                   mem_valid,
    output logic [ADDR_WIDTH-1:0]  mem_addr,
    output logic [DATA_WIDTH-1:0]  mem_wdata,
    output logic                   mem_we,
    output logic [DATA_WIDTH/8-1:0] mem_be,
    input  logic                   mem_ready,
    input  logic [DATA_WIDTH-1:0]  mem_rdata,
    input  logic                   mem_valid_out
);

    // Memory controller state machine
    typedef enum logic [2:0] {
        IDLE,
        READ_REQ,
        READ_WAIT,
        WRITE_REQ,
        WRITE_WAIT,
        ERROR
    } mem_state_t;
    
    mem_state_t                    state, next_state;
    
    // Request buffering
    logic [ADDR_WIDTH-1:0]         addr_reg;
    logic [DATA_WIDTH-1:0]         wdata_reg;
    logic                          we_reg;
    logic [DATA_WIDTH/8-1:0]       be_reg;
    
    // Transaction tracking
    logic [15:0]                   timeout_counter;
    logic                          timeout_error;
    
    // Performance counters
    logic [31:0]                   read_count;
    logic [31:0]                   write_count;
    logic [31:0]                   error_count;
    
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
                if (cache_if.valid) begin
                    if (cache_if.we) begin
                        next_state = WRITE_REQ;
                    end else begin
                        next_state = READ_REQ;
                    end
                end
            end
            
            READ_REQ: begin
                if (mem_ready) begin
                    next_state = READ_WAIT;
                end
            end
            
            READ_WAIT: begin
                if (mem_valid_out) begin
                    next_state = IDLE;
                end else if (timeout_error) begin
                    next_state = ERROR;
                end
            end
            
            WRITE_REQ: begin
                if (mem_ready) begin
                    next_state = WRITE_WAIT;
                end
            end
            
            WRITE_WAIT: begin
                if (mem_ready) begin  // Write completion
                    next_state = IDLE;
                end else if (timeout_error) begin
                    next_state = ERROR;
                end
            end
            
            ERROR: begin
                next_state = IDLE;  // Recovery
            end
        endcase
    end
    
    // Request registration
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            addr_reg <= '0;
            wdata_reg <= '0;
            we_reg <= 1'b0;
            be_reg <= '0;
        end else begin
            if (state == IDLE && cache_if.valid) begin
                addr_reg <= cache_if.addr;
                wdata_reg <= cache_if.wdata;
                we_reg <= cache_if.we;
                be_reg <= cache_if.be;
            end
        end
    end
    
    // Timeout handling
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            timeout_counter <= '0;
            timeout_error <= 1'b0;
        end else begin
            if (state == READ_WAIT || state == WRITE_WAIT) begin
                timeout_counter <= timeout_counter + 1;
                timeout_error <= (timeout_counter > MEM_TIMEOUT_CYCLES);
            end else begin
                timeout_counter <= '0;
                timeout_error <= 1'b0;
            end
        end
    end
    
    // Performance counters
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            read_count <= '0;
            write_count <= '0;
            error_count <= '0;
        end else begin
            if (state == READ_REQ && next_state == READ_WAIT) begin
                read_count <= read_count + 1;
            end
            if (state == WRITE_REQ && next_state == WRITE_WAIT) begin
                write_count <= write_count + 1;
            end
            if (next_state == ERROR) begin
                error_count <= error_count + 1;
            end
        end
    end
    
    // Memory interface outputs
    assign mem_clk = clk;
    assign mem_rst_n = rst_n;
    assign mem_valid = (state == READ_REQ || state == WRITE_REQ);
    assign mem_addr = addr_reg;
    assign mem_wdata = wdata_reg;
    assign mem_we = we_reg && (state == WRITE_REQ);
    assign mem_be = be_reg;
    
    // Cache interface outputs
    assign cache_if.ready = (state == IDLE) || 
                           (state == READ_WAIT && mem_valid_out) ||
                           (state == WRITE_WAIT && mem_ready);
    assign cache_if.rdata = mem_rdata;
    assign cache_if.valid = (state == READ_WAIT && mem_valid_out) ||
                           (state == WRITE_WAIT && mem_ready) ||
                           (state == ERROR);

endmodule
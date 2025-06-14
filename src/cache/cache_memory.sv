// cache_memory.sv
//Cache Memory System
`include "parameters.sv"
`include "types.sv"

module cache_memory (
    input  logic                    clk,
    input  logic                    rst_n,
    
    // Cache Request Interface
    input  cache_req_t             cache_req,
    input  logic                   cache_req_valid,
    output logic                   cache_req_ready,
    
    // Cache Response Interface
    output cache_resp_t            cache_resp,
    output logic                   cache_resp_valid,
    input  logic                   cache_resp_ready,
    
    // Memory Interface
    mem_interface.master           mem_if
);

    // Cache parameters
    localparam CACHE_SIZE = 1024;          // Cache size in lines
    localparam CACHE_LINE_SIZE = 64;       // Cache line size in bytes
    localparam CACHE_WAYS = 4;             // 4-way set associative
    localparam CACHE_SETS = CACHE_SIZE / CACHE_WAYS;
    localparam CACHE_ADDR_BITS = $clog2(CACHE_SETS);
    localparam TAG_BITS = ADDR_WIDTH - CACHE_ADDR_BITS - $clog2(CACHE_LINE_SIZE);
    
    // Cache memory arrays
    logic [TAG_BITS-1:0]           tag_array [CACHE_WAYS-1:0][CACHE_SETS-1:0];
    logic [DATA_WIDTH-1:0]         data_array [CACHE_WAYS-1:0][CACHE_SETS-1:0];
    logic                          valid_array [CACHE_WAYS-1:0][CACHE_SETS-1:0];
    logic                          dirty_array [CACHE_WAYS-1:0][CACHE_SETS-1:0];
    
    // LRU replacement policy
    logic [1:0]                    lru_array [CACHE_SETS-1:0];
    
    // Address parsing
    logic [TAG_BITS-1:0]           req_tag;
    logic [CACHE_ADDR_BITS-1:0]    req_index;
    logic [$clog2(CACHE_LINE_SIZE)-1:0] req_offset;
    
    assign req_tag = cache_req.addr[ADDR_WIDTH-1:ADDR_WIDTH-TAG_BITS];
    assign req_index = cache_req.addr[CACHE_ADDR_BITS-1+$clog2(CACHE_LINE_SIZE):$clog2(CACHE_LINE_SIZE)];
    assign req_offset = cache_req.addr[$clog2(CACHE_LINE_SIZE)-1:0];
    
    // Cache lookup
    logic [CACHE_WAYS-1:0]         way_hit;
    logic [1:0]                    hit_way;
    logic                          cache_hit;
    logic                          cache_miss;
    
    // Generate hit signals for each way
    genvar way;
    generate
        for (way = 0; way < CACHE_WAYS; way++) begin : gen_way_hit
            assign way_hit[way] = valid_array[way][req_index] && 
                                  (tag_array[way][req_index] == req_tag);
        end
    endgenerate
    
    // Priority encoder for hit way
    always_comb begin
        hit_way = '0;
        cache_hit = 1'b0;
        
        for (int i = 0; i < CACHE_WAYS; i++) begin
            if (way_hit[i]) begin
                hit_way = i[1:0];
                cache_hit = 1'b1;
                break;
            end
        end
    end
    
    assign cache_miss = cache_req_valid && !cache_hit;
    
    // Cache controller state machine
    typedef enum logic [2:0] {
        IDLE,
        LOOKUP,
        ALLOCATE,
        WRITEBACK,
        FILL,
        RESPOND
    } cache_state_t;
    
    cache_state_t                  state, next_state;
    
    // Registers for current request
    cache_req_t                    req_reg;
    logic                          req_valid_reg;
    logic [1:0]                    victim_way;
    
    // Miss handling
    logic                          miss_pending;
    logic                          fill_pending;
    logic                          writeback_pending;
    
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
                if (cache_req_valid) begin
                    next_state = LOOKUP;
                end
            end
            
            LOOKUP: begin
                if (cache_hit) begin
                    next_state = RESPOND;
                end else if (cache_miss) begin
                    next_state = ALLOCATE;
                end
            end
            
            ALLOCATE: begin
                if (dirty_array[victim_way][req_index] && valid_array[victim_way][req_index]) begin
                    next_state = WRITEBACK;
                end else begin
                    next_state = FILL;
                end
            end
            
            WRITEBACK: begin
                if (mem_if.ready && mem_if.valid) begin
                    next_state = FILL;
                end
            end
            
            FILL: begin
                if (mem_if.valid && mem_if.ready) begin
                    next_state = RESPOND;
                end
            end
            
            RESPOND: begin
                if (cache_resp_ready) begin
                    next_state = IDLE;
                end
            end
        endcase
    end
    
    // Request registration
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            req_reg <= '0;
            req_valid_reg <= 1'b0;
        end else begin
            if (state == IDLE && cache_req_valid) begin
                req_reg <= cache_req;
                req_valid_reg <= 1'b1;
            end else if (state == RESPOND && cache_resp_ready) begin
                req_valid_reg <= 1'b0;
            end
        end
    end
    
    // Victim way selection (simple round-robin for now)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            victim_way <= '0;
        end else begin
            if (state == ALLOCATE) begin
                // Find invalid way first
                victim_way <= '0;
                for (int i = 0; i < CACHE_WAYS; i++) begin
                    if (!valid_array[i][req_index]) begin
                        victim_way <= i[1:0];
                        break;
                    end
                end
                
                // If all ways valid, use LRU
                if (valid_array[0][req_index] && valid_array[1][req_index] && 
                    valid_array[2][req_index] && valid_array[3][req_index]) begin
                    victim_way <= lru_array[req_index];
                end
            end
        end
    end
    
    // Cache array updates
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Initialize arrays
            for (int way = 0; way < CACHE_WAYS; way++) begin
                for (int set = 0; set < CACHE_SETS; set++) begin
                    valid_array[way][set] <= 1'b0;
                    dirty_array[way][set] <= 1'b0;
                    tag_array[way][set] <= '0;
                    data_array[way][set] <= '0;
                end
            end
            
            for (int set = 0; set < CACHE_SETS; set++) begin
                lru_array[set] <= '0;
            end
        end else begin
            // Handle cache fills
            if (state == FILL && mem_if.valid) begin
                valid_array[victim_way][req_index] <= 1'b1;
                tag_array[victim_way][req_index] <= req_tag;
                data_array[victim_way][req_index] <= mem_if.rdata;
                dirty_array[victim_way][req_index] <= 1'b0;
            end
            
            // Handle cache writes
            if (state == LOOKUP && cache_hit && req_reg.req_type == CACHE_WRITE) begin
                data_array[hit_way][req_index] <= req_reg.wdata;
                dirty_array[hit_way][req_index] <= 1'b1;
            end
            
            // Update LRU on hits
            if (state == LOOKUP && cache_hit) begin
                lru_array[req_index] <= (lru_array[req_index] + 1) % CACHE_WAYS;
            end
        end
    end
    
    // Memory interface control
    always_comb begin
        mem_if.valid = 1'b0;
        mem_if.addr = '0;
        mem_if.wdata = '0;
        mem_if.we = 1'b0;
        mem_if.be = '1; // Byte enable - all bytes
        
        case (state)
            WRITEBACK: begin
                mem_if.valid = 1'b1;
                mem_if.addr = {tag_array[victim_way][req_index], req_index, {$clog2(CACHE_LINE_SIZE){1'b0}}};
                mem_if.wdata = data_array[victim_way][req_index];
                mem_if.we = 1'b1;
            end
            
            FILL: begin
                mem_if.valid = 1'b1;
                mem_if.addr = req_reg.addr;
                mem_if.we = 1'b0;
            end
        endcase
    end
    
    // Cache response generation
    always_comb begin
        cache_resp = '0;
        cache_resp_valid = 1'b0;
        
        if (state == RESPOND) begin
            cache_resp_valid = 1'b1;
            cache_resp.trans_id = req_reg.trans_id;
            cache_resp.hit = (state == RESPOND); // If we reach RESPOND, we have the data
            
            if (req_reg.req_type == CACHE_READ) begin
                if (cache_hit) begin
                    cache_resp.data = data_array[hit_way][req_index];
                end else begin
                    cache_resp.data = mem_if.rdata; // Data from memory fill
                end
            end else begin // CACHE_WRITE
                cache_resp.data = req_reg.wdata; // Echo back write data
            end
        end
    end
    
    // Ready signal - can accept new request when idle
    assign cache_req_ready = (state == IDLE);
    
    // Performance monitoring (optional)
    logic [31:0] hit_count, miss_count, total_accesses;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            hit_count <= '0;
            miss_count <= '0;
            total_accesses <= '0;
        end else begin
            if (state == LOOKUP && req_valid_reg) begin
                total_accesses <= total_accesses + 1;
                if (cache_hit) begin
                    hit_count <= hit_count + 1;
                end else begin
                    miss_count <= miss_count + 1;
                end
            end
        end
    end

endmodule
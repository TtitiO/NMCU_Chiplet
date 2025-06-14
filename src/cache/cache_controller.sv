// src/cache/cache_controller.sv
// Cache Controller with MSHR and Prefetcher support

module cache_controller
    import nmcu_pkg::*;
(
    input  logic                    clk,
    input  logic                    rst_n,
    
    // Control Interface
    input  logic                    flush,
    input  logic                    invalidate,
    output logic                    ready,
    
    // PE Array Interface (Load/Store requests)
    input  logic                    pe_req_valid,
    input  cache_req_t              pe_req,
    output logic                    pe_req_ready,
    output logic                    pe_resp_valid,
    output cache_resp_t             pe_resp,
    input  logic                    pe_resp_ready,
    
    // Memory Interface (to external memory)
    output logic                    mem_req_valid,
    output mem_req_t                mem_req,
    input  logic                    mem_req_ready,
    input  logic                    mem_resp_valid,
    input  mem_resp_t               mem_resp,
    output logic                    mem_resp_ready,
    
    // Cache Memory Interface
    output logic                    cache_mem_we,
    output logic [CACHE_INDEX_WIDTH-1:0] cache_mem_addr,
    output cache_line_t             cache_mem_wdata,
    input  cache_line_t             cache_mem_rdata,
    output logic [CACHE_TAG_WIDTH-1:0] cache_mem_tag_we,
    output logic [CACHE_TAG_WIDTH-1:0] cache_mem_tag_addr,
    output cache_tag_t              cache_mem_tag_wdata,
    input  cache_tag_t              cache_mem_tag_rdata,
    
    // Statistics and Debug
    output logic [31:0]             hit_count,
    output logic [31:0]             miss_count,
    output logic [31:0]             prefetch_count
);

    // Cache Parameters
    localparam CACHE_WAYS = 4;
    localparam CACHE_SETS = 1 << CACHE_INDEX_WIDTH;
    localparam CACHE_LINE_SIZE = CACHE_LINE_WIDTH / 8; // bytes
    
    // State Machine
    typedef enum logic [2:0] {
        IDLE        = 3'b000,
        TAG_CHECK   = 3'b001,
        ALLOCATE    = 3'b010,
        WRITE_BACK  = 3'b011,
        FILL        = 3'b100,
        RESPOND     = 3'b101,
        FLUSH_STATE = 3'b110
    } cache_state_t;
    
    cache_state_t current_state, next_state;
    
    // Request Buffer
    cache_req_t req_buffer;
    logic req_buffer_valid;
    
    // Tag and Data Arrays
    cache_tag_t tag_array [CACHE_SETS-1:0][CACHE_WAYS-1:0];
    logic [CACHE_WAYS-1:0] valid_bits [CACHE_SETS-1:0];
    logic [CACHE_WAYS-1:0] dirty_bits [CACHE_SETS-1:0];
    logic [1:0] lru_counter [CACHE_SETS-1:0][CACHE_WAYS-1:0];
    
    // Address Breakdown
    logic [CACHE_TAG_WIDTH-1:0] req_tag;
    logic [CACHE_INDEX_WIDTH-1:0] req_index;
    logic [CACHE_OFFSET_WIDTH-1:0] req_offset;
    
    // Hit/Miss Logic
    logic [CACHE_WAYS-1:0] way_hit;
    logic cache_hit;
    logic [1:0] hit_way;
    logic [1:0] victim_way;
    
    // MSHR (Miss Status Handling Register)
    typedef struct packed {
        logic valid;
        logic [31:0] addr;
        logic [1:0] req_type;
        logic [DATA_WIDTH-1:0] write_data;
        logic [1:0] way;
        logic pending;
    } mshr_entry_t;
    
    mshr_entry_t mshr [MSHR_ENTRIES-1:0];
    logic [MSHR_ENTRIES-1:0] mshr_valid;
    logic mshr_full;
    logic [MSHR_ENTRIES-1:0] mshr_alloc_idx;
    
    // Prefetcher
    logic [31:0] prefetch_addr;
    logic prefetch_valid;
    logic prefetch_ready;
    
    // Statistics
    logic [31:0] hit_count_reg;
    logic [31:0] miss_count_reg;
    logic [31:0] prefetch_count_reg;
    
    // Address Parsing
    always_comb begin
        req_tag = pe_req.addr[31:CACHE_OFFSET_WIDTH+CACHE_INDEX_WIDTH];
        req_index = pe_req.addr[CACHE_OFFSET_WIDTH+CACHE_INDEX_WIDTH-1:CACHE_OFFSET_WIDTH];
        req_offset = pe_req.addr[CACHE_OFFSET_WIDTH-1:0];
    end
    
    // State Machine - Sequential
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= IDLE;
        end else begin
            current_state <= next_state;
        end
    end
    
    // State Machine - Combinational
    always_comb begin
        next_state = current_state;
        
        case (current_state)
            IDLE: begin
                if (flush) begin
                    next_state = FLUSH_STATE;
                end else if (pe_req_valid && pe_req_ready) begin
                    next_state = TAG_CHECK;
                end
            end
            
            TAG_CHECK: begin
                if (cache_hit) begin
                    next_state = RESPOND;
                end else if (!mshr_full) begin
                    next_state = ALLOCATE;
                end else begin
                    next_state = IDLE; // Retry later
                end
            end
            
            ALLOCATE: begin
                if (dirty_bits[req_index][victim_way]) begin
                    next_state = WRITE_BACK;
                end else begin
                    next_state = FILL;
                end
            end
            
            WRITE_BACK: begin
                if (mem_req_ready) begin
                    next_state = FILL;
                end
            end
            
            FILL: begin
                if (mem_resp_valid) begin
                    next_state = RESPOND;
                end
            end
            
            RESPOND: begin
                if (pe_resp_ready) begin
                    next_state = IDLE;
                end
            end
            
            FLUSH_STATE: begin
                // Simplified flush - just invalidate all
                next_state = IDLE;
            end
        endcase
    end
    
    // Request Buffer
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            req_buffer <= '0;
            req_buffer_valid <= 1'b0;
        end else if (pe_req_valid && pe_req_ready) begin
            req_buffer <= pe_req;
            req_buffer_valid <= 1'b1;
        end else if (current_state == RESPOND && pe_resp_ready) begin
            req_buffer_valid <= 1'b0;
        end
    end
    
    // Tag Array Management
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < CACHE_SETS; i++) begin
                for (int j = 0; j < CACHE_WAYS; j++) begin
                    tag_array[i][j] <= '0;
                    lru_counter[i][j] <= 2'b00;
                end
                valid_bits[i] <= '0;
                dirty_bits[i] <= '0;
            end
        end else begin
            // Handle flush/invalidate
            if (flush || invalidate) begin
                for (int i = 0; i < CACHE_SETS; i++) begin
                    valid_bits[i] <= '0;
                    dirty_bits[i] <= '0;
                end
            end
            
            // Update on cache fill
            if (current_state == FILL && mem_resp_valid) begin
                tag_array[req_index][victim_way] <= req_tag;
                valid_bits[req_index][victim_way] <= 1'b1;
                dirty_bits[req_index][victim_way] <= (req_buffer.req_type == CACHE_WRITE);
                
                // Update LRU
                lru_counter[req_index][victim_way] <= 2'b11;
                for (int j = 0; j < CACHE_WAYS; j++) begin
                    if (j != victim_way && lru_counter[req_index][j] > 0) begin
                        lru_counter[req_index][j] <= lru_counter[req_index][j] - 1;
                    end
                end
            end
            
            // Update on cache hit
            if (current_state == TAG_CHECK && cache_hit) begin
                if (req_buffer.req_type == CACHE_WRITE) begin
                    dirty_bits[req_index][hit_way] <= 1'b1;
                end
                
                // Update LRU
                lru_counter[req_index][hit_way] <= 2'b11;
                for (int j = 0; j < CACHE_WAYS; j++) begin
                    if (j != hit_way && lru_counter[req_index][j] > 0) begin
                        lru_counter[req_index][j] <= lru_counter[req_index][j] - 1;
                    end
                end
            end
        end
    end
    
    // Hit/Miss Detection
    always_comb begin
        way_hit = '0;
        cache_hit = 1'b0;
        hit_way = '0;
        
        for (int i = 0; i < CACHE_WAYS; i++) begin
            if (valid_bits[req_index][i] && 
                (tag_array[req_index][i] == req_tag)) begin
                way_hit[i] = 1'b1;
                cache_hit = 1'b1;
                hit_way = i[1:0];
            end
        end
    end
    
    // Victim Selection (LRU)
    always_comb begin
        victim_way = 2'b00;
        for (int i = 0; i < CACHE_WAYS; i++) begin
            if (lru_counter[req_index][i] == 2'b00) begin
                victim_way = i[1:0];
                break;
            end
        end
    end
    
    // MSHR Management
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < MSHR_ENTRIES; i++) begin
                mshr[i] <= '0;
            end
            mshr_valid <= '0;
        end else begin
            // Allocate MSHR entry on miss
            if (current_state == ALLOCATE && !mshr_full) begin
                for (int i = 0; i < MSHR_ENTRIES; i++) begin
                    if (!mshr_valid[i]) begin
                        mshr[i].valid <= 1'b1;
                        mshr[i].addr <= req_buffer.addr;
                        mshr[i].req_type <= req_buffer.req_type;
                        mshr[i].write_data <= req_buffer.write_data;
                        mshr[i].way <= victim_way;
                        mshr[i].pending <= 1'b1;
                        mshr_valid[i] <= 1'b1;
                        break;
                    end
                end
            end
            
            // Clear MSHR entry on completion
            if (current_state == RESPOND && pe_resp_ready) begin
                for (int i = 0; i < MSHR_ENTRIES; i++) begin
                    if (mshr_valid[i] && mshr[i].addr == req_buffer.addr) begin
                        mshr_valid[i] <= 1'b0;
                        break;
                    end
                end
            end
        end
    end
    
    assign mshr_full = &mshr_valid;
    
    // Cache Memory Interface
    always_comb begin
        cache_mem_we = 1'b0;
        cache_mem_addr = req_index;
        cache_mem_wdata = mem_resp.data;
        cache_mem_tag_we = '0;
        cache_mem_tag_addr = req_index;
        cache_mem_tag_wdata.tag = req_tag;
        cache_mem_tag_wdata.valid = 1'b1;
        cache_mem_tag_wdata.dirty = (req_buffer.req_type == CACHE_WRITE);
        
        if (current_state == FILL && mem_resp_valid) begin
            cache_mem_we = 1'b1;
            cache_mem_tag_we[victim_way] = 1'b1;
        end
    end
    
    // Memory Interface
    always_comb begin
        mem_req_valid = 1'b0;
        mem_req.addr = req_buffer.addr;
        mem_req.size = CACHE_LINE_SIZE;
        mem_req.req_type = MEM_READ;
        mem_req.burst_len = 8'd1;
        mem_resp_ready = 1'b0;
        
        if (current_state == WRITE_BACK) begin
            mem_req_valid = 1'b1;
            mem_req.addr = {tag_array[req_index][victim_way], req_index, {CACHE_OFFSET_WIDTH{1'b0}}};
            mem_req.req_type = MEM_WRITE;
            mem_req.data = cache_mem_rdata;
        end else if (current_state == FILL) begin
            mem_req_valid = 1'b1;
            mem_resp_ready = 1'b1;
        end
    end
    
    // PE Interface
    always_comb begin
        pe_req_ready = (current_state == IDLE) && !flush;
        pe_resp_valid = (current_state == RESPOND);
        pe_resp.data = cache_mem_rdata;
        pe_resp.hit = cache_hit;
        pe_resp.ready = 1'b1;
    end
    
    // Statistics
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            hit_count_reg <= '0;
            miss_count_reg <= '0;
            prefetch_count_reg <= '0;
        end else begin
            if (current_state == TAG_CHECK) begin
                if (cache_hit) begin
                    hit_count_reg <= hit_count_reg + 1;
                end else begin
                    miss_count_reg <= miss_count_reg + 1;
                end
            end
            
            if (prefetch_valid && prefetch_ready) begin
                prefetch_count_reg <= prefetch_count_reg + 1;
            end
        end
    end
    
    assign ready = (current_state == IDLE) && !flush;
    assign hit_count = hit_count_reg;
    assign miss_count = miss_count_reg;
    assign prefetch_count = prefetch_count_reg;
    
    // Simple Sequential Prefetcher
    prefetcher u_prefetcher (
        .clk(clk),
        .rst_n(rst_n),
        .access_addr(req_buffer.addr),
        .access_valid(current_state == TAG_CHECK),
        .cache_miss(!cache_hit),
        .prefetch_addr(prefetch_addr),
        .prefetch_valid(prefetch_valid),
        .prefetch_ready(prefetch_ready)
    );
    
    // Assertions
    `ifdef SIMULATION
        assert property (@(posedge clk) disable iff (!rst_n)
                        pe_req_valid && pe_req_ready |-> ##1 current_state == TAG_CHECK)
        else $error("Invalid state transition after request");
        
        assert property (@(posedge clk) disable iff (!rst_n)
                        current_state == RESPOND |-> pe_resp_valid)
        else $error("Response not valid in RESPOND state");
    `endif

endmodule
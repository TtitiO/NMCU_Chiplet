// mshr.sv
// Miss Status Handling Register
`include "parameters.sv"
`include "types.sv"

module mshr #(
    parameter MSHR_ENTRIES = 8
) (
    input  logic                    clk,
    input  logic                    rst_n,
    
    // Allocation interface
    input  logic                    allocate,
    input  logic [ADDR_WIDTH-1:0]   alloc_addr,
    input  logic [TRANS_ID_WIDTH-1:0] alloc_trans_id,
    output logic                    alloc_ready,
    output logic [$clog2(MSHR_ENTRIES)-1:0] alloc_entry,
    
    // Deallocation interface
    input  logic                    deallocate,
    input  logic [$clog2(MSHR_ENTRIES)-1:0] dealloc_entry,
    
    // Lookup interface
    input  logic [ADDR_WIDTH-1:0]   lookup_addr,
    output logic                    lookup_hit,
    output logic [$clog2(MSHR_ENTRIES)-1:0] lookup_entry,
    
    // Status interface
    output logic [MSHR_ENTRIES-1:0] entry_valid,
    output logic [ADDR_WIDTH-1:0]   entry_addr [MSHR_ENTRIES-1:0],
    output logic [TRANS_ID_WIDTH-1:0] entry_trans_id [MSHR_ENTRIES-1:0]
);

    // MSHR entry structure
    typedef struct packed {
        logic                       valid;
        logic [ADDR_WIDTH-1:0]      addr;
        logic [TRANS_ID_WIDTH-1:0]  trans_id;
        logic [31:0]                timestamp;
    } mshr_entry_t;
    
    mshr_entry_t                   mshr_table [MSHR_ENTRIES-1:0];
    logic [31:0]                   cycle_counter;
    
    // Entry allocation logic
    logic [$clog2(MSHR_ENTRIES)-1:0] free_entry;
    logic                          has_free_entry;
    
    // Find free entry
    always_comb begin
        free_entry = '0;
        has_free_entry = 1'b0;
        
        for (int i = 0; i < MSHR_ENTRIES; i++) begin
            if (!mshr_table[i].valid) begin
                free_entry = i[$clog2(MSHR_ENTRIES)-1:0];
                has_free_entry = 1'b1;
                break;
            end
        end
    end
    
    // Lookup logic
    always_comb begin
        lookup_hit = 1'b0;
        lookup_entry = '0;
        
        for (int i = 0; i < MSHR_ENTRIES; i++) begin
            if (mshr_table[i].valid && (mshr_table[i].addr == lookup_addr)) begin
                lookup_hit = 1'b1;
                lookup_entry = i[$clog2(MSHR_ENTRIES)-1:0];
                break;
            end
        end
    end
    
    // Cycle counter
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cycle_counter <= '0;
        end else begin
            cycle_counter <= cycle_counter + 1;
        end
    end
    
    // MSHR table management
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < MSHR_ENTRIES; i++) begin
                mshr_table[i] <= '0;
            end
        end else begin
            // Allocation
            if (allocate && has_free_entry) begin
                mshr_table[free_entry].valid <= 1'b1;
                mshr_table[free_entry].addr <= alloc_addr;
                mshr_table[free_entry].trans_id <= alloc_trans_id;
                mshr_table[free_entry].timestamp <= cycle_counter;
            end
            
            // Deallocation
            if (deallocate && dealloc_entry < MSHR_ENTRIES) begin
                mshr_table[dealloc_entry].valid <= 1'b0;
            end
        end
    end
    
    // Output assignments
    assign alloc_ready = has_free_entry;
    assign alloc_entry = free_entry;
    
    // Status outputs
    genvar i;
    generate
        for (i = 0; i < MSHR_ENTRIES; i++) begin : gen_status
            assign entry_valid[i] = mshr_table[i].valid;
            assign entry_addr[i] = mshr_table[i].addr;
            assign entry_trans_id[i] = mshr_table[i].trans_id;
        end
    endgenerate

endmodule
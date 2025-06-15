// nmcu_project/src/include/nmcu_pkg.sv
// Function: Define common parameters for the NMCU project
package nmcu_pkg;

    // Common Parameters
    parameter DATA_WIDTH      = 32;       // Data bus width (e.g., for integers or floats)
    parameter ADDR_WIDTH      = 32;       // Address bus width
    parameter LEN_WIDTH       = 8;        // Length/burst size width

    // PE Array Parameters
    parameter PE_ROWS         = 4;        // Number of PE rows (for future Systolic Array)
    parameter PE_COLS         = 4;        // Number of PE columns (for future Systolic Array)
    parameter MAC_DATA_WIDTH  = DATA_WIDTH; // Data width for MAC operations (input/output)

    // Cache Parameters (TODO: simplified for now, revisit for future)
    parameter CACHE_LINE_SIZE = 64;       // Cache line size in bytes (for future)
    parameter CACHE_NUM_SETS  = 256;      // Number of cache sets (for future)
    parameter MEM_SIZE_WORDS  = 16384;    // 16K words for TB simulation
    parameter MEM_LATENCY     = 5;        // Latency for simulated main memory

    // Derived Parameters
    localparam DATA_BYTES_PER_WORD = DATA_WIDTH / 8;
    localparam CACHE_LINE_WORDS    = CACHE_LINE_SIZE / DATA_BYTES_PER_WORD;

    // Define common AXI-like interfaces for internal communication
    // Request/Response structure for memory operations
    typedef struct packed {
        logic                           valid;
        logic                           write_en;
        logic [ADDR_WIDTH-1:0]          addr;
        logic [DATA_WIDTH-1:0]          wdata;
        logic [LEN_WIDTH-1:0]           len; // Burst length (e.g., number of words)
    } mem_req_t;

    typedef struct packed {
        logic                           valid;
        logic [ADDR_WIDTH-1:0]          addr; // Address associated with the response (useful for debug/MSHR)
        logic [DATA_WIDTH-1:0]          rdata;
        logic                           hit; // For future cache implementation
    } mem_resp_t;

    // // Define common handshake interface (valid/ready)
    // typedef struct packed {
    //     logic valid;
    //     logic ready;
    // } handshake_t;

endpackage : nmcu_pkg

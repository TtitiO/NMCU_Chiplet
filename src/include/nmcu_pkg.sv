// nmcu_project/src/include/nmcu_pkg.sv
// Function: Define common parameters for the NMCU project
`ifndef _NMCU_PKG_SV_
`define _NMCU_PKG_SV_
package nmcu_pkg;

    // Common Parameters
    parameter DATA_WIDTH      = 32;       // Data bus width (e.g., for integers or floats)
    parameter ADDR_WIDTH      = 32;       // Address bus width
    parameter LEN_WIDTH       = 8;        // Length/burst size width
    parameter PSUM_WIDTH      = 2 * DATA_WIDTH;

    // Cache Parameters (TODO: simplified for now, revisit for future)
    parameter CACHE_LINE_SIZE = 64;       // Cache line size in bytes (for future)
    parameter CACHE_NUM_SETS  = 256;      // Number of cache sets (for future)
    parameter MEM_SIZE_WORDS  = 65536;    // 64K words for TB simulation
    parameter MEM_LATENCY     = 5;        // Latency for simulated main memory

    // Derived Parameters
    localparam DATA_BYTES_PER_WORD = DATA_WIDTH / 8;
    localparam CACHE_LINE_WORDS    = CACHE_LINE_SIZE / DATA_BYTES_PER_WORD;

    // --- FC Layer Dimensions for Testbench ---
    // Centralized here from the testbench for consistency.
    // C[BATCH_SIZE][OUTPUT_NEURONS] = A[BATCH_SIZE][INPUT_FEATURES] * B[INPUT_FEATURES][OUTPUT_NEURONS]
    parameter BATCH_SIZE        = 4;   // How many input vectors to process at once (N)
    parameter INPUT_FEATURES    = 8;   // Dimension of the input vector (K)
    parameter OUTPUT_NEURONS    = 4;   // Dimension of the output vector (M)

    // --- PE Array Parameters ---
    // These define the physical size of the systolic array.
    // It's good practice to link them to the problem size for initial verification.
    // This configuration maps the entire output matrix to the PE array at once.
    parameter PE_ROWS         = BATCH_SIZE;     // Set to 4 to match the number of output rows
    parameter PE_COLS         = OUTPUT_NEURONS; // Set to 4 to match the number of output columns

    // --- Explicit Matrix Type Definitions ---
    // These typedefs resolve the Verilator C++ compilation error by providing
    // unambiguous types for multi-dimensional arrays passed to tasks.
    typedef logic [DATA_WIDTH-1:0] input_matrix_t  [0:BATCH_SIZE-1][0:INPUT_FEATURES-1];
    typedef logic [DATA_WIDTH-1:0] weight_matrix_t [0:INPUT_FEATURES-1][0:OUTPUT_NEURONS-1];
    typedef logic [PSUM_WIDTH-1:0] output_matrix_t [0:BATCH_SIZE-1][0:OUTPUT_NEURONS-1];

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

`endif

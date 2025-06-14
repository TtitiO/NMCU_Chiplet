// src/common/parameters.sv
// NMCU Chiplet Parameters Definition

`ifndef NMCU_PARAMETERS_SV
`define NMCU_PARAMETERS_SV

package nmcu_pkg;

    // ========================================================================
    // Clock and Reset Parameters
    // ========================================================================
    parameter int COMPUTE_CLK_FREQ_MHZ = 1000;  // 1GHz
    parameter int MEMORY_CLK_FREQ_MHZ = 800;    // 800MHz for HBM/DDR

    // ========================================================================
    // Data Width Parameters
    // ========================================================================
    parameter int DATA_WIDTH = 16;              // 16-bit data (INT16/BF16)
    parameter int ADDR_WIDTH = 32;              // 32-bit address
    parameter int WEIGHT_WIDTH = 16;            // 16-bit weight
    parameter int RESULT_WIDTH = 32;            // 32-bit accumulation result

    // ========================================================================
    // PE Array Parameters
    // ========================================================================
    parameter int PE_ARRAY_SIZE_X = 16;         // 16x16 PE array
    parameter int PE_ARRAY_SIZE_Y = 16;
    parameter int PE_TOTAL_NUM = PE_ARRAY_SIZE_X * PE_ARRAY_SIZE_Y;

    // ========================================================================
    // Cache Parameters
    // ========================================================================
    parameter int CACHE_LINE_SIZE = 64;         // 64 bytes cache line
    parameter int CACHE_LINE_WIDTH = CACHE_LINE_SIZE * 8; // 512 bits
    parameter int L1_DATA_CACHE_SIZE_KB = 64;   // 64KB L1 data cache
    parameter int L1_INST_CACHE_SIZE_KB = 32;   // 32KB L1 instruction cache
    parameter int CACHE_WAYS = 4;               // 4-way set associative
    parameter int CACHE_SETS = (L1_DATA_CACHE_SIZE_KB * 1024) / (CACHE_LINE_SIZE * CACHE_WAYS);
    parameter int CACHE_INDEX_WIDTH = $clog2(CACHE_SETS);
    parameter int CACHE_TAG_WIDTH = ADDR_WIDTH - CACHE_INDEX_WIDTH - $clog2(CACHE_LINE_SIZE);
    parameter int CACHE_OFFSET_WIDTH = $clog2(CACHE_LINE_SIZE);

    // ========================================================================
    // Memory Interface Parameters
    // ========================================================================
    parameter int MEM_DATA_WIDTH = 512;         // HBM/DDR data width
    parameter int MEM_BURST_LENGTH = 8;         // Burst length
    parameter int MEM_REQ_QUEUE_DEPTH = 16;     // Memory request queue depth

    // ========================================================================
    // UCIe Interface Parameters
    // ========================================================================
    parameter int UCIE_FLIT_WIDTH = 256;        // UCIe flit width
    parameter int UCIE_LANES = 8;               // Number of UCIe lanes
    parameter int UCIE_TX_BUFFER_DEPTH = 32;    // TX buffer depth
    parameter int UCIE_RX_BUFFER_DEPTH = 32;    // RX buffer depth

    // ========================================================================
    // Control Unit Parameters
    // ========================================================================
    parameter int CMD_OPCODE_WIDTH = 8;         // Command opcode width
    parameter int CMD_QUEUE_DEPTH = 16;         // Command queue depth
    parameter int STATUS_WIDTH = 8;             // Status register width

    // ========================================================================
    // FIFO Parameters
    // ========================================================================
    parameter int PE_INPUT_FIFO_DEPTH = 32;     // PE input FIFO depth
    parameter int PE_OUTPUT_FIFO_DEPTH = 32;    // PE output FIFO depth
    parameter int DATA_DISPATCHER_FIFO_DEPTH = 64; // Data dispatcher FIFO depth

    // ========================================================================
    // Performance Parameters
    // ========================================================================
    parameter int MAX_AVG_LATENCY_NS = 80;      // Maximum average latency in ns
    parameter int MAX_WORST_LATENCY_NS = 150;   // Maximum worst-case latency in ns
    parameter real MIN_BANDWIDTH_UTIL = 0.9;    // Minimum 90% bandwidth utilization

    // ========================================================================
    // MSHR Parameters (Miss Status Handling Register)
    // ========================================================================
    parameter int MSHR_ENTRIES = 8;             // Number of MSHR entries
    parameter int MSHR_ID_WIDTH = $clog2(MSHR_ENTRIES);

    // ========================================================================
    // Prefetcher Parameters
    // ========================================================================
    parameter int PREFETCH_BUFFER_DEPTH = 16;   // Prefetch buffer depth
    parameter int PREFETCH_DISTANCE = 4;        // Prefetch distance
    parameter int PREFETCH_DEGREE = 2;          // Prefetch degree

    // ========================================================================
    // Pipeline Parameters
    // ========================================================================
    parameter int PIPELINE_STAGES = 8;          // Total pipeline stages
    parameter int MAC_PIPELINE_STAGES = 3;      // MAC pipeline stages

    // ========================================================================
    // Debug and Verification Parameters
    // ========================================================================
    parameter int DEBUG_COUNTER_WIDTH = 32;     // Debug counter width
    parameter bit ENABLE_ASSERTIONS = 1'b1;     // Enable assertions
    parameter bit ENABLE_COVERAGE = 1'b1;       // Enable coverage collection

endpackage

`endif // NMCU_PARAMETERS_SV

// src/common/types.sv
// NMCU Chiplet Type Definitions

`ifndef NMCU_TYPES_SV
`define NMCU_TYPES_SV

`include "parameters.sv"

package nmcu_types;
    import nmcu_pkg::*;

    // ========================================================================
    // Basic Data Types
    // ========================================================================
    typedef logic [DATA_WIDTH-1:0]         data_t;
    typedef logic [WEIGHT_WIDTH-1:0]       weight_t;
    typedef logic [RESULT_WIDTH-1:0]       result_t;
    typedef logic [ADDR_WIDTH-1:0]         addr_t;
    typedef logic [CACHE_LINE_WIDTH-1:0]   cache_line_t;
    typedef logic [MEM_DATA_WIDTH-1:0]     mem_data_t;
    typedef logic [UCIE_FLIT_WIDTH-1:0]    ucie_flit_t;

    // ========================================================================
    // Cache Related Types
    // ========================================================================
    typedef logic [CACHE_TAG_WIDTH-1:0]    cache_tag_t;
    typedef logic [CACHE_INDEX_WIDTH-1:0]  cache_index_t;
    typedef logic [CACHE_OFFSET_WIDTH-1:0] cache_offset_t;
    typedef logic [CACHE_WAYS-1:0]         cache_way_mask_t;
    typedef logic [$clog2(CACHE_WAYS)-1:0] cache_way_id_t;

    // Cache State Enumeration
    typedef enum logic [1:0] {
        CACHE_INVALID = 2'b00,
        CACHE_VALID   = 2'b01,
        CACHE_DIRTY   = 2'b11
    } cache_state_e;

    // Cache Request Types
    typedef enum logic [2:0] {
        CACHE_READ     = 3'b000,
        CACHE_WRITE    = 3'b001,
        CACHE_PREFETCH = 3'b010,
        CACHE_FLUSH    = 3'b011,
        CACHE_INVALIDATE = 3'b100
    } cache_req_type_e;

    // Cache Request Structure
    typedef struct packed {
        cache_req_type_e    req_type;
        addr_t              addr;
        cache_line_t        data;
        logic               valid;
        logic [3:0]         id;
    } cache_req_t;

    // Cache Response Structure
    typedef struct packed {
        cache_line_t        data;
        logic               hit;
        logic               valid;
        logic [3:0]         id;
    } cache_resp_t;

    // ========================================================================
    // Memory Interface Types
    // ========================================================================
    typedef enum logic [2:0] {
        MEM_READ    = 3'b000,
        MEM_WRITE   = 3'b001,
        MEM_BURST_READ  = 3'b010,
        MEM_BURST_WRITE = 3'b011
    } mem_cmd_e;

    // Memory Request Structure
    typedef struct packed {
        mem_cmd_e           cmd;
        addr_t              addr;
        mem_data_t          data;
        logic [7:0]         burst_len;
        logic               valid;
        logic [3:0]         id;
    } mem_req_t;

    // Memory Response Structure
    typedef struct packed {
        mem_data_t          data;
        logic               ready;
        logic               valid;
        logic               error;
        logic [3:0]         id;
    } mem_resp_t;

    // ========================================================================
    // PE Array Types
    // ========================================================================
    typedef logic [$clog2(PE_ARRAY_SIZE_X)-1:0] pe_x_id_t;
    typedef logic [$clog2(PE_ARRAY_SIZE_Y)-1:0] pe_y_id_t;

    // PE Operation Types
    typedef enum logic [2:0] {
        PE_NOP          = 3'b000,
        PE_MAC          = 3'b001,  // Multiply-Accumulate
        PE_ADD          = 3'b010,
        PE_MUL          = 3'b011,
        PE_RELU         = 3'b100,
        PE_LOAD_WEIGHT  = 3'b101,
        PE_CLEAR_ACC    = 3'b110
    } pe_op_e;

    // PE Control Structure
    typedef struct packed {
        pe_op_e             op;
        logic               enable;
        logic               weight_load_en;
        logic               acc_clear;
        logic               result_valid;
    } pe_ctrl_t;

    // PE Data Structure
    typedef struct packed {
        data_t              input_data;
        weight_t            weight_data;
        result_t            partial_sum;
        logic               input_valid;
        logic               weight_valid;
    } pe_data_t;

    // ========================================================================
    // UCIe Interface Types
    // ========================================================================
    typedef enum logic [3:0] {
        UCIE_IDLE       = 4'b0000,
        UCIE_REQUEST    = 4'b0001,
        UCIE_RESPONSE   = 4'b0010,
        UCIE_DATA       = 4'b0011,
        UCIE_CREDIT     = 4'b0100,
        UCIE_POISON     = 4'b0101,
        UCIE_ERROR      = 4'b0110
    } ucie_flit_type_e;

    // UCIe Flit Structure
    typedef struct packed {
        ucie_flit_type_e    flit_type;
        logic [7:0]         dest_id;
        logic [7:0]         src_id;
        logic [7:0]         seq_num;
        ucie_flit_t         payload;
        logic               valid;
        logic               ready;
    } ucie_packet_t;

    // ========================================================================
    // Control Unit Types
    // ========================================================================
    typedef enum logic [CMD_OPCODE_WIDTH-1:0] {
        CMD_NOP         = 8'h00,
        CMD_LOAD_WEIGHT = 8'h01,
        CMD_LOAD_INPUT  = 8'h02,
        CMD_COMPUTE     = 8'h03,
        CMD_STORE_RESULT = 8'h04,
        CMD_FLUSH_CACHE = 8'h05,
        CMD_CONFIG_PE   = 8'h06,
        CMD_STATUS_READ = 8'h07,
        CMD_RESET       = 8'hFF
    } cmd_opcode_e;

    // Command Structure
    typedef struct packed {
        cmd_opcode_e        opcode;
        addr_t              addr;
        logic [15:0]        length;
        logic [15:0]        config_data;
        logic               valid;
        logic [3:0]         id;
    } cmd_t;

    // Status Structure
    typedef struct packed {
        logic               idle;
        logic               busy;
        logic               error;
        logic               cache_miss;
        logic [3:0]         pe_status;
        logic [7:0]         reserved;
    } status_t;

    // ========================================================================
    // MSHR Types
    // ========================================================================
    typedef enum logic [1:0] {
        MSHR_IDLE       = 2'b00,
        MSHR_PENDING    = 2'b01,
        MSHR_WAITING    = 2'b10,
        MSHR_COMPLETE   = 2'b11
    } mshr_state_e;

    // MSHR Entry Structure
    typedef struct packed {
        mshr_state_e        state;
        addr_t              addr;
        cache_req_type_e    req_type;
        logic [3:0]         req_id;
        logic [7:0]         timestamp;
        logic               valid;
    } mshr_entry_t;

    // ========================================================================
    // Prefetcher Types
    // ========================================================================
    typedef enum logic [1:0] {
        PREFETCH_NONE       = 2'b00,
        PREFETCH_SEQUENTIAL = 2'b01,
        PREFETCH_STRIDED    = 2'b10,
        PREFETCH_PATTERN    = 2'b11
    } prefetch_type_e;

    // Prefetch Request Structure
    typedef struct packed {
        prefetch_type_e     pref_type;
        addr_t              base_addr;
        logic [15:0]        stride;
        logic [7:0]         distance;
        logic [7:0]         degree;
        logic               enable;
    } prefetch_req_t;

    // ========================================================================
    // Debug and Performance Types
    // ========================================================================
    typedef struct packed {
        logic [DEBUG_COUNTER_WIDTH-1:0] cache_hits;
        logic [DEBUG_COUNTER_WIDTH-1:0] cache_misses;
        logic [DEBUG_COUNTER_WIDTH-1:0] mem_requests;
        logic [DEBUG_COUNTER_WIDTH-1:0] pe_operations;
        logic [DEBUG_COUNTER_WIDTH-1:0] ucie_flits_tx;
        logic [DEBUG_COUNTER_WIDTH-1:0] ucie_flits_rx;
    } perf_counters_t;

    // Error Types
    typedef enum logic [3:0] {
        ERR_NONE            = 4'h0,
        ERR_CACHE_TIMEOUT   = 4'h1,
        ERR_MEM_ERROR       = 4'h2,
        ERR_UCIE_ERROR      = 4'h3,
        ERR_PE_OVERFLOW     = 4'h4,
        ERR_CMD_INVALID     = 4'h5,
        ERR_ADDR_INVALID    = 4'h6,
        ERR_DATA_CORRUPT    = 4'h7
    } error_type_e;

endpackage

`endif // NMCU_TYPES_SV
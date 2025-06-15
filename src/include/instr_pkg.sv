// nmcu_project/src/include/instr_pkg.sv
// Function: Define instruction format and opcodes from CPU to NMCU
package instr_pkg;
    import nmcu_pkg::*;

    // Opcode definitions
    typedef enum logic [3:0] {
        INSTR_NOP       = 4'h0,
        INSTR_LOAD      = 4'h1, // Load data from memory to internal register/cache
        INSTR_STORE     = 4'h2, // Store data from internal register/cache to memory
        INSTR_MAC       = 4'h3, // Matrix Multiply-Accumulate or similar AI operation
        INSTR_HALT      = 4'hF  // Halt operation
    } opcode_t;

    // Instruction format (simplified)
    // CPU sends instructions to NMCU via chiplet interconnect
    // For MAC, 'data' field can be used for dimensions (M,N,K) or other parameters
    typedef struct packed {
        opcode_t               opcode;
        logic [ADDR_WIDTH-1:0] addr_a; // Base address for operand A (or dest for load/store)
        logic [ADDR_WIDTH-1:0] addr_b; // Base address for operand B (or source for store)
        logic [ADDR_WIDTH-1:0] addr_c; // Base address for result C
        logic [DATA_WIDTH-1:0] data;   // General purpose data (e.g., store value,
                                       // dimensions M,N,K for MAC)
        logic [LEN_WIDTH-1:0]  len;    // Length/size for load/store or sub-dimensions for MAC
    } instruction_t;

    // NMCU response to CPU
    typedef struct packed {
        logic               valid;
        logic [DATA_WIDTH-1:0] data;
        logic [1:0]         status; // 0: OK, 1: Error, 2: Busy
    } nmcu_cpu_resp_t;

endpackage : instr_pkg

// nmcu_project/src/cache/cache_system.sv
// Function: Simplified cache system.
// CORRECTED: The arbiter is removed, as the Control Unit is now the only master.
// It now acts as a simple pass-through to the main memory interface.
`include "nmcu_pkg.sv"

module cache_system (
    input  logic                clk,
    input  logic                rst_n,

    // From Control Unit (the only master)
    input  nmcu_pkg::mem_req_t  req_i,
    output nmcu_pkg::mem_resp_t resp_o,

    // To Memory Interface
    output nmcu_pkg::mem_req_t  mem_req_o,
    input  nmcu_pkg::mem_resp_t mem_resp_i
);

    assign mem_req_o = req_i;

    assign resp_o = mem_resp_i;

endmodule

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

    always_comb begin
        mem_req_o = req_i;
        resp_o = mem_resp_i;

        // Debug prints for store operations
        // if (req_i.valid && req_i.write_en) begin
        //     $display("T=%0t [CACHE] Store request - addr=%0d, data=%0d, valid=%b", 
        //             $time, req_i.addr, req_i.wdata, req_i.valid);
        // end
        // if (mem_resp_i.valid) begin
        //     $display("T=%0t [CACHE] Memory response received - valid=%b", $time, mem_resp_i.valid);
        // end
    end

endmodule

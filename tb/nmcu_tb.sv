// Function: Testbench for the top-level NMCU module.
`timescale 1ns / 1ps

module nmcu_tb;

    import nmcu_pkg::*;
    import instr_pkg::*;

    // Clock and Reset
    logic clk;
    logic rst_n;

    // DUT Interface
    logic            cpu_instr_valid;
    instruction_t    cpu_instruction;
    logic            cpu_instr_ready;
    logic            nmcu_resp_valid;
    logic            nmcu_resp_ready;
    nmcu_cpu_resp_t  nmcu_response;

    // Instantiate DUT
    nmcu dut (
        .clk(clk), .rst_n(rst_n),
        .cpu_instr_valid(cpu_instr_valid),
        .cpu_instruction(cpu_instruction),
        .cpu_instr_ready(cpu_instr_ready),
        .nmcu_resp_valid_o(nmcu_resp_valid),
        .nmcu_resp_ready_i(nmcu_resp_ready),
        .nmcu_response_o(nmcu_response)
    );

    // Clock generation
    always #5 clk = ~clk;

    // Main test sequence
    initial begin
        // 1. Initialization
        clk = 0;
        rst_n = 0;
        cpu_instr_valid = 0;
        cpu_instruction = '0;
        nmcu_resp_ready = 1'b1; // Always ready to accept response

        $display("T=%0t [TB] Starting Simulation...", $time);

        // 2. Reset sequence
        #10;
        rst_n = 1;
        $display("T=%0t [TB] Reset released.", $time);

        // 3. Test sequence
        wait(cpu_instr_ready);

        // Test 1: Store value 55 to addr 100, and 2 to addr 101
        send_instr(INSTR_STORE, 100, 0, 0, 55, 1);
        send_instr(INSTR_STORE, 101, 0, 0, 2, 1);

        // Test 2: Load value from addr 100 and check
        send_instr(INSTR_LOAD, 100, 0, 0, 0, 1);
        wait (nmcu_resp_valid);
        if (nmcu_response.data == 55) $display("T=%0t [TB] LOAD test PASSED.", $time);
        else $display("T=%0t [TB] LOAD test FAILED. Expected 55, got %0d", $time, nmcu_response.data);

        // Test 3: Perform MAC(addr_a=100, addr_b=101, result_addr=200)
        $display("T=%0t [TB] Sending MAC instruction.", $time);
        send_instr(INSTR_MAC, 100, 101, 200, 0, 1);
        wait (nmcu_resp_valid); // Wait for MAC completion response
        $display("T=%0t [TB] MAC operation complete.", $time);

        // Test 4: Load result from addr 200 and check (55 * 2 = 110)
        send_instr(INSTR_LOAD, 200, 0, 0, 0, 1);
        wait (nmcu_resp_valid);
        if (nmcu_response.data == 110) $display("T=%0t [TB] MAC test PASSED.", $time);
        else $display("T=%0t [TB] MAC test FAILED. Expected 110, got %0d", $time, nmcu_response.data);

        // 4. Finish simulation
        #100;
        $display("T=%0t [TB] Simulation finished.", $time);
        $finish;
    end

    // Task to send an instruction to the DUT
    task send_instr(
        input opcode_t op,
        input logic [ADDR_WIDTH-1:0] addr_a,
        input logic [ADDR_WIDTH-1:0] addr_b,
        input logic [ADDR_WIDTH-1:0] addr_c,
        input logic [DATA_WIDTH-1:0] data,
        input logic [LEN_WIDTH-1:0]  len
    );
        wait(cpu_instr_ready);
        cpu_instr_valid = 1;
        cpu_instruction.opcode = op;
        cpu_instruction.addr_a = addr_a;
        cpu_instruction.addr_b = addr_b;
        cpu_instruction.addr_c = addr_c;
        cpu_instruction.data   = data;
        cpu_instruction.len    = len;
        @(posedge clk);
        cpu_instr_valid = 0;
    endtask

endmodule
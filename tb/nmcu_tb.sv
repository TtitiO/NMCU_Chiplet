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
    instr_pkg::instruction_t    cpu_instruction;
    logic            cpu_instr_ready;
    logic            nmcu_resp_valid;
    logic            nmcu_resp_ready;
    instr_pkg::nmcu_cpu_resp_t  nmcu_response;

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
        @(posedge clk); // Allow one clock for DUT to come out of reset properly
        @(posedge clk); // Additional clock to ensure control unit is in IDLE state

        // 3. Test sequence
        // Test 1: Store value 55 to addr 100, and 2 to addr 101
        send_instr(INSTR_STORE, 100, 0, 0, 55, 1);
        wait_for_response();
        send_instr(INSTR_STORE, 101, 0, 0, 2, 1);
        wait_for_response();

        // Test 2: Load value from addr 100 and check
        send_instr(INSTR_LOAD, 100, 0, 0, 0, 1);
        wait_for_response();
        if (received_data == 55) $display("T=%0t [TB] LOAD test PASSED.", $time);
        else $display("T=%0t [TB] LOAD test FAILED. Expected 55, got %0d", $time, received_data);

        send_instr(INSTR_LOAD, 101, 0, 0, 0, 1);
        wait_for_response();
        if (received_data == 2) $display("T=%0t [TB] LOAD test PASSED.", $time);
        else $display("T=%0t [TB] LOAD test FAILED. Expected 2, got %0d", $time, received_data);

        // Test 3: Perform MAC and check for completion
        send_instr(INSTR_MAC, 100, 101, 200, 0, 1);
        wait_for_response();
        if(received_status == 2'b00) // Use received_status
            $display("T=%0t [TB] MAC operation reported complete.", $time);
        else
            $display("T=%0t [TB] MAC operation FAILED. Status: %b", $time, received_status);

        // Test 4: Load the result of the MAC and verify
        send_instr(INSTR_LOAD, 200, 0, 0, 0, 1);
        wait_for_response();
        if (received_data == 110 && received_status == 2'b00) // Use received_data and received_status
            $display("T=%0t [TB] MAC result test PASSED.", $time);
        else
            $display("T=%0t [TB] MAC result test FAILED. Expected 110 (OK), got %0d (%b)", $time, received_data, received_status);

        // 4. Finish simulation
        #100;
        $display("T=%0t [TB] Simulation finished.", $time);
        $finish;
    end

    // Task to send an instruction to the DUT. It now waits robustly.
    task automatic send_instr(input opcode_t op, input logic [ADDR_WIDTH-1:0] addr_a, input logic [ADDR_WIDTH-1:0] addr_b, input logic [ADDR_WIDTH-1:0] addr_c, input logic [DATA_WIDTH-1:0] data, input logic [LEN_WIDTH-1:0]  len);
        $display("T=%0t [TB] Waiting for cpu_instr_ready...", $time);
        while (!cpu_instr_ready) begin
            @(posedge clk);
        end
        $display("T=%0t [TB] cpu_instr_ready received, sending instruction...", $time);

        cpu_instr_valid = 1;
        cpu_instruction = '{op, addr_a, addr_b, addr_c, data, len};
        @(posedge clk);
        cpu_instr_valid = 0;
        $display("T=%0t [TB] Instruction sent.", $time);
    endtask

        // Add local variables to store the received data and status
    logic [DATA_WIDTH-1:0] received_data;
    logic [1:0]  received_status; // Assuming response_status_t is defined

    task automatic wait_for_response();
        $display("T=%0t [TB] Waiting for response...", $time);
        while(!nmcu_resp_valid) begin
            @(posedge clk);
        end
        // Capture the response data and status *immediately* when valid is high
        received_data = nmcu_response.data;
        received_status = nmcu_response.status;

        $display("T=%0t [TB] Response received from DUT. Data: %0d, Status: %b", $time, received_data, received_status);
        // Acknowledge the response by pulsing nmcu_resp_ready if needed,
        // or just letting it clear itself if the DUT clears after a cycle.
        // If nmcu_resp_ready is a handshake signal, you might need:
        // nmcu_resp_ready = 1; // Assert ready
        @(posedge clk);
        // nmcu_resp_ready = 0; // De-assert ready (if it's a pulse)

        // For your current setup, where nmcu_resp_ready is always 1,
        // the additional @(posedge clk) might just be to advance time for the DUT
        // to clear the valid signal, which is fine, as long as you've captured the data.
    endtask


endmodule

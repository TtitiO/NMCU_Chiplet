// Function: Testbench for the top-level NMCU module.
// Revision: Updated to demonstrate 4x4 matrix multiplication using systolic array
`timescale 1ns / 1ps

module nmcu_tb;

    import nmcu_pkg::*;
    import instr_pkg::*;

    // --- Testbench Parameters ---
    localparam TIMEOUT_CYCLES = 5000; // Max cycles to wait for a response
    localparam MATRIX_SIZE = 4;       // 4x4 matrix size

    // --- Clock and Reset ---
    logic clk;
    logic rst_n;

    // --- DUT Interface ---
    logic                       cpu_instr_valid;
    instr_pkg::instruction_t    cpu_instruction;
    logic                       cpu_instr_ready;
    logic                       nmcu_resp_valid;
    logic                       nmcu_resp_ready;
    instr_pkg::nmcu_cpu_resp_t  nmcu_response;

    // --- Test Matrices ---
    // Matrix A: 4x4 input matrix
    logic [DATA_WIDTH-1:0] matrix_a [0:3][0:3] = '{
        '{1, 2, 3, 4},
        '{5, 6, 7, 8},
        '{9, 10, 11, 12},
        '{13, 14, 15, 16}
    };

    // Matrix B: 4x4 input matrix
    logic [DATA_WIDTH-1:0] matrix_b [0:3][0:3] = '{
        '{1, 5, 9, 13},
        '{2, 6, 10, 14},
        '{3, 7, 11, 15},
        '{4, 8, 12, 16}
    };

    // Expected result matrix (A * B)
    logic [PSUM_WIDTH-1:0] expected_result [0:3][0:3] = '{
        '{90, 202, 314, 426},
        '{202, 458, 714, 970},
        '{314, 714, 1114, 1514},
        '{426, 970, 1514, 2058}
    };

    // --- Instantiate DUT ---
    nmcu dut (
        .clk(clk),
        .rst_n(rst_n),
        .cpu_instr_valid(cpu_instr_valid),
        .cpu_instruction(cpu_instruction),
        .cpu_instr_ready(cpu_instr_ready),
        .nmcu_resp_valid_o(nmcu_resp_valid),
        .nmcu_resp_ready_i(nmcu_resp_ready),
        .nmcu_response_o(nmcu_response)
    );

    // --- Clock Generation ---
    always #5 clk = ~clk;

    // --- Main Test Sequence ---
    initial begin
        // 1. Initialization
        clk = 0;
        rst_n = 0;
        cpu_instr_valid = 0;
        cpu_instruction = '0;
        nmcu_resp_ready = 1'b1; // Always ready to accept response

        $display("T=%0t [%m] Starting Simulation...", $time);

        // 2. Reset Sequence
        #10;
        rst_n = 1;
        $display("T=%0t [%m] Reset released.", $time);
        @(posedge clk);
        @(posedge clk); // Ensure control unit is in IDLE state

        // 3. Test Sequence - Matrix Multiplication
        $display("T=%0t [%m] ====== Loading Matrix A ======", $time);
        for (int i = 0; i < MATRIX_SIZE; i++) begin
            for (int j = 0; j < MATRIX_SIZE; j++) begin
                send_instr(INSTR_STORE, i*MATRIX_SIZE + j, 0, 0, matrix_a[i][j], 1);
                wait_for_response();
            end
        end

        $display("T=%0t [%m] ====== Loading Matrix B ======", $time);
        for (int i = 0; i < MATRIX_SIZE; i++) begin
            for (int j = 0; j < MATRIX_SIZE; j++) begin
                send_instr(INSTR_STORE, 100 + i*MATRIX_SIZE + j, 0, 0, matrix_b[i][j], 1);
                wait_for_response();
            end
        end

        $display("T=%0t [%m] ====== Performing Matrix Multiplication ======", $time);
        // Perform MAC operation for each element in the result matrix
        for (int i = 0; i < MATRIX_SIZE; i++) begin
            for (int j = 0; j < MATRIX_SIZE; j++) begin
                // Calculate the result address
                int result_addr = 200 + i*MATRIX_SIZE + j;
                // Perform MAC operation
                send_instr(INSTR_MAC, i*MATRIX_SIZE, 100 + j*MATRIX_SIZE, result_addr, 0, MATRIX_SIZE);
                wait_for_response();
                if (received_status != 2'b00)
                    $fatal(1, "T=%0t [%m] FATAL: MAC operation FAILED at position [%0d][%0d]. Status: %b", 
                           $time, i, j, received_status);
            end
        end

        $display("T=%0t [%m] ====== Verifying Results ======", $time);
        // Verify each element of the result matrix
        for (int i = 0; i < MATRIX_SIZE; i++) begin
            for (int j = 0; j < MATRIX_SIZE; j++) begin
                send_instr(INSTR_LOAD, 200 + i*MATRIX_SIZE + j, 0, 0, 0, 1);
                wait_for_response();
                if (received_data != expected_result[i][j]) begin
                    $fatal(1, "T=%0t [%m] FATAL: Result mismatch at [%0d][%0d]. Expected %0d, got %0d", 
                           $time, i, j, expected_result[i][j], received_data);
                end
                $display("T=%0t [%m] INFO: Result at [%0d][%0d] = %0d (PASSED)", 
                        $time, i, j, received_data);
            end
        end

        // 4. Finish simulation
        #100;
        $display("T=%0t [%m] Simulation finished successfully.", $time);
        $finish;
    end

    // Task to send an instruction, with simplified timeout logic.
    task automatic send_instr(
        input opcode_t op,
        input logic [ADDR_WIDTH-1:0] addr_a,
        input logic [ADDR_WIDTH-1:0] addr_b,
        input logic [ADDR_WIDTH-1:0] addr_c,
        input logic [DATA_WIDTH-1:0] data,
        input logic [LEN_WIDTH-1:0]  len
    );
        int timeout_counter = 0;
        $display("T=%0t [%m] Waiting for cpu_instr_ready...", $time);
        while (!cpu_instr_ready) begin
            if (timeout_counter > TIMEOUT_CYCLES) begin
                $fatal(1, "T=%0t [%m] FATAL: Timeout waiting for cpu_instr_ready. DUT may be stuck.", $time);
            end
            timeout_counter++;
            @(posedge clk);
        end

        $display("T=%0t [%m] cpu_instr_ready received, sending instruction...", $time);
        cpu_instr_valid = 1;
        cpu_instruction = '{
            opcode: op,
            addr_a: addr_a,
            addr_b: addr_b,
            addr_c: addr_c,
            data:   data,
            len:    len
        };
        @(posedge clk);
        cpu_instr_valid = 0;
        $display("T=%0t [%m] Instruction sent.", $time);
    endtask

    // Local variables to capture the response from the DUT.
    logic [DATA_WIDTH-1:0] received_data;
    logic [1:0]            received_status;

    // Task to wait for a response, with simplified timeout logic.
    task automatic wait_for_response();
        int timeout_counter = 0;
        $display("T=%0t [%m] Waiting for response...", $time);
        while (!nmcu_resp_valid) begin
            if (timeout_counter > TIMEOUT_CYCLES) begin
                $fatal(1, "T=%0t [%m] FATAL: Timeout waiting for nmcu_resp_valid. DUT did not respond.", $time);
            end
            timeout_counter++;
            @(posedge clk);
        end

        received_data   = nmcu_response.data;
        received_status = nmcu_response.status;
        $display("T=%0t [%m] Response received. Data: %0d, Status: %b", $time, received_data, received_status);

        @(posedge clk);
    endtask

endmodule

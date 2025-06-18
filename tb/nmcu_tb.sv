// Function: Testbench for the top-level NMCU module.
// Revision: Updated to demonstrate 4x4 matrix multiplication using systolic array
`timescale 1ns / 1ps

module nmcu_tb;

    import nmcu_pkg::*;
    import instr_pkg::*;

    // --- Testbench Parameters ---
    localparam TIMEOUT_CYCLES = 10000; // Max cycles to wait for a response
    localparam MATRIX_N = 2;
    localparam MATRIX_M = 2;
    localparam MATRIX_K = 2;

    // --- Define memory layout ---
    localparam ADDR_A_BASE = 0;
    localparam ADDR_B_BASE = 100;
    localparam ADDR_C_BASE = 200;

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
    logic [DATA_WIDTH-1:0] matrix_a [0:MATRIX_N-1][0:MATRIX_K-1] = '{
        '{1, 2},
        '{3, 4}
    };

    logic [DATA_WIDTH-1:0] matrix_b [0:MATRIX_K-1][0:MATRIX_M-1] = '{
        '{5, 6},
        '{7, 8}
    };

    // Expected Result C = A * B
    // C[0][0] = (1*5) + (2*7) = 19
    // C[0][1] = (1*6) + (2*8) = 22
    // C[1][0] = (3*5) + (4*7) = 43
    // C[1][1] = (3*6) + (4*8) = 50
    logic [PSUM_WIDTH-1:0] expected_result [0:MATRIX_N-1][0:MATRIX_M-1] = '{
        '{19, 22},
        '{43, 50}
     };

    logic [PSUM_WIDTH-1:0] result_matrix_c [0:MATRIX_N-1][0:MATRIX_M-1];

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
        @(posedge clk);

        // 3. Test Sequence - Matrix Multiplication
        $display("T=%0t [%m] ====== Loading Matrix A ======", $time);
        for (int i = 0; i < MATRIX_N; i++) begin
            for (int j = 0; j < MATRIX_K; j++) begin
                // FIX: Pass dummy values for N, M, K to prevent assignment error
                send_instr(INSTR_STORE, ADDR_A_BASE + (i * MATRIX_K + j), 0, 0, matrix_a[i][j], 1, '0, '0, '0);
                wait_for_response();
            end
        end

        $display("T=%0t [%m] ====== Loading Matrix B ======", $time);
        for (int i = 0; i < MATRIX_K; i++) begin
            for (int j = 0; j < MATRIX_M; j++) begin
                // FIX: Pass dummy values for N, M, K to prevent assignment error
                send_instr(INSTR_STORE, ADDR_B_BASE + (i * MATRIX_M + j), 0, 0, matrix_b[i][j], 1, '0, '0, '0);
                wait_for_response();
            end
        end

        $display("T=%0t [%m] ====== Performing Matrix Multiplication ======", $time);
        send_instr(INSTR_MATMUL, ADDR_A_BASE, ADDR_B_BASE, ADDR_C_BASE, 0, 0, MATRIX_N, MATRIX_M, MATRIX_K);
        wait_for_response();
        if (received_status != 2'b00)
            $fatal(1, "T=%0t [%m] FATAL: MATMUL operation FAILED. Status: %b", $time, received_status);
        $display("T=%0t [%m] INFO: MATMUL operation complete.", $time);

        $display("T=%0t [%m] ====== Verifying Results ======", $time);
        for (int i = 0; i < MATRIX_N; i++) begin
            for (int j = 0; j < MATRIX_M; j++) begin
                // FIX: Pass dummy values for N, M, K to prevent assignment error
                send_instr(INSTR_LOAD, ADDR_C_BASE + (i * MATRIX_M + j), 0, 0, 0, 1, '0, '0, '0);
                wait_for_response();
                result_matrix_c[i][j] = received_data;
                if (received_data != expected_result[i][j]) begin
                    $display("T=%0t [%m] FATAL: Result mismatch at C[%0d][%0d]. Expected %0d, got %0d",
                           $time, i, j, expected_result[i][j], received_data);
                end else begin
                    $display("T=%0t [%m] INFO: Result at C[%0d][%0d] = %0d (PASSED)",
                            $time, i, j, received_data);
                end
            end
        end

        // display the test matrix a and b
        $display("\nT=%0t [%m] ====== Test Matrix A ======", $time);
        $display("┌─────┬─────┐");
        for (int i = 0; i < MATRIX_N; i++) begin
            $write("│");
            for (int j = 0; j < MATRIX_K; j++) begin
                $write(" %3d │", matrix_a[i][j]);
            end
            $display();
            if (i < MATRIX_N-1) begin
                $display("├─────┼─────┤");
            end
        end
        $display("└─────┴─────┘\n");

        $display("\nT=%0t [%m] ====== Test Matrix B ======", $time);
        $display("┌─────┬─────┐");
        for (int i = 0; i < MATRIX_K; i++) begin
            $write("│");
            for (int j = 0; j < MATRIX_M; j++) begin
                $write(" %3d │", matrix_b[i][j]);
            end
            $display();
            if (i < MATRIX_K-1) begin
                $display("├─────┼─────┤");
            end
        end
        $display("└─────┴─────┘\n");

        // display the expected result matrix c
        $display("\nT=%0t [%m] ====== Expected Result Matrix C ======", $time);
        $display("┌─────┬─────┐");
        for (int i = 0; i < MATRIX_N; i++) begin
            $write("│");
            for (int j = 0; j < MATRIX_M; j++) begin
                $write(" %3d │", expected_result[i][j]);
            end
            $display();
            if (i < MATRIX_N-1) begin
                $display("├─────┼─────┤");
            end
        end
        $display("└─────┴─────┘\n");

        // result matrix c
        $display("\nT=%0t [%m] ====== Result Matrix C ======", $time);
        $display("┌─────┬─────┐");
        for (int i = 0; i < MATRIX_N; i++) begin
            $write("│");
            for (int j = 0; j < MATRIX_M; j++) begin
                $write(" %3d │", result_matrix_c[i][j]);
            end
            $display();
            if (i < MATRIX_N-1) begin
                $display("├─────┼─────┤");
            end
        end
        $display("└─────┴─────┘\n");

        #100;
        $display("T=%0t [%m] Simulation finished successfully.", $time);
        $finish;
    end

    // Task to send an instruction
    task automatic send_instr(
        input opcode_t op,
        input logic [ADDR_WIDTH-1:0] addr_a,
        input logic [ADDR_WIDTH-1:0] addr_b,
        input logic [ADDR_WIDTH-1:0] addr_c,
        input logic [DATA_WIDTH-1:0] data,
        input logic [LEN_WIDTH-1:0]  len,
        input logic [LEN_WIDTH-1:0] N,
        input logic [LEN_WIDTH-1:0] M,
        input logic [LEN_WIDTH-1:0] K
    );
        wait (cpu_instr_ready);

        $display("T=%0t [%m] DUT is ready, sending instruction %s", $time, op.name());
        cpu_instr_valid = 1;
        // FIX: Assign all fields explicitly to prevent assignment pattern errors.
        cpu_instruction.opcode = op;
        cpu_instruction.addr_a = addr_a;
        cpu_instruction.addr_b = addr_b;
        cpu_instruction.addr_c = addr_c;
        cpu_instruction.data   = data;
        cpu_instruction.len    = len;
        cpu_instruction.N      = N;
        cpu_instruction.M      = M;
        cpu_instruction.K      = K;

        @(posedge clk);
        cpu_instr_valid = 0;
    endtask

    // Local variables to capture the response from the DUT.
    logic [PSUM_WIDTH-1:0] received_data;
    logic [1:0]            received_status;

    // Task to wait for a response
    task automatic wait_for_response();
        int timeout_counter = 0;
        while (!nmcu_resp_valid) begin
            if (timeout_counter > TIMEOUT_CYCLES) begin
                $fatal(1, "T=%0t [%m] FATAL: Timeout waiting for nmcu_resp_valid. DUT did not respond.", $time);
            end
            timeout_counter++;
            @(posedge clk);
        end

        received_data   = nmcu_response.data;
        received_status = nmcu_response.status;
        $display("T=%0t [%m] Response received. Status: %b, Data: %0d", $time, received_status, received_data);

        @(posedge clk);
    endtask

endmodule

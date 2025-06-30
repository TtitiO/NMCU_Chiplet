# NMCU_Chiplet

## General NMCU Architecture
```text
+---------------------------------------------------------------------------------+
|                                 NMCU Chiplet                                    |
|                                                                                 |
|  +---------------------------+      +--------------------------+                |
|  | Chiplet Interconnect I/F  |<---->|     Control Unit &       |                |
|  | (e.g., UCIe Adapter)      |      |     Instruction Decoder  |----(Commands,  |
|  +---------------------------+      +------------+-------------+     Data      |
|                                                  |   ^           Operands)   |
|                               (Cache Req/Resp)   |   | (Result)              |
|                                                  v   |                       v
|  +---------------------------------------------------+--------------+  +----------+------------------+
|  |                         Cache System                          |  | PE Array Interface/          |
|  | +----------------------+  +---------------------------------+ |  | Data Dispatcher (FIFOs)      |
|  | | Cache Controller     |  |          Cache Memory           | |  +--------------------------+
|  | | (incl. MSHR,         |<->| +-----------+   +-----------+   | |              |
|  | |  Prefetcher)         |  | | Tag Array |   | Data Array|   | |              v
|  | +--------+-------------+  | +-----------+   +-----------+   | |  +---------------------------+
|  |          |               +---------------------------------+ |  |  Processing Element Array |
|  +----------|---------------------------------------------------+  |  (e.g., Systolic Array)   |
|             | (Fill/Writeback Requests)                            |  +----+----+----+----+    |
|             v                                                      |  | PE | PE | PE | PE |    |
|   +------------------------+                                       |  +----+----+----+----+    |
|   |  Memory Interface      |                                       |  ...                      |
|   |  Controller (to HBM/   |                                       |  ...                      |
|   |  DDR)                  |                                       +---------------------------+
|   +------------------------+                                                    
|                                                                                 
+---------------------------------------------------------------------------------+
```

```mermaid
stateDiagram-v2
    direction TD

    [*] --> IDLE
    IDLE: Wait for new instruction
    IDLE --> IDLE: "No new instruction"
    IDLE --> EXECUTE_MEM: "Instruction is LOAD/STORE"
    IDLE --> INIT_MATMUL: "Instruction is MATMUL"
    IDLE --> RESPOND_CPU: "Instruction is NOP/HALT"

    state "Memory Operations" as mem_ops {
        EXECUTE_MEM: Issue Read/Write to Cache
        EXECUTE_MEM --> RESPOND_CPU: "Cache response valid"
    }

    state "Matrix Multiplication (C=A*B)" as matmul_ops {
        INIT_MATMUL: Initialize tile counters (i,j,k=0)
        INIT_MATMUL --> FETCH_A_TILE

        FETCH_A_TILE: Read A tile from Memory, Store in pe_a_tile_buffer
        FETCH_A_TILE --> FETCH_B_TILE: "A tile buffer full"

        FETCH_B_TILE: Read B tile from Memory, Store in pe_b_tile_buffer
        FETCH_B_TILE --> STREAM_PE_DATA: "B tile buffer full"

        STREAM_PE_DATA: Stream A/B buffers to PE Array
        STREAM_PE_DATA --> LATCH_PE_RESULTS: "Streaming complete"

        LATCH_PE_RESULTS: Wait for pe_done_i, Buffer results from pe_result_i
        LATCH_PE_RESULTS --> UPDATE_TILE_ADDRS: "PEs done"

        UPDATE_TILE_ADDRS: Increment k_tile
        UPDATE_TILE_ADDRS --> FETCH_A_TILE: "More tiles in K"
        UPDATE_TILE_ADDRS --> STORE_C_TILE: "k_tile loop complete"

        STORE_C_TILE: Write pe_result_buffer to Memory
        STORE_C_TILE --> RESPOND_CPU: "MATMUL Complete"
    }

    RESPOND_CPU: Send status/data to CPU
    RESPOND_CPU --> IDLE: "CPU ready for response"

```

### Control Unit & Instruction Decoder

```mermaid
graph TD
    subgraph "Host System"
        CPU
    end

    subgraph "NMCU Chiplet"
        direction LR
        CU["🎛️<br/>Control Unit &<br/>Instruction Decoder"]
        CACHE["💾<br/>Cache System<br/>(Memory Interface)"]
        PE_ARRAY["🔢<br/>4x4 Systolic PE Array"]
    end
    
    CPU -- "Instruction (e.g., MATMUL)" --> CU
    CU -- "Memory Requests (Addr, R/W)" --> CACHE
    CACHE -- "Data" --> CU
    CU -- "Skewed Operands (A, B)" --> PE_ARRAY
    PE_ARRAY -- "Done Signal" --> CU
    CU -- "Writeback Request (C)" --> CACHE
    CU -- "Completion Response" --> CPU
```


```mermaid
stateDiagram-v2
    direction LR

    [*] --> IDLE
    IDLE: Assert cpu_instr_ready\nWait for new instruction
    IDLE --> IDLE: "No new instruction"
    IDLE --> EXECUTE_MEM: "Instruction is LOAD/STORE"
    IDLE --> INIT_MATMUL: "Instruction is MATMUL"
    IDLE --> RESPOND_CPU: "Instruction is NOP/HALT"

    state "Memory Operations" as mem_ops {
        EXECUTE_MEM: Issue Read/Write to Cache\n(cache_req_o)\nWait for response
        EXECUTE_MEM --> RESPOND_CPU: "Cache response valid"
    }

    state "Matrix Multiplication (C=A*B)" as matmul_ops {
        INIT_MATMUL: Latch N, M, K, Addrs\nInitialize tile counters (i,j,k=0)
        INIT_MATMUL --> FETCH_A_TILE

        FETCH_A_TILE: Read A tile from Memory\n(based on i_tile, k_tile)\nStore in pe_a_tile_buffer
        FETCH_A_TILE --> FETCH_B_TILE: "A tile buffer full"

        FETCH_B_TILE: Read B tile from Memory\n(based on j_tile, k_tile)\nStore in pe_b_tile_buffer
        FETCH_B_TILE --> STREAM_PE_DATA: "B tile buffer full"

        STREAM_PE_DATA: Stream A/B buffers\nto PE Array via\npe_operand_a/b_o
        STREAM_PE_DATA --> LATCH_PE_RESULTS: "Streaming complete"

        LATCH_PE_RESULTS: Wait for pe_done_i\nBuffer results from\npe_result_i
        LATCH_PE_RESULTS --> UPDATE_TILE_ADDRS: "PEs done"

        UPDATE_TILE_ADDRS: Increment k_tile
        UPDATE_TILE_ADDRS --> FETCH_A_TILE: "More tiles in K"
        UPDATE_TILE_ADDRS --> STORE_C_TILE: "k_tile loop complete"

        STORE_C_TILE: Write pe_result_buffer\nto Memory (Matrix C)
        STORE_C_TILE --> FETCH_A_TILE: "More C tiles to compute"
        STORE_C_TILE --> RESPOND_CPU: "MATMUL Complete"
    }

    RESPOND_CPU: Assert nmcu_resp_valid_o\nSend status/data to CPU
    RESPOND_CPU --> IDLE: "CPU ready for response"
```

## Project Tree
```text
nmcu_project/
├── src/
│   ├── include/
│   │   ├── nmcu_pkg.sv                # Global parameters and common types
│   │   └── instr_pkg.sv               # Instruction opcodes and formats
│   ├── chiplets/
│   │   └── nmcu.sv                    # Top-level NMCU module
│   ├── interconnect/
│   │   └── chiplet_interconnect_if.sv # Placeholder for chiplet interconnect interface 
│   ├── control/
│   │   └── control_unit_decoder.sv    # Control Unit & Instruction Decoder
│   ├── cache/
│   │   └── cache_system.sv            # Simplified Cache System (bypass logic for now)
│   ├── pe/
│   │   ├── pe_array_interface.sv      # PE Array Interface & Data Dispatcher
│   │   └── pe_array.sv                # Processing Element Systolic Array
│   └── mem_ctrl/
│       └── memory_interface.sv        # Interface to external memory (DDR)
└── tb/
    └── nmcu_tb.sv                     # Testbench for NMCU module
```

## Features
- [x] Implement Basic structure of NMCU
- [x] Implement systolic array with 4x4 PE array
    - [ ] change PE size to user-defined
- [ ] Implement complete cache module design
- [ ] Support complete memory interface
- [ ] Integrate ddr4 memory module.
- [ ] Implement Chiplet interconnection
- [ ] Enhance *fan-out* systolic arrays functionality. 
    - [ ] Weight Stationary
    - [ ] Input Stationary
    - [ ] Output Stationary
    - [ ] Row Stationary
- [ ] Experiment&Evaluation
    - [ ] Hardware Design Space Exploration
    - [ ] Transformers Benchmarking



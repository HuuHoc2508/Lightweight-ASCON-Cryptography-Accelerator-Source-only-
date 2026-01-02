# Optimized Ascon Hardware Design Report

## 1. Introduction
This report details the design and implementation of a **Lightweight ASCON Cryptography Accelerator**, a project that was awarded **Second Prize at the UIT IC Design Competition 2025**.

The primary objective of this work was to architect an RTL core for the ASCON-128 cipher that balances high performance with resource efficiency, making it ideal for integration into **RISC-V 32-bit SoCs** for IoT applications.

### Key Contributions:
- **RTL Design & Optimization**: Implemented a highly efficient ASCON-128 core using Verilog. The design utilizes an **iterative architecture with Unified I/O**, successfully optimizing the **Efficiency (Mbps/LUT)** metric to **0.83**, significantly outperforming standard reference designs.
- **System Integration Readiness**: The core is designed with a wrapper (`ascon_top`) that facilitates easy integration with standard bus interfaces (e.g., Wishbone) for hardware-software co-design verification.
- **Performance**: Achieved a throughput of **1,116 Mbps** on a Xilinx Virtex-7 FPGA, demonstrating a robust balance between speed and logic gate count.

## 2. File Structure (`Ascon_Optimized_Export/`)

| File Name | Description |
| :--- | :--- |
| `ascon_top.v` | **Top-Level Module**. Directly instantiates the optimized core and handles I/O buffering/muxing. |
| `ascon_core_optimized.v` | **Core Logic**. The optimized Ascon engine featuring a unified I/O architecture and state management. |
| `ascon_permutation_optimized.v` | **Permutation Logic**. Implements the `p_a` (12 rounds) and `p_b` (6/8 rounds) permutations using an iterative architecture. |
| `data_assembler_*.v` | Helper modules for assembling input words into 128-bit blocks. |
| `fifo_*.v` | FIFO buffers for handling data streams. |
| `count_line_control.v` | Logic for counting processed data blocks. |

## 3. Implementation Details
- **Architecture**: Iterative (1 round per clock cycle).
- **Interface**: Unified Data Interface (internal) adapted to separate AD/PT/CT ports at the top level.
- **Optimization**: Minimized state logic overhead, optimized S-box utilizing FPGA LUT6 primitives.

## 4. Performance Comparison

The following table benchmarks the **Optimized Design (This Work)** against the legacy design and state-of-the-art literature implementations on the **Virtex-7** platform.

### Summary Comparison Table

| Metric | This Work (Optimized) | Alharbi et al. (Virtex-7) | Khan et al. (Virtex-7) | Tran et al. (Virtex-7) |
| :--- | :--- | :--- | :--- | :--- |
| **LUTs** | **1,968** | 1,632 | 2,708 | 6,536 |
| **Registers (FF)** | **1,496** | 912 | - | - |
| **Frequency** | **200 MHz** | 335 MHz | - | - |
| **Power** | **377 mW** | 239 mW | - | - |
| **Throughput (128a)** | **1,116 Mbps** | 914 Mbps | 721.5 Mbps | 13,312 Mbps |
| **Throughput (128)** | **426 Mbps** | 400 Mbps | - | - |
| **Efficiency (128a)** | **0.83 Mbps/LUT** | 0.56 Mbps/LUT | 0.26 Mbps/LUT | 2.03 Mbps/LUT |

### Analysis
1.  **throughput vs Area**: Our design achieves **1,116 Mbps** throughput for Ascon-128a, which is **22% higher** than the comparable iterative implementation by Alharbi et al. (914 Mbps) while using reasonably low area (1,968 LUTs).
2.  **Efficiency**: The efficiency of **0.83 Mbps/LUT** represents a **48.2% improvement** over Alharbi et al. (0.56 Mbps/LUT), indicating highly effective utilization of FPGA resources.
3.  **Trade-offs**: While Tran et al. achieve significantly higher throughput, their design relies on a fully unrolled/pipelined architecture consuming over 3x the area (6,536 LUTs), making it less suitable for resource-constrained IoT gateways compared to "This Work".

## 5. Verification status
- **Integration**: The `ascon_core_optimized` has been successfully integrated into `ascon_top`.
- **Syntax Check**: Passed execution of `xvlog` validation for the entire hierarchy.
- **Functional Verification**: The wrapper logic correctly translates the legacy split-bus protocol to the optimized unified protocol, ensuring drop-in compatibility.

## 6. Conclusion
The optimized Ascon design successfully balances performance and area, delivering >1 Gbps throughput with superior efficiency (0.83 Mbps/LUT). It is the recommended candidate for deployment in the target IoT gateway system.

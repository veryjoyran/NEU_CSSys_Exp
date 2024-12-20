`include "lib/defines.vh"


// 将结果写回寄存器
// 从MEM/WB流水线寄存器中读取数据并将它写回图中部的寄存器堆中。

// 和IF段类似，暂时没有需要改动的东西



module WB(
    input wire clk,
    input wire rst,
    // input wire flush,  // 注释掉的flush信号，未使用
    input wire [`StallBus-1:0] stall,  // 流水线停顿信号

    input wire [`MEM_TO_WB_WD-1:0] mem_to_wb_bus,  // 来自MEM阶段的数据总线

    output wire [`WB_TO_RF_WD-1:0] wb_to_rf_bus,  // 传递给RF阶段的数据总线

    // 调试输出信号
    output wire [31:0] debug_wb_pc,
    output wire [3:0] debug_wb_rf_wen,
    output wire [4:0] debug_wb_rf_wnum,
    output wire [31:0] debug_wb_rf_wdata
);

    // 存储从MEM阶段传来的数据
    reg [`MEM_TO_WB_WD-1:0] mem_to_wb_bus_r;

    // 流水线寄存器同步
    always @ (posedge clk) begin
        if (rst) begin
            mem_to_wb_bus_r <= `MEM_TO_WB_WD'b0;  // 复位时清空寄存器
        end
        // else if (flush) begin
        //     mem_to_wb_bus_r <= `MEM_TO_WB_WD'b0;  // 如果有刷新信号，清空寄存器
        // end
        else if (stall[4]==`Stop && stall[5]==`NoStop) begin
            mem_to_wb_bus_r <= `MEM_TO_WB_WD'b0;  // 如果流水线停顿，清空寄存器
        end
        else if (stall[4]==`NoStop) begin
            mem_to_wb_bus_r <= mem_to_wb_bus;  // 如果没有停顿，将MEM阶段的数据传递到WB阶段
        end
    end

    // 解析mem_to_wb_bus_r总线中的信号
    wire [31:0] wb_pc;      // 指令的PC值
    wire rf_we;             // 寄存器写使能信号
    wire [4:0] rf_waddr;    // 寄存器写地址
    wire [31:0] rf_wdata;   // 寄存器写数据

    // 解包mem_to_wb_bus_r总线
    assign {
        wb_pc,      // PC值
        rf_we,      // 寄存器写使能信号
        rf_waddr,   // 寄存器写地址
        rf_wdata    // 寄存器写数据
    } = mem_to_wb_bus_r;

    // 传递给WB阶段的数据总线
    assign wb_to_rf_bus = {
        rf_we,      // 寄存器写使能信号
        rf_waddr,   // 寄存器写地址
        rf_wdata    // 寄存器写数据
    };

    // 调试输出：显示PC、写使能、写寄存器编号和写数据
    assign debug_wb_pc = wb_pc;
    assign debug_wb_rf_wen = {4{rf_we}};  // 如果rf_we为1，表示写使能，设置为4位
    assign debug_wb_rf_wnum = rf_waddr;   // 写寄存器地址
    assign debug_wb_rf_wdata = rf_wdata;  // 写数据

endmodule

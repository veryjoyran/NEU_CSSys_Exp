`include "lib/defines.vh"

module MEM(
    input wire clk,
    input wire rst,
    // input wire flush,  // 注释掉的 flush 信号，未使用
    input wire [`StallBus-1:0] stall,  // 流水线停顿信号

    input wire [`EX_TO_MEM_WD-1:0] ex_to_mem_bus,  // 来自EX阶段的数据总线
    input wire [31:0] data_sram_rdata,  // 数据存储器的读取数据

    output wire [`MEM_TO_WB_WD-1:0] mem_to_wb_bus  // 传递给WB阶段的数据总线
);

    // 存储从EX阶段传来的数据
    reg [`EX_TO_MEM_WD-1:0] ex_to_mem_bus_r;

    // 流水线寄存器同步
    always @ (posedge clk) begin
        if (rst) begin
            ex_to_mem_bus_r <= `EX_TO_MEM_WD'b0;  // 复位时清空寄存器
        end
        // else if (flush) begin
        //     ex_to_mem_bus_r <= `EX_TO_MEM_WD'b0;  // 如果有刷新信号，清空寄存器
        // end
        else if (stall[3]==`Stop && stall[4]==`NoStop) begin
            ex_to_mem_bus_r <= `EX_TO_MEM_WD'b0;  // 如果流水线停顿，清空寄存器
        end
        else if (stall[3]==`NoStop) begin
            ex_to_mem_bus_r <= ex_to_mem_bus;  // 如果没有停顿，传递EX阶段的数据
        end
    end

    // 从ex_to_mem_bus_r中提取出各个信号
    wire [31:0] mem_pc;       // 指令的PC值
    wire data_ram_en;         // 数据存储器使能信号
    wire [3:0] data_ram_wen;  // 数据存储器写使能信号
    wire sel_rf_res;          // 寄存器写回选择
    wire rf_we;               // 寄存器写使能
    wire [4:0] rf_waddr;      // 寄存器写地址
    wire [31:0] rf_wdata;     // 寄存器写数据
    wire [31:0] ex_result;    // EX阶段的结果
    wire [31:0] mem_result;   // MEM阶段的结果

    // 解析EX阶段到MEM阶段的数据总线
    assign {
        mem_pc,         // PC值
        data_ram_en,    // 数据存储器使能信号
        data_ram_wen,   // 数据存储器写使能信号
        sel_rf_res,     // 寄存器写回选择
        rf_we,          // 寄存器写使能
        rf_waddr,       // 寄存器写地址
        ex_result       // EX阶段的执行结果
    } =  ex_to_mem_bus_r;

    // 设置寄存器写数据，选择来自MEM阶段还是EX阶段
    assign rf_wdata = sel_rf_res ? mem_result : ex_result;

    // 传递给WB阶段的数据总线
    assign mem_to_wb_bus = {
        mem_pc,     // PC值
        rf_we,      // 寄存器写使能信号
        rf_waddr,   // 寄存器写地址
        rf_wdata    // 寄存器写数据
    };

endmodule

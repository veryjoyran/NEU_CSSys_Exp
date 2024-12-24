// 访问内存操作
// 可能从EX/MEM流水线寄存器中得到地址读取数据寄存器，并将数据存入MEM/WB流水线寄存器。
// 这段代码处理内存访问（访存）指令的操作，并决定如何将内存读取的结果传递到下一阶段（WB阶段），
// 如果指令需要从内存中读取数据，它将在此阶段完成数据的加载。

`include "lib/defines.vh"  // 引入宏定义文件，定义一些常量

module MEM(
    input wire clk,  // 时钟信号
    input wire rst,  // 复位信号
    // input wire flush,  // 此信号未使用，可能用于刷新操作
    input wire [`StallBus-1:0] stall,  // 流水线停顿信号，控制流水线是否继续执行

    input wire [`EX_TO_MEM_WD-1:0] ex_to_mem_bus,  // 从EX阶段传来的数据总线，包含内存操作相关信息
    input wire [31:0] data_sram_rdata,  // 从数据内存（SRAM）读取的数据
    input wire [3:0] data_ram_sel,  // 数据内存选择信号，控制不同类型的访存操作（字节、半字、字等）
    input wire [`LoadBus-1:0] ex_load_bus,  // EX阶段传递的加载操作控制信号（例如是否进行加载）

    output wire [`MEM_TO_WB_WD-1:0] mem_to_wb_bus,  // 传递到WB阶段的总线，包含写回寄存器的数据
    output wire [`MEM_TO_RF_WD-1:0] mem_to_rf_bus  // 传递到寄存器堆的总线，包含写回的数据
);

    // 中间寄存器，用于保存EX阶段的结果和控制信号
    reg [`LoadBus-1:0] ex_load_bus_r;  // EX阶段加载指令的信号寄存器
    reg [3:0] data_ram_sel_r;  // 数据内存选择信号寄存器

    reg [`EX_TO_MEM_WD-1:0] ex_to_mem_bus_r;  // EX到MEM阶段的数据总线寄存器

    always @ (posedge clk) begin
        if (rst) begin
            // 如果复位信号为高电平，清空寄存器的内容
            ex_to_mem_bus_r <= `EX_TO_MEM_WD'b0;  // 清空EX到MEM的总线数据
            data_ram_sel_r <= 3'b0;  // 清空数据内存选择信号
            ex_load_bus_r <= `LoadBus'b0;  // 清空EX阶段的加载信号
        end
        // else if (flush) begin
        //     ex_to_mem_bus_r <= `EX_TO_MEM_WD'b0;  // 此部分代码可能用于处理flush操作，暂时没有启用
        // end
        else if (stall[3]==`Stop && stall[4]==`NoStop) begin
            // 如果流水线停顿（stall）信号指示当前阶段需要停顿，清空寄存器内容
            ex_to_mem_bus_r <= `EX_TO_MEM_WD'b0;  // 清空EX到MEM的总线数据
            data_ram_sel_r <= 3'b0;  // 清空数据内存选择信号
            ex_load_bus_r <= `LoadBus'b0;  // 清空EX阶段的加载信号
        end
        else if (stall[3]==`NoStop) begin
            // 如果流水线没有停顿，更新寄存器的内容
            ex_to_mem_bus_r <= ex_to_mem_bus;  // 更新EX到MEM的总线数据
            data_ram_sel_r <= data_ram_sel;  // 更新数据内存选择信号
            ex_load_bus_r <= ex_load_bus;  // 更新EX阶段的加载信号
        end
    end

    // 从EX到MEM阶段的数据总线解析
    wire [31:0] mem_pc;  // MEM阶段的PC地址
    wire data_ram_en;  // 数据内存使能信号，控制是否启用内存读取
    wire [3:0] data_ram_wen;  // 数据内存写使能信号，控制内存写入的字节
    wire sel_rf_res;  // 控制是否从内存结果选择数据
    wire rf_we;  // 寄存器文件写使能信号，控制是否写回寄存器
    wire [4:0] rf_waddr;  // 寄存器写地址
    wire [31:0] rf_wdata;  // 写回寄存器的数据
    wire [31:0] ex_result;  // EX阶段的结果
    wire [31:0] mem_result;  // MEM阶段的结果

    // 加载指令类型信号
    wire inst_lb, inst_lbu, inst_lh, inst_lhu, inst_lw;
    wire [7:0] b_data;  // 字节数据
    wire [15:0] h_data;  // 半字数据
    wire [31:0] w_data;  // 字数据

    // 将EX到MEM阶段的总线数据拆解
    assign {
        mem_pc,         // 从EX阶段传来的PC地址
        data_ram_en,    // 数据内存使能信号
        data_ram_wen,   // 数据内存写使能信号
        sel_rf_res,     // 是否从内存结果选择数据
        rf_we,          // 寄存器文件写使能信号
        rf_waddr,       // 寄存器写地址
        ex_result       // EX阶段的计算结果
    } =  ex_to_mem_bus_r;

    // 拆解EX阶段的加载指令控制信号
    assign {
        inst_lb,  // 处理字节加载指令
        inst_lbu, // 处理无符号字节加载指令
        inst_lh,  // 处理半字加载指令
        inst_lhu, // 处理无符号半字加载指令
        inst_lw   // 处理字加载指令
    } = ex_load_bus_r;

    // 根据选择信号决定写回的数据来源，优先选择内存结果
    assign rf_wdata = sel_rf_res ? mem_result : ex_result;

    // 如果数据内存使能信号有效，则读取数据，否则为0
    assign mem_result = data_ram_en ? data_sram_rdata : 32'b0;

    // 处理不同数据类型的加载结果（目前这些值暂时设为0，因为只关心32位数据）
    assign b_data = 8'b0;  // 字节数据
    assign h_data = 16'b0;  // 半字数据
    assign w_data = data_sram_rdata;  // 字数据，直接使用从内存读取的数据

    // 将MEM阶段的结果传递到WB阶段
    assign mem_to_wb_bus = {
        mem_pc,     // 传递PC地址
        rf_we,      // 寄存器写使能信号
        rf_waddr,   // 寄存器写地址
        rf_wdata    // 寄存器写数据
    };

    // 将MEM阶段的结果传递到寄存器堆
    assign mem_to_rf_bus = {
        // mem_pc,  // 这里暂时没有传递PC地址
        rf_we,      // 寄存器写使能信号
        rf_waddr,   // 寄存器写地址
        rf_wdata    // 寄存器写数据
    };

endmodule

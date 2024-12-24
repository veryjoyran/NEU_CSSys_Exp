// 执行运算或计算地址（反正就是和alu相关）
// 从ID/EX流水线存器中读取由存器1传过来的值和存器2传过来的值
// （或存器1传过来的值和符号扩展过后的立即数的值），
// 并用ALU将它们相加，结果值存入EX/MEM流水线存器。

// alu模块已经提供，基本通过给alu提供控制信号就可以完成逻辑和算术运算
// 对于需要访存的指令在此段发出访存请求
`include "lib/defines.vh"

module EX(
    input wire clk,  // 时钟信号
    input wire rst,  // 复位信号
    input wire flush,  // 流水线冲刷信号（未使用）
    input wire [`StallBus-1:0] stall,  // 停顿信号

    input wire [`ID_TO_EX_WD-1:0] id_to_ex_bus,  // 从ID阶段到EX阶段的数据总线
    // LW SW：从ID阶段传递的load和save信号
    input wire [`LoadBus-1:0] id_load_bus,  // load信号
    input wire [`SaveBus-1:0] id_save_bus,  // save信号

    output wire [`EX_TO_MEM_WD-1:0] ex_to_mem_bus,  // 从EX阶段到MEM阶段的数据总线
    output wire [`EX_TO_RF_WD-1:0] ex_to_rf_bus,    // 从EX阶段到寄存器文件的数据总线

    output wire data_sram_en,    // 数据SRAM使能信号
    output wire [3:0] data_sram_wen,  // 数据SRAM写使能信号
    output wire [31:0] data_sram_addr,  // 数据SRAM地址
    output wire [31:0] data_sram_wdata,  // 数据SRAM写数据
    output wire [3:0] data_ram_sel,  // 数据RAM选择信号
    output wire [`LoadBus-1:0] ex_load_bus  // EX阶段load信号
);

    // 寄存器，用于保存来自ID阶段的数据
    reg [`ID_TO_EX_WD-1:0] id_to_ex_bus_r;
    reg [`LoadBus-1:0] id_load_bus_r;
    reg [`SaveBus-1:0] id_save_bus_r;

    // 时钟上升沿时，更新寄存器的值
    always @ (posedge clk) begin
        if (rst) begin
            // 复位时，清空寄存器
            id_to_ex_bus_r <= `ID_TO_EX_WD'b0;
            id_save_bus_r <= `SaveBus'b0;
            id_load_bus_r <= `LoadBus'b0;
        end
        // else if (flush) begin
        //     id_to_ex_bus_r <= `ID_TO_EX_WD'b0;
        // end
        else if (stall[2]==`Stop && stall[3]==`NoStop) begin
            // 当stall信号为停顿时，清空寄存器
            id_to_ex_bus_r <= `ID_TO_EX_WD'b0;
            id_save_bus_r <= `SaveBus'b0;
            id_load_bus_r <= `LoadBus'b0;
        end
        else if (stall[2]==`NoStop) begin
            // 当stall信号不为停顿时，更新寄存器
            id_to_ex_bus_r <= id_to_ex_bus;
            id_save_bus_r <= id_save_bus;
            id_load_bus_r <= id_load_bus;
        end
    end

    // EX阶段的各个信号
    wire [31:0] ex_pc, inst;  // PC和指令
    wire [11:0] alu_op;       // ALU操作码
    wire [2:0] sel_alu_src1;  // ALU源1选择
    wire [3:0] sel_alu_src2;  // ALU源2选择
    wire data_ram_en;         // 数据RAM使能信号
    wire [3:0] data_ram_wen;  // 数据RAM写使能信号
    wire rf_we;               // 寄存器文件写使能
    wire [4:0] rf_waddr;      // 寄存器文件写地址
    wire sel_rf_res;          // 寄存器文件结果选择
    wire [31:0] rf_rdata1, rf_rdata2;  // 寄存器文件读数据

    reg is_in_delayslot;  // 是否在延迟槽

    // 从寄存器`id_to_ex_bus_r`中解码出各个信号
    assign {
        ex_pc,          // 148:117
        inst,           // 116:85
        alu_op,         // 84:83
        sel_alu_src1,   // 82:80
        sel_alu_src2,   // 79:76
        data_ram_en,    // 75
        data_ram_wen,   // 74:71
        rf_we,          // 70
        rf_waddr,       // 69:65
        sel_rf_res,     // 64
        rf_rdata1,      // 63:32
        rf_rdata2       // 31:0
    } = id_to_ex_bus_r;

    // 对立即数进行符号扩展和零扩展
    wire [31:0] imm_sign_extend, imm_zero_extend, sa_zero_extend;
    assign imm_sign_extend = {{16{inst[15]}}, inst[15:0]};  // 符号扩展
    assign imm_zero_extend = {16'b0, inst[15:0]};  // 零扩展
    assign sa_zero_extend = {27'b0, inst[10:6]};  // 立即数位移扩展

    // ALU的两个源操作数
    wire [31:0] alu_src1, alu_src2;
    wire [31:0] alu_result, ex_result;

    // 识别load和save指令
    wire inst_lb, inst_lbu, inst_lh, inst_lhu, inst_lw;
    wire inst_sb, inst_sh, inst_sw;
    assign alu_src1 = sel_alu_src1[1] ? ex_pc :
                      sel_alu_src1[2] ? sa_zero_extend : rf_rdata1;  // 选择ALU的源操作数1

    assign alu_src2 = sel_alu_src2[1] ? imm_sign_extend :
                      sel_alu_src2[2] ? 32'd8 :
                      sel_alu_src2[3] ? imm_zero_extend : rf_rdata2;  // 选择ALU的源操作数2

    // ALU运算
    alu u_alu(
        .alu_control (alu_op),      // ALU操作码
        .alu_src1    (alu_src1),    // ALU源操作数1
        .alu_src2    (alu_src2),    // ALU源操作数2
        .alu_result  (alu_result)   // ALU运算结果
    );

    assign ex_result = alu_result;  // EX阶段的结果

    // EX到MEM的数据总线
    assign ex_to_mem_bus = {
        ex_pc,          // 75:44
        data_ram_en,    // 43
        data_ram_wen,   // 42:39
        sel_rf_res,     // 38
        rf_we,          // 37
        rf_waddr,       // 36:32
        ex_result       // 31:0
    };

    // EX到RF的数据总线
    assign ex_to_rf_bus = {
        rf_we,          // 37
        rf_waddr,       // 36:32
        ex_result       // 31:0
    };

    // Load指令信号
    assign {
        inst_lb,
        inst_lbu,
        inst_lh,
        inst_lhu,
        inst_lw
    } = id_load_bus_r;
    assign {
        inst_sb,
        inst_sh,
        inst_sw
    } = id_save_bus_r;
    assign ex_load_bus = {
        inst_lb,
        inst_lbu,
        inst_lh,
        inst_lhu,
        inst_lw
    };

    // 数据RAM选择信号（只对加载/保存指令有效）
    assign data_ram_sel = inst_lw | inst_sw ? 4'b1111 : 4'b0000;
    assign data_sram_en = data_ram_en;  // 数据SRAM使能
    assign data_sram_wen = {4{data_ram_wen}} & data_ram_sel;  // 数据SRAM写使能
    assign data_sram_addr = ex_result;  // 数据SRAM地址
    assign data_sram_wdata = rf_rdata2;  // 数据SRAM写数据

    // 乘法操作部分
    wire [63:0] mul_result;  // 乘法结果
    wire mul_signed;         // 有符号乘法标记

    reg [31:0] mul_ina;      // 乘法操作数1
    reg [31:0] mul_inb;      // 乘法操作数2

    // 乘法模块实例
    mul u_mul(
        .clk        (clk),
        .resetn     (~rst),
        .mul_signed (mul_signed),
        .ina        (mul_ina),
        .inb        (mul_inb),
        .result     (mul_result)  // 乘法运算结果
    );

endmodule

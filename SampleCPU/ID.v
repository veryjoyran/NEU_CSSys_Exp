// 指令解码，同时读取寄存器
// IF/ID阶段可能会取出经符号扩展为32位的立即数和两个从寄存器中读取的数，放入ID/EX流水线寄存器

// 需要在该级进行指令译码
// 从寄存器中读取需要的数据
// 完成数据相关处理
// 生成发给EX段的控制信号
`include "lib/defines.vh"  // 引入定义文件，包含常量和宏定义

module ID(  // ID（指令解码）模块
    input wire clk,  // 时钟信号
    input wire rst,  // 复位信号
    // input wire flush,  // 暂时注释掉的刷新信号
    input wire [`StallBus-1:0] stall,  // 停顿信号，控制流水线暂停

    output wire stallreq,  // 停顿请求信号，指示是否需要暂停流水线

    input wire [`IF_TO_ID_WD-1:0] if_to_id_bus,  // 从IF（指令获取）到ID（指令解码）模块的输入数据

    input wire [31:0] inst_sram_rdata,  // 从数据存储器读取的指令数据

    input wire [`WB_TO_RF_WD-1:0] wb_to_rf_bus,  // 从WB（写回）阶段到RF（寄存器堆）阶段的输入数据

    input wire [`EX_TO_RF_WD-1:0] ex_to_rf_bus,  // 从EX（执行）阶段到RF（寄存器堆）阶段的输入数据

    input wire [`MEM_TO_RF_WD-1:0] mem_to_rf_bus,  // 从MEM（内存访问）阶段到RF（寄存器堆）阶段的输入数据

    output wire [`LoadBus-1:0] id_load_bus,  // ID模块输出的加载相关数据

    output wire [`SaveBus-1:0] id_save_bus,  // ID模块输出的保存相关数据

    output wire [`ID_TO_EX_WD-1:0] id_to_ex_bus,  // ID模块到EX模块的输入数据

    output wire [`BR_WD-1:0] br_bus  // 分支相关的控制信号
);

    reg [`IF_TO_ID_WD-1:0] if_to_id_bus_r;  // 寄存器，用于存储来自IF阶段的数据
    wire [31:0] inst;  // 当前指令
    wire [31:0] id_pc;  // 当前PC（程序计数器）值
    wire ce;  // 使能信号

    // 以下信号来自不同的阶段（WB、EX、MEM）的数据
    wire wb_rf_we;  // WB阶段写寄存器的使能信号
    wire [4:0] wb_rf_waddr;  // WB阶段写寄存器的地址
    wire [31:0] wb_rf_wdata;  // WB阶段写寄存器的数据

    wire ex_rf_we;  // EX阶段写寄存器的使能信号
    wire [4:0] ex_rf_waddr;  // EX阶段写寄存器的地址
    wire [31:0] ex_rf_wdata;  // EX阶段写寄存器的数据

    wire mem_rf_we;  // MEM阶段写寄存器的使能信号
    wire [4:0] mem_rf_waddr;  // MEM阶段写寄存器的地址
    wire [31:0] mem_rf_wdata;  // MEM阶段写寄存器的数据

    // 始终块，时钟上升沿触发
    always @ (posedge clk) begin
        if (rst) begin
            // 如果复位信号有效，清空if_to_id_bus_r
            if_to_id_bus_r <= `IF_TO_ID_WD'b0;
        end
        // else if (flush) begin
        //     ic_to_id_bus <= `IC_TO_ID_WD'b0;
        // end
        else if (stall[1]==`Stop && stall[2]==`NoStop) begin
            // 如果有停顿请求，并且当前阶段不需要停顿，清空if_to_id_bus_r
            if_to_id_bus_r <= `IF_TO_ID_WD'b0;
        end
        else if (stall[1]==`NoStop) begin
            // 如果没有停顿请求，将if_to_id_bus的内容传递给if_to_id_bus_r
            if_to_id_bus_r <= if_to_id_bus;
        end
    end

    // 指令数据赋值
    assign inst = inst_sram_rdata;

    // 提取EX阶段的数据
    assign {
        ex_rf_we,
        ex_rf_waddr,
        ex_rf_wdata
    } = ex_to_rf_bus;

    // 提取MEM阶段的数据
    assign {
        mem_rf_we,
        mem_rf_waddr,
        mem_rf_wdata
    } = mem_to_rf_bus;

    // 提取IF阶段的PC和使能信号
    assign {
        ce,
        id_pc
    } = if_to_id_bus_r;

    // 提取WB阶段的数据
    assign {
        wb_rf_we,
        wb_rf_waddr,
        wb_rf_wdata
    } = wb_to_rf_bus;

    // 解码指令的字段
    wire [5:0] opcode;  // 操作码
    wire [4:0] rs, rt, rd, sa;  // 源寄存器、目标寄存器、目标寄存器、移位量
    wire [5:0] func;  // 功能码
    wire [15:0] imm;  // 立即数
    wire [25:0] instr_index;  // 指令索引（跳转地址）
    wire [19:0] code;  // 高20位的常数
    wire [4:0] base;  // 基址寄存器
    wire [15:0] offset;  // 偏移量
    wire [2:0] sel;  // 选择信号

    // 操作数和功能码的解码
    wire [63:0] op_d, func_d;  // 操作码和功能码的扩展信号
    wire [31:0] rs_d, rt_d, rd_d, sa_d;  // 寄存器数据

    // ALU源选择信号
    wire [2:0] sel_alu_src1;
    wire [3:0] sel_alu_src2;
    wire [11:0] alu_op;  // ALU操作码

    // 数据存储器使能信号及写使能信号
    wire data_ram_en;  // 数据存储器使能
    wire [3:0] data_ram_wen;  // 数据存储器写使能

    // 寄存器堆写使能、写地址和目标选择信号
    wire rf_we;  // 寄存器堆写使能
    wire [4:0] rf_waddr;  // 寄存器堆写地址
    wire sel_rf_res;  // 寄存器堆结果选择信号
    wire [2:0] sel_rf_dst;  // 寄存器堆目标选择信号

    // 寄存器堆的数据输入输出信号
    wire [31:0] rdata1, rdata2;  // 寄存器堆的读取数据
    wire [31:0] ndata1, ndata2;  // 新的寄存器数据

// 数据相关部分
// 根据不同的写回数据（wb_rf_we、mem_rf_we、ex_rf_we）判断数据源，
// 并选择合适的值传递给`ndata1`和`ndata2`。如果该寄存器已经被某个阶段写回，则直接使用写回的数据。
assign ndata1 = ((ex_rf_we && rs == ex_rf_waddr) ? ex_rf_wdata : 32'b0) |  // 如果EX阶段写回寄存器，且地址与当前rs相同，使用EX阶段的写回数据
               ((mem_rf_we && rs == mem_rf_waddr) ? mem_rf_wdata : 32'b0) |  // 如果MEM阶段写回寄存器，且地址与当前rs相同，使用MEM阶段的写回数据
               ((wb_rf_we && rs == wb_rf_waddr) ? wb_rf_wdata : 32'b0) |    // 如果WB阶段写回寄存器，且地址与当前rs相同，使用WB阶段的写回数据
               (((ex_rf_we && rs == ex_rf_waddr) || (mem_rf_we && rs == mem_rf_waddr) || (wb_rf_we && rs == wb_rf_waddr)) ? 32'b0 : rdata1); // 否则使用rdata1的值

assign ndata2 = ((ex_rf_we && rt == ex_rf_waddr) ? ex_rf_wdata : 32'b0) |  // 如果EX阶段写回寄存器，且地址与当前rt相同，使用EX阶段的写回数据
               ((mem_rf_we && rt == mem_rf_waddr) ? mem_rf_wdata : 32'b0) |  // 如果MEM阶段写回寄存器，且地址与当前rt相同，使用MEM阶段的写回数据
               ((wb_rf_we && rt == wb_rf_waddr) ? wb_rf_wdata : 32'b0) |    // 如果WB阶段写回寄存器，且地址与当前rt相同，使用WB阶段的写回数据
               (((ex_rf_we && rt == ex_rf_waddr) || (mem_rf_we && rt == mem_rf_waddr) || (wb_rf_we && rt == wb_rf_waddr)) ? 32'b0 : rdata2); // 否则使用rdata2的值

// 寄存器堆（regfile）实例化
// 负责读取寄存器值以及在WB阶段写回数据
regfile u_regfile(
    .clk    (clk),           // 时钟信号
    .raddr1 (rs),            // 读取寄存器1的地址
    .rdata1 (rdata1),        // 读取寄存器1的数据
    .raddr2 (rt),            // 读取寄存器2的地址
    .rdata2 (rdata2),        // 读取寄存器2的数据
    .we     (wb_rf_we),      // 写使能信号
    .waddr  (wb_rf_waddr),   // 写寄存器地址
    .wdata  (wb_rf_wdata)    // 写入的数据
);

// 从指令中提取各个字段
assign opcode = inst[31:26];   // 操作码（opcode）
assign rs = inst[25:21];       // 源寄存器1（rs）
assign rt = inst[20:16];       // 源寄存器2（rt）
assign rd = inst[15:11];       // 目标寄存器（rd）
assign sa = inst[10:6];        // 移位量（sa）
assign func = inst[5:0];       // 功能码（func）
assign imm = inst[15:0];       // 立即数（imm）
assign instr_index = inst[25:0]; // 指令索引（instr_index）
assign code = inst[25:6];      // 操作码的高6位（code）
assign base = inst[25:21];     // 基址（base）
assign offset = inst[15:0];    // 偏移量（offset）
assign sel = inst[2:0];        // 选择信号（sel）

// 指令解码
// 定义各种指令的类型，例如加法、减法、跳转等
wire inst_ori, inst_lui, inst_addiu, inst_beq;
wire inst_subu, inst_jr, inst_jal, inst_addu;
wire inst_bne, inst_sll, inst_or, inst_xor , inst_lw, inst_sw;
wire inst_sltiu, inst_lb, inst_lbu, inst_lh;
wire inst_lhu, inst_sb, inst_sh;
wire inst_add, inst_addi;
wire inst_sub, inst_slt, inst_slti, inst_sltu;

// 定义操作类型
wire op_add, op_sub, op_slt, op_sltu;
wire op_and, op_nor, op_or, op_xor;
wire op_sll, op_srl, op_sra, op_lui;

// 对操作码（opcode）进行解码，得到操作类型
decoder_6_64 u0_decoder_6_64(
    .in  (opcode),   // 输入操作码
    .out (op_d)      // 输出操作类型
);

// 对功能码（func）进行解码，得到功能类型
decoder_6_64 u1_decoder_6_64(
    .in  (func),     // 输入功能码
    .out (func_d)    // 输出功能类型
);

// 对寄存器地址（rs和rt）进行解码
decoder_5_32 u0_decoder_5_32(
    .in  (rs),       // 输入寄存器地址1
    .out (rs_d)      // 输出寄存器1解码值
);

decoder_5_32 u1_decoder_5_32(
    .in  (rt),       // 输入寄存器地址2
    .out (rt_d)      // 输出寄存器2解码值
);

// 各种指令的匹配
assign inst_ori     = op_d[6'b00_1101];   // ori指令
assign inst_lui     = op_d[6'b00_1111];   // lui指令
assign inst_addiu   = op_d[6'b00_1001];   // addiu指令
assign inst_beq     = op_d[6'b00_0100];   // beq指令

assign inst_subu    = op_d[6'b00_0000] & func_d[6'b10_0011];   // subu指令
assign inst_jr      = op_d[6'b00_0000] & func_d[6'b00_1000];   // jr指令
assign inst_jal     = op_d[6'b00_0011];   // jal指令
assign inst_addu    = op_d[6'b00_0000] & func_d[6'b10_0001];   // addu指令

assign inst_bne     = op_d[6'b00_0101];   // bne指令
assign inst_sll     = op_d[6'b00_0000] & func_d[6'b00_0000];   // sll指令
assign inst_or      = op_d[6'b00_0000] & func_d[6'b10_0101];   // or指令

assign inst_xor     = op_d[6'b00_0000] & func_d[6'b10_0110];   // xor指令
assign inst_lw      = op_d[6'b10_0011];   // lw指令
assign inst_sw      = op_d[6'b10_1011];   // sw指令

assign inst_add     = op_d[6'b00_0000] & func_d[6'b10_0000];   // add指令
assign inst_addi    = op_d[6'b00_1000];   // addi指令
assign inst_sub     = op_d[6'b00_0000] & func_d[6'b10_0010];   // sub指令

assign inst_slt     = op_d[6'b00_0000] & func_d[6'b10_1010];   // slt指令
assign inst_slti    = op_d[6'b00_1010];   // slti指令
assign inst_sltu    = op_d[6'b00_0000] & func_d[6'b10_1011];   // sltu指令
assign inst_sltiu   = op_d[6'b00_1011];   // sltiu指令

// 一些指令没有使用（例如lb、lbu、lh、lhu、sb、sh），这里只做占位
assign inst_lb      = 1'b0;   // lb指令占位
assign inst_lbu     = 1'b0;   // lbu指令占位
assign inst_lh      = 1'b0;   // lh指令占位
assign inst_lhu     = 1'b0;   // lhu指令占位
assign inst_sb      = 1'b0;   // sb指令占位
assign inst_sh      = 1'b0;   // sh指令占位


// rs to reg1
// 选择 ALU 的第一个操作数源。根据不同的指令类型，选择不同的输入到 reg1（即 ALU 的第一个操作数）
// inst_ori, inst_addiu, inst_subu, inst_jr, inst_addu, inst_or, inst_xor, inst_lw, inst_sw 指令选择 rs（寄存器源）
assign sel_alu_src1[0] = inst_ori | inst_addiu | inst_subu | inst_jr | inst_addu | inst_or | inst_xor | inst_lw | inst_sw;

// pc to reg1
// 选择 ALU 的第一个操作数源。只有 jal 指令会将 PC（程序计数器）值传递到 reg1
assign sel_alu_src1[1] = inst_jal;

// sa_zero_extend to reg1
// 选择 ALU 的第一个操作数源。只有 sll 指令会将 sa_zero_extend（即位移量）传递到 reg1
assign sel_alu_src1[2] = inst_sll;


// rt to reg2
// 选择 ALU 的第二个操作数源。根据不同的指令类型，选择 rt（寄存器源）作为第二个操作数
assign sel_alu_src2[0] = inst_subu | inst_addu | inst_sll | inst_or | inst_xor;

// imm_sign_extend to reg2
// 选择 ALU 的第二个操作数源。对立即数进行符号扩展，用于处理立即数相关指令（lui、addiu、lw、sw）
assign sel_alu_src2[1] = inst_lui | inst_addiu | inst_lw | inst_sw;

// 32'b8 to reg2
// 选择 ALU 的第二个操作数源。jal 指令将一个固定的值 32'b8 传递到 reg2
assign sel_alu_src2[2] = inst_jal;

// imm_zero_extend to reg2
// 选择 ALU 的第二个操作数源。ori 指令会将一个零扩展的立即数传递到 reg2
assign sel_alu_src2[3] = inst_ori;


// 定义 ALU 的操作类型：
// 加法操作（包括 add、addi、addiu、jal、addu、lw、sw 指令）
assign op_add = inst_add | inst_addi | inst_addiu | inst_jal | inst_addu | inst_lw | inst_sw;

// 减法操作（包括 subu、sub 指令）
assign op_sub = inst_subu | inst_sub;

// 小于操作（带符号）指令：slt 和 slti
assign op_slt = inst_slt | inst_slti;

// 小于操作（无符号）指令：sltu 和 sltiu
assign op_sltu = inst_sltu | inst_sltiu;

// 与操作（目前未使用）
assign op_and = 1'b0;

// 或操作的相反操作（目前未使用）
assign op_nor = 1'b0;

// 或操作（ori、or 指令）
assign op_or = inst_ori | inst_or;

// 异或操作（xor 指令）
assign op_xor = inst_xor;

// 左移逻辑操作（sll 指令）
assign op_sll = inst_sll;

// 右移逻辑操作（目前未使用）
assign op_srl = 1'b0;

// 右移算术操作（目前未使用）
assign op_sra = 1'b0;

// 加载上半部分立即数操作（lui 指令）
assign op_lui = inst_lui;

// 将所有 ALU 操作组合到一起，形成一个 12 位的 ALU 操作码
assign alu_op = {op_add, op_sub, op_slt, op_sltu,
                 op_and, op_nor, op_or, op_xor,
                 op_sll, op_srl, op_sra, op_lui};

// 判断是否启用数据 RAM（lw 和 sw 指令访问数据内存）
assign data_ram_en = inst_sw | inst_lw;

// 判断是否启用数据 RAM 写操作（只有 sw 指令写数据到内存）
assign data_ram_wen = inst_sw;

// 判断是否启用寄存器文件写操作（根据不同指令设置寄存器写使能）
assign rf_we = inst_ori | inst_lui | inst_addiu | inst_subu | inst_jal | inst_addu | inst_sll |
                inst_or | inst_xor | inst_lw |
                inst_add | inst_addi | inst_sub | inst_slt | inst_slti | inst_sltu | inst_sltiu;

// 选择寄存器文件目的寄存器的输入（选择 rd 或 rt 或 31 号寄存器）
assign sel_rf_dst[0] = inst_subu | inst_addu | inst_sll | inst_or | inst_xor | inst_add | inst_sub | inst_slt | inst_sltu;
assign sel_rf_dst[1] = inst_ori | inst_lui | inst_addiu | inst_lw | inst_addi | inst_slti | inst_sltiu;

// 对于 jal 指令，目标寄存器固定为 31 号寄存器
assign sel_rf_dst[2] = inst_jal;

// 根据选择的寄存器目标，选择写入的寄存器地址（rd、rt 或 31 号寄存器）
assign rf_waddr = {5{sel_rf_dst[0]}} & rd
                | {5{sel_rf_dst[1]}} & rt
                | {5{sel_rf_dst[2]}} & 32'd31;

// 选择写回的结果来源：0 来自 ALU 结果；1 来自加载的数据
assign sel_rf_res = inst_lw;

// 将 ID 阶段的信号汇总到一个总线 id_to_ex_bus，传送到 EX 阶段
assign id_to_ex_bus = {
    id_pc,          // 158:127：PC 地址
    inst,           // 126:95：指令
    alu_op,         // 94:83：ALU 操作码
    sel_alu_src1,   // 82:80：ALU 第一个操作数来源
    sel_alu_src2,   // 79:76：ALU 第二个操作数来源
    data_ram_en,    // 75：数据 RAM 启用标志
    data_ram_wen,   // 74:71：数据 RAM 写使能
    rf_we,          // 70：寄存器文件写使能
    rf_waddr,       // 69:65：寄存器文件写地址
    sel_rf_res,     // 64：寄存器写回结果来源
    ndata1,         // 63:32：寄存器值 1
    ndata2          // 31:0：寄存器值 2
};

// 分支相关信号
wire br_e;         // 是否为分支
wire [31:0] br_addr;  // 分支目标地址
wire rs_eq_rt;     // 判断 rs 是否等于 rt
wire rs_ge_z;      // 判断 rs 是否大于等于 0
wire rs_gt_z;      // 判断 rs 是否大于 0
wire rs_le_z;      // 判断 rs 是否小于等于 0
wire rs_lt_z;      // 判断 rs 是否小于 0
wire [31:0] pc_plus_4;  // PC + 4

assign pc_plus_4 = id_pc + 32'h4; // PC+4 用于分支计算

// 判断 rs 和 rt 是否相等
assign rs_eq_rt = (ndata1 == ndata2);

// 判断分支条件是否成立
assign br_e = inst_beq & rs_eq_rt | inst_jr | inst_jal | inst_bne & ~rs_eq_rt;

// 计算分支目标地址，根据不同的指令选择不同的计算方式
assign br_addr = (inst_beq ? (pc_plus_4 + {{14{inst[15]}}, inst[15:0], 2'b0}) : 32'b0) |
                 (inst_jr ? ndata1 : 32'b0) |
                 (inst_jal ? {pc_plus_4[31:28], instr_index, 2'b0} : 32'b0) |
                 (inst_bne ? (pc_plus_4 + {{14{inst[15]}}, inst[15:0], 2'b0}) : 32'b0);

// 加载指令相关信号
assign id_load_bus = {
    inst_lb,
    inst_lbu,
    inst_lh,
    inst_lhu,
    inst_lw
};

// 存储指令相关信号
assign id_save_bus = {
    inst_sb,
    inst_sh,
    inst_sw
};

// 分支控制总线
assign br_bus = {
    br_e,
    br_addr
};

enmodule

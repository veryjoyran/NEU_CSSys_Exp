`include "lib/defines.vh"  // 引入定义文件，包含各种宏定义和参数

// CPU核心，定义流水线
// 该模块整合了指令取（IF）、指令译码（ID）、执行（EX）、访存（MEM）和写回（WB）五个流水线阶段
// 同时包含控制模块（CTRL）用于管理流水线的停顿和冲刷

module mycpu_core(
    input wire clk,                  // 时钟信号
    input wire rst,                  // 重置信号，高电平有效
    input wire [5:0] int,            // 中断信号

    // 指令存储器接口
    output wire inst_sram_en,        // 指令存储器使能信号
    output wire [3:0] inst_sram_wen, // 指令存储器写使能信号
    output wire [31:0] inst_sram_addr, // 指令存储器地址
    output wire [31:0] inst_sram_wdata, // 指令存储器写数据
    input wire [31:0] inst_sram_rdata,  // 指令存储器读数据

    // 数据存储器接口
    output wire data_sram_en,        // 数据存储器使能信号
    output wire [3:0] data_sram_wen, // 数据存储器写使能信号
    output wire [31:0] data_sram_addr, // 数据存储器地址
    output wire [31:0] data_sram_wdata, // 数据存储器写数据
    input wire [31:0] data_sram_rdata,  // 数据存储器读数据

    // 调试信号
    output wire [31:0] debug_wb_pc,        // 写回阶段的PC值
    output wire [3:0] debug_wb_rf_wen,     // 写回阶段的寄存器写使能信号
    output wire [4:0] debug_wb_rf_wnum,    // 写回阶段的寄存器写地址
    output wire [31:0] debug_wb_rf_wdata   // 写回阶段的寄存器写数据
);

// 内部信号定义
wire [`IF_TO_ID_WD-1:0] if_to_id_bus;         // IF到ID的数据总线
wire [`ID_TO_EX_WD-1:0] id_to_ex_bus;         // ID到EX的数据总线
wire [`EX_TO_MEM_WD-1:0] ex_to_mem_bus;       // EX到MEM的数据总线
wire [`MEM_TO_WB_WD-1:0] mem_to_wb_bus;       // MEM到WB的数据总线
wire [`EX_TO_RF_WD-1:0] ex_to_rf_bus;         // EX到寄存器文件的数据总线
wire [`MEM_TO_RF_WD-1:0] mem_to_rf_bus;       // MEM到寄存器文件的数据总线
wire [`BR_WD-1:0] br_bus;                     // 分支信息总线
wire [`DATA_SRAM_WD-1:0] ex_dt_sram_bus;      // EX到数据SRAM的数据总线
wire [`WB_TO_RF_WD-1:0] wb_to_rf_bus;         // WB到寄存器文件的数据总线
wire [`LoadBus-1:0] id_load_bus;              // ID阶段的Load信号
wire [`LoadBus-1:0] ex_load_bus;              // EX阶段的Load信号
wire [3:0] data_ram_sel;                      // 数据RAM选择信号
wire [`SaveBus-1:0] id_save_bus;              // ID阶段的Save信号
wire [`StallBus-1:0] stall;                   // 停顿信号总线
wire ex_id;                                    // EX阶段标识信号

wire [71:0] id_hi_lo_bus;                      // ID阶段的HI/LO寄存器总线
wire [65:0] ex_hi_lo_bus;                      // EX阶段的HI/LO寄存器总线

// 停顿请求信号
wire stallreq_for_ex;       // EX阶段的停顿请求
wire stallreq_for_load;     // Load操作的停顿请求
wire stallreq_for_bru;      // 分支操作的停顿请求

// 实例化指令取（IF）模块
IF u_IF(
    .clk             (clk             ),    // 时钟信号
    .rst             (rst             ),    // 重置信号
    .stall           (stall           ),    // 停顿信号
    .br_bus          (br_bus          ),    // 分支信息
    .if_to_id_bus    (if_to_id_bus    ),    // IF到ID的数据总线
    .inst_sram_en    (inst_sram_en    ),    // 指令存储器使能
    .inst_sram_wen   (inst_sram_wen   ),    // 指令存储器写使能
    .inst_sram_addr  (inst_sram_addr  ),    // 指令存储器地址
    .inst_sram_wdata (inst_sram_wdata )     // 指令存储器写数据
);

// 实例化指令译码（ID）模块
ID u_ID(
    .clk             (clk             ),    // 时钟信号
    .rst             (rst             ),    // 重置信号
    .stall           (stall           ),    // 停顿信号
    .stallreq        (stallreq        ),    // 停顿请求信号（待定义）
    .if_to_id_bus    (if_to_id_bus    ),    // IF到ID的数据总线
    .inst_sram_rdata (inst_sram_rdata ),    // 指令存储器读数据
    .wb_to_rf_bus    (wb_to_rf_bus    ),    // WB到寄存器文件的数据总线
    .ex_to_rf_bus    (ex_to_rf_bus    ),    // EX到寄存器文件的数据总线
    .mem_to_rf_bus   (mem_to_rf_bus   ),    // MEM到寄存器文件的数据总线
    .id_to_ex_bus    (id_to_ex_bus    ),    // ID到EX的数据总线
    .ex_id           (ex_id           ),    // EX阶段标识信号
    .id_load_bus     (id_load_bus     ),    // ID阶段Load信号
    .id_save_bus     (id_save_bus     ),    // ID阶段Save信号
    .stallreq_for_bru(stallreq_for_bru),    // 分支操作的停顿请求信号
    .br_bus          (br_bus          ),    // 分支信息
    .id_hi_lo_bus    (id_hi_lo_bus    ),    // ID阶段HI/LO寄存器总线
    .ex_hi_lo_bus    (ex_hi_lo_bus    )     // EX阶段HI/LO寄存器总线
);

// 实例化执行（EX）模块
EX u_EX(
    .clk             (clk             ),    // 时钟信号
    .rst             (rst             ),    // 重置信号
    .stall           (stall           ),    // 停顿信号
    .id_to_ex_bus    (id_to_ex_bus    ),    // ID到EX的数据总线
    // .ex_to_id_bus    (ex_to_id_bus    ), // 注释掉的信号
    .ex_id           (ex_id           ),    // EX阶段标识信号
    .ex_to_rf_bus    (ex_to_rf_bus    ),    // EX到寄存器文件的数据总线
    .ex_to_mem_bus   (ex_to_mem_bus   ),    // EX到MEM的数据总线
    .id_load_bus     (id_load_bus     ),    // ID阶段Load信号
    .id_save_bus     (id_save_bus     ),    // ID阶段Save信号
    .ex_load_bus     (ex_load_bus     ),    // EX阶段Load信号
    .stallreq_for_ex (stallreq_for_ex ),    // EX阶段停顿请求信号
    .data_ram_sel    (data_ram_sel    ),    // 数据RAM选择信号
    .data_sram_en    (data_sram_en    ),    // 数据存储器使能信号
    .data_sram_wen   (data_sram_wen   ),    // 数据存储器写使能信号
    .data_sram_addr  (data_sram_addr  ),    // 数据存储器地址
    .data_sram_wdata (data_sram_wdata ),    // 数据存储器写数据
    .id_hi_lo_bus    (id_hi_lo_bus    ),    // ID阶段HI/LO寄存器总线
    .ex_hi_lo_bus    (ex_hi_lo_bus    )     // EX阶段HI/LO寄存器总线
);

// 实例化访存（MEM）模块
MEM u_MEM(
    .clk                (clk                ),  // 时钟信号
    .rst                (rst                ),  // 重置信号
    .stall              (stall              ),  // 停顿信号
    .ex_to_mem_bus      (ex_to_mem_bus      ),  // EX到MEM的数据总线
    .ex_load_bus        (ex_load_bus        ),  // EX阶段Load信号
    .data_sram_rdata    (data_sram_rdata    ),  // 数据存储器读数据
    .data_ram_sel       (data_ram_sel       ),  // 数据RAM选择信号
    .stallreq_for_load  (stallreq_for_load  ),  // Load操作的停顿请求信号
    .mem_to_wb_bus      (mem_to_wb_bus      ),  // MEM到WB的数据总线
    .mem_to_rf_bus      (mem_to_rf_bus      )   // MEM到寄存器文件的数据总线
);

// 实例化写回（WB）模块
WB u_WB(
    .clk               (clk               ),    // 时钟信号
    .rst               (rst               ),    // 重置信号
    .stall             (stall             ),    // 停顿信号
    .mem_to_wb_bus     (mem_to_wb_bus     ),    // MEM到WB的数据总线
    .wb_to_rf_bus      (wb_to_rf_bus      ),    // WB到寄存器文件的数据总线
    .debug_wb_pc       (debug_wb_pc       ),    // 写回阶段的PC值
    .debug_wb_rf_wen   (debug_wb_rf_wen   ),    // 写回阶段的寄存器写使能信号
    .debug_wb_rf_wnum  (debug_wb_rf_wnum  ),    // 写回阶段的寄存器写地址
    .debug_wb_rf_wdata (debug_wb_rf_wdata )     // 写回阶段的寄存器写数据
);

// 实例化控制（CTRL）模块
CTRL u_CTRL(
    .rst               (rst               ),    // 重置信号
    .stallreq_for_ex   (stallreq_for_ex   ),    // EX阶段的停顿请求信号
    .stallreq_for_load (stallreq_for_load ),    // Load操作的停顿请求信号
    .stallreq_for_bru  (stallreq_for_bru  ),    // 分支操作的停顿请求信号
    .stall             (stall             )     // 停顿信号总线输出
);

endmodule

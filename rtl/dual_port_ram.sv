`timescale 1ns / 1ps

module dual_port_ram #(
    parameter ADDR_WIDTH = 9,
    parameter DATA_WIDTH = 32,
    parameter SEL_WIDTH  = DATA_WIDTH/8
)(
    input  logic                     clk,
    input  logic                     rst,

    // Wishbone ports: 0 = A, 1 = B
    input  logic [ADDR_WIDTH-1:0]    wb_addr_i  [1:0],
    input  logic [DATA_WIDTH-1:0]    wb_data_i  [1:0],
    input  logic [SEL_WIDTH-1:0]     wb_sel_i   [1:0],
    input  logic                     wb_we_i    [1:0],
    input  logic                     wb_stb_i   [1:0],
    output logic                     wb_ack_o   [1:0],
    output logic                     wb_stall_o [1:0],
    output logic [DATA_WIDTH-1:0]    wb_data_o  [1:0]
);

localparam PA = 0;
localparam PB = 1;

// Decode MSB as macro select, LSBs as address
wire sel [1:0];
wire [ADDR_WIDTH-2:0] addr_lsb [1:0];

generate
    for (genvar i = 0; i < 2; i++) begin
        assign sel[i]      = wb_addr_i[i][ADDR_WIDTH-1];
        assign addr_lsb[i] = wb_addr_i[i][ADDR_WIDTH-2:0];
    end
endgenerate

// Stall logic: A has priority
assign wb_stall_o[PA] = 1'b0;
assign wb_stall_o[PB] = wb_stb_i[PA] && wb_stb_i[PB] && (sel[PA] == sel[PB]);

// ACK logic: registered per port
always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        wb_ack_o <= '{default:0};
    end else begin
        for (int p = 0; p < 2; p++)
            wb_ack_o[p] <= wb_stb_i[p] && !wb_stall_o[p];
    end
end

// RAM control signals
logic                 en       [1:0];
logic [SEL_WIDTH-1:0] we_mem   [1:0];
logic [DATA_WIDTH-1:0] di_mem  [1:0];
logic [ADDR_WIDTH-2:0] addr_mem[1:0];
logic [DATA_WIDTH-1:0] do_mem  [1:0];

always_comb begin
    en       = '{default:0};
    we_mem   = '{default:'0};
    di_mem   = '{default:0};
    addr_mem = '{default:0};

    // Service each port
    for (int p = 0; p < 2; p++) begin
        if (wb_stb_i[p] && !wb_stall_o[p]) begin
            en[sel[p]]       = 1;
            di_mem[sel[p]]   = wb_data_i[p];
            addr_mem[sel[p]] = addr_lsb[p];
            if (wb_we_i[p])
                we_mem[sel[p]] = wb_sel_i[p];
        end
    end
end

// Instantiate DFFRAM macros
generate
    for (genvar r = 0; r < 2; r++) begin: ram_inst
        DFFRAM256x32 mem (
            .CLK (clk),
            .WE0 (we_mem[r]),
            .EN0 (en[r]),
            .Di0 (di_mem[r]),
            .Do0 (do_mem[r]),
            .A0  (addr_mem[r])
        );
    end
endgenerate

// Output MUX
assign wb_data_o[PA] = do_mem[sel[PA]];
assign wb_data_o[PB] = do_mem[sel[PB]];

endmodule

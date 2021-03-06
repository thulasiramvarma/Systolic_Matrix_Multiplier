function integer clog2;
    input integer value;
begin
    for (clog2=0; value>0; clog2=clog2+1)
        value = value >> 1;
    end
endfunction

module dut_tb
#(
    parameter D_W = 8,        //operand data width
    parameter D_W_ACC = 16,   //accumulator data width
    parameter N = 4,
    parameter M = 8
)
();

reg                                 clk=1'b0;
reg     [1:0]                       rst;

reg                                 rd_en_A;
reg                                 rd_en_B;
wire    [clog2((M*M*D_W)/8)-1:0]    rd_addr_A;
wire    [clog2((M*M*D_W)/8)-1:0]    rd_addr_B;
wire    [clog2(M)-1:0]             pixel_cntr_A;
wire    [clog2(M/N)-1:0]           slice_cntr_A;
wire    [clog2(M/N)-1:0]           pixel_cntr_B;
wire    [clog2(M)-1:0]             slice_cntr_B;
reg     [(N*D_W)-1:0]                A ;
reg     [(N*D_W)-1:0]                B ;
wire    [D_W*N-1:0]                A_pipe;
wire    [D_W*N-1:0]                B_pipe;
wire    [D_W_ACC*N*N-1:0]                  D;//[(N**2)-1:0]  ;
reg    [D_W_ACC-1:0]                  mem2       [0:M*M-1];//[(N**2)-1:0]  ;

reg     [D_W*N-1:0]                  mem0    [0:(M*M)/N-1];
reg     [D_W*N-1:0]                  mem1    [0:(M*M)/N-1];

initial begin
    $readmemh("A.mem", mem0);
end
initial begin
    $readmemh("B.mem", mem1);
end

assign A_pipe[D_W-1:0] = A[D_W-1:0];

genvar x;
for (x=1;x<N;x=x+1)
begin
   pipe
   #(
    .D_W(D_W),
    .pipes(x)
   )
   pipe_inst_A
   (
    .clk    (clk),
    .rst    (rst[0]),
    .in_p   (A[((x+1)*D_W)-1:x*D_W]),
    .out_p  (A_pipe[((x+1)*D_W)-1:x*D_W])
   );
end

assign B_pipe[D_W-1:0] = B[D_W-1:0];
for (x=1;x<N;x=x+1)
begin
   pipe
   #(
    .D_W(D_W),
    .pipes(x)
   )
   pipe_inst_B
   (
    .clk    (clk),
    .rst    (rst[0]),
    .in_p   (B[((x+1)*D_W)-1:x*D_W]),
    .out_p  (B_pipe[((x+1)*D_W)-1:x*D_W])
   );
end

always@(posedge clk)
begin
    if (rst[0])
    begin
        rd_en_A <= 1;
    end
end

always@(posedge clk)
begin
    if (rst[0])
    begin
        rd_en_B <= 1;
    end
end

always@(posedge clk)
begin
    if (rst[0]==1'b0)
    begin
        if (rd_en_A)
        begin
            A  <= mem0[rd_addr_A];
        end
    end
    else
    begin
        A  <= 0;
    end
end

always@(posedge clk)
begin
    if (rst[0]==1'b0)
    begin
        if (rd_en_B)
        begin
            B  <= mem1[rd_addr_B];
        end
    end
    else
    begin
        B  <= 0;
    end
end

wire    [N-1:0] init_pe_pipe  [N-1:0];
assign  rd_addr_A = (slice_cntr_A*(M)+pixel_cntr_A);
assign  rd_addr_B = (pixel_cntr_B*(M)+slice_cntr_B);

reg enable_row_count_A = 1;
wire [N*N-1:0]   valid_D;

systolic 
#(
    .D_W     (D_W),
    .D_W_ACC     (D_W_ACC),
    .N      (N),
    .M      (M)
)
systolic_dut 
(
    .clk            (clk)   , 
    .rst            (rst[0]) ,
    .enable_row_count_A    (enable_row_count_A),
    .slice_cntr_A      (slice_cntr_A),
    .slice_cntr_B      (slice_cntr_B),
    .pixel_cntr_A         (pixel_cntr_A),
    .pixel_cntr_B         (pixel_cntr_B),
    .A             (A_pipe)    , 
    .B             (B_pipe),     
    .D              (D) ,
    .valid_D            (valid_D)  
);

always #5 clk = ~clk;

initial
begin
    $timeformat(-9, 2, " ns", 20);
    rst = 2'b11;
end

always @(posedge clk) begin
	rst <= rst>>1;
end

reg [31:0]  counter_finish = 0;

reg                    [2:0]             rst_pe = 2'b00;
always@(posedge clk)
begin
	if(rst[0]) begin
		rst_pe <= 1'b0;
	end else begin
		if (pixel_cntr_A==M-1)
		begin
			rst_pe <= 2'b01;
		end
		else
		begin
			rst_pe <= rst_pe >> 1;
		end
	end
end

genvar y;
for (x=0;x<N;x=x+1)
begin
    for (y=0;y<N;y=y+1)
    begin
        pipe
        #(
         .D_W(1),
         .pipes(x+y+1)
        )
        pipe_inst_rst
        (
         .clk    (clk),
         .rst    (),
         .in_p   (rst_pe[0]),
         .out_p  (init_pe_pipe[x][y])
        );
    end
end

reg init = 0;

always@(posedge clk)
begin
	if(rst[0]) begin
		counter_finish <= 0;
	end else if (init_pe_pipe[N-1][N-1])
	begin
		counter_finish <= counter_finish + 1;
	end
end

reg [31:0]  patch =1;

always@(posedge clk)
begin
	if(rst[0]) begin
		enable_row_count_A <= 1'b0;
		patch <= 1;
	end else begin
		if (enable_row_count_A == 1'b1)
		begin
			enable_row_count_A <= 1'b0;
		end

		else if (pixel_cntr_A == M-2 && patch == (M/N))
		begin
			patch <= 1;
			enable_row_count_A <= ~enable_row_count_A;
		end

		else if (pixel_cntr_A == M-2)
		begin
			patch <= patch + 1 ;
		end
	end
end



for (x=0;x<N;x=x+1)
begin
    for (y=0;y<N;y=y+1)
    begin
        always@(posedge clk)
        begin
            if (valid_D[x*N+y]==1'b1 && rst[0]==1'b0)
            begin
                $display("Out at PE[%0d][%0d] is %0d at %0t", x,y,D[D_W_ACC*(x*N+y+1)-1 : D_W_ACC*(x*N+y)], $time);
                mem2[(counter_finish*N*N)+(x*N)+y] <= D[D_W_ACC*(x*N+y+1)-1 : D_W_ACC*(x*N+y)];
            end
        end
    end
end

always@(posedge clk)
begin
    if (counter_finish == (M*M)/(N*N))
    begin
        $writememh("D.mem", mem2);
        $finish; // important to quit for automated grading
    end
end
initial begin
	$dumpfile("lab3.vcd");
	$dumpvars;
end

endmodule
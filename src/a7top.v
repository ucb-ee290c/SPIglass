module a7top #(
    parameter CLOCK_FREQ = 100_000_000,
    /* verilator lint_off REALCVT */
    // Sample the button signal every 500us
    parameter integer B_SAMPLE_CNT_MAX = $rtoi(0.0005 * CLOCK_FREQ),
    // The button is considered 'pressed' after 100ms of continuous pressing
    parameter integer B_PULSE_CNT_MAX = $rtoi(0.100 / 0.0005)
    /* lint_on */
)(
    input CLK100MHZ,
    input reset,
    input SPI_CLK,
    input SPI_CS,
    input SPI_MOSI,
    output SPI_MISO
);
    wire FPGA_CLK = CLK100MHZ;
    
    /* 
    The A7's reset button is high when not pressed. We use active high reset.
    */
    wire n_reset = ~reset;
    spiflash #(
        .ADDRL(19)
    ) spiflash (
        .clk(SPI_CLK),
        .cs(SPI_CS),
        .mosi(SPI_MOSI),
        .miso(SPI_MISO),
        .reset(n_reset)
    );

endmodule

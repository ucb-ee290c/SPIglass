## Source: https://github.com/Digilent/digilent-xdc/blob/master/Arty-A7-100-Master.xdc

## Clock signal
set_property -dict { PACKAGE_PIN E3    IOSTANDARD LVCMOS33 } [get_ports { CLK100MHZ }]; #IO_L12P_T1_MRCC_35 Sch=gclk[100]
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports { CLK100MHZ }];

## Buttons
set_property -dict { PACKAGE_PIN C2    IOSTANDARD LVCMOS33 } [get_ports { reset }]; #IO_L16P_T2_35 Sch=ck_rst

##Pmod Header JD
set_property -dict { PACKAGE_PIN D4    IOSTANDARD LVCMOS33 } [get_ports { SPI_CS   }]; #IO_L11N_T1_SRCC_35 Sch=jd[1]
set_property -dict { PACKAGE_PIN D3    IOSTANDARD LVCMOS33 } [get_ports { SPI_MOSI }]; #IO_L12N_T1_MRCC_35 Sch=jd[2]
set_property -dict { PACKAGE_PIN F4    IOSTANDARD LVCMOS33 } [get_ports { SPI_CLK  }]; #IO_L13P_T2_MRCC_35 Sch=jd[3]
set_property -dict { PACKAGE_PIN F3    IOSTANDARD LVCMOS33 } [get_ports { SPI_MISO }]; #IO_L13N_T2_MRCC_35 Sch=jd[4]


create_clock -period 19 -name spi_clk -waveform {0.000 9.500} [get_ports SPI_CLK]
## The SPI clock is entirely detatched and desync'd from the FPGA clock.
## Set them to seperate groups to prevent clock-crossing timing violations
set_clock_groups -asynchronous  -group sys_clk_pin -group spi_clk

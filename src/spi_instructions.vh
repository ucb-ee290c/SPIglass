`ifndef _SPI_INSTRUCTIONS_VH_
`define _SPI_INSTRUCTIONS_VH_

`define SF_READ_UNIQUE_ID       8'h4B
`define SF_PAGE_PROGRAM         8'h02
`define SF_SECTOR_ERASE_4K      8'h20
`define SF_BLOCK_ERASE_32K      8'h52
`define SF_BLOCK_ERASE_64K      8'hD8
`define SF_READ_DATA            8'h03
`define SF_FAST_READ            8'h0B
`define SF_WRITE_ENABLE         8'h06
`define SF_WRITE_DISABLE        8'h04
`define SF_JEDEC_ID             8'h9F

`endif /* _SPI_INSTRUCTIONS_VH_ */
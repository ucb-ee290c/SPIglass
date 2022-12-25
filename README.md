# SPIGlass

This project is a simple, fully synthesizable SPI Flash device. It is currently
implemented for the Arty A7-100T but can trivially be ported to any device by 
modifying the `Makefile`, the top file, and the constraints file. This project
is written in Verilog.

On the Arty A7-100T, this design is able to provide read and write access to
512K of BRAM backed memory at 52.6MHz.

### Limitations
This design supports only the handful of commands necessary to support basic
reading and writing. Thus, the only instructions (currently) supported are:

* Write Enable
* Write Disable
* Read Data
* Program Page

Additionally, while some efforts have been made to verify the correctness of
the design, no serious guarantees are given about whether or not this design
really works. Use at your own peril <3


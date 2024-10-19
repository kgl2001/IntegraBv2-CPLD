CPLD Code for IntegraBV2 (Hardware Revision 01).
For use with XILINX XC95144XL-TQG100 CPLD

CPLD logic for the IntegraB V2 ROM / RAM Expansion Board for the BBC Model B Microcomputer.
Main Features include:
8 onboard ROM sockets that will accept various 8K, 16K & 32K ROM, RAM, FRAM, EEPROM, FLASH modules and PALPROM modules
Access to 4 x 16K ROM sockets on main motherboard
512K Battery backed RAM:
- 16 x 16K SWRAM banks
- 20K Shadow RAM
- 12K Private RAM
- RAM banks 0..3 can be individually switched out for the ROM sockets on the main motherboard using jumpers on IntegraB board
- RAM banks 8..11 can be individually configured to accept PALPROM ROM images. Images are loaded to extended RAM
- RAM banks 8..15 can be individually switched out for the ROM sockets on the IntegraB motherboard using jumpers on IntegraB board
- All RAM banks can be individually software Write Protected / Enabled using new IBOS *SRWP / SRWE commands

New recovery mode that allows simple erase of all RAM on IntegraB board and reload of ROM images in the event of RAM corruption. Also used to load PALPROM images
Y2K compliant RTC
`timescale 1ns / 1ps
/************************************************************************
	 IntegraBV2.v

	 IntegraB V2 - A fully expanded ROM / RAM Board for BBC Micro
	 Revision 01 - November 2020
    Copyright (C) 2020 Ken Lowe

    IntegraBV2 is free software: you can redistribute it and/or modify
	 it under the terms of the GNU General Public License as published by
	 the Free Software Foundation, either version 3 of the License, or
	 (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.

	 Email: ken@skidog.co.uk

************************************************************************/
module IntegraBV2(
	input from_CPU_RnW,
	input from_CPU_Phi1,
	input from_CPU_Phi2, //Temporary input
	input from_CPU_dPhi2,
	input bbc_nRST,
	input [7:0] bbc_DATA,
	input [15:0] bbc_ADDRESS,
	input [15:0] RamWriteProt,
	input [15:8] IntegraRomSel,
	input [3:0] BeebRomSel,

	output to_bbc_Phi1,
	output to_bbc_RnW,
	output to_bbc_rD0,
	output to_bbc_rD1,
	output nDBuf_CE,
	output nDBuf_Dir,
	output nWDS,
	output nRDS,
	output nRomBankSel0_3,
	output [15:8] nRomBankSel,
	output RTC_AS,
	output RTC_DS,
	output RAM_CE,
	output [18:14] Ram_ADDRESS
	);


	// Repeat RnW & Phi1 from Input to Output
	wire	 Phi1;
	wire	 Phi2;
	wire	 ShAct;
	wire	 RnW;
	assign Phi1			 = from_CPU_Phi1;
	assign Phi2			 = from_CPU_Phi2;
	assign RnW			 = from_CPU_RnW;
	assign to_bbc_Phi1 = !(!Phi1 & !ShAct);
	assign to_bbc_RnW  = !(!RnW  & !ShAct);
	assign nDBuf_Dir	 = RnW;

	// Address decoding. Note that the lowest 2 bits A0 and A1 are not used.
	wire   FE3x		= (bbc_ADDRESS[15:4] == 12'hFE3);
	wire	 FE30_7  = FE3x && (bbc_ADDRESS[3] == 1'b0);
	wire   FE30_3  = FE3x && (bbc_ADDRESS[3:2] == 2'b00);
	wire   FE34_7  = FE3x && (bbc_ADDRESS[3:2] == 2'b01);
	
	// nWDS is normally just !( RnW & !Phi1) but we check for Write protect and hold nWDS high is Write Protect is active.
	// nWDS needs to consider all 16 RAM banks AND the Shadow Bank
	wire	 ShadowSel;
	wire   RamBankSel[15:0];
	wire	 GenBankSel[15:0];
	assign nRDS = !( RnW & Phi2);
	assign nWDS =   !((!RnW & Phi2 & GenBankSel[10] & !RamWriteProt[10])
					|     (!RnW & Phi2 & GenBankSel[11] & !RamWriteProt[11])
					|     (!RnW & Phi2 & GenBankSel[12] & !RamWriteProt[12])
					|     (!RnW & Phi2 & GenBankSel[13] & !RamWriteProt[13])
					|     (!RnW & Phi2 & GenBankSel[14] & !RamWriteProt[14])
					|     (!RnW & Phi2 & GenBankSel[15] & !RamWriteProt[15])
	 				|     (!RnW & Phi2 & ShadowSel));
	
	//assign nWDS = !((!RnW & Phi2 & !RamBankSel[0]  & !RamWriteProt[0]  & !BeebRomSel[0])
	//				|   (!RnW & Phi2 & !RamBankSel[1]  & !RamWriteProt[1]  & !BeebRomSel[1])
	//				|   (!RnW & Phi2 & !RamBankSel[2]  & !RamWriteProt[2]  & !BeebRomSel[2])
	//				|   (!RnW & Phi2 & !RamBankSel[3]  & !RamWriteProt[3]  & !BeebRomSel[3])
	//				|	 (!RnW & Phi2 & !RamBankSel[4]  & !RamWriteProt[4])
	//				|   (!RnW & Phi2 & !RamBankSel[5]  & !RamWriteProt[5])
	//				|   (!RnW & Phi2 & !RamBankSel[6]  & !RamWriteProt[6])
	//				|   (!RnW & Phi2 & !RamBankSel[7]  & !RamWriteProt[7])
	//				|   (!RnW & Phi2 & !RamBankSel[8]  & !RamWriteProt[8]  & !IntegraRomSel[8])
	//				|   (!RnW & Phi2 & !RamBankSel[9]  & !RamWriteProt[9]  & !IntegraRomSel[9])
	//				|   (!RnW & Phi2 & !RamBankSel[10] & !RamWriteProt[10] & !IntegraRomSel[10])
	//				|   (!RnW & Phi2 & !RamBankSel[11] & !RamWriteProt[11] & !IntegraRomSel[11])
	//				|   (!RnW & Phi2 & !RamBankSel[12] & !RamWriteProt[12] & !IntegraRomSel[12])
	//				|   (!RnW & Phi2 & !RamBankSel[13] & !RamWriteProt[13] & !IntegraRomSel[13])
	//				|   (!RnW & Phi2 & !RamBankSel[14] & !RamWriteProt[14] & !IntegraRomSel[14])
	//				|   (!RnW & Phi2 & !RamBankSel[15] & !RamWriteProt[15] & !IntegraRomSel[15])
	//				|   (!RnW & Phi2 &  ShadowSel));

	// This logic sets PrvAct to logic state '1' if the addresses in the Private memory range &8000..&AFFF and if one of the Private Memory flags is active. 
	reg	 PrvEn;
	reg	 PrvS8;
	reg	 PrvS4;
	reg	 PrvS1;
	assign PrvAct    =   ((bbc_ADDRESS[15:12] == 4'h8) & (bbc_ADDRESS[11:10] == 2'b00) & PrvS1 & PrvEn  //address decodes to &8000..&83FF. Maps to &0000..&03FF in Shadow RAM
						  |    (bbc_ADDRESS[15:12] == 4'h8) &  PrvS4 & PrvEn   										 //address decodes to &8000..&8FFF. Maps to &0000..&0FFF in Shadow RAM
						  |    (bbc_ADDRESS[15:12] == 4'h9) &  PrvS8 & PrvEn											 //address decodes to &9000..&9FFF. Maps to &1000..&1FFF in Shadow RAM
						  |    (bbc_ADDRESS[15:12] == 4'hA) &  PrvS8 & PrvEn);										 //address decodes to &A000..&AFFF. Maps to &2000..&2FFF in Shadow RAM

	// This logic sets ShAct to logic state '1' if the addresses in the screen range &3000..&7FFF and if Shadow Memory is active. 
	reg	 ShEn;
	reg	 MemSel;
	wire	 ScreenMem =  ((bbc_ADDRESS[15:12] == 4'h3)    //address decodes to &3000..&3FFF
						  |   (bbc_ADDRESS[15:14] == 2'b01)); //address decodes to &4000..&7FFF
	assign ShAct     = ScreenMem & ShEn & !MemSel;

	// ShadowSel is logic '1' when either Shadow or Private RAM is being accessed. 
	// Note that Shadow and Private memory is mapped to a 32k Block of RAM as follows:
	// Function			BBC Memory	32K RAM
	//	Screen memory	3000..7FFF	3000..7FFF
	//	Private Prv1	8000..83FF	0000..03FF
	// Private Prv4	8000..8FFF	0000..0FFF
	// Private Prv8	9000..AFFF	1000..2FFF
	assign ShadowSel = !(!ShAct & !PrvAct);

	
	// The following logic is used to demux the ROM banks.
	// Banks 0..3 are located on the Beeb mainboard. These banks can be switched out for SWRAM on the IntegraB board instead
	// Banks 4..7 are SWRAM banks located on the IntegraB board
	// Banks 8..15 are ROM slots on the IntegraB board. These banks can be switched out for SWRAM on the IntegraB board instead
	// All SWRAM can be write protected in 16k banks.
	reg	 rD0;
	reg	 rD1;
	reg	 rD2;
	reg	 rD3;
	wire	 ROMDec;
	assign to_bbc_rD0 = rD0;
	assign to_bbc_rD1 = rD1;

	// If address is in range &8000..&BFFF then SWRAddr = 1, otherwise 0
	wire	 SWRAddr  =  (bbc_ADDRESS[15:14] == 2'b10);

	// Check if address is in the range &8000..&BFFF and it's not Private RAM that's being accessed.
	// assign ROMDec   = SWRAddr & !PrvAct;
	assign ROMDec   =  (SWRAddr & !PrvAct & Phi2
						 |	  SWRAddr & !PrvAct & !nRomBankSel0_3);


	// GenBankSel[x] is logic '1' when bank is selected
	// wire	 GenBankSel[15:0];
	assign GenBankSel[0]   = !rD3 & !rD2 & !rD1 & !rD0 & ROMDec;
	assign GenBankSel[1]   = !rD3 & !rD2 & !rD1 &  rD0 & ROMDec;
	assign GenBankSel[2]   = !rD3 & !rD2 &  rD1 & !rD0 & ROMDec;
	assign GenBankSel[3]   = !rD3 & !rD2 &  rD1 &  rD0 & ROMDec;
	assign GenBankSel[4]   = !rD3 &  rD2 & !rD1 & !rD0 & ROMDec;
	assign GenBankSel[5]   = !rD3 &  rD2 & !rD1 &  rD0 & ROMDec;
	assign GenBankSel[6]   = !rD3 &  rD2 &  rD1 & !rD0 & ROMDec;
	assign GenBankSel[7]   = !rD3 &  rD2 &  rD1 &  rD0 & ROMDec;
	assign GenBankSel[8]   =  rD3 & !rD2 & !rD1 & !rD0 & ROMDec;
	assign GenBankSel[9]   =  rD3 & !rD2 & !rD1 &  rD0 & ROMDec;
	assign GenBankSel[10]  =  rD3 & !rD2 &  rD1 & !rD0 & ROMDec;
	assign GenBankSel[11]  =  rD3 & !rD2 &  rD1 &  rD0 & ROMDec;
	assign GenBankSel[12]  =  rD3 &  rD2 & !rD1 & !rD0 & ROMDec;
	assign GenBankSel[13]  =  rD3 &  rD2 & !rD1 &  rD0 & ROMDec;
	assign GenBankSel[14]  =  rD3 &  rD2 &  rD1 & !rD0 & ROMDec;
	assign GenBankSel[15]  =  rD3 &  rD2 &  rD1 &  rD0 & ROMDec;
	

	// Logic to select Motherboard ROM Banks 0..3
	// Check if bank is mapped to ROM on beeb motherboard, or to RAM on IntegraB board
	// GenBankSel[x] is the output of the 4..16 line decoder. Logic '1' if output is decoded
	//	BeebRomSel[x] is based on jumper selection via pull up resistor. Logic '1' selects motherboard ROM. Logic '0' selects onboard RAM
	// nRomBankSelB[x] is logic '0' when bank is selected
	wire   nRomBankSelB[3:0];
	assign nRomBankSelB[0] = !(GenBankSel[0] & BeebRomSel[0]);
	assign nRomBankSelB[1] = !(GenBankSel[1] & BeebRomSel[1]);
	assign nRomBankSelB[2] = !(GenBankSel[2] & BeebRomSel[2]);
	assign nRomBankSelB[3] = !(GenBankSel[3] & BeebRomSel[3]);
	assign nRomBankSel0_3  = nRomBankSelB[0] & nRomBankSelB[1] & nRomBankSelB[2] & nRomBankSelB[3];

	// Logic to select IntegraB ROM Banks 8..15
	// Check if bank is mapped to ROM on IntegraB board, or to RAM on IntegraB board
	// GenBankSel[x] is the output of the 4..16 line decoder. Logic '1' if output is decoded
	//	IntegraRomSel[x] is based on jumper selection via pull up resistor. Logic '1' selects motherboard ROM. Logic '0' selects onboard RAM
	// nRomBankSel[x] is logic '0' when bank is selected otherwire open collector
	// assign nRomBankSel[8]  =  (GenBankSel[8]  & IntegraRomSel[8])  ? 1'b0 : 1'bz;
	// assign nRomBankSel[9]  =  (GenBankSel[9]  & IntegraRomSel[9])  ? 1'b0 : 1'bz;
	// assign nRomBankSel[10] =  (GenBankSel[10] & IntegraRomSel[10]) ? 1'b0 : 1'bz;
	// assign nRomBankSel[11] =  (GenBankSel[11] & IntegraRomSel[11]) ? 1'b0 : 1'bz;
	// assign nRomBankSel[12] =  (GenBankSel[12] & IntegraRomSel[12]) ? 1'b0 : 1'bz;
	// assign nRomBankSel[13] =  (GenBankSel[13] & IntegraRomSel[13]) ? 1'b0 : 1'bz;
	// assign nRomBankSel[14] =  (GenBankSel[14] & IntegraRomSel[14]) ? 1'b0 : 1'bz;
	// assign nRomBankSel[15] =  (GenBankSel[15] & IntegraRomSel[15]) ? 1'b0 : 1'bz;


	assign nRomBankSel[9]	= 	 !ShadowSel ? 1'bz : 1'b0;
	assign nRomBankSel[11]  =   (!GenBankSel[10] & !GenBankSel[11]) ? 1'bz : 1'b0;
	assign nRomBankSel[13]  =   (!GenBankSel[12] & !GenBankSel[13]) ? 1'bz : 1'b0;
	assign nRomBankSel[15]  =   (!GenBankSel[14] & !GenBankSel[15]) ? 1'bz : 1'b0;

	assign IntRTC	= 1'b0; // 0 for internal and 1 for external
	// wire	 IntRTC  = IntegraRomSel[15];
	assign RTC_AS  = FE3x && (bbc_ADDRESS[3:2] == 2'b10) && !RnW && Phi2 && !IntRTC; // &FE38..B -> Address Strobe
	assign RTC_DS  = FE3x && (bbc_ADDRESS[3:2] == 2'b11) && Phi2 && !IntRTC;  // &FE3C..F -> Data Strobe
	assign nRomBankSel[10]  =	 FE3x && (bbc_ADDRESS[3:2] == 2'b10) && !RnW && Phi2 && IntRTC; // &FE38..B -> Address Strobe
	assign nRomBankSel[12]  =	 FE3x && (bbc_ADDRESS[3:2] == 2'b11) && Phi2 && IntRTC;  // &FE3C..F -> Data Strobe
	
	// assign nRomBankSel[8]  = 1'b1; // temporary disable on board ROM
	// assign nRomBankSel[9]  = 1'b1; // temporary disable on board ROM
	// assign nRomBankSel[10] = 1'b1; // temporary disable on board ROM
	// assign nRomBankSel[11] = 1'b1; // temporary disable on board ROM
	// assign nRomBankSel[12] = 1'b1; // temporary disable on board ROM
	// assign nRomBankSel[13] = 1'b1; // temporary disable on board ROM
	// assign nRomBankSel[14] = 1'b1; // temporary disable on board ROM
	// assign nRomBankSel[15] = 1'b1; // temporary disable on board ROM
	
	// Logic to select IntegraB RAM Banks 0..15
	// Check if bank is mapped to ROM on either beeb motherboard / IntegraB board, or to RAM on IntegraB board
	// assign RamBankSel[0]	  = !(GenBankSel[0]  & !BeebRomSel[0]);
	// assign RamBankSel[1]	  = !(GenBankSel[1]  & !BeebRomSel[1]);
	// assign RamBankSel[2]	  = !(GenBankSel[2]  & !BeebRomSel[2]);
	// assign RamBankSel[3]	  = !(GenBankSel[3]  & !BeebRomSel[3]);
	// assign RamBankSel[4]	  = !(GenBankSel[4]);
	// assign RamBankSel[5]	  = !(GenBankSel[5]);
	// assign RamBankSel[6]	  = !(GenBankSel[6]);
	// assign RamBankSel[7]	  = !(GenBankSel[7]);
	// assign RamBankSel[8]	  = !(GenBankSel[8]  & !IntegraRomSel[8]);
	// assign RamBankSel[9]	  = !(GenBankSel[9]  & !IntegraRomSel[9]);
	// assign RamBankSel[10]  = !(GenBankSel[10] & !IntegraRomSel[10]);
	// assign RamBankSel[11]  = !(GenBankSel[11] & !IntegraRomSel[11]);
	// assign RamBankSel[10]  = !(GenBankSel[10]);
	// assign RamBankSel[11]  = !(GenBankSel[11]);
	// assign RamBankSel[12]  = !(GenBankSel[12] & !IntegraRomSel[12]);
	// assign RamBankSel[13]  = !(GenBankSel[13] & !IntegraRomSel[13]);
	// assign RamBankSel[14]  = !(GenBankSel[14] & !IntegraRomSel[14]);
	// assign RamBankSel[15]  = !(GenBankSel[15] & !IntegraRomSel[15]);
	// assign RAM_CE			  =   RamBankSel[0]  & RamBankSel[1]  & RamBankSel[2]  & RamBankSel[3]
	// 							  &   RamBankSel[4]  & RamBankSel[5]  & RamBankSel[6]  & RamBankSel[7]
	// 							  &   RamBankSel[8]  & RamBankSel[9]  & RamBankSel[10] & RamBankSel[11]
	// 							  &   RamBankSel[12] & RamBankSel[13] & RamBankSel[14] & RamBankSel[15] & !ShadowSel;
	// assign RAM_CE = 1'b1; // temporary disable on board RAM

	// RAM addresses A0..A13 and data lines D0..D7 are wired to the CPU (via buffers on the IntegraB board)
	// RAM addresses A14..A18 are switched by the CPLD based on which RAM bank has been selected
	// ShadowSel is a 32k block based on Shadow RAM and Private RAM. A14 switches between the upper and lower bank.
	// assign Ram_ADDRESS[14] = rD0 & !ShadowSel
	// 							  | bbc_ADDRESS[14] & ShadowSel;
	// assign Ram_ADDRESS[15] = rD1 & !ShadowSel;
	// assign Ram_ADDRESS[16] = rD2 & !ShadowSel;
	// assign Ram_ADDRESS[17] = rD3 & !ShadowSel;
	// assign Ram_ADDRESS[18] = ShadowSel;

	// Logic to enable the data buffer.
	// Buffer needs to be enabled (logic low) when accessing onboard SWRAM, SWROM, Shadow RAM, Private RAM, or when writing data to registers &FE30..&FE3F
	assign nDBuf_CE     	  =  !SWRAddr & !ShadowSel & !FE3x
								  |  !nRomBankSel0_3 & !ShadowSel & !FE3x; // this line ensures the IntegraB data buffer not active when accessing off board SWROM
	// assign nDBuf_CE	     	=  !SWRAddr & !ShadowSel & !FE30_7
	//								|  !nRomBankSel0_3 & !ShadowSel & !FE30_7; // this line ensures the IntegraB data buffer not active when accessing off board SWROM


	//This data is latched when address is in the range FE30..FE33
	//rD0..rD3 are used to decode the selected SWROM bank
   always @(negedge Phi2 or negedge bbc_nRST) begin
      if (!bbc_nRST) begin
         rD0 <= 1'b0;
      end else if (!RnW && FE30_3) begin
         rD0 <= bbc_DATA[0];
      end
   end

   always @(negedge Phi2 or negedge bbc_nRST) begin
      if (!bbc_nRST) begin
         rD1 <= 1'b0;
      end else if (!RnW && FE30_3) begin
         rD1 <= bbc_DATA[1];
      end
   end

   always @(negedge Phi2 or negedge bbc_nRST) begin
      if (!bbc_nRST) begin
         rD2 <= 1'b0;
      end else if (!RnW && FE30_3) begin
         rD2 <= bbc_DATA[2];
      end
   end

   always @(negedge Phi2 or negedge bbc_nRST) begin
      if (!bbc_nRST) begin
         rD3 <= 1'b0;
      end else if (!RnW && FE30_3) begin
         rD3 <= bbc_DATA[3];
      end
   end

	//PrvEn is used in conjunction with addresses in the range &8000..& to select Private RAM
   always @(negedge Phi2 or negedge bbc_nRST) begin
      if (!bbc_nRST) begin
         PrvEn <= 1'b0;
      end else if (!RnW && FE30_3) begin
         PrvEn <= bbc_DATA[6];
      end
   end
 
	always @(negedge Phi2 or negedge bbc_nRST) begin
      if (!bbc_nRST) begin
         MemSel <= 1'b0;
      end else if (!RnW && FE30_3) begin
         MemSel <= bbc_DATA[7];
      end
   end


	//This data is latched when address is in the range FE34..FE37

   always @(negedge Phi2 or negedge bbc_nRST) begin
      if (!bbc_nRST) begin
         PrvS8 <= 1'b0;
      end else if (!RnW && FE34_7) begin
         PrvS8 <= bbc_DATA[4];
      end
   end
	
	always @(negedge Phi2 or negedge bbc_nRST) begin
      if (!bbc_nRST) begin
         PrvS4 <= 1'b0;
      end else if (!RnW && FE34_7) begin
         PrvS4 <= bbc_DATA[5];
      end
   end

   always @(negedge Phi2 or negedge bbc_nRST) begin
      if (!bbc_nRST) begin
         PrvS1 <= 1'b0;
      end else if (!RnW && FE34_7) begin
         PrvS1 <= bbc_DATA[6];
      end
   end

   always @(negedge Phi2 or negedge bbc_nRST) begin
      if (!bbc_nRST) begin
         ShEn <= 1'b0;
      end else if (!RnW && FE34_7) begin
         ShEn <= bbc_DATA[7];
      end
   end

endmodule

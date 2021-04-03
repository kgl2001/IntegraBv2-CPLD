`timescale 1ns / 1ps
/************************************************************************
	 IntegraBV2.v

	 IntegraB V2 - A fully expanded ROM / RAM Board for BBC Micro
	 Revision 01 - December 2020
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
	//	input from_CPU_Phi2, //Temporary input (borrowed output nROMBankSel[14] - Pin 27, GCLK 3)
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
	output nRAM_CE,
	output [18:14] Ram_ADDRESS
	);


	// Repeat RnW & Phi1 from Input to Output
	wire	 Phi1;
	wire	 Phi2;
	wire	 ShAct;
	wire	 RnW;
	assign Phi1			 = from_CPU_Phi1;
	assign Phi2			 = !from_CPU_Phi1;
	//	assign Phi2			 = from_CPU_Phi2;
	assign RnW			 = from_CPU_RnW;
	assign to_bbc_Phi1 = !(!Phi1 & !ShAct);
	assign to_bbc_RnW  = !(!RnW  & !ShAct);
	assign nDBuf_Dir	 = RnW;

	// Address decoding. Note that the lowest 2 bits A0 and A1 are not used.
	wire   FE3x		= (bbc_ADDRESS[15:4] == 12'hFE3);
	wire   FE30_3  = FE3x && (bbc_ADDRESS[3:2] == 2'b00);
	wire   FE34_7  = FE3x && (bbc_ADDRESS[3:2] == 2'b01);
	wire   FE38		= FE3x && (bbc_ADDRESS[3:0] == 4'h8);
	wire   FE39		= FE3x && (bbc_ADDRESS[3:0] == 4'h9);
	wire   FE3A    = FE3x && (bbc_ADDRESS[3:0] == 4'hA);
	wire   FE3B    = FE3x && (bbc_ADDRESS[3:0] == 4'hB);
	wire   FE3C_F  = FE3x && (bbc_ADDRESS[3:2] == 2'b11);

	// Address decoding for Computer Concept PALPROM Type 2 (32k)
	wire   a804x	= (bbc_ADDRESS[15:4] == 12'h804);
	wire   a806x	= (bbc_ADDRESS[15:4] == 12'h806);
	wire   aBFAx	= (bbc_ADDRESS[15:4] == 12'hBFA);
	wire   aBFCx	= (bbc_ADDRESS[15:4] == 12'hBFC);
	wire   aBFEx	= (bbc_ADDRESS[15:4] == 12'hBFE);
	wire   cc2Bk0  = a806x | aBFCx | aBFEx;
	wire   cc2Bk1  = a804x | aBFAx;


	
	// nWDS is normally just !( RnW & !Phi1) but we check for Write protect and hold nWDS high is Write Protect is active.
	// nWDS needs to consider all 16 RAM banks AND the Shadow Bank
	reg	 WP[15:0];	//Soft Write Protect
	reg	 EF[7:0];	//Extended functions
	reg	 long_RST;
	reg	 long_RST2;
	reg	 long_CLR;
	wire	 ShadowSel;
	wire   nRamBankSel[15:0];
	wire	 GenBankSel[15:0];
	assign nRDS = !(  RnW & Phi2 & !long_CLR);
	assign nWDS = !((!RnW & Phi2 & GenBankSel[0]  & WP[0]  & !BeebRomSel[0])
					|   (!RnW & Phi2 & GenBankSel[1]  & WP[1]  & !BeebRomSel[1])
					|   (!RnW & Phi2 & GenBankSel[2]  & WP[2]  & !BeebRomSel[2])
					|   (!RnW & Phi2 & GenBankSel[3]  & WP[3]  & !BeebRomSel[3])
					|	 (!RnW & Phi2 & GenBankSel[4]  & WP[4])
					|   (!RnW & Phi2 & GenBankSel[5]  & WP[5])
					|   (!RnW & Phi2 & GenBankSel[6]  & WP[6])
					|   (!RnW & Phi2 & GenBankSel[7]  & WP[7])
					|   (!RnW & Phi2 & GenBankSel[8]  & WP[8]  & !IntegraRomSel[8])
					|   (!RnW & Phi2 & GenBankSel[9]  & WP[9]  & !IntegraRomSel[9])
					|   (!RnW & Phi2 & GenBankSel[10] & WP[10] & !IntegraRomSel[10])
					|   (!RnW & Phi2 & GenBankSel[11] & WP[11] & !IntegraRomSel[11])
					|   (!RnW & Phi2 & GenBankSel[12] & WP[12] & !IntegraRomSel[12])
					|   (!RnW & Phi2 & GenBankSel[13] & WP[13] & !IntegraRomSel[13])
					|   (!RnW & Phi2 & GenBankSel[14] & WP[14] & !IntegraRomSel[14])
					|   (!RnW & Phi2 & GenBankSel[15] & WP[15] & !IntegraRomSel[15])
					|   (!RnW & Phi2 & GenBankSel[8]           &  IntegraRomSel[8])
					|   (!RnW & Phi2 & GenBankSel[9]           &  IntegraRomSel[9])
					|   (!RnW & Phi2 & GenBankSel[10]          &  IntegraRomSel[10])
					|   (!RnW & Phi2 & GenBankSel[11]          &  IntegraRomSel[11])
					|   (!RnW & Phi2 & GenBankSel[12]          &  IntegraRomSel[12])
					|   (!RnW & Phi2 & GenBankSel[13]          &  IntegraRomSel[13])
					|   (!RnW & Phi2 & GenBankSel[14]          &  IntegraRomSel[14])
					|   (!RnW & Phi2 & GenBankSel[15]          &  IntegraRomSel[15])
					|   (!RnW & Phi2 & ShadowSel));

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
	// Function      | BBC Memory	| 32K RAM
	// --------------+------------+-----------
	//	Screen memory | 3000..7FFF	| 3000..7FFF
	//	Private Prv1  | 8000..83FF	| 0000..03FF
	// Private Prv4  | 8000..8FFF	| 0000..0FFF
	// Private Prv8  | 9000..AFFF | 1000..2FFF
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
	// nRomBankSelB[x] is logic '0' when bank is selected otherwire logic '1'
	// long_RTS2 will enable Beeb ROM banks regardless of BeebROMSel status if long BREAK is performed
	wire   nRomBankSelB[3:0];
	assign nRomBankSelB[0] = !(GenBankSel[0] & (BeebRomSel[0] | long_RST2));
	assign nRomBankSelB[1] = !(GenBankSel[1] & (BeebRomSel[1] | long_RST2));
	assign nRomBankSelB[2] = !(GenBankSel[2] & (BeebRomSel[2] | long_RST2));
	assign nRomBankSelB[3] = !(GenBankSel[3] & (BeebRomSel[3] | long_RST2));
	assign nRomBankSel0_3  = nRomBankSelB[0] & nRomBankSelB[1] & nRomBankSelB[2] & nRomBankSelB[3];

	// Logic to select IntegraB ROM Banks 8..15
	// Check if bank is mapped to ROM on IntegraB board, or to RAM on IntegraB board
	// GenBankSel[x] is the output of the 4..16 line decoder. Logic '1' if output is decoded
	//	IntegraRomSel[x] is based on jumper selection via pull up resistor. Logic '1' selects IntegraB ROM socket. Logic '0' selects onboard RAM
	// nRomBankSel[x] is logic '0' when bank is selected otherwire open collector
	assign nRomBankSel[8]  =  (GenBankSel[8]  & IntegraRomSel[8])  ? 1'b0 : 1'bz;
	assign nRomBankSel[9]  =  (GenBankSel[9]  & IntegraRomSel[9])  ? 1'b0 : 1'bz;
	assign nRomBankSel[10] =  (GenBankSel[10] & IntegraRomSel[10]) ? 1'b0 : 1'bz;
	assign nRomBankSel[11] =  (GenBankSel[11] & IntegraRomSel[11]) ? 1'b0 : 1'bz;
	assign nRomBankSel[12] =  (GenBankSel[12] & IntegraRomSel[12]) ? 1'b0 : 1'bz;
	assign nRomBankSel[13] =  (GenBankSel[13] & IntegraRomSel[13]) ? 1'b0 : 1'bz;
	assign nRomBankSel[14] =  (GenBankSel[14] & IntegraRomSel[14]) ? 1'b0 : 1'bz;
	assign nRomBankSel[15] =  (GenBankSel[15] & IntegraRomSel[15]) ? 1'b0 : 1'bz;

	// Logic to select IntegraB RAM Banks 0..15
	// Check if bank is mapped to ROM on either beeb motherboard / IntegraB board, or to RAM on IntegraB board
	// GenBankSel[x] is the output of the 4..16 line decoder. Logic '1' if output is decoded
	//	IntegraRomSel[x] is based on jumper selection via pull up resistor. Logic '1' selects motherboard ROM. Logic '0' selects onboard RAM
	// nRamBankSel[x] is logic '0' when bank is selected otherwire logic '1'
	assign nRamBankSel[0]	= !(GenBankSel[0]  & !BeebRomSel[0]);
	assign nRamBankSel[1]	= !(GenBankSel[1]  & !BeebRomSel[1]);
	assign nRamBankSel[2]	= !(GenBankSel[2]  & !BeebRomSel[2]);
	assign nRamBankSel[3]	= !(GenBankSel[3]  & !BeebRomSel[3]);
	assign nRamBankSel[4]	= !(GenBankSel[4]);
	assign nRamBankSel[5]	= !(GenBankSel[5]);
	assign nRamBankSel[6]	= !(GenBankSel[6]);
	assign nRamBankSel[7]	= !(GenBankSel[7]);
	assign nRamBankSel[8]	= !(GenBankSel[8]  & !IntegraRomSel[8]);
	assign nRamBankSel[9]	= !(GenBankSel[9]  & !IntegraRomSel[9]);
	assign nRamBankSel[10]  = !(GenBankSel[10] & !IntegraRomSel[10]);
	assign nRamBankSel[11]  = !(GenBankSel[11] & !IntegraRomSel[11]);
	assign nRamBankSel[12]  = !(GenBankSel[12] & !IntegraRomSel[12]);
	assign nRamBankSel[13]  = !(GenBankSel[13] & !IntegraRomSel[13]);
	assign nRamBankSel[14]  = !(GenBankSel[14] & !IntegraRomSel[14]);
	assign nRamBankSel[15]  = !(GenBankSel[15] & !IntegraRomSel[15]);

	// Logic to Enable RAM IC
	// If any RAM bank or shadow / private RAM is being accessed, then nRAM_CE is logic '0' otherwise logic '1'
	assign nRAM_CE				=   nRamBankSel[0]  & nRamBankSel[1]  & nRamBankSel[2]  & nRamBankSel[3]
									&   nRamBankSel[4]  & nRamBankSel[5]  & nRamBankSel[6]  & nRamBankSel[7]
	 								&   nRamBankSel[8]  & nRamBankSel[9]  & nRamBankSel[10] & nRamBankSel[11]
	 								&   nRamBankSel[12] & nRamBankSel[13] & nRamBankSel[14] & nRamBankSel[15] & !ShadowSel;

	// RAM addresses A0..A13 and data lines D0..D7 are wired to the CPU (via buffers on the IntegraB board)
	// RAM addresses A14..A18 are switched by the CPLD based on which RAM bank has been selected
	// ShadowSel is a 32k block based on Shadow RAM and Private RAM. A14 switches between the upper and lower bank.
	// Additional logic on A[16] to allow swapping of RAM Banks 0..3 with RAM Banks 4..7. Swapping can only occur in Recovery Mode


	assign Ram_ADDRESS[14] =  GenBankSel[1]  | GenBankSel[3]  | GenBankSel[5]  | GenBankSel[7]
								  |  GenBankSel[9]  | GenBankSel[11] | GenBankSel[13] | GenBankSel[15]
								  | (bbc_ADDRESS[14] & ShadowSel);
								  
	assign Ram_ADDRESS[15] =  GenBankSel[2]  | GenBankSel[3]  | GenBankSel[6]  | GenBankSel[7]
								  |  GenBankSel[10] | GenBankSel[11] | GenBankSel[14] | GenBankSel[15];
								  
	assign Ram_ADDRESS[16] = ((GenBankSel[0]  | GenBankSel[1]  | GenBankSel[2]  | GenBankSel[3]) &  long_RST2 &  EF[0])
								  | ((GenBankSel[4]  | GenBankSel[5]  | GenBankSel[6]  | GenBankSel[7]) &  long_RST2 & !EF[0])
								  | ((GenBankSel[4]  | GenBankSel[5]  | GenBankSel[6]  | GenBankSel[7]) & !long_RST2)
								  |   GenBankSel[12] | GenBankSel[13] | GenBankSel[14] | GenBankSel[15];
								  
	assign Ram_ADDRESS[17] =  GenBankSel[8]  | GenBankSel[9]  | GenBankSel[10] | GenBankSel[11]
								  |  GenBankSel[12] | GenBankSel[13] | GenBankSel[14] | GenBankSel[15];
								  
	assign Ram_ADDRESS[18] =  ShadowSel;


//	assign Ram_ADDRESS[14] = rD0 & !ShadowSel
//								  | bbc_ADDRESS[14] & ShadowSel;
//	assign Ram_ADDRESS[15] = rD1 & !ShadowSel;
//	assign Ram_ADDRESS[16] = (((((rD2 ^ EF[0]) & !rD3) | (rD2 & rD3)) & long_RST2) | (rD2 & !long_RST2)) & !ShadowSel;
//	assign Ram_ADDRESS[17] = rD3 & !ShadowSel;
//	assign Ram_ADDRESS[18] = ShadowSel;

	// Logic to control RTC address and data strobe lines
	assign RTC_AS          = FE38   && Phi2 && !RnW; // &FE38    -> Address Strobe
	assign RTC_DS          = FE3C_F && Phi2;         // &FE3C..F -> Data Strobe

	// Logic to enable the data buffer.
	// Buffer needs to be enabled (logic low) when accessing onboard SWRAM, SWROM, Shadow RAM, Private RAM, or when writing data to registers &FE30..&FE3F
	assign nDBuf_CE     	  =  !SWRAddr & !ShadowSel & !FE3x
	 							  |  !nRomBankSel0_3 & !ShadowSel & !FE3x; // this line ensures the IntegraB data buffer not active when accessing off board SWROM


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

	//PrvEn is used in conjunction with addresses in the range &8000..&AFFF to select Private RAM
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



	//This code is used to monitor the Break key via bbc_nRST.
	//Switch into Recovery Mode:
	//If the Break key is held for >0.8 seconds, then onboard ROMs 7..15 & RAM 0..15 are read protected.
	//At the same time, ROMs 0..3 are enabled, overriding RAM select function
	//When the Break key is then released, then after a further 0.6 seconds the onboard onboard ROMs 7..15 & RAM 0..15 are read enabled again.
	//RAM select function remains overridden until switched out of Recovery Mode
	//Switch out of Recovery Mode:
	//Press Break key for <0.8 seconds
	
	
	//2MHz clock, so 17 bits required to count 0.1 sec
	reg [20:0] slow_clk = 0;
	reg [7:0] countseca = 0;
	reg [7:0] countsecb = 0;

	always @ (negedge Phi2) begin
			if (slow_clk == 21'd200000) slow_clk <= 21'b0;
			else slow_clk <= slow_clk + 1'b1;
	end

	assign msec_tick = (slow_clk == 21'd200000);

	//Long reset will occur 0.8 seconds after Break is pressed. Long reset will remain active as long as Break continues to be pressed
	//Long reset will clear immediately after Break is released.
	//positive pulse will last for one sec_tick cycle (0.1 sec), so reduce countsec value by 0.1 second to get required period.
	always @ (negedge Phi2) begin
		if (!bbc_nRST && msec_tick) begin
			if (countseca == 8'd7) countseca <= 8'b0;
			else  countseca <= countseca + 1'b1;
		end else if (bbc_nRST) begin
			countseca <= 8'b0;
		end
	end

	assign long_RSTa = (countseca == 8'd7);
	
	//long_RST will go high after BREAK has been held for (long_RSTa * 0.5) + 0.5 seconds
	//long_RST will go low immediately after BREAK is released
	always @ (negedge Phi2) begin
		if (bbc_nRST) long_RST <= 1'b0;
		else if (long_RSTa) long_RST <= 1'b1;
	end

	//long_RST2 will go high at the same time as long_RST goes high
	//but will remain high until Break is pressed again
	//This is effectively a 'In Recovery Mode' flag
	always @ (negedge Phi2) begin
		if (long_CLR) long_RST2 <= 1'b1;
		else if (!bbc_nRST) long_RST2 <= 1'b0;
	end

	always @ (negedge Phi2) begin
		if (!long_RST && msec_tick) begin
			if (countsecb == 8'd5) countsecb <= 8'b0;
			else  countsecb <= countsecb + 1'b1;
		end else if (long_RST) begin
			countsecb <= 8'b0;
		end
	end
	
	assign long_CLRa = (countsecb == 8'd5);
	
	always @ (negedge Phi2) begin
		if (long_CLRa) long_CLR <= 1'b0;
		if (long_RST) long_CLR <= 1'b1;
	end

	//Extended functions
	//Bit 0: Swap Banks 0..3 with Banks 4..7 - Logic 0 - No swap
	//Bit 1: Switch in and out Extra RAM banks (To be implemented)
   always @(negedge Phi2 or negedge bbc_nRST) begin
      if (!bbc_nRST) begin
         EF[0] <= 1'b0;
      end else if (!RnW && FE39) begin
         EF[0] <= bbc_DATA[0];
      end
   end

   always @(negedge Phi2 or negedge bbc_nRST) begin
      if (!bbc_nRST) begin
         EF[1] <= 1'b0;
      end else if (!RnW && FE39) begin
         EF[1] <= bbc_DATA[1];
      end
   end

//   always @(negedge Phi2) begin
//		if (!RnW && FE39) EF[0] <= bbc_DATA[0];
//   end
//	
//   always @(negedge Phi2) begin
//		if (!RnW && FE39) EF[1] <= bbc_DATA[1];
//   end



	//Software based write protect function
	//On start up, all banks are write protected
	//RAM Banks 0..7 are write enabled / protected by writing to address FE3A
	//RAM Banks 8..F are write enabled / protected by writing to address FE3B
	//Logic state 0 = write protected. Logic state 1 = write enabled

	//   always @(negedge Phi2) begin
	//     if (long_RST) begin
	//         WP[0] <= 1'b0;
	//      end else if (!RnW && FE3A) begin
	//         WP[0] <= bbc_DATA[0];
	//      end
	//   end

   always @(negedge Phi2) begin
		if (!RnW && FE3A) WP[0] <= bbc_DATA[0];
   end
	
   always @(negedge Phi2) begin
		if (!RnW && FE3A) WP[1] <= bbc_DATA[1];
   end
	
   always @(negedge Phi2) begin
		if (!RnW && FE3A) WP[2] <= bbc_DATA[2];
   end
	
   always @(negedge Phi2) begin
		if (!RnW && FE3A) WP[3] <= bbc_DATA[3];
   end
	
   always @(negedge Phi2) begin
		if (!RnW && FE3A) WP[4] <= bbc_DATA[4];
   end
	
   always @(negedge Phi2) begin
		if (!RnW && FE3A) WP[5] <= bbc_DATA[5];
   end
	
   always @(negedge Phi2) begin
		if (!RnW && FE3A) WP[6] <= bbc_DATA[6];
   end
	
   always @(negedge Phi2) begin
		if (!RnW && FE3A) WP[7] <= bbc_DATA[7];
   end
	
   always @(negedge Phi2) begin
		if (!RnW && FE3B) WP[8] <= bbc_DATA[0];
   end
	
   always @(negedge Phi2) begin
		if (!RnW && FE3B) WP[9] <= bbc_DATA[1];
   end
	
   always @(negedge Phi2) begin
		if (!RnW && FE3B) WP[10] <= bbc_DATA[2];
   end
	
   always @(negedge Phi2) begin
		if (!RnW && FE3B) WP[11] <= bbc_DATA[3];
   end
	
   always @(negedge Phi2) begin
		if (!RnW && FE3B) WP[12] <= bbc_DATA[4];
   end
	
   always @(negedge Phi2) begin
		if (!RnW && FE3B) WP[13] <= bbc_DATA[5];
   end
	
   always @(negedge Phi2) begin
		if (!RnW && FE3B) WP[14] <= bbc_DATA[6];
   end
	
   always @(negedge Phi2) begin
		if (!RnW && FE3B) WP[15] <= bbc_DATA[7];
   end


   //PALPROM ccA14 switch
	//Currently hard coded to use RAM banks 10 & 11 for testing
	reg ccA14;
   always @(negedge Phi2) begin
      if (cc2Bk0) ccA14 <= 1'b0;
      else if (cc2Bk1) ccA14 <= 1'b1;
   end

	reg ccA14out;
	wire ccA14_clk = (aBFEx & !nRDS & GenBankSel[10]);
   always @(posedge ccA14_clk) begin
      if (!bbc_nRST) ccA14out <= 1'b0;
      else ccA14out <= ccA14;
   end

	
//PIN 15    = !A14RESET; /* Intermediate feedback latch, not connected on PCB */
//PIN 17    = !A14OUT;   /* A14 to 27C256 */
//PIN 19    = !ENBOUT;   /* To Clk PIN 1 on GAL */

//BANK0      = 0x804x # 0xBFAx;
//BANK1      = 0x806x # 0xBFCx # 0xBFEx;
//A14RST = BANK0;

//ENBOUT     = !nCE & !nOE;

//A14RESET.d = BANK0;
//A14OUT.d   = BANK1 # (A14OUT & !A14RST);	
	
	
endmodule

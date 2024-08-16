`timescale 1ns / 1ps
/************************************************************************
IntegraBV2-Rev02a.v

 IntegraB V2  - A fully expanded ROM / RAM Board for BBC Micro
 Revision 01a - July 2024 - Basic IntegraB board implementation
 Revision 02a - July 2024 - Extended functions added:
                Recovery Mode via long RST
		Read default Write Enable status from jumpers on Power Up
		128K PALPROM in Bank 11
		64K PALPROM in Bank 10
						 
Copyright (C) 2024 Ken Lowe

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
   	// input from_CPU_Phi2, //Temporary input (borrowed output nROMBankSel[14] - Pin 27, GCLK 3)
	// Note: If using this input, it is necessary to update the .ucf file, and comment out the
	//       'assign nRomBankSel[14] =' line below.
	//       It is then necessary to jumper from CPU pin 39 over to centre pin on SA4
	input from_CPU_dPhi2,
	input bbc_nRST,
	inout [7:0] bbc_DATA,
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
//	assign Phi2			 = !from_CPU_dPhi2;
	assign RnW			 = from_CPU_RnW;
	assign to_bbc_Phi1 = !(!Phi1 && !ShAct);
	assign to_bbc_RnW  = !(!RnW  && !ShAct);
	assign nDBuf_Dir	 = RnW;

	// Address decoding. Note that the lowest 2 bits A0 and A1 are not used.
	wire   FE3x		= (bbc_ADDRESS[15:4] == 12'hFE3);
	wire   FE30_3  = FE3x && (bbc_ADDRESS[3:2] == 2'b00);
	wire   FE34_7  = FE3x && (bbc_ADDRESS[3:2] == 2'b01);
	wire   FE38		= FE3x && (bbc_ADDRESS[3:0] == 4'h8);
	wire   FE39		= FE3x && (bbc_ADDRESS[3:0] == 4'h9);
	wire   FE3A    = FE3x && (bbc_ADDRESS[3:0] == 4'hA);
	wire   FE3B    = FE3x && (bbc_ADDRESS[3:0] == 4'hB);
	wire   FE3C    = FE3x && (bbc_ADDRESS[3:0] == 4'hC);
	wire   FE3C_F  = FE3x && (bbc_ADDRESS[3:2] == 2'b11);

	// Address decoding for Computer Concept PALPROM Type 2 (32k)
	wire   a80xx	= (bbc_ADDRESS[15:8] == 8'h80);
	wire   a8040	= a80xx && (bbc_ADDRESS[7:5] == 3'b010);
	wire   a8060	= a80xx && (bbc_ADDRESS[7:5] == 3'b011);

	wire   aBFxx	= (bbc_ADDRESS[15:8] == 8'hBF);
	wire   aBFA0	= aBFxx && (bbc_ADDRESS[7:5] == 3'b101);
	wire   aBFC0	= aBFxx && (bbc_ADDRESS[7:5] == 3'b110);
	wire   aBFE0	= aBFxx && (bbc_ADDRESS[7:5] == 3'b111);

	wire   cc2Bk0  = a8060 || aBFC0;
	wire   cc2Bk1  = a8040 || aBFA0 | aBFE0;


	
	reg	 [15:0] WP;								// Soft Write Protect. Status read from jumpers on initial power up.
	reg	 [1:0] EF = 2'b00;					// Extended functions
//	reg	 [1:0] PPEn = 2'b00;					// PALPROM Enabled
	reg	 long_RST;								// Set if Break is held for recovery time. Will clear immediately when Break is released
	reg	 RecMode;								// Set when in recovery mode
	reg	 long_CLR;								// Held high for a period after Break is released, following a long_RST
//	reg	 cc2aOut;								// Used to switch banks in a  32k CC PALPROM
//	reg	 cc2bOut;								// Used to switch banks in a  32k CC PALPROM
	reg	 cc2aBank[1:0];						// Used to switch banks in a  32k CC PALPROM
	reg	 cc2bBank[1:0];						// Used to switch banks in a  32k CC PALPROM
	reg	 [3:0] cc4Bank = 4'b0001;			// Used to switch banks in a  64k CC PALPROM
	reg	 [7:0] cc8Bank = 8'b00000001;		// Used to switch banks in a 128k CC PALPROM
	wire	 ShadowSel;
	wire   [31:0] nRamBankSel;
	wire	 [15:0] GenBankSel;

	assign nRDS = !(  RnW && Phi2 && !long_CLR);

	// nWDS is normally just !( RnW & !Phi1) but we check for Write protect and hold nWDS high is Write Protect is active.
	// nWDS needs to consider all 16 RAM banks AND the Shadow RAM Bank. However, shadow RAM is NEVER write protected.
	// Default Write Protect strategy, where both onboard RAM and external sockets can be soft Write Protected.

	assign nWDS = !((!RnW && Phi2 && GenBankSel[0]  && WP[0])
					||  (!RnW && Phi2 && GenBankSel[1]  && WP[1])
					||  (!RnW && Phi2 && GenBankSel[2]  && WP[2])
					||  (!RnW && Phi2 && GenBankSel[3]  && WP[3])
					||  (!RnW && Phi2 && GenBankSel[4]  && WP[4])
					||  (!RnW && Phi2 && GenBankSel[5]  && WP[5])
					||  (!RnW && Phi2 && GenBankSel[6]  && WP[6])
					||  (!RnW && Phi2 && GenBankSel[7]  && WP[7])
					||  (!RnW && Phi2 && GenBankSel[8]  && WP[8])
					||  (!RnW && Phi2 && GenBankSel[9]  && WP[9])
					||  (!RnW && Phi2 && GenBankSel[10] && WP[10])
					||  (!RnW && Phi2 && GenBankSel[11] && WP[11])
					||  (!RnW && Phi2 && GenBankSel[12] && WP[12])
					||  (!RnW && Phi2 && GenBankSel[13] && WP[13])
					||  (!RnW && Phi2 && GenBankSel[14] && WP[14])
					||  (!RnW && Phi2 && GenBankSel[15] && WP[15])
					||  (!RnW && Phi2 && ShadowSel));


	// Alternative Write Protect strategy, where only onboard RAM can be soft Write Protected.
	/*
	assign nWDS = !((!RnW && Phi2 && GenBankSel[0]  && WP[0]  && !BeebRomSel[0])
					||  (!RnW && Phi2 && GenBankSel[1]  && WP[1]  && !BeebRomSel[1])
					||  (!RnW && Phi2 && GenBankSel[2]  && WP[2]  && !BeebRomSel[2])
					||  (!RnW && Phi2 && GenBankSel[3]  && WP[3]  && !BeebRomSel[3])
					||  (!RnW && Phi2 && GenBankSel[4]  && WP[4])
					||  (!RnW && Phi2 && GenBankSel[5]  && WP[5])
					||  (!RnW && Phi2 && GenBankSel[6]  && WP[6])
					||  (!RnW && Phi2 && GenBankSel[7]  && WP[7])
					||  (!RnW && Phi2 && GenBankSel[8]  && WP[8]  && !IntegraRomSel[8])
					||  (!RnW && Phi2 && GenBankSel[9]  && WP[9]  && !IntegraRomSel[9])
					||  (!RnW && Phi2 && GenBankSel[10] && WP[10] && !IntegraRomSel[10])
					||  (!RnW && Phi2 && GenBankSel[11] && WP[11] && !IntegraRomSel[11])
					||  (!RnW && Phi2 && GenBankSel[12] && WP[12] && !IntegraRomSel[12])
					||  (!RnW && Phi2 && GenBankSel[13] && WP[13] && !IntegraRomSel[13])
					||  (!RnW && Phi2 && GenBankSel[14] && WP[14] && !IntegraRomSel[14])
					||  (!RnW && Phi2 && GenBankSel[15] && WP[15] && !IntegraRomSel[15])
					||  (!RnW && Phi2 && GenBankSel[8]            &&  IntegraRomSel[8])
					||  (!RnW && Phi2 && GenBankSel[9]            &&  IntegraRomSel[9])
					||  (!RnW && Phi2 && GenBankSel[10]           &&  IntegraRomSel[10])
					||  (!RnW && Phi2 && GenBankSel[11]           &&  IntegraRomSel[11])
					||  (!RnW && Phi2 && GenBankSel[12]           &&  IntegraRomSel[12])
					||  (!RnW && Phi2 && GenBankSel[13]           &&  IntegraRomSel[13])
					||  (!RnW && Phi2 && GenBankSel[14]           &&  IntegraRomSel[14])
					||  (!RnW && Phi2 && GenBankSel[15]           &&  IntegraRomSel[15])
					||  (!RnW && Phi2 && ShadowSel));
	*/

	// This logic sets PrvAct to logic state '1' if the addresses in the Private memory range &8000..&AFFF and if one of the Private Memory flags is active. 
	reg	 PrvEn;
	reg	 PrvS8;
	reg	 PrvS4;
	reg	 PrvS1;
	
	assign PrvAct    =   ((bbc_ADDRESS[15:12] == 4'h8) && (bbc_ADDRESS[11:10] == 2'b00) && PrvS1 && PrvEn //address decodes to &8000..&83FF. Maps to &0000..&03FF in Shadow RAM
						  ||   (bbc_ADDRESS[15:12] == 4'h8) &&  PrvS4 && PrvEn   										//address decodes to &8000..&8FFF. Maps to &0000..&0FFF in Shadow RAM
						  ||   (bbc_ADDRESS[15:12] == 4'h9) &&  PrvS8 && PrvEn											//address decodes to &9000..&9FFF. Maps to &1000..&1FFF in Shadow RAM
						  ||   (bbc_ADDRESS[15:12] == 4'hA) &&  PrvS8 && PrvEn);										   //address decodes to &A000..&AFFF. Maps to &2000..&2FFF in Shadow RAM


	// This logic sets ShAct to logic state '1' if the addresses in the screen range &3000..&7FFF and if Shadow Memory is active. 
	reg	 ShEn;
	reg	 MemSel;
	wire	 ScreenMem =  ((bbc_ADDRESS[15:12] == 4'h3)    //address decodes to &3000..&3FFF
						  ||   (bbc_ADDRESS[15:14] == 2'b01)); //address decodes to &4000..&7FFF
	assign ShAct     = ScreenMem && ShEn && !MemSel;


	// ShadowSel is logic '1' when either Shadow or Private RAM is being accessed. 
	// Note that Shadow and Private memory is mapped to a 32k Block of RAM as follows:
	//
	//		Function      | BBC Memory	| 32K RAM
	//		--------------+------------+-----------
	//		Screen memory | 3000..7FFF	| 3000..7FFF
	//		Private Prv1  | 8000..83FF	| 0000..03FF
	//		Private Prv4  | 8000..8FFF	| 0000..0FFF
	//		Private Prv8  | 9000..AFFF | 1000..2FFF
	//
	assign ShadowSel = !(!ShAct && !PrvAct);

	// The following logic is used to demux the ROM banks.
	// Banks 0..3 are located on the Beeb mainboard. These banks can be switched out for SWRAM on the IntegraB board instead
	// Banks 4..7 are SWRAM banks located on the IntegraB board
	// Banks 8..15 are ROM slots on the IntegraB board. These banks can be switched out for SWRAM on the IntegraB board instead
	// All SWRAM can be write protected in 16k banks.
	reg	 [3:0] rD;
	wire	 ROMDec;
	assign to_bbc_rD0 = rD[0];
	assign to_bbc_rD1 = rD[1];

	// If address is in range &8000..&BFFF then SWRAddr = 1, otherwise 0
	wire	 SWRAddr  =  (bbc_ADDRESS[15:14] == 2'b10);

	// Check if address is in the range &8000..&BFFF and it's not Private RAM that's being accessed.
	assign ROMDec   =  ((SWRAddr && !PrvAct && Phi2)
						 ||  (SWRAddr && !PrvAct && !nRomBankSel0_3));

	// GenBankSel[x] is logic '1' when bank is selected

	assign GenBankSel[0]   = (rD == 0'h0) && ROMDec;
	assign GenBankSel[1]   = (rD == 4'h1) && ROMDec;
	assign GenBankSel[2]   = (rD == 4'h2) && ROMDec;
	assign GenBankSel[3]   = (rD == 4'h3) && ROMDec;
	assign GenBankSel[4]   = (rD == 4'h4) && ROMDec;
	assign GenBankSel[5]   = (rD == 4'h5) && ROMDec;
	assign GenBankSel[6]   = (rD == 4'h6) && ROMDec;
	assign GenBankSel[7]   = (rD == 4'h7) && ROMDec;
	assign GenBankSel[8]   = (rD == 4'h8) && ROMDec;
	assign GenBankSel[9]   = (rD == 4'h9) && ROMDec;
	assign GenBankSel[10]  = (rD == 4'hA) && ROMDec;
	assign GenBankSel[11]  = (rD == 4'hB) && ROMDec;
	assign GenBankSel[12]  = (rD == 4'hC) && ROMDec;
	assign GenBankSel[13]  = (rD == 4'hD) && ROMDec;
	assign GenBankSel[14]  = (rD == 4'hE) && ROMDec;
	assign GenBankSel[15]  = (rD == 4'hF) && ROMDec;


	// Logic to select Motherboard ROM Banks 0..3
	// Check if bank is mapped to ROM on beeb motherboard, or to RAM on IntegraB board
	// GenBankSel[x] is the output of the 4..16 line decoder. Logic '1' if output is decoded
	//	BeebRomSel[x] is based on jumper selection via pull up resistor. Logic '1' selects motherboard ROM. Logic '0' selects onboard RAM
	// nRomBankSelB[x] is logic '0' when bank is selected otherwire logic '1'
	// RecMode will enable Beeb ROM banks regardless of BeebROMSel status if long BREAK is performed
	wire   nRomBankSelB[3:0];
	assign nRomBankSelB[0] = !(GenBankSel[0] && (BeebRomSel[0] || RecMode));
	assign nRomBankSelB[1] = !(GenBankSel[1] && (BeebRomSel[1] || RecMode));
	assign nRomBankSelB[2] = !(GenBankSel[2] && (BeebRomSel[2] || RecMode));
	assign nRomBankSelB[3] = !(GenBankSel[3] && (BeebRomSel[3] || RecMode));
	assign nRomBankSel0_3  = nRomBankSelB[0] && nRomBankSelB[1] && nRomBankSelB[2] && nRomBankSelB[3];

	// Logic to select IntegraB ROM Banks 8..15
	// Check if bank is mapped to ROM on IntegraB board, or to RAM on IntegraB board
	// GenBankSel[x] is the output of the 4..16 line decoder. Logic '1' if output is decoded
	//	IntegraRomSel[x] is based on jumper selection via pull up resistor. Logic '1' selects IntegraB ROM socket. Logic '0' selects onboard RAM
	// nRomBankSel[x] is logic '0' when bank is selected otherwire open collector
	assign nRomBankSel[8]  =  (GenBankSel[8]  && IntegraRomSel[8]  && !RecMode) ? 1'b0 : 1'bz;
	assign nRomBankSel[9]  =  (GenBankSel[9]  && IntegraRomSel[9]  && !RecMode) ? 1'b0 : 1'bz;
	assign nRomBankSel[10] =  (GenBankSel[10] && IntegraRomSel[10] && !RecMode) ? 1'b0 : 1'bz;
	assign nRomBankSel[11] =  (GenBankSel[11] && IntegraRomSel[11] && !RecMode) ? 1'b0 : 1'bz;
	assign nRomBankSel[12] =  (GenBankSel[12] && IntegraRomSel[12] && !RecMode) ? 1'b0 : 1'bz;
	assign nRomBankSel[13] =  (GenBankSel[13] && IntegraRomSel[13] && !RecMode) ? 1'b0 : 1'bz;
	assign nRomBankSel[14] =  (GenBankSel[14] && IntegraRomSel[14] && !RecMode) ? 1'b0 : 1'bz;
	assign nRomBankSel[15] =  (GenBankSel[15] && IntegraRomSel[15] && !RecMode) ? 1'b0 : 1'bz;

	// Logic to select IntegraB RAM Banks 0..15
	// Check if bank is mapped to ROM on either beeb motherboard / IntegraB board, or to RAM on IntegraB board
	// GenBankSel[x] is the output of the 4..16 line decoder. Logic '1' if output is decoded
	//	IntegraRomSel[x] is based on jumper selection via pull up resistor. Logic '1' selects motherboard ROM. Logic '0' selects onboard RAM
	// nRamBankSel[x] is logic '0' when bank is selected otherwire logic '1'

	// RAM addresses A0..A13 and data lines D0..D7 are wired to the CPU (via buffers on the IntegraB board)
	// RAM addresses A14..A18 are switched by the CPLD based on which RAM bank has been selected
	// ShadowSel is a 32k block based on Shadow RAM and Private RAM. A14 switches between the upper and lower bank.
	// Additional logic on A[16] to allow swapping of RAM Banks 0..3 with RAM Banks 4..7. Swapping can only occur in Recovery Mode

	assign nRamBankSel[0]	= !((GenBankSel[0]  & !ShadowSel & !RecMode & !BeebRomSel[0])
									|   (GenBankSel[4]  & !ShadowSel &  RecMode &  EF[0]));
	
	assign nRamBankSel[1]	= !((GenBankSel[1]  & !ShadowSel & !RecMode & !BeebRomSel[1])
									|   (GenBankSel[5]  & !ShadowSel &  RecMode &  EF[0]));

	assign nRamBankSel[2]	= !((GenBankSel[2]  & !ShadowSel & !RecMode & !BeebRomSel[2])
									|   (GenBankSel[6]  & !ShadowSel &  RecMode &  EF[0]));

	assign nRamBankSel[3]	= !((GenBankSel[3]  & !ShadowSel & !RecMode & !BeebRomSel[3])
									|   (GenBankSel[7]  & !ShadowSel &  RecMode &  EF[0]));

	assign nRamBankSel[4]	= !((GenBankSel[4]  & !ShadowSel & !RecMode)
									|   (GenBankSel[4]  & !ShadowSel &  RecMode & !EF[0] & !EF[1]));

	assign nRamBankSel[5]	= !((GenBankSel[5]  & !ShadowSel & !RecMode)
									|   (GenBankSel[5]  & !ShadowSel &  RecMode & !EF[0] & !EF[1]));

	assign nRamBankSel[6]	= !((GenBankSel[6]  & !ShadowSel & !RecMode)
									|   (GenBankSel[6]  & !ShadowSel &  RecMode & !EF[0] & !EF[1]));

	assign nRamBankSel[7]	= !((GenBankSel[7]  & !ShadowSel & !RecMode)
									|   (GenBankSel[7]  & !ShadowSel &  RecMode & !EF[0] & !EF[1]));

//	assign nRamBankSel[8]	= !((GenBankSel[8]  & !ShadowSel & !RecMode & !IntegraRomSel[8]  & cc2aBank[0])
//									|   (GenBankSel[8]  & !ShadowSel &  RecMode & !EF[1]));
	assign nRamBankSel[8]	= !((GenBankSel[8]  & !ShadowSel & !RecMode & !IntegraRomSel[8])
									|   (GenBankSel[8]  & !ShadowSel &  RecMode & !EF[1]));

//	assign nRamBankSel[9]	= !((GenBankSel[9]  & !ShadowSel & !RecMode & !IntegraRomSel[9]  & cc2bBank[0])
//									|   (GenBankSel[9]  & !ShadowSel &  RecMode & !EF[1]));
	assign nRamBankSel[9]	= !((GenBankSel[9]  & !ShadowSel & !RecMode & !IntegraRomSel[9])
									|   (GenBankSel[9]  & !ShadowSel &  RecMode & !EF[1]));

	assign nRamBankSel[10]  = !((GenBankSel[10] & !ShadowSel & !RecMode & !IntegraRomSel[10] & cc4Bank[0])
									|   (GenBankSel[10] & !ShadowSel &  RecMode & !EF[1]));
//	assign nRamBankSel[10]  = !((GenBankSel[10] & !ShadowSel & !RecMode & !IntegraRomSel[10])
//									|   (GenBankSel[10] & !ShadowSel &  RecMode & !EF[1]));

	assign nRamBankSel[11]  = !((GenBankSel[11] & !ShadowSel & !RecMode & !IntegraRomSel[11] & cc8Bank[0])
									|   (GenBankSel[11] & !ShadowSel &  RecMode & !EF[1]));
//	assign nRamBankSel[11]  = !((GenBankSel[11] & !ShadowSel & !RecMode & !IntegraRomSel[11])
//									|   (GenBankSel[11] & !ShadowSel &  RecMode & !EF[1]));

	assign nRamBankSel[12]  = !((GenBankSel[12] & !ShadowSel & !RecMode & !IntegraRomSel[12])
									|   (GenBankSel[12] & !ShadowSel &  RecMode & !EF[1]));

	assign nRamBankSel[13]  = !((GenBankSel[13] & !ShadowSel & !RecMode & !IntegraRomSel[13])
									|   (GenBankSel[13] & !ShadowSel &  RecMode & !EF[1]));

	assign nRamBankSel[14]  = !((GenBankSel[14] & !ShadowSel & !RecMode & !IntegraRomSel[14])
									|   (GenBankSel[14] & !ShadowSel &  RecMode & !EF[1]));

	assign nRamBankSel[15]  = !((GenBankSel[15] & !ShadowSel & !RecMode & !IntegraRomSel[15])
									|   (GenBankSel[15] & !ShadowSel &  RecMode & !EF[1]));

	assign nRamBankSel[16]  =  !(ShadowSel & !bbc_ADDRESS[14]);
	assign nRamBankSel[17]  =  !(ShadowSel &  bbc_ADDRESS[14]);

// Banks 22..24 have been assigned to cc4 PALPROM. Base ROM is stored in Bank 10
// Banks 25..31 have been assigned to cc8 PALPROM. Base ROM is stored in Bank 11
//	assign nRamBankSel[31:18]  =  14'b11111111111111;  
	assign nRamBankSel[21:18]  =  4'b1111;  

// Banks 20 & 21 have been assigned to cc2 PALPROMs. Insufficient space in CPLD to include this!
/*	assign nRamBankSel[20]  = !((GenBankSel[8]  & !ShadowSel & !RecMode & !IntegraRomSel[8]  &  ccA14out)		//Bank 1 for cc2 PALPROM. Base ROM is in Bank 8
									|   (GenBankSel[4]  & !ShadowSel &  RecMode & EF[1]));									//Accessed via Bank 4 when in recovery mode

	assign nRamBankSel[21]  = !((GenBankSel[9]  & !ShadowSel & !RecMode & !IntegraRomSel[9]  &  cc2bBank[1])	//Bank 1 for cc2 PALPROM. Base ROM is in Bank 9
									|   (GenBankSel[5]  & !ShadowSel &  RecMode & EF[1]));									//Accessed via Bank 5 when in recovery mode
*/

// Banks 22..24 have been assigned to cc4 PALPROM. Base ROM is stored in Bank 10

	assign nRamBankSel[22]  = !((GenBankSel[10] & !ShadowSel & !RecMode & !IntegraRomSel[10] &  cc4Bank[1])	//Bank 1 for cc4 PALPROM. Base ROM is in Bank 10
									|   (GenBankSel[6]  & !ShadowSel &  RecMode & EF[1]));									//Accessed via Bank 6 when in recovery mode

	assign nRamBankSel[23]  = !((GenBankSel[10] & !ShadowSel & !RecMode & !IntegraRomSel[10] &  cc4Bank[2])	//Bank 2 for cc4 PALPROM. Base ROM is in Bank 10
									|   (GenBankSel[7]  & !ShadowSel &  RecMode & EF[1]));									//Accessed via Bank 7 when in recovery mode

	assign nRamBankSel[24]  = !((GenBankSel[10] & !ShadowSel & !RecMode & !IntegraRomSel[10] &  cc4Bank[3])	//Bank 3 for cc4 PALPROM. Base ROM is in Bank 10
									|   (GenBankSel[8]  & !ShadowSel &  RecMode & EF[1]));									//Accessed via Bank 8 when in recovery mode


// Banks 25..31 have been assigned to cc8 PALPROM. Base ROM is stored in Bank 11
	assign nRamBankSel[25]  = !((GenBankSel[11] & !ShadowSel & !RecMode & !IntegraRomSel[11] &  cc8Bank[1])	//Bank 1 for cc8 PALPROM. Base ROM is in Bank 11
									|   (GenBankSel[9]  & !ShadowSel &  RecMode & EF[1]));									//Accessed via Bank 9 when in recovery mode

	assign nRamBankSel[26]  = !((GenBankSel[11] & !ShadowSel & !RecMode & !IntegraRomSel[11] &  cc8Bank[2])	//Bank 2 for cc8 PALPROM. Base ROM is in Bank 11
									|   (GenBankSel[10] & !ShadowSel &  RecMode & EF[1]));									//Accessed via Bank 10 when in recovery mode

	assign nRamBankSel[27]  = !((GenBankSel[11] & !ShadowSel & !RecMode & !IntegraRomSel[11] &  cc8Bank[3])	//Bank 3 for cc8 PALPROM. Base ROM is in Bank 11
									|   (GenBankSel[11] & !ShadowSel &  RecMode & EF[1]));									//Accessed via Bank 11 when in recovery mode

	assign nRamBankSel[28]  = !((GenBankSel[11] & !ShadowSel & !RecMode & !IntegraRomSel[11] &  cc8Bank[4])	//Bank 4 for cc8 PALPROM. Base ROM is in Bank 11
									|   (GenBankSel[12] & !ShadowSel &  RecMode & EF[1]));									//Accessed via Bank 12 when in recovery mode

	assign nRamBankSel[29]  = !((GenBankSel[11] & !ShadowSel & !RecMode & !IntegraRomSel[11] &  cc8Bank[5])	//Bank 5 for cc8 PALPROM. Base ROM is in Bank 11
									|   (GenBankSel[13] & !ShadowSel &  RecMode & EF[1]));									//Accessed via Bank 13 when in recovery mode

	assign nRamBankSel[30]  = !((GenBankSel[11] & !ShadowSel & !RecMode & !IntegraRomSel[11] &  cc8Bank[6])	//Bank 6 for cc8 PALPROM. Base ROM is in Bank 11
									|   (GenBankSel[14] & !ShadowSel &  RecMode & EF[1]));									//Accessed via Bank 14 when in recovery mode

	assign nRamBankSel[31]  = !((GenBankSel[11] & !ShadowSel & !RecMode & !IntegraRomSel[11] &  cc8Bank[7])	//Bank 7 for cc8 PALPROM. Base ROM is in Bank 11
									|   (GenBankSel[15] & !ShadowSel &  RecMode & EF[1]));									//Accessed via Bank 15 when in recovery mode

	
	// Logic to Enable RAM IC
	// If any RAM bank or shadow / private RAM is being accessed, then nRAM_CE is logic '0' otherwise logic '1'
	assign nRAM_CE				=   nRamBankSel[0]  && nRamBankSel[1]  && nRamBankSel[2]  && nRamBankSel[3]
									&&   nRamBankSel[4]  && nRamBankSel[5]  && nRamBankSel[6]  && nRamBankSel[7]
	 								&&   nRamBankSel[8]  && nRamBankSel[9]  && nRamBankSel[10] && nRamBankSel[11]
	 								&&   nRamBankSel[12] && nRamBankSel[13] && nRamBankSel[14] && nRamBankSel[15]
	 								&&   nRamBankSel[16] && nRamBankSel[17] && nRamBankSel[18] && nRamBankSel[19]
	 								&&   nRamBankSel[20] && nRamBankSel[21] && nRamBankSel[22] && nRamBankSel[23]
	 								&&   nRamBankSel[24] && nRamBankSel[25] && nRamBankSel[26] && nRamBankSel[27]
	 								&&   nRamBankSel[28] && nRamBankSel[29] && nRamBankSel[30] && nRamBankSel[31];

	// This is the code that actually toggles the extended RAM address lines, A14..A18, based on which RAM bank has been selected.
	assign Ram_ADDRESS[14] =  !nRamBankSel[1]  || !nRamBankSel[3]  || !nRamBankSel[5]  || !nRamBankSel[7]
								  || !nRamBankSel[9]  || !nRamBankSel[11] || !nRamBankSel[13] || !nRamBankSel[15]
								  || !nRamBankSel[17] || !nRamBankSel[19] || !nRamBankSel[21] || !nRamBankSel[23]
								  || !nRamBankSel[25] || !nRamBankSel[27] || !nRamBankSel[29] || !nRamBankSel[31];
								  
	assign Ram_ADDRESS[15] =  !nRamBankSel[2]  || !nRamBankSel[3]  || !nRamBankSel[6]  || !nRamBankSel[7]
								  || !nRamBankSel[10] || !nRamBankSel[11] || !nRamBankSel[14] || !nRamBankSel[15]
								  || !nRamBankSel[18] || !nRamBankSel[19] || !nRamBankSel[22] || !nRamBankSel[23]
								  || !nRamBankSel[26] || !nRamBankSel[27] || !nRamBankSel[30] || !nRamBankSel[31];

	assign Ram_ADDRESS[16] =  !nRamBankSel[4]  || !nRamBankSel[5]  || !nRamBankSel[6]  || !nRamBankSel[7]
								  || !nRamBankSel[12] || !nRamBankSel[13] || !nRamBankSel[14] || !nRamBankSel[15]
								  || !nRamBankSel[20] || !nRamBankSel[21] || !nRamBankSel[22] || !nRamBankSel[23]
								  || !nRamBankSel[28] || !nRamBankSel[29] || !nRamBankSel[30] || !nRamBankSel[31];

	assign Ram_ADDRESS[17] =  !nRamBankSel[8]  || !nRamBankSel[9]  || !nRamBankSel[10] || !nRamBankSel[11]
								  || !nRamBankSel[12] || !nRamBankSel[13] || !nRamBankSel[14] || !nRamBankSel[15]
								  || !nRamBankSel[24] || !nRamBankSel[25] || !nRamBankSel[26] || !nRamBankSel[27]
								  || !nRamBankSel[28] || !nRamBankSel[29] || !nRamBankSel[30] || !nRamBankSel[31];

	assign Ram_ADDRESS[18] =  !nRamBankSel[16] || !nRamBankSel[17] || !nRamBankSel[18] || !nRamBankSel[19]
								  || !nRamBankSel[20] || !nRamBankSel[21] || !nRamBankSel[22] || !nRamBankSel[23]
								  || !nRamBankSel[24] || !nRamBankSel[25] || !nRamBankSel[26] || !nRamBankSel[27]
								  || !nRamBankSel[28] || !nRamBankSel[29] || !nRamBankSel[30] || !nRamBankSel[31];
								  

	// Logic to control RTC address and data strobe lines
	assign RTC_AS          = FE38   && Phi2 && !RnW; // &FE38    -> Address Strobe
	assign RTC_DS          = FE3C_F && Phi2;         // &FE3C..F -> Data Strobe

	// Logic to enable the data buffer.
	// Buffer needs to be enabled (logic low) when accessing onboard SWRAM, SWROM, Shadow RAM, Private RAM, or when writing data to registers &FE30..&FE3F
	assign nDBuf_CE     	  =  !SWRAddr && !ShadowSel && !FE3x
	 							  || !nRomBankSel0_3 && !ShadowSel && !FE3x; // this line ensures the IntegraB data buffer not active when accessing off board SWROM


	// This data is latched when address is in the range FE30..FE33
	// rD (or rD[3:0]) is used to decode the selected SWROM bank
	// PrvEn is used in conjunction with addresses in the range &8000..&AFFF to select Private RAM
//	always @(negedge Phi2 or negedge bbc_nRST) begin
	always @(negedge Phi2) begin
      if (!bbc_nRST) begin
			rD     = 4'h0;
			PrvEn  = 1'b0;
			MemSel = 1'b0;
		end
      else if (!RnW && FE30_3) begin
		   rD     = bbc_DATA[3:0];
			PrvEn  = bbc_DATA[6];
			MemSel = bbc_DATA[7];
		end
   end


	// This data is latched when address is in the range FE34..FE37
//	always @(negedge Phi2 or negedge bbc_nRST) begin
	always @(negedge Phi2) begin
       if (!bbc_nRST) begin
			PrvS8 = 1'b0;
			PrvS4 = 1'b0;
			PrvS1 = 1'b0;
			ShEn  = 1'b0;
      end
		else if (!RnW && FE34_7) begin
			PrvS8 = bbc_DATA[4];
			PrvS4 = bbc_DATA[5];
			PrvS1 = bbc_DATA[6];
			ShEn  = bbc_DATA[7];
		end
   end


//  Recovery Mode
//  -------------
//  This code is used to monitor the Break key via bbc_nRST.
//  To switch into Recovery Mode:
//  - If the Break key is held for >0.8 seconds, then onboard ROMs 7..15 & RAM 0..15 are read protected.
//  - At the same time, beeb Motherboard ROMs 0..3 are enabled, overriding RAM select function
//  - When the Break key is then released, then after a further 0.6 seconds the onboard onboard ROMs 7..15 & RAM 0..15 are read enabled again.
//  - RAM select function remains overridden until switched out of Recovery Mode
//  To switch out of Recovery Mode:
//  - Press Break key for <0.8 seconds
// It is recommended that the following ROMS are plugged into the beeb motherboard to allow the Recovery mode to function effectively.
// In normal operation, these ROMs would not be visible. Instead, the equivalent RAM banks would be mapped into these slots:
// - Language ROM (eg BASIC)
// - Filesystem ROM (eg DNFS)
// - SWRAM utility ROM (eg Advanced ROM Manager)
	
	//  2MHz clock, so 18 bits required to count 0.1 sec (200,000 pulses)
	reg [17:0] slow_clk = 0;
	reg [2:0] countseca = 0;
	reg [2:0] countsecb = 0;

	always @ (negedge Phi2) begin
			if (slow_clk == 18'd200000) slow_clk <= 18'b0;
			else slow_clk <= slow_clk + 1'b1;
	end

	assign msec_tick = (slow_clk == 18'd200000);

	//  Long reset will occur 0.8 seconds after Break is pressed. Long reset will remain active as long as Break continues to be pressed
	//  Long reset will clear immediately after Break is released.
	//  positive pulse will last for one sec_tick cycle (0.1 sec), so reduce countsec value by 0.1 second to get required period.
	always @ (negedge Phi2) begin
		if (!bbc_nRST && msec_tick) begin
			if (countseca == 3'd7) countseca <= 3'b0;
			else  countseca <= countseca + 1'b1;
		end else if (bbc_nRST) begin
			countseca <= 3'b0;
		end
	end

	assign long_RSTa = (countseca == 3'd7);
	
	//  long_RST will go high after BREAK has been held for (long_RSTa * 0.5) + 0.5 seconds
	//  long_RST will go low immediately after BREAK is released
	always @ (negedge Phi2) begin
		if (bbc_nRST) long_RST <= 1'b0;
		else if (long_RSTa) long_RST <= 1'b1;
	end

	//  RecMode will go high at the same time as long_RST goes high
	//  but will remain high until Break is pressed again
	//  This is effectively an 'In Recovery Mode' flag
	always @ (negedge Phi2) begin
		if (long_CLR) RecMode <= 1'b1;
		else if (!bbc_nRST) RecMode <= 1'b0;
	end

	always @ (negedge Phi2) begin
		if (!long_RST && msec_tick) begin
			if (countsecb == 3'd5) countsecb <= 3'b0;
			else  countsecb <= countsecb + 1'b1;
		end else if (long_RST) begin
			countsecb <= 3'b0;
		end
	end
	
	assign long_CLRa = (countsecb == 3'd5);
	
	always @ (negedge Phi2) begin
		if (long_CLRa) long_CLR <= 1'b0;
		if (long_RST) long_CLR <= 1'b1;
	end


//  Extended functions
//  ------------------
//  In recovery mode, Beeb ROM banks 0..3 are active, and RAM banks 4..15
//  become visible after the OS has initialised. This allows corrupt RAM
//  banks to be wiped. However, RAM banks 0..3 and extended RAM banks are
//  not initially available in this mode, so the extended functions allow
//  these banks to be mapped in by writing to address &FE39 as follows:
//  EF[0]: Swap RAM Banks 0..3 with Banks 4..7 - Logic 0 - No swap
//  EF[1]: Switch in and out Extra RAM banks

   always @(negedge Phi2) begin
//   always @(negedge Phi2 or negedge bbc_nRST) begin
           if    (!bbc_nRST) EF = 2'b00;
      else if (!RnW && FE39) EF = bbc_DATA;
   end

//   always @(negedge Phi2) begin
//			  if (!RnW && FE39 && RecMode) PPEn = bbc_DATA[3:2];
//   end


//  Software based write protect function
//  -------------------------------------
//  On power up, initial Write Protect status is read from jumper bank RamWriteProt
//  On entering Recovery Mode, RAM Banks 4..7 are write enabled. All others are disabled
//  The Write protect status can subsequently be adjusted as follows:
//  RAM Banks 0..7 are write enabled / protected by writing to address &FE3A
//  RAM Banks 8..F are write enabled / protected by writing to address &FE3B
//  Logic state 0 = write protected. Logic state 1 = write enabled
//
   always @(negedge Phi2) begin
		     if    (!bbc_nRST) WP       = ~RamWriteProt;
		else if (!RnW && FE3A) WP[7:0]  = bbc_DATA;
		else if (!RnW && FE3B) WP[15:8] = bbc_DATA;
	end
	

	assign bbc_DATA[7]   = (Phi2 && FE38 && RnW) ? 1'b0 : 1'bz;
	assign bbc_DATA[6:5] = (Phi2 && FE38 && RnW) ? ~EF[1:0] : 2'bzz;
	assign bbc_DATA[4]   = (Phi2 && FE38 && RnW) ? RecMode : 1'bz;
	assign bbc_DATA[3:0] = (Phi2 && FE38 && RnW) ? ~BeebRomSel[3:0] : 4'bzzzz;
	assign bbc_DATA      = (Phi2 && FE39 && RnW) ? ~IntegraRomSel[15:8] : 8'hzz;
   assign bbc_DATA      = (Phi2 && FE3A && RnW) ? WP[7:0]  : 8'hzz;
   assign bbc_DATA      = (Phi2 && FE3B && RnW) ? WP[15:8] : 8'hzz;


   // 32k Computer Concepts PALPROM (Inter-Word, Inter-Sheet)
	// Currently hard coded to use RAM banks 9 & 23 for testing
	//
	//	wire cc2aClk = (!nRDS & GenBankSel[9]) | !bbc_nRST;
	//	always @(posedge cc2aClk) begin
	//		if (cc2Bk0 || !bbc_nRST) cc2aOut = 1'b0;
	//		if (cc2Bk1) cc2aOut = 1'b1;
	//	end


   // 32k Computer Concepts PALPROM (Inter-Word, Inter-Sheet)
	// Currently hard coded to use RAM banks 10 & 24 for testing
	//	wire cc2bClk = (!nRDS & GenBankSel[10]) | !bbc_nRST;
	//	always @(posedge cc2bClk) begin
	//		if (cc2Bk0 || !bbc_nRST) cc2bOut = 1'b0;
	//		if (cc2Bk1) cc2bOut = 1'b1;
	//	end


   // 32k Computer Concepts PALPROM (Inter-Word, Inter-Sheet)
	// Currently hard coded to use RAM banks 8 & 20 for testing
   //
	//	wire cc2aClk = (!nRDS & GenBankSel[8]) | !bbc_nRST;
   //	always @(posedge cc2aClk) begin
   //		     if ((cc2Bk0) || !bbc_nRST) cc2aBank = 2'b01;		//hBFE0..hBFFF
   //		else if ((cc2Bk1))              cc2aBank = 2'b10;		//hBFC0..hBFDF
   //	end

   //32k Computer Concepts PALPROM (Inter-Word, Inter-Sheet)
	//Currently hard coded to use RAM banks 9 & 21 for testing
	//
	//	wire cc2bClk = (!nRDS & GenBankSel[9]) | !bbc_nRST;
	//	always @(posedge cc2bClk) begin
	//		     if ((cc2Bk0) || !bbc_nRST) cc2bBank = 2'b01;		//hBFE0..hBFFF
	//		else if ((cc2Bk1))				  cc2bBank = 2'b10;		//hBFC0..hBFDF
	//	end


	// This code is lifted from MAME and defines the switch points for Quest Paint and ConQuest:
	//	{
	//		/* switching zones for Quest Paint and ConQuest */
	//		switch (offset & 0x3fe0)
	//		{
	//		case 0x0820: m_bank = 2; break;
	//		case 0x11e0: m_bank = 1; break;
	//		case 0x12c0: m_bank = 3; break;
	//		case 0x1340: m_bank = 0; break;
	//		}
	//	}


   // 32k Watford Electronic PALPROM (Quest Paint)
	// Note the lower 8k is always active, and the upper 8k is switched
	// Since we have no control over A13, we use 4 x 16k banks with the 32K PALPROM mapped as follows:
	// RAM Bank | Address Range | PALPROM Address | Switch
	// ---------+---------------+-----------------+-------------
	// 10       | h8000 - hAFFF | h0000 - h1FFF   | 
	// 10       | hB000 - hCFFF | h0000 - h1FFF   | h9340..h935F
	// 22       | h8000 - hAFFF | h0000 - h1FFF   |
	// 22       | hB000 - hCFFF | h2000 - h3FFF   | h91E0..h91FF
	// 23       | h8000 - hAFFF | h0000 - h1FFF   |
	// 23       | hB000 - hCFFF | h4000 - h5FFF   | h8820..h883F
	// 24       | h8000 - hAFFF | h0000 - h1FFF   |
	// 24       | hB000 - hCFFF | h6000 - h7FFF   | h92C0..h92DF
	
	// Currently hard coded to use RAM banks 10 & 22..24 for testing

	wire cc4Clk = (!nRDS && GenBankSel[10]) || !bbc_nRST;
	always @(posedge cc4Clk) begin
	//	     if (!PPEn[0])															 cc4Bank = 4'b0001;	//Disable PALPROM
	//	else if ((bbc_ADDRESS[15:5] == 11'b1001_0011_010) || !bbc_nRST) cc4Bank = 4'b0001;	//h9340..h935F
		     if ((bbc_ADDRESS[15:5] == 11'b1001_0011_010) || !bbc_nRST) cc4Bank = 4'b0001;	//h9340..h935F
		else if  (bbc_ADDRESS[15:5] == 11'b1001_0001_111)					 cc4Bank = 4'b0010;	//h91E0..h91FF
		else if  (bbc_ADDRESS[15:5] == 11'b1000_1000_001)					 cc4Bank = 4'b0100;	//h8820..h883F
		else if  (bbc_ADDRESS[15:5] == 11'b1001_0010_110)					 cc4Bank = 4'b1000;	//h92C0..h92DF
	end

   // 64k Computer Concepts PALPROM (xxxxxxxxxxx)
	// Currently hard coded to use RAM banks 10 & 22..24 for testing
	//
	//	wire cc4Clk = (!nRDS & GenBankSel[10]) | !bbc_nRST;
	//	always @(posedge cc4Clk) begin
	//		     if ((bbc_ADDRESS[15:5] == 11'b10111111100) || !bbc_nRST) cc4Bank = 4'b0001;	//hBF80..hBF9F
	//		else if ((bbc_ADDRESS[15:5] == 11'b10111111101))				  cc4Bank = 4'b0010;	//hBFA0..hBFBF
	//		else if ((bbc_ADDRESS[15:5] == 11'b10111111110))				  cc4Bank = 4'b0100; //hBFC0..hBFDF
	//		else if ((bbc_ADDRESS[15:5] == 11'b10111111111))				  cc4Bank = 4'b1000;	//hBFE0..hBFFF
	//	end

   // 128k Computer Concepts PALPROM (SpellMaster, MegaROM)
	// Currently hard coded to use RAM banks 11 & 25..31 for testing
	//
	wire cc8Clk = (!nRDS && GenBankSel[11]) || !bbc_nRST;
	always @(posedge cc8Clk) begin
	//	     if (!PPEn[1])																		 cc8Bank = 8'b00000001; //Disable PALPROM
	//	else if ((bbc_ADDRESS[15:5] == 11'b10111111111) || !bbc_nRST)				 cc8Bank = 8'b00000001;	//hBFE0..hBFFF
		     if ((bbc_ADDRESS[15:5] == 11'b10111111111) || !bbc_nRST)				 cc8Bank = 8'b00000001;	//hBFE0..hBFFF
		else if ((bbc_ADDRESS[15:5] == 11'b10111111110) && (cc8Bank[0] == 1'b1)) cc8Bank = 8'b00000010;	//hBFC0..hBFDF
		else if ((bbc_ADDRESS[15:5] == 11'b10111111101) && (cc8Bank[0] == 1'b1)) cc8Bank = 8'b00000100;	//hBFA0..hBFBF
		else if ((bbc_ADDRESS[15:5] == 11'b10111111100) && (cc8Bank[0] == 1'b1)) cc8Bank = 8'b00001000;	//hBF80..hBF9F
		else if ((bbc_ADDRESS[15:5] == 11'b10111111011) && (cc8Bank[0] == 1'b1)) cc8Bank = 8'b00010000;	//hBF60..hBF7F
		else if ((bbc_ADDRESS[15:5] == 11'b10111111010) && (cc8Bank[0] == 1'b1)) cc8Bank = 8'b00100000;	//hBF40..hBF5F
		else if ((bbc_ADDRESS[15:5] == 11'b10111111001) && (cc8Bank[0] == 1'b1)) cc8Bank = 8'b01000000;	//hBF20..hBF3F
		else if ((bbc_ADDRESS[15:5] == 11'b10111111000) && (cc8Bank[0] == 1'b1)) cc8Bank = 8'b10000000;	//hBF00..hBF1F
	end

endmodule

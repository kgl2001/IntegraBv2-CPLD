`timescale 1ns / 1ps
/************************************************************************
IntegraBV2.v

IntegraB V2  -	A fully expanded ROM / RAM Board for BBC Micro
Revision 01a -	July 2024 - Basic IntegraB board implementation
Revision 02a -	July 2024 - Extended functions added:
				Recovery Mode via long RST
				Read default Write Enable status from jumpers on Power Up
				CC 128K PALPROM in Banks 11 & 25..31
				CC 64K or WE(QST) 32K PALPROM in Banks 10 & 22..24
Revision 02b -	August 2024 - Added logic to switch between RAM / PALPROM
				Add logic to access Private & Shadow RAM in Recovery
				Add logic to access unused RAM banks 18 & 19 in Recovery
				Clock PALPROMs on negedge Phi2
				Additional WE PALPROM type added to Bank 11 (WEWAP)
				Additional WE PALPROM type added to Bank 10 (WETED)
				CC 32K PALPROM added to Banks 9 & 21
				CC 32K PALPROM added to Banks 8 & 20

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
	input	from_CPU_RnW,
	input	from_CPU_Phi1,
	// input from_CPU_Phi2, //Temporary input (borrowed output nROMBankSel[14] - Pin 27, GCLK 3)
	// Note: If using this input, it is necessary to update the .ucf file, and comment out the
	//       'assign nRomBankSel[14] =' line below.
	//       It is then necessary to jumper from CPU pin 39 over to centre pin on SA4
	input	from_CPU_dPhi2,
	input	bbc_nRST,
	inout	[7:0]  bbc_DATA,
	input	[15:0] bbc_ADDRESS,
	input	[7:0]  RamWriteProt,
	input	[7:0]  RamPALSel,
	input	[15:8] IntegraRomSel,
	input	[3:0]  BeebRomSel,

	output	to_bbc_Phi1,
	output	to_bbc_RnW,
	output	to_bbc_rD0,
	output	to_bbc_rD1,
	output	nDBuf_CE,
	output	nDBuf_Dir,
	output	nWDS,
	output	nRDS,
	output	nRomBankSel0_3,
	output	[15:8] nRomBankSel,
	output	RTC_AS,
	output	RTC_DS,
	output	nRAM_CE,
	output	[18:14] Ram_ADDRESS
	);


	// Repeat RnW & Phi1 from Input to Output
	wire	Phi1;
	wire	Phi2;
	wire	ShAct;
	wire	RnW;
	assign	Phi1		=  from_CPU_Phi1;
	assign	Phi2		= !from_CPU_Phi1;
//	assign	Phi2		=  from_CPU_Phi2;
//	assign	Phi2		= !from_CPU_dPhi2;
	assign	RnW			=  from_CPU_RnW;
	assign	to_bbc_Phi1	= !(!Phi1 && !ShAct);
	assign	to_bbc_RnW	= !(!RnW  && !ShAct);
	assign	nDBuf_Dir	= RnW;

	// Address decoding.
	wire	aFE3x	= (bbc_ADDRESS[15:4] == 12'hFE3);
	wire	aFE30_3	= aFE3x && (bbc_ADDRESS[3:2] == 2'b00);
	wire	aFE34_7	= aFE3x && (bbc_ADDRESS[3:2] == 2'b01);
	wire	aFE38	= aFE3x && (bbc_ADDRESS[3:0] == 4'h8);
	wire	aFE39	= aFE3x && (bbc_ADDRESS[3:0] == 4'h9);
	wire	aFE3A	= aFE3x && (bbc_ADDRESS[3:0] == 4'hA);
	wire	aFE3B	= aFE3x && (bbc_ADDRESS[3:0] == 4'hB);
	wire	aFE3C	= aFE3x && (bbc_ADDRESS[3:0] == 4'hC);
	wire	aFE3F	= aFE3x && (bbc_ADDRESS[3:0] == 4'hF);

	// Address decoding for Computer Concept 32k PALPROM
	wire	a80xx	= (bbc_ADDRESS[15:8] == 8'h80);
	wire	a8040	= a80xx && (bbc_ADDRESS[7:5] == 3'b010);
	wire	a8060	= a80xx && (bbc_ADDRESS[7:5] == 3'b011);

	wire	aBFxx	= (bbc_ADDRESS[15:8] == 8'hBF);
	wire	aBFA0	= aBFxx && (bbc_ADDRESS[7:5] == 3'b101);
	wire	aBFC0	= aBFxx && (bbc_ADDRESS[7:5] == 3'b110);
	wire	aBFE0	= aBFxx && (bbc_ADDRESS[7:5] == 3'b111);

	// Switch points for Computer Concept 32k PALPROM
	wire	acc2Bk0 = a8060 || aBFC0;
	wire	acc2Bk1 = a8040 || aBFA0 || aBFE0;

	
	reg		[15:0] WP;						// Soft Write Protect. Status read from jumpers on initial power up.
	reg		[1:0] EF = 2'b00;				// Extended functions
	reg		long_RST;						// Set if Break is held for recovery time. Will clear immediately when Break is released
	reg		RecMode;						// Set when in recovery mode
	reg		long_CLR;						// Held high for a period after Break is released, following a long_RST
	reg		[1:0] pp2aBank = 2'b01;			// Used to switch banks in a  32k CC PALPROM
	reg		[1:0] pp2bBank = 2'b01;			// Used to switch banks in a  32k CC PALPROM
	reg		[3:0] pp4Bank = 4'b0001;		// Used to switch banks in a  64k CC PALPROM
	reg		[7:0] pp8Bank = 8'b00000001;	// Used to switch banks in a 128k CC PALPROM
	wire	ShadowSel;
	wire	[31:0] nRamBankSel;
	wire	[15:0] GenBankSel;

	assign	nRDS = !(  RnW && Phi2 && !long_CLR);

	// nWDS is normally just !( RnW & !Phi1) but we check for Write protect and hold nWDS high is Write Protect is active.
	// nWDS needs to consider all 16 RAM banks AND the Shadow RAM Bank. However, shadow RAM is NEVER write protected.
	// Default Write Protect strategy, where both onboard RAM and external sockets can be soft Write Protected.

	assign	nWDS = !((!RnW && Phi2 && GenBankSel[0]  && WP[0])
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
	assign	nWDS = !((!RnW && Phi2 && GenBankSel[0]  && WP[0]  && !BeebRomSel[0])
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
	reg		PrvEn;
	reg		PrvS8;
	reg		PrvS4;
	reg		PrvS1;
	
	assign	PrvAct	=   ((bbc_ADDRESS[15:12] == 4'h8) && (bbc_ADDRESS[11:10] == 2'b00) && PrvS1 && PrvEn	//address decodes to &8000..&83FF. Maps to &0000..&03FF in Shadow RAM
					||   (bbc_ADDRESS[15:12] == 4'h8) &&  PrvS4 && PrvEn   									//address decodes to &8000..&8FFF. Maps to &0000..&0FFF in Shadow RAM
					||   (bbc_ADDRESS[15:12] == 4'h9) &&  PrvS8 && PrvEn									//address decodes to &9000..&9FFF. Maps to &1000..&1FFF in Shadow RAM
					||   (bbc_ADDRESS[15:12] == 4'hA) &&  PrvS8 && PrvEn);									//address decodes to &A000..&AFFF. Maps to &2000..&2FFF in Shadow RAM


	// This logic sets ShAct to logic state '1' if the addresses in the screen range &3000..&7FFF and if Shadow Memory is active. 
	reg		ShEn;
	reg		MemSel;
	wire	ScreenMem	=  ((bbc_ADDRESS[15:12] == 4'h3)    //address decodes to &3000..&3FFF
						||  (bbc_ADDRESS[15:14] == 2'b01)); //address decodes to &4000..&7FFF
	assign	ShAct		= ScreenMem && ShEn && !MemSel;


	// ShadowSel is logic '1' when either Shadow or Private RAM is being accessed. 
	// Note that Shadow and Private memory is mapped to a 32k Block of RAM as follows:
	//
	// Function      | BBC Memory | 32K RAM
	// --------------+------------+-----------
	// Screen memory | 3000..7FFF | 3000..7FFF
	// Private Prv1  | 8000..83FF | 0000..03FF
	// Private Prv4  | 8000..8FFF | 0000..0FFF
	// Private Prv8  | 9000..AFFF | 1000..2FFF
	//
	assign	ShadowSel = !(!ShAct && !PrvAct);

	// The following logic is used to demux the ROM banks.
	// Banks 0..3 are located on the Beeb mainboard. These banks can be switched out for SWRAM on the IntegraB board instead
	// Banks 4..7 are SWRAM banks located on the IntegraB board
	// Banks 8..15 are ROM slots on the IntegraB board. These banks can be switched out for SWRAM on the IntegraB board instead
	// All SWRAM can be write protected in 16k banks.
	reg		[3:0] rD;
	wire	BankDecode;
	assign	to_bbc_rD0 = rD[0];
	assign	to_bbc_rD1 = rD[1];

	// If address is in range &8000..&BFFF then SWRAddr = 1, otherwise 0
	wire	SWRAddr			= (bbc_ADDRESS[15:14] == 2'b10);

	// Check if address is in the range &8000..&BFFF and it's not Private RAM that's being accessed.
	//	assign BankDecode	=  ((SWRAddr && !PrvAct && Phi2)
	//				 	 	||  (SWRAddr && !PrvAct && !nRomBankSel0_3));
	// Moved Phi2 test onto nROMBankSel
	assign	BankDecode		=  (SWRAddr && !PrvAct);

	// GenBankSel[x] is logic '1' when bank is selected

	assign	GenBankSel[0]	= (rD == 4'h0) && BankDecode;
	assign	GenBankSel[1]	= (rD == 4'h1) && BankDecode;
	assign	GenBankSel[2]	= (rD == 4'h2) && BankDecode;
	assign	GenBankSel[3]	= (rD == 4'h3) && BankDecode;
	assign	GenBankSel[4]	= (rD == 4'h4) && BankDecode;
	assign	GenBankSel[5]	= (rD == 4'h5) && BankDecode;
	assign	GenBankSel[6]	= (rD == 4'h6) && BankDecode;
	assign	GenBankSel[7]	= (rD == 4'h7) && BankDecode;
	assign	GenBankSel[8]	= (rD == 4'h8) && BankDecode;
	assign	GenBankSel[9]	= (rD == 4'h9) && BankDecode;
	assign	GenBankSel[10]	= (rD == 4'hA) && BankDecode;
	assign	GenBankSel[11]	= (rD == 4'hB) && BankDecode;
	assign	GenBankSel[12]	= (rD == 4'hC) && BankDecode;
	assign	GenBankSel[13]	= (rD == 4'hD) && BankDecode;
	assign	GenBankSel[14]	= (rD == 4'hE) && BankDecode;
	assign	GenBankSel[15]	= (rD == 4'hF) && BankDecode;


	// Logic to select Motherboard ROM Banks 0..3
	// Check if bank is mapped to ROM on beeb motherboard, or to RAM on IntegraB board
	// GenBankSel[x] is the output of the 4..16 line decoder. Logic '1' if output is decoded
	// BeebRomSel[x] is based on jumper selection via pull up resistor. Logic '1' selects motherboard ROM. Logic '0' selects onboard RAM
	// nRomBankSelB[x] is logic '0' when bank is selected otherwire logic '1'
	// RecMode will enable Beeb ROM banks regardless of BeebROMSel status if long BREAK is performed
	wire	nRomBankSelB[3:0];
	assign	nRomBankSelB[0] = !(GenBankSel[0] && (BeebRomSel[0] || RecMode));
	assign	nRomBankSelB[1] = !(GenBankSel[1] && (BeebRomSel[1] || RecMode));
	assign	nRomBankSelB[2] = !(GenBankSel[2] && (BeebRomSel[2] || RecMode));
	assign	nRomBankSelB[3] = !(GenBankSel[3] && (BeebRomSel[3] || RecMode));
	assign	nRomBankSel0_3  = nRomBankSelB[0] && nRomBankSelB[1] && nRomBankSelB[2] && nRomBankSelB[3];

	// Logic to select IntegraB ROM Banks 8..15
	// Check if bank is mapped to ROM on IntegraB board, or to RAM on IntegraB board
	// GenBankSel[x] is the output of the 4..16 line decoder. Logic '1' if output is decoded
	// IntegraRomSel[x] is based on jumper selection via pull up resistor. Logic '1' selects IntegraB ROM socket. Logic '0' selects onboard RAM
	// nRomBankSel[x] is logic '0' when bank is selected otherwire open collector
	// Added Phi2 into this logic to satisfy FRAM requirements (removed from BankDecode to fix loop).
	
	assign	nRomBankSel[8]  =  (GenBankSel[8]  && IntegraRomSel[8]  && !RecMode && Phi2) ? 1'b0 : 1'bz;
	assign	nRomBankSel[9]  =  (GenBankSel[9]  && IntegraRomSel[9]  && !RecMode && Phi2) ? 1'b0 : 1'bz;
	assign	nRomBankSel[10] =  (GenBankSel[10] && IntegraRomSel[10] && !RecMode && Phi2) ? 1'b0 : 1'bz;
	assign	nRomBankSel[11] =  (GenBankSel[11] && IntegraRomSel[11] && !RecMode && Phi2) ? 1'b0 : 1'bz;
	assign	nRomBankSel[12] =  (GenBankSel[12] && IntegraRomSel[12] && !RecMode && Phi2) ? 1'b0 : 1'bz;
	assign	nRomBankSel[13] =  (GenBankSel[13] && IntegraRomSel[13] && !RecMode && Phi2) ? 1'b0 : 1'bz;
	assign	nRomBankSel[14] =  (GenBankSel[14] && IntegraRomSel[14] && !RecMode && Phi2) ? 1'b0 : 1'bz;
	assign	nRomBankSel[15] =  (GenBankSel[15] && IntegraRomSel[15] && !RecMode && Phi2) ? 1'b0 : 1'bz;
	
	// Logic to select IntegraB RAM Banks 0..15
	// Check if bank is mapped to ROM on either beeb motherboard / IntegraB board, or to RAM on IntegraB board
	// GenBankSel[x] is the output of the 4..16 line decoder. Logic '1' if output is decoded
	// IntegraRomSel[x] is based on jumper selection via pull up resistor. Logic '1' selects motherboard ROM. Logic '0' selects onboard RAM
	// nRamBankSel[x] is logic '0' when bank is selected otherwire logic '1'

	// RAM addresses A0..A13 and data lines D0..D7 are wired to the CPU (via buffers on the IntegraB board)
	// RAM addresses A14..A18 are switched by the CPLD based on which RAM bank has been selected
	// ShadowSel is a 32k block based on Shadow RAM and Private RAM. A14 switches between the upper and lower bank.
	// 'Extended Function' logic allows the following RAM bank remapping whilst in Recovery Mode:
	//		mapping of RAM Banks 0..15 into GenBanks 0..15 by setting EF[0]=0 & EF[1]=0.
	//		mapping of RAM Banks 0..3 into GenBanks 4..7 by setting EF[0]=1 & EF[1]=0.
	// 		mapping of Private & Shadow RAM Banks 16 & 17 into GenBanks 12 & 13 by setting EF[0]=1 & EF[1]=0.
	//		mapping of unused RAM Banks 18 & 19 into GenBanks 14 & 15 by setting EF[0]=1 & EF[1]=0.
	//		mapping of PALPROM hidden banks 20..31 into GenBanks 4..15 by setting EF[1]=1.
	// Banks 8..11 can be switched between RAM & PALPROM via Jumpers. This is done in the PALPROM logic.

	assign	nRamBankSel[0]	= !((GenBankSel[0]  && !ShadowSel && !RecMode && !BeebRomSel[0])
							||  (GenBankSel[4]  && !ShadowSel &&  RecMode &&  EF[0] &&  !EF[1]));
	
	assign	nRamBankSel[1]	= !((GenBankSel[1]  && !ShadowSel && !RecMode && !BeebRomSel[1])
							||  (GenBankSel[5]  && !ShadowSel &&  RecMode &&  EF[0] &&  !EF[1]));

	assign	nRamBankSel[2]	= !((GenBankSel[2]  && !ShadowSel && !RecMode && !BeebRomSel[2])
							||  (GenBankSel[6]  && !ShadowSel &&  RecMode &&  EF[0] &&  !EF[1]));

	assign	nRamBankSel[3]	= !((GenBankSel[3]  && !ShadowSel && !RecMode && !BeebRomSel[3])
							||  (GenBankSel[7]  && !ShadowSel &&  RecMode &&  EF[0] &&  !EF[1]));

	assign	nRamBankSel[4]	= !((GenBankSel[4]  && !ShadowSel && !RecMode)
							||  (GenBankSel[4]  && !ShadowSel &&  RecMode && !EF[0] && !EF[1]));

	assign	nRamBankSel[5]	= !((GenBankSel[5]  && !ShadowSel && !RecMode)
							||  (GenBankSel[5]  && !ShadowSel &&  RecMode && !EF[0] && !EF[1]));

	assign	nRamBankSel[6]	= !((GenBankSel[6]  && !ShadowSel && !RecMode)
							||  (GenBankSel[6]  && !ShadowSel &&  RecMode && !EF[0] && !EF[1]));

	assign	nRamBankSel[7]	= !((GenBankSel[7]  && !ShadowSel && !RecMode)
							||  (GenBankSel[7]  && !ShadowSel &&  RecMode && !EF[0] && !EF[1]));

	assign	nRamBankSel[8]	= !((GenBankSel[8]  && !ShadowSel && !RecMode && !IntegraRomSel[8]  && pp2aBank[0])
							||  (GenBankSel[8]  && !ShadowSel &&  RecMode && !EF[1]));

	assign	nRamBankSel[9]	= !((GenBankSel[9]  && !ShadowSel && !RecMode && !IntegraRomSel[9]  && pp2bBank[0])
							||  (GenBankSel[9]  && !ShadowSel &&  RecMode && !EF[1]));

	assign	nRamBankSel[10]	= !((GenBankSel[10] && !ShadowSel && !RecMode && !IntegraRomSel[10] && pp4Bank[0])
							||  (GenBankSel[10] && !ShadowSel &&  RecMode && !EF[1]));

	assign	nRamBankSel[11]	= !((GenBankSel[11] && !ShadowSel && !RecMode && !IntegraRomSel[11] && pp8Bank[0])
							||  (GenBankSel[11] && !ShadowSel &&  RecMode && !EF[1]));


	assign	nRamBankSel[12]	= !((GenBankSel[12] && !ShadowSel && !RecMode && !IntegraRomSel[12])
							||  (GenBankSel[12] && !ShadowSel &&  RecMode && !EF[0] && !EF[1]));

	assign	nRamBankSel[13]	= !((GenBankSel[13] && !ShadowSel && !RecMode && !IntegraRomSel[13])
							||  (GenBankSel[13] && !ShadowSel &&  RecMode && !EF[0] && !EF[1]));
	
	assign	nRamBankSel[14]	= !((GenBankSel[14] && !ShadowSel && !RecMode && !IntegraRomSel[14])
							||  (GenBankSel[14] && !ShadowSel &&  RecMode && !EF[0] && !EF[1]));

	assign	nRamBankSel[15]	= !((GenBankSel[15] && !ShadowSel && !RecMode && !IntegraRomSel[15])
							||  (GenBankSel[15] && !ShadowSel &&  RecMode && !EF[0] && !EF[1]));

	// Note: In Recovery Mode, ShadowSel is always at logic 0 (set by ShEn latch).
	assign	nRamBankSel[16]	= !((ShadowSel && !bbc_ADDRESS[14])
							||  (GenBankSel[12] && !ShadowSel &&  RecMode &&  EF[0] &&  !EF[1]));

	// Note: In Recovery Mode, ShadowSel is always at logic 0 (set by ShEn latch).
	assign	nRamBankSel[17]	= !((ShadowSel &&  bbc_ADDRESS[14])
							||  (GenBankSel[13] && !ShadowSel &&  RecMode &&  EF[0] &&  !EF[1]));

	assign	nRamBankSel[18]	=  !(GenBankSel[14] && !ShadowSel &&  RecMode &&  EF[0] &&  !EF[1]); // Bank 18 is unused

	assign	nRamBankSel[19]	=  !(GenBankSel[15] && !ShadowSel &&  RecMode &&  EF[0] &&  !EF[1]); // Bank 19 is unused
							
	// Bank 20 has been assigned to pp2a PALPROM. Base ROM is stored in Banks 8
	assign	nRamBankSel[20]	= !((GenBankSel[8]  && !ShadowSel && !RecMode && !IntegraRomSel[8] &&  pp2aBank[1])	//Bank 1 for pp2 PALPROM. Base ROM is in Bank 8
							||  (GenBankSel[4]  && !ShadowSel &&  RecMode && EF[1]));							//Accessed via Bank 4 when in recovery mode

	// Bank 21 has been assigned to pp2b PALPROM. Base ROM is stored in Banks 9
	assign	nRamBankSel[21]	= !((GenBankSel[9]  && !ShadowSel && !RecMode && !IntegraRomSel[9] &&  pp2bBank[1])	//Bank 1 for pp2 PALPROM. Base ROM is in Bank 9
							||  (GenBankSel[5]  && !ShadowSel &&  RecMode && EF[1]));							//Accessed via Bank 5 when in recovery mode
	
	// Banks 22..24 have been assigned to pp4 PALPROM. Base ROM is stored in Bank 10
	assign	nRamBankSel[22]	= !((GenBankSel[10] && !ShadowSel && !RecMode && !IntegraRomSel[10] && pp4Bank[1])	//Bank 1 for pp4 PALPROM. Base ROM is in Bank 10
							||  (GenBankSel[6]  && !ShadowSel &&  RecMode && EF[1]));							//Accessed via Bank 6 when in recovery mode

	assign	nRamBankSel[23]	= !((GenBankSel[10] && !ShadowSel && !RecMode && !IntegraRomSel[10] && pp4Bank[2])	//Bank 2 for pp4 PALPROM. Base ROM is in Bank 10
							||  (GenBankSel[7]  && !ShadowSel &&  RecMode && EF[1]));							//Accessed via Bank 7 when in recovery mode

	assign	nRamBankSel[24]	= !((GenBankSel[10] && !ShadowSel && !RecMode && !IntegraRomSel[10] && pp4Bank[3])	//Bank 3 for pp4 PALPROM. Base ROM is in Bank 10
							||  (GenBankSel[8]  && !ShadowSel &&  RecMode && EF[1]));							//Accessed via Bank 8 when in recovery mode

	// Banks 25..31 have been assigned to pp8 PALPROM. Base ROM is stored in Bank 11
	assign	nRamBankSel[25]	= !((GenBankSel[11] && !ShadowSel && !RecMode && !IntegraRomSel[11] && pp8Bank[1])	//Bank 1 for pp8 PALPROM. Base ROM is in Bank 11
							||  (GenBankSel[9]  && !ShadowSel &&  RecMode && EF[1]));							//Accessed via Bank 9 when in recovery mode

	assign	nRamBankSel[26]	= !((GenBankSel[11] && !ShadowSel && !RecMode && !IntegraRomSel[11] && pp8Bank[2])	//Bank 2 for pp8 PALPROM. Base ROM is in Bank 11
							||  (GenBankSel[10] && !ShadowSel &&  RecMode && EF[1]));							//Accessed via Bank 10 when in recovery mode

	assign	nRamBankSel[27]	= !((GenBankSel[11] && !ShadowSel && !RecMode && !IntegraRomSel[11] && pp8Bank[3])	//Bank 3 for pp8 PALPROM. Base ROM is in Bank 11
							||  (GenBankSel[11] && !ShadowSel &&  RecMode && EF[1]));							//Accessed via Bank 11 when in recovery mode

	assign	nRamBankSel[28]	= !((GenBankSel[11] && !ShadowSel && !RecMode && !IntegraRomSel[11] && pp8Bank[4])	//Bank 4 for pp8 PALPROM. Base ROM is in Bank 11
							||  (GenBankSel[12] && !ShadowSel &&  RecMode && EF[1]));							//Accessed via Bank 12 when in recovery mode

	assign	nRamBankSel[29]	= !((GenBankSel[11] && !ShadowSel && !RecMode && !IntegraRomSel[11] && pp8Bank[5])	//Bank 5 for pp8 PALPROM. Base ROM is in Bank 11
							||  (GenBankSel[13] && !ShadowSel &&  RecMode && EF[1]));							//Accessed via Bank 13 when in recovery mode

	assign	nRamBankSel[30]	= !((GenBankSel[11] && !ShadowSel && !RecMode && !IntegraRomSel[11] && pp8Bank[6])	//Bank 6 for pp8 PALPROM. Base ROM is in Bank 11
							||  (GenBankSel[14] && !ShadowSel &&  RecMode && EF[1]));							//Accessed via Bank 14 when in recovery mode

	assign	nRamBankSel[31]	= !((GenBankSel[11] && !ShadowSel && !RecMode && !IntegraRomSel[11] && pp8Bank[7])	//Bank 7 for pp8 PALPROM. Base ROM is in Bank 11
							||  (GenBankSel[15] && !ShadowSel &&  RecMode && EF[1]));							//Accessed via Bank 15 when in recovery mode

	
	// Logic to Enable RAM IC
	// If any RAM bank or shadow / private RAM is being accessed, then nRAM_CE is logic '0' otherwise logic '1'
	assign	nRAM_CE			=   nRamBankSel[0]  && nRamBankSel[1]  && nRamBankSel[2]  && nRamBankSel[3]
							&&  nRamBankSel[4]  && nRamBankSel[5]  && nRamBankSel[6]  && nRamBankSel[7]
	 						&&  nRamBankSel[8]  && nRamBankSel[9]  && nRamBankSel[10] && nRamBankSel[11]
	 						&&  nRamBankSel[12] && nRamBankSel[13] && nRamBankSel[14] && nRamBankSel[15]
	 						&&  nRamBankSel[16] && nRamBankSel[17] && nRamBankSel[18] && nRamBankSel[19]
	 						&&  nRamBankSel[20] && nRamBankSel[21] && nRamBankSel[22] && nRamBankSel[23]
	 						&&  nRamBankSel[24] && nRamBankSel[25] && nRamBankSel[26] && nRamBankSel[27]
	 						&&  nRamBankSel[28] && nRamBankSel[29] && nRamBankSel[30] && nRamBankSel[31];

	// This is the code that actually toggles the extended RAM address lines, A14..A18, based on which RAM bank has been selected.
	assign	Ram_ADDRESS[14]	=  !nRamBankSel[1]  || !nRamBankSel[3]  || !nRamBankSel[5]  || !nRamBankSel[7]
							|| !nRamBankSel[9]  || !nRamBankSel[11] || !nRamBankSel[13] || !nRamBankSel[15]
							|| !nRamBankSel[17] || !nRamBankSel[19] || !nRamBankSel[21] || !nRamBankSel[23]
							|| !nRamBankSel[25] || !nRamBankSel[27] || !nRamBankSel[29] || !nRamBankSel[31];
								  
	assign	Ram_ADDRESS[15]	=  !nRamBankSel[2]  || !nRamBankSel[3]  || !nRamBankSel[6]  || !nRamBankSel[7]
							|| !nRamBankSel[10] || !nRamBankSel[11] || !nRamBankSel[14] || !nRamBankSel[15]
							|| !nRamBankSel[18] || !nRamBankSel[19] || !nRamBankSel[22] || !nRamBankSel[23]
							|| !nRamBankSel[26] || !nRamBankSel[27] || !nRamBankSel[30] || !nRamBankSel[31];

	assign	Ram_ADDRESS[16]	=  !nRamBankSel[4]  || !nRamBankSel[5]  || !nRamBankSel[6]  || !nRamBankSel[7]
							|| !nRamBankSel[12] || !nRamBankSel[13] || !nRamBankSel[14] || !nRamBankSel[15]
							|| !nRamBankSel[20] || !nRamBankSel[21] || !nRamBankSel[22] || !nRamBankSel[23]
							|| !nRamBankSel[28] || !nRamBankSel[29] || !nRamBankSel[30] || !nRamBankSel[31];

	assign	Ram_ADDRESS[17]	=  !nRamBankSel[8]  || !nRamBankSel[9]  || !nRamBankSel[10] || !nRamBankSel[11]
							|| !nRamBankSel[12] || !nRamBankSel[13] || !nRamBankSel[14] || !nRamBankSel[15]
							|| !nRamBankSel[24] || !nRamBankSel[25] || !nRamBankSel[26] || !nRamBankSel[27]
							|| !nRamBankSel[28] || !nRamBankSel[29] || !nRamBankSel[30] || !nRamBankSel[31];

	assign	Ram_ADDRESS[18]	=  !nRamBankSel[16] || !nRamBankSel[17] || !nRamBankSel[18] || !nRamBankSel[19]
							|| !nRamBankSel[20] || !nRamBankSel[21] || !nRamBankSel[22] || !nRamBankSel[23]
							|| !nRamBankSel[24] || !nRamBankSel[25] || !nRamBankSel[26] || !nRamBankSel[27]
							|| !nRamBankSel[28] || !nRamBankSel[29] || !nRamBankSel[30] || !nRamBankSel[31];
								  

	// Logic to control RTC address and data strobe lines
	assign	RTC_AS			= aFE38 && Phi2 && !RnW; // &FE38 -> Address Strobe
	assign	RTC_DS			= aFE3C && Phi2;         // &FE3C -> Data Strobe

	// Logic to enable the data buffer.
	// Buffer needs to be enabled (logic low) when accessing onboard SWRAM, SWROM, Shadow RAM, Private RAM, or when writing data to registers &FE30..&FE3F
	assign	nDBuf_CE		=  !SWRAddr && !ShadowSel && !aFE3x
	 						|| !nRomBankSel0_3 && !ShadowSel && !aFE3x; // this line ensures the IntegraB data buffer not active when accessing off board SWROM


	// This data is latched when address is in the range FE30..FE33
	// rD (or rD[3:0]) is used to decode the selected SWROM bank
	// PrvEn is used in conjunction with addresses in the range &8000..&AFFF to select Private RAM
	always @(negedge Phi2) begin
		if (!bbc_nRST) begin
			rD     = 4'h0;
			PrvEn  = 1'b0;
			MemSel = 1'b0;
		end
		else if (!RnW && aFE30_3) begin
			rD     = bbc_DATA[3:0];
			PrvEn  = bbc_DATA[6];
			MemSel = bbc_DATA[7];
		end
	end


	// This data is latched when address is in the range FE34..FE37
	always @(negedge Phi2) begin
		if (!bbc_nRST || RecMode) begin
			PrvS8 = 1'b0;
			PrvS4 = 1'b0;
			PrvS1 = 1'b0;
			ShEn  = 1'b0;
		end
		else if (!RnW && aFE34_7) begin
			PrvS8 = bbc_DATA[4];
			PrvS4 = bbc_DATA[5];
			PrvS1 = bbc_DATA[6];
			ShEn  = bbc_DATA[7];
		end
	end


	//	Recovery Mode
	//	-------------
	//	This code is used to monitor the Break key via bbc_nRST.
	//	To switch into Recovery Mode:
	//	- If the Break key is held for >0.8 seconds, then onboard ROMs 7..15 & RAM 0..15 are read protected.
	//	- At the same time, beeb Motherboard ROMs 0..3 are enabled, overriding RAM select function
	//	- When the Break key is then released, then after a further 0.6 seconds the onboard onboard ROMs 7..15 & RAM 0..15 are read enabled again.
	//	- RAM select function remains overridden until switched out of Recovery Mode
	//	To switch out of Recovery Mode:
	//	- Press Break key for <0.8 seconds
	//  It is recommended that the following ROMS are plugged into the beeb motherboard to allow the Recovery mode to function effectively.
	//	In normal operation, these ROMs would not be visible. Instead, the equivalent RAM banks would be mapped into these slots:
	//	- Language ROM (eg BASIC)
	//	- Filesystem ROM (eg DNFS)
	//	- SWRAM utility ROM (eg Advanced ROM Manager)
	
	//	2MHz clock, so 18 bits required to count 0.1 sec (200,000 pulses)
	reg	[17:0] slow_clk = 0;
	reg	[2:0] countseca = 0;
	reg	[2:0] countsecb = 0;

	always @ (negedge Phi2) begin
		if (slow_clk == 18'd200000) slow_clk <= 18'b0;
		else slow_clk <= slow_clk + 1'b1;
	end

	assign	msec_tick = (slow_clk == 18'd200000);

	// Long reset will occur 0.8 seconds after Break is pressed. Long reset will remain active as long as Break continues to be pressed
	// Long reset will clear immediately after Break is released.
	// positive pulse will last for one sec_tick cycle (0.1 sec), so reduce countsec value by 0.1 second to get required period.
	always @ (negedge Phi2) begin
		if (!bbc_nRST && msec_tick) begin
			if (countseca == 3'd7) countseca <= 3'b0;
			else  countseca <= countseca + 1'b1;
		end
		else if (bbc_nRST) begin
			countseca <= 3'b0;
		end
	end

	assign	long_RSTa = (countseca == 3'd7);
	
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
		end
		else if (long_RST) begin
			countsecb <= 3'b0;
		end
	end
	
	assign	long_CLRa = (countsecb == 3'd5);
	
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
	//		mapping of RAM Banks 0..15 into GenBanks 0..15 by setting EF[0]=0 & EF[1]=0.
	//		mapping of RAM Banks 0..3 into GenBanks 4..7 by setting EF[0]=1 & EF[1]=0.
	// 		mapping of Private & Shadow RAM Banks 16 & 17 into GenBanks 12 & 13 by setting EF[0]=1 & EF[1]=0.
	//		mapping of unused RAM Banks 18 & 19 into GenBanks 14 & 15 by setting EF[0]=1 & EF[1]=0.
	//		mapping of PALPROM hidden banks 20..31 into GenBanks 4..15 by setting EF[1]=1.

	always @(negedge Phi2) begin
		if (!bbc_nRST) EF = 2'b00;
		else if (!RnW && aFE39) EF = bbc_DATA;
	end


	//  Software based write protect function
	//  -------------------------------------
	//  Each time the IBOS *SRWE and *SRWP commands are called, the updated values
	//  are written to the bank of WP registers in the CPLD, and to two 8 bit
	//  registers in Private RAM.
	//  On power up or BREAK, the CPLD will read the Write Protect status (in 32k
	//  chunks) from jumper bank RamWriteProt and fan these out to bank of 16k
	//  registers, WP. IBOS will read these registers on BREAK and store to two
	//  default registers in the RTC for use during an IBOS Reset. Afer reading
	//  the WP registers, IBOS will then write to the WP registers with the settings
	//  that are currently saved in Private RAM, restoring the previously set values.
	//  The CPLD Write Protect status is adjusted by IBOS as follows:
	//  	RAM Banks 0..7 are write enabled / protected by writing to address &FE3A
	//  	RAM Banks 8..F are write enabled / protected by writing to address &FE3B
	//  Logic state 0 = write protected. Logic state 1 = write enabled
	//
	always @(negedge Phi2) begin
		if (!bbc_nRST) begin
			WP[15] = !RamWriteProt[7];
			WP[14] = !RamWriteProt[7];
			WP[13] = !RamWriteProt[6];
			WP[12] = !RamWriteProt[6];
			WP[11] = !RamWriteProt[5];
			WP[10] = !RamWriteProt[5];
			WP[9]  = !RamWriteProt[4];
			WP[8]  = !RamWriteProt[4];
			WP[7]  = !RamWriteProt[3];
			WP[6]  = !RamWriteProt[3];
			WP[5]  = !RamWriteProt[2];
			WP[4]  = !RamWriteProt[2];
			WP[3]  = !RamWriteProt[1];
			WP[2]  = !RamWriteProt[1];
			WP[1]  = !RamWriteProt[0];
			WP[0]  = !RamWriteProt[0];
		end
		else if (!RnW && aFE3A) WP[7:0]  = bbc_DATA;
		else if (!RnW && aFE3B) WP[15:8] = bbc_DATA;
	end
	

	assign	bbc_DATA[7]   = (Phi2 && aFE38 && RnW) ? 1'b0 : 1'bz;
	assign	bbc_DATA[6:5] = (Phi2 && aFE38 && RnW) ? ~EF[1:0] : 2'bzz;
	assign	bbc_DATA[4]   = (Phi2 && aFE38 && RnW) ? RecMode : 1'bz;
	assign	bbc_DATA[3:0] = (Phi2 && aFE38 && RnW) ? ~BeebRomSel[3:0] : 4'bzzzz;
	assign	bbc_DATA      = (Phi2 && aFE39 && RnW) ? ~IntegraRomSel[15:8] : 8'hzz;
	assign	bbc_DATA      = (Phi2 && aFE3A && RnW) ? WP[7:0]  : 8'hzz;
	assign	bbc_DATA      = (Phi2 && aFE3B && RnW) ? WP[15:8] : 8'hzz;
	assign	bbc_DATA      = (Phi2 && aFE3F && RnW) ? ~RamPALSel[7:0] : 8'hzz;


	// 32k Computer Concepts PALPROMs (CC32K: Inter-Word, Master ROM, AMX Design2)
	// Use jumpers RamPALSel[1:0] for PALPROM A and jumpers RamPALSel[3:2] for PALPROM B.
	// x0: CC32K. x1: Switching disabled.
	// Logic '0' when jumper installed. Logic '1' when jumper removed.
	// PALPROM A uses RAM banks 8 & 20
	// PALPROM B Uses RAM banks 9 & 21
	
	always @(negedge Phi2) begin
		if (!nRDS && GenBankSel[8]) begin
	//	if (RnW && GenBankSel[8]) begin
			if (RamPALSel[0])				pp2aBank = 2'b01;	//Disable PALPROM switching
			else if (acc2Bk0 || !bbc_nRST)	pp2aBank = 2'b01;	//hBFE0..hBFFF (CC32K)
			else if (acc2Bk1)				pp2aBank = 2'b10;	//hBFC0..hBFDF (CC32K)
		end
	end

	always @(negedge Phi2) begin
		if (!nRDS && GenBankSel[9]) begin
	//	if (RnW && GenBankSel[9]) begin
			if (RamPALSel[2])				pp2bBank = 2'b01;	//Disable PALPROM switching
			else if (acc2Bk0 || !bbc_nRST)	pp2bBank = 2'b01;	//hBFE0..hBFFF (CC32K)
			else if (acc2Bk1)				pp2bBank = 2'b10;	//hBFC0..hBFDF (CC32K)
		end
	end


	// Combined code for 64k Computer Concepts PALPROM (CC64K) & 32k Watford Electronic PALPROM (WEQST & WETED) 
	// 64k Computer Concepts PALPROM (CC64K: Inter-Base, Publisher, Wordwise Plus II)
	// Note: WW+II is a 32k PALPROM designed to work with CC64K PALPROM switching logic.
	//		 It is therefore necessary to duplicate WW+II ROM into upper 32k bank to create a 64k ROM.
	//
	// 32k Watford Electronic PALPROM (WEQST: QuestPaint, ConQuest, PCB Designer & WETED: TED)
	// Note: The lower 8k of WE PALPROMs is never swtiched. Only the upper 8k is switched
	// 		 Since we have no control over A13, we use 4 x 16k banks with the 32K PALPROM mapped as follows:
	//
	// RAM Bank | Address Range | PALPROM Address | QP/CQ/PCB Switch | TED Switch
	// ---------+---------------+-----------------+------------------+--------------
	// 10       | h8000 - hAFFF | h0000 - h1FFF   |                  |              
	// 10       | hB000 - hCFFF | h0000 - h1FFF   | h9340..h935F     | h9F80..h9F9F 
	// 22       | h8000 - hAFFF | h0000 - h1FFF   |                  |              
	// 22       | hB000 - hCFFF | h2000 - h3FFF   | h91E0..h91FF     | h9FA0..h9FBF 
	// 23       | h8000 - hAFFF | h0000 - h1FFF   |                  |              
	// 23       | hB000 - hCFFF | h4000 - h5FFF   | h8820..h883F     | h9FC0..h9FDF 
	// 24       | h8000 - hAFFF | h0000 - h1FFF   |                  |              
	// 24       | hB000 - hCFFF | h6000 - h7FFF   | h92C0..h92DF     | h9FE0..h9FFF 
	//
	// Use jumpers RamPALSel[5:4] to select PALPROM Type.
	// 00: CC64K, 01: WETED, 10: WEQST, 11: Disabled
	// Logic '0' when jumper installed. Logic '1' when jumper removed.
	// Uses RAM banks 10 & 22..24

	always @(negedge Phi2) begin
		if (!nRDS && GenBankSel[10]) begin
		//if (RnW && GenBankSel[10]) begin
			if ((!bbc_nRST)
			     ||  (RamPALSel[5] &&  RamPALSel[4])																	//Disable PALPROM switching
			     ||  (RamPALSel[5] && !RamPALSel[4] && (bbc_ADDRESS[15:5] == 11'b1001_0011_010))						//h9340..h935F (WEQST)
				 || (!RamPALSel[5] &&  RamPALSel[4] && (bbc_ADDRESS[15:5] == 11'b1001_1111_100))						//h9F80..h9F9F (WETED)
				 || (!RamPALSel[5] && !RamPALSel[4] && (bbc_ADDRESS[15:5] == 11'b1011_1111_100)))	pp4Bank = 4'b0001;	//hBF80..hBF9F (CC64K)
			else if ((RamPALSel[5] && !RamPALSel[4] && (bbc_ADDRESS[15:5] == 11'b1001_0001_111))						//h91E0..h91FF (WEQST)
				 || (!RamPALSel[5] &&  RamPALSel[4] && (bbc_ADDRESS[15:5] == 11'b1001_1111_101))						//h9FA0..h9FBF (WETED)
				 || (!RamPALSel[5] && !RamPALSel[4] && (bbc_ADDRESS[15:5] == 11'b1011_1111_101)))	pp4Bank = 4'b0010;	//hBFA0..hBFBF (CC64K)
			else if ((RamPALSel[5] && !RamPALSel[4] && (bbc_ADDRESS[15:5] == 11'b1000_1000_001))						//h8820..h883F (WEQST)
				 || (!RamPALSel[5] &&  RamPALSel[4] && (bbc_ADDRESS[15:5] == 11'b1001_1111_110))						//h9FC0..h9FDF (WETED)
				 || (!RamPALSel[5] && !RamPALSel[4] && (bbc_ADDRESS[15:5] == 11'b1011_1111_110)))	pp4Bank = 4'b0100;	//hBFC0..hBFDF (CC64K)
			else if ((RamPALSel[5] && !RamPALSel[4] && (bbc_ADDRESS[15:5] == 11'b1001_0010_110))						//h92C0..h92DF (WEQST)
				 || (!RamPALSel[5] &&  RamPALSel[4] && (bbc_ADDRESS[15:5] == 11'b1001_1111_111))						//h9FE0..h9FFF (WETED)
				 || (!RamPALSel[5] && !RamPALSel[4] && (bbc_ADDRESS[15:5] == 11'b1011_1111_111)))	pp4Bank = 4'b1000;	//hBFE0..hBFFF (CC64K)
		end
	end
	
	// Combined code for 128k Computer Concepts PALPROM (CC128K) & 64k Watford Electronics PALPROM (WEWAP)
	// 128k Computer Concepts PALPROM (CC128K: SpellMaster, MegaROM)
	// 64k Watford Electronics PALPROM (WEWAP: Wapping)
	// Note: The lower 8k of WE PALPROMs is never swtiched. Only the upper 8k is switched
	// 		 Since we have no control over A13, we use 8 x 16k banks with the 64K PALPROM mapped as follows:
	//
	// RAM Bank | Address Range | PALPROM Address | Wapping Switch
	// ---------+---------------+-----------------+----------------
	// 11       | h8000 - hAFFF | h0000 - h1FFF   |              
	// 11       | hB000 - hCFFF | h0000 - h1FFF   | h9F00..h9F1F 
	// 25       | h8000 - hAFFF | h0000 - h1FFF   |              
	// 25       | hB000 - hCFFF | h2000 - h3FFF   | h9F20..h9F3F 
	// 26       | h8000 - hAFFF | h0000 - h1FFF   |              
	// 26       | hB000 - hCFFF | h4000 - h5FFF   | h9F40..h9F5F 
	// 27       | h8000 - hAFFF | h0000 - h1FFF   |              
	// 27       | hB000 - hCFFF | h6000 - h7FFF   | h9F60..h9F7F 
	// 28       | h8000 - hAFFF | h0000 - h1FFF   |              
	// 28       | hB000 - hCFFF | h8000 - h9FFF   | h9F80..h9F9F 
	// 29       | h8000 - hAFFF | h0000 - h1FFF   |              
	// 29       | hB000 - hCFFF | hA000 - hBFFF   | h9FA0..h9FBF 
	// 30       | h8000 - hAFFF | h0000 - h1FFF   |              
	// 30       | hB000 - hCFFF | hC000 - hDFFF   | h9FC0..h9FDF 
	// 31       | h8000 - hAFFF | h0000 - h1FFF   |              
	// 31       | hB000 - hCFFF | hE000 - hFFFF   | h9FE0..h9FFF 
	//
	// Use jumpers RamPALSel[7:6] to select PALPROM Type.
	// 00: CC128K, 10: WEWAP, x1: Disabled
	// Logic '0' when jumper installed. Logic '1' when jumper removed.
	// Uses RAM banks 11 & 25..31
	
	always @(negedge Phi2) begin
		if (!nRDS && GenBankSel[11]) begin
		//if (RnW && GenBankSel[11]) begin
			if  (RamPALSel[6] || !bbc_nRST)																pp8Bank = 8'b00000001;	//Disable PALPROM switching
			else if ((RamPALSel[7] && (bbc_ADDRESS[15:5] == 11'b1011_1111_111))													//hBFE0..hBFFF	(CC128K)
				 || (!RamPALSel[7] && (bbc_ADDRESS[15:5] == 11'b1001_1111_000)))					 	pp8Bank = 8'b00000001;	//h9F00..h9F1F	(WEWAP)
			else if ((RamPALSel[7] && (bbc_ADDRESS[15:5] == 11'b1011_1111_110) && (pp8Bank[0] == 1'b1))							//hBFC0..hBFDF	(CC128K)
				 || (!RamPALSel[7] && (bbc_ADDRESS[15:5] == 11'b1001_1111_001)))					 	pp8Bank = 8'b00000010;	//h9F20..h9F3F	(WEWAP)
			else if ((RamPALSel[7] && (bbc_ADDRESS[15:5] == 11'b1011_1111_101) && (pp8Bank[0] == 1'b1))							//hBFA0..hBFBF	(CC128K)
				 || (!RamPALSel[7] && (bbc_ADDRESS[15:5] == 11'b1001_1111_010)))					 	pp8Bank = 8'b00000100;	//h9F40..h9F5F	(WEWAP)
			else if ((RamPALSel[7] && (bbc_ADDRESS[15:5] == 11'b1011_1111_100) && (pp8Bank[0] == 1'b1))							//hBF80..hBF9F	(CC128K)
				 || (!RamPALSel[7] && (bbc_ADDRESS[15:5] == 11'b1001_1111_011)))					 	pp8Bank = 8'b00001000;	//h9F60..h9F7F	(WEWAP)
			else if ((RamPALSel[7] && (bbc_ADDRESS[15:5] == 11'b1011_1111_011) && (pp8Bank[0] == 1'b1))							//hBF60..hBF7F	(CC128K)
				 || (!RamPALSel[7] && (bbc_ADDRESS[15:5] == 11'b1001_1111_100)))					 	pp8Bank = 8'b00010000;	//h9F80..h9F9F	(WEWAP)
			else if ((RamPALSel[7] && (bbc_ADDRESS[15:5] == 11'b1011_1111_010) && (pp8Bank[0] == 1'b1))							//hBF40..hBF5F	(CC128K)
				 || (!RamPALSel[7] && (bbc_ADDRESS[15:5] == 11'b1001_1111_101)))					 	pp8Bank = 8'b00100000;	//h9FA0..h9FBF	(WEWAP)
			else if ((RamPALSel[7] && (bbc_ADDRESS[15:5] == 11'b1011_1111_001) && (pp8Bank[0] == 1'b1))							//hBF20..hBF3F	(CC128K)
				 || (!RamPALSel[7] && (bbc_ADDRESS[15:5] == 11'b1001_1111_110)))					 	pp8Bank = 8'b01000000;	//h9FC0..h9FDF	(WEWAP)
			else if ((RamPALSel[7] && (bbc_ADDRESS[15:5] == 11'b1011_1111_000) && (pp8Bank[0] == 1'b1))							//hBF00..hBF1F	(CC128K)
				 || (!RamPALSel[7] && (bbc_ADDRESS[15:5] == 11'b1001_1111_111)))					 	pp8Bank = 8'b10000000;	//h9FE0..h9FFF	(WEWAP)
		end
	end

endmodule

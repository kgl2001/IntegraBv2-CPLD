REM CC32K 32k PALPROM Loader
REM This will only work
REM with IntegraB V2 board.
REM The board must be in
REM Recovery Mode (long break)
REM before running this code.
REM (C) Ken Lowe 2024
REM Version 2.4 11/09/2024
DIM osblock% 16
DIM mcode% &200
DIM buffer% &1000
CLOSE#0
MODE7
VDU131:PRINT"     Integra-B V2 PALPROM Loader"
VDU131:PRINT"     ---------------------------"
VDU28,0,24,39,3
PRINT"Checking for 2nd processor ..";
A%=&EA:X%=0:Y%=&FF:IF((USR&FFF4)AND&FF00)<>0VDU7,129:PRINT"Error"''"Please disable 2nd processor and"'"re-run this program":PROCResetFlags:END
VDU130:PRINT"Ok"'"Checking for V2 Hardware ....";
IFNOT(FNvercheck)VDU7,129:PRINT"Error"''"Sorry. V2 Harware not detected.":PROCResetFlags:END
VDU130:PRINT"Ok"'"Checking for recovery mode ..";
IFNOT(FNrecmode)VDU7,129:PRINT"Error"''"Please press CTRL-BREAK for longer"'"than 2 seconds, and re-run this program":PROCResetFlags:END
VDU130:PRINT"Ok"'"Loading image to Bank .......";:VDU131:PRINT"8 OR 9?";

bank%=FNbankno
numbanks%=2
ppflags%=(2^(bank%-7))
ppflagsmask%=(2^(bank%-7)) EOR &FF
path$=""
file$="IWordROM"

rrflags%=?&FE39*&100+(?&FE38 OR &F0)
rrinflags%=2^(bank%-8)*&100
rroutflags%=0

gblue%=148:gred%=145:ggreen%=146:gwhite%=151
jopen%=98:jclosed%=106

VDU8,8,8,8,8,8,8,8,130:PRINT;bank%;"      "
PROCassembly
PROCSetSWTable
PRINT"Checking jumper settings ....";
tochg%=FNcheckrr
IF(tochg%)<>0 VDU7,129:PRINT;tochg%;"xError"'':PROCjumpers:PROCResetFlags:END
?&FE3F=&FF:REM Disable all bank switching in CPLD
cc%=LEN(file$)
IFpath$<>"" path$=path$+"."
fh%=OPENIN(path$+file$)
IF cc%>10 file$=LEFT$(file$,9)+".":cc%=10
VDU130:PRINT"Ok"'"Loading ";file$;" to block ";
FORn%=cc%TO10:PRINT".";:NEXT:PRINT"       ";
FORn%=0TOnumbanks%-1
b%=0
REPEAT
VDU8,8,8,8,8,8,8,131:PRINT;n%;"/";STR$~(&8000+b%*&1000);
s%=FNpartload(fh%,buffer%,(b%*&1000 + n%*&4000),&1000)
IFs%VDU8,8,8,8,8,8,8,7,129:PRINT"Failed"''"Error opening file":PROCResetFlags:END
?newrom=FNswram(n%):?&70=buffer%MOD256:?&71=buffer%DIV256:?&72=0:?&73=&80+b%*&10:CALLsrload
b%=b%+1
UNTIL(b%>3)
NEXT
CLOSE#?osblock%
VDU8,8,8,8,8,8,8,130:PRINT"Done  "'"Writing config to CMOS RAM ..";
?&FE3A=0
X%=&3F
A%=(USR(ReadRtcRam) AND ppflagsmask%) OR ppflags%: CALL WriteRtcRam
A%=bank%:CALLremoveBankAFromSRDATA
VDU130:PRINT"Done"'"Write Protecting bank ";bank%;" ....";:IFbank%<10PRINT".";
PROCResetFlags:PROCWPBank
VDU130:PRINT"Done"''"Press CTRL-BREAK to initialise"
END

DEFFNpartload(h%,l%,o%,c%)
A%=3:REM OSGBPB part load function
X%=osblock%MOD256
Y%=osblock%DIV256
?osblock%=h%:REM file handle
osblock%!1=l%:REM load addr
osblock%!5=c%:REM no of bytes to read
osblock%!9=o%:REM offset within file
q%=l%:REM preserve original load address
=((USR&FFD1 AND &FF000000) DIV &1000000) AND 1

DEFPROCassembly
flagsCopyLow%=&70
flagsCopyHigh%=&71
inflagsCopyLow%=&72
inflagsCopyHigh%=&73
outflagsCopyLow%=&74
outflagsCopyHigh%=&75
jpCount%=&76

FORpass%=0TO2STEP2
P%=mcode%
[OPT pass%
.srload
LDA&F4
STAoldrom
LDAnewrom
STA&F4
STA&FE30
LDX#&10
LDY#0
.loop1
LDA(&70),Y:STA(&72),Y
INY:BNEloop1
INC&71:INC&73
DEX:BNEloop1
LDAoldrom
STA&F4
STA&FE30
RTS

.jumpers
LDA #0:STA jpCount%
LDX #15
.jmploop
ASL flagsCopyLow%:ROL flagsCopyHigh%:BCS checkForBlueRed
LDA #gwhite%:LDY #jopen%
ASL outflagsCopyLow%:ROL outflagsCopyHigh%
ASL inflagsCopyLow%:ROL inflagsCopyHigh%:BCC storeNewJumper
LDA #ggreen%:LDY #jclosed%
INC jpCount%
.storeNewJumper
STA jpstore,X:TYA:STA jpstore+16,X
DEX
BPL jmploop
RTS
.checkForBlueRed
LDA #gblue%:LDY #jclosed%
ASL inflagsCopyLow%:ROL inflagsCopyHigh%
ASL outflagsCopyLow%:ROL outflagsCopyHigh%:BCC storeNewJumper
LDA #gred%:LDY #jopen%
INC jpCount%
JMP storeNewJumper
.jpstore
EQUS"0123456789ABCDEF"
EQUS"0123456789ABCDEF"
.newrom EQUB0
.oldrom EQUB0

.ReadRtcRam
PHP
JSR SeiSelectRtcAddressX
LDA &FE3C
PLP
RTS

.WriteRtcRam
PHP
JSR SeiSelectRtcAddressX
STA &FE3C
PLP
RTS

.SeiSelectRtcAddressX
SEI
JSR Nop2
STX &FE38
NOP
.Nop2
NOP:NOP
RTS

.removeBankAFromSRDATA
JSR EnablePrivateRam8300X
LDX #3
.FindLoop
CMP &830C,X:BEQ Found
DEX:BPL FindLoop
JSR DisablePrivateRam8300X
RTS

.Found
LDA #&FF:STA &830C,X
.Shuffle
LDX #0:LDY #0
.ShuffleLoop
LDA &830C,X:BMI Unassigned
STA &830C,Y:INY
.Unassigned
INX:CPX #&04:BNE ShuffleLoop
TYA:TAX
JMP PadLoopStart
			
.PadLoop
LDA #&FF:STA &830C,Y
INY
.PadLoopStart
CPY #4:BNE PadLoop
JSR DisablePrivateRam8300X
RTS

.ReadPrivateRam8300X
JSR EnablePrivateRam8300X
LDA &8300,X
JMP DisablePrivateRam8300X

.WritePrivateRam8300X
JSR EnablePrivateRam8300X
STA &8300,X
JMP DisablePrivateRam8300X

.EnablePrivateRam8300X
PHP:SEI
PHA
LDA #01:STA &FE39
LDA #&10:STA &FE3B
LDA &F4:STA oldrom
LDA #12:STA &F4:STA &FE30
PLA
PLP
PHA:PLA
RTS

.DisablePrivateRam8300X
PHP:SEI
PHA
LDA oldrom:STA &F4:STA &FE30
LDA #0:STA &FE39
STA &FE3B
PLA
PLP
PHA:PLA
RTS
]
NEXT
ENDPROC

DEFPROCSetSWTable
REM bank, &FE39, &FE3A, &FE3B
REM &FE39: SWRAM 0=Normal 2=Hidden
REM &FE3A: W/P 0..7  0=W/P 1=W/E
REM &FE3B: W/P 8..15 0=W/P 1=W/E
DIMswrammap%(numbanks%-1, 3)
FORn%=0TOnumbanks%-1
FORo%=0TO3
READ swrammap%(n%,o%)
NEXT:NEXT
DATA bank%,0,0,bank%-7
DATA bank%-4,2,2^(bank%-4),0
ENDPROC

DEFFNswram (block%)
?&FE39=swrammap%(block%,1)
?&FE3A=swrammap%(block%,2)
?&FE3B=swrammap%(block%,3)
=swrammap%(block%,0)

DEFFNvercheck
?&FE39=0:ver%=(?&FE38 AND &E0)=&60
IFver% ?&FE39=3:ver%=(?&FE38 AND &E0)=&00
=ver%

DEFFNrecmode
=(?&FE38 AND &10)=&10

DEFFNbankno
Y%=TRUE
REPEAT
A$=INKEY$(200)
IFA$="8" Y%=8
IFA$="9" Y%=9
UNTILY%<>TRUE
=Y%

DEFFNreadwpflags
shortWP%=0
?&FE38=&3E:loWP%=?&FE3C:?&FE38=&3F:hiWP%=?&FE3C
longWP%=hiWP%*&100+loWP%
FORn%=0TO7
IF(longWP% AND 2^(n%*2))=2^(n%*2) shortWP%=(shortWP% OR 2^n%)
NEXT
=?&FE3F*&100+shortWP%

DEFFNreadrrflags
=?&FE39*&100+(?&FE38 OR &F0)

DEFFNcheckwp
?flagsCopyLow%=wpflags%MOD256:?flagsCopyHigh%=wpflags%DIV256
?inflagsCopyLow%=wpinflags%MOD256:?inflagsCopyHigh%=wpinflags%DIV256
?outflagsCopyLow%=wpoutflags%MOD256:?outflagsCopyHigh%=wpoutflags%DIV256
CALLjumpers
=?jpCount%

DEFFNcheckrr
?flagsCopyLow%=rrflags%MOD256:?flagsCopyHigh%=rrflags%DIV256
?inflagsCopyLow%=rrinflags%MOD256:?inflagsCopyHigh%=rrinflags%DIV256
?outflagsCopyLow%=rroutflags%MOD256:?outflagsCopyHigh%=rroutflags%DIV256
CALLjumpers
=?jpCount%

DEFPROCjumpers
tmp%=FNcheckrr
PRINT'"      RAM/PALPROM ";:VDU151,106,135:PRINT" Default W/E"
PRINT'"   J2          RAM / ROM Jumper Bank"
PRINT" ";
VDU151,104,44,44,44,44,44,44,44,44,44,44,44,44,44,44,44,44,44,108,32,32,32,32,32,104,44,44,44,44,44,44,44,44,44,108,135
PRINT'" ";
VDU151,106
FORn%=15TO8STEP-1
PRINT;CHR$(?(jpstore+n%));CHR$(?(jpstore+16+n%));
NEXT
VDU151,106,135,32,32,32,151,106
FORn%=3TO0STEP-1
PRINT;CHR$(?(jpstore+n%));CHR$(?(jpstore+16+n%));
NEXT
VDU151,106,135
PRINT'" ";
VDU151,42,44,44,44,44,44,44,44,44,44,44,44,44,44,44,44,44,44,46,32,32,32,32,32,42,44,44,44,44,44,44,44,44,44,46

PRINT''"Jumpers to Change:"
VDU146,106,135:PRINT"Install Jumper   ";:VDU145,98,135:PRINT"Remove Jumper"
PRINT"Jumpers to Leave:"
VDU148,106,135:PRINT"Jumper Installed ";:VDU151,98,135:PRINT"Jumper Removed"

ENDPROC

DEFPROCResetFlags
?&FE39=0:?&FE3A=0:?&FE3B=0
ENDPROC

DEFPROCWPBank
X%=&B9
A%=(USR(ReadPrivateRam8300X)AND(2^(bank%MOD8)EOR255))
CALL WritePrivateRam8300X
ENDPROC

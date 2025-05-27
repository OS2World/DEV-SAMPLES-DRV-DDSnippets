		.486p

NOHARDWARE	=	0
ERRORTRACE	=	0

ID_MEDAV	=	0FFFEh
ID_RuskPCI	=	4

RESETTIME	=	1 ; 1ms
RESETTIME_NS	=	RESETTIME * 1000000

HOLESIZE	=	1 SHL 25	  ; 32MiB
HOLEMASK	=	HOLESIZE - 1 - 3  ; mask bits 2..24

MAXNUMBUFFERS	=	1000
MAXSIZEBUFFER	=	12*1024*1024	  ; 12MiB
MAXNUMJOBS	=	200000
MAXJOBSIZE	=	4*1024*1024	  ; 4MiB

TICKCOUNT	=	10

		%NOINCL
		INCLUDE DevHlp.inc

		IDEAL
		SMART
		LOCALS

		INCLUDE "Dev.inc"

EXTRN		DOSPUTMESSAGE:FAR
EXTRN		DOSDEVIOCTL:FAR
EXTRN		DOSOPEN:FAR
EXTRN		DOSCLOSE:FAR
EXTRN		DOS32FLATDS:ABS
EXTRN		DOSIODELAYCNT:ABS

SEGMENT 	RData	 DWORD PUBLIC USE16 'DATA'
ENDS		RData

SEGMENT 	RCode	 DWORD PUBLIC USE16 'CODE'
ENDS		RCode

SEGMENT 	RData
DeviceHeader	DevHdr	<-1, -1, \
			DEV_CHR + DEV_SHR + DEV_OPN + DEV_LEVEL3, \
			OFFSET Strategy, 0,			  \
			'RSKPCI$ ', 0, 0, 0                       \
			DEV_IOCTL2 + DEV_16MB + DEV_INITCOMPLT >
DevHlp		=	DeviceHeader.res

FuncTable	DW	Init
		DW	NotSupported	; N/A
		DW	NotSupported	; N/A
		DW	NotSupported	; N/A
		DW	Read
		DW	NotSupported	; Nondest Read, no Wait
		DW	NotSupported	; Input Status
		DW	NotSupported	; Flush Input
		DW	Write
		DW	NotSupported	; Write / Verify
		DW	NotSupported	; Output Status
		DW	NotSupported	; Flush Output
		DW	NotSupported	; N/A
		DW	Open
		DW	Close
		DW	NotSupported	; N/A
		DW	IOCtl
		DW	NotSupported	; N/A
		DW	NotSupported	; N/A
		DW	NotSupported	; N/A
		DW	NotSupported	; Deinstall
		DW	NotSupported	; N/A
		DW	NotSupported	; N/A
		DW	NotSupported	; N/A
		DW	NotSupported	; N/A
		DW	NotSupported	; N/A
		DW	NotSupported	; N/A
		DW	NotSupported	; N/A
		DW	Shutdown
		DW	NotSupported	; N/A
		DW	NotSupported	; N/A
		DW	InitComplete
FuncTableLen	=	($ - FuncTable) / (Size FuncTable)

Hole		DD	?
FlatSel 	DW	DOS32FLATDS
HoleMask	DD	HOLEMASK

HolePtr 	EQU	FWORD Hole

BlockIdError	DD	?
BlockIdBuffer	DD	?
BIDError	DW	OFFSET BlockIdError, RData
BIDBuffer	DW	OFFSET BlockIdBuffer, RData

DMAStarted	DD	0
DMAStopped	DD	0
DMAIntNoBuffer	DD	0
RdyIntNoBuffer	DD	0
RdyIntWDMA	DD	0
UnhandledInt	DD	0

STRUC		DMADesc 	; all addresses are physical addresses!
  MemAddr	DD	?
  IOAddr	DD	?
  numBytes	DD	?
  nextDesc	DD	?	; | 9h or Bh (at end of chain)
ENDS		DMADesc

DescFlags	=	1001b	; read, descriptor on PCI bus
DescFlagsEnd	=	0010b	; end of chain
DescFlagsR	=	1000b	; read;

DMADescPhys	DD	?
DMADescriptors	DD	?
DMADescSize	DD	?

STRUC		LList
  Head		DW	?
  Tail		DW	?
ENDS		LList

FreeList	LList	<0, OFFSET FreeList.Head>
FullList	LList	<0, OFFSET FullList.Head>
DoneList	LList	<0, OFFSET DoneList.Head>

	IF ERRORTRACE
		ALIGN	4
		DB	'Reg:'
RegEAX		DD	0
RegEBX		DD	0
RegECX		DD	0
RegEDX		DD	0
RegESI		DD	0
RegEDI		DD	0
		DB	'Err:'
LastError	DD	0
	ENDIF

STRUC		DMABuf
  next		DW	?
  BufPhys	DD	?
  BufLin	DD	?
  BufProcess	DD	?
  DescLin	DD	?
  DescPhys	DD	?
ENDS		DMABuf

CurrentDMABuf	DW	?
numDMABuffers	DW	?
DMABufSize	DD	?
DMABlockSize	DD	?
ADCBankSwitch	DB	?
		Align	2
DMABuffers	DMABuf	MAXNUMBUFFERS DUP (<0>)

Hello		DB	"RuskPCI Driver"
RevStr		DB	"$Revision:   1.5  $"
Revision	=	RevStr + 12
		INCLUDE "RSKBuild.inc"
CRLF		DB	0Dh, 0Ah

EEData:
CardType	DW	?
CardRevision	DW	?
SerialNumber	DD	?
ConfigLen	DB	?
		DW	(30 - ($ - EEData) / 2) DUP (?)

STRUC		PCIDataR
  Result	DB	?
ENDS		PCIDataR

STRUC		PCIInfo
  Common	PCIDataR <>
  Config	DB	?
  MajorVersion	DB	?
  MinorVersion	DB	?
  LastBus	DB	?
ENDS		PCIInfo

PCI_InfoPkt	PCIInfo <>

STRUC		PageInfo
  Addr		DD	?
  Len		DD	?
ENDS		PageInfo

Function	DB	?
Bus		DB	?
DevFunction	DB	?
ConfigReg	DB	?
ConfigRegSize	DB	?
ConfigData	DD	?
MemBase 	DD	?
IOBase		DW	?
IRQ		DW	?
Flags		DW	?
IntReg		DW	?

NUMPAGES	=	400	; for MAXNUMJOBS sized job list

Pages		PageInfo NUMPAGES+1 DUP (?)
hLock		DB	12 DUP (?)
pPages		DD	?
phLock		DD	?

DMAenabled	DB	0

KillBit 	=	0
KillFlag	=	(1 SHL KillBit)
AbortBitE	=	1
AbortFlagE	=	(1 SHL AbortBitE)
AbortBitB	=	2
AbortFlagB	=	(1 SHL AbortBitB)

ResDataEnd:

RMName		DB	'RESMGR$ '
RMIDC		IDC	<>

RMCALLBASE	   =	 0
RMRESERVED	   =	(RMCALLBASE+0)
RMRESERVED2	   =	(RMCALLBASE+1)
RMCREATEDRIVER	   =	(RMCALLBASE+2)
RMDESTROYDRIVER    =	(RMCALLBASE+3)
RMCREATEADAPTER    =	(RMCALLBASE+4)
RMDESTROYADAPTER   =	(RMCALLBASE+5)
RMCREATEDEVICE	   =	(RMCALLBASE+6)
RMDESTROYDEVICE    =	(RMCALLBASE+7)
RMALLOCRESOURCE    =	(RMCALLBASE+8)
RMDEALLOCRESOURCE  =	(RMCALLBASE+9)
RMCLAIMRESOURCES   =	(RMCALLBASE+10)
RMRELEASERESOURCES =	(RMCALLBASE+11)
RMCREATELDEV	   =	(RMCALLBASE+12)
RMDESTROYLDEV	   =	(RMCALLBASE+13)
RMCREATESYSNAME    =	(RMCALLBASE+14)
RMDESTROYSYSNAME   =	(RMCALLBASE+15)
RMADDTOHDEVICE	   =	(RMCALLBASE+16)
RMKEYTOHANDLELIST  =	(RMCALLBASE+17)
RMHANDLETOTYPE	   =	(RMCALLBASE+18)
RMHANDLETOPARENT   =	(RMCALLBASE+19)
RMUPDATEADJUNCT    =	(RMCALLBASE+20)
RMADJTOHANDLELIST  =	(RMCALLBASE+21)
RMHDEVTOHLDEV	   =	(RMCALLBASE+22)
RMRESTOHANDLELIST  =	(RMCALLBASE+23)
RMACTIVATEADAPTER  =	(RMCALLBASE+24)
RMDEACTIVATEADAPTER=	(RMCALLBASE+25)
RMCREATELINKDEVICE =	(RMCALLBASE+26)
RMMODIFYRESOURCES  =	(RMCALLBASE+27)
RMGETNODEINFO	   =	(RMCALLBASE+28)
RMPARSESCSIINQUIRY =	(RMCALLBASE+29)
;add new RMAPIs here and update RMLASTCALL
RMLASTCALL	   =	(RMCALLBASE+30)

DRF_STATIC	EQU	0000h
DRT_OS2 	EQU	3
DRS_CHAR	EQU	1

DriverDesc	DB	"RUSK PCI bridge driver",0
DriverVendor	DB	"Medav GmbH",0

DriverStruc:
DName		DW	0, 0
Description	DW	OFFSET DriverDesc, SEG DriverDesc
DVendor 	DW	OFFSET DriverVendor, SEG DriverVendor
MajorVer	DB	1
MinorVer	DB	1
Year		DW	2001
Month		DB	8
Day		DB	1
DrfFlags	DW	DRF_STATIC
DType		DW	DRT_OS2
DSubType	DW	DRS_CHAR
CallBack	DD	0

AS_NO16MB_ADDRESS_LIMIT=0
AS_BASE_BRIDGE	=	06h
AS_SUB_OTHER	=	80h
AS_INTF_GENERIC =	01h
AS_HOSTBUS_PCI	=	4
AS_BUSWIDTH_32BIT  =	30h
ADJ_ADAPTER_NUMBER =	2
ADJ_DEVICE_NUMBER  =	3

AdapterName	DB	"RuskPCI",0

AdapterStruc:
AName		DW	OFFSET AdapterName, SEG AdapterName
AFlags		DW	AS_NO16MB_ADDRESS_LIMIT
AType		DW	AS_BASE_BRIDGE
ASubType	DW	AS_SUB_OTHER
AInterface	DW	AS_INTF_GENERIC
AHostBus	DW	AS_HOSTBUS_PCI
AHostBusWidth	DW	AS_BUSWIDTH_32BIT
AAdjunctList	DW	OFFSET AAdj0Next, SEG AAdj0Next
Ares		DD	0
AAdj0Next	DD	0
AAdj0Len	DW	10
AAdj0Type	DW	ADJ_ADAPTER_NUMBER
AAdj0Base	DW	0

DS_FIXED_LOGICALNAME =	2
DS_TYPE_IO	     =	15	; IO type device

DeviceName	DB	"RSKPCI$ -  Rusk bridge device",0

DeviceStruc:
DevName 	DW	OFFSET DeviceName, SEG DeviceName
DevFlags	DW	DS_FIXED_LOGICALNAME
DevType 	DW	DS_TYPE_IO
DevAdjunctList	DW	OFFSET DAdj0Next, SEG DAdj0Next
DAdj0Next	DD	0
DAdj0Len	DW	10
DAdj0Type	DW	ADJ_DEVICE_NUMBER
DAdj0Base	DW	0

RS_TYPE_IO	=	1
RS_TYPE_IRQ	=	2
RS_TYPE_MEM	=	3

STRUC		RMIORes
  Type		DD	?
  BaseIOPort	DW	?
  NumIOPorts	DW	?
  IOFlags	DW	?
  IOAddrLine	DW	?
  res_		DD	?
ENDS		RMIORes
RS_IO_EXCLUSIVE =	1
RS_IO_MULTIPLEXED =	2

STRUC		RMIrqRes
  Type		DD	?
  IRQLevel	DW	?
  PCIIrqPin	DW	?
  IRQFlags	DW	?
  res		DW	?
  IntHandler	DD	?
  res_		DD	?
ENDS		RMIrqRes
RS_PCI_INT_A	=	1
RS_IRQ_SHARED	=	4

STRUC		RMMemRes
  Type		DD	?
  MemBase	DD	?
  MemSize	DD	?
  MemFlags	DW	?
  res		DW	?
  res_		DD	?
ENDS		RMMemRes
RS_MEM_EXCLUSIVE =	1

IOResource	RMIORes  <RS_TYPE_IO , 0, 100h, RS_IO_MULTIPLEXED, 16>
IrqResource	RMIrqRes <RS_TYPE_IRQ, 0, RS_PCI_INT_A, RS_IRQ_SHARED, 0, 0>
MemResource	RMMemRes <RS_TYPE_MEM, 0, HOLESIZE, RS_MEM_EXCLUSIVE, 0>
RMhDriver	DD	0
RMhAdapter	DD	0
RMhDevice	DD	0
Resources	DD	3
hResourceIO	DD	0
hResourceIrq	DD	0
hResourceMem	DD	0

OEMHLP_Name	DB	"OEMHLP$ ",0    ; OEMHLP$ name
OEMHLP_Handle	DW	0		; handle for file access
Action		DW	0		; DOSOPEN parameter

FA_SYSTEM	EQU	4		; system file attribute
OEMHLP_CAT	EQU	80h		; DOSDEVIOCTL category
OEMHLP_PCI	EQU	0Bh		; PCI Bios functions
OPN_EXIST	EQU	0001h		; open an existing file/create a file
OPN_RDWRACC	EQU	0042h		; read/write access
PCI_FUNC_QUERY	EQU	0		; query PCI Bios Info
PCI_FUNC_FINDD	EQU	1		; find PCI device
PCI_FUNC_READ	EQU	3		; read PCI config register
PCI_FUNC_WRITE	EQU	4		; write PCI config register

STRUC		PCIParm
  Function	DB	?
ENDS		PCIParm

PCI_ParamPkt	PCIParm <PCI_FUNC_QUERY>

STRUC		PCIParmFindD
  Common	PCIParm <>
  DeviceID	DW	?
  VendorID	DW	?
  Index 	DB	?
ENDS		PCIParmFindD

PCI_PPktFind	PCIParmFindD <PCI_FUNC_FINDD, ID_RuskPCI, ID_MEDAV, 0>

Quiet		DB	0
Vendor		DB	0

ENDS		RData

SEGMENT 	RCode
		ASSUME	CS:RCode, DS:RData

; Hardwareparameter des PLX9080

LocalArbiter	=	08h
PCIrev21	=	24
IntControlReg	=	68h
PCIIntEnable	=	  100h
PCILocalIntEn	=	  800h
PCILocalInt	=	 8000h
DMA0IntEnable	=	40000h
DMA0Int 	=      200000h

ControlReg	=	6Ch
ResetBit	=	30

DMA0Mode	=	80h
DMA0DescPtr	=	90h
DMA0CmdStatus	=	0A8h
DMAenable	=	00001b
DMAstart	=	00010b
DMAabort	=	00100b
DMAclrint	=	01000b
DMAdone 	=	10000b

; RUSK Adressen

MCCONTROL	=	0000800h
MCTNextSet	=	00000100b
MCTErrorInt	=	00100000b
MCTDataReady	=	01000000b

IRQStatusReg	=	0400000h
IRQMaskReg	=	0400004h
IRQDataReady	=	00001b
IRQErrorInt	=	01000b
IRQTest 	=	10000b

NavData 	=	00001000h
NavDataSize	=	48 * 4

MCCTRLREG	=	0300000h
SWReset 	=	10000000b
LCAInit 	=	   10000b
LCADone 	=	   01000b
LCAProg 	=	   00100b
LCACClk 	=	   00010b
LCADin		=	   00001b

ADCCSWITCHMEM	=	1180000h

; Parameter- und Datenpakete

STRUC		IOParmReg
  Reg		DD	?	; Register Address
ENDS		IOParmReg
IOParmSizeReg	=	SIZE IOParmReg

STRUC		IOParmBlock
  Reg		DD	?	; Register Address
  Addr		DD	?	; Ring3 User
  Len		DD	?	; <= 64KB !
ENDS		IOParmBlock
IOParmSizeBlock =	SIZE IOParmBlock

STRUC		IOParmLCA
  Addr		DD	?	; Ring3 User
  Len		DD	?	; <= 64KB !
ENDS		IOParmLCA
IOParmSizeLCA	=	SIZE IOParmLCA

STRUC		IODataReg
  Value 	DD	?	; Register Value
ENDS		IODataReg
IODataSizeReg	=	SIZE IODataReg

RECORD		JobFlags Direction:1, Skip:1
				; Direction: 0 : read, 1 : write
				; Skip: 0 : execute, 1 : skip

STRUC		DMAJob
  Reg		DD	?	; Register Address (start)
  Len		DB 3 DUP (?)	; Bytes !
  Flags 	JobFlags ?
ENDS		DMAJob

STRUC		IOCfgDMA
  NumBuffers	DW	?
  ADCBankSwitch DB	?
  filler	DB	?
  NumJobs	DD	?	; number of jobs following
  Jobs		DD	?	; pointer to jobs (R3 user)
;;  Jobs	  DMAJob  <?>
ENDS		IOCfgDMA
IOCfgDMASize	=	SIZE IOCfgDMA

STRUC		IOParmHBuf
  Addr		DD	?	; Ring3 User
  Mode		DB	?	; 0 : return old buffer
				; 1 : return old buffer, get next buffer
				; 2 : return old buffer, wait for next buffer
ENDS		IOParmHBuf
IOParmSizeHBuf	=	SIZE IOParmHBuf

STRUC		IOParmStartStop
  Mode		DB	?	; 0 : stop DMA, 1: start DMA
ENDS		IOParmStartStop
IOParmSizeStartStop =	SIZE IOParmStartStop

STRUC		IOErrorCtr
  DMAIntNoBuffer DD	?
  RdyIntNoBuffer DD	?
  RdyIntWDMA	 DD	?
  UnhandledInt	 DD	?
ENDS		IOErrorCtr
IOErrorCtrSize	=	SIZE IOErrorCtr

ReqPacket	=	(RqP ES:BX)
IOPacket	=	(RqPIOCtl ES:BX)
ParmReg 	=	(IOParmReg GS:SI)
ParmBlock	=	(IOParmBlock GS:SI)
ParmLCA 	=	(IOParmLCA GS:SI)
ParmDMA 	=	(IOCfgDMA GS:SI)
ParmHBuf	=	(IOParmHBuf GS:SI)
ParmStartStop	=	(IOParmStartStop GS:SI)
DataReg 	=	(IODataReg GS:SI)
ErrorCtr	=	(IOErrorCtr GS:SI)

; falls mal Register im Speicher getraced werden sollen...

	IF ERRORTRACE
PROC		DumpRegs NEAR
		MOV	[RegEAX], EAX
		MOV	[RegEBX], EBX
		MOV	[RegECX], ECX
		MOV	[RegEDX], EDX
		MOV	[RegESI], ESI
		MOV	[RegEDI], EDI
		RET
ENDP		DumpRegs
	ENDIF

PROC		Delay	NEAR
		PUSH	ECX
		MOV	ECX, DOSIODELAYCNT	; loops for 500ns
		IMUL	ECX, 200
@@Loop:
		DEC	ECX
		JNZ	@@Loop
		POP	ECX
		RET
ENDP		Delay

; Zurcksetzen einer RuskPCI-Karte
; L”st gleichzeitig eine gegebenenfalls gesetzte Softwaresperre

PROC		ResetCard NEAR
		PUSH	EAX CX DX

		MOV	DX, [IOBase]
		OR	DL, ControlReg + 3
		IN	AL, DX
		OR	AL, 1 SHL (ResetBit - 3 * 8)
		OUT	DX, AL

		PUSH	DI
		PUSH	BX
		PUSH	DX
		MOV	AX, DS
		MOV	BX, CS
		MOV	CX, RESETTIME
		MOV	DI, 0
		MOV	DX, DevHlp_ProcBlock
		CALL	[DevHlp]
		POP	DX
		POP	BX
		POP	DI

		AND	AL, NOT (1 SHL (ResetBit - 3 * 8))
		OUT	DX, AL

		MOV	DX, [IOBase]
		MOV	EAX, 0FE000000h ; LAS0RR
		OUT	DX, EAX
		ADD	DX, 4h - 0h
		MOV	EAX, 000000001h ; LAS0BA
		OUT	DX, EAX
		ADD	DX, 8h - 4h
		MOV	EAX, 001000000h ; MARBR
		OUT	DX, EAX
		ADD	DX, 10h - 8h
		MOV	EAX, 000000000h ; EROMRR
		OUT	DX, EAX
		ADD	DX, 18h - 10h
		MOV	EAX, 0410300C3h ; LBRDD0
		OUT	DX, EAX

		ADD	DX, 80h - 18h
;		 MOV	 EAX, 0000207C3h ; DMAMODE0
		MOV	EAX, 0000227C3h ; DMAMODE0
		OUT	DX, EAX

		POP	DX CX EAX
		RET
ENDP		ResetCard

; enable interrupts on PCI bridge

PROC		EnableInt
		PUSH	EDX ES

		LES	EDX, [HolePtr]
		MOV	[BYTE ES:EDX + MCCONTROL], MCTErrorInt OR MCTDataReady
		MOV	[BYTE ES:EDX + IRQMaskReg], 0

		MOV	DX, [IOBase]
		OR	DL, IntControlReg + 1
		MOV	AX, (PCIIntEnable OR PCILocalIntEn OR DMA0IntEnable) SHR 8
		OUT	DX, AX			; enable interrupts

		POP	ES EDX
		RET
ENDP		EnableInt

; disable interrupts on PCI bridge

PROC		DisableInt
		PUSH	EDX ES

		MOV	DX, [IOBase]
		OR	DL, IntControlReg + 1
		MOV	AX, 0			; disable global PCI IRQ & LIRQ
		OUT	DX, AX			; disable interrupts

		LES	EDX, [HolePtr]
		MOV	[BYTE ES:EDX + MCCONTROL], MCTErrorInt OR MCTDataReady
		MOV	[BYTE ES:EDX + IRQMaskReg], 0 ; reset Test IRQ, unmask IRQs

		POP	ES EDX
		RET
ENDP		DisableInt

; enable interrupts on attached hardware

PROC		EnableRuskInt
		PUSH	EDX ES

		LES	EDX, [HolePtr]
		MOV	[BYTE ES:EDX + MCCONTROL], MCTErrorInt OR MCTDataReady
		OR	[BYTE ES:EDX + IRQMaskReg], IRQDataReady OR IRQErrorInt

		POP	ES EDX
		RET
ENDP		EnableRuskInt

; disable interrupts on attached hardware

PROC		DisableRuskInt
		PUSH	EDX ES

		LES	EDX, [HolePtr]
		MOV	[BYTE ES:EDX + MCCONTROL], MCTErrorInt OR MCTDataReady
		MOV	[BYTE ES:EDX + IRQMaskReg], 0 ; reset Test IRQ, unmask IRQs

		POP	ES EDX
		RET
ENDP		DisableRuskInt

; Interrupt-Routine

PROC		RskInt	FAR

		MOV	DX, [IntReg]
		IN	AX, DX
		TEST	AX, (PCILocalInt OR DMA0Int) SHR 8
		JNZ	@@TestInt

		STC
		RET
@@TestInt:
		CLI
		LES	EDI, [HolePtr]

		TEST	AH, DMA0Int SHR 16	; end DMA IRQ ?
		JZ	@@TestLocalIRQ
		PUSH	AX
@@EndOfDMA:
		MOV	DX, [IOBase]
		ADD	DX, DMA0CmdStatus
		MOV	AL, DMAclrint OR DMAenable
		OUT	DX, AL

		INC	[DMAStopped]

		XOR	AX, AX
		LOCK XCHG AX, [CurrentDMABuf]
		OR	AX, AX
		JZ	@@BadEndOfDMA

		LEA	BX, [FullList]
		CALL	ListIns

		TEST	[Flags], KillFlag
		SETZ	AL
		NEG	AL
		AND	AL, MCTNextSet
		MOV	[BYTE ES:EDI + MCCONTROL], AL
		NEG	[DMAenabled]

		MOV	EBX, [DWORD BIDBuffer]
		SHLD	EAX, EBX, 16
		MOV	DL, DevHlp_ProcRun
		CALL	[DevHlp]

@@EndOfDMAEnd:
		POP	AX
@@TestLocalIRQ:
		TEST	AL, PCILocalInt SHR 8	; local PCI IRQ ?
		JZ	@@IntDone		; no

		MOV	AL, [ES:EDI + IRQStatusReg]
		TEST	AL, IRQDataReady OR IRQErrorInt
		JZ	@@Unhandled		; something weird is going on

		MOV	[BYTE ES:EDI + MCCONTROL], MCTErrorInt OR MCTDataReady

		TEST	AL, IRQDataReady
		JZ	@@ErrorInt

;		 TEST	 [BYTE ES:EDI + IRQMaskReg], IRQTest
;		 JZ	 @@Unhandled

		MOV	[BYTE ES:EDI + IRQStatusReg], 0 ; reset Test IRQ
		PUSH	AX
@@DataReady:
		MOV	AX, [Flags]
		AND	AX, KillFlag
		JNZ	@@DataReadyEnd

		OR	AX, [CurrentDMABuf]
		JNZ	@@BadRdyWDMA

		LEA	BX, [FreeList]
		CALL	ListRem
		JZ	@@BadRdyNoBuffer

		MOV	BX, AX
		LOCK XCHG AX, [CurrentDMABuf]

		TEST	[ADCBankSwitch], 0FFh
		JZ	@@StartDMA
		MOV	[BYTE ES:EDI + ADCCSWITCHMEM], 1 ; ADC bank switch
@@StartDMA:
		MOV	DX, [IOBase]
		ADD	DX, DMA0DescPtr
		MOV	EAX, [(DMABuf BX).DescPhys]
		OR	AL, DescFlags
		OUT	DX, EAX
		ADD	DX, DMA0CmdStatus - DMA0DescPtr
		MOV	AL, DMAenable OR DMAstart
		OUT	DX, AL

		INC	[DMAStarted]
@@DataReadyEnd:
		POP	AX
		TEST	AL, IRQErrorInt
		JZ	@@IntDone
@@ErrorInt:
		XOR	EBX, EBX
		LOCK XCHG EBX, [BlockIdError]
		OR	EBX, EBX
		JZ	@@IntDone
		MOV	EBX, [DWORD BIDError]
		SHLD	EAX, EBX, 16
		MOV	DL, DevHlp_ProcRun
		CALL	[DevHlp]
@@IntDone:
		MOV	AL, [BYTE IRQ]
		MOV	DL, DevHlp_EOI
		CALL	[DevHlp]

		CLC
		STI
		RET

@@BadEndOfDMA:
		INC	[DMAIntNoBuffer]
		JMP	@@EndOfDMAEnd
@@BadRdyNoBuffer:
		INC	[RdyIntNoBuffer]
		JMP	@@DataReadyEnd
@@BadRdyWDMA:
		INC	[RdyIntWDMA]
		JMP	@@DataReadyEnd
@@Unhandled:
		MOV	[BYTE ES:EDI + IRQMaskReg], 0 ; shut down interrupts
		INC	[UnhandledInt]
		JMP	@@IntDone

ENDP		RskInt



; Timer service (benutzt fr Simulation)

PROC		Timer	FAR
		PUSH	DS EAX

		MOV	AX, RData
		MOV	DS, AX

		CLI
		MOV	AL, [DMAenabled]
		OR	AL, AL
		JLE	@@End

		NEG	AL
		MOV	[DMAenabled], AL

		LDS	EAX, [HolePtr]
		MOV	[BYTE DS:EAX + IRQStatusReg], IRQTest
@@End:
		STI
		POP	EAX DS
		RET
ENDP		Timer


; Context hook (for deferred task time processing)

PROC		CtxHook FAR
		RET
ENDP		CtxHook

; Device Strategy Entrypoints

PROC		Strategy FAR
		MOV	AX, RPDONE + RPERR + ERROR_BAD_COMMAND
		MOVZX	SI, [ReqPacket.Command]
		CMP	SI, FuncTableLen
		JAE	@@NotSupported
		SHL	SI, 1
		PUSH	ES
		PUSH	BX
		MOV	BP, SP
		CALL	[FuncTable+SI]
		POP	BX
		POP	ES
@@NotSupported:
		MOV	[ReqPacket.Status], AX
		RET
ENDP		Strategy

PROC		Common	NEAR
Read:
Write:
		MOV	[(RqPRdWr ES:BX).Count], 0
		JMP	Open
Close:
		MOV	[DMAenabled], 0
		LOCK OR [Flags], KillFlag OR AbortFlagB

		XOR	EBX, EBX
		LOCK XCHG EBX, [BlockIdError]
		OR	EBX, EBX
		JZ	@@Free1
		LOCK OR [Flags], AbortFlagE
		MOV	EBX, [DWORD BIDError]
		SHLD	EAX, EBX, 16
		MOV	DL, DevHlp_ProcRun
		CALL	[DevHlp]
@@Free1:
		XOR	AX, AX
		LOCK XCHG AX, [CurrentDMABuf]
		OR	AX, AX
		JZ	@@Free2
		MOV	AX, DS
		MOV	BX, CS
		MOV	CX, 10
		MOV	DI, 0
		MOV	DX, DevHlp_ProcBlock + 100h
		CALL	[DevHlp]
@@Free2:
		CALL	FreeDMABuffer
Open:
		MOV	AX, RPDONE
NotSupported:
		RET
ENDP		Common

PROC		FreeDMABuffer NEAR
		PUSH	EAX SI CX DX

		XOR	CX, CX
		LOCK XCHG CX, [numDMABuffers]
		OR	CX, CX
		JZ	@@End

		CLI
		LEA	AX, [FreeList.Head]
		LOCK XCHG AX, [FreeList.Tail]
		XOR	AX, AX
		LOCK XCHG AX, [FreeList.Head]
		XOR	AX, AX
		LOCK XCHG AX, [CurrentDMABuf]
		LEA	AX, [FullList.Head]
		LOCK XCHG AX, [FullList.Tail]
		XOR	AX, AX
		LOCK XCHG AX, [FullList.Head]
		LEA	AX, [DoneList.Head]
		LOCK XCHG AX, [DoneList.Tail]
		XOR	AX, AX
		LOCK XCHG AX, [DoneList.Head]
		XOR	EBX, EBX
		LOCK XCHG EBX, [BlockIdBuffer]
		STI

		OR	EBX, EBX
		JZ	@@FreeMem
		LOCK OR [Flags], AbortFlagB
		MOV	EBX, [DWORD BIDBuffer]
		SHLD	EAX, EBX, 16
		MOV	DL, DevHlp_ProcRun
		CALL	[DevHlp]
@@FreeMem:
		LEA	SI, [DMABuffers]
@@FreeLoop:
		XOR	EAX, EAX
		LOCK XCHG EAX, [(DMABuf SI).BufProcess]
		OR	EAX, EAX
		JZ	@@Free1
		MOV	DL, DevHlp_VMFree
		CALL	[DevHlp]
@@Free1:
		XOR	EAX, EAX
		LOCK XCHG EAX, [(DMABuf SI).BufLin]
		OR	EAX, EAX
		JZ	@@Free2
		MOV	DL, DevHlp_VMFree
		CALL	[DevHlp]
@@Free2:
		ADD	SI, SIZE DMABuf
		LOOP	@@FreeLoop

		XOR	EAX, EAX
		LOCK XCHG EAX, [DMADescriptors]
		OR	EAX, EAX
		JZ	@@End
		MOV	DL, DevHlp_VMFree
		CALL	[DevHlp]
@@End:
		POP	DX CX SI EAX
		RET
ENDP		FreeDMABuffer

CAT_RUSK	=	0C1h
FUN_READREG	=	60h
FUN_READBLOCK	=	61h
FUN_CONFIGDMA	=	62h
FUN_QUERYCONFIG =	63h
FUN_WAITERROR	=	64h
FUN_FREEDMA	=	65h
FUN_HANDLEBUF	=	66h
FUN_GETERRORS	=	67h
FUN_WRITEREG	=	40h
FUN_WRITEBLOCK	=	41h
FUN_WRITELCA	=	42h
FUN_RESET	=	43h
FUN_KILL	=	44h
FUN_ABORT	=	45h
FUN_STARTSTOP	=	46h

; IO Control Dispatcher

PROC		IOCtl	NEAR
		CMP	[IOPacket.Category], CAT_RUSK
		JNE	@@Error
		MOV	AL, [IOPacket.Function]
		CMP	AL, FUN_RESET
		JE	ResetRuskPCI
		CMP	AL, FUN_KILL
		JE	Kill
		CMP	AL, FUN_ABORT
		JE	Abort
		CMP	AL, FUN_HANDLEBUF
		JE	HandleBuffer
		CMP	AL, FUN_STARTSTOP
		JE	StartStopDMA
		CMP	AL, FUN_READREG
		JE	ReadReg
		CMP	AL, FUN_READBLOCK
		JE	ReadBlock
		CMP	AL, FUN_WRITEREG
		JE	WriteReg
		CMP	AL, FUN_WRITEBLOCK
		JE	WriteBlock
		CMP	AL, FUN_WRITELCA
		JE	WriteLCA
		CMP	AL, FUN_QUERYCONFIG
		JE	QueryConfig
		CMP	AL, FUN_WAITERROR
		JE	WaitError
		CMP	AL, FUN_CONFIGDMA
		JE	ConfigDMA
		CMP	AL, FUN_FREEDMA
		JE	FreeDMA
		CMP	AL, FUN_GETERRORS
		JE	GetErrors
		CMP	AL, FUN_RESET
		JE	ResetRuskPCI
		CMP	AL, FUN_QUERYCONFIG
		JE	QueryConfig
		CMP	AL, FUN_WRITELCA
		JE	WriteLCA
@@Error:
		MOV	AX, RPDONE + RPERR + ERROR_INVALID_PARAMETER
		RET
ENDP		IOCtl

; prfe das Parameterpaket auf korrekte L„nge und Adressierbarkeit
;  ES:BX : IOPaket
;  AX	 : erwartete L„nge der Parameter
;  wenn ok, dann
;  CX	 : L„nge der Parameter

PROC		CheckPPacket NEAR
		MOV	CX, [IOPacket.ParamLen]
		OR	CX, CX
		JNZ	@@CheckLen
		MOV	CX, AX
@@CheckLen:
		CMP	CX, AX
		JB	@@ParameterFail
		PUSH	DI
		MOV	DI, [WORD (IOPacket.Param) + 0]
		MOV	AX, [WORD (IOPacket.Param) + 2]
		MOV	DX, DevHlp_VerifyAccess
		CALL	[DevHlp]
	IF ERRORTRACE
		MOV	[LastError], EAX
	ENDIF
		POP	DI
		JNC	@@Exit
@@AccessFail:
		MOV	AX, RPDONE + RPERR + ERROR_GEN_FAILURE
		JMP	@@Error
@@ParameterFail:
		MOV	AX, RPDONE + RPERR + ERROR_INVALID_PARAMETER
@@Error:
		STC
@@Exit:
		RET
ENDP		CheckPPacket

; prfe das Datenpaket auf korrekte L„nge und Adressierbarkeit
;  ES:BX : IOPaket
;  AX	 : erwartete L„nge der Daten
;  wenn ok, dann
;  CX	 : L„nge der Daten

PROC		CheckDPacket NEAR
		MOV	CX, [IOPacket.DataLen]
		OR	CX, CX
		JNZ	@@CheckLen
		MOV	CX, AX
@@CheckLen:
		CMP	CX, AX
		JNE	@@ParameterFail
		PUSH	DI
		MOV	DI, [WORD (IOPacket.Data) + 0]
		MOV	AX, [WORD (IOPacket.Data) + 2]
		MOV	DX, DevHlp_VerifyAccess + (1 SHL 8)	; check R/W
		CALL	[DevHlp]
	IF ERRORTRACE
		MOV	[LastError], EAX
	ENDIF
		POP	DI
		JNC	@@Exit
@@AccessFail:
		MOV	AX, RPDONE + RPERR + ERROR_GEN_FAILURE
		JMP	@@Error
@@ParameterFail:
		MOV	AX, RPDONE + RPERR + ERROR_INVALID_PARAMETER
@@Error:
		STC
@@Exit:
		RET
ENDP		CheckDPacket

; blockiere einen Thread
; EBX: BlockID
; ECX: Timeout

PROC		Block	NEAR
		PUSH	EDI
		SHLD	EAX, EBX, 16
		SHLD	EDI, ECX, 16
		MOV	DX, DevHlp_ProcBlock
		CLI
		CALL	[DevHlp]
	IF ERRORTRACE
		MOV	[LastError], EAX
	ENDIF
		POP	EDI
		RET
ENDP		Block

; Locked Speicher
;  EAX: Lock Flags
;  EBX: Adresse
;  ECX: L„nge

PROC		Lock	NEAR
		PUSH	SI
		MOV	EDI, [pPages]
		MOV	ESI, [phLock]
		MOV	DL, DevHlp_VMLock
		CALL	[DevHlp]
	IF ERRORTRACE
		MOV	[LastError], EAX
	ENDIF
		POP	SI
		RET
ENDP		Lock

; Unlocked Speicher

PROC		Unlock	NEAR
		PUSH	EAX
		MOV	ESI, [phLock]
		MOV	DL, DevHlp_VMUnlock
		CALL	[DevHlp]
	IF ERRORTRACE
		MOV	[LastError], EAX
	ENDIF
		POP	EAX
		RET
ENDP		Unlock

PROC		FreeDMA NEAR
		CALL	FreeDMABuffer
		MOV	AX, RPDONE
@@Exit:
		RET
ENDP		FreeDMA


; H„nge Element in Liste ein (am Ende!), Aufruf mit Interrupts disabled!
; AX: Pointer auf Element
; BX: Pointer auf Liste

PROC		ListIns NEAR
		PUSH	SI

		MOV	SI, AX
		MOV	[WORD SI], 0
		LOCK XCHG SI, [(LList BX).Tail]
		LOCK OR [SI], AX

		POP	SI
		RET
ENDP		ListIns

; Entferne Element aus Liste (am Anfang!), Aufruf mit Interrupts disabled!
; BX: Pointer auf Liste
; AX: Pointer auf Element oder NULL

PROC		ListRem NEAR
		MOV	AX, [(LList BX).Head]
		OR	AX, AX
		JZ	@@End
		PUSH	SI
		MOV	SI, AX
		MOV	AX, [SI]
		OR	AX, AX
		LOCK XCHG AX, [(LList BX).Head]
		JNZ	@@End2
		LEA	SI, [(LList BX).Head]
		LOCK XCHG SI, [(LList BX).Tail]
@@End2:
		POP	SI
@@End:
		OR	AX, AX
		RET
ENDP		ListRem

; Schreibe ein Register auf dem DSP-Bus

PROC		WriteReg NEAR
		MOV	AX, IOParmSizeReg
		CALL	CheckPPacket
		JC	@@Exit
		MOV	AX, IODataSizeReg
		CALL	CheckDPacket
		JC	@@Exit
		LGS	SI, [IOPacket.Data]
		MOV	EAX, [DataReg.Value]
		LGS	SI, [IOPacket.Param]
		MOV	EDI, [ParmReg.Reg]
		AND	EDI, [HoleMask]
		ADD	EDI, [Hole]
		MOV	ES, [FlatSel]
		MOV	[ES:EDI], EAX
		MOV	AX, RPDONE
@@Exit:
		RET
ENDP		WriteReg

; Schreibe einen RegisterBlock auf dem DSP-Bus

PROC		WriteBlock NEAR
		MOV	AX, IOParmSizeBlock
		CALL	CheckPPacket
		JC	@@Exit
		LGS	SI, [IOPacket.Param]

		MOV	EBX, [ParmBlock.Addr]
		CMP	EBX, 1 SHL 16
		JB	@@ParameterFail

		MOV	ECX, [ParmBlock.Len]
		OR	ECX, ECX
		JZ	@@Done
		CMP	ECX, NUMPAGES SHL 12
		JA	@@ParameterFail

		MOV	EAX, 0
		CALL	Lock
		JC	@@AccessFail

		SHR	ECX, 2
		MOV	EDI, [ParmBlock.Reg]
		MOV	ESI, [ParmBlock.Addr]
		AND	EDI, [HoleMask]
		ADD	EDI, [Hole]
		MOV	ES, [FlatSel]
		CLD
		REP MOVS [DWORD ES:EDI],[DWORD ES:ESI]

		CALL	Unlock
@@Done:
		MOV	AX, RPDONE
		JMP	@@Exit
@@ParameterFail:
		MOV	AX, RPDONE + RPERR + ERROR_INVALID_PARAMETER
		JMP	@@Exit
@@AccessFail:
		MOV	AX, RPDONE + RPERR + ERROR_GEN_FAILURE
@@Exit:
		RET
ENDP		WriteBlock

; Lese ein Register auf dem DSP-Bus

PROC		ReadReg NEAR
		MOV	AX, IOParmSizeReg
		CALL	CheckPPacket
		JC	@@Exit
		MOV	AX, IODataSizeReg
		CALL	CheckDPacket
		JC	@@Exit
		LGS	SI, [IOPacket.Param]
		MOV	EDI, [ParmReg.Reg]
		AND	EDI, [HoleMask]
		ADD	EDI, [Hole]
		LGS	SI, [IOPacket.Data]
		MOV	ES, [FlatSel]
		MOV	EAX, [ES:EDI]
		MOV	[DataReg.Value], EAX
		MOV	AX, RPDONE
@@Exit:
		RET
ENDP		ReadReg

; Lese einen RegisterBlock auf dem DSP-Bus

PROC		ReadBlock NEAR
		MOV	AX, IOParmSizeBlock
		CALL	CheckPPacket
		JC	@@Exit
		LGS	SI, [IOPacket.Param]

		MOV	EBX, [ParmBlock.Addr]
		CMP	EBX, 1 SHL 16
		JB	@@ParameterFail

		MOV	ECX, [ParmBlock.Len]
		OR	ECX, ECX
		JZ	@@Done
		CMP	ECX, NUMPAGES SHL 12
		JA	@@ParameterFail

		MOV	EAX, 1000b
		CALL	Lock
		JC	@@AccessFail

		SHR	ECX, 2
		MOV	EDI, [ParmBlock.Addr]
		MOV	ESI, [ParmBlock.Reg]
		AND	ESI, [HoleMask]
		ADD	ESI, [Hole]
		MOV	ES, [FlatSel]
		CLD
		REP MOVS [DWORD ES:EDI],[DWORD ES:ESI]

		CALL	Unlock
@@Done:
		MOV	AX, RPDONE
		JMP	@@Exit
@@ParameterFail:
		MOV	AX, RPDONE + RPERR + ERROR_INVALID_PARAMETER
		JMP	@@Exit
@@AccessFail:
		MOV	AX, RPDONE + RPERR + ERROR_GEN_FAILURE
@@Exit:
		RET
ENDP		ReadBlock

; frage Fehlerz„hler ab

PROC		GetErrors NEAR
		MOV	AX, IOErrorCtrSize
		CALL	CheckDPacket
		JC	@@Exit
		LGS	SI, [IOPacket.Data]
		MOV	EAX, [DMAIntNoBuffer]
		MOV	[ErrorCtr.DMAIntNoBuffer], EAX
		MOV	EAX, [RdyIntNoBuffer]
		MOV	[ErrorCtr.RdyIntNoBuffer], EAX
		MOV	EAX, [RdyIntWDMA]
		MOV	[ErrorCtr.RdyIntWDMA], EAX
		MOV	EAX, [UnhandledInt]
		MOV	[ErrorCtr.UnhandledInt], EAX
		MOV	AX, RPDONE
@@Exit:
		RET
ENDP		GetErrors

PROC		ConfigDMA NEAR
		ARG	ReqPacketPtr:DWORD
		LOCAL	@@numBuffers:WORD, @@numJobs:DWORD, @@JobList:DWORD, @@BankSwitch:BYTE = @@LocalSize

		PUSH	BP
		MOV	BP, SP
		SUB	SP, @@LocalSize

		CALL	FreeDMABuffer

		MOV	AX, IOCfgDMASize
		CALL	CheckPPacket
		JC	@@Exit
		MOV	AX, IODataSizeReg
		CALL	CheckDPacket
		JC	@@Exit
		LGS	SI, [IOPacket.Param]

		MOV	AX, [ParmDMA.NumBuffers]
		OR	AX, AX
		JZ	@@ParameterFail
		CMP	AX, MAXNUMBUFFERS
		JA	@@ParameterFail
		MOV	[@@numBuffers], AX

		MOV	AL, [ParmDMA.ADCBankSwitch]
		CMP	AL, 1
		JA	@@ParameterFail
		MOV	[@@BankSwitch], AL

		MOV	ECX, [ParmDMA.NumJobs]
		OR	ECX, ECX
		JZ	@@ParameterFail
		CMP	ECX, MAXNUMJOBS
		JA	@@ParameterFail
		MOV	[@@numJobs], ECX

		MOVZX	EAX, [@@numBuffers]
		IMUL	ECX, EAX
		IMUL	ECX, SIZE DMADesc
		MOV	[DMADescSize], ECX

		PUSH	SI
		MOV	AX, DS		; allocate mem for DMA descriptors
		LEA	ESI, [DMADescPhys]
		MOV	DL, DevHlp_VirtToLin
		CALL	[DevHlp]
	IF ERRORTRACE
		MOV	[LastError], EAX
	ENDIF
		MOV	EDI, EAX
		MOV	ECX, [DMADescSize]
		ADD	ECX, 4095		; need fill to full page!
		AND	ECX, NOT 4095
		MOV	EAX, 1010b
		MOV	DL, DevHlp_VMAlloc
		CALL	[DevHlp]
	IF ERRORTRACE
		MOV	[LastError], EAX
	ENDIF
		POP	SI
		JC	@@AccessFail
		MOV	[DMADescriptors], EAX

		MOV	ECX, [@@numJobs]
		IMUL	ECX, SIZE DMADesc
		MOV	EBX, [ParmDMA.Jobs]
		CMP	EBX, 10000h
		JB	@@ParameterFail
	IF 0
		MOV	EAX, 0
		CALL	Lock
		JC	@@AccessFail
	ENDIF
		MOV	[@@JobList], EBX

		MOV	ESI, [@@JobList]       ; count buffer size and create
		MOV	EDI, [DMADescriptors]  ; prototype DMA descriptors
		MOV	ES, [FlatSel]
		MOV	EDX, DescFlags
		XOR	EAX, EAX	       ; accumulates size of DMA buffer
		MOV	ECX, [@@numJobs]
@@GetSizeLoop:
		MOV	[(DMADesc ES:EDI).MemAddr], EAX
		MOV	EBX, [(DMAJob ES:ESI).Reg]
		AND	EBX, [HoleMask]
		ADD	EBX, [MemBase]
		MOV	[(DMADesc ES:EDI).IOAddr], EBX
		MOV	EBX, [DWORD (DMAJob ES:ESI).Len]
		SHL	EBX, 2		    ; DWORDS!
		TEST	[(DMAJob ES:ESI).Flags], MASK Skip ; is this a filler op ?
		JNZ	@@GetSizeContinue
		DEC	EBX
		AND	EBX, MAXJOBSIZE - 1
		INC	EBX
		MOV	[(DMADesc ES:EDI).numBytes], EBX
		ADD	EDX, SIZE DMADesc
		TEST	[(DMAJob ES:ESI).Flags], MASK Direction
		JZ	@@DMARead
		AND	DL, NOT DescFlagsR
		XOR	EBX, EBX	    ; do not advance on writes!
@@DMARead:
		MOV	[(DMADesc ES:EDI).nextDesc], EDX
		OR	DL, DescFlagsR

		ADD	EDI, SIZE DMADesc
@@GetSizeContinue:
		ADD	EAX, EBX
		ADD	ESI, SIZE DMAJob
		DEC	ECX
		JNZ	@@GetSizeLoop

		SUB	EDI, SIZE DMADesc
		OR	[BYTE (DMADesc ES:EDI).nextDesc], DescFlagsEnd
		ADD	EDI, SIZE DMADesc

	IF 0
		CALL	Unlock
	ENDIF

		MOV	[DMABufSize], EAX
		CMP	EAX, MAXSIZEBUFFER
		JA	@@ParameterFail
		ADD	EAX, 4095		; need fill to full page!
		AND	EAX, NOT 4095
		MOV	[DMABlockSize], EAX

		MOV	AX, DS
		LEA	ESI, [DMABuffers]
		MOV	DL, DevHlp_VirtToLin
		CALL	[DevHlp]
		LEA	EDI, [(DMABuf EAX).BufPhys]

		MOV	SI, [@@numBuffers]	; allocate buffer memory
@@AllocLoop:
		MOV	ECX, [DMABlockSize]
		MOV	EAX, 1010b
		MOV	DL, DevHlp_VMAlloc
		CALL	[DevHlp]
	IF ERRORTRACE
		JNC	@@F0
		MOV	[RegEBX], EAX
@@F0:
	ENDIF
		JC	@@AllocFail
		MOV	[(DMABuf ES:EDI-2).BufLin], EAX

		MOV	EBX, EAX		; map it into process space
		MOV	EAX, 21h		; map high!
		MOV	DL, DevHlp_VMGlobalToProcess
		CALL	[DevHlp]
		JNC	@@AllocOk
	IF ERRORTRACE
		MOV	[RegECX], EAX
	ENDIF
		MOV	EAX, 1h 		; map normal!
		MOV	DL, DevHlp_VMGlobalToProcess
		CALL	[DevHlp]
	IF ERRORTRACE
		JNC	@@F1
		MOV	[RegECX], EAX
@@F1:
	ENDIF
		JC	@@AllocFail
@@AllocOk:
		MOV	[(DMABuf ES:EDI-2).BufProcess], EAX

		ADD	EDI, SIZE DMABuf
		INC	[numDMABuffers]
		DEC	SI
		JNZ	@@AllocLoop
@@AllocFail:
		MOV	CX, [numDMABuffers]
		OR	CX, CX
		JZ	@@Done

		CLD
		PUSH	EBP			; duplicate prototype DMA
		MOV	EAX, [@@numJobs]	; descriptors and store
		IMUL	EAX, SIZE DMADesc	; descriptor pointers into
		LEA	BX, [DMABuffers]	; DMA buffer structs
		MOV	EDI, [DMADescriptors]
		MOV	EBP, [DMADescPhys]
		MOV	DX, [numDMABuffers]
@@DescLoop:
		MOV	[(DMABuf BX).DescPhys], EBP
		MOV	[(DMABuf BX).DescLin], EDI
		MOV	ESI, [DMADescriptors]
		MOV	ECX, EAX
		SHR	ECX, 2
		REP MOVS [DWORD ES:EDI], [DWORD ES:ESI]
		ADD	EBP, EAX
		ADD	BX, SIZE DMABuf
		DEC	DX
		JNZ	@@DescLoop
		POP	EBP

		MOV	DX, [numDMABuffers]	; patch up DMA descriptors to
		LEA	BX, [DMABuffers]	; physical memory addresses
@@BufLoop:
		MOV	EDI, [(DMABuf DS:BX).DescLin]
		MOV	EAX, [(DMABuf DS:BX).BufPhys]
		MOV	ESI, [(DMABuf DS:BX).DescPhys]
		MOV	ECX, [@@numJobs]
@@DescLoopP:
		ADD	[(DMADesc ES:EDI).MemAddr], EAX
		ADD	[(DMADesc ES:EDI).nextDesc], ESI
		ADD	EDI, SIZE DMADesc
		DEC	ECX
		JNZ	@@DescLoopP

		ADD	BX, SIZE DMABuf
		DEC	DX
		JNZ	@@BufLoop

		MOV	CX, [numDMABuffers]	; build free buffer list
		LEA	AX, [DMABuffers]
		LEA	BX, [FreeList]
@@ListInsLoop:
		CALL	ListIns
		ADD	AX, SIZE DMABuf
		LOOP	@@ListInsLoop
@@Done:
		LES	BX, [ReqPacketPtr]
		LGS	SI, [IOPacket.Data]
		MOVZX	EAX, [numDMABuffers]
		MOV	[DataReg.Value], EAX
		OR	AX, AX
		JZ	@@AccessFail

		MOV	AL, [@@BankSwitch]
		MOV	[ADCBankSwitch], AL
		MOV	AX, RPDONE
		JMP	@@Exit
@@ParameterFail:
		MOV	AX, RPDONE + RPERR + ERROR_INVALID_PARAMETER
		JMP	@@Exit
@@AccessFail:
		MOV	AX, RPDONE + RPERR + ERROR_GEN_FAILURE
@@Exit:
		LEAVE
		RET
ENDP		ConfigDMA

PROC		HandleBuffer NEAR
		ARG	ReqPacketPtr:DWORD
		LOCAL	@@Mode:BYTE = @@LocalSize

		PUSH	BP
		MOV	BP, SP
		SUB	SP, @@LocalSize

		MOV	AX, IOParmSizeHBuf
		CALL	CheckPPacket
		JC	@@Exit

		LGS	SI, [IOPacket.Param]
		MOV	AL, [ParmHBuf.Mode]
		MOV	[@@Mode], AL
		OR	AL, AL
		JZ	@@ReturnBuf
		CMP	AL, 2
		JA	@@ParameterFail

		MOV	AX, IODataSizeReg
		CALL	CheckDPacket
		JC	@@Exit
@@ReturnBuf:
		MOV	CX, [numDMABuffers]
		OR	CX, CX
		JZ	@@BadCommand

		MOV	EAX, [ParmHBuf.Addr]
		OR	EAX, EAX
		JZ	@@ReturnDone

		TEST	[DoneList.Head], 0FFFFh
		JZ	@@BadCommand

		MOV	SI, [DoneList.Tail]	; most likely returned buffer
		CMP	EAX, [(DMABuf SI).BufProcess]
		JNZ	@@DoSearch
		LEA	BX, [DoneList]
		CALL	ListRem
		JMP	@@Found1
@@DoSearch:
		MOV	SI, [DoneList.Head]
		LEA	DI, [DoneList.Head]
@@SearchLoop:
		CMP	EAX, [(DMABuf SI).BufProcess]
		JZ	@@Found
		MOV	DI, SI
		MOV	SI, [(DMABuf SI).next]
		OR	SI, SI
		JNZ	@@SearchLoop
		JMP	@@ParameterFail
@@Found:
		MOV	AX, [(DMABuf SI).next]
		MOV	[(DMABuf DI).next], AX
		MOV	AX, SI
@@Found1:
		LEA	BX, [FreeList]
		CLI
		CALL	ListIns
		STI
@@ReturnDone:
		CMP	[@@Mode], 0
		JE	@@Done

		CLI
		MOV	EBX, [DWORD BIDBuffer]
		XOR	EAX, EAX
		LOCK CMPXCHG [BlockIdBuffer], EBX
		JNZ	@@used
@@PollBuffer:
		LEA	BX, [FullList]
		CALL	ListRem

		MOV	SI, AX
		MOV	EDX, 0
		JZ	@@NoBuffer

		MOV	EDX, [(DMABuf SI).BufProcess]
		LEA	BX, [DoneList]
		CALL	ListIns
		JMP	@@StoreBuffer
@@NoBuffer:
		CMP	[@@Mode], 1
		JE	@@StoreBuffer

		MOV	EBX, [DWORD BIDBuffer]
		MOV	ECX, -1
		CALL	Block

		JC	@@Interrupted
		LOCK BTR [Flags], AbortBitB
		JC	@@Interrupted
		CLI
		JMP	@@PollBuffer
@@StoreBuffer:
		XOR	EBX, EBX
		LOCK XCHG [BlockIdBuffer], EBX
		STI
		LES	BX, [ReqPacketPtr]
		LGS	SI, [IOPacket.Data]
		MOV	[DataReg.Value], EDX
@@Done:
		MOV	AX, RPDONE
		JMP	@@Exit
@@ParameterFail:
		MOV	AX, RPDONE + RPERR + ERROR_INVALID_PARAMETER
		JMP	@@Exit
@@BadCommand:
		MOV	AX, RPDONE + RPERR + ERROR_BAD_COMMAND
		JMP	@@Exit
@@Interrupted:
		XOR	EBX, EBX
		LOCK XCHG [BlockIdBuffer], EBX
		STI
		MOV	AX, RPDONE + RPERR + ERROR_CHAR_CALL_INTERRUPTED
		JMP	@@Exit
@@used:
		MOV	AX, RPDONE + RPERR + ERROR_DEVICE_IN_USE
@@Exit:
		LEAVE
		RET
ENDP		HandleBuffer


; Starte/Stoppe DMA

PROC		StartStopDMA NEAR
		MOV	AX, IOParmSizeStartStop
		CALL	CheckPPacket
		JC	@@Exit
		LGS	SI, [IOPacket.Param]
		MOV	AL, [ParmStartStop.Mode]
		MOV	[DMAenabled], AL
		OR	AL, AL
		JNZ	@@Start
		LOCK OR [Flags], AbortFlagB
		CALL	DisableRuskInt
		MOV	EBX, [DWORD BIDBuffer]
		SHLD	EAX, EBX, 16
		MOV	DL, DevHlp_ProcRun
		CALL	[DevHlp]
		JMP	@@End
@@Start:
		CALL	EnableRuskInt
@@End:
		MOV	AX, RPDONE
@@Exit:
		RET
ENDP		StartStopDMA

PROC		Wait	NEAR
		PUSH	EBX ECX

		MOV	EBX, [DWORD @@BlockID]
		MOV	ECX, 1
		CALL	Block

		POP	ECX EBX
		RET

@@BlockID:	DW	OFFSET Wait, RCode
ENDP		Wait

; Programmiere das LCA

CONFIGSIZE	=	7914h
MAXWAIT 	=	10

PROC		WriteLCA NEAR
		MOV	AX, IOParmSizeLCA
		CALL	CheckPPacket
		JC	@@Exit
		LGS	SI, [IOPacket.Param]

		MOV	EBX, [ParmLCA.Addr]
		CMP	EBX, 1 SHL 16
		JB	@@ParameterFail

		MOV	ECX, [ParmLCA.Len]
		CMP	ECX, CONFIGSIZE
		JNE	@@ParameterFail

	IF 0
		MOV	EAX, 10000b
		CALL	Lock
		JC	@@AccessFail
	ENDIF

		MOV	ESI, [ParmLCA.Addr]
		MOV	EDI, MCCTRLREG
		AND	EDI, [HoleMask]
		ADD	EDI, [Hole]
		MOV	ES, [FlatSel]
		CLD

		MOV	AL, [ES:EDI]
		TEST	AL, LCAInit
		JZ	@@ErrorAndUnlock

		MOV	AL, 0
		MOV	[ES:EDI], AL
		MOV	BX, MAXWAIT
		CALL	Delay
@@WaitInitLow:
		MOV	AL, [ES:EDI]
		TEST	AL, LCAInit
		JZ	@@next1
		CALL	Wait
		DEC	BX
		JNZ	@@WaitInitLow
		JMP	@@ErrorAndUnlock
@@next1:
		MOV	AL, LCAProg
		MOV	[ES:EDI], AL
		MOV	BX, MAXWAIT
		CALL	Delay
@@WaitDoneLow:
		MOV	AL, [ES:EDI]
		AND	AL, LCAInit OR LCADone
		CMP	AL, LCAInit
		JE	@@ProgLoopO
		CALL	Wait
		DEC	BX
		JNZ	@@WaitDoneLow
		JMP	@@ErrorAndUnlock

@@ProgLoopO:
		LODS	[BYTE ES:ESI]
		MOV	BL, 8
@@ProgLoopI:
		MOV	DL, AL
		AND	DL, LCADin
		OR	DL, LCAProg
		MOV	[ES:EDI], DL
		OR	DL, LCACClk
		MOV	[ES:EDI], DL
		SHR	AL, 1
		DEC	BL
		JNZ	@@ProgLoopI
		DEC	ECX
		JNZ	@@ProgLoopO

		MOV	BL, 8
@@ProgLoopE:
		MOV	DL, LCAProg OR LCADin
		MOV	[ES:EDI], DL
		OR	DL, LCACClk
		MOV	[ES:EDI], DL
		DEC	BL
		JNZ	@@ProgLoopE

		MOV	AL, [ES:EDI]
		TEST	AL, LCADone
		JZ	@@ErrorAndUnlock

	IF 0
		CALL	Unlock
	ENDIF
@@Done:
		MOV	AX, RPDONE
		JMP	@@Exit
@@ParameterFail:
		MOV	AX, RPDONE + RPERR + ERROR_INVALID_PARAMETER
		JMP	@@Exit
@@ErrorAndUnlock:
	IF 0
		CALL	Unlock
	ENDIF
@@AccessFail:
		MOV	AX, RPDONE + RPERR + ERROR_GEN_FAILURE
@@Exit:
		RET
ENDP		WriteLCA

; Warte auf einen Error-Interrupt

PROC		WaitError NEAR
		MOV	EBX, [DWORD BIDError]
		XOR	EAX, EAX
		LOCK CMPXCHG [BlockIdError], EBX
		JNZ	@@used

		MOV	ECX, -1
		CALL	Block

		MOV	AX, RPDONE
		JC	@@Interrupted
		LOCK BTR [Flags], AbortBitE
		JNC	@@Exit
@@Interrupted:
		MOV	AX, RPDONE + RPERR + ERROR_CHAR_CALL_INTERRUPTED
		JMP	@@Exit
@@used:
		MOV	AX, RPDONE + RPERR + ERROR_DEVICE_IN_USE
@@Exit:
		RET
ENDP		WaitError

; l”se einen Hardware-Reset der RuskPCI-Karte aus. Gib auáerdem den Schreib- bzw.
; Lesekanal wieder frei.

PROC		ResetRuskPCI NEAR
		CALL	ResetCard
		XOR	EAX, EAX
		MOV	[Flags], AX
		MOV	[DMAenabled], AL
		MOV	[DMAIntNoBuffer], EAX
		MOV	[RdyIntNoBuffer], EAX
		MOV	[UnhandledInt], EAX
		CALL	EnableInt
		MOV	AX, RPDONE
		RET
ENDP		ResetRuskPCI

PROC		Shutdown NEAR
		CALL	ResetCard
		CALL	DisableInt
		MOV	AX, RPDONE
		RET
ENDP		Shutdown

; L”se alle blockierten Threads und sperre den Schreib- bzw. Lesekanal zu einer
; RuskPCI Karte. Die Sperre gilt bis zum n„chsten Reset-Kommando.

PROC		Kill	NEAR
		LOCK OR [Flags], KillFlag

; L”se alle blockierten Threads zu einer RuskPCI-Karte oder setze Semaphor

Abort:
		LOCK OR [Flags], AbortFlagE OR AbortFlagB
		MOV	AX, RPDONE
		RET
ENDP		Kill

; return configuration data

STRUC		tConfigData
  CardType	DW	?
  CardRevision	DW	?
  SerialNumber	DD	?
  ConfigLen	DB	?
ENDS		tConfigData

QConfigData	=	(tConfigData ES:BX)

PROC		QueryConfig NEAR
		MOV	AX, [IOPacket.DataLen]
		AND	AX, NOT 1
		JZ	@@ParameterFail
		CALL	CheckDPacket
		JC	@@Exit
		LES	DI, [IOPacket.Data]

		CLD
		MOV	SI, OFFSET EEData
		SHR	CX, 1
		REP MOVSW
		JMP	@@Done
@@ParameterFail:
		MOV	AX, RPDONE + RPERR + ERROR_INVALID_PARAMETER
		JMP	@@Exit
@@Done:
		MOV	AX, RPDONE
@@Exit:
		RET
ENDP		QueryConfig

; Initialisierung Teil 2 (Ring 0 protected)
; 1) fhre einen Kartenreset aus

PROC		InitComplete NEAR
		PUSH	DS
		POP	ES

		MOV	AX, OFFSET Timer
		MOV	BX, TICKCOUNT
		MOV	DL, DevHlp_TickCount
		CALL	[DevHlp]

		MOV	AX, DS
		LEA	ESI, [Pages]
		MOV	DL, DevHlp_VirtToLin
		CALL	[DevHlp]
		MOV	[pPages], EAX
		MOV	AX, DS
		LEA	ESI, [hLock]
		MOV	DL, DevHlp_VirtToLin
		CALL	[DevHlp]
		MOV	[phLock], EAX

		MOV	AX, DS
		LEA	ESI, [MemBase]
		MOV	DL, DevHlp_VirtToLin
		CALL	[DevHlp]
		MOV	EDI, EAX
		MOV	ECX, HOLESIZE
		MOV	EAX, 10000b
		MOV	DL, DevHlp_VMAlloc
		CALL	[DevHlp]
		MOV	[Hole], EAX

		CALL	DisableInt
		CALL	ResetCard
		CALL	EnableInt
@@End:
		MOV	AX, RPDONE
		RET
ENDP		InitComplete

ResCodeEnd:

; gib zur Boot-Zeit eine Meldung auf die Konsole aus

MACRO		Print	Message, Extra
		PUSH	1		; stdout
		PUSH	(SIZE Message) + (Extra)
		PUSH	DS
		PUSH	OFFSET Message
		CALL	DOSPUTMESSAGE
ENDM		Print

MACRO		PrintL	Message, Size
		PUSH	1		; stdout
		PUSH	(Size)
		PUSH	DS
		PUSH	OFFSET Message
		CALL	DOSPUTMESSAGE
ENDM		PrintL

; rufe eine Funktion des PCI-BIOS im PC-ROM auf

PROC		PCIBios NEAR
		PUSH	DS
		PUSH	DI			; returned data structure
		PUSH	DS
		PUSH	SI			; parm. list
		PUSH	OEMHLP_PCI		; request code for PCI calls
		PUSH	OEMHLP_CAT		; IOCTL category code
		PUSH	[OEMHLP_Handle] 	; file handle
		CALL	DOSDEVIOCTL		; make call to OEMHLP$
		RET
ENDP		PCIBios

; rufe eine Funktion des Resource-Managers von Ring 3 aus auf

PROC		RMR3	NEAR
		PUSH	BX
		MOV	BX, SP
		ADD	BX, 4
		PUSH	SS
		PUSH	BX
		PUSH	AX
		CALL	[RMIDC.R3Entry]
		POP	BX
		RET
ENDP		RMR3

EEPort		=	6Ch
EEClk		=	(1 SHL 24)
EECS		=	(1 SHL 25)
EEDI		=	(1 SHL 26)
EEDO		=	(1 SHL 27)

PROC		WriteEE NEAR
		OUT	DX, EAX
		MOV	AH, 10
@@WaitLoop:
		IN	AL, DX		; wait a little
		DEC	AH
		JNZ	@@WaitLoop
		RET
ENDP		WriteEE

PROC		ReadEEProm NEAR
		MOV	DX, [IOBase]
		ADD	DX, EEPort

		IN	EAX, DX 	; get initial value
		MOV	ESI, EAX
		AND	EAX, NOT (EEDI OR EEClk)
		OR	EAX, EECS
		CALL	WriteEE 	; setup EEProm

		MOV	CX, 3 + 6
		MOV	EBX, 110100010b SHL (26 - 8)
@@CmdLoop:
		AND	EAX, NOT (EEDI OR EEClk)
		MOV	EDI, EBX
		AND	EDI, EEDI
		OR	EAX, EDI
		OR	EAX, EECS
		CALL	WriteEE
		OR	EAX, EEClk
		CALL	WriteEE
		SHL	EBX, 1
		LOOP	@@CmdLoop

		MOV	CH, 30
		CLD
		PUSH	DS
		POP	ES
		MOV	DI, OFFSET EEData
@@ReadWordLoop:
		MOV	BX, 0
		MOV	CL, 16
@@ReadBitLoop:
		AND	EAX, NOT (EEDI OR EEClk)
		OR	EAX, EECS
		CALL	WriteEE
		OR	EAX, EEClk
		CALL	WriteEE
		IN	EAX, DX
		TEST	EAX, EEDO
		SETNZ	AL
		SHR	AL, 1
		RCL	BX, 1
		DEC	CL
		JNZ	@@ReadBitLoop
		MOV	AX, BX
		STOSW
		DEC	CH
		JNZ	@@ReadWordLoop

		MOV	EAX, ESI
		OUT	DX, EAX 		; restore initial value

		ROL	[SerialNumber], 16	; big -> little endian
		RET
ENDP		ReadEEProm

; Initialisierung Teil 1 (Ring 3 protected)
; 1) sichere Pointer auf Device-Helper
; 2) parse die Commandline hinsichtlich
;      -  Treibername
;      -  Quiet-Flag
;      -  Vendor- bzw. Device-ID-Override
; 3) gib gegebenenfalls Bootmeldung auf Konsole aus
; 4) ”ffne PCI-Bios
; 5) ”ffne Resource-Manager
; 6) suche RuskPCI-Karte
; falls keine Karte gefunden -> melde unkritischen Fehler
; 7) frage Hardware-Resourcen der Karte ab (IRQ, IO-Port, Memory-Adresse)
; 8) melde Treiber und Karte mit den gefundenen Inforationen beim Resource-
;    Manager an
; 9) schlieáe PCI-Bios
;10) melde erfolgreiche Initialisierung

PROC		Init	NEAR
		MOV	EAX, [(RqPInit ES:BX).DevHlp]
		MOV	[DevHlp], EAX

; parse Args
		PUSH	DS
		PUSH	DS
		POP	GS

		ASSUME	CS:RCode, DS:NOTHING, GS:RData

		LDS	SI, [(RqPInit ES:BX).Args]
@@EatNonBlanks:
		LODSB
		OR	AL, AL
		JZ	@@ParseEnd
		CMP	AL, ':'
		JE	@@GotSep
		CMP	AL, '\'
		JNE	@@CheckBlank
@@GotSep:
		MOV	[DName+0], SI
		MOV	[DName+2], DS
@@CheckBlank:
		CMP	AL, ' '
		JNE	@@EatNonBlanks
		MOV	[BYTE SI-1], 0
@@EatBlanks:
		LODSB
		CMP	AL, ' '
		JE	@@EatBlanks
		CMP	AL, '/'
		JNE	@@ParseEnd
		LODSB
		AND	AL, 5Fh
		CMP	AL, 'Q'
		SETE	[Quiet]
		JE	@@EatBlanks
		CMP	AL, 'I'
		JNE	@@ParseEnd
		LODSB
		AND	AL, 5Fh
		CMP	AL, 'D'
		JNE	@@ParseEnd
		LODSB
		AND	AL, 5Fh
		CMP	AL, 'V'
		SETE	[Vendor]
		JE	@@GetID
		CMP	AL, 'D'
		JNZ	@@ParseEnd
@@GetID:
		LODSB
		CMP	AL, ':'
		JNZ	@@ParseEnd
		MOV	CX, 4
@@GetIDLoop:
		LODSB
		CMP	AL, '0'
		JB	@@ParseEnd
		CMP	AL, '9'
		JBE	@@GotDigit
		AND	AL, 5Fh
		CMP	AL, 'A'
		JB	@@ParseEnd
		CMP	AL, 'F'
		JA	@@ParseEnd
		SUB	AL, 'A' - '9' - 1
@@GotDigit:
		SUB	AL, '0'
		SHL	AX, 16 - 4
		SHLD	BX, AX, 4
		LOOP	@@GetIDLoop
		TEST	[Vendor], 1
		JNZ	@@GotVendorID
		MOV	[PCI_PPktFind.DeviceID], BX
		JMP	@@EatBlanks
@@GotVendorID:
		MOV	[PCI_PPktFind.VendorID], BX
		JMP	@@EatBlanks
@@ParseEnd:
		POP	DS

		ASSUME	CS:RCode, DS:RData, GS:NOTHING

		TEST	[Quiet], 1
		JNZ	@@NoHello
		Print	Hello, 0
		PrintL	Revision, 5
		PrintL	BldMsg, <SIZE BldMsg>
		PrintL	CRLF, 2
@@NoHello:
		PUSH	DS
		PUSH	OFFSET OEMHLP_Name	; device name
		PUSH	DS
		PUSH	OFFSET OEMHLP_Handle	; file handle
		PUSH	DS
		PUSH	OFFSET Action		; action taken
		PUSH	0			; high order half of file size
		PUSH	0			; low order half of file size
		PUSH	FA_SYSTEM		; file attribute
		PUSH	OPN_EXIST		; fail if it does not exist
		PUSH	OPN_RDWRACC		; get read/write access
		PUSH	0			; reserved
		PUSH	0			; reserved
		CALL	DOSOPEN 		; get a handle for OEMHLP$

		MOV	BX, OFFSET RMName
		MOV	DI, OFFSET RMIDC
		MOV	DL, DevHlp_AttachDD
		CALL	[DevHlp]
		MOV	AX, [RMIDC.R3DS]
		MOV	[(WORD RMIDC.R3Entry)+2], AX

		PUSH	DS
		PUSH	OFFSET RMhDriver
		PUSH	DS
		PUSH	OFFSET DriverStruc
		MOV	AX, RMCREATEDRIVER
		CALL	RMR3
		ADD	SP, 8

		MOV	DI, OFFSET PCI_InfoPkt
		MOV	SI, OFFSET PCI_ParamPkt
		CALL	PCIBios 		; get PCI BIOS info

		MOV	AL, [(PCIDataR PCI_InfoPkt).Result]
		OR	AL, AL
		JNZ	@@PCIError

	IFE NOHARDWARE

		LEA	DI, [Function]
		MOV	SI, OFFSET PCI_PPktFind
		CALL	PCIBios 		; search for RuskPCI

		MOV	AL, [(PCIDataR DI).Result]
		OR	AL, AL
		JNZ	@@PCIError

		LEA	SI, [Function]
		MOV	[Function], PCI_FUNC_READ
		MOV	[ConfigReg], 3Ch
		MOV	[ConfigRegSize], 1
		LEA	DI, [(ConfigData) - 1]
		CALL	PCIBios
		MOV	AX, [WORD ConfigData]
		MOV	[IRQ], AX

		MOV	[ConfigReg], 14h	; Config regs (IO space)
		MOV	[ConfigRegSize], 2
		LEA	DI, [(ConfigData) - 1]
		CALL	PCIBios
		MOV	AX, [WORD ConfigData]
		AND	AX, NOT 1
		MOV	[IOBase], AX

		MOV	[ConfigReg], 18h	; bridge base (mem space)
		MOV	[ConfigRegSize], 4
		LEA	DI, [(MemBase) - 1]
		CALL	PCIBios
		AND	[MemBase], NOT 15

		MOV	DX, [IOBase]
		ADD	DX, IntControlReg + 1
		MOV	[IntReg], DX
		MOV	AX, 0
		OUT	DX, AX			; disable interrupts

		MOV	AX, OFFSET RskInt
		MOV	BX, [IRQ]
		MOV	DX, DevHlp_SetIRQ + (1 SHL 8)
		CALL	[DevHlp]
	ELSE

		MOV	[IRQ], 9
		XOR	EAX, EAX
		SHL	AX, 9
		ADD	AX, 8100h
		MOV	[IOBase], AX
		MOV	EAX, 0E8000000h
		MOV	[MemBase], EAX
	ENDIF

		MOV	AX, [IOBase]
		MOV	[IOResource.BaseIOPort], AX
		PUSH	DS
		PUSH	OFFSET IOResource
		PUSH	DS
		PUSH	OFFSET hResourceIO
		PUSH	[RMhDriver]
		MOV	AX, RMALLOCRESOURCE
		CALL	RMR3
		ADD	SP, 12

		MOV	AX, [IRQ]
		MOV	[IrqResource.IRQLevel], AX
		PUSH	DS
		PUSH	OFFSET IrqResource
		PUSH	DS
		PUSH	OFFSET hResourceIrq
		PUSH	[RMhDriver]
		MOV	AX, RMALLOCRESOURCE
		CALL	RMR3
		ADD	SP, 12

		MOV	EAX, [MemBase]
		MOV	[MemResource.MemBase], EAX
		PUSH	DS
		PUSH	OFFSET MemResource
		PUSH	DS
		PUSH	OFFSET hResourceMem
		PUSH	[RMhDriver]
		MOV	AX, RMALLOCRESOURCE
		CALL	RMR3
		ADD	SP, 12

		PUSH	DS
		PUSH	OFFSET Resources
		PUSH	LARGE 0
		PUSH	DS
		PUSH	OFFSET AdapterStruc
		PUSH	DS
		PUSH	OFFSET RMhAdapter
		PUSH	[RMhDriver]
		MOV	AX, RMCREATEADAPTER
		CALL	RMR3
		ADD	SP, 5*4

		PUSH	LARGE 0
		PUSH	[RMhAdapter]
		PUSH	DS
		PUSH	OFFSET DeviceStruc
		PUSH	DS
		PUSH	OFFSET RMhDevice
		PUSH	[RMhDriver]
		MOV	AX, RMCREATEDEVICE
		CALL	RMR3
		ADD	SP, 5*4

		CALL	ReadEEProm		; get EEProm configuration data

		XOR	AX, AX
@@PCIError:
		PUSH	AX
		PUSH	[OEMHLP_Handle] 	; file handle
		CALL	DOSCLOSE		; done with OEMHLP$
		POP	AX

		LES	BX, [BP]
		MOV	[(RqPInitE ES:BX).Units], 0
		OR	AL,AL
		JNZ	@@InitFail

		MOV	[(RqPInitE ES:BX).CodeEnd], OFFSET ResCodeEnd - 1
		MOV	[(RqPInitE ES:BX).DataEnd], OFFSET ResDataEnd - 1
		MOV	AX, RPDONE

		RET
@@InitFail:
		MOV	[(RqPInitE ES:BX).CodeEnd], 0
		MOV	[(RqPInitE ES:BX).DataEnd], 0
		MOV	AX, RPDONE + RPERR + ERROR_INIT_FAIL_NONCRITICAL
		RET
ENDP		Init

ENDS		RCode

		END

; $Header:   P:/ruskpci/driver/rskpci.asm   1.5   10 Sep 2002 10:13:22   EN  $
;
; $Log:   P:/ruskpci/driver/rskpci.asm  $
;  
;     Rev 1.5   10 Sep 2002 10:13:22   EN
;  - change: add 'skip' operation
;
;     Rev 1.4	29 Oct 2001 14:03:50   EN
;  -new: read/write to DSP bus
;
;     Rev 1.3	14 Sep 2001 13:55:16   EN
;  - don't lock job list, add error traces
;
;     Rev 1.2	06 Sep 2001 11:30:02   EN
;  - fix calculation of DMA descriptor buffer size
;
;     Rev 1.1	05 Sep 2001 10:40:30   EN
;  - minor fixes and additions
;
;     Rev 1.0	24 Aug 2001 14:15:14   EN
;  Initial revision.
;

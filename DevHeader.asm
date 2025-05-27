	page	,132

;**************************************************************************
;*
;* SOURCE FILE NAME = S506SEGS.ASM
;*
;*		      S506 CODE/DATA segment declarations.
;*
;****************************************************************************

		INCLUDE devhdr.inc

EXTRN		DOSIODELAYCNT:ABS
EXTRN		DOS32FLATDS:ABS

DDHeader	SEGMENT DWORD PUBLIC 'DATA'
		PUBLIC	_DDHeader

_DDHeader	DD	-1
		DW	DEVLEV_3 + DEV_CHAR_DEV + DEV_30
		DW	_Strategy1Handler
		DW	_IDCHandler
		DB	"IBMS506$"
		DW	0
		DW	0
		DW	0
		DW	0
		DD	DEV_ADAPTER_DD + DEV_INITCOMPLETE + DEV_IOCTL2
		DW	0

DDHeader	ENDS


LIBDATA 	SEGMENT DWORD PUBLIC 'DATA'
LIBDATA 	ENDS

		PUBLIC	_Delay500

_DATA		SEGMENT DWORD PUBLIC 'DATA'

/* make the calibrated 500ns delay value available to the driver code */

_Delay500	DW	DOSIODELAYCNT

_DATA		ENDS

CONST		SEGMENT DWORD PUBLIC 'CONST'
CONST		ENDS

_BSS		SEGMENT DWORD PUBLIC 'BSS'
_BSS		ENDS

_TEXT		SEGMENT DWORD PUBLIC 'CODE'
		ASSUME CS:_TEXT, DS:_DATA

/* the strategy 1 handler code must be located in the default code segment */

EXTRN		_Strategy1Handler:NEAR
EXTRN		_IDCHandler:NEAR

_TEXT		ENDS

		PUBLIC	_DSSel
		PUBLIC	_CSSel
		PUBLIC	_FlatSel

Code		SEGMENT DWORD PUBLIC 'CODE'
		.386p
		MOV	EBP, [ESP]	; retrieve RetIP
		INT 3			; honey pot trap
		INT 3
		INT 3

		.286p

/* make the default data and code segment selectors available in all contexts */
/* make the kernel flat 4GB data selector available in all contexts	      */

_DSSel		DW	SEG _DATA
_CSSel		DW	SEG _TEXT
_FlatSel	DW	DOS32FLATDS

Code		ENDS

LIBCODE 	SEGMENT DWORD PUBLIC 'CODE'
LIBCODE 	ENDS

EndCode 	SEGMENT BYTE PUBLIC 'CODE'

		ASSUME	CS:EndCode
		PUBLIC	__CodeEnd
__CodeEnd:
EndCode 	ENDS


RMCode		SEGMENT DWORD PUBLIC 'CODE'
		.386p
		MOV	EBP, [ESP]	; retrieve RetIP
		INT 3			; honey pot trap
		INT 3
		INT 3

		.286p
RMCode		ENDS

CSCode		SEGMENT DWORD PUBLIC 'CODE'
CSCode		ENDS

/* the default data segment consists of several sections */

DGROUP		GROUP	DDHeader, CONST, _BSS, LIBDATA, _DATA

/* the default code segment consists of several sections */

StaticGroup	GROUP	Code, LIBCODE, _TEXT, InitCode, EndCode

/* there is another code segment */

StaticGroup2	GROUP	RMCode, CSCode,

		END

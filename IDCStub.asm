_DATA		SEGMENT DWORD PUBLIC 'DATA'
_DATA		ENDS

CONST		SEGMENT DWORD PUBLIC 'CONST'
CONST		ENDS

_BSS		SEGMENT DWORD PUBLIC 'BSS'
_BSS		ENDS

_TEXT		SEGMENT DWORD PUBLIC 'CODE'
		ASSUME CS:_TEXT, DS:_DATA

		EXTRN  _IDCHandler:NEAR/FAR
		.386p

; IDC stub to C handler routines
;
; IDC handler entry points need to be located in the
; default code segment!

; VOID NEAR/FAR _cdecl IDCHandler (/* any argument type */)

		PUBLIC	_IDCStub
_IDCStub	PROC FAR

		PUSH ES
		PUSH DS
		PUSHAD

; handle arguments here to match the handler function prototype

		MOV	DS, CS:[_DSSel]
		CALL	_IDCHandler

		POPAD
		POP  DS
		POP  ES
		RET

_IDCStub	ENDP

		.286p

_DSSel		DW	SEG _DATA

_TEXT		ENDS

		END

_DATA		SEGMENT DWORD PUBLIC 'DATA'
_DATA		ENDS

CONST		SEGMENT DWORD PUBLIC 'CONST'
CONST		ENDS

_BSS		SEGMENT DWORD PUBLIC 'BSS'
_BSS		ENDS

_TEXT		SEGMENT DWORD PUBLIC 'CODE'
		ASSUME CS:_TEXT, DS:_DATA

		EXTRN  _CxtHookHandler:NEAR
		.386p

; context hook callback stub to C handler routines
;
 context hook handler entry points need to be located in the
; default code segment!

; VOID NEAR/FAR _cdecl CtxHookHandler (/* any argument type */)

		PUBLIC	_CtxHookStub
_CtxHookStub	PROC FAR

		PUSH ES
		PUSH DS
		PUSHAD

		PUSH	EAX	; stack frame is compatible to any data type
		MOV	DS, CS:[_DSSel]
		CALL	_CtxHookHandler
		ADD	SP, 4

		POPAD
		POP  DS
		POP  ES
		RET

_CtxHookStub	ENDP

		.286p

_DSSel		DW	SEG _DATA

_TEXT		ENDS

		END

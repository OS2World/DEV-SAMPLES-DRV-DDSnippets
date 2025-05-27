/**************************************************************************
 *
 * SOURCE FILE NAME = S506RTE.C
 *
 * DESCRIPTION : Strategy 1 Entry Point
 *
 ****************************************************************************/

#include "devcmd.h"
#include "reqpkt.h"

#pragma optimize(OPTIMIZE, on)

#define StatusError(pRPH,ErrorCode) (pRPH)->Status = (ErrorCode)

/*------------------------------------------------------------------------*/
/* OS/2 Strategy Request Router 					  */
/* ---------------------------- 					  */
/* This routine receives the OS/2 Packets.				  */
/*------------------------------------------------------------------------*/

VOID FAR _cdecl Strategy1Handler (void)
{
  PRPH pRPH;		       /* Pointer to RPH (Request Packet Header)      */

  _asm {
    mov word ptr pRPH[0], bx	   /*  pRPH is initialized to		      */
    mov word ptr pRPH[2], es	   /*  ES:BX passed from the kernel	      */
  }

  StatusError (pRPH, STATUS_DONE);  // default to done

  switch (pRPH->Cmd) {
    case CMDInitBase :
      DriverInit ((PRPINITIN) pRPH);
      break;

    case CMDInitComplete : {
      UCHAR noAPM;

      InitComplete = 1;

      // attach to APM

      if (!(noAPM = APMAttach())) {

	// if attached, register for suspend and resume

	APMRegister ((PAPMHANDLER)APMEventHandler,
		     APM_NOTIFYSETPWR | APM_NOTIFYNORMRESUME |
		     APM_NOTIFYCRITRESUME | APM_NOTIFYSTBYRESUME,
		     0);

	// prepare driver to deal with APM notifications

      } else {

	// prepare driver to deal with APM events (like suspend) even if it
	// doesn't see any notifications about them!

      }

      // processing PCCards is save now
      // if supported PCCards are inserted configure them just as same as
      // at an CardInsertion event

      if (PCCardPresent) {
	USHORT Socket;

	for (Socket = 0; Socket < NumSockets; Socket++) {
	  if (CSConfigure (Socket) == 0) {
	    CardInsertion (Socket);
	  }
	}
      }
      break;
    }

    case CMDShutdown : {

      // this is called before (function code 0) and after (function code 1)
      // shutdown of all filesystems

      if (((PRPSAVERESTORE)pRPH)->FuncCode) {

	// put devices to sleep

      }
      break;
    }

    default :
      StatusError (pRPH, STATUS_DONE | STATUS_ERR_UNKCMD);
  }
}



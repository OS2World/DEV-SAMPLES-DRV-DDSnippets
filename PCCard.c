#include "CardServices.h"
#include "CardServStub.h"
#include <PCMCIA.H>

#define YEAR  2002
#define MONTH 8
#define DAY   19
#define VERSION 0x150

#pragma optimize(OPTIMIZE, on)

CHAR	 PCMCIA_DDName[9] = "PCMCIA$ ";
IDCTABLE CSIDC = { 0 };
USHORT	 CSHandle = 0;
CHAR	 PCCardPresent = 0;
UCHAR	 NumSockets = 0;
ULONG	 CSCtxHook = 0;
USHORT	 CSIrqAvail = 0xDEB8;

struct CI_Info CIInfo = {
  0, sizeof (CIInfo),
  ATB_IOClient | ATB_Insert4Sharable | ATB_Insert4Exclusive, VERSION, 0,
  ((YEAR - 1980) << 9) | (MONTH << 5) | DAY,
  offsetof (struct CI_Info, CI_Name), sizeof (CIInfo.CI_Name),
  offsetof (struct CI_Info, CI_Vendor), sizeof (CIInfo.CI_Vendor),
  "DaniS506 EIDE Driver",
  "Copyright Daniela Engert 2002, all rights reserved"
};


/* Attach to PCMCIA.SYS
 * check for presence of card service
 * allocate a context hook for deferred processing of events
 * register driver with card services
 * scan sockets for PCCards already inserted (no card insertion events generated!)
 */

USHORT NEAR PCMCIASetup()
{
  if (SELECTOROF(CSIDC.ProtIDCEntry) != NULL)
    return (FALSE);	/* already initialized */

  if (!DevHelp_AttachDD (PCMCIA_DDName, (NPBYTE)&CSIDC) &&
      CardServicesPresent() &&
      !DevHelp_AllocateCtxHook ((NPFN)&CSHookHandler, (PULONG)&CSCtxHook) &&
      !CSRegisterClient()) {
    int Socket;

    for (Socket = 0; Socket < NumSockets; Socket++)
      if (0 == CSCardPresent (Socket)) {
	PCCardPresent |= (1 << Socket);
      }
    return (FALSE);
  }
  return (TRUE);
}

/****************************************************************************
 *
 * FUNCTION NAME = CSCallbackHandler
 *
 * DESCRIPTION	 = This function services card insertion and card removal
 *		   callback events from card services
 *
 ****************************************************************************/

VOID NEAR _cdecl CSCallbackHandler (USHORT Socket, USHORT Event, PUCHAR Buffer)
{
  /*
  ** release resources if a card removal event occurs
  ** acquire resources if card insertion event occurs
  */

  switch (Event) {
    case CARD_REMOVAL:
      if (!InitComplete) return;
      PCCardPresent &= ~(1 << Socket);
      CSUnconfigure (Socket);
      CardRemoval (Socket);
      return;

    case CARD_INSERTION:
      if (!InitComplete) return;

      if (CSConfigure (Socket) == 0) {
	PCCardPresent |= (1 << Socket);
	CardInsertion (Socket);
      }
      return;

    case CLIENTINFO: {
      struct CI_Info FAR *CIin = (struct CI_Info FAR *)Buffer;

      if (CIin->CI_Attributes == 0) {
	  CIInfo.CI_MaxLength = CIin->CI_MaxLength;

	if (CIInfo.CI_InfoLen > CIInfo.CI_MaxLength)
	  CIInfo.CI_InfoLen = CIInfo.CI_MaxLength;

	memcpy (CIin, (PUCHAR)&CIInfo, CIInfo.CI_InfoLen);
      }
      return;
    }

    /* handle other events if required */
  }
}

USHORT NEAR CardRemoval (USHORT Socket) {

  /* handle removal of a PCCard
   * - detach hardware from the supporting driver code
   * - release resources allocated to the hardware being removed
   * - prepare driver to handle calls directed at removed hardware *gratiously*
   */

  return (0);
}

USHORT NEAR CardInsertion (USHORT Socket) {

  /* handle insertion of a PCCard (part I)
   * - allocate resources to the hardware being inserted
   * - make a *short* test if hardware is supported and healthy
   * - release resources if test fails
   */

  if (test passed) {

    /* defer full initialization (make take long) */

    DevHelp_ArmCtxHook (Socket, CSCtxHook);

  } else {

    /* release resources */

    CSUnconfigure (Socket);
  }
  return (0);
}

USHORT NEAR _fastcall CardInsertionDeferred (USHORT Socket) {

  /* handle insertion of a PCCard (part II)
   * - full initialization of the newly inserted PCCard
   * - release resources if initialization fails
   */

  if (initialized) {

   /* attach hardware to the supporting driver code */

  } else {

    /* release resources */

    CSUnconfigure (Socket);
  }
  return (0);
}

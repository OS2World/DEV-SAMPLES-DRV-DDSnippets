/**************************************************************************
 *
 * SOURCE FILE NAME = CS.C
 *
 ****************************************************************************/

#include "CardServices.h"
#include "CardServStub.h"
#include "pcmcia.h"

#pragma optimize(OPTIMIZE, on)

static struct GTD_P GetTuple = { 0 };

/****************************************************************************
 *
 * FUNCTION NAME = CardServicesPresent
 *
 * DESCRIPTION	 = This function determines if card services is present on the
 *		   system.
 *		   The function returns the value TRUE if card services is
 *		   present.  Otherwise, the value FALSE is returned.
 *
 ****************************************************************************/

BOOL FAR CardServicesPresent (void)
{
  struct GCSI_P CSInfo;
  IDC_PACKET	idc;

  /* initialize signature field - set maximum length for vendor
  ** string - get card services info
  */

  *(PUSHORT)CSInfo.GCSI_Signature = 0;
  CSInfo.GCSI_VStrLen = 1;

  idc.function	 = GetCardServicesInfo;
  idc.pointer	 = NULL;
  idc.arglength  = sizeof (CSInfo);
  idc.argpointer = &CSInfo;

  if (CallCardServices (&idc) != SUCCESS) return (FALSE);

  /* store number of sockets */
  NumSockets	    = CSInfo.GCSI_Count;
  CIInfo.CI_CSLevel = CSInfo.GCSI_CSLevel;

  /* if card services are present then return true  */
  return (*(PUSHORT)CSInfo.GCSI_Signature == 0x5343);  // "CS"
}

/****************************************************************************
 *
 * FUNCTION NAME = CSCardPresent
 *
 * DESCRIPTION	 = This function determines if a card is present in a
 *		   particular socket.
 *		   The parameter 'Socket' contains the socket to be checked
 *		   for a card.
 *		   The function returns the value TRUE if a card is present.
 *		   Otherwise, the function returns the value FALSE.
 *
 ****************************************************************************/

USHORT FAR CSCardPresent (USHORT Socket)
{
  USHORT       rc;
  struct GS_P  Status;
  struct GCI_P GetConfig;

  Status.GS_Socket = Socket;

  if ((rc = CallCS (GetStatus, &Status, sizeof (Status))) != 0) return (rc);

  /* check if card present bit is set */
  if (!(Status.GS_CardState & 0x0080)) return (NO_CARD);

  GetConfig.GCI_Socket = Socket;
  if ((rc = CallCS (GetConfigurationInfo, &GetConfig, sizeof (GetConfig))) != 0) return (rc);

  clrmem ((NPCH)&GetTuple.GTD_Attributes, sizeof (GetTuple) - sizeof (GetTuple.GTD_Socket));
  GetTuple.GTD_Socket = Socket;

  switch (GetConfig.GCI_FuncCode) {
    case TPLFID_FixedDisk: GetTuple.GTD_DesiredTuple = CISTPL_FUNCE; break;
    case 0xFF:
    case 0:		   GetTuple.GTD_DesiredTuple = CISTPL_VERS_1; break;
    default:		   return (NO_CARD);
  }

  if ((rc = CallCS (GetFirstTuple, &GetTuple, sizeof (struct GFT_P))) != 0) return (BAD_ATTRIBUTE);

  GetTuple.GTD_TupleOffset  = 2;
  GetTuple.GTD_TupleDataMax = TUPLE_LEN;
  if ((rc = CallCS (GetTupleData, &GetTuple, sizeof (GetTuple))) != 0) return (BAD_ATTRIBUTE);

  rc = NO_CARD;
  switch (GetTuple.GTD_DesiredTuple) {
    case CISTPL_FUNCE:
      if ((GetTuple.GTD_TupleDataLen >= 3) &&
	  (GetTuple.GTD_TupleData[0] == 0x01))
	rc = 0;
      break;
    case CISTPL_VERS_1: {
      PCHAR p = (PCHAR)(GetTuple.GTD_TupleData);
      PCHAR q = p + GetTuple.GTD_TupleDataLen;
      p += 2;
      while (*(p++) != 0);
      while ((p < q) && (*p != 0)) {
	USHORT u = *(PUSHORT)(p + 0) & ~0x2020;
	UCHAR  v = p[2] & ~0x20;
	UCHAR  w = p[3] & ~0x20;

	if (((u == 0x5441) && (v == 0x41) && ((w == 0x50) || (w < 0x40))) || // ATA ATAPI
	    ((u == 0x4449) && (v == 0x45) && (w < 0x40))) { // IDE
	  rc = 0;
	  break;
	}
	p++;
      }
    }
  }
  return (rc);
}

/****************************************************************************
 *
 * FUNCTION NAME = CSRegisterClient
 *
 * DESCRIPTION	 = This function registers as a client with card services.
 *
 * RETURN-NORMAL = 0
 *
 * RETURN-ERROR  = -1
 *
 ****************************************************************************/

struct RC_P Register;

USHORT FAR CSRegisterClient (void)
{
  USHORT     rc;
  IDC_PACKET idc;

  Register.RC_Attributes = ATB_IOClient | ATB_Insert4Sharable | ATB_Insert4Exclusive;
  Register.RC_EventMask = EM_CardDetectChange;

  idc.function	 = RegisterClient;
  idc.pointer	 = (PVOID)CSCallbackStub;
  idc.arglength  = sizeof (Register);
  idc.argpointer = &Register;

  if ((rc = CallCardServices (&idc)) != SUCCESS) return (rc);

  CSHandle = idc.handle;
  return (SUCCESS);
}

USHORT NEAR CallCS (USHORT Function, PVOID Arg, USHORT ArgLen) {
  IDC_PACKET idc;
  int rc;

  idc.handle	 = CSHandle;
  idc.function	 = Function;
  idc.pointer	 = NULL;
  idc.arglength  = ArgLen;
  idc.argpointer = Arg;
  rc = CallCardServices (&idc);
  if ((Function == GetConfigurationInfo) && idc.handle && (CSHandle != idc.handle))
    rc = BAD_HANDLE;
  return (rc);
}

USHORT NEAR TryIRQ (struct IRQ_P _far *SetIRQ, USHORT Filter) {
  USHORT rc = 1;
  USHORT IRQList = CSIrqAvail & Filter;

  if (IRQList) {
    SetIRQ->IRQ_IRQInfo2 = IRQList;

    rc = CallCS (RequestIRQ, SetIRQ, sizeof (*SetIRQ));
    if (rc && InitActive) CSIrqAvail &= ~IRQList;
  }
  return (rc);
}

USHORT NEAR TryIO (struct IO_P _far *SetIO, USHORT Port) {
  SetIO->IO_BasePort1 = Port;
  SetIO->IO_BasePort2 = Port + 0x0E;
  return (CallCS (RequestIO, SetIO, sizeof (*SetIO)));
}

USHORT FAR CSConfigure (NPA npA, USHORT Socket) {
  USHORT rc;
  int i, j;
  char haveIRQ = FALSE, haveIO = FALSE;
  struct GCI_P GetConfig;
  struct IO_P  SetIO;
  struct IRQ_P SetIRQ;
  typedef struct CfgTblIdx {
    unsigned int Entry:6;
    unsigned int isDefault:1;
    unsigned int hasIFByte:1;
  } *pCfgTblIdx;
  UCHAR Option, SkipOption = 0xFF;

  haveIRQ = FALSE;
  haveIO = FALSE;

  if (!CSIrqAvail) return (1);
  if ((rc = CSCardPresent (Socket)) != 0) return (rc);

  fclrmem (&GetConfig, sizeof (GetConfig));
  GetConfig.GCI_Socket = Socket;
  CallCS (GetConfigurationInfo, &GetConfig, sizeof (GetConfig));

  clrmem (&GetTuple.GTD_Attributes, sizeof (GetTuple) - sizeof (GetTuple.GTD_Socket));
  GetTuple.GTD_Socket = Socket;
  GetTuple.GTD_DesiredTuple = CISTPL_CFTABLE_ENTRY;
  rc = CallCS (GetFirstTuple, &GetTuple, sizeof (struct GFT_P));

  while (!rc) {
    NPCH p;
    struct Features {
      unsigned int Power:2;
      unsigned int Timing:1;
      unsigned int IO:1;
      unsigned int IRQ:1;
      unsigned int Mem:2;
      unsigned int Ext:1;
    } *pFeatures;

    GetTuple.GTD_TupleOffset  = 2;
    GetTuple.GTD_TupleDataMax = TUPLE_LEN;
    CallCS (GetTupleData, &GetTuple, sizeof (GetTuple));
    p = (PUCHAR)GetTuple.GTD_TupleData;

    Option = ((pCfgTblIdx)p)->Entry;
    if (Option == SkipOption) goto nextConfig;
    if (((pCfgTblIdx)p)->hasIFByte) {
      p++;
      if ((*p & 0x0F) != 1) {
	SkipOption = Option;
	goto nextConfig;
      }
    }
    p++;
    pFeatures = (struct Features *)p++;
    if (pFeatures->Mem) {
      SkipOption = Option;
      goto nextConfig;
    }
    for (i = pFeatures->Power; i > 0; i--) {
      for (j = *(p++); j > 0; j >>= 1)
	if (j & 1) while (*(p++) & 0x80);
    }
    if (pFeatures->Timing) {
      i = ~ *(p++);
      if (i & 0x03) { while (*(p++) & 0x80); }
      if (i & 0x1C) { while (*(p++) & 0x80); }
      if (i & 0xE0) { while (*(p++) & 0x80); }
    }
    if (pFeatures->IO) {
      struct IOSpace {
	unsigned int AddrLines:5;
	unsigned int Bus8:1;
	unsigned int Bus16:1;
	unsigned int Range:1;
      } *pIOSpace;
      int SizeLen, SizeAdr, Port[2], Len[2];

      if (haveIO) {
	CallCS (ReleaseIO, &SetIO, sizeof (SetIO));
	haveIO = FALSE;
      }
      pIOSpace = (struct IOSpace *)p++;

      SetIO.IO_Socket = Socket;
      SetIO.IO_Attributes1 = ATB_DataPathWidth;
      SetIO.IO_NumPorts1 = 16;
      SetIO.IO_Attributes2 = ATB_DataPathWidth;
      SetIO.IO_NumPorts2 = 0;
      SetIO.IO_IOAddrLines = 16;

      if (pIOSpace->Range) {
	i = *(p++);
	SizeLen = (1U << ((i >> 6) & 3)) >> 1;
	SizeAdr = (1U << ((i >> 4) & 3)) >> 1;

	SetIO.IO_BasePort1 = *(NPUSHORT)p;
	p += SizeAdr;

	if (!(i & 0x0F)) {
	  SetIO.IO_BasePort2 = SetIO.IO_BasePort1 + 0x0E;
	} else {
	  SetIO.IO_NumPorts1 = 8;
	  SetIO.IO_NumPorts2 = 2;

	  SetIO.IO_NumPorts1 = 1 + *p;
	  p += SizeLen;

	  SetIO.IO_BasePort2 = *(NPUSHORT)p;
	  p += SizeAdr;

	  SetIO.IO_NumPorts2 = 1 + *p;
	}
	p += SizeLen;

	rc = CallCS (RequestIO, &SetIO, sizeof (SetIO));
      } else {

	if (npA->BasePortpref)	 // try preferred port if available
	  rc = TryIO (&SetIO, npA->BasePortpref);
	else
	  rc = 1;

	if (rc) {
	  j = 1 << pIOSpace->AddrLines;

	  for (i = 0x100; i != 0;) {
	    i -= j;
	    if (!(rc = TryIO (&SetIO, i + 0x100))) break;
	    if (!(rc = TryIO (&SetIO, i + 0x300))) break;
	    if (!(rc = TryIO (&SetIO, i + 0x200))) break;
	  }
	}
      }
      haveIO = rc == 0;
    }

    if (pFeatures->IRQ) {
      struct IRQ {
	unsigned int IRQLevel:4;
	unsigned int Mask:1;
	unsigned int Level:1;
	unsigned int Pulse:1;
	unsigned int Share:1;
      } *pIRQ;

      if (!haveIRQ) {
	USHORT IRQList;

	pIRQ = (struct IRQ *)p++;
	pIRQ->Mask = 1;
	pIRQ->IRQLevel = 0;

	SetIRQ.IRQ_Socket = Socket;
	SetIRQ.IRQ_Attributes = ATB_Exclusive;
	SetIRQ.IRQ_IRQInfo1 = *(NPCH)pIRQ;

	if (npA->IRQprefLevel)	  // try preferred IRQ if available
	  haveIRQ = !TryIRQ (&SetIRQ, 1 << npA->IRQprefLevel);

	if (!haveIRQ)		  // try highest IRQs available
	  haveIRQ = !TryIRQ (&SetIRQ, 0xF000);

	if (!haveIRQ)		  // try high IRQs available
	  haveIRQ = !TryIRQ (&SetIRQ, 0xFF00);

	if (!haveIRQ) { 	  // try all IRQs available
	  haveIRQ = !TryIRQ (&SetIRQ, 0xFFFF);
	  if (!haveIRQ && InitActive) break;
	}
      }
    }

    if (haveIO && haveIRQ) break;

  nextConfig:
    GetTuple.GTD_TupleOffset = 0;
    rc = CallCS (GetNextTuple, &GetTuple, sizeof (struct GFT_P));
  }

  if (haveIO && haveIRQ && SetIO.IO_BasePort1 && SetIO.IO_BasePort2 && SetIRQ.IRQ_AssignedIRQ) {
    GetConfig.GCI_Attributes = ATB_EIRQ;
    GetConfig.GCI_IntType = IT_MEMandIO;
    GetConfig.GCI_Option = 0x40 | Option;
    GetConfig.GCI_Present &= CB_Option;

    rc = CallCS (RequestConfiguration, &GetConfig, sizeof (struct RCF_P));
    if (rc == 0) {
      clrmem (&(npA->CSConfig), sizeof (GetConfig));
      npA->CSConfig.GCI_Socket = Socket;
      CallCS (GetConfigurationInfo, &(npA->CSConfig), sizeof (GetConfig));

      npA->BasePort   = npA->CSConfig.GCI_BasePort1;
      npA->StatusPort = npA->CSConfig.GCI_BasePort2;
      if (!npA->StatusPort) npA->StatusPort = npA->BasePort + 0x0E;
      npA->IRQLevel   = npA->CSConfig.GCI_AssignedIRQ;
      npA->Socket     = Socket;

      return (0);
    }
  }
  npA->BasePort   = 0;
  npA->StatusPort = 0;
  npA->IRQLevel   = -1;
  npA->Socket	   = -1;

  if (haveIO) {
    CallCS (ReleaseIO, &SetIO, sizeof (SetIO));
    haveIO = FALSE;
  }

  if (haveIRQ) {
    CallCS (ReleaseIRQ, &SetIRQ, sizeof (SetIRQ));
    haveIRQ = FALSE;
  }

  return (rc);
}

VOID FAR CSReconfigure (NPA npA) {
  CallCS (ReleaseConfiguration, &(npA->CSConfig), sizeof (struct RLC_P));

  RehookIRQ (npA);
  DevHelp_ProcBlock ((ULONG)(PVOID)&CSReconfigure, 31UL, 0);

  CallCS (RequestConfiguration, &(npA->CSConfig), sizeof (struct RCF_P));
}

USHORT FAR CSUnconfigure (NPA npA) {
  USHORT rc;
  struct IO_P  RelIO;
  struct RIRQ_P RelIRQ;

  RelIO.IO_Socket = npA->Socket;
  RelIO.IO_BasePort1 = npA->CSConfig.GCI_BasePort1;
  if ((RelIO.IO_BasePort2 = npA->CSConfig.GCI_BasePort2) != 0) {
    RelIO.IO_NumPorts1 = 8;
    RelIO.IO_NumPorts2 = 2;
  } else {
    RelIO.IO_NumPorts1 = 16;
    RelIO.IO_NumPorts2 = 0;
  }
  RelIO.IO_Attributes1 = 0;
  RelIO.IO_Attributes2 = 0;
  RelIO.IO_IOAddrLines = 16;

  CallCS (ReleaseConfiguration, &(npA->CSConfig), sizeof (struct RLC_P));
  CallCS (ReleaseIO, &RelIO, sizeof (RelIO));

  RelIRQ.RIRQ_Socket = npA->Socket;
  RelIRQ.RIRQ_Attributes = ATB_Exclusive;
  RelIRQ.RIRQ_AssignedIRQ = npA->IRQLevel;

  CallCS (ReleaseIRQ, &RelIRQ, sizeof (RelIRQ));
  UnhookIRQ (npA);

  npA->BasePort   = 0;
  npA->StatusPort = 0;
  npA->IRQLevel   = -1;
  npA->Socket	  = -1;
}

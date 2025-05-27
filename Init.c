#define YEAR  2002
#define MONTH 9
#define DAY   15

PFN		Device_Help    = NULL;
PGINFOSEG	pGlobal        = NULL;
PDDD_PARM_LIST	pDDDParmList   = NULL;
ULONG		ppDataSeg      = 0L;
HDRIVER 	hDriver        = 0L;
UCHAR		TimerPool[TIMER_POOL_SIZE] = { 0 };

UCHAR  DrvrNameTxt[]	 = "DANIS506.ADD";
USHORT DrvrNameSize	 = sizeof (DrvrNameTxt);
UCHAR  DrvrDescriptTxt[] = "DMA Adapter Driver for ST506/IDE DASD";
UCHAR  VendorNameTxt[]	 = "Dani";

DRIVERSTRUCT DriverStruct =
{
   DrvrNameTxt, 			     /* DrvrName		*/
   DrvrDescriptTxt,			     /* DrvrDescript		*/
   VendorNameTxt,			     /* VendorName		*/
   CMVERSION_MAJOR,			     /* MajorVer		*/
   CMVERSION_MINOR,			     /* MinorVer		*/
   YEAR,MONTH,DAY,			     /* Date			*/
   0,					     /* DrvrFlags		*/
   DRT_ADDDM,				     /* DrvrType		*/
   DRS_ADD,				     /* DrvrSubType		*/
   NULL 				     /* DrvrCallback		*/
};

VOID NEAR DriverInit (PRPINITIN pRPH)
  PMACHINE_CONFIG_INFO pMCHI;
  USHORT	       OSVersion;
  PSZ		       pCmdLine;
  PSEL		       p;

  /* store away the device helper entry point */

  Device_Help = pRPH->DevHlpEP;

  /* get pointer to global info segment */

  DevHelp_GetDOSVar (DHGETDOSV_SYSINFOSEG, 0, (PPVOID)&p);
  SELECTOROF (pGlobal) = *p;
  OSVersion = pGlobal->uchMajorVersion * 10 + pGlobal->uchMinorVersion;

  /* get pointer to device driver parameters */

  pDDDParmList = (PDDD_PARM_LIST)((PRPINITIN)pRPH)->InitArgs;

  /* get physical address of default data segment */

  DevHelp_VirtToPhys (MAKEP (DSSel, 0), (PULONG)&ppDataSeg);

  /* get pointer to machine config info */

  pMCHI = MAKEP (SELECTOROF(pDDD_Parm_List), (USHORT)pDDD_Parm_List->machine_config_table);

  /* check machine type */

  if (pMCHI->BusInfo & BUSINFO_MCA) {
    goto S506_Deinstall;
  }

  /* get pointer to driver command line and parse it */

  pCmdLine = MAKEP (SELECTOROF(pDDD_Parm_List), (USHORT)pDDD_Parm_List->cmd_line_args);
  ParseCmdLine (pCmdLine);

  /* Allocate driver handle */

  RMCreateDriver (&DriverStruct, &hDriver);

  /* allocate timer poor and initialize it */
  ADD_InitTimer (TimerPool, sizeof (TimerPool));

  /* if Merlin or later get the PnP detected devices */

  if (OSVersion > 230) {
    FindDetected (FALSE);
    FindDetected (TRUE);
  }

  /* attach to PCCard subsystem and initialize related stuff */

  SetupPCMCIA();

  /* Initialize driver	*/
  /* allocate resources */

S506_Install:

  /* everything is fine so far			       */
  /* ajust sizes of the default data and code segement */
  /* assign allocated resources to the driver	       */
  /* stay resident				       */

#define pRPO ((PRPINITOUT)pRPH)

  pRPO->CodeEnd    = (USHORT) &_CodeEnd;
  pRPO->DataEnd    = (USHORT) MemTop - 1;
  pRPO->rph.Status = STDON;

  AssignRMResources();

  rc = FALSE;

S506_Deinstall:

  /* if an error has happened: */
  /* deinstall timer handler   */
  /* deallocate resources      */
  /* destroy RM entities       */
  /* fail silently and unload  */

  if (rc) {
    ADD_DeInstallTimer();
    DeallocateRMResources();
    RMDestroyDriver (hDriver);

    pRPO->CodeEnd    = 0;
    pRPO->DataEnd    = 0;
    pRPO->rph.Status = STDON + ERROR_I24_QUIET_INIT_FAIL;
  }
}


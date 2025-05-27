/* required by Resource Manager Library */

PFN    RM_Help	 = NULL;
PFN    RM_Help0  = NULL;
PFN    RM_Help3  = NULL;
ULONG  RMFlags	 = 0;

/* some driver wide values */

HDRIVER    hDriver		     = 0L;
HWRESOURCE HWResource[MAX_RESOURCES] = { 0 };

/* Used for scanning the RM device database */

CHAR   IDEPnPId[]    = "PNP0600";
UCHAR  PnPwork[1024] = {0};

/*----------------------------------------------*/
/* Adapter Description				*/
/*----------------------------------------------*/
UCHAR AdaptDescriptNameTxt[] = "IDE_0 (E)IDE Controller";

ADAPTERSTRUCT AdapterStruct =
{
  AdaptDescriptNameTxt, 	     /* AdaptDescriptName; */
  AS_16MB_ADDRESS_LIMIT,	     /* AdaptFlags;	   */
  AS_BASE_MSD,			     /* BaseType;	   */
  AS_SUB_IDE,			     /* SubType;	   */
  AS_INTF_GENERIC,		     /* InterfaceType;	   */
  AS_HOSTBUS_ISA,		     /* HostBusType;	   */
  AS_BUSWIDTH_16BIT,		     /* HostBusWidth;	   */
  NULL, 			     /* pAdjunctList;	   */
  NULL				     /* reserved	   */
};

/*----------------------------------------------*/
/* Device Description				*/
/*----------------------------------------------*/
UCHAR DevDescriptNameTxt[] = "HD_0 Hard Drive";

DEVICESTRUCT DevStruct =
{
   DevDescriptNameTxt,	 /* DevDescriptName; */
   DS_FIXED_LOGICALNAME, /* DevFlags;	  */
   DS_TYPE_DISK 	 /* DevFlags;	     */
};

/*-------------------------------*/
/* AllocAdapterResources()	 */
/*				 */
/*-------------------------------*/

USHORT FAR AllocAdapterResources (PTRTYPE_INSTANCE npInst)
{
  USHORT	 rc = 0;
  RESOURCESTRUCT Resource;
  NPHRESOURCE	 nphRes = HWResource;

  memset (npResourceList, sizeof (npInst->ResourceBuf), 0);
  nphRes = &(npResourceList->hResource[0]);

  /*-----------------------*/
  /* AllocIRQResource	   */
  /*-----------------------*/

  Resource.ResourceType 	     = RS_TYPE_IRQ;
  Resource.IRQResource.IRQLevel      = npInst->IRQLevel;
  Resource.IRQResource.PCIIrqPin     = npInst->Flags & INTSHARED ?
					 RS_PCI_INT_A : RS_PCI_INT_NONE;
  Resource.IRQResource.IRQFlags      = npInst->Flags & INTSHARED ?
					 RS_IRQ_SHARED : RS_IRQ_MULTIPLEXED;

  if (rc = RMAllocResource (hDriver, nphRes, &Resource)) {
    npInst->Status = ATS_ALLOC_IRQ_FAILED;
    goto AllocAdapterResourcesExit;
  }
  nphRes++;

  /*----------------------*/
  /* AllocIOResource	  */
  /*----------------------*/

  Resource.ResourceType 	     = RS_TYPE_IO;
  Resource.IOResource.BaseIOPort     = npInst->BasePort;
  Resource.IOResource.NumIOPorts     = 8;
  Resource.IOResource.IOFlags	     = RS_IO_MULTIPLEXED;
  Resource.IOResource.IOAddressLines = 16;

  if (rc = RMAllocResource (hDriver, nphRes, &Resource)) {
    npInst->Status = ATS_ALLOC_IO_FAILED;
    goto AllocAdapterResourcesExit;
  }
  nphRes++;

  /*----------------------*/
  /* AllocIOResource	  */
  /*----------------------*/

  Resource.IOResource.BaseIOPort = npInst->StatusPort;
  Resource.IOResource.NumIOPorts = 1;

  if (rc = RMAllocResource (hDriver, nphRes, &Resource)) {
    npInst->Status = ATS_ALLOC_IO_FAILED;
    goto AllocAdapterResourcesExit;
  }
  nphRes++;

  if (npInst->BM_BaseAddress != 0) {
    /*----------------------*/
    /* AllocIOResource	    */
    /*----------------------*/

    Resource.IOResource.BaseIOPort = npInst->BM_BaseAddress;
    Resource.IOResource.NumIOPorts = npInst->BMSize;
    Resource.IOResource.IOFlags    = RS_IO_MULTIPLEXED;

    if (rc = RMAllocResource (hDriver, nphRes, &Resource)) {
      npInst->Status = ATS_ALLOC_IO_FAILED;
      goto AllocAdapterResourcesExit;
    }
    nphRes++;
  }

  if (npInst->MemBase != 0) {
    /*----------------------*/
    /* AllocIOResource	    */
    /*----------------------*/

    Resource.ResourceType	  = RS_TYPE_MEM;
    Resource.MEMResource.MemBase  = npInst->MemBase;
    Resource.MEMResource.MemSize  = npInst->MemSize;
    Resource.MEMResource.MemFlags = RS_MEM_SHARED;

    if (!RMAllocResource (hDriver, nphRes, &Resource))
      nphRes++;
  }

  npResourceList->NumResource = nphRes - &(npResourceList->hResource[0]);
  return (rc);

AllocAdapterResourcesExit:

  DeallocAdapterResources (npInst);
  return (rc);
}

/*-------------------------------*/
/*				 */
/* DeallocAdapterResources()	 */
/*				 */
/*-------------------------------*/
VOID FAR DeallocAdapterResources (PTRTYPE_INSTANCE npInst)
{
  UCHAR i;
  NPHRESOURCE nphRes;

  nphRes = &(npResourceList->hResource[0]);
  for (i = MAX_RESOURCES; i > 0; i--) {
    if (*nphRes) {
      RMDeallocResource (hDriver, *nphRes);
      *(nphRes++) = 0;
    }
  }
}

/*-------------------------------*/
/*				 */
/* AssignResources()		 */
/*				 */
/*-------------------------------*/
VOID FAR AssignResources()
{
  PTRTYPE_INSTANCE npInst;
  UCHAR    i, j, k;
  ADJUNCT  Adjunct;
  HDEVICE  hDevice;
  HADAPTER hAdapter;

  Adjunct.pNextAdj  = 0;
  Adjunct.AdjLength = sizeof (ADJUNCT);
  Adjunct.AdjType   = ADJ_ADD_UNIT;
  Adjunct.Add_Unit.ADDHandle = ADDHandle;

  for (i = 0; i < numInstances; i++) {
    npInst = InstancePtrs[i];

    /*---------------------------------------------------*/
    /* increment controller number in adapter string:	 */
    /* Original String is "IDE_0 ST506/IDE Controller"   */
    /*---------------------------------------------------*/

    AdapterStruct.AdaptDescriptName[4] = '0' + i;

    /*
    ** There is adapter object information available to
    ** identify individual PCI adapters.  Only a global is
    ** is available to disern other bus types.	Default host
    ** host bus type is AS_HOSTBUS_ISA.
    */
    if (npInst->isPCI)
      AdapterStruct.HostBusType = AS_HOSTBUS_PCI;
    else if (npInst->isPCCard)
      AdapterStruct.HostBusType = AS_HOSTBUS_PCMCIA;
    else if (npInst->isEISA)
      AdapterStruct.HostBusType = AS_HOSTBUS_EISA;
    else
      AdapterStruct.HostBusType = AS_HOSTBUS_ISA;

    RMCreateAdapter (hDriver, &hAdapter, &AdapterStruct,
		     NULL, (PAHRESOURCE)(npInst->ResourceBuf));

    for (j = 0; j < npInst->numUnits; j++) {
      Adjunct.Add_Unit.UnitHandle = npUnit->UnitHandle;
      DevStruct.pAdjunctList = &Adjunct;

      /*-----------------------------------------*/
      /* Copy Device Description to local buffer */
      /*-----------------------------------------*/

      memcpy (ScratchBuf, DevDescriptNameTxt, sizeof (DevDescriptNameTxt));

      /*---------------------------------------------------*/
      /* increment device number in buffer string:	   */
      /* Original String is "HD_0 Hard Drive"              */
      /*---------------------------------------------------*/

      ScratchBuf[3] += j;

      /*--------------------------------------------------*/
      /* if a model number is exists, copy the portion of */
      /* string that will fit in the local buffer	  */
      /*--------------------------------------------------*/

      strncpy (ScratchBuf + 5, npUnit->ModelNum, 42 - 5);

      DevStruct.DevDescriptName = ScratchBuf;
      DevStruct.DevFlags = (npUnit->Flags & REMOVABLE) ?
			    DS_REMOVEABLE_MEDIA : DS_FIXED_LOGICALNAME;

      RMCreateDevice (hDriver, &hDevice, &DevStruct, hAdapter, NULL);
    }
  }
}


/*-------------------------------*/
/*				 */
/* FindDetected()		 */
/*				 */
/* Scan the device database	 */
/* for supported devices	 */
/*				 */
/*-------------------------------*/

VOID FAR FindDetected (BOOL SearchCompatibleId)
{
  ULONG PnPId = 0, CompatibleId = 0;
  NPHANDLELIST npHandleList = (NPHANDLELIST)ScratchBuf;
  USHORT i, j;
  NPRM_GETNODE_DATA npNode = (NPRM_GETNODE_DATA)&PnPwork;

  // convert ID to binary
  if (!RMConvertID (SearchCompatibleID ? &CompatibleId : &PnPId,
		    IDEPnPId,
		    RM_CONVERT_TO_ID)) {
    // clear handle counts
    npHandleList->cHandles = 0; 		    // force count to 0
    npHandleList->cMaxHandles = 1 + MAX_ADAPTERS;   // tell how much room is in the buffer
    // search for devices with this ID
    RMDevIDToHandleList (RM_IDTYPE_EISA,	    // specific format of device ID fields
			 PnPId,
			 NULL,
			 CompatibleId,
			 NULL,
			 NULL,
			 CompatableID ? SEARCH_ID_COMPATIBLEID :
					SEARCH_ID_DEVICEID,
						    // device ID fields
			 HANDLE_CURRENT_DETECTED,   // search the CURRENT detected tree
			 npHandleList); 	    // place for output
    // if there were some devices found
    for (i = 0; i < npHandleList->cHandles; i++) {
      // get size of data for node space
      npNode->RMNodeSize = sizeof (PnPwork);
      // Get the node data now
      if (!RMGetNodeInfo (npHandleList->Handles[i], npNode, sizeof (PnPwork))) {
	// update the Adapter Table with this node
	if (npNode->RMNode.pResourceList)
	  UpdateATTable (npNode->RMNode.pResourceList);
      }
    }
  }
}

/*-------------------------------*/
/*				 */
/* LocateATEntry()		 */
/*				 */
/*-------------------------------*/
PTRTYPE_INSTANCE FAR LocateATEntry (USHORT BasePort)
{
  PTRTYPE_INSTANCE npInst = InstanceTable;
  USHORT i;

  for (i = 0; i < MAX_ADAPTERS; i++, npInst++) {
    // if the ports match
    if ((BasePort == npInst->BasePort) && !(npInst->Flags & PCMCIA)) {
      // we've found the entry
      break;
    } else {
      // if port didn't match, is this entry disabled
      // and not defined??
      if ((npInst->Flags & DISABLED) &&
	  ((npInst->BasePort == 0) || (npInst->BasePort == 0xFFFF))) {
	// found the place to put this one
	break;
      }
    }
  }
  // searched table, no free slots, oops
  if (i == MAX_ADAPTERS)
    npInst=NULL;

  return npInst;
}

/*-------------------------------*/
/*				 */
/* UpdateATTable()		 */
/*				 */
/*-------------------------------*/
VOID FAR UpdateATTable (PRESOURCELIST pResourceList)
{
  PTRTYPE_INSTANCE npInst;
  USHORT i, j;

  // loop thru the resource structures
  for (j = 0; j < pResourceList->Count; j++) {
    // if this is an IO Structure with an 8 port usage
    // (status port is one port usage)
    if (pResourceList->Resource[j].ResourceType == RS_TYPE_IO &&
	pResourceList->Resource[j].IOResource.NumIOPorts == 8) {
      // find AT entry that matches, or a new one
      if (npInst = LocateATEntry (pResourceList->Resource[j].IOResource.BaseIOPort)) {

	// turn off disabled flag if unused and not forced disabled
	if (npInst->BasePort == 0) {
	  npInst->Flags &= ~DISABLED;
	  npInst->Flags |=  BIOSDEFAULTS;
	}

	// start at the top of the resource list again
	for (i = 0; i < pResourceList->Count; i++) {
	  switch (pResourceList->Resource[i].ResourceType) {
	    case RS_TYPE_IO:
	      // set base port address
	      if (pResourceList->Resource[i].IOResource.NumIOPorts == 8)
		npInst->BasePort = pResourceList->Resource[i].IOResource.BaseIOPort;
	      else
		// set Device Control port address
		npInst->StatusPort = pResourceList->Resource[i].IOResource.BaseIOPort;
	      break;

	    case RS_TYPE_IRQ:
	      // set IRQ level
	      npInst->IRQLevel = pResourceList->Resource[i].IRQResource.IRQLevel;
	      break;

	    default:
	      // shouldn't be any other resources
	      break;
	  }
	}
      }
      // done handling this entry
      break;
    }
  }
}


/**************************************************************************
 *
 * SOURCE FILE NAME = S506OEMI.C
 *
 ****************************************************************************/

#include "OemHlp.h"

#pragma optimize(OPTIMIZE, on)

CHAR	 OEMHLP_DDName[9] = "OEMHLP$ ";
IDCTABLE OemHlpIDC	  = { 0 };

UCHAR FAR SetupOEMHlp()
{
  PCI_PARM_FIND_DEV PCIParmPkt;
  PCI_DATA	    PCIDataPkt;
  RP_GENIOCTL	    IOCtlRP;

  if ((SELECTOROF(OemHlpIDC.ProtIDCEntry) != NULL) &&
      (OemHlpIDC.ProtIDC_DS != NULL))
    return (0);     /* alread initialized */

  /* Setup Global OEMHlp Variables */
  if (DevHelp_AttachDD (OEMHLP_DDName, (NPBYTE)&OemHlpIDC))
    return (1);     /* Couldn't find OEMHLP's IDC */

  if ((SELECTOROF(OemHlpIDC.ProtIDCEntry) == NULL) ||
      (OemHlpIDC.ProtIDC_DS == NULL))
    return (1);     /* Bad Entry Point or Data Segment */

  /* Setup Parm Packet */
  PCIParmPkt.PCISubFunc = PCI_GET_BIOS_INFO;

  /* Setup IOCTL Request Packet */
  IOCtlRP.ParmPacket = (PUCHAR)&PCIParmPkt;
  IOCtlRP.DataPacket = (PUCHAR)&PCIDataPkt;

  if (CallOEMHlp ((PRPH)&IOCtlRP)) return (1);
  if (PCIDataPkt.bReturn != PCI_SUCCESSFUL) return (1);

  PCIHWMechanism = PCIDataPkt.Data_Bios_Info.HWMech & 3;
  return (0);
}


/**************************************************************************
 *
 * SOURCE FILE NAME = S506APM.C
 *
 * DESCRIPTION : Adapter Driver APM callback routines
 *
 ****************************************************************************/

#include <APMCALLS.H>

#pragma optimize(OPTIMIZE, on)

/*------------------------------------*/
/* APM Suspend/Resume Support	      */
/* Reinitializes adapters and units   */
/* following a resume event.	      */
/*------------------------------------*/

USHORT FAR _cdecl APMEventHandler (PAPMEVENT Event)
{
  USHORT Message = (USHORT)Event->ulParm1;
  USHORT PwrState;

  if (Message == APM_SETPWRSTATE) {

    PowerState = PwrState = (USHORT)(Event->ulParm2 >> 16);
    if (PwrState != APM_PWRSTATEREADY)
      return (APMSuspend (PwrState));

  } else if ((Message == APM_NORMRESUMEEVENT) ||
	     (Message == APM_CRITRESUMEEVENT) ||
	     (Message == APM_STBYRESUMEEVENT)) {
    PowerState = 0;
    return (APMResume());

  }
  return 0;
}

USHORT NEAR APMSuspend (USHORT PowerState)
{
  if (PowerState == APM_PWRSTATESUSPEND) {

  /* prepare hardware and software for suspend */

  }
  return 0;
}

USHORT NEAR APMResume()
{
  /* restore/reinitialize hardware and software after resume */

  return 0;
}


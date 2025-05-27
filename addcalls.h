/**************************************************************************
 *
 * SOURCE FILE NAME =  ADDCALLS.H
 *
 * DESCRIPTIVE NAME =  C Function Prototypes/Structures for services
 *		       contained in ADDCALLS.LIB
 *
 * Purpose:   ADDCALLS.LIB provides the following services:
 *
 *		   - C Callable Timer Manager
 *
 ****************************************************************************/

/*
** Timer Data Structure
*/

typedef struct _ADD_TIMER_DATA	 {	      /* ADDT */

  ULONG        Interval;		      /* Interval value in millisecond */
  ULONG        BackupInterval;		      /* Interval value for backup     */
  PFN	       NotifyEntry;		      /* Notify address 	       */
  PVOID        Parm_1;			      /* parameter which ADD wants     */
  PVOID        Parm_2;			      /* parameter which ADD wants     */
} ADD_TIMER_DATA;


/*
** Timer Pool Structure
*/

typedef struct _ADD_TIMER_POOL	 {	      /* ADDT */

  USHORT	 MTick; 		      /* Milliseconds per timer tick   */
  ADD_TIMER_DATA TimerData[1];		      /* Interval value for backup     */
} ADD_TIMER_POOL;

/*
** If the caller wants "n" timer elements, the size of data pool is
**
**    sizeof(ADD_TIMER_POOL) + (n-1)*(ADD_TIMER_DATA).
**
*/

/*
** ADD Common Services
*/


BOOL APIENTRY f_ADD_InitTimer(PBYTE, USHORT);
BOOL APIENTRY f_ADD_DeInstallTimer(VOID);
BOOL APIENTRY f_ADD_StartTimerMS(PUSHORT, ULONG, PFN, PVOID, PVOID);
BOOL APIENTRY f_ADD_CancelTimer(USHORT);

BOOL PASCAL NEAR ADD_InitTimer(PBYTE, USHORT);
BOOL PASCAL NEAR ADD_DeInstallTimer(VOID);
BOOL PASCAL NEAR ADD_StartTimerMS(PUSHORT, ULONG, PFN, PVOID, PVOID);
BOOL PASCAL NEAR ADD_CancelTimer(USHORT);

/*
** ADD Common Services R / C
*/

#define ADD_SUCCESS   0
#define ADD_ERROR     1



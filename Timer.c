/**************************************************************************
 *
 * SOURCE FILE NAME = S506TIMR.C
 *
 * DESCRIPTION : Adapter Driver timer driven entry points.
 ****************************************************************************/

#include "addcalls.h"

#pragma optimize(OPTIMIZE, on)

#define NUM_TIMERS 2
#define TIMER_POOL_SIZE (sizeof (ADD_TIMER_POOL) +			  \
			 (NUM_TIMERS - 1) * sizeof (ADD_TIMER_DATA))

USHORT IRQTimerHandle  = 0;
USHORT TickerHandle    = 0;

UCHAR  TimerPool[TIMER_POOL_SIZE] = { 0 };

//
// IRQTimer()
//
// Expected interrupt timeout routine.
//

VOID FAR _cdecl IRQTimer (USHORT TimerHandle, ULONG Parameter1, ULONG Parameter2)
{
  cancelling the timer makes it an one-shot timer!

  ADD_CancelTimer (TimerHandle);

  do something useful here
}


// free running timer with a given call interval

VOID FAR _cdecl Ticker (USHORT TimerHandle, ULONG Parameter1, ULONG Parameter2)
{
  do something useful here
}

{
  /* Initialize timer pool */

  ADD_InitTimer (TimerPool, sizeof (TimerPool));

  /* start a timer to call function 'Ticker' with arguments arg1 and arg2 */
  /* repeatedly after each TICKER_INTERVAL milliseconds 		  */

  ADD_StartTimerMS (&TickerHandle, TICKER_INTERVAL, (PFN)Ticker, arg1, arg2);

  /* stop all timer processing and destroy timer pool */

  ADD_DeInstallTimer();
}


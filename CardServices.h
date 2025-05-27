/**************************************************************************
 *
 * SOURCE FILE NAME = CS.H
 *
 * DESCRIPTIVE NAME = Card Services Header File
 *
 ****************************************************************************/

/*
 * constant definitions
 */

#ifndef SUCCESS
#define SUCCESS 0
#endif

/*
 * type definitions
 */

typedef struct _IDC_PACKET {
  UCHAR  function;
  USHORT handle;
  PVOID  pointer;
  USHORT arglength;
  PVOID  argpointer;
} IDC_PACKET;


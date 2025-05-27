_VENDOR  = DANI
_VERSION = 1.5
_FIXLEVEL = 0á

# import TIMESTAMP from environment (created by some script) or define it here

TIMESTAMP=17.9.2002 12:57:21	   Nachtigall

FILEVER = @^#$(_VENDOR):$(_VERSION)^#@^#^#1^#^# $(TIMESTAMP)::
	  ::$(_FIXLEVEL)::@@
CFLAGS = $(CFLAGS) /DVERSION=\"$(_VERSION).$(_FIXLEVEL)\"

# the generated DESCRIPTION will be
#
# DESCRIPTION "@#DANI:1.5#@##1## 17.9.2002 12:57:21       Nachtigall::
#	       ::0á::@@  Adapter Driver for ST506/IDE DASD"
#
# resulting in a BldLevel output like this:
#
# Signature:	   @#DANI:1.5#@##1## 17.9.2002 12:57:21       Nachtigall::
#		   ::0á::@@  Adapter Driver for ST506/IDE DASD
# Vendor:	   DANI
# Revision:	   1.05
# Date/Time:	   17.9.2002 12:57:21
# Build Machine:   Nachtigall
# File Version:    1.5
# Description:	   Adapter Driver for ST506/IDE DASD
#

danis506.add:  $(OBJS) $(LIBS) $(HDR) makefile
	Rem Create DEF file <<$(@B).def
LIBRARY $(@B)

DESCRIPTION "$(FILEVER)  Adapter Driver for ST506/IDE DASD"

PROTMODE

SEGMENTS
 DDHeader	CLASS 'DATA'
 LIBDATA	CLASS 'DATA'
 _DATA		CLASS 'DATA'
 CONST		CLASS 'CONST'
 _BSS		CLASS 'BSS'
 'Code'         CLASS 'CODE' IOPL
 LIBCODE	CLASS 'CODE' IOPL
 _TEXT		CLASS 'CODE' IOPL
 InitCode	CLASS 'CODE' IOPL
 EndCode	CLASS 'CODE' IOPL
 Messages	CLASS 'MSGS' IOPL SWAPPABLE
 CSCode 	CLASS 'CODE' IOPL SWAPPABLE
 FCode		CLASS 'CODE' IOPL SWAPPABLE
 RMCode 	CLASS 'CODE' IOPL SWAPPABLE

<<keep

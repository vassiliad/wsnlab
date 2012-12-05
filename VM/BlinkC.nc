// $Id: BlinkC.nc,v 1.5 2008/06/26 03:38:26 regehr Exp $

/*									tab:4
 * "Copyright (c) 2000-2005 The Regents of the University  of California.  
 * All rights reserved.
 *
 * Permission to use, copy, modify, and distribute this software and its
 * documentation for any purpose, without fee, and without written agreement is
 * hereby granted, provided that the above copyright notice, the following
 * two paragraphs and the author appear in all copies of this software.
 * 
 * IN NO EVENT SHALL THE UNIVERSITY OF CALIFORNIA BE LIABLE TO ANY PARTY FOR
 * DIRECT, INDIRECT, SPECIAL, INCIDENTAL, OR CONSEQUENTIAL DAMAGES ARISING OUT
 * OF THE USE OF THIS SOFTWARE AND ITS DOCUMENTATION, EVEN IF THE UNIVERSITY OF
 * CALIFORNIA HAS BEEN ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 * 
 * THE UNIVERSITY OF CALIFORNIA SPECIFICALLY DISCLAIMS ANY WARRANTIES,
 * INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY
 * AND FITNESS FOR A PARTICULAR PURPOSE.  THE SOFTWARE PROVIDED HEREUNDER IS
 * ON AN "AS IS" BASIS, AND THE UNIVERSITY OF CALIFORNIA HAS NO OBLIGATION TO
 * PROVIDE MAINTENANCE, SUPPORT, UPDATES, ENHANCEMENTS, OR MODIFICATIONS."
 *
 * Copyright (c) 2002-2003 Intel Corporation
 * All rights reserved.
 *
 * This file is distributed under the terms in the attached INTEL-LICENSE     
 * file. If you do not find these files, copies can be found by writing to
 * Intel Research Berkeley, 2150 Shattuck Avenue, Suite 1300, Berkeley, CA, 
 * 94704.  Attention:  Intel License Inquiry.
 */

/**
 * Implementation for Blink application.  Toggle the red LED when a
 * Timer fires.
 **/

#include "Timer.h"

#define BROADCAST_PERIOD 1000


module BlinkC @safe()
{
  uses interface WSNVMC as VM;
	uses interface Boot;
	uses interface Leds;
}
implementation
{
	nx_uint8_t app1[] = { 0x0b,
                        0x04,
                        0x04,
                        0xC1 ,0xE0 ,0x03 ,0x00,
                        0xE0 ,0x03, 0xC0 , 0x00 };

  nx_uint8_t app2[] = { 0x17,
                        0x06, 
                        0x0E,
                        0xC1,	0x11, 0x01, 0xE0, 0x03, 0x00,

                        0xA1, 0x07, 0xC0, 0x11, 0x00, 0xE0, 0x07, 0x00, 
                        0xC1, 0x11, 0x01, 0xE0, 0x03, 0x00};
	
	nx_uint8_t app3[] = {  0x14,
												 0x03, 
												 0x0E, 
												 0xE0, 0x05, 0x00, 
												 0xD1, 0x12, 0x32, 0x42, 0x01, 0x92, 0x04, 0xC0, 0xB0, 0x02, 0xC1, 0xE0, 0x05, 0x00 };
	
	event void Boot.booted()
	{
		call VM.upload_binary(app2, 2);
		call VM.upload_binary(app2, 1);
		call VM.upload_binary(app3, 0);

	}

  event void VM.application_done(uint8_t id)
  {

  }
}


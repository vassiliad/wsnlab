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
  uses interface SplitControl;
	uses interface Boot;
	uses interface Leds;
  uses interface WSNSerialC as Serial;
}
implementation
{
  
  event void SplitControl.startDone(error_t err)
  {
    uint8_t id;

    if ( err != SUCCESS ) {
      call SplitControl.start();
      return;
    }
    id = call Serial.get_buf();
    call Serial.print_str(id, "Test: ");
    call Serial.print_int(id, id);
    call Serial.print_buf(id);

    id = call Serial.get_buf();
    call Serial.print_str(id, "Test: ");
    call Serial.print_int(id, id);
    call Serial.print_buf(id);

    id = call Serial.get_buf();
    call Serial.print_str(id, "Test: ");
    call Serial.print_int(id, id);
    call Serial.print_buf(id);

    id = call Serial.get_buf();
    call Serial.print_str(id, "Test: ");
    call Serial.print_int(id, id);
    call Serial.print_buf(id);
  }

  event void SplitControl.stopDone(error_t err)
  {
  }

  event void Serial.receive(void* payload, uint8_t len)
  {
  }

	event void Boot.booted()
	{
    call SplitControl.start();
	}
}


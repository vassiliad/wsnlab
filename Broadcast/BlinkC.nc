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
	uses interface Timer<TMilli> as Timer;
	uses interface SplitControl as BroadcastControl;
	uses interface WSNBroadcastC as Broadcast;
	uses interface AMPacket;
	uses interface Boot;
	uses interface Leds;
}
implementation
{
	event void Boot.booted()
	{
		call BroadcastControl.start();
	}
	event void BroadcastControl.stopDone(error_t err) { }


	event void Broadcast.receive(nx_uint8_t *data, uint8_t len, uint16_t source, uint16_t last_hop, uint8_t hops)
	{
		uint16_t msg = *((nx_uint16_t*)data);

		dbg("BlinkC", "Received: %d from %d\n", msg, source);


		switch( last_hop ) {
			case 0:
				call Leds.led0Toggle();
				break;
			case 1:
				call Leds.led1Toggle();
				break;
			case 2:
				call Leds.led2Toggle();
				break;
		}
	}

	event void BroadcastControl.startDone(error_t err)
	{
		if ( err == SUCCESS ) {
			// call Timer.startPeriodic(BROADCAST_PERIOD);
		}
	}

	event void Timer.fired()
	{
		nx_uint16_t me;
    me = call AMPacket.address();
  
		call Broadcast.send( &me, sizeof(uint16_t));

	}

}


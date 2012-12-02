#include "Timer.h"

module BlinkC @safe()
{
	uses interface Timer<TMilli> as Timer;
	uses interface SplitControl as QueryControl;
	uses interface WSNQueryC as Query;
	uses interface AMPacket;
	uses interface Boot;
	uses interface Leds;
}
implementation
{
	enum OPTIONS { Period=15, Lifetime=15 };

	event void Boot.booted()
	{
		call QueryControl.start();
	}

	event void QueryControl.stopDone(error_t err)
	{
	
	}

	event void QueryControl.startDone(error_t err)
	{
		if ( err == SUCCESS) {
			if ( TOS_NODE_ID%10 == 0 ) {
        call Timer.startOneShot(Lifetime*70000);
				call Query.query(Period, Lifetime);
			} else {
			}
		} else {
			call QueryControl.start();
		}
	}

	event void Timer.fired()
	{
    exit(0);
	}
  
  task void report_value() {
     call Query.query_new_sense(TOS_NODE_ID);
  }

	event error_t Query.query_sense()
	{
    if ( TOS_NODE_ID%10 == 0 )
      return FAIL;

    post report_value();
		return SUCCESS;
	}


	event	void Query.query_result(uint16_t value, uint16_t source)
	{
		dbg("BlinkC", "Result: %d from %d\n", value, source);
	}

}


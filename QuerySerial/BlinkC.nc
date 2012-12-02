#include "Timer.h"

module BlinkC @safe()
{
	uses interface Timer<TMilli> as Timer;
	uses interface SplitControl as QueryControl;
	uses interface WSNQueryC as Query;
	uses interface AMPacket;
	uses interface Boot;

  uses interface AMSend as SSend;
  uses interface Receive as SRecv;
  uses interface SplitControl as SControl;
  uses interface Read<uint16_t> as Sensor;

  uses interface Leds;
}
implementation
{
	enum OPTIONS { Period=10, Lifetime=11, MaxMsgQueue=40, MsgSize=5 };
  
  typedef nx_struct {
    nx_uint8_t period;
    nx_uint16_t lifetime;
  } nx_period_lifetime_t;

  uint8_t msgs = 0;
  uint8_t msgs_start = 0;
  nx_uint16_t msgs_queue[MaxMsgQueue][MsgSize];
  message_t p;

  void queue_msg(uint16_t source, uint16_t value, uint8_t in_packet);
  void queue_print();

  task void dummySignal()
  {
    call Query.query_new_sense(12);
  }

  void queue_msg(uint16_t source, uint16_t value, uint8_t in_packet) 
  {
    nx_uint16_t *m;

    if ( msgs < MaxMsgQueue ) {
      m = msgs_queue[( msgs_start+msgs ) % MaxMsgQueue];
      m[0] = source;
      m[1] = value;
      m[2] = in_packet;
      msgs++;
    }

    queue_print();
  }

  void queue_print()
  {
    nx_uint16_t *msg;
    nx_uint8_t  *msg2;

    if ( msgs == 0 )
      return;

    msg = (nx_uint16_t*) call SSend.getPayload(&p, MsgSize);
    msg2 = (nx_uint8_t*)(msg)+4;
    
    msg[0] = msgs_queue[msgs_start][0];
    msg[1] = msgs_queue[msgs_start][1];
    msg2[0] = ((nx_uint8_t*)(msgs_queue[msgs_start]))[4];
    

    call SSend.send(AM_BROADCAST_ADDR, &p, MsgSize);
  }
  
	event void Boot.booted()
	{
		call QueryControl.start();
    call SControl.start();
	}

	event void QueryControl.stopDone(error_t err)
	{
	
	}

	event void QueryControl.startDone(error_t err)
	{
		if ( err != SUCCESS) {
			call QueryControl.start();

		}
	}
  
  event void SControl.stopDone(error_t err) {
    
  }

  event void SControl.startDone(error_t err) {
    if ( err != SUCCESS )
      call SControl.start();
  }

	event void Timer.fired()
	{
	}
  
  event void Sensor.readDone( error_t err,uint16_t data)
  {
    call Query.query_new_sense(data);
  }

	event error_t Query.query_sense()
	{
    if ( call Sensor.read() == SUCCESS ) {
      call Leds.led2Toggle();
    }

    // post dummySignal();
		return SUCCESS;
	}


	event	void Query.query_result(uint16_t value, uint16_t source, uint8_t in_packet)
	{
    call Leds.led1Toggle();
    queue_msg(source, value, in_packet);
    dbg("BlinkC", "Result: %d from %d in packet: %d\n", value, source, in_packet);
	}
  
  event void SSend.sendDone(message_t* bufPtr, error_t error) {
    msgs_start++;
    msgs--;

    msgs_start = msgs_start % MaxMsgQueue;

    if ( msgs )
      queue_print();
  }

  event message_t *SRecv.receive(message_t* msg, void* payload, uint8_t len) {
    nx_period_lifetime_t *pl = (nx_period_lifetime_t*) payload;

    if ( len != sizeof(nx_period_lifetime_t) )
      return msg;
    
    call Query.query(pl->period, pl->lifetime);
    //call Timer.startOneShot(pl->lifetime*1000+100);
    return msg;
  }
}


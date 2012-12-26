module WSNSerialM
{
  provides interface WSNSerialC;
  provides interface SplitControl;

  uses interface AMSend as SSend;
  uses interface Receive as SRecv;
  uses interface SplitControl as SControl;
}
implementation
{
  enum Config { QueueSize=30, MsgSize=20, Buffers=50 };
  enum BufferState { Free, Taken };

  char buffers[Buffers][MsgSize];
  uint8_t buffers_size[Buffers];

  enum BufferState buffers_state[Buffers];
  
  uint8_t busy = FALSE;
  uint8_t msgs = 0; 
  uint8_t msgs_start = 0;
  char msgs_queue[QueueSize][MsgSize];
  message_t packet;

  task void printNextMsg();

  command uint8_t WSNSerialC.get_buf()
  {
    uint8_t i;

    for ( i=0; i<Buffers; ++i )
      if ( buffers_state[i] == Free ) {
        buffers_state[i] = Taken;
        return i+1;
      }
    
    return 0;
  }
  
  void sendmsg() {
    uint8_t *p, i, len;
    nx_uint8_t* q;
      
    if ( busy == TRUE )
      return;

    if ( msgs == 0 )
      return;

    busy = TRUE;
    
    p = msgs_queue[msgs_start];

    len = strlen(p);

    msgs_start = (msgs_start+1)%QueueSize;
    msgs--;

    if ( len == 0 ) {
      busy = FALSE;
      return;
    }


    q = (nx_uint8_t*) call SSend.getPayload(&packet, len*sizeof(char));

    for (i=0; i<len; ++i )
      q[i] = p[i];

    if ( call SSend.send(AM_BROADCAST_ADDR,&packet,  len) == SUCCESS ) {
      dbg("WSNSerialM", "# %s\n", p);
    } else {
      busy = FALSE;
      dbg("WSNSerialM", "$ %s\n", p);

      if ( msgs )
        post printNextMsg();
    }

  }

  task void printNextMsg()
  {
    sendmsg(); 
  }

  command void WSNSerialC.print_buf(uint8_t id)
  {
    uint8_t i;
    uint8_t *p;
    uint8_t len;
    
    if ( id ==0 || id > Buffers )
      return;
    
    buffers_state[id-1] = Free;
    buffers_size[id-1]  = 0;
    len = strlen(buffers[id-1]);
    
    if ( len == 0 )
      return;
      
    p = msgs_queue[ (msgs+msgs_start) % QueueSize ];
    
    if ( msgs < QueueSize )
      msgs ++;
    

    for ( i=0; i < len; ++i ) 
      p[i] = buffers[id-1][i];
    p[i] = 0;
    
    post printNextMsg();
  }

  command void WSNSerialC.print_str(uint8_t id, char *str)
  {
    char *p;

    uint8_t i, steps;
    
    if ( id ==0 || id > Buffers )
      return;

    p = buffers[id-1] + buffers_size[id-1];
    
    steps = 0;
    for ( i=0; str[i]!=0; ++i, ++steps ) 
      p[i] = str[i];

    p[i] = 0;

    buffers_size[id-1] += steps;
}

  command void WSNSerialC.print_int(uint8_t id, uint8_t integer)
  {
    char *p;
    char temp[10];

    uint8_t i, j, steps;
    
    if ( id ==0 || id > Buffers )
      return;

    p = buffers[id-1] + buffers_size[id-1];

    steps = 0;
    
    if ( integer>0 ) {
      while ( integer ) {
        i = integer / 10;
        j = integer % 10;

        integer =  i;
        temp[steps++] = j+'0';
      }
    } else {
      temp[0] = '0';
      steps = 1;
    }

    for ( i=0; i<steps; ++i ) 
      p[i] = temp[steps-i-1];

    p[i] = 0;

    buffers_size[id-1] += steps;
  }


  command error_t SplitControl.start()
  {
    uint8_t i;

    for (i=0; i<Buffers; ++i ) {
      buffers_state[i] = Free ;
      buffers_size[i]  = 0;
    }

    msgs = 0;
    msgs_start = 0;

    return call SControl.start();
  }

  command error_t SplitControl.stop()
  {
    return call SControl.stop();
  }
  

  event void SControl.startDone(error_t err)
  {
    signal SplitControl.startDone(err);
  }

  event void SControl.stopDone(error_t err) {
    signal SplitControl.stopDone(err);
  }

  event void SSend.sendDone(message_t* bufPtr, error_t error) {
    busy = FALSE;

    if ( msgs )
			post printNextMsg();
  }

  event message_t *SRecv.receive(message_t* msg, void* payload, uint8_t len) {
    signal WSNSerialC.receive(payload, len);
    return msg;
  }

}


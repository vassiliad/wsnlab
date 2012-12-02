#include "message.h"

#define MAX_QUEUE 10
#define MAX_SEQ 50
#define MAX_NEIGH 5
#define MAX_NEIGH_QUEUE 8
#define WSN_SIGNATURE 0x42
#define WSN_OVERHEAD 5
#define MAX_MSG_SIZE TOSH_DATA_LENGTH-WSN_OVERHEAD

module WSNBroadcastM
{
  provides {
    interface WSNBroadcastC as Broadcast[uint8_t id];
    interface SplitControl;
  }

  uses {
    interface Random;
    interface Packet;
    interface AMPacket;
    interface AMSend;
    interface Receive as AMReceive;
    interface SplitControl as AMControl;
    interface Leds;

    interface Timer<TMilli> as TmrSend;
  }
}
implementation
{
  

  typedef struct {
    uint16_t source;
    uint8_t  seq;
    uint16_t neigh;
    uint8_t  victim; // if set to 1 can be deleted to free space
  } seq_t;

  typedef nx_struct {
    nx_uint8_t type;
    nx_uint8_t id;
    nx_uint8_t seq;
    nx_uint16_t source;
    nx_uint8_t data[MAX_MSG_SIZE];
  } broadcast_msg_t;
  
  seq_t seqs[MAX_SEQ];
  uint16_t neighs[MAX_NEIGH];
  int8_t queue_write=0, queue_read=0;
  message_t queue[MAX_QUEUE];
    
  uint8_t retransmits = 0;
  uint8_t my_seq = 0;
  uint8_t busy = FALSE;
  task void sendNextBcast();

  uint8_t seq_is_new(uint16_t neigh, uint16_t source, uint8_t seq)
  {
    uint8_t i,j, start;

    for ( i=0; i<MAX_SEQ; i++ ) {
      if ( seqs[i].source == source ) {
        if ( seqs[i].seq < seq || ( seqs[i].seq==255 && seq==0 ) /*|| ( (int16_t)seqs[i].seq - (int16_t)seq > 5) */) {
          dbg("BroadcastM", "had %d got %d set to %d for %d\n", seqs[i].seq, seq, (uint8_t)(seq), source);

          seqs[i].seq = seq;
          call Leds.led0On();

          return TRUE;
        } else {
          call Leds.led0Off();
          return FALSE;
         }
      }
    }
          call Leds.led0On();

    dbg("BroadcastM", "had %d got %d set to %d for %d\n", seqs[i].seq, seq, (uint8_t)(seq), source);
    // figure out if there's reserved space for @neigh

    for ( i=0; i<MAX_NEIGH; i++ )
      if ( neighs[i] == neigh || neighs[i] == AM_BROADCAST_ADDR )
        break;


    if ( i == MAX_NEIGH ) {
      // there is no slot reserved for @neigh nor can we make space for him
      // try to kill a victim entry first

      for ( i=0; i<MAX_SEQ; i++ )
        // we found an empty slot, use it as a victim entry
        if ( seqs[i].source == AM_BROADCAST_ADDR ) {
          seqs[i].source = source;
          seqs[i].neigh = neigh;
          seqs[i].seq = seq;
          seqs[i].victim = 1;

          return TRUE;
        }

      // No empty slots were found, make free space start with the victim entries

      for ( j= call Random.rand16()%MAX_SEQ, i=0 ; i<MAX_SEQ; j=(j+1)%MAX_SEQ, i++ )
        if ( seqs[j].victim == 1 ) {
          seqs[j].source = source;
          seqs[j].neigh = neigh;
          seqs[j].seq = seq;

          return TRUE;
        }

      // There are no victim entries either, pick a random block of seqs and take it over

      i = call Random.rand16()%MAX_NEIGH;

      neighs[i] = neigh;

      j = i * (MAX_NEIGH_QUEUE) + call Random.rand16()%(MAX_NEIGH_QUEUE);
      seqs[j].seq = seq;
      seqs[j].neigh = neigh;
      seqs[j].source = source;
      seqs[j].victim = 0;

      return TRUE;
    } else {
      neighs[i] = neigh;
      // There is space allocated for this neighbour
      start = i * (MAX_NEIGH_QUEUE);
      // Find an empty slot
      for ( j=start; j<start + (MAX_NEIGH_QUEUE); j++ )
        if ( seqs[j].source == AM_BROADCAST_ADDR ) {
          seqs[j].source = source;
          seqs[j].neigh = neigh;
          seqs[j].seq = seq;
          seqs[j].victim = 0;

          return TRUE;
        }

      // Try to find a victim
      for ( j=i*(MAX_NEIGH_QUEUE), i=0 ; i<MAX_SEQ; j=(j+1)%MAX_SEQ, i++ )
        if ( seqs[j].victim ) {
          seqs[j].source = source;
          seqs[j].neigh = neigh;
          seqs[j].seq = seq;
          seqs[j].victim = 0;

          return TRUE;
        }

      // No victims found, pick a random slot and use it
      j = call Random.rand16()%(MAX_NEIGH_QUEUE) + start;

      seqs[j].source = source;
      seqs[j].neigh = neigh;
      seqs[j].seq = seq;
      seqs[j].victim = 0;

      return TRUE;
    }
    
    return TRUE;
  }

  error_t queue_push(void *data, uint8_t len, uint8_t id, uint16_t source, uint8_t seq)
  {
    uint8_t i, *t;
    broadcast_msg_t *msg;
    
    if ( queue_write == (queue_read-1 + MAX_QUEUE) % MAX_QUEUE )
      return ESIZE;
    
    t = (uint8_t*) data;

    msg = (broadcast_msg_t*) call Packet.getPayload(queue+queue_write, len+WSN_OVERHEAD);
    call Packet.setPayloadLength(queue+queue_write, len+WSN_OVERHEAD);
    msg->type = WSN_SIGNATURE;
    msg->id = id;
    msg->source = source;
    msg->seq = seq;

    for ( i=0; i<len; i++ )
      msg->data[i] = t[i];
    
    queue_write= (queue_write+1) % MAX_QUEUE;

    if ( busy == FALSE )
      if ( queue_write == (queue_read+1) % MAX_QUEUE)
        call TmrSend.startOneShot(call Random.rand16()%250);
        
    dbg("BroadcastM","queue_push( %d, %d )\n", msg->source, len );

    return SUCCESS;
  }

  /***************************************/
  
  task void sendNextBcast()
  {
    uint16_t me = call AMPacket.address();

    if ( busy == TRUE )
      return;

    if ( queue_write == queue_read )
      return;
    // fix the size
    if ( call AMSend.send(AM_BROADCAST_ADDR, queue+queue_read, 
                     call Packet.payloadLength(queue+queue_read)) == SUCCESS ) {
      dbg("BroadcastM", "sendNextBcast() success\n");
      retransmits = 0;
      busy = TRUE;

      if ( me == ((broadcast_msg_t*) call Packet.getPayload(queue+queue_read, TOSH_DATA_LENGTH))->source )
        switch( me ) {
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
    } else {
      // need to retransmit
      dbg("BroadcastM", "sendNextBcast() failed(retransmits: %d) -- %d\n", retransmits, call Packet.payloadLength(queue+queue_read));
      if ( ++retransmits <= 3 )
        call TmrSend.startOneShot(call Random.rand16()%500);
      else
        retransmits = 0;
    }
  }

  event void TmrSend.fired()
  {
    post sendNextBcast();
  }

  command error_t SplitControl.start()
  {
    return call AMControl.start();
  }

  command error_t SplitControl.stop()
  { 
    return call AMControl.stop();
  }

  command error_t Broadcast.send[uint8_t id](void *data, uint8_t len)
  {
    uint8_t seq;

    if ( len > MAX_MSG_SIZE ) 
      return ESIZE;

    dbg("BroadcastM", "Sending %s (%d)-%d\n", (char*)data, id, call AMPacket.address());
      

    if ( my_seq == 255 )
      my_seq = 0;
    else
      my_seq++;

    seq = my_seq;
    
    return queue_push(data, len, id, call AMPacket.address(), seq);
  }


  /**************************************/
  default event void Broadcast.receive[uint8_t id](void *data, uint8_t len, uint16_t source) {}

  event void AMSend.sendDone(message_t* msg, error_t error)
  {
    dbg("BroadcastM", "AMSend.sendDone\n");
    busy = FALSE;

    if ( error == SUCCESS )
      queue_read = (queue_read + 1) % MAX_QUEUE;

    if ( queue_write != queue_read )
      call TmrSend.startOneShot(call Random.rand16()%250);
  }

  event message_t* AMReceive.receive(message_t* msg, void* payload, uint8_t len)
  {
    uint8_t i;
    broadcast_msg_t *bcast = (broadcast_msg_t*) payload;
    broadcast_msg_t temp;


    

    if ( len < WSN_OVERHEAD )
      return msg;

    if (  bcast->type != WSN_SIGNATURE )
      return msg;

    // filter my own msgs
    if ( call AMPacket.address() == bcast->source )
      return msg;
    
    if ( seq_is_new(call AMPacket.source(msg), bcast->source, bcast->seq) == FALSE )
      return msg;
    dbg("BroadcastM", "MSG: neigh(%d) src(%d) seq(%d) id(%d) len(%d)\n", call AMPacket.source(msg),
        bcast->source, bcast->seq, bcast->id, len-WSN_OVERHEAD);

    temp.source = bcast->source;
    temp.id = bcast->id;
    temp.seq = bcast->seq;
    
    for ( i=0; i<len; i++ )
      temp.data[i] = bcast->data[i];

    queue_push(bcast->data, len-WSN_OVERHEAD, bcast->id, bcast->source, bcast->seq);
    // should figure out another way
    dbg("BroadcastM", "rec_seq: %d\n", bcast->id);
    signal Broadcast.receive[temp.id](temp.data, len-WSN_OVERHEAD, temp.source);
    
    return msg;
  }

  task void signalStartDone()
  {
    signal SplitControl.startDone(SUCCESS);
  }

  event void AMControl.startDone(error_t err)
  {
    uint8_t i;
    if ( err != SUCCESS )
      return;

    for ( i=0; i<MAX_NEIGH; i++ )
      neighs[i] = AM_BROADCAST_ADDR;

    for ( i=0; i<MAX_SEQ; i++ ) {
      seqs[i].source = AM_BROADCAST_ADDR;
      seqs[i].seq = 0;
      seqs[i].victim = 0;
    }

    post signalStartDone();
  }

  event void AMControl.stopDone(error_t err)
  {
    signal SplitControl.stopDone(err);
  }
}

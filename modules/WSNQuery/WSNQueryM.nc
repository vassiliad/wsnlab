#include "wsnbroadcast.h"

module WSNQueryM
{
  uses interface Timer<TMilli> as Tick;
  uses interface Timer<TMilli> as Prop;
  uses interface WSNBroadcastC as Broadcast;
  uses interface WSNBroadcastC as Fallback;
  uses interface SplitControl as BroadcastControl;
  uses interface Random;
  uses interface AMPacket;
  uses interface Packet;
  uses interface Receive as SubRecv;
  uses interface AMSend as SubSend;
  uses interface PacketAcknowledgements;
  uses interface Leds;

  provides interface SplitControl;
  provides interface WSNQueryC as Query;
}
implementation
{
#define QUERY_MAX_RESULTS_IN_PACKET ( (WSN_MSG_SIZE-sizeof(uint16_t))/sizeof(nx_node_result_t) )
  enum CONFIG { MaxOrigins=20,MaxQueries=20, MaxRoute=200,
      SensePeriod=1000, PropPeriod=500, MaxRetransmits=3,
      MaxBuffer=50};

  typedef	struct {
    uint16_t node;
    uint16_t result;
  } node_result_t;


  typedef	nx_struct {
    nx_uint16_t node;
    nx_uint16_t result;
  } nx_node_result_t;

  typedef nx_struct {
    nx_uint16_t origin;
    nx_node_result_t nr[];
  } nx_packet_results_t;

  typedef struct {
    uint8_t  num;
    node_result_t nr[QUERY_MAX_RESULTS_IN_PACKET];
  } results_t;

  typedef struct {
    uint16_t source;		
    uint8_t  period;
    uint16_t  lifetime;
    uint16_t  ticks;
  } query_t;

  typedef struct {
    uint16_t target;
    uint16_t next;
  } route_t;

  typedef nx_struct {
    nx_uint8_t  period;
    nx_uint16_t  lifetime;
  } nx_query_request_t;

  uint16_t  origins[MaxOrigins];
  results_t results[MaxOrigins];
  uint8_t   results_num = 0;

  node_result_t recvd_results[MaxBuffer];
  uint8_t   recvd_results_start=0;
  uint8_t   recvd_results_size =0;
  
  query_t queries[MaxQueries];
  uint8_t queries_num = 0;

  route_t routes[MaxRoute];
  uint8_t routes_num = 0;

  uint8_t busy = 0;
  message_t packet;

  uint8_t retransmits = 0;
    

  error_t log_recv_result(uint16_t node, uint16_t result)
  {
    uint8_t i,j;

    for ( i = 0, j = recvd_results_start; i<recvd_results_size; ++i, j = (j+1)%MaxBuffer ) {
      if ( recvd_results[j].node == node ) {
        if ( recvd_results[j].result == result )
          return FAIL;
        else {
          recvd_results[j].result = result;
          return SUCCESS;
        }  
      }
    }
    
    if ( recvd_results_size != MaxBuffer ) {
      recvd_results_size++;
    } else {
      recvd_results_start = ( recvd_results_start +1 ) % MaxBuffer;
    }

    recvd_results[j].node = node;
    recvd_results[j].result = result;
    
    return SUCCESS;
  }
 

  error_t results_add(results_t* _results, uint16_t sensor, uint16_t value)
  {
    uint8_t i;

    for ( i=0; i<_results->num; i++ )
      if ( _results->nr[i].node == sensor ) {
        return SUCCESS;
      }

    if ( _results->num == QUERY_MAX_RESULTS_IN_PACKET )
      return ENOMEM;

    _results->nr[i].node = sensor;
    _results->nr[i].result = value;
    _results->num = _results->num +1;

    return SUCCESS;
  }


  error_t results_log(uint16_t origin, uint16_t sensor, uint16_t value )
  {
    uint8_t o = 0;

    
    // See if there are any results for origin

    for ( ; o< results_num; o++ )
      if ( origins[o] == origin )
        // append the new results
        if ( results_add(results+o, sensor, value) == SUCCESS ) {
          dbg("QueryM_v","Loggged (s: %d, r: %d, o: %d)\n",
              sensor, value, origin);
          return SUCCESS;
        }
    
/*
    for ( o =0; o<results_num; o++ ) {
      if ( origins[o] == origin ) {
        return results_add(results+o, sensor, value);
      }
    } */

    if ( o < MaxOrigins ) {
      origins[o] = origin;
      if ( results_add(results+o, sensor, value) == SUCCESS ) {
        results_num++;
        dbg("QueryM_v","Loggged (s: %d, r: %d, o: %d)\n",
            sensor, value, origin);
        return SUCCESS;
      }
    }
    dbg("BlinkC", "%d) Failure to log (o: %d, s: %d, r: %d)\n",
        
        origin, sensor, value);
    return ENOMEM;
 }

  uint16_t route_get(uint16_t target)
  {
    uint8_t i;

    for ( i = 0; i < routes_num; i++ )
      if ( routes[i].target == target ) {
        return routes[i].next;
      }

    return AM_BROADCAST_ADDR;
  }

  void route_rem(uint16_t next_hop) {
    uint8_t i;

    for (i=0; i<routes_num; ) {
      if ( routes[i].next == next_hop ) {
        routes[i] = routes[routes_num-1];
        routes_num--;
        continue;
      }
        
      i++;
    }
  }


  void route_add(uint16_t target, uint16_t next_hop) {
    uint8_t i;

    for (i=0; i<routes_num; i++ )
      if ( routes[i].target == target )
        break;

    if ( i < MaxRoute )
      routes_num++;
    else
      i = (uint8_t)(call Random.rand16()%MaxRoute);

    routes[i].target = target;
    routes[i].next   = next_hop;
  }

  void query_add(uint16_t source, uint8_t period, uint16_t lifetime)
  {
    uint8_t i, ticks, _i;

    ticks = 0;

    for ( i=0; i<queries_num; i++ ) {
      if ( queries[i].period == period )
        ticks = queries[i].ticks;

      if ( queries[i].source == source ) {
        break;
       }
    }

    for ( _i = i; ticks==0 && _i < queries_num; _i++ ) {
      if ( queries[_i].period == period )
        ticks = queries[_i].ticks;
    }

    if ( i == queries_num ) {
      if ( i == MaxQueries )
        i = (uint8_t)(call Random.rand16()%MaxQueries);
      else
        i = queries_num++;
    }

    queries[i].source   = source;
    queries[i].period   = period;
    queries[i].lifetime = lifetime;
    queries[i].ticks    = ticks%period;

  }

  task void propagate_results()
  {
    nx_packet_results_t *p;
    nx_packet_results_t temp;
    uint8_t i, num;
    uint16_t nh;

    if ( results_num == 0 )
      return;

    dbg("QueryM_v", "Propagating: %d results\n", results[0].num);

    if ( busy )
      return;
    busy = 1;
    nh = route_get(origins[0]);

    num = sizeof(uint16_t)+results[0].num*sizeof(nx_node_result_t);

    if ( nh != AM_BROADCAST_ADDR ) {
      dbg("QueryM_v", "num: %d, bytes; %d\n", results[0].num, num);
      p = (nx_packet_results_t*) call SubSend.getPayload(&packet, num);

      p->origin = origins[0];

      for ( i=0; i<results[0].num; ++i ) {
        p->nr[i].node = results[0].nr[i].node;
        p->nr[i].result = results[0].nr[i].result;
      }

      call PacketAcknowledgements.requestAck(&packet);
      retransmits = 0;

      if ( call SubSend.send(nh, &packet, num) == SUCCESS ) { 
        dbg("QueryM", "Subsend to %d for %d Done size: %d\n", nh, origins[0], results[0].num);
      } else {
        dbg("BlinkC", "SubSend  (%d:%d)-- Failed\n", nh, origins[0]);
        busy = FALSE;
      }

    } else {
      dbg("BlinkC", "Using fallback for %d\n", origins[0]);
      temp.origin = origins[0];

      for ( i=0; i<results[0].num; ++i ) {
        temp.nr[i].node = results[0].nr[i].node;
        temp.nr[i].result = results[0].nr[i].result;
      }

      if ( call Fallback.sendHops(&temp, num, 1) == SUCCESS ) {
        busy = 0;
      }
    }

    results[0].num = 0;
    results_num--;

    if ( results_num ) {
      origins[0] = origins[results_num];
      results[0].num = results[results_num].num;

      for ( i=0; i<results[0].num; ++i ) {
        results[0].nr[i].result= results[results_num].nr[i].result;
        results[0].nr[i].node = results[results_num].nr[i].node;
      }
    }
  }

  event void SubSend.sendDone(message_t* msg, error_t error)
  {
    if ( call PacketAcknowledgements.wasAcked(msg) == FALSE ) {
      retransmits ++;
      if ( retransmits == MaxRetransmits+1 ) {
        busy = FALSE;
        retransmits = 0;
        return;
      }

      if ( call SubSend.send(call AMPacket.destination(&packet), &packet, call Packet.payloadLength(&packet)) != SUCCESS ) {
        dbg("BlinkC", "-------------------Retransmitting packet %d\n", retransmits);
        busy = FALSE;
        retransmits = 0;

        route_rem(call AMPacket.destination(&packet));
      }
    } else {
      busy = FALSE;
      retransmits = 0;
    }

  }

  event message_t* SubRecv.receive(message_t* msg, void* payload, uint8_t len )
  {
    nx_packet_results_t *pr = (nx_packet_results_t*)payload;
    uint8_t num;
    uint8_t i;
    uint16_t target;

    num = ( (len-sizeof(uint16_t))/sizeof(nx_node_result_t));

    dbg("QueryM_v", "Got msg (%d)\n", len);

    if ( len < sizeof(uint16_t) + sizeof(nx_node_result_t) )
      return msg;

    dbg("QueryM", "(%d)Got %d results for %d from %d\n",
        len, num, pr->origin, call AMPacket.source(msg));
    
    target = (uint16_t) pr->origin;

    if ( target == call AMPacket.address() ) {
      for ( i=0; i<num; ++i ) {
        //if ( log_recv_result(pr->nr[i].node, pr->nr[i].result) == SUCCESS )
          signal Query.query_result(pr->nr[i].result, pr->nr[i].node, num);
      }
    } else {	
      for ( i=0; i<num; ++i ) {
        results_log(pr->origin, pr->nr[i].node, pr->nr[i].result);
      }
    }

    return msg;
  }

  event void BroadcastControl.stopDone(error_t err) 
  { 
    signal SplitControl.stopDone(err);
  }

  event void Fallback.receive(nx_uint8_t *data,  uint8_t len, uint16_t source, 
      uint16_t last_hop, uint8_t hops)
  {
    nx_uint8_t *t1, *t2;
    nx_packet_results_t *pr = (nx_packet_results_t*)data;
    uint16_t nh;
    uint8_t num;
    uint8_t i;

    num = ( (len-sizeof(uint16_t))/sizeof(nx_node_result_t));

    dbg("QueryM_v", "Got msg (%d) [through the fallback channel]\n", len);

    if ( len < sizeof(uint16_t) + sizeof(nx_node_result_t) )
      return;

    dbg("QueryM", "(%d)Got %d results for %d from %d [through the fallback channel]\n",len, num, pr->origin, last_hop);

    nh = route_get(pr->origin);

    if ( nh == AM_BROADCAST_ADDR )
      return;
    if ( busy )
      return;

    busy = 1;

    t1 = (nx_uint8_t*) call SubSend.getPayload(&packet, len);
    t2 = (nx_uint8_t*) pr;

    for ( i=0; i<len; i++ )
      t1[i] = t2[i];

    call PacketAcknowledgements.requestAck(&packet);

    retransmits = 0;
    if ( call SubSend.send(nh, &packet, len ) == SUCCESS ) { 
      dbg("QueryM_v", "Subsend OK for fallback!\n");
    } else {
      busy = 0;
      dbg("QueryM", "SubSend  Failed for fallback\n");
    }

  }

  event void Broadcast.receive(nx_uint8_t* data,  uint8_t len, uint16_t source, 
      uint16_t last_hop, uint8_t hops)
  {
    nx_query_request_t *query = (nx_query_request_t*) data;


    if ( len != sizeof(nx_query_request_t ) )
      return;

    route_add(source, last_hop);
    query_add(source, query->period, query->lifetime);
    
    dbg("BlinkC", "Got request from %d with period %d for a lifetime of %d\n",
        source, query->period, query->lifetime);
  }

  event void BroadcastControl.startDone(error_t err)
  {
    if ( err == SUCCESS ) {
     call Tick.startPeriodic(SensePeriod);
     call Prop.startPeriodic(PropPeriod);
    }

    signal SplitControl.startDone(err);
  }

  event void Prop.fired()
  {
     post propagate_results();
  }

  command void Query.query_new_sense(uint16_t result) {
    uint8_t i;
    uint16_t me = call AMPacket.address();

    for ( i=0; i< queries_num; i++ ) {
      if ( queries[i].ticks % queries[i].period == 0 ) {
        results_log(queries[i].source, me, result);
      }
    }
  }

  event void Tick.fired()
  {
    uint8_t i=0;
    error_t err;
    
    while ( i < queries_num ) {
      queries[i].ticks ++;

      if ( queries[i].ticks> queries[i].lifetime ) {
        queries_num--;
        dbg("QueryM_v", "Removed query %d\n", queries[i].source);
        queries[i] = queries[queries_num];
        continue;
      }

      if ( queries[i].ticks % queries[i].period ==0) {
        err = signal Query.query_sense();

        if ( err != SUCCESS )
          queries_num = 0 ;

        break;
      }
      i++;
    }
  }

  command error_t Query.query(uint8_t period, uint16_t lifetime)
  {
    nx_query_request_t req;


      req.period = period;
      req.lifetime = lifetime;

      dbg("QueryM_v", "New query(period: %d, lifetime: %d)\n", req.period, req.lifetime);

      return call Broadcast.send(&req, sizeof(nx_query_request_t));
  }

  default event error_t Query.query_sense() { }
  default event void    Query.query_result(uint16_t value, uint16_t source, uint8_t in_packet)	{	}

  command error_t SplitControl.start()
  {
    return call BroadcastControl.start();
  }

  command error_t SplitControl.stop()
  {
    return call BroadcastControl.stop();
  }
}


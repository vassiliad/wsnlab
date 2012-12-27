module WSNVMM
{
	uses {
		interface Timer<TMilli> as Timer[int id];
		interface Leds;
		interface Read<uint16_t>;
		interface WSNSerialC as Serial;
		interface SplitControl as SControl;
		interface WSNBroadcastC as Broadcast;
		interface SplitControl as BroadcastControl;
		interface AMPacket;
		interface Packet;

		interface SplitControl as NetControl;
		interface AMSend as NetSend;
		interface Receive as NetReceive;
	}

	provides {
		interface SplitControl as Control;
		interface WSNVMC as VM;
	}
}
implementation
{
	enum {MaxApps=3, MaxRegs=10, CacheLifetime=3000, MaxRoutes=15
				, MaxMsgs=5};
	enum {NewApp=12};

	enum {HandlerNone=0, HandlerInit=1, HandlerTimer=2, HandlerNet=3};

	typedef struct {
		uint16_t node;
		uint16_t hop;
	} route_t;

	typedef nx_struct {
		nx_uint8_t length;
		nx_uint8_t length_init;
		nx_uint8_t length_timer;
		nx_uint8_t length_net;
		nx_uint8_t payload[255];
	} nx_binary_t;

	typedef nx_struct {
		nx_uint16_t sink;
		nx_uint8_t  id;
		nx_int8_t  r[];
	} nx_msg_t;
	
	typedef nx_struct {
		nx_uint8_t guard;
		nx_uint8_t id;
		nx_binary_t binary;
	} nx_new_app_t;

	typedef struct {
		uint16_t sink;
		uint8_t pc;
		uint8_t is_active;
		uint8_t in_handler;
		uint8_t return_handler;
		uint8_t return_pc;
		uint8_t id;
		uint8_t has_net;
		uint8_t waiting;
		int8_t regs[MaxRegs];
		uint8_t init[255];
		uint8_t timer[255];
		uint8_t net[255];
		uint8_t stopped;
	} app_t;
		
	bool busy = FALSE;
	message_t  msgs[MaxMsgs];
	uint8_t msgs_size=0;
	uint8_t msgs_start=0;

	app_t apps[MaxApps];

	uint8_t  active_vm = MaxApps;
	uint16_t cache_value;
	uint32_t cache_time=0;
	uint8_t  cache_valid=0;

	route_t routes[MaxRoutes];
	uint8_t routes_start=0, routes_size=0;


	error_t bcastControl=EBUSY, serialControl=EBUSY, netControl=EBUSY;

	error_t app_set(int slot, nx_binary_t* binary, int id, uint16_t sink);
	void binary_to_handlers(nx_binary_t *binary, uint8_t* init, 
			uint8_t *timer, uint8_t *net);
	task void next_instruction();
	void request_sense_data(int id);
	error_t route_get(uint16_t node, uint16_t *hop);
	void chooseNextVM();
	task void sendNextMsg();
	void sendMsg(uint16_t sink, uint8_t id, uint8_t r7, uint8_t r8,
		uint8_t sendBoth);
	

	// Net
	task void sendNextMsg()
	{	

		message_t *msg = msgs + msgs_start;
		
		if ( msgs_size == 0 )
			return;
		if ( busy == TRUE )
			return;

		busy = TRUE;
	
		dbg("BlinkC","sending: %d len:%d\n", call AMPacket.destination(msg),
				call Packet.payloadLength(msg));
		if ( call NetSend.send(call AMPacket.destination(msg), msg,
				call Packet.payloadLength(msg)) == SUCCESS )
			busy = TRUE;
		else {
			busy = FALSE;
		}

		msgs_start = (msgs_start+1)%MaxMsgs;
		msgs_size--;
	}
		
	void sendMsg(uint16_t sink, uint8_t id, uint8_t r7, uint8_t r8,
		uint8_t sendBoth)
	{
		nx_msg_t *p;
		uint16_t hop;
		uint8_t len;
		message_t *msg;


		if ( route_get(sink, &hop) != SUCCESS )
			return;
		
		msg = msgs+( (msgs_start+msgs_size)%MaxMsgs );

		if ( msgs_size == MaxMsgs )
			msgs_start = (msgs_start+1)%MaxMsgs;
		else
			msgs_size++;

		len = 4 + (sendBoth!=0);
		p = (nx_msg_t*) call NetSend.getPayload(msg, len);

		p->sink = sink;
		p->id = id;
		p->r[0] = r7;
dbg("BlinkC", "sink:%d hop;%d\n", sink, hop);
		if ( sendBoth )
			p->r[1] = r8;
		
		call AMPacket.setDestination(msg, hop);
		call Packet.setPayloadLength(msg, len);

		if ( busy == FALSE )
			post sendNextMsg();
	}

	event void NetSend.sendDone(message_t* msg, error_t error)
	{
		busy = FALSE;
		if ( msgs_size )
			post sendNextMsg();
	}

	event message_t* NetReceive.receive(message_t* msg, void* payload, 
			uint8_t len)
	{
		uint8_t i;
		uint8_t buf;
		uint8_t r8,r9;

		nx_msg_t *m = (nx_msg_t*)payload;

		if ( len < 4 )
			return msg;
		
		buf = call Serial.get_buf();
		call Serial.print_str(buf, "Msg:len=");
		call Serial.print_int(buf, len);
		call Serial.print_str(buf, ",sink=");
		call Serial.print_int(buf, (uint8_t)m->sink);
		call Serial.print_str(buf, ",id=");
		call Serial.print_int(buf, m->id);
		call Serial.print_str(buf, ",from=");
		call Serial.print_int(buf, call AMPacket.source(msg));
		call Serial.print_buf(buf);

		if ( m->sink == call AMPacket.address() ) {
			for ( i=0; i<MaxApps; ++i ) {
				if ( apps[i].sink == m->sink 
						&& apps[i].id == m->id
						&& apps[i].is_active == 1 
						&& apps[i].has_net == 1 ) {
						
					apps[i].regs[8] = m->r[0];
					
					if ( len == 5 )
						apps[i].regs[9] = m->r[1];
					apps[i].return_handler = apps[i].in_handler;
					apps[i].return_pc = apps[i].pc;

					apps[i].pc = 0;
					apps[i].in_handler = HandlerNet;

					if ( active_vm == MaxApps )
						active_vm = i;
					return msg;
				}
			}
		}
		
		if ( call AMPacket.address() == m->sink )
			return msg;

		r8 = m->r[0];

		if ( len == 5 )
			r9 = m->r[1];
		sendMsg( 0, m->id, r8, r9, len==5);
		return msg;
	}

	void chooseNextVM()
	{
		uint8_t i,j;

		for ( i=1; i<=MaxApps; i++ ) {
			j = (active_vm+i)%MaxApps;
			if ( apps[j].is_active == 1 && apps[j].waiting == 0 ) {
				if ( apps[j].in_handler ) {
					active_vm = j;
					post next_instruction();
					return;
				}
			}
		}
		active_vm = MaxApps;
	}

	void printSignedInt(uint8_t buf, int8_t i)
	{
		if ( i >= 0 ) {
			call Serial.print_int(buf, i);
		} else {
			call Serial.print_str(buf, "-");
			call Serial.print_int(buf, (uint8_t)(-i));
		}
	}

	// Routes
	void route_add(uint16_t node, uint16_t hop)
	{
		uint8_t p;

		p = (routes_start+routes_size)%MaxRoutes;

		if ( routes_size == MaxRoutes ) {
			routes_start ++; // eat up the oldest entry
		} else {
			routes_size++;
		}

		routes[p].node = node;
		routes[p].hop  = hop;
	}

	error_t route_get(uint16_t node, uint16_t *hop) {
		uint8_t i;

		for ( i=0; i<routes_size; ++i ) {
			if ( routes[ (i+routes_start)%MaxRoutes ].node == node ) {
				*hop = routes[ (i+routes_start)%MaxRoutes ].hop;
				return SUCCESS;
			}
		}

		return FAIL;
	}

	event void Broadcast.receive(nx_uint8_t *data, uint8_t len,
			uint16_t source, uint16_t last_hop, uint8_t hops)
	{
		nx_new_app_t *p = ( nx_new_app_t*) data;
		uint8_t buf;

		if ( len > 2+4 && p->guard == NewApp ) {
			route_add(source, last_hop);

			buf = call Serial.get_buf();
			call Serial.print_str(buf,"NewApp::size=");
			call Serial.print_int(buf, len);
			call Serial.print_str(buf, ",init=");
			call Serial.print_int(buf, p->binary.length_init);
			call Serial.print_str(buf, ",timer=");
			call Serial.print_int(buf, p->binary.length_timer);
			call Serial.print_str(buf, ",net=");
			call Serial.print_int(buf, p->binary.length_net);
			call Serial.print_str(buf,"\tid:");
			call Serial.print_int(buf, p->id);
			call Serial.print_str(buf, ", sink:");
			call Serial.print_int(buf, (uint8_t)source);
			call Serial.print_buf(buf);

			call VM.upload_binary(&(p->binary), p->id, source);
		}
	}

	command error_t Control.start()
	{
		uint8_t i;
		for ( i=0; i<MaxApps; ++i ) {
			apps[i].return_pc = 0;
			apps[i].is_active = 0;
			apps[i].stopped = 0;
			apps[i].has_net = 0;
			apps[i].in_handler = HandlerNone;
			apps[i].return_handler = HandlerNone;
		}

		msgs_size = 0;
		msgs_start = 0;
		return call SControl.start() & call BroadcastControl.start();
	}

	command error_t Control.stop()
	{
		return call SControl.stop() & call BroadcastControl.stop();
	}

	
	event void NetControl.stopDone(error_t err) {
		netControl = err;
		if ( serialControl != EBUSY 
			&& bcastControl != EBUSY 
			&& netControl!=EBUSY)
			signal Control.stopDone(serialControl|bcastControl|netControl);
	}

	event void NetControl.startDone(error_t err) {
		netControl = err;

		if ( serialControl != EBUSY 
			&& bcastControl != EBUSY 
			&& netControl!=EBUSY)
			signal Control.startDone(serialControl|bcastControl|netControl);
	}

	event void BroadcastControl.stopDone(error_t err) {
		bcastControl = err;

		if ( serialControl != EBUSY 
			&& bcastControl != EBUSY 
			&& netControl!=EBUSY)
			signal Control.stopDone(serialControl|bcastControl|netControl);
	}

	event void BroadcastControl.startDone(error_t err) {
		bcastControl = err;

		if ( serialControl != EBUSY 
			&& bcastControl != EBUSY 
			&& netControl!=EBUSY)
			signal Control.startDone(serialControl|bcastControl|netControl);
	}

	event void SControl.stopDone(error_t err) {
		serialControl = err;

		if ( serialControl != EBUSY 
			&& bcastControl != EBUSY 
			&& netControl!=EBUSY)
			signal Control.stopDone(serialControl|bcastControl|netControl);
	}

	event void SControl.startDone(error_t err) {
		serialControl = err;

		if ( serialControl != EBUSY 
			&& bcastControl != EBUSY 
			&& netControl!=EBUSY)
			signal Control.startDone(serialControl|bcastControl|netControl);
	}

	command error_t VM.propagate_binary(void *binary, uint8_t len,
			uint8_t id)
	{
		uint8_t i;
		nx_new_app_t app;

		app.guard = NewApp;
		app.id = id;
		app.binary = *((nx_binary_t*)binary);

		for ( i=0; i<len; ++i)
			app.binary.payload[i] = ((nx_binary_t*)binary)->payload[i];

		call VM.upload_binary((nx_uint8_t*)binary, id
				,call AMPacket.address() );

		return call Broadcast.send(&app, len+2);
	}


	event void Serial.receive(void* payload, uint8_t len) {
		nx_binary_t  *bin;
		nx_uint8_t action, id;

		action = ((nx_uint8_t*)payload)[0];
		id = ((nx_uint8_t*)payload)[1];

		bin = (nx_binary_t*)((nx_uint8_t*)payload+2);

		if ( action == 0 ) {
			call VM.propagate_binary(bin, len, id);
		} else if ( action == 1 )
			call VM.stop_application(id);
		else if ( action == 2 )
			call VM.start_application(id);
	}


	event void Read.readDone( error_t result, uint16_t val )
	{
		uint8_t i, last;

		if ( val > 127 )
			val = 127;

		cache_time = call Timer.getNow[0]();
		cache_value = val;
		cache_valid = 1;
		last = active_vm;

		for ( i=0; i<MaxApps; ++i ) {
			if ( apps[i].is_active && apps[i].waiting ) {
				apps[i].regs[ apps[i].waiting -1] = val;
				apps[i].waiting = 0;
				last = i;
			}
		}

		if ( active_vm == MaxApps ) {
			active_vm = last;

			post next_instruction();
		}
	}

	void request_sense_data(int id)
	{
		uint32_t now;

		if ( cache_valid ) {
			now = call Timer.getNow[0]();

			if ( now - cache_time <= CacheLifetime ) {
				apps[id].regs[apps[id].waiting-1] = cache_value;

				dbg("WSNVMM_v", "app[%d].r%d = %d\n", id, apps[id].waiting
						, apps[id].regs[apps[id].waiting-1]);
				apps[id].waiting = 0;

				if ( active_vm == MaxApps ) {
					active_vm = id;
					post next_instruction();
				} 
				return;
			} 
		}

		call Read.read();
	}

	void binary_to_handlers(nx_binary_t *binary, uint8_t *init, 
			uint8_t *timer, uint8_t *net)
	{
		uint8_t i;

		nx_uint8_t *p;

		dbg("WSNVMM", "size: %d\n", binary->length);
		dbg("WSNVMM", "init_size:  %d\n", binary->length_init);
		dbg("WSNVMM", "timer_size: %d\n", binary->length_timer);
		dbg("WSNVMM", "timer_net:  %d\n", binary->length_net);

		p = ( (nx_uint8_t*) binary ) + 4;

		dbg("WSNVMM", "Init:\n");
		for ( i=0; i<binary->length_init; ++i, ++p ) 
			init[i] = *p;

		dbg("WSNVMM", "Timer\n");
		for ( i=0; i<binary->length_timer; ++i, ++p )
			timer[i] = *p;

		dbg("WSNVMM", "Net\n");
		for ( i=0; i<binary->length_net; ++i, ++p )
			net[i] = *p;

		dbg("WSNVMM", "Done loading\n");
	}

	error_t app_set(int slot, nx_binary_t* binary, int id, uint16_t sink)
	{
		app_t *p = apps + slot;
		uint8_t j;

		if ( slot >= MaxApps ) {
			return ENOMEM;
		}

		dbg("BlinkC", "sink is %d\n", sink);

		p->sink = sink;
		p->is_active = 0;
		p->pc = 0;
		p->id = id;
		p->in_handler=HandlerInit;
		p->return_handler = HandlerNone;
		p->return_pc = 0;
		p->waiting = 0;
		p->has_net = ( binary->length_net > 0 );
		binary_to_handlers(binary, p->init, p->timer, p->net);

		for ( j=0; j<MaxRegs; ++j )
			p->regs[j] = 0;

		p->is_active = 1;

		if ( active_vm == MaxApps ) {
			active_vm = slot;
			post next_instruction();
		}

		return SUCCESS;
	}

	task void next_instruction()
	{
		uint8_t i;
		uint8_t *instr;
		uint8_t buf;

		app_t *p = apps + active_vm;

		if ( active_vm == MaxApps )
			return;

		if ( p->in_handler==HandlerInit)
			instr = p->init + p->pc;
		else if ( p->in_handler == HandlerTimer )
			instr = p->timer + p->pc;
		else
			instr = p->net + p->pc;

		dbg("WSNVMM", "Executing for %d:%d (%x)\n", 
				active_vm, p->pc, instr[0] & 0xF0);

		buf = call Serial.get_buf();

		call Serial.print_int(buf, p->sink);
		call Serial.print_str(buf, ".");
		call Serial.print_int(buf, p->id);

		if ( p->pc < 10 )
			call Serial.print_str(buf, ": ");
		else
			call Serial.print_str(buf, ":");
		call Serial.print_int(buf, p->pc);
		call Serial.print_str(buf, " ");

		switch ( instr[0] & 0xF0 ) {
			case 0x00:
				dbg("WSNVMM_v", "Ret\n");
				//        buf = call Serial.get_buf();
				call Serial.print_str(buf, "Ret");
				call Serial.print_buf(buf);

				dbg("WSNVMM", "Done Handler %d\n", p->in_handler);

				p->in_handler = p->return_handler;
				p->pc = p->return_pc;
				break;
			case 0x10:
				i = instr[0] & 0x0f;

				if ( i>0 && i < MaxRegs ) {
					p->regs[i-1] = (int8_t) instr[1];
					(p->pc)+=2;
				}

				dbg("WSNVMM_v", "Set r%d=%d\n", i, (int8_t) instr[1]);
				//        buf = call Serial.get_buf();
				call Serial.print_str(buf, "Set r");
				call Serial.print_int(buf, i);
				call Serial.print_str(buf, "=");
				printSignedInt(buf, instr[1]);
				call Serial.print_buf(buf);

				break;

			case 0x20:
				i = instr[0] & 0x0f;
				if ( i > 0 && i <= MaxRegs 
						&& instr[1] <= MaxRegs  && instr[1] > 0 ) {
					p->regs[i-1] = p->regs[instr[1]-1];
					(p->pc)+=2;
				}

				dbg("WSNVMM_v", "Cpy r%d, r%d\n", i, instr[1]);

				//        buf = call Serial.get_buf();
				call Serial.print_str(buf, "Cp r");
				call Serial.print_int(buf, i);
				call Serial.print_str(buf, "=r");
				call Serial.print_int(buf, instr[1]);
				call Serial.print_str(buf, " : " );
				printSignedInt(buf, p->regs[i-1]);
				call Serial.print_buf(buf);

				break;

			case 0x30:
				i = instr[0] & 0x0f;
				if ( i > 0 && i <= MaxRegs 
						&& instr[1]>0 && instr[1] <= MaxRegs ) {
					(p->regs[i-1]) += p->regs[instr[1]-1];
					(p->pc)+=2;
				}

				dbg("WSNVMM_v", "Add r%d, r%d\n", i, instr[1]);
				//       buf = call Serial.get_buf();
				call Serial.print_str(buf, "Add r");
				call Serial.print_int(buf, i);
				call Serial.print_str(buf, "=r");
				call Serial.print_int(buf, instr[1]);
				call Serial.print_str(buf, " : " );
				printSignedInt(buf, p->regs[i-1]);
				call Serial.print_buf(buf);

				break;

			case 0x40:
				i = instr[0] & 0x0f;
				if ( i > 0 && i <= MaxRegs 
						&& instr[1] > 0 &&  instr[1] <= MaxRegs ) {
					(p->regs[i-1]) -= p->regs[instr[1]-1];
					(p->pc)+=2;
				}


				dbg("WSNVMM_v", "Sub r%d, r%d -> %d\n", i, instr[1], p->regs[i-1]);
				//     buf = call Serial.get_buf();
				call Serial.print_str(buf, "Sub r");
				call Serial.print_int(buf, i);
				call Serial.print_str(buf, "=r");
				call Serial.print_int(buf, instr[1]);
				call Serial.print_str(buf, " : " );
				printSignedInt(buf, p->regs[i-1]);
				call Serial.print_buf(buf);

				break;

			case 0x50:
				i = instr[0] & 0x0f;
				if ( i > 0 && i <= MaxRegs ) {
					(p->regs[i-1])++;

				}
				(p->pc)++;

				dbg("WSNVMM_v", "Inc r%d\n", i);
				call Serial.print_str(buf, "Inc r");
				call Serial.print_int(buf, i);
				call Serial.print_str(buf, " : " );
				printSignedInt(buf, p->regs[i-1]);
				call Serial.print_buf(buf);
				break;

			case 0x60:
				i = instr[0] & 0x0f;
				if ( i > 0 && i <= MaxRegs ) {
					(p->regs[i-1])--;
				}
				(p->pc)++;

				dbg("WSNVMM_v", "Dec r%d\n", i);

				//        buf = call Serial.get_buf();
				call Serial.print_str(buf, "Dec r");
				call Serial.print_int(buf, i);

				call Serial.print_str(buf, " : " );
				printSignedInt(buf, p->regs[i-1]);
				call Serial.print_buf(buf);
				break;

			case 0x70:
				i = instr[0] & 0x0f;
				if ( i > 0 && i <= MaxRegs 
						&& instr[1] > 0 && instr[1] <= MaxRegs ) {
					(p->regs[i-1]) = p->regs[instr[1]-1] > p->regs[i-1] ?
						p->regs[instr[1]-1] : p->regs[i-1];
					(p->pc)+=2;
				}

				dbg("WSNVMM_v", "Max r%d, r%d\n", i, instr[1]);
				//        buf = call Serial.get_buf();
				call Serial.print_str(buf, "Max r");
				call Serial.print_int(buf, i);
				call Serial.print_str(buf, "=r");
				call Serial.print_int(buf, instr[1]);
				call Serial.print_str(buf, " : " );
				printSignedInt(buf, p->regs[i-1]);
				call Serial.print_buf(buf);
				break;


			case 0x80:
				i = instr[0] & 0x0f;
				if ( i > 0 && i <= MaxRegs 
						&& instr[1] > 0 &&  instr[1] <= MaxRegs ) {
					(p->regs[i-1]) = p->regs[instr[1]-1] < p->regs[i-1] ?
						p->regs[instr[1]-1] : p->regs[i-1];
					(p->pc)+=2;
				}

				dbg("WSNVMM_v", "Min r%d, r%d\n", i, instr[1]);
				//        buf = call Serial.get_buf();
				call Serial.print_str(buf, "Min r");
				call Serial.print_int(buf, i);
				call Serial.print_str(buf, "=r");
				call Serial.print_int(buf, instr[1]);
				call Serial.print_str(buf, " : " );
				printSignedInt(buf, p->regs[i-1]);
				call Serial.print_buf(buf);
				break;

			case 0x90:
				i = instr[0] & 0x0f;
				(p->pc)++;
				if ( p->regs[i-1] > 0 ) {
					p->pc += (int8_t)instr[1];
				} else {
					(p->pc)++;
				}
				dbg("WSNVMM_v", "bgz r%d, %d\n", i, (int8_t) instr[1]);
				//        buf = call Serial.get_buf();
				call Serial.print_str(buf, "Bgz r");
				call Serial.print_int(buf, i);
				call Serial.print_str(buf, ",");
				printSignedInt(buf, instr[1]);
				call Serial.print_str(buf, " : ");
				if ( p->regs[i-1] > 0 )
					call Serial.print_str(buf, "taken");
				else
					call Serial.print_str(buf, "not taken");
				call Serial.print_buf(buf);

				break;

			case 0xA0:
				i = instr[0] & 0x0f;
				(p->pc)++;
				if ( p->regs[i-1] == 0 ) {
					p->pc += (int8_t)instr[1];
				} else {
					(p->pc)++;
				}
				dbg("WSNVMM_v", "bez r%d, %d\n", i, (int8_t) instr[1]);

				//        buf = call Serial.get_buf();
				call Serial.print_str(buf, "Bez r");
				call Serial.print_int(buf, i);
				call Serial.print_str(buf, ",");
				printSignedInt(buf, instr[1]);
				call Serial.print_str(buf, " : ");
				if ( p->regs[i-1] == 0 )
					call Serial.print_str(buf, "taken");
				else
					call Serial.print_str(buf, "not taken");

				call Serial.print_buf(buf);
				break;

			case 0xB0:
				(p->pc) += 1 + (int8_t) instr[1];
				dbg("WSNVMM_v", "bra %d\n", (int8_t) instr[1]);
				//        buf = call Serial.get_buf();
				call Serial.print_str(buf, "Bra ");
				printSignedInt(buf, instr[1]);
				call Serial.print_buf(buf);

				break;

			case 0xC0:
				dbg("WSNVMM_v", "Led: %d\n",  instr[0]&0x0f);
				//        buf = call Serial.get_buf();
				call Serial.print_str(buf, "Led ");
				call Serial.print_int(buf, instr[0]&0x0f);
				call Serial.print_buf(buf);


				if ( instr[0]&0x0f )
					switch ( apps[active_vm].id ) {
						case 0:
							call Leds.led0On();
							break;

						case 1:
							call Leds.led1On();
							break;

						case 2:
							call Leds.led2On();
							break;
					}
				else
					switch ( apps[active_vm].id ) {
						case 0:
							call Leds.led0Off();
							break;

						case 1:
							call Leds.led1Off();
							break;

						case 2:
							call Leds.led2Off();
							break;
					}

				(p->pc)++;
				break;

			case 0xD0:
				i = instr[0] & 0x0f;
				dbg("WSNVMM_v", "Rdb: r%d\n", i);
				//        buf = call Serial.get_buf();
				call Serial.print_str(buf, "Rdb ");
				call Serial.print_int(buf, i);
				call Serial.print_buf(buf);
				apps[active_vm].waiting = i;
				request_sense_data(active_vm);
				(p->pc)++;
				break;

			case 0xE0:
				i = instr[0] & 0x0f;
				if ( i == 0 ) {
					dbg("WSNVMM_v", "Tmr[%d]: %d\n",i, instr[1]);
					//        buf = call Serial.get_buf();
					call Serial.print_str(buf, "Tmr[");
					call Serial.print_int(buf, i);
					call Serial.print_str(buf, "] ");
					call Serial.print_int(buf, instr[1]);
					call Serial.print_buf(buf);

					call Timer.startOneShot[active_vm](instr[1]*1000);
					if ( call Timer.isRunning[active_vm]() == FALSE )
						exit(0);

				} else {

				}
				(p->pc)+=2;
				break;

			case 0xF0:
				i = instr[0] & 0x0f;
				p->pc = p->pc +1;
				sendMsg(0, p->id,p->regs[6], p->regs[7], i);

				call Serial.print_str(buf, "Send{");
				printSignedInt(buf, p->regs[6]);
				if ( i !=0 ) {
					call Serial.print_str(buf, ",");
					printSignedInt(buf, p->regs[7]);
				}
				call Serial.print_str(buf, "}");
				call Serial.print_buf(buf);
				break;
		}

		chooseNextVM();	// choose vm and post next_instruction if necessary
	}

	default command uint32_t Timer.getNow[int id](){
		dbg("BlinkC", "This should not be executed");

		return 0;
	}

	default command bool Timer.isRunning[int id]()
	{
		dbg("BlinkC", "This should not be executed");
		return FALSE;

	}

	default command void Timer.startOneShot[int id](uint32_t milli){
		dbg("BlinkC", "This should not be executed");
	}

	event void Timer.fired[int id]()
	{
		dbg("BlinkC", "FIRED %d (%d)\n", id, active_vm);
		apps[id].in_handler = HandlerTimer;
		apps[id].pc = 0;


		if ( active_vm == MaxApps ) {
			active_vm = id;
			post next_instruction();
		}
	}

	command error_t VM.upload_binary(void *binary, uint8_t id, uint16_t sink)
	{
		uint8_t i, slot;

		slot = MaxApps;

		for ( i=0; i<MaxApps; i++ )
			if ( apps[i].is_active && apps[i].id == id ) {
				apps[i].is_active = 0;
				return app_set(i, (nx_binary_t*)binary, id, sink);
			} else if ( apps[i].is_active == 0 )
				slot = i;

		if ( slot == MaxApps )
			return ENOMEM;

		return app_set(slot, (nx_binary_t*)binary, id, sink);
	}

	command error_t VM.stop_application(uint8_t id)
	{
		uint8_t i, j;

		for ( i=0; i<MaxApps; i++ ) {
			if ( apps[i].is_active && apps[i].id == id ) {
				apps[i].is_active = 0;
				apps[i].stopped = 1;
				break;
			}
		}

		if ( i == MaxApps )
			return FAIL;

		switch ( id ) {
			case 0:
				call Leds.led0Off();
				break;

			case 1:
				call Leds.led1Off();
				break;

			case 2:
				call Leds.led2Off();
				break;
		}

		if ( active_vm == i )
			for ( i=1; i<=MaxApps; i++ ) {
				j = (active_vm+i)%MaxApps;
				if ( apps[j].is_active == 1 && apps[j].waiting == 0 ) {
					if ( apps[j].in_handler ) {
						active_vm = j;
						return SUCCESS;
					}
				}
			}

		active_vm = MaxApps;

		return SUCCESS;
	}

	command error_t VM.start_application(uint8_t id)
	{
		uint8_t i,slot = MaxApps;
		app_t *p;

		for ( i=0; i<MaxApps; i++ ) {
			if ( apps[i].id == id && apps[i].stopped==1 ) {
				slot = i;
				p = apps+i;
				p->stopped = 0;
				break;
			}
		}

		if ( slot == MaxApps )
			return FAIL;


		for (i=0; i<MaxRegs; i++ )
			p->regs[i] = 0;

		p->is_active = 0;

		switch ( id ) {
			case 0:
				call Leds.led0Off();
				break;

			case 1:
				call Leds.led1Off();
				break;

			case 2:
				call Leds.led2Off();
				break;
		}

		p->pc = 0;
		p->id = id;
		p->in_handler=HandlerInit;
		p->return_handler = HandlerNone;
		p->return_pc = 0;
		p->waiting = 0;
		p->is_active = 1;

		if ( active_vm == MaxApps ) {
			active_vm = slot;
			post next_instruction();
		}

		return SUCCESS;
	}
}


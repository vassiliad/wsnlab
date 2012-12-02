module WSNVMM
{
	uses interface Timer<TMilli> as Timer[int id];
	uses interface Leds;

	provides interface WSNVMC as VM;
}
implementation
{
	enum {MaxApps=3};

	typedef nx_struct {
		nx_uint8_t length;
		nx_uint8_t length_init;
		nx_uint8_t length_timer;
		nx_uint8_t payload[];
	} nx_binary_t;

	typedef struct {
		uint8_t opcode;
		uint8_t arg2;
	} instruction_t;

	typedef struct {
		uint8_t pc;
		uint8_t is_active;
		uint8_t in_init;
		uint8_t id;
		uint8_t timer_set;
		uint8_t timer_active;
		uint8_t waiting;
		instruction_t init[255];
		instruction_t timer[255];
	} app_t;

	app_t apps[MaxApps];

	typedef nx_struct {
	} nx_packed_app_t;

	uint8_t active_vm = MaxApps;

	error_t app_set(int slot, nx_binary_t* binary, int id);
	void binary_to_handlers(nx_binary_t *binary, instruction_t* init,
			instruction_t *timer);
	uint8_t binary_to_instruction(nx_uint8_t* binary, instruction_t *instr);
	task void next_instruction();

	uint8_t binary_to_instruction(nx_uint8_t* binary, instruction_t *instr)
	{
		uint8_t opcode = binary[0];
		uint8_t arg2   = binary[1];

		instr->opcode = opcode;

		dbg("BlinkC", "Op: %X (%X)\n", (opcode&0xf0), opcode);
		opcode = (opcode&0xf0);

		switch( opcode ) {
			case 0x00:
			case 0x50:
			case 0x60:
			case 0xC0:
			case 0xD0:
				return 1;

			default:
				instr->arg2 = arg2;
				return 2;
		}
	}

	void binary_to_handlers(nx_binary_t *binary, instruction_t* init,
			instruction_t *timer)
	{
		uint8_t i,j;
		nx_uint8_t *p;

		dbg("BlinkC", "size: %d\n", binary->length);
		dbg("BlinkC", "init_size: %d\n", binary->length_init);
		dbg("BlinkC", "timer_size: %d\n", binary->length_timer);

		p = ( (nx_uint8_t*) binary ) + 3;

		dbg("BlinkC", "Init:\n");
		for ( i=0, j=0; i<binary->length_init; ++j ) 
			i += binary_to_instruction(p+i, init+j);

		p += binary->length_init;

		dbg("BlinkC", "Timer\n");
		for ( i=0, j=0; i<binary->length_timer; ++j )
			i += binary_to_instruction(p+i, timer+j);
		dbg("BlinkC", "Done loading\n");
	}

	error_t app_set(int slot, nx_binary_t* binary, int id)
	{
		app_t *p = apps + slot;
		uint8_t j;

		if ( slot >= MaxApps )
			return ENOMEM;

		p->is_active = 0;
		p->pc = 0;
		p->id = id;
		p->in_init=1;
		p->timer_set=0;
		p->timer_active=0;
		p->waiting = 0;
		binary_to_handlers(binary, p->init, p->timer);
		p->is_active = 1;

		if ( active_vm == MaxApps ) {
			active_vm = slot;
			post next_instruction();
		}

		return SUCCESS;
	}

	task void next_instruction()
	{
		uint8_t i,j;
		instruction_t *instr;

		app_t *p = apps + active_vm;
		
		dbg("BlinkC", "Executing for %d:%d\n", active_vm, p->pc);

		if ( active_vm == MaxApps )
			return;


		if ( p->in_init )
			instr = p->init + p->pc;
		else
			instr = p->timer + p->pc;

		switch ( instr->opcode & 0xF0 ) {
			case 0x00:
				dbg("BlinkC", "Ret\n");

				if ( p->in_init == 1 ) {
					dbg("BlinkC", "Done Init\n");
					p->in_init = 0;
					if ( p->timer_set == 0 ) {
						p->is_active = 0;
					}
				} else {
					dbg("BlinkC", "Done Timer\n");
					p->timer_active = 0;
					if ( p->timer_set == 0 )
						p->is_active = 0;
				}
				break;

			case 0x10:
				break;

			case 0x20:
				break;

			case 0x30:
				break;

			case 0x40:
				break;

			case 0x50:
				break;

			case 0x60:
				break;

			case 0x70:
				break;

			case 0x80:
				break;

			case 0x90:
				break;

			case 0xA0:
				break;

			case 0xB0:
				break;

			case 0xC0:
				dbg("BlinkC", "Led: %d\n", instr->opcode&0x0f);
				(p->pc)++;
				break;

			case 0xD0:
				break;

			case 0xE0:
				dbg("BlinkC", "Tmr: %d\n", instr->arg2);
				p->timer_set=1;
				call Timer.startOneShot[active_vm](instr->arg2);
				(p->pc)++;
				break;
		}

		for ( i=1; i<=MaxApps; i++ ) {
			j = (active_vm+i)%MaxApps;
			if ( apps[j].is_active == 1 && 
					 apps[j].waiting == 0 ) {
				if ( apps[j].in_init == 1 )  {
					active_vm = j;
				} else {
					if ( apps[j].timer_active == 1 )
						active_vm = j;
					else
						continue;
				}
				post next_instruction();
				return;
			}
		}
		active_vm = MaxApps;
	}

	default command void Timer.startOneShot[int id](uint32_t milli){}

	event void Timer.fired[int id]()
	{
		apps[id].timer_active = 1;
		apps[id].in_init = 0;
		apps[id].pc = 0;
		if ( active_vm == MaxApps ) {
			active_vm = id;
			post next_instruction();
		}
	}

	command error_t VM.upload_binary(void *binary, uint8_t id)
	{
		uint8_t i, slot;

		slot = MaxApps;

		for ( i=0; i<MaxApps; i++ )
			if ( apps[i].is_active && apps[i].id == id ) {
				apps[i].is_active = 0;
				return app_set(i, (nx_binary_t*)binary, id);
			} else if ( apps[i].is_active == 0 )
				slot = i;

		if ( slot == MaxApps )
			return ENOMEM;

		return app_set(slot, (nx_binary_t*)binary, id);
	}

	command error_t VM.stop_application(uint8_t id)
	{
		uint8_t i;

		for ( i=0; i<MaxApps; i++ ) {
			if ( apps[i].is_active && apps[i].id == id ) {
				apps[i].is_active = 0;
			}
		}
	}

	command error_t VM.start_application(uint8_t id)
	{
	}

}


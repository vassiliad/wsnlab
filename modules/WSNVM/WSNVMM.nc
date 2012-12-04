module WSNVMM
{
  uses interface Timer<TMilli> as Timer[int id];
  uses interface Leds;

  provides interface WSNVMC as VM;
}
implementation
{
  enum {MaxApps=3, MaxRegs=6};

  typedef nx_struct {
    nx_uint8_t length;
    nx_uint8_t length_init;
    nx_uint8_t length_timer;
    nx_uint8_t payload[];
  } nx_binary_t;

  typedef struct {
    uint8_t pc;
    uint8_t is_active;
    uint8_t in_init;
    uint8_t id;
    uint8_t timer_set;
    uint8_t timer_active;
    uint8_t waiting;
    int8_t regs[MaxRegs];

    uint8_t init[255];
    uint8_t timer[255];
  } app_t;

  app_t apps[MaxApps];

  typedef nx_struct {
  } nx_packed_app_t;

  uint8_t active_vm = MaxApps;

  error_t app_set(int slot, nx_binary_t* binary, int id);
  void binary_to_handlers(nx_binary_t *binary, uint8_t* init, uint8_t *timer);
  // uint8_t binary_to_instruction(nx_uint8_t* binary, instruction_t *instr);
  task void next_instruction();

  /* uint8_t binary_to_instruction(nx_uint8_t* binary, instruction_t *instr)
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
     } */

  void binary_to_handlers(nx_binary_t *binary, uint8_t *init, uint8_t *timer)	{
    uint8_t i;

    nx_uint8_t *p;

    dbg("BlinkC", "size: %d\n", binary->length);
    dbg("BlinkC", "init_size: %d\n", binary->length_init);
    dbg("BlinkC", "timer_size: %d\n", binary->length_timer);

    p = ( (nx_uint8_t*) binary ) + 3;

    dbg("BlinkC", "Init:\n");
    for ( i=0; i<binary->length_init; ++i, ++p ) 
      init[i] = *p;

    dbg("BlinkC", "Timer\n");
    for ( i=0; i<binary->length_timer; ++i, ++p )
      timer[i] = *p;

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
    uint8_t i,j;
    uint8_t *instr;

    app_t *p = apps + active_vm;


    if ( active_vm == MaxApps )
      return;


    if ( p->in_init )
      instr = p->init + p->pc;
    else
      instr = p->timer + p->pc;
    dbg("BlinkC", "Executing for %d:%d (%x)\n", active_vm, p->pc, instr[0] & 0xF0);

    switch ( instr[0] & 0xF0 ) {
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
        i = instr[0] & 0x0f;

        if ( i < MaxRegs ) {
          p->regs[i] = (int8_t) instr[1];
          (p->pc)+=2;
        }

        dbg("BlinkC_v", "Set r%d:=%d\n", i, (int8_t) instr[1]);


        break;

      case 0x20:
        i = instr[0] & 0x0f;
        if ( i < MaxRegs && instr[1] < MaxRegs ) {
          p->regs[i] = p->regs[instr[1]];
          (p->pc)+=2;
        }

        dbg("BlinkC_v", "Cpy r%d, r%d\n", i, instr[1]);

        break;

      case 0x30:
        i = instr[0] & 0x0f;
        if ( i < MaxRegs && instr[1] < MaxRegs ) {
          (p->regs[i]) += p->regs[instr[1]];
          (p->pc)+=2;
        }

        dbg("BlinkC_v", "Add r%d, r%d\n", i, instr[1]);
        break;

      case 0x40:
        i = instr[0] & 0x0f;
        if ( i < MaxRegs && instr[1] < MaxRegs ) {
          (p->regs[i]) -= p->regs[instr[1]];
          (p->pc)+=2;
        }

        dbg("BlinkC_v", "Sub r%d, r%d\n", i, instr[1]);
        break;

      case 0x50:
        i = instr[0] & 0x0f;
        if ( i < MaxRegs ) {
          (p->regs[i])++;
        }
        (p->pc)++;

        dbg("BlinkC_v", "Inc r%d\n", i);
        break;

      case 0x60:
        i = instr[0] & 0x0f;
        if ( i < MaxRegs ) {
          (p->regs[i])--;
        }
        (p->pc)++;

        dbg("BlinkC_v", "Dec r%d\n", i);
        break;

      case 0x70:
        i = instr[0] & 0x0f;
        if ( i < MaxRegs && instr[1] < MaxRegs ) {
          (p->regs[i]) = p->regs[instr[1]] > p->regs[i] ? p->regs[instr[1]] : p->regs[i];
          (p->pc)+=2;
        }

        dbg("BlinkC_v", "Max r%d, r%d\n", i, instr[1]);
        break;


      case 0x80:
        i = instr[0] & 0x0f;
        if ( i < MaxRegs && instr[1] < MaxRegs ) {
          (p->regs[i]) = p->regs[instr[1]] < p->regs[i] ? p->regs[instr[1]] : p->regs[i];
          (p->pc)+=2;
        }

        dbg("BlinkC_v", "Min r%d, r%d\n", i, instr[1]);
        break;

      case 0x90:
        i = instr[0] & 0x0f;
        (p->pc)++;
        if ( p->regs[i] > 0 ) {
          p->pc += (int8_t)instr[1];
        } else {
          (p->pc)++;
        }
        dbg("BlinkC_v", "bgz r%d, %d\n", i, (int8_t) instr[1]);

        break;

      case 0xA0:
        i = instr[0] & 0x0f;
        (p->pc)++;
        if ( p->regs[i] == 0 ) {
          p->pc += (int8_t)instr[1];
        } else {
          (p->pc)++;
        }
        dbg("BlinkC_v", "bez r%d, %d\n", i, (int8_t) instr[1]);

        break;

      case 0xB0:
        (p->pc) += 2 + (int8_t) instr[1];
        dbg("BlinkC_v", "bra %d\n", (int8_t) instr[1]);

        break;

      case 0xC0:
        dbg("BlinkC", "Led: %d\n", instr[0]&0x0f);
        (p->pc)++;
        break;

      case 0xD0:
        break;

      case 0xE0:
        dbg("BlinkC_v", "Tmr: %d\n", instr[1]);

        p->timer_set=1;
        call Timer.startOneShot[active_vm](instr[1]);
        (p->pc)+=2;
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


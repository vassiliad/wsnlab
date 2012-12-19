module WSNVMM
{
  uses interface Timer<TMilli> as Timer[int id];
  uses interface Leds;
  uses interface Read<uint16_t>;
  uses interface WSNSerialC as Serial;
  provides interface SplitControl as Control;
  uses interface SplitControl as SControl;
  provides interface WSNVMC as VM;
}
implementation
{
  enum {MaxApps=3, MaxRegs=6, CacheLifetime=3000};

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
    uint8_t stopped;
  } app_t;

  app_t apps[MaxApps];

  typedef nx_struct {
  } nx_packed_app_t;

  uint8_t  active_vm = MaxApps;
  uint16_t cache_value;
  uint32_t cache_time=0;
  uint8_t  cache_valid=0;


  error_t app_set(int slot, nx_binary_t* binary, int id);
  void binary_to_handlers(nx_binary_t *binary, uint8_t* init, 
      uint8_t *timer);
  task void next_instruction();
  void request_sense_data(int id);

  command error_t Control.start()
  {
    uint8_t i;
    for ( i=0; i<MaxApps; ++i ) {
      apps[i].is_active = 0;
      apps[i].stopped = 0;
    }

    return call SControl.start();
  }

  command error_t Control.stop()
  {
    return call SControl.stop();
  }

  event void SControl.stopDone(error_t err) {
    signal Control.stopDone(err);
  }

  event void SControl.startDone(error_t err) {
    if ( err != SUCCESS )
      call SControl.start();
    signal Control.startDone(err);
  }



  event void Serial.receive(void* payload, uint8_t len) {
    nx_uint8_t action, id;

    action = ((nx_uint8_t*)payload)[0];
    id = ((nx_uint8_t*)payload)[1];

    if ( action == 0 ) {
      call VM.upload_binary((nx_uint8_t*) payload+2, id);
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
        // dbg("WSNVMM_v", "app[%d].r%d = %d\n", i, apps[i].waiting, apps[i].regs[apps[i].waiting-1]);
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

        dbg("WSNVMM_v", "app[%d].r%d = %d\n", id, apps[id].waiting, apps[id].regs[apps[id].waiting-1]);
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
      uint8_t *timer)
  {
    uint8_t i;

    nx_uint8_t *p;

    dbg("WSNVMM", "size: %d\n", binary->length);
    dbg("WSNVMM", "init_size: %d\n", binary->length_init);
    dbg("WSNVMM", "timer_size: %d\n", binary->length_timer);

    p = ( (nx_uint8_t*) binary ) + 3;

    dbg("WSNVMM", "Init:\n");
    for ( i=0; i<binary->length_init; ++i, ++p ) 
      init[i] = *p;

    dbg("WSNVMM", "Timer\n");
    for ( i=0; i<binary->length_timer; ++i, ++p )
      timer[i] = *p;

    dbg("WSNVMM", "Done loading\n");
  }

  error_t app_set(int slot, nx_binary_t* binary, int id)
  {
    app_t *p = apps + slot;
    uint8_t j;

    if ( slot >= MaxApps ) {
      return ENOMEM;
    }

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
    uint8_t buf;

    app_t *p = apps + active_vm;

    if ( active_vm == MaxApps )
      return;

    if ( p->in_init )
      instr = p->init + p->pc;
    else
      instr = p->timer + p->pc;

    dbg("WSNVMM", "Executing for %d:%d (%x)\n", active_vm, p->pc, instr[0] & 0xF0);


    switch ( instr[0] & 0xF0 ) {
      case 0x00:
        dbg("WSNVMM_v", "Ret\n");
        buf = call Serial.get_buf();
        call Serial.print_str(buf, "Ret");
        call Serial.print_buf(buf);

        if ( p->in_init == 1 ) {
          dbg("WSNVMM", "Done Init\n");
          p->in_init = 0;
          if ( p->timer_set == 0 ) {
            p->is_active = 0;
          }
        } else {
          dbg("WSNVMM", "Done Timer\n");
          p->timer_active = 0;
          if ( p->timer_set == 0 )
            p->is_active = 0;
        }
        break;

      case 0x10:
        i = instr[0] & 0x0f;

        if ( i>0 && i < MaxRegs ) {
          p->regs[i-1] = (int8_t) instr[1];
          (p->pc)+=2;
        }

        dbg("WSNVMM_v", "Set r%d:=%d\n", i, (int8_t) instr[1]);
        buf = call Serial.get_buf();
        call Serial.print_str(buf, "Set r");
        call Serial.print_int(buf, i);
        call Serial.print_str(buf, ":=");

        if ( instr[1] >= 0 ) {
          call Serial.print_int(buf, instr[1]);
        } else {
          call Serial.print_str(buf, "-");
          call Serial.print_int(buf, (uint8_t)(-instr[1]));
        }

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

        buf = call Serial.get_buf();
        call Serial.print_str(buf, "Cp r");
        call Serial.print_int(buf, i);
        call Serial.print_str(buf, ":=r");
        call Serial.print_int(buf, instr[1]);
        call Serial.print_str(buf, " ==> " );

        if ( p->regs[instr[1]-1] >= 0 ) {
          call Serial.print_int(buf, p->regs[i-1]);
        } else {
          call Serial.print_str(buf, "-");
          call Serial.print_int(buf, (uint8_t)(-p->regs[i-1]));
        }

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
        buf = call Serial.get_buf();
        call Serial.print_str(buf, "Add r");
        call Serial.print_int(buf, i);
        call Serial.print_str(buf, ":=r");
        call Serial.print_int(buf, instr[1]);
        call Serial.print_str(buf, " ==> " );

        if ( p->regs[instr[1]-1] >= 0 ) {
          call Serial.print_int(buf, p->regs[i-1]);
        } else {
          call Serial.print_str(buf, "-");
          call Serial.print_int(buf, (uint8_t)(-p->regs[i-1]));
        }

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
        buf = call Serial.get_buf();
        call Serial.print_str(buf, "Sub r");
        call Serial.print_int(buf, i);
        call Serial.print_str(buf, ":=r");
        call Serial.print_int(buf, instr[1]);
        call Serial.print_str(buf, " ==> " );

        if ( p->regs[instr[1]-1] >= 0 ) {
          call Serial.print_int(buf, p->regs[i-1]);
        } else {
          call Serial.print_str(buf, "-");
          call Serial.print_int(buf, (uint8_t)(-p->regs[i-1]));
        }

        call Serial.print_buf(buf);

        break;

      case 0x50:
        i = instr[0] & 0x0f;
        if ( i > 0 && i <= MaxRegs ) {
          (p->regs[i-1])++;

        }
        (p->pc)++;

        dbg("WSNVMM_v", "Inc r%d\n", i);
        buf = call Serial.get_buf();
        call Serial.print_str(buf, "Inc r");
        call Serial.print_int(buf, i);

        call Serial.print_str(buf, " ==> " );

        if ( p->regs[instr[1]-1] >= 0 ) {
          call Serial.print_int(buf, p->regs[i-1]);
        } else {
          call Serial.print_str(buf, "-");
          call Serial.print_int(buf, (uint8_t)(-p->regs[i-1]));
        }

        call Serial.print_buf(buf);
        break;

      case 0x60:
        i = instr[0] & 0x0f;
        if ( i > 0 && i <= MaxRegs ) {
          (p->regs[i-1])--;
        }
        (p->pc)++;

        dbg("WSNVMM_v", "Dec r%d\n", i);

        buf = call Serial.get_buf();
        call Serial.print_str(buf, "Dec r");
        call Serial.print_int(buf, i);

        call Serial.print_str(buf, " ==> " );

        if ( p->regs[instr[1]-1] >= 0 ) {
          call Serial.print_int(buf, p->regs[i-1]);
        } else {
          call Serial.print_str(buf, "-");
          call Serial.print_int(buf, (uint8_t)(-p->regs[i-1]));
        }

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
        buf = call Serial.get_buf();
        call Serial.print_str(buf, "Max r");
        call Serial.print_int(buf, i);
        call Serial.print_str(buf, ":=r");
        call Serial.print_int(buf, instr[1]);
        call Serial.print_str(buf, " ==> " );

        if ( p->regs[instr[1]-1] >= 0 ) {
          call Serial.print_int(buf, p->regs[i-1]);
        } else {
          call Serial.print_str(buf, "-");
          call Serial.print_int(buf, (uint8_t)(-p->regs[i-1]));
        }

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
        buf = call Serial.get_buf();
        call Serial.print_str(buf, "Min r");
        call Serial.print_int(buf, i);
        call Serial.print_str(buf, ":=r");
        call Serial.print_int(buf, instr[1]);
        call Serial.print_str(buf, " ==> " );

        if ( p->regs[instr[1]-1] >= 0 ) {
          call Serial.print_int(buf, p->regs[i-1]);
        } else {
          call Serial.print_str(buf, "-");
          call Serial.print_int(buf, (uint8_t)(-p->regs[i-1]));
        }
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
        buf = call Serial.get_buf();
        call Serial.print_str(buf, "Bgz r");
        call Serial.print_int(buf, i);
        call Serial.print_str(buf, ",");

        if ( instr[1] >= 0 ) {
          call Serial.print_int(buf, instr[1]);
        } else {
          call Serial.print_str(buf, "-");
          call Serial.print_int(buf, (uint8_t)(-instr[1]));
        }

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

        buf = call Serial.get_buf();
        call Serial.print_str(buf, "Bez r");
        call Serial.print_int(buf, i);
        call Serial.print_str(buf, ",");

        if ( instr[1] >= 0 ) {
          call Serial.print_int(buf, instr[1]);
        } else {
          call Serial.print_str(buf, "-");
          call Serial.print_int(buf, (uint8_t)(-instr[1]));
        }

        call Serial.print_buf(buf);
        break;

      case 0xB0:
        (p->pc) += 1 + (int8_t) instr[1];
        dbg("WSNVMM_v", "bra %d\n", (int8_t) instr[1]);
        buf = call Serial.get_buf();
        call Serial.print_str(buf, "Bra ");

         if ( instr[1] >= 0 ) {
          call Serial.print_int(buf, instr[1]);
        } else {
          call Serial.print_str(buf, "-");
          call Serial.print_int(buf, (uint8_t)(-instr[1]));
        }

        call Serial.print_buf(buf);
 
        break;

      case 0xC0:
        dbg("WSNVMM_v", "Led: %d\n",  instr[0]&0x0f);
        buf = call Serial.get_buf();
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
        buf = call Serial.get_buf();
        call Serial.print_str(buf, "Rdb ");
        call Serial.print_int(buf, i);
        call Serial.print_buf(buf);
apps[active_vm].waiting = i;
        request_sense_data(active_vm);
        (p->pc)++;
        break;

      case 0xE0:
        dbg("WSNVMM_v", "Tmr: %d\n", instr[1]);
        buf = call Serial.get_buf();
        call Serial.print_str(buf, "Tmr ");
        call Serial.print_int(buf, instr[1]);
        call Serial.print_buf(buf);

        p->timer_set=1;
        call Timer.startOneShot[active_vm](instr[1]*1000);
        (p->pc)+=2;
        break;
    }

    for ( i=1; i<=MaxApps; i++ ) {
      j = (active_vm+i)%MaxApps;
      if ( apps[j].is_active == 1 && apps[j].waiting == 0 ) {
        if ( apps[j].in_init == 1  || apps[j].timer_active == 1 ) {
          active_vm = j;
          post next_instruction();
          return;
        }
      }
    }
    active_vm = MaxApps;
  }

  default command uint32_t Timer.getNow[int id](){ return 0;}
  default command void Timer.startOneShot[int id](uint32_t milli){}

  event void Timer.fired[int id]()
  {
    apps[id].timer_active = 1;
    apps[id].in_init = 0;
    apps[id].pc = 0;

    dbg("BlinkC", "FIRED %d (%d)\n", id, active_vm);
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
          if ( apps[j].in_init == 1  || apps[j].timer_active == 1 ) {
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
    p->in_init=1;
    p->timer_set=0;
    p->timer_active=0;
    p->waiting = 0;
    p->is_active = 1;

    if ( active_vm == MaxApps ) {
      active_vm = slot;
      post next_instruction();
    }

    return SUCCESS;
  }
}



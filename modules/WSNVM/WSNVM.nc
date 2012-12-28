configuration WSNVM
{
	provides interface WSNVMC as VM;
  provides interface SplitControl;
}
implementation
{
  components new TimerMilliC() as Timer0;
	components new TimerMilliC() as Timer1;
	components new TimerMilliC() as Timer2;
  components new DemoSensorC() as Sensor;
	components new AMSenderC(15);
	components new AMReceiverC(15);

	components ActiveMessageC;
	components WSNBroadcast;
	components WSNVMM;
  components WSNSerial;
  components LedsC;
	
	WSNVMM.BroadcastControl -> WSNBroadcast.SplitControl;
	WSNVMM.Propagate-> WSNBroadcast.WSNBroadcastC[42];
	WSNVMM.BcastStop-> WSNBroadcast.WSNBroadcastC[52];
  WSNVMM.Leds -> LedsC;
	WSNVMM.Read -> Sensor;
  WSNVMM.Timer[0] -> Timer0;
  WSNVMM.Timer[1] -> Timer1;
  WSNVMM.Timer[2] -> Timer2;
	
  WSNVMM.VM = VM;
  WSNVMM.Serial -> WSNSerial;
  WSNVMM.Control = SplitControl;
  WSNVMM.SControl -> WSNSerial;

	WSNVMM.NetSend -> AMSenderC;
	WSNVMM.NetReceive ->AMReceiverC;
	WSNVMM.NetControl -> ActiveMessageC;
	WSNVMM.AMPacket -> ActiveMessageC;
	WSNVMM.Packet -> ActiveMessageC;
}

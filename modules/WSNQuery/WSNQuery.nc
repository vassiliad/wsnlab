configuration WSNQuery
{
	provides interface SplitControl;
	provides interface WSNQueryC as Query;
}
implementation
{
  components WSNBroadcast, ActiveMessageC;
  components new TimerMilliC() as Timer;
	components new TimerMilliC() as Timer2;
	components WSNQueryM;
	components RandomC;
	components new AMSenderC(2);
  components new AMReceiverC(2);
  components LedsC;

  WSNQueryM.Leds -> LedsC;
	WSNQueryM.Prop -> Timer2;
	WSNQueryM.Packet -> ActiveMessageC;
	WSNQueryM.PacketAcknowledgements -> ActiveMessageC;
	WSNQueryM.SubSend -> AMSenderC;
	WSNQueryM.SubRecv -> AMReceiverC;
	WSNQueryM.Random -> RandomC;
	WSNQueryM.BroadcastControl -> WSNBroadcast;
  WSNQueryM.Broadcast -> WSNBroadcast.WSNBroadcastC[0];
	WSNQueryM.Fallback -> WSNBroadcast.WSNBroadcastC[1];
  WSNQueryM.AMPacket -> ActiveMessageC;
  WSNQueryM.Tick -> Timer;
	WSNQueryM.SplitControl = SplitControl;
	WSNQueryM.Query = Query;
}

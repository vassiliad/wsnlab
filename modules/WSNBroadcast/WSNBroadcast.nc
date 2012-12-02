configuration WSNBroadcast
{
  provides interface SplitControl;
  provides interface WSNBroadcastC[uint8_t id];
}
implementation
{
  components WSNBroadcast2M as WSNBroadcastM, ActiveMessageC;
  components new AMSenderC(1);
  components new AMReceiverC(1);
  components RandomC;
  components new TimerMilliC() as Timer;
  components LedsC;

  SplitControl = WSNBroadcastM.SplitControl;
  WSNBroadcastC = WSNBroadcastM.Broadcast;
  WSNBroadcastM.Leds -> LedsC;
  WSNBroadcastM.AMControl -> ActiveMessageC;

  WSNBroadcastM.AMSend    -> AMSenderC;
  WSNBroadcastM.AMReceive -> AMReceiverC;
  WSNBroadcastM.AMPacket  -> ActiveMessageC;
  WSNBroadcastM.Packet  -> ActiveMessageC;

  WSNBroadcastM.Random -> RandomC;

  WSNBroadcastM.TmrSend -> Timer;
}

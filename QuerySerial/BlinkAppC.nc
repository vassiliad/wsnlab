configuration BlinkAppC
{
}
implementation
{
  components MainC, BlinkC, WSNQuery, LedsC;
  components new TimerMilliC() as Timer;
  components SerialActiveMessageC as AM;
  components new DemoSensorC() as Sensor;
  
  BlinkC -> MainC.Boot;
  BlinkC.Leds -> LedsC;
  BlinkC.Sensor -> Sensor;
  BlinkC.SRecv -> AM.Receive[0];
  BlinkC.SSend -> AM.AMSend[0];
  BlinkC.SControl -> AM;
  BlinkC.Timer     -> Timer;
  BlinkC.Query -> WSNQuery;
	BlinkC.QueryControl -> WSNQuery;
  BlinkC.Leds -> LedsC;
}


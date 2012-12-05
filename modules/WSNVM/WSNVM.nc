configuration WSNVM
{
	provides interface WSNVMC as VM;
}
implementation
{
  components new TimerMilliC() as Timer0;
	components new TimerMilliC() as Timer1;
	components new TimerMilliC() as Timer2;
  components new DemoSensorC() as Sensor;
	components WSNVMM;
  components LedsC;

  WSNVMM.Leds -> LedsC;
	WSNVMM.Read -> Sensor;
  WSNVMM.Timer[0] -> Timer0;
  WSNVMM.Timer[1] -> Timer1;
  WSNVMM.Timer[2] -> Timer2;
	WSNVMM.VM = VM;
}

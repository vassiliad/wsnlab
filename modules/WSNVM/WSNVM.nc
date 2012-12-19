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
	components WSNVMM;
  components WSNSerial;
  components LedsC;

  WSNVMM.Leds -> LedsC;
	WSNVMM.Read -> Sensor;
  WSNVMM.Timer[0] -> Timer0;
  WSNVMM.Timer[1] -> Timer1;
  WSNVMM.Timer[2] -> Timer2;
	
  WSNVMM.VM = VM;
  WSNVMM.Serial -> WSNSerial;
  WSNVMM.Control = SplitControl;
  WSNVMM.SControl -> WSNSerial;
}

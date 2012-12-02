configuration BlinkAppC
{
}
implementation
{
  components MainC, BlinkC, WSNQuery, LedsC;
  components new TimerMilliC() as Timer;


  BlinkC -> MainC.Boot;

  BlinkC.Timer     -> Timer;
  BlinkC.Query -> WSNQuery;
	BlinkC.QueryControl -> WSNQuery;
  BlinkC.Leds -> LedsC;
}


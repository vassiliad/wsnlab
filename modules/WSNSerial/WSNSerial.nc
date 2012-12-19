configuration WSNSerial
{
  provides interface WSNSerialC;
  provides interface SplitControl;
}
implementation
{
  components WSNSerialM;
  components SerialActiveMessageC as AM;

  SplitControl = WSNSerialM.SplitControl;
  WSNSerialC = WSNSerialM.WSNSerialC;
  WSNSerialM.SRecv -> AM.Receive[0];
  WSNSerialM.SSend -> AM.AMSend[0];
  WSNSerialM.SControl -> AM;
}


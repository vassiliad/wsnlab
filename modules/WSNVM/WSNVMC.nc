interface WSNVMC {
  command error_t upload_binary(void *binary, uint8_t id, uint16_t sink, uint8_t hops);
	command error_t propagate_binary(void *binary,uint8_t len, uint8_t id, uint8_t hops);
  command error_t stop_application(uint8_t id);
  command error_t start_application(uint8_t id);
}

interface WSNBroadcastC {
  command error_t send(void *data, uint8_t len);
	command error_t sendHops(void *data, uint8_t len, uint8_t max_hops);
  event void receive(nx_uint8_t *data, uint8_t len, uint16_t source, uint16_t last_hop, uint8_t hops);
}

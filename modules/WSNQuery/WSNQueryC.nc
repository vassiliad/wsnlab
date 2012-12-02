interface WSNQueryC {
	command error_t query(uint8_t period, uint16_t lifetime);
	event   error_t query_sense();
  command void query_new_sense(uint16_t value);
	event	  void    query_result(uint16_t value, uint16_t source, uint8_t in_packet);
}

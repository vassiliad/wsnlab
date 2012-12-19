interface WSNSerialC {
  command uint8_t get_buf();
  command void print_str(uint8_t id, char *str);
  command void print_int(uint8_t id, uint8_t integer);
  command void print_buf(uint8_t id);

  event void receive(void* payload, uint8_t len);
}

interface WSNVMC {
  command error_t upload_binary(void *binary, uint8_t id);
  command error_t stop_application(uint8_t id);
  command error_t start_application(uint8_t id);
}

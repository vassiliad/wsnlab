xscale-elf-objcopy --output-target=binary build/intelmote2/main.exe build/intelmote2/main.bin.out
/opt/tinyos-2.x/tools/platforms/intelmote2/openocd/imote2-ocd-program.py build/intelmote2/main.bin.out

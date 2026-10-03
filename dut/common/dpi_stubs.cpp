// CVA6's source list exposes debug transport DPI declarations even though
// system_top does not instantiate either testbench transport.
extern "C" int debug_tick(unsigned char*, unsigned char, int*, int*, int*,
                           unsigned char, unsigned char*, int, int) {
    return 0;
}

extern "C" int jtag_tick(unsigned char*, unsigned char*, unsigned char*,
                          unsigned char*, unsigned char) {
    return 0;
}

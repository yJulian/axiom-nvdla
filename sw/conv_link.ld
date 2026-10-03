ENTRY(_start)
SECTIONS {
  . = 0x80000000;
  .text : { *(.text.start) *(.text*) *(.rodata*) *(.data*) }
  . = 0x80010000;
  .conv_input : { *(.conv_input) }
  . = 0x80020000;
  .conv_weight : { *(.conv_weight) }
  . = 0x80050000;
  .bss (NOLOAD) : { *(.bss*) *(COMMON) }
}

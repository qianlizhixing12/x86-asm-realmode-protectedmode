SECTIONS
{
    . = 0;
    .header : { *(.header) }
    .code   : { *(.code) }
    .code_1 : { *(.code_1) }
    .code_2 : { *(.code_2) }
    .data   : { *(.data) }
    .data_1 : { *(.data_1) }
    .data_2 : { *(.data_2) }
    .stack  : { *(.stack) }
    .trail  : { *(.trail) }
}
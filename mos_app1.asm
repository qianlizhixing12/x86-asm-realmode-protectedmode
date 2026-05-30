SECTION header vstart=0
    program_length   dd program_end              ;程序总长度#0x00
    entry_point      dd start                    ;程序入口点#0x04

SECTION data vfollows=header
    message_1 db '[USER TASK1]: CCCCCCCCCCCCCCCCCCCCCCC', 0x0d, 0x0a, 0
    reserved  times 4096*5 db 0             ;保留一个空白区，以演示分页

[bits 32]
SECTION code vfollows=data
start:
    mov eax, 0
    mov ebx, message_1
    int 0x88
    jmp start


SECTION trail
program_end:

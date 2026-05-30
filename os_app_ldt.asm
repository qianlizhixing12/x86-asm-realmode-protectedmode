SECTION header vstart=0
    ;程序总长度#0x00
    program_length   dd program_end
    ;程序头部的长度#0x04
    head_len         dd header_end
    ;程序入口#0x08
    prgentry         dd start
    ;代码段位置#0x0c
    code_seg         dd section.code.start
    ;代码段长度#0x10 
    code_len         dd code_end
    ;数据段位置#0x14
    data_seg         dd section.data.start
    ;数据段长度#0x18
    data_len         dd data_end
    ;栈段位置#0x1c
    stack_seg        dd section.stack.start
    ;栈段长度#0x20
    stack_len        dd stack_end
    ;符号地址检索表#0x24
    salt_items       dd (header_end-salt)/256
    ;#0x28
    salt:
    PrintString      db  '@PrintString'
                     times 256-($-PrintString) db 0
    TerminateProgram db  '@TerminateProgram'
                     times 256-($-TerminateProgram) db 0
    ReadDiskData     db  '@ReadDiskData'
                     times 256-($-ReadDiskData) db 0
header_end:

SECTION data vstart=0
;缓冲区
buffer times 1024 db  0
message_1         db  0x0d, 0x0a, 0x0d, 0x0a
                  db  '**********User program is runing**********'
                  db  0x0d, 0x0a, 0
message_2         db  'Disk data:', 0x0d, 0x0a, 0
data_end:


SECTION stack vstart=0
    ;保留2KB的栈空间
    times 2048    db 0
stack_end:


[bits 32]
SECTION code vstart=0
start:
    mov eax, ds
    mov fs, eax

    mov ss, fs:[stack_seg]
    mov esp, stack_end

    mov ds, fs:[data_seg]

    mov ebx, message_1
    call far [fs:PrintString]

    ;逻辑扇区号100
    mov esi, 100
    ;缓冲区偏移地址
    mov edi, buffer
    ;段间调用
    call far [fs:ReadDiskData]

    mov ebx, message_2
    call far [fs:PrintString]

    mov ebx, buffer
    call far [fs:PrintString]

    ;将控制权返回到系统
    call far [fs:TerminateProgram]
code_end:

SECTION trail
program_end:

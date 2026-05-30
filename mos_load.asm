%include 'mos_config.asm'

section .mbr vstart=0x7c00
start:
    xor ax, ax
    mov ds, ax
    mov ss, ax
    mov sp, 0x7c00

    ;计算GDT所在的逻辑数据段地址
    mov eax, cs:[pgdt+0x02]
    xor edx, edx
    mov ebx, 16
    div ebx
    mov ds, eax                                  ;令DS指向该段以进行操作
    mov ebx, edx                                 ;段内起始偏移地址

    ;创建0#描述符，它是空描述符，这是处理器的要求
    mov dword ds:[ebx+0x00], 0x00000000
    mov dword ds:[ebx+0x04], 0x00000000
    ;创建1#描述符，保护模式下的代码段描述符
    ;基地址为0x00000000，段界限为0xfffff，粒度为4KB，总共4GB，特权级为0，代码段描述符向上扩展（c=1100 98=10011000）
    mov dword ds:[ebx+0x08], 0x0000_ffff
    mov dword ds:[ebx+0x0c], 0x00_c_f_98_00
    ;创建2#描述符，保护模式下的数据段和堆栈段描述符
    ;基地址为0x00000000，段界限为0xfffff，粒度为4KB，总共4GB，特权级为0，数据段描述符向上扩展(c=1100 92=10010010)
    mov dword ds:[ebx+0x10], 0x0000_ffff
    mov dword ds:[ebx+0x14], 0x00_c_f_92_00
    ;创建3#描述符，保护模式下的代码段描述符
    ;基地址为0x00000000，段界限为0xfffff，粒度为4KB，总共4GB，特权级为3，代码段描述符向上扩展（c=1100 f8=11111000）
    mov dword ds:[ebx+0x18], 0x0000_ffff
    mov dword ds:[ebx+0x1c], 0x00_c_f_f8_00
    ;创建4#描述符，保护模式下的数据段和堆栈段描述符，特权级为3
    ;基地址为0x00000000，段界限为0xfffff，粒度为4KB，总共4GB，特权级为3，数据段描述符向上扩展(c=1100 f2=11110010)
    mov dword ds:[ebx+0x20], 0x0000_ffff
    mov dword ds:[ebx+0x24], 0x00_c_f_f2_00

    mov word cs:[pgdt], 39                       ;描述符表的界限（总字节数减一）
    lgdt cs:[pgdt]                               ;初始化描述符表寄存器GDTR

    ;南桥芯片内的端口，打开A20
    in al, 0x92
    or al, 0000_0010B
    out 0x92, al

    cli                                          ;保护模式下中断机制未建立，禁止中断
    mov eax, cr0
    or eax, 1
    mov cr0, eax                                 ;设置PE位，开启保护模式

    jmp dword flat_core_code_seg_sel:flush       ;以下进入保护模式跳到flush

[bits 32]
flush:
    ;加载段选择子
    mov eax, flat_core_data_seg_sel
    mov ds, eax
    mov es, eax
    mov fs, eax
    mov gs, eax
    mov ss, eax
    mov esp, 0x7c00                              ;堆栈指针

  .read_core_size:
    mov eax, core_start_sector
    mov ebx, core_base_address
    call read_hard_disk_0

    ;以下判断整个程序有多大
    mov eax, ds:[core_base_address]
    xor edx, edx
    mov ecx, 512
    div ecx

    or edx, edx
    jnz .div_eq_zero                             ;未除尽，结果刚好等于剩余读取扇区加多度一个扇区
    dec eax                                      ;已经读了一个扇区，扇区总数减1
  .div_eq_zero:
    or eax, eax
    jz setup

    mov ecx, eax                                 ;循环次数（剩余扇区数）
    mov eax, core_start_sector
  .load_core:
    inc eax
    call read_hard_disk_0
    loop .load_core

setup:
  ;准备打开分页机制。从此，再也不用在段之间转来转去，实在晕乎~
  .pdt:                                          ;创建系统内核的页目录表PDT
    mov ebx, 0x00020000                          ;页目录的物理地址
    mov ecx, 1024                                ;1024个目录项
    xor esi, esi
  .pdt_zero:
    mov dword es:[ebx+esi], 0x00000000           ;页目录表项清零
    add esi, 4
    loop .pdt_zero

  .pdt_init:
    mov dword ds:[ebx+4092], 0x00020003          ;在页目录内创建指向页目录表自己的目录项
    mov dword ds:[ebx+0], 0x00021003             ;在页目录内创建与线性地址0x00000000对应的目录项,此目录项仅用于过渡
    mov dword ds:[ebx+2048], 0x00021003          ;在页目录内创建与线性地址0x80000000对应的目录项

  .pt:                                           ;创建与上面那个目录项相对应的页表，初始化页表项
    mov ebx, 0x00021000                          ;页表的物理地址
    xor eax, eax                                 ;起始页的物理地址
    xor esi, esi
  .pt_init:
    mov edx, eax
    or edx, 0x00000003
    mov ds:[ebx+esi*4], edx                      ;登记页的物理地址
    add eax, 0x1000                              ;下一个相邻页的物理地址
    inc esi
    cmp esi, 256                                 ;仅低端1MB内存对应的页才是有效的
    jl .pt_init

  .pt_zero:                                      ;其余的页表项置为无效
    mov dword es:[ebx+esi*4], 0x00000000
    add esi, 4
    cmp esi, 1024
    jl .pt_zero

  ;令CR3寄存器指向页目录，并正式开启页功能
  .page_open:
    mov eax, 0x00020000                          ;00000000000000100000_000000000000B PCD=PWT=0
    mov cr3, eax
    mov eax, cr0
    or eax, 0x80000000
    mov cr0, eax                                 ;开启分页机制

  ;将GDT的线性地址映射到从0x80000000开始的相同位置
  .gdt:
    sgdt ds:[pgdt]
    add dword ds:[pgdt+2], 0x80000000            ;GDTR也用的是线性地址
    lgdt ds:[pgdt]

    ;将堆栈映射到高端，这是非常容易被忽略的一件事。应当把内核的所有东西都移到高端，否则，一定会和正在加载的用户任务局部空间里的内容冲突，而且很难想到问题会出在这里
    add esp, 0x80000000

  .start:
    jmp [ds:0x80040000+0x4]

;从硬盘读取一个逻辑扇区
;输入：EAX=逻辑扇区号
;输入：DS:EBX=目标缓冲区地址
;输出：EBX=EBX+512
read_hard_disk_0:
    push eax
    push ecx
    push edx

    push eax

    mov dx, 0x1f2
    mov al, 1                                          ;读取的扇区数
    out dx, al

    mov dx, 0x1f3
    pop eax
    out dx, al                                         ;LBA地址7~0

    mov dx, 0x1f4
    shr eax, 8
    out dx, al                                         ;LBA地址15~8

    mov dx, 0x1f5
    shr eax, 8
    out dx, al                                         ;LBA地址23~16

    mov dx, 0x1f6
    shr eax, 8
    or al, 0xe0
    out dx, al                                         ;LBA地址27~24

    mov dx, 0x1f7
    mov al, 0x20                                       ;读命令
    out dx, al

  .waits:
    in al, dx
    and al, 0x88
    cmp al, 0x08
    jnz .waits                                         ;不忙，且硬盘已准备好数据传输

    mov ecx, 256                                       ;总共要读取的字数
    mov dx, 0x1f0
  .readw:
    in ax, dx
    mov ds:[ebx], ax
    add ebx, 2
    loop .readw

    pop edx
    pop ecx
    pop eax
    ret

pgdt dw 0                                              ;GDT大小
     dd 0x00007e00                                     ;GDT物理地址

times 510-($-$$) db 0
dw  0xaa55
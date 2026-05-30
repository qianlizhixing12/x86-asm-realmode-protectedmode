;内核的大部分内容都应当固定
mem_4gb_data_seg_sel equ 0x0008       ;4GB数据段的段选择子，0x0008=0000000000001_000B
mbr_code_seg_sel     equ 0x0010       ;mbr代码段的段选择子，0x0010=0000000000010_000B
mem_stack_seg_sel    equ 0x0018       ;栈段的段选择子，0x0018=0000000000011_000B
video_ram_seg_sel    equ 0x0020       ;视频显示缓冲区的段选择子，0x0020=0000000000100_000B
sys_routine_seg_sel  equ 0x0028       ;系统公共例程代码段的选择子，0x0028=0000000000101_000B
core_data_seg_sel    equ 0x0030       ;内核数据段选择子，0x0030=0000000000110_000B
core_code_seg_sel    equ 0x0038       ;内核代码段选择子，0x0038=0000000000111_000B
;用户程序的起始逻辑扇区号50
app_start_sector     equ 0x00000032

;系统核心的头部，用于加载核心程序
section header vstart=0
    ;                                                   编译后                   加载重定向后
    core_length      dd core_end                       ;[0x00]核心程序总长度
    sys_routine_seg  dd section.sys_routine.start      ;[0x04]系统公用例程段位置
    core_data_seg    dd section.core_data.start        ;[0x08]核心数据段位置
    core_code_seg    dd section.core_code.start        ;[0x0c]核心代码段位置
    core_entry       dd start                          ;[0x10]核心代码段入口点
                     dw core_code_seg_sel              ;[0x14]

[bits 32]
SECTION sys_routine vstart=0
;字符串显示例程，显示0终止的字符串并移动光标
;输入：DS:EBX=串地址
put_string:
    push eax
    push ebx
    push ecx

    ;获取光标位置存在ax中
    call get_cursor
  .getc:
    mov cl, ds:[ebx]
    ;cl=0？
    or cl, cl
    jz .exit
    ;回车符？
    cmp cl, 0x0d
    jz .cr
    ;换行符？
    cmp cl, 0x0a
    jz .lf
    ;那就正常显示字符
    call put_char
    jmp .next_char
  ;光标移动到当前行的第一列
  .cr:
    mov cl, 80
    div cl
    mul cl
    call set_cursor
    jmp .next
  ;光标移动到下一行，列位置不变
  .lf:
    add eax, 80
    call roll_screen
    jmp .next
  ;以下将光标位置推进一个字符
  .next_char:
    add eax, 1
    call roll_screen
  ;下一个字符
  .next:
    inc ebx
    jmp .getc

  .exit:
    pop ecx
    pop ebx
    pop eax
    retf

;获取光标，输出：eax=光标位置,仅用于段内调用
get_cursor:
    push edx

    xor eax, eax

    mov dx, 0x3d4
    ;光标位置高字节
    mov al, 0x0e
    out dx, al
    mov dx, 0x3d5
    in al, dx
    mov ah, al
    ;光标位置低字节
    mov dx, 0x3d4
    mov al, 0x0f
    out dx, al
    mov dx, 0x3d5
    in al, dx

    pop edx
    ret

;设置光标，输入：eax=光标位置,仅用于段内调用
set_cursor:
    push eax
    push ebx
    push edx

    mov ebx, eax

    mov dx, 0x3d4
    mov al, 0x0e
    out dx, al
    mov dx, 0x3d5
    mov al, bh
    out dx, al
    mov dx, 0x3d4
    mov al, 0x0f
    out dx, al
    mov dx, 0x3d5
    mov al, bl
    out dx, al

    ; popad
    pop edx
    pop ebx
    pop eax
    ret

;判断光标是否超出屏幕滚屏，输入：eax=光标位置，输出：eax=光标位置,仅用于段内调用
roll_screen:
    cmp eax, 2000
    jl .exit

    push ebx
    push ecx
    push ds
    push es
    push esi
    push edi

    ;第二行～第二十五行向上移动
    mov ebx, video_ram_seg_sel
    mov ds, ebx
    mov es, ebx
    cld
    mov esi, 0xa0
    mov edi, 0x00
    mov ecx, 1920
    rep movsw

    ;清除屏幕最底一行
    mov ebx, 3840
    mov ecx, 80
  .cls:
    mov word es:[ebx], 0x0720
    add ebx, 2
    loop .cls
    sub eax, 80

    pop edi
    pop esi
    pop es
    pop ds
    pop ecx
    pop ebx
    ret

  .exit:
    call set_cursor
    ret

;显示单个字符，输入：cl=字符ascii，eax=光标位置,仅用于段内调用
put_char:
    push eax
    push ebx
    push es

    mov ebx, video_ram_seg_sel
    mov es, ebx
    ;一个字符在显存中对应两个字节，这里必须乘以2
    shl eax, 1
    mov es:[eax], cl

    pop es
    pop ebx
    pop eax
    ret

;-------------------------------------------------------------------------------
;此例程用于说明如何通过请求特权级RPL解决因请求者身份与CPL不同而带来的安全问题
;read_hard_disk_with_gate:                  ;从硬盘读取一个逻辑扇区
                                            ;输入：PUSH 逻辑扇区号
                                            ;      PUSH 目标缓冲区所在段的选择子
                                            ;      PUSH 目标缓冲区在段内的偏移量
                                            ;返回：无
         ;push eax
         ;push ebx
         ;push ecx

         ;mov ax,[esp+0x10]                  ;获取调用者的CS
         ;arpl [esp+0x18],ax                 ;将数据段选择子调整到真实的请求特权级别
         ;mov ds,[esp+0x18]                  ;用真实的段选择子加载段寄存器DS

         ;mov eax,[esp+0x1c]                 ;从栈中取得逻辑扇区号
         ;mov ebx,[esp+0x14]                 ;从栈中取得缓冲区在段内的偏移量

         ;此部分的功能是读硬盘，并传送到缓冲区，予以省略。

         ;retf 12

;从硬盘读取一个逻辑扇区
;输入：ESI=逻辑扇区号
;输入：DS:EDI=目标缓冲区地址
;输出：EDI=EDI+512
read_hard_disk_0:
    push eax
    push ebx
    push ecx
    push edx

    mov dx, 0x1f2
    ;读取的扇区数
    mov al, 1
    out dx, al

    mov dx, 0x1f3
    mov eax, esi
    ;LBA地址7~0
    out dx, al

    mov dx, 0x1f4
    shr eax, 8
    ;LBA地址15~8
    out dx, al

    mov dx, 0x1f5
    shr eax, 8
    ;LBA地址23~16
    out dx, al

    mov dx, 0x1f6
    shr eax, 8
    or al, 0xe0
    ;LBA地址27~24
    out dx, al

    mov dx, 0x1f7
    ;读命令
    mov al, 0x20
    out dx, al

  .waits:
    in al, dx
    and al, 0x88
    cmp al, 0x08
    ;不忙，且硬盘已准备好数据传输
    jnz .waits

    ;总共要读取的字数
    mov ecx, 256
    mov dx, 0x1f0
  .readw:
    in ax, dx
    mov ds:[edi], ax
    add edi, 2
    loop .readw

    pop edx
    pop ecx
    pop ebx
    pop eax
    retf

;分配内存
;输入：ECX=希望分配的字节数
;输出：ECX=起始线性地址
allocate_memory:
    push eax
    push ebx
    push ds

    mov eax, core_data_seg_sel
    mov ds, eax

    ;下一次分配时的起始地址
    mov eax, ds:[ram_alloc]
    add eax, ecx

    ;这里应当有检测可用内存数量的指令
    ;返回分配的起始地址
    mov ecx, ds:[ram_alloc]

    mov ebx, eax
    ;强制对齐
    and ebx, 0xfffffffc
    add ebx, 4
    ;下次分配的起始地址最好是4字节对齐
    test eax, 0x00000003
    ;如果没有对齐，则强制对齐
    cmovnz eax, ebx
    ;下次从该地址分配内存
    mov ds:[ram_alloc], eax

    pop ds
    pop ebx
    pop eax
    retf

;构造存储器和系统的段描述符
;输入：EAX=线性基地址
;输入：EBX=段界限
;输入：ECX=属性（各属性位都在原始位置，其它没用到的位置0）
;输出：EDX:EAX=完整的描述符
make_seg_descriptor:
    mov edx, eax
    shl eax, 16
    ;描述符前32位(EAX)构造完毕
    or ax, bx

    ;清除基地址中无关的位
    and edx, 0xffff0000
    rol edx, 8
    ;装配基址的31~24和23~16(80486+)
    bswap edx

    xor bx, bx
    ;装配段界限的高4位
    or edx, ebx
    ;装配属性
    or edx, ecx

    retf

;构造门的描述符（调用门等）
;输入：EAX=门代码在段内偏移地址
;输入：EBX=门代码所在段的选择子
;输入：ECX=段类型及属性等（各属性位都在原始位置）
;输出：EDX:EAX=完整的描述符
make_gate_descriptor:
    push ebx
    push ecx

    ;组装调用门的高双字部分
    mov edx, eax
    mov dx, cx

    ;得到偏移地址低16位
    and eax, 0x0000ffff
    shl ebx, 16
    ;组装段选择子部分
    or eax, ebx

    pop ecx
    pop ebx
    retf

;在GDT内安装一个新的描述符
;输入：EDX:EAX=描述符
;输出：CX=描述符的选择子
set_up_gdt_descriptor:
    push eax
    push ebx
    push edx
    push ds
    push es

    ;切换到核心数据段
    mov ebx, core_data_seg_sel
    mov ds, ebx
    mov ebx, mem_4gb_data_seg_sel
    mov es, ebx

    ;获取GDT
    sgdt ds:[pgdt]

    ;GDT界限
    movzx ebx, word ds:[pgdt]
    ;GDT总字节数，也是下一个描述符偏移
    inc ebx
    ;下一个描述符的线性地址
    add ebx, ds:[pgdt+2]

    mov es:[ebx], eax
    mov es:[ebx+4], edx
    ;增加一个描述符的大小
    add word ds:[pgdt], 8

    ;对GDT的更改生效
    lgdt ds:[pgdt]

    ;得到GDT界限值
    mov ax, ds:[pgdt]
    xor dx, dx
    mov bx, 8
    div bx
    mov cx, ax
    ;将索引号移到正确位置
    shl cx, 3

    pop es
    pop ds
    pop edx
    pop ebx
    pop eax
    retf

SECTION core_data vstart=0
    msg_os  db 'We are now in protect mode, and the system core is loaded, '
            db 'and the video display routine works perfectly.'
            db 0x0d, 0x0a, 0x0d, 0x0a, 0
    msg_gate       db 'System wide CALL-GATE mounted.', 0x0d, 0x0a, 0
    msg_user_load  db 'Loading user program...', 0x0d, 0x0a, 0
    msg_user_run   db 'Run user program...', 0x0d, 0x0a, 0
    msg_user_ret   db 'User program terminated, control returned.', 0x0d, 0x0a, 0
    ;内核用的缓冲区
    core_buf times 2048 db 0
    ;下次分配内存时的起始地址
    ram_alloc      dd 0x00100000
    ;用于设置和修改GDT
    pgdt    dw 0
            dd 0
    ;任务控制块链
    tcb_chain   dd 0
    ;符号地址检索表
    salt:
    salt_1  db  '@PrintString'
              times 256-($-salt_1) db 0
              dd  put_string
              dw  sys_routine_seg_sel
    salt_2  db  '@ReadDiskData'
              times 256-($-salt_2) db 0
              dd  read_hard_disk_0
              dw  sys_routine_seg_sel
    salt_3  db  '@TerminateProgram'
              times 256-($-salt_3) db 0
              dd  return_point
              dw  core_code_seg_sel
    salt_item_len   equ $-salt_3
    salt_items      equ ($-salt)/salt_item_len

SECTION core_code vstart=0
;在LDT内安装一个新的描述符
;输入：EDX:EAX=描述符
;输入：EBX=TCB基地址
;输出：CX=描述符的选择子
fill_descriptor_in_ldt:
    push eax
    push edx
    push edi
    push ds

    mov ecx, mem_4gb_data_seg_sel
    mov ds, ecx

    ;获得LDT基地址
    mov edi, ds:[ebx+0x0c]
    ;获得LDT界限
    xor ecx, ecx
    mov cx, ds:[ebx+0x0a]
    ;LDT的总字节数，即新描述符偏移地址
    inc cx

    ;安装描述符
    mov ds:[edi+ecx+0x00], eax
    mov ds:[edi+ecx+0x04], edx
    ;得到新的LDT界限值
    add cx, 8
    dec cx
    ;更新LDT界限值到TCB
    mov ds:[ebx+0x0a], cx

    mov ax, cx
    xor dx, dx
    mov cx, 8
    div cx

    ;左移3位，并且使TI位=1，指向LDT，最后使RPL=00
    mov cx, ax
    shl cx, 3
    or cx, 0000_0000_0000_0100B

    pop ds
    pop edi
    pop edx
    pop eax
    ret

;加载并重定位用户程序
;输入: PUSH 逻辑扇区号
;输入: PUSH 任务控制块基地址
load_relocate_program:
    pushad
    push ds
    push es

    mov ecx, mem_4gb_data_seg_sel
    mov es, ecx

    ;为访问通过堆栈传递的参数做准备
    mov ebp, esp

    ;从堆栈中取得TCB的基地址
    mov esi, ss:[ebp+11*4]
    ;以下申请创建LDT所需要的内存，允许安装20个LDT描述符
    mov ecx, 160
    call sys_routine_seg_sel:allocate_memory
    ;登记LDT基地址到TCB中
    mov es:[esi+0x0c], ecx
    ;登记LDT初始的界限到TCB中
    mov word es:[esi+0x0a], 0xffff

    ;以下开始加载用户程序
    mov eax, core_data_seg_sel
    ;切换DS到内核数据段
    mov ds, eax

    ;从堆栈中取出用户程序起始扇区号
    mov esi, ss:[ebp+12*4]
    ;读取程序头部数据 
    mov edi, core_buf
    call sys_routine_seg_sel:read_hard_disk_0

    ;程序尺寸
    mov eax, ds:[core_buf]
    ;使之512字节对齐（能被512整除的数，低9位都为0）
    mov ebx, eax
    and ebx, 0xfffffe00
    add ebx, 512
    ;程序的大小正好是512的倍数吗?
    test eax, 0x000001ff
    ;不是使用凑整的结果
    cmovnz eax, ebx

    ;实际需要申请的内存数量
    mov ecx, eax
    call sys_routine_seg_sel:allocate_memory
    ;登记程序加载基地址到TCB中
    mov esi, ss:[ebp+11*4]
    mov es:[esi+0x06], ecx
    ;申请到的内存首地址
    mov edi, ecx
    mov esi, ss:[ebp+12*4]

    ;总扇区数
    xor edx, edx
    mov ecx, 512
    div ecx
    mov ecx, eax

    ;临时变量 bx=程序尺寸512对齐 edi=申请到的内存首地址 ecx=总扇区数
    ;切换DS到0-4GB的段
    mov eax, mem_4gb_data_seg_sel
    mov ds, eax
  .read_program:
    call sys_routine_seg_sel:read_hard_disk_0
    inc esi
    ;循环读，直到读完整个用户程序
    loop .read_program

    ;建立程序头部段描述符
    ;获得程序加载基地址
    mov esi, ss:[ebp+11*4]
    mov edi, es:[esi+0x06]
    ;程序头部起始线性地址
    mov eax, edi
    mov ebx, ds:[edi+0x04]
    ;段界限
    dec ebx
    ;字节粒度的数据段描述符，特权级3
    mov ecx, 0x0040f200
    call sys_routine_seg_sel:make_seg_descriptor
    ;安装头部段描述符到LDT中
    ;TCB的基地址
    mov ebx, esi
    call fill_descriptor_in_ldt
    ;设置选择子的特权级为3
    or cx, 0000_0000_0000_0011B
    ;登记程序头部段选择子到TCB和头部内
    mov es:[esi+0x44], cx
    mov ds:[edi+0x04], cx

    ;建立程序代码段描述符
    ;代码起始线性地址
    mov eax, edi
    add eax, ds:[edi+0x0c]
    ;段长度
    mov ebx, ds:[edi+0x10]
    ;段界限
    dec ebx
    ;字节粒度的代码段描述符，特权级3
    mov ecx, 0x0040f800
    call sys_routine_seg_sel:make_seg_descriptor
    ;TCB的基地址
    mov ebx, esi
    call fill_descriptor_in_ldt
    ;设置选择子的特权级为3
    or cx, 0000_0000_0000_0011B
    ;登记代码段选择子到头部
    mov ds:[edi+0x0c], cx

    ;建立程序数据段描述符
    ;数据段起始线性地址
    mov eax, edi
    add eax, ds:[edi+0x14]
    ;段长度
    mov ebx, ds:[edi+0x18]
    ;段界限
    dec ebx
    ;字节粒度的数据段描述符，特权级3
    mov ecx, 0x0040f200
    call sys_routine_seg_sel:make_seg_descriptor
    ;TCB的基地址
    mov ebx, esi
    call fill_descriptor_in_ldt
    ;设置选择子的特权级为3
    or cx, 0000_0000_0000_0011B
    ;登记数据段选择子到头部
    mov ds:[edi+0x14], cx

    ;建立程序堆栈段描述符
    ;数据段起始线性地址
    mov eax, edi
    add eax, ds:[edi+0x1c]
    ;段长度
    mov ebx, ds:[edi+0x20]
    ;段界限
    dec ebx
    ;字节粒度的堆栈段描述符，特权级3
    mov ecx, 0x0040f200
    call sys_routine_seg_sel:make_seg_descriptor
    ;TCB的基地址
    mov ebx, esi
    call fill_descriptor_in_ldt
    ;设置选择子的特权级为3
    or cx, 0000_0000_0000_0011B
    ;登记堆栈段选择子到头部
    mov ds:[edi+0x1c], cx

    ;重定位SALT
    ;这里和前一章不同，头部段描述符已安装，但还没有生效，故只能通过4GB段访问用户程序头部
    mov eax, mem_4gb_data_seg_sel
    mov es, eax
    mov eax, core_data_seg_sel
    mov ds, eax

    cld

    ;U-SALT条目数(通过访问4GB段取得)
    mov ecx, es:[edi+0x24]
    ;U-SALT在4GB段内的偏移
    add edi, 0x28
  .b2:
    push ecx
    push edi

    mov ecx, salt_items
    mov esi, salt
  .b3:
    push edi
    push esi
    push ecx

    ;检索表中，每条目的比较次数
    mov ecx, 64
    ;每次比较4字节
    repe cmpsd
    jnz .b4
    ;若匹配，则esi恰好指向其后的地址
    mov eax, ds:[esi]
    ;将字符串改写成偏移地址
    mov es:[edi-256], eax
    mov ax, ds:[esi+4]
    ;以用户程序自己的特权级使用调用门故RPL=3
    or ax, 0000000000000011B
    ;回填段选择子
    mov es:[edi-252], ax
  .b4:
    pop ecx
    pop esi
    add esi, salt_item_len
    ;回填段选择子从头比较
    pop edi
    loop .b3

    pop edi
    add edi,256
    pop ecx
    loop .b2

    ;从堆栈中取得TCB的基地址
    mov esi, ss:[ebp+11*4]

    ;创建0特权级栈
    ;以4KB为单位的栈段界限值
    mov ecx, 0
    ;登记0特权级栈界限到TCB
    mov es:[esi+0x1a], ecx
    inc ecx
    ;乘以4096，得到段大小
    shl ecx, 12
    push ecx
    call sys_routine_seg_sel:allocate_memory
    ;登记0特权级栈基地址到TCB
    mov es:[esi+0x1e], ecx
    mov eax, ecx
    ;段长度（界限）
    mov ebx, es:[esi+0x1a]
    ;4KB粒度，读写，特权级0
    mov ecx, 0x00c09200
    call sys_routine_seg_sel:make_seg_descriptor
    ;TCB的基地址
    mov ebx, esi
    call fill_descriptor_in_ldt
    ;设置选择子的特权级为0
    ;or cx, 0000_0000_0000_0000
    ;登记0特权级堆栈选择子到TCB
    mov es:[esi+0x22],cx
    ;登记0特权级堆栈初始ESP到TCB
    pop dword es:[esi+0x24]

    ;创建1特权级堆栈
    mov ecx, 0
    ;登记1特权级堆栈尺寸到TCB
    mov es:[esi+0x28], ecx
    inc ecx
    ;乘以4096，得到段大小
    shl ecx, 12
    push ecx
    call sys_routine_seg_sel:allocate_memory
    ;登记1特权级堆栈基地址到TCB
    mov es:[esi+0x2c], ecx
    mov eax, ecx
    ;段长度（界限）
    mov ebx, es:[esi+0x28]
    ;4KB粒度，读写，特权级1
    mov ecx, 0x00c0b200
    call sys_routine_seg_sel:make_seg_descriptor
    ;TCB的基地址
    mov ebx, esi
    call fill_descriptor_in_ldt
    ;设置选择子的特权级为1
    or cx, 0000_0000_0000_0001
    ;登记1特权级堆栈选择子到TCB
    mov es:[esi+0x30], cx
    ;登记1特权级堆栈初始ESP到TCB
    pop dword es:[esi+0x32]

    ;创建2特权级堆栈
    mov ecx, 0
    ;登记2特权级堆栈尺寸到TCB
    mov es:[esi+0x36], ecx
    inc ecx
    ;乘以4096，得到段大小
    shl ecx, 12
    push ecx
    call sys_routine_seg_sel:allocate_memory
    ;登记2特权级堆栈基地址到TCB
    mov es:[esi+0x3a], ecx
    mov eax, ecx
    ;段长度（界限）
    mov ebx, es:[esi+0x36]
    ;4KB粒度，读写，特权级2
    mov ecx, 0x00c0d200
    call sys_routine_seg_sel:make_seg_descriptor
    ;TCB的基地址
    mov ebx, esi
    call fill_descriptor_in_ldt
    ;设置选择子的特权级为2
    or cx, 0000_0000_0000_0010
    ;登记2特权级堆栈选择子到TCB
    mov es:[esi+0x3e], cx
    ;登记2特权级堆栈初始ESP到TCB
    pop dword es:[esi+0x40]

    ;在GDT中登记LDT描述符
    ;LDT的起始线性地址
    mov eax, es:[esi+0x0c]
    ;LDT段界限
    movzx ebx, word es:[esi+0x0a]
    ;LDT描述符，特权级0
    mov ecx, 0x00008200
    call sys_routine_seg_sel:make_seg_descriptor
    call sys_routine_seg_sel:set_up_gdt_descriptor
    ;登记LDT选择子到TCB中
    mov es:[esi+0x10], cx
  
    ;创建用户程序的TSS
    ;tss的基本尺寸
    mov ecx, 104
    mov es:[esi+0x12], cx
    ;登记TSS界限值到TCB
    dec word es:[esi+0x12]
    call sys_routine_seg_sel:allocate_memory
    ;登记TSS基地址到TCB
    mov es:[esi+0x14], ecx

    ;登记基本的TSS表格内容
    ;登记0特权级栈初始ESP到TSS中
    mov edx, es:[esi+0x24]
    mov es:[ecx+4], edx 
    ;登记0特权级栈段选择子到TSS中
    mov dx, es:[esi+0x22]
    mov es:[ecx+8], dx
    ;登记1特权级栈初始ESP到TSS中
    mov edx, es:[esi+0x32]
    mov es:[ecx+12], edx
    ;登记1特权级栈段选择子到TSS中
    mov dx, es:[esi+0x30]
    mov es:[ecx+16], dx
    ;登记2特权级栈初始ESP到TSS中
    mov edx, es:[esi+0x40]
    mov es:[ecx+20], edx
    ;登记2特权级栈段选择子到TSS中
    mov dx, es:[esi+0x3e]
    mov es:[ecx+24], dx
    ;登记任务的LDT选择子到TSS中
    mov dx, es:[esi+0x10]
    mov es:[ecx+96], dx
    ;T=0,I/O位串基地址为103
    mov dword es:[ecx+100], 0x00670000

    ;在GDT中登记TSS描述符
    ;TSS的起始线性地址
    mov eax, es:[esi+0x14]
    ;段长度（界限）
    movzx ebx, word es:[esi+0x12]
    ;TSS描述符，特权级0
    mov ecx, 0x00008900
    call sys_routine_seg_sel:make_seg_descriptor
    call sys_routine_seg_sel:set_up_gdt_descriptor
    ;登记TSS选择子到TCB
    mov [es:esi+0x18], cx

    pop es
    pop ds
    popad
    ;丢弃调用本过程前压入的参数
    ret 8

;在TCB链上追加任务控制块
;输入：ECX=TCB线性基地址
append_to_tcb_link:
    push eax
    push edx
    push ds
    push es

    ;令DS指向内核数据段
    mov eax, core_data_seg_sel
    mov ds, eax
    ;令ES指向4GB段
    mov eax, mem_4gb_data_seg_sel
    mov es, eax

    ;当前TCB指针域清零，以指示这是最后一个TCB
    mov dword es:[ecx+0x00], 0
    ;TCB表头指针
    mov eax, ds:[tcb_chain]
    ;链表为空？
    or eax, eax
    jz .notcb

  .searc:
    mov edx, eax
    mov eax, es:[edx+0x00]
    or eax, eax
    jnz .searc

    mov es:[edx+0x00], ecx
    jmp .retpc

  .notcb:
    ;若为空表，直接令表头指针指向TCB
    mov ds:[tcb_chain], ecx

  .retpc:
    pop es
    pop ds
    pop edx
    pop eax
    ret

start:
    ;使ds指向核心数据段
    mov eax, core_data_seg_sel
    mov ds, eax

    ;显示保护模式提示信息
    mov ebx, msg_os
    call sys_routine_seg_sel:put_string

    ;安装为整个系统服务的调用门。特权级之间的控制转移必须使用门
    ;core-salt表的条目数量
    mov ecx, salt_items
    ;core-salt表的起始位置
    mov edi, salt
  .b3:
    push ecx
    ;该条目入口点的32位偏移地址
    mov eax, ds:[edi+256]
    ;该条目入口点的段选择子
    mov bx, ds:[edi+260]
    ;特权级3的调用门(3以上的特权级才允许访问)，0个参数(因为用寄存器传递参数，而没有用栈)
    mov cx, 1_11_0_1100_000_00000B
    call sys_routine_seg_sel:make_gate_descriptor
    call sys_routine_seg_sel:set_up_gdt_descriptor
    ;将返回的门描述符选择子回填
    mov ds:[edi+260], cx
    ;指向下一个core-salt条目
    add edi, salt_item_len
    pop ecx
    loop .b3

  .next:
    ;通过门显示信息(偏移量将被忽略)
    mov ebx, msg_gate
    call far [ds:salt_1+256]

    ;显示加载用户app提示信息，在内核中调用例程不需要通过门
    mov ebx, msg_user_load
    call sys_routine_seg_sel:put_string

    ;创建任务控制块。这不是处理器的要求，而是我们自己为了方便而设立的
    mov ecx, 0x46
    call sys_routine_seg_sel:allocate_memory
    ;将任务控制块追加到TCB链表
    call append_to_tcb_link

    ;用户程序位于逻辑50扇区
    push dword app_start_sector
    ;压入任务控制块起始线性地址
    push ecx
    call load_relocate_program

    ;显示运行用户app提示信息
    mov ebx, msg_user_run
    call sys_routine_seg_sel:put_string

    mov eax, mem_4gb_data_seg_sel
    mov ds, eax
    ;加载任务状态段选择子
    ltr ds:[ecx+0x18]
    ;加载LDT选择子
    lldt ds:[ecx+0x10]

    ;切换到用户程序头部段
    mov ds, ds:[ecx+0x44]
    ;以下假装是从调用门返回。摹仿处理器压入返回参数
    ;调用前的堆栈段选择子
    push dword ds:[0x1c]
    ;调用前的esp
    push dword 0
    ;调用前的代码段选择子
    push dword ds:[0x0c]
    ;调用前的eip
    push dword ds:[0x08]

    retf

;用户程序返回点
return_point:
    ;使ds指向核心数据段
    mov eax, core_data_seg_sel
    mov ds, eax

    ;显示用户app返回提示信息
    mov ebx, msg_user_ret
    call sys_routine_seg_sel:put_string

    hlt

SECTION core_trail
core_end:

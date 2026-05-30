;内核的大部分内容都应当固定
mem_4gb_data_seg_sel equ 0x0008       ;4GB数据段的段选择子，0x0008=0000000000001_000B
mbr_code_seg_sel     equ 0x0010       ;mbr代码段的段选择子，0x0010=0000000000010_000B
mem_stack_seg_sel    equ 0x0018       ;栈段的段选择子，0x0018=0000000000011_000B
video_ram_seg_sel    equ 0x0020       ;视频显示缓冲区的段选择子，0x0020=0000000000100_000B
sys_routine_seg_sel  equ 0x0028       ;系统公共例程代码段的选择子，0x0028=0000000000101_000B
core_data_seg_sel    equ 0x0030       ;内核数据段选择子，0x0030=0000000000110_000B
core_code_seg_sel    equ 0x0038       ;内核代码段选择子，0x0038=0000000000111_000B
;中断描述符表的线性地址
idt_linear_address   equ 0x1F000
;用户程序1的起始逻辑扇区号50
app1_start_sector    equ 0x00000032
;用户程序2的起始逻辑扇区号100
app2_start_sector    equ 0x00000064

;系统核心的头部，用于加载核心程序
section header vstart=0
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

    cli

    call .get_cursor                                   ;获取光标位置存在ax中
  .getc:
    mov cl, ds:[ebx]
    or cl, cl
    jz .exit                                           ;cl=0？
    cmp cl, 0x0d
    jz .cr                                             ;回车符？
    cmp cl, 0x0a
    jz .lf                                             ;换行符？
    call .put_char                                     ;正常显示字符
    jmp .next_char
  .cr:                                                 ;光标移动到当前行的第一列
    mov cl, 80
    div cl
    mul cl
    call .set_cursor
    jmp .next
  .lf:                                                 ;光标移动到下一行，列位置不变
    add eax, 80
    call .roll_screen
    jmp .next
  .next_char:
    add eax, 1                                         ;以下将光标位置推进一个字符
    call .roll_screen
  .next:                                               ;下一个字符
    inc ebx
    jmp .getc

  .exit:
    sti

    pop ecx
    pop ebx
    pop eax
    retf

  ;获取光标，输出：eax=光标位置
  .get_cursor:
    push edx

    xor eax, eax

    mov dx, 0x3d4
    mov al, 0x0e                                       ;光标位置高字节
    out dx, al
    mov dx, 0x3d5
    in al, dx
    mov ah, al
    mov dx, 0x3d4
    mov al, 0x0f                                       ;光标位置低字节
    out dx, al
    mov dx, 0x3d5
    in al, dx

    pop edx
    ret

  ;设置光标，输入：eax=光标位置
  .set_cursor:
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

    pop edx
    pop ebx
    pop eax
    ret

  ;判断光标是否超出屏幕滚屏，输入：eax=光标位置，输出：eax=光标位置
  .roll_screen:
    cmp eax, 2000
    jl .return

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

    .return:
    call .set_cursor
    ret

  ;显示单个字符，输入：cl=字符ascii，eax=光标位置
  .put_char:
    push eax
    push ebx
    push es

    mov ebx, video_ram_seg_sel
    mov es, ebx
    shl eax, 1                                         ;一个字符在显存中对应两个字节，这里必须乘以2
    mov es:[eax], cl

    pop es
    pop ebx
    pop eax
    ret

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
    mov al, 1                                          ;读取的扇区数
    out dx, al

    mov dx, 0x1f3
    mov eax, esi
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

    mov eax, ds:[ram_alloc]                            ;下一次分配时的起始地址
    add eax, ecx

    ;这里应当有检测可用内存数量的指令
    mov ecx, ds:[ram_alloc]                            ;返回分配的起始地址

    mov ebx, eax
    and ebx, 0xfffffffc                                ;强制对齐
    add ebx, 4
    test eax, 0x00000003                               ;下次分配的起始地址最好是4字节对齐
    cmovnz eax, ebx                                    ;如果没有对齐，则强制对齐
    mov ds:[ram_alloc], eax                            ;下次从该地址分配内存

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
    or ax, bx                                          ;描述符前32位(EAX)构造完毕

    and edx, 0xffff0000                                ;清除基地址中无关的位
    rol edx, 8
    bswap edx                                          ;装配基址的31~24和23~16(80486+)

    xor bx, bx
    or edx, ebx                                        ;装配段界限的高4位
    or edx, ecx                                        ;装配属性

    retf

;构造门的描述符（调用门等）
;输入：EAX=门代码在段内偏移地址
;输入：EBX=门代码所在段的选择子
;输入：ECX=段类型及属性等（各属性位都在原始位置）
;输出：EDX:EAX=完整的描述符
make_gate_descriptor:
    push ebx
    push ecx

    mov edx, eax                                       ;组装调用门的高双字部分
    mov dx, cx

    and eax, 0x0000ffff                                ;得到偏移地址低16位
    shl ebx, 16
    or eax, ebx                                        ;组装段选择子部分

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

    sgdt ds:[pgdt]                                     ;获取GDT

    movzx ebx, word ds:[pgdt]                          ;GDT界限
    inc ebx                                            ;GDT总字节数，也是下一个描述符偏移
    add ebx, ds:[pgdt+2]                               ;下一个描述符的线性地址

    mov es:[ebx], eax
    mov es:[ebx+4], edx
    add word ds:[pgdt], 8                              ;增加一个描述符的大小

    lgdt ds:[pgdt]                                     ;对GDT的更改生效

    mov ax, ds:[pgdt]                                  ;得到GDT界限值
    xor dx, dx
    mov bx, 8
    div bx
    mov cx, ax
    shl cx, 3                                          ;将索引号移到正确位置

    pop es
    pop ds
    pop edx
    pop ebx
    pop eax
    retf

;通用的异常处理过程
general_exception_handler:
    mov ebx, msg_core_expt
    call sys_routine_seg_sel:put_string

    hlt

;通用的中断处理过程
general_interrupt_handler:
    push eax

    mov al, 0x20                                       ;中断结束命令EOI
    out 0xa0, al                                       ;向从片发送
    out 0x20, al                                       ;向主片发送

    pop eax
    iretd

;实时时钟中断处理过程
rtm_0x70_interrupt_handle:
    pushad

    mov al, 0x20                                       ;中断结束命令EOI
    out 0xa0, al                                       ;向8259A从片发送
    out 0x20, al                                       ;向8259A主片发送

    mov al, 0x0c                                       ;寄存器C的索引，且开放NMI
    out 0x70, al
    in al, 0x71                                        ;读一下RTC的寄存器C，否则只发生一次中断，此处不考虑闹钟和周期性中断的情况

    ;请求任务调度
    call sys_routine_seg_sel:initiate_task_switch

    popad
    iretd

;主动发起任务切换
;输入：无
;输出：无
initiate_task_switch:
    pushad
    push ds
    push es

    mov eax, core_data_seg_sel
    mov es, eax
    mov eax, mem_4gb_data_seg_sel
    mov ds, eax

    mov eax, es:[tcb_chain]
    cmp eax, 0
    jz .return

  ;搜索状态为忙（当前任务）的节点
  .task_busy_search:
    cmp word ds:[eax+0x04], 0xffff
    cmove esi, eax                                     ;找到忙的节点，ESI=节点的线性地址
    jz .task_ready_search
    mov eax, ds:[eax]
    jmp .task_busy_search

  ;从当前节点继续搜索就绪任务的节点
  .task_ready_search:
    mov ebx, ds:[eax]
    or ebx, ebx
    jz .task_ready_search_head                         ;到链表尾部也未发现就绪节点，从头找
    cmp word ds:[ebx+0x04], 0x0000
    cmove edi, ebx                                     ;已找到就绪节点，EDI=节点的线性地址
    jz .task_switch
    mov eax, ebx
    jmp .task_ready_search

  .task_ready_search_head:
    mov ebx, es:[tcb_chain]                            ;EBX=链表首节点线性地址
  .do_search:
    cmp word ds:[ebx+0x04], 0x0000
    cmove edi, ebx                                     ;已找到就绪节点，EDI=节点的线性地址
    jz .task_switch
    mov ebx, ds:[ebx]
    or ebx, ebx
    jz .return                                         ;链表中已经不存在空闲任务，返回
    jmp .do_search

  ;就绪任务的节点已经找到，准备切换到该任务
  .task_switch:
    not word ds:[esi+0x04]                             ;将忙状态的节点改为就绪状态的节点
    not word ds:[edi+0x04]                             ;将就绪状态的节点改为忙状态的节点
    jmp far [ds:edi+0x14]                              ;任务切换

  .return:
    pop es
    pop ds
    popad
    retf

;终止当前任务，注意执行此例程时，当前任务仍在运行中，此例程其实也是当前任务的一部分
terminate_current_task:
    mov eax, core_data_seg_sel
    mov es, eax
    mov eax, mem_4gb_data_seg_sel
    mov ds, eax

    mov eax, es:[tcb_chain]                            ;EAX=首节点的线性地址

  ;搜索状态为忙（当前任务）的节点
  .task_curent_search:
    cmp word ds:[eax+0x04], 0xffff
    jz .task_curent_terminate                          ;找到忙的节点，EAX=节点的线性地址
    mov eax, ds:[eax]
    jmp .task_curent_search

  ;将状态为忙的节点改成终止状态
  .task_curent_terminate:
    mov word ds:[eax+0x04], 0x3333

    mov ebx, es:[tcb_chain]                            ;EBX=链表首节点线性地址
  ;搜索就绪状态的任务
  .task_ready_search:
    cmp word ds:[ebx+0x04], 0x0000
    jz .task_switch                                    ;已找到就绪节点，EBX=节点的线性地址
    mov ebx, ds:[ebx]
    jmp .task_ready_search

  ;就绪任务的节点已经找到，准备切换到该任务
  .task_switch:
    not word ds:[ebx+0x04]                             ;将就绪状态的节点改为忙状态的节点
    jmp far [ds:ebx+0x14]                              ;任务切换

;清理已经终止的任务并回收资源
do_task_clean:
    ;搜索TCB链表，找到状态为终止的节点
    ;将节点从链表中拆除
    ;回收任务占用的各种资源（可以从它的TCB中找到）

    retf

SECTION core_data vstart=0
    msg_core      db 'We are now in protect mode, and the system core is loaded, and the IDT is mounted.', 0x0d, 0x0a, 0
    msg_gate      db 0x0d, 0x0a, 'System wide CALL-GATE mounted and test OK.', 0x0d, 0x0a, 0
    msg_core_init db 0x0d, 0x0a, 'Core task created.', 0x0d, 0x0a, 0
    msg_core_run  db 0x0d, 0x0a, '[CORE TASK]: I am working!', 0x0d, 0x0a, 0
    msg_core_expt db 0x0d, 0x0a, '********Exception encounted********', 0x0d, 0x0a, 0
    core_buf      times 2048 db 0                      ;内核用的缓冲区
    ram_alloc     dd 0x00100000                        ;下次分配内存时的起始地址
    pgdt          dw 0                                 ;用于设置和修改GDT
                  dd 0
    pidt          dw 0                                 ;用于设置和修改IDT
                  dd 0
    tcb_chain     dd 0                                 ;任务控制块链
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
              dd  terminate_current_task
              dw  sys_routine_seg_sel
    salt_4  db  '@InitTaskSwitch'
              times 256-($-salt_4) db 0
              dd  initiate_task_switch
              dw  sys_routine_seg_sel
    salt_item_len   equ $-salt_4
    salt_items      equ ($-salt)/salt_item_len

SECTION core_code vstart=0
;创建中断描述符表IDT，注意在此期间不得开放中断，也不得调用put_string例程！
fill_idt_descriptor:
    push eax
    push ebx
    push ecx
    push edx
    push esi

    ;前20个向量是处理器异常使用的
    mov eax, general_exception_handler                 ;门代码在段内偏移地址
    mov ebx, sys_routine_seg_sel                       ;门代码所在段的选择子
    mov ecx, 0x8e00                                    ;32位中断门，0特权级
    call sys_routine_seg_sel:make_gate_descriptor
    mov ebx, idt_linear_address                        ;中断描述符表的线性地址
    xor esi, esi
  .idt0:
    mov es:[ebx+esi*8], eax
    mov es:[ebx+esi*8+4], edx
    inc esi
    cmp esi, 19                                        ;安装前22个异常中断处理过程
    jle .idt0

    ;其余为保留或硬件使用的中断向量
    mov eax, general_interrupt_handler                 ;门代码在段内偏移地址
    mov ebx, sys_routine_seg_sel                       ;门代码所在段的选择子
    mov ecx, 0x8e00                                    ;32位中断门，0特权级
    call sys_routine_seg_sel:make_gate_descriptor
    mov ebx, idt_linear_address                        ;中断描述符表的线性地址
  .idt1:
    mov es:[ebx+esi*8], eax
    mov es:[ebx+esi*8+4], edx
    inc esi
    cmp esi, 255                                       ;安装普通的中断处理过程
    jle .idt1

  ;设置实时时钟中断处理过程
  .rtm:
    mov eax, rtm_0x70_interrupt_handle                 ;门代码在段内偏移地址
    mov ebx, sys_routine_seg_sel                       ;门代码所在段的选择子
    mov ecx, 0x8e00                                    ;32位中断门，0特权级
    call sys_routine_seg_sel:make_gate_descriptor
    mov ebx, idt_linear_address                        ;中断描述符表的线性地址
    mov es:[ebx+0x70*8], eax
    mov es:[ebx+0x70*8+4], edx

  ;准备开放中断
  .load_idt:
    mov word ds:[pidt], 256*8-1                        ;IDT的界限
    mov dword ds:[pidt+2], idt_linear_address
    lidt ds:[pidt]                                     ;加载中断描述符表寄存器IDTR

  ;设置8259A中断控制器
  .intr_8259a_1:
    mov al, 0x11
    out 0x20, al                                       ;ICW1：边沿触发/级联方式
    mov al, 0x20
    out 0x21, al                                       ;ICW2:起始中断向量
    mov al, 0x04
    out 0x21, al                                       ;ICW3:从片级联到IR2
    mov al, 0x01
    out 0x21, al                                       ;ICW4:非总线缓冲，全嵌套，正常EOI

    mov al, 0x11
    out 0xa0, al                                       ;ICW1：边沿触发/级联方式
    mov al, 0x70
    out 0xa1, al                                       ;ICW2:起始中断向量
    mov al, 0x02
    out 0xa1, al                                       ;ICW3:从片级联到IR2
    mov al, 0x01
    out 0xa1, al                                       ;ICW4:非总线缓冲，全嵌套，正常EOI

  ;设置和时钟中断相关的硬件
  .cmos:
    mov al, 0x0b                                       ;RTC寄存器B
    or al, 0x80                                        ;阻断NMI
    out 0x70, al
    mov al, 0x12                                       ;设置寄存器B，禁止周期性中断，开放更新结束后中断，BCD码，24小时制
    out 0x71, al

  .intr_8259a_2:
    in al, 0xa1                                        ;读8259从片的IMR寄存器
    and al, 0xfe                                       ;清除bit 0(此位连接RTC)
    out 0xa1, al                                       ;写回此寄存器

    mov al, 0x0c
    out 0x70, al
    in al, 0x71                                        ;读RTC寄存器C，复位未决的中断状态

  .open_itr:
    sti                                                ;开放硬件中断

    pop esi
    pop edx
    pop ecx
    pop ebx
    pop eax
    ret

;安装为整个系统服务的调用门，特权级之间的控制转移必须使用门
fill_gate_descriptor:
    pushad

    mov ecx, salt_items                                ;core-salt表的条目数量
    mov edi, salt                                      ;core-salt表的起始位置
  .fill_gate:
    push ecx
    mov eax, ds:[edi+256]                              ;该条目入口点的32位偏移地址
    mov bx, ds:[edi+260]                               ;该条目入口点的段选择子
    mov cx, 1_11_0_1100_000_00000B                     ;特权级3的调用门(3以上的特权级才允许访问)，0个参数(因为用寄存器传递参数，而没有用栈)
    call sys_routine_seg_sel:make_gate_descriptor
    call sys_routine_seg_sel:set_up_gdt_descriptor
    mov ds:[edi+260], cx                               ;将返回的门描述符选择子回填
    add edi, salt_item_len                             ;指向下一个core-salt条目
    pop ecx
    loop .fill_gate

    popad
    ret

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

    mov dword es:[ecx+0x00], 0                         ;当前TCB指针域清零，以指示这是最后一个TCB
    mov eax, ds:[tcb_chain]                            ;TCB表头指针
    or eax, eax                                        ;链表为空？
    jz .notcb

  .searc:
    mov edx, eax
    mov eax, es:[edx+0x00]
    or eax, eax
    jnz .searc

    mov es:[edx+0x00], ecx
    jmp .retpc

  .notcb:
    mov ds:[tcb_chain], ecx                            ;若为空表，直接令表头指针指向TCB

  .retpc:
    pop es
    pop ds
    pop edx
    pop eax
    ret

;为内核创建任务
fill_core_task:
    pushad

    cli

    ;为内核任务创建任务控制块TCB
    mov ecx, 0x46
    call sys_routine_seg_sel:allocate_memory
    call append_to_tcb_link                            ;将此TCB添加到TCB链中
    mov word es:[ecx+0x04], 0xffff                     ;任务的状态为“忙”
    mov esi, ecx

    ;为内核任务的TSS分配内存空间
    mov ecx, 104
    mov es:[esi+0x12], cx
    call sys_routine_seg_sel:allocate_memory
    mov es:[esi+0x14], ecx                             ;在内核TCB中保存TSS基地址
    ;在程序管理器(内核)的TSS中设置必要的项目
    mov word es:[ecx+96], 0                            ;没有LDT。处理器允许没有LDT的任务
    mov word es:[ecx+102], 103                         ;没有I/O位图。0特权级事实上不需要
    mov word es:[ecx+0], 0                             ;反向链=0
    mov dword es:[ecx+28], 0                           ;登记CR3(PDBR)
    mov word es:[ecx+100], 0                           ;T=0
    ;不需要0、1、2特权级堆栈。0特级不会向低特权级转移控制

    ;创建TSS描述符，并安装到GDT中
    mov eax, ecx                                       ;TSS的起始线性地址
    mov ebx, 103                                       ;段长度（界限）
    mov ecx, 0x00008900                                ;TSS描述符，特权级0
    call sys_routine_seg_sel:make_seg_descriptor
    call sys_routine_seg_sel:set_up_gdt_descriptor
    mov word es:[esi+0x18], cx                         ;登记TSS选择子到TCB

    ;任务寄存器TR中的内容是任务存在的标志，该内容也决定了当前任务是谁
    ;下面的指令为当前正在执行的0特权级任务“程序管理器”后补手续（TSS）
    ltr cx

    sti

    popad
    ret

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

    mov edi, ds:[ebx+0x0c]                             ;获得LDT基地址
    xor ecx, ecx
    mov cx, ds:[ebx+0x0a]                              ;获得LDT界限
    inc cx                                             ;LDT的总字节数，即新描述符偏移地址

    mov ds:[edi+ecx+0x00], eax                         ;安装描述符
    mov ds:[edi+ecx+0x04], edx

    add cx, 8
    dec cx                                             ;得到新的LDT界限值
    mov ds:[ebx+0x0a], cx                              ;更新LDT界限值到TCB

    mov ax, cx
    xor dx, dx
    mov cx, 8
    div cx

    mov cx, ax
    shl cx, 3
    or cx, 0000_0000_0000_0100B                        ;左移3位，并且使TI位=1，指向LDT，最后使RPL=00

    pop ds
    pop edi
    pop edx
    pop eax
    ret

;读取用户app大小
;输入：ESI=逻辑扇区号
;输出：EAX=程序大小
read_user_app_size:
    push ebx
    push edx
    push edi

    ;读取程序头部数据
    mov edi, core_buf
    call sys_routine_seg_sel:read_hard_disk_0

    ;程序尺寸
    xor edx, edx
    mov eax, ds:[core_buf]
    ;使之512字节对齐（能被512整除的数，低9位都为0）
    mov ebx, eax
    and ebx, 0xfffffe00
    add ebx, 512
    ;程序的大小正好是512的倍数吗?
    test eax, 0x000001ff
    ;不是使用凑整的结果
    cmovnz eax, ebx

    pop edi
    pop edx
    pop ebx
    ret

;加载用户app
;输入：ESI=逻辑扇区号
;输入：EAX=程序大小
;输入：ECX=加载基地址
load_user_app:
    pushad
    push ds

    ;申请到的内存首地址
    mov edi, ecx
    ;总扇区数
    xor edx, edx
    mov ecx, 512
    div ecx
    mov ecx, eax

    ;临时变量 esi=程序硬盘扇区号 edi=申请到的内存首地址 ecx=总扇区数
    ;切换DS到0-4GB的段
    mov eax, mem_4gb_data_seg_sel
    mov ds, eax
  .read_program:
    call sys_routine_seg_sel:read_hard_disk_0
    inc esi
    ;循环读，直到读完整个用户程序
    loop .read_program

    pop ds
    popad
    ret

;重定位SALT
reload_user_salt:
    pushad

    ;这里和前一章不同，头部段描述符已安装，但还没有生效，故只能通过4GB段访问用户程序头部
    cld

    mov ecx, es:[esi+0x24]               ;user-salt条目数(通过访问4GB段取得)
    mov edi, esi
    add edi, 0x28                        ;user-salt在4GB段内的偏移
  .user_salt_search:
    push ecx
    push edi

        mov ecx, salt_items              ;core-salt条目数
        mov esi, salt                    ;core-salt在数据段内的偏移
      .core_salt_search:
        push edi
        push esi
        push ecx

        mov ecx, 64                      ;检索表中，每条目的比较次数
        repe cmpsd                       ;每次比较4字节
        jnz .next_core_salt
        mov eax, ds:[esi]                ;若匹配，则esi恰好指向其后的地址
        mov es:[edi-256], eax            ;将字符串改写成偏移地址
        mov ax, ds:[esi+4]
        or ax, 0000000000000011B         ;以用户程序自己的特权级使用调用门故RPL=3
        mov es:[edi-252], ax             ;回填段选择子

      .next_core_salt:
        pop ecx
        pop esi
        add esi, salt_item_len
        pop edi                          ;回填段选择子从头比较
        loop .core_salt_search

      .next_user_salt:
        pop edi
        add edi, 256
        pop ecx
        loop .user_salt_search

    popad
    ret

;为用户创建任务
;输入：ESI=逻辑扇区号
load_relocate_program:
    pushad

    cli

    ;为用户任务创建任务控制块TCB
    mov ecx, 0x46
    call sys_routine_seg_sel:allocate_memory
    mov word es:[ecx+0x04], 0                          ;TCB任务状态：就绪
    call append_to_tcb_link                            ;将此TCB添加到TCB链中
    mov edi, ecx

    ;为用户任务的TSS分配内存空间
    mov ecx, 104                                       ;TSS的基本尺寸
    mov es:[edi+0x12], cx
    dec word es:[edi+0x12]                             ;登记TSS界限值到TCB
    call sys_routine_seg_sel:allocate_memory
    mov es:[edi+0x14], ecx                             ;登记TSS基地址到TCB

    ;为用户任务的LDT分配内存空间，允许安装20个LDT描述符
    mov ecx, 160
    call sys_routine_seg_sel:allocate_memory
    mov es:[edi+0x0c], ecx                             ;登记LDT基地址到TCB中
    mov word es:[edi+0x0a], 0xffff                     ;登记LDT初始的界限到TCB中

    ;读取程序大小
    call read_user_app_size
    ;为用户app分配内存
    mov ecx, eax
    call sys_routine_seg_sel:allocate_memory
    mov es:[edi+0x06], ecx                             ;登记程序加载基地址到TCB中
    call load_user_app

    ;获得程序加载基地址
    mov esi, es:[edi+0x06]

    ;建立程序头部段描述符
    mov eax, esi                                       ;程序头部起始线性地址
    mov ebx, es:[esi+0x04]                             ;段长度
    dec ebx                                            ;段界限
    mov ecx, 0x0040f200                                ;字节粒度的数据段描述符，特权级3
    call sys_routine_seg_sel:make_seg_descriptor
    mov ebx, edi                                       ;TCB的基地址
    call fill_descriptor_in_ldt                        ;安装头部段描述符到LDT中
    or cx, 0000_0000_0000_0011B                        ;设置选择子的特权级为3
    mov es:[edi+0x44], cx                              ;登记程序头部段选择子到TCB
    mov es:[esi+0x04], cx                              ;登记程序头部段选择子到头部内

    ;建立程序代码段描述符
    mov eax, esi
    add eax, es:[esi+0x0c]                             ;代码起始线性地址
    mov ebx, es:[esi+0x10]                             ;段长度
    dec ebx                                            ;段界限
    mov ecx, 0x0040f800                                ;字节粒度的代码段描述符，特权级3
    call sys_routine_seg_sel:make_seg_descriptor
    mov ebx, edi                                       ;TCB的基地址
    call fill_descriptor_in_ldt                        ;安装头部段描述符到LDT中
    or cx, 0000_0000_0000_0011B                        ;设置选择子的特权级为3
    mov es:[esi+0x0c], cx                              ;登记代码段选择子到头部

    ;建立程序数据段描述符
    mov eax, esi
    add eax, es:[esi+0x14]                             ;数据段起始线性地址
    mov ebx, es:[esi+0x18]                             ;段长度
    dec ebx                                            ;段界限
    mov ecx, 0x0040f200                                ;字节粒度的数据段描述符，特权级3
    call sys_routine_seg_sel:make_seg_descriptor
    mov ebx, edi                                       ;TCB的基地址
    call fill_descriptor_in_ldt                        ;安装头部段描述符到LDT中
    or cx, 0000_0000_0000_0011B                        ;设置选择子的特权级为3
    mov es:[esi+0x14], cx                              ;登记数据段选择子到头部

    ;建立程序堆栈段描述符
    mov eax, esi
    add eax, es:[esi+0x1c]                             ;数据段起始线性地址
    mov ebx, es:[esi+0x20]                             ;段长度
    dec ebx                                            ;段界限
    mov ecx, 0x0040f200                                ;字节粒度的堆栈段描述符，特权级3
    call sys_routine_seg_sel:make_seg_descriptor
    mov ebx, edi                                       ;TCB的基地址
    call fill_descriptor_in_ldt                        ;安装头部段描述符到LDT中
    or cx, 0000_0000_0000_0011B                        ;设置选择子的特权级为3
    mov es:[esi+0x1c], cx                              ;登记堆栈段选择子到头部

    ;重定位用户SALT
    call reload_user_salt

    ;创建0特权级栈
    mov ecx, 0                                         ;以4KB为单位的栈段界限值
    mov es:[edi+0x1a], ecx                             ;登记0特权级栈界限到TCB
    inc ecx
    shl ecx, 12                                        ;乘以4096，得到段大小
    push ecx
    call sys_routine_seg_sel:allocate_memory
    mov es:[edi+0x1e], ecx                             ;登记0特权级栈基地址到TCB
    mov eax, ecx
    mov ebx, es:[edi+0x1a]                             ;段长度（界限）
    mov ecx, 0x00c09200                                ;4KB粒度，读写，特权级0
    call sys_routine_seg_sel:make_seg_descriptor
    mov ebx, edi                                       ;TCB的基地址
    call fill_descriptor_in_ldt
    ;or cx, 0000_0000_0000_0000                        ;设置选择子的特权级为0
    mov es:[edi+0x22], cx                              ;登记0特权级堆栈选择子到TCB
    pop dword es:[edi+0x24]                            ;登记0特权级堆栈初始ESP到TCB

    ;创建1特权级堆栈
    mov ecx, 0
    mov es:[edi+0x28], ecx                             ;登记1特权级堆栈尺寸到TCB
    inc ecx
    shl ecx, 12                                        ;乘以4096，得到段大小
    push ecx
    call sys_routine_seg_sel:allocate_memory
    mov es:[edi+0x2c], ecx                             ;登记1特权级堆栈基地址到TCB
    mov eax, ecx
    mov ebx, es:[edi+0x28]                             ;段长度（界限）
    mov ecx, 0x00c0b200                                ;4KB粒度，读写，特权级1
    call sys_routine_seg_sel:make_seg_descriptor
    mov ebx, edi                                       ;TCB的基地址
    call fill_descriptor_in_ldt
    or cx, 0000_0000_0000_0001                         ;设置选择子的特权级为1
    mov es:[edi+0x30], cx                              ;登记1特权级堆栈选择子到TCB
    pop dword es:[edi+0x32]                            ;登记1特权级堆栈初始ESP到TCB

    ;创建2特权级堆栈
    mov ecx, 0
    mov es:[edi+0x36], ecx                             ;登记2特权级堆栈尺寸到TCB
    inc ecx
    shl ecx, 12                                        ;乘以4096，得到段大小
    push ecx
    call sys_routine_seg_sel:allocate_memory
    mov es:[edi+0x3a], ecx                             ;登记2特权级堆栈基地址到TCB
    mov eax, ecx
    mov ebx, es:[edi+0x36]                             ;段长度（界限）
    mov ecx, 0x00c0d200                                ;4KB粒度，读写，特权级2
    call sys_routine_seg_sel:make_seg_descriptor
    mov ebx, edi                                       ;TCB的基地址
    call fill_descriptor_in_ldt
    or cx, 0000_0000_0000_0010                         ;设置选择子的特权级为2
    mov es:[edi+0x3e], cx                              ;登记2特权级堆栈选择子到TCB
    pop dword es:[edi+0x40]                            ;登记2特权级堆栈初始ESP到TCB

    ;在GDT中登记LDT描述符
    mov eax, es:[edi+0x0c]                             ;LDT的起始线性地址
    movzx ebx, word es:[edi+0x0a]                      ;LDT段界限
    mov ecx, 0x00008200                                ;LDT描述符，特权级0
    call sys_routine_seg_sel:make_seg_descriptor
    call sys_routine_seg_sel:set_up_gdt_descriptor
    mov es:[edi+0x10], cx                              ;登记LDT选择子到TCB中

    mov esi, es:[edi+0x14]                             ;TSS的基地址
    ;登记基本的TSS表格内容
    mov word [es:esi+0], 0                             ;反向链=0
    mov edx, es:[edi+0x24]                             ;登记0特权级栈初始ESP到TSS中
    mov es:[esi+4], edx
    mov dx, es:[edi+0x22]                              ;登记0特权级栈段选择子到TSS中
    mov es:[esi+8], dx
    mov edx, es:[edi+0x32]                             ;登记1特权级栈初始ESP到TSS中
    mov es:[esi+12], edx
    mov dx, es:[edi+0x30]                              ;登记1特权级栈段选择子到TSS中
    mov es:[esi+16], dx
    mov edx, es:[edi+0x40]                             ;登记2特权级栈初始ESP到TSS中
    mov es:[esi+20], edx
    mov dx, es:[edi+0x3e]                              ;登记2特权级栈段选择子到TSS中
    mov es:[esi+24], dx
    mov dword es:[esi+28], 0                           ;登记CR3(PDBR)

    mov ebx, es:[edi+0x06]
    mov edx, es:[ebx+0x08]
    mov es:[esi+32], edx                               ;登记程序入口点（EIP）到TSS

    mov word es:[esi+72], 0                            ;TSS中的ES=0
    mov dx, es:[ebx+0x0c]
    mov es:[esi+76], dx                                ;登记程序代码段（CS）选择子到TSS中
    mov dx, es:[ebx+0x1c]
    mov es:[esi+80], dx                                ;登记程序堆栈段（SS）选择子到TSS中
    mov dx, es:[ebx+0x04]
    mov word es:[esi+84], dx                           ;登记程序数据段（DS）选择子到TSS中。注意，它指向程序头部段
    mov word es:[esi+88], 0                            ;TSS中的FS=0
    mov word es:[esi+92], 0                            ;TSS中的GS=0

    mov dx, es:[edi+0x10]                              ;登记任务的LDT选择子到TSS中
    mov es:[esi+96], dx

    mov dx, es:[edi+0x12]                              ;登记任务的I/O位图偏移到TSS中
    mov es:[esi+102], dx
    mov word es:[esi+100], 0                           ;T=0

    pushfd
    pop dword es:[esi+36]                              ;EFLAGS

    ;在GDT中登记TSS描述符
    mov eax, es:[edi+0x14]                             ;TSS的起始线性地址
    movzx ebx, word es:[edi+0x12]                      ;段长度（界限）
    mov ecx, 0x00008900                                ;TSS描述符，特权级0
    call sys_routine_seg_sel:make_seg_descriptor
    call sys_routine_seg_sel:set_up_gdt_descriptor
    ;登记TSS选择子到TCB
    mov es:[edi+0x18], cx

    sti

    popad
    ret

start:
    ;使ds指向核心数据段
    mov eax, core_data_seg_sel
    mov ds, eax
    ;令es指向4GB数据段
    mov ecx, mem_4gb_data_seg_sel
    mov es, ecx

    call fill_idt_descriptor
    mov ebx, msg_core
    call sys_routine_seg_sel:put_string                ;显示保护模式提示信息

    call fill_gate_descriptor
    mov ebx, msg_gate
    call far [ds:salt_1+256]                           ;通过门显示信息(偏移量将被忽略)

    call fill_core_task
    ;现在可认为“程序管理器”任务正执行中
    mov ebx, msg_core_init
    call sys_routine_seg_sel:put_string

    mov esi, app1_start_sector
    call load_relocate_program                         ;加载用户app

    ;为说明任务切换而特意添加的无操作指令
    nop
    nop
    nop

    ;可以创建更多的任务，重复load_relocate_program步骤
    mov esi, app2_start_sector
    call load_relocate_program                         ;加载用户app

  .do_switch:
    mov ebx, msg_core_run
    call sys_routine_seg_sel:put_string

    ;这里可以添加创建新的任务的功能，比如：
    ; mov esi, app_start_sector
    ; call load_relocate_program

    ;清理已经终止的任务，并回收它们占用的资源
    call sys_routine_seg_sel:do_task_clean

    hlt

    jmp .do_switch

SECTION core_trail
core_end:
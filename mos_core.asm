%include 'mos_config.asm'

SECTION header vstart=core_line_address
    core_length      dd core_end        ;核心程序总长度#00
    core_entry       dd start           ;核心代码段入口点#04

[bits 32]
SECTION sys_routine vfollows=header
;字符串显示例程，显示0终止的字符串并移动光标
;输入：DS:EBX=字符串线性地址
put_string:
    pushad
    pushfd
    cli

    call .get_cursor                             ;获取光标位置存在ax中
  .getc:
    mov cl, ds:[ebx]
    or cl, cl
    jz .exit                                     ;cl=0？
    cmp cl, 0x0d
    jz .cr                                       ;回车符？
    cmp cl, 0x0a
    jz .lf                                       ;换行符？
    call .put_char                               ;正常显示字符
    jmp .next_char
  .cr:                                           ;光标移动到当前行的第一列
    mov cl, 80
    div cl
    mul cl
    call .set_cursor
    jmp .next
  .lf:                                           ;光标移动到下一行，列位置不变
    add eax, 80
    call .roll_screen
    jmp .next
  .next_char:
    add eax, 1                                   ;以下将光标位置推进一个字符
    call .roll_screen
  .next:                                         ;下一个字符
    inc ebx
    jmp .getc

  .exit:
    popfd                                        ;硬件操作完毕，恢复原先中断状态
    popad
    ret

  ;获取光标，输出：eax=光标位置
  .get_cursor:
    push edx

    xor eax, eax

    mov dx, 0x3d4
    mov al, 0x0e                                 ;光标位置高字节
    out dx, al
    mov dx, 0x3d5
    in al, dx
    mov ah, al
    mov dx, 0x3d4
    mov al, 0x0f                                 ;光标位置低字节
    out dx, al
    mov dx, 0x3d5
    in al, dx

    ; and eax, 0x0000ffff                        ;准备使用32位寻址方式访问显存

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
    push esi
    push edi

    ;第二行～第二十五行向上移动
    cld
    mov esi, 0x800b80a0
    mov edi, 0x800b8000
    mov ecx, 1920
    rep movsw

    ;清除屏幕最底一行
    mov ebx, 3840
    mov ecx, 80
    .cls:
    mov word es:[0x800b8000+ebx], 0x0720
    add ebx, 2
    loop .cls
    sub eax, 80

    pop edi
    pop esi
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

    shl eax, 1                                   ;一个字符在显存中对应两个字节，这里必须乘以2
    mov ds:[0x800b8000+eax], cl

    pop ebx
    pop eax
    ret

;从硬盘读取一个逻辑扇区（平坦模型）
;输入：EAX=逻辑扇区号
;输入：DS:EBX=目标缓冲区线性地址
;输出：EBX=EBX+512
read_hard_disk_0:
    push eax
    push ecx
    push edx
    pushfd
    cli

  .set:
    push eax

    mov dx, 0x1f2
    mov al, 1                                    ;读取的扇区数
    out dx, al

    mov dx, 0x1f3
    pop eax
    out dx, al                                   ;LBA地址7~0

    mov dx, 0x1f4
    shr eax, 8
    out dx, al                                   ;LBA地址15~8

    mov dx, 0x1f5
    shr eax, 8
    out dx, al                                   ;LBA地址23~16

    mov dx, 0x1f6
    shr eax, 8
    or al, 0xe0
    out dx, al                                   ;LBA地址27~24

    mov dx, 0x1f7
    mov al, 0x20                                       ;读命令
    out dx, al

  .waits:
    in al, dx
    and al, 0x88
    cmp al, 0x08
    jnz .waits                                   ;不忙，且硬盘已准备好数据传输

    mov ecx, 256                                 ;总共要读取的字数
    mov dx, 0x1f0
  .readw:
    in ax, dx
    mov ds:[ebx], ax
    add ebx, 2
    loop .readw

  .return:
    popfd                                        ;硬件操作完毕，恢复原先中断状态
    pop edx
    pop ecx
    pop eax
    ret

;创建新页目录，并复制当前页目录内容
;输出：EAX=新页目录的物理地址
create_copy_cur_pdir:
    push esi
    push edi
    push ebx
    push ecx

    call allocate_a_4k_page
    mov ebx, eax
    or ebx, 0x00000007
    mov ds:[0xfffffff8], ebx

    invlpg ds:[0xfffffff8]

    mov esi, 0xfffff000                          ;ESI->当前页目录的线性地址
    mov edi, 0xffffe000                          ;EDI->新页目录的线性地址
    mov ecx, 1024                                ;ECX=要复制的目录项数
    cld
    repe movsd

    pop ecx
    pop ebx
    pop edi
    pop esi
    ret

;分配一个页，并安装在当前活动的层级分页结构中
;输入：EBX=页的线性地址
allocate_a_4k_page:
    push ebx

    xor eax, eax
  .search_free_page:
    bts ds:[page_bit_map], eax
    jnc .get_page
    inc eax
    cmp eax, page_map_len*8
    jl .search_free_page

  .no_free_page:
    mov ebx, msg_core_mem
    call put_string
    hlt                                          ;没有可以分配的页停机

  .get_page:
    shl eax, 12                                  ;乘以4096（0x1000）

  .return:
    pop ebx
    ret

;分配一个页，并安装在当前活动的层级分页结构中
;输入：EBX=页的线性地址
alloc_inst_a_page:
    push eax
    push ebx
    push ecx
    push esi

  ;检查该线性地址所对应的页表是否存在
  .pde_check:
    mov esi, ebx
    and esi, 0xffc00000                          ;清除页表索引和页内偏移部分
    shr esi, 20                                  ;将页目录索引乘以4作为页内偏移
    or esi, 0xfffff000                           ;页目录自身的线性地址+表内偏移
    test dword ds:[esi], 0x00000001              ;P位是否为“1”。检查该线性地址是否已经有对应的页表
    jnz .pte_check

  ;创建并安装该线性地址所对应的页表
  .pde_inst:
    call allocate_a_4k_page                      ;分配一个页做为页表
    or eax, 0x00000007
    mov ds:[esi], eax                            ;在页目录中登记该页表

    ;清空当前页表
    mov eax, ebx
    and eax, 0xffc00000
    shr eax, 10
    or eax, 0xffc00000
    mov ecx, 1024
  .pde_zero:
    mov dword ds:[eax], 0x00000000
    add eax, 4
    loop .pde_zero

  ;检查该线性地址对应的页表项（页）是否存在
  .pte_check:
    mov esi, ebx
    and esi, 0xfffff000                          ;清除页内偏移部分
    shr esi, 10                                  ;将页目录索引变成页表索引，页表索引乘以4作为页内偏移
    or esi, 0xffc00000                           ;得到该线性地址对应的页表项
    test dword ds:[esi], 0x00000001              ;P位是否为“1”。检查该线性地址是否已经有对应的页
    jnz .return

  ;创建并安装该线性地址所对应的页
  .pte_inst:
    call allocate_a_4k_page                      ;分配一个页，这才是要安装的页
    or eax, 0x00000007
    mov ds:[esi], eax

  .return:
    pop esi
    pop ecx
    pop ebx
    pop eax
    ret

;在指定任务的虚拟内存空间中分配内存
;输入：EBX=任务控制块TCB的线性地址
;输入：ECX=希望分配的字节数
;输出：ECX=已分配的起始线性地址
task_alloc_memory:
    push eax
    push ebx

    ;获得本次内存分配的起始线性地址
    mov ebx, ds:[ebx+0x06]                       ;获得本次分配的起始线性地址
    mov eax, ebx
    add ecx, ebx                                 ;本次分配，最后一个字节之后的线性地址
    push ecx

    ;为请求的内存分配页
    and ebx, 0xfffff000                          ;低12位清零
    and ecx, 0xfffff000                          ;低12位清零
  .next_page:
    call alloc_inst_a_page                       ;安装当前线性地址所在的页
    add ebx, 0x1000                              ;+4096
    cmp ebx, ecx
    jle .next_page

    ;将用于下一次分配的线性地址强制按4字节对齐
    pop ecx
  .align:
    test ecx, 0x00000003                         ;线性地址是4字节对齐的吗？
    jz .return                                   ;是，直接返回
    add ecx, 4                                   ;否，强制按4字节对齐
    and ecx, 0xfffffffc

  .return:
    pop ebx
    mov ds:[ebx+0x06], ecx                       ;将下次分配可用的线性地址回存到TCB中
    mov ecx, eax

    pop eax
    ret

;在当前任务的地址空间中分配内存
;输入：ECX=希望分配的字节数
;输出：ECX=起始线性地址
allocate_memory:
    push ebx

    mov ebx, ds:[tcb_chain]                      ;ebx=首节点的线性地址

  ;搜索当前节点
  .search_current_tcb:
    cmp word ds:[ebx+0x04], 0xffff
    jz .current_tcb                              ;找到忙的节点，EBX=节点的线性地址
    mov ebx, ds:[ebx]
    jmp .search_current_tcb

  ;开始分配内存
  .current_tcb:
    call task_alloc_memory

  .return:
    pop ebx
    ret

;构造门的描述符（调用门等）
;输入：EAX=门代码在段内偏移地址
;输入：EBX=门代码所在段的选择子
;输入：ECX=段类型及属性等（各属性位都在原始位置）
;输出：EDX:EAX=完整的描述符
make_gate_descriptor:
    push ebx
    push ecx

    mov edx, eax                                 ;组装调用门的高双字部分
    mov dx, cx

    and eax, 0x0000ffff                          ;得到偏移地址低16位
    shl ebx, 16
    or eax, ebx                                  ;组装段选择子部分

    pop ecx
    pop ebx
    ret

;构造存储器和系统的段描述符
;输入：EAX=线性基地址
;输入：EBX=段界限
;输入：ECX=属性（各属性位都在原始位置，其它没用到的位置0）
;输出：EDX:EAX=完整的描述符
make_seg_descriptor:
    push ebx
    push ecx

    mov edx, eax
    shl eax, 16
    or ax, bx                                          ;描述符前32位(EAX)构造完毕

    and edx, 0xffff0000                                ;清除基地址中无关的位
    rol edx, 8
    bswap edx                                          ;装配基址的31~24和23~16(80486+)

    xor bx, bx
    or edx, ebx                                        ;装配段界限的高4位
    or edx, ecx                                        ;装配属性

    pop ecx
    pop ebx
    ret

;在GDT内安装一个新的描述符
;输入：EDX:EAX=描述符
;输出：CX=描述符的选择子
set_up_gdt_descriptor:
    push eax
    push ebx
    push edx

    sgdt ds:[pgdt]                               ;获取GDT

    movzx ebx, word ds:[pgdt]                    ;GDT界限
    inc ebx                                      ;GDT总字节数，也是下一个描述符偏移
    add ebx, ds:[pgdt+2]                         ;下一个描述符的线性地址

    mov ds:[ebx], eax
    mov ds:[ebx+4], edx
    add word ds:[pgdt], 8                        ;增加一个描述符的大小

    lgdt ds:[pgdt]                               ;对GDT的更改生效

    mov ax, ds:[pgdt]                            ;得到GDT界限值
    xor dx, dx
    mov bx, 8
    div bx
    mov cx, ax
    shl cx, 3                                    ;将索引号移到正确位置

    pop edx
    pop ebx
    pop eax
    ret

;通用的异常处理过程
general_exception_handler:
    mov ebx, msg_core_expt
    call put_string

    cli

    hlt

;通用的中断处理过程
general_interrupt_handler:
    push eax

    mov al, 0x20                                 ;中断结束命令EOI
    out 0xa0, al                                 ;向从片发送
    out 0x20, al                                 ;向主片发送

    pop eax
    iretd

;实时时钟中断处理过程
rtm_0x70_interrupt_handle:
    push eax

    mov al, 0x20                                 ;中断结束命令EOI
    out 0xa0, al                                 ;向8259A从片发送
    out 0x20, al                                 ;向8259A主片发送

    mov al, 0x0c                                 ;寄存器C的索引，且开放NMI
    out 0x70, al
    in al, 0x71                                  ;读一下RTC的寄存器C，否则只发生一次中断，此处不考虑闹钟和周期性中断的情况

    call initiate_task_switch                    ;请求任务调度

    pop eax
    iretd

;系统调用处理过程
int_0x88_handler:
    call [ds:eax * 4 + sys_call]
    iretd

;恢复指定任务的执行
;输入：EDI=新任务的TCB的线性地址
resume_task_execute:
    mov eax, ds:[edi + 10]
    mov ds:[tss + 4], eax                      ;用新任务的RSP0设置TSS的RSP0域
    mov eax, ds:[edi + 22]
    mov cr3, eax                               ;恢复新任务的CR3
    mov ds, ds:[edi + 34]
    mov es, ds:[edi + 36]
    mov fs, ds:[edi + 38]
    mov gs, ds:[edi + 40]
    mov eax, ds:[edi + 42]
    mov ebx, ds:[edi + 46]
    mov ecx, ds:[edi + 50]
    mov edx, ds:[edi + 54]
    mov esi, ds:[edi + 58]
    mov ebp, ds:[edi + 66]

    test word ds:[edi + 32], 3                   ;SS.RPL=3？
    jnz .to_r3                                   ;是的。转.to_r3
    mov esp, ds:[edi + 70]
    mov ss, ds:[edi + 32]
    jmp .do_sw

  .to_r3:
    push dword ds:[edi + 32]                     ;SS
    push dword ds:[edi + 70]                     ;ESP
  .do_sw:
    push dword ds:[edi + 74]                     ;EFLAGS
    push dword ds:[edi + 30]                     ;CS
    push dword ds:[edi + 26]                     ;EIP

    not word ds:[edi + 0x04]                     ;将就绪状态的节点改为忙状态的节点
    mov edi, ds:[edi + 62]

    iretd

;主动发起任务切换
initiate_task_switch:
    push eax
    push ebx
    push esi
    push edi

    mov eax, ds:[tcb_chain]
    cmp eax, 0
    jz .return

  ;搜索状态为忙（当前任务）的节点
  .task_busy_search:
    cmp word ds:[eax+0x04], 0xffff
    cmove esi, eax                               ;找到忙的节点，ESI=节点的线性地址
    jz .task_ready_search
    mov eax, ds:[eax]
    jmp .task_busy_search

  ;从当前节点继续搜索就绪任务的节点
  .task_ready_search:
    mov ebx, ds:[eax]
    or ebx, ebx
    jz .task_ready_search_head                   ;到链表尾部也未发现就绪节点，从头找
    cmp word ds:[ebx+0x04], 0x0000
    cmove edi, ebx                               ;已找到就绪节点，EDI=节点的线性地址
    jz .task_switch
    mov eax, ebx
    jmp .task_ready_search

  .task_ready_search_head:
    mov ebx, ds:[tcb_chain]                      ;EBX=链表首节点线性地址
  .do_search:
    cmp word ds:[ebx+0x04], 0x0000
    cmove edi, ebx                               ;已找到就绪节点，EDI=节点的线性地址
    jz .task_switch
    mov ebx, ds:[ebx]
    or ebx, ebx
    jz .return                                   ;链表中已经不存在空闲任务，返回
    jmp .do_search

  ;就绪任务的节点已经找到，准备切换到该任务
  .task_switch:
    ;保存旧任务的状态，EAX/EBX/ESI/EDI不用保存，在任务恢复执行时将自动从栈中弹出并恢复
    mov eax, cr3
    mov ds:[esi + 22], eax                       ;保存CR3
    mov ds:[esi + 50], ecx
    mov ds:[esi + 54], edx
    mov ds:[esi + 66], ebp
    mov ds:[esi + 70], esp
    mov dword ds:[esi + 26], .return             ;恢复执行时的EIP
    mov ds:[esi + 30], cs
    mov ds:[esi + 32], ss
    mov ds:[esi + 34], ds
    mov ds:[esi + 36], es
    mov ds:[esi + 38], fs
    mov ds:[esi + 40], gs
    pushfd
    pop dword ds:[esi + 74]
    not word ds:[esi + 4]                        ;将忙状态的节点改为就绪状态的节点

    jmp resume_task_execute                      ;转去恢复并执行新任务

  .return:
    pop edi
    pop esi
    pop ebx
    pop eax
    ret

;终止当前任务，注意执行此例程时，当前任务仍在运行中，此例程其实也是当前任务的一部分
terminate_current_task:
    mov edi, ds:[tcb_chain]
  ;搜索状态为忙（当前任务）的节点
  .task_curent_search:
    cmp word ds:[edi+0x04], 0xffff
    jz .task_curent_terminate                    ;找到忙的节点，edi=节点的线性地址
    mov edi, ds:[edi]
    jmp .task_curent_search

  ;将状态为忙的节点改成终止状态
  .task_curent_terminate:
    mov word ds:[edi+0x04], 0x3333

    mov edi, es:[tcb_chain]
  ;搜索就绪状态的任务
  .task_ready_search:
    cmp word ds:[edi+0x04], 0x0000
    jz .task_switch                              ;已找到就绪节点，edi=节点的线性地址
    mov edi, ds:[edi]
    jmp .task_ready_search

  ;就绪任务的节点已经找到，准备切换到该任务
  .task_switch:
    jmp resume_task_execute            ;转去恢复并执行新任务

;清理已经终止的任务并回收资源
do_task_clean:
    ;搜索TCB链表，找到状态为终止的节点
    ;将节点从链表中拆除
    ;回收任务占用的各种资源（可以从它的TCB中找到）
    ret

SECTION core_data vfollows=sys_routine
    msg_core      db 'Setup interrupt system and system-call......', 0x0d, 0x0a, 0
    msg_core_int  db 0x0d, 0x0a, 'int0x88 test OK.', 0x0d, 0x0a, 0
    msg_core_tss  db 0x0d, 0x0a, 'Core TSS is created.', 0x0d, 0x0a, 0
    msg_core_tcb  db 0x0d, 0x0a, 'Core task created.', 0x0d, 0x0a, 0
    msg_core_run  db 0x0d, 0x0a, '[CORE TASK]: I am working!', 0x0d, 0x0a, 0
    msg_core_expt db 0x0d, 0x0a, '********Exception encounted********', 0x0d, 0x0a, 0
    msg_core_mem  db 0x0d, 0x0a, '********No more pages********', 0x0d, 0x0a, 0
    page_bit_map  db 0xff,0xff,0xff,0xff,0xff,0xff,0x55,0x55
                  db 0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff
                  db 0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff
                  db 0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff
                  db 0x55,0x55,0x55,0x55,0x55,0x55,0x55,0x55
                  db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00
                  db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00
                  db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00
    page_map_len  equ $-page_bit_map
    pgdt          dw 0                           ;用于设置和修改GDT
                  dd 0
    pidt          dw 0                           ;用于设置和修改IDT
                  dd 0
    tss           times 128 db 0                 ;任务状态段
    tcb           times 128 db 0                 ;任务状态段
    tcb_chain     dd 0                           ;任务控制块链
    core_buf      times 2048 db 0                ;内核用的缓冲区
    ;系统调用功能入口
    sys_call      dd put_string
                  dd read_hard_disk_0
                  dd terminate_current_task
                  dd initiate_task_switch
                  dd allocate_memory

SECTION core_code vfollows=core_data
;创建中断描述符表IDT
fill_idt_descriptor:
    push eax
    push ebx
    push ecx
    push edx
    push esi

    ;前20个向量是处理器异常使用的
    mov eax, general_exception_handler           ;门代码在段内偏移地址
    mov ebx, flat_core_code_seg_sel              ;门代码所在段的选择子
    mov ecx, 0x8e00                              ;32位中断门，0特权级
    call make_gate_descriptor
    mov ebx, idt_line_address                    ;中断描述符表的线性地址
    xor esi, esi
  .idt0:
    mov es:[ebx+esi*8], eax
    mov es:[ebx+esi*8+4], edx
    inc esi
    cmp esi, 19                                  ;安装前20个异常中断处理过程
    jle .idt0

    ;其余为保留或硬件使用的中断向量
    mov eax, general_interrupt_handler           ;门代码在段内偏移地址
    mov ebx, flat_core_code_seg_sel              ;门代码所在段的选择子
    mov ecx, 0x8e00                              ;32位中断门，0特权级
    call make_gate_descriptor
    mov ebx, idt_line_address                    ;中断描述符表的线性地址
  .idt1:
    mov es:[ebx+esi*8], eax
    mov es:[ebx+esi*8+4], edx
    inc esi
    cmp esi, 255                                 ;安装普通的中断处理过程
    jle .idt1

  ;设置实时时钟中断处理过程
  .rtm:
    mov eax, rtm_0x70_interrupt_handle           ;门代码在段内偏移地址
    mov ebx, flat_core_code_seg_sel              ;门代码所在段的选择子
    mov ecx, 0x8e00                              ;1_00_01110_000_00000B，32位中断门，0特权级
    call make_gate_descriptor
    mov ebx, idt_line_address                    ;中断描述符表的线性地址
    mov es:[ebx+0x70*8], eax
    mov es:[ebx+0x70*8+4], edx

  ;设置系统调用中断的处理过程
  .int:
    mov eax, int_0x88_handler                    ;门代码在段内偏移地址
    mov bx, flat_core_code_seg_sel               ;门代码所在段的选择子
    mov cx, 0xee00                               ;1_11_01110_000_00000B，32位中断门，3特权级
    call make_gate_descriptor
    mov ebx, idt_line_address                    ;中断描述符表的线性地址
    mov es:[ebx+0x88*8],eax                      ;中断向量：0x88
    mov es:[ebx+0x88*8+4],edx

  ;准备开放中断
  .load_idt:
    mov word ds:[pidt], 256*8-1                  ;IDT的界限
    mov dword ds:[pidt+2], idt_line_address
    lidt ds:[pidt]                               ;加载中断描述符表寄存器IDTR

  ;设置8259A中断控制器
  .intr_8259a:
    mov al, 0x11
    out 0x20, al                                 ;ICW1：边沿触发/级联方式
    mov al, 0x20
    out 0x21, al                                 ;ICW2:起始中断向量
    mov al, 0x04
    out 0x21, al                                 ;ICW3:从片级联到IR2
    mov al, 0x01
    out 0x21, al                                 ;ICW4:非总线缓冲，全嵌套，正常EOI

    mov al, 0x11
    out 0xa0, al                                 ;ICW1：边沿触发/级联方式
    mov al, 0x70
    out 0xa1, al                                 ;ICW2:起始中断向量
    mov al, 0x02
    out 0xa1, al                                 ;ICW3:从片级联到IR2
    mov al, 0x01
    out 0xa1, al                                 ;ICW4:非总线缓冲，全嵌套，正常EOI

  ;设置和时钟中断相关的硬件
  .cmos:
    mov al, 0x0b                                 ;RTC寄存器B
    or al, 0x80                                  ;阻断NMI
    out 0x70, al
    mov al, 0x12                                 ;设置寄存器B，禁止周期性中断，开放更新结束后中断，BCD码，24小时制
    out 0x71, al

  .intr_8259a_2:
    in al, 0xa1                                  ;读8259从片的IMR寄存器
    and al, 0xfe                                 ;清除bit 0(此位连接RTC)
    out 0xa1, al                                 ;写回此寄存器

    mov al, 0x0c
    out 0x70, al
    in al, 0x71                                  ;读RTC寄存器C，复位未决的中断状态

  .return:
    pop esi
    pop edx
    pop ecx
    pop ebx
    pop eax
    ret

;创建任务状态段TSS，整个系统实际上只需要一个TSS即可
fill_core_tss:
    push eax
    push ebx
    push ecx

    mov ecx, 32
    xor ebx, ebx
  .zero:
    mov dword ds:[tss + ebx], 0                  ;TSS的多数字段已经不用，全部清空。
    add ebx, 4
    loop .zero

  .init:
    mov word ds:[tss + 8], flat_core_data_seg_sel ;因特权级之间的转移而发生栈切换时，本系统只会发生3到0的切换。因此，只需要TSS中设置SS0，且必须是0特权级的栈段选择子
    mov word ds:[tss + 102], 103                 ;没有I/O许可位图部分

  ;创建TSS描述符，并安装到GDT中
  .gdt:
    mov eax, tss                                 ;TSS的起始线性地址
    mov ebx, 103                                 ;段长度（界限）
    mov ecx, 0x00008900                          ;TSS描述符，特权级0
    call make_seg_descriptor
    call set_up_gdt_descriptor

    ;令任务寄存器TR指向唯一的TSS并不再改变
    ltr cx

  .return:
    pop ecx
    pop ebx
    pop eax
    ret

;为内核任务创建任务控制块TCB
fill_core_tcb:
    mov word ds:[tcb + 4], 0xffff                ;任务的状态为“忙”
    mov dword ds:[tcb + 6], core_line_alloc_at   ;登记内核中可用于分配的起始线性地址
    mov ecx, tcb
    call append_to_tcb_link                      ;将内核任务的TCB添加到TCB链中

    ret

;在TCB链上追加任务控制块
;输入：ECX=TCB线性基地址
append_to_tcb_link:
    push eax
    push edx
    pushfd
    cli

    mov dword ds:[ecx+0x00], 0                   ;当前TCB指针域清零，以指示这是最后一个TCB
    mov eax, ds:[tcb_chain]                      ;TCB表头指针
    or eax, eax                                  ;链表为空？
    jz .notcb

  .searc:
    mov edx, eax
    mov eax, ds:[edx+0x00]
    or eax, eax
    jnz .searc

    mov es:[edx+0x00], ecx
    jmp .retpc

  .notcb:
    mov ds:[tcb_chain], ecx                      ;若为空表，直接令表头指针指向TCB

  .retpc:
    popfd
    pop edx
    pop eax
    ret

;为用户创建任务
;输入: PUSH逻辑扇区号
;输入: PUSH任务控制块基地址
load_relocate_program:
    pushad

    mov ebp, esp                                 ;为访问通过堆栈传递的参数做准备

    ;清空当前页目录的前半部分（对应低2GB的局部地址空间）
    mov ebx, 0xfffff000
    xor esi, esi
  .pde_zero:
    mov dword ds:[ebx+esi*4], 0x00000000
    inc esi
    cmp esi, 512
    jl .pde_zero

    mov ebx, cr3                                 ;刷新TLB
    mov cr3, ebx

  .read_app_size:                                ;读取程序大小
    mov eax, ss:[ebp+10*4]                       ;从堆栈中取出用户程序起始扇区号
    mov ebx, core_buf
    call read_hard_disk_0

    xor edx, edx
    mov eax, ds:[core_buf]                       ;程序尺寸
    mov ebx, eax
    and ebx, 0xfffffe00
    add ebx, 512                                 ;使之512字节对齐（能被512整除的数，低9位都为0）
    test eax, 0x000001ff                         ;程序的大小正好是512的倍数吗?
    cmovnz eax, ebx                              ;不是使用凑整的结果

  .alloc_app_size:
    mov esi, ss:[ebp+9*4]                        ;从堆栈中取得TCB的基地址
    mov ebx, esi
    mov ecx, eax                                 ;实际需要申请的内存数量
    call task_alloc_memory

  .calc_app_sector:                              ;总扇区数
    mov ebx, ecx                                 ;申请到的内存首地址
    xor edx, edx
    mov ecx, 512
    div ecx
    mov ecx, eax

    mov eax, ss:[ebp+10*4]                       ;起始扇区号
  .load_app:
    call read_hard_disk_0
    inc eax
    loop .load_app

  .stack3_init:                                  ;为用户任务分配栈空间
    mov ebx, esi                                 ;TCB的线性地址
    mov ecx, 4096                                ;4KB的空间
    call task_alloc_memory
    mov ecx, ds:[esi+6]                          ;下一次分配的起始线性地址就是栈顶指针
    mov dword ds:[esi+70], ecx

  .stack0_init:                                  ;创建用于中断和调用门的0特权级栈空间
    mov ebx, esi
    mov ecx, 4096                                ;4KB的空间
    call task_alloc_memory
    mov ecx, ds:[esi+6]                          ;下一次分配的起始线性地址就是栈顶指针
    mov dword ds:[esi+10], ecx                   ;TCB的ESP0域

  .pdt_copy:                                     ;创建用户任务的页目录
    call create_copy_cur_pdir
    mov ds:[esi + 22], eax                       ;填写TCB的CR3(PDBR)域

    mov word ds:[esi+30], flat_user_code_seg_sel ;TCB的CS域
    mov word ds:[esi+32], flat_user_data_seg_sel ;TCB的SS域
    mov word ds:[esi+34], flat_user_data_seg_sel ;TCB的DS域
    mov word ds:[esi+36], flat_user_data_seg_sel ;TCB的ES域
    mov word ds:[esi+38], flat_user_data_seg_sel ;TCB的FS域
    mov word ds:[esi+40], flat_user_data_seg_sel ;TCB的GS域
    mov eax, ds:[0x04]                           ;从任务的4GB地址空间获取入口点
    mov ds:[esi+26], eax                         ;填写TCB的EIP域
    pushfd
    pop dword ds:[esi+74]                        ;填写TCB的EFLAGS域
    mov word ds:[esi+4], 0                       ;任务状态：就绪

  .return:
    popad
    ret 8                                        ;丢弃调用本过程前压入的参数

start:
    mov ebx, msg_core
    call put_string

    call fill_idt_descriptor

    ;测试系统调用
    mov ebx, msg_core_int
    mov eax, 0                                   ;通过系统调用的0号功能显示信息
    int 0x88                                     ;尽管TSS尚未准备好，但不会切换栈

    sti                                          ;开放硬件中断

    call fill_core_tss
    mov ebx, msg_core_tss
    call put_string

    call fill_core_tcb
    ;现在可认为“程序管理器”任务正执行中
    mov ebx, msg_core_tcb
    call put_string

    mov ecx, 128                                 ;为TCB分配内存
    call allocate_memory
    mov word ds:[ecx+0x04], 0                    ;任务状态：就绪
    mov dword ds:[ecx+0x06], 0                   ;任务内可用于分配的初始线性地址
    push dword app0_start_sector                 ;用户程序位于逻辑50扇区
    push ecx                                     ;压入任务控制块起始线性地址
    call load_relocate_program                   ;加载用户app
    call append_to_tcb_link                      ;将此TCB添加到TCB链中，必须最后添加防止还没创建好任务，就在切换

    mov ecx, 128                                 ;为TCB分配内存
    call allocate_memory
    mov word ds:[ecx+0x04], 0                    ;任务状态：就绪
    mov dword ds:[ecx+0x06], 0                   ;任务内可用于分配的初始线性地址
    push dword app1_start_sector                 ;用户程序位于逻辑100扇区
    push ecx                                     ;压入任务控制块起始线性地址
    call load_relocate_program                   ;加载用户app
    call append_to_tcb_link                      ;将此TCB添加到TCB链中，必须最后添加防止还没创建好任务，就在切换

  .do_switch:
    mov ebx, msg_core_run
    call put_string

    call do_task_clean                           ;清理已经终止的任务，并回收它们占用的资源

    hlt

    jmp .do_switch

SECTION core_tail
core_end:
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
    call .get_cursor
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
    call .put_char
    jmp .next_char
  ;光标移动到当前行的第一列
  .cr:
    mov cl, 80
    div cl
    mul cl
    call .set_cursor
    jmp .next
  ;光标移动到下一行，列位置不变
  .lf:
    add eax, 80
    call .roll_screen
    jmp .next
  ;以下将光标位置推进一个字符
  .next_char:
    add eax, 1
    call .roll_screen
  ;下一个字符
  .next:
    inc ebx
    jmp .getc

  .exit:
    pop ecx
    pop ebx
    pop eax
    retf

  ;获取光标，输出：eax=光标位置
  .get_cursor:
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

    ; popad
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
    ;一个字符在显存中对应两个字节，这里必须乘以2
    shl eax, 1
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
    msg_core      db 'We are now in protect mode, and the system core is loaded, and the video display routine works perfectly.', 0x0d, 0x0a, 0
    msg_gate      db 0x0d, 0x0a, 'System wide CALL-GATE mounted.', 0x0d, 0x0a, 0
    msg_core_init db 0x0d, 0x0a, '[CORE TASK]: Running at CPL=0. Now create user task and switch to it.', 0x0d, 0x0a, 0
    msg_core_load db 0x0d, 0x0a, '[CORE TASK]: Loading user program...', 0x0d, 0x0a, 0
    msg_core_run  db 0x0d, 0x0a, '[CORE TASK]: I am working!', 0x0d, 0x0a, 0
    msg_core_wait db 0x0d, 0x0a, '[CORE TASK]: No task to be switched,sleep!', 0x0d, 0x0a, 0
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
              dd  terminate_current_task
              dw  sys_routine_seg_sel
    salt_4  db  '@InitTaskSwitch'
              times 256-($-salt_4) db 0
              dd  initiate_task_switch
              dw  sys_routine_seg_sel
    salt_item_len   equ $-salt_4
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

;安装为整个系统服务的调用门，特权级之间的控制转移必须使用门
install_gate_descriptor:
    pushad

    ;core-salt表的条目数量
    mov ecx, salt_items
    ;core-salt表的起始位置
    mov edi, salt
  .install_gate:
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
    loop .install_gate

    popad
    ret

;为内核创建任务
install_core_task:
    pushad

    ;为内核任务创建任务控制块TCB
    mov ecx, 0x46
    call sys_routine_seg_sel:allocate_memory
    ;任务的状态为“忙”
    mov word es:[ecx+0x04], 0xffff
    ;将此TCB添加到TCB链中
    call append_to_tcb_link
    mov esi, ecx

    ;为内核任务的TSS分配内存空间
    mov ecx, 104
    mov es:[esi+0x12], cx
    call sys_routine_seg_sel:allocate_memory
    ;在内核TCB中保存TSS基地址
    mov es:[esi+0x14], ecx
    ;在程序管理器(内核)的TSS中设置必要的项目
    ;没有LDT。处理器允许没有LDT的任务
    mov word es:[ecx+96], 0
    ;没有I/O位图。0特权级事实上不需要
    mov word es:[ecx+102], 103
    ;反向链=0
    mov word es:[ecx+0], 0
    ;登记CR3(PDBR)
    mov dword es:[ecx+28], 0
    ;T=0
    mov word es:[ecx+100], 0
    ;不需要0、1、2特权级堆栈。0特级不会向低特权级转移控制

    ;创建TSS描述符，并安装到GDT中
    ;TSS的起始线性地址
    mov eax, ecx
    ;段长度（界限）
    mov ebx, 103
    ;TSS描述符，特权级0
    mov ecx, 0x00008900
    call sys_routine_seg_sel:make_seg_descriptor
    call sys_routine_seg_sel:set_up_gdt_descriptor
    ;登记TSS选择子到TCB
    mov word es:[esi+0x18], cx

    ;任务寄存器TR中的内容是任务存在的标志，该内容也决定了当前任务是谁
    ;下面的指令为当前正在执行的0特权级任务“程序管理器”后补手续（TSS）
    ltr cx

    popad
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

    popad
    ret

start:
    ;使ds指向核心数据段
    mov eax, core_data_seg_sel
    mov ds, eax
    ;令es指向4GB数据段
    mov ecx, mem_4gb_data_seg_sel
    mov es,ecx

    ;显示保护模式提示信息
    mov ebx, msg_core
    call sys_routine_seg_sel:put_string

    call install_gate_descriptor
    ;通过门显示信息(偏移量将被忽略)
    mov ebx, msg_gate
    call far [ds:salt_1+256]

    call install_core_task
    ;现在可认为“程序管理器”任务正执行中
    mov ebx, msg_core_init
    call sys_routine_seg_sel:put_string

    ;显示加载用户app提示信息，在内核中调用例程不需要通过门
    mov ebx, msg_core_load
    call sys_routine_seg_sel:put_string
    mov esi, app_start_sector
    call load_relocate_program

    ;可以创建更多的任务，重复load_relocate_program步骤

  .do_switch:
    ;主动切换到其它任务，给它们运行的机会
    call sys_routine_seg_sel:initiate_task_switch

    mov ebx, msg_core_run
    call sys_routine_seg_sel:put_string

    ;这里可以添加创建新的任务的功能，比如：
    ; mov ebx, msg_core_load
    ; call sys_routine_seg_sel:put_string
    ; mov esi, app_start_sector
    ; call load_relocate_program

    ;清理已经终止的任务，并回收它们占用的资源
    call sys_routine_seg_sel:do_task_clean

    mov eax, ds:[tcb_chain]
  .find_ready:
    ;还有处于就绪状态的任务？
    cmp word es:[eax+0x04], 0x0000
    ;有，继续执行任务切换
    jz .do_switch
    mov eax, es:[eax]
    ;还有用户任务吗？
    or eax, eax
    ;一直搜索到链表尾部
    jnz .find_ready

    ;已经没有可以切换的任务，停机
    mov ebx, msg_core_wait
    call sys_routine_seg_sel:put_string
    hlt

SECTION core_trail
core_end:

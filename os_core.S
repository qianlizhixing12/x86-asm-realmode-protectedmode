.include "config.S"

.att_syntax prefix
.code32

# 系统核心的头部，用于加载核心程序
.section .header,"aw",@progbits
.balign 16
header_begin:
  #                                                      偏移
  core_length:      .long core_end-header_begin          # [0x00]核心程序总长度
  sys_routine_seg:  .long sys_routine_begin              # [0x04]系统公用例程段位置
  core_data_seg:    .long core_data_begin                # [0x08]核心数据段位置
  core_code_seg:    .long core_code_begin                # [0x0c]核心代码段位置
  core_entry:       .long start-core_code_begin          # [0x10]核心代码段入口点
                    .word core_code_seg_sel              # [0x14]
header_end:

.section .sys_routine,"ax",@progbits
.balign 16
sys_routine_begin:
# 获取光标,仅用于段内调用
# 输出：eax=光标位置
get_cursor:
  pushl %edx

  xorl %eax, %eax

  # 光标位置高字节
  movw $0x3d4, %dx
  movb $0x0e, %al
  outb %al, %dx
  movw $0x3d5, %dx
  inb %dx, %al
  movb %al, %ah
  # 光标位置低字节
  movw $0x3d4, %dx
  movb $0x0f, %al
  outb %al, %dx
  movw $0x3d5, %dx
  inb %dx, %al

  popl %edx
  ret

# 设置光标,仅用于段内调用
# 输入：eax=光标位置
set_cursor:
  pushl %eax
  pushl %ebx
  pushl %edx

  movl %eax, %ebx

  # 光标位置高字节
  movw $0x3d4, %dx
  movb $0x0e, %al
  outb %al, %dx
  movw $0x3d5, %dx
  movb %bh, %al
  outb %al, %dx
  # 光标位置低字节
  movw $0x3d4, %dx
  movb $0x0f, %al
  outb %al, %dx
  movw $0x3d5, %dx
  movb %bl, %al
  outb %al, %dx

  popl %edx
  popl %ebx
  popl %eax
  ret

# 判断光标是否超出屏幕滚屏,仅用于段内调用
# 输入：eax=光标位置
# 输出：eax=光标位置
roll_screen:
  cmpl $2000, %eax
  jl 1f

  pushl %ebx
  pushl %ecx
  pushw %ds
  pushw %es
  pushl %esi
  pushl %edi

  # 第二行～第二十五行向上移动
  movl $video_ram_seg_sel, %ebx
  movw %bx, %ds
  movw %bx, %es
  cld
  movl $0xa0, %esi
  xorl %edi, %edi
  movl $1920, %ecx
  rep movsw

  # 清除屏幕最底一行
  movw $3840, %di
  movw $80, %cx
  movw $0x0720, %ax
  rep stosw

  popl %edi
  popl %esi
  popw %es
  popw %ds
  popl %ecx
  popl %ebx

1:
  ret

# 显示单个字符,仅用于段内调用
# 输入：cl=字符ascii
# 输入：eax=光标位置
put_char:
  pushl %eax
  pushl %ebx
  pushw %es

  movl $video_ram_seg_sel, %ebx
  movw %bx, %es
  movl %eax, %ebx
  shll $1, %ebx         # 一个字符在显存中对应两个字节，这里必须乘以2
  movb %cl, %al
  movb $0x0c, %ah       # 黑底红字
  movw %ax, %es:(%ebx)

  popw %es
  popl %ebx
  popl %eax
  ret

# 字符串显示例程，显示0终止的字符串并移动光标
# 输入：DS:EBX=串地址
put_string:
  pushl %eax
  pushl %ebx
  pushl %ecx

  # 获取光标位置存在ax中
  call get_cursor
1:
  movb %ds:(%ebx), %cl
  cmpb $0x00, %cl
  jz 5f                # cl=0退出
  cmpb $0x0d, %cl
  jz 2f                # 回车符
  cmpb $0x0a, %cl
  jz 3f                # 换行符
  call put_char        # 正常显示字符
  incl %ebx
  call roll_screen
  call set_cursor
  jmp 4f               # 处理下一个字符

  # 回车符处理(光标移动到当前行的第一列)
2:
  movb $80, %bl
  divb %bl
  mulb %bl
  call set_cursor
  jmp 4f

  # 换行符处理(光标移动到下一行，列位置不变)
3:
  addl $80, %eax
  call roll_screen
  call set_cursor
  jmp 4f

  # 处理下一个字符
4:
  incl %ebx
  jmp 1b

5:
  popl %ecx
  popl %ebx
  popl %eax
  ret

# 从硬盘读取一个逻辑扇区
# 输入：ESI=逻辑扇区号
# 输入：DS:EDI=目标缓冲区地址
# 输出：EDI=EDI+512
read_hard_disk_0:
    push eax
    push ebx
    push ecx
    push edx

    mov dx, 0x1f2
    # 读取的扇区数
    mov al, 1
    out dx, al

    mov dx, 0x1f3
    mov eax, esi
    # LBA地址7~0
    out dx, al

    mov dx, 0x1f4
    shr eax, 8
    # LBA地址15~8
    out dx, al

    mov dx, 0x1f5
    shr eax, 8
    # LBA地址23~16
    out dx, al

    mov dx, 0x1f6
    shr eax, 8
    or al, 0xe0
    # LBA地址27~24
    out dx, al

    mov dx, 0x1f7
    # 读命令
    mov al, 0x20
    out dx, al

  .waits:
    in al, dx
    and al, 0x88
    cmp al, 0x08
    # 不忙，且硬盘已准备好数据传输
    jnz .waits

    # 总共要读取的字数
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

# 分配内存
# 输入：ECX=希望分配的字节数
# 输出：ECX=起始线性地址
allocate_memory:
    push eax
    push ebx
    push ds

    mov eax, core_data_seg_sel
    mov ds, eax

    # 下一次分配时的起始地址
    mov eax, ds:[ram_alloc]
    add eax, ecx

    # 这里应当有检测可用内存数量的指令
    # 返回分配的起始地址
    mov ecx, ds:[ram_alloc]

    mov ebx, eax
    # 强制对齐
    and ebx, 0xfffffffc
    add ebx, 4
    # 下次分配的起始地址最好是4字节对齐
    test eax, 0x00000003
    # 如果没有对齐，则强制对齐
    cmovnz eax, ebx
    # 下次从该地址分配内存
    mov ds:[ram_alloc], eax

    pop ds
    pop ebx
    pop eax
    retf

# 构造存储器和系统的段描述符
# 输入：EAX=线性基地址
# 输入：EBX=段界限
# 输入：ECX=属性（各属性位都在原始位置，其它没用到的位置0）
# 输出：EDX:EAX=完整的描述符
make_seg_descriptor:
    mov edx, eax
    shl eax, 16
    # 描述符前32位(EAX)构造完毕
    or ax, bx

    # 清除基地址中无关的位
    and edx, 0xffff0000
    rol edx, 8
    # 装配基址的31~24和23~16(80486+)
    bswap edx

    xor bx, bx
    # 装配段界限的高4位
    or edx, ebx
    # 装配属性
    or edx, ecx

    retf

# 在GDT内安装一个新的描述符
# 输入：EDX:EAX=描述符
# 输出：CX=描述符的选择子
set_up_gdt_descriptor:
    push eax
    push ebx
    push edx
    push ds
    push es

    # 切换到核心数据段
    mov ebx, core_data_seg_sel
    mov ds, ebx
    mov ebx, mem_4gb_data_seg_sel
    mov es, ebx

    # 获取GDT
    sgdt ds:[pgdt]

    # GDT界限
    movzx ebx, word ds:[pgdt]
    # GDT总字节数，也是下一个描述符偏移
    inc ebx
    # 下一个描述符的线性地址
    add ebx, ds:[pgdt+2]

    mov es:[ebx], eax
    mov es:[ebx+4], edx
    # 增加一个描述符的大小
    add word ds:[pgdt], 8

    # 对GDT的更改生效
    lgdt ds:[pgdt]

    # 得到GDT界限值
    mov ax, ds:[pgdt]
    xor dx, dx
    mov bx, 8
    div bx
    mov cx, ax
    # 将索引号移到正确位置
    shl cx, 3

    pop es
    pop ds
    pop edx
    pop ebx
    pop eax
    retf
sys_routine_end:

.section .core_data,"a",@progbits
.balign 16
core_data_begin:
  msg_os: .ascii "We are now in protect mode, and the system core is loaded, "
          .ascii "and the video display routine works perfectly."
          .byte 0x0d, 0x0a, 0x0d, 0x0a, 0
  msg_user_load: .ascii "Loading user program..."
                 .byte 0x0d, 0x0a, 0
  msg_user_run: .ascii "Run user program..."
                .byte 0x0d, 0x0a, 0
  msg_user_ret: .ascii "User program terminated, control returned."
                .byte 0x0d, 0x0a, 0
  core_buf: .fill 2048, 1, 0    # 内核用的缓冲区
  ram_alloc: .long 0x00100000   # 下次分配内存时的起始地址
  pgdt: .word 0                 # 用于设置和修改GDT
        .long 0
  esp_pointer: .long 0          # 内核用来临时保存自己的栈指针
  salt:                         # 符号地址检索表
  salt_1: .ascii "@PrintString"
          .fill 256-(.-salt_1), 1, 0
          .long (put_string-sys_routine_begin)
          .word sys_routine_seg_sel
  salt_2: .ascii "@ReadDiskData"
          .fill 256-(.-salt_2), 1, 0
          .long (read_hard_disk_0-sys_routine_begin)
          .word sys_routine_seg_sel
  salt_3: .ascii "@TerminateProgram"
          .fill 256-(.-salt_3), 1, 0
          .long (return_point-sys_routine_begin)
          .word sys_routine_seg_sel
  .equ salt_item_len (.-salt_3)
  .equ salt_items (.-salt)/salt_item_len
core_data_end:

.section .core_code,"ax",@progbits
.balign 16
core_code_begin:
# 加载并重定位用户程序
# 输入：ESI=逻辑扇区号
# 返回：AX=指向用户程序头部的选择子
load_relocate_program:
  pushl %ebx
  pushl %ecx
  pushl %edx
  pushl %esi
  pushl %edi

  pushw %ds
  pushw %es

  # 切换DS到内核数据段
  mov eax, core_data_seg_sel
  mov ds, eax

  # 读取程序头部数据(在os缓存区进行)
  mov edi, core_buf
  call sys_routine_seg_sel:read_hard_disk_0

  # 程序尺寸
  mov eax, ds:[core_buf]
  # 使之512字节对齐（能被512整除的数，低9位都为0）
  mov ebx, eax
  and ebx, 0xfffffe00
  add ebx, 512
  # 程序的大小正好是512的倍数吗?
  test eax, 0x000001ff
  # 不是使用凑整的结果
  cmovnz eax, ebx
  # 程序尺寸 512对齐
  mov ebx, eax

  # 实际需要申请的内存数量
  mov ecx, eax
  call sys_routine_seg_sel:allocate_memory
  # 申请到的内存首地址
  mov edi, ecx

  # 总扇区数
  xor edx, edx
  mov ecx, 512
  div ecx
  mov ecx, eax

  # 临时变量 bx=程序尺寸512对齐 edi=申请到的内存首地址 ecx=总扇区数
  push edi
  # 切换DS到0-4GB的段
  mov eax, mem_4gb_data_seg_sel
  mov ds, eax
.read_program:
  call sys_routine_seg_sel:read_hard_disk_0
  inc esi
  # 循环读，直到读完整个用户程序
  loop .read_program

  # 建立程序头部段描述符
  # 恢复程序装载的首地址
  pop edi
  # 程序头部起始线性地址
  mov eax, edi
  mov ebx, ds:[edi+0x04]
  # 段界限
  dec ebx
  # 字节粒度的数据段描述符
  mov ecx, 0x00409200
  call sys_routine_seg_sel:make_seg_descriptor
  call sys_routine_seg_sel:set_up_gdt_descriptor
  mov ds:[edi+0x04], cx

  # 建立程序代码段描述符
  # 代码起始线性地址
  mov eax, edi
  add eax, ds:[edi+0x0c]
  mov ebx, ds:[edi+0x10]
  # 段界限
  dec ebx
  # 字节粒度的代码段描述符
  mov ecx, 0x00409800
  call sys_routine_seg_sel:make_seg_descriptor
  call sys_routine_seg_sel:set_up_gdt_descriptor
  mov ds:[edi+0x0c], cx

  # 建立程序数据段描述符
  # 数据段起始线性地址
  mov eax, edi
  add eax, ds:[edi+0x14]
  mov ebx, ds:[edi+0x18]
  # 段界限
  dec ebx
  # 字节粒度的数据段描述符
  mov ecx, 0x00409200
  call sys_routine_seg_sel:make_seg_descriptor
  call sys_routine_seg_sel:set_up_gdt_descriptor
  mov ds:[edi+0x14], cx

  # 建立程序堆栈段描述符
  # 数据段起始线性地址
  mov eax, edi
  add eax, ds:[edi+0x1c]
  mov ebx, ds:[edi+0x20]
  # 段界限
  dec ebx
  # 字节粒度的数据段描述符
  mov ecx, 0x00409200
  call sys_routine_seg_sel:make_seg_descriptor
  call sys_routine_seg_sel:set_up_gdt_descriptor
  mov ds:[edi+0x1c], cx

  # 重定位SALT
  mov eax, ds:[edi+0x04]
  # es用户程序头部
  mov es, eax
  mov eax, core_data_seg_sel
  mov ds, eax

  cld

  # 用户程序的SALT条目数
  mov ecx, es:[0x24]
  # 用户程序内的SALT位于头部内0x28处
  mov edi, 0x28
.b2:
  push ecx
  push edi

  # 系统公共例程SALT条目数
  mov ecx, salt_items
  mov esi, salt
.b3:
  push edi
  push esi
  push ecx

  # 检索表中，每条目的比较次数
  mov ecx, 64
  # 每次比较4字节
  repe cmpsd
  jnz .b4
  # 若匹配，esi恰好指向其后的地址数据
  mov eax, ds:[esi]
  # 将字符串改写成偏移地址
  mov es:[edi-256], eax
  mov ax, ds:[esi+4]
  # 段选择子
  mov es:[edi-252], ax
.b4:
  pop ecx
  pop esi
  add esi, salt_item_len
  # 从头比较
  pop edi
  loop .b3

  pop edi
  add edi, 256
  pop ecx
  loop .b2

  mov ax, es:[0x04]

  # 恢复到调用此过程前的es段
  pop es
  # 恢复到调用此过程前的ds段
  pop ds
  pop edi
  pop esi
  pop edx
  pop ecx
  pop ebx
  ret

start:
  # 使ds指向核心数据段
  movl $core_data_seg_sel, %eax
  movw %ax, %ds

  # 显示保护模式提示信息
  movl $(msg_os-core_data_begin), %ebx
  lcall $sys_routine_seg_sel, $(put_string-sys_routine_begin)

  # 显示加载用户app提示信息
  movl $(msg_user_load-core_data_begin), %ebx
  lcall $sys_routine_seg_sel, $(put_string-sys_routine_begin)

  # 用户程序位于逻辑50扇区
  movl $app_start_sector, %esi
  call load_relocate_program

  # 显示运行用户app提示信息
  movl $(msg_user_run-core_data_begin), %ebx
  lcall $sys_routine_seg_sel, $(put_string-sys_routine_begin)

  # 临时保存堆栈指针
  movl %esp, %ds:$(esp_pointer-core_data_begin)
  movw %ax, %ds
  # 控制权交给用户程序（入口点）,堆栈可能切换
  ljmp *%ds:0x08

# 用户程序返回点
return_point:
  movl $core_data_seg_sel, %eax
  movw %ax, %ds

  # 切换回内核自己的堆栈
  movl $mem_stack_seg_sel, %eax
  movw %ax, %ss
  movl %ds:$(esp_pointer-core_data_begin), %esp

  # 显示用户app返回提示信息
  movl $(msg_user_ret-core_data_begin), %ebx
  lcall $sys_routine_seg_sel, $(put_string-sys_routine_begin)

  # 这里可以放置清除用户程序各种描述符的指令
  # 也可以加载并启动其它程序
  hlt
core_code_end:

.section .trail,"a",@progbits
core_end:

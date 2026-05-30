.att_syntax prefix
.code16

# 用户程序头部段
.section .header,"aw",@progbits
.balign 16
header_begin:
  #                                                                        偏移
  program_length:  .long program_end-header_begin      # 程序总长度         [0x00]
  code_entry:      .word start-code_begin              # 程序入口点         [0x04]
                   .long code_begin          #                          [0x06]
  realloc_tbl_len: .word (header_end-code_segment)/4   # 段重定位表项个数    [0x0a]
  code_segment:    .long code_begin                    #                  [0x0c]
  data_segment:    .long data_begin                    #                  [0x10]
  stack_segment:   .long stack_begin                   #                  [0x14]
header_end:

.section .code,"ax",@progbits
.balign 16
code_begin:
# 获取光标
# 输出：di=光标位置
get_cursor:
  pushw %ax
  pushw %dx

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

  movw %ax, %di

  popw %dx
  popw %ax
  ret

# 设置光标
# 输入：di=光标位置
set_cursor:
  pushw %ax
  pushw %dx

  # 光标位置高字节
  movw $0x3d4, %dx
  movb $0x0e, %al
  outb %al, %dx
  movw $0x3d5, %dx
  movw %di, %ax
  movb %ah, %al
  outb %al, %dx
  # 光标位置低字节
  movw $0x3d4, %dx
  movb $0x0f, %al
  outb %al, %dx
  movw $0x3d5, %dx
  movw %di, %ax
  outb %al, %dx

  popw %dx
  popw %ax
  ret

# 判断光标是否超出屏幕滚屏
# 输入：di=光标位置
# 输出：di=光标位置
roll_screen:
  cmpw $2000, %di
  jl 1f

  pushw %ax
  pushw %cx
  pushw %ds
  pushw %es
  pushw %si
  pushw %di

  # 第二行～第二十五行向上移动
  movw $0xb800, %ax
  movw %ax, %ds
  movw %ax, %es
  cld
  movw $0xa0, %si
  xorw %di, %di
  movw $1920, %cx
  rep movsw

  # 清除屏幕最底一行
  movw $3840, %di
  movw $80, %cx
  movw $0x0720, %ax
  rep stosw

  popw %di
  popw %si
  popw %es
  popw %ds
  popw %cx
  popw %ax
  subw $80, %di

1:
  ret

# 显示单个字符
# 输入：cl=字符ascii
# 输入：di=光标位置
put_char:
  pushw %ax
  pushw %di
  pushw %es

  movw $0xb800, %ax
  movw %ax, %es
  movb %cl, %al
  movb $0x0c, %ah       # 黑底红字
  shlw $1, %di          # 每个字符在显存中对应两个字节，这里必须乘以2
  movw %ax, %es:(%di)

  popw %es
  popw %di
  popw %ax
  ret

# 显示字符串(0结尾)
# 输入：DS:si=串地址
put_string:
  pushw %ax
  pushw %bx
  pushw %cx
  pushw %si
  pushw %di

  # 获取光标位置存在di中
  call get_cursor

  # 依次处理各个字符
1:
  movb %ds:(%si), %cl
  cmpb $0x00, %cl
  jz 5f                # cl=0退出
  cmpb $0x0d, %cl
  jz 2f                # 回车符
  cmpb $0x0a, %cl
  jz 3f                # 换行符
  call put_char        # 正常显示字符
  incw %di
  call roll_screen
  call set_cursor
  jmp 4f               # 处理下一个字符

  # 回车符处理(光标移动到当前行的第一列)
2:
  movw %di, %ax
  movb $80, %bl
  divb %bl
  mulb %bl
  movw %ax, %di
  call set_cursor
  jmp 4f

  # 换行符处理(光标移动到下一行，列位置不变)
3:
  addw $80, %di
  call roll_screen
  call set_cursor
  jmp 4f

  # 处理下一个字符
4:
  incw %si
  jmp 1b

5:
  popw %di
  popw %si
  popw %cx
  popw %bx
  popw %ax
  ret

// BCD码转ASCII
// 输入：AL=bcd码
// 输出：AX=ascii
bcd_to_ascii:
  movb %al, %ah

  andb $0x0f, %al
  addb $'0', %al

  shrb $4, %ah
  andb $0x0f, %ah
  addb $'0', %ah

  ret

# 0x70中断，获取时间，显示时间
new_int_0x70:
  pushw %ax
  pushw %bx
  pushw %es

1:
  # RTC寄存器A索引，屏蔽NMI，等待更新完成
  movb $0x8a, %al
  outb %al, $0x70
  inb $0x71, %al
  test $0x80, %al
  jnz 1b

  # 从屏幕上的12行36列开始显示
  movw $0xb800, %ax
  movw %ax, %es
  mov $(12*160 + 30*2), %bx

  # 读显示RTC当前时间(时)
  movb $0x84, %al
  outb %al, $0x70
  inb $0x71, %al
  call bcd_to_ascii
  movb %ah, %es:(%bx)
  movb %al, %es:2(%bx)

  # 显示分隔符:
  movb $':', %al
  movb %al, %es:4(%bx)

  # 读显示RTC当前时间(分)
  movb $0x82, %al
  outb %al, $0x70
  inb $0x71, %al
  call bcd_to_ascii
  movb %ah, %es:6(%bx)
  movb %al, %es:8(%bx)

  # 显示分隔符:
  movb $':', %al
  movb %al, %es:10(%bx)

  # 读显示RTC当前时间(秒)
  movb $0x80, %al
  outb %al, $0x70
  inb $0x71, %al
  call bcd_to_ascii
  movb %ah, %es:12(%bx)
  movb %al, %es:14(%bx)

  # 读取寄存器C是清除所有中断标志，否则RTC无法产生新的中断
  movb $0x0c, %al
  outb %al, $0x70
  inb $0x71, %al

  # 发送中断结束命令EOI
  movb $0x20, %al
  outb %al, $0xa0      # 从片
  outb %al, $0x20      # 主片

  popw %es
  popw %bx
  popw %ax
  iret

# 程序入口，初始执行时，DS和ES指向用户程序头部段
start:
  # 设置程序自己的堆栈
  movw %es:stack_segment, %ax
  movw %ax, %ss
  movw $stack_end, %sp

  # 设置程序自己的数据段
  movw %es:data_segment, %ax
  movw %ax, %ds

  # 显示初始信息
  movw $(init_msg-data_begin), %si
  call put_string
  # 显示安装信息
  movw $(inst_msg-data_begin), %si
  call put_string

  # 防止改动期间发生新的0x70号中断
  cli

  # 接管0x70号中断
  pushw %es
  xorw %ax, %ax
  movw %ax, %es
  movw $(new_int_0x70-code_begin), %es:(0x70 * 4)
  movw %cs, %es:(0x70 * 4 + 2)
  popw %es

  # RTC寄存器B索引，屏蔽NMI，保存原值
  movb $0x8b, %al
  outb %al, $0x70
  inb $0x71, %al
  movb %al, %ah

  # 禁止周期性中断，开放更新结束后中断，BCD码，24小时制
  movb $0x8b, %al
  outb %al, $0x70
  movb %ah, %al
  movb $0x12, %al
  outb %al, $0x71

  # 读取寄存器C是清除所有中断标志，否则RTC无法产生新的中断
  movb $0x0c, %al
  outb %al, $0x70
  inb $0x71, %al

  # 开放从8259A的IRQ8(RTC中断)
  inb $0xa1, %al
  andb $0xfe, %al
  outb %al, $0xa1

  # 重新开放中断
  sti

  # 显示安装完成信息
  movw $(done_msg-data_begin), %si
  call put_string

  # 显示提示信息
  movw $(tips_msg-data_begin), %si
  call put_string

idle:
  hlt
  jmp idle
code_end:

.section .data,"aw",@progbits
.balign 16
data_begin:
  init_msg: .ascii "Starting...\r\n\0"
  inst_msg: .ascii "Installing a new interrupt 70H...\0"
  done_msg: .ascii "Done.\r\n\0"
  tips_msg: .ascii "Clock is now working.\0"
data_end:

.section .stack,"aw",@nobits
.balign 16
stack_begin:
  .space 256
stack_end:

.section .trail,"a",@progbits
.balign 16
program_end:

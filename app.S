.att_syntax prefix
.code16

# 用户程序头部段
.section .header,"aw",@progbits
.balign 16
header_begin:
  #                                                                        偏移
  program_length:  .long program_end-header_begin      # 程序总长度         [0x00]
  code_entry:      .word start-code_1_begin            # 程序入口点         [0x04]
                   .long code_1_begin          #                          [0x06]
  realloc_tbl_len: .word (header_end-code_1_segment)/4 # 段重定位表项个数    [0x0a]
  code_1_segment:  .long code_1_begin                  #                  [0x0c]
  code_2_segment:  .long code_2_begin                  #                  [0x10]
  data_1_segment:  .long data_1_begin                  #                  [0x14]
  data_2_segment:  .long data_2_begin                  #                  [0x18]
  stack_segment:   .long stack_begin                   #                  [0x1c]
header_end:

.section .code_1,"ax",@progbits
.balign 16
code_1_begin:
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

# 程序入口，初始执行时，DS和ES指向用户程序头部段
start:
  # 设置程序自己的堆栈
  movw %es:stack_segment, %ax
  movw %ax, %ss
  movw $stack_end, %sp

  # 设置程序自己的数据段
  movw %es:data_1_segment, %ax
  movw %ax, %ds
  # 显示第一段信息
  movw $(data_1_begin-data_1_begin), %si
  call put_string

  # 转移到代码段2执行
  pushw %es:code_2_segment
  pushw $(code_2_begin-code_2_begin)
  lretw

run:
  # 段寄存器DS切换到数据段2
  movw %es:data_2_segment, %ax
  movw %ax, %ds
  # 显示第二段信息
  movw $(data_2_begin-data_2_begin), %si
  call put_string

1:
  jmp 1b
code_1_end:

.section .code_2,"ax",@progbits
.balign 16
code_2_begin:
  # 转移到代码段1接着执行
  pushw %es:code_1_segment
  pushw $(run-code_1_begin)
  lretw
code_2_end:

.section .data_1,"a",@progbits
.balign 16
data_1_begin:
  .ascii "This is GAS "
  .ascii "Simple bootload!"
  .byte 0x0d,0x0a,0x0d,0x0a
  .byte 0
data_1_end:

.section .data_2,"a",@progbits
.balign 16
data_2_begin:
  .ascii "The above contents is written by nxx "
  .ascii "2026-02-05!"
  .byte 0
data_2_end:

.section .stack,"aw",@nobits
.balign 16
stack_begin:
  .space 256
stack_end:

.section .trail,"a",@progbits
.balign 16
program_end:

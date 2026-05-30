.att_syntax prefix
.code16

.section .text,"awx",@progbits
.global _start
.type _start, @function
_start:
  xorw %ax, %ax
  movw %ax, %ds
  movw %ax, %ss
  movw $0x7c00, %sp

  # 计算GDT所在的逻辑段地址
  movw pgdt + 0x02, %ax
  movw pgdt + 0x04, %dx
  movw $16, %bx
  divw %bx
  # ES指向该段以进行操作
  movw %ax, %es
  # 段内起始偏移地址
  movw %dx, %bx

  # 创建空描述符，处理器要求
  movl $0x00000000, %es:(%bx)
  movl $0x00000000, %es:0x04(%bx)

  # 创建数据段描述符，对应0~4GB的线性地址空间
  movl $0x0000ffff, %es:0x08(%bx)     # 基地址为0，段界限为0xfffff，4GB
  movl $0x00cf9200, %es:0x0c(%bx)     # 粒度为4KB，向上扩展(c=1100 92=10010010)

  # 创建数据段描述符（文本模式下的显示缓冲区）
  movl $0x8000ffff, %es:0x10(%bx)     # 基地址为0x000b8000，段界限为0xfffff
  movl $0x0040920b, %es:0x14(%bx)     # 粒度为1B，向上扩展(4=0100 92=10010010)

  # 创建代码段描述符
  movl $0x7c0001ff, %es:0x18(%bx)     # 基地址为0x00007c00，段界限为0x001ff，512字节
  movl $0x00409800, %es:0x1c(%bx)     # 粒度为1B，代码段描述符（4=0100 98=10011000）

  # 创建栈段描述符
  movl $0x7c00fffe, %es:0x20(%bx)     # 基地址为0x00007c00，段界限为0xffffe
  movl $0x00cf9600, %es:0x24(%bx)     # 粒度为4KB，向下扩展(c=1100 96=10010110)

  # 初始化描述符表寄存器GDTR，描述符表的界限（总字节数减一）
  movw $39, pgdt
  lgdt pgdt

  # 南桥芯片内端口，打开A20
  inb $0x92, %al
  orb $0b00000010, %al
  outb %al, $0x92

  # 保护模式下中断机制尚未建立，禁止中断
  cli

  # 设置PE位，开启保护模式
  movl %cr0, %eax
  orl $1, %eax
  movl %eax, %cr0

  # 刷新流水线进入保护模式 3代码段选择子0x0018=0000000000011000B
  ljmp $0x0018, $(flush-_start)

.code32

flush:
  # 加载1数据段选择子 0x0008=0000000000001000
  movw $0x0008, %ax
  movw %ax, %ds

  # 加载2数据段选择子 0x0010=0000000000010000
  movw $0x0010, %ax
  movw %ax, %es

  # 显示保护模式信息
  movw $msg, %si
  xorw %di, %di
  # 32位模式下的loop使用ecx
  movl $(msg_end-msg), %ecx
1:
  movb %ds:(%si), %al
  movb %al, %es:(%di)
  movb $0x0c, %es:0x01(%di)
  incw %si
  addw $2, %di
  loop 1b

  # 加载4栈段选择子0x0020=0000000000100000
  movw $0x0020, %ax
  movw %ax, %ss
  xorl %esp, %esp

  # 开始冒泡排序，遍历次数=串长度-1
  movw $data, %si
  movl $(data_end-data-1), %ecx
2:
  pushl %ecx
  xorw %bx, %bx
3:
  movw %ds:(%bx, %si), %ax
  cmpb %ah, %al
  jge 4f
  xchgb %al, %ah
  mov %ax, %ds:(%bx, %si)
4:
  incw %bx
  loop 3b
  popl %ecx
  loop 2b

  # 显示结果
  movw $(80*2), %di
  movl $(data_end-data), %ecx
5:
  movb %ds:(%si), %al
  movb %al, %es:(%di)
  movb $0x0c, %es:0x01(%di)
  incw %si
  addw $2, %di
  loop 5b

  hlt

msg:
  .ascii "Protect mode OK."
msg_end:
data:
  .ascii "s0ke4or92xap3fv8giuzjcy5l1m7hd6bnqtw."
data_end:

# GDT 大小 - 物理地址
pgdt:
  .word 0
  .long 0x00007e00

.fill   510 - (. - _start), 1, 0
.word   0xAA55

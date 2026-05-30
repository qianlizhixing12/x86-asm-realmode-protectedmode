.include "config.S"

.att_syntax prefix
.code16

.section .text,"ax",@progbits
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

  # 创建空描述符0，处理器要求
  movl $0x00000000, %es:(%bx)
  movl $0x00000000, %es:0x04(%bx)

  # 创建数据段描述符1，对应0~4GB的线性地址空间
  movl $0x0000ffff, %es:0x08(%bx)     # 基地址为0，段界限为0xfffff，4GB
  movl $0x00cf9200, %es:0x0c(%bx)     # 粒度为4KB，向上扩展(c=1100 92=10010010)

  # 创建代码段描述符2
  movl $0x7c0001ff, %es:0x10(%bx)     # 基地址为0x00007c00，段界限为0x001ff，512字节
  movl $0x00409800, %es:0x14(%bx)     # 粒度为1B，代码段描述符（4=0100 98=10011000）

  # 创建栈段描述符3
  # 基址 = 0x00007C00
  # 偏移下限 = 0xFFFFF000 → 线性地址 = 0x7C00 + 0xFFFFF000 = 0x00006C00（32 位截断）
  # 偏移上限 = 0xFFFFFFFF → 线性地址 = 0x7C00 + 0xFFFFFFFF = 0x00007BFF
  movl $0x7c00fffe, %es:0x18(%bx)     # 基地址为0x00007c00，段界限为0xffffe
  movl $0x00cf9600, %es:0x1c(%bx)     # 粒度为4KB，向下扩展(c=1100 96=10010110)

  # 创建数据段描述符4（文本模式下的显示缓冲区）
  movl $0x8000ffff, %es:0x20(%bx)     # 基地址为0x000b8000，段界限为0xfffff
  movl $0x0040920b, %es:0x24(%bx)     # 粒度为1B，向上扩展(4=0100 92=10010010)

  # 初始化描述符表寄存器GDTR，描述符表的界限（总字节数减一）
  movw $39, pgdt
  lgdt pgdt

  # 南桥芯片内端口，打开A20
  inb $0x92, %al
  orb $0b00000010, %al
  outb %al, $0x92

  # 设置PE位，开启保护模式
  movl %cr0, %eax
  orl $1, %eax
  movl %eax, %cr0

  # 刷新流水线进入保护模式 3代码段选择子0x0018=0000000000011000B
  ljmp $mbr_code_seg_sel, $(flush-_start)

.code32

flush:
  # 加载4G数据段选择子
  movw $mem_4gb_data_seg_sel, %ax
  movw %ax, %ds

  # 加载栈段选择子
  movw $mem_stack_seg_sel, %ax
  movw %ax, %ss
  // xorl %esp, %esp
  movl $0xffffffff, %esp


  # 加载系统核心程序
  movl $core_start_sector, %esi
  movl $core_base_address, %edi
  # 以下读取程序的起始部分（一个扇区）
  call read_hard_disk_0

  # 判断整个程序有多大
  movl core_base_address, %eax
  addw $511, %ax
  xorl %edx, %edx
  movl $512, %ecx
  divl %ecx
  decl %eax
  jz setup

  # 读取剩余扇区数
  movl %eax, %ecx
1:
  incl %esi
  call read_hard_disk_0
  loop 1b

setup:
  # 不可以在代码段内寻址pgdt，但可以通过4GB的段来访问
  movl pgdt + 0x02, %edi

  # 创建5#描述符，保护模式下的公用例程代码段描述符
  movl core_base_address+0x04, %eax                  # 公用例程代码段起始汇编地址
  movl core_base_address+0x08, %ebx                  # 核心数据段汇编地址
  subl %eax, %ebx
  decl %ebx                                          # 公用例程段界限
  addl $core_base_address, %eax                      # 公用例程段基地址
  movl $0x00409800, %ecx                             # 字节粒度的代码段描述符
  call make_gdt_descriptor
  movl %eax, %ds:0x28(%edi)
  movl %edx, %ds:0x2c(%edi)

  # 创建6#描述符，保护模式下的核心数据段描述符
  movl core_base_address+0x08, %eax                  # 核心数据段起始汇编地址
  movl core_base_address+0x0c, %ebx                  # 核心代码段汇编地址
  subl %eax, %ebx
  decl %ebx                                          # 核心数据段界限
  addl $core_base_address, %eax                      # 核心数据段基地址
  movl $0x00409200, %ecx                             # 字节粒度的数据段描述符
  call make_gdt_descriptor
  movl %eax, %ds:0x30(%edi)
  movl %edx, %ds:0x34(%edi)

  # 创建7#描述符，保护模式下的核心代码段描述符
  movl core_base_address+0x0c, %eax                  # 核心代码段起始汇编地址
  movl core_base_address, %ebx                       # 程序总长度
  subl %eax, %ebx
  decl %ebx                                          # 核心代码段界限
  addl $core_base_address, %eax                      # 核心代码段基地址
  movl $0x00409800, %ecx                             # 字节粒度的代码段描述符
  call make_gdt_descriptor
  movl %eax, %ds:0x38(%edi)
  movl %edx, %ds:0x3c(%edi)

  movw $63, pgdt                                     # 描述符表的界限（总字节数减一）
  lgdt pgdt                                          # 初始化描述符表寄存器GDTR
  ljmp *%ds:$core_base_address+0x10

# 从硬盘读取一个逻辑扇区
# 输入：ESI=逻辑扇区号
# 输入：DS:EDI=目标缓冲区地址
# 输出：EDI=EDI+512
read_hard_disk_0:
  pushl %eax
  pushl %ecx
  pushl %edx

  # 读取的扇区数
  movw $0x1f2, %dx
  movb $1, %al
  outb %al, %dx

  # LBA地址7~0
  movw $0x1f3, %dx
  movl %esi, %eax
  outb %al, %dx

  # LBA地址15~8
  movw $0x1f4, %dx
  shrl $8, %eax
  outb %al, %dx

  # LBA地址23~16
  movw $0x1f5, %dx
  shrl $8, %eax
  outb %al, %dx

  # LBA地址27~24，LBA28模式，主盘
  movw $0x1f6, %dx
  shrl $8, %eax
  andb $0x0f, %al
  orb $0xe0, %al
  outb %al, %dx

  # 读命令(0x20)
  movw $0x1f7, %dx
  movb $0x20, %al
  outb %al, %dx

  # 等待，不忙且硬盘已准备好数据传输
1:
  inb %dx, %al
  andb $0x88, %al
  cmpb $0x08, %al
  jnz 1b

  # 读取数据
  movw $0x1f0, %dx
  movw $256, %cx
  # 高效读取：从DX端口->ES:DI，自动增加DI
  cld
  rep insw

  popl %edx
  popl %ecx
  popl %eax
  ret

# 构造描述符
# 输入：EAX=线性基地址
# 输入：EBX=段界限
# 输入：ECX=属性（各属性位都在原始位置，其它没用到的位置0）
# 输出：EDX:EAX=完整的描述符
make_gdt_descriptor:
  movl %eax, %edx
  shll $16, %eax
  orw %bx, %ax                                       # 描述符前32位(EAX)构造完毕

  andl $0xffff0000, %edx                             # 清除基地址中无关的位
  roll $8, %edx
  bswap %edx                                         # 装配基址的31~24和23~16(80486+)

  xorw %bx, %bx
  orl %ebx, %edx                                     # 装配段界限的高4位
  orl %ecx, %edx                                     # 装配属性

  ret

# GDT 大小 - 物理地址
pgdt:
  .word 0
  .long 0x00007e00

.fill   510 - (. - _start), 1, 0
.word   0xAA55

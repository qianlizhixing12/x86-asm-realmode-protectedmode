.att_syntax prefix
.code16

# 用户程序在硬盘起始逻辑扇区号
.equ app_phy_lba_start, 100
# 用户程序被加载到内存起始地址
.equ app_mem_base, 0x10000

.section .text,"ax",@progbits
.global _start
.type _start, @function
_start:
  xorw %ax, %ax
  movw %ax, %ds
  movw %ax, %ss
  movw $0x7c00, %sp

  # 计算用户程序被加载到内存的逻辑地址(ES:DI)
  movw $(app_mem_base & 0xffff), %ax
  movw $(app_mem_base >> 16), %dx
  movw $16, %bx
  divw %bx
  movw %ax, %es
  movw %dx, %di

  xorw %bx, %bx
  movw $app_phy_lba_start, %si
  # 读取程序的起始部分
  call read_hard_disk_once
  # 加载整个程序
  call read_hard_disk_app

  # 重定位程序
  call calc_app_start
  call calc_app_table

  # 转移到用户程序运行
  movw %es, %ax
  movw %ax, %ds
  ljmp *%es:0x04(%di)

1:
  jmp 1b

// .size _start, .-_start

# 从硬盘读取一个逻辑扇区(程序头部)
# 输入：SI=起始逻辑扇区号低16位
# 输入：BX=起始逻辑扇区号高16位(有效12位)
# 输入：ES:DI=目标缓冲区地址
read_hard_disk_once:
  pushw %ax
  pushw %cx
  pushw %dx
  pushw %di

  # 读取的扇区数
  movw $0x1f2, %dx
  movb $1, %al
  outb %al, %dx

  # LBA地址7~0
  movw $0x1f3, %dx
  movw %si, %ax
  outb %al, %dx

  # LBA地址15~8
  movw $0x1f4, %dx
  movb %ah, %al
  outb %al, %dx

  # LBA地址23~16
  movw $0x1f5, %dx
  movw %bx, %ax
  outb %al, %dx

  # LBA地址27~24，LBA28模式，主盘
  movw $0x1f6, %dx
  movb %ah, %al
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

  popw %di
  popw %dx
  popw %cx
  popw %ax
  ret

# 从硬盘读取程序剩余的扇区(除去程序头部)
# 输入：SI=起始逻辑扇区号低16位
# 输入：BX=起始逻辑扇区号高16位(有效12位)
# 输入：ES:DI=程序头部地址
read_hard_disk_app:
  pushw %ax
  pushw %bx
  pushw %cx
  pushw %dx
  pushw %di
  pushw %si
  pushw %es

  # 从头部读取程序总长度(偏移0)
  movw %es:(%di), %ax
  movw %es:0x02(%di), %dx
  # 计算需要的总扇区数(长度/512)
  addw $511, %ax
  adcw $0, %dx
  movw $512, %bx
  divw %bx
  decw %ax
  jz 2f

  # 读取剩余扇区数
  movw %ax, %cx
1:
  movw %es, %ax
  addw $0x20, %ax    # 得到下一个以512字节为边界的段地址 512/16=32(0x20)
  movw %ax, %es
  incw %si
  xorw %bx, %bx
  call read_hard_disk_once
  loop 1b

2:
  popw %es
  popw %si
  popw %di
  popw %dx
  popw %cx
  popw %bx
  popw %ax
  ret

# 计算16位段地址
# 输入：DX:AX=32位物理地址（DX高16位，实模式下DX高16位为0，AX低16位）
# 输出：AX=16位段基地址
calc_segment_base:
  pushw %dx

  addw $(app_mem_base & 0xffff), %ax
  adcw $(app_mem_base >> 16), %dx
  shrw $4, %ax
  shlw $12, %dx
  orw %dx, %ax

  popw %dx
  ret

// 修正用户程序入口代码段地址(偏移0x06处)
calc_app_start:
  movw %es:0x06(%di), %ax
  movw %es:0x08(%di), %dx
  call calc_segment_base
  # 回填修正后的入口点代码段基址
  movw %ax, %es:0x06(%di)
  movw $0, %es:0x08(%di)

  ret

# 修正用户程序所有段的地址(段重定位表)
calc_app_table:
  movw %es:0x0a(%di), %cx
  movw $0x0c, %bx
1:
  movw %es:(%bx, %di), %ax
  movw %es:0x02(%bx, %di), %dx
  call calc_segment_base
  # 回填段的基址
  movw %ax, %es:0(%bx, %di)
  movw $0, %es:0x02(%bx, %di)
  # 下一个重定位项（每项占4个字节）
  addw $4, %bx
  loop 1b

  ret


.fill   510 - (. - _start), 1, 0
.word   0xAA55

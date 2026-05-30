.code16

.section .text
.global _start

_start:
  xorw %ax, %ax
  movw %ax, %ds
  movw %ax, %es

// 方式一：调用int 10h中断控制显示
1:
  movw $BootMessage, %ax
  movw %ax, %bp
  movw $16, %cx
  movW $0, %dX
  movw $0x000c, %bx
  movw $0x1301, %ax
  int $0x10

// 方式二：采用mov指令向0xb800传送数据控制显示(黑底白字)
  movw $0xb800, %ax
  movw %ax, %es
  movw $BootMessage, %si
  movw $0xa0, %bx
  movw $16, %cx
2:
  movb (%si), %al
  movb %al, %es:(%bx)
  incw %bx
  movb $0x07, %es:(%bx)
  incw %bx
  incw %si
  loop 2b

  jmp .

BootMessage:
  .ascii "Hello, OS world!"

.fill   510 - (. - _start), 1, 0
.word   0xAA55

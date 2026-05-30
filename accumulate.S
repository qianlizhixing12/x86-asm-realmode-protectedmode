.code16

.section .text
.global _start
_start:
  jmp start

msg:
  .ascii "1+2+3+...+100="

start:
  xorw %ax, %ax
  movw %ax, %ds
  movw %ax, %ss
  movw $0x7c00, %sp

  // 打印msg
  movw $0xb800, %ax
  movw %ax, %es
  xorw %di, %di
  movw $(start - msg), %cx
  movw $msg, %bx
  xorw %si, %si
1:
  movb (%bx, %si), %al
  movb $0x0c, %ah
  movw %ax, %es:(%di)
  incw %si
  addw $2, %di
  loop 1b

  // 计算累加
  xorw %ax, %ax
  movw $1, %cx
2:
  addw %cx, %ax
  incw %cx
  cmpw $100, %cx
  jle 2b

  // 计算各个数位
  xorw %cx, %cx
  movw $10, %bx
3:
  xorw %dx, %dx
  divw %bx
  addb $'0', %dl
  pushw %dx
  incw %cx
  cmpw $0, %ax
  jne 3b

  // 显示各个数位
4:
  popw %ax
  movb $0x0c, %ah
  movw %ax, %es:(%di)
  addw $2, %di
  loop 4b

  jmp .

.fill   510 - (. - _start), 1, 0
.word   0xAA55

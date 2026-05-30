.code16

.section .text
.global _start
_start:
  jmp start

buff:
  .byte 0, 0, 0, 0, 0

start:
  // 设置数据段/栈段地址
  xorw %ax, %ax
  movw %ax, %ds
  movw %ax, %ss

  // 设置结果缓存区地址
  movw $buff, %bx      # 设置基地址
  movw $0, %si         # 设置索引

  // 计算标号地址10进制结果
  movw $(start - _start), %ax     # 设置被除数（取得标号start的偏移地址）
  movw $10, %di        # 设置除数
  movw $5, %cx
1:
  // 依此求各位数字(个 十 百 千 万)
  xorw %dx, %dx
  divw %di
  // 依此保存各位数字(个 十 百 千 万)
  movb %dl, (%bx, %si)
  incw %si
  loop 1b

  movw $0xb800, %ax
  movw %ax, %es
  xorw %di, %di
  movw $buff, %bx
  movw $4, %si
  movw $5, %cx
2:
  // 依此打印各位数字(万 千 百 十 个)
  movb (%bx, %si), %al
  addb $'0', %al    # 转为 ASCII
  movb $0x0c, %ah   # 黑底红字
  movw %ax, %es:(%di)
  decw %si
  addw $2, %di
  loop 2b

  jmp .

.fill   510 - (. - _start), 1, 0
.word   0xAA55

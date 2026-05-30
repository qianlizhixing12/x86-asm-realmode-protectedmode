# x86-asm-realmode-protectedmode

《x86汇编语言：从实模式到保护模式》源码
从nasm汇编语法翻译为gas汇编语法

# x86汇编语言：从实模式到保护模式第2版(mbr目录)

1. helloword.S
2. label_address_runtime.S            31751(0x7c07)
3. label_address_offset.S             00007(0x0007); 0x7c07 - 0x0007 = 0x7c00
4. accumulate.S                       05050D
5. app_bootload.S app.S               加载多段程序
6. app_bootload.S app_interrupt_cmos.S   加载中断程序
7. gdt_sort.S                            加载gdt，冒泡排序
8.  os_bootload.S os_core.S os_app.asm diskdata.txt 加载运行app（0, 1, 50, 100扇区）
9.  os_bootload.S os_core_ldt.asm os_app_ldt.asm diskdata.txt 加载运行app（0, 1, 50, 100扇区）
10. os_bootload.S os_core_task.asm os_app_task.asm 加载app切换task（0, 1, 50扇区）
11. os_bootload.S os_core_interrupt.asm os_app_task0.asm os_app_task1.asm 加载app切换task（0, 1, 50, 100扇区）
12. os_bootload.S os_core_page.asm os_app_task0.asm os_app_task1.asm 加载app切换task（0, 1, 50, 100扇区）
13. mos_load.asm mos_core.asm mos_app0.asm mos_app1.asm 平坦内存模型任务切换

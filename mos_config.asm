;段选择子
flat_core_code_seg_sel equ 0x0008       ;平坦模型下的内核（0特权级）4GB代码段选择子，0x0008=0000000000001_000B
flat_core_data_seg_sel equ 0x0010       ;平坦模型下的内核（0特权级）4GB数据段选择子，0x0010=0000000000010_000B
flat_user_code_seg_sel equ 0x001b       ;平坦模型下的用户（3特权级）4GB代码段选择子，0x0018=0000000000011_000B
flat_user_data_seg_sel equ 0x0023       ;平坦模型下的用户（3特权级）4GB数据段选择子，0x0020=0000000000100_000B
;内核物理地址，内核的大部分内容都应当固定
mbr_base_address       equ 0x00007c00   ;mbr的起始内存地址
gdt_base_address       equ 0x00007e00   ;gdt的起始内存地址
idt_base_address       equ 0x0001f000   ;idt起始的起始内存地址
pdt_base_address       equ 0x00020000   ;内核页目录表的起始内存地址
pt_base_address        equ 0x00021000   ;内核页表的起始内存地址
core_base_address      equ 0x00040000   ;内核加载的起始内存地址
;内核线性地址
core_line_base         equ 0x80000000   ;内核线性地址高地址基址
mbr_line_address       equ 0x80007c00   ;mbr的起始线性地址
gdt_line_address       equ 0x80007e00   ;gdt的起始线性地址
idt_line_address       equ 0x8001f000   ;中断描述符表的线性地址
core_line_address      equ 0x80040000   ;内核加载的线性地址
video_line_address     equ 0x800b8000   ;显存的线性地址
core_line_alloc_at     equ 0x80100000   ;内核中可用于分配的起始线性地址
;程序存储磁盘扇区
core_start_sector      equ 1            ;内核的起始逻辑扇区号1
app0_start_sector      equ 50           ;用户程序0的起始逻辑扇区号50
app1_start_sector      equ 100          ;用户程序1的起始逻辑扇区号100
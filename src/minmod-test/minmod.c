#include <linux/module.h>
static int __init i(void){return 0;}
static void __exit x(void){}
module_init(i); module_exit(x); MODULE_LICENSE("GPL");

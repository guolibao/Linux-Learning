#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/module.h>

#include <linux/slab.h>
#include <linux/kfifo.h>

MODULE_DESCRIPTION("Kfifo test");
MODULE_AUTHOR("Victor Andrei Oprea");
MODULE_LICENSE("GPL");

struct mything {
	unsigned char msg[10];
};

#define FIFO_SIZE 16
static DECLARE_KFIFO(buffer, struct mything *, FIFO_SIZE);

static void put(struct mything *foo)
{
	kfifo_put(&buffer, foo);
}

static int get(struct mything **foo)
{
	return kfifo_get(&buffer, foo);
}

static int list_init(void)
{
	int i = 0;
	struct mything *foo;

	printk(KERN_INFO "Loading module");
	INIT_KFIFO(buffer);

	for (i = 0; i < 10; ++i) {
		foo = kmalloc(sizeof(struct mything), GFP_KERNEL);
		printk(KERN_INFO "Put [%p]\n", foo);
		strcpy(foo->msg, "Hello\0");
		put(foo);
	}

	printk(KERN_INFO "Kfifo has %d elements", kfifo_size(&buffer));

	i = 1;
	while(i) {
		i = get(&foo);
		printk(KERN_INFO "[%d] %s loaded %p\n", i, foo->msg, foo);
	}

	return 0;
}

static void list_exit(void)
{
}

module_init(list_init);
module_exit(list_exit);
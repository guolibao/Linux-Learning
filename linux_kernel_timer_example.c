#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/timer.h>
#include <linux/jiffies.h>

static void mykmod_timer_handler(unsigned long data);
static unsigned long onesec;

DEFINE_TIMER(mytimer, mykmod_timer_handler, 0, 0);

static void
mykmod_timer_handler(unsigned long data)
{
        unsigned long j = jiffies;
        pr_info("mykmod timer %u jiffies\n", (unsigned)j);

        mod_timer(&mytimer, jiffies + onesec);
}


static int __devinit mykmod_init(void)
{
        unsigned long j = jiffies;

        onesec = msecs_to_jiffies(1000 * 1);

        pr_info("mykmod loaded %u/%u jiffies before\n", (unsigned)j, (unsigned)onesec);

        mod_timer(&mytimer, jiffies + onesec);

        pr_info("mykmod loaded %u jiffies after \n", (unsigned)j);

        return 0;
}

static void __devexit mykmod_exit(void)
{
        del_timer(&mytimer);
        pr_info("mykmod exit\n");
}

module_init(mykmod_init);
module_exit(mykmod_exit);

MODULE_DESCRIPTION("mykmod");
MODULE_LICENSE("GPL");

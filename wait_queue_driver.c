/* driver-08

   Demonstration of a wait queue.  An event is placed in the queue and 
   nothing happens until some condition it tests turns out to be true.
   This is a simple example - readers wait until a writer changes flag
   allowing them to wake up, one at a time.
*/
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/fs.h>
#include <asm/uaccess.h>
#include <linux/semaphore.h>
#include <linux/cdev.h>
#include <linux/wait.h>
#include <linux/sched.h>
static int Major;

struct cdev *kernel_cdev; 
static int flag = 0;
static DECLARE_WAIT_QUEUE_HEAD(wq);
static char buff[100];

int open(struct inode *inode, struct file *filp) {
   printk(KERN_INFO "open:\n"); 
   return 0;
}

int release(struct inode *inode, struct file *filp) {
    printk(KERN_INFO "release:\n");
    return 0;
}

/* 
   When a process sleeps, it does so in expectation that some
   condition will become true in the future. Any process that sleeps
   must check to be sure that the condition it was waiting for is
   really true when it wakes up again.  

   The simplest way to sleep in the Linux kernel is via a macro called
   'wait_event' (with a few variants); it combines handling the details
   of sleeping with a check on the condition a process is waiting
   for. The forms of wait_event are: 

      wait_event(queue, condition)
      wait_event_interruptible(queue, condition)
      wait_event_timeout(queue, condition, timeout)
      wait_event_interruptible_timeout(queue, condition, timeout) 

   In all of the above forms, queue is the wait queue head to
   use.  Notice that it is passed "by value." The condition is an
   arbitrary boolean expression that is evaluated by the macro before
   and after sleeping;  until condition evaluates to a true value, the
   process continues to sleep. 

   Note that condition may be evaluated an arbitrary number of times,
   so it should not have any side effects.  

   If you use wait_event, your process is put into an uninterruptible
   sleep which is usually not what you want. The preferred alternative
   is wait_event_interruptible, which can be interrupted by
   signals.  This version returns an integer value that you should
   check; a nonzero value means your sleep was interrupted by some
   sort of signal, and your driver should probably return
   -ERESTARTSYS.  

   The final versions (wait_event_interruptible_timeout and
   wait_event_timeout) wait for a limited time; after that time period
   (expressed in jiffies) expires, the macros return with a value of 0
   regardless of how the condition evaluates.

   The other half of the picture, of course, is waking up. Some other
   thread of execution (a different process, or an interrupt handler,
   perhaps) has to perform the wakeup for you, since your process is
   asleep. The basic function that wakes up sleeping processes is
   called 'wake_up'. It comes in several forms including:
   
      void wake_up(wait_queue_head_t *queue); 
      void wake_up_interruptible(wait_queue_head_t *queue); 

   'wake_up' more or less wakes up all processes waiting on the given
   queue.  The other form 'wake_up_interruptible' restricts itself to
   processes performing an interruptible sleep.  In general, the two
   are indistinguishable; in practice, the convention is to use
   'wake_up' if you are using 'wait_event' and 'wake_up_interruptible'
   if you use 'wait_event_interruptible'.
*/
ssize_t read (struct file *filp, char *b, size_t c, loff_t *o) { 
   ssize_t ret;
   printk(KERN_EMERG "reader going to sleep\n");
   wait_event_interruptible(wq, flag != 0); 
   flag = 0;   /* what happens if this is set to 0? */
   ret = copy_to_user(b, buff, c);
   printk(KERN_EMERG "reader awakened and leaving [%d:%s]\n",ret,buff); 
   return ret; 
}

ssize_t write(struct file *filp, const char *b, size_t c, loff_t *o) { 
   ssize_t ret;
   flag = 1;
   ret = copy_from_user(buff,b,strlen(b));
   printk(KERN_EMERG "writer awakening the readers [%d]\n",ret);
   wake_up_interruptible(&wq);
   return ret; /* succeed, to avoid retrial - one write needed */
}

struct file_operations fops = { 
   .owner = THIS_MODULE,
   .read = read, 
   .write = write, 
   .open = open, 
   .release = release
};

int tester1_init (void) {
   int ret;
   dev_t dev_no, dev;

   kernel_cdev = cdev_alloc();    
   kernel_cdev->ops = &fops; 
   kernel_cdev->owner = THIS_MODULE;
   printk(KERN_INFO "init: starting driver\n");

   ret = alloc_chrdev_region(&dev_no, 0, 1,"tester1");
   if (ret < 0) {
      printk("Major number allocation is failed\n");
      return ret;    
   }
   Major = MAJOR(dev_no);
   dev = MKDEV(Major,0);

   printk(KERN_INFO "init: Major %d\n", Major);

   ret = cdev_add(kernel_cdev, dev, 1);
   if(ret < 0 ) {
      printk(KERN_INFO "Unable to allocate cdev");
      return ret;
   }

   return 0;
}

void tester1_cleanup(void) {
   printk(KERN_INFO "cleanup: unloading driver\n");
   unregister_chrdev_region(Major, 1);
   cdev_del(kernel_cdev);
}

module_init(tester1_init);
module_exit(tester1_cleanup);

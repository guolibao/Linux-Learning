#include <sys/types.h>
#include <sys/stat.h>
#include <sys/ioctl.h>
#include <fcntl.h>
#include <string.h>
#include <linux/ioctl.h>
#include <stdlib.h>
#include <stdio.h>

#define MSCDEV_IOCTL_MAGIC	0x33

#define IOCTL_MSCDEV_MAIN_SEND		_IOC( _IOC_WRITE, MSCDEV_IOCTL_MAGIC, 0, 0 )
#define IOCTL_MSCDEV_MAIN_RECV		_IOC( _IOC_READ,  MSCDEV_IOCTL_MAGIC, 1, 0 )
#define IOCTL_MSCDEV_PANEL_SEND		_IOC( _IOC_WRITE, MSCDEV_IOCTL_MAGIC, 2, 0 )
#define IOCTL_MSCDEV_PANEL_RECV		_IOC( _IOC_READ,  MSCDEV_IOCTL_MAGIC, 3, 0 )
#define IOCTL_MSCDEV_TEST			_IOC( _IOC_WRITE, MSCDEV_IOCTL_MAGIC, 4, 0 )
#define IOCTL_MSCDEV_TEST2			_IOC( _IOC_NONE,  MSCDEV_IOCTL_MAGIC, 5, 0 )

static const char*	C_DEVICE_NAME		= "/dev/mscdev";


int main(int argc, char *argv[])
{
	int fd = -1;
	fd = open(C_DEVICE_NAME, O_RDWR);
	if(-1 != fd)
	{
		unsigned char buf[] = {
			0x00, 	// Function, 0x00
			0x02,	// Message Length
			0x00,	// Packet type
			0x00,	// Packet sequence number
			0x00, 	// Telegram, 0x00
			0x21, 	// Type, 0x21
			0x01,	// data[0]
			0x02	// data[1]
		};
		ioctl(fd, IOCTL_MSCDEV_MAIN_SEND, buf);
		close(fd);
	}
	else
	{
		printf("error\n");
	}

	
	return 0;
}

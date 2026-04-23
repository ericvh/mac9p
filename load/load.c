#include <sys/mount.h>
#include <sys/wait.h>
#include <unistd.h>
#include <err.h>

static char *kext = "/Library/Extensions/9p.kext";
static char *kextload = "/sbin/kextload";
static char *kmutil = "/usr/bin/kmutil";

int
main(int argc, char *argv[])
{
#pragma unused(argc)
#pragma unused(argv)
	struct vfsconf vfc;
	union wait status;
	pid_t pid;
	int i;

	if (getvfsbyname("9p", &vfc) == 0)
		return 0;

	switch((pid = fork())){
	case -1:
		err(1, "fork");
		return -1;
	case 0:
		/* shut up */
		for(i=1; i<3; i++)
			close(i);
		if (access(kmutil, X_OK) == 0) {
			execl(kmutil, "kmutil", "load", "-p", kext, NULL);
			warn("execl %s", kmutil);
		} else {
			execl(kextload, kextload, kext, NULL);
			warn("execl %s", kextload);
		}
		_exit(1);
	}

	if(waitpid(pid, (int*)&status, 0) != pid)
		err(1, "waitpid");

	if(!WIFEXITED(status))
		err(1, "load tool signal %d", WTERMSIG(status));

	if(WEXITSTATUS(status))
		err(1, "load %s failed", kext);

	return 0;
}

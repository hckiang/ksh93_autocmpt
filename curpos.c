#include <stdio.h>
#include <termios.h>
#include <sys/ioctl.h>
#include <sys/select.h>
#include <unistd.h>
#define MAXLOOP 30
#define MAXGAG  16
int main(void) {
	tcflag_t oldclflag;
	struct termios tm;
	struct timeval t;
	fd_set f;
	int x, y;
	int c, i, nloop, j;
	char gaggedch[MAXGAG];
	tcgetattr(STDIN_FILENO, &tm);
	oldclflag = tm.c_lflag;
	tm.c_lflag &= ~ICANON & ~ECHO;
	tcsetattr(STDIN_FILENO, TCSADRAIN, &tm);
	tm.c_lflag = oldclflag;
	printf("\033[6n");
	fflush(stdout);
	tcdrain(STDIN_FILENO);
	FD_ZERO(&f);
	FD_SET(STDIN_FILENO, &f);
	t.tv_sec = 0;
/* Can't be too small because things can be rather slow especially in
   for example konsole or gnome-terminal, both of which are very slow. */
	t.tv_usec = 200000;
	i = 0;
	nloop = 0;
RETRY:
	if (select(STDIN_FILENO + 1, &f, NULL, NULL, &t) == 1)
		if (scanf("\033[%d;%dR", &x, &y) == 2)
			goto GOOD;
		else {  /* Stuff things into gaggedch buffer and retry */
			c = getc(stdin);
			if (i < MAXGAG)         gaggedch[i++] = (char)c;
			if (nloop++ < MAXLOOP)  goto RETRY;
			else                    goto BAD;
		}
	else if (nloop++ < MAXLOOP) goto RETRY; else goto BAD;
BAD:  /* Probably terminal not responding to query */
	tcsetattr(STDIN_FILENO, TCSANOW, &tm);
	for (j = 0; j < i; ++j)
		ioctl(STDIN_FILENO, TIOCSTI, gaggedch + j);
	return 1;
GOOD:
	tcsetattr(STDIN_FILENO, TCSANOW, &tm);
	for (j = 0; j < i; ++j)
		ioctl(STDIN_FILENO, TIOCSTI, gaggedch + j);
	fprintf(stderr, "%d\t%d\n",x,y);
	return 0;
}


// Wrapper that enables raw mode then executes the escript
#include <stdio.h>
#include <stdlib.h>
#include <termios.h>
#include <unistd.h>
#include <sys/wait.h>

static struct termios orig_termios;

void disable_raw_mode() {
    tcsetattr(STDIN_FILENO, TCSAFLUSH, &orig_termios);
}

void enable_raw_mode() {
    if (tcgetattr(STDIN_FILENO, &orig_termios) == -1) {
        // Not a TTY, skip raw mode
        fprintf(stderr, "[wrapper] tcgetattr failed - not a TTY\n");
        return;
    }

    fprintf(stderr, "[wrapper] Successfully got terminal attrs, enabling raw mode\n");
    atexit(disable_raw_mode);

    struct termios raw = orig_termios;
    raw.c_lflag &= ~(ECHO | ICANON | ISIG | IEXTEN);
    raw.c_iflag &= ~(BRKINT | ICRNL | INPCK | ISTRIP | IXON);
    raw.c_oflag &= ~(OPOST);
    raw.c_cflag |= (CS8);
    raw.c_cc[VMIN] = 1;
    raw.c_cc[VTIME] = 0;

    if (tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw) == -1) {
        fprintf(stderr, "[wrapper] tcsetattr failed\n");
    } else {
        fprintf(stderr, "[wrapper] Raw mode enabled successfully\n");
    }
}

int main(int argc, char *argv[]) {
    // Enable raw mode on the current terminal
    enable_raw_mode();

    // Execute the real escript (passed as first argument)
    if (argc < 2) {
        fprintf(stderr, "Usage: %s <escript_path> [args...]\n", argv[0]);
        return 1;
    }

    // Execute the escript with remaining arguments
    execvp(argv[1], &argv[1]);

    // If execvp returns, it failed
    perror("execvp");
    return 1;
}

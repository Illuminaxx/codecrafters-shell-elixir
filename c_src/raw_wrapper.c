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
    FILE *debug = fopen("/tmp/raw_wrapper_debug.log", "w");
    if (debug) {
        fprintf(debug, "Wrapper started\n");
        fflush(debug);
    }

    if (tcgetattr(STDIN_FILENO, &orig_termios) == -1) {
        // Not a TTY, skip raw mode
        if (debug) {
            fprintf(debug, "tcgetattr failed - not a TTY\n");
            fclose(debug);
        }
        return;
    }

    if (debug) {
        fprintf(debug, "tcgetattr succeeded\n");
        fflush(debug);
    }

    atexit(disable_raw_mode);

    struct termios raw = orig_termios;
    raw.c_lflag &= ~(ECHO | ICANON | ISIG | IEXTEN);
    raw.c_iflag &= ~(BRKINT | ICRNL | INPCK | ISTRIP | IXON);
    // Keep OPOST enabled so \n is converted to \r\n automatically
    // raw.c_oflag &= ~(OPOST);
    raw.c_cflag |= (CS8);
    raw.c_cc[VMIN] = 1;
    raw.c_cc[VTIME] = 0;

    if (tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw) == -1) {
        if (debug) {
            fprintf(debug, "tcsetattr failed\n");
            fclose(debug);
        }
    } else {
        if (debug) {
            fprintf(debug, "tcsetattr succeeded - raw mode enabled\n");
            fclose(debug);
        }
    }
}

int main(int argc, char *argv[]) {
    FILE *debug = fopen("/tmp/raw_wrapper_main.log", "w");
    if (debug) {
        fprintf(debug, "Wrapper main() started with %d args\n", argc);
        for (int i = 0; i < argc; i++) {
            fprintf(debug, "  argv[%d] = %s\n", i, argv[i]);
        }
        fflush(debug);
        fclose(debug);
    }

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

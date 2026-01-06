// Raw stdin reader - reads stdin in raw mode and outputs to stdout
// Communicates with Elixir via simple byte protocol
#include <stdio.h>
#include <stdlib.h>
#include <termios.h>
#include <unistd.h>

static struct termios orig_termios;

void disable_raw_mode() {
    tcsetattr(STDIN_FILENO, TCSAFLUSH, &orig_termios);
}

void enable_raw_mode() {
    tcgetattr(STDIN_FILENO, &orig_termios);
    atexit(disable_raw_mode);

    struct termios raw = orig_termios;
    raw.c_lflag &= ~(ECHO | ICANON | ISIG | IEXTEN);
    raw.c_iflag &= ~(BRKINT | ICRNL | INPCK | ISTRIP | IXON);
    raw.c_oflag &= ~(OPOST);
    raw.c_cflag |= (CS8);
    raw.c_cc[VMIN] = 1;
    raw.c_cc[VTIME] = 0;

    tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw);
}

int main() {
    // Try to enable raw mode (will fail if not a TTY, that's ok)
    if (isatty(STDIN_FILENO)) {
        enable_raw_mode();
    }

    // Read bytes from stdin and write them to stdout unchanged
    // Elixir will read from this Port
    unsigned char c;
    while (read(STDIN_FILENO, &c, 1) == 1) {
        // Just echo the byte to stdout for Elixir to read
        write(STDOUT_FILENO, &c, 1);
        fflush(stdout);
    }

    return 0;
}

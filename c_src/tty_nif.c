#include <erl_nif.h>
#include <termios.h>
#include <unistd.h>
#include <string.h>

static struct termios orig_termios;

static ERL_NIF_TERM enable_raw_mode(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
    struct termios raw;

    // Get current terminal attributes
    if (tcgetattr(STDIN_FILENO, &orig_termios) == -1) {
        return enif_make_tuple2(env,
            enif_make_atom(env, "error"),
            enif_make_string(env, "tcgetattr failed", ERL_NIF_LATIN1));
    }

    // Copy to raw and modify
    raw = orig_termios;

    // Disable echo, canonical mode, signals
    raw.c_lflag &= ~(ECHO | ICANON | ISIG | IEXTEN);

    // Disable input processing
    raw.c_iflag &= ~(BRKINT | ICRNL | INPCK | ISTRIP | IXON);

    // Disable output processing
    raw.c_oflag &= ~(OPOST);

    // Set character size to 8 bits
    raw.c_cflag |= (CS8);

    // Set minimum bytes and timeout for read
    raw.c_cc[VMIN] = 1;
    raw.c_cc[VTIME] = 0;

    // Apply the changes
    if (tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw) == -1) {
        return enif_make_tuple2(env,
            enif_make_atom(env, "error"),
            enif_make_string(env, "tcsetattr failed", ERL_NIF_LATIN1));
    }

    return enif_make_atom(env, "ok");
}

static ERL_NIF_TERM disable_raw_mode(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
    if (tcsetattr(STDIN_FILENO, TCSAFLUSH, &orig_termios) == -1) {
        return enif_make_tuple2(env,
            enif_make_atom(env, "error"),
            enif_make_string(env, "tcsetattr restore failed", ERL_NIF_LATIN1));
    }

    return enif_make_atom(env, "ok");
}

static ErlNifFunc nif_funcs[] = {
    {"enable_raw_mode", 0, enable_raw_mode},
    {"disable_raw_mode", 0, disable_raw_mode}
};

ERL_NIF_INIT(Elixir.TTY, nif_funcs, NULL, NULL, NULL, NULL)

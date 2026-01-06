ERLANG_PATH = $(shell elixir -e 'IO.puts(:code.root_dir())')
CFLAGS = -O3 -std=c99 -fPIC -I$(ERLANG_PATH)/usr/include
LDFLAGS = -shared

ifeq ($(shell uname),Darwin)
	LDFLAGS += -dynamiclib -undefined dynamic_lookup
endif

NIF_SO = ../priv/tty_nif.so

all: $(NIF_SO)

$(NIF_SO): tty_nif.c
	@mkdir -p ../priv
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $<

clean:
	rm -f $(NIF_SO)

.PHONY: all clean

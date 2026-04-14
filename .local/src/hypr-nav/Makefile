PREFIX ?= $(HOME)/.local

hypr-nav: hypr-nav.c
	$(CC) -O2 -Wall -Wextra -o $@ $<

install: hypr-nav
	install -Dm755 hypr-nav $(PREFIX)/bin/hypr-nav

clean:
	rm -f hypr-nav

.PHONY: install clean

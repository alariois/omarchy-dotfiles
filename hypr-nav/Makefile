PREFIX ?= $(HOME)/.local

CFLAGS ?= -O2 -Wall -Wextra

hypr-nav: hypr-nav.c
	$(CC) $(CFLAGS) -o $@ $<

test_hypr_nav: test_hypr_nav.c hypr-nav.c
	$(CC) -Wall -Wextra -g -DTESTING -o $@ test_hypr_nav.c

test: test_hypr_nav
	./test_hypr_nav

test-integration: hypr-nav
	./test_integration.sh

install: hypr-nav
	install -Dm755 hypr-nav $(PREFIX)/bin/hypr-nav

clean:
	rm -f hypr-nav test_hypr_nav

.PHONY: install clean test test-integration

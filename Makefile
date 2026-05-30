PREFIX     ?= $(HOME)/.local
BINDIR      = $(PREFIX)/bin
COMPDIR     = $(HOME)/.local/share/bash-completion/completions

.PHONY: install uninstall link

install:
	install -Dm755 vissh.sh $(BINDIR)/vissh
	install -Dm644 completions/vissh.bash $(COMPDIR)/vissh

uninstall:
	rm -f $(BINDIR)/vissh
	rm -f $(COMPDIR)/vissh

# For development: symlink so edits are live immediately
link:
	mkdir -p $(BINDIR) $(COMPDIR)
	ln -sf $(CURDIR)/vissh.sh $(BINDIR)/vissh
	ln -sf $(CURDIR)/completions/vissh.bash $(COMPDIR)/vissh

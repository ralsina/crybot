CRYSTAL = crystal
FLAGS = -Dpreview_mt -Dexecution_context
TARGET = bin/crybot
SHELL_TARGET = bin/crysh

all: build shell-build

build:
	$(CRYSTAL) build $(FLAGS) src/main.cr -o $(TARGET)

shell-build:
	$(CRYSTAL) build src/crysh.cr -o $(SHELL_TARGET)

run: build
	./$(TARGET)

clean:
	rm -f $(TARGET) $(SHELL_TARGET)

deploy_site:
	cd docs-site && nicolino build && rsync -rav --delete output/* root@rocky:/data/stacks/web/websites/crybot.ralsina.me/

.PHONY: all build shell-build run clean deploy_site

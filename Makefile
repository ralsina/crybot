CRYSTAL = crystal
FLAGS = -Dpreview_mt
TARGET = bin/crybot

all: build

build:
	$(CRYSTAL) build $(FLAGS) src/main.cr -o $(TARGET)

run: build
	./$(TARGET)

clean:
	rm -f $(TARGET)

deploy_site:
	cd docs-site && nicolino build && rsync -rav --delete output/* root@rocky:/data/stacks/web/websites/crybot.ralsina.me/

.PHONY: all build run clean deploy_site

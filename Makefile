CRYSTAL = crystal
FLAGS = -Dpreview_mt --release
TARGET = bin/crybot

all: build

build:
	$(CRYSTAL) build $(FLAGS) src/main.cr -o $(TARGET)

run: build
	./$(TARGET)

clean:
	rm -f $(TARGET)

.PHONY: all build run clean

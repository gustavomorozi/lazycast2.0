# control: teclado/mouse (sempre necessário)
# h264 / player: OpenMAX legado — só em Raspberry Pi 1–4 com userland 32-bit
.PHONY: all control h264 player

all: control

control:
	$(MAKE) -C control

h264:
	$(MAKE) -C h264

player:
	$(MAKE) -C player

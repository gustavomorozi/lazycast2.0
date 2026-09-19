# Raspberry Pi 5: apenas o utilitário de controle (UIBC). Players OpenMAX foram removidos.
.PHONY: all control

all: control

control:
	$(MAKE) -C control

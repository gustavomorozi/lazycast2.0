# Raspberry Pi 1-4 (Legacy 32-bit, OpenMAX)

Valido apenas para Pi 1-4 com Raspberry Pi OS Legacy 32-bit. **Nao use no Raspberry Pi 5.**

Selecione "**Raspberry Pi OS (Legacy, 32-bit)** Uma porta do Debian Bullseye com atualizações de segurança e ambiente desktop" ao gravar o cartão SD. Debian Bookworm parece causar alguns problemas.

Em um sistema operacional novo, instale ``cmake``:
```
sudo apt install cmake
```
Clone o repositório userland do Raspberry Pi e execute ``buildme``:
```
git clone https://github.com/raspberrypi/userland
cd userland
./buildme
```
Substitua ``vc4-kms-v3d`` por ``vc4-fkms-v3d`` em ``/boot/config.txt``:
```
sudo sed -i 's/vc4-kms-v3d/vc4-fkms-v3d/g' /boot/config.txt
```
Então reinicie:
```
sudo reboot
```
(Você pode ver [este post](https://github.com/homeworkc/lazycast/issues/100#issuecomment-1003732280) para mais detalhes.)

## Compilar binários
Instale pacotes (para compilar os players):
```
sudo apt install libx11-dev libasound2-dev libavformat-dev libavcodec-dev python3-evdev
```
Compile bibliotecas no Pi:
```
cd /opt/vc/src/hello_pi/libs/ilclient/
sudo make
cd /opt/vc/src/hello_pi/hello_video
sudo make
```
Clone este repositório (para um diretório desejado):
```
cd ~/
git clone https://github.com/homeworkc/lazycast
```
Vá para o diretório ``lazycast`` e então execute ``make``:
```
cd lazycast
make
```



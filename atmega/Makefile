GCCFLAGS=-g -Os -Wall -mmcu=atmega168 
LINKFLAGS=-Wl,-u,vfprintf -lprintf_flt -Wl,-u,vfscanf -lscanf_flt -lm
AVRDUDEFLAGS=-c avr109 -p m168 -b 115200 -P /dev/ttyUSB0
LINKOBJECTS=libnerdkits/delay.o libnerdkits/lcd.o libnerdkits/uart.o

all:	lcddisplay-upload

lcddisplay.hex:	lcddisplay.c
	make -C libnerdkits
	avr-gcc ${GCCFLAGS} ${LINKFLAGS} -o lcddisplay.o lcddisplay.c ${LINKOBJECTS}
	avr-objcopy -j .text -O ihex lcddisplay.o lcddisplay.hex
	
lcddisplay.ass:	lcddisplay.hex
	avr-objdump -S -d lcddisplay.o > lcddisplay.ass
	
lcddisplay-upload:	lcddisplay.hex
	#avrdude ${AVRDUDEFLAGS} -U flash:w:lcddisplay.hex:a
	avrdude ${AVRDUDEFLAGS} -e
	sleep 0.1
	avrdude ${AVRDUDEFLAGS} -D -U flash:w:lcddisplay.hex:a

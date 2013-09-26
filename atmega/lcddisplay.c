// initialload.c
// for NerdKits with ATmega168
// mrobbins@mit.edu

#define F_CPU 14745600

#include <stdio.h>
#include <math.h>

#include <avr/io.h>
#include <avr/interrupt.h>
#include <avr/pgmspace.h>
#include <inttypes.h>

#include "libnerdkits/delay.h"
#include "libnerdkits/uart.h"
#include "libnerdkits/lcd.h"

// PIN DEFINITIONS:
//
// PC4 -- LED anode

int main() {
	// fire up the LCD
	lcd_init();
	FILE lcd_stream = FDEV_SETUP_STREAM(lcd_putchar, 0, _FDEV_SETUP_WRITE);
	FILE uart_stream = FDEV_SETUP_STREAM(uart_putchar, uart_getchar, _FDEV_SETUP_RW);
	stdin = stdout = &uart_stream;

	lcd_home();

	uint8_t i = 0;
	char buf[3];

	while(1) {
		if (fgets(buf, sizeof buf - 1, stdin) == NULL)
			break;

		if (buf[0] == '\n' || buf[0] == '\r') {
			if      (i < 20) { i = 20; }
			else if (i < 40) { i = 40; }
			else if (i < 60) { i = 60; }
			else if (i < 80) { i = 80; }
		}
		else if (buf[0] == '\033') {
			break;
			// Quit on ESC
		}
		else {
			i++;
			if      (i == 21) { lcd_line_two(); }
			else if (i == 41) { lcd_line_three(); }
			else if (i == 61) { lcd_line_four(); }
			else if (i == 81) { lcd_line_one(); i = 0; }
	
			fprintf_P(&lcd_stream, PSTR("%s"), buf);
		}
  	}

	lcd_clear_and_home();
    //                     01234567890123456789
	lcd_write_string(PSTR("FINE! DONE THEN.    "));
	while (1) {}

	return 0;
}

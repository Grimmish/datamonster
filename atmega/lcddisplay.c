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
	uint8_t x = 0;
	char buf[90];

	uint8_t bufcount = 0;
	uint8_t lcdcol;
	uint8_t lcdrow;
	uint8_t over = 0;

	while(1) {
		if (fgets(buf, sizeof buf - 1, stdin) == NULL)
			break;

		printf_P(PSTR("\nFULL TRANSMISSION:%s:\n"), buf);

		lcdcol = 1;
		lcdrow = 1;
		lcd_line_one(); 
		printf_P(PSTR("\nL1:")); 

		for (x=0; x < 90; x++) {
			if (buf[x] == '\0') {
				printf_P(PSTR("\n***\n"));

				for (lcdcol; lcdcol < 21; lcdcol++) {
					fprintf_P(&lcd_stream, PSTR(" "));
				}
				lcdrow++;
				for (lcdrow; lcdrow < 5; lcdrow++) {
					lcdcol = 1;
					if      (lcdrow == 2) { lcd_line_two(); }
					else if (lcdrow == 3) { lcd_line_three(); }
					else if (lcdrow == 4) { lcd_line_four(); }

					for (lcdcol; lcdcol < 21; lcdcol++) {
						fprintf_P(&lcd_stream, PSTR(" "));
					}
				}
				break;
			}
			else if (buf[x] < 32) {
    			printf_P(PSTR("*"));
			}
			else {
				fprintf_P(&lcd_stream, PSTR("%c"), buf[x]);
    			printf_P(PSTR("%c"), buf[x]);
				//delay_ms(20);
				lcdcol++;
				if (lcdcol > 20) {
					lcdrow++;
					lcdcol = 1;

					if      (lcdrow == 2) { lcd_line_two(); printf_P(PSTR("\nL2:")); }
					else if (lcdrow == 3) { lcd_line_three(); printf_P(PSTR("\nL3:")); }
					else if (lcdrow == 4) { lcd_line_four(); printf_P(PSTR("\nL4:"));  }
					else if (lcdrow == 5) { break; printf_P(PSTR("\n***\n")); }
				}
			}
		}

  	}

	return 0;
}

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

#include "libnerdkits/lcd.h"

// PIN DEFINITIONS:
//
// PC4 -- LED anode

int main() {
  // fire up the LCD
  lcd_init();
  FILE lcd_stream = FDEV_SETUP_STREAM(lcd_putchar, 0, _FDEV_SETUP_WRITE);
  lcd_home();

  // print message to screen
  //			 20 columns wide:
  //                     01234567890123456789

/*
  lcd_line_one();
  lcd_write_string(PSTR("  Congratulations!  "));
  delay_ms (500);
  lcd_line_two();
  lcd_write_string(PSTR("********************"));
  delay_ms (500);
  lcd_line_three();
  lcd_write_string(PSTR("  Your USB NerdKit  "));
  delay_ms (500);
  lcd_line_four();
  lcd_write_string(PSTR("      is alive!     "));
  delay_ms (4000);
*/

  double chuck = 1;

  while(1) {
    lcd_line_one();
    //                           01234567890123456789
  	fprintf_P(&lcd_stream, PSTR("Timer:  %4.1f  "), (chuck / 10));
	chuck++;
  	delay_ms (100);
  }
  
  return 0;
}

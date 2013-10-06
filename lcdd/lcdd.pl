#!/usr/bin/perl

use warnings;
use strict;
use FileHandle;
use Data::Dumper;


my $debug = 1;
#my $debug = undef;

my $panel = {
	accel => 1,
	gyro => 0,
	gps => "wait",
	aldl => "no",
	ssid => "Arcadia-Z",
	ip => "10.0.0.134"
};

#              12345678901234567890
my $lcdform = "SENSORS:[%-5.5s %-4.4s]" .
              "GPS:%-4.4s[          ]" .
              "ALDL:%-2.2s [          ]" .
              "%s/%-*.*s";

#####################################
###  Main
#####################################

&drawLCD($lcdform, $panel);

while (1) {
	open(my $inpipe, "<", "/var/tmp/lcdd.pipe")
		or die "DIE: Couldn't open inpipe: $!\n";

	while(<$inpipe>) {
		chomp;
		my @update = split(/:/);
		next unless (scalar @update == 2 && defined $panel->{$update[0]});
		$panel->{$update[0]} = $update[1];
		&drawLCD($lcdform, $panel);
	}
}

#####################################
###  Subs
#####################################

sub drawLCD {
	my $template = shift;
	my $contents = shift;

	my $stage = sprintf($template,
	                    ($contents->{accel} > 0 ? "ACCEL" : "accel"), ($contents->{gyro} > 0 ? "GYRO" : "gyro"),
	                    $contents->{gps},
	                    $contents->{aldl},
	                    $contents->{ip}, length($contents->{ip}), length($contents->{ip}), $contents->{ssid});

	if ($debug) {
		print "\n12345678901234567890\n";
		print "$_\n" foreach (unpack('a20 a20 a20 a20', $stage));
	}
	else {
		printf "GONE TO SERIAL PORT";
	}
}

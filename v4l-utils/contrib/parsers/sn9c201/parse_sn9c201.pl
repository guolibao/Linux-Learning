#!/usr/bin/perl

#   Copyright (C) 2010 Mauro Carvalho Chehab
#
#   This program is free software; you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation, version 2 of the License.
#
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
# This small script parses USB dumps generated by several drivers,
# decoding USB bits.
#
# To use it, do:
# dmesg | ./parse_usb.pl
#
# Also, there are other utilities that produce similar outputs, and it
# is not hard to parse some USB analyzers log into the expected format.
#
use strict;
use Getopt::Long;

my $debug = 0;
GetOptions('d' => \$debug);

# FIXME: How to handle multiple registers being changed at the same time?

my %reg_map = (
	0x10e0 => "SN9C201_R10E0_IMG_FMT",
	0x1180 => "SN9C201_R1180_HSTART_LOW",
	0x1181 => "SN9C201_R1181_HSTART_HIGH",
	0x1182 => "SN9C201_R1182_VSTART_LOW",
	0x1183 => "SN9C201_R1183_VSTART_HIGH",
	0x1184 => "SN9C201_R1184_HSIZE",
	0x1185 => "SN9C201_R1185_VSIZE",
	0x1189 => "SN9C201_R1189_SCALE",
	0x11b8 => "SN9C201_R11B8_CLK_CTRL",
);


sub i2c_reg($)
{
	my %decode;
	my $reg = shift;

	$reg =~ s/\s+.*//;
	$reg = hex("$reg");

	if ($reg & 0x01) {
		$decode{"speed"} = "400kbps";
	} else {
		$decode{"speed"} = "100kbps";
	}
	if ($reg & 0x02) {
		$decode{"op"} = "RD";
	} else {
		$decode{"op"} = "WR";
	}
	$decode{"busy"} = "BUSY" if (($reg & 0x04) == 0);
	$decode{"err"} = "ERR" if ($reg & 0x08);
	$decode{"size"} = ($reg >> 4) & 7;
	$decode{"i2c"} = "3wire" if (($reg & 0x80) == 0);

	return %decode;
}

sub type_req($)
{
	my $reqtype = shift;
	my $s;

	if ($reqtype & 0x80) {
		$s = "RD ";
	} else {
		$s = "WR ";
	}
	if (($reqtype & 0x60) == 0x20) {
		$s .= "CLAS ";
	} elsif (($reqtype & 0x60) == 0x40) {
		$s .= "VEND ";
	} elsif (($reqtype & 0x60) == 0x60) {
		$s .= "RSVD ";
	}

	if (($reqtype & 0x1f) == 0x00) {
		$s .= "DEV ";
	} elsif (($reqtype & 0x1f) == 0x01) {
		$s .= "INT ";
	} elsif (($reqtype & 0x1f) == 0x02) {
		$s .= "EP ";
	} elsif (($reqtype & 0x1f) == 0x03) {
		$s .= "OTHER ";
	} elsif (($reqtype & 0x1f) == 0x04) {
		$s .= "PORT ";
	} elsif (($reqtype & 0x1f) == 0x05) {
		$s .= "RPIPE ";
	} else {
		$s .= sprintf "RECIP 0x%02x ", $reqtype & 0x1f;
	}

	$s =~ s/\s+$//;
	return $s;
}

my %i2c;
my $i2c_id;
while (<>) {
	tr/A-F/a-f/;
	if (m/([0-9a-f].) ([0-9a-f].) ([0-9a-f].) ([0-9a-f].) ([0-9a-f].) ([0-9a-f].) ([0-9a-f].) ([0-9a-f].)[\<\>\s]+(.*)/) {
		my $reqtype = hex($1);
		my $req = hex($2);
		my $wvalue = hex("$4$3");
		my $windex = hex("$6$5");
		my $wlen = hex("$8$7");
		my $payload = $9;
		my $fullpayload = $9;

		%i2c = i2c_reg($payload) if ($wvalue == 0x10c0);

		if (($wvalue >= 0x10c0) && ($wvalue <= 0x10c2)) {
			my $reg = $wvalue;
			if ($reg == 0x10c0) {
				$payload =~ s/^([0-9a-f].)//;
				$payload =~ s/^\s+//;
				$reg++;
			}
			if ($reg == 0x10c1 && $payload ne "") {
				$i2c_id = $payload;
				$i2c_id =~ s/\s+.*//;
				$i2c_id = "addr=0x$i2c_id, ";
				$payload =~ s/^([0-9a-f].)//;
				$payload =~ s/^\s+//;
				$reg++;
			}

			my $data;
			for (my $i = 0; ($i < $i2c{"size"}) && ($payload ne ""); $i++) {
				my $tmp = $payload;
				$tmp =~ s/\s+.*//;
				$payload =~ s/^([0-9a-f].)//;
				$payload =~ s/^\s+//;
				$data .= "0x$tmp, ";
			}
			$data =~ s/\,\s+$//;

			my $discard;
			for (my $i = 0; ($i < 5) && ($payload ne ""); $i++) {
				my $tmp = $payload;
				$tmp =~ s/\s+.*//;
				$payload =~ s/^([0-9a-f].)//;
				$payload =~ s/^\s+//;
				$discard .= "0x$tmp, ";
			}
			$discard =~ s/\,\s+$//;

			my $s = sprintf "%s %s %s %s %s size=%d",
				$i2c{"op"}, $i2c{"speed"}, $i2c{"busy"}, $i2c{"err"}, $i2c{"i2c"}, $i2c{"size"};
			$s =~ s/\s+/ /g;

			if ($debug) {
				if ($reqtype & 0x80) {
					printf "Read I2C: $s $i2c_id$data";
				} else {
					printf "I2C $s $i2c_id$data";
				}
				printf " ($discard)" if ($discard);
				printf "Extra: $payload" if ($payload);
				print "\n";

				printf("\t%s, Req %3d, wValue: 0x%04x, wIndex 0x%04x, wlen %d: %s\n",
					type_req($reqtype), $req, $wvalue, $windex, $wlen, $fullpayload);
			}
			next if ($reg < 0x10c2);
			if (($i2c{"size"} == 1) && ($reqtype & 0x80)) {
				printf "i2c_r1(gspca_dev, $data);\n";
			} elsif (($i2c{"size"} == 2) && (($reqtype & 0x80) == 0)) {
				printf "i2c_w1(gspca_dev, $data);\n";
			} else {
				if ($reqtype & 0x80) {
					printf "i2c_r(gspca_dev, { $data }, %d);\n", $i2c{"size"};
				} else {
					printf "i2c_w(gspca_dev, { $data }, %d);\n", $i2c{"size"};
				}
			}
		} else {
			printf("%s, Req %3d, wValue: 0x%04x, wIndex 0x%04x, wlen %d: %s\n",
				type_req($reqtype), $req, $wvalue, $windex, $wlen, $payload) if ($debug);

			my $reg;
			if (defined($reg_map{$wvalue})) {
				$reg = $reg_map{$wvalue};
			} else {
				$reg = sprintf "0x%04x", $wvalue;
			}

			if ($reqtype == 0xc1) {
				printf "reg_r(gspcadev, %s);\t/* read %s*/\n", $reg, $payload;
			} elsif ($reqtype == 0x41) {
				printf "reg_w(gspcadev, %s, { %s });*/\n", $reg, $payload;
			}
		}
	}
}

#!/usr/bin/perl
use POSIX qw(strftime); $| = 1;
while (<STDIN>) { print strftime("%H:%M:%S ", localtime), $_; }

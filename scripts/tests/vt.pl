#!/usr/bin/env perl
# vt.pl COLS ROWS FILE — replay a terminal transcript (from `script`) on a
# COLS x ROWS screen that wraps long lines and scrolls, the way a real terminal
# does, and print what the user would see: the scrollback, then the screen.
# Handles \r, \n, cursor up/down (CSI A/B), erase (CSI K/J); other escapes are
# ignored.
use strict;
use warnings;

my ($W, $H, $file) = @ARGV;
open my $f, '<:utf8', $file or die "$file: $!\n";
my $t = do { local $/; <$f> };
binmode STDOUT, ':utf8';

my @back;
my @scr = ('') x $H;
my ($r, $c) = (0, 0);

sub lf {
  if ($r == $H - 1) { push @back, shift @scr; push @scr, '' }
  else { $r++ }
}

sub put {
  my $ch = shift;
  if ($c >= $W) { $c = 0; lf() }          # deferred wrap, like xterm
  my $l = $scr[$r];
  $l .= ' ' x ($c - length $l) if length $l < $c;
  substr($l, $c, 1) = $ch;
  $scr[$r] = $l;
  $c++;
}

while (length $t) {
  if ($t =~ s/^\e\[\??([0-9;]*)([A-Za-z])//) {
    my ($n, $k) = ($1 eq '' ? 1 : $1, $2);
    if    ($k eq 'A') { $r -= $n; $r = 0 if $r < 0 }
    elsif ($k eq 'B') { $r += $n; $r = $H - 1 if $r > $H - 1 }
    elsif ($k eq 'K') { $scr[$r] = substr($scr[$r], 0, $c) if length $scr[$r] > $c }
    elsif ($k eq 'J') { $scr[$r] = substr($scr[$r], 0, $c) if length $scr[$r] > $c; $scr[$_] = '' for $r + 1 .. $H - 1 }
    next;
  }
  my $ch = substr($t, 0, 1, '');
  if    ($ch eq "\r") { $c = 0 }
  elsif ($ch eq "\n") { lf(); $c = 0 }
  elsif ($ch =~ /[\x00-\x1f]/) { }
  else { put($ch) }
}

my @all = (@back, @scr);
s/\s+$// for @all;
pop @all while @all && $all[-1] eq '';
print "$_\n" for @all;

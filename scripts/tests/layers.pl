#!/usr/bin/env perl
# layers.pl FILE... — check the lib layering (superpowers.sh's header): a file
# calls functions of its own layer or the ones above (a lower number), never
# below, and no calls go round in a cycle. A call is a function name used
# outside a comment in another file. Prints each violation; exits 1 if any.
use strict;
use warnings;

my %layer = (
  ui => 1, pipeline => 1,
  files => 2, json => 2, fetch => 2, lock => 2,
  (map { $_ => 3 } qw(skills security agents stacks ripgrep codemap mcp hooks targets legacy
                      claude codex copilot cursor gemini antigravity devin)),
  install => 4, check => 4, picker => 4,
  superpowers => 5,
);

my (%def, %src, %edge, $bad);
for my $f (@ARGV) {
  my ($name) = $f =~ m{([^/]+)\.sh$} or die "$f: not a .sh file\n";
  defined $layer{$name} or die "$f: no layer — add it to the table in $0\n";
  open my $fh, '<', $f or die "$f: $!\n";
  my $s = do { local $/; <$fh> };
  $src{$name} = join "\n", grep { !/^\s*#/ } split /\n/, $s;
  $def{$1} = $name while $s =~ /^\s*([a-z_][a-z0-9_]*)\(\)\s*\{/mg;
}

for my $from (sort keys %src) {
  for my $fn (sort keys %def) {
    my $to = $def{$fn};
    next if $to eq $from || $src{$from} !~ /(?<![\w\$-])\Q$fn\E(?![\w-])/;
    $edge{$from}{$to} = 1;
    next if $layer{$to} <= $layer{$from};
    print "$from.sh (layer $layer{$from}) calls $fn from $to.sh (layer $layer{$to}, below it)\n";
    $bad = 1;
  }
}

my (%state, @path);
sub visit {
  my $n = shift;
  $state{$n} = 1;
  push @path, $n;
  for my $m (sort keys %{ $edge{$n} || {} }) {
    if (($state{$m} || 0) == 1) {
      my ($i) = grep { $path[$_] eq $m } 0 .. $#path;
      print "cycle: ", join(' -> ', map { "$_.sh" } @path[$i .. $#path], $m), "\n";
      $bad = 1;
    } elsif (!$state{$m}) {
      visit($m);
    }
  }
  pop @path;
  $state{$n} = 2;
}
visit($_) for grep { !$state{$_} } sort keys %src;
exit($bad ? 1 : 0);

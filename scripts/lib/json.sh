# Editing the agents' JSON configs in place.

# json_edit FILE PERL — PERL mutates $d (the parsed object, {} if missing)
# with the helpers below. Perl + JSON::PP (core since 5.14) rather than node, so
# it works on machines without node. JSONC-tolerant so .vscode/*.json with
# comments works (the original is kept as FILE.bak). Keys are written sorted.
# An object left empty deletes the file.
#   add_entry($d, PATH..., ENTRY)       push ENTRY onto the array at PATH
#   add_values($d, PATH..., [VALUES])   push the VALUES not already there
#   drop_entries($d, PATH..., qr/RE/)   drop entries whose JSON matches RE
#   drop_values($d, PATH..., [VALUES])  drop these scalar values
#   delete_key($d, PATH...)             delete the key at PATH
#   put_ours($d, PATH..., VALUE, qr/RE/) set the key at PATH, unless it holds a
#                                       value of someone else's (JSON not
#                                       matching RE): then JSON_SKIPPED is set
#   drop_ours($d, PATH..., qr/RE/)      delete the key at PATH if its JSON matches RE
# The drop/delete helpers never create anything and prune the containers they
# leave empty.
json_edit() {
  local file="$1" code="$2"
  mkdir -p "$(dirname "$file")"
  rm -f "$TMP_DIR/json.skipped"
  SP_FILE="$file" SP_CODE="$code" SP_SKIPPED="$TMP_DIR/json.skipped" perl 2> "$TMP_DIR/json.err" <<'PERL' \
    || die "could not update ${file#"$PROJECT_DIR"/}: $(tail -1 "$TMP_DIR/json.err")"
use strict;
use warnings;
use JSON::PP;
my $file = $ENV{SP_FILE};

sub strip_jsonc {
  my $s = shift;
  $s =~ s{("(?:\\.|[^"\\])*")|//[^\n]*|/\*.*?\*/}{defined $1 ? $1 : ''}gse;
  $s =~ s{("(?:\\.|[^"\\])*")|,(\s*[\}\]])}{defined $1 ? $1 : $2}gse;
  return $s;
}

sub enc { JSON::PP->new->canonical->encode($_[0]) }
sub is_empty { my $v = shift; ref $v eq 'HASH' ? !%$v : ref $v eq 'ARRAY' ? !@$v : 0 }

# the containers along PATH (undef past the first missing one)
sub chain {
  my ($d, @path) = @_;
  my @chain = ($d);
  for my $k (@path) {
    my $parent = $chain[-1];
    return @chain, undef unless ref $parent eq 'HASH' && exists $parent->{$k};
    push @chain, $parent->{$k};
  }
  return @chain;
}

sub prune {
  my ($d, @path) = @_;
  my @chain = chain($d, @path);
  for my $i (reverse 0 .. $#path) {
    last unless defined $chain[$i + 1] && is_empty($chain[$i + 1]);
    delete $chain[$i]{$path[$i]};
  }
}

sub vivify {
  my ($d, @path) = @_;
  my $last = pop @path;
  my $h = $d;
  $h = ($h->{$_} //= {}) for @path;
  return $h->{$last} //= [];
}

sub add_entry { my $entry = pop; push @{ vivify(@_) }, $entry }

sub add_values {
  my $values = pop;
  my $list = vivify(@_);
  my %have = map { ref $_ ? () : ($_ => 1) } @$list;
  push @$list, grep { !$have{$_}++ } @$values;
}

sub edit_list {
  my ($fn, $d, @path) = @_;
  my $list = (chain($d, @path))[-1];
  return unless ref $list eq 'ARRAY';
  @$list = grep { $fn->($_) } @$list;
  prune($d, @path);
}

sub drop_entries { my $re = pop; edit_list(sub { enc($_[0]) !~ $re }, @_) }

sub drop_values {
  my %drop = map { $_ => 1 } @{ pop() };
  edit_list(sub { ref $_[0] || !$drop{ $_[0] } }, @_);
}

sub delete_key {
  my ($d, @path) = @_;
  my $last = pop @path;
  my $parent = (chain($d, @path))[-1];
  return unless ref $parent eq 'HASH';
  delete $parent->{$last};
  prune($d, @path);
}

sub put_ours {
  my ($re, $value) = (pop, pop);
  my ($d, @path) = @_;
  my $last = pop @path;
  my $h = $d;
  $h = ($h->{$_} //= {}) for @path;
  if (exists $h->{$last} && enc($h->{$last}) !~ $re) {
    open my $fh, '>', $ENV{SP_SKIPPED} or die "$ENV{SP_SKIPPED}: $!\n";
    return;
  }
  $h->{$last} = $value;
}

sub drop_ours {
  my $re = pop;
  my ($d, @path) = @_;
  my $v = (chain($d, @path))[-1];
  delete_key($d, @path) if defined $v && enc($v) =~ $re;
}

my $d = {};
if (-f $file) {
  my $raw = do { local $/; open my $fh, '<:raw', $file or die "$file: $!\n"; <$fh> };
  if ($raw =~ /\S/) {
    $d = eval { JSON::PP->new->utf8->decode($raw) };
    unless ($d) {
      $d = JSON::PP->new->utf8->decode(strip_jsonc($raw));
      open my $bak, '>:raw', "$file.bak" or die "$file.bak: $!\n";
      print $bak $raw;
    }
  }
}
die "$file: not a JSON object\n" unless ref $d eq 'HASH';
eval "$ENV{SP_CODE}; 1" or die $@;
if (!%$d) { unlink $file }
else {
  open my $fh, '>:raw', $file or die "$file: $!\n";
  print $fh JSON::PP->new->utf8->canonical->indent->indent_length(2)->space_after->encode($d);
}
PERL
  JSON_SKIPPED=0
  [ -f "$TMP_DIR/json.skipped" ] && JSON_SKIPPED=1
  ok "${file#"$PROJECT_DIR"/}"
}

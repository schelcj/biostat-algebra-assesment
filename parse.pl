#!/usr/bin/env perl

use Modern::Perl;
use File::Slurp qw(read_file);
use File::Temp;
use IO::Scalar;
use Data::Dumper;

my $test         = $ARGV[0];
my @questions    = ();
my $question_ref = [];
my $contents     = read_file($test);
my $temp_fh      = File::Temp->new();

$contents =~ s/^(?:(.*)?\\begin{document})|(?:\\end{document})$//gs;

{
  local $/ = q{%QUESTION };
  my $content_fh = IO::Scalar->new(\$contents);
  @questions = map {$_} $content_fh->getlines;
}

foreach my $question (@questions) {
  next if $question !~ /^(?<number>\d+)/;
  my $number = $+{number};
  $question_ref->[$number]->{number} = $number;

  {
    local $/ = q{%};
    my $question_fh = IO::Scalar->new(\$question);
    foreach my $line ($question_fh->getlines) {

      given ($line) {
        when ($line =~ /^$number\n/) {
          my @parts = grep {/^\\/} split(/\n/, $line);
          map {$_ =~ s/^(.*) \\\\$/$1/g} @parts;
          $question_ref->[$number]->{question} = join(qq{\n}, @parts);
        }
        when ($line =~ /^$number(?<answer>([A-D]))\n/) {
          my $answer = $+{answer};
          $line =~ s/^${number}${answer}\n(.*)(?:(?:\s+[\\]+\s+[\n%]+)|\n+$)/$1/g;
          $question_ref->[$number]->{answers}->{$answer} = $line;
        }
      }
    }
  }
}

print Dumper $question_ref;

#!/usr/bin/env perl

use Modern::Perl;
use WWW::Mechanize;
use Net::Netrc;
use Readonly;
use File::Slurp qw(read_file);
use File::Temp;
use IO::Scalar;
use Carp qw(croak);
use English qw(-no_match_vars);
use List::MoreUtils qw(apply);
use Data::Dumper;

Readonly::Scalar my $EMPTY         => q{};
Readonly::Scalar my $BANG          => q{!};
Readonly::Scalar my $WEBLOGIN_URL  => q{https://weblogin.umich.edu};
Readonly::Scalar my $COSIGN_CGI    => q{cosign-bin/cosign.cgi};
Readonly::Scalar my $UMLESSONS_URL => q{https://lessons.ummu.umich.edu};
Readonly::Scalar my $UNIT_URL      => q{https://lessons.ummu.umich.edu/2k/manage/unit/list_lessons/sph_algebra_assesment};
Readonly::Scalar my $DIRECTIONS    => q{Hello World};
Readonly::Scalar my $SUMMARY       => q{Goodbye World};

my $latex       = $ARGV[0];                             # TODO - use getopts
my $lesson_name = q{2013};                              # TODO - get from command line arg
my $title       = q{SPH Algebra Assesment for 2013};    # TODO - get from command line arg
my $agent       = get_login_agent();
my $parsed_ref  = parse_latex($latex);

print Dumper $parsed_ref;
exit;

#create_lesson($lesson_name, $title);
#my $resource_id = create_resource($lesson_name);
#create_question($resource_id, $lesson_name, $question, @answers);

sub parse_latex {
  my ($test)       = @_;
  my @questions    = ();
  my $question_ref = [];
  my $contents     = read_file($test);
  my $temp_fh      = File::Temp->new();

  $contents =~ s/^(?:(.*)?\\begin{document})|(?:\\end{document})$//gs;

  {
    local $INPUT_RECORD_SEPARATOR = q{%QUESTION };
    my $content_fh = IO::Scalar->new(\$contents);
    @questions = map {$_} $content_fh->getlines;
  }

  foreach my $question (@questions) {
    my $number;

    if ($question =~ /^(\d+)/) {
      $number = $1;
      $question_ref->[$number]->{number} = $number;
    } else {
      next;
    }

    {
      local $INPUT_RECORD_SEPARATOR = q{%};
      my $question_fh = IO::Scalar->new(\$question);
      foreach my $line ($question_fh->getlines) {

        given ($line) {
          when ($line =~ /^$number\n/) {
            my @parts = apply {$_ =~ s/^(.*) \\\\$/$1/g} grep {/^\\/} split(/\n/, $line);
            $question_ref->[$number]->{question} = join(qq{\n}, @parts);
          }
          when ($line =~ /^$number([A-D])\n/) {
            my $answer = $1;
            $line =~ s/^${number}${answer}\n(.*)(?:(?:\s+[\\]+\s+[\n%]+)|\n+$)/$1/g;
            $question_ref->[$number]->{answers}->{$answer} = $line;
          }
        }
      }
    }
  }

  return $question_ref;
}

sub get_login_agent {
  my $mach = Net::Netrc->lookup('cosign.umich.edu');
  my $www  = WWW::Mechanize->new();

  $www->get($WEBLOGIN_URL);
  $www->post(
    qq{$WEBLOGIN_URL/$COSIGN_CGI}, {
      login    => $mach->login,
      password => $mach->password,
      ref      => qq{$UMLESSONS_URL/2k/manage/workspace/reader},
      service  => 'cosign-lessons.ummu',
    }
  );

  if ($www->success) {
    say 'Logged into CoSign successfully';
  } else {
    croak 'Unable to login to CoSign';
  }

  return $www;
}

sub create_lesson {
  my ($name, $lesson_title) = @_;

  $agent->post(
    qq{$UMLESSONS_URL/2k/manage/lesson/setup/sph_algebra_assesment}, {
      op    => 'Continue...',
      style => 'quiz',
    }
  );

  $agent->post(
    qq{$UMLESSONS_URL/2k/manage/lesson/update_settings/sph_algebra_assesment#lesson}, {
      charset               => $BANG,
      defaultShowTitle      => 'FALSE',
      firstItemFirst        => 'TRUE',
      howManyItemsDisplayed => 'ALL',
      keywords              => $EMPTY,
      lastItemLast          => 'TRUE',
      name                  => $name,
      navigationOptions     => 'sequential-only',
      new_setup             => 1,
      op                    => 'save',
      other_charset         => $EMPTY,
      passingThreshold      => '70',
      presentationStyle     => 'page-by-page',
      randomization         => 'FALSE',
      repeatOptions         => 'once',
      showBanner            => 'TRUE',
      showFeedback          => 'TRUE',
      showFooter            => 'TRUE',
      showLinks             => 'TRUE',
      style                 => 'quiz',
      title                 => $lesson_title,
    }
  );

  $agent->post(
    qq{$UMLESSONS_URL/2k/manage/lesson/update_content/sph_algebra_assesment/$name#directions}, {
      directionsText => $DIRECTIONS,
      op             => 'save',
      section        => 'directions',
    }
  );

  $agent->post(
    qq{$UMLESSONS_URL/2k/manage/lesson/update_content/sph_algebra_assesment/$name#summary}, {
      summaryText => $SUMMARY,
      op          => 'save',
      section     => 'summary',
    }
  );

  if ($agent->success) {
    say qq{Create lesson ($name) successfully};
  }

  return;
}

sub create_resource {
  my ($name) = @_;

  my $resource_title = 'Mathjax';
  my $resource       = <<'EOF';
<!-- html -->
<script type="text/javascript" src="http://cdn.mathjax.org/mathjax/latest/MathJax.js?config=TeX-AMS-MML_HTMLorMML"></script>
<!-- html -->
EOF

  $agent->post(
    qq{$UMLESSONS_URL/2k/manage/resource/setup/sph_algebra_assesment/$name}, {
      choice => 'text',
      op     => 'Continue...',
    }
  );

  $agent->post(
    qq{$UMLESSONS_URL/2k/manage/resource/create/sph_algebra_assesment/$name}, {
      choice          => 'text',
      title           => $resource_title,
      keywords        => $EMPTY,
      border          => '0',
      borderBgColor   => 'black',
      borderFillColor => 'none',
      op              => 'Save',
      excerpt         => $resource,
    }
  );

  my ($url, $resource_id) = split(/\$/, $agent->response->previous->header('location'));

  if ($agent->success) {
    say qq{Create resource ($resource_title - $resource_id) successfully};
  }

  return $resource_id;
}

sub create_question {
  my ($resource_id, $name, $question, @answers) = @_;

  $agent->post(
    qq{$UMLESSONS_URL/2k/manage/inquiry/create/sph_algebra_assesment/$name}, {
      choice                               => 'multiple_choice',
      op                                   => 'Save',
      question                             => $question,
      'multiple_choice:numberAnswers'      => '4',
      'multiple_response:numberAnswers'    => '4',
      'opinion_poll:numberAnswers'         => '5',
      'question/align'                     => 'LEFT',
      'question/resource'                  => $resource_id,
      'rating_scale_queries:numberAnswers' => '5',
      'rating_scales:numberAnswers'        => '1',
    }
  );

  return;
}

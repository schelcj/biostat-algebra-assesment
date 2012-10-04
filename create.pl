#!/usr/bin/env perl

# TODO questions 11 and 23 have rendering issues

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
use Text::Roman;
use Data::Dumper;

Readonly::Scalar my $EMPTY         => q{};
Readonly::Scalar my $BANG          => q{!};
Readonly::Scalar my $WEBLOGIN_URL  => q{https://weblogin.umich.edu};
Readonly::Scalar my $COSIGN_CGI    => q{cosign-bin/cosign.cgi};
Readonly::Scalar my $UMLESSONS_URL => q{https://lessons.ummu.umich.edu};
Readonly::Scalar my $UNIT_URL_NAME => q{sph_algebra_assesment};
Readonly::Scalar my $DIRECTIONS    => q{Hello World};
Readonly::Scalar my $SUMMARY       => q{Goodbye World};

my $latex       = $ARGV[0];                             # TODO - use getopts
my $lesson_name = q{2013};                              # TODO - get from command line arg
my $title       = q{SPH Algebra Assesment for 2013};    # TODO - get from command line arg
my $agent       = get_login_agent();
my $parsed_ref  = parse_latex($latex);

create_lesson($lesson_name, $title);

my $resource_id = create_resource($lesson_name);

foreach my $question (@{$parsed_ref}) {
  next if not $question;                                # FIXME how did that undef get in there?

  my $question_id = create_question($resource_id, $lesson_name, $question);
  say "Created question #$question->{number} - $question_id";

  add_answers($question_id, $lesson_name, $question->{answers});
  my $answer_count = scalar keys %{$question->{answers}};
  say "Added $answer_count to question #$question->{number}";
}

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
            my @parts = grep {/^\\/} split(/\n/, $line);

            # my @lines = apply {$_ =~ s/^(.*) \\\\$/$1/g} @parts;
            # FIXME these should be equivalent but something weird is going on in perl

            my @lines;
            for (@parts) {
              $_ =~ s/^(.*) \\\\$/$1/g;
              push @lines, $_;
            }

            $question_ref->[$number]->{question} = join(qq{\n}, @lines);
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

sub format_latex_for_mathjax {
  my ($latex) = @_;
  return sprintf(qq{<!-- html -->\n\\( %s \\)\n<!-- html -->\n}, $latex);
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
    qq{$UMLESSONS_URL/2k/manage/lesson/setup/$UNIT_URL_NAME}, {
      op    => 'Continue...',
      style => 'quiz',
    }
  );

  $agent->post(
    qq{$UMLESSONS_URL/2k/manage/lesson/update_settings/$UNIT_URL_NAME#lesson}, {
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
    qq{$UMLESSONS_URL/2k/manage/lesson/update_content/$UNIT_URL_NAME/$name#directions}, {
      directionsText => $DIRECTIONS,
      op             => 'save',
      section        => 'directions',
    }
  );

  $agent->post(
    qq{$UMLESSONS_URL/2k/manage/lesson/update_content/$UNIT_URL_NAME/$name#summary}, {
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
    qq{$UMLESSONS_URL/2k/manage/resource/setup/$UNIT_URL_NAME/$name}, {
      choice => 'text',
      op     => 'Continue...',
    }
  );

  $agent->post(
    qq{$UMLESSONS_URL/2k/manage/resource/create/$UNIT_URL_NAME/$name}, {
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

  (my $id = $agent->response->previous->header('location')) =~ s/^.*\$(.*)$/$1/g;

  if ($agent->success) {
    say qq{Created resource ($resource_title - $id) successfully};
  }

  return $id;
}

sub create_question {
  my ($rid, $name, $question) = @_;

  my $question_text = format_latex_for_mathjax($question->{question});
  my $answers       = scalar keys %{$question->{answers}};

  $agent->post(
    qq{$UMLESSONS_URL/2k/manage/inquiry/create/$UNIT_URL_NAME/$name}, {
      choice                            => 'multiple_choice',
      op                                => 'Save',
      question                          => $question_text,
      'multiple_choice:numberAnswers'   => $answers,
      'multiple_response:numberAnswers' => $answers,
      'question/resource'               => $rid,
      'question/align'                  => 'ABOVE',
    }
  );

  (my $id = $agent->response->previous->header('location')) =~ s/^.*\$([\w]+)(?:\?.*)?$/$1/g;

  $agent->post(
    qq{$UMLESSONS_URL/2k/manage/multiple_choice/update_settings/unit_4697/quiz_001\$${id}#}, {
      correctCaption        => 'Correct!',
      feedback              => 'TRUE',
      firstItemFirst        => 'FALSE',
      generalFeedback       => 'FALSE',
      howManyItemsDisplayed => 'ALL',
      incorrectCaption      => 'This is not correct.',
      keywords              => $EMPTY,
      lastItemLast          => 'FALSE',
      op                    => 'save',
      pointsWorth           => '1',
      randomization         => 'FALSE',
      repeatQuestion        => 'FALSE',
      responseLabelStyle    => 'alpha',
      setDefault            => 'FALSE',
      showTitle             => 'FALSE',
      specificFeedback      => 'TRUE',
      title                 => qq[Q: $question->{number}],
    }
  );

  return $id;
}

sub add_answers {
  my ($id, $name, $answers) = @_;

  my $answer_number = 1;
  foreach my $answer (sort keys %{$answers}) {
    my $roman       = lc(roman($answer_number));
    my $order       = qq{c$roman.$answer_number};
    my $answer_text = $answers->{$answer};
    
    my $count = ()= $answer_text =~ /\$/g;
    if ($count > 1) {
      $answer_text =~ s/\$//g;
    }

    $agent->post(
      qq[$UMLESSONS_URL/2k/manage/multiple_choice/update_content/$UNIT_URL_NAME/$name\$${id}#answers.c$roman], {
        op                  => 'save',
        order               => $order,
        qq{order.$order}    => $order,
        response            => format_latex_for_mathjax($answer_text),
        section             => qq{answers.c$roman},
        correct             => 'FALSE',
        feedback            => $EMPTY,
        'response/align'    => 'LEFT',
        'response/resource' => 'none',
        'feedback/align'    => 'LEFT',
        'feedback/resource' => 'none',
      }
    );

    say "Added answer $answer to question $id";
    $answer_number++;
  }

  return;
}

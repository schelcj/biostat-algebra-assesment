#!/usr/bin/env perl

# FIXME - question 11 still has escapes on % and $

use FindBin qw($Bin);
use Modern::Perl;
use WWW::Mechanize;
use Net::Netrc;
use Readonly;
use File::Slurp qw(read_file);
use File::Temp;
use IO::Scalar;
use Carp qw(croak);
use English qw(-no_match_vars);
use List::MoreUtils qw(apply first_index);
use Text::Roman;
use Config::Tiny;
use Getopt::Compact;
use URI;
use Data::Dumper;
use JSON::Any;

Readonly::Scalar my $EMPTY          => q{};
Readonly::Scalar my $BANG           => q{!};
Readonly::Scalar my $SPACE          => q{ };
Readonly::Scalar my $COLON          => q{:};
Readonly::Scalar my $COMA           => q{,};
Readonly::Scalar my $WEBLOGIN_URL   => q{https://weblogin.umich.edu};
Readonly::Scalar my $COSIGN_CGI     => q{cosign-bin/cosign.cgi};
Readonly::Scalar my $UNIT_URL_NAME  => q{sph_algebra_assesment};
Readonly::Scalar my $UMLESSONS_URL  => q{https://lessons.ummu.umich.edu/2k/manage};
Readonly::Scalar my $RESOURCES_URL  => qq{$UMLESSONS_URL/unit/list_resources/$UNIT_URL_NAME};
Readonly::Scalar my $GRAPHIC_REGEXP => qr/^(.*)\\includegraphics\[[\w\.\=]+\]\{([^}]+)}(.*)$/s;

## no tidy
my $opts = Getopt::Compact->new(
  struct => [
    [[qw(c config)],     q(Config file),                q(=s)],
    [[qw(t test)],       q(Test name to build),         q(=s)],
    [[qw(p parse_only)], q(Parse the test and dump to stdout)],
  ]
)->opts();
## use tidy
my $config     = Config::Tiny->read($opts->{config});
my $test       = $config->{$opts->{test}};
my $answer_ref = parse_answers($test->{answers});
my $comps_ref  = parse_competencies($test->{competencies});
my $parsed_ref = parse_latex($test->{test}, $answer_ref);

if ($opts->{parse_only}) {
  print Dumper $parsed_ref, $comps_ref;
  exit;
}

my $agent = get_login_agent();
create_lesson($test);

my $mathjax_resource_id = find_resource($test->{lesson_name}, q{mathjax});
croak 'Could not find mathjax resource' if not $mathjax_resource_id;

foreach my $question (@{$parsed_ref}) {
  next if not $question;

  my $question_id = create_question($mathjax_resource_id, $test->{lesson_name}, $question);
  say "Created question #$question->{number} - $question_id";

  add_answers($question_id, $test->{lesson_name}, $question->{correct}, $question->{answers});
  my $answer_count = scalar keys %{$question->{answers}};
  say "Added $answer_count to question #$question->{number}";
}

sub get_login_agent {
  my $mach = Net::Netrc->lookup('cosign.umich.edu');
  my $www  = WWW::Mechanize->new();

  $www->get($WEBLOGIN_URL);
  $www->post(
    qq{$WEBLOGIN_URL/$COSIGN_CGI}, {
      login    => $mach->login,
      password => $mach->password,
      ref      => qq{$UMLESSONS_URL/workspace/reader},
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

sub parse_latex {
  my ($file, $answers) = @_;

  my @questions    = ();
  my $question_ref = [];
  my $contents     = read_file($file);
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
      $number                             = $1;
      $question_ref->[$number]->{number}  = $number;
      $question_ref->[$number]->{correct} = $answers->{$number};
    } else {
      next;
    }

    {
      local $INPUT_RECORD_SEPARATOR = q{%};
      my $question_fh = IO::Scalar->new(\$question);
      foreach my $line ($question_fh->getlines) {

        given ($line) {
          when (/^$number\n/) {
            my @parts = grep {/^\\/} split(/\n/, $line);
            my @lines;
            for (@parts) {
              $_ =~ s/^(.*) \\\\$/$1/g;
              push @lines, $_;
            }

            $question_ref->[$number]->{question} = join(qq{\n}, @lines);
          }
          when (/^$number([A-D])\s*\n/) {
            my $answer = $1;
            $line =~ s/^${number}${answer}\n(.*)(?:(?:\s+[\\]+\s+[\n%]+)|\n+$)/$1/g;
            $question_ref->[$number]->{answers}->{lc($answer)} = {text => $line};
          }
          when (/^(\s+.*)\s+\\\\[\n]/) {
            $question_ref->[$number]->{question} .= $1;
          }
          default {
          }
        }
      }
    }

    if ($question_ref->[$number]->{question} =~ /$GRAPHIC_REGEXP/) {
      $question_ref->[$number]->{question} = $1 . $3;
      $question_ref->[$number]->{resource} = $2;
    }

    foreach my $key (sort keys %{$question_ref->[$number]->{answers}}) {
      if ($question_ref->[$number]->{answers}->{$key}->{text} =~ /$GRAPHIC_REGEXP/) {
        $question_ref->[$number]->{answers}->{$key} = {
          text     => $1 . $3,
          resource => $2,
        };
      }
    }
  }

  return $question_ref;
}

sub parse_answers {
  my ($file) = @_;

  my $answers = {};
  foreach my $line (read_file($file)) {
    chomp($line);
    next if $line !~ /^\d+/;
    my ($number, $answer) = split(/$SPACE/, $line);
    $answers->{$number} = $answer;
  }

  return $answers;
}

sub parse_competencies {
  my ($file) = @_;
  my $comps = {competencies_map => {$EMPTY => [0]}};
  my @lines = read_file($file);

  foreach my $line (@lines) {
    chomp $line;
    next if $line =~ /^TEST/;
    next if $line =~ /^\s?$/;

    my ($competency, $questions) = split(/$COLON/, $line);
    my @questions = split(/$COMA/, $questions);

    push @{$comps->{categories}}, $competency;

    for my $i (@questions) {
      $i =~ s/\s//g;

      my $page = qq{Page $i};

      push @{$comps->{competencies_map}->{$page}}, first_index {$_ eq $competency} @{$comps->{categories}};
    }
  }

  return $comps;
}

sub format_latex_for_mathjax {
  my ($latex) = @_;
  return sprintf(qq{<!-- html -->\n\\( %s \\)\n<!-- html -->\n}, $latex);
}

sub get_response_id {
  my ($url) = @_;

  my $uri = URI->new($url);
  my ($path, $id) = split(/\$/, $uri->path);

  return $id;
}

sub create_lesson {
  my ($test_conf) = @_;
  my $directions  = read_file($test_conf->{directions});
  my $summary     = read_file($test_conf->{summary});
  my $name        = $test_conf->{lesson_name};
  my $title       = $test_conf->{lesson_title};

  $agent->post(
    qq{$UMLESSONS_URL/lesson/setup/$UNIT_URL_NAME}, {
      op    => 'Continue...',
      style => 'quiz',
    }
  );

  $agent->post(
    qq{$UMLESSONS_URL/lesson/update_settings/$UNIT_URL_NAME#lesson}, {
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
      title                 => $title,
    }
  );

  $agent->post(
    qq{$UMLESSONS_URL/lesson/update_content/$UNIT_URL_NAME/$name#directions}, {
      directionsText => $directions,
      op             => 'save',
      section        => 'directions',
    }
  );

  my $jquery_resource_id       = find_resource($name, q{Jquery});
  my $competencies_resource_id = find_resource($name, q{Competencies});
  my $comp_map_resource_id     = create_competencies_resource($comps_ref);

  $agent->post(
    qq{$UMLESSONS_URL/lesson/update_content/$UNIT_URL_NAME/$name#summary}, [
      summaryText            => $summary,
      op                     => 'save',
      section                => 'summary',
      'summaryText/align'    => 'ABOVE',
      'summaryText/resource' => $jquery_resource_id,
      'summaryText/resource' => $competencies_resource_id,
      'summaryText/resource' => $comp_map_resource_id,
    ]
  );

  if ($agent->success) {
    say qq{Create lesson ($name) successfully};
  }

  return;
}

sub find_resource {
  my ($name, $title) = @_;
  $agent->get($RESOURCES_URL);
  my $link = $agent->find_link(text_regex => qr/^(?:${name}:)?${title}/i);
  return ($link) ? get_response_id($link->url) : 0;
}

sub create_question {
  my ($rid, $name, $question) = @_;

  my $question_text = format_latex_for_mathjax($question->{question});
  my $answers       = scalar keys %{$question->{answers}};
  my $param_ref     = {};

  $agent->post(
    qq{$UMLESSONS_URL/inquiry/create/$UNIT_URL_NAME/$name}, {
      choice                            => 'multiple_choice',
      op                                => 'Save',
      question                          => $question_text,
      'multiple_choice:numberAnswers'   => $answers,
      'multiple_response:numberAnswers' => $answers,
      'question/resource'               => $rid,
      'question/align'                  => 'ABOVE',
    }
  );
  my $question_id = get_response_id($agent->response->previous->header('location'));

  if (exists $question->{resource}) {
    my $img_rid = find_resource($name, $question->{resource});

    $agent->post(
      qq{$UMLESSONS_URL/multiple_choice/update_content/$UNIT_URL_NAME/$name\$$question_id#}, [
        op                  => 'Save',
        question            => $question_text,
        section             => 'question',
        'question/resource' => $img_rid,
        'question/resource' => $rid,
        'question/align'    => 'BELOW'
      ]
    );
  }

  my $id = get_response_id($agent->response->previous->header('location'));
  $agent->post(
    qq{$UMLESSONS_URL/multiple_choice/update_settings/$UNIT_URL_NAME/$name\$${id}#}, {
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
  my ($id, $name, $correct_answer, $answers) = @_;

  my $answer_number = 1;
  foreach my $answer (sort keys %{$answers}) {
    my $roman       = lc(roman($answer_number));
    my $order       = qq{c$roman.$answer_number};
    my $answer_text = $answers->{$answer}->{text};
    my $resource_id = 'none';

    ## no tidy
    my $count = ()= $answer_text =~ /\$/g;
    ## use tidy
    if ($count > 1) {
      $answer_text =~ s/\$//g;
    }

    if (exists $answers->{$answer}->{resource}) {
      $resource_id = find_resource($name, $answers->{$answer}->{resource});
    }

    my $param_ref = [
      op                  => 'save',
      order               => $order,
      qq{order.$order}    => $order,
      response            => ($answer_text ne $EMPTY) ? format_latex_for_mathjax($answer_text) : $EMPTY,
      section             => qq{answers.c$roman},
      correct             => ($answer eq $correct_answer) ? 'TRUE' : 'FALSE',
      feedback            => $EMPTY,
      'response/align'    => 'LEFT',
      'response/resource' => $resource_id,
      'feedback/align'    => 'LEFT',
      'feedback/resource' => 'none',
    ];

    $agent->post(qq[$UMLESSONS_URL/multiple_choice/update_content/$UNIT_URL_NAME/$name\$${id}#answers.c$roman], $param_ref);

    say "Added answer $answer to question $id";
    $answer_number++;
  }

  return;
}

sub create_img_resource {
  return _create_resource('image', @_);
}

sub create_txt_resource {
  return _create_resource('text', @_);
}

sub _create_resource {
  my ($type, $name, $title, $resource) = @_;
  croak qq{Invalid resource type ($type)!} if $type !~ /^(?:image|text)$/;
  my $url = qq{$UMLESSONS_URL/resource/create/$UNIT_URL_NAME/$name};

  $agent->post(
    qq{$UMLESSONS_URL/resource/setup/$UNIT_URL_NAME/$name}, {
      choice => $type,
      op     => 'Continue...',
    }
  );

  my $param_ref = {
    choice          => $type,
    title           => $title,
    keywords        => $EMPTY,
    border          => '0',
    borderBgColor   => 'black',
    borderFillColor => 'none',
    op              => 'Save',
  };

  my $id;
  given ($type) {
    when (/text/) {
      $param_ref->{excerpt} = $resource;
      $agent->post($url, $param_ref);
      $id = get_response_id($agent->response->previous->header('location'));
    }
    when (/image/) {

      # FIXME some random bug server side is eating our uploads.
      #       for the time being upload by hand and find the resource
      #       that matches $title and return that id instead.
      #
      #       Well this poses a problem as the resources haven't been
      #       created yet. what a freaking mess.
      #
      # $param_ref->{upload_file} = $resource;
      # $agent->agent_alias('Windows IE 6');
      # $agent->form_name('fm');
      # map { $agent->field($_, $param_ref->{$_}) } keys %{$param_ref};
      # my $res = $agent->submit();

      $id = find_resource($name, $title);
    }
  }

  if ($agent->success) {
    say qq{Created resource ($title - $id) successfully};
  }

  return $id;
}

sub create_competencies_resource {
  my ($comps) = @_;

  my $json = sprintf
    qq{<!-- html -->\n<script type="text/javascript">\nvar competencies = %s\n</script>\n<!-- html -->},
    JSON::Any->to_json($comps_ref);

  return create_txt_resource($test->{lesson_name}, q{Competency Map}, $json);
}


#!/usr/bin/env perl

use Modern::Perl;
use WWW::Mechanize;
use Net::Netrc;
use Readonly;
use Data::Dumper;

Readonly::Scalar my $EMPTY         => q{};
Readonly::Scalar my $BANG          => q{!};
Readonly::Scalar my $WEBLOGIN_URL  => q{https://weblogin.umich.edu};
Readonly::Scalar my $COSIGN_CGI    => q{cosign-bin/cosign.cgi};
Readonly::Scalar my $UMLESSONS_URL => q{https://lessons.ummu.umich.edu};
Readonly::Scalar my $UNIT_URL      => q{https://lessons.ummu.umich.edu/2k/manage/unit/list_lessons/sph_algebra_assesment};
Readonly::Scalar my $DIRECTIONS    => q{Hello World};
Readonly::Scalar my $SUMMARY       => q{Goodbye World};

my $agent = get_login_agent();

create_lesson(q{lesson_name}, q{title});

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


  return $www;
}

sub create_lesson {
  my ($lesson_name, $title) = @_;

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
      name                  => $lesson_name,
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
    qq{$UMLESSONS_URL/2k/manage/lesson/update_content/sph_algebra_assesment/$lesson_name#directions}, {
      directionsText => $DIRECTIONS,
      op             => 'save',
      section        => 'directions',
    }
  );

  $agent->post(
    qq{$UMLESSONS_URL/2k/manage/lesson/update_content/sph_algebra_assesment/$lesson_name#summary}, {
      summaryText => $SUMMARY,
      op          => 'save',
      section     => 'summary',
    }
  );

  return;
}

sub create_resource {
}

sub create_

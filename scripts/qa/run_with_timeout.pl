#!/usr/bin/env perl

use strict;
use warnings;
use POSIX qw(WNOHANG setpgid);
use Time::HiRes qw(sleep);

my $seconds = shift @ARGV;
die "usage: run_with_timeout.pl <seconds> <command> [args...]\n"
  if !defined($seconds) || $seconds !~ /^\d+$/ || $seconds < 1 || !@ARGV;

my $child_pid = fork();
die "fork failed: $!\n" if !defined($child_pid);

if ($child_pid == 0) {
  setpgid(0, 0) == 0 or die "setpgid failed: $!\n";
  exec @ARGV or die "exec failed: $!\n";
}

sub stop_child_group {
  my ($signal) = @_;
  my $child_reaped = 0;

  my $group_alive = sub {
    return kill 0, -$child_pid;
  };
  my $reap_child = sub {
    return if $child_reaped;
    my $finished = waitpid($child_pid, WNOHANG);
    $child_reaped = 1 if $finished == $child_pid || $finished == -1;
  };

  kill $signal, -$child_pid if $group_alive->();

  for (1 .. 50) {
    $reap_child->();
    last if !$group_alive->();
    sleep 0.1;
  }

  # 직접 child가 먼저 끝나도 같은 process group의 손자 프로세스가 남을 수 있다.
  # grace period 뒤 group 전체가 살아 있으면 반드시 KILL한다.
  if ($group_alive->()) {
    kill 'KILL', -$child_pid;
  }
  waitpid($child_pid, 0) if !$child_reaped;
}

$SIG{ALRM} = sub {
  stop_child_group('TERM');
  exit 124;
};
$SIG{INT} = sub {
  stop_child_group('INT');
  exit 130;
};
$SIG{TERM} = sub {
  stop_child_group('TERM');
  exit 143;
};

alarm $seconds;
waitpid($child_pid, 0);
my $status = $?;
alarm 0;

exit 128 + ($status & 127) if $status & 127;
exit $status >> 8;

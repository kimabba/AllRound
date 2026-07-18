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
  kill $signal, -$child_pid;

  for (1 .. 50) {
    my $finished = waitpid($child_pid, WNOHANG);
    return if $finished == $child_pid;
    sleep 0.1;
  }

  kill 'KILL', -$child_pid;
  waitpid($child_pid, 0);
}

my $timed_out = 0;
$SIG{ALRM} = sub {
  $timed_out = 1;
  stop_child_group('TERM');
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

exit 124 if $timed_out;
exit 128 + ($status & 127) if $status & 127;
exit $status >> 8;

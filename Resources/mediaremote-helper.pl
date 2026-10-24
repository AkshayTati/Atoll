#!/usr/bin/perl
use strict;
use warnings;
use DynaLoader;

my $dylib = shift @ARGV
  or die "usage: mediaremote-helper.pl DYLIB [list|send BUNDLE COMMAND]\n";

my $command = shift @ARGV // 'list';
$ENV{ISLET_HELPER_COMMAND} = $command;

if ($command eq 'send') {
  my $bundle = shift @ARGV;
  die "missing bundle id\n" unless defined $bundle;
  my $code = shift @ARGV;
  die "missing command id\n" unless defined $code;
  $ENV{ISLET_HELPER_BUNDLE} = $bundle;
  $ENV{ISLET_HELPER_CODE} = $code;
}

my $handle = DynaLoader::dl_load_file($dylib, 0)
  or die "failed to load $dylib\n";
my $symbol = DynaLoader::dl_find_symbol($handle, 'islet_run')
  or die "missing islet_run symbol\n";

DynaLoader::dl_install_xsub('main::islet_run', $symbol);
islet_run();

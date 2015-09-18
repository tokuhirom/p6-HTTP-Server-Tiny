#!/usr/bin/env perl
use strict;
use warnings;
use utf8;
use 5.022000;
use autodie;

no warnings 'recursion';

# run server process by following command:
#   SINGLE_PROCESS=1 perl6-m --profile-filename=aaa.json --profile -Ilib bin/crustup --port=5000 eg/hello.psgi6
# call servers.
#    ab -n 1000 -c 1 http://localhost:5000/exit
# then, terminate proc.
#    http://localhost:5000/exit
#
# aggregate result:
#    perl author/moar-profiler-cli.pl < aaa.json

use JSON::XS;
use Data::Dumper;

my $json = join("",<>);
my $dat = decode_json($json);

my %id_rec_depth;
my %id_to_inclusive;
my %id_to_entries;
my %id_to_exclusive;

my %node_id_to_name;
my %node_id_to_file;
my %node_id_to_line;

my $walk; $walk = sub {
    my ($node) = @_;
    my $id = $node->{id};

    if (!$node_id_to_name{$id}) {
        $node_id_to_name{$id} = $node->{name} || '<anon>';
        $node_id_to_line{$id} = $node->{line} || '<unknown>';
        $node_id_to_file{$id} = $node->{file} || '<unknown>';
    }

    unless ($id_to_entries{$id}) {
        $id_to_inclusive{$id} = 0;
        $id_to_exclusive{$id} = 0;
        $id_rec_depth{$id} = 0;
    }

    $id_to_entries{$id} = $node->{entries};
    $id_to_exclusive{$id} += $node->{exclusive_time};

    if ($id_rec_depth{$id} == 0) {
        $id_to_inclusive{$id} += $node->{inclusive_time};
    }
    if ($node->{callees}) {
        $id_rec_depth{$id}++;
        for (@{$node->{callees}}) {
            $walk->($_);
        }
        $id_rec_depth{$id}--;
    }
};

my $root = $dat->[0]->{call_graph};

$walk->($root);


for my $id (sort { $id_to_inclusive{$a} <=> $id_to_inclusive{$b} } keys %id_to_entries) {
    say join("\t",
        $id_to_inclusive{$id},
        $id_to_exclusive{$id},
        $node_id_to_name{$id},
        $node_id_to_file{$id},
        $node_id_to_line{$id});
}


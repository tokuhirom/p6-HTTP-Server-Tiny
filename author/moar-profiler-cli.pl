#!/usr/bin/env perl
use strict;
use warnings;
use utf8;
use 5.022000;
use autodie;
use Getopt::Long;
use JSON::XS;
use Data::Dumper;
use Term::ANSIColor;
use List::Util qw/sum max/;

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

my $sort = 'inclusive';
GetOptions(
    's|sort=s' => \$sort,
    'r|reverse!' => \my $reverse,
    'c|callee=i' => \my $show_callee,
    'l|limit=i' => \my $limit,
);

our $CALLEE_DUMP_LEVEL = 0;

my $json = join("",<>);
my $dat = decode_json($json);

my %id_rec_depth;
my %id_to_inclusive;
my %id_to_entries;
my %id_to_exclusive;

my %node_id_to_name;
my %node_id_to_file;
my %node_id_to_line;

my %id_to_callee;

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
            $id_to_callee{$_->{id}}{$id}++;
            $walk->($_);
        }
        $id_rec_depth{$id}--;
    }
};

my $root = $dat->[0]->{call_graph};

$walk->($root);

my $total_inclusive = $root->{inclusive_time};
my $total_exclusive = sum values %id_to_exclusive;

my @ids = keys %id_to_inclusive;
if ($sort eq 'inclusive') {
    @ids = sort { $id_to_inclusive{$a} <=> $id_to_inclusive{$b} } @ids;
} elsif ($sort eq 'exclusive') {
    @ids = sort { $id_to_exclusive{$a} <=> $id_to_exclusive{$b} } @ids;
} else {
    die "unknown sort mode: '$sort'\n";
}
if ($reverse) {
    @ids = reverse @ids;
}

print "sorted by $sort\n";
printf("%s %s %s %s %s\n",
    'inclusive',
    'exclusive',
    'name',
    'file',
    'line');

my $i = 0;
for my $id (@ids) {
    my $line = sprintf("%s(%.2f%%) %s(%.2f%%) %s %s %s\n",
        $id_to_inclusive{$id},
        eval { ($id_to_inclusive{$id} / $total_inclusive)*100 } // '-',
        $id_to_exclusive{$id},
        eval { ($id_to_exclusive{$id} / $total_exclusive)*100 } // '-',
        $node_id_to_name{$id},
        $node_id_to_file{$id},
        $node_id_to_line{$id});
    if ($show_callee) {
        $line = colored(['green'], $line);
    }
    print $line;

    if ($show_callee) {
        dump_callee($id);
    }

    if (defined($limit) && $i++ > $limit) {
        last;
    }
}

sub dump_callee {
    my $id = shift;

    my @callee_ids = sort keys %{$id_to_callee{$id} // {}};
    for my $callee_id (@callee_ids) {
        printf "%s %s %s %s %s\n", (' ' x $CALLEE_DUMP_LEVEL), $callee_id, $node_id_to_name{$callee_id}, $node_id_to_file{$callee_id}, $node_id_to_line{$callee_id};
        if ($CALLEE_DUMP_LEVEL < $show_callee-1) {
            local $CALLEE_DUMP_LEVEL = $CALLEE_DUMP_LEVEL + 1;
            dump_callee($callee_id);
        }
    }
}


#!/usr/bin/env perl
use strict;
use warnings;
use IO::Socket::INET;
use JSON qw(encode_json);

$| = 1;

sub log_json {
    my ($level, $msg, $fields) = @_;
    $fields //= {};
    my %payload = (level => $level, msg => $msg, %{$fields});
    print STDOUT encode_json(\%payload), "\n";
}

log_json('INFO', 'server start', { port => 8088 });

my $server = IO::Socket::INET->new(
    LocalAddr => '0.0.0.0',
    LocalPort => 8088,
    Proto     => 'tcp',
    Listen    => SOMAXCONN,
    Reuse     => 1,
) or die "bind: $!\n";

while (my $client = $server->accept()) {
    my $req = <$client>;
    my ($path) = $req =~ m{GET (\S+)};
    if (!defined $path) {
        print $client "HTTP/1.1 400 Bad Request\r\nConnection: close\r\n\r\n";
    } elsif ($path eq '/health' || $path eq '/smoke') {
        print $client "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok";
    } elsif ($path eq '/work') {
        select(undef, undef, undef, 0.05);
        log_json('INFO', 'request complete', { route => '/work', duration_ms => 50 });
        my $body = '{"status":"ok"}';
        print $client "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: ",
          length($body), "\r\nConnection: close\r\n\r\n", $body;
    } else {
        print $client "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n";
    }
    close $client;
}

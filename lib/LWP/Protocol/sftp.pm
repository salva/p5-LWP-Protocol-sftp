package LWP::Protocol::sftp;

our $VERSION = '0.01';

# BEGIN { local $| =1; print "loading LWP::Protocol::sftp\n"; }


use strict;
use warnings;

use base qw(LWP::Protocol);
LWP::Protocol::implementor(sftp => __PACKAGE__);

require LWP::MediaTypes;
require HTTP::Request;
require HTTP::Response;
require HTTP::Status;
require HTTP::Date;

require URI::Escape;
require HTML::Entities;

use Net::SFTP::Foreign;
use Net::SFTP::Foreign::Constants qw(:flags :status);
use Fcntl qw(S_ISDIR);
use Sort::Key qw(keysort);

use constant PUT_BLOCK_SIZE => 8192;

sub request
{
    my($self, $request, $proxy, $arg, $size) = @_;

    # print __PACKAGE__."->request($self, $request, $proxy, $arg, $size)\n";

    LWP::Debug::trace('()');

    $size = 4096 unless defined $size and $size > 0;

    # check proxy
    defined $proxy and
	return HTTP::Response->new(HTTP::Status::RC_BAD_REQUEST,
				  'You can not proxy through the sftpsystem');

    # check method
    my $method = $request->method;

    # check url
    my $url = $request->url;

    my $scheme = $url->scheme;
    if ($scheme ne 'sftp') {
	return HTTP::Response->new(HTTP::Status::RC_INTERNAL_SERVER_ERROR,
				   "LWP::Protocol::sftp::request called for '$scheme'")
    }

    if (defined $url->password) {
	return HTTP::Response->new(HTTP::Status::RC_NOT_IMPLEMENTED,
				   "LWP::Protocol::sftp does not support text passwords for authentication")
    }

    my $host = $url->host;
    my $port = $url->port;
    my $user = $url->user;

    my $path  = $url->path;

    my $sftp = eval { Net::SFTP::Foreign->new(host => $host,
					      user => $user,
					      port => $port) };
    if ($@) {
	return HTTP::Response->new(HTTP::Status::RC_SERVICE_UNAVAILABLE,
				   "unable to establish ssh connection to remote machine ($@)")
    }

    # handle GET and HEAD methods

    my $response = eval {

	if ($method eq 'GET' || $method eq 'HEAD') {

	    my $stat = $sftp->do_stat($path);

	    # check if-modified-since
	    my $ims = $request->header('If-Modified-Since');
	    if (defined $ims) {
		my $time = HTTP::Date::str2time($ims);
		if (defined $time and $time >= $stat->mtime) {
		    return HTTP::Response->new(HTTP::Status::RC_NOT_MODIFIED,
					       "$method $path")
		}
	    }

	    # Ok, should be an OK response by now...
	    my $response = HTTP::Response->new(HTTP::Status::RC_OK);

	    # fill in response headers
	    $response->header('Last-Modified', HTTP::Date::time2str($stat->mtime));

	    if (S_ISDIR($stat->perm)) {         # If the path is a directory, process it
		# generate the HTML for directory
		my @ls = keysort { $_->{filename} } $sftp->ls($path);

		# Make directory listing
		my $pathe = $path . '/';
		my @lines = map {
		    my $fn=$_->{filename};
		    my $furl = URI::Escape::uri_escape($fn);
		    if (S_ISDIR($_->{a}->perm)) {
			$fn .= '/';
			$furl .= '/';
		    }
		    my $desc = HTML::Entities::encode($fn);
		    qq{<li><a href="$furl">$desc</a>}
		} @ls;

		# Ensure that the base URL is "/" terminated
		my $base = $url->clone;
		unless ($base->path =~ m|/$|) {
		    $base->path($base->path . "/");
		}
		my $html = join("\n",
				"<HTML>\n<HEAD>",
				"<TITLE>Directory $path</TITLE>",
				"<BASE HREF=\"$base\">",
				"</HEAD>\n<BODY>",
				"<H1>Directory listing of $path</H1>",
				"<UL>", @lines, "</UL>",
				"</BODY>\n</HTML>\n");

		$response->header('Content-Type',   'text/html');
		$response->header('Content-Length', length $html);
		$html = "" if $method eq "HEAD";

		return $self->collect_once($arg, $response, $html);
	    }

	    # path is a regular file
	    my $file_size = $stat->size;
	    $response->header('Content-Length', $file_size);
	    LWP::MediaTypes::guess_media_type($path, $response);

	    # read the file
	    if ($method ne "HEAD") {
		my $fh = $sftp->do_open($path);
		my $off = 0;

		$response = $self->collect($arg, $response, sub {
					       if ($off < $file_size) {
						   my $content = $sftp->do_read($fh, $off, $size);
						   my $status = $sftp->status;
						   my $bytes = length $content;
						   $off += $bytes;
						   return \$content if $bytes > 0;
					       }
					       return \ "";
					   });
		$sftp->do_close($fh);
	    }
	    return $response;
	}

	# handle PUT method
	if ($method eq 'PUT') {
	    my $fh = $sftp->do_open($path, SSH2_FXF_WRITE | SSH2_FXF_CREAT | SSH2_FXF_TRUNC);

	    my $content = $request->content;
	    my $len = length $content;
	    my $off = 0;

	    while ($off<$len) {
		my $status = $sftp->do_write($fh, $off, substr($content, $off, PUT_BLOCK_SIZE ));
		$status == SSH2_FX_OK or die "write failed";
		$off+=PUT_BLOCK_SIZE
	    }

	    $sftp->do_close($fh);

	    #return HTTP::Response->new(&HTTP::Status::RC_INTERNAL_SERVER_ERROR,
	    #                          "Cannot write file '$path': $!");
	
	    return HTTP::Response->new(HTTP::Status::RC_OK);
	}

	# unsupported method
	return HTTP::Response->new(HTTP::Status::RC_BAD_REQUEST,
				  'Library does not allow method ' .
				  "$method for 'sftp:' URLs");
    };

    if ($@) {
	my ($status, $msg)=$sftp->status;
	return HTTP::Response->new(HTTP::Status::RC_INTERNAL_SERVER_ERROR,
				   "sftp error: $msg ($status) - $@");
    }
    return $response;
}

1;
__END__

=head1 NAME

LWP::Protocol::sftp - adds support for SFTP uris to LWP::Protocol package

=head1 SYNOPSIS

  use LWP::Simple;
  my $content = get('sftp://me@myhost:29/home/me/foo/bar');


=head1 DESCRIPTION

After this module is installed, LWP can be used to access remote file
systems via SFTP.

This module is based on L<Net::SFTP::Foreign>.

=head1 SEE ALSO

L<LWP> and L<Net::SFTP::Foreign> documentation. L<ssh(1)>, L<sftp(1)>
manual pages. OpenSSH web site at L<http://www.openssh.org>.

=head1 AUTHOR

Salvador FandiE<ntilde>o <sfandino@yahoo.com>

=head1 COPYRIGHT

Copyright (C) 2005 by Salvador FandiE<ntilde>o.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.4 or,
at your option, any later version of Perl 5 you may have available.

=cut

use 5.008;
use ExtUtils::MakeMaker;

WriteMakefile( NAME => 'LWP::Protocol::sftp',
	       VERSION_FROM => 'lib/LWP/Protocol/sftp.pm',
	       PREREQ_PM => { LWP => 0,
			      URI::sftp => 0,
			      Net::SFTP::Foreign => '1.40' },
	       ABSTRACT => 'adds SFTP support to LWP',
	       AUTHOR => 'Salvador Fandino <sfandino@yahoo.com>');



use 5.008;
use ExtUtils::MakeMaker;

WriteMakefile( NAME => 'LWP::Protocol::sftp',
	       VERSION_FROM => 'lib/LWP/Protocol/sftp.pm',
	       PREREQ_PM => { Sort::Key => 0.14,
			      LWP => 0,
			      URI::sftp => 0,
			      Net::SFTP::Foreign => 0.58 },
	       ABSTRACT => 'adds SFTP support to LWP',
	       AUTHOR => 'Salvador Fandino <sfandino@yahoo.com>');



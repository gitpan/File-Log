#
#  Log.pm
#
#  Synopsis:            see POD at end of file
#
#
#-- The package
#------------------
package File::Log;

$VERSION = sprintf("%d.%02d", q'$Revision: 1.1 $' =~ /(\d+)\.(\d+)/);
#------------------
#
my $CVS_Log = q{

$Log: ibm_accruals.pl,v $
Revision 1.1  2004/07/18 18:20:11  greg
- Initial release to CPAN

};
#
#

#-- Required Modules
#-------------------
use vars qw($_errStr $_expText);
use 5.006;
use strict;
use warnings;
use Carp qw(confess);
use Symbol;


#-- Global Variables
#-------------------
$_errStr  = '';
$_expText = '';   # Used to store all text sent to exp() if storeExpText flag set


# Constructor new
sub new
{
	my $proto  = shift;
	my $class  = ref($proto) || $proto;

	my $self = {};
	bless($self, $class);

	# Run initialisation code
	return $self->_init(@_);
}

sub _init
{
	my $self = shift;

	# Set some initial default values
	$self->{'logfilemode'}     = '>>';
	$self->{'debug'}           = 4;
	$self->{'pidstamp'}        = 0;
	$self->{'datetimestamp'}   = 0;
	$self->{'stderrredirect'}  = 1;
	$self->{'defaultfile'}     = 0;
	$self->{'_logFileOpen'}    = 0;
	$self->{'_fileHandle'}     = gensym;
	$self->{'storeexptext'}    = 0;
	$self->{'logfiledatetime'} = 0;
	$self->{'_expCnt'}         = 0;



	# Have we been passed anything
	if (@_ != 0)
	{
		# We are expecting our configuration to come as an anonymous hash
		if (ref $_[0] eq 'HASH')
		{
   			my $hash=$_[0];

			foreach my $key (keys %$hash)
			{
			    $self->{lc($key)}=$hash->{$key};
   			}
		}
		else
		{
			(
				$self->{'logfilename'},
				$self->{'logfilemode'},
				$self->{'debug'},
				$self->{'appname'},
				$self->{'pidstamp'},
				$self->{'datetimestamp'},
				$self->{'stderrredirect'},
				$self->{'defaultfile'},
				$self->{'storeexptext'},
				$self->{'logfiledatetime'},
			) = @_;
		}
	}

	# Do we have a name for the log file.
	# If no Do we have the name of the application - since this will form the basis of the log file name
	unless (defined($self->{'logfilename'}) && $self->{'logfilename'} ne '' && defined($self->{'appname'}) && $self->{'appname'} ne '')
	{
		use FindBin qw($RealBin $RealScript);

		# Get the real location and name of the application and strip unwanted extensions
		(my $appName = "$RealBin/$RealScript") =~ s/\.pl$|\.bat$|\.cmd$//i;

		$self->{'appname'} = $appName;

		$self->{'logfilename'} = $self->{'appname'}.'.log' unless (defined($self->{'logfilename'}) && $self->{'logfilename'} ne '');
	}

	# Open the logfile
	return $self->_open;
}



sub _open
{
	my $self = shift;

	# If the current log file is open close it.
	close($self->{'_fileHandle'}) if($self->{'_logFileOpen'});

	my $logFileName = $self->{'logfilename'};
	if ($self->{'logfiledatetime'})
	{
		#-- Current day & time
		my ($tm_sec, $tm_min, $tm_hr, $tm_day, $tm_month, $tm_year, undef, undef, undef) = localtime();
		my $file_DT = sprintf "%d%02d%02d-%02d%02d%02d", ($tm_year + 1900), ($tm_month + 1), $tm_day, $tm_hr, $tm_min, $tm_sec;

		$logFileName =~ s/(\.[^.]*?$)/"_$file_DT$1"/e;
	}

	# Restore the log file name
	$self->{'logfilename'} = $logFileName;


	# Actually open the log file
	unless (open($self->{'_fileHandle'}, $self->{'logfilemode'}.$logFileName))
	{
		$_errStr = "Could not open '$logFileName' in mode '$self->{'logfilemode'}': $1";
		$self->{'_logFileOpen'} = 0;
		return undef;
	}

	# Set the internal flag to indicate that the file is open
	$self->{'_logFileOpen'} = 1;
	$_errStr = '';

	local *LF = $self->{'_fileHandle'};

	# Do we need to redirect stderr to the logfile
	if ($self->{stderrredirect})
	{
		#close STDERR;
		unless (open(STDERR, '>&LF'))
		{
			# There was an error, log it to the file and set the package error string
			my ($pkg, $file, $line) = caller;

			my $err = "Error Package: $pkg, File: $file, Line: $line\n";
			$err   .= "Close and dup of STDERR to log file '$logFileName' failed: $! ";

			print {$self->{'_fileHandle'}} $err."\n";
			$_errStr = $err;
		}
	}

	# Need to redirect STDOUT to the log file if select is used to set the default file handle
	if ($self->{'defaultfile'})
	{
		unless (open(STDOUT, '>&LF'))
		{
			# There was an error, log it to the file and set the package error string
			my ($pkg, $file, $line) = caller;

			my $err = "Error Package: $pkg, File: $file, Line: $line\n";
			$err   .= "Close and dup of STDOUT to log file '$logFileName' failed: $!";

			print LF $err."\n";
			$_errStr = $err;
		}
	}

	# Set autoflush
	my $oldSelect = select LF;
	$| = 1;
	select $oldSelect unless ($self->{'defaultfile'});

	# Make the log file readable by all, modifiable by the owner
	chmod 0644, $logFileName;

	return $self;
}



sub msg
{
	my $self = shift;

	my $now = '';
	my $pid = '';


	# Do we have enough parameters
	@_ > 1 or confess 'Usage: log->msg(debugLevel, "message string"|@messageStrings)';

	# If the supplied debug level is greater than the current debug value return
	return if shift > $self->{'debug'};

	my $str = join('', @_);

	# Set the timestamp if required
	$now = scalar(localtime()).'   ' if ($self->{'datetimestamp'});

	# Set the process ID if required
	$pid = $$.' ' if ($self->{'pidstamp'});

	# Format the string and print it to the logfile
	$str =~ s/\n(?=.)/\n$pid$now/gs;
	print {$self->{'_fileHandle'}} "$pid$now".$str;
}



sub exp
{
	my $self = shift;

	my $now = '';
	my $pid = '';

	# Do we have enough parameters
	@_ >= 1 or confess 'Usage: log->msg(debugLevel, "message string"|@messageStrings)';

	# Keep track of the number of exception calls for this object
	$self->_incExpCnt;

	my $str = join('', @_);

	# Set the timestamp if required
	$now = scalar(localtime()).'   ' if ($self->{'datetimestamp'});

	# Set the process ID if required
	$pid = $$.' ' if ($self->{'pidstamp'});

	# Format the string and print it to the logfile
	$str =~ s/\n(?=.)/\n** $pid$now/gs;
	print {$self->{'_fileHandle'}} "** $pid$now$str";

	# Append the sting if store mode is true
	$_expText .= "** $pid$now$str" if $self->{'storeexptext'};
}



sub close
{
	my $self = shift;

	close *{$self->{'_fileHandle'}} if (ref($self->{'_fileHandle'}) eq 'GLOB' && $self->{'_logFileOpen'});
	$self->{'_logFileOpen'} = 0;
}


sub PIDstamp
{
	my $self = shift;
	my $prev = $self->{'pidstamp'};
	if (@_)
	{
		$self->{'pidstamp'} = ($_[0] ? 1: 0);
	}
	return $prev;
}



sub dateTimeStamp
{
	my $self = shift;
	my $prev = $self->{'datetimestamp'};
	if (@_)
	{
		$self->{'datetimestamp'} = ($_[0] ? 1: 0);
	}
	return $prev;
}



sub debugValue
{
	my $self = shift;
	my $prev = $self->{'debug'};
	if (@_)
	{
		# Update the debug value if it's greater than zero
		$self->{'debug'} = int($_[0]) if ($_[0] >= 0);
	}
	return $prev;
}



sub expText
{
	my $self = shift;
	my $prev = $self->{'storeexptext'};
	if (@_)
	{
		# Update the storeexptext value
		$self->{'storeexptext'} = $_[0];
	}
	return $prev;
}



sub getExpText
{
	my $self = shift;

	# Return undef if we don't have storeExpText flag set
	return(wantarray ? () : undef) unless $self->{'storeexptext'};

	return(wantarray ? ($_expText) : $_expText);
}



sub clearExpText
{
	my $self = shift;

	$_expText = '';
}

sub expCnt         { return $_[0]->{_expCnt};  }
sub _incExpCnt     { $_[0]->{_expCnt}++; }
sub getLogFileName { return $_[0]->{'logfilename'}; }


#####################################################################
# DO NOT REMOVE THE FOLLOWING LINE, IT IS NEEDED TO LOAD THIS LIBRARY
1;


__END__

## POD DOCUMENTATION ##


=head1 NAME

Log - A simple Object Orientated Logger

=head1 SYNOPSIS

 use Log;

 # Pretty format, all the parameters
 my $log = Log->new({
   debug           => 4,                   # Set the debug level
   logFileName     => 'myLogFile.log',     # define the log filename
   logFileMode     => '>',                 # '>>' Append or '>' overwrite
   dateTimeStamp   => 1,                   # Timestamp log data entries
   stderrRedirect  => 1,                   # Redirect STDERR to the log file
   defaultFile     => 1,                   # Use the log file as the default filehandle
   logFileDateTime => 1,                   # Timestamp the log filename
   appName         => 'myApplicationName', # The name of the application
   PIDstamp        => 1,                   # Stamp the log data with the Process ID
   storeExpText    => 1,                   # Store internally all exp text
 });

 # Minimal instance, logfile name based on application name
 my $log = Log->new();

 # Typical usage, set the debug level and log filename (say from a config file)
 my $log = Log->new({ debug => $debugLevel, logFileName => $logFileName, });

 # Print message to the log file if the debug is >= 2
 $log->msg(2, "Add this to the log file if debug >= 2 \n");

 # Print an exception (error) message to the log file
 $log->exp("Something went wrong\n");

 # Close the log file (optional at exit)
 $log->close();

 # Change the debug level, capturing the old value
 $oldDebugValue     = $log->debugValue($newDebugValue);

 $currentDebugValue = $log->debugValue();

 # Get all the exceptions text (so you can do something with all the errors, eg email them)
 $allExceptions     = $log->getExpText();

 $numberErrors      = $log->expCnt();        # How many times has $log->exp been called

=head1 DESCRIPTION

I<Log> is a class providing methods to log data to a file.  There are a number
of parameters that can be passed to allow configuration of the logger.

=head1 REQUIRED MODULES

Carp (confess is used), FindBin and Symbol;

=head1 METHODS

There are no class methods, the object methods are described below.
Private class method start with the underscore character '_' and
should be treated as I<Private>.

=head2 new

Called to create a I<Log> object.  The following optional named parameters can be
passed to the constructor via an anonymous hash:

=over 4

=item debug

Used to set the debug level.  The default level is 9.  The debug level is used by
other methods to determine if data is logged or ignored.  See C<msg> and C<exp> methods.

=item logFileName

Defines the path and name of the log file that is written too.  If not defined then
the value of appName with '.log' appended is used.  If appName is not defined in the
constructor then BinFind is used to determine the name of the application.

=item logFileMode

Used to determine if the log file is overwritten or appended too.
Default is append.  Valid value are '>' for overwrite and '>>' for append.

=item dateTimeStamp

If true (default is false), then each entry written to the log file using the C<msg> and
C<exp> methods has the current date and time prepended to the data.

=item stderrRedirect

If true (default is true), then redirect STDERR to the log file.

=item defaultFile

If true (default is false), then select the log file as the default output file.

=item logFileDateTime

If true (default is false), then include the date and time into the name of the log file
just before the '.log'.  The format of the date and time used is _YYYYMMDD-HHMMSS

=item appName

If logFileName is not defined then the appName is used as the basis of the log file.
If appName is not defined then the FindBin module is use to determine the name of the
application and is stored within the appName hash variable.

=item PIDstamp

If true (default is false), then the Process ID is prepended to the data written to the log file
by the C<msg> and C<exp> methods.  This is handy when there are more than one processes writting
to the same log file.

=item storeExpText

If true (default is false), then any data written with the C<exp> method is also stored internally for
later retrival with the C<getExpText> method.  The stored data can also be cleared with the C<clearExpText>
method.  This can be useful if there may be multiple exceptions which you then want to report on (other
than in the log file) as one text string.

=back


=head2 _init & Private methods

I<Private> method to initialise the object on construction.  Called by C<new()>.
All I<Private> methods start with B<_> and should be treated as PRIVATE.  No other
private methods are documented (since they are private).

=head2 msg

The C<msg> method is used to log a message to the log file.  The first B<POSITIONAL> argument
to C<msg> is the "debug level" at which the message should be added to the log file if the instance
"debug value" is greater than or equal to the "debug level".

The second and optional subsiquent arguments are treated as text to print to the log file.

eg.  $log->msg(2, "Printed to log file if 'debug' is greater than or equal to 2 \n");

B<Note> that newline characters are B<not> automatically appended by this method.

=head2 exp

C<exp> is used to report exceptions.  There is no "debug level" parameter,
just one or more text strings which are printed to the log file.  The text printed
has "**" prepended to each line (this occurs before prepended timestamp or PID values).

B<Note> that newline characters are B<not> automatically appended by this method.

=head2 close

Closes the file handle associated with the log file.

=head2 DESTROY

C<DESTROY> is defined and closes the file handle associated with the log file.


=head2 PIDstamp

The C<PIDstamp> method can be used to set or get the value of the I<PIDstamp> instance variable.
If called without parameters, the current value of the I<PIDstamp> instance variable is returned.
If called with a parameter, the parameter is used to set the I<PIDstamp> instance variable and the
previous value is returned.

Refer to the C<new> method for further information.

=head2 dateTimeStamp

The C<dateTimeStamp> method can be used to set or get the value of the I<dateTimeStamp> instance variable.
If called without parameters, the current value of the I<dateTimeStamp> instance variable is returned.
If called with a parameter, the parameter is used to set the I<dateTimeStamp> instance variable and the
previous value is returned.

Refer to the C<new> method for further information.


=head2 debugValue

The C<debugValue> method can be used to set or get the value of the I<debugValue> instance variable.
If called without parameters, the current value of the I<debugValue> instance variable is returned.
If called with a parameter, the parameter is used to set the I<debugValue> instance variable and the
previous value is returned.

Refer to the C<new> method for further information.

=head2 expText

The C<expText> method can be used to set or get the value of the I<storeexptext> instance variable.
If called without parameters, the current value of the I<storeexptext> instance variable is returned.
If called with a parameter, the parameter is used to set the I<storeexptext> instance variable and the
previous value is returned.

Refer to the C<new> method for further information.

=head2 getExpText

The C<expText> method is used to retreive the stored value of the instance "Exception Text".

=head2 clearExpText

The C<clearExpText> method is used to clear the stored value of the instance "Exception Text".

=head2 expCnt

The C<expCnt> method is used to retreive the number of times that the exp method has been called for this object.

=head2 getFileName

The C<getFileName> method is used to retreive the actual log file name used for this object.

=head1 PROPERTIES

see the C<new> method.

=head1 KNOWN ISSUES

none

=head1 AUTHOR

Greg George, IT Technology Solutions P/L, Australia
Mobile: +61-404-892-159, Email: gng@cpan.org

=head1 LICENSE

Copyright (c) 1999- Greg George. All rights reserved. This
program is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=head1 CVS ID

$Id: Log.pl,v 1.1 2004/07/18 18:20:11 gxg6 Exp $

=cut


#---< End of File >---#
#!/usr/bin/perl

# yum install perl-Crypt-SSLeay
# yum install perl-RPC-XML
# http://www.softwaretestingconcepts.com/test-automation-using-testlink-xmlrpc-api-steps-and-sample-python-client-program
# http://search.cpan.org/~rjray/RPC-XML-0.71/
# http://jetmore.org/john/misc/phpdoc-testlink193-api/TestlinkAPI/TestlinkXMLRPCServer.html

use strict;

use RPC::XML;
use RPC::XML::Client;
use Data::Dumper;

my $dumpRaw    = 0;
# !!! You have to change all three of these to valid local settings to get this to work:
#my $testServer  = 'https://localhost/testlink/lib/api/xmlrpc.php';
#my $APIKey      = 'PUT_YOUR_API_ACCESS_KEY_IN_HERE';
#my $projectName = 'PUT_THE_NAME_OF_YOUR_PROJECT_HERE';

my $resp;
my $method;
my $options;
my $log      = -t STDIN ? 1 : 0; # only log if we're being run via a term
my %statuses = ('passed' => 'p', 'failed' => 'f', 'blocked' => 'b');

my $planName    = shift || die "Need Test Plan name to continue\n";

my $client = RPC::XML::Client->new($testServer);

#############
# Confirm test plan exists, get planID
$resp = $client->send_request('tl.getTestPlanByName', {
	'devKey' => $APIKey, 'testprojectname' => $projectName, testplanname => $planName
});
if (isResponseError($resp)) {
	die "An error occurred in getTestPlanByName ($main::apiLastResponseCode): $main::apiLastResponseString\n";
}
#print Dumper($resp);
my $projectID = $resp->value->[0]{testproject_id};
my $planID    = $resp->value->[0]{id};
print "Found planID = $planID, projectID = $projectID\n" if ($log);


############
# In the future, get all builds, pick the right one if it exists, or create new.
# For now though, just assign all tests to the 'HEAD' build
$resp = $client->send_request('tl.getBuildsForTestPlan', {
	'devKey' => $APIKey, 'testplanid' => $planID
});
if (isResponseError($resp)) {
	die "An error occurred in getBuildsForTestPlan ($main::apiLastResponseCode): $main::apiLastResponseString\n";
}
#print Dumper($resp);
my $buildID = $resp->value->[0]{id};
print "Found buildID = $buildID\n" if ($log);


###############
# Get all available test plan platforms.  This is kind of simple right now.  For now, if test runner is on linux, we will run
# any test case assigned to a plan with "Linux" in it, and same with Windows.  In future we probably want to filter
# on specific os releases and architectures
$resp = $client->send_request('tl.getTestPlanPlatforms', {
	'devKey' => $APIKey, 'testplanid' => $planID
});
if (isResponseError($resp)) {
	die "An error occurred in getTestPlanPlatforms ($main::apiLastResponseCode): $main::apiLastResponseString\n";
}
#print Dumper($resp);
my %platformInfo = ();
foreach my $platform (@{$resp->value()}) {
	$platformInfo{$platform->{id}} = $platform;
}

#################
# Now get all test cases in the test plan.
$resp = $client->send_request('tl.getTestCasesForTestPlan', {
	'devKey' => $APIKey, 'testplanid' => $planID,
});
if (isResponseError($resp)) {
	die "An error occurred in getTestCasesForTestPlan ($main::apiLastResponseCode): $main::apiLastResponseString\n";
}
#print Dumper($resp);
my $respData  = $resp->value();
my %testCases = ();
# manually filter the test cases in the test plan against our currently selected platform
foreach my $caseID (keys %$respData) {
	foreach my $platformID (keys %{$respData->{$caseID}}) {
	#	if ($platformID eq $platformInfo{id} && $respData->{$caseID}{$platformID}{active} == 1) {
			$testCases{$caseID}{$platformID} = $respData->{$caseID}{$platformID};
	#	}
	}
}
#print Dumper(\%testCases);
print "Found ", scalar(keys(%testCases)), " test cases to run\n" if ($log);


###########################
# Now we loop and execute
my %tcResults = ();
foreach my $caseID (keys %testCases) {
	$resp = $client->send_request('tl.getExecutionResults', {
		'devKey' => $APIKey, 'testplanid' => $planID, 'testcaseid' => $caseID, 'numexecs' => 2,
	});
	if (isResponseError($resp)) {
		die "An error occurred in getExecutionResult ($main::apiLastResponseCode): $main::apiLastResponseString\n";
	}
	$tcResults{$caseID}{results} = $resp->value();
	$tcResults{$caseID}{configs} = getCaseConfigs($testCases{$caseID}{(keys(%{$testCases{$caseID}}))[0]}{summary});
	#print Dumper($resp);
}

# this is super quick and dirty.  Long term I would like to see an email that has an attachment which is a CSV file
# with values like this:
# package,component,testScript,platform,ExecDate,Status
# CoreDevice,Categories,Categories.t,server - CentOS 5.5 x86_64,2012-03-27 15:31:03,failed
# and with an easily-readible body that includes HTML like the following (only include lines for case/platform
# pairs that have changed status:
# TCID,TestScript,Platform,prevExecTime,lastExecTime
# 1234,codeDevice-ui/Categories.t,server - CentOS 5.5 x86_64,2012-03-26 14:31:03,2012-03-27 15:31:03
# the key to the HTML in the body is that the BGcolor for the last two cells will indicate the status of
# that test run (green = passed, red = failed, blue = blocked, black = not run).  This allows an easily-scannable
# list of _changed_ test cases.

# For now though, just use text.  Also ignore platform for right now.
foreach my $caseID (keys %tcResults) {
	my $r = $tcResults{$caseID}{results};
	my $c = $tcResults{$caseID}{configs};
	# skip if it's never been run
	next if ($r->[0]{id} == -1);
	# skip if there's not a change in the results
	next if ($r->[0]{status} eq $r->[1]{status});
	
	#print "$caseID $tcResults{$caseID}{configs}{TestScript} $r->[1]{status} -> $r->[0]{status}\n";
	printf "%-8s %6s %s\n               %3s %20s -> %3s %20s\n",
		$caseID,
		"$r->[1]{status} -> $r->[0]{status}",
		$c->{TestScript},
		$r->[1]{platform_id}, $r->[1]{execution_ts},
		$r->[0]{platform_id}, $r->[0]{execution_ts};
}

exit;


# take a case's summary field and return a ref to a hash containing key->value pairs.
# the summary field might look like this:
#<div>
#<div>TestScript: coreAAA-ui/Users.t</div>
#<div>TestType: Standard</div>
#</div>
sub getCaseConfigs {
	my $summary = shift;
	my $null    = chr(0);
	my %config  = ();
	
	$summary =~ s|</div>\n<div>|$null|smg;
	$summary =~ s|</?div>|$null|g;
	$summary =~ s|$null{2,}|$null|;
	$summary =~ s|^$null+||;
	$summary =~ s|$null+$||;
	
	foreach my $pair (split(/$null/, $summary)) {
		next if ($pair =~ m|^\s*$|); # silently skip blank lines
		$pair =~ s|<[^>]+>||g;
		$pair =~ s|\n||gsm;
		if ($pair !~ m|^\w+:\s|) {
			print STDERR "saw config line '$pair', can normalize to 'key: value', skipping\n";
			next;
		}
		else {
			my($k,$v) = split(/:\s+/, $pair, 2);
			$config{$k} = $v;
		}
	}
	
	return(\%config);
}

# takes a response from an API call and tells you if it is an error or not.
# returns one of the following:
# 0 - no error, we have data in the object
# 1 - API error - we received an error in the API response itself
# 2 - unknown local error
# 3 - unknown local HTTP level error (bad URL, remote host offline, etc)
# 4 - XMLRPC fault (for instance, incorrect RPC method name)
# 5 - unknown API response type (no data in response, unsure if this error type exists)
# 6 - code error in this module - shouldn't happen
# Also sets:
#    $main::apiLastResponseCode  - return code as described above
#    $main::apiLastResponseString - a text string describing the last api response (typically
#                                   something like the description above, plus any error text
#                                   that might have been returned by the tools
sub isResponseError {
	my $apiResp = shift;
	
	my $code = \$main::apiLastResponseCode;
	my $text = \$main::apiLastResponseString;
	
	$$code = 6;
	$$text = "unknown subroutine error";
	
	if (!$apiResp) {
		$$code = 2;
		$$text = "Unknown local error";
		#print STDERR "Request failed, exiting\n";
		#exit 1;
	}
	elsif (!ref($apiResp)) {
		# can get this by using incorrect url (I added "2" to the end of the URL)
		$$code = 3;
		$$text = "Local request error: $apiResp";
	}
	elsif ($apiResp->is_fault) {
		# can get this by using an incorrect method (I changed method to "getTestPlanByName2")
		#print STDERR "XMLRPC Fault: ", $resp->value->{faultCode}, ": ", $resp->value->{faultString}, "\n";
		#exit 3;
		$$code = 4;
		$$text = 'XMLRPC Fault: ' . $resp->value->{faultCode} . ': ' . $resp->value->{faultString};
	}
	else {
		my $respData = $resp->value;
		
		#print Dumper($respData), "\n";
		
		# note every valid response returns an array ref for data (see getTestCasesForTestPlan), so
		# split our error checking
		if (ref($respData) eq 'ARRAY') {
			if (scalar(@$respData) == 0) {
				# not sure if this is a real condition or not
				#print STDERR "Unexpected response from server: No objects in response\n";
				#exit 4;
				$$code = 5;
				$$text = "Unexpected response from server: No objects in response";
			}
			# there's no single "API Error" flag, this is the best test I could come up with
			# It is an API error response if:
			#  - the data is an array ref
			#  - the first element in the array is a hash ref
			#  - that hash has exactly two keys
			#  - the two keys are {code} and {message}
			# One interesting thing to note is that you can have two error objects (for instance, if you make a
			# getTestPlanByName call with an invalid API Key, you will get two errors, the first will be "Invalid
			# API Key" and the second will be "Test Plan Not Found").  It appears that the first is the most relevant,
			# so I'll be using it as if it were the sole error
			#elsif (isError($respData)) {
			elsif (ref($respData->[0]) eq 'HASH' && scalar(keys(%{$respData->[0]})) == 2 &&
					exists($respData->[0]{code}) && exists($respData->[0]{message})) {
				# simulate by passing in a plan name that doesn't exist
				#print "Unable to find testplan '$planName': ($respData->[0]{code}) $respData->[0]{message}\n";
				#exit 5;
				$$code = 1;
				$$text = "($respData->[0]{code}) $respData->[0]{message}";
			}
			# turing off the checking for this state, I don't think it's a global error condition
			#elsif (scalar(@$respData) > 1) {
			#	# not sure if this is a real error state or not
			#	print STDERR "Something unexpected happened - received >1 items in response to getTestPlanByName:\n", Dumper($respData), "\n";
			#	exit 6;
			#}
			else {
				$$code = 0;
				$$text = "";
			}
		}
		# I haven't seen very many example of the data key being a hash, assume it's always ok for now
		elsif (ref($respData) eq 'HASH') {
			$$code = 0;
			$$text = "";
		}
	}
	return $$code;
}

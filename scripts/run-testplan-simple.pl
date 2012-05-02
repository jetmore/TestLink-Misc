#!/usr/bin/perl

# This is a sanitized version of the "nightly test runner" I bashed up for my company.
# It is very unlikely to be usable verbatim, but it shows some fundamental concepts:
#	- how to interact w/ TestLink XMLRPC api with a perl client
#	- an attempt at an error checking function for api responses
#	- a method for storing external test information in test cases
#	- how to post results back to TestLink

# -- John Jetmore, 2012

# yum install perl-Crypt-SSLeay
# yum install perl-RPC-XML
# http://www.softwaretestingconcepts.com/test-automation-using-testlink-xmlrpc-api-steps-and-sample-python-client-program
# http://search.cpan.org/~rjray/RPC-XML-0.71/
# http://jetmore.org/john/misc/phpdoc-testlink193-api/TestlinkAPI/TestlinkXMLRPCServer.html

use strict;

use RPC::XML;
use RPC::XML::Client;
use Data::Dumper;

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
#print Dumper($resp); # uncomment to see what the raw response looks like
my $projectID = $resp->value->[0]{testproject_id};
my $planID    = $resp->value->[0]{id};
print "Found planID = $planID, projectID = $projectID\n" if ($log);


############
# This just picks the first build returned and uses it.  Errors if no build available
# for test plan.
$resp = $client->send_request('tl.getBuildsForTestPlan', {
	'devKey' => $APIKey, 'testplanid' => $planID
});
if (isResponseError($resp)) {
	die "An error occurred in getBuildsForTestPlan ($main::apiLastResponseCode): $main::apiLastResponseString\n";
}
#print Dumper($resp); # uncomment to see what the raw response looks like
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
#print Dumper($resp); # uncomment to see what the raw response looks like
my %platformInfo = ();
# This heuristic was specific to my company's use.  Tailor to taste.
foreach my $platform (@{$resp->value()}) {
	if ($^O eq 'linux' && ($platform->{name} =~ /\bCentOS\b/i || $platform->{name} =~ /\bLinux\b/i)) {
		%platformInfo = %$platform;
		last;
	}
	elsif ($^O eq 'windows' && $platform->{name} =~ /\bWindows\b/i) {
		%platformInfo = %$platform;
		last;
	}
}
if (!$platformInfo{id}) {
	die "No available platform matched current platform\n" .
	    "Current: $^O\n" .
	    "Available: \n" . Dumper($resp->value());
}
print "Found platform = $platformInfo{id}, $platformInfo{name}\n" if ($log);


#################
# Now get all test cases in the test plan.
$resp = $client->send_request('tl.getTestCasesForTestPlan', {
	'devKey' => $APIKey, 'testplanid' => $planID,
});
if (isResponseError($resp)) {
	die "An error occurred in getTestCasesForTestPlan ($main::apiLastResponseCode): $main::apiLastResponseString\n";
}
#print Dumper($resp); # uncomment to see what the raw response looks like
my $respData  = $resp->value();
my %testCases = ();
# manually filter the test cases in the test plan against our currently selected platform
foreach my $caseID (keys %$respData) {
	foreach my $platformID (keys %{$respData->{$caseID}}) {
		if ($platformID eq $platformInfo{id} && $respData->{$caseID}{$platformID}{active} == 1) {
			$testCases{$caseID}{$platformID} = $respData->{$caseID}{$platformID};
		}
	}
}
#print Dumper(\%testCases);
print "Found ", scalar(keys(%testCases)), " test cases to run\n" if ($log);


###########################
# Now we loop and execute
foreach my $caseID (keys %testCases) {
	
	# As far as I can tell there's no real standard for how external test information is stored
	# in a testlink testcase.  We chose to pursue:
	#	1) 1 external test script per test case
	#	2) external test "configs" are stored in the testcase's "summary" field
	#	3) configs are:
	#		- one config per line
	#		- line format is KEY: VALUE
	#	4) Specific keys:
	#		- TestScript - complete path, including executable, of external test script
	#		- TestScriptOptions - Any command line options for TestScript
	#		- TestType - free text right now, but allow us a way to tell the test executor to run
	#		             different tests
	foreach my $platformID (keys %{$testCases{$caseID}}) {
		my $notes       = "";
		my $status      = "";
		my $tc          = $testCases{$caseID}{$platformID};
		my $caseConfigs = getCaseConfigs($tc->{summary});
		
		if (!$caseConfigs->{TestScript}) {
			$notes  = "Can't execute test, no TestScript set on test case";
			$status = $statuses{blocked};
		}
		else {
			($status,$notes) = getTestStatus($caseConfigs->{TestScript}, $caseConfigs->{TestScriptOptions});
		}
		$resp = $client->send_request('tl.reportTCResult', {
			'devKey'     => $APIKey,
			'testcaseid' => $caseID,
			'testplanid' => $planID,
			'status'     => $status,
			'buildid'    => $buildID,
			'notes'      => $notes,
			'platformid' => $platformID,
		});
		if (isResponseError($resp)) {
			print STDERR "Unable to save result for TC:$caseID, platform:$platformID:\n",
			             "\t($main::apiLastResponseCode): $main::apiLastResponseString\n",
			             "\t\$notes = $notes\n",
			             "\t\$status = $status\n";
		}
		print "TC:$caseID, P:$platformID, $status", ($notes =~ m|\n|sm ? '' : ", $notes"), "\n" if ($log);
	}
}

exit;

sub getTestStatus {
	my $testScript  = shift;
	my $testOptions = shift;
	$testScript    = "/path/to/standard/test/repo/$testScript" if ($testScript !~ m|^/|);

	if (!-e $testScript) {
		return($statuses{blocked}, "$testScript does not exist");
	}
	elsif (!-x $testScript) {
		return($statuses{blocked}, "$testScript is not executable");
	}
	
	# this needs to be more flexible long term (path to perl and base needs to be flexible)
	my $cmd = "$testScript $testOptions 2>&1";
	if (!open(P, "$cmd |")) {
		return($statuses{blocked}, "Error opening pipe to $cmd: $!");
	}
	my $output = join('', <P>);
	close(P);
	
	if ($?) {
		return($statuses{failed}, $output);
	}
	elsif ($output =~ /TODO/) {
		# We're using perl test harnesses for our initial implementation, so we have a very specific
		# check here that, even if the external test script returned "0" (success), we still need
		# to mark the test case as blocked if there's any "TODO" individual tests
		
		# this might need to be changed, but for now if there's a TODO, set the status to block
		# to indicate that, while it's not a hard failure, it's still not "right" yet.
		return($statuses{blocked}, $output);
	}
	return($statuses{passed}, $output);
}

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
			print STDERR "saw config line '$pair', can't normalize to 'key: value', skipping\n";
			next;
		}
		else {
			my($k,$v) = split(/:\s+/, $pair, 2);
			$config{$k} = $v;
		}
	}
	
	return(\%config);
}

# Hoo boy is the API for TestLink messed up when it comes to error checking.  This is my best attempt
# at a single function that checks for error states in the returned object.  It works for every function
# I've used it on, but it wouldn't surprise me a bit if it incorrectlt reported an error condition 
# for interfaces I haven't tried yet.

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

This is a collection of tweaks, tools, and shortcuts I've found that have made my
interactions with TestLink 1.9.3 much better.

scripts/
	run-testplan-simple.pl
		Simple demonstration of using a perl client to interact with the TestLink XMLRPC
		API.  More complex than the very simple demo client included in the distribution,
		it includes
			* A demonstration of several more API methods
			* an attempt at a reusable error checking function for api responses
			* a method for storing external test information in test cases
			* example of posting results back to TestLink via tl.reportTCResult
	
	get-testplan-status.pl
		Very, very simple script to get a report of _changed_ testcase statuses.
		Because we are still so early in implementing automated testing, it's not
		especially interesting to be notified on failed or blocked test runs.
		However, it is very interesting to learn about testcases whose status
		changed in the last test run, which is what this script does.
		
		NOTE that this script requires a patch to xmlrpc.class.php.  The patch
		will be posted here in the future, but for now it is only available
		at http://www.jetmore.org/john/blog/2012/03/missing-testlink-api-function-getexecutionresults/


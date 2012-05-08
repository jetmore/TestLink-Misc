This is a collection of tweaks, tools, and shortcuts I've found that have made my interactions with TestLink 1.9.3 much better.

Scripts - standalone tools
--------

### scripts/run-testplan-simple.pl

Simple demonstration of using a perl client to interact with the TestLink XMLRPC API.  More complex than the very simple demo client included in the distribution, it includes
* A demonstration of several more API methods than the standard perl example script
* An attempt at a reusable error checking function for api responses
* A method for storing external test information in test cases
* Example of posting results back to TestLink via tl.reportTCResult

### scripts/get-testplan-status.pl
Very, very simple script to get a report of _changed_ testcase statuses. Because we are still so early in implementing automated testing, it's not especially interesting to be notified on failed or blocked test runs. However, it is very interesting to learn about testcases whose status changed in the last test run, which is what this script does.

NOTE that this script requires a patch to xmlrpc.class.php.  See patches/getExecutionResults.patch below.

Patches - modifying existing tools and UI elements
------

All patches are against TestLink 1.9.3.  Patches can be applied by changing directories to the top level of the TestLink install and running patch with -p1.  For example:

    cd /path/to/testlink-1.9.3
    patch --dry-run -p1 -i /path/to/PatchFile.patch
    patch -p1 -i /path/to/PatchFile.patch

### patches/getExecutionResults.patch

This is a simple extension to the TestLink API, adding a function called `getExecutionResults()`.  This function is used by the get-testplan-status.pl script.  See http://www.jetmore.org/john/blog/2012/03/missing-testlink-api-function-getexecutionresults/ for more details.

### patches/ui-tweaks.patch

This is a collection of UI tweaks I found to be vital in using TestLink.  This is a single patch that incorporates several tweaks I discovered over a few months.  Because each of the changes involves the same file, and often the same lines of the same file, I am not taking the time to separate out the individual patches.  The blog posts referenced below contain more specific diffs for each change, along with explanation of why the change was needed.  Changes included in this patch:

* Better copy/paste in Test Cases (see http://www.jetmore.org/john/blog/2011/09/better-copypaste-when-editing-test-steps-in-testlink/)
* Setting default "editor" font, and default step/result font (see http://www.jetmore.org/john/blog/2011/09/setting-default-font-in-testlink/)
* Setting alternating background color in test steps to make steps more easily distinguishable (see http://www.jetmore.org/john/blog/2011/08/alternating-test-step-row-colors-in-testlink/ and http://www.jetmore.org/john/blog/2011/11/ui-improvements-for-testlinks-vertical-step-layout/)
* Hide editor toolba by default (no post, just too lazy to remove this from the diff)
* Change editor default line break from P to DIV to prevent blank line on single "enter" (no post)
# xdcrDifferPreCheck
xdcrDiffer uses on SDK to create a DCP connection and for other things. SDK errors might be tricky to debug the connectivity issues. xdcrDifferPreCheck can be used to perform a connection pre-check before running xdcrDiffer.
xdcrDifferPreCheck, can be used to do the following:
1. Connect to ns_server port of all source cluster nodes and target cluster nodes using the credentials which xdcrDiffer would use.
2. Connect to memcached port of all source cluster nodes and target cluster nodes using the credentials which xdcrDiffer would use.
3. Run xdcrDiffer with SDK verbose debug logging.

## Flags to run
```
./runDiffer.sh -h
Invalid option: h requires an argument
Missing username
Usage: ./runDiffer.sh -u <username> -p <password> -h <hostname:port> -s <sourceBucket> -t <targetBucket> -r <remoteClusterName> -g <preCheckMode=(0|1|2)> [-v <targetUrl>] [-n <remoteClusterUsername> -q <remoteClusterPassword>] [-c clean] [-b ] [-e <mutationRetries>] [-w <setupTimeoutInSeconds>]

This script will set up the necessary environment variable to allow the XDCR diff tool to connect to the metakv service in the
specified source cluster (NOTE: over http://) and retrieve the specified replication spec and run the difftool on it.
The difftool currently only supports connecting to remote targets with username and password. Thus, if the specified remote cluster
reference only contains certificate, then specify the remoteClusterUsername and remoteClusterPassword accordingly.

use "-b" to get document body for comparison instead of metadata. This is a slower option and it will not get tombstones

use "-g" change the mode of pre-check:
0: no extra pre-check. Runs differ with SDK verbose debug logging.
	- Results will be logged in xdcrDiffer_noPrecheck.log
1: connection pre-check performed on ns_server port of all source and target cluster nodes using the credentials that xdcrDiffer would use.
	- Results will be logged in xdcrDiffer_nsServerPreCheck.log
2: connection pre-check performed on memcached port of all source and target cluster nodes using the credentials that xdcrDiffer would use.
	- Results will be logged in xdcrDiffer_kvPreCheck.log

```
## Examples
```
./runDiffer.sh -u Administrator -p wewewe -h 127.0.0.1:9000 -r C2 -s B1 -t B2 -g 0
```
```
./runDiffer.sh -u Administrator -p wewewe -h 127.0.0.1:9000 -r C2 -s B1 -t B2 -g 1
```
```
./runDiffer.sh -u Administrator -p wewewe -h 127.0.0.1:9000 -r C2 -s B1 -t B2 -g 2
```

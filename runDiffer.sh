#!/bin/bash

#build Copyright (c) 2013-2021 Couchbase, Inc.
# Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
# except in compliance with the License. You may obtain a copy of the License at
#   http://www.apache.org/licenses/LICENSE-2.0
# Unless required by applicable law or agreed to in writing, software distributed under the
# License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
# either express or implied. See the License for the specific language governing permissions
# and limitations under the License.

run_args=$@

execGo="xdcrDiffer"
differLogFileName="${execGo}.log"

function findExec() {
	if [[ ! -f "$execGo" ]]; then
		echo "Unable to find xdcr diff tool. Did you run make?"
		exit 1
	fi
}

function printHelp() {
	findExec

	cat <<EOF
Usage: $0 -u <username> -p <password> -h <hostname:port> -s <sourceBucket> -t <targetBucket> -r <remoteClusterName> -g <preCheckMode=(0|1|2)> [-v <targetUrl>] [-n <remoteClusterUsername> -q <remoteClusterPassword>] [-c clean] [-b ] [-e <mutationRetries>] [-w <setupTimeoutInSeconds>]

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
EOF
}

function waitForBgJobs {
	local mainPid=$1
	local mainPidCnt=$(ps -ef | grep -v grep | grep -c $mainPid)
	local jobsCnt=$(jobs -l | grep -c "Running")
	while (((($jobsCnt > 0)) && (($mainPidCnt > 0)))); do
		sleep 1
		jobsCnt=$(jobs -l | grep -c "Running")
		mainPidCnt=$(ps -ef | grep -v grep | grep -c $mainPid)
	done
}

function killBgTail {
	local tailPid=$(jobs -l | grep tail | awk '{print $2}')
	if [[ ! -z "$tailPid" ]]; then
		kill $tailPid >/dev/null 2>&1
	fi
}

while getopts ":h:p:u:r:s:t:n:q:v:cbe:w:g:" opt; do
	case ${opt} in
	u)
		username=$OPTARG
		;;
	p)
		password=$OPTARG
		;;
	h)
		hostname=$OPTARG
		;;
	r)
		remoteClusterName=$OPTARG
		;;
	s)
		sourceBucketName=$OPTARG
		;;
	t)
		targetBucketName=$OPTARG
		;;
	n)
		remoteClusterUsername=$OPTARG
		;;
	q)
		remoteClusterPassword=$OPTARG
		;;
	c)
		cleanBeforeRun=1
		;;
	b)
		compareBody=true
		;;
	v)
		targetUrl=$OPTARG
		;;
	e)
		mutationRetries=$OPTARG
		;;
	d)
		debugMode=1
		;;
	w)
		setupTimeout=$OPTARG
		;;
	g)
		preCheckMode=$OPTARG
		;;
	\?)
		echo "Invalid option: $OPTARG" 1>&2
		;;
	:)
		echo "Invalid option: $OPTARG requires an argument" 1>&2
		;;
	esac
done
shift $((OPTIND - 1))

if [[ -z "$username" ]]; then
	echo "Missing username"
	printHelp
	exit 1
elif [[ -z "$password" ]]; then
	echo "Missing password"
	printHelp
	exit 1
elif [[ -z "$hostname" ]]; then
	echo "Missing hostname and port"
	printHelp
	exit 1
elif [[ -z "$sourceBucketName" ]]; then
	echo "Missing sourceBucket"
	printHelp
	exit 1
elif [[ -z "$targetBucketName" ]]; then
	echo "Missing targetBucket"
	printHelp
	exit 1
elif [[ -z "$remoteClusterName" ]] && [[ -z "$targetUrl" ]]; then
	echo "Missing remoteCluster name or target URL"
	printHelp
	exit 1
fi

findExec

export CBAUTH_REVRPC_URL="http://$username:$password@$hostname"
echo "Exporting $CBAUTH_REVRPC_URL"

if [[ ! -z "$cleanBeforeRun" ]]; then
	echo "Cleaning up before run..."
	for directory in "source target fileDiff mutationDiff checkpoint"; do
		rm -rf $directory
	done
fi

unameOut=$(uname)
maxFileDescs=""

if [[ "$unameOut" == "Linux" ]] || [[ "$unameOut" == "Darwin" ]]; then
	maxFileDescs=$(ulimit -n)
	if (($? == 0)) && [[ "$maxFileDescs" =~ ^[[:digit:]]+$ ]] && (($maxFileDescs > 4)); then
		# use 3/4 to prevent overrun
		maxFileDescs=$(echo $(($maxFileDescs / 4 * 3)))
	fi
fi

currentPwd=$(pwd)
execString="$currentPwd/$execGo"
execString="${execString} -sourceUrl"
execString="${execString} $hostname"
execString="${execString} -sourceUsername"
execString="${execString} $username"
execString="${execString} -sourcePassword"
execString="${execString} $password"
execString="${execString} -sourceBucketName"
execString="${execString} $sourceBucketName"
execString="${execString} -targetBucketName"
execString="${execString} $targetBucketName"

if [[ ! -z "$remoteClusterUsername" ]] && [[ ! -z "$remoteClusterPassword" ]]; then
	execString="${execString} -targetUsername"
	execString="${execString} $remoteClusterUsername"
	execString="${execString} -targetPassword"
	execString="${execString} $remoteClusterPassword"
fi
if [[ ! -z "$remoteClusterName" ]]; then
	execString="${execString} -remoteClusterName"
	execString="${execString} $remoteClusterName"
elif [[ ! -z "$targetUrl" ]]; then
	execString="${execString} -targetUrl"
	execString="${execString} $targetUrl"
fi
if [[ ! -z "$maxFileDescs" ]]; then
	execString="${execString} -numberOfFileDesc"
	execString="${execString} $maxFileDescs"
fi
if [[ ! -z "$compareBody" ]]; then
	execString="${execString} -compareBody"
	execString="${execString} $compareBody"
fi
if [[ ! -z "$mutationRetries" ]]; then
	execString="${execString} -mutationRetries"
	execString="${execString} $mutationRetries"
fi
if [[ ! -z "$setupTimeout" ]]; then
	execString="${execString} -setupTimeout"
	execString="${execString} $setupTimeout"
fi
if [[ ! -z "$preCheckMode" ]]; then
	execString="${execString} -preCheckMode"
	execString="${execString} $preCheckMode"

	if (( $preCheckMode == 0 )); then
		differLogFileName="xdcrDiffer_noPrecheck.log"
	elif (( $preCheckMode == 1 )); then
		differLogFileName="xdcrDiffer_nsServerPreCheck.log"
	elif (( $preCheckMode == 2  )); then
		differLogFileName="xdcrDiffer_kvPreCheck.log"
	else
		echo "Invalid -preCheckMode or -g value. Can be 0, 1 or 2." 
		exit 1
	fi

	echo "Results logged as $differLogFileName"
fi

echo $execString

# Execute the differ in background and watch the pid to be finished
$execString >$differLogFileName 2>&1 &
bgPid=$(jobs -p)

# in the meantime, trap ctrl-c and pass the signal to the program
trap ctrl_c INT

function ctrl_c() {
	if [[ -z "$bgPid" ]]; then
		exit 0
	else
		kill -SIGINT $bgPid
		killBgTail
	fi
}

tail -f $differLogFileName &
waitForBgJobs $bgPid
killBgTail

unset CBAUTH_REVRPC_URL

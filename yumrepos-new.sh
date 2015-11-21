#!/bin/bash
#
# Creates Yum repos for the ERS Backend
#
# */5 * * * *    /usr/local/sbin/yumrepos-new.sh se-evd>> /var/log/yumrepos-se-evd.log 2>&1
#
# $Id$
# 
# 21/11/2015 Parijat Mukherjee
#

if [ -z "$1" ]; then echo Require parameter name; exit 1; fi

raw_name="$1"
name="${raw_name}"

if [ -n "$3" ]; then
	artifact_modifier="$3"
	name=${raw_name}-${artifact_modifier}
fi

versions="RELEASE LATEST"
arch386="el5.i386|noarch"
arch="el5.x86_64|noarch"
arch86="x86_64|noarch"
logfile=/var/log/${name}.log
runfile=/var/run/${name}.pid
artifact_id=${name}-backend
yum_repo_path=/var/www/html/${raw_name}/${artifact_id}
cachedir=/var/cache/$name
nexus_url=http://nexus:8081/nexus
nexus_repos="releases snapshots"
group_id=com.seamless.customer.${raw_name}

# logs to logfile and on console
function log (){
	echo $1
	echo $1 >> $logfile
}

log "Starting "

[ -n "$2" ] && versions="$2"

# Check that we're not already running
time=$(date "+%F %T")
if [ -e $runfile ]; then
	read pid < $runfile
	[ -n "$pid" -a -d /proc/$pid ] && log  "$time - $$: Aborting; last job ($pid) is not finished. lock file is $runfile " && exit 1
fi

echo $$ > $runfile
echo "$time - $$: Starting $name" >> $logfile;

# Workaround bugs in createrepo
mkdir -p $yum_repo_path
find $yum_repo_path -type d -wholename "*/repodata/repodata" | xargs rm -rf
find $yum_repo_path -type d -name ".olddata" | xargs rm -rf

echo "Versions $versions"

for v in $versions; do
	# Get the list of packages
	_plist=
	_artifact_version=
	_artifact_repos=$nexus_repos
	case $v in
		LATEST)
			_artifact_repos=snapshots
			;;
		RELEASE)
			_artifact_repos=releases
			;;
		*)
			;;
	esac

	echo "Repos $_artifact_repos"
    for t in $_artifact_repos; do
        _url="${nexus_url}/service/local/artifact/maven/redirect?r=${t}&g=${group_id}&a=${artifact_id}&v=${v}&p=properties"
		echo $url
		echo $url >> $logfile
        _curl=$(curl -fsL "$_url" | sed -re '/^#/d' -e '/^$/d' -e 's/=/-/')
		if [ "x" != "x$_curl" ]; then
			_plist=$_curl
			_artifact_version=$(curl -fsL "$_url" | grep "^${artifact_id}=" | awk -F= '{print $2}')
			echo "$(date "+%F %T") - $$:   Found $_artifact_version in $t" >> $logfile
			echo "$(date "+%F %T") - $$:   Found $_artifact_version in $t"
			break
		fi
	done
	[ "x" = "x$_plist" ] && { echo "Unknown version: ${v}"; continue; }
	[ "x" = "x$_artifact_version" ] && { echo "Cannot determine the version of ${artifact_id}"; continue; }

	yum_repos="$_artifact_version"
	[ "$_artifact_version" != "$v" ] && yum_repos="$_artifact_version $v"
	for yum_repo in $yum_repos; do
		_path=${yum_repo_path}/${yum_repo}

		echo "Working on $_path"
		mkdir -p $_path
		pushd $_path > /dev/null

		# Find packages and create symlinks
		_list=
		for p in $_plist; do

		echo
		echo "###Processing package $p"
		echo
			_pkg=
			_repos=$nexus_repos
			case $p in
				se-qr-backend-*)
					case $p in
						*-SNAPSHOT)
							_repos=snapshots
							;;
						*)
							_repos=releases
							;;
					esac
					;;
				*) ;;
			esac
			_pkg=$(echo $p | sed -e 's/-SNAPSHOT//')


		packageLinked="false"

			for repo in $_repos; do


# Try to find using locate first
# Then try to find in com/seamless
# Then try to find in se/seamless

			echo "Searching for $_pkg in repo $repo"

			if [ "$packageLinked" == "false" ];then
					echo "Looking For $_pkg "
					packages=$(find /opt/sonatype-work/nexus/storage/${repo}/com/seamless/ -type f -name "${_pkg}*.rpm" | grep -E ${arch})
					echo "Packages found are $packages"

					if [ "$packages" == "" ]; then
					echo "Packages not found in com/seamless we will try looking in se/seamless"
					packages=$(find /opt/sonatype-work/nexus/storage/${repo}/se/seamless/ -type f -name "${_pkg}*.rpm" | grep -E ${arch})
					fi

					if [ "$packages" == "" ]; then
					echo "Packages not found in se/seamless we will try with ${arch386} architecture"
					packages=$(find /opt/sonatype-work/nexus/storage/${repo}/com/seamless/ -type f -name "${_pkg}*.rpm" | grep -E ${arch386})
					fi

					if [ "$packages" == "" ]; then
					echo "Packages not found in com/seamless we will try looking in se/seamless with ${arch386} architecture"
					packages=$(find /opt/sonatype-work/nexus/storage/${repo}/se/seamless/ -type f -name "${_pkg}*.rpm" | grep -E ${arch386})
					fi

					if [ "$packages" == "" ]; then
					echo "Packages not found in se/seamless we will try with ${arch86} architecture"
					packages=$(find /opt/sonatype-work/nexus/storage/${repo}/com/seamless/ -type f -name "${_pkg}*.rpm" | grep -E ${arch86})
					fi

					if [ "$packages" == "" ]; then
					echo "Packages not found in com/seamless we will try looking in se/seamless with ${arch86} architecture"
					packages=$(find /opt/sonatype-work/nexus/storage/${repo}/se/seamless/ -type f -name "${_pkg}*.rpm" | grep -E ${arch86})
					fi
				fi

				if [ "$packages" != "" ]; then
				for f in $packages; do
					echo "Linking $f"
					ln -fs $f
					_list="$(basename $f)|$_list"
				done
				packageLinked="true"
				else
				echo "No packages found in $repo"
				fi
			done
		done

		# Remove packages that were not on the list
		for l in $(find . -type l | grep -vE ${_list%?}); do
			rm -f $l
		done

		createrepo -q --cachedir $cachedir .

		echo "$(date "+%F %T") - $$:   Created yum repo for $yum_repo" >> $logfile

		popd > /dev/null
	done
done

echo "$(date "+%F %T") - $$: Finished ${name}" >> $logfile

rm -f $runfile
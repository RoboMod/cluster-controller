#!/bin/bash

# Script to control a project running on a cluster
# Copyright (C) 2014, Andreas Ihrig (alias RoboMod)
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <http://www.gnu.org/licenses/>.
#
# Thanks for:
#  - sub command implementation from https://gist.github.com/waylan/4080362
#  - processing options with help from http://mywiki.wooledge.org/BashFAQ/035
#
# Configuration of static parameters like project name and ssh login name
# are done in cluster-controller.conf. The command have to in 'apostrophes' 
# to prevent execution and parameter substitution outside the cluster.
#
# Special informations:
#  - Cygwin users should add the following line to their .bashrc
#    eval `ssh-agent -s`

# get base directory
base_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )/../"

# load configuration
source $( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )/cluster-controller.conf

# helpers for ssh agent and useful commands
ssh_agent() {
    # check if key is add to agent, yet
    add="y"
    for id in `ssh-add -l | awk '{print $3}'`; do
        if [ `readlink -f $id` == `readlink -f $1` ]; then
            add="n"
        fi
    done    
    
    if [ "$add" == "y" ]; then
        # add key and check result
        ssh-add $1
        if [ ! "$?" ]; then
            echo "Error with ssh-agent"
            exit 1
        fi
    fi
}

sync_directory() {
    # parameter 1 is the projects directory on the cluster
    # parameter 2 is a possible sub directory
    # parameter 3 defines the synch direction ("r": download, others: upload)
    
    # reverse sync if parameter 2 is r
    if [ "$3" == "r" ]; then 
        source="$ssh_user@$ssh_server:~/$1"
        target=$base_dir
    else
        source=$base_dir
        target="$ssh_user@$ssh_server:~/$1"
    fi
    
    # add sub directory if given
    if [ "$2" ]; then
        source=$source/$2
        target=$target
    fi
    
    # TODO: show progress with implementation from http://serverfault.com/a/462562
    args="-azxe ssh --stats --exclude=.svn/ --exclude=.directory/"
    rsync $args $source $target
}

submit_job() {
    # start ssh session and run command
    QSUB_COMMAND="qsub -N $project_name -M $project_mail -l walltime=$walltime,nodes=$num_nodes -o $directory/$results_directory/ -v base_dir=$directory,results_directory=$results_directory,pre_commands=\"$pre_commands\",command=\"$cluster_command\" ~/$directory/clustering/cluster-script.pbs"
    #echo $QSUB_COMMAND
    JOB_ID=`ssh  $ssh_user@$ssh_server $QSUB_COMMAND`
    if [ $? == 0 ]; then
        echo "Submitted job with id: $JOB_ID"
    else
        echo "Error"
    fi
}

get_jobs() {
    # get job ids from cluster
    QSUB_COMMAND="qstat -u techsoz | grep techsoz | sed -e 's/^\([0-9][0-9]*\).*$/\1/g'"
    JOB_ARRAY=(`ssh  $ssh_user@$ssh_server $QSUB_COMMAND`)
    #echo ${JOB_ARRAY[@]}
    if [ ${#JOB_ARRAY[*]} -eq 0 ]; then
        echo "No jobs running"
        exit 1
    fi
    
    echo ${JOB_ARRAY[@]}
}

kill_job() {
    # start ssh session and run command
    QSUB_COMMAND="qdel $1"
    STATUS=`ssh  $ssh_user@$ssh_server $QSUB_COMMAND`
    if [ $? == 0 ]; then
        echo "Killed job with id: $1"
    fi
}

# subcommand to sync project folder to cluster
sub_sync() {
    directory="$project_name"

    # process options
    while :; do
        case $1 in
            -d|--directory) 
                if [ "$2" ]; then
                    directory=$2
                    echo "Sync to $2"
                    shift 2
                    continue
                else
                    echo "Please specify a directory!"
                    exit 1
                fi
                ;;
            -s|-ssh-agent)
                if [ "$2" ]; then
                    ssh_agent $2
                    shift 2
                    continue
                else
                    echo -n "Enter SSH key file: "
                    read $filename
                    ssh_agent $filename
                fi
                ;;
            -h|--help) 
                echo "Usage: $(basename $0) start [options]"
                echo " -d | --directory DIRECTORY" $'\t' "Directory on cluster to sync below home folder"
                echo " -s | --ssh-agent FILENAME" $'\t' "Use SSH agent with key in FILENAME"
                echo " -h | --help" $'\t\t\t' "Display help"
                exit 0
                ;;
            *)
                break
        esac
        
        shift
    done

    echo "Synchronizing $project_name folder to $cluster_name"
    
    sync_directory $directory
    
    echo "Finished."
}

# subcommand to start project script (cluster-script.pbs) on cluster
sub_start() {
    sync=1
    sync_parameters=
    num_jobs=1
    directory="$project_name"

    # process options
    while :; do
        case $1 in
            -m|--multiple)
                if [ "$2" ]; then
                    if [ $2 -le 0 ]; then
                        echo "Bad number."
                        exit 1
                    fi
                    
                    if [ $2 -gt 1 ]; then
                        num_jobs=$2
                        echo "Submit $num_jobs jobs"
                    fi
                    
                    shift 2
                    continue
                else
                    echo "No number of jobs specified. Assuming 1."
                fi
                ;;
            -n|--nosync) 
                echo "No synchronization."
                sync=
                ;;
            -p|--sync-parameters) 
                if [ "$2" ]; then
                    sync_parameters=$2
                    shift 2
                    continue
                fi
                ;;
            -d|--directory) 
                if [ "$2" ]; then
                    directory=$2
                    echo "Use directory $2"
                    shift 2
                    continue
                else
                    echo "Please specify a directory!"
                    exit 1
                fi
                ;;
            -s|-ssh-agent)
                if [ "$2" ]; then
                    ssh_agent $2
                    shift 2
                    continue
                else
                    echo -n "Enter SSH key file: "
                    read $filename
                    ssh_agent $filename
                fi
                ;;
            -h|--help) 
                echo "Usage: $(basename $0) start [options]"
                echo " -m | --mutiple NUMBER" $'\t\t\t' "Submit <NUMBER> jobs"
                echo " -n | --nosync" $'\t\t\t\t' "Don't synchronize before submitting process"
                echo " -d | --directory DIRECTORY" $'\t\t' "Directory on $cluster_name to find $project_name below home folder (relativ path)"
                echo " -p | --sync-parameters \"PARAMETERS\"" $'\t' "Parameters passed to sync subcommand"
                echo " -s | --ssh-agent FILENAME" $'\t' "Use SSH agent with key in FILENAME"
                echo " -h | --help" $'\t\t\t\t' "Display help"
                exit 0
                ;;
            *)
                break
        esac
        
        shift
    done
    
    # synchronize if wanted
    if [ $sync ]; then
        # override directory cause maybe user passed option directory
        sub_sync $sync_parameters -d $directory
    fi
    
    # submit job(s)
    for((i=0; i<$num_jobs; i++)) do
        submit_job 
    done
}

# subcommand to show status of submitted jobs
sub_status(){
    # process options
    while :; do
        case $1 in
            -s|-ssh-agent)
                if [ "$2" ]; then
                    ssh_agent $2
                    shift 2
                    continue
                else
                    echo -n "Enter SSH key file: "
                    read $filename
                    ssh_agent $filename
                fi
                ;;
            -h|--help) 
                echo "Usage: $(basename $0) status [options]"
                echo " -s | --ssh-agent FILENAME" $'\t' "Use SSH agent with key in FILENAME"
                echo " -h | --help" $'\t\t\t' "Display help"
                exit 0
                ;;
            *)
                break
        esac
        
        shift
    done

    # start ssh session and run command
    QSUB_COMMAND="qstat -u $ssh_user"
    STATUS=`ssh $ssh_user@$ssh_server $QSUB_COMMAND`
    if [ "$STATUS" ]; then
        printf "$STATUS\n";
        
        echo ""
        echo -n "| "
        states=("C" "E" "H" "Q" "R" "T" "W" "S")
        for state in "${states[@]}"; do
            count=`echo "$STATUS" | awk -vstate=$state 'BEGIN { nr = 0 } $10 == state { nr += 1 } END { print nr }'`
            echo -n "$state: $count | "        
        done
        echo ""
    else
        echo "No jobs running."
    fi
}

# subcommand to stop job(s) on cluster    
sub_stop() {
    JOB_ID=
    
    # process options
    while :; do
        case $1 in
            -a|--all) 
                echo "Kill all jobs."
                JOB_ID="*"
                ;;
            -s|-ssh-agent)
                if [ "$2" ]; then
                    ssh_agent $2
                    shift 2
                    continue
                else
                    echo -n "Enter SSH key file: "
                    read $filename
                    ssh_agent $filename
                fi
                ;;
            -h|--help) 
                echo "Usage: $(basename $0) stop [options] [job_id]"
                echo " -a | --all" $'\t' "Kill all running jobs"
                echo " -s | --ssh-agent FILENAME" $'\t' "Use SSH agent with key in FILENAME"
                echo " -h | --help" $'\t\t\t\t' "Display help"
                exit 0
                ;;
            *)
                break
        esac
        
        shift
    done
    
    if [ "$JOB_ID" == "*" ]; then
        JOB_ARRAY=`get_jobs`
        if [ "$JOB_ARRAY" == "No jobs running" ]; then
            echo "No jobs running"
            exit 1
        fi
        
        for job in ${JOB_ARRAY[@]}; do
            kill_job $job
        done
    else
        if [ "$1" ]; then
            JOB_ID=$1
        else
            echo "Please specify a job id:"
            
            JOB_ARRAY=`get_jobs`
            if [ "$JOB_ARRAY" == "No jobs running" ]; then
                echo "No jobs running"
                exit 1
            fi
            
            # display options and ask user
            count=1
            for job in ${JOB_ARRAY[@]}; do
                echo " $count: $job"
                let count=(count+1)
            done
			echo " *: all"
            echo -n "Please chose an option: "
            read JOB_NUMBER
            
			# kill all jobs
			if [ "$JOB_NUMBER" == "*" ]; then
				for job in ${JOB_ARRAY[@]}; do
					kill_job $job
				done
				
				exit 0
			fi
				
			# kill job by number
            if [ $JOB_NUMBER -ge 1 ] && [ $JOB_NUMBER -le ${#JOB_ARRAY[*]} ]; then
                # get job id
                count=1
                for job in ${JOB_ARRAY[@]}; do
                    if [ "$count" == "$JOB_NUMBER" ]; then
                        JOB_ID=$job
                    fi
                    let count=(count+1)
                done
                
                if [ ! "$JOB_ID" ]; then
                    echo "Bad input"
                    exit 1
                fi
                
                echo "You chose job with id: $JOB_ID"
				kill_job $JOB_ID
				
				exit 0
            else
				echo "Bad input"
				exit 1
            fi
        fi
        
        
    fi
}

# subcommand to get results from cluster
sub_results() {
    directory="$project_name"

    # process options
    while :; do
        case $1 in
            -d|--directory) 
                if [ "$2" ]; then
                    directory=$2
                    echo "Sync to $2"
                    shift 2
                    continue
                else
                    echo "Please specify a directory!"
                    exit 1
                fi
                ;;
            -s|-ssh-agent)
                if [ "$2" ]; then
                    ssh_agent $2
                    shift 2
                    continue
                else
                    echo -n "Enter SSH key file: "
                    read $filename
                    ssh_agent $filename
                fi
                ;;
            -h|--help) 
                echo "Usage: $(basename $0) stop [options] [job_id]"
                echo " -d | --directory DIRECTORY" $'\t' "Project directory on cluster below home folder (relativ path)"
                echo " -s | --ssh-agent FILENAME" $'\t' "Use SSH agent with key in FILENAME"
                echo " -h | --help" $'\t\t\t\t' "Display help"
                exit 0
                ;;
            *)
                break
        esac
        
        shift
    done
    
    sync_directory $directory $results_directory "r"
}

# subcommand to manage ssh keys
sub_ssh() {
    filename=

    # process options
    while :; do
        case $1 in
            -c|--create) 
                if [ "$2" ]; then
                    filename=$2
                    shift 2
                    continue
                else
                    echo -n "Please specify an identity file name: "
                    read $filename
                    if [ ! "$filename" ]; then
                        exit 1
                    fi
                fi
                ;;
            -u|--upload) 
                if [ "$2" ]; then
                    filename=$2
                    shift 2
                    continue
                else
                    echo "Please specify an identity file name!"
                    exit 1
                fi
                ;;
            -h|--help) 
                echo "Usage: $(basename $0) start [options]"
                echo " -c | --create FILENAME" $'\t' "Create SSH key in FILENAME and upload"
                echo " -u | --upload FILENAME" $'\t' "Upload SSH pub key to $cluster_name"
                echo " -h | --help" $'\t\t\t' "Display help"
                exit 0
                ;;
            *)
                break
        esac
        
        shift
    done
    
    if [ -e "$filename" ]; then
        ssh-copy-id -i "$filename" $ssh_user@$ssh_server
    else
        ssh-keygen -f "$filename"
        ssh-copy-id -i "$filename" $ssh_user@$ssh_server
    fi
}

# show help about subcommands
sub_help() {
    echo "Usage: $(basename $0) <subcommand> [options]"
    echo "Subcommands:"
    echo " sync" $'\t\t' "Synchronize file to $cluster_name"
    echo " start" $'\t\t' "Start $project_name on $cluster_name"
    echo " status" $'\t' "Check status of $project_name"
    echo " stop" $'\t\t' "Stop $project_name"
    echo " results" $'\t' "Get resulst from $cluster_name"
    echo " ssh" $'\t\t' "Manage SSH login to $cluster_name"
    echo ""
    echo "For help with each subcommand run:"
    echo " $(basename $0) <subcommand> -h|--help"
    echo ""
}

# process subcommands
subcommand=$1
case $subcommand in
    "" | "-h" | "--help")
        sub_help
        exit 0
        ;;
    *)
        shift
        sub_${subcommand} $@
        if [ $? = 127 ]; then
            echo "Error: '$subcommand' is not a known subcommand." >&2
            echo " Run '$(basename $0) --help' for a list of known subcommands." >&2
            exit 1
        fi
        ;;
esac
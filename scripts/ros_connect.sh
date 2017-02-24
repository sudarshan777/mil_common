#!/bin/bash

# ROS Connect is a small set of functions that makes managing the currently
# selected ROS master simple and convenient. It's default is to dynamically
# determine which hosts are online and allow the user to select one, but a
# hostname can be passed as an argument to bypass this process. Once a hostname
# is selected, all future shells will default to using it. If a different shell
# is required for future sessions, simply run mil_connect again. The help menu
# can be accessed with the -h flag and it details how to disable this
# persistence feature as well as how to set the roscore for a single shell.


# These parameters define the network to search on
DEFAULT_HOST="localhost"
SEARCH_DOMAIN="ad.mil.ufl.edu"
SUBNET="192.168.37.0/24"

# These are the hostnames for all MIL hosts that run a remote roscore
HOSTNAMES=(	"mil-sub-sub8.$SEARCH_DOMAIN"
		"mil-nav-wamv.$SEARCH_DOMAIN"
		"mil-shuttle.$SEARCH_DOMAIN"
)

# These are the common names that map one-to-one to the above hostnames
COMMNAMES=(	"SubjuGator"
		"NaviGator"
		"Shuttle"
)

# The hostname persistence file
PERSISTENCE_FILE=~/.ros_connect_persistence


check_host() {
	HOST="$1"

	# Attempts to ping the host to make sure it is reachable
	HOST_PING=$(ping -c 2 $HOST 2>&1 | grep "% packet" | awk -F'[%]' '{print $1}' | awk -F'[ ]' '{print $NF}')
	if [ ! -z "${HOST_PING}" ]; then

		# Uses packet loss percentage to determine if the connection is strong
		if [ $HOST_PING -lt 25 ]; then

			# Will return true if ping was successful and packet loss was below 25%
			echo "true"
		fi
	fi
}

check_roscore_hosts() {
	AVAILABLE_HOSTS=()

	# Check whether or not each hostname is online
	for ((HOST_ID=0; HOST_ID<${#HOSTNAMES[@]}; HOST_ID++)); do
		if [ "`check_host ${HOSTNAMES[$HOST_ID]}`" = "true" ]; then
			AVAILABLE_HOSTS+=($HOST_ID)
		fi
	done
}

set_ros_ip() {
	LOCAL_IP="`ip route get $SUBNET | awk '{print $NF; exit}'`"
	LOCAL_HOSTNAME="`hostname`.$SEARCH_DOMAIN"

	# Sets ROS_HOSTNAME if the hostname is resolvable on the search domain
	if [ ! -z "`dig +short $LOCAL_HOSTNAME | awk '{ print ; exit }'`" ]; then
		unset ROS_IP
		export ROS_HOSTNAME=$LOCAL_HOSTNAME

	# Sets ROS_IP to the IP address on this machine's main NIC as a fallback
	else
		unset ROS_HOSTNAME
		export ROS_IP=$LOCAL_IP
	fi
}

unset_ros_ip() {

	# Clears the ROS_IP and ROSS_HOSTNAME environment variables
	unset ROS_IP
	unset ROS_HOSTNAME
}

set_ros_master() {

	# Sets ROS_MASTER_URI to the hostname of the selected remote roscore
	export ROS_MASTER_URI=http://$1:11311
	echo "The master roscore is set to http://$1:11311"
}

ros_connect() {
	HOST_DISCOVERY=true

	# Gets the state of hostname persistence from the persistence file
	if [ -z `cat $PERSISTENCE_FILE | grep "disabled"` ]; then
		PERSIST=true
	else
		PERSIST=false
	fi

	# Handles command line arguments
	while [ "$#" -gt 0 ]; do
		case $1 in
			-h|--help)
				echo "Usage: ros_connect [OPTION] [HOSTNAME]..."
				echo "Manager for connections to remote roscores."
				echo ""
				echo "Option		GNU long option		Meaning"
				echo "-h		--help			Display the help menu"
				echo "-p		--persistence		Toggle persistence across shells"
				echo "-o		--one-time		Only set the roscore for this shell"
				echo "-n [HOSTNAME]	--hostname		Manually pass in a hostname"
				HOST_DISCOVERY=false
				PERSIST=false
				shift 1
				;;
			-p|--persistence)
				if [ -z `cat $PERSISTENCE_FILE | grep "disabled"` ]; then
					echo "disabled" > $PERSISTENCE_FILE
				else
					echo $DEFAULT_HOST > $PERSISTENCE_FILE
				fi
				HOST_DISCOVERY=false
				PERSIST=false
				shift 1
				;;
			-o|--one-time)
				PERSIST=false
				shift 1
				;;
			-n|--hostname)
				HOST="$2"
				if [ "$HOST" != "localhost" ]; then
					set_ros_ip
				else
					unset_ros_ip
				fi
				set_ros_master $HOST
				HOST_DISCOVERY=false
				shift 2
				;;
			*)
				echo "Option $1 is not implemented."
				echo "Try 'ros_connect --help' for more information."
				HOST_DISCOVERY=false
				PERSIST=false
				shift 1
				;;
		esac
	done

	# Skips the host discovery process if the hostname was passed in
	if ($HOST_DISCOVERY); then

		# If no arguments were passed in, detect the available remote roscores
		check_roscore_hosts

		# If none of the remote roscores are accessible, use localhost as the default roscore
		if [ ${#AVAILABLE_HOSTS[@]} -eq 0 ]; then
			echo "None of the remote roscores are available on this network"
			HOST=$DEFAULT_HOST

		# If just one remote roscore was accessible, connect directly to that roscore
		elif [ ${#AVAILABLE_HOSTS[@]} -eq 1 ]; then
			echo "The only remote roscore that could be detected is running on ${COMMNAMES[$AVAILABLE_HOSTS]}"
			HOST=${HOSTNAMES[$AVAILABLE_HOSTS]}
			set_ros_ip
			set_ros_master ${HOSTNAMES[$AVAILABLE_HOSTS]}

		# If multiple remote roscores were detected, allow the user to select one
		else
			echo "Multiple remote roscores were detected on this network"
			for ((ID_INDEX=0; ID_INDEX<${#AVAILABLE_HOSTS[@]}; ID_INDEX++)); do
				echo "	$(($ID_INDEX + 1)). ${COMMNAMES[${AVAILABLE_HOSTS[$ID_INDEX]}]}"
			done
			echo -n "Select a remote roscore to connect to: " && read RESPONSE
			if [ ! $RESPONSE -lt 1 ] && [ ! $RESPONSE -gt $ID_INDEX ]; then
				HOST=${HOSTNAMES[${AVAILABLE_HOSTS[$(($RESPONSE - 1))]}]}
				set_ros_ip
				set_ros_master ${HOSTNAMES[${AVAILABLE_HOSTS[$(($RESPONSE - 1))]}]}
			else
				echo "Invalid selection, no roscore selected"
			fi
		fi
	fi

	if ($PERSIST) && [ ! -z $HOST ]; then
		echo $HOST > $PERSISTENCE_FILE
	fi
}

ros_disconnect() {

	# Disconnects from any remote roscore and connects to the local one
	ros_connect -n $DEFAULT_HOST
}


# Prints debugging output for the master roscore that is currently selected
alias ros_env='echo "ROS_IP=$ROS_IP
ROS_HOSTNAME=$ROS_HOSTNAME
ROS_MASTER_URI=$ROS_MASTER_URI"'


# Generates the persistence file if it does not exist
if [ ! -f $PERSISTENCE_FILE ]; then
	echo $DEFAULT_HOST > $PERSISTENCE_FILE
fi

# A simple implementation of hostname selection persistence
if [ -z `cat $PERSISTENCE_FILE | grep "disabled"` ] && [ ! -z "`cat $PERSISTENCE_FILE`" ]; then
	ros_connect -n "`cat $PERSISTENCE_FILE`"
fi

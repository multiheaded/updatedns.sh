#!/usr/bin/env bash
SCRIPT=$(readlink -f $0)
SCRIPTPATH=$(dirname $SCRIPT)

CONFIGFILE="${SCRIPTPATH}/config.json"

PREFIX=/usr
ECHO=$PREFIX/bin/echo
WGET=$PREFIX/bin/wget
GREP=$PREFIX/bin/grep
NSUPDATE=$PREFIX/bin/nsupdate
DIG=$PREFIX/bin/dig
JQ=$PREFIX/bin/jq

UTILITIESFOUND=0
for prog in $ECHO $WGET $GREP $NSUPDATE $DIG $JQ
do
    test -x $prog || { echo "This program depends on the executable ${prog}! Please install it." >&2; UTILITIESFOUND=1; } 
done

if [ $UTILITIESFOUND -eq 1 ]
then
    exit 1
fi


args=`getopt c: $*`

set --  ${args}
while true; do
    case "${1}" in 
        -c)
            CONFIGFILE="${2}"
	    shift; shift;
            ;;
        --)
            shift; break;
            ;;
    esac
done

if ! [ -e ${CONFIGFILE} ]
then
    ${ECHO} "Config file \"${CONFIGFILE}\" not found! Exiting..." >&2
    exit 1
fi

#only support one entry for now
KEYFILE=$(${JQ} -r '.updatedns[0].Keyfile' ${CONFIGFILE})
IPV6SITE=$(${JQ} -r '.updatedns[0].IPv6Service' ${CONFIGFILE})
IPV4SITE=$(${JQ} -r '.updatedns[0].IPv4Service' ${CONFIGFILE})
DNSSERVER=$(${JQ} -r '.updatedns[0].DNSServer' ${CONFIGFILE})
ZONE=$(${JQ} -r '.updatedns[0].Zone' ${CONFIGFILE})
HOST=$(${JQ} -r '.updatedns[0].Host' ${CONFIGFILE})
TTL=$(${JQ} -r '.updatedns[0].TTL' ${CONFIGFILE})

SETTINGSPRESENT=0
for C in "KEYFILE" "IPV6SITE" "IPV4SITE" "DNSSERVER" "ZONE" "HOST" "TTL"
do
    VALUE="${!C}"
    echo "${VALUE}"
    test -z "${VALUE}" || test "${VALUE}" = "null" && { echo "${C} has not been properly configured." >&2; SETTINGSPRESENT=1; } 
done

if [ $SETTINGSPRESENT -eq 1 ]
then
    echo "Exiting..." >&2
    exit 1
fi

IPV4REGEX='([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})'
IPV6REGEX="(([0-9a-fA-F]{1,4}:){7,7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,7}:|([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})|:((:[0-9a-fA-F]{1,4}){1,7}|:)|fe80:(:[0-9a-fA-F]{0,4}){0,4}%[0-9a-zA-Z]{1,}|::(ffff(:0{1,4}){0,1}:){0,1}((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])|([0-9a-fA-F]{1,4}:){1,4}:((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9]))"

getIPAddr () {
    local CMD=$1
    local REGEX=$2
    local IP=$(${CMD} | ${GREP} -E -o ${REGEX})

    if [ ! -z "$IP" ]
    then
        echo $IP
        return 0
    else
        return 1
    fi
}

collectIPv4Addr() {
    getIPAddr "$WGET --quiet -O - $IPV4SITE" "$IPV4REGEX"
    return $?
}

collectIPv6Addr() {
    getIPAddr "$WGET --quiet -O - $IPV6SITE" "$IPV6REGEX"
    return $?
}

digAssignedIPv4Addr() {
    getIPAddr "${DIG} +noall +answer ${HOST} @${DNSSERVER} A" "$IPV4REGEX"
    return $?
}

digAssignedIPv6Addr() {
    getIPAddr "${DIG} +noall +answer ${HOST} @${DNSSERVER} AAAA" "$IPV6REGEX"
    return $?
}

generateRecordUpdateStr() {
    local FINDIP=$1
    local DIGIP=$2
    local RECORDTYPE=$3

    local SHOULDUPDATE=1
    local UPDATESTR=""

    local CURRENTIP=$($FINDIP)
    if [ $? -eq 0 ]
    then
        local DUGIP=$($DIGIP)
        if [ "a${CURRENTIP}" != "a${DUGIP}" ]
        then
            SHOULDUPDATE=0
            UPDATESTR="${UPDATESTR}$(${ECHO} -n "update delete ${HOST} ${RECORDTYPE}\n")"
            UPDATESTR="${UPDATESTR}$(${ECHO} -n "update add ${HOST} ${TTL} ${RECORDTYPE} ${CURRENTIP}\n")"
        else
            echo "No need to update ${RECORDTYPE} record, is set to ${CURRENTIP}" >&2
        fi
    fi

    ${ECHO} -n "$UPDATESTR"
    return $SHOULDUPDATE
}

generateUpdateQuery() {
    local QUERY=$(${ECHO} -n "server ${DNSSERVER}\nzone ${ZONE}\n" )

    QUERY="${QUERY}$(generateRecordUpdateStr collectIPv4Addr digAssignedIPv4Addr A)"
    QUERY="${QUERY}$(generateRecordUpdateStr collectIPv6Addr digAssignedIPv6Addr AAAA)"

    QUERY="${QUERY}$(${ECHO} -n "show\nsend\n")"

    ${ECHO} "$QUERY" | grep "update add" >/dev/null 2>&1 && { ${ECHO} -n "$QUERY"; return 0; }
    return 1
}

QUERY=$(generateUpdateQuery)

if [ $? -eq 0 ]
then
    ${ECHO} -e -n $QUERY | ${NSUPDATE} -k ${KEYFILE} >&2
fi



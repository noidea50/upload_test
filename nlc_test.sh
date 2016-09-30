#!/bin/bash

start=$(date +"%s")
bm_pass=UpSideD0wn
script_dir=`pwd`
alerts="./alerts.txt"
if [ ! -f ${alerts} ]; then
    touch ${alerts}
fi

set_env	()	{
# set env variables
bm_env=$(echo $bm_env | awk '{print toupper($0)}' )
if [ "$bm_env" = "PSTG" ]; then
    bm_user=bmpstg@us.ibm.com
    bm_env_url=https://api.stage1.ng.bluemix.net
    bm_orgs=$BM_PSTG_ORGS
elif [ "$bm_env" = "PPRD" ]; then
    bm_user=bmpprd@us.ibm.com
    bm_env_url=https://api.ng.bluemix.net
    bm_orgs=$BM_PPRD_ORGS
else
    echo "Missing or invalid environment: " $bm_env
    exit 1
fi
}

test_url() {
    local start=$(date +"%s")
    local test=$1
    echo ""
    echo "URL = "https://$url
    curl --request GET https://${url} --output ./${org_array[$i]}_body.txt --dump-header ./${org_array[$i]}_header.txt
    cat ./${org_array[$i]}_header.txt | grep "HTTP/1.1 200 OK"
    if [ $? -eq 0 ]; then
        echo "URL test successful"
    else
        echo "ERROR: nlc URL ${url} is not accessible" >> ${alerts}
    fi
    rm ./${org_array[$i]}*.txt
    local end=$(date +"%s")
    local time_elapsed=$(expr $end - $start | awk '{print int($1/60)":"int($1%60)}')
    echo "time elapsed for nlc url test is: ${time_elapsed} min:sec"
}


usage ()	{
	cat << EOF
	USAGE :: $progName -env [environment]

	example:
	./findInLogs.sh -env pstg 

EOF
        if [ ! -z "$1" ]; then
                exit $1;
        fi
}

check_space () {
ret_code=
num_nlc_running=
check_space=$(cf login -u ${bm_user} -p ${bm_pass} -o ${org_array[$i]} -s production | grep "not found")
if [ -z "$check_space" ]; then
    echo ""
    nlc_app=$(cf apps | grep "natural-language-classifier-tooling")
    if [ -n "$nlc_app" ]; then
        state=$(echo $nlc_app | awk '{print $2}')
        if [ "${state}" = "started" ]; then
            echo ""
            name=$(echo $nlc_app | awk '{print $1}')
            nlc_running=$((cf app ${name} | tee /dev/tty ) | awk -F"#" '{print $2 $3 $4 $5 $6}')
            num_nlc_running=$(echo $nlc_running | grep -o "running" | wc -l)
            if [[ "$num_nlc_running" -eq "5" ]]; then
                echo "Health check successful, all nlc services are running"
                #ret_code=$?
		url=$(cf apps | grep "nlc" | awk '{print $7}' | tr -d '[[:space:]]')
		test_url ${url}
            elif [[ "$num_nlc_running" -gt "0" ]]; then
		echo "org= ${org_array[$i]}, ALERT: Only ${num_nlc_running}/5 nlc services are running" >> ${alerts}
            else
		echo "org=${org_array[$i]}, ERROR: No nlc services are running!!" >> ${alerts}
            fi
        fi
    else
        echo "org=${org_array[$i]}, ERROR: Could not find a valid nlc app" >> ${alerts}
    fi
    echo ""
else
    echo "ERROR:" ${check_space}
    echo "org=${org_array[$i]},ERROR: nlc service could not be found" >> ${alerts}
fi
}

#####################################################
# Check for no arguments
if [ $# -eq 0 ]; then
        echo "ERROR:no arguments supplied"    
        usage 0
        exit $1;
fi
#####################################################
# Parse input arguments
export LOCAL_ARGS=""
while [ $# -gt 0 ]; do
	arg=$( tr '[:upper:]' '[:lower:]' <<< $1 )
	case $arg in
	"-env") shift
 	   	bm_env=$1
    		shift
	    	;;
	"-help"|"-?") shift
		usage 0
		shift
		;;
	*)
		echo "Invalid argument: ${arg}"
    		usage 1
    		;;
	esac
done
#####################################################
# Main script
# Source env file
source ${script_dir}/org.properties.env
main_test="total org test"
echo ""
set_env

# Set Blue Mix endpoint
cf api ${bm_env_url}

org_array=($bm_orgs)
echo ""
echo "BM url is : " ${bm_env_url}
echo "BM user is : " ${bm_user}
num_orgs=$((${#org_array[@]}))
echo ${bm_env} " Organizations to be tested [${num_orgs}] are: " ${org_array[@]}
echo ""
#echo "Number of identified orgs to be tested = " $num_orgs

# Login into each identified org unit
for((i=0; i<$num_orgs; ++i)) do
    echo ""
    echo "Testing org: " ${org_array[$i]}
    check_space
    echo ""
    cf logout
done
num_errors=$(cat ${alerts} | wc -l)
echo ""
echo $num_errors " errors found"
cat ${alerts}

# clear the contents of the alerts file
> ${alerts}
end=$(date +"%s")
time_elapsed=$(expr $end - $start | awk '{print int($1/60)":"int($1%60)}')
echo "Total test time is: ${time_elapsed} min:sec"

#!/bin/bash

NC='\033[0m'
red()      { TSTAMP=$(date +"%Y-%m-%d %H:%M:%S"); echo -e "\033[0;31m$TSTAMP $@${NC}";}
blue()     { TSTAMP=$(date +"%Y-%m-%d %H:%M:%S"); echo -e "\033[0;96m$TSTAMP $@${NC}";}
green()    { TSTAMP=$(date +"%Y-%m-%d %H:%M:%S"); echo -e "\033[1;32m$TSTAMP $@${NC}";}
yellow()   { TSTAMP=$(date +"%Y-%m-%d %H:%M:%S"); echo -e "\033[0;33m$TSTAMP $@${NC}";}
darkGreen(){ TSTAMP=$(date +"%Y-%m-%d %H:%M:%S"); echo -e "\033[38;5;002m$TSTAMP $@${NC}";}

CURL_OPTS="-s -k"
#CURL_OPTS=-v
TOKEN=
GRAPHQ_SERVER=https://api.veritone.com
GRAPHQL_API_URL=${GRAPHQL_SERVER}/v3/graphql
green "Using GRAPHQL_API_URL=$GRAPHQL_API_URL"
OUTDIR=tmpres
mkdir -p $OUTDIR

## -------------------------------------------------------------------------------
## creating a recording, upload the file as specified by $1 parameter
## and generate the {recording_id}.json
## -------------------------------------------------------------------------------
##
function createRecording {
    local filename=$1
    local base_filename=$(basename $filename)
    local task_output_file=${OUTDIR}/recording_id.json
    local recording_id=""
    local start_datetime=$(date "+%s")
    local duration_float=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 $filename)
    DURATION=$(echo "$duration_float/1" | bc)
    local stop_datetime=$(($start_datetime + DURATION))
#    echo -------------------------------------------------------------------
    echo "Create recording for $filename, $start_datetime, $stop_datetime, $DURATION"
#    echo -------------------------------------------------------------------
    local query_string="mutation { createTDO(input: {startDateTime: '$start_datetime', stopDateTime: '$stop_datetime', status: \"recording\", details: { veritoneFile: { filename: \"$base_filename\"}}}){id details}}"
    echo querystring = ${query_string}
    curl ${CURL_OPTS} -H "Authorization: Bearer $TOKEN" -H "Content-type: application/json" -o ${task_output_file} \
        -d '{"query":"mutation { createTDO(input: {startDateTime: '$start_datetime', stopDateTime: '$stop_datetime', status: \"recording\", details: { veritoneFile: { filename: \"'$base_filename'\"}}}){id details}}"}' \
    ${GRAPHQL_API_URL}
    cat $task_output_file| jq -e '.data.createTDO.id' > /dev/null
    if [ $? -eq 0 ]; then
        recording_id=$(cat $task_output_file| jq '.data.createTDO.id'|sed "s/\"//g")
        green "OK. Recording_id=${recording_id}"
    else
        red "Failed to create recording."
        cat ${task_output_file}
        exit 1
    fi

#    echo -----------------------
    echo Upload Asset GraphQL
#    echo -----------------------
    echo "Uploading ${filename} to recording ${recording_id}..."
    local asset_result=${OUTDIR}/${recording_id}_asset.txt
    #AS_URI=1
    if [ -z $AS_URI ];
    then
       ## real streaming here
       query_string="mutation {createAsset(input:  {containerId:  \"$recording_id\", assetType:\"media\", contentType:\"audio/wav\", fileData:{originalFileUri:\"$filename\"}}){id}}"
       echo querystring = ${query_string}
       curl ${CURL_OPTS} -XPOST -H "Authorization: Bearer $TOKEN" -o ${asset_result} -F file=@${filename} -F query="${query_string}" ${GRAPHQL_API_URL}
    else
        echo "Storing FILE as URI"
        curl ${CURL_OPTS} -H "Authorization: Bearer $TOKEN" -H "Content-type: application/json" -o ${asset_result} \
            -d '{"query":"mutation {createAsset(input:  {containerId:  \"'$recording_id'\", assetType:\"media\", contentType:\"audio/mp3\", uri:\"'$filename'\"}){id}}"}' \
        ${GRAPHQL_API_URL}
    fi
    cat $asset_result | jq -e '.data.createAsset.id' > /dev/null
    if [ $? -eq 0 ]; then
        local local_asset_id=$(cat $asset_result | jq '.data.createAsset.id')
        green "OK. Asset=${local_asset_id} created for Recording=${recording_id}"
    else
        red "Failed to create asset for recording."
        cat ${$asset_result}
        exit 1
    fi

    RECORDING_ID=${recording_id}
}
filesize () {
  local filename=$1
  local afilesize=`(
  du --apparent-size --block-size=1 "$filename" 2>/dev/null ||
  gdu --apparent-size --block-size=1 "$filename" 2>/dev/null ||
  find "$filename" -printf "%s" 2>/dev/null ||
  gfind "$filename" -printf "%s" 2>/dev/null ||
  stat --printf="%s" "$filename" 2>/dev/null ||
  stat -f%z "$filename" 2>/dev/null ||
  wc -c <"$filename" 2>/dev/null
) | awk '{print $1}'`
  echo $afilesize
}

## Given  recording_id, look up job to make sure that
## ntasks are retrieved
function verify  {
    local recording_id=$1
    local expectedNTasks=$2
    local recording_output_file=$OUTDIR/${recording_id}-verify.json
    JOB_DONE=true
    curl ${CURL_OPTS} -H "Authorization: Bearer $TOKEN"  -H "Content-type: application/json"  -o ${recording_output_file}  \
-d '{"query":"{temporalDataObject(id: \"'${recording_id}'\") {id tasks {count records{jobId id engineId status log{text}}}}}"}' \
  ${GRAPHQL_API_URL}
    cat ${recording_output_file} | jq -e '.data.temporalDataObject.tasks.count' > /dev/null
    if [ $? -eq 0 ]; then
        nTasks=$(cat ${recording_output_file} | jq '.data.temporalDataObject.tasks.count'  | sed 's/\"//g')
        if [ "$nTasks" -ne "$expectedNTasks" ]; then
            red "Failed to create tasks for ${recording_id}.  Found only ${nTasks} tasks instead of ${expectedNTasks}"
            exit 1
        fi

        j=0
        (( nTasks -- ))
        for i in $(seq 0 $nTasks); do
          status=`cat ${recording_output_file} | jq ".data.temporalDataObject.tasks.records[${i}].status" | sed 's/\"//g'`
          taskId=`cat ${recording_output_file} | jq ".data.temporalDataObject.tasks.records[${i}].id" | sed 's/\"//g'`
          engineId=`cat ${recording_output_file} | jq ".data.temporalDataObject.tasks.records[${i}].engineId" | sed 's/\"//g'`
          if [ "$status" != "complete" ]; then
             if [ "$status" == "failed" ]; then
                JOB_DONE=true
                red "$taskId (engine=$engineId) has status=${status}"
             else
             	JOB_DONE=false
             	yellow "$taskId (engine=$engineId) has status=${status}"
             fi
          fi
        done
        if [ "$JOB_DONE" = "true" ]; then
            green "All tasks are finished for ${recording_id}"
            cat ${recording_output_file} | jq ''
        fi
    else
        red "Failed to retrieve tasks started for ${recording_id}"
        exit 1
    fi
}
# ------ START HERE.......
blue "--------------------------------------------------------------------"
blue " Testing ENGINE_ID=${ENGINE_ID}"
blue "--------------------------------------------------------------------"
if [ -z $AIWARE_GRAPHIQL_TOKEN ]; then
    echo "Please define $AIWARE_GRAPHIQL_TOKEN"
    exit 1
fi
TOKEN="${AIWARE_GRAPHIQL_TOKEN}"
if [[ $# -eq 0 ]]; then
     ASSET_FILE=simple.wav
else
     ASSET_FILE=$1
fi
createRecording $ASSET_FILE
expectedNTasks=1
if [ -z $TRANSCODE_IT ]; then
    createJobViaGraphQL ${RECORDING_ID}
else
    createJobWithTranscodingViaGraphQL ${RECORDING_ID}
    expectedNTasks=2
fi
timestamp=$(date "+%s")
fsize=$(filesize $ASSET_FILE)
echo ${timestamp},${RECORDING_ID},${ASSET_FILE},${DURATION},$fsize,${JOB_ID} >> ${OUTFILE}


## if we can get the DURATION, make sure they know that the

if [ ! -z $NO_VERIFY ]; then
fi
#echo "-----------------------------------------------"
echo "Checking tasks for ${RECORDING_ID}"
#echo "-----------------------------------------------"

JOB_DONE=false

TEN_MIN=600
TWO_MIN=120
SLEEP=15s
## Determining the sleep interval depending on the DURATION of the media
if [ "$DURATION" -gt "$TEN_MIN" ]; then
   SLEEP=60s
else
  if [ "$DURATION" -gt "$TWO_MIN" ]; then
     SLEEP=30s
  fi
fi

while [ "$JOB_DONE" = "false" ]
do
    yellow "Sleeping for $SLEEP before checking job status.."
    sleep $SLEEP
    verify ${RECORDING_ID} ${expectedNTasks}
done
exit 0

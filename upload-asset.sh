#!/bin/bash

NC='\033[0m'
red()      { TSTAMP=$(date +"%Y-%m-%d %H:%M:%S"); echo -e "\033[0;31m$TSTAMP $@${NC}";}
blue()     { TSTAMP=$(date +"%Y-%m-%d %H:%M:%S"); echo -e "\033[0;96m$TSTAMP $@${NC}";}
green()    { TSTAMP=$(date +"%Y-%m-%d %H:%M:%S"); echo -e "\033[1;32m$TSTAMP $@${NC}";}
yellow()   { TSTAMP=$(date +"%Y-%m-%d %H:%M:%S"); echo -e "\033[0;33m$TSTAMP $@${NC}";}
darkGreen(){ TSTAMP=$(date +"%Y-%m-%d %H:%M:%S"); echo -e "\033[38;5;002m$TSTAMP $@${NC}";}

#TODO : Define these values
#TOKEN=
#ASSET_FILE
#ASSET_TYPE=
#CONTENT_TYPE=
#SOURCE
#RECORDING_ID=



CURL_OPTS="-s -k"
#CURL_OPTS=-v
GRAPHQL_SERVER=https://api.veritone.com
GRAPHQL_API_URL=${GRAPHQL_SERVER}/v3/graphql
green "Using GRAPHQL_API_URL=$GRAPHQL_API_URL"
OUTDIR=tmpres
mkdir -p $OUTDIR

## -------------------------------------------------------------------------------
## Upload filename ($1) as an asset to recording ($2)
## -------------------------------------------------------------------------------
##
function uploadAsset () {
    local filename=$1
    local recording_id=$2
    local asset_type=$3
    local content_type=$4
    local source=$5
    local base_filename=$(basename $filename)
#    echo -----------------------
    echo Upload Asset GraphQL
#    echo -----------------------
    echo "Uploading ${filename} to recording ${recording_id}..."
    local asset_result=${OUTDIR}/${recording_id}_asset.txt
    #AS_URI=1
    if [ -z $AS_URI ];
    then
       ## real streaming here
       query_string="mutation {createAsset(input:  {containerId:  \"$recording_id\", assetType:\"$asset_type\", contentType:\"$content_type\", fileData:{originalFileUri:\"$filename\"}jsondata:{source :\"$source\"}}){id signedUri}}"
       echo querystring = ${query_string}
       set -x
       curl ${CURL_OPTS} -XPOST -H "Authorization: Bearer $TOKEN" -o ${asset_result} -F file=@${filename} -F query="${query_string}" ${GRAPHQL_API_URL}
       set +x
    fi
    cat $asset_result | jq -e '.data.createAsset.id' > /dev/null
    if [ $? -eq 0 ]; then
        local local_asset_id=$(cat $asset_result | jq '.data.createAsset.id')
        green "OK. Asset=${local_asset_id} created for Recording=${recording_id}"
    else
        red "Failed to create asset for recording."
        cat ${$asset_result} | jq ''
        exit 1
    fi
}

# ------ START HERE.......
blue "--------------------------------------------------------------------"
blue "--------------------------------------------------------------------"
if [ -z $TOKEN ]; then
    echo "Please define TOKEN"
    exit 1
fi
if [ -z $ASSET_FILE ]; then
   echo "Please define ASSET_FILE"
   exit 1
fi
if [ -z $ASSET_TYPE ]; then
   ASSET_TYPE='v-human-transcript'
fi
if [ -z $CONTENT_TYPE ]; then
   CONTENT_TYPE='text/plain'
fi
if [ -z $RECORDING_ID ]; then
   ## infer from the file name without extension
  f=${ASSET_FILE##*/}
  RECORDING_ID="${f%.*}"
fi
if [ -z $SOURCE ]; then
  SOURCE='human-transcript'
fi

echo GOT the following:
echo ASSET_FILE=$ASSET_FILE
echo ASSET_TYPE=$ASSET_TYPE
echo CONTENT_TYPE=$CONTENT_TYPE
echo RECORDING_ID=$RECORDING_ID
echo SOURCE=$SOURCE

uploadAsset $ASSET_FILE $RECORDING_ID $ASSET_TYPE $CONTENT_TYPE $SOURCE


#!/usr/bin/env bash

#
# We expect the user to (at least) provide the output ZIP.
#
[ $# -eq 0 ] && exit 1

#
# The user must export the organization/profile name and
# their token, so we can upload everything.
#
[[ -z "${GITHUB_TOKEN}" ]] && exit 1
[[ -z "${ORGANIZATION_NAME}" ]] && exit 1

#
# Extract all the information from the ZIP.
#
ZIP_PATH="$1"
ZIP_VARS=($(echo $ZIP_PATH | tr "-" "\n"))
ZIP_NAME=$(basename $ZIP_PATH)

#
# Base URL used to upload the ZIP to GitHub
#
BASE_RELEASE_URL="https://github.com/$ORGANIZATION_NAME/android_device_amazon_$(echo ${ZIP_VARS[4]} | cut -f1 -d'.')/releases"

#
# Base URL used to upload the JSON to GitHub
#
BASE_OTAS_URL="git@github.com:R0rt1z2/OTA.git"

#
# Simple logger to print messages with different verbosity
#
loge() { echo -e "\033[0;31m[!]: ${1} \033[0m"; }
logi() { echo -e "\033[0;33m[*]: ${1} \033[0m"; }
logs() { echo -e "\033[0;32m[+]: ${1} \033[0m"; }

#
# Dump all the variables and generate the OTA json
#
dumpvars() {
    METADATA=$(unzip -p "$ZIP_PATH" META-INF/com/android/metadata)
    DEVICE=$(echo "$METADATA" | grep pre-device | cut -f2 -d '=' | cut -f1 -d ',')
    SDK_LEVEL=$(echo "$METADATA" | grep post-sdk-level | cut -f2 -d '=')
    TIMESTAMP=$(echo "$METADATA" | grep post-timestamp | cut -f2 -d '=')
    DATE=$(echo $FILENAME | cut -f3 -d '-')
    ID=$(echo ${TIMESTAMP}${DEVICE}${SDK_LEVEL} | sha256sum | cut -f 1 -d ' ')
    SIZE=$(stat -c%s "$ZIP_PATH")
    TYPE=${ZIP_VARS[3]}
    VERSION=${ZIP_VARS[1]}
}

#
# Fetch all the available versions for the desired device
# and decide the build version for the new build.
#
get_new_version() {
    local cur_version='1'
    local new_version='0'

    while [ "$new_version" == "0" ]
    do
        if curl --head --silent --fail "$BASE_RELEASE_URL/tag/$VERSION-$cur_version.0" &>/dev/null;
          then
            cur_version=$(($cur_version+1))
          else
            new_version="$VERSION-$cur_version.0"
        fi
    done

    echo $new_version
}

#
# Uploads everything (both the json and the zip file) to GitHub
#
upload_everything() {
    # JSON
    rm -fr OTA &>/dev/null && git clone $BASE_OTAS_URL &>/dev/null
    mv lineageos_$DEVICE.json OTA/ && cd OTA && git add . &&
        git commit -m "OTA: [$DEVICE]: LineageOS $VERSION - $(date '+%Y-%m-%d')" &>/dev/null &&
           git push -f && cd ..

    # ZIP
    GITHUB_REPO="https://api.github.com/repos/$ORGANIZATION_NAME/android_device_amazon_$DEVICE"
    AUTH="Authorization: token $GITHUB_TOKEN"
    TAG=$(get_new_version)
    TAG_INFO=$(curl -H "$AUTH" "$GITHUB_REPO/releases/tags/$TAG")
    TAG_ID=$(curl -X POST "$GITHUB_REPO/releases" -H "$AUTH" -d "{\"tag_name\": \"$TAG\", \"target_commitish\": \"lineage-$VERSION\", \"name\": \"LineageOS $VERSION for $DEVICE\", \"body\": \"\"}" | jq '.id')
    GITHUB_ASSET="https://uploads.github.com/repos/$ORGANIZATION_NAME/android_device_amazon_$DEVICE/releases/$TAG_ID/assets?name=$ZIP_NAME"
    LOG=$(curl -T "$ZIP_PATH" -H "$AUTH" -H "Content-Type: $(file -b --mime-type "$ZIP_PATH")" "$GITHUB_ASSET")
    DLOAD_URL=$(jq -r '.browser_download_url' <<<"$LOG")
    [[ $DLOAD_URL == null ]] && loge "Couldn't upload $ZIP_NAME!" || logs $DLOAD_URL
}

logi "Dumping $ZIP_NAME vars..."

dumpvars
echo """{
  \"response\": [
    {
      \"datetime\": \"$TIMESTAMP\",
      \"filename\": \"$ZIP_NAME\",
      \"id\": \"$ID\",
      \"romtype\": \"$TYPE\",
      \"size\": \"$SIZE\",
      \"url\": \"$BASE_RELEASE_URL/download/$(get_new_version)/$ZIP_NAME\",
      \"version\": \"$VERSION\"
    }
  ]
}""" > lineageos_$DEVICE.json

logi "Uploading $ZIP_NAME..."
upload_everything

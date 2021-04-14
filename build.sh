#! /bin/bash
set -e

# basic var setting
if [[ -z "$1" && -z "$2" ]]; then
  echo "This script requires 2 arguments"
  exit 1
fi
TYPE="$1"
ARG="$2"

alias dockerRun='docker run --rm -i'

main() {
  case "$TYPE" in
    "compare") # compare external endpoints file to this one after being tagged
      CloneRepo templateout development
      cp endpoints.template templateout/
      dockerRun -v $(pwd)/templateout:/buildout -e RELEASE_TAG=${ARG} ghcr.io/netbootxyz/yaml-merge
      CheckFileChanged templateout/endpoints.yml ;;
    "versioning") # generate the releases file and compare it to the merged one in the main repo
      CloneRepo templateout development
      cp releases.template templateout/
      dockerRun -v $(pwd)/templateout:/buildout -e VERSION="${ARG}" \
        ghcr.io/netbootxyz/yaml-merge:external /buildout/roles/netbootxyz/defaults/main.yml /buildout/releases.template
      CheckFileChanged templateout/roles/netbootxyz/defaults/main.yml ;;
    "build") # build the output contents based on build type
      BuildImages ;;
    "endpoints") # commit the new release upstream to be included in the boot menus
      VersionBump "internal" ;;
    "releases")  # commit the new external version upstream to be included in the boot menus
      VersionBump "external" ;;
    "discord") # send status to discord
      NotifyDiscord ;;
  esac
}

ReplaceVersion() {
  sed -i "s/REPLACE_VERSION/${EXTERNAL_VERSION}/g" settings.sh
  sed -i "s/REPLACE_VERSION/${EXTERNAL_VERSION}/g" endpoints.template
}
BuildImages() {
  alias dockerRunBuildOut='dockerRun -v $(pwd)/buildout:/buildout'
  case "${ARG}" in
    "iso_extraction")
      ReplaceVersion
      mkdir -p buildout
      cp settings.sh buildout/settings.sh
      dockerRunBuildOut ghcr.io/netbootxyz/iso-processor
      ;;
   "initrd_layer")
      ReplaceVersion
      mkdir -p buildout
      cp settings.sh buildout/settings.sh
      dockerRun -v $(pwd)/buildout:/buildout ghcr.io/netbootxyz/iso-processor
      sudo docker build --no-cache --build-arg EXTERNAL_VERSION=${EXTERNAL_VERSION} -t files .
      dockerRunBuildOut files
      ;;
    "custom_kernel")
      docker build --no-cache -f Dockerfile --build-arg EXTERNAL_VERSION=${EXTERNAL_VERSION} -t kernel .
      mkdir -p buildout
      dockerRunBuildOut kernel
      ;;
    "initrd_patch")
      ReplaceVersion
      mkdir -p buildout
      cp settings.sh buildout/settings.sh
      dockerRunBuildOut ghcr.io/netbootxyz/iso-processor
      sudo docker build --no-cache -f Dockerfile --build-arg EXTERNAL_VERSION=${EXTERNAL_VERSION} -t files .
      dockerRunBuildOut files
      mv buildout buildin
      mkdir -p buildout
      cp settings.sh buildout/settings.sh
      dockerRunBuildOut -v $(pwd)/buildin:/buildin -e COMPRESS_INITRD="true" ghcr.io/netbootxyz/iso-processor
      ;;
    "direct_file")
      ReplaceVersion
      mkdir -p buildout
      source settings.sh
      while read -r DL; do
        URL="${DL%|*}"
        OUT="${DL#*|}"
        curl -Lf "${URL}" -o buildout/"${OUT}"
      done <<< "${DOWNLOADS}"
      ;;
  esac
  if [[ -f "post-processing.sh" ]]; then
    sudo bash post-processing.sh
  fi
}

VersionBump() {
  local type="$1"
  mkdir remote && cd $_
  CloneRepo . development
  if [[ "$type" == "internal" ]]; then
      cp endpoints.yml ../templateout/
      docker run --rm -i -e RELEASE_TAG="NULL" -v $(pwd)/../templateout:/buildout ghcr.io/netbootxyz/yaml-merge
      PushMergedToRepo endpoints.yml "Version bump for ${GITHUB_ENDPOINT}:${BRANCH} new tag ${ARG}"
      ;;
  elif [[ "$type" == "external" ]]; then
      PushChangeToRepo roles/netbootxyz/defaults/main.yml "External Version bump for ${BRANCH} new version string \"${ARG}\" "
      ;;
  fi
  git push https://netboot-ci:${CI_TOKEN}@github.com/netbootxyz/netboot.xyz.git --all
  git rev-parse HEAD | cut -c1-8 > ../commit.txt ;;
}


NotifyDiscord() {
  case "${ARG}" in 
    "success")
      curl -X POST -H "Content-Type: application/json" --data \
      '{
        "avatar_url": "https://api.microlink.io/?url=https://twitter.com/github&embed=image.url",
        "embeds": [
          {
            "color": 1681177,
            "description": "__**New Asset Published**__ \n**Release:**  https://github.com/'${GITHUB_REPOSITORY}'/releases/tag/'${GITHUB_TAG}'\n**Version Bump:**  https://github.com/netbootxyz/netboot.xyz/commit/'$(cat commit.txt)'\n**Build:**  https://github.com/'${GITHUB_REPOSITORY}'/actions/runs/'${GITHUB_RUN_ID}'\n**Workflow Name:**  '${GITHUB_WORKFLOW}'\n**External Version:**  '${EXTERNAL_VERSION}'\n**Status:**  Success\n**Change:** https://github.com/'${GITHUB_REPOSITORY}'/commit/'${GITHUB_SHA}'\n"
          }
        ],
        "username": "Github"
      }' \
      ${DISCORD_HOOK_URL}
      ;;
    "failure" ]; then
      curl -X POST -H "Content-Type: application/json" --data \
      '{
        "avatar_url": "https://api.microlink.io/?url=https://twitter.com/github&embed=image.url",
        "embeds": [
          {
            "color": 16711680,
            "description": "**Build:**  https://github.com/'${GITHUB_REPOSITORY}'/actions/runs/'${GITHUB_RUN_ID}'\n**Workflow Name:**  '${GITHUB_WORKFLOW}'\n**External Version:**  '${EXTERNAL_VERSION}'\n**Status:**  Failure\n**Change:** https://github.com/'${GITHUB_REPOSITORY}'/commit/'${GITHUB_SHA}'\n"
          }
        ],
        "username": "Github"
      }' \
      ${DISCORD_HOOK_URL}
      ;;
    "versiongood" ]; then
      curl -X POST -H "Content-Type: application/json" --data \
      '{
        "avatar_url": "https://api.microlink.io/?url=https://twitter.com/github&embed=image.url",
        "embeds": [
          {
            "color": 1681177,
            "description": "__**New Version Detected**__ \n**Version Bump:**  https://github.com/netbootxyz/netboot.xyz/commit/'$(cat commit.txt)'\n**Workflow Name:**  '${GITHUB_WORKFLOW}'\n**Build:**  https://github.com/'${GITHUB_REPOSITORY}'/actions/runs/'${GITHUB_RUN_ID}'\n**Status:**  Success\n**Change:** https://github.com/'${GITHUB_REPOSITORY}'/commit/'${GITHUB_SHA}'\n"
          }
        ],
        "username": "Github"
      }' \
      ${DISCORD_HOOK_URL}
      ;;
    "versionbad" ]; then
      curl -X POST -H "Content-Type: application/json" --data \
      '{
        "avatar_url": "https://api.microlink.io/?url=https://twitter.com/github&embed=image.url",
        "embeds": [
          {
            "color": 16711680,
            "description": "**Build:**  https://github.com/'${GITHUB_REPOSITORY}'/actions/runs/'${GITHUB_RUN_ID}'\n**Workflow Name:**  '${GITHUB_WORKFLOW}'\n**Status:**  Failure\n**Change:** https://github.com/'${GITHUB_REPOSITORY}'/commit/'${GITHUB_SHA}'\n"
          }
        ],
        "username": "Github"
      }' \
      ${DISCORD_HOOK_URL}
      ;;
    *)
      exit 1
      ;;
  esac
}

CloneRepo() {
  local dir="$1"
  local branch="$2"
  [[ -n "$branch" ]] && branch="-b $branch"
  git clone https://github.com/netbootxyz/netboot.xyz.git $branch $dir
}

PushChangeToRepo() {
  local filename="$1"
  local commitMessage="$2"
  cp ../templateout/merged.yml "$filename"
  git add "$filename"
  git commit -m "$commitMessage"
  git push https://netboot-ci:${CI_TOKEN}@github.com/netbootxyz/netboot.xyz.git --all
  git rev-parse HEAD | cut -c1-8 > ../commit.txt
} 

CheckFileChanged() {
  local filename="$1"
  local currentHash=$(md5sum "$filename" | cut -c1-8)
  local newHash=$(md5sum templateout/merged.yml | cut -c1-8)
  # This has allready been pushed just kill off build
  if [[ "${CURRENTHASH}" == "${NEWHASH}" ]]; then
    echo "Hash is same, exiting..."
    exit 1
  fi
  echo "Hash is different.  Continuing..."
}

# call the function at the top, having read the script
main

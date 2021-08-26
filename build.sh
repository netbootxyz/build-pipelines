#! /bin/bash
set -e

# basic var setting
if [ -z "$1" ] && [ -z "$2" ]; then
  echo "This script requires 2 arguments"
  exit 1
fi
TYPE="$1"
ARG="$2"


# compare external endpoints file to this one after being tagged
if [ "${TYPE}" == "compare" ]; then
  git clone https://github.com/netbootxyz/netboot.xyz.git -b development templateout
  sed -i "s/REPLACE_VERSION/${EXTERNAL_VERSION}/g" endpoints.template
  cp endpoints.template templateout/
  docker run --rm -i -e RELEASE_TAG=${ARG} -v $(pwd)/templateout:/buildout ghcr.io/netbootxyz/yaml-merge
  CURRENTHASH=$(md5sum templateout/endpoints.yml | cut -c1-8)
  NEWHASH=$(md5sum templateout/merged.yml | cut -c1-8)
  # This has allready been pushed just kill off the build
  if [[ "${CURRENTHASH}" == "${NEWHASH}" ]]; then
    exit 1
  fi
fi

# generate the releases file and compare it to the merged one in the main repo
if [ "${TYPE}" == "versioning" ]; then
  git clone https://github.com/netbootxyz/netboot.xyz.git -b development templateout
  cp releases.template templateout/
  docker run --rm -i -e VERSION="${ARG}" -v $(pwd)/templateout:/buildout ghcr.io/netbootxyz/yaml-merge:external /buildout/roles/netbootxyz/defaults/main.yml /buildout/releases.template
  CURRENTHASH=$(md5sum templateout/roles/netbootxyz/defaults/main.yml | cut -c1-8)
  NEWHASH=$(md5sum templateout/merged.yml | cut -c1-8)
  # This has allready been pushed just kill off build
  if [[ "${CURRENTHASH}" == "${NEWHASH}" ]]; then
    echo "Hash is same, exiting..."
    exit 1
  fi
  echo "Hash is different.  Continuing..."
fi

# build the output contents based on build type
if [ "${TYPE}" == "build" ]; then
  if [ "${ARG}" == "iso_extraction" ]; then
    sed -i "s/REPLACE_VERSION/${EXTERNAL_VERSION}/g" settings.sh
    mkdir -p buildout
    cp settings.sh buildout/settings.sh
    docker run --rm -i -v $(pwd)/buildout:/buildout ghcr.io/netbootxyz/iso-processor
  elif [ "${ARG}" == "initrd_layer" ]; then
    sed -i "s/REPLACE_VERSION/${EXTERNAL_VERSION}/g" settings.sh
    mkdir -p buildout
    cp settings.sh buildout/settings.sh
    docker run --rm -i -v $(pwd)/buildout:/buildout ghcr.io/netbootxyz/iso-processor
    sudo docker build --no-cache -f Dockerfile --build-arg EXTERNAL_VERSION=${EXTERNAL_VERSION} -t files .
    docker run --rm -i -v $(pwd)/buildout:/buildout files
  elif [ "${ARG}" == "custom_kernel" ]; then
    docker build --no-cache -f Dockerfile --build-arg EXTERNAL_VERSION=${EXTERNAL_VERSION} -t kernel .
    mkdir -p buildout
    docker run --rm -i -v $(pwd)/buildout:/buildout kernel
  elif [ "${ARG}" == "initrd_patch" ]; then
    sed -i "s/REPLACE_VERSION/${EXTERNAL_VERSION}/g" settings.sh
    mkdir -p buildout
    cp settings.sh buildout/settings.sh
    docker run --rm -i -v $(pwd)/buildout:/buildout ghcr.io/netbootxyz/iso-processor
    sudo docker build --no-cache -f Dockerfile --build-arg EXTERNAL_VERSION=${EXTERNAL_VERSION} -t files .
    docker run --rm -i -v $(pwd)/buildout:/buildout files
    mv buildout buildin
    mkdir -p buildout
    cp settings.sh buildout/settings.sh
    docker run --rm -i -e COMPRESS_INITRD="true" -v $(pwd)/buildout:/buildout -v $(pwd)/buildin:/buildin ghcr.io/netbootxyz/iso-processor
  elif [ "${ARG}" == "direct_file" ]; then
    sed -i "s/REPLACE_VERSION/${EXTERNAL_VERSION}/g" settings.sh
    mkdir -p buildout
    source settings.sh
    while read -r DL; do
      URL="${DL%|*}"
      OUT="${DL#*|}"
      curl -Lf "${URL}" -o buildout/"${OUT}"
    done <<< "${DOWNLOADS}"
  fi
  if [ -f "post-processing.sh" ]; then
    sudo bash post-processing.sh
  fi
fi

# commit the new release upstream to be included in the boot menus
if [ "${TYPE}" == "endpoints" ]; then
  mkdir remote
  git clone https://github.com/netbootxyz/netboot.xyz.git remote
  cd remote
  git checkout -f development
  cp endpoints.yml ../templateout/
  docker run --rm -i -e RELEASE_TAG="NULL" -v $(pwd)/../templateout:/buildout ghcr.io/netbootxyz/yaml-merge
  cp ../templateout/merged.yml endpoints.yml
  git add endpoints.yml
  git commit -m "Version bump for ${GITHUB_ENDPOINT}:${BRANCH} new tag ${ARG}"
  git push https://netboot-ci:${CI_TOKEN}@github.com/netbootxyz/netboot.xyz.git --all
  git rev-parse HEAD | cut -c1-8 > ../commit.txt
fi

# commit the new external version upstream to be included in the boot menus
if [ "${TYPE}" == "releases" ]; then
  mkdir remote
  git clone https://github.com/netbootxyz/netboot.xyz.git remote
  cd remote
  git checkout -f development
  cp ../templateout/merged.yml roles/netbootxyz/defaults/main.yml
  git add roles/netbootxyz/defaults/main.yml
  git commit -m "External Version bump for ${BRANCH} new version string \"${ARG}\" "
  git push https://netboot-ci:${CI_TOKEN}@github.com/netbootxyz/netboot.xyz.git --all
  git rev-parse HEAD | cut -c1-8 > ../commit.txt
fi

# send status to discord
if [ "${TYPE}" == "discord" ]; then
  if [ "${ARG}" == "success" ]; then
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
  elif [ "${ARG}" == "failure" ]; then
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
  elif [ "${ARG}" == "versiongood" ]; then
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
  elif [ "${ARG}" == "versionbad" ]; then
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
  else
    exit 1
  fi
fi

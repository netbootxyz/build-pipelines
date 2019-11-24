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
  cp endpoints.template templateout/
  docker run --rm -it -e RELEASE_TAG=${ARG} -v $(pwd)/templateout:/buildout netbootxyz/yaml-merge
  CURRENTHASH=$(md5sum templateout/endpoints.yml | cut -c1-8)
  NEWHASH=$(md5sum templateout/merged.yml | cut -c1-8)
  # This has allready been pushed just kill off travis build
  if [[ "${CURRENTHASH}" == "${NEWHASH}" ]]; then
    exit 1
  fi
fi


# build the output contents based on build type
if [ "${TYPE}" == "build" ]; then
  if [ "${ARG}" == "iso_extraction" ]; then
    sed -i "s/REPLACE_VERSION/${EXTERNAL_VERSION}/g" settings.sh
    mkdir -p buildout
    cp settings.sh buildout/settings.sh
    docker run --rm -it -v $(pwd)/buildout:/buildout netbootxyz/iso-processor
  elif [ "${ARG}" == "custom_kernel" ]; then
    docker build --no-cache -f Dockerfile --build-arg EXTERNAL_VERSION=${EXTERNAL_VERSION} -t kernel .
    mkdir -p buildout
    docker run --rm -it -v $(pwd)/buildout:/buildout kernel
  else
    exit 1
  fi
fi

# commit the new release upstream to be included in the boot menus
if [ "${TYPE}" == "endpoints" ]; then
  mkdir remote
  git clone https://github.com/netbootxyz/netboot.xyz.git remote
  cd remote
  git checkout -f development
  cp endpoints.yml ../templateout/
  docker run --rm -it -e RELEASE_TAG="NULL" -v $(pwd)/../templateout:/buildout netbootxyz/yaml-merge
  cp ../templateout/merged.yml endpoints.yml
  git add endpoints.yml
  git commit -m "Version bump for ${GITHUB_ENDPOINT}:${BRANCH} new tag ${ARG}"
  git push https://netboot-ci:${GITHUB_TOKEN}@github.com/netbootxyz/netboot.xyz.git --all
fi

# send status to discord
if [ "${TYPE}" == "discord" ]; then
  if [ "${ARG}" == "success" ]; then
    curl -X POST -H "Content-Type: application/json" --data \
    '{
      "avatar_url": "https://avatars.io/twitter/travisci",
      "embeds": [
        {
          "color": 1681177,
          "description": "__**New Asset Published**__ \n**Release:**  https://github.com/'${GITHUB_ENDPOINT}'/releases/tag/'${TRAVIS_TAG}'\n**Build:**  '${TRAVIS_BUILD_WEB_URL}'\n**External Version:**  '${EXTERNAL_VERSION}'\n**Status:**  Success\n**Change:** https://github.com/'${GITHUB_ENDPOINT}'/commit/'${TRAVIS_COMMIT}'\n"
        }
      ],
      "username": "Travis CI"
    }' \
    ${DISCORD_HOOK_URL}
  elif [ "${ARG}" == "failure" ]; then
    curl -X POST -H "Content-Type: application/json" --data \
    '{
      "avatar_url": "https://avatars.io/twitter/travisci",
      "embeds": [
        {
          "color": 16711680,
          "description": "**Build:**  '${TRAVIS_BUILD_WEB_URL}'\n**External Version:**  '${EXTERNAL_VERSION}'\n**Status:**  Failure\n**Change:** https://github.com/'${GITHUB_ENDPOINT}'/commit/'${TRAVIS_COMMIT}'\n"
        }
      ],
      "username": "Travis CI"
    }' \
    ${DISCORD_HOOK_URL}
  else
    exit 1
  fi
fi

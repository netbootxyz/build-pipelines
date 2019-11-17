# NETBOOT.XYZ Build Environment

## Intro

The purpose of this repository is 2 parts: 

- Maintain the centralized logic used by asset builders conventionally publishing the contents of Live CD ISOs or customized Kernel/Initrd combos with specific logic to allow booting from a github HTTPS endpoint.

- Be an evolving written explanation of the current state of the automated build system spanning all of these externally ingested assets.

Outside of these core principles this document should provide as much possible information on how to properly participate in the project as a whole.

## Templating NETBOOT.XYZ

Our main visible output is https available customized IPXE Menu assets that can be easily consumed by a series of custom built IPXE boot mediums.
The purpose of templating the menu output serves two purposes as it makes it possible for this project to be updated by bots reaching out for our own custom hosted assets and it also makes it possible for users to locally host their own customized menu/boot medium sets.
To encapsilate all build steps and menu templating Ansible was selected as a platform using Jinja templates. 

The build process should always strive to: 

- Provide dead simple build instructions to produce usable output for a normal user that does not have a deep understanding of the project
- Build helper environments in the form of Docker containers that can be used for hosting the build output
- Have documented tools the user can leverage to produce a copycat site of netboot.xyz under their own domain along with a method for consuming our releases
- Allow users to easily pick and choose the components they want to be included in their menus and custom options to go along with them. 

If we can adhere to these standards it should be possible to become an industry standard for booting Operating systems off the Internet instead of an isolated environment and garner support from external projects that want to be on the list presented to users by default.   

### Templating basics

NEEDS EXPANSION TO EXPLAIN JINJA TEMPLATING RULES FOR PROJECT

### Using the templates to self host

Throughout this document you will read about the concept of a centralized list of endpoints, these are specific assets we as a project produce and host out of Github releases.
Out of everything that is hosted in these menus the contents of Live CDs we tear apart and publish dwarfs them all in size. 

If a user has a need to boot these medium many times either in a local home setup or a full Enterprise enviroment we need to provide the tools to be able to easily mirror our build output and provide options to selectively download only what they choose to show in their menus.

At the time of this writing the current menus for the project are a mix of legacy menus for publically available assets at HTTP/HTTPS endpoints 

## Building HTTPS compatible Live CD components

What a user would conventionally consider a Live CD is made up of 3 main components we need to boot the operating system over the internet: 

- Kernel - This is the Linux Kernel, the main program loaded to communicate with the underlying hardware in the computer. 

- Initramfs - What you would consider a pre-boot environment the Kernel will execute an init process using the contents of this file.

- SquashFS - This is the main operating system that the user cares about booting into. 

Kernel loads, init is kicked off, init locates and loads the squashfs into a ramdisk, bare init in the initramfs is passed off to the contents of the SquashFS conventionally modern init managers like upstart or systemd. 

The first problem you run into when trying to consume these components is while many people mirror the ISOs themselves the components inside the ISO will never be ripped out and made available for ephemeral download.
Next you need the ability to download the SquashFS at boot time in the Initramfs using an https endpoint which due to most distros being as lean as possible ca-cert bundles and https cabable curl or wget will rarely be bundled in pre-boot and in some cases they simply lack the logic to be able to download any remote files, they expect them to be on a locally accessable CD/USB.  

### Asset publishing to Github releases

Github allows us to host files up to 2 gigabytes in size and does not have strict limits on the number of files attached to a release. This allows us to download external ISOs and extract their contents in Travis build jobs finishing by uploading the files we need from them to Github Releases.

Asset repos use near identical logic to pull and publish their components as we have intentionally centralized their build logic in a git based script and download/extraction process to a centralized Docker container. 

The logic for the build script is in this repo, and the logic for the Docker extraction container can be found here: 
https://github.com/netbootxyz/docker-iso-processor

The Docker container above ingests a settings file IE:

```
URL="http://releases.ubuntu.com/18.04/ubuntu-REPLACE_VERSION-desktop-amd64.iso.torrent"
TYPE=torrent
CONTENTS="\
casper/filesystem.squashfs|filesystem.squashfs"
```

The keyword `REPLACE_VERSION` will be substituted in at build time if the external release is version tracked with daily builds.

At the core of the Asset repo concept and really our build infrastrucure as a whole is an endpoints yaml template: 

```
endpoints:
  ubuntu-18.04-default-squash:
    path: /ubuntu-squash/releases/download/REPLACE_RELEASE_NAME/
    files:
    - filesystem.squashfs
    os: "ubuntu"
    version: "18.04"
    flavor: "core"
    kernel: "ubuntu-18.04-live-kernel"
```

You will notice this file contains a keyword `REPLACE_RELEASE_NAME` this allows us to substitute in the unique relese name at build time comprised of the external version number and the current commit for that build. These endpoints on release get pushed to our development branch:
https://github.com/netbootxyz/netboot.xyz/blob/development/endpoints.yml
This list of metadata allows us to generate boot menu releases with every incremental change to the underlying assets they point to in Github.  

These will also contain a settings.sh file that is used by the helper 

Asset repos fall into two main categories for us from a build pipeline perspective.

#### Daily builds to check for external version changes

These types of builds are not limited to but conventionally will be tied to what distributions consider `stable` releases. These releases will have a minor version number. Ubuntu for example has a current stable release of Ubuntu 18.04 Bionic Beaver, but the live CD is currently versioned at 18.04.3, we as an organization do not want to keep track of this kind of stuff. 
Our assumption will always be that the end Users want to boot the latest minor versions and we should not be hosting old minor versions unless there are very specific reasons. 

These builds need to be able to be run daily and handle failure to retrieve the current external version for the releases. Meaning if they get a null response back the null version number should not allow a successful build as a protection from publishing empty/corrupt releases.

The external version checks should be written in bash where possible and compatible with a base configured travis virtual build environment.
This logic flow for this daily build process is as follows: 
* Travis cron job kicks off the build for the branch we have decided to run daily checks for a minor version change
* The external verison number is gotten and applied to the endpoints template in the repo
* The current centralized endpoints template in our main development repo is pulled in and merged with the template from the local repo
* If the file generated does not match the MD5 of the origional file downloaded then we continue the build process eventually publishing the new asset
* The new asset being published updates the centralized endpoints and the loop can continue

#### Static builds for non version tracked assets

For some asset ingestion we can assume that the ISO we download and extract at that version number will be those components as long as the items exist in our boot menus. 
These can build once and publish to add their metadata to the centralized endpoints and stay put until we make changes to that repo/branch. 
In the case of static builds effort should still be made to ingest and tag the release with a unique ID for an external marker. Most distros will provide md5sums or sha265sums of their published ISO for verification the first 8 characters of this sha should be a go to to mark the release on Github. 


### Compatibility between standard init hooks and Github releases

Github Releases have 3 major drawbacks when it comes to publishing web consumable squash files in an initramfs: 

* They are HTTPS endpoints 
* They are limited to 2 gigabyte file sizes
* They use a 302 redirect to point to an actual file in S3 object storage ( most standard web header reads give you 403 in S3 ) 

Because of this we will likely need to maintain special patches for all of the pre-init hooks distros use. It will be impossible to tell a Linux distribution that they should support the detection of 302 redirects but then a 403 error on the followed endpoint, or that they should test for the existence of a proprietary formatted filename `filesystem.squashfs.part2` and append that file to the initial http download.

Patching and generating custom bootable kernels and initramfs assets should be handled in Docker where possible using that distros native tools. A docker image of a distribution will conventionally have the same tools available as a full install when it comes to the downloading and modification of their kernel/initramfs combos.

Each distro conventionally has their own special hooks in their initramfs to get everything ready to pass off to main init, below are the ones we currently support patches for and a brief explanation of what we need to change.

#### Ubuntu's Casper

Casper has recently added http downloads, but lacks it completely in stable. We need to specifically patch in:

* full modification of hooks to support an http/https endpoint to fetch the squashFS
* A full wget binary
* All of the needed ca-certs for wget to use HTTPS
* Support for our proprietary multi-part downloads

Wget and ca-certs can be handled with [initramfs-tools hooks](http://manpages.ubuntu.com/manpages/bionic/man8/initramfs-tools.8.html#hook%20scripts) 

Below is a specific example for adding an HTTPS wget:

```
#!/bin/sh -e
## required header
PREREQS=""
case $1 in
        prereqs) echo "${PREREQS}"; exit 0;;
esac
. /usr/share/initramfs-tools/hook-functions

## add wget from bionic install
copy_exec /usr/bin/wget /bin

## copy ssl certs
mkdir -p \
	$DESTDIR/etc/ssl \
	$DESTDIR/usr/share/ca-certificates/
cp -a \
	/etc/ssl/certs \
	$DESTDIR/etc/ssl/
cp -a \
	/etc/ca-certificates \
	$DESTDIR/etc/
cp -a \
	/usr/share/ca-certificates/mozilla \
	$DESTDIR/usr/share/ca-certificates/
echo "ca_directory=/etc/ssl/certs" > $DESTDIR/etc/wgetrc
```

As for the modifications needed to actually boot off of HTTPS endpoints vs what Casper was designed to do we have stacked our own logic on top of what others have done in the past and failed to get merged into the main project. [The code in the Kernel building repos](https://github.com/netbootxyz/ubuntu-core-18.04/blob/master/root/patch) will always be a better reference than this document. 

#### Debian's Live-Boot

Unlike Ubuntu, Debian's live-boot hooks do support fetching the squashfs from a remote http endpoint but also needs modifications: 

* A full wget binary
* All of the needed ca-certs for wget to use HTTPS
* Support for our proprietary multi-part downloads

Please see the Casper section above to understand how we use initramfs-tools scripts to add in complete wget.
Also again here [the code in the Kernel building repos](https://github.com/netbootxyz/debian-core-10/blob/master/root/patch) will always be a better reference than this document. 

#### Manjaro's miso hooks

Manjaro is Arch based but they maintain their own specific pre-init hooks located [here](https://gitlab.manjaro.org/tools/development-tools/manjaro-tools/tree/master/initcpio/hooks) . 

All that Manjaro requires is slight code changes to support 302 redirects as they use a series of squashfs files and ping the webserver for all of them and will only download and mount on a `200 OK` response which Github lacks.

**EXPAND THIS WHEN WE FIGURE OUT WHY MISO HANGS ON INITIAL SSL NEGOTIATION**

#### Red Hat's Dracut

**WRITE WHEN WE DO FEDORA/REDHAT**


## Development workflow

**ADD GRAPHIC HERE** ( should detail users contributing along with our bots contributing and how that makes it from development to a final release hosted out of netboot.xyz ) 

From 30,000 feet up we as an organization will take our own internal bot commits along with general development and create a snapshot of the rolling release to test in a release canidate. 
These RC endpoints should be generally acceptable for a normal user to consume as long as they understand they might run into bugs and need to report them to us. 
Both the RC and main release should contain the same changelog with the squashed commit messages that went into that since the last stable release. 
Development will also produce a `latest` style consumable endpoint but this should only ever be used for testing and will never be officially supported. 

This section only applies to our main project that outputs menu and bootable asset files. The asset repos will generally be managed strictly by NETBOOT.XYZ team members and have a less restrictive workflow.

### Hosted fully functional build output

Every time a change is made we need to take that incremental change and create useable output hosted in S3.

Commits to development should push their menus/boot files to S3 in a subfolder based off of the commit SHA. 

Pull requests should produce the same style output, but it should also ping back into the PR the link to it all so the people participating have something to test. 

**EXPAND SECTION WITH LAYOUT FOR LINKING TO THESE BUILDS AND METHODS FOR MAKING SURE WE CHECK THEM OUT** 

### Continuous integration

**THIS IS ALL THEORY NOW BUT SOME LOCAL TESTS HAVE BEEN RUN**
Every build possible should publish a web page we are able to click on containing: 

- A screenshot or animation of the IPXE boot rom loading and landing to the main menu **MIGHT BE ABLE TO DO THIS WITH QEMU/ASCIINEMA web players to capture serial output of the DHCP and bootstrap**
- Clickable easy to read links to the different build assets for download

Possible to fully emulate the IPXE kernel in jslinux ? https://bellard.org/jslinux/faq.html
Can we do linting of any kind IPXE files do not look like they have any kind of public linting option ? 


**SCREENSHOT HERE OF WORKING PAGE**

Asset booting?? It should technically be possible if we maintain a boot snippet in every asset repo (possibly in the endpoints.template) . 
Could have an IPXE booter linked to a VM stack that runs the VM for a period of time to allow the OS to load and takes a screenshot every X seconds and upload it all to S3 and ping it in to discord.
Would need local x86 nodes for this, would never be possible with free infra. 

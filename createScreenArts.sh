#!/bin/bash

### Script settings
defaultDevice="Nexus5X"
devicesPropFile="devices_properties.json"
devicesFolder="devices"
screenshotsFolder="screenshots"
backgroundsFolder="backgrounds"

### Script init
init () {
	rm -rf tmp
	device=${defaultDevice}
	targetWidth=1080
	targetHeight=1920

	# Check available devices
	declare -ga aDevice
	for item in $(find ./${devicesFolder}/* -maxdepth 0 -type d); do aDevice+=$(echo "${item}" | cut -d"/" -f3); done
}

### Core 
createScreenshots () {
	echo "$(date "+%D-%T") - Start screen arts creation"
	setProps ${device}
	local i=0 # Used for backgrounds id
	for screenshot in $(find ./${screenshotsFolder}/0-raw/ -maxdepth 1 -type f | sort); do
		filename=$(basename -- "${screenshot%.*}")

		# Resize screenshot
		mkdir -p ./${screenshotsFolder}/1-resized
		filenameResize="./${screenshotsFolder}/1-resized/${filename}.png"
		convert $screenshot -resize ${aProps[screenWidth]}x${aProps[screenHeight]} $filenameResize
		screenshot=$filenameResize

		# Add frame
		mkdir -p ./${screenshotsFolder}/2-framed
		filenameFramed="./${screenshotsFolder}/2-framed/${filename}.png"
		composite $screenshot ${deviceFilesPath}${aProps[frameFile]} -geometry +${aProps[screenOffsetX]}+${aProps[screenOffsetY]} $filenameFramed
		screenshot=$filenameFramed

		# Add shadow
		mkdir -p ./${screenshotsFolder}/3-shadowed
		filenameShadowed="./${screenshotsFolder}/3-shadowed/${filename}.png"
		composite -gravity center $screenshot ${deviceFilesPath}${aProps[shadowFile]} $filenameShadowed
		screenshot=$filenameShadowed

		# Add glare
		mkdir -p ./${screenshotsFolder}/4-glared
		filenameGlared="./${screenshotsFolder}/4-glared/${filename}.png"
		composite -gravity center ${deviceFilesPath}${aProps[glareFile]} $screenshot $filenameGlared
		screenshot=$filenameGlared

		# Add background
		## resize image before add the background
		mogrify -resize ${targetWidth}x${targetHeight} $screenshot
		mogrify -resize ${aProps[zoomFactor]} $screenshot
				
		## Add the background
		mkdir -p ./${screenshotsFolder}/5-final
		filenameWithBackground="./${screenshotsFolder}/5-final/${filename}.png"
		backgroundId=$(($i % $backgroundsNumber + 1))
		composite -gravity center $screenshot ${aBackgrounds[$backgroundId]} $filenameWithBackground

		echo "$(date "+%D-%T") - Screen $i done. ($filename.png)"
		i=$((i+1))
	done
}


### Utilities functions
usage () {
	echo "Available options :"
    echo "  -d [device_id]	: Device used for framing ($defaultDevice by default)"
    echo "  -m [download|list]	: Manage devices :"
    echo "				- Download them from Android dev website."
    echo "				- List the available ones."
}

manageDevices () {
	read -p "What would you like to do with device? [download|list] : " option
	case "$option" in
		'download'|'d')	downloadDevices ;;
		'list'|'l')		listDevices ;;
		*) 				echo "Sorry, the '$option' option is not available."; exit 1 ;;
	esac
}

downloadDevices () {
	devicesList=$(./${devicesFolder}/jq -r '.[] | .id' ./${devicesFolder}/$devicesPropFile)
	i=0
	for device in $devicesList; do
		echo " Downloading ressources for '$device'."
		for orientation in port land; do
			resTypes=$(./${devicesFolder}/jq -r ".[] | select(.id==\"$device\") | .${orientation}Res[]" ./${devicesFolder}/$devicesPropFile)
			for resType in $resTypes; do
 				mkdir -p ./${devicesFolder}/$device
				filename="${orientation}_${resType}.png"
				curl -s -m 2 "https://android-dot-google-developers.appspot.com/distribute/marketing-tools/device-art-resources/pixel_2_xl/$filename" > ./${devicesFolder}/${device}/$filename
			done
		done
		i=$((i+1))
	done
	echo "Finished. $i devices downloaded."
}

listDevices () {
	echo "This available devices are:"
	for device in "${aDevice[@]}"; do
		echo "  - $device"
	done
	echo "Check de 'devices' folder for more details."
}

setProps () {
	local device=$1
	deviceFilesPath="./${devicesFolder}/${device}/"
	unset aProps && declare -gA aProps
	while read prop || [ -n "$prop" ]; do 	# [ -n "$prop" ] is for the last line. 'read' only considers lines ending with a "newline" char.
		propName=$(echo "$prop" | cut -d"=" -f1)
		propValue=$(echo "$prop" | cut -d"=" -f2)
		aProps+=([${propName}]="${propValue}")
	done < ${deviceFilesPath}${devicesPropFile}
}

listBackgrounds () {
	local i=0
	declare -gA aBackgrounds
	mkdir -p ./${backgroundsFolder}/resized

	for background in $(find ./backgrounds/ -maxdepth 1 -type f -exec file {} \; | grep -oP '^.+: \w+ image' | cut -d":" -f1 | sort); do
		i=$((i+1))
		echo "Preparing background $i... ($background)"
		## Blur & resize background
		filenameBackground="./${backgroundsFolder}/resized/$(basename -- ${background%.*}).png"
		convert ${background} -filter Gaussian -resize 90% -define filter:sigma=4 -resize 112%  $filenameBackground 	# Used to blur the image quickly
		mogrify  -resize ${targetWidth}x${targetHeight}^ -gravity center -extent ${targetWidth}x${targetHeight} $filenameBackground
		# without blur : convert ${aBackgrounds[$i]} -resize ${targetWidth}x${targetHeight}^ -gravity center -extent ${targetWidth}x${targetHeight} $filenameBackground
		
		# Add background in the list
		aBackgrounds+=([$i]="${filenameBackground}")
	done
	backgroundsNumber=$i
}


### Run the script
init
while getopts ":d:mh" optname; do
    case ${optname} in
      d)	device=${OPTARG}  ;;
	  m)	manageDevices; exit 0 ;;
	  h)	usage; exit 0 ;;
      \?) 	echo "The '-${OPTARG}' option is invalid."; usage; exit 1 ;;
      :)	echo "Option -${OPTARG} requires an argument. Try -h for help."; exit 1 ;;
      *)	echo "Unknown error while processing options"; usage; exit 1 ;;
    esac
done
shift "$((OPTIND-1))"	# Clean params list

# Check if device is OK
if [[ " ${aDevice[*]} " != *" ${device} "* ]]; then
	echo "The device '$device' is not available. Try '-l' option for devices list."
	exit 1
fi

# Go screenshots, go!
listBackgrounds
createScreenshots

echo -e "$(date "+%D-%T") - Finished!"

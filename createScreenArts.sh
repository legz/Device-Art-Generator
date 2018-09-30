#!/bin/bash

### Script settings
defaultDevice="nexus_5x"
devicesPropFile="devices_properties.json"
devicesFolder="devices"
imagesFolder="images"
backgroundsFolder="$imagesFolder/backgrounds"

### Script init
init () {
	rm -rf tmp
	device=${defaultDevice}
	targetWidth=1080
	targetHeight=1920

	# Check available devices
	declare -ga aDevice

	devicesList=$(./${devicesFolder}/jq -r '.[] | .id' ./${devicesFolder}/$devicesPropFile)
	for item in $devicesList; do
		if [ -d "./${devicesFolder}/$item" ]; then aDevice+=("$item"); fi
	done
}

### Core 
createScreenshots () {
	echo "$(date "+%D-%T") - Start screen arts creation"
	#setProps ${device}
	local i=0 # Used for backgrounds id
	for screenshot in $(find ./${imagesFolder}/0-raw/ -maxdepth 1 -type f | sort); do
		filename=$(basename -- "${screenshot%.*}")
		deviceFilesPath="./${devicesFolder}/${device}/"

		# Detect orientation
		if [[ $(identify -format '%[fx:(w>h)]' $screenshot) = "1" ]]; then
			local orientation="land"
		else
			local orientation="port"
		fi

		# Resize screenshot
		mkdir -p ./${imagesFolder}/1-resized
		filenameResize="./${imagesFolder}/1-resized/${filename}.png"
		screenWidth=$(jq -r ".[] | select(.id==\"${device}\") | .${orientation}Size[0]" ./${devicesFolder}/$devicesPropFile)
		screenHeight=$(jq -r ".[] | select(.id==\"${device}\") | .${orientation}Size[1]" ./${devicesFolder}/$devicesPropFile)
		convert $screenshot -resize ${screenWidth}x${screenHeight} $filenameResize
		screenshot=$filenameResize

		# Add frame
		mkdir -p ./${imagesFolder}/2-framed
		filenameFramed="./${imagesFolder}/2-framed/${filename}.png"
		frameFile="${deviceFilesPath}${orientation}_back.png"
		screenOffsetX=$(jq -r ".[] | select(.id==\"${device}\") | .${orientation}Offset[0]" ./${devicesFolder}/$devicesPropFile)
		screenOffsetY=$(jq -r ".[] | select(.id==\"${device}\") | .${orientation}Offset[1]" ./${devicesFolder}/$devicesPropFile)
		composite $screenshot $frameFile -geometry +$screenOffsetX+$screenOffsetY $filenameFramed
		screenshot=$filenameFramed

		# Add shadow
		mkdir -p ./${imagesFolder}/3-shadowed
		filenameShadowed="./${imagesFolder}/3-shadowed/${filename}.png"
		shadowFile="${deviceFilesPath}${orientation}_shadow.png"
		composite -gravity center $screenshot $shadowFile $filenameShadowed
		screenshot=$filenameShadowed

		# Add glare
		mkdir -p ./${imagesFolder}/4-glared
		filenameGlared="./${imagesFolder}/4-glared/${filename}.png"
		glareFile="${deviceFilesPath}${orientation}_fore.png"
		composite -gravity center $glareFile $screenshot $filenameGlared
		screenshot=$filenameGlared

		# Add background
		## resize image before add the background
		if [[ "$orientation" = "port" ]]; then
			mogrify -resize ${targetWidth}x${targetHeight} $screenshot
		else
			mogrify -resize ${targetHeight}x${targetWidth} $screenshot
		fi
		zoomFactor=$(jq -r ".[] | select(.id==\"${device}\") | .zoomFactor" ./${devicesFolder}/$devicesPropFile)
		mogrify -resize ${zoomFactor}% $screenshot
				
		## Rotate the background if needed
		background=${aBackgrounds[$(($i % $backgroundsNumber + 1))]}
		if [[ $(identify -format '%[fx:(w>h)]' $background) = "1" ]]; then local backgroundOrientation="land"; else local backgroundOrientation="port"; fi
		if [[ "$orientation" != "$backgroundOrientation" ]]; then
			mogrify -rotate "90" $background
		fi

		## Add the background
		mkdir -p ./${imagesFolder}/5-final
		filenameWithBackground="./${imagesFolder}/5-final/${filename}.png"
		composite -gravity center $screenshot $background $filenameWithBackground

		i=$((i+1))
		echo "$(date "+%D-%T") - Screen $i done. ($filename.png)"
	done
}


### Utilities functions
usage () {
	echo "Available options:"
    echo "  -d [device_id]	: Device used for framing ($defaultDevice by default)"
    echo "  -m [download|list]	: Manage devices:"
    echo "				- Download them from Android dev website."
    echo "				- List the available ones."
}

manageDevices () {
	read -p $'What would you like to do regarding devices? [\e[4md\e[0mownload|\e[4ml\e[0mist]: ' option
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
				curl -s -m 3 "https://android-dot-google-developers.appspot.com/distribute/marketing-tools/device-art-resources/$device/$filename" > ./${devicesFolder}/${device}/$filename
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
	echo "Check the 'devices' folder for more details."
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

	for background in $(find ./${backgroundsFolder}/ -maxdepth 1 -type f -exec file {} \; | grep -oP '^.+: \w+ image' | cut -d":" -f1 | sort); do
		i=$((i+1))
		echo "Preparing background $i... ($background)"
		# Resize background
		filenameBackground="./${backgroundsFolder}/resized/$(basename -- ${background%.*}).png"
		
		# Blur version
		##convert ${background} -filter Gaussian -resize 90% -define filter:sigma=4 -resize 112%  $filenameBackground 	# Used to blur the image quickly
		##mogrify  -resize ${targetWidth}x${targetHeight}^ -gravity center -extent ${targetWidth}x${targetHeight} $filenameBackground
		
		# Simple resize withou blur
		convert ${background} -resize ${targetWidth}x${targetHeight}^ -gravity center -extent ${targetWidth}x${targetHeight} $filenameBackground
		
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

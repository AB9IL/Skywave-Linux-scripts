#!/bin/bash

# Copyright (c) 2019 by Philip Collier, radio AB9IL <webmaster@ab9il.net>
# This is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version. There is NO warranty; not even for
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

# Capture, decode, and save AIS data.

# define the rofi and fzf commands
ROFI_COMMAND1="rofi -dmenu -p Select -lines 5"
FZF_COMMAND1="fzf --layout=reverse --header=Select:"

IFS=$'\n'
jsonfile=$HOME"/ais_log.json"
#Get the SDR frequency offset (ppm)
ppm=$(cat /usr/local/etc/sdr_offset)
#Get the SDR gain (gain)
gain=$(cat /usr/local/etc/sdr_gain)
fifo='/tmp/ais.dump'

dumpto_file() {
# create a pipe
mkfifo -m 666 $fifo
# start reading from the pipe
gpsdecode -j < $fifo | tee -a "$jsonfile" &
# feed the pipe
rtl_ais -p "$ppm" -g "$gain" &
nc 127.0.0.1 10110 > $fifo

WINDOW=$(yad --info --height 100 --width 350 \
--title="RTL-AIS - Running." \
--text="The dual channel AIS monitor is running.
To stop, use this application and select \"Stop AIS capture and logging.\""
);
}

dumpto_db(){
# create a pipe
mkfifo -m 666 $fifo
# call the python script to read the pipe and build the database
sh -c "ais-fileto-sqlite $fifo"
# get nmea data and feed the pipe
rtl_ais -p "$ppm" -g "$gain" &
nc 127.0.0.1 10110 > $fifo

WINDOW=$(yad --info --height 100 --width 350 \
--title="RTL-AIS - Running." \
--text="The dual channel AIS monitor is running.
To stop, use this application and select \"Stop AIS capture and logging.\""
);
}

readto_db() {
FILE=$(yad --file-selection --title="RTL-AIS - Select File" \
--text="Select a file containing raw NMEA sentences to decode.");

case $? in
	0)
		echo "$FILE selected.";;
	1)
		echo "No file selected."
		WINDOW=$(yad --info --height 100 --width 350 \
		--title="RTL-AIS - NMEA - Decode to Database." \
		--text="No file selected. \nNo decoding accomplished.")
		exit;;
	2)
		echo "Something went wrong..."
		WINDOW=$(yad --info --height 100 --width 350 \
		--title="RTL-AIS - NMEA - Decode to Database." \
		--text="No file selected. \nNo decoding accomplished.")
		exit;;
esac

nmeafile=$FILE
# call the python script to read the file and build the database
sh -c "ais-fileto-sqlite $nmeafile"

WINDOW=$(yad --info --height 100 --width 350 \
--title="RTL-AIS - NMEA - Decode to Database." \
--text="The decoder process has run. \
\nFind the timestamped \
\"\n...ais-decoded.db\" file.");
}

readto_json() {
FILE=$(yad --file-selection --title="RTL-AIS - Select File with NMEA Data");
case $? in
	0)
		echo "\"$FILE\" selected."
		TIME=$(date +%Y-%m-%d_%H-%M-%S)
		nmeafile=$FILE
		# cat -> decode -> save
		gpsdecode < "$nmeafile" | tee "${TIME}-ais-decoded.json"

		WINDOW=$(yad --info --height 100 --width 350 \
		--title="RTL-AIS - NMEA - Decode to JSON." \
		--text="The decoder process has run. \
        \nFind the timestamped \
        \"\n...ais-decoded.json\" file.")
		;;
	1)
		echo "No file selected."
		WINDOW=$(yad --info --height 100 --width 350 \
		--title="RTL-AIS - NMEA - Decode to JSON." \
		--text="No file selected. \nNo decoding accomplished.")
		exit
		;;
	2)
		echo "Something went wrong..."
		WINDOW=$(yad --info --height 100 --width 350 \
		--title="RTL-AIS - NMEA - Decode to JSON." \
		--text="Something went wrong. \nNo decoding accomplished.")
		exit
		;;
esac
}

startmapper() {
# Select the json file to send to the mapper
FILE=$(yad --file-selection --title="RTL-AIS - Select Json File with AIS Data");
case $? in
	0)
		echo "\"$FILE\" selected."
		jsonfile=$FILE
		ais-mapper "$jsonfile"

		WINDOW=$(yad --info --height 100 --width 350 \
		--title="RTL-AIS - Mapper Starting." \
		--text="Data has been sent to the mapper.")
		;;
	1)
		echo "No file selected."
		WINDOW=$(yad --info --height 100 --width 350 \
		--title="RTL-AIS - Mapping Failed: No File Selected" \
		--text="No file selected. \nNo map plotting possible.")
		exit
		;;
	2)
		echo "Something went wrong..."
		WINDOW=$(yad --info --height 100 --width 350 \
		--title="RTL-AIS - Mapping Failed: Something Went Wrong" \
		--text="Something went wrong. \nNo mapping accomplished.")
		exit
		;;
esac

}

stopcapture() {
killall rtl_ais nc
rm -f $fifo
}

showhelp(){
echo "The AIS monitor captures Automatic Identification System
      data from maritime vessels, such as position, movement
      direction, and speed.

Usage: $0 to start from the terminal.
       $0 gui to start in Rofi.

       Select the mode of data presentation.
       Choices are:
         - capture data and store it in a database
         - read data from a file and copy it to a database
         - read data and write it to a file in json format

       Use the \"SDR Operating Parameters\" app to:
         - enter your geographic coordinates for the map.
         - set the SDR device gain
         - set the device ppm offset corection
         - set other device operating parameters

         "
}

case "$1" in
    "")
        COMMAND1=$FZF_COMMAND1
        ;;
    "gui")
        COMMAND1=$ROFI_COMMAND1
        ;;
    *)
        showhelp
        ;;
esac

OPTIONS="Capture AIS NMEA sentences by radio, decode, and write to a logfile. 
Capture AIS NMEA sentences by radio, decode, and write to a database.
Read a file containing AIS NMEA sentences, decode, and write to a database.
Read a file containing AIS NMEA sentences, decode, and write to a json file.
Stop AIS capture and logging."

# Take the choice; exit if no answer matches options.
(IFS=" "; REPLY="$(echo "$OPTIONS" | $COMMAND1 )"

[[ "$REPLY" == "Capture AIS NMEA sentences by radio, decode, and write to a logfile." ]] && dumpto_file
[[ "$REPLY" == "Capture AIS NMEA sentences by radio, decode, and write to a database." ]] && dumpto_db
[[ "$REPLY" == "Read a file containing AIS NMEA sentences, decode, and write to a database." ]] && readto_db
[[ "$REPLY" == "Read a file containing AIS NMEA sentences, decode, and write to a json file." ]] && readto_json
[[ "$REPLY" == "Plot decoded AIS info on a map." ]] && startmapper
[[ "$REPLY" == "Stop AIS capture and logging." ]] && stopcapture)

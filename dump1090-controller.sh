#!/bin/bash

# Copyright (c) 2019 by Philip Collier, radio AB9IL <webmaster@ab9il.net>
# This is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version. There is NO warranty; not even for
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

# Capture, decode, and save ADS-B data.

#Get the SDR frequency offset (ppm)
ppm=$(cat /usr/local/etc/sdr_offset)
#Get the SDR gain (gain)
gain=$(cat /usr/local/etc/sdr_gain)
#Get the SoapySDR driver string
devdriver=$(cat /usr/local/etc/sdr_driver)
#Get the SoapySDR key number
devkey=$(cat /usr/local/etc/sdr_key)
#Get the receiver position
readarray -t devposition < /usr/local/etc/sdr_posn
fifo='/run/dump1090/1090.dump'

# define the rofi and fzf commands
ROFI_COMMAND1="rofi -dmenu -p Select -lines 5"
FZF_COMMAND1="fzf --layout=reverse --header=Select:"

startlog() {
# run dump1090
mkfifo -m 666 $fifo
rx_sdr -F CU8 -f 1090000000 -s 2048000 -p $ppm -g $gain -d driver=$devdriver','$devkey $fifo &
cat $fifo | dump1090 --net-sbs-port 30003 --fix &
nc 127.0.0.1 30003 | egrep --line-buffered 'MSG,1|MSG,3|MSG,4|MSG,6' >> $HOME/adsb.log &
}

start_decoded_log() {
# run dump1090
mkfifo -m 666 $fifo
rx_sdr -F CU8 -f 1090000000 -s 2048000 -p $ppm -g $gain -d driver=$devdriver','$devkey $fifo &
cat $fifo | dump1090 --net --net-sbs-port 30003 --fix &
/usr/local/bin/dump1090-stream-parser &
sqlitebrowser $HOME/adsb_messages.db &
}

startplot() {
# split the position into variables for latitude and longitude
latitude=$(echo $devposition | cut -f1 -d ",")
longitude=$(echo $devposition | cut -f2 -d ",")

cp /usr/local/share/dump1090/html/config.js.orig /usr/local/share/dump1090/html/config.js
# edit the config file with actual lat/lon
sed -i "
	32s/.*/SiteLat = $latitude;/ ;
	33s/.*/SiteLon = $longitude;/ ;
	37s/.*/DefaultCenterLat = $latitude;/ ;
	38s/.*/DefaultCenterLon = $longitude;/ ;" /usr/local/share/dump1090/html/config.js

# run dump1090
mkfifo -m 666 $fifo
rx_sdr -F CU8 -f 1090000000 -s 2048000 -p $ppm -g $gain -d driver=$devdriver','$devkey $fifo &
cat $fifo | dump1090 --net --net-sbs-port 30003 --write-json /run/dump1090 --fix &

# Open the map in firefox
firefox --new-tab http://localhost/dump1090/ &

# Start the stream parser
/usr/local/bin/dump1090-stream-parser &
}

notifyerror(){
        echo "Something went wrong!!!!!!"
        WINDOW=$(yad --info --height 100 --width 350 \
		--title="Dump1090 - Error." \
		--text="Something went wrong!!!!!!");
		stop_dump
        exit
}

stop_dump(){
killall -9 dump1090 rx_sdr rtl_sdr rtl_tcp $(lsof -t -i:30003) sqlitebrowser
pkill -f /usr/local/bin/dump1090-stream-parser
find /run/dump1090/ -type p -delete
exit
}

sdr_params() {
sh -c "sdr-params.sh"
}

showhelp() {
echo "Dump1090 captures pulse modulated data from mode-s transponders
aboard aircraft.

Usage: $0 to start from the terminal.
       $0 gui to start in Rofi.

       Select the mode of data presentation.
       Choices are:
         - raw data dump to file
         - store data in database
         - present data on a map

       Use the SDR Operating Parameters app to:
         - enter your geographic coordinates for the map.
         - set the SDR device gain
         - set the device ppm offset corection
         - set other device operating parameters

         "
}

OPTIONS="Start Dump1090 and plot aircraft positions.
Start Dump1090 and write decoded data to a database.
Start Dump1090 and write raw data to a logfile.
Set your geograpgic location or device parameters.
Stop Dump1090."

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

# Take the choice; exit if no answer matches options.
REPLY="$(echo -e "$OPTIONS" | $COMMAND1 )"

[[ "$REPLY" == "Start Dump1090 and plot aircraft positions." ]] && startplot
[[ "$REPLY" == "Start Dump1090 and write decoded data to a database." ]] && start_decoded_log
[[ "$REPLY" == "Start Dump1090 and write raw data to a logfile." ]] && startlog
[[ "$REPLY" == "Stop Dump1090." ]] && stop_dump
[[ "$REPLY" == "Set your geograpgic location or device parameters." ]] && sdr_params

#!/bin/bash

# Copyright (c) 2021 by Philip Collier, radio AB9IL
# This script is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version. There is NO warranty; not even for
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

# Measure and save rtl-sdr calibration information using GSM base stations.
# Edit the file referenced for gain setting by certain applications.
# Save SoapySDR device string and key for other uses.

Encoding=UTF-8

#Get the SDR frequency offset (ppm)
ppm=$(cat /usr/local/etc/sdr_offset)
#Get the SDR gain (gain)
gain=$(cat /usr/local/etc/sdr_gain)
#Get device driver data
driver=$(cat /usr/local/etc/sdr_driver)
#Get device key
devkey=$(cat /usr/local/etc/sdr_key)
#Get geographic location
pos=$(cat /usr/local/etc/sdr_posn)

get_offset(){
echo "Best channel is: $best_channel."
	WINDOW=$(yad --info --height 100 --width 350 \
	--title="Calibration and Gain" \
	--text="Channel $best_channel selected for ppm offset measurements.");

offset=($(kal -c $best_channel -g $gain -e $ppm 2>&1 | grep "absolute error" | grep -Po "\d*\." | awk '{printf "%.0f", $0}'))

if [[ -z "$offset" ]]; then
		problem="Could not determine offset."
		notifyerror
fi

echo "Offset (ppm) is: $offset."
echo $offset > /usr/local/etc/sdr_offset  # save offset for general usage
sed -i "s/corr_freq=.*/corr_freq=${offset}000000/g" ~/.config/gqrx/default.conf # save offset for gqrx

	WINDOW=$(yad --info --height 100 --width 350 \
	--title="Calibration and Gain" \
	--text="An offset of $offset ppm has been written to file /usr/local/etc/sdr_offset.");
}

notifyerror(){
echo "Something went wrong: $problem"
	WINDOW=$(yad --info --height 100 --width 400 \
	--title="Calibration and Gain" \
	--text="Something went wrong:
$problem");
	exit
}

scan_band(){
echo "Please stand by.  Scanning for $band stations..."
mapfile -t arr < <(kal -v -s $band -g $gain -e $ppm 2>&1 | grep 'chan:' | awk '{printf $2" "$7"\n"}' | sort -nrk2)
echo "Chan Strength"
printf '%s\n' "${arr[@]}"
set -- ${arr[0]}

best_channel=$1
# Terminate if there is no usable channel
if [[ -z "$best_channel" ]]; then
		problem="Could not find a usable channel."
		notifyerror
fi

get_offset
}

set_device(){
OUTPUT=$(yad --forms --title="SoapySDR Device Type" --width 400 --height 100 \
--text="Enter the SDR start-up parameters
reported by \"SoapySDRUtil --find\"." \
--separator="," \
--entry="SoapySDR Device Driver (e.g. rtlsdr or airspy):" \
--entry="SoapySDR Device Key (e.g. 0, 1, or 2):" \
);

driver=$(awk -F, '{print $1}' <<<$OUTPUT)
devkey=$(awk -F, '{print $2}' <<<$OUTPUT)

if [[ -z "$driver" ]]; then
	problem="Incorrect format or no device data."
	notifyerror
fi

if [[ -z "$devkey" ]]; then
	problem="Incorrect format or no device data."
	notifyerror
fi

# write device driver data to the reference file
echo $driver > /usr/local/etc/sdr_driver

# write device key to the reference file
echo $devkey > /usr/local/etc/sdr_key

	WINDOW=$(yad --info --height 100 --width 350 \
	--title="SoapySDR Device Type" \
	--text="Device driver $driver has been written to file /usr/local/etc/sdr_driver.
Device key $devkey has been written to file /usr/local/etc/sdr_key.");
}

set_gain(){
OUTPUT=$(yad --forms --title="Calibration and Gain" --width 400 --height 100 \
--text="Enter the desired SDR gain." \
--entry="Gain:");

gain=$(awk -F, '{print $1}' <<<$OUTPUT)

if [[ -z "$gain" ]]; then
	problem="Incorrect format or no gain data."
    notifyerror
fi

# write gain setting to the reference file
echo $gain > /usr/local/etc/sdr_gain

	WINDOW=$(yad --info --height 100 --width 350 \
	--title="Calibration and Gain" \
	--text="A gain of $gain has been written to file /usr/local/etc/sdr_gain.");
}

check_soapy() {
mydevinfo=$(SoapySDRUtil --find)
	WINDOW=$(yad --info --height 500 --width 500 \
	--title="SoapySDR Device Type" \
	--text="${mydevinfo}");
}

set_offset(){
OUTPUT=$(yad --forms --title="Calibration and Gain" --width 400 --height 100 \
--text="Enter the desired SDR offset (ppm)." \
--entry="Offset:");

offset=$(awk -F, '{print $1}' <<<$OUTPUT)

if [[ -z "$offset" ]]; then
	problem="Incorrect format or no offset data."
    notifyerror
fi

echo $offset > /usr/local/etc/sdr_offset  # save offset for general usage
offset2="$(bc<<<${offset}*10)"
sed -i "s/corr_freq=.*/corr_freq=${offset2}00000/g" ~/.config/gqrx/default.conf # save offset for gqrx

	WINDOW=$(yad --info --height 100 --width 350 \
	--title="Calibration and Gain" \
	--text="An offset of $offset ppm has been written to file /usr/local/etc/sdr_offset.");
}

set_position(){
OUTPUT=$(yad --forms --title="Geographic Position" --width 400 --height 300 \
--text="Enter the geographic coordinates.
* Use decimal format and comma separate the numbers.
* WEST and SOUTH coordinates are negative values.
For example, JFK airport:  40.64,-73.78 " \
--entry="Latitude, Longitude:");

lat=$(awk -F, '{print $1}' <<<$OUTPUT)
lon=$(awk -F, '{print $2}' <<<$OUTPUT)


if [[ -z "$lat" ]]; then
	problem="Incorrect format or no position data."
    notifyerror
fi

if [[ -z "$lon" ]]; then
	problem="Incorrect format or no position data."
    notifyerror
fi

# write coordinates to the reference file
echo $lat","$lon > /usr/local/etc/sdr_posn

	WINDOW=$(yad --info --height 100 --width 350 \
	--title="Geographic Position" \
	--text="A position of $lat,$lon has been written to file /usr/local/etc/sdr_posn.");
}

toggle_tee() {
teemode="UNKNOWN"
OUTPUT=$(yad  --list  --title "RTLSDR Bias Tee" --width 500 --height 170 \
--text "Toggle the RTLSDR bias tee on or off." \
--radiolist  --column "Pick" --column "Action" \
FALSE "Set bias tee ON."  \
TRUE "Set bias tee OFF.");

	if [  "$OUTPUT" = "Set bias tee ON." ]; then
		rtl_biast -b 1
		teemode="ON"

	elif [  "$OUTPUT" = "Set bias tee OFF." ]; then
		rtl_biast -b 0
		teemode="OFF"

	fi

	WINDOW=$(yad --info --height 100 --width 310 \
	--title="RTLSDR Bias Tee" \
	--text="The bias tee has been set to $teemode.");
}

ans=$(yad  --list  --title "SDR Operating Parameters" --width 500 --height 640 \
--text "Manage RTL-SDR frequency calibration and gain.
1) Calibration uses measurements of GSM base stations.
2) Device gain is saved for reference by other applications.
3) Please be patient: it is a slow process.

Currently you have these settings:
Device:  $driver
Key:  $devkey
Offset:  $ppm
Gain:  $gain
Geographic position:  $pos
" \
--radiolist  --column "Pick" --column "Action" \
TRUE "Scan for GSM 850 MHz base stations." \
FALSE "Scan for GSM 900 MHz base stations." \
FALSE "Scan for E-GSM base stations." \
FALSE "Check SoapySDR device information." \
FALSE "Toggle RTLSDR bias tee on or off." \
FALSE "Manually program the SDR offset." \
FALSE "Manually program the SDR gain." \
FALSE "Manually program the SoapySDR device data." \
FALSE "Manually program geographic coordinates.");

[[ "$ans" == "Scan for GSM 850 MHz base stations." ]] && band='GSM850' && scan_band

[[ "$ans" == "Scan for GSM 900 MHz base stations." ]] && band='GSM900' && scan_band

[[ "$ans" == "Scan for E-GSM base stations." ]] && band='EGSM' && scan_band

[[ "$ans" == "Check SoapySDR device information." ]] && check_soapy

[[ "$ans" == "Toggle RTLSDR bias tee on or off." ]] && toggle_tee

[[ "$ans" == "Manually program the SDR offset." ]] && set_offset

[[ "$ans" == "Manually program the SDR gain." ]] && set_gain

[[ "$ans" == "Manually program the SoapySDR device data." ]] && set_device

[[ "$ans" == "Manually program geographic coordinates." ]] && set_position

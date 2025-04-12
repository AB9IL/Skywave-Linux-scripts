#!/bin/bash

# Copyright (c) 2019 by Philip Collier, radio AB9IL <webmaster@ab9il.net>
# This is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version. There is NO warranty; not even for
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

# Capture a wide RF bandwidth and operate a multichannel SDR receiver.

streamname="RTLSDR-Airband Multichannel"
genre="Voice Communicatons"
#Get the SDR frequency offset (ppm)
corr=$(cat /usr/local/etc/sdr_offset)
#Get the SDR gain (gain)
gain=$(cat /usr/local/etc/sdr_gain)
#Get the SoapySDR driver string
devdriver=$(cat /usr/local/etc/sdr_driver)
#Get the SoapySDR device key, such as "rtl=0"
devkey=$(cat /usr/local/etc/sdr_key)
# strip the number from the device key
key="$(echo "$devkey" | cut -f2 -d "=")"

# file with voice frequencies
voicefreqs="/usr/local/etc/VOICE_FREQS"

#Get the frequency and mode list
readarray FREQLIST < "$voicefreqs"

# compute the median frequency here...
MYLIST=()
for thefreq in "${FREQLIST[@]}"; do
	a=$(echo "$thefreq" | cut -f1 -d ",")
	MYLIST+=("${a}")
done

IFS=$'\n'
ctrfreq=$(awk '{arr[NR]=$1} END {if (NR%2==1) print arr[(NR+1)/2];
else print (arr[NR/2]+arr[NR/2+1])/2}' <<< sort <<< "${MYLIST[*]}")

# Format the center frequency the SDR will use
ctrfreq=$(printf "%8.2f\n" "$ctrfreq")

echo "Found the frequency list in ${voicefreqs}: ${MYLIST[*]}"
echo "Median frequency is ${ctrfreq}"
unset IFS

# The number of channels
channels=${#MYLIST[@]}

start0(){
#start rtlsdr-airband on PulseAudio
cp -f /usr/local/etc/rtl_airband-pulse.conf /usr/local/etc/rtl_airband.conf
/usr/local/bin/rtl_airband &
# Force pulseaudio and rtl_airband to work
sleep 3
/etc/init.d/alsa-utils restart
pulseaudio -k
# Remind the user to stop manually.
WINDOW=$(yad --info --height 100 --width 350 \
--title="Multichannel Voice - Running" \
--text="The multichannel receiver is running.
Output is on PulseAudio.
To stop, use this application and select \"Stop Multichannel Voice.\""
);
}

start1(){
#start rtlsdr-airband on the Icecast server
cp -f /usr/local/etc/rtl_airband-icecast.conf /usr/local/etc/rtl_airband.conf
systemctl start icecast2
sleep 3
#start rtlsdr-airband
/usr/local/bin/rtl_airband &
sleep 3
firefox --new-tab http://localhost:7000/mixer1.mp3 &
# Remind the user to stop manually.
WINDOW=$(yad --info --height 100 --width 350 \
--title="Multichannel Voice - Running" \
--text="The multichannel receiver is running.
Output is on the Icecast server.
To stop, use this application and select \"Stop Multichannel Voice.\""
);
}

start2(){
#build the config file for using PulseAudio
build_pulse
#start reception with output on PulseAudio
start0
}

start3(){
#build the config file for using Icecast
build_icecast
#start reception and output on Icecast
start1
}

stop(){
#stop rtlsdr-airband
killall -9 rtl_airband "$(lsof -t -i:8000)"
#stop the icecast2 server
systemctl stop icecast2
echo "STOPPED RTLSDR-Airband. Alpha Mike Foxtrot..."
exit
}

build_pulse(){
# data and config for PulseAudio
#top of the file, defining SDR tuning, etc
echo '# This is a sample configuration file for RTLSDR-Airband.
# Just a single SDR with multiple AM channels in multichannel mode.
# Each channel is sent to PulseAusio. Settings are described
# in reference.conf.

# increase fft size (min 256, max 8192)
fft_size = 1024

mixers: {
  mixer1: {
    outputs: (
        {
	      type = "pulse";
          stream_name = "'$streamname'";
          genre = "'$genre'";
	}
    );
  }
};

devices:
({
  type = "soapysdr";
  device_string = "driver='$devdriver',soapy='$key'";
  gain = '$gain';
  centerfreq = '$ctrfreq';
  correction = '$corr';
  channels:
  (' > /usr/local/etc/rtl_airband-pulse.conf

#write the channel and signal modulation confifig data here...
n=1
comma=","
for thechannel in "${FREQLIST[@]}"; do
freq=$(echo $thechannel | cut -f1 -d ",")
sigmode=$(echo $thechannel | cut -f2 -d ",")

if (( $n == $channels )); then
     comma=""
fi

# for multiple channels use stereo
if [[ $(( $n % 2 )) -eq 0 ]];
	then bal="+0.6" ;
	else bal="-0.6" ;
fi

# for one channel use mono
if (( $channels == 1 ));
	then bal="0.0"
fi

# middle of the file, defining channels and outputs
echo '{
      freq = '$freq';
      modulation = "'$sigmode'";
      outputs: (
    {
	  type = "mixer";
	  name = "mixer1";
	  balance = '$bal';
	}
      );
    }'$comma >> /usr/local/etc/rtl_airband-pulse.conf

let "n++"
done

#bottom of the file
echo '  );
 }
);' >> /usr/local/etc/rtl_airband-pulse.conf
}

build_icecast(){
# data and config for icecast
#top of the file, defining SDR tuning, etc
echo '# This is a sample configuration file for RTLSDR-Airband.
# Just a single SDR with multiple AM channels in multichannel mode.
# Each channel is sent to the Icecast server. Settings are described
# in reference.conf.

# increase fft size (min 256, max 8192)
fft_size = 1024

mixers: {
  mixer1: {
    outputs: (
        {
	      type = "icecast";
	      server = "localhost";
          port = 7000;
          mountpoint = "mixer1.mp3";
          name = "'$streamname'";
          genre = "'$genre'";
          username = "source";
          password = "skywave";
	}
    );
  }
};

devices:
({
  type = "soapysdr";
  device_string = "driver='$devdriver',soapy='$key'";
  gain = '$gain';
  centerfreq = '$ctrfreq';
  correction = '$corr';
  channels:
  (' > /usr/local/etc/rtl_airband-icecast.conf

#write the channel and mode confifig data here...
n=1
comma=","
for thechannel in "${FREQLIST[@]}"; do
freq=$(echo $thechannel | cut -f1 -d ",")
sigmode=$(echo $thechannel | cut -f2 -d ",")

if (( $n == $channels )); then
     comma=""
fi

# for multiple channels use stereo
if [[ $(( $n % 2 )) -eq 0 ]];
	then bal="+0.6" ;
	else bal="-0.6" ;
fi

# for one channel use mono
if (( $channels == 1 ));
	then bal="0.0"
fi

# middle of the file, defining channels and outputs
echo '{
      freq = '$freq';
      modulation = "'$sigmode'";
      outputs: (
    {
	  type = "mixer";
	  name = "mixer1";
	  balance = '$bal';
	}
      );
    }'$comma >> /usr/local/etc/rtl_airband-icecast.conf

let "n++"
done

#bottom of the file
echo '  );
 }
);' >> /usr/local/etc/rtl_airband-icecast.conf
}

backupconf(){
cp -f /usr/local/etc/rtl_airband.conf /usr/local/etc/rtl_airband.conf.bak
}

restoreconf(){
cp -f /usr/local/etc/rtl_airband.conf.bak /usr/local/etc/rtl_airband.conf
}

notifyerror(){
        echo "Something went wrong!!!!!!"
        WINDOW=$(yad --info --height 100 --width 350 \
		--title="Multicgannel Voice - Error." \
		--text="Something went wrong!!!!!!");
}

ans=$(yad --list --title "Multichannel Voice" --height 540 --width 500 \
--text "Multichannel Voice functions:
--Uses SoapySDR drivers
--Simultaneous multichannel demodulation
--Set demodulation independently per channel
--Stereo mixing for for multiple channels
--Softwaare powered by \"RTLSDR-Airband\"
--Edit the frequencies in /usr/local/etc/VOICE_FREQS
  The format is one frequency and mode per line, comma separated.

Frequencies:
${MYLIST[*]}
" \
--radiolist  --column "Pick" --column "Action" \
FALSE "Start Multichannel Voice (PulseAudio)" \
FALSE "Set channels and start Multichannel Voice (PulseAudio)" \
FALSE "Backup the current config file" \
FALSE "Restore the config file from a backup" \
FALSE "Edit the frequency list" \
TRUE "Stop Multichannel Voice" \
);

[[ "$ans" == "Start Multichannel Voice (PulseAudio)" ]] && start0
# [[ "$ans" == "Start Multichannel Voice (Icecast)" ]] && start1
[[ "$ans" == "Set channels and start Multichannel Voice (PulseAudio)" ]] && start2
# [[ "$ans" == "Set channels and start Multichannel Voice (Icecast)" ]] && start3
[[ "$ans" == "Backup the current config file" ]] && backupconf
[[ "$ans" == "Restore the config file from a backup" ]] && restoreconf
[[ "$ans" == "Edit the frequency list" ]] && \
    x-terminal-emulator -e vi "$voicefreqs"
[[ "$ans" == "Stop Multichannel Voice" ]] && stop

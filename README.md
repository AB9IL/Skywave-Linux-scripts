# Skywave-Linux-scripts
Scripts providing efficient, powerful, yet user friendly software defined radio operation, signal decoding, or other functions in Skywave Linux.  They work on most Linux with Bash and commonly installed utilities.

#### aeromodes.sh:
Requires acarsdec and vdlm2dec.  Simultaneous and multichannel ACARS or VDL Mode 2 data capture.

#### ais-file-decoder:
Requires python3 with modules ais and json.  AIS file decoder converts logs of NMEA data to decoded json format.

#### ais-fileto-sqlite:
Requires python3 and modules ais, sqlite3, and json. AIS file decoder converts logs of NMEA data to an sqlite database file.

#### ais-mapper:
Requires python3 and modules folium, pandas, and numpy. 

#### ais_monitor.sh:
Requires rtl-ais.  Simultaneous dual channel ais maritime data capture.  The ais-mapper reads a file of decoded NMEA sentences containing AIS data, builds a dataframe, and plots vessels according to mmsi, name, latitude, and longitude.

#### audioprism-selector:
Requires audioprism.  Sets parameters to display colorful audio spectrum waterfall based on user choice of a high, medium, or low sampling rate.

#### dump1090-stream-parser
Requires dump1090. Receives ADS-B data, parses it, and passes it on for viewing or saving in a datatbase.

#### dump1090.sh:
Requires dump1090 and dump1090-stream-parser.  Capture, parse, and save aeronautical ADS-B data.

#### rtlsdr-airband.sh:
Requires RTLSDR-Airband.  Simultaneous multichannel am or nbfm voice reception.

#### sdr-bookmarks:
Requires Rofi and / or fzf.  Reads a list of radio bookmarks to tune on your local RTL-SDR.  It presents a "fuzzy finder" style menu.  When a frequency is selected, rtl_fm tunes to it and drops into the background to provide audio.  Bring up the menu again to select another frequency or stop reception.  The radio bookmarks are stored in the file "sdrbookmarks" located in the ~/.config directory.  Entries are one per line, formatted in order of "frequency mode description" with the description in quotes.  There is a menu option for editing the list.

#### sdr-params.sh:
Requires kalibrate-rtl.  Store SDR parameters for use by other applications and also measure rtl-sdr frequency offsets (the error in ppm).  Manually enter the soapysdr device string and index.  This script makes it convenient for dump1090, rtl_fm, or other to read what you want to use for gain or have for a ppm offset.  You must put code to fetch the data into those other scripts.

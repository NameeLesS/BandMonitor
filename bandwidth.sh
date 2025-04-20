#!/bin/bash

INTERFACE_NAME=$1
UPDATE_PERIOD=$2
DOWNLOAD_BANDWIDTH=()
UPLOAD_BANDWIDTH=()
TIME=()
MAX_TIMESTEPS=90
CURRENT_TIMESTEP=0
WINDOW_SIZE=($(tput lines) $(tput cols))
RENDER_STATIC_ELEMENTS=true


if [ $# -ne 2 ]; then
	echo "Program takes 2 arguments, ${#} were provided"
	exit 1
fi

if ! [[ $UPDATE_PERIOD =~ ^[0-9]+[.]?[0-9]*$ ]]
then
	echo "Expected int got ${UPDATE_PERIOD}"
	exit 1
fi

function max_min(){
	# Finds the maximum value in a given array
	max_val=$1
	min_val=$1
	for val in $@; do
		if [ $max_val -lt $val ]
		then
			max_val=$val
		fi
		
		if [ $min_val -gt $val ]
		then
			min_val=$val
		fi
	done

	echo $max_val $min_val
}

function net_statistics(){
	# Read the interface stats
	if [ -e "/sys/class/net/${INTERFACE_NAME}" ] 
	then
		P_TX_BYTES=${TX_BYTES}
		P_RX_BYTES=${RX_BYTES}
		RX_BYTES=$(cat "/sys/class/net/${INTERFACE_NAME}/statistics/rx_bytes")
		TX_BYTES=$(cat "/sys/class/net/${INTERFACE_NAME}/statistics/tx_bytes")
		CURRENT_TIMESTEP=$((CURRENT_TIMESTEP+1))
	else
		echo "Interface ${INTERFACE_NAME} doesn't exist"
		exit 1
	fi

	if [ ${#TIME[@]} -lt 1 ]
	then
		TIME+=(0)
	else
		TIME+=( "$((TIME[-1]+UPDATE_PERIOD))" )
	fi

	# Update the bandwidths
	if [ $P_RX_BYTES ] && [ $RX_BYTES ]
	then
		DOWNLOAD_BANDWIDTH+=($(((RX_BYTES-P_RX_BYTES)/(UPDATE_PERIOD*1000))))
		UPLOAD_BANDWIDTH+=($(((TX_BYTES-P_TX_BYTES)/(UPDATE_PERIOD*1000))))
	else
		DOWNLOAD_BANDWIDTH+=(0)
		UPLOAD_BANDWIDTH+=(0)
	fi

	# Shift the buffer if it reached the maximum length
	if [ $CURRENT_TIMESTEP -gt $MAX_TIMESTEPS ]
	then
		DOWNLOAD_BANDWIDTH=("${DOWNLOAD_BANDWIDTH[@]:1}")
		UPLOAD_BANDWIDTH=("${UPLOAD_BANDWIDTH[@]:1}")
		TIME=("${TIME[@]:1}")
		CURRENT_TIMESTEP=$((CURRENT_TIMESTEP-1))
	fi
}

function clear_screen_chunk(){
	# clear_screen_chunk x1 y1 x2 y2
	local x1=$1
	local y1=$2
	local x2=$3
	local y2=$4
	local output=""
	local line_content=""
	local space="­"

	for i in $(seq $x1 $x2); do
		line_content="$line_content$space"
	done;

	for j in $(seq $y1 $y2); do
		output="$output\033[$j;${x1}H${line_content}"
	done;

	echo $output
}

function vline(){
	# vline x y height symbol color
	local x=$1
	local y=$2
	local height=$3
	local symbol=$4
	local color=$5

	local output=
	for i in $(seq 1 $height); do
		output="${output}\033[38;5;${color}m\033[$((y+i));${x}H$symbol\033[0m"
	done;

	echo $output
}

function hline(){
	# hline x y width symbol color
	local x=$1
	local y=$2
	local width=$3
	local symbol=$4
	local color=$5

	local output="\033[38;5;${color}m"
	for i in $(seq 1 $width); do
		output="$output\033[${y};$((x+i))H$symbol"
	done;

	output="$output\033[0m"
	echo $output
}

function box(){
	# box x y height width color
	local x=$1
	local y=$2
	local height=$3
	local width=$4
	local color=$5

	local output=
	output="$output$(vline $x $((y)) $((height-1)) "│" $color)\033[38;5;${color}m\033[$y;${x}H┌\033[$((y+height));${x}H└\033[0m"
	output="$output$(vline $((x+width)) $y $height "│" $color)\033[38;5;${color}m\033[$y;$((x+width))H┐\033[$((y+height));$((x+width))H┘\033[0m"
	output=$output$(hline $x $y $((width-1)) "─" $color)
	output=$output$(hline $x $((y+height)) $((width-1)) "─" $color)

	echo $output
}


function bar(){
	# bar x y height color
	local x=$1
	local y=$2
	local height=$3
	local color=$4

	local output="\033[38;5;${color}m"
	for i in $(seq 1 $height); do
		output="$output\033[$((y-i));${x}H▒"
	done;

	output="$output\033[0m"
	echo $output
}

function plot(){
	# plot x y width height title color data_size labels data
	local x=$1
	local y=$2
	local width=$3
	local height=$4
	local title=$5
	local color=$6
	local data_size=$7
	local labels=${@:8:data_size}
	local data=${@:$((data_size+8))}
	local TICKS_NUMBER=5
	local output=
	
	# Draw axes with tick labels
	output="${output}$(hline $x $y $width "━" 7)"

	# Add xtick labels
	local labels_spacing=$((width/TICKS_NUMBER))
	read max_label min_label <<< "$(max_min ${labels[@]})"
	local ticks_difference=$((UPDATE_PERIOD*MAX_TIMESTEPS/TICKS_NUMBER))
	for i in $(seq 1 $TICKS_NUMBER); do
		local x_pos=$((x+((i-1)*labels_spacing)))
		local tick_value=$((min_label+(ticks_difference*(i-1))))
		output="${output}\033[$((y+1));${x_pos}H${tick_value}"
	done;

	# Draw bars
	read max_height min_height <<< "$(max_min ${data[@]})"
	local height_interval=$(((max_height-min_height)/height))

	local i=0
	for data_point in $data; do
		data_point=$(((data_point-min_height)/(height_interval+1)+1))
		output="${output}$(bar $((i+x+1)) $y $data_point $color)"
		i=$((i+1))
	done;

	# Add ytick labels
	output="$output$(vline $x $((y-height-2)) $((height+1)) "┃" 7)\033[38;5;7m\033[$((y));$((x))H┗\033[0m"
	local height_spacing=$(((height+1)/TICKS_NUMBER))
	local height_tick_difference=$(((max_height-min_height+2*TICKS_NUMBER)/TICKS_NUMBER))
	for i in $(seq 1 $TICKS_NUMBER); do
		local y_pos=$((y-((i-1)*height_spacing)-1))
		local tick_value=$((min_height+(height_tick_difference*(i-1))))
		output="${output}\033[${y_pos};$((x-5))H${tick_value}"
	done;

	# Set title
	output="$output\033[38;5;231m\033[1m\033[$((y-height-2));$((x+(4*(width/10))))H${title}\033[0m"

	echo $output

}

function summary_box(){
	# summary_box x y name speed max total color title
	local x=$1
	local y=$2
	local speed=$4
	local max=$5
	local total=$6
	local color=$7
	local title=$8
	local margin=2
	local output="\033[38;5;3m\033[4m\033[1m\033[$y;$((x+38))H${title}\033[0m"
	output="$output\033[38;5;231m\033[1m\033[$((y+margin));${x}H🢒$3\033[0m"
	output="$output\033[38;5;7m\033[$((y+3+margin));$((x+2))H🢒Current: $((speed)) \033[$((y+3+margin));$((x+40))H(Kbps)"
	output="$output\033[$((y+6+margin));$((x+2))H🢒Top: $((max)) \033[$((y+6+margin));$((x+40))H(Kbps)"
	output="$output\033[$((y+9+margin));$((x+2))H🢒Total: $((total/1000000)) \033[$((y+9+margin));$((x+40))H(MB)\033[0m"

	if [ $RENDER_STATIC_ELEMENTS ]
	then
		output="$output$(box $((x-margin)) $((y-margin)) $(((WINDOW_SIZE[0]/10)*5)) 100 $color)"
	fi
	echo $output
}

function update(){
	local padding=1
	local offset_y=1
	read download_max download_min <<< "$(max_min ${DOWNLOAD_BANDWIDTH[@]})"
	read upload_max upload_min <<< "$(max_min ${UPLOAD_BANDWIDTH[@]})"

	local output=
	output="$output$(summary_box $(((WINDOW_SIZE[1]/20)*11)) $(((WINDOW_SIZE[0]/20)*1)) "Upload" ${UPLOAD_BANDWIDTH[-1]} $upload_max $TX_BYTES 2 "Interface: $INTERFACE_NAME")"
	output="$output$(summary_box $(((WINDOW_SIZE[1]/20)*11)) $(((WINDOW_SIZE[0]/20)*14)) "Download" ${DOWNLOAD_BANDWIDTH[-1]} $download_max $RX_BYTES 1)"
 
	output="$output$(plot $((7+padding)) $(((WINDOW_SIZE[0]/10)*5-offset_y)) $(((WINDOW_SIZE[1]/20)*9)) $(((WINDOW_SIZE[0]/10)*4)) "Upload(Kilobytes/s)" 2 $CURRENT_TIMESTEP ${TIME[@]} ${UPLOAD_BANDWIDTH[@]})"
	output="$output$(plot $((7+padding)) $(((WINDOW_SIZE[0]/10)*10-offset_y)) $(((WINDOW_SIZE[1]/20)*9)) $(((WINDOW_SIZE[0]/10)*4)) "Download(Kilobytes/s)" 1 $CURRENT_TIMESTEP ${TIME[@]} ${DOWNLOAD_BANDWIDTH[@]})"

	if [ $RENDER_STATIC_ELEMENTS ]
	then
		output="$output$(box $padding $padding $((WINDOW_SIZE[0]-2*padding)) $(((WINDOW_SIZE[1]/10)*5)) 6)"
	fi

	echo $output
}

function loop(){
	trap 'tput rmcup; tput cnorm' EXIT
	tput smcup
	tput civis

	local clear_charts=$(clear_screen_chunk 3 3 $((WINDOW_SIZE[1]/2)) $((19*WINDOW_SIZE[0]/20)))
	local clear_summary_box_upload=$(clear_screen_chunk $(((WINDOW_SIZE[1]/20)*11)) $((((WINDOW_SIZE[0]/20)*1)+5)) $((((WINDOW_SIZE[1]/20)*11)+50)) $((((WINDOW_SIZE[0]/20)*1)+5)))
	local clear_summary_box_download=$(clear_screen_chunk $(((WINDOW_SIZE[1]/20)*11)) $((((WINDOW_SIZE[0]/20)*14)+5)) $((((WINDOW_SIZE[1]/20)*11)+50)) $((((WINDOW_SIZE[0]/20)*14)+5)))

	while true;
	do
		net_statistics
		output="$(update)"
		printf "$clear_summary_box_upload$clear_summary_box_download$clear_charts$output"
		RENDER_STATIC_ELEMENTS=false
		sleep $UPDATE_PERIOD
	done;
}

loop

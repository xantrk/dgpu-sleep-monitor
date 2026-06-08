#!/bin/bash

# Read AC adapter online status from any ADP* or IEC* power supply
ac_online="0"
for a in /sys/class/power_supply/ADP* /sys/class/power_supply/IEC*; do
	if [ -f "$a/online" ]; then
		val=$(tr -d '[:space:]' <"$a/online")
		if [ "$val" = "1" ]; then
			ac_online="1"
		fi
		break
	fi
done

# Read first available BAT status (trim only trailing newline)
bat_status="Unknown"
for s in /sys/class/power_supply/BAT*/status; do
	if [ -f "$s" ]; then
		bat_status=$(sed 's/[[:space:]]*$//' <"$s")
		break
	fi
done

echo "${ac_online} ${bat_status}"

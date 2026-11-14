# Run on the phone (as the normal user): state of the remoteprocs and their links
echo "== uptime $(cut -d' ' -f1 /proc/uptime)"
echo "== remoteproc"
for r in /sys/class/remoteproc/remoteproc*; do
	echo "$(basename $r): $(cat $r/name) state=$(cat $r/state) fw=$(cat $r/firmware 2>/dev/null) recovery=$(cat $r/recovery 2>/dev/null)"
done
echo "== rpmsg devices"
ls /sys/bus/rpmsg/devices/ 2>&1 | tr '\n' ' '; echo
echo "== fastrpc"; ls -l /dev/fastrpc-* 2>&1
echo "== rmtfs"; ls -l /dev/qcom_rmtfs_mem* 2>&1; cat /sys/class/rmtfs/*/phys_addr /sys/class/rmtfs/*/size 2>/dev/null | tr '\n' ' '; echo
echo "== drm/gpu"; cat /sys/class/drm/card*-DSI-1/status 2>&1
echo "== kernel log"
journalctl -k -b --no-pager -o short-monotonic | grep -iE "remoteproc|q6v5|_pas|pas |glink|qrtr|sysmon|rmtfs|pdr|pd.mapper|fastrpc|smp2p|apr|mpss|adsp|cdsp|slpi|modem|ssr|crash|fatal|watchdog|scm|qmp|aoss" | sed "s/samsung-r9q kernel: //" | tail -90

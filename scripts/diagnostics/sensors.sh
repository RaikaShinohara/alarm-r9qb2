# Run on the phone (normal user): SSC sensor stack status
echo "== uptime $(cut -d' ' -f1 /proc/uptime)"
for r in /sys/class/remoteproc/remoteproc*; do printf "%s=%s " $(cat $r/name) $(cat $r/state); done; echo
systemctl is-active hexagonrpcd-sdsp iio-sensor-proxy | tr '\n' ' '; echo
echo "temp.json writes: $(journalctl -b --no-pager -u hexagonrpcd-sdsp -o cat | grep -c temp.json)"
for p in HasAccelerometer AccelerometerOrientation HasAmbientLight LightLevel HasProximity ProximityNear; do
	printf "%-26s %s\n" $p "$(busctl get-property net.hadess.SensorProxy /net/hadess/SensorProxy net.hadess.SensorProxy $p 2>&1)"
done
printf "%-26s %s\n" HasCompass "$(busctl get-property net.hadess.SensorProxy /net/hadess/SensorProxy/Compass net.hadess.SensorProxy.Compass HasCompass 2>&1)"
echo "== ssccli accelerometer"
timeout 8 ssccli --sensor accelerometer --timeout 5 2>&1 | grep -v "^$" | head -8

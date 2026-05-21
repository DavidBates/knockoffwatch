# Support

knockoffwatch is a personal open-source project with no official support. That said, there are a few ways to get help.

## Bug reports and feature requests

Open a [GitHub Issue](https://github.com/fakewatch/knockoffwatch/issues). Please include:

- iOS version
- iPhone model
- Watch model (if known)
- Steps to reproduce
- What you expected vs. what happened

## Watch compatibility

This app was reverse-engineered specifically for the **LaxasFit Watch Ultra**. Similar budget BLE watches that use the Nordic UART Service (NUS) with the same packet format may work, but are untested. If you find a compatible device, feel free to open an issue or PR with notes.

## Common issues

**The app can't find my watch during scanning**
Make sure the watch is powered on, charged, and within a few feet of your iPhone. If it still doesn't appear, try restarting Bluetooth on your iPhone.

**Readings seem inaccurate**
Health readings from consumer smartwatches are estimates and vary in accuracy. These readings come directly from the watch hardware — the app reports exactly what the watch sends. Do not use them for medical decisions.

**Apple Health isn't receiving data**
Check **Settings → Privacy & Security → Health → knockoffwatch** and confirm all three write permissions (Heart Rate, Blood Pressure, Oxygen Saturation) are enabled.

## Contributing

Pull requests are welcome. See the architecture overview in [`README.md`](README.md) and the protocol reference in [`agent_instruct.md`](agent_instruct.md) before diving in.

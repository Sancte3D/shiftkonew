(
// 01_synthdefs.scd
// Core SynthDefs for the modular breakbeat layer.
// Requires:
// - ~fxBus (global reverb/effect bus, stereo). Falls back to main out if unset.

SynthDef(\slicePlayer, { |out = 0, fxBus = -1, buf = 0, slice = 0, slicesTotal = 16,
	amp = 0.5, rate = 1.0, pan = 0.0, revSend = 0.15|
	var sig, env, sliceFrames, startPos, dry, sendBus;
	var ampSm, rateSm, panSm, revSm;

	// Anti-zipper smoothing for live hardware control
	ampSm = Lag.kr(amp.clip(0, 2), 0.05);
	rateSm = VarLag.kr(rate.clip(0.05, 4), 0.08, warp: \sine);
	panSm = Lag.kr(pan.clip(-1, 1), 0.06);
	revSm = Lag.kr(revSend.clip(0, 1), 0.08);

	sliceFrames = BufFrames.kr(buf) / slicesTotal.max(1);
	startPos = slice.clip(0, slicesTotal - 1) * sliceFrames;

	// Fast click-safe envelope per slice
	env = EnvGen.kr(
		Env([0, 1, 1, 0], [0.003, 0.92, 0.06], [-4, 0, -4]),
		timeScale: (sliceFrames / SampleRate.ir) / rateSm.max(0.001),
		doneAction: 2
	);

	sig = PlayBuf.ar(1, buf, BufRateScale.kr(buf) * rateSm, startPos: startPos);
	dry = Pan2.ar(sig * env * ampSm, panSm);

	// Main out
	Out.ar(out, dry * (1 - revSm));

	// Global reverb/fx send
	sendBus = Select.kr(fxBus >= 0, [out, fxBus]);
	Out.ar(sendBus, dry * revSm);
}).add;
)

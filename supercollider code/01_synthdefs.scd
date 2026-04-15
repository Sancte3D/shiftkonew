(
// 01_synthdefs.scd
// Core SynthDefs for the modular breakbeat layer.
// Requires:
// - ~fxBus (global reverb/effect bus, stereo). Falls back to main out if unset.

SynthDef(\slicePlayer, { |out = 0, fxBus = -1, buf = 0, slice = 0, slicesTotal = 16,
	amp = 0.5, rate = 1.0, pan = 0.0, revSend = 0.15, cutoff = 15000, hpf = 90|
	var sig, env, sliceFrames, startPos, dry, sendBus;
	var ampSm, rateSm, panSm, revSm, cutoffSm, hpfSm;

	// Anti-zipper smoothing for live hardware control
	ampSm = Lag.kr(amp.clip(0, 2), 0.05);
	rateSm = VarLag.kr(rate.clip(0.05, 4), 0.08, warp: \sine);
	panSm = Lag.kr(pan.clip(-1, 1), 0.06);
	revSm = Lag.kr(revSend.clip(0, 1), 0.08);
	cutoffSm = Lag.kr(cutoff.clip(80, 18000), 0.06);
	hpfSm = Lag.kr(hpf.clip(30, 1200), 0.06);

	sliceFrames = BufFrames.kr(buf) / slicesTotal.max(1);
	startPos = slice.clip(0, slicesTotal - 1) * sliceFrames;

	// Fast click-safe envelope per slice
	env = EnvGen.kr(
		Env([0, 1, 1, 0], [0.003, 0.92, 0.06], [-4, 0, -4]),
		timeScale: (sliceFrames / SampleRate.ir) / rateSm.max(0.001),
		doneAction: 2
	);

	sig = PlayBuf.ar(1, buf, BufRateScale.kr(buf) * rateSm, startPos: startPos);
	sig = HPF.ar(sig, hpfSm);
	sig = RLPF.ar(sig, cutoffSm, 0.9);
	dry = Pan2.ar(sig * env * ampSm, panSm);

	// Main out
	Out.ar(out, dry * (1 - revSm));

	// Global reverb/fx send
	sendBus = Select.kr(fxBus >= 0, [out, fxBus]);
	Out.ar(sendBus, dry * revSm);
}).add;

SynthDef(\dnbKick, { |out = 0, amp = 0.65, pan = 0.0, revSend = 0.03, fxBus = -1|
	var env, pitchEnv, body, click, sig, dry, sendBus;
	var ampSm, panSm, revSm;

	ampSm = Lag.kr(amp.clip(0, 1.2), 0.02);
	panSm = Lag.kr(pan.clip(-1, 1), 0.03);
	revSm = Lag.kr(revSend.clip(0, 0.5), 0.04);

	env = EnvGen.kr(Env.perc(0.0008, 0.22, curve: -8), doneAction: 2);
	pitchEnv = XLine.kr(190, 44, 0.045);
	body = SinOsc.ar(pitchEnv, 0, env);
	click = HPF.ar(WhiteNoise.ar(0.22), 2500) * EnvGen.kr(Env.perc(0.0005, 0.012, 1, -6));
	sig = (body + click).tanh;
	dry = Pan2.ar(sig * ampSm, panSm);

	Out.ar(out, dry * (1 - revSm));
	sendBus = Select.kr(fxBus >= 0, [out, fxBus]);
	Out.ar(sendBus, dry * revSm);
}).add;
)

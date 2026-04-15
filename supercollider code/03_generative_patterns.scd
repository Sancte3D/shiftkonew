(
// 03_generative_patterns.scd
// Generative DnB/Jungle slicer pattern layer.
// Load after 01_synthdefs.scd.

~dnbClock = TempoClock.new(170 / 60);
~dnbTargetBpm = 170;
~originalSampleBPM = 135;
~dnbSlices = 16;
~dnbBuf = nil;

// Runtime-control proxies (updated from MIDI mapping module)
Pdefn(\chaosProb, 0.2);       // optional global chaos control (kept for live mapping compatibility)
Pdefn(\dnbAmp, 0.35);
Pdefn(\dnbRateOffset, 1.0);
Pdefn(\dnbRevSend, 0.15);
Pdefn(\dnbRollDensity, 0.0);  // 0 -> 16th, 1 -> 32nd tendency
Pdefn(\dnbStutterProb, 0.08); // subtle default stutter injections
Pdefn(\dnbBreakHPF, 90);
Pdefn(\dnbKickAmp, 0.45);
Pdefn(\dnbSidechainDepth, 0.18);

~loadDnbBuffer = { |path|
	if(path.notNil and: { path.size > 0 }) {
		if(~dnbBuf.notNil) { ~dnbBuf.free; };
		~dnbBuf = Buffer.read(s, path, action: {
			("DNB buffer loaded: " ++ path).postln;
		});
	};
};

~setDnbTempo = { |bpm = 170|
	~dnbTargetBpm = bpm.clip(80, 220);
	~dnbClock.tempo = ~dnbTargetBpm / 60;
};

~setDnbSourceBpm = { |bpm = 135|
	~originalSampleBPM = bpm.clip(60, 220);
};

~dnbPattern = Pbind(
	\instrument, \slicePlayer,
	\buf, Pfunc { ~dnbBuf ? 0 },
	\slicesTotal, Pfunc { ~dnbSlices ? 16 },

	// 16th-note base grid, roll density and optional stutter injections
	\dur, Pfunc {
		var r = (Pdefn(\dnbRollDensity).source ? 0.0).clip(0, 1);
		if(1.0.rand < r) { 0.125 } { 0.25 }
	},
	// Optional slice duplication (Pdup-style stutter behavior)
	\str, Pfunc {
		var p = (Pdefn(\dnbStutterProb).source ? 0.0).clip(0, 1);
		if(1.0.rand < p) { [2, 3, 4].choose } { 1 }
	},

	// Safe default slice selection: stable loop 80% / random chop 20%
	\slice, Pdup(
		Pkey(\str),
		Pwrand(
			[
				Pseq((0..15), inf),
				Prand((0..15), inf)
			],
			[
				0.8,
				0.2
			],
			inf
		)
	),

	// Time-stretch: target/source BPM * live offset
	// Wichtig: target BPM wird live aus der Clock gelesen.
	\rate, Pfunc {
		// Tempo-adaptive playback (not locked to 170):
		// rate = targetBpm / sourceBpm * rateOffset
		((~dnbClock.tempo * 60) / (~originalSampleBPM ? 135)) *
		((Pdefn(\dnbRateOffset).source ? 1.0).clip(0.25, 2.0))
	},
	\hpf, Pfunc { (Pdefn(\dnbBreakHPF).source ? 90).clip(30, 1200) },

	// 80/20 ghost model keeps accents predictable and musical
	\isGhost, Pwrand([0, 1], [0.8, 0.2], inf),
	\baseAmp, Pif(
		Pkey(\isGhost) > 0,
		Pfunc { (Pdefn(\dnbAmp).source ? 0.35).clip(0, 1) * 0.35 },
		Pfunc { (Pdefn(\dnbAmp).source ? 0.35).clip(0, 1) * 0.90 }
	),
	// Lightweight sidechain feel: stronger kick steps reduce break amplitude slightly.
	\sidechain, Pfunc { ((Pdefn(\dnbSidechainDepth).source ? 0.18).clip(0, 0.6)) },
	\amp, Pkey(\baseAmp) * (1 - Pkey(\sidechain)),
	// Pkey-based filter articulation follows ghost/main identity
	\cutoff, Pif(Pkey(\isGhost) > 0, 1200, 15000),
	\revSend, Pfunc { (Pdefn(\dnbRevSend).source ? 0.15).clip(0, 1) },
	\pan, Pwhite(-0.15, 0.15, inf),
	\out, Pfunc { ~mainOutBus ? 0 },
	\fxBus, Pfunc { (~fxBus ? -1) }
);

~dnbKickPattern = Pbind(
	\instrument, \dnbKick,
	\dur, 0.25,
	\isKick, Pseq([1, 0, 0, 0, 1, 0, 0, 0], inf),
	\amp, Pif(
		Pkey(\isKick) > 0,
		Pfunc { (Pdefn(\dnbKickAmp).source ? 0.45).clip(0, 1) },
		0
	),
	\pan, 0,
	\revSend, 0.02,
	\out, Pfunc { ~mainOutBus ? 0 },
	\fxBus, Pfunc { (~fxBus ? -1) }
);

~dnbCombinedPattern = Ppar([~dnbPattern, ~dnbKickPattern], inf);

~dnbPlayer = nil;
~startDnb = {
	if(~dnbBuf.isNil) {
		"DNB start aborted: load a sample first.".postln;
	} {
		if(~dnbPlayer.notNil) { ~dnbPlayer.stop; };
		~dnbPlayer = ~dnbCombinedPattern.play(~dnbClock, quant: 4);
		"DNB pattern started.".postln;
	};
};

~stopDnb = {
	if(~dnbPlayer.notNil) { ~dnbPlayer.stop; ~dnbPlayer = nil; };
	"DNB pattern stopped.".postln;
};
)

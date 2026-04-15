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
Pdefn(\chaosProb, 0.3);       // 0.0 -> mostly linear, 1.0 -> mostly random
Pdefn(\dnbAmp, 0.35);
Pdefn(\dnbRateOffset, 1.0);
Pdefn(\dnbRevSend, 0.15);
Pdefn(\dnbRollDensity, 0.0);  // 0 -> 16th, 1 -> 32nd tendency

~loadDnbBuffer = { |path|
	if(path.notNil and: { path.size > 0 }) {
		if(~dnbBuf.notNil) { ~dnbBuf.free; };
		~dnbBuf = Buffer.read(s, path, action: {
			("DNB buffer loaded: " ++ path).postln;
		});
	};
};

~setDnbTempo = { |bpm = 170|
	~dnbTargetBpm = bpm.clip(120, 190);
	~dnbClock.tempo = ~dnbTargetBpm / 60;
};

~dnbPattern = Pbind(
	\instrument, \slicePlayer,
	\buf, Pfunc { ~dnbBuf ? 0 },
	\slicesTotal, Pfunc { ~dnbSlices ? 16 },

	// 16th-note base grid, optional roll density -> occasional 32nds
	\dur, Pfunc {
		var r = (Pdefn(\dnbRollDensity).source ? 0.0).clip(0, 1);
		if(1.0.rand < r) { 0.125 } { 0.25 }
	},

	// Chaos-controlled slicing via Pdefn(\chaosProb)
	\slice, Pwrand(
		[
			Pseq((0..15), inf),
			Prand((0..15), inf)
		],
		[
			Pfunc { (1 - (Pdefn(\chaosProb).source ? 0.3)).clip(0, 1) },
			Pfunc { (Pdefn(\chaosProb).source ? 0.3).clip(0, 1) }
		],
		inf
	),

	// Time-stretch: target/source BPM * live offset
	// Wichtig: target BPM wird live aus der Clock gelesen.
	\rate, Pfunc {
		((~dnbClock.tempo * 60) / (~originalSampleBPM ? 135)) *
		((Pdefn(\dnbRateOffset).source ? 1.0).clip(0.5, 1.5))
	},

	\amp, Pfunc {
		var a = (Pdefn(\dnbAmp).source ? 0.35).clip(0, 1);
		// Ghost-note dynamics
		if(1.0.rand < 0.2) { a * 0.28 } { a * 0.9 }
	},
	\revSend, Pfunc { (Pdefn(\dnbRevSend).source ? 0.15).clip(0, 1) },
	\pan, Pwhite(-0.15, 0.15, inf),
	\out, Pfunc { ~mainOutBus ? 0 },
	\fxBus, Pfunc { (~fxBus ? -1) }
);

~dnbPlayer = nil;
~startDnb = {
	if(~dnbBuf.isNil) {
		"DNB start aborted: load a sample first.".postln;
	} {
		if(~dnbPlayer.notNil) { ~dnbPlayer.stop; };
		~dnbPlayer = ~dnbPattern.play(~dnbClock, quant: 4);
		"DNB pattern started.".postln;
	};
};

~stopDnb = {
	if(~dnbPlayer.notNil) { ~dnbPlayer.stop; ~dnbPlayer = nil; };
	"DNB pattern stopped.".postln;
};
)

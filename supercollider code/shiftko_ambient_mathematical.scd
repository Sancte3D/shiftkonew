/*
SHIFTKO -> SuperCollider (mathematische Neuimplementierung)
-----------------------------------------------------------
Phase-1-Extrakt (Pd DSP-Essenz):
- GUI/Busse: bpm, mood-raw, reverb-room-base, drone-level, notes-level, noise-level,
  texture-level, master-vol, transport, root-hz, chord/pedal-level, 7x Scale-Weights.
- Cutoff-Mathematik: filterCutoff = base * lfoMul * rndMul * chaosMul, danach Clamp.
- Reverb-Raum: reverbRoom = reverbBase * lfoMul * rndMul, danach Clamp.
- line~/vline~ => zeitliche Interpolation/Envelope-Generator.
- catch~/throw~ => Summenbusse (drone, notes, texture, noise), danach FX-Kette.
*/

s.waitForBoot {
	SynthDef(\shiftkoAmbientMath, { |out=0,
		// GUI-Args (aus Pd abgeleitet)
		bpm=60, moodRaw=0.3, reverbRoomBase=0.4, droneLevel=0.6, notesLevel=0.5,
		noiseLevel=0.06, textureLevel=0.1, masterVol=0.4, transport=1,
		deprecatedHeadphoneMode=0, rootHz=256, droneGate=1, notesGate=1, noiseGate=1, textureGate=1,
		chordLevel=0.6, pedalLevel=0.08, cosmicW=100, wonderW=0, hopefulW=0, kotoW=0,
		ragaW=0, pelogW=0, safir16W=0, filterCutoffBase=1800, wholeTime=4000, macroGate=1, noiseType=0
	|
		var bpmS, mood, roomBase, dLvl, nLvl, nzLvl, texLvl, mVol, tr, rtHz;
		var dGate, nGate, nzGate, tGate, chLvl, pdLvl, fBase, mGate;
		var weights, weightNorm, scaleSel, scaleHz, trigRate, trig, noteTrig;
		var scaleCosmic, scaleWonder, scaleHopeful, scaleKoto, scaleRaga, scalePelog, scaleSafir16;
		var root, sub, octave, fifth, droneCore, droneLfoL, droneLfoR, droneStereo;
		var detuneA, detuneB, noteHz, noteEnv, noteSig, textureSig, noiseSig;
		var lfoMul, rndMul, chaosMul, cutoff, roomMulRnd, roomCtrl;
		var dryL, dryR, wetL, wetR, mix, hpSafety;

		// Alle kritischen Steuerwerte mit Lag.kr glätten (Anti-Zipper/Anti-Klick)
		bpmS   = Lag.kr(bpm.clip(30, 100), 0.3);
		mood   = Lag.kr(moodRaw.clip(0, 1), 1.2);
		roomBase = Lag.kr(reverbRoomBase.clip(0.001, 0.8), 1.0);
		dLvl   = Lag.kr(droneLevel.clip(0.001, 0.8), 1.5);
		nLvl   = Lag.kr(notesLevel.clip(0.001, 0.8), 1.5);
		nzLvl  = Lag.kr(noiseLevel.clip(0, 0.3), 1.0);
		texLvl = Lag.kr(textureLevel.clip(0, 0.3), 1.0);
		mVol   = Lag.kr(masterVol.clip(0.001, 0.75), 1.0);
		tr     = Lag.kr(transport.clip(0, 1), 0.2);
		rtHz   = Lag.kr(rootHz.clip(32, 1600), 2.0);
		dGate  = Lag.kr(droneGate.clip(0, 1), 0.3);
		nGate  = Lag.kr(notesGate.clip(0, 1), 0.3);
		nzGate = Lag.kr(noiseGate.clip(0, 1), 0.3);
		tGate  = Lag.kr(textureGate.clip(0, 1), 0.3);
		chLvl  = Lag.kr(chordLevel.clip(0, 0.8), 1.2);
		pdLvl  = Lag.kr(pedalLevel.clip(0, 0.3), 1.2);
		fBase  = Lag.kr(filterCutoffBase.clip(120, 12000), 2.5);
		mGate  = Lag.kr(macroGate.clip(0, 1), 3.0);

		// Gewichtete Skalenwahl (Pd-Gedanke: "Chords_Scales" + Weight-Slider)
		weights = [cosmicW, wonderW, hopefulW, kotoW, ragaW, pelogW, safir16W].max(0.001);
		weightNorm = weights / (weights.sum + 1e-9);
		scaleSel = TWChoose.kr(
			trig: Impulse.kr((bpmS / 60) / 4),
			array: [0, 1, 2, 3, 4, 5, 6],
			weights: weightNorm
		);

		// Skalen als Frequenzverhaeltnisse zur root-Frequenz
		scaleCosmic  = [1, 9/8, 5/4, 4/3, 3/2, 5/3, 2];
		scaleWonder  = [1, 16/15, 9/8, 6/5, 4/3, 3/2, 8/5, 2];
		scaleHopeful = [1, 9/8, 5/4, 45/32, 3/2, 5/3, 15/8, 2];
		scaleKoto    = [1, 9/8, 4/3, 3/2, 16/9, 2];
		scaleRaga    = [1, 16/15, 6/5, 4/3, 3/2, 8/5, 9/5, 2];
		scalePelog   = [1, 1.07, 1.18, 1.32, 1.52, 1.74, 2];
		scaleSafir16 = [1, 16/15, 9/8, 6/5, 5/4, 4/3, 45/32, 3/2, 8/5, 5/3, 9/5, 15/8, 2];

		trigRate = ((bpmS / 60) / 2).clip(0.05, 4);
		trig = Impulse.kr(trigRate) * tr * nGate * mGate;
		noteTrig = CoinGate.kr(0.9, trig);

		scaleHz = Select.kr(
			scaleSel,
			[
				TChoose.kr(noteTrig, scaleCosmic),
				TChoose.kr(noteTrig, scaleWonder),
				TChoose.kr(noteTrig, scaleHopeful),
				TChoose.kr(noteTrig, scaleKoto),
				TChoose.kr(noteTrig, scaleRaga),
				TChoose.kr(noteTrig, scalePelog),
				TChoose.kr(noteTrig, scaleSafir16)
			]
		) * rtHz;

		// Filter-Multiplikatoren wie in Pd-Mix-Patches (LFO + Random + Chaos)
		lfoMul = SinOsc.kr(0.001).range(0.4, 2.5);
		rndMul = LFDNoise1.kr(1/600).range(0.65, 1.35);
		chaosMul = LFDNoise3.kr(1/17).range(0.72, 1.28);
		cutoff = (fBase * lfoMul * rndMul * chaosMul).clip(120, 14000);

		// Drone: harmonische Schichtung (sub + root + octave + fifth), leicht stereo-bewegt
		root = SinOsc.ar(rtHz);
		sub = SinOsc.ar(rtHz * 0.5) * 0.20;
		octave = (SinOsc.ar(rtHz * 2) + (Saw.ar(rtHz * 2) * 0.15)) * 0.24;
		fifth = SinOsc.ar(rtHz * 3) * 0.10;
		droneCore = (root * 0.52 + sub + octave + fifth) * dLvl * dGate;

		droneLfoL = SinOsc.kr(0.013).range(0.76, 1.0);
		droneLfoR = SinOsc.kr(0.017).range(0.76, 1.0);
		droneStereo = [droneCore * droneLfoL, droneCore * droneLfoR];

		// Notes: duale Detune-Voices + lange Ambient-Release-Zeit
		detuneA = 1.001;
		detuneB = 0.999;
		noteHz = Lag.kr(scaleHz, 1.2);
		noteEnv = EnvGen.kr(Env.perc(0.02, 16.0, 0.7, curve: -4), gate: noteTrig);
		noteSig = (
			SinOsc.ar(noteHz * detuneA) +
			SinOsc.ar(noteHz * detuneB)
		) * noteEnv * nLvl * 0.25;
		noteSig = [noteSig * SinOsc.kr(0.021).range(0.72, 1.0), noteSig * SinOsc.kr(0.029).range(0.72, 1.0)];

		// Texture + Noise Layer
		textureSig = HPF.ar(PinkNoise.ar(0.18), 400) * LPF.kr(SinOsc.kr(0.02).range(3200, 8600), 4);
		textureSig = textureSig ! 2 * texLvl * tGate * 0.28;

		noiseSig = SelectX.ar(noiseType.clip(0, 1), [WhiteNoise.ar(1), PinkNoise.ar(1)]);
		noiseSig = HPF.ar(noiseSig, 90) ! 2 * nzLvl * nzGate * 0.22;

		// Summenbus + Filter + Reverb-Proxy
		dryL = droneStereo[0] + noteSig[0] + textureSig[0] + noiseSig[0] + (chLvl * 0.02) + (pdLvl * 0.01);
		dryR = droneStereo[1] + noteSig[1] + textureSig[1] + noiseSig[1] + (chLvl * 0.02) + (pdLvl * 0.01);
		dryL = RLPF.ar(dryL, cutoff, 0.55);
		dryR = RLPF.ar(dryR, cutoff * 0.99, 0.58);

		roomMulRnd = LFDNoise1.kr(1/600).range(0.75, 1.25);
		roomCtrl = (roomBase * roomMulRnd).clip(0.02, 0.88);
		wetL = JPverb.ar(dryL, t60: roomCtrl.linlin(0.02, 0.88, 0.8, 7.5), damp: 0.45, size: 2.8);
		wetR = JPverb.ar(dryR, t60: roomCtrl.linlin(0.02, 0.88, 0.8, 7.5), damp: 0.43, size: 2.9);

		mix = XFade2.ar([dryL, dryR], [wetL, wetR], roomCtrl.linlin(0.02, 0.88, -0.4, 0.7));
		hpSafety = HPF.ar(mix, 20);

		// Anti-Clipping-Airbag: Soft-Clip + Limiter
		mix = tanh(hpSafety * 1.35);
		mix = Limiter.ar(mix, 0.95, 0.01);

		Out.ar(out, mix * mVol * tr);
	}).add;

	s.sync;

	// Startinstanz
	~shiftko = Synth(\shiftkoAmbientMath);
};

/*
Beispiele:
~shiftko.set(\bpm, 54, \moodRaw, 0.72, \reverbRoomBase, 0.52);
~shiftko.set(\cosmicW, 0, \wonderW, 100, \hopefulW, 25);
~shiftko.set(\notesLevel, 0.55, \droneLevel, 0.62, \textureLevel, 0.14);
~shiftko.free;
*/

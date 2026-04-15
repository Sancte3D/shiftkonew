(
// 02_midi_mapping.scd
// MIDI mapping for the breakbeat subsystem.
// Load after 03_generative_patterns.scd.

MIDIClient.init;
MIDIIn.connectAll;

~freeDnbMidiDefs = {
	if(~dnbMidiDefs.notNil) { ~dnbMidiDefs.do(_.free); };
	~dnbMidiDefs = List.new;
};

~freeDnbMidiDefs.value;
~dnbMidiDefs = List.new;

// Default CC map (adjust to your controller layout)
~dnbCc = (
	breakVol: 15,
	chaos: 16,
	rateOffset: 18,
	revSend: 19,
	stutterProb: 20,
	breakHpf: 21,
	kickAmp: 22,
	sidechainDepth: 23
);

// 1) Breakbeat volume / mute
~dnbMidiDefs.add(
	MIDIdef.cc(\dnb_break_vol, { |val|
		var amp = val.linlin(0, 127, 0.0, 1.0);
		Pdefn(\dnbAmp, amp);
	}, ~dnbCc[\breakVol])
);

// 2) Slicing chaos probability
~dnbMidiDefs.add(
	MIDIdef.cc(\dnb_chaos_prob, { |val|
		var p = val.linlin(0, 127, 0.0, 1.0);
		Pdefn(\chaosProb, p);
	}, ~dnbCc[\chaos])
);

// 3) Pitch / rate offset (tape style)
~dnbMidiDefs.add(
	MIDIdef.cc(\dnb_rate_offset, { |val|
		var r = val.linlin(0, 127, 0.25, 2.0);
		Pdefn(\dnbRateOffset, r);
	}, ~dnbCc[\rateOffset])
);

// 4) Reverb send for drums
~dnbMidiDefs.add(
	MIDIdef.cc(\dnb_rev_send, { |val|
		var send = val.linlin(0, 127, 0.0, 1.0);
		Pdefn(\dnbRevSend, send);
	}, ~dnbCc[\revSend])
);

// 5) Optional stutter probability (Pdup density)
~dnbMidiDefs.add(
	MIDIdef.cc(\dnb_stutter_prob, { |val|
		var p = val.linlin(0, 127, 0.0, 0.35);
		Pdefn(\dnbStutterProb, p);
	}, ~dnbCc[\stutterProb])
);

// 6) Break high-pass filter (avoid low-end conflict with sub bass)
~dnbMidiDefs.add(
	MIDIdef.cc(\dnb_break_hpf, { |val|
		var hz = val.linexp(0, 127, 30, 1200);
		Pdefn(\dnbBreakHPF, hz);
	}, ~dnbCc[\breakHpf])
);

// 7) Synthetic kick layer amount
~dnbMidiDefs.add(
	MIDIdef.cc(\dnb_kick_amp, { |val|
		var a = val.linlin(0, 127, 0.0, 1.0);
		Pdefn(\dnbKickAmp, a);
	}, ~dnbCc[\kickAmp])
);

// 8) Sidechain depth on break layer
~dnbMidiDefs.add(
	MIDIdef.cc(\dnb_sidechain_depth, { |val|
		var d = val.linlin(0, 127, 0.0, 0.6);
		Pdefn(\dnbSidechainDepth, d);
	}, ~dnbCc[\sidechainDepth])
);

"DNB MIDI mapping ready.".postln;
)

props.globals.initNode("/sim/flaps/current-setting", 0, "INT");

setlistener("/sim/flaps/current-setting", 
	func {
		var index = arg[0].getValue();
		var useSetting = 0;
		if(index!=nil and index>=0) useSetting = getprop("/sim/flaps/setting["~index~"]");
		if(useSetting!=nil) setprop("/controls/flight/flaps", useSetting);
	}, 0, 0
);

var flapCheck = func {
	var kias =	getprop("/velocities/airspeed-kt");
	var flapPos = getprop("/sim/flaps/current-setting");
	if(kias == nil or flapPos == nil) 
		return;
	
	if(kias > 200 and flapPos > 0 ) {
		controls.stepProps("/controls/flight/flaps", "/sim/flaps", -2);
		screen.log.write("Autoretracting flaps (over 200kt), setting to 0 deg");
	}
	else if(kias > 170 and flapPos > 1 ) {
		controls.stepProps("/controls/flight/flaps", "/sim/flaps", -1);
		screen.log.write("Autoretracting flaps (over 170kt), setting to 25 deg");
	}
	
}

